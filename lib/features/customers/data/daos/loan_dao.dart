import 'dart:convert';

import 'package:drift/drift.dart';
import '../../../../core/data/local/app_database.dart';
import '../../../../core/data/local/tables/loans_table.dart';
import '../../../../core/money/money.dart';
import '../../../../core/permissions/app_permission.dart';
import '../../../../core/permissions/authorization_guard.dart';
import '../../../auth/domain/models/app_user.dart';
import '../../domain/models/loan.dart';
import '../../domain/models/loan_term.dart';
import 'package:uuid/uuid.dart';

part 'loan_dao.g.dart';

/// Data Access Object for Loan agreements (Story 2.5).
///
/// All queries are strictly scoped to [shopId] to enforce tenant isolation.
/// A loan can only be created, read, or updated within its owning shop.
@DriftAccessor(tables: [Loans])
class LoanDao extends DatabaseAccessor<AppDatabase> with _$LoanDaoMixin {
  LoanDao(super.db);

  /// Entity type recorded in `sync_queue` for loan-related events.
  static const String loanEntityType = 'loan';

  /// Action type recorded in `sync_queue` for a loan agreement creation.
  static const String createLoanActionType = 'create_loan_agreement';

  /// Action type recorded in `sync_queue` for a disbursement confirmation.
  static const String confirmLoanDisbursementActionType =
      'confirm_loan_disbursement';

  /// PRD FR-31 audit category for a confirmed cash disbursement event.
  static const int loanDisbursementAuditCategory = 4;
  /// Action type recorded in `sync_queue` for a loan cancellation.
  /// PRD FR-31 audit category for a loan agreement origination event.
  static const int loanOriginationAuditCategory = 2;

  /// Action type recorded in `sync_queue` for a loan cancellation.
  static const String cancelLoanAgreementActionType =
      'cancel_loan_agreement';

  /// Converts a Drift [LoanEntry] row into a domain [Loan].
  Loan _toDomain(LoanEntry entry) {
    return Loan(
      id: entry.id,
      shopId: entry.shopId,
      customerId: entry.customerId,
      principalCents: entry.principalCents,
      balanceCents: entry.balanceCents,
      status: LoanStatus.fromValue(entry.status),
      workflowStatus: LoanWorkflowStatus.fromValue(entry.workflowStatus),
      dueDate: DateTime.fromMillisecondsSinceEpoch(entry.dueDate.millisecondsSinceEpoch, isUtc: true),
      createdAt: DateTime.fromMillisecondsSinceEpoch(entry.createdAt.millisecondsSinceEpoch, isUtc: true),
      settledAt: entry.settledAt != null
          ? DateTime.fromMillisecondsSinceEpoch(entry.settledAt!.millisecondsSinceEpoch, isUtc: true)
          : null,
      termPresetDays: entry.termPresetDays,
      customDueDate: entry.customDueDate != null
          ? DateTime.fromMillisecondsSinceEpoch(entry.customDueDate!.millisecondsSinceEpoch, isUtc: true)
          : null,
      disbursedAt: entry.disbursedAt != null
          ? DateTime.fromMillisecondsSinceEpoch(entry.disbursedAt!.millisecondsSinceEpoch, isUtc: true)
          : null,
      disbursedByUserId: entry.disbursedByUserId,
      cancelledAt: entry.cancelledAt != null
          ? DateTime.fromMillisecondsSinceEpoch(entry.cancelledAt!.millisecondsSinceEpoch, isUtc: true)
          : null,
      cancellationReason: entry.cancellationReason,
      correctionPending: entry.correctionPending,
    );
  }

  /// Converts a domain [Loan] into a Drift [LoansCompanion].
  LoansCompanion _toCompanion(Loan loan) {
    return LoansCompanion(
      id: Value(loan.id),
      shopId: Value(loan.shopId),
      customerId: Value(loan.customerId),
      principalCents: Value(loan.principalCents),
      balanceCents: Value(loan.balanceCents),
      status: Value(loan.status.value),
      workflowStatus: Value(loan.workflowStatus.value),
      dueDate: Value(loan.dueDate),
      createdAt: Value(loan.createdAt),
      settledAt: Value(loan.settledAt),
      termPresetDays: Value(loan.termPresetDays),
      customDueDate: Value(loan.customDueDate),
      disbursedAt: Value(loan.disbursedAt),
      disbursedByUserId: Value(loan.disbursedByUserId),
      cancelledAt: Value(loan.cancelledAt),
      cancellationReason: Value(loan.cancellationReason),
      correctionPending: Value(loan.correctionPending),
    );
  }

