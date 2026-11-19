import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/core/permissions/authorization_guard.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/correction_dao.dart';
import 'package:credit_system/features/customers/data/daos/payment_dao.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:uuid/uuid.dart';

const String shopId = 'corr-shop-1111-1111-1111-111111111101';
const String otherShopId = 'corr-shop-1111-1111-1111-111111111102';
const int customerId = 1;
const String ownerId = 'corr-owner-1111-1111-1111-111111111101';
const String managerId = 'corr-mgr-1111-1111-1111-111111111101';
const String cashierId = 'corr-cash-1111-1111-1111-111111111101';
const String creditId = 'corr-credit-1111-1111-1111-111111111101';
const String paymentId = 'corr-pay-1111-1111-1111-111111111101';

Future<void> seedData(AppDatabase db) async {
  final now = DateTime.utc(2026, 10, 20);

  await db.into(db.shops).insert(
    ShopEntry(
      id: shopId,
      name: 'Correction Test Shop',
      currencyCode: 'LKR',
      timezone: 'Asia/Colombo',
      createdAt: now,
      updatedAt: now,
    ),
  );
  await db.into(db.shops).insert(
    ShopEntry(
      id: otherShopId,
      name: 'Other Shop',
      currencyCode: 'LKR',
      timezone: 'Asia/Colombo',
      createdAt: now,
      updatedAt: now,
    ),
  );

  for (final user in [
    (id: ownerId, username: 'corr-owner', role: 'shop_owner'),
    (id: managerId, username: 'corr-mgr', role: 'manager'),
    (id: cashierId, username: 'corr-cash', role: 'cashier'),
  ]) {
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: user.id,
        shopId: shopId,
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
      id: customerId,
      shopId: shopId,
      fullName: 'Correction Customer',
      nic: '851234567V',
      phone: '0771234567',
      address: '1 Test St',
      createdAt: now,
      updatedAt: now,
    ),
  );

  // A disbursed credit with principal 500000 (Rs. 5,000.00) and balance 300000,
  // after a payment of 200000 was recorded.
  await db.into(db.credits).insert(
    CreditsCompanion.insert(
      id: creditId,
      shopId: shopId,
      customerId: customerId,
      principalCents: 500000,
      balanceCents: 300000,
      status: const Value('active'),
      workflowStatus: const Value('disbursed'),
      termPresetDays: const Value(30),
      dueDate: DateTime.utc(2026, 11, 20),
      disbursedAt: Value(DateTime.utc(2026, 10, 21)),
      disbursedByUserId: Value(ownerId),
      createdAt: now,
      correctionPending: const Value(false),
    ),
  );

  // The original (erroneous) payment of 200000.
  await db.into(db.payments).insert(
    PaymentsCompanion.insert(
      id: paymentId,
      shopId: shopId,
      creditId: creditId,
      receiptNumber: 'RCP-CORR-001',
      amountCents: 200000,
      preBalanceCents: 500000,
      postBalanceCents: 300000,
      paymentType: 'partial',
      recordedAt: DateTime.utc(2026, 10, 21),
      recordedByUserId: cashierId,
      customerId: customerId,
      customerName: 'Correction Customer',
      customerNic: '851234567V',
      shopName: 'Correction Test Shop',
      idempotencyKey: 'idemp-orig-pay',
    ),
  );
}

AppUser owner({bool isActive = true}) => AppUser(
      id: ownerId,
      shopId: shopId,
      username: 'corr-owner',
      fullName: 'Correction Owner',
      role: AppRole.shopOwner,
      isActive: isActive,
    );

AppUser manager({bool isActive = true}) => AppUser(
      id: managerId,
      shopId: shopId,
      username: 'corr-mgr',
      fullName: 'Correction Manager',
      role: AppRole.manager,
      isActive: isActive,
    );

AppUser cashier({bool isActive = true}) => AppUser(
      id: cashierId,
      shopId: shopId,
      username: 'corr-cash',
      fullName: 'Correction Cashier',
      role: AppRole.cashier,
      isActive: isActive,
    );

