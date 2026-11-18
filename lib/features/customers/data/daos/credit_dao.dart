import 'dart:convert';

import 'package:drift/drift.dart';
import '../../../../core/data/local/app_database.dart';
import '../../../../core/data/local/tables/credits_table.dart';
import '../../../../core/money/money.dart';
import '../../../../core/permissions/app_permission.dart';
import '../../../../core/permissions/authorization_guard.dart';
import '../../../auth/domain/models/app_user.dart';
import '../../domain/models/credit.dart';
import '../../domain/models/credit_term.dart';
import 'package:uuid/uuid.dart';

part 'credit_dao.g.dart';

/// Data Access Object for Credit agreements (Story 2.5).
///
/// All queries are strictly scoped to [shopId] to enforce tenant isolation.
/// A credit can only be created, read, or updated within its owning shop.
@DriftAccessor(tables: [Credits])
class CreditDao extends DatabaseAccessor<AppDatabase> with _$CreditDaoMixin {
  CreditDao(super.db);

  /// Entity type recorded in `sync_queue` for credit-related events.
  static const String creditEntityType = 'credit';

  /// Action type recorded in `sync_queue` for a credit agreement creation.
  static const String createCreditActionType = 'create_credit';

  /// Action type recorded in `sync_queue` for a disbursement confirmation.
  static const String confirmCreditDisbursementActionType =
      'confirm_credit_disbursement';

  /// PRD FR-31 audit category for a confirmed cash disbursement event.
  static const int creditDisbursementAuditCategory = 4;
  /// Action type recorded in `sync_queue` for a credit cancellation.
  /// PRD FR-31 audit category for a credit agreement origination event.
  static const int creditOriginationAuditCategory = 2;

  /// Action type recorded in `sync_queue` for a credit cancellation.
  static const String cancelCreditAgreementActionType =
      'cancel_credit_agreement';

  /// Converts a Drift [CreditEntry] row into a domain [Credit].
  Credit _toDomain(CreditEntry entry) {
    return Credit(
      id: entry.id,
      shopId: entry.shopId,
      customerId: entry.customerId,
      principalCents: entry.principalCents,
      balanceCents: entry.balanceCents,
      status: CreditStatus.fromValue(entry.status),
      workflowStatus: CreditWorkflowStatus.fromValue(entry.workflowStatus),
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
      creditType: CreditType.fromValue(entry.creditType),
    );
  }

  /// Converts a domain [Credit] into a Drift [CreditsCompanion].
  CreditsCompanion _toCompanion(Credit credit) {
    return CreditsCompanion(
      id: Value(credit.id),
      shopId: Value(credit.shopId),
      customerId: Value(credit.customerId),
      principalCents: Value(credit.principalCents),
      balanceCents: Value(credit.balanceCents),
      status: Value(credit.status.value),
      workflowStatus: Value(credit.workflowStatus.value),
      dueDate: Value(credit.dueDate),
      createdAt: Value(credit.createdAt),
      settledAt: Value(credit.settledAt),
      termPresetDays: Value(credit.termPresetDays),
      customDueDate: Value(credit.customDueDate),
      disbursedAt: Value(credit.disbursedAt),
      disbursedByUserId: Value(credit.disbursedByUserId),
      cancelledAt: Value(credit.cancelledAt),
      cancellationReason: Value(credit.cancellationReason),
      correctionPending: Value(credit.correctionPending),
      creditType: Value(credit.creditType.value),
    );
  }

  /// Inserts a new credit record into the local SQLite database.
  ///
  /// Validates that the credit belongs to [shopId] before insertion.
  /// Throws [sqlite.SqliteException] if foreign key constraints are violated
  /// (e.g., referenced customer or shop does not exist).
  Future<void> createCredit(Credit credit) async {
    if (credit.shopId.trim().isEmpty) {
      throw ArgumentError.value(credit.shopId, 'shopId', 'shopId cannot be empty');
    }
    if (credit.customerId <= 0) {
      throw ArgumentError.value(
          credit.customerId, 'customerId', 'customerId must be a positive integer');
    }
    await into(credits).insert(_toCompanion(credit));
  }

