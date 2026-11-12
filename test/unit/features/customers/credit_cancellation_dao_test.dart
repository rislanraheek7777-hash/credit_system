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
import 'package:credit_system/features/customers/data/daos/credit_dao.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';

void main() {
  late AppDatabase db;
  late CreditDao creditDao;
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
    creditDao = CreditDao(db);
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
  Future<Credit> createPendingAgreement({
    String idempotencyKey = 'orig-key',
    int customerId = customerAlphaId,
    Money principal = const Money(500000),
    int? termPresetDays,
  }) async {
    return creditDao.createCreditAgreement(
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

  group('CreditDao.cancelCreditAgreement - successful cancellation (AC-4)', () {
    test('transitions a pending-disbursement credit to Cancelled / Cancelled',
        () async {
      final credit = await createPendingAgreement(
        idempotencyKey: 'cancel-success-1',
      );

      final cancelled = await creditDao.cancelCreditAgreement(
        actor: owner(),
        idempotencyKey: 'cancel-success-1-key',
        creditId: credit.id,
        cancelledAt: DateTime.now().toUtc(),
        cancellationReason: 'Customer abandoned the agreement',
      );

      expect(cancelled.status, equals(CreditStatus.cancelled));
      expect(cancelled.workflowStatus, equals(CreditWorkflowStatus.cancelled));
      expect(cancelled.isCancelled, isTrue);
      expect(cancelled.isDisbursed, isFalse);
      expect(cancelled.cancelledAt, isNotNull);
      expect(cancelled.cancellationReason,
          equals('Customer abandoned the agreement'));
      // Principal and balance are untouched (cancelled before disbursement).
      expect(cancelled.principalCents, equals(credit.principalCents));
      expect(cancelled.balanceCents, equals(credit.balanceCents));
      expect(cancelled.disbursedAt, isNull);
      expect(cancelled.disbursedByUserId, isNull);
    });

    test('persists the cancelled state and cancellation reason',
        () async {
      final credit = await createPendingAgreement(
        idempotencyKey: 'cancel-persist-1',
      );

      final cancelledAt = DateTime.utc(2026, 10, 15, 14, 30);
      await creditDao.cancelCreditAgreement(
        actor: owner(),
        idempotencyKey: 'cancel-persist-1-key',
        creditId: credit.id,
        cancelledAt: cancelledAt,
        cancellationReason: 'Customer abandoned the agreement',
      );

      final persisted = await creditDao.getCreditById(shopAlphaId, credit.id);
      expect(persisted, isNotNull);
      expect(persisted!.status, equals(CreditStatus.cancelled));
      expect(persisted.workflowStatus, equals(CreditWorkflowStatus.cancelled));
      expect(persisted.cancelledAt, equals(cancelledAt));
      expect(persisted.cancellationReason,
          equals('Customer abandoned the agreement'));
    });

    test('records a Category 2 audit/event entry with cancel_credit_agreement',
        () async {
      final credit = await createPendingAgreement(
        idempotencyKey: 'cancel-audit-1',
      );

      await creditDao.cancelCreditAgreement(
        actor: owner(),
        idempotencyKey: 'cancel-audit-1-key',
        creditId: credit.id,
        cancelledAt: DateTime.now().toUtc(),
        cancellationReason: 'Customer abandoned the agreement',
      );

      final rows = await db.select(db.syncQueue).get();
      final event = rows.firstWhere(
        (r) => r.actionType == CreditDao.cancelCreditAgreementActionType,
      );
      expect(event.entityType, equals('credit'));
      expect(event.entityId, equals(credit.id));
      expect(event.shopId, equals(shopAlphaId));
      expect(event.status, equals('pending_server_ack'));

      final payload = jsonDecode(event.payloadJson) as Map<String, dynamic>;
      expect(payload['auditCategory'],
          equals(CreditDao.creditOriginationAuditCategory));
      expect(payload['auditCategory'], equals(2),
          reason: 'PRD FR-31 category 2 is "Credit agreement origination and cancellation".');
      expect(payload['auditEvent'], equals('cancel_credit_agreement'));
      expect(payload['actorId'], equals(ownerId));
      expect(payload['creditId'], equals(credit.id));
      expect(payload['cancelledAt'], isNotNull);
      expect(payload['cancellationReason'],
          equals('Customer abandoned the agreement'));
      expect(payload['principalCents'], equals(credit.principalCents));
      expect(payload['balanceCents'], equals(credit.balanceCents));
    });

    test('collateral items remain in custody after cancellation', () async {
      final credit = await createPendingAgreement(
        idempotencyKey: 'cancel-collateral-1',
      );

      await creditDao.cancelCreditAgreement(
        actor: owner(),
        idempotencyKey: 'cancel-collateral-1-key',
        creditId: credit.id,
        cancelledAt: DateTime.now().toUtc(),
        cancellationReason: 'Customer abandoned the agreement',
      );

      final items = await collateralDao.getCollateralItemsByCreditId(
        shopAlphaId,
        credit.id,
      );
      expect(items.length, equals(1));
      expect(items.first.id, equals(collateralItemId));
      expect(items.first.creditId, equals(credit.id));
      // Custody status is unchanged by cancellation.
      expect(items.first.custodyStatus, isNotNull);
    });
  });

  group('CreditDao.cancelCreditAgreement - authorization', () {
    test('rejects a non-Shop Owner actor', () async {
      final credit = await createPendingAgreement(
        idempotencyKey: 'cancel-auth-1',
      );

      await expectLater(
        creditDao.cancelCreditAgreement(
          actor: cashier(),
          idempotencyKey: 'cancel-auth-1-key',
          creditId: credit.id,
          cancelledAt: DateTime.now().toUtc(),
          cancellationReason: 'Customer abandoned the agreement',
        ),
        throwsA(isA<PermissionDeniedException>()),
      );

      // The credit remains unchanged.
      final still = await creditDao.getCreditById(shopAlphaId, credit.id);
      expect(still!.status, equals(CreditStatus.active));
      expect(still.workflowStatus,
          equals(CreditWorkflowStatus.pendingDisbursement));
      expect(still.cancelledAt, isNull);
      expect(still.cancellationReason, isNull);

      // No cancellation journal entry was created.
      final cancellationEvents = (await db.select(db.syncQueue).get())
          .where((r) => r.actionType == CreditDao.cancelCreditAgreementActionType)
          .toList();
      expect(cancellationEvents, isEmpty);
    });

    test('rejects a deactivated actor', () async {
      final credit = await createPendingAgreement(
        idempotencyKey: 'cancel-auth-2',
      );

      await expectLater(
        creditDao.cancelCreditAgreement(
          actor: owner().copyWith(isActive: false),
          idempotencyKey: 'cancel-auth-2-key',
          creditId: credit.id,
          cancelledAt: DateTime.now().toUtc(),
          cancellationReason: 'Customer abandoned the agreement',
        ),
        throwsA(isA<PermissionDeniedException>()),
      );

      final still = await creditDao.getCreditById(shopAlphaId, credit.id);
      expect(still!.workflowStatus, equals(CreditWorkflowStatus.pendingDisbursement));
    });

    test('rejects a cross-shop Shop Owner', () async {
      final credit = await createPendingAgreement(
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
        creditDao.cancelCreditAgreement(
          actor: betaOwner,
          idempotencyKey: 'cancel-auth-3-key',
          creditId: credit.id,
          cancelledAt: DateTime.now().toUtc(),
          cancellationReason: 'Customer abandoned the agreement',
        ),
        throwsA(isA<StateError>()),
      );

      final still = await creditDao.getCreditById(shopAlphaId, credit.id);
      expect(still!.workflowStatus, equals(CreditWorkflowStatus.pendingDisbursement));
    });
  });

  group('CreditDao.cancelCreditAgreement - input validation', () {
    test('rejects a blank idempotency key', () async {
      final credit = await createPendingAgreement(
        idempotencyKey: 'cancel-input-1',
      );

      await expectLater(
        creditDao.cancelCreditAgreement(
          actor: owner(),
          idempotencyKey: '   ',
          creditId: credit.id,
          cancelledAt: DateTime.now().toUtc(),
          cancellationReason: 'Customer abandoned the agreement',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects an empty cancellation reason', () async {
      final credit = await createPendingAgreement(
        idempotencyKey: 'cancel-input-2',
      );

      await expectLater(
        creditDao.cancelCreditAgreement(
          actor: owner(),
          idempotencyKey: 'cancel-input-2-key',
          creditId: credit.id,
          cancelledAt: DateTime.now().toUtc(),
          cancellationReason: '',
        ),
        throwsA(isA<ArgumentError>()),
      );

      await expectLater(
        creditDao.cancelCreditAgreement(
          actor: owner(),
          idempotencyKey: 'cancel-input-2-key-2',
          creditId: credit.id,
          cancelledAt: DateTime.now().toUtc(),
          cancellationReason: '   ',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects cancellation for a credit that does not exist in the shop',
        () async {
      await expectLater(
        creditDao.cancelCreditAgreement(
          actor: owner(),
          idempotencyKey: 'cancel-input-3-key',
          creditId: 'non-existent-credit-id',
          cancelledAt: DateTime.now().toUtc(),
          cancellationReason: 'Customer abandoned the agreement',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('CreditDao.cancelCreditAgreement - state transition guards', () {
    test('rejects cancellation of a disbursed credit', () async {
      final credit = await createPendingAgreement(
        idempotencyKey: 'cancel-disbursed-1',
        termPresetDays: 30,
      );

      final disbursedAt = DateTime.utc(2026, 10, 15, 6);
      await creditDao.confirmCreditDisbursement(
        actor: owner(),
        idempotencyKey: 'cancel-disbursed-1-disburs',
        creditId: credit.id,
        disbursedAt: disbursedAt,
      );

      await expectLater(
        creditDao.cancelCreditAgreement(
          actor: owner(),
          idempotencyKey: 'cancel-disbursed-1-key',
          creditId: credit.id,
          cancelledAt: DateTime.now().toUtc(),
          cancellationReason: 'Customer abandoned the agreement',
        ),
        throwsA(isA<CreditCancellationStateException>()),
      );

      // The credit remains disbursed.
      final still = await creditDao.getCreditById(shopAlphaId, credit.id);
      expect(still!.status, equals(CreditStatus.active));
      expect(still.workflowStatus, equals(CreditWorkflowStatus.disbursed));
      expect(still.cancelledAt, isNull);
      expect(still.cancellationReason, isNull);

      // No cancellation journal entry was created.
      final cancellationEvents = (await db.select(db.syncQueue).get())
          .where((r) => r.actionType == CreditDao.cancelCreditAgreementActionType)
          .toList();
      expect(cancellationEvents, isEmpty);
    });

    test('rejects cancellation of an already-cancelled credit', () async {
      final credit = await createPendingAgreement(
        idempotencyKey: 'cancel-already-1',
      );

      await creditDao.cancelCreditAgreement(
        actor: owner(),
        idempotencyKey: 'cancel-already-1-first',
        creditId: credit.id,
        cancelledAt: DateTime.now().toUtc(),
        cancellationReason: 'Customer abandoned the agreement',
      );

      // A second cancellation with a different key is refused because the
      // agreement is no longer awaiting disbursement.
      await expectLater(
        creditDao.cancelCreditAgreement(
          actor: owner(),
          idempotencyKey: 'cancel-already-1-second',
          creditId: credit.id,
          cancelledAt: DateTime.now().toUtc(),
          cancellationReason: 'Second attempt',
        ),
        throwsA(isA<CreditCancellationStateException>()),
      );

      // The credit remains cancelled once.
      final still = await creditDao.getCreditById(shopAlphaId, credit.id);
      expect(still!.status, equals(CreditStatus.cancelled));
      expect(still.workflowStatus, equals(CreditWorkflowStatus.cancelled));
    });
  });

  group('CreditDao.cancelCreditAgreement - idempotency', () {
    test('a retry with the same idempotency key does not cancel twice',
        () async {
      final credit = await createPendingAgreement(
        idempotencyKey: 'cancel-idem-1',
      );

      final cancelledAt = DateTime.now().toUtc();
      final first = await creditDao.cancelCreditAgreement(
        actor: owner(),
        idempotencyKey: 'cancel-idem-1-key',
        creditId: credit.id,
        cancelledAt: cancelledAt,
        cancellationReason: 'Customer abandoned the agreement',
      );
      final second = await creditDao.cancelCreditAgreement(
        actor: owner(),
        idempotencyKey: 'cancel-idem-1-key',
        creditId: credit.id,
        cancelledAt: cancelledAt,
        cancellationReason: 'Customer abandoned the agreement',
      );

      // The retry returns the same cancelled credit.
      expect(second.id, equals(first.id));
      expect(second.status, equals(CreditStatus.cancelled));

      // Only one cancellation journal entry exists.
      final cancellationEvents = (await db.select(db.syncQueue).get())
          .where((r) => r.actionType == CreditDao.cancelCreditAgreementActionType)
          .toList();
      expect(cancellationEvents.length, equals(1));

      // Only one credit row exists.
      final credits = await db.select(db.credits).get();
      expect(credits.length, equals(1));
    });

    test('a retry with a different key on an already-cancelled credit is refused',
        () async {
      final credit = await createPendingAgreement(
        idempotencyKey: 'cancel-idem-2',
      );

      await creditDao.cancelCreditAgreement(
        actor: owner(),
        idempotencyKey: 'cancel-idem-2-first',
        creditId: credit.id,
        cancelledAt: DateTime.now().toUtc(),
        cancellationReason: 'Customer abandoned the agreement',
      );

      // A second cancellation with a different key is refused because the
      // agreement is no longer awaiting disbursement.
      await expectLater(
        creditDao.cancelCreditAgreement(
          actor: owner(),
          idempotencyKey: 'cancel-idem-2-second',
          creditId: credit.id,
          cancelledAt: DateTime.now().toUtc(),
          cancellationReason: 'Second attempt',
        ),
        throwsA(isA<CreditCancellationStateException>()),
      );
    });
  });

  group('CreditDao.cancelCreditAgreement - transaction atomicity', () {
    test('sync-queue entry and credit update commit together', () async {
      final credit = await createPendingAgreement(
        idempotencyKey: 'cancel-atomic-1',
      );

      await creditDao.cancelCreditAgreement(
        actor: owner(),
        idempotencyKey: 'cancel-atomic-1-key',
        creditId: credit.id,
        cancelledAt: DateTime.now().toUtc(),
        cancellationReason: 'Customer abandoned the agreement',
      );

      // Both the credit row and the sync-queue row exist.
      final persisted = await creditDao.getCreditById(shopAlphaId, credit.id);
      expect(persisted!.status, equals(CreditStatus.cancelled));

      final queueRows = await db.select(db.syncQueue).get();
      expect(queueRows, isNotEmpty);
      final cancellationRow = queueRows.firstWhere(
        (r) => r.actionType == CreditDao.cancelCreditAgreementActionType,
      );
      expect(cancellationRow.entityId, equals(credit.id));
      expect(cancellationRow.shopId, equals(shopAlphaId));
    });

    test('rolls back atomically when the audit event cannot be persisted',
        () async {
      final credit = await createPendingAgreement(
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
        creditDao.cancelCreditAgreement(
          actor: owner(),
          idempotencyKey: 'cancel-atomic-fail-1-key',
          creditId: credit.id,
          cancelledAt: DateTime.now().toUtc(),
          cancellationReason: 'Customer abandoned the agreement',
        ),
        throwsA(isA<Exception>()),
      );

      // The credit must not be cancelled.
      final still = await creditDao.getCreditById(shopAlphaId, credit.id);
      expect(still!.status, equals(CreditStatus.active));
      expect(still.workflowStatus, equals(CreditWorkflowStatus.pendingDisbursement));
      expect(still.cancelledAt, isNull);
      expect(still.cancellationReason, isNull);

      // No cancellation journal entry was created.
      final cancellationEvents = (await db.select(db.syncQueue).get())
          .where((r) => r.actionType == CreditDao.cancelCreditAgreementActionType)
          .toList();
      expect(cancellationEvents, isEmpty);
    });
  });
}

