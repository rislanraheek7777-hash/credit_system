import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

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

void main() {
  late AppDatabase db;
  late LoanDao loanDao;
  late CollateralDao collateralDao;

  const shopAlphaId = '11111111-1111-1111-1111-111111111401';
  const shopBetaId = '11111111-1111-1111-1111-111111111402';
  const customerAlphaId = 1;
  const customerBetaId = 2;
  const ownerId = '11111111-1111-1111-1111-111111111405';
  const cashierId = '11111111-1111-1111-1111-111111111406';
  const collateralItemId = 'coll-cancel-1';

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);
    loanDao = LoanDao(db);
    collateralDao = CollateralDao(db);

    final now = DateTime.now().toUtc();

    for (final shop in [
      (id: shopAlphaId, name: 'Alpha Jewellers'),
      (id: shopBetaId, name: 'Beta Jewellers'),
    ]) {
      await db.into(db.shops).insert(
        ShopEntry(
          id: shop.id,
          name: shop.name,
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    for (final user in [
      (id: ownerId, username: 'alpha.owner', role: AppRole.shopOwner),
      (id: cashierId, username: 'alpha.cashier', role: AppRole.cashier),
    ]) {
      await db.into(db.appUsers).insert(
        AppUserEntry(
          id: user.id,
          shopId: shopAlphaId,
          username: user.username,
          fullName: user.username,
          role: user.role.key,
          isActive: true,
          sessionVersion: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

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

    await collateralDao.createCollateralItem(CollateralItem(
      id: collateralItemId,
      shopId: shopAlphaId,
      customerId: customerAlphaId,
      itemReferenceId: 'COLL-CANCEL-001',
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

  AppUser owner() => AppUser(
        id: ownerId,
        shopId: shopAlphaId,
        username: 'alpha.owner',
        fullName: 'Alpha Owner',
        role: AppRole.shopOwner,
        isActive: true,
      );

  AppUser cashier() => AppUser(
        id: cashierId,
        shopId: shopAlphaId,
        username: 'alpha.cashier',
        fullName: 'Alpha Cashier',
        role: AppRole.cashier,
        isActive: true,
      );

  /// Creates a pending-disbursement agreement with a single pledged collateral
  /// item.
  Future<Loan> createPendingAgreement({
    String idempotencyKey = 'orig-key',
    int customerId = customerAlphaId,
    Money principal = const Money(500000),
    int? termPresetDays,
  }) async {
    return loanDao.createLoanAgreement(
      actor: owner(),
      idempotencyKey: idempotencyKey,
      customerId: customerId,
      principal: principal,
      dueDate: DateTime.now().toUtc().add(const Duration(days: 30)),
      createdAt: DateTime.now().toUtc(),
      collateralItemIds: const [collateralItemId],
      termPresetDays: termPresetDays,
    );
  }

  group('LoanDao.cancelLoanAgreement - successful cancellation (AC-4)', () {
    test('transitions a pending-disbursement loan to Cancelled / Cancelled',
        () async {
      final loan = await createPendingAgreement(
        idempotencyKey: 'cancel-success-1',
      );

      final cancelled = await loanDao.cancelLoanAgreement(
        actor: owner(),
        idempotencyKey: 'cancel-success-1-key',
        loanId: loan.id,
        cancelledAt: DateTime.now().toUtc(),
        cancellationReason: 'Customer abandoned the agreement',
      );

      expect(cancelled.status, equals(LoanStatus.cancelled));
      expect(cancelled.workflowStatus, equals(LoanWorkflowStatus.cancelled));
      expect(cancelled.isCancelled, isTrue);
      expect(cancelled.isDisbursed, isFalse);
      expect(cancelled.cancelledAt, isNotNull);
      expect(cancelled.cancellationReason,
          equals('Customer abandoned the agreement'));
      // Principal and balance are untouched (cancelled before disbursement).
      expect(cancelled.principalCents, equals(loan.principalCents));
      expect(cancelled.balanceCents, equals(loan.balanceCents));
      expect(cancelled.disbursedAt, isNull);
      expect(cancelled.disbursedByUserId, isNull);
    });

    test('persists the cancelled state and cancellation reason',
        () async {
      final loan = await createPendingAgreement(
        idempotencyKey: 'cancel-persist-1',
      );

      final cancelledAt = DateTime.utc(2026, 10, 15, 14, 30);
      await loanDao.cancelLoanAgreement(
        actor: owner(),
        idempotencyKey: 'cancel-persist-1-key',
        loanId: loan.id,
        cancelledAt: cancelledAt,
        cancellationReason: 'Customer abandoned the agreement',
      );

      final persisted = await loanDao.getLoanById(shopAlphaId, loan.id);
      expect(persisted, isNotNull);
      expect(persisted!.status, equals(LoanStatus.cancelled));
      expect(persisted.workflowStatus, equals(LoanWorkflowStatus.cancelled));
      expect(persisted.cancelledAt, equals(cancelledAt));
      expect(persisted.cancellationReason,
          equals('Customer abandoned the agreement'));
    });

    test('records a Category 2 audit/event entry with cancel_loan_agreement',
        () async {
      final loan = await createPendingAgreement(
        idempotencyKey: 'cancel-audit-1',
      );

      await loanDao.cancelLoanAgreement(
        actor: owner(),
        idempotencyKey: 'cancel-audit-1-key',
        loanId: loan.id,
        cancelledAt: DateTime.now().toUtc(),
        cancellationReason: 'Customer abandoned the agreement',
      );

      final rows = await db.select(db.syncQueue).get();
      final event = rows.firstWhere(
        (r) => r.actionType == LoanDao.cancelLoanAgreementActionType,
      );
      expect(event.entityType, equals('loan'));
      expect(event.entityId, equals(loan.id));
      expect(event.shopId, equals(shopAlphaId));
      expect(event.status, equals('pending_server_ack'));

      final payload = jsonDecode(event.payloadJson) as Map<String, dynamic>;
      expect(payload['auditCategory'],
          equals(LoanDao.loanOriginationAuditCategory));
      expect(payload['auditCategory'], equals(2),
          reason: 'PRD FR-31 category 2 is "Loan agreement origination and cancellation".');
      expect(payload['auditEvent'], equals('cancel_loan_agreement'));
      expect(payload['actorId'], equals(ownerId));
      expect(payload['loanId'], equals(loan.id));
      expect(payload['cancelledAt'], isNotNull);
      expect(payload['cancellationReason'],
          equals('Customer abandoned the agreement'));
      expect(payload['principalCents'], equals(loan.principalCents));
      expect(payload['balanceCents'], equals(loan.balanceCents));
    });

    test('collateral items remain in custody after cancellation', () async {
      final loan = await createPendingAgreement(
        idempotencyKey: 'cancel-collateral-1',
      );

      await loanDao.cancelLoanAgreement(
        actor: owner(),
        idempotencyKey: 'cancel-collateral-1-key',
        loanId: loan.id,
        cancelledAt: DateTime.now().toUtc(),
        cancellationReason: 'Customer abandoned the agreement',
      );

      final items = await collateralDao.getCollateralItemsByLoanId(
        shopAlphaId,
        loan.id,
      );
      expect(items.length, equals(1));
      expect(items.first.id, equals(collateralItemId));
      expect(items.first.loanId, equals(loan.id));
      // Custody status is unchanged by cancellation.
      expect(items.first.custodyStatus, isNotNull);
    });
  });

  group('LoanDao.cancelLoanAgreement - authorization', () {
    test('rejects a non-Shop Owner actor', () async {
      final loan = await createPendingAgreement(
        idempotencyKey: 'cancel-auth-1',
      );

      await expectLater(
        loanDao.cancelLoanAgreement(
          actor: cashier(),
          idempotencyKey: 'cancel-auth-1-key',
          loanId: loan.id,
          cancelledAt: DateTime.now().toUtc(),
          cancellationReason: 'Customer abandoned the agreement',
        ),
        throwsA(isA<PermissionDeniedException>()),
      );

      // The loan remains unchanged.
      final still = await loanDao.getLoanById(shopAlphaId, loan.id);
      expect(still!.status, equals(LoanStatus.active));
      expect(still.workflowStatus,
          equals(LoanWorkflowStatus.pendingDisbursement));
      expect(still.cancelledAt, isNull);
      expect(still.cancellationReason, isNull);

      // No cancellation journal entry was created.
      final cancellationEvents = (await db.select(db.syncQueue).get())
          .where((r) => r.actionType == LoanDao.cancelLoanAgreementActionType)
          .toList();
      expect(cancellationEvents, isEmpty);
    });

    test('rejects a deactivated actor', () async {
      final loan = await createPendingAgreement(
        idempotencyKey: 'cancel-auth-2',
      );

      await expectLater(
        loanDao.cancelLoanAgreement(
          actor: owner().copyWith(isActive: false),
          idempotencyKey: 'cancel-auth-2-key',
          loanId: loan.id,
          cancelledAt: DateTime.now().toUtc(),
          cancellationReason: 'Customer abandoned the agreement',
        ),
        throwsA(isA<PermissionDeniedException>()),
      );

      final still = await loanDao.getLoanById(shopAlphaId, loan.id);
      expect(still!.workflowStatus, equals(LoanWorkflowStatus.pendingDisbursement));
    });

    test('rejects a cross-shop Shop Owner', () async {
      final loan = await createPendingAgreement(
        idempotencyKey: 'cancel-auth-3',
      );

      final betaOwner = AppUser(
        id: 'beta-owner',
        shopId: shopBetaId,
        username: 'beta.owner',
        fullName: 'Beta Owner',
        role: AppRole.shopOwner,
        isActive: true,
      );

      await expectLater(
        loanDao.cancelLoanAgreement(
          actor: betaOwner,
          idempotencyKey: 'cancel-auth-3-key',
          loanId: loan.id,
          cancelledAt: DateTime.now().toUtc(),
          cancellationReason: 'Customer abandoned the agreement',
        ),
        throwsA(isA<StateError>()),
      );

      final still = await loanDao.getLoanById(shopAlphaId, loan.id);
      expect(still!.workflowStatus, equals(LoanWorkflowStatus.pendingDisbursement));
    });
  });

  group('LoanDao.cancelLoanAgreement - input validation', () {
    test('rejects a blank idempotency key', () async {
      final loan = await createPendingAgreement(
        idempotencyKey: 'cancel-input-1',
      );

      await expectLater(
        loanDao.cancelLoanAgreement(
          actor: owner(),
          idempotencyKey: '   ',
          loanId: loan.id,
          cancelledAt: DateTime.now().toUtc(),
          cancellationReason: 'Customer abandoned the agreement',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects an empty cancellation reason', () async {
      final loan = await createPendingAgreement(
        idempotencyKey: 'cancel-input-2',
      );

      await expectLater(
        loanDao.cancelLoanAgreement(
          actor: owner(),
          idempotencyKey: 'cancel-input-2-key',
          loanId: loan.id,
          cancelledAt: DateTime.now().toUtc(),
          cancellationReason: '',
        ),
        throwsA(isA<ArgumentError>()),
      );

      await expectLater(
        loanDao.cancelLoanAgreement(
          actor: owner(),
          idempotencyKey: 'cancel-input-2-key-2',
          loanId: loan.id,
          cancelledAt: DateTime.now().toUtc(),
          cancellationReason: '   ',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects cancellation for a loan that does not exist in the shop',
        () async {
      await expectLater(
        loanDao.cancelLoanAgreement(
          actor: owner(),
          idempotencyKey: 'cancel-input-3-key',
          loanId: 'non-existent-loan-id',
          cancelledAt: DateTime.now().toUtc(),
          cancellationReason: 'Customer abandoned the agreement',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('LoanDao.cancelLoanAgreement - state transition guards', () {
    test('rejects cancellation of a disbursed loan', () async {
      final loan = await createPendingAgreement(
        idempotencyKey: 'cancel-disbursed-1',
        termPresetDays: 30,
      );

      final disbursedAt = DateTime.utc(2026, 10, 15, 6);
      await loanDao.confirmLoanDisbursement(
        actor: owner(),
        idempotencyKey: 'cancel-disbursed-1-disburs',
        loanId: loan.id,
        disbursedAt: disbursedAt,
      );

      await expectLater(
        loanDao.cancelLoanAgreement(
          actor: owner(),
          idempotencyKey: 'cancel-disbursed-1-key',
          loanId: loan.id,
          cancelledAt: DateTime.now().toUtc(),
          cancellationReason: 'Customer abandoned the agreement',
        ),
        throwsA(isA<LoanCancellationStateException>()),
      );

      // The loan remains disbursed.
      final still = await loanDao.getLoanById(shopAlphaId, loan.id);
      expect(still!.status, equals(LoanStatus.active));
      expect(still.workflowStatus, equals(LoanWorkflowStatus.disbursed));
      expect(still.cancelledAt, isNull);
      expect(still.cancellationReason, isNull);

      // No cancellation journal entry was created.
      final cancellationEvents = (await db.select(db.syncQueue).get())
          .where((r) => r.actionType == LoanDao.cancelLoanAgreementActionType)
          .toList();
      expect(cancellationEvents, isEmpty);
    });

    test('rejects cancellation of an already-cancelled loan', () async {
      final loan = await createPendingAgreement(
        idempotencyKey: 'cancel-already-1',
      );

      await loanDao.cancelLoanAgreement(
        actor: owner(),
        idempotencyKey: 'cancel-already-1-first',
        loanId: loan.id,
        cancelledAt: DateTime.now().toUtc(),
        cancellationReason: 'Customer abandoned the agreement',
      );

      // A second cancellation with a different key is refused because the
      // agreement is no longer awaiting disbursement.
      await expectLater(
        loanDao.cancelLoanAgreement(
          actor: owner(),
          idempotencyKey: 'cancel-already-1-second',
          loanId: loan.id,
          cancelledAt: DateTime.now().toUtc(),
          cancellationReason: 'Second attempt',
        ),
        throwsA(isA<LoanCancellationStateException>()),
      );

      // The loan remains cancelled once.
      final still = await loanDao.getLoanById(shopAlphaId, loan.id);
      expect(still!.status, equals(LoanStatus.cancelled));
      expect(still.workflowStatus, equals(LoanWorkflowStatus.cancelled));
    });
  });

  group('LoanDao.cancelLoanAgreement - idempotency', () {
    test('a retry with the same idempotency key does not cancel twice',
        () async {
      final loan = await createPendingAgreement(
        idempotencyKey: 'cancel-idem-1',
      );

      final cancelledAt = DateTime.now().toUtc();
      final first = await loanDao.cancelLoanAgreement(
        actor: owner(),
        idempotencyKey: 'cancel-idem-1-key',
        loanId: loan.id,
        cancelledAt: cancelledAt,
        cancellationReason: 'Customer abandoned the agreement',
      );
      final second = await loanDao.cancelLoanAgreement(
        actor: owner(),
        idempotencyKey: 'cancel-idem-1-key',
        loanId: loan.id,
        cancelledAt: cancelledAt,
        cancellationReason: 'Customer abandoned the agreement',
      );

      // The retry returns the same cancelled loan.
      expect(second.id, equals(first.id));
      expect(second.status, equals(LoanStatus.cancelled));

      // Only one cancellation journal entry exists.
      final cancellationEvents = (await db.select(db.syncQueue).get())
          .where((r) => r.actionType == LoanDao.cancelLoanAgreementActionType)
          .toList();
      expect(cancellationEvents.length, equals(1));

      // Only one loan row exists.
      final loans = await db.select(db.loans).get();
      expect(loans.length, equals(1));
    });

    test('a retry with a different key on an already-cancelled loan is refused',
        () async {
      final loan = await createPendingAgreement(
        idempotencyKey: 'cancel-idem-2',
      );

      await loanDao.cancelLoanAgreement(
        actor: owner(),
        idempotencyKey: 'cancel-idem-2-first',
        loanId: loan.id,
        cancelledAt: DateTime.now().toUtc(),
        cancellationReason: 'Customer abandoned the agreement',
      );

      // A second cancellation with a different key is refused because the
      // agreement is no longer awaiting disbursement.
      await expectLater(
        loanDao.cancelLoanAgreement(
          actor: owner(),
          idempotencyKey: 'cancel-idem-2-second',
          loanId: loan.id,
          cancelledAt: DateTime.now().toUtc(),
          cancellationReason: 'Second attempt',
        ),
        throwsA(isA<LoanCancellationStateException>()),
      );
    });
  });

  group('LoanDao.cancelLoanAgreement - transaction atomicity', () {
    test('sync-queue entry and loan update commit together', () async {
      final loan = await createPendingAgreement(
        idempotencyKey: 'cancel-atomic-1',
      );

      await loanDao.cancelLoanAgreement(
        actor: owner(),
        idempotencyKey: 'cancel-atomic-1-key',
        loanId: loan.id,
        cancelledAt: DateTime.now().toUtc(),
        cancellationReason: 'Customer abandoned the agreement',
      );

      // Both the loan row and the sync-queue row exist.
      final persisted = await loanDao.getLoanById(shopAlphaId, loan.id);
      expect(persisted!.status, equals(LoanStatus.cancelled));

      final queueRows = await db.select(db.syncQueue).get();
      expect(queueRows, isNotEmpty);
      final cancellationRow = queueRows.firstWhere(
        (r) => r.actionType == LoanDao.cancelLoanAgreementActionType,
      );
      expect(cancellationRow.entityId, equals(loan.id));
      expect(cancellationRow.shopId, equals(shopAlphaId));
    });

    test('rolls back atomically when the audit event cannot be persisted',
        () async {
      final loan = await createPendingAgreement(
        idempotencyKey: 'cancel-atomic-fail-1',
      );

      // Install a trigger that aborts any insert into sync_queue.
      await db.customStatement('''
        CREATE TRIGGER "fail_cancel_sync_queue_insert"
        BEFORE INSERT ON "sync_queue"
        BEGIN
          SELECT RAISE(ABORT, 'simulated audit persistence failure');
        END;
      ''');

      await expectLater(
        loanDao.cancelLoanAgreement(
          actor: owner(),
          idempotencyKey: 'cancel-atomic-fail-1-key',
          loanId: loan.id,
          cancelledAt: DateTime.now().toUtc(),
          cancellationReason: 'Customer abandoned the agreement',
        ),
        throwsA(isA<Exception>()),
      );

      // The loan must not be cancelled.
      final still = await loanDao.getLoanById(shopAlphaId, loan.id);
      expect(still!.status, equals(LoanStatus.active));
      expect(still.workflowStatus, equals(LoanWorkflowStatus.pendingDisbursement));
      expect(still.cancelledAt, isNull);
      expect(still.cancellationReason, isNull);

      // No cancellation journal entry was created.
      final cancellationEvents = (await db.select(db.syncQueue).get())
          .where((r) => r.actionType == LoanDao.cancelLoanAgreementActionType)
          .toList();
      expect(cancellationEvents, isEmpty);
    });
  });
}
