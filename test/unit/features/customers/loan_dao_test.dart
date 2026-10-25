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
import 'package:credit_system/features/customers/data/daos/loan_dao.dart';
import 'package:credit_system/features/customers/domain/models/loan.dart';

Future<void> insertLoan(AppDatabase db, Loan loan) async {
  await db.into(db.loans).insert(LoansCompanion(
    id: Value(loan.id),
    shopId: Value(loan.shopId),
    customerId: Value(loan.customerId),
    principalCents: Value(loan.principalCents),
    balanceCents: Value(loan.balanceCents),
    status: Value(loan.status.value),
    workflowStatus: Value(loan.workflowStatus.value),
    termPresetDays: Value(loan.termPresetDays),
    customDueDate: Value(loan.customDueDate),
    disbursedAt: Value(loan.disbursedAt),
    disbursedByUserId: Value(loan.disbursedByUserId),
    cancelledAt: Value(loan.cancelledAt),
    cancellationReason: Value(loan.cancellationReason),
    dueDate: Value(loan.dueDate),
    createdAt: Value(loan.createdAt),
    settledAt: Value(loan.settledAt),
  ));
}

void main() {
  late AppDatabase db;
  late LoanDao loanDao;

  const shopAlphaId = '11111111-1111-1111-1111-111111111101';
  const shopBetaId = '11111111-1111-1111-1111-111111111102';
  const customerAlphaId = '11111111-1111-1111-1111-111111111103';
  const customerBetaId = '11111111-1111-1111-1111-111111111104';

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);
    loanDao = LoanDao(db);

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

  group('LoanDao - Shop-Scoped Queries', () {
    test('createLoan inserts record with correct shop scoping', () async {
      final now = DateTime.now().toUtc();
      await insertLoan(db,
        Loan(
          id: 'loan-alpha-1',
          shopId: shopAlphaId,
          customerId: customerAlphaId,
          principalCents: 500000,
          balanceCents: 500000,
          status: LoanStatus.active,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
        ),
      );

      final loans = await loanDao.getLoansByCustomerId(
        shopAlphaId,
        customerAlphaId,
      );
      expect(loans.length, equals(1));
      expect(loans.first.id, equals('loan-alpha-1'));
      expect(loans.first.status, equals(LoanStatus.active));
    });

    test('getLoansByCustomerId is strictly shop-scoped', () async {
      final now = DateTime.now().toUtc();
      await insertLoan(db,
        Loan(
          id: 'loan-alpha-1',
          shopId: shopAlphaId,
          customerId: customerAlphaId,
          principalCents: 500000,
          balanceCents: 500000,
          status: LoanStatus.active,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
        ),
      );
      await insertLoan(db,
        Loan(
          id: 'loan-beta-1',
          shopId: shopBetaId,
          customerId: customerBetaId,
          principalCents: 300000,
          balanceCents: 300000,
          status: LoanStatus.active,
          dueDate: now.add(const Duration(days: 60)),
          createdAt: now,
        ),
      );

      final alphaLoans = await loanDao.getLoansByCustomerId(
        shopAlphaId,
        customerAlphaId,
      );
      expect(alphaLoans.length, equals(1));
      expect(alphaLoans.first.id, equals('loan-alpha-1'));

      final betaLoans = await loanDao.getLoansByCustomerId(
        shopBetaId,
        customerBetaId,
      );
      expect(betaLoans.length, equals(1));
      expect(betaLoans.first.id, equals('loan-beta-1'));
    });

    test('getLoansByStatus filters by status within shop', () async {
      final now = DateTime.now().toUtc();
      await insertLoan(db,
        Loan(
          id: 'loan-active-1',
          shopId: shopAlphaId,
          customerId: customerAlphaId,
          principalCents: 500000,
          balanceCents: 500000,
          status: LoanStatus.active,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
        ),
      );
      await insertLoan(db,
        Loan(
          id: 'loan-overdue-1',
          shopId: shopAlphaId,
          customerId: customerAlphaId,
          principalCents: 300000,
          balanceCents: 300000,
          status: LoanStatus.overdue,
          dueDate: now.subtract(const Duration(days: 5)),
          createdAt: now,
        ),
      );
      await insertLoan(db,
        Loan(
          id: 'loan-settled-1',
          shopId: shopAlphaId,
          customerId: customerAlphaId,
          principalCents: 200000,
          balanceCents: 0,
          status: LoanStatus.settled,
          workflowStatus: LoanWorkflowStatus.disbursed,
          dueDate: now.subtract(const Duration(days: 10)),
          createdAt: now,
          settledAt: now,
        ),
      );

      final activeLoans = await loanDao.getLoansByStatus(
        shopAlphaId,
        LoanStatus.active,
      );
      expect(activeLoans.length, equals(1));
      expect(activeLoans.first.status, equals(LoanStatus.active));

      final overdueLoans = await loanDao.getLoansByStatus(
        shopAlphaId,
        LoanStatus.overdue,
      );
      expect(overdueLoans.length, equals(1));
      expect(overdueLoans.first.status, equals(LoanStatus.overdue));

      final settledLoans = await loanDao.getLoansByStatus(
        shopAlphaId,
        LoanStatus.settled,
      );
      expect(settledLoans.length, equals(1));
      expect(settledLoans.first.status, equals(LoanStatus.settled));
    });

    test('getLoansByCustomerAndStatus filters by both customer and status', () async {
      final now = DateTime.now().toUtc();
      await insertLoan(db,
        Loan(
          id: 'loan-active-1',
          shopId: shopAlphaId,
          customerId: customerAlphaId,
          principalCents: 500000,
          balanceCents: 500000,
          status: LoanStatus.active,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
        ),
      );
      await insertLoan(db,
        Loan(
          id: 'loan-active-2',
          shopId: shopAlphaId,
          customerId: customerBetaId,
          principalCents: 300000,
          balanceCents: 300000,
          status: LoanStatus.active,
          dueDate: now.add(const Duration(days: 60)),
          createdAt: now,
        ),
      );

      final alphaActiveLoans = await loanDao.getLoansByCustomerAndStatus(
        shopAlphaId,
        customerAlphaId,
        LoanStatus.active,
      );
      expect(alphaActiveLoans.length, equals(1));
      expect(alphaActiveLoans.first.id, equals('loan-active-1'));

      final betaActiveLoans = await loanDao.getLoansByCustomerAndStatus(
        shopAlphaId,
        customerBetaId,
        LoanStatus.active,
      );
      expect(betaActiveLoans.length, equals(1));
      expect(betaActiveLoans.first.id, equals('loan-active-2'));
    });

    test('getLoanById returns null for cross-shop lookup', () async {
      final now = DateTime.now().toUtc();
      await insertLoan(db,
        Loan(
          id: 'loan-alpha-1',
          shopId: shopAlphaId,
          customerId: customerAlphaId,
          principalCents: 500000,
          balanceCents: 500000,
          status: LoanStatus.active,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
        ),
      );

      final found = await loanDao.getLoanById(shopAlphaId, 'loan-alpha-1');
      expect(found, isNotNull);
      expect(found!.id, equals('loan-alpha-1'));

      final notFound = await loanDao.getLoanById(shopBetaId, 'loan-alpha-1');
      expect(notFound, isNull);
    });
  });

  group('LoanDao - Story 4.1 Loan Agreement Creation', () {
    const itemId = 'collateral-item-1';
    const secondItemId = 'collateral-item-2';
    const cashierId = 'cashier-user-1';
    const otherShopCustomerId = '11111111-1111-1111-1111-111111111105';

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

    Future<Loan> createAgreement({
      String idempotencyKey = 'idem-key-1',
      String customerId = customerAlphaId,
      Money principal = const Money(500000),
      List<String> collateralItemIds = const [itemId],
      AppUser? actor,
    }) {
      return loanDao.createLoanAgreement(
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
      final loan = await createAgreement(
        principal: const Money(500000),
      );

      expect(loan.principalCents, equals(500000));
      expect(loan.balanceCents, equals(500000));
      expect(loan.balanceCents, equals(loan.principalCents));
    });

    test('applies no interest or fees to the principal', () async {
      // A one-year term must still leave the balance exactly equal to the
      // principal: the model is strictly zero-interest.
      final createdAt = DateTime.utc(2026, 10, 14);
      final loan = await loanDao.createLoanAgreement(
        actor: cashier,
        idempotencyKey: 'idem-zero-interest',
        customerId: customerAlphaId,
        principal: const Money(123456),
        dueDate: createdAt.add(const Duration(days: 365)),
        createdAt: createdAt,
        collateralItemIds: const [itemId],
      );

      expect(loan.principalCents, equals(123456));
      expect(loan.balanceCents, equals(123456));
    });

    test('initialises financial status Active and workflow status Pending '
        'Disbursement', () async {
      final loan = await createAgreement();

      expect(loan.status, equals(LoanStatus.active));
      expect(
        loan.workflowStatus,
        equals(LoanWorkflowStatus.pendingDisbursement),
      );
      expect(loan.isPendingDisbursement, isTrue);
      expect(loan.isDisbursed, isFalse);
      expect(loan.settledAt, isNull);
    });

    test('binds the pledged collateral items to the new loan', () async {
      final loan = await createAgreement(
        collateralItemIds: const [itemId, secondItemId],
      );

      final items = await collateralDao.getCollateralItemsByLoanId(
        shopAlphaId,
        loan.id,
      );
      expect(items.length, equals(2));
      expect(items.map((i) => i.id), containsAll([itemId, secondItemId]));
    });

    test('records the local audit event for loan agreement origination', () async {
      final createdAt = DateTime.utc(2026, 10, 14, 9, 30);
      final loan = await loanDao.createLoanAgreement(
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
        (row) => row.entityId == loan.id && row.entityType == 'loan',
      );

      expect(audit.actionType, equals('create_loan'));
      expect(audit.status, equals('pending_server_ack'));
      expect(audit.shopId, equals(shopAlphaId));

      final payload = jsonDecode(audit.payloadJson) as Map<String, dynamic>;
      // PRD FR-31 category 2 is "Loan agreement origination".
      expect(payload['auditCategory'], equals(2));
      expect(payload['auditEvent'], equals('loan_agreement_origination'));
      // The actor, loan reference, principal amount and timestamp are preserved.
      expect(payload['actorId'], equals(cashier.id));
      expect(payload['loanId'], equals(loan.id));
      expect(payload['principalCents'], equals(750000));
      expect(payload['currency'], equals('LKR'));
      expect(
        payload['createdAt'],
        equals(createdAt.toIso8601String()),
      );
    });

    test('rejects a deactivated actor', () async {
      expect(
        () => createAgreement(actor: deactivatedCashier),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('rejects an actor without the createLoans permission', () async {
      expect(
        () => createAgreement(actor: unprivilegedUser),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('rejects a non-positive principal amount', () async {
      expect(
        () => createAgreement(principal: const Money(0)),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => createAgreement(principal: const Money(-100)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a blank idempotency key', () async {
      expect(
        () => createAgreement(idempotencyKey: '   '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a loan with no pledged collateral item', () async {
      expect(
        () => createAgreement(collateralItemIds: const []),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a customer that does not belong to the actor shop', () async {
      // The customer exists, but in a different tenant.
      expect(
        () => createAgreement(customerId: customerBetaId),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects a collateral item that does not exist', () async {
      expect(
        () => createAgreement(collateralItemIds: const ['missing-item']),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects a collateral item belonging to another customer', () async {
      expect(
        () => createAgreement(
          customerId: otherShopCustomerId,
          collateralItemIds: const [itemId],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects a collateral item already pledged to another loan', () async {
      final first = await createAgreement(idempotencyKey: 'idem-first');
      expect(first.id, isNotEmpty);

      // A second agreement cannot re-pledge the same item.
      expect(
        () => createAgreement(
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

      final loans = await db.select(db.loans).get();
      expect(loans.length, equals(1));

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

      final loans = await db.select(db.loans).get();
      expect(loans.length, equals(1));
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
      final loans = await db.select(db.loans).get();
      expect(loans, isEmpty);

      final auditRows = await db.select(db.syncQueue).get();
      expect(auditRows, isEmpty);
    });

    test('scopes the created agreement to the actor shop', () async {
      final loan = await createAgreement();

      expect(loan.shopId, equals(shopAlphaId));
      expect(loan.customerId, equals(customerAlphaId));

      // A different tenant cannot see the agreement.
      final crossShop = await loanDao.getLoanById(shopBetaId, loan.id);
      expect(crossShop, isNull);
    });

    test('blocks payments while the agreement is pending disbursement', () async {
      final loan = await createAgreement();

      expect(loan.isActionable, isFalse);
      expect(
        loan.assertPaymentsAllowed,
        throwsA(
          isA<LoanPaymentBlockedException>().having(
            (e) => e.message,
            'message',
            'Payments cannot be accepted on undisbursed loans.',
          ),
        ),
      );
    });
  });
}
