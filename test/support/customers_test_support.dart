/// Shared fixtures and helpers for the customer credit-list widget tests.
///
/// The customer profile and the shop-wide credit list render the same credit
/// cards, so their tests share the same database seeding, the same viewport
/// handling and the same asynchronous pumping helpers.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:credit_system/features/customers/presentation/credit_draft_agreement_action.dart';
import 'package:credit_system/features/customers/presentation/credit_draft_agreement_view_screen.dart';

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
    creditType: Value(credit.creditType.value),
  ));
}

/// Taps the shared draft agreement action for [creditId] and waits until the
/// on-screen draft agreement view has opened.
///
/// Fails the test when the action reports an inline failure instead.
Future<void> openDraftAgreement(
  WidgetTester tester,
  String creditId,
) async {
  await tester.tap(find.byKey(CreditDraftAgreementAction.buttonKey(creditId)));
  await pumpUntil(
    tester,
    () =>
        find.byType(CreditDraftAgreementViewScreen).evaluate().isNotEmpty ||
        find.byKey(CreditDraftAgreementAction.errorKey(creditId)).evaluate().isNotEmpty,
  );
  final error =
      find.byKey(CreditDraftAgreementAction.errorKey(creditId));
  if (error.evaluate().isNotEmpty) {
    fail('Draft view failed: ${tester.widget<Text>(error).data}');
  }
}