  /// Inserts a new loan record into the local SQLite database.
  ///
  /// Validates that the loan belongs to [shopId] before insertion.
  /// Throws [sqlite.SqliteException] if foreign key constraints are violated
  /// (e.g., referenced customer or shop does not exist).
  Future<void> createLoan(Loan loan) async {
    if (loan.shopId.trim().isEmpty) {
      throw ArgumentError.value(loan.shopId, 'shopId', 'shopId cannot be empty');
    }
    if (loan.customerId <= 0) {
      throw ArgumentError.value(
          loan.customerId, 'customerId', 'customerId must be a positive integer');
    }
    await into(loans).insert(_toCompanion(loan));
  }

  /// Retrieves all loans for [customerId] strictly scoped within [shopId].
  ///
  /// Returns loans ordered by due date ascending.
  Future<List<Loan>> getLoansByCustomerId(
    String shopId,
    int customerId,
  ) async {
    final query = select(loans)
      ..where((l) => l.shopId.equals(shopId) & l.customerId.equals(customerId))
      ..orderBy([(l) => OrderingTerm.asc(l.dueDate)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Retrieves all loans in [shopId] matching [status].
  ///
  /// Strictly scoped to [shopId] — loans in other shops are never returned.
  Future<List<Loan>> getLoansByStatus(String shopId, LoanStatus status) async {
    final query = select(loans)
      ..where((l) =>
          l.shopId.equals(shopId) & l.status.equals(status.value))
      ..orderBy([(l) => OrderingTerm.asc(l.dueDate)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Retrieves all loans for [customerId] in [shopId] matching [status].
  ///
  /// Strictly scoped to [shopId] — loans in other shops are never returned.
  Future<List<Loan>> getLoansByCustomerAndStatus(
    String shopId,
    int customerId,
    LoanStatus status,
  ) async {
    final query = select(loans)
      ..where((l) =>
          l.shopId.equals(shopId) &
          l.customerId.equals(customerId) &
          l.status.equals(status.value))
      ..orderBy([(l) => OrderingTerm.asc(l.dueDate)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Retrieves a loan by [loanId] strictly scoped within [shopId].
  ///
  /// Returns `null` if the loan does not exist or belongs to another shop.
  Future<Loan?> getLoanById(String shopId, String loanId) async {
    final query = select(loans)
      ..where((l) => l.shopId.equals(shopId) & l.id.equals(loanId));
    final entry = await query.getSingleOrNull();
    return entry != null ? _toDomain(entry) : null;
  }
  /// Reactive stream of all loans in [shopId], ordered by due date ascending.
  ///
  /// Emits the current list immediately and again whenever the loans table
  /// changes for [shopId]. Strictly scoped to [shopId].
  /// Retrieves all loans in [shopId], ordered by due date ascending.
  ///
  /// Strictly scoped to [shopId] — loans in other shops are never returned.
  Future<List<Loan>> getLoansByShopId(String shopId) async {
    final query = select(loans)
      ..where((l) => l.shopId.equals(shopId))
      ..orderBy([(l) => OrderingTerm.asc(l.dueDate)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Resolves the configured [ShopTimeZone] for [shopId] from the shops table.
  ///
  /// Fails closed with [UnsupportedShopTimeZoneException] for an unknown
  /// identifier rather than silently falling back.
  Future<ShopTimeZone> resolveShopTimeZone(String shopId) async {
    final entry = await (select(db.shops)
          ..where((s) => s.id.equals(shopId)))
        .getSingle();
    return ShopTimeZone(entry.timezone);
  }

  /// Updates the status and workflow status of a loan strictly scoped to
  /// [shopId].
  Future<void> updateLoanStatus({
    required String shopId,
    required String loanId,
    required LoanStatus status,
    required LoanWorkflowStatus workflowStatus,
  }) async {
    await (update(loans)
          ..where((l) => l.shopId.equals(shopId) & l.id.equals(loanId)))
        .write(LoansCompanion(
      status: Value(status.value),
      workflowStatus: Value(workflowStatus.value),
    ));
  }

  Stream<List<Loan>> watchLoansByShopId(String shopId) {
    final query = select(loans)
      ..where((l) => l.shopId.equals(shopId))
      ..orderBy([(l) => OrderingTerm.asc(l.dueDate)]);
    return query.watch().map((entries) => entries.map(_toDomain).toList());
  }
  /// Creates a loan agreement with the agreed term (Story 4.1 / Story 4.3).
  Future<Loan> createLoanAgreement({
    required AppUser actor,
    required String idempotencyKey,
    required int customerId,
    required Money principal,
    required DateTime dueDate,
    required DateTime createdAt,
    required List<String> collateralItemIds,
    int? termPresetDays,
    DateTime? customDueDate,
  }) async {
    if (!actor.isActive) {
      throw const PermissionDeniedException(
        'Access denied: User account is deactivated.',
        requiredPermission: 'createLoans',
      );
    }
    AuthorizationGuard.checkPermission(
      isActive: actor.isActive,
      effectivePermissions: actor.effectivePermissions,
      permission: AppPermission.createLoans,
      actionDescription: 'create a loan agreement',
    );

    if (termPresetDays != null && customDueDate != null) {
      throw ArgumentError.value(null, 'term', 'either a preset term or a custom date, not both');
    }
    if (termPresetDays != null && !const {30, 60, 90}.contains(termPresetDays)) {
      throw ArgumentError.value(termPresetDays, 'termPresetDays', 'must be one of 30, 60, or 90 days');
    }

    final loanId = const Uuid().v4();
    final now = DateTime.now().toUtc();

    final idempotencyClaimed = await into(db.syncQueue).insertReturningOrNull(
      SyncQueueCompanion(
        id: Value(const Uuid().v4()),
        shopId: Value(actor.shopId),
        idempotencyKey: Value(idempotencyKey),
        entityType: Value(loanEntityType),
        entityId: Value(loanId),
        actionType: Value(createLoanActionType),
        payloadJson: Value(jsonEncode({
          'auditCategory': 2,
          'auditEvent': 'loan_agreement_origination',
          'actorId': actor.id,
          'loanId': loanId,
          'customerId': customerId,
          'principalCents': principal.minorUnits,
        })),
        status: Value('pending_server_ack'),
        createdAt: Value(now),
      ),
      mode: InsertMode.insertOrIgnore,
    );

    if (idempotencyClaimed == null) {
      throw ArgumentError.value(idempotencyKey, 'idempotencyKey', 'already exists');
    }

    final loan = Loan(
      id: loanId,
      shopId: actor.shopId,
      customerId: customerId,
      principalCents: principal.minorUnits,
      balanceCents: principal.minorUnits,
      status: LoanStatus.active,
      workflowStatus: LoanWorkflowStatus.pendingDisbursement,
      dueDate: dueDate,
      createdAt: createdAt,
      termPresetDays: termPresetDays,
      customDueDate: customDueDate,
      correctionPending: false,
    );

    await into(loans).insert(_toCompanion(loan));

    // Bind the pledged collateral items to the new loan agreement.
    if (collateralItemIds.isNotEmpty) {
      await (update(db.collateralItems)
            ..where((c) =>
                c.shopId.equals(actor.shopId) &
                c.id.isIn(collateralItemIds)))
          .write(CollateralItemsCompanion(
        loanId: Value(loanId),
        updatedAt: Value(now),
      ));
    }

    return loan;
  }

  /// Confirms physical cash disbursement of an existing agreement (Story 4.3, AC-1).
  ///
  /// Transitions `Pending Disbursement` → `Disbursed`, records the confirmed
  /// cash disbursement timestamp and disbursing staff ID, finalises the
  /// official calendar due date from the agreed term, and queues a Category 4
  /// audit/event record in `sync_queue`. Never creates a loan agreement and
  /// never records a payment.
  ///
  /// Authorizes with `AppPermission.confirmLoanDisbursement`. All writes occur
  /// in one database transaction; a failure rolls all back.
  Future<Loan> confirmLoanDisbursement({
    required AppUser actor,
    required String idempotencyKey,
    required String loanId,
    required DateTime disbursedAt,
  }) async {
    if (!actor.isActive) {
      throw const PermissionDeniedException(
        'Access denied: User account is deactivated.',
        requiredPermission: 'confirmLoanDisbursement',
      );
    }
    AuthorizationGuard.checkPermission(
      isActive: actor.isActive,
      effectivePermissions: actor.effectivePermissions,
      permission: AppPermission.confirmLoanDisbursement,
      actionDescription: 'confirm cash disbursement',
    );

    if (idempotencyKey.trim().isEmpty) {
      throw ArgumentError.value(
        idempotencyKey,
        'idempotencyKey',
        'idempotency key cannot be blank',
      );
    }

    return await db.transaction(() async {
      // Re-read inside the transaction to get the latest committed state.
      final current = await getLoanById(actor.shopId, loanId);
      if (current == null) {
        throw StateError('Loan $loanId not found in shop ${actor.shopId}.');
      }

      // Idempotency guard: claim the key. Null means duplicate key (same-key retry).
      final idempotencyClaimed = await into(db.syncQueue).insertReturningOrNull(
        SyncQueueCompanion(
          id: Value(const Uuid().v4()),
          shopId: Value(actor.shopId),
          idempotencyKey: Value(idempotencyKey),
          entityType: Value(loanEntityType),
          entityId: Value(loanId),
          actionType: Value(confirmLoanDisbursementActionType),
          payloadJson: Value(''), // placeholder; replaced below after due-date calc
          status: Value('pending_server_ack'),
          createdAt: Value(DateTime.now().toUtc()),
        ),
        mode: InsertMode.insertOrIgnore,
      );

      if (idempotencyClaimed == null) {
        // Same key was already claimed. Verify it is for the same action and loan.
        final existing = await (select(db.syncQueue)
              ..where((r) => r.shopId.equals(actor.shopId)
                  & r.idempotencyKey.equals(idempotencyKey)))
          .getSingleOrNull();

        if (existing == null
            || existing.actionType != confirmLoanDisbursementActionType
            || existing.entityId != loanId) {
          throw StateError(
            'Idempotency key $idempotencyKey is bound to a different operation or agreement.',
          );
        }

        // A claim without a completed disbursement is refused.
        if (current.workflowStatus != LoanWorkflowStatus.disbursed) {
          throw StateError(
            'Idempotency key $idempotencyKey was claimed but the disbursement was not completed.',
          );
        }

        // Genuine retry: return the disbursed loan state.
        return current;
      }

      // No double disbursement: enforce at the domain layer.
      current.assertDisbursementAllowed();

      // Calculate official due date from the current loan's agreed term.
      final shopEntry = await (select(db.shops)
            ..where((s) => s.id.equals(actor.shopId)))
        .getSingle();
      final shopTimeZone = ShopTimeZone(shopEntry.timezone);
      final calculator = OfficialDueDateCalculator(shopTimeZone: shopTimeZone);
      final customDate = current.customDueDate != null
          ? shopTimeZone.localDateOf(current.customDueDate!)
          : null;
      final officialDueDate = calculator.officialDueDate(
        disbursedAt: disbursedAt,
        termPresetDays: current.termPresetDays,
        customDueDate: customDate,
      );

      // Update the sync_queue payload with the calculated official due date.
      await (update(db.syncQueue)
            ..where((r) => r.id.equals(idempotencyClaimed.id)))
        .write(SyncQueueCompanion(
          payloadJson: Value(jsonEncode({
            'auditCategory': loanDisbursementAuditCategory,
            'auditEvent': 'confirmed_cash_disbursement',
            'actorId': actor.id,
            'loanId': loanId,
            'shopId': actor.shopId,
            'disbursedAt': disbursedAt.toIso8601String(),
            'officialDueDate': officialDueDate.toIso8601String(),
          })),
        ));

      // Apply the disbursement to the domain model.
      final disbursedLoan = current.withDisbursement(
        disbursedAt: disbursedAt,
        disbursedByUserId: actor.id,
        officialDueDate: officialDueDate,
      );

      // Conditional update: only succeeds if the loan is still pending
      // disbursement. This prevents concurrent double-disbursement when two
      // requests use different idempotency keys.
      final int rowsAffected = await (update(loans)
            ..where((l) =>
                (l.id.equals(loanId)) &
                (l.workflowStatus.equals(LoanWorkflowStatus.pendingDisbursement.value))))
          .write(_toCompanion(disbursedLoan));

      if (rowsAffected == 0) {
        // Another transaction won the race. Roll back all writes by throwing.
        throw LoanDisbursementStateException(
          'Loan $loanId is not awaiting disbursement '
          '(workflow status: ${current.workflowStatus.value}). '
          'Cash disbursement confirmation is refused.',
        );
      }

      return disbursedLoan;
    });
  }

  /// Cancels a pending-disbursement loan agreement (Story 4.3, AC-4).
  ///
  /// Transitions `Pending Disbursement` → `Cancelled / Cancelled`, records the
  /// cancellation timestamp and mandatory reason, and queues a Category 2
  /// audit/event record in `sync_queue`. Principal and balance are untouched.
  /// Collateral items remain in custody (no custody transition performed).
  ///
  /// Authorizes with Shop Owner administrative action. All writes occur in one
  /// database transaction; a failure rolls all writes back.
  Future<Loan> cancelLoanAgreement({
    required AppUser actor,
    required String idempotencyKey,
    required String loanId,
    required DateTime cancelledAt,
    required String cancellationReason,
  }) async {
    AuthorizationGuard.checkOwnerAdministrativeAction(
      isActive: actor.isActive,
      actorRole: actor.role,
      actionDescription: 'cancel a loan agreement',
    );

    if (idempotencyKey.trim().isEmpty) {
      throw ArgumentError.value(
        idempotencyKey,
        'idempotencyKey',
        'idempotency key cannot be blank',
      );
    }
    if (cancellationReason.trim().isEmpty) {
      throw ArgumentError.value(
        cancellationReason,
        'cancellationReason',
        'cancellation reason cannot be blank',
      );
    }

    return await db.transaction(() async {
      final current = await getLoanById(actor.shopId, loanId);
      if (current == null) {
        throw StateError('Loan $loanId not found in shop ${actor.shopId}.');
      }

      // State guard is applied after idempotency claim, so retries can return
      // the already-cancelled loan without re-running the guard.

      final idempotencyClaimed = await into(db.syncQueue).insertReturningOrNull(
        SyncQueueCompanion(
          id: Value(const Uuid().v4()),
          shopId: Value(actor.shopId),
          idempotencyKey: Value(idempotencyKey),
          entityType: Value(loanEntityType),
          entityId: Value(loanId),
          actionType: Value(cancelLoanAgreementActionType),
          payloadJson: Value(''), // placeholder; replaced below
          status: Value('pending_server_ack'),
          createdAt: Value(DateTime.now().toUtc()),
        ),
        mode: InsertMode.insertOrIgnore,
      );

      if (idempotencyClaimed == null) {
        // Same key was already claimed. Verify it is for the same action and loan.
        final existing = await (select(db.syncQueue)
              ..where((r) =>
                  r.shopId.equals(actor.shopId) &
                  r.idempotencyKey.equals(idempotencyKey)))
            .getSingleOrNull();

        if (existing == null ||
            existing.actionType != cancelLoanAgreementActionType ||
            existing.entityId != loanId) {
          throw StateError(
            'Idempotency key $idempotencyKey is bound to a different operation or agreement.',
          );
        }

        // Genuine retry: return the cancelled loan state.
        if (current.workflowStatus == LoanWorkflowStatus.cancelled) {
          return current;
        }
        throw LoanCancellationStateException(
          'Loan $loanId is not awaiting disbursement '
          '(workflow status: ${current.workflowStatus.value}). '
          'Cancellation is refused.',
        );
      }

      // State guard: only pending-disbursement agreements may be cancelled.
      current.assertCancellationAllowed();

      final cancelledLoan = current.withCancellation(
        cancelledAt: cancelledAt,
        cancellationReason: cancellationReason,
      );

      await (update(db.syncQueue)
            ..where((r) => r.id.equals(idempotencyClaimed.id)))
          .write(SyncQueueCompanion(
        payloadJson: Value(jsonEncode({
          'auditCategory': loanOriginationAuditCategory,
          'auditEvent': 'cancel_loan_agreement',
          'actorId': actor.id,
          'loanId': loanId,
          'shopId': actor.shopId,
          'cancelledAt': cancelledAt.toIso8601String(),
          'cancellationReason': cancellationReason.trim(),
          'principalCents': current.principalCents,
          'balanceCents': current.balanceCents,
        })),
      ));

      final int rowsAffected = await (update(loans)
            ..where((l) =>
                l.id.equals(loanId) &
                l.shopId.equals(actor.shopId) &
                l.workflowStatus
                    .equals(LoanWorkflowStatus.pendingDisbursement.value)))
          .write(_toCompanion(cancelledLoan));

      if (rowsAffected == 0) {
        throw LoanCancellationStateException(
          'Loan $loanId is not awaiting disbursement '
          '(workflow status: ${current.workflowStatus.value}). '
          'Cancellation is refused.',
        );
      }

      return cancelledLoan;
    });
  }
}

