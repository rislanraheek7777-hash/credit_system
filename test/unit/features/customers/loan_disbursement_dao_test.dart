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
import 'package:credit_system/features/customers/domain/models/loan_term.dart';

void main() {
  late AppDatabase db;
  late LoanDao loanDao;

  const shopAlphaId = '11111111-1111-1111-1111-111111111301';
  const shopBetaId = '11111111-1111-1111-1111-111111111302';
  const customerAlphaId = 11;
  const customerBetaId = 12;
  const managerId = '11111111-1111-1111-1111-111111111305';
  const cashierId = '11111111-1111-1111-1111-111111111306';
  const itemId = 'coll-disb-1';

  /// 2026-10-15 06:00 UTC is 2026-10-15 11:30 in Asia/Colombo.
  final disbursedAt = DateTime.utc(2026, 10, 15, 6);

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);
    loanDao = LoanDao(db);

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
      (id: managerId, username: 'alpha.manager', role: 'manager'),
      (id: cashierId, username: 'alpha.cashier', role: 'cashier'),
    ]) {
      await db.into(db.appUsers).insert(
        AppUserEntry(
          id: user.id,
          shopId: shopAlphaId,
          username: user.username,
          fullName: user.username,
          role: user.role,
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
    await CollateralDao(db).createCollateralItem(CollateralItem(
      id: itemId,
      shopId: shopAlphaId,
      customerId: customerAlphaId,
      itemReferenceId: 'COLL-DISB-001',
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

  AppUser manager({bool isActive = true}) => AppUser(
        id: managerId,
        shopId: shopAlphaId,
        username: 'alpha.manager',
        fullName: 'Alpha Manager',
        role: AppRole.manager,
        isActive: isActive,
      );

  AppUser cashier() => AppUser(
        id: cashierId,
        shopId: shopAlphaId,
        username: 'alpha.cashier',
        fullName: 'Alpha Cashier',
        role: AppRole.cashier,
        isActive: true,
      );

  /// Creates an agreement awaiting disbursement with the given agreed term.
  Future<Loan> createPendingAgreement({
    int? termPresetDays,
    DateTime? customDueDate,
    String idempotencyKey = 'orig-key',
  }) async {
    final zone = ShopTimeZone.defaultTimeZone();
    final creation = zone.localDateOf(DateTime.now().toUtc());
    final preliminary = termPresetDays != null
        ? zone.instantAtStartOfDay(creation.addDays(termPresetDays))
        : (customDueDate ?? zone.instantAtStartOfDay(creation.addDays(30)));

    return loanDao.createLoanAgreement(
      actor: manager(),
      idempotencyKey: idempotencyKey,
      customerId: customerAlphaId,
      principal: const Money(500000),
      dueDate: preliminary,
      createdAt: DateTime.now().toUtc(),
      collateralItemIds: const [itemId],
      termPresetDays: termPresetDays,
      customDueDate: customDueDate,
    );
  }

  group('LoanDao.confirmLoanDisbursement - successful confirmation (AC-1)', () {
    test('transitions the agreement to Active / Disbursed', () async {
      final loan = await createPendingAgreement(termPresetDays: 30);

      final disbursed = await loanDao.confirmLoanDisbursement(
        actor: manager(),
        idempotencyKey: 'disb-1',
        loanId: loan.id,
        disbursedAt: disbursedAt,
      );

      expect(disbursed.status, equals(LoanStatus.active));
      expect(disbursed.workflowStatus, equals(LoanWorkflowStatus.disbursed));
      expect(disbursed.isDisbursed, isTrue);
      expect(disbursed.isPendingDisbursement, isFalse);
      expect(disbursed.isActionable, isTrue,
          reason: 'A disbursed loan becomes actionable for customer actions.');
    });

    test('records the disbursing staff member and the confirmed timestamp',
        () async {
      final loan = await createPendingAgreement(termPresetDays: 30);

      final disbursed = await loanDao.confirmLoanDisbursement(
        actor: manager(),
        idempotencyKey: 'disb-2',
        loanId: loan.id,
        disbursedAt: disbursedAt,
      );

      expect(disbursed.disbursedByUserId, equals(managerId));
      expect(disbursed.disbursedAt, isNotNull);
      expect(
        disbursed.disbursedAt!.toUtc(),
        equals(disbursedAt.toUtc()),
      );
      expect(disbursed.hasDisbursementRecord, isTrue);
    });

    test('records an audit/event entry with the PRD FR-31 category 4',
        () async {
      final loan = await createPendingAgreement(termPresetDays: 30);

      await loanDao.confirmLoanDisbursement(
        actor: manager(),
        idempotencyKey: 'disb-3',
        loanId: loan.id,
        disbursedAt: disbursedAt,
      );

      final rows = await db.select(db.syncQueue).get();
      final event = rows.firstWhere(
        (r) => r.actionType == LoanDao.confirmLoanDisbursementActionType,
      );
      expect(event.entityType, equals('loan'));
      expect(event.entityId, equals(loan.id));
      expect(event.shopId, equals(shopAlphaId));

      final payload = jsonDecode(event.payloadJson) as Map<String, dynamic>;
      expect(payload['auditCategory'],
          equals(LoanDao.loanDisbursementAuditCategory));
      expect(payload['auditCategory'], equals(4),
          reason: 'PRD FR-31 category 4 is "Confirmed cash disbursement".');
      expect(payload['auditEvent'], equals('confirmed_cash_disbursement'));
      expect(payload['actorId'], equals(managerId));
      expect(payload['loanId'], equals(loan.id));
      expect(payload['disbursedAt'], isNotNull);
      expect(payload['officialDueDate'], isNotNull);
    });

    test('does not create a second loan agreement and does not act as a '
        'payment', () async {
      final loan = await createPendingAgreement(termPresetDays: 30);

      final disbursed = await loanDao.confirmLoanDisbursement(
        actor: manager(),
        idempotencyKey: 'disb-4',
        loanId: loan.id,
        disbursedAt: disbursedAt,
      );

      // No second agreement was created.
      expect(await db.select(db.loans).get(), hasLength(1));

      // The agreed principal and the outstanding balance are untouched: a
      // disbursement is not a payment.
      expect(disbursed.principalCents, equals(500000));
      expect(disbursed.balanceCents, equals(500000));
    });
  });

  group('LoanDao.confirmLoanDisbursement - official due date (AC-2, AC-3)',
      () {
    final zone = ShopTimeZone.defaultTimeZone();

    String localDueDate(DateTime instant) =>
        zone.localDateOf(instant).isoDate;

    test('30-day preset disbursed 2026-10-15 gives 2026-11-14 (TC-1)',
        () async {
      final loan = await createPendingAgreement(termPresetDays: 30);
      final disbursed = await loanDao.confirmLoanDisbursement(
        actor: manager(),
        idempotencyKey: 'tc1',
        loanId: loan.id,
        disbursedAt: disbursedAt,
      );
      expect(localDueDate(disbursed.dueDate), equals('2026-11-14'));
    });

    test('60-day preset disbursed 2026-10-15 gives 2026-12-14 (TC-2)',
        () async {
      final loan = await createPendingAgreement(termPresetDays: 60);
      final disbursed = await loanDao.confirmLoanDisbursement(
        actor: manager(),
        idempotencyKey: 'tc2',
        loanId: loan.id,
        disbursedAt: disbursedAt,
      );
      expect(localDueDate(disbursed.dueDate), equals('2026-12-14'));
    });

    test('90-day preset disbursed 2026-10-15 gives 2027-01-13 (TC-3)',
        () async {
      final loan = await createPendingAgreement(termPresetDays: 90);
      final disbursed = await loanDao.confirmLoanDisbursement(
        actor: manager(),
        idempotencyKey: 'tc3',
        loanId: loan.id,
        disbursedAt: disbursedAt,
      );
      expect(localDueDate(disbursed.dueDate), equals('2027-01-13'));
    });

    test('a valid custom due date is confirmed and saved (TC-4)', () async {
      // Agreement created with a custom due date of 2026-11-20.
      final custom = zone.instantAtStartOfDay(
        const LocalCalendarDate(2026, 11, 20),
      );
      final loan = await createPendingAgreement(customDueDate: custom);

      // Disbursed 2026-10-12, which is before the custom date.
      final disbursed = await loanDao.confirmLoanDisbursement(
        actor: manager(),
        idempotencyKey: 'tc4',
        loanId: loan.id,
        disbursedAt: DateTime.utc(2026, 10, 12, 6),
      );

      expect(localDueDate(disbursed.dueDate), equals('2026-11-20'));
    });

    test('a custom due date equal to the disbursement date is blocked (TC-5)',
        () async {
      final custom = zone.instantAtStartOfDay(
        const LocalCalendarDate(2026, 10, 15),
      );
      final loan = await createPendingAgreement(customDueDate: custom);

      await expectLater(
        loanDao.confirmLoanDisbursement(
          actor: manager(),
          idempotencyKey: 'tc5a',
          loanId: loan.id,
          disbursedAt: disbursedAt,
        ),
        throwsA(isA<OfficialDueDateValidationException>()),
      );

      // The agreement is untouched.
      final still = await loanDao.getLoanById(shopAlphaId, loan.id);
      expect(still!.workflowStatus, equals(LoanWorkflowStatus.pendingDisbursement));
      expect(still.disbursedAt, isNull);
    });

    test('a custom due date before the disbursement date is blocked (TC-5)',
        () async {
      final custom = zone.instantAtStartOfDay(
        const LocalCalendarDate(2026, 10, 15),
      );
      final loan = await createPendingAgreement(customDueDate: custom);

      await expectLater(
        loanDao.confirmLoanDisbursement(
          actor: manager(),
          idempotencyKey: 'tc5b',
          loanId: loan.id,
          disbursedAt: DateTime.utc(2026, 10, 16, 6),
        ),
        throwsA(isA<OfficialDueDateValidationException>()),
      );
    });

    test('the official due date is finalised in the shop time zone, not UTC',
        () async {
      final loan = await createPendingAgreement(termPresetDays: 30);
      final disbursed = await loanDao.confirmLoanDisbursement(
        actor: manager(),
        idempotencyKey: 'tz-1',
        loanId: loan.id,
        disbursedAt: disbursedAt,
      );

      // 2026-10-15 06:00Z is 2026-10-15 11:30 in Colombo.
      expect(
        zone.localDateOf(disbursed.dueDate),
        equals(const LocalCalendarDate(2026, 11, 14)),
      );
      // The stored instant is local midnight of the due date.
      expect(
        zone.instantAtStartOfDay(const LocalCalendarDate(2026, 11, 14)),
        equals(disbursed.dueDate.toUtc()),
      );
    });
  });

  group('LoanDao.confirmLoanDisbursement - authorization (AC-1)', () {
    test('rejects an actor without the confirmLoanDisbursement permission',
        () async {
      final loan = await createPendingAgreement(termPresetDays: 30);

      await expectLater(
        loanDao.confirmLoanDisbursement(
          actor: cashier(),
          idempotencyKey: 'auth-1',
          loanId: loan.id,
          disbursedAt: disbursedAt,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );

      expect(await db.select(db.loans).get(), hasLength(1));
      final still = await loanDao.getLoanById(shopAlphaId, loan.id);
      expect(still!.workflowStatus, equals(LoanWorkflowStatus.pendingDisbursement));
      final disbursementEvents = (await db.select(db.syncQueue).get())
          .where((r) => r.actionType == LoanDao.confirmLoanDisbursementActionType)
          .toList();
      expect(disbursementEvents, isEmpty);
    });

    test('rejects a deactivated actor', () async {
      final loan = await createPendingAgreement(termPresetDays: 30);

      await expectLater(
        loanDao.confirmLoanDisbursement(
          actor: manager(isActive: false),
          idempotencyKey: 'auth-2',
          loanId: loan.id,
          disbursedAt: disbursedAt,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );

      final still = await loanDao.getLoanById(shopAlphaId, loan.id);
      expect(still!.workflowStatus, equals(LoanWorkflowStatus.pendingDisbursement));
    });

    test('rejects a loan that belongs to another shop', () async {
      final loan = await createPendingAgreement(termPresetDays: 30);

      final betaOwner = AppUser(
        id: 'beta-owner',
        shopId: shopBetaId,
        username: 'beta.owner',
        fullName: 'Beta Owner',
        role: AppRole.shopOwner,
        isActive: true,
      );

      await expectLater(
        loanDao.confirmLoanDisbursement(
          actor: betaOwner,
          idempotencyKey: 'auth-3',
          loanId: loan.id,
          disbursedAt: disbursedAt,
        ),
        throwsA(isA<StateError>()),
      );

      final still = await loanDao.getLoanById(shopAlphaId, loan.id);
      expect(still!.workflowStatus, equals(LoanWorkflowStatus.pendingDisbursement));
    });
  });

  group('LoanDao.confirmLoanDisbursement - duplicate and retry safety', () {
    test('refuses to disburse an already-disbursed loan', () async {
      final loan = await createPendingAgreement(termPresetDays: 30);

      await loanDao.confirmLoanDisbursement(
        actor: manager(),
        idempotencyKey: 'dup-1',
        loanId: loan.id,
        disbursedAt: disbursedAt,
      );

      // A second confirmation with a *different* key is refused because the
      // agreement is no longer awaiting disbursement.
      await expectLater(
        loanDao.confirmLoanDisbursement(
          actor: manager(),
          idempotencyKey: 'dup-2',
          loanId: loan.id,
          disbursedAt: disbursedAt,
        ),
        throwsA(isA<LoanDisbursementStateException>()),
      );

      expect(await db.select(db.loans).get(), hasLength(1));
    });

    test('a retry with the same idempotency key does not disburse twice',
        () async {
      final loan = await createPendingAgreement(termPresetDays: 30);

      final first = await loanDao.confirmLoanDisbursement(
        actor: manager(),
        idempotencyKey: 'retry-1',
        loanId: loan.id,
        disbursedAt: disbursedAt,
      );
      final second = await loanDao.confirmLoanDisbursement(
        actor: manager(),
        idempotencyKey: 'retry-1',
        loanId: loan.id,
        disbursedAt: disbursedAt,
      );

      expect(second.id, equals(first.id));
      expect(await db.select(db.loans).get(), hasLength(1));

      // Exactly one disbursement audit/event record exists.
      final events = (await db.select(db.syncQueue).get())
          .where((r) => r.actionType == LoanDao.confirmLoanDisbursementActionType)
          .toList();
      expect(events.length, equals(1));
    });

    test('rejects a blank idempotency key', () async {
      final loan = await createPendingAgreement(termPresetDays: 30);

      await expectLater(
        loanDao.confirmLoanDisbursement(
          actor: manager(),
          idempotencyKey: '   ',
          loanId: loan.id,
          disbursedAt: disbursedAt,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rolls back atomically when the audit/event record cannot be '
        'persisted', () async {
      final loan = await createPendingAgreement(termPresetDays: 30);

      // Simulate an audit-persistence failure on the local audit/sync queue.
      await db.customStatement('''
        CREATE TRIGGER "fail_sync_queue_insert"
        BEFORE INSERT ON "sync_queue"
        BEGIN
          SELECT RAISE(ABORT, 'simulated audit persistence failure');
        END;
      ''');

      await expectLater(
        loanDao.confirmLoanDisbursement(
          actor: manager(),
          idempotencyKey: 'rollback-1',
          loanId: loan.id,
          disbursedAt: disbursedAt,
        ),
        throwsA(anything),
      );

      // The disbursement must not survive a failed audit write.
      final still = await loanDao.getLoanById(shopAlphaId, loan.id);
      expect(still!.workflowStatus, equals(LoanWorkflowStatus.pendingDisbursement));
      expect(still.disbursedAt, isNull);
      expect(still.disbursedByUserId, isNull);

      final auditRows = (await db.select(db.syncQueue).get())
          .where((r) => r.actionType == LoanDao.confirmLoanDisbursementActionType)
          .toList();
      expect(auditRows, isEmpty,
          reason: 'The failed disbursement must not leave an audit/event row.');
    });
  });

  group('LoanDao.createLoanAgreement - agreed term recording (AC-2, AC-3)', () {
    test('persists the agreed preset term', () async {
      final loan = await createPendingAgreement(termPresetDays: 60);
      expect(loan.termPresetDays, equals(60));
      expect(loan.customDueDate, isNull);
    });

    test('persists the agreed custom due date', () async {
      final zone = ShopTimeZone.defaultTimeZone();
      final custom = zone.instantAtStartOfDay(
        const LocalCalendarDate(2026, 11, 20),
      );
      final loan = await createPendingAgreement(customDueDate: custom);
      expect(loan.termPresetDays, isNull);
      expect(loan.customDueDate, isNotNull);
      expect(
        zone.localDateOf(loan.customDueDate!),
        equals(const LocalCalendarDate(2026, 11, 20)),
      );
    });

    test('rejects supplying both a preset term and a custom due date',
        () async {
      final zone = ShopTimeZone.defaultTimeZone();
      await expectLater(
        loanDao.createLoanAgreement(
          actor: manager(),
          idempotencyKey: 'term-both',
          customerId: customerAlphaId,
          principal: const Money(500000),
          dueDate: DateTime.now().toUtc(),
          createdAt: DateTime.now().toUtc(),
          collateralItemIds: const [itemId],
          termPresetDays: 30,
          customDueDate:
              zone.instantAtStartOfDay(const LocalCalendarDate(2026, 11, 20)),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a term that is not an approved preset', () async {
      await expectLater(
        loanDao.createLoanAgreement(
          actor: manager(),
          idempotencyKey: 'term-bad',
          customerId: customerAlphaId,
          principal: const Money(500000),
          dueDate: DateTime.now().toUtc(),
          createdAt: DateTime.now().toUtc(),
          collateralItemIds: const [itemId],
          termPresetDays: 45,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