Future<Credit> currentCredit(AppDatabase db) async {
  final entry = await (db.select(db.credits)
        ..where((l) => l.id.equals(creditId) & l.shopId.equals(shopId)))
      .getSingle();
  return Credit(
    id: entry.id,
    shopId: entry.shopId,
    customerId: entry.customerId,
    principalCents: entry.principalCents,
    balanceCents: entry.balanceCents,
    status: CreditStatus.fromValue(entry.status),
    workflowStatus: CreditWorkflowStatus.fromValue(entry.workflowStatus),
    dueDate: entry.dueDate,
    createdAt: entry.createdAt,
    settledAt: entry.settledAt,
    termPresetDays: entry.termPresetDays,
    customDueDate: entry.customDueDate,
    disbursedAt: entry.disbursedAt,
    disbursedByUserId: entry.disbursedByUserId,
    cancelledAt: entry.cancelledAt,
    cancellationReason: entry.cancellationReason,
    correctionPending: entry.correctionPending,
  );
}

Future<List<QueryRow>> currentLedgerEntries(AppDatabase db) async {
  return db.customSelect(
    'SELECT entry_type, amount_cents, pre_balance_cents, post_balance_cents, reason, credit_id, correction_id, original_payment_id FROM credit_ledger_entries WHERE shop_id = ?',
    variables: [Variable<String>(shopId)],
  ).get();
}

