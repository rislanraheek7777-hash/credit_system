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
import 'package:flutter_test/flutter_test.dart';

/// Focused regression coverage for the idempotency semantics of
/// [LoanDao.confirmLoanDisbursement] (Story 4.3, finding T2).
///
/// An idempotency record is only a *claim* that an operation ran. It does not
/// prove that the requested operation succeeded, nor that it succeeded for
/// the requested agreement. The authoritative source of truth for whether an
/// agreement was actually disbursed is the persisted loan row itself.
///
/// These tests therefore pin down that a key claimed by a different
/// operation, or by a different agreement, can never be turned into a false
/// successful disbursement.
void main() {
  const shopAlphaId = '11111111-1111-1111-1111-111111111701';
  const shopBetaId = '11111111-1111-1111-1111-111111111702';
  const customerAlphaId = '11111111-1111-1111-1111-111111111703';
  const customerBetaId = '11111111-1111-1111-1111-111111111704';
  const managerId = '11111111-1111-1111-1111-111111111705';
  const cashierId = '11111111-1111-1111-1111-111111111706';

  late AppDatabase db;
  late LoanDao loanDao;

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
      await db.into(db.shops).insert(ShopEntry(
        id: shop.id,
        name: shop.name,
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ));
    }
    for (final user in [
      (id: managerId, username: 'alpha.manager', role: 'manager'),
      (id: cashierId, username: 'alpha.cashier', role: 'cashier'),
    ]) {
      await db.into(db.appUsers).insert(AppUserEntry(
        id: user.id,
        shopId: shopAlphaId,
        username: user.username,
        fullName: user.username,
        role: user.role,
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ));
    }
    for (final customer in [
      (id: customerAlphaId, shopId: shopAlphaId, nic: '851234567V'),
      (id: customerBetaId, shopId: shopBetaId, nic: '901234567V'),
    ]) {
      await db.into(db.customers).insert(CustomerEntry(
        id: customer.id,
        shopId: customer.shopId,
        fullName: customer.id,
        nic: customer.nic,
        phone: '0771234567',
        address: '1 Main St',
        createdAt: now,
        updatedAt: now,
      ));
    }
    for (final item in [
      (id: 'coll-idem-a', shopId: shopAlphaId, customerId: customerAlphaId),
      (id: 'coll-idem-b', shopId: shopAlphaId, customerId: customerAlphaId),
      (id: 'coll-idem-beta', shopId: shopBetaId, customerId: customerBetaId),
    ]) {
      await CollateralDao(db).createCollateralItem(CollateralItem(
        id: item.id,
        shopId: item.shopId,
        customerId: item.customerId,
        itemReferenceId: 'REF-${item.id}',
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

  AppUser manager({String shopId = shopAlphaId}) => AppUser(
        id: managerId,
        shopId: shopId,
        username: 'alpha.manager',
        fullName: 'Alpha Manager',
        role: AppRole.manager,
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

  /// Originates an agreement that is awaiting disbursement.
  Future<Loan> originate({
    required String idempotencyKey,
    String customerId = customerAlphaId,
    String itemId = 'coll-idem-a',
    String shopId = shopAlphaId,
  }) async {
    return loanDao.createLoanAgreement(
      actor: manager(shopId: shopId),
      idempotencyKey: idempotencyKey,
      customerId: customerId,
      principal: const Money(500000),
      dueDate: DateTime.utc(2026, 11, 13, 18, 30),
      createdAt: DateTime.now().toUtc(),
      collateralItemIds: [itemId],
      termPresetDays: 30,
    );
  }

  /// Writes an idempotency record directly, simulating a claim left behind by
  /// an operation that did not complete.
  Future<void> writeClaim({
    required String idempotencyKey,
    required String entityId,
    required String actionType,
    String entityType = 'loan',
    String shopId = shopAlphaId,
  }) async {
    await db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
      id: 'claim-$idempotencyKey',
      shopId: shopId,
      idempotencyKey: idempotencyKey,
      entityType: entityType,
      entityId: entityId,
      actionType: actionType,
      payloadJson: '{}',
      createdAt: DateTime.now().toUtc(),
    ));
  }

  group('an idempotency key claimed by another operation is refused', () {
    test('an origination key reused for a disbursement is refused', () async {
      final loan = await originate(idempotencyKey: 'shared-key');

      // The origination already claimed the key.
      final claims = await db.select(db.syncQueue).get();
      expect(
        claims.firstWhere((c) => c.idempotencyKey == 'shared-key').actionType,
        equals(LoanDao.createLoanActionType),
      );

      await expectLater(
        loanDao.confirmLoanDisbursement(
          actor: manager(),
          idempotencyKey: 'shared-key',
          loanId: loan.id,
          disbursedAt: disbursedAt,
        ),
        throwsA(isA<StateError>()),
        reason: 'A key that belongs to the origination operation must not '
            'produce a disbursement result.',
      );

      // The agreement was NOT disbursed.
      final still = await loanDao.getLoanById(shopAlphaId, loan.id);
      expect(still!.workflowStatus, equals(LoanWorkflowStatus.pendingDisbursement));
      expect(still.disbursedAt, isNull);
      expect(still.disbursedByUserId, isNull);
      expect(
        (await db.select(db.syncQueue).get())
            .where((c) => c.actionType == LoanDao.confirmLoanDisbursementActionType),
        isEmpty,
        reason: 'No disbursement event may be recorded for a refused request.',
      );
    });

    test('a different action type on the same entity type is refused',
        () async {
      final loan = await originate(idempotencyKey: 'other-action-origin');
      await writeClaim(
        idempotencyKey: 'other-action-key',
        entityId: loan.id,
        actionType: 'some_unrelated_action',
      );

      await expectLater(
        loanDao.confirmLoanDisbursement(
          actor: manager(),
          idempotencyKey: 'other-action-key',
          loanId: loan.id,
          disbursedAt: disbursedAt,
        ),
        throwsA(isA<StateError>()),
      );

      final still = await loanDao.getLoanById(shopAlphaId, loan.id);
      expect(still!.workflowStatus, equals(LoanWorkflowStatus.pendingDisbursement));
    });

    test('a disbursement key reused for a different loan is refused',
        () async {
      final first = await originate(
        idempotencyKey: 'loan-a-origin',
        itemId: 'coll-idem-a',
      );
      final second = await originate(
        idempotencyKey: 'loan-b-origin',
        itemId: 'coll-idem-b',
      );

      // Disburse the first agreement.
      await loanDao.confirmLoanDisbursement(
        actor: manager(),
        idempotencyKey: 'disbursement-key',
        loanId: first.id,
        disbursedAt: disbursedAt,
      );

      // Reusing that key for the second agreement must not report the first
      // agreement's disbursement as the second agreement's result.
      await expectLater(
        loanDao.confirmLoanDisbursement(
          actor: manager(),
          idempotencyKey: 'disbursement-key',
          loanId: second.id,
          disbursedAt: disbursedAt,
        ),
        throwsA(isA<StateError>()),
      );

      final secondStill = await loanDao.getLoanById(shopAlphaId, second.id);
      expect(secondStill!.workflowStatus,
          equals(LoanWorkflowStatus.pendingDisbursement),
          reason: 'The second agreement must not be disbursed by a key that '
              'belongs to the first one.');
      expect(secondStill.disbursedAt, isNull);
    });
  });

  group('an idempotency record does not prove the operation completed', () {
    test('a claim without a completed disbursement is refused', () async {
      final loan = await originate(idempotencyKey: 'incomplete-origin');
      await writeClaim(
        idempotencyKey: 'incomplete-key',
        entityId: loan.id,
        actionType: LoanDao.confirmLoanDisbursementActionType,
      );

      await expectLater(
        loanDao.confirmLoanDisbursement(
          actor: manager(),
          idempotencyKey: 'incomplete-key',
          loanId: loan.id,
          disbursedAt: disbursedAt,
        ),
        throwsA(isA<StateError>()),
        reason: 'The persisted loan row is the source of truth; the agreement '
            'is still awaiting disbursement.',
      );

      final still = await loanDao.getLoanById(shopAlphaId, loan.id);
      expect(still!.workflowStatus, equals(LoanWorkflowStatus.pendingDisbursement));
      expect(still.disbursedAt, isNull);
    });
  });

  group('a genuine retry of the same disbursement', () {
    test('returns the same disbursed agreement and creates no duplicates',
        () async {
      // The origination and the disbursement are different operations and
      // therefore use different keys.
      final loan = await originate(idempotencyKey: 'retry-origin-key');

      final first = await loanDao.confirmLoanDisbursement(
        actor: manager(),
        idempotencyKey: 'retry-key',
        loanId: loan.id,
        disbursedAt: disbursedAt,
      );
      expect(first.id, equals(loan.id));
      expect(first.workflowStatus, equals(LoanWorkflowStatus.disbursed));
      expect(first.disbursedByUserId, equals(managerId));

      // Several more retries of the very same request.
      for (var i = 0; i < 4; i++) {
        final retry = await loanDao.confirmLoanDisbursement(
          actor: manager(),
          idempotencyKey: 'retry-key',
          loanId: loan.id,
          disbursedAt: disbursedAt,
        );
        expect(retry.id, equals(first.id));
        expect(retry.workflowStatus, equals(LoanWorkflowStatus.disbursed));
        expect(retry.disbursedAt, equals(first.disbursedAt));
        expect(retry.disbursedByUserId, equals(first.disbursedByUserId));
        expect(retry.dueDate, equals(first.dueDate));
      }

      // Exactly one agreement and exactly one disbursement event.
      expect(await db.select(db.loans).get(), hasLength(1));
      final events = (await db.select(db.syncQueue).get())
          .where((r) => r.actionType == LoanDao.confirmLoanDisbursementActionType)
          .toList();
      expect(events, hasLength(1));

      // The persisted disbursement record is the one written by the first,
      // successful attempt.
      final persisted = await loanDao.getLoanById(shopAlphaId, loan.id);
      expect(persisted!.disbursedAt, equals(first.disbursedAt));
      expect(persisted.disbursedByUserId, equals(managerId));
    });
  });

  group('shop scope and authorization are still enforced', () {
    test('an actor without the permission is refused before any lookup',
        () async {
      final loan = await originate(idempotencyKey: 'auth-origin');
      await loanDao.confirmLoanDisbursement(
        actor: manager(),
        idempotencyKey: 'auth-disbursement-key',
        loanId: loan.id,
        disbursedAt: disbursedAt,
      );

      await expectLater(
        loanDao.confirmLoanDisbursement(
          actor: cashier(),
          idempotencyKey: 'auth-disbursement-key',
          loanId: loan.id,
          disbursedAt: disbursedAt,
        ),
        throwsA(isA<PermissionDeniedException>()),
        reason: 'Authorization is enforced before the idempotency fast path, '
            'so a retry cannot bypass it.',
      );
    });

    test('an agreement in another shop is not disbursed through a shared key',
        () async {
      final betaLoan = await originate(
        idempotencyKey: 'beta-key',
        customerId: customerBetaId,
        itemId: 'coll-idem-beta',
        shopId: shopBetaId,
      );

      await expectLater(
        loanDao.confirmLoanDisbursement(
          actor: manager(shopId: shopAlphaId),
          idempotencyKey: 'beta-key',
          loanId: betaLoan.id,
          disbursedAt: disbursedAt,
        ),
        throwsA(isA<StateError>()),
        reason: 'The idempotency lookup and the loan lookup are both scoped to '
            "the actor's own shop.",
      );

      final untouched = await loanDao.getLoanById(shopBetaId, betaLoan.id);
      expect(untouched!.workflowStatus,
          equals(LoanWorkflowStatus.pendingDisbursement));
    });
  });
}
