import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/core/permissions/authorization_guard.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_dao.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';
import 'package:credit_system/features/customers/data/daos/credit_dao.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';

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

void main() {
  late AppDatabase db;
  late CreditDao creditDao;

  const shopAlphaId = '11111111-1111-1111-1111-111111111101';
  const shopBetaId = '11111111-1111-1111-1111-111111111102';
  const int customerAlphaId = 11;
  const int customerBetaId = 12;

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);
    creditDao = CreditDao(db);

    final now = DateTime.now().toUtc();
    await db.into(db.shops).insert(
      ShopEntry(
        id: shopAlphaId,
        name: 'Alpha Jewellers',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.shops).insert(
      ShopEntry(
        id: shopBetaId,
        name: 'Beta Jewellers',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.customers).insert(
      CustomerEntry(
        id: customerAlphaId,
        shopId: shopAlphaId,
        fullName: 'Alpha Customer',
        nic: '851234567V',
        phone: '0771234567',
        address: '1 Main St',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.customers).insert(
      CustomerEntry(
        id: customerBetaId,
        shopId: shopBetaId,
        fullName: 'Beta Customer',
        nic: '901234567V',
        phone: '0779876543',
        address: '2 Main St',
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('CreditDao - Shop-Scoped Queries', () {
    test('createCredit inserts record with correct shop scoping', () async {
      final now = DateTime.now().toUtc();
      await insertCredit(db,
        Credit(
          id: 'credit-alpha-1',
          shopId: shopAlphaId,
          customerId: customerAlphaId,
          principalCents: 500000,
          balanceCents: 500000,
          status: CreditStatus.active,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
        ),
      );

      final credits = await creditDao.getCreditsByCustomerId(
        shopAlphaId,
        customerAlphaId,
      );
      expect(credits.length, equals(1));
      expect(credits.first.id, equals('credit-alpha-1'));
      expect(credits.first.status, equals(CreditStatus.active));
    });

    test('getCreditsByCustomerId is strictly shop-scoped', () async {
      final now = DateTime.now().toUtc();
      await insertCredit(db,
        Credit(
          id: 'credit-alpha-1',
          shopId: shopAlphaId,
          customerId: customerAlphaId,
          principalCents: 500000,
          balanceCents: 500000,
          status: CreditStatus.active,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
        ),
      );
      await insertCredit(db,
        Credit(
          id: 'credit-beta-1',
          shopId: shopBetaId,
          customerId: customerBetaId,
          principalCents: 300000,
          balanceCents: 300000,
          status: CreditStatus.active,
          dueDate: now.add(const Duration(days: 60)),
          createdAt: now,
        ),
      );

      final alphaCredits = await creditDao.getCreditsByCustomerId(
        shopAlphaId,
        customerAlphaId,
      );
      expect(alphaCredits.length, equals(1));
      expect(alphaCredits.first.id, equals('credit-alpha-1'));

      final betaCredits = await creditDao.getCreditsByCustomerId(
        shopBetaId,
        customerBetaId,
      );
      expect(betaCredits.length, equals(1));
      expect(betaCredits.first.id, equals('credit-beta-1'));
    });

    test('getCreditsByStatus filters by status within shop', () async {
      final now = DateTime.now().toUtc();
      await insertCredit(db,
        Credit(
          id: 'credit-active-1',
          shopId: shopAlphaId,
          customerId: customerAlphaId,
          principalCents: 500000,
          balanceCents: 500000,
          status: CreditStatus.active,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
        ),
      );
      await insertCredit(db,
        Credit(
          id: 'credit-overdue-1',
          shopId: shopAlphaId,
          customerId: customerAlphaId,
          principalCents: 300000,
          balanceCents: 300000,
          status: CreditStatus.overdue,
          dueDate: now.subtract(const Duration(days: 5)),
          createdAt: now,
        ),
      );
      await insertCredit(db,
        Credit(
          id: 'credit-settled-1',
          shopId: shopAlphaId,
          customerId: customerAlphaId,
          principalCents: 200000,
          balanceCents: 0,
          status: CreditStatus.settled,
          workflowStatus: CreditWorkflowStatus.disbursed,
          dueDate: now.subtract(const Duration(days: 10)),
          createdAt: now,
          settledAt: now,
        ),
      );

      final activeCredits = await creditDao.getCreditsByStatus(
        shopAlphaId,
        CreditStatus.active,
      );
      expect(activeCredits.length, equals(1));
      expect(activeCredits.first.status, equals(CreditStatus.active));

      final overdueCredits = await creditDao.getCreditsByStatus(
        shopAlphaId,
        CreditStatus.overdue,
      );
      expect(overdueCredits.length, equals(1));
      expect(overdueCredits.first.status, equals(CreditStatus.overdue));

      final settledCredits = await creditDao.getCreditsByStatus(
        shopAlphaId,
        CreditStatus.settled,
      );
      expect(settledCredits.length, equals(1));
      expect(settledCredits.first.status, equals(CreditStatus.settled));
    });

    test('getCreditsByCustomerAndStatus filters by both customer and status', () async {
      final now = DateTime.now().toUtc();
      await insertCredit(db,
        Credit(
          id: 'credit-active-1',
          shopId: shopAlphaId,
          customerId: customerAlphaId,
          principalCents: 500000,
          balanceCents: 500000,
          status: CreditStatus.active,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
        ),
      );
      await insertCredit(db,
        Credit(
          id: 'credit-active-2',
          shopId: shopAlphaId,
          customerId: customerBetaId,
          principalCents: 300000,
          balanceCents: 300000,
          status: CreditStatus.active,
          dueDate: now.add(const Duration(days: 60)),
          createdAt: now,
        ),
      );

      final alphaActiveCredits = await creditDao.getCreditsByCustomerAndStatus(
        shopAlphaId,
        customerAlphaId,
        CreditStatus.active,
      );
      expect(alphaActiveCredits.length, equals(1));
      expect(alphaActiveCredits.first.id, equals('credit-active-1'));

      final betaActiveCredits = await creditDao.getCreditsByCustomerAndStatus(
        shopAlphaId,
        customerBetaId,
        CreditStatus.active,
      );
      expect(betaActiveCredits.length, equals(1));
      expect(betaActiveCredits.first.id, equals('credit-active-2'));
    });

    test('getCreditById returns null for cross-shop lookup', () async {
      final now = DateTime.now().toUtc();
      await insertCredit(db,
        Credit(
          id: 'credit-alpha-1',
          shopId: shopAlphaId,
          customerId: customerAlphaId,
          principalCents: 500000,
          balanceCents: 500000,
          status: CreditStatus.active,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
        ),
      );

      final found = await creditDao.getCreditById(shopAlphaId, 'credit-alpha-1');
      expect(found, isNotNull);
      expect(found!.id, equals('credit-alpha-1'));

      final notFound = await creditDao.getCreditById(shopBetaId, 'credit-alpha-1');
      expect(notFound, isNull);
    });
  });

  group('CreditDao - Story 4.1 Credit Agreement Creation', () {
    const itemId = 'collateral-item-1';
    const secondItemId = 'collateral-item-2';
    const cashierId = 'cashier-user-1';
    const otherShopCustomerId = 13;

    late CollateralDao collateralDao;
    late AppUser cashier;
    late AppUser deactivatedCashier;
    late AppUser unprivilegedUser;

    setUp(() async {
      collateralDao = CollateralDao(db);

      cashier = AppUser(
        id: cashierId,
        shopId: shopAlphaId,
        username: 'alpha.cashier',
        fullName: 'Alpha Cashier',
        role: AppRole.cashier,
        isActive: true,
      );
      deactivatedCashier = AppUser(
        id: cashierId,
        shopId: shopAlphaId,
        username: 'alpha.cashier',
        fullName: 'Alpha Cashier',
        role: AppRole.cashier,
        isActive: false,
      );
      unprivilegedUser = AppUser(
        id: 'unprivileged-user',
        shopId: shopAlphaId,
        username: 'alpha.viewer',
        fullName: 'Alpha Viewer',
        role: AppRole.custom,
        customPermissions: const {AppPermission.viewCustomers},
        isActive: true,
      );

      final now = DateTime.now().toUtc();
      await db.into(db.appUsers).insert(
        AppUserEntry(
          id: cashierId,
          shopId: shopAlphaId,
          username: 'alpha.cashier',
          fullName: 'Alpha Cashier',
          role: 'cashier',
          isActive: true,
          sessionVersion: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db.into(db.customers).insert(
        CustomerEntry(
          id: otherShopCustomerId,
          shopId: shopAlphaId,
          fullName: 'Second Alpha Customer',
          nic: '951234567V',
          phone: '0775556667',
          address: '5 Main St',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await collateralDao.createCollateralItem(CollateralItem(
        id: itemId,
        shopId: shopAlphaId,
        customerId: customerAlphaId,
        itemReferenceId: 'COLL-4-1-001',
        category: CollateralItemCategory.gold,
        description: '22K gold necklace',
        conditionGrade: 'Like New',
        weightMilligrams: 5500,
        estimatedValueCents: 1500000,
      ));
      await collateralDao.createCollateralItem(CollateralItem(
        id: secondItemId,
        shopId: shopAlphaId,
        customerId: customerAlphaId,
        itemReferenceId: 'COLL-4-1-002',
        category: CollateralItemCategory.electronics,
        description: 'Laptop',
        conditionGrade: 'Good',
        weightMilligrams: 1500000,
        estimatedValueCents: 400000,
      ));
    });

    Future<Credit> createAgreement({
      String idempotencyKey = 'idem-key-1',
      int customerId = customerAlphaId,
      Money principal = const Money(500000),
      List<String> collateralItemIds = const [itemId],
      AppUser? actor,
    }) {
      return creditDao.createCreditAgreement(
        actor: actor ?? cashier,
        idempotencyKey: idempotencyKey,
        customerId: customerId,
        principal: principal,
        dueDate: DateTime.now().toUtc().add(const Duration(days: 30)),
        createdAt: DateTime.now().toUtc(),
        collateralItemIds: collateralItemIds,
      );
    }

    test('initial outstanding balance equals the principal exactly', () async {
      final credit = await createAgreement(
        principal: const Money(500000),
      );

      expect(credit.principalCents, equals(500000));
      expect(credit.balanceCents, equals(500000));
      expect(credit.balanceCents, equals(credit.principalCents));
    });

    test('applies no interest or fees to the principal', () async {
      // A one-year term must still leave the balance exactly equal to the
      // principal: the model is strictly zero-interest.
      final createdAt = DateTime.utc(2026, 10, 14);
      final credit = await creditDao.createCreditAgreement(
        actor: cashier,
        idempotencyKey: 'idem-zero-interest',
        customerId: customerAlphaId,
        principal: const Money(123456),
        dueDate: createdAt.add(const Duration(days: 365)),
        createdAt: createdAt,
        collateralItemIds: const [itemId],
      );

      expect(credit.principalCents, equals(123456));
      expect(credit.balanceCents, equals(123456));
    });

    test('initialises financial status Active and workflow status Pending '
        'Disbursement', () async {
      final credit = await createAgreement();

      expect(credit.status, equals(CreditStatus.active));
      expect(
        credit.workflowStatus,
        equals(CreditWorkflowStatus.pendingDisbursement),
      );
      expect(credit.isPendingDisbursement, isTrue);
      expect(credit.isDisbursed, isFalse);
      expect(credit.settledAt, isNull);
    });

    test('marks an amount-only agreement as a cash credit', () async {
      final credit = await createAgreement(collateralItemIds: const []);

      expect(credit.creditType, equals(CreditType.cash));

      // The type round-trips through persistence.
      final persisted = await creditDao.getCreditById(shopAlphaId, credit.id);
      expect(persisted?.creditType, equals(CreditType.cash));
    });

    test('marks an agreement with item receipts as an items credit', () async {
      final credit = await createAgreement(collateralItemIds: const [itemId]);

      expect(credit.creditType, equals(CreditType.items));

      final persisted = await creditDao.getCreditById(shopAlphaId, credit.id);
      expect(persisted?.creditType, equals(CreditType.items));
    });

    test('binds the pledged collateral items to the new credit', () async {
      final credit = await createAgreement(
        collateralItemIds: const [itemId, secondItemId],
      );

      final items = await collateralDao.getCollateralItemsByCreditId(
        shopAlphaId,
        credit.id,
      );
      expect(items.length, equals(2));
      expect(items.map((i) => i.id), containsAll([itemId, secondItemId]));
    });

    test('records the local audit event for credit agreement origination', () async {
      final createdAt = DateTime.utc(2026, 10, 14, 9, 30);
      final credit = await creditDao.createCreditAgreement(
        actor: cashier,
        idempotencyKey: 'idem-audit',
        customerId: customerAlphaId,
        principal: const Money(750000),
        dueDate: createdAt.add(const Duration(days: 30)),
        createdAt: createdAt,
        collateralItemIds: const [itemId],
      );

      final auditRows = await db.select(db.syncQueue).get();
      final audit = auditRows.firstWhere(
        (row) => row.entityId == credit.id && row.entityType == 'credit',
      );

      expect(audit.actionType, equals('create_credit'));
      expect(audit.status, equals('pending_server_ack'));
      expect(audit.shopId, equals(shopAlphaId));

      final payload = jsonDecode(audit.payloadJson) as Map<String, dynamic>;
      // PRD FR-31 category 2 is "Credit agreement origination".
      expect(payload['auditCategory'], equals(2));
      expect(payload['auditEvent'], equals('credit_agreement_origination'));
      // The actor, credit reference, amount and timestamp are preserved.
      expect(payload['actorId'], equals(cashier.id));
      expect(payload['creditId'], equals(credit.id));
      expect(payload['principalCents'], equals(750000));
      expect(payload['currency'], equals('LKR'));
      expect(
        payload['createdAt'],
        equals(createdAt.toIso8601String()),
      );
    });

    test('rejects a deactivated actor', () async {
      await expectLater(
        () async => await createAgreement(actor: deactivatedCashier),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('rejects an actor without the createCredits permission', () async {
      await expectLater(
        () async => await createAgreement(actor: unprivilegedUser),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('rejects a non-positive principal amount', () async {
      await expectLater(
        () async => await createAgreement(principal: const Money(0)),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        () async => await createAgreement(principal: const Money(-100)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a blank idempotency key', () async {
      await expectLater(
        () async => await createAgreement(idempotencyKey: '   '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('creates a credit with zero item receipts', () async {
      final credit = await createAgreement(collateralItemIds: const []);

      expect(credit.id, isNotEmpty);
      expect(credit.principalCents, equals(500000));
      expect(credit.balanceCents, equals(500000));

      final persisted = await creditDao.getCreditById(shopAlphaId, credit.id);
      expect(persisted, isNotNull);
      expect(persisted!.id, equals(credit.id));

      // No item receipt was bound to the new agreement.
      final items = await db.select(db.collateralItems).get();
      expect(items.every((i) => i.creditId == null), isTrue);
    });

    test('rejects a customer that does not belong to the actor shop', () async {
      // The customer exists, but in a different tenant.
      await expectLater(
        () async => await createAgreement(customerId: customerBetaId),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects a collateral item that does not exist', () async {
      await expectLater(
        () async => await createAgreement(collateralItemIds: const ['missing-item']),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects a collateral item belonging to another customer', () async {
      await expectLater(
        () async => await createAgreement(
          customerId: otherShopCustomerId,
          collateralItemIds: const [itemId],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects a collateral item already pledged to another credit', () async {
      final first = await createAgreement(idempotencyKey: 'idem-first');
      expect(first.id, isNotEmpty);

      // A second agreement cannot re-pledge the same item.
      await expectLater(
        () async => await createAgreement(
          idempotencyKey: 'idem-second',
          collateralItemIds: const [itemId],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('is idempotent: a repeated submission with the same key returns the '
        'original agreement', () async {
      final first = await createAgreement(idempotencyKey: 'idem-repeat');
      final second = await createAgreement(idempotencyKey: 'idem-repeat');

      expect(second.id, equals(first.id));
      expect(second.balanceCents, equals(first.balanceCents));

      final credits = await db.select(db.credits).get();
      expect(credits.length, equals(1));

      // The audit event is not duplicated either.
      final auditRows = await db.select(db.syncQueue).get();
      expect(auditRows.length, equals(1));
    });

    test('commits exactly one agreement for concurrent duplicate submissions',
        () async {
      final results = await Future.wait([
        createAgreement(idempotencyKey: 'idem-concurrent'),
        createAgreement(idempotencyKey: 'idem-concurrent'),
      ]);

      expect(results[0].id, equals(results[1].id));

      final credits = await db.select(db.credits).get();
      expect(credits.length, equals(1));
    });

    test('rolls back atomically when the audit event cannot be persisted',
        () async {
      // Simulate an audit-persistence failure on the local audit/sync queue.
      await db.customStatement('''
        CREATE TRIGGER "fail_sync_queue_insert"
        BEFORE INSERT ON "sync_queue"
        BEGIN
          SELECT RAISE(ABORT, 'simulated audit persistence failure');
        END;
      ''');

      await expectLater(
        createAgreement(idempotencyKey: 'idem-audit-failure'),
        throwsA(anything),
      );

      // The agreement must not survive a failed audit write.
      final credits = await db.select(db.credits).get();
      expect(credits, isEmpty);

      final auditRows = await db.select(db.syncQueue).get();
      expect(auditRows, isEmpty);
    });

    test('scopes the created agreement to the actor shop', () async {
      final credit = await createAgreement();

      expect(credit.shopId, equals(shopAlphaId));
      expect(credit.customerId, equals(customerAlphaId));

      // A different tenant cannot see the agreement.
      final crossShop = await creditDao.getCreditById(shopBetaId, credit.id);
      expect(crossShop, isNull);
    });

    test('blocks payments while the agreement is pending disbursement', () async {
      final credit = await createAgreement();

      expect(credit.isActionable, isFalse);
      expect(
        credit.assertPaymentsAllowed,
        throwsA(
          isA<CreditPaymentBlockedException>().having(
            (e) => e.message,
            'message',
            'Payments cannot be accepted on undisbursed credits.',
          ),
        ),
      );
    });
  });
}