void main() {
  late AppDatabase db;
  late CorrectionDao correctionDao;
  late PaymentDao paymentDao;

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);
    correctionDao = CorrectionDao(db);
    paymentDao = PaymentDao(db);
    await seedData(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('CorrectionDao - requestCorrection', () {
    test('manager with requestCorrections can request a correction', () async {
      final correction = await correctionDao.requestCorrection(
        actor: manager(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        originalPaymentId: paymentId,
        amount: Money.fromCents(200000),
        reason: 'Typographical error; entered 35000 instead of 3500.',
        requestedAt: DateTime.utc(2026, 10, 22),
      );

      expect(correction.status, equals(CreditCorrectionStatus.pendingApproval));
      expect(correction.correctionAmountCents, equals(200000));
      expect(correction.reason, contains('Typographical error'));
      expect(correction.isPending, isTrue);

      // The correction lock is active on the credit.
      final credit = await currentCredit(db);
      expect(credit.correctionPending, isTrue);
    });

    test('cashier without requestCorrections cannot request a correction', () async {
      expect(
        () => correctionDao.requestCorrection(
          actor: cashier(),
          idempotencyKey: const Uuid().v4(),
          creditId: creditId,
          originalPaymentId: paymentId,
          amount: Money.fromCents(1000),
          reason: 'Some reason.',
          requestedAt: DateTime.utc(2026, 10, 22),
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('request requires a mandatory non-empty reason', () async {
      expect(
        () => correctionDao.requestCorrection(
          actor: manager(),
          idempotencyKey: const Uuid().v4(),
          creditId: creditId,
          originalPaymentId: paymentId,
          amount: Money.fromCents(1000),
          reason: '   ',
          requestedAt: DateTime.utc(2026, 10, 22),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('request requires a positive amount', () async {
      expect(
        () => correctionDao.requestCorrection(
          actor: manager(),
          idempotencyKey: const Uuid().v4(),
          creditId: creditId,
          originalPaymentId: paymentId,
          amount: Money.fromCents(0),
          reason: 'Some reason.',
          requestedAt: DateTime.utc(2026, 10, 22),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('request on a credit in another shop is rejected', () async {
      expect(
        () => correctionDao.requestCorrection(
          actor: manager(),
          idempotencyKey: const Uuid().v4(),
          creditId: creditId,
          originalPaymentId: paymentId,
          amount: Money.fromCents(1000),
          reason: 'Some reason.',
          requestedAt: DateTime.utc(2026, 10, 22),
        ).then((_) async {
          // Use a manager from the other shop by creating a cross-shop actor.
          final otherActor = AppUser(
            id: 'corr-other-mgr',
            shopId: otherShopId,
            username: 'corr-other',
            fullName: 'Other Manager',
            role: AppRole.manager,
            isActive: true,
          );
          return correctionDao.requestCorrection(
            actor: otherActor,
            idempotencyKey: const Uuid().v4(),
            creditId: creditId,
            originalPaymentId: paymentId,
            amount: Money.fromCents(1000),
            reason: 'Cross-shop attempt.',
            requestedAt: DateTime.utc(2026, 10, 22),
          );
        }),
        throwsA(isA<StateError>()),
      );
    });

    test('a second correction cannot be requested while one is pending', () async {
      await correctionDao.requestCorrection(
        actor: manager(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        originalPaymentId: paymentId,
        amount: Money.fromCents(1000),
        reason: 'First request.',
        requestedAt: DateTime.utc(2026, 10, 22),
      );

      expect(
        () => correctionDao.requestCorrection(
          actor: manager(),
          idempotencyKey: const Uuid().v4(),
          creditId: creditId,
          originalPaymentId: paymentId,
          amount: Money.fromCents(2000),
          reason: 'Second request.',
          requestedAt: DateTime.utc(2026, 10, 22),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('idempotent retry returns the same correction without duplicating', () async {
      final key = const Uuid().v4();
      final first = await correctionDao.requestCorrection(
        actor: manager(),
        idempotencyKey: key,
        creditId: creditId,
        originalPaymentId: paymentId,
        amount: Money.fromCents(1000),
        reason: 'Idempotency test.',
        requestedAt: DateTime.utc(2026, 10, 22),
      );

      final second = await correctionDao.requestCorrection(
        actor: manager(),
        idempotencyKey: key,
        creditId: creditId,
        originalPaymentId: paymentId,
        amount: Money.fromCents(999999),
        reason: 'Different payload, same key.',
        requestedAt: DateTime.utc(2026, 10, 22),
      );

      expect(second.id, equals(first.id));
      expect(second.reason, equals('Idempotency test.'));
      final corrections = await correctionDao.getCorrectionsByCredit(shopId, creditId);
      expect(corrections.length, equals(1));
    });
  });

  group('CorrectionDao - approveCorrection (Shop Owner only)', () {
    test('owner can approve a pending correction', () async {
      await correctionDao.requestCorrection(
        actor: manager(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        originalPaymentId: paymentId,
        amount: Money.fromCents(200000),
        reason: 'Typographical error; entered 35000 instead of 3500.',
        requestedAt: DateTime.utc(2026, 10, 22),
      );

      final correction = await correctionDao.approveCorrection(
        actor: owner(),
        idempotencyKey: const Uuid().v4(),
        correctionId: (await correctionDao.getCorrectionsByCredit(shopId, creditId)).first.id,
        reviewedAt: DateTime.utc(2026, 10, 23),
      );

      expect(correction.status, equals(CreditCorrectionStatus.approved));
      expect(correction.isApproved, isTrue);
      expect(correction.reviewedByUserId, equals(ownerId));
      expect(correction.resultingBalanceCents, equals(500000)); // 300000 + 200000

      // The correction lock is lifted.
      final credit = await currentCredit(db);
      expect(credit.correctionPending, isFalse);
      expect(credit.balanceCents, equals(500000));

      // An immutable compensating debit ledger entry was posted:
      // balance increased by the full reversed amount (300000 + 200000 = 500000).
      final entries = await currentLedgerEntries(db);
      expect(entries, hasLength(1));
      expect(entries.first.read<String>('entry_type'), equals('compensating_debit'));
      expect(entries.first.read<int>('amount_cents'), equals(200000));
      expect(entries.first.read<int>('pre_balance_cents'), equals(300000));
      expect(entries.first.read<int>('post_balance_cents'), equals(500000));
      expect(entries.first.read<String>('credit_id'), equals(creditId));
      expect(entries.first.read<String?>('original_payment_id'), equals(paymentId));
      expect(entries.first.read<String?>('correction_id'), equals(correction.id));
      expect(entries.first.read<String>('reason'), contains('Typographical error'));
    });

    test('non-owner (manager) cannot approve a correction', () async {
      await correctionDao.requestCorrection(
        actor: manager(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        originalPaymentId: paymentId,
        amount: Money.fromCents(1000),
        reason: 'Some reason.',
        requestedAt: DateTime.utc(2026, 10, 22),
      );
      final correctionId =
          (await correctionDao.getCorrectionsByCredit(shopId, creditId)).first.id;

      expect(
        () => correctionDao.approveCorrection(
          actor: manager(),
          idempotencyKey: const Uuid().v4(),
          correctionId: correctionId,
          reviewedAt: DateTime.utc(2026, 10, 23),
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('a correction cannot be approved twice', () async {
      await correctionDao.requestCorrection(
        actor: manager(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        originalPaymentId: paymentId,
        amount: Money.fromCents(1000),
        reason: 'Some reason.',
        requestedAt: DateTime.utc(2026, 10, 22),
      );
      final correctionId =
          (await correctionDao.getCorrectionsByCredit(shopId, creditId)).first.id;

      await correctionDao.approveCorrection(
        actor: owner(),
        idempotencyKey: const Uuid().v4(),
        correctionId: correctionId,
        reviewedAt: DateTime.utc(2026, 10, 23),
      );

      // The balance was already adjusted once; a second approval must not
      // adjust it again.
      expect(
        () => correctionDao.approveCorrection(
          actor: owner(),
          idempotencyKey: const Uuid().v4(),
          correctionId: correctionId,
          reviewedAt: DateTime.utc(2026, 10, 23),
        ),
        throwsA(isA<StateError>()),
      );

      final credit = await currentCredit(db);
      expect(credit.balanceCents, equals(301000)); // adjusted exactly once
      expect(credit.correctionPending, isFalse);
    });

    test('approving a correction in another shop is rejected', () async {
      await correctionDao.requestCorrection(
        actor: manager(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        originalPaymentId: paymentId,
        amount: Money.fromCents(1000),
        reason: 'Some reason.',
        requestedAt: DateTime.utc(2026, 10, 22),
      );
      final correctionId =
          (await correctionDao.getCorrectionsByCredit(shopId, creditId)).first.id;

      final otherOwner = AppUser(
        id: 'corr-other-owner',
        shopId: otherShopId,
        username: 'corr-other-owner',
        fullName: 'Other Owner',
        role: AppRole.shopOwner,
        isActive: true,
      );

      expect(
        () => correctionDao.approveCorrection(
          actor: otherOwner,
          idempotencyKey: const Uuid().v4(),
          correctionId: correctionId,
          reviewedAt: DateTime.utc(2026, 10, 23),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('CorrectionDao - rejectCorrection (Shop Owner only)', () {
    test('owner can reject a pending correction; balance unchanged, lock lifted', () async {
      await correctionDao.requestCorrection(
        actor: manager(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        originalPaymentId: paymentId,
        amount: Money.fromCents(200000),
        reason: 'Invalid request.',
        requestedAt: DateTime.utc(2026, 10, 22),
      );
      final correctionId =
          (await correctionDao.getCorrectionsByCredit(shopId, creditId)).first.id;
      final balanceBefore = (await currentCredit(db)).balanceCents;

      final correction = await correctionDao.rejectCorrection(
        actor: owner(),
        idempotencyKey: const Uuid().v4(),
        correctionId: correctionId,
        rejectionReason: 'Not a genuine error.',
        reviewedAt: DateTime.utc(2026, 10, 23),
      );

      expect(correction.status, equals(CreditCorrectionStatus.rejected));
      expect(correction.isRejected, isTrue);
      expect(correction.rejectionReason, equals('Not a genuine error.'));
      expect(correction.reviewedByUserId, equals(ownerId));

      // Rejection leaves the balance unchanged.
      final credit = await currentCredit(db);
      expect(credit.balanceCents, equals(balanceBefore));
      // The lock is lifted.
      expect(credit.correctionPending, isFalse);
    });

    test('rejection creates no ledger entry', () async {
      await correctionDao.requestCorrection(
        actor: manager(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        originalPaymentId: paymentId,
        amount: Money.fromCents(200000),
        reason: 'Invalid request.',
        requestedAt: DateTime.utc(2026, 10, 22),
      );
      final correctionId =
          (await correctionDao.getCorrectionsByCredit(shopId, creditId)).first.id;

      await correctionDao.rejectCorrection(
        actor: owner(),
        idempotencyKey: const Uuid().v4(),
        correctionId: correctionId,
        rejectionReason: 'Not a genuine error.',
        reviewedAt: DateTime.utc(2026, 10, 23),
      );

      // Rejection posts no compensating ledger entry.
      final entries = await currentLedgerEntries(db);
      expect(entries, isEmpty);
    });

    test('reject requires a mandatory reason', () async {
      await correctionDao.requestCorrection(
        actor: manager(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        originalPaymentId: paymentId,
        amount: Money.fromCents(1000),
        reason: 'Some reason.',
        requestedAt: DateTime.utc(2026, 10, 22),
      );
      final correctionId =
          (await correctionDao.getCorrectionsByCredit(shopId, creditId)).first.id;

      expect(
        () => correctionDao.rejectCorrection(
          actor: owner(),
          idempotencyKey: const Uuid().v4(),
          correctionId: correctionId,
          rejectionReason: '   ',
          reviewedAt: DateTime.utc(2026, 10, 23),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('non-owner cannot reject a correction', () async {
      await correctionDao.requestCorrection(
        actor: manager(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        originalPaymentId: paymentId,
        amount: Money.fromCents(1000),
        reason: 'Some reason.',
        requestedAt: DateTime.utc(2026, 10, 22),
      );
      final correctionId =
          (await correctionDao.getCorrectionsByCredit(shopId, creditId)).first.id;

      expect(
        () => correctionDao.rejectCorrection(
          actor: manager(),
          idempotencyKey: const Uuid().v4(),
          correctionId: correctionId,
          rejectionReason: 'Not allowed.',
          reviewedAt: DateTime.utc(2026, 10, 23),
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });
  });

  group('CorrectionDao - correction lock blocks payments', () {
    test('payment is blocked while a correction is pending', () async {
      await correctionDao.requestCorrection(
        actor: manager(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        originalPaymentId: paymentId,
        amount: Money.fromCents(1000),
        reason: 'Pending correction.',
        requestedAt: DateTime.utc(2026, 10, 22),
      );

      expect(
        () => paymentDao.recordPayment(
          actor: cashier(),
          idempotencyKey: const Uuid().v4(),
          creditId: creditId,
          amount: Money.fromCents(5000),
          recordedAt: DateTime.utc(2026, 10, 23),
        ),
        throwsA(isA<CreditCorrectionPendingException>()),
      );

      // The credit balance is unchanged by the blocked payment attempt.
      final credit = await currentCredit(db);
      expect(credit.balanceCents, equals(300000));
    });

    test('payment is allowed once the correction is rejected (lock lifted)', () async {
      await correctionDao.requestCorrection(
        actor: manager(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        originalPaymentId: paymentId,
        amount: Money.fromCents(1000),
        reason: 'Pending correction.',
        requestedAt: DateTime.utc(2026, 10, 22),
      );
      final correctionId =
          (await correctionDao.getCorrectionsByCredit(shopId, creditId)).first.id;
      await correctionDao.rejectCorrection(
        actor: owner(),
        idempotencyKey: const Uuid().v4(),
        correctionId: correctionId,
        rejectionReason: 'Not allowed.',
        reviewedAt: DateTime.utc(2026, 10, 23),
      );

      // After rejection the lock is lifted and a payment can be recorded.
      final receipt = await paymentDao.recordPayment(
        actor: cashier(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        amount: Money.fromCents(5000),
        recordedAt: DateTime.utc(2026, 10, 23),
      );
      expect(receipt.amountCents, equals(5000));

      final credit = await currentCredit(db);
      expect(credit.correctionPending, isFalse);
      expect(credit.balanceCents, equals(295000));
    });
  });

  group('CorrectionDao - queries', () {
    test('getCorrectionsByStatus filters by status within the shop', () async {
      await correctionDao.requestCorrection(
        actor: manager(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        originalPaymentId: paymentId,
        amount: Money.fromCents(1000),
        reason: 'Pending one.',
        requestedAt: DateTime.utc(2026, 10, 22),
      );
      final pending = await correctionDao.getCorrectionsByStatus(
        shopId, 'pending_approval',
      );
      expect(pending.length, equals(1));
    });

    test('corrections are strictly shop-scoped', () async {
      await correctionDao.requestCorrection(
        actor: manager(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        originalPaymentId: paymentId,
        amount: Money.fromCents(1000),
        reason: 'Shop-scoped.',
        requestedAt: DateTime.utc(2026, 10, 22),
      );

      final otherShopCorrections =
          await correctionDao.getCorrectionsByCredit(otherShopId, creditId);
      expect(otherShopCorrections.isEmpty, isTrue);
    });
  });

  group('CorrectionDao - adjustBalance (Shop Owner only)', () {
    test('owner can perform a valid debit adjustment', () async {
      final entry = await correctionDao.adjustBalance(
        actor: owner(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        amount: Money.fromCents(50000),
        adjustmentType: CreditLedgerEntryType.adjustmentDebit,
        reason: 'Dispute settlement concession.',
        recordedAt: DateTime.utc(2026, 10, 23),
      );

      expect(entry.entryType, equals(CreditLedgerEntryType.adjustmentDebit));
      expect(entry.amountCents, equals(50000));
      expect(entry.preBalanceCents, equals(300000));
      expect(entry.postBalanceCents, equals(350000));
      expect(entry.reason, equals('Dispute settlement concession.'));
      expect(entry.recordedByUserId, equals(ownerId));
      expect(entry.isCompensatingDebit, isFalse);

      final credit = await currentCredit(db);
      expect(credit.balanceCents, equals(350000));

      final entries = await currentLedgerEntries(db);
      expect(entries, hasLength(1));
      expect(entries.first.read<String>('entry_type'), equals('adjustment_debit'));
      expect(entries.first.read<int>('amount_cents'), equals(50000));
      expect(entries.first.read<int>('post_balance_cents'), equals(350000));
    });

    test('owner can perform a valid credit adjustment', () async {
      final entry = await correctionDao.adjustBalance(
        actor: owner(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        amount: Money.fromCents(50000),
        adjustmentType: CreditLedgerEntryType.adjustmentCredit,
        reason: 'Rounding reconciliation.',
        recordedAt: DateTime.utc(2026, 10, 23),
      );

      expect(entry.entryType, equals(CreditLedgerEntryType.adjustmentCredit));
      expect(entry.preBalanceCents, equals(300000));
      expect(entry.postBalanceCents, equals(250000));

      final credit = await currentCredit(db);
      expect(credit.balanceCents, equals(250000));
    });

    test('a full-balance credit adjustment settles the credit atomically', () async {
      final entry = await correctionDao.adjustBalance(
        actor: owner(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        amount: Money.fromCents(300000),
        adjustmentType: CreditLedgerEntryType.adjustmentCredit,
        reason: 'Insolvent customer; forgive the whole balance.',
        recordedAt: DateTime.utc(2026, 10, 23),
      );

      expect(entry.postBalanceCents, equals(0));

      final credit = await currentCredit(db);
      expect(credit.balanceCents, equals(0));
      expect(credit.status, equals(CreditStatus.settled));
      expect(credit.settledAt, isNotNull);
      expect(credit.workflowStatus, equals(CreditWorkflowStatus.disbursed));
    });

    test('a debit adjustment raises the balance and keeps the credit active', () async {
      final entry = await correctionDao.adjustBalance(
        actor: owner(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        amount: Money.fromCents(150000),
        adjustmentType: CreditLedgerEntryType.adjustmentDebit,
        reason: 'Undercharged at disbursement.',
        recordedAt: DateTime.utc(2026, 10, 23),
      );

      expect(entry.postBalanceCents, equals(450000));
      final credit = await currentCredit(db);
      expect(credit.balanceCents, equals(450000));
      expect(credit.status, equals(CreditStatus.active));
      expect(credit.settledAt, isNull);
    });

    test('non-owner cannot adjust balance', () async {
      expect(
        () => correctionDao.adjustBalance(
          actor: manager(),
          idempotencyKey: const Uuid().v4(),
          creditId: creditId,
          amount: Money.fromCents(50000),
          adjustmentType: CreditLedgerEntryType.adjustmentDebit,
          reason: 'Some reason.',
          recordedAt: DateTime.utc(2026, 10, 23),
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('cross-shop credit access is rejected', () async {
      final otherOwner = AppUser(
        id: 'corr-other-owner',
        shopId: otherShopId,
        username: 'corr-other-owner',
        fullName: 'Other Owner',
        role: AppRole.shopOwner,
        isActive: true,
      );

      expect(
        () => correctionDao.adjustBalance(
          actor: otherOwner,
          idempotencyKey: const Uuid().v4(),
          creditId: creditId,
          amount: Money.fromCents(50000),
          adjustmentType: CreditLedgerEntryType.adjustmentDebit,
          reason: 'Cross-shop attempt.',
          recordedAt: DateTime.utc(2026, 10, 23),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects empty or whitespace rationale', () async {
      expect(
        () => correctionDao.adjustBalance(
          actor: owner(),
          idempotencyKey: const Uuid().v4(),
          creditId: creditId,
          amount: Money.fromCents(50000),
          adjustmentType: CreditLedgerEntryType.adjustmentDebit,
          reason: '   ',
          recordedAt: DateTime.utc(2026, 10, 23),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects zero or negative amount', () async {
      expect(
        () => correctionDao.adjustBalance(
          actor: owner(),
          idempotencyKey: const Uuid().v4(),
          creditId: creditId,
          amount: Money.fromCents(0),
          adjustmentType: CreditLedgerEntryType.adjustmentDebit,
          reason: 'Some reason.',
          recordedAt: DateTime.utc(2026, 10, 23),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => correctionDao.adjustBalance(
          actor: owner(),
          idempotencyKey: const Uuid().v4(),
          creditId: creditId,
          amount: Money.fromCents(-100),
          adjustmentType: CreditLedgerEntryType.adjustmentDebit,
          reason: 'Some reason.',
          recordedAt: DateTime.utc(2026, 10, 23),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects credit that would make balance negative', () async {
      expect(
        () => correctionDao.adjustBalance(
          actor: owner(),
          idempotencyKey: const Uuid().v4(),
          creditId: creditId,
          amount: Money.fromCents(400000),
          adjustmentType: CreditLedgerEntryType.adjustmentCredit,
          reason: 'Excessive credit.',
          recordedAt: DateTime.utc(2026, 10, 23),
        ),
        throwsA(isA<StateError>()),
      );

      final credit = await currentCredit(db);
      expect(credit.balanceCents, equals(300000));
    });

    test('ledger entry and credit balance agree after successful adjustment', () async {
      await correctionDao.adjustBalance(
        actor: owner(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        amount: Money.fromCents(25000),
        adjustmentType: CreditLedgerEntryType.adjustmentDebit,
        reason: 'Concession.',
        recordedAt: DateTime.utc(2026, 10, 23),
      );

      final credit = await currentCredit(db);
      expect(credit.balanceCents, equals(325000));

      final entries = await currentLedgerEntries(db);
      expect(entries, hasLength(1));
      expect(entries.first.read<int>('pre_balance_cents'), equals(300000));
      expect(entries.first.read<int>('post_balance_cents'), equals(325000));
      expect(entries.first.read<int>('post_balance_cents'), equals(credit.balanceCents));
    });

    test('ledger entry, balance, sync journal and audit event roll back on failure', () async {
      await db.customStatement('''
        CREATE TRIGGER "fail_sync_queue_insert"
        BEFORE INSERT ON "sync_queue"
        BEGIN
          SELECT RAISE(ABORT, 'simulated audit persistence failure');
        END;
      ''');

      final balanceBefore = (await currentCredit(db)).balanceCents;

      expect(
        () => correctionDao.adjustBalance(
          actor: owner(),
          idempotencyKey: const Uuid().v4(),
          creditId: creditId,
          amount: Money.fromCents(50000),
          adjustmentType: CreditLedgerEntryType.adjustmentDebit,
          reason: 'Rollback test.',
          recordedAt: DateTime.utc(2026, 10, 23),
        ),
        throwsA(anything),
      );

      final credit = await currentCredit(db);
      expect(credit.balanceCents, equals(balanceBefore));

      final entries = await currentLedgerEntries(db);
      expect(entries, isEmpty);

      final syncRows = await db.select(db.syncQueue).get();
      expect(syncRows, isEmpty);
    });

    test('repeating the same idempotency key does not double-apply', () async {
      final key = const Uuid().v4();
      final first = await correctionDao.adjustBalance(
        actor: owner(),
        idempotencyKey: key,
        creditId: creditId,
        amount: Money.fromCents(50000),
        adjustmentType: CreditLedgerEntryType.adjustmentDebit,
        reason: 'Idempotency test.',
        recordedAt: DateTime.utc(2026, 10, 23),
      );

      final second = await correctionDao.adjustBalance(
        actor: owner(),
        idempotencyKey: key,
        creditId: creditId,
        amount: Money.fromCents(999999),
        adjustmentType: CreditLedgerEntryType.adjustmentDebit,
        reason: 'Different payload, same key.',
        recordedAt: DateTime.utc(2026, 10, 23),
      );

      expect(second.id, equals(first.id));
      expect(second.amountCents, equals(50000));

      final credit = await currentCredit(db);
      expect(credit.balanceCents, equals(350000));

      final entries = await currentLedgerEntries(db);
      expect(entries, hasLength(1));
    });

    test('original payment records and previous ledger entries remain unchanged', () async {
      await correctionDao.adjustBalance(
        actor: owner(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        amount: Money.fromCents(50000),
        adjustmentType: CreditLedgerEntryType.adjustmentDebit,
        reason: 'First adjustment.',
        recordedAt: DateTime.utc(2026, 10, 23),
      );

      final payment = await (db.select(db.payments)
            ..where((p) => p.id.equals(paymentId) & p.shopId.equals(shopId)))
          .getSingle();
      expect(payment.amountCents, equals(200000));

      await correctionDao.adjustBalance(
        actor: owner(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        amount: Money.fromCents(10000),
        adjustmentType: CreditLedgerEntryType.adjustmentCredit,
        reason: 'Second adjustment.',
        recordedAt: DateTime.utc(2026, 10, 24),
      );

      final entries = await currentLedgerEntries(db);
      expect(entries, hasLength(2));
      expect(entries.first.read<int>('amount_cents'), equals(50000));
      expect(entries.first.read<int>('post_balance_cents'), equals(350000));

      final credit = await currentCredit(db);
      expect(credit.balanceCents, equals(340000));
    });

    test('adjustment is blocked while a correction is pending', () async {
      await correctionDao.requestCorrection(
        actor: manager(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        originalPaymentId: paymentId,
        amount: Money.fromCents(1000),
        reason: 'Pending correction.',
        requestedAt: DateTime.utc(2026, 10, 22),
      );
      expect((await currentCredit(db)).correctionPending, isTrue);

      expect(
        () => correctionDao.adjustBalance(
          actor: owner(),
          idempotencyKey: const Uuid().v4(),
          creditId: creditId,
          amount: Money.fromCents(50000),
          adjustmentType: CreditLedgerEntryType.adjustmentDebit,
          reason: 'Should be blocked.',
          recordedAt: DateTime.utc(2026, 10, 23),
        ),
        throwsA(isA<StateError>()),
      );

      final credit = await currentCredit(db);
      expect(credit.balanceCents, equals(300000));
      expect(credit.correctionPending, isTrue);
    });
  });
}

