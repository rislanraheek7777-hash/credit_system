import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_dao.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';
import 'package:credit_system/features/customers/data/daos/credit_dao.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:credit_system/features/customers/domain/services/credit_submission_idempotency.dart';
import 'package:credit_system/features/customers/presentation/credit_disbursement_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the customer-facing consequence of finding T2
/// (Story 4.3).
///
/// A cash-disbursement confirmation that reuses an idempotency key claimed by
/// another operation must never be reported to the operator as a successful
/// disbursement. Before the fix the screen showed
/// "Cash disbursement confirmed" while the agreement was still awaiting
/// disbursement.
void main() {
  const shopId = '11111111-1111-1111-1111-111111111801';
  const customerId = 1;
  const managerId = '11111111-1111-1111-1111-111111111804';
  const itemId = 'coll-ui-idem-1';

  late AppDatabase db;

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);

    final now = DateTime.now().toUtc();
    await db.into(db.shops).insert(ShopEntry(
      id: shopId,
      name: 'Idempotency Shop',
      currencyCode: 'LKR',
      timezone: 'Asia/Colombo',
      createdAt: now,
      updatedAt: now,
    ));
    await db.into(db.appUsers).insert(AppUserEntry(
      id: managerId,
      shopId: shopId,
      username: 'idem.manager',
      fullName: 'Idem Manager',
      role: 'manager',
      isActive: true,
      sessionVersion: 1,
      createdAt: now,
      updatedAt: now,
    ));
    await db.into(db.customers).insert(CustomerEntry(
      id: customerId,
      shopId: shopId,
      fullName: 'Idempotency Customer',
      nic: '851234567V',
      phone: '0771234567',
      address: '1 Main St',
      createdAt: now,
      updatedAt: now,
    ));
    await CollateralDao(db).createCollateralItem(CollateralItem(
      id: itemId,
      shopId: shopId,
      customerId: customerId,
      itemReferenceId: 'COLL-UI-IDEM-001',
      category: CollateralItemCategory.gold,
      description: '22K gold necklace',
      conditionGrade: 'Like New',
      weightMilligrams: 5500,
      estimatedValueCents: 1500000,
    ));
  });

  tearDown(() async {
    await db.close();
  });

  AppUser manager() => AppUser(
        id: managerId,
        shopId: shopId,
        username: 'idem.manager',
        fullName: 'Idem Manager',
        role: AppRole.manager,
        isActive: true,
      );

  testWidgets(
      'a confirmation that reuses an origination key reports an error instead '
      'of a successful disbursement', (tester) async {
    final creditDao = CreditDao(db);
    final credit = await creditDao.createCreditAgreement(
      actor: manager(),
      idempotencyKey: 'shared-ui-key',
      customerId: customerId,
      principal: const Money(500000),
      dueDate: DateTime.now().toUtc().add(const Duration(days: 30)),
      createdAt: DateTime.now().toUtc(),
      collateralItemIds: const [itemId],
      termPresetDays: 30,
    );

    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      home: CreditDisbursementScreen(
        shopId: shopId,
        creditId: credit.id,
        currentUser: manager(),
        database: db,
        // The screen is forced to reuse the key that the origination already
        // claimed.
        idempotency: _FixedKeyIdempotency('shared-ui-key'),
      ),
    ));

    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find
          .byKey(const Key('disbursement_state_banner'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }

    await tester.tap(find.byKey(const Key('confirm_disbursement_button')));
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find
          .byKey(const Key('disbursement_error_display'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }

    // The operator is told the confirmation failed ...
    expect(find.byKey(const Key('disbursement_error_display')), findsOneWidget);
    // ... and is NOT told that cash was handed over.
    expect(find.byKey(const Key('disbursement_success_display')), findsNothing);

    // The agreement is still awaiting disbursement.
    final still = await creditDao.getCreditById(shopId, credit.id);
    expect(still!.workflowStatus, equals(CreditWorkflowStatus.pendingDisbursement));
    expect(still.disbursedAt, isNull);
    expect(still.disbursedByUserId, isNull);

    // No disbursement event was recorded.
    final events = (await db.select(db.syncQueue).get())
        .where((r) => r.actionType == CreditDao.confirmCreditDisbursementActionType)
        .toList();
    expect(events, isEmpty);
  });
}

/// Forces every submission to use one fixed idempotency key.
class _FixedKeyIdempotency extends CreditSubmissionIdempotency {
  _FixedKeyIdempotency(this.fixedKey);

  final String fixedKey;

  @override
  String keyFor(CreditSubmissionFingerprint fingerprint) => fixedKey;
}

