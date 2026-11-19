import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:uuid/uuid.dart';

import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/core/permissions/authorization_guard.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/correction_dao.dart';
import 'package:credit_system/features/customers/data/daos/credit_dao.dart';
import 'package:credit_system/features/customers/data/daos/payment_dao.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';

/// Story 5.6: Staff-Proposed, Owner-Approved Balance Adjustments (Partial
/// Forgiveness).
///
/// Covers the full lifecycle against the in-memory database:
/// proposal -> pending correction + credit lock -> owner approve/reject ->
/// immutable ledger entry -> lock lift -> settle the remainder. A staff actor
/// may never approve; an adjustment exceeding the balance is refused.
const String shopId = 'adjust-shop-1111-1111-1111-111111111101';
const int customerId = 1;
const String ownerId = 'adjust-owner-1111-1111-1111-111111111102';
const String managerId = 'adjust-manager-1111-1111-1111-111111111103';
const String creditId = 'adjust-credit-1111-1111-1111-111111111104';

AppUser ownerActor() => AppUser(
      id: ownerId,
      shopId: shopId,
      username: 'adjust-owner',
      fullName: 'Adjust Owner',
      role: AppRole.shopOwner,
      isActive: true,
      sessionVersion: 1,
    );

AppUser managerActor() => AppUser(
      id: managerId,
      shopId: shopId,
      username: 'adjust-manager',
      fullName: 'Adjust Manager',
      role: AppRole.manager,
      isActive: true,
      sessionVersion: 1,
    );

