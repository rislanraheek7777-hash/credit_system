import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull;
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

Future<AppDatabase> seedCredit({int balanceCents = 300000}) async {
  final executor = AppDatabaseConnection.openInMemoryConnection();
  final db = AppDatabase.forTesting(executor);

  final now = DateTime.now().toUtc();
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
      status: const Value('active'),
      workflowStatus: const Value('disbursed'),
      termPresetDays: const Value(30),
      dueDate: now.add(const Duration(days: 30)),
      disbursedAt: Value(now.subtract(const Duration(days: 10))),
      disbursedByUserId: Value(ownerId),
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
