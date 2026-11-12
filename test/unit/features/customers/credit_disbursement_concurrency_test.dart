import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_dao.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';
import 'package:credit_system/features/customers/data/daos/credit_dao.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Regression coverage for the concurrency safety of the cash-disbursement
/// transition (Story 4.3, finding T4).
///
/// Two confirmations that use *different* valid idempotency keys but target
/// the same eligible agreement must not both succeed: the handover is a
/// single physical event and therefore produces a single authoritative
/// disbursement record and a single category-4 audit event.
///
/// The application-level read of the agreement happens before the write
/// transaction, so it cannot be relied on to serialise two writers. The
/// eligibility check has to be part of the write itself.
void main() {
  const shopId = '11111111-1111-1111-1111-111111111901';
  const customerId = 1;
  const managerId = '11111111-1111-1111-1111-111111111904';
  const itemA = 'coll-race-a';
  const itemB = 'coll-race-b';

  late AppDatabase db;
  late CreditDao creditDao;

  /// Two distinguishable disbursement instants, so the persisted record
  /// identifies which request actually performed the transition.
  final disbursedAtA = DateTime.utc(2026, 10, 15, 6);
  final disbursedAtB = DateTime.utc(2026, 10, 15, 7);

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);
    creditDao = CreditDao(db);

    final now = DateTime.now().toUtc();
    await db.into(db.shops).insert(ShopEntry(
      id: shopId,
      name: 'Race Shop',
      currencyCode: 'LKR',
      timezone: 'Asia/Colombo',
      createdAt: now,
      updatedAt: now,
    ));
    await db.into(db.appUsers).insert(AppUserEntry(
      id: managerId,
      shopId: shopId,
      username: 'race.manager',
      fullName: 'Race Manager',
      role: 'manager',
      isActive: true,
      sessionVersion: 1,
      createdAt: now,
      updatedAt: now,
    ));
    await db.into(db.customers).insert(CustomerEntry(
      id: customerId,
      shopId: shopId,
      fullName: 'Race Customer',
      nic: '851234567V',
      phone: '0771234567',
      address: '1 Main St',
      createdAt: now,
      updatedAt: now,
    ));
    for (final item in [
      (id: itemA, reference: 'COLL-RACE-A'),
      (id: itemB, reference: 'COLL-RACE-B'),
    ]) {
      await CollateralDao(db).createCollateralItem(CollateralItem(
        id: item.id,
        shopId: shopId,
        customerId: customerId,
        itemReferenceId: item.reference,
        category: CollateralItemCategory.gold,
        description: '22K gold necklace',
        conditionGrade: 'Like New',
        weightMilligrams: 5500,
        estimatedValueCents: 1500000,
      ));
    }
  });

  tearDown(() async {
    await db.close();
  });

  AppUser manager() => AppUser(
        id: managerId,
        shopId: shopId,
        username: 'race.manager',
        fullName: 'Race Manager',
        role: AppRole.manager,
        isActive: true,
      );

  Future<Credit> originate({
    required String idempotencyKey,
    required String itemId,
  }) async {
    return creditDao.createCreditAgreement(
      actor: manager(),
      idempotencyKey: idempotencyKey,
      customerId: customerId,
      principal: const Money(500000),
      dueDate: DateTime.utc(2026, 11, 13, 18, 30),
      createdAt: DateTime.now().toUtc(),
      collateralItemIds: [itemId],
      termPresetDays: 30,
    );
  }

  /// Runs a confirmation and captures either its value or its error.
  Future<Object> capture(Future<Credit> future) async {
    try {
      return await future;
    } catch (error) {
      return error;
    }
  }

  group('two concurrent confirmations of the same agreement', () {
    test('at most one performs the state transition', () async {
      final credit = await originate(
        idempotencyKey: 'race-origin',
        itemId: itemA,
      );

      // Both requests are started before either is awaited, so both read the
      // agreement while it is still awaiting disbursement. They use two
      // different, individually valid idempotency keys.
      final first = capture(creditDao.confirmCreditDisbursement(
        actor: manager(),
        idempotencyKey: 'race-key-a',
        creditId: credit.id,
        disbursedAt: disbursedAtA,
      ));
      final second = capture(creditDao.confirmCreditDisbursement(
        actor: manager(),
        idempotencyKey: 'race-key-b',
        creditId: credit.id,
        disbursedAt: disbursedAtB,
      ));

      final outcomes = await Future.wait([first, second]);

      final successes = outcomes.whereType<Credit>().toList();
      final failures = outcomes.whereType<Object>().where((o) => o is! Credit).toList();

      expect(successes, hasLength(1),
          reason: 'Exactly one request may perform the cash disbursement.');
      expect(failures, hasLength(1),
          reason: 'The request that loses the race must not report success.');

      // The loser receives an explicit non-success outcome that names the
      // reason, consistent with the existing "not awaiting disbursement"
      // convention.
      expect(failures.single, isA<CreditDisbursementStateException>());
      expect(
        failures.single.toString(),
        contains(credit.id),
        reason: 'The refusal must identify the agreement.',
      );
    });

    test('the persisted disbursement record has one authoritative result',
        () async {
      final credit = await originate(
        idempotencyKey: 'race-origin',
        itemId: itemA,
      );

      final first = capture(creditDao.confirmCreditDisbursement(
        actor: manager(),
        idempotencyKey: 'race-key-a',
        creditId: credit.id,
        disbursedAt: disbursedAtA,
      ));
      final second = capture(creditDao.confirmCreditDisbursement(
        actor: manager(),
        idempotencyKey: 'race-key-b',
        creditId: credit.id,
        disbursedAt: disbursedAtB,
      ));

      final outcomes = await Future.wait([first, second]);
      final winner = outcomes.whereType<Credit>().single;

      final persisted = await creditDao.getCreditById(shopId, credit.id);
      expect(persisted!.workflowStatus, equals(CreditWorkflowStatus.disbursed));
      expect(persisted.disbursedAt, equals(winner.disbursedAt),
          reason: 'The persisted record must be the one written by the request '
              'that actually performed the transition.');
      expect(persisted.disbursedByUserId, equals(managerId));
      expect(persisted.dueDate, equals(winner.dueDate));
      expect(persisted.principalCents, equals(500000));
      expect(persisted.balanceCents, equals(500000),
          reason: 'A disbursement is not a payment.');
    });

    test('no duplicate category-4 audit event is created for the handover',
        () async {
      final credit = await originate(
        idempotencyKey: 'race-origin',
        itemId: itemA,
      );

      final first = capture(creditDao.confirmCreditDisbursement(
        actor: manager(),
        idempotencyKey: 'race-key-a',
        creditId: credit.id,
        disbursedAt: disbursedAtA,
      ));
      final second = capture(creditDao.confirmCreditDisbursement(
        actor: manager(),
        idempotencyKey: 'race-key-b',
        creditId: credit.id,
        disbursedAt: disbursedAtB,
      ));
      await Future.wait([first, second]);

      final events = (await db.select(db.syncQueue).get())
          .where((r) =>
              r.actionType == CreditDao.confirmCreditDisbursementActionType &&
              r.entityId == credit.id)
          .toList();
      expect(events, hasLength(1),
          reason: 'One physical handover produces exactly one authoritative '
              'audit event.');
    });

    test('a genuine retry of the successful request still returns the '
        'disbursed agreement', () async {
      final credit = await originate(
        idempotencyKey: 'race-origin',
        itemId: itemA,
      );

      final first = capture(creditDao.confirmCreditDisbursement(
        actor: manager(),
        idempotencyKey: 'race-key-a',
        creditId: credit.id,
        disbursedAt: disbursedAtA,
      ));
      final second = capture(creditDao.confirmCreditDisbursement(
        actor: manager(),
        idempotencyKey: 'race-key-b',
        creditId: credit.id,
        disbursedAt: disbursedAtB,
      ));
      final outcomes = await Future.wait([first, second]);
      final winner = outcomes.whereType<Credit>().single;
      final winningKey = winner.disbursedAt == disbursedAtA
          ? 'race-key-a'
          : 'race-key-b';

      // Retrying the winning request with its own key is a genuine retry and
      // must return the same disbursed agreement without duplicating anything.
      final retry = await creditDao.confirmCreditDisbursement(
        actor: manager(),
        idempotencyKey: winningKey,
        creditId: credit.id,
        disbursedAt: winner.disbursedAt!,
      );
      expect(retry.id, equals(winner.id));
      expect(retry.workflowStatus, equals(CreditWorkflowStatus.disbursed));
      expect(retry.disbursedAt, equals(winner.disbursedAt));

      final events = (await db.select(db.syncQueue).get())
          .where((r) =>
              r.actionType == CreditDao.confirmCreditDisbursementActionType &&
              r.entityId == credit.id)
          .toList();
      expect(events, hasLength(1));
    });

    test('a request for a different agreement is unaffected', () async {
      final firstCredit = await originate(
        idempotencyKey: 'other-origin-a',
        itemId: itemA,
      );
      final secondCredit = await originate(
        idempotencyKey: 'other-origin-b',
        itemId: itemB,
      );

      final first = capture(creditDao.confirmCreditDisbursement(
        actor: manager(),
        idempotencyKey: 'other-key-a',
        creditId: firstCredit.id,
        disbursedAt: disbursedAtA,
      ));
      final second = capture(creditDao.confirmCreditDisbursement(
        actor: manager(),
        idempotencyKey: 'other-key-b',
        creditId: secondCredit.id,
        disbursedAt: disbursedAtB,
      ));

      final outcomes = await Future.wait([first, second]);
      expect(outcomes.whereType<Credit>(), hasLength(2),
          reason: 'Two different agreements may each be disbursed once.');

      final persistedFirst =
          await creditDao.getCreditById(shopId, firstCredit.id);
      final persistedSecond =
          await creditDao.getCreditById(shopId, secondCredit.id);
      expect(persistedFirst!.workflowStatus,
          equals(CreditWorkflowStatus.disbursed));
      expect(persistedSecond!.workflowStatus,
          equals(CreditWorkflowStatus.disbursed));

      final events = (await db.select(db.syncQueue).get())
          .where((r) => r.actionType == CreditDao.confirmCreditDisbursementActionType)
          .toList();
      expect(events, hasLength(2),
          reason: 'Each agreement has its own handover and its own event.');
    });
  });

  group('a failure after the conditional transition rolls the writes back',
      () {
    test('a failure injected after the credit write leaves no partial state '
        'and a retry succeeds', () async {
      final credit = await originate(
        idempotencyKey: 'rollback-origin',
        itemId: itemA,
      );

      // The failure is injected by an AFTER UPDATE trigger, so it fires only
      // once the credit row has actually been written. The trigger reports the
      // row state it observed, which proves the injection point: the failure
      // happens *after* the disbursement write, not before it.
      await db.customStatement('''
        CREATE TRIGGER "fail_credits_disbursement_after_write"
        AFTER UPDATE ON "credits"
        BEGIN
          SELECT RAISE(ABORT, 'after-write failure: workflow_status=' || NEW.workflow_status);
        END;
      ''');

      Object? failure;
      try {
        await creditDao.confirmCreditDisbursement(
          actor: manager(),
          idempotencyKey: 'rollback-key',
          creditId: credit.id,
          disbursedAt: disbursedAtA,
        );
      } catch (error) {
        failure = error;
      }

      expect(failure, isA<sqlite.SqliteException>());
      expect(
        failure.toString(),
        contains('workflow_status=disbursed'),
        reason: 'The failure must have been injected after the credit row was '
            'written, not before.',
      );

      // No partial credit update ...
      final persisted = await creditDao.getCreditById(shopId, credit.id);
      expect(persisted!.workflowStatus,
          equals(CreditWorkflowStatus.pendingDisbursement));
      expect(persisted.disbursedAt, isNull);
      expect(persisted.disbursedByUserId, isNull);
      expect(persisted.dueDate,
          equals(DateTime.utc(2026, 11, 13, 18, 30)));

      // ... no audit event ...
      final events = (await db.select(db.syncQueue).get())
          .where((r) =>
              r.actionType == CreditDao.confirmCreditDisbursementActionType)
          .toList();
      expect(events, isEmpty,
          reason: 'The audit record and the disbursement must commit or roll '
              'back together.');

      // ... and no stale idempotency claim.
      final claims = (await db.select(db.syncQueue).get())
          .where((r) => r.idempotencyKey == 'rollback-key')
          .toList();
      expect(claims, isEmpty,
          reason: 'The idempotency claim must be rolled back with the '
              'transaction.');

      // Once the injected failure is gone, a valid retry of the very same
      // request succeeds: no stale claim is in the way.
      await db.customStatement(
          'DROP TRIGGER "fail_credits_disbursement_after_write";');

      final retry = await creditDao.confirmCreditDisbursement(
        actor: manager(),
        idempotencyKey: 'rollback-key',
        creditId: credit.id,
        disbursedAt: disbursedAtA,
      );
      expect(retry.workflowStatus, equals(CreditWorkflowStatus.disbursed));
      expect(retry.disbursedByUserId, equals(managerId));

      final afterRetry = (await db.select(db.syncQueue).get())
          .where((r) =>
              r.actionType == CreditDao.confirmCreditDisbursementActionType)
          .toList();
      expect(afterRetry, hasLength(1),
          reason: 'The retry produces exactly one authoritative audit event.');
    });

    test('the original first-statement failure point never reaches the credit '
        'write, so it cannot prove a rollback after the write', () async {
      final credit = await originate(
        idempotencyKey: 'first-statement-origin',
        itemId: itemA,
      );

      // A marker table plus an AFTER UPDATE trigger that records every
      // disbursement write of the credit row.
      await db.customStatement(
          'CREATE TABLE "write_markers" ("id" TEXT NOT NULL PRIMARY KEY);');
      await db.customStatement('''
        CREATE TRIGGER "record_credits_update"
        AFTER UPDATE ON "credits"
        BEGIN
          INSERT INTO "write_markers" ("id") VALUES (NEW.id);
        END;
      ''');

      // The original failure point: the idempotency guard insert is the
      // FIRST statement of the transaction, so aborting it stops the
      // transaction before the credit row is ever written.
      await db.customStatement('''
        CREATE TRIGGER "fail_sync_queue_insert"
        BEFORE INSERT ON "sync_queue"
        BEGIN
          SELECT RAISE(ABORT, 'simulated audit persistence failure');
        END;
      ''');

      await expectLater(
        creditDao.confirmCreditDisbursement(
          actor: manager(),
          idempotencyKey: 'first-statement-key',
          creditId: credit.id,
          disbursedAt: disbursedAtA,
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );

      final markers = await db.customSelect('SELECT * FROM write_markers').get();
      expect(markers, isEmpty,
          reason: 'The credits UPDATE was never executed, so a failure at the '
              'first statement cannot demonstrate a rollback of a credit '
              'write.');

      final persisted = await creditDao.getCreditById(shopId, credit.id);
      expect(persisted!.workflowStatus,
          equals(CreditWorkflowStatus.pendingDisbursement));
    });

    test('without the transaction the same writes would persist a partial '
        'state, so the rollback guarantee is load-bearing', () async {
      final credit = await originate(
        idempotencyKey: 'bypass-origin',
        itemId: itemA,
      );

      // The same two writes the DAO performs, but NOT inside a transaction.
      await db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
        id: 'bypass-guard',
        shopId: shopId,
        idempotencyKey: 'bypass-key',
        entityType: CreditDao.creditEntityType,
        entityId: credit.id,
        actionType: CreditDao.confirmCreditDisbursementActionType,
        payloadJson: '{}',
        createdAt: DateTime.now().toUtc(),
      ));
      await (db.update(db.credits)..where((l) => l.id.equals(credit.id))).write(
        CreditsCompanion(
          workflowStatus: const Value('disbursed'),
          disbursedAt: Value(disbursedAtA),
          disbursedByUserId: const Value(managerId),
        ),
      );

      // Both writes persisted: without the transaction there is no rollback,
      // so the assertions of the test above genuinely depend on it.
      final persisted = await creditDao.getCreditById(shopId, credit.id);
      expect(persisted!.workflowStatus, equals(CreditWorkflowStatus.disbursed));
      expect(persisted.disbursedAt, equals(disbursedAtA));

      final claims = (await db.select(db.syncQueue).get())
          .where((r) => r.idempotencyKey == 'bypass-key')
          .toList();
      expect(claims, hasLength(1),
          reason: 'Outside a transaction the audit record survives even when '
              'the disbursement later fails.');
    });
  });
}

