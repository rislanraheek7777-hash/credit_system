import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/core/permissions/authorization_guard.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_dao.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';
import 'package:credit_system/features/customers/domain/models/loan.dart';

void main() {
  late AppDatabase db;
  late CollateralDao collateralDao;

  const shopId = 'shop-closure-test';
  const customerId = 'cust-closure-test';
  const settledLoanId = 'loan-settled-01';
  const activeLoanId = 'loan-active-02';

  final ownerUser = AppUser(
    id: 'user-owner',
    shopId: shopId,
    username: 'owner',
    fullName: 'Shop Owner',
    role: AppRole.shopOwner,
  );

  final managerUser = AppUser(
    id: 'user-manager',
    shopId: shopId,
    username: 'manager',
    fullName: 'Shop Manager',
    role: AppRole.manager,
  );

  final inactiveOwner = AppUser(
    id: 'user-inactive-owner',
    shopId: shopId,
    username: 'inactive_owner',
    fullName: 'Inactive Owner',
    role: AppRole.shopOwner,
    isActive: false,
  );

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);
    collateralDao = CollateralDao(db);

    final now = DateTime.now().toUtc();

    // 1. Seed Shop
    await db.into(db.shops).insert(
      ShopEntry(
        id: shopId,
        name: 'Closure Test Shop',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );

    // 2. Seed Customer
    await db.into(db.customers).insert(
      CustomerEntry(
        id: customerId,
        shopId: shopId,
        fullName: 'Closure Test Customer',
        nic: '991234567V',
        phone: '0779998888',
        address: '123 Main Street',
        createdAt: now,
        updatedAt: now,
      ),
    );

    // 3. Seed Users
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: ownerUser.id,
        shopId: shopId,
        username: ownerUser.username,
        fullName: ownerUser.fullName,
        role: 'shop_owner',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: managerUser.id,
        shopId: shopId,
        username: managerUser.username,
        fullName: managerUser.fullName,
        role: 'manager',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: inactiveOwner.id,
        shopId: shopId,
        username: inactiveOwner.username,
        fullName: inactiveOwner.fullName,
        role: 'shop_owner',
        isActive: false,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );

    // 4. Seed Settled Loan
    await db.into(db.loans).insert(
      LoanEntry(
        id: settledLoanId,
        shopId: shopId,
        customerId: customerId,
        principalCents: 500000,
        balanceCents: 0,
        status: LoanStatus.settled.value,
        workflowStatus: LoanWorkflowStatus.disbursed.value,
        dueDate: now.subtract(const Duration(days: 5)),
        createdAt: now.subtract(const Duration(days: 35)),
        settledAt: now.subtract(const Duration(days: 2)),
        correctionPending: false,
      ),
    );

    // 5. Seed Active Loan
    await db.into(db.loans).insert(
      LoanEntry(
        id: activeLoanId,
        shopId: shopId,
        customerId: customerId,
        principalCents: 500000,
        balanceCents: 500000,
        status: LoanStatus.active.value,
        workflowStatus: LoanWorkflowStatus.disbursed.value,
        dueDate: now.add(const Duration(days: 25)),
        createdAt: now.subtract(const Duration(days: 5)),
        correctionPending: false,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  CollateralItem createTestItem({
    required String id,
    required String loanId,
    required String referenceId,
    required CollateralCustodyStatus custodyStatus,
  }) {
    final now = DateTime.now().toUtc();
    return CollateralItem(
      id: id,
      shopId: shopId,
      customerId: customerId,
      loanId: loanId,
      itemReferenceId: referenceId,
      category: CollateralItemCategory.gold,
      description: 'Test Gold Ring',
      conditionGrade: 'Good',
      weightMilligrams: 4000,
      estimatedValueCents: 80000,
      photoUri: '/photos/$id.jpg',
      photoHash: 'hash-$id',
      custodyStatus: custodyStatus,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('Story 3.5: Administrative Closure - Authorization & Validation', () {
    test('non-owner cannot execute administrative closure', () async {
      final item = createTestItem(
        id: 'item-1',
        loanId: settledLoanId,
        referenceId: 'ITEM-001',
        custodyStatus: CollateralCustodyStatus.exceptionHeld,
      );
      await collateralDao.createCollateralItem(item);

      expect(
        () => collateralDao.executeAdministrativeClosure(
          shopId,
          settledLoanId,
          actor: managerUser,
          reason: 'Item seized by authorities',
          idempotencyKey: 'idemp-mgr-01',
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('deactivated owner cannot execute administrative closure', () async {
      final item = createTestItem(
        id: 'item-2',
        loanId: settledLoanId,
        referenceId: 'ITEM-002',
        custodyStatus: CollateralCustodyStatus.exceptionHeld,
      );
      await collateralDao.createCollateralItem(item);

      expect(
        () => collateralDao.executeAdministrativeClosure(
          shopId,
          settledLoanId,
          actor: inactiveOwner,
          reason: 'Item lost in vault incident',
          idempotencyKey: 'idemp-inact-01',
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('blank reason is rejected with ArgumentError', () async {
      final item = createTestItem(
        id: 'item-3',
        loanId: settledLoanId,
        referenceId: 'ITEM-003',
        custodyStatus: CollateralCustodyStatus.exceptionHeld,
      );
      await collateralDao.createCollateralItem(item);

      expect(
        () => collateralDao.executeAdministrativeClosure(
          shopId,
          settledLoanId,
          actor: ownerUser,
          reason: '   ',
          idempotencyKey: 'idemp-blank-reason',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('blank idempotency key is rejected with ArgumentError', () async {
      final item = createTestItem(
        id: 'item-4',
        loanId: settledLoanId,
        referenceId: 'ITEM-004',
        custodyStatus: CollateralCustodyStatus.exceptionHeld,
      );
      await collateralDao.createCollateralItem(item);

      expect(
        () => collateralDao.executeAdministrativeClosure(
          shopId,
          settledLoanId,
          actor: ownerUser,
          reason: 'Valid reason',
          idempotencyKey: '   ',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('non-settled loan (active balance) cannot be administratively closed', () async {
      final item = createTestItem(
        id: 'item-5',
        loanId: activeLoanId,
        referenceId: 'ITEM-005',
        custodyStatus: CollateralCustodyStatus.exceptionHeld,
      );
      await collateralDao.createCollateralItem(item);

      expect(
        () => collateralDao.executeAdministrativeClosure(
          shopId,
          activeLoanId,
          actor: ownerUser,
          reason: 'Closure attempt on active loan',
          idempotencyKey: 'idemp-active-loan',
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('not fully settled'),
        )),
      );
    });

    test('loan without any exceptionHeld items cannot be administratively closed', () async {
      // Loan has only returned items
      final item = createTestItem(
        id: 'item-6',
        loanId: settledLoanId,
        referenceId: 'ITEM-006',
        custodyStatus: CollateralCustodyStatus.returned,
      );
      await collateralDao.createCollateralItem(item);

      expect(
        () => collateralDao.executeAdministrativeClosure(
          shopId,
          settledLoanId,
          actor: ownerUser,
          reason: 'All items returned, closure not needed',
          idempotencyKey: 'idemp-no-exception',
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('at least one collateral item must be in exception held status'),
        )),
      );
    });

    test('loan with active or unresolved items blocks administrative closure', () async {
      // 1 item in exceptionHeld, 1 item in discrepancy
      final item1 = createTestItem(
        id: 'item-7a',
        loanId: settledLoanId,
        referenceId: 'ITEM-007A',
        custodyStatus: CollateralCustodyStatus.exceptionHeld,
      );
      final item2 = createTestItem(
        id: 'item-7b',
        loanId: settledLoanId,
        referenceId: 'ITEM-007B',
        custodyStatus: CollateralCustodyStatus.discrepancy,
      );
      await collateralDao.createCollateralItem(item1);
      await collateralDao.createCollateralItem(item2);

      expect(
        () => collateralDao.executeAdministrativeClosure(
          shopId,
          settledLoanId,
          actor: ownerUser,
          reason: 'Try closing while discrepancy pending',
          idempotencyKey: 'idemp-discrepancy-block',
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('all items must be in terminal custody'),
        )),
      );
    });
  });

  group('Story 3.5: Administrative Closure - Successful Execution & Audit', () {
    test('successfully executes administrative closure, records Category 11 SyncQueue and closure entry', () async {
      // Item 1: exceptionHeld, Item 2: returned
      final item1 = createTestItem(
        id: 'item-8a',
        loanId: settledLoanId,
        referenceId: 'ITEM-008A',
        custodyStatus: CollateralCustodyStatus.exceptionHeld,
      );
      final item2 = createTestItem(
        id: 'item-8b',
        loanId: settledLoanId,
        referenceId: 'ITEM-008B',
        custodyStatus: CollateralCustodyStatus.returned,
      );
      await collateralDao.createCollateralItem(item1);
      await collateralDao.createCollateralItem(item2);

      const idempotencyKey = 'idemp-admin-closure-success-01';
      const reason = 'Police investigation impounded item 008A. Handover impossible.';

      await collateralDao.executeAdministrativeClosure(
        shopId,
        settledLoanId,
        actor: ownerUser,
        reason: reason,
        idempotencyKey: idempotencyKey,
      );

      // Verify closure record
      final closure = await collateralDao.getAdministrativeClosureByLoanId(
        shopId,
        settledLoanId,
      );
      expect(closure, isNotNull);
      expect(closure!.shopId, equals(shopId));
      expect(closure.loanId, equals(settledLoanId));
      expect(closure.reason, equals(reason));
      expect(closure.closedByUserId, equals(ownerUser.id));
      expect(closure.itemIds, contains(item1.id));
      expect(closure.itemIds.length, equals(1));

      // Verify isLoanAdministrativelyClosed
      final isClosed = await collateralDao.isLoanAdministrativelyClosed(
        shopId,
        settledLoanId,
      );
      expect(isClosed, isTrue);

      // Verify items remain in their original custody states
      final inDb1 = await collateralDao.getCollateralItemById(shopId, item1.id);
      expect(inDb1!.custodyStatus, equals(CollateralCustodyStatus.exceptionHeld));
      final inDb2 = await collateralDao.getCollateralItemById(shopId, item2.id);
      expect(inDb2!.custodyStatus, equals(CollateralCustodyStatus.returned));

      // Verify Category 11 SyncQueue entry
      final syncEntries = await (db.select(db.syncQueue)
            ..where((s) =>
                s.shopId.equals(shopId) &
                s.idempotencyKey.equals(idempotencyKey)))
          .get();
      expect(syncEntries.length, equals(1));
      final sync = syncEntries.first;
      expect(sync.entityType, equals('loan'));
      expect(sync.entityId, equals(settledLoanId));
      expect(sync.actionType, equals('close_collateral_exception'));

      final payload = jsonDecode(sync.payloadJson) as Map<String, dynamic>;
      expect(payload['auditCategory'], equals(11));
      expect(payload['auditEvent'], equals('loan_administrative_closure'));
      expect(payload['actorId'], equals(ownerUser.id));
      expect(payload['reason'], equals(reason));
      expect(payload['exceptionItemIds'], equals([item1.id]));
    });

    test('re-submitting with identical idempotency key is an idempotent no-op', () async {
      final item = createTestItem(
        id: 'item-9',
        loanId: settledLoanId,
        referenceId: 'ITEM-009',
        custodyStatus: CollateralCustodyStatus.exceptionHeld,
      );
      await collateralDao.createCollateralItem(item);

      const idempotencyKey = 'idemp-duplicate-test';
      const reason = 'Confiscated item cannot be returned';

      await collateralDao.executeAdministrativeClosure(
        shopId,
        settledLoanId,
        actor: ownerUser,
        reason: reason,
        idempotencyKey: idempotencyKey,
      );

      // Second execution with same key should not throw
      await collateralDao.executeAdministrativeClosure(
        shopId,
        settledLoanId,
        actor: ownerUser,
        reason: reason,
        idempotencyKey: idempotencyKey,
      );

      // Exactly 1 closure and 1 sync queue record
      final closures = await (db.select(db.loanAdministrativeClosures)
            ..where((c) => c.shopId.equals(shopId) & c.loanId.equals(settledLoanId)))
          .get();
      expect(closures.length, equals(1));

      final syncEntries = await (db.select(db.syncQueue)
            ..where((s) => s.shopId.equals(shopId) & s.idempotencyKey.equals(idempotencyKey)))
          .get();
      expect(syncEntries.length, equals(1));
    });

    test('attempting second closure on already-closed loan under different key throws StateError', () async {
      final item = createTestItem(
        id: 'item-10',
        loanId: settledLoanId,
        referenceId: 'ITEM-010',
        custodyStatus: CollateralCustodyStatus.exceptionHeld,
      );
      await collateralDao.createCollateralItem(item);

      await collateralDao.executeAdministrativeClosure(
        shopId,
        settledLoanId,
        actor: ownerUser,
        reason: 'Initial closure reason',
        idempotencyKey: 'idemp-closure-01',
      );

      expect(
        () => collateralDao.executeAdministrativeClosure(
          shopId,
          settledLoanId,
          actor: ownerUser,
          reason: 'Second closure attempt',
          idempotencyKey: 'idemp-closure-02',
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('already undergone administrative closure'),
        )),
      );
    });
  });

  group('Story 3.5: Dynamic Workflow Status Derivation (AD-3)', () {
    test('derives "Closed (Collateral Exception)" when loan is settled and closure record exists', () async {
      final item = createTestItem(
        id: 'item-11',
        loanId: settledLoanId,
        referenceId: 'ITEM-011',
        custodyStatus: CollateralCustodyStatus.exceptionHeld,
      );
      await collateralDao.createCollateralItem(item);

      await collateralDao.executeAdministrativeClosure(
        shopId,
        settledLoanId,
        actor: ownerUser,
        reason: 'Item held under legal dispute',
        idempotencyKey: 'idemp-dyn-01',
      );

      final domainLoan = Loan(
        id: settledLoanId,
        shopId: shopId,
        customerId: customerId,
        principalCents: 500000,
        balanceCents: 0,
        termPresetDays: 30,
        status: LoanStatus.settled,
        workflowStatus: LoanWorkflowStatus.disbursed,
        dueDate: DateTime.now().toUtc(),
        createdAt: DateTime.now().toUtc(),
        settledAt: DateTime.now().toUtc(),
      );

      final status = await collateralDao.deriveOverallWorkflowStatus(
        shopId,
        domainLoan,
      );
      expect(status, equals('Closed (Collateral Exception)'));
    });

    test('derives "Settled / Closed (All Collateral Returned)" when all items returned and no closure', () async {
      final item = createTestItem(
        id: 'item-12',
        loanId: settledLoanId,
        referenceId: 'ITEM-012',
        custodyStatus: CollateralCustodyStatus.returned,
      );
      await collateralDao.createCollateralItem(item);

      final domainLoan = Loan(
        id: settledLoanId,
        shopId: shopId,
        customerId: customerId,
        principalCents: 500000,
        balanceCents: 0,
        termPresetDays: 30,
        status: LoanStatus.settled,
        workflowStatus: LoanWorkflowStatus.disbursed,
        dueDate: DateTime.now().toUtc(),
        createdAt: DateTime.now().toUtc(),
        settledAt: DateTime.now().toUtc(),
      );

      final status = await collateralDao.deriveOverallWorkflowStatus(
        shopId,
        domainLoan,
      );
      expect(status, equals('Settled / Closed (All Collateral Returned)'));
    });

    test('derives "Settled (Pending Collateral Return)" when loan is settled but items pending handover', () async {
      final item = createTestItem(
        id: 'item-13',
        loanId: settledLoanId,
        referenceId: 'ITEM-013',
        custodyStatus: CollateralCustodyStatus.inCustody,
      );
      await collateralDao.createCollateralItem(item);

      final domainLoan = Loan(
        id: settledLoanId,
        shopId: shopId,
        customerId: customerId,
        principalCents: 500000,
        balanceCents: 0,
        termPresetDays: 30,
        status: LoanStatus.settled,
        workflowStatus: LoanWorkflowStatus.disbursed,
        dueDate: DateTime.now().toUtc(),
        createdAt: DateTime.now().toUtc(),
        settledAt: DateTime.now().toUtc(),
      );

      final status = await collateralDao.deriveOverallWorkflowStatus(
        shopId,
        domainLoan,
      );
      expect(status, equals('Settled (Pending Collateral Return)'));
    });
  });
}
