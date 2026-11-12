/// Shared fixtures and helpers for the customer credit-list widget tests.
///
/// The customer profile and the shop-wide credit list render the same credit
/// cards, so their tests share the same database seeding, the same viewport
/// handling, the same asynchronous pumping helpers and the same document
/// presenter seam.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:credit_system/features/customers/presentation/credit_draft_agreement_action.dart';

/// The shop tenant used by the credit-list widget tests.
const String testShopId = 'shop-123';

/// The borrower used by the credit-list widget tests.
const int testCustomerId = 456;

/// The staff member used by the credit-list widget tests.
const String testUserId = 'user-1';

/// The borrower's full name used by the credit-list widget tests.
const String testCustomerName = 'Sunil Perera';

/// Pumps until [condition] holds, so asynchronous Drift work completes before
/// assertions instead of relying on arbitrary delays.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxIterations = 100,
}) async {
  for (var i = 0; i < maxIterations; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (condition()) return;
  }
  fail('pumpUntil: condition never became true within $maxIterations pumps.');
}

/// Enlarges the test surface so the whole profile, the credit cards and the
/// origination form are reachable without scrolling.
void useLargeSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// Opens a fresh in-memory database.
Future<AppDatabase> openTestDatabase() async {
  final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
  return AppDatabase.forTesting(inMemoryExecutor);
}

/// Seeds the shop and the borrower the credit lists read from.
///
/// [timezone] is the shop's operational IANA identifier. Pass a non-default
/// zone to pin that the screens render dates in the shop's own zone.
Future<void> seedShopAndCustomer(
  AppDatabase db, {
  String shopId = testShopId,
  int customerId = testCustomerId,
  String shopName = 'Test Shop',
  String timezone = 'Asia/Colombo',
}) async {
  final now = DateTime.now().toUtc();
  await db.into(db.shops).insert(
    ShopEntry(
      id: shopId,
      name: shopName,
      currencyCode: 'LKR',
      timezone: timezone,
      createdAt: now,
      updatedAt: now,
    ),
  );
  await db.into(db.customers).insert(
    CustomerEntry(
      id: customerId,
      shopId: shopId,
      fullName: testCustomerName,
      nic: '851234567V',
      phone: '0771234567',
      address: '1 Main St, Colombo',
      createdAt: now,
      updatedAt: now,
    ),
  );
}

/// Inserts a credit row.
Future<void> insertCredit(AppDatabase db, Credit credit) async {
  await db.into(db.credits).insert(CreditsCompanion(
    id: Value(credit.id),
    shopId: Value(credit.shopId),
    customerId: Value(credit.customerId),
    principalCents: Value(credit.principalCents),
    balanceCents: Value(credit.balanceCents),
    status: Value(credit.status.value),
    workflowStatus: Value(credit.workflowStatus.value),
    termPresetDays: Value(credit.termPresetDays),
    customDueDate: Value(credit.customDueDate),
    disbursedAt: Value(credit.disbursedAt),
    disbursedByUserId: Value(credit.disbursedByUserId),
    cancelledAt: Value(credit.cancelledAt),
    cancellationReason: Value(credit.cancellationReason),
    dueDate: Value(credit.dueDate),
    createdAt: Value(credit.createdAt),
    settledAt: Value(credit.settledAt),
  ));
}

/// Renders the raw bytes of an uncompressed PDF as text.
///
/// The document service writes the PDF uncompressed on purpose ("Kept
/// uncompressed so mandatory text remains inspectable in QA"), so the printed
/// text can be searched for the content the slip is required to carry.
String pdfText(Uint8List bytes) => utf8.decode(bytes, allowMalformed: true);

/// A document presenter that records what the draft action handed over.
///
/// The production presenter waits on a platform channel that never resolves
/// under `flutter test`, so the hand-off is only observable through an
/// injected presenter.
class RecordingDocumentPresenter {
  /// The bytes handed to the presenter.
  Uint8List? bytes;

  /// The file name handed to the presenter.
  String? fileName;

  /// The path the presenter reports the document as saved to.
  ///
  /// `null` models the platform taking the document itself (a browser
  /// download), which the action reports as a download rather than a save.
  String? savedPath = '/tmp/draft-agreement.pdf';

  /// Presents [bytes] as [fileName] and reports [savedPath].
  Future<String?> call(Uint8List bytes, String fileName) async {
    this.bytes = bytes;
    this.fileName = fileName;
    return savedPath;
  }
}

/// Taps the shared draft agreement action for [creditId] and waits until the
/// document has been handed over.
///
/// Fails the test when the action reports an inline failure instead.
Future<void> generateDraftAgreement(
  WidgetTester tester,
  String creditId,
) async {
  await tester.tap(find.byKey(CreditDraftAgreementAction.buttonKey(creditId)));
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    final error =
        find.byKey(CreditDraftAgreementAction.errorKey(creditId));
    if (error.evaluate().isNotEmpty) {
      fail('Draft generation failed: ${tester.widget<Text>(error).data}');
    }
    if (find.byType(AlertDialog).evaluate().isNotEmpty) return;
  }
  fail('The draft agreement was never handed over to the presenter.');
}