Future<AppDatabase> seedCredit({
  int balanceCents = 300000,
  String status = 'active',
  String workflowStatus = 'disbursed',
}) async {
  final executor = AppDatabaseConnection.openInMemoryConnection();
  final db = AppDatabase.forTesting(executor);

  final now = DateTime.now().toUtc();
  final isCancelled = status == 'cancelled';
  final isDisbursedWorkflow = workflowStatus == 'disbursed';
  await db.into(db.shops).insert(
    ShopEntry(
      id: shopId,
      name: 'Adjust Shop',
      currencyCode: 'LKR',
      timezone: 'Asia/Colombo',
      createdAt: now,
      updatedAt: now,
    ),
  );
  await db.into(db.customers).insert(
    CustomerEntry(
      id: customerId,
      shopId: shopId,
      fullName: 'Adjust Customer',
      nic: '851234567V',
      phone: '0771234567',
      address: '1 Adjust St',
      createdAt: now,
      updatedAt: now,
    ),
  );
  for (final (id, username, fullName, role) in [
    (ownerId, 'adjust-owner', 'Adjust Owner', 'shop_owner'),
    (managerId, 'adjust-manager', 'Adjust Manager', 'manager'),
  ]) {
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: id,
        shopId: shopId,
        username: username,
        fullName: fullName,
        role: role,
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
  await db.into(db.credits).insert(
    CreditsCompanion.insert(
      id: creditId,
      shopId: shopId,
      customerId: customerId,
      principalCents: 500000,
      balanceCents: balanceCents,
      status: Value(status),
      workflowStatus: Value(workflowStatus),
      termPresetDays: const Value(30),
      dueDate: now.add(const Duration(days: 30)),
      disbursedAt: isDisbursedWorkflow
          ? Value(now.subtract(const Duration(days: 10)))
          : const Value.absent(),
      disbursedByUserId:
          isDisbursedWorkflow ? Value(ownerId) : const Value.absent(),
      cancelledAt: isCancelled ? Value(now) : const Value.absent(),
      cancellationReason:
          isCancelled ? const Value('Cancelled before disbursement') : const Value.absent(),
      settledAt: status == 'settled'
          ? Value(now.subtract(const Duration(days: 3)))
          : const Value.absent(),
      createdAt: now,
      correctionPending: const Value(false),
    ),
  );
  return db;
}

void main() {
  test('staff propose partial forgiveness; the credit locks pending owner approval',
      () async {
    final db = await seedCredit();
    final now = DateTime.now().toUtc();

    final correction = await CorrectionDao(db).requestCorrection(
      actor: managerActor(),
      idempotencyKey: const Uuid().v4(),
      creditId: creditId,
      originalPaymentId: null,
      amount: Money.fromCents(100000),
      reason: 'Customer can only pay part of the balance now.',
      requestedAt: now,
      direction: CorrectionDao.directionCredit,
    );

    expect(correction.isPending, isTrue);
    expect(correction.direction, CorrectionDao.directionCredit);
    expect(correction.originalPaymentId, isNull);
    expect(correction.correctionAmountCents, 100000);

    // The correction lock is active on the credit.
    final credit = await CreditDao(db).getCreditById(shopId, creditId);
    expect(credit!.correctionPending, isTrue);
    expect(credit.balanceCents, 300000, reason: 'no balance change before approval');

    await db.close();
  });

  test('a staff actor cannot approve the proposal', () async {
    final db = await seedCredit();
    final now = DateTime.now().toUtc();
    final dao = CorrectionDao(db);

    final correction = await dao.requestCorrection(
      actor: managerActor(),
      idempotencyKey: const Uuid().v4(),
      creditId: creditId,
      originalPaymentId: null,
      amount: Money.fromCents(100000),
      reason: 'Partial forgiveness requested.',
      requestedAt: now,
      direction: CorrectionDao.directionCredit,
    );

    await expectLater(
      dao.approveCorrection(
        actor: managerActor(),
        idempotencyKey: const Uuid().v4(),
        correctionId: correction.id,
        reviewedAt: now,
      ),
      throwsA(isA<PermissionDeniedException>()),
    );

    await db.close();
  });

  test('owner approval posts adjustment_credit, recalculates the balance and lifts the lock',
      () async {
    final db = await seedCredit();
    final now = DateTime.now().toUtc();
    final dao = CorrectionDao(db);

    final correction = await dao.requestCorrection(
      actor: managerActor(),
      idempotencyKey: const Uuid().v4(),
      creditId: creditId,
      originalPaymentId: null,
      amount: Money.fromCents(100000),
      reason: 'Partial forgiveness requested by staff.',
      requestedAt: now,
      direction: CorrectionDao.directionCredit,
    );

    final approved = await dao.approveCorrection(
      actor: ownerActor(),
      idempotencyKey: const Uuid().v4(),
      correctionId: correction.id,
      reviewedAt: DateTime.now().toUtc(),
    );

    expect(approved.isApproved, isTrue);
    expect(approved.resultingBalanceCents, 200000);

    final credit = await CreditDao(db).getCreditById(shopId, creditId);
    expect(credit!.balanceCents, 200000);
    expect(credit.correctionPending, isFalse);

    final ledger = await dao.getLedgerEntriesByCredit(shopId, creditId);
    expect(ledger, hasLength(1));
    expect(ledger.single.entryType, CreditLedgerEntryType.adjustmentCredit);
    expect(ledger.single.amountCents, 100000);
    expect(ledger.single.preBalanceCents, 300000);
    expect(ledger.single.postBalanceCents, 200000);
    expect(ledger.single.correctionId, correction.id);

    await db.close();
  });

  test('owner rejection leaves the balance unchanged and lifts the lock',
      () async {
    final db = await seedCredit();
    final now = DateTime.now().toUtc();
    final dao = CorrectionDao(db);

    final correction = await dao.requestCorrection(
      actor: managerActor(),
      idempotencyKey: const Uuid().v4(),
      creditId: creditId,
      originalPaymentId: null,
      amount: Money.fromCents(50000),
      reason: 'Forgiveness requested.',
      requestedAt: now,
      direction: CorrectionDao.directionCredit,
    );

    final rejected = await dao.rejectCorrection(
      actor: ownerActor(),
      idempotencyKey: const Uuid().v4(),
      correctionId: correction.id,
      rejectionReason: 'Customer can pay in full next month.',
      reviewedAt: DateTime.now().toUtc(),
    );

    expect(rejected.isRejected, isTrue);
    expect(rejected.rejectionReason, 'Customer can pay in full next month.');
    expect(rejected.resultingBalanceCents, isNull);

    final credit = await CreditDao(db).getCreditById(shopId, creditId);
    expect(credit!.balanceCents, 300000);
    expect(credit.correctionPending, isFalse);

    final ledger = await dao.getLedgerEntriesByCredit(shopId, creditId);
    expect(ledger, isEmpty);

    await db.close();
  });

  test('a forgiveness proposal exceeding the outstanding balance is refused',
      () async {
    final db = await seedCredit();
    final now = DateTime.now().toUtc();
    final dao = CorrectionDao(db);

    await expectLater(
      dao.requestCorrection(
        actor: managerActor(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        originalPaymentId: null,
        amount: Money.fromCents(400000),
        reason: 'Forgive more than the balance.',
        requestedAt: now,
        direction: CorrectionDao.directionCredit,
      ),
      throwsA(isA<StateError>()),
    );

    final credit = await CreditDao(db).getCreditById(shopId, creditId);
    expect(credit!.balanceCents, 300000);
    expect(credit.correctionPending, isFalse);

    await db.close();
  });

  test('an increase adjustment posts adjustment_debit and raises the balance',
      () async {
    final db = await seedCredit();
    final now = DateTime.now().toUtc();
    final dao = CorrectionDao(db);

    final correction = await dao.requestCorrection(
      actor: managerActor(),
      idempotencyKey: const Uuid().v4(),
      creditId: creditId,
      originalPaymentId: null,
      amount: Money.fromCents(25000),
      reason: 'Undercharged at disbursement; customer agreed to owe more.',
      requestedAt: now,
      direction: CorrectionDao.directionDebit,
    );

    await dao.approveCorrection(
      actor: ownerActor(),
      idempotencyKey: const Uuid().v4(),
      correctionId: correction.id,
      reviewedAt: DateTime.now().toUtc(),
    );

    final credit = await CreditDao(db).getCreditById(shopId, creditId);
    expect(credit!.balanceCents, 325000);

    final ledger = await dao.getLedgerEntriesByCredit(shopId, creditId);
    expect(ledger.single.entryType, CreditLedgerEntryType.adjustmentDebit);
    expect(ledger.single.postBalanceCents, 325000);

    await db.close();
  });

  test('double-tap approve with the same idempotency key commits exactly once',
      () async {
    final db = await seedCredit();
    final now = DateTime.now().toUtc();
    final dao = CorrectionDao(db);

    final correction = await dao.requestCorrection(
      actor: managerActor(),
      idempotencyKey: const Uuid().v4(),
      creditId: creditId,
      originalPaymentId: null,
      amount: Money.fromCents(100000),
      reason: 'Partial forgiveness requested by staff.',
      requestedAt: now,
      direction: CorrectionDao.directionCredit,
    );

    final approveKey = const Uuid().v4();
    final approved = await dao.approveCorrection(
      actor: ownerActor(),
      idempotencyKey: approveKey,
      correctionId: correction.id,
      reviewedAt: DateTime.now().toUtc(),
    );
    // A re-transmitted approval with the same key resolves to the recorded
    // decision instead of posting a second ledger entry.
    final approvedAgain = await dao.approveCorrection(
      actor: ownerActor(),
      idempotencyKey: approveKey,
      correctionId: correction.id,
      reviewedAt: DateTime.now().toUtc(),
    );

    expect(approvedAgain.id, approved.id);
    expect(approvedAgain.isApproved, isTrue);

    final credit = await CreditDao(db).getCreditById(shopId, creditId);
    expect(credit!.balanceCents, 200000, reason: 'balance reduced exactly once');
    expect(credit.correctionPending, isFalse);

    final ledger = await dao.getLedgerEntriesByCredit(shopId, creditId);
    expect(ledger, hasLength(1));

    await db.close();
  });

  test('a full forgiveness settles the credit atomically on approval',
      () async {
    final db = await seedCredit();
    final now = DateTime.now().toUtc();
    final dao = CorrectionDao(db);

    // Zero is permitted: a forgiveness equal to the full balance.
    final correction = await dao.requestCorrection(
      actor: managerActor(),
      idempotencyKey: const Uuid().v4(),
      creditId: creditId,
      originalPaymentId: null,
      amount: Money.fromCents(300000),
      reason: 'Customer is insolvent; forgive the whole balance.',
      requestedAt: now,
      direction: CorrectionDao.directionCredit,
    );

    final approved = await dao.approveCorrection(
      actor: ownerActor(),
      idempotencyKey: const Uuid().v4(),
      correctionId: correction.id,
      reviewedAt: DateTime.now().toUtc(),
    );

    expect(approved.resultingBalanceCents, 0);

    final credit = await CreditDao(db).getCreditById(shopId, creditId);
    expect(credit!.balanceCents, 0);
    expect(credit.status, CreditStatus.settled,
        reason: 'a zero-balance credit must not strand as active');
    expect(credit.settledAt, isNotNull);
    expect(credit.correctionPending, isFalse);

    final ledger = await dao.getLedgerEntriesByCredit(shopId, creditId);
    expect(ledger.single.entryType, CreditLedgerEntryType.adjustmentCredit);
    expect(ledger.single.postBalanceCents, 0);

    await db.close();
  });

  test("a 'credit'-direction proposal referencing an original payment is rejected at validation",
      () async {
    final db = await seedCredit();
    final now = DateTime.now().toUtc();
    final dao = CorrectionDao(db);

    await expectLater(
      dao.requestCorrection(
        actor: managerActor(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        originalPaymentId: 'some-payment-id',
        amount: Money.fromCents(50000),
        reason: 'Forgive part of the payment.',
        requestedAt: now,
        direction: CorrectionDao.directionCredit,
      ),
      throwsA(isA<ArgumentError>()),
    );

    final credit = await CreditDao(db).getCreditById(shopId, creditId);
    expect(credit!.correctionPending, isFalse,
        reason: 'a rejected proposal must not lock the credit');

    await db.close();
  });

  test('proposals are refused on pending-disbursement, cancelled and zero-balance credits',
      () async {
    for (final scenario in [
      ({'status': 'active', 'workflowStatus': 'pending_disbursement'}),
      ({'status': 'cancelled', 'workflowStatus': 'cancelled'}),
      ({'status': 'active', 'workflowStatus': 'disbursed'}),
    ]) {
      final isZeroBalance = scenario['workflowStatus'] == 'disbursed';
      final db = await seedCredit(
        status: scenario['status']!,
        workflowStatus: scenario['workflowStatus']!,
        balanceCents: isZeroBalance ? 0 : 300000,
      );
      final now = DateTime.now().toUtc();

      await expectLater(
        CorrectionDao(db).requestCorrection(
          actor: managerActor(),
          idempotencyKey: const Uuid().v4(),
          creditId: creditId,
          originalPaymentId: null,
          amount: Money.fromCents(50000),
          reason: 'Forgiveness requested.',
          requestedAt: now,
          direction: CorrectionDao.directionCredit,
        ),
        throwsA(isA<StateError>()),
        reason: scenario.toString(),
      );

      final credit = await CreditDao(db).getCreditById(shopId, creditId);
      expect(credit!.correctionPending, isFalse);

      await db.close();
    }
  });

  test('a payment correction on a settled credit is exempt from the eligibility gate (Story 5.5)',
      () async {
    final db = await seedCredit(
      status: 'settled',
      workflowStatus: 'disbursed',
      balanceCents: 0,
    );
    final now = DateTime.now().toUtc();
    await db.into(db.payments).insert(
      PaymentsCompanion.insert(
        id: 'payment-full-1',
        shopId: shopId,
        creditId: creditId,
        receiptNumber: 'RCP-TEST-FULLSETTLE',
        amountCents: 500000,
        preBalanceCents: 500000,
        postBalanceCents: 0,
        paymentType: 'full_settlement',
        recordedAt: now.subtract(const Duration(days: 10)),
        recordedByUserId: ownerId,
        customerId: customerId,
        customerName: 'Adjust Customer',
        customerNic: '851234567V',
        shopName: 'Adjust Shop',
        idempotencyKey: 'idemp-full-1',
      ),
    );
    final dao = CorrectionDao(db);

    final correction = await dao.requestCorrection(
      actor: managerActor(),
      idempotencyKey: const Uuid().v4(),
      creditId: creditId,
      originalPaymentId: 'payment-full-1',
      amount: Money.fromCents(500000),
      reason: 'The settling payment was recorded erroneously.',
      requestedAt: now,
      direction: CorrectionDao.directionDebit,
    );

    expect(correction.isPending, isTrue);

    await db.close();
  });

  test('a proposal on an overdue credit (status overdue, workflow disbursed) is accepted',
      () async {
    final db = await seedCredit(
      status: 'overdue',
      workflowStatus: 'disbursed',
      balanceCents: 300000,
    );
    final now = DateTime.now().toUtc();
    final dao = CorrectionDao(db);

    final correction = await dao.requestCorrection(
      actor: managerActor(),
      idempotencyKey: const Uuid().v4(),
      creditId: creditId,
      originalPaymentId: null,
      amount: Money.fromCents(100000),
      reason: 'Forgiveness requested for a delinquent borrower.',
      requestedAt: now,
      direction: CorrectionDao.directionCredit,
    );

    expect(correction.isPending, isTrue);

    final credit = await CreditDao(db).getCreditById(shopId, creditId);
    expect(credit!.correctionPending, isTrue);

    await db.close();
  });

  test('the approval audit entry carries actor ids, target credit, direction, pre/post balance and justification',
      () async {
    final db = await seedCredit();
    final now = DateTime.now().toUtc();
    final dao = CorrectionDao(db);

    const justification = 'Customer is insolvent; partial forgiveness agreed.';
    final correction = await dao.requestCorrection(
      actor: managerActor(),
      idempotencyKey: const Uuid().v4(),
      creditId: creditId,
      originalPaymentId: null,
      amount: Money.fromCents(100000),
      reason: justification,
      requestedAt: now,
      direction: CorrectionDao.directionCredit,
    );

    await dao.approveCorrection(
      actor: ownerActor(),
      idempotencyKey: const Uuid().v4(),
      correctionId: correction.id,
      reviewedAt: DateTime.now().toUtc(),
    );

    final auditRows = await (db.select(db.syncQueue)
          ..where((s) => s.actionType.equals('approve_correction')))
        .get();
    expect(auditRows, isNotEmpty);

    final payloads = auditRows
        .map((row) => jsonDecode(row.payloadJson) as Map<String, dynamic>)
        .toList();
    for (final payload in payloads) {
      expect(payload['auditCategory'], 7);
      expect(payload['actorId'], ownerId);
      expect(payload['correctionId'], correction.id);
      expect(payload['creditId'], creditId);
      expect(payload['direction'], 'credit');
      expect(payload['reason'], justification);
    }
    final committingPayload = payloads.firstWhere(
      (payload) => payload.containsKey('previousBalanceCents'),
    );
    expect(committingPayload['previousBalanceCents'], 300000);
    expect(committingPayload['newBalanceCents'], 200000);

    await db.close();
  });

  test('an approval whose balance re-check fails rolls back completely',
      () async {
    final db = await seedCredit();
    final now = DateTime.now().toUtc();
    final dao = CorrectionDao(db);

    // Full-balance forgiveness proposed while the balance is 300000.
    final correction = await dao.requestCorrection(
      actor: managerActor(),
      idempotencyKey: const Uuid().v4(),
      creditId: creditId,
      originalPaymentId: null,
      amount: Money.fromCents(300000),
      reason: 'Customer cannot pay.',
      requestedAt: now,
      direction: CorrectionDao.directionCredit,
    );

    // A concurrent writer shrinks the balance directly (bypassing the DAO
    // and the lock, as a settlement would inside its own transaction).
    await db.customStatement(
      'UPDATE credits SET balance_cents = 100000 WHERE id = ?',
      [creditId],
    );

    await expectLater(
      dao.approveCorrection(
        actor: ownerActor(),
        idempotencyKey: const Uuid().v4(),
        correctionId: correction.id,
        reviewedAt: DateTime.now().toUtc(),
      ),
      throwsA(isA<StateError>()),
    );

    // The approval rolled back: correction still pending, no ledger entry,
    // no approval audit row recorded.
    final pending = await dao.getCorrectionById(shopId, correction.id);
    expect(pending!.isPending, isTrue);
    expect(await dao.getLedgerEntriesByCredit(shopId, creditId), isEmpty);

    await db.close();
  });

  test('settlement-forgiveness end to end: propose, owner approves, settle the remainder',
      () async {
    final db = await seedCredit();
    final now = DateTime.now().toUtc();
    final dao = CorrectionDao(db);

    // 1. Staff propose forgiveness of 100000 from a 300000 balance.
    final correction = await dao.requestCorrection(
      actor: managerActor(),
      idempotencyKey: const Uuid().v4(),
      creditId: creditId,
      originalPaymentId: null,
      amount: Money.fromCents(100000),
      reason: 'Customer cannot pay in full this month.',
      requestedAt: now,
      direction: CorrectionDao.directionCredit,
    );

    // 2. Payments are blocked while the proposal is pending.
    await expectLater(
      PaymentDao(db).recordPayment(
        actor: managerActor(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditId,
        amount: Money.fromCents(300000),
        recordedAt: now,
      ),
      throwsA(isA<CreditCorrectionPendingException>()),
    );

    // 3. Shop Owner approves the forgiveness.
    await dao.approveCorrection(
      actor: ownerActor(),
      idempotencyKey: const Uuid().v4(),
      correctionId: correction.id,
      reviewedAt: DateTime.now().toUtc(),
    );

    // 4. Staff settles the remaining 200000; the credit settles.
    final receipt = await PaymentDao(db).recordPayment(
      actor: managerActor(),
      idempotencyKey: const Uuid().v4(),
      creditId: creditId,
      amount: Money.fromCents(200000),
      recordedAt: DateTime.now().toUtc(),
    );
    expect(receipt.isFullSettlement, isTrue);

    final credit = await CreditDao(db).getCreditById(shopId, creditId);
    expect(credit!.balanceCents, 0);
    expect(credit.status, CreditStatus.settled);

    await db.close();
  });
}