  /// Retrieves all credits for [customerId] strictly scoped within [shopId].
  ///
  /// Returns credits ordered by due date ascending.
  Future<List<Credit>> getCreditsByCustomerId(
    String shopId,
    int customerId,
  ) async {
    final query = select(credits)
      ..where((l) => l.shopId.equals(shopId) & l.customerId.equals(customerId))
      ..orderBy([(l) => OrderingTerm.asc(l.dueDate)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Retrieves all credits in [shopId] matching [status].
  ///
  /// Strictly scoped to [shopId] — credits in other shops are never returned.
  Future<List<Credit>> getCreditsByStatus(String shopId, CreditStatus status) async {
    final query = select(credits)
      ..where((l) =>
          l.shopId.equals(shopId) & l.status.equals(status.value))
      ..orderBy([(l) => OrderingTerm.asc(l.dueDate)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Retrieves all credits for [customerId] in [shopId] matching [status].
  ///
  /// Strictly scoped to [shopId] — credits in other shops are never returned.
  Future<List<Credit>> getCreditsByCustomerAndStatus(
    String shopId,
    int customerId,
    CreditStatus status,
  ) async {
    final query = select(credits)
      ..where((l) =>
          l.shopId.equals(shopId) &
          l.customerId.equals(customerId) &
          l.status.equals(status.value))
      ..orderBy([(l) => OrderingTerm.asc(l.dueDate)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Retrieves a credit by [creditId] strictly scoped within [shopId].
  ///
  /// Returns `null` if the credit does not exist or belongs to another shop.
  Future<Credit?> getCreditById(String shopId, String creditId) async {
    final query = select(credits)
      ..where((l) => l.shopId.equals(shopId) & l.id.equals(creditId));
    final entry = await query.getSingleOrNull();
    return entry != null ? _toDomain(entry) : null;
  }
  /// Reactive stream of all credits in [shopId], ordered by due date ascending.
  ///
  /// Emits the current list immediately and again whenever the credits table
  /// changes for [shopId]. Strictly scoped to [shopId].
  /// Retrieves all credits in [shopId], ordered by due date ascending.
  ///
  /// Strictly scoped to [shopId] — credits in other shops are never returned.
  Future<List<Credit>> getCreditsByShopId(String shopId) async {
    final query = select(credits)
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
    try {
      return ShopTimeZone(entry.timezone);
    } on UnsupportedShopTimeZoneException {
      return ShopTimeZone.defaultTimeZone();
    }
  }

  /// Updates the status and workflow status of a credit strictly scoped to
  /// [shopId].
  Future<void> updateCreditStatus({
    required String shopId,
    required String creditId,
    required CreditStatus status,
    required CreditWorkflowStatus workflowStatus,
  }) async {
    await (update(credits)
          ..where((l) => l.shopId.equals(shopId) & l.id.equals(creditId)))
        .write(CreditsCompanion(
      status: Value(status.value),
      workflowStatus: Value(workflowStatus.value),
    ));
  }

  Stream<List<Credit>> watchCreditsByShopId(String shopId) {
    final query = select(credits)
      ..where((l) => l.shopId.equals(shopId))
      ..orderBy([(l) => OrderingTerm.asc(l.dueDate)]);
    return query.watch().map((entries) => entries.map(_toDomain).toList());
  }
  /// Creates a credit agreement with the agreed term (Story 4.1 / Story 4.3).
  ///
  /// [collateralItemIds] may be empty: item attachment is optional, so a
  /// zero-item agreement is persisted without any item binding.
  Future<Credit> createCreditAgreement({
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
        requiredPermission: 'createCredits',
      );
    }
    AuthorizationGuard.checkPermission(
      isActive: actor.isActive,
      effectivePermissions: actor.effectivePermissions,
      permission: AppPermission.createCredits,
      actionDescription: 'create a credit agreement',
    );

    if (termPresetDays != null && customDueDate != null) {
      throw ArgumentError.value(null, 'term', 'either a preset term or a custom date, not both');
    }
    if (termPresetDays != null && !const {30, 60, 90}.contains(termPresetDays)) {
      throw ArgumentError.value(termPresetDays, 'termPresetDays', 'must be one of 30, 60, or 90 days');
    }

    if (idempotencyKey.trim().isEmpty) {
      throw ArgumentError.value(idempotencyKey, 'idempotencyKey', 'must not be blank');
    }

    if (principal.minorUnits <= 0) {
      throw ArgumentError.value(principal.minorUnits, 'principal', 'must be positive');
    }

    // Idempotent replay: if this key was already processed, return the
    // original agreement without re-running validation or writes.
    final existingQueueEarly = await (select(db.syncQueue)
          ..where((q) =>
              q.shopId.equals(actor.shopId) &
              q.idempotencyKey.equals(idempotencyKey)))
        .getSingleOrNull();
    if (existingQueueEarly != null) {
      final existingCredit = await (select(db.credits)
            ..where((l) => l.id.equals(existingQueueEarly.entityId)))
          .getSingleOrNull();
      if (existingCredit != null) {
        return _toDomain(existingCredit);
      }
    }

    final customer = await (select(db.customers)
          ..where((c) =>
              c.id.equals(customerId) & c.shopId.equals(actor.shopId)))
        .getSingleOrNull();
    if (customer == null) {
      throw StateError('Customer does not belong to the actor shop');
    }

    // Collateral is optional: an empty selection must not produce invalid
    // SQL such as `IN ()`, which SQLite rejects with a syntax error.
    final collateralRows = collateralItemIds.isEmpty
        ? []
        : await (select(db.collateralItems)
              ..where((c) =>
                  c.shopId.equals(actor.shopId) &
                  c.id.isIn(collateralItemIds)))
            .get();
    if (collateralRows.length != collateralItemIds.length) {
      throw StateError('Collateral item does not exist');
    }
    for (final row in collateralRows) {
      if (row.customerId != customerId) {
        throw StateError('Collateral item belongs to another customer');
      }
      if (row.creditId != null) {
        throw StateError('Collateral item already pledged to another credit');
      }
    }

    final shop = await (select(db.shops)..where((s) => s.id.equals(actor.shopId))).getSingle();

    return await db.transaction(() async {
      final creditId = const Uuid().v4();
      final now = DateTime.now().toUtc();

      final idempotencyClaimed = await into(db.syncQueue).insertReturningOrNull(
        SyncQueueCompanion(
          id: Value(const Uuid().v4()),
          shopId: Value(actor.shopId),
          idempotencyKey: Value(idempotencyKey),
          entityType: Value(creditEntityType),
          entityId: Value(creditId),
          actionType: Value(createCreditActionType),
          payloadJson: Value(jsonEncode({
            'auditCategory': 2,
            'auditEvent': 'credit_agreement_origination',
            'actorId': actor.id,
            'creditId': creditId,
            'customerId': customerId,
            'principalCents': principal.minorUnits,
            'currency': shop.currencyCode,
            'creditType': collateralItemIds.isEmpty ? 'cash' : 'items',
            'dueDate': dueDate.toIso8601String(),
            'createdAt': createdAt.toIso8601String(),
          })),
          status: Value('pending_server_ack'),
          createdAt: Value(now),
        ),
        mode: InsertMode.insertOrIgnore,
      );

      if (idempotencyClaimed == null) {
        final existingQueue = await (select(db.syncQueue)
              ..where((q) =>
                  q.shopId.equals(actor.shopId) &
                  q.idempotencyKey.equals(idempotencyKey)))
            .getSingleOrNull();
        if (existingQueue != null) {
          final existingCredit = await (select(db.credits)
                ..where((l) => l.id.equals(existingQueue.entityId)))
              .getSingleOrNull();
          if (existingCredit != null) {
            return _toDomain(existingCredit);
          }
        }
        throw ArgumentError.value(idempotencyKey, 'idempotencyKey', 'already exists');
      }

      final credit = Credit(
        id: creditId,
        shopId: actor.shopId,
        customerId: customerId,
        principalCents: principal.minorUnits,
        balanceCents: principal.minorUnits,
        status: CreditStatus.active,
        workflowStatus: CreditWorkflowStatus.pendingDisbursement,
        dueDate: dueDate,
        createdAt: createdAt,
        termPresetDays: termPresetDays,
        customDueDate: customDueDate,
        correctionPending: false,
        // A monetary-amount-only agreement is a cash credit; attaching one or
        // more item receipts makes it an items credit. The type is fixed at
        // origination and never reclassified afterwards.
        creditType: collateralItemIds.isEmpty
            ? CreditType.cash
            : CreditType.items,
      );

      await into(credits).insert(_toCompanion(credit));

      // Bind the pledged collateral items to the new credit agreement.
      if (collateralItemIds.isNotEmpty) {
        await (update(db.collateralItems)
              ..where((c) =>
                  c.shopId.equals(actor.shopId) &
                  c.id.isIn(collateralItemIds)))
            .write(CollateralItemsCompanion(
          creditId: Value(creditId),
          updatedAt: Value(now),
        ));
      }

      return credit;
    });
  }

  /// Confirms physical cash disbursement of an existing agreement (Story 4.3, AC-1).
  ///
  /// Transitions `Pending Disbursement` → `Disbursed`, records the confirmed
  /// cash disbursement timestamp and disbursing staff ID, finalises the
  /// official calendar due date from the agreed term, and queues a Category 4
  /// audit/event record in `sync_queue`. Never creates a credit agreement and
  /// never records a payment.
  ///
  /// Authorizes with `AppPermission.confirmCreditDisbursement`. All writes occur
  /// in one database transaction; a failure rolls all back.
  Future<Credit> confirmCreditDisbursement({
    required AppUser actor,
    required String idempotencyKey,
    required String creditId,
    required DateTime disbursedAt,
  }) async {
    if (!actor.isActive) {
      throw const PermissionDeniedException(
        'Access denied: User account is deactivated.',
        requiredPermission: 'confirmCreditDisbursement',
      );
    }
    AuthorizationGuard.checkPermission(
      isActive: actor.isActive,
      effectivePermissions: actor.effectivePermissions,
      permission: AppPermission.confirmCreditDisbursement,
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
      final current = await getCreditById(actor.shopId, creditId);
      if (current == null) {
        throw StateError('Credit $creditId not found in shop ${actor.shopId}.');
      }

      // Idempotency guard: claim the key. Null means duplicate key (same-key retry).
      final idempotencyClaimed = await into(db.syncQueue).insertReturningOrNull(
        SyncQueueCompanion(
          id: Value(const Uuid().v4()),
          shopId: Value(actor.shopId),
          idempotencyKey: Value(idempotencyKey),
          entityType: Value(creditEntityType),
          entityId: Value(creditId),
          actionType: Value(confirmCreditDisbursementActionType),
          payloadJson: Value(''), // placeholder; replaced below after due-date calc
          status: Value('pending_server_ack'),
          createdAt: Value(DateTime.now().toUtc()),
        ),
        mode: InsertMode.insertOrIgnore,
      );

      if (idempotencyClaimed == null) {
        // Same key was already claimed. Verify it is for the same action and credit.
        final existing = await (select(db.syncQueue)
              ..where((r) => r.shopId.equals(actor.shopId)
                  & r.idempotencyKey.equals(idempotencyKey)))
          .getSingleOrNull();

        if (existing == null
            || existing.actionType != confirmCreditDisbursementActionType
            || existing.entityId != creditId) {
          throw StateError(
            'Idempotency key $idempotencyKey is bound to a different operation or agreement.',
          );
        }

        // A claim without a completed disbursement is refused.
        if (current.workflowStatus != CreditWorkflowStatus.disbursed) {
          throw StateError(
            'Idempotency key $idempotencyKey was claimed but the disbursement was not completed.',
          );
        }

        // Genuine retry: return the disbursed credit state.
        return current;
      }

      // No double disbursement: enforce at the domain layer.
      current.assertDisbursementAllowed();

      // Calculate official due date from the current credit's agreed term.
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
            'auditCategory': creditDisbursementAuditCategory,
            'auditEvent': 'confirmed_cash_disbursement',
            'actorId': actor.id,
            'creditId': creditId,
            'shopId': actor.shopId,
            'disbursedAt': disbursedAt.toIso8601String(),
            'officialDueDate': shopTimeZone.localDateOf(officialDueDate).isoDate,
          })),
        ));

      // Apply the disbursement to the domain model.
      final disbursedCredit = current.withDisbursement(
        disbursedAt: disbursedAt,
        disbursedByUserId: actor.id,
        officialDueDate: officialDueDate,
      );

      // Conditional update: only succeeds if the credit is still pending
      // disbursement. This prevents concurrent double-disbursement when two
      // requests use different idempotency keys.
      final int rowsAffected = await (update(credits)
            ..where((l) =>
                (l.id.equals(creditId)) &
                (l.workflowStatus.equals(CreditWorkflowStatus.pendingDisbursement.value))))
          .write(_toCompanion(disbursedCredit));

      if (rowsAffected == 0) {
        // Another transaction won the race. Roll back all writes by throwing.
        throw CreditDisbursementStateException(
          'Credit $creditId is not awaiting disbursement '
          '(workflow status: ${current.workflowStatus.value}). '
          'Cash disbursement confirmation is refused.',
        );
      }

      return disbursedCredit;
    });
  }

  /// Cancels a pending-disbursement credit agreement (Story 4.3, AC-4).
  ///
  /// Transitions `Pending Disbursement` → `Cancelled / Cancelled`, records the
  /// cancellation timestamp and mandatory reason, and queues a Category 2
  /// audit/event record in `sync_queue`. Principal and balance are untouched.
  /// Collateral items remain in custody (no custody transition performed).
  ///
  /// Authorizes with Shop Owner administrative action. All writes occur in one
  /// database transaction; a failure rolls all writes back.
  Future<Credit> cancelCreditAgreement({
    required AppUser actor,
    required String idempotencyKey,
    required String creditId,
    required DateTime cancelledAt,
    required String cancellationReason,
  }) async {
    AuthorizationGuard.checkOwnerAdministrativeAction(
      isActive: actor.isActive,
      actorRole: actor.role,
      actionDescription: 'cancel a credit agreement',
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
      final current = await getCreditById(actor.shopId, creditId);
      if (current == null) {
        throw StateError('Credit $creditId not found in shop ${actor.shopId}.');
      }

      // State guard is applied after idempotency claim, so retries can return
      // the already-cancelled credit without re-running the guard.

      final idempotencyClaimed = await into(db.syncQueue).insertReturningOrNull(
        SyncQueueCompanion(
          id: Value(const Uuid().v4()),
          shopId: Value(actor.shopId),
          idempotencyKey: Value(idempotencyKey),
          entityType: Value(creditEntityType),
          entityId: Value(creditId),
          actionType: Value(cancelCreditAgreementActionType),
          payloadJson: Value(''), // placeholder; replaced below
          status: Value('pending_server_ack'),
          createdAt: Value(DateTime.now().toUtc()),
        ),
        mode: InsertMode.insertOrIgnore,
      );

      if (idempotencyClaimed == null) {
        // Same key was already claimed. Verify it is for the same action and credit.
        final existing = await (select(db.syncQueue)
              ..where((r) =>
                  r.shopId.equals(actor.shopId) &
                  r.idempotencyKey.equals(idempotencyKey)))
            .getSingleOrNull();

        if (existing == null ||
            existing.actionType != cancelCreditAgreementActionType ||
            existing.entityId != creditId) {
          throw StateError(
            'Idempotency key $idempotencyKey is bound to a different operation or agreement.',
          );
        }

        // Genuine retry: return the cancelled credit state.
        if (current.workflowStatus == CreditWorkflowStatus.cancelled) {
          return current;
        }
        throw CreditCancellationStateException(
          'Credit $creditId is not awaiting disbursement '
          '(workflow status: ${current.workflowStatus.value}). '
          'Cancellation is refused.',
        );
      }

      // State guard: only pending-disbursement agreements may be cancelled.
      current.assertCancellationAllowed();

      final cancelledCredit = current.withCancellation(
        cancelledAt: cancelledAt,
        cancellationReason: cancellationReason,
      );

      await (update(db.syncQueue)
            ..where((r) => r.id.equals(idempotencyClaimed.id)))
          .write(SyncQueueCompanion(
        payloadJson: Value(jsonEncode({
          'auditCategory': creditOriginationAuditCategory,
          'auditEvent': 'cancel_credit_agreement',
          'actorId': actor.id,
          'creditId': creditId,
          'shopId': actor.shopId,
          'cancelledAt': cancelledAt.toIso8601String(),
          'cancellationReason': cancellationReason.trim(),
          'principalCents': current.principalCents,
          'balanceCents': current.balanceCents,
        })),
      ));

      final int rowsAffected = await (update(credits)
            ..where((l) =>
                l.id.equals(creditId) &
                l.shopId.equals(actor.shopId) &
                l.workflowStatus
                    .equals(CreditWorkflowStatus.pendingDisbursement.value)))
          .write(_toCompanion(cancelledCredit));

      if (rowsAffected == 0) {
        throw CreditCancellationStateException(
          'Credit $creditId is not awaiting disbursement '
          '(workflow status: ${current.workflowStatus.value}). '
          'Cancellation is refused.',
        );
      }

      return cancelledCredit;
    });
  }
}


