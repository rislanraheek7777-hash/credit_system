import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';
import '../../../../core/data/local/app_database.dart';
import '../../../../core/data/local/tables/app_users_table.dart';
import '../../../../core/data/local/tables/credit_corrections_table.dart';
import '../../../../core/data/local/tables/credit_ledger_entries_table.dart';
import '../../../../core/data/local/tables/credits_table.dart';
import '../../../../core/data/local/tables/payments_table.dart';
import '../../../../core/data/local/tables/shops_table.dart';
import '../../../../core/data/local/tables/sync_queue_table.dart';
import '../../../../core/money/money.dart';
import '../../../../core/permissions/app_permission.dart';
import '../../../../core/permissions/authorization_guard.dart';
import '../../../../features/auth/domain/models/app_user.dart';
import '../../../../features/customers/domain/models/credit.dart';
import 'package:uuid/uuid.dart';

part 'correction_dao.g.dart';

/// Data Access Officer for controlled financial correction requests (Story 5.5).
///
/// All queries are strictly scoped to [shopId] to enforce tenant isolation.
/// A correction request can only be created, approved, or rejected within its
/// owning shop.
///
/// Writes use `attachedDatabase.transaction()` with `BEGIN IMMEDIATE` semantics
/// (Drift default), so the correction record, the credit lock/balance update,
/// and the local audit/sync queue entry commit or roll back together — no
/// partial state is ever visible (PRD FR-22).
///
/// The original payment record referenced by a correction is never overwritten
/// or deleted (PRD FR-23 / Story 5.5 AC-3).
///
/// NOTE (Story 5.6): For payment-correction reversals the exact meaning of
/// `correctionAmountCents` (full original payment vs. only the excess) is an
/// open accounting decision for the correction workflow. For balance
/// adjustments (Story 5.6) the `direction` column always resolves which way
/// the approved adjustment moves the balance (`debit` increases it, `credit`
/// decreases it — the partial forgiveness write-down), and an approved
/// credit-direction adjustment exceeding the outstanding balance is rejected.
@DriftAccessor(
  tables: [Credits, Payments, CreditCorrections, CreditLedgerEntries, SyncQueue, Shops, AppUsers],
)
class CorrectionDao extends DatabaseAccessor<AppDatabase>
    with _$CorrectionDaoMixin {
  CorrectionDao(super.db);

  /// `entity_type` used by the local audit/sync queue for corrections.
  static const String correctionEntityType = 'correction';

  /// `action_type` used when a correction is requested.
  static const String requestCorrectionActionType = 'request_correction';

  /// `action_type` used when a correction is approved by the Shop Owner.
  static const String approveCorrectionActionType = 'approve_correction';

  /// `action_type` used when a correction is rejected by the Shop Owner.
  static const String rejectCorrectionActionType = 'reject_correction';

  /// `entity_type` used by the local audit/sync queue for manual balance
  /// adjustments.
  static const String adjustmentEntityType = 'adjustment';

  /// `action_type` used when a Shop Owner records a manual balance adjustment.
  static const String adjustBalanceActionType = 'adjust_balance';

  /// Audit event name for manual balance adjustments (PRD FR-31, category 7).
  static const String adjustmentAuditEvent = 'adjust_balance';

  /// Audit event name for correction requests and decisions (PRD FR-31).
  static const String correctionAuditEvent = 'correction_request';

  /// Direction value: the adjustment increases the credit balance.
  static const String directionDebit = 'debit';

  /// Direction value: the adjustment decreases the credit balance (write-down).
  static const String directionCredit = 'credit';

  /// Converts a Drift [CreditCorrectionEntry] row into a domain [CreditCorrection].
  CreditCorrection _toDomain(CreditCorrectionEntry entry) {
    return CreditCorrection(
      id: entry.id,
      shopId: entry.shopId,
      creditId: entry.creditId,
      originalPaymentId: entry.originalPaymentId,
      requestedByUserId: entry.requestedByUserId,
      createdAt: entry.createdAt,
      correctionAmountCents: entry.correctionAmountCents,
      direction: entry.direction,
      reason: entry.reason,
      status: CreditCorrectionStatus.fromValue(entry.status),
      reviewedByUserId: entry.reviewedByUserId,
      reviewedAt: entry.reviewedAt,
      rejectionReason: entry.rejectionReason,
      resultingBalanceCents: entry.resultingBalanceCents,
      updatedAt: entry.updatedAt,
    );
  }

  /// Converts a Drift [CreditLedgerEntryEntry] row into a domain
  /// [CreditLedgerEntry].
  CreditLedgerEntry _toDomainLedger(CreditLedgerEntryEntry entry) {
    return CreditLedgerEntry(
      id: entry.id,
      shopId: entry.shopId,
      creditId: entry.creditId,
      originalPaymentId: entry.originalPaymentId,
      correctionId: entry.correctionId,
      entryType: CreditLedgerEntryType.fromValue(entry.entryType),
      amountCents: entry.amountCents,
      preBalanceCents: entry.preBalanceCents,
      postBalanceCents: entry.postBalanceCents,
      reason: entry.reason,
      recordedByUserId: entry.recordedByUserId,
      recordedAt: entry.recordedAt,
      createdAt: entry.createdAt,
    );
  }

  /// Submits a correction request for a payment on [creditId].
  ///
  /// Steps:
  /// 1. Authorization: actor must be active and hold `requestCorrections`.
  /// 2. Input validation: idempotency key, credit id, amount and reason must be
  ///    present; amount must be positive.
  /// 3. Eligibility: the credit must exist in the actor's shop and must not
  ///    already have a pending correction (the correction lock).
  /// 4. Atomic transaction:
  ///    a. Insert idempotency guard row in `sync_queue` (unique constraint on
  ///       `(shop_id, idempotency_key)` prevents duplicates).
  ///    b. Set `correctionPending = true` on the credit (activates the lock).
  ///    c. Insert the `pending_approval` correction row.
  ///    d. Insert the local audit/sync queue entry.
  ///
  /// Returns the requested [CreditCorrection].
  ///
  /// Throws [PermissionDeniedException] when the actor is deactivated or does
  /// not hold `requestCorrections`.
  /// Throws [ArgumentError] when [idempotencyKey], [creditId], [reason] is
  /// blank, [amount] is not positive, or [direction] is not 'debit' or
  /// 'credit'. For a `credit`-direction proposal, [StateError] is also thrown
  /// when [amount] exceeds the outstanding balance.
  /// Throws [StateError] when the credit does not exist in the actor's shop or
  /// when a correction is already pending for that credit.
  Future<CreditCorrection> requestCorrection({
    required AppUser actor,
    required String idempotencyKey,
    required String creditId,
    required String? originalPaymentId,
    required Money amount,
    required String reason,
    required DateTime requestedAt,
    String direction = directionDebit,
  }) async {
    // --- Authorization: require an active user with requestCorrections ---
    if (!actor.isActive) {
      throw const PermissionDeniedException(
        'Access denied: User account is deactivated.',
      );
    }
    AuthorizationGuard.checkPermission(
      isActive: actor.isActive,
      effectivePermissions: actor.effectivePermissions,
      permission: AppPermission.requestCorrections,
      actionDescription: 'request a credit correction',
    );

    // --- Input validation ---
    final key = idempotencyKey.trim();
    if (key.isEmpty) {
      throw ArgumentError.value(
        idempotencyKey,
        'idempotencyKey',
        'idempotencyKey cannot be empty',
      );
    }
    if (creditId.trim().isEmpty) {
      throw ArgumentError.value(
        creditId,
        'creditId',
        'creditId cannot be empty',
      );
    }
    if (amount.minorUnits <= 0) {
      throw ArgumentError.value(
        amount.minorUnits,
        'amount',
        'Correction amount must be a positive value in minor units',
      );
    }
    if (direction != directionDebit && direction != directionCredit) {
      throw ArgumentError.value(
        direction,
        'direction',
        "direction must be 'debit' or 'credit'",
      );
    }
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw ArgumentError.value(
        reason,
        'reason',
        'A mandatory business explanation is required for a correction request',
      );
    }

    // --- Idempotency fast path ---
    final claimed = await _findIdempotencyClaim(actor.shopId, key);
    if (claimed != null) {
      return _resolveRecordedCorrection(
        shopId: actor.shopId,
        idempotencyKey: key,
        claim: claimed,
      );
    }

    // --- The credit must exist in the actor's own shop ---
    final credit = await creditDaoGetById(actor.shopId, creditId);
    if (credit == null) {
      throw StateError(
        'Cannot request correction: credit ID "$creditId" not found in shop '
        '"${actor.shopId}".',
      );
    }

    // --- A credit-direction adjustment exceeding the outstanding balance is
    //     rejected up front (no negative balances). ---
    if (direction == directionCredit &&
        amount.minorUnits > credit.balanceCents) {
      throw StateError(
        'Cannot request adjustment: the credit-direction amount of '
        '${amount.minorUnits} minor units exceeds the outstanding balance of '
        'credit ID "$creditId".',
      );
    }

    // --- A correction must not already be pending for this credit ---
    if (credit.correctionPending) {
      throw StateError(
        'Cannot request correction: credit ID "$creditId" already has a pending '
        'correction request. Payments are blocked until the existing request '
        'is approved or rejected.',
      );
    }

    // --- Original payment, when supplied, must belong to this credit/shop ---
    if (originalPaymentId != null && originalPaymentId.isNotEmpty) {
      final payment = await (select(payments)
            ..where((p) =>
                p.shopId.equals(actor.shopId) &
                p.id.equals(originalPaymentId) &
                p.creditId.equals(creditId)))
          .getSingleOrNull();
      if (payment == null) {
        throw StateError(
          'Cannot request correction: payment ID "$originalPaymentId" not '
          'found for credit ID "$creditId" in shop "${actor.shopId}".',
        );
      }
    }

    final now = requestedAt.toUtc();
    final correctionId = const Uuid().v4();
    var duplicated = false;

    await attachedDatabase.transaction(() async {
      // --- Re-read the credit inside the transaction to detect concurrent
      //     corrections/payments that changed the lock state. ---
      final currentCredit = await creditDaoGetById(actor.shopId, creditId);
      if (currentCredit == null) {
        throw StateError(
          'Cannot request correction: credit ID "$creditId" not found in shop '
          '"${actor.shopId}".',
        );
      }
      if (currentCredit.correctionPending) {
        throw StateError(
          'Cannot request correction: credit ID "$creditId" already has a pending '
          'correction request.',
        );
      }

      // --- Idempotency guard row (written first so concurrent submissions
      //     with the same key cannot produce a second correction) ---
      final guard = await into(syncQueue).insertReturningOrNull(
        SyncQueueCompanion.insert(
          id: const Uuid().v4(),
          shopId: actor.shopId,
          idempotencyKey: key,
          entityType: correctionEntityType,
          entityId: correctionId,
          actionType: requestCorrectionActionType,
          payloadJson: jsonEncode({
            'auditCategory': 6,
            'auditEvent': correctionAuditEvent,
            'actorId': actor.id,
            'creditId': creditId,
            'originalPaymentId': originalPaymentId,
            'amountCents': amount.minorUnits,
            'direction': direction,
            'reason': cleanReason,
            'requestedAt': now.toIso8601String(),
            'shopId': actor.shopId,
          }),
          createdAt: now,
          updatedAt: Value(now),
        ),
        mode: InsertMode.insertOrIgnore,
      );

      if (guard == null) {
        duplicated = true;
        return;
      }

      // --- Activate the correction lock on the credit ---
      final affected = await (update(credits)
            ..where((l) =>
                l.shopId.equals(actor.shopId) &
                l.id.equals(creditId) &
                l.correctionPending.equals(false)))
          .write(CreditsCompanion(
        correctionPending: Value(true),
      ));

      if (affected == 0) {
        // Another writer modified the credit first. Roll back this transaction.
        throw StateError(
          'Unable to request correction: the credit state changed concurrently '
          'for credit ID "$creditId".',
        );
      }

      // --- Insert the correction request row ---
      await into(creditCorrections).insert(
        CreditCorrectionsCompanion.insert(
          id: correctionId,
          shopId: actor.shopId,
          creditId: creditId,
          originalPaymentId: Value(originalPaymentId),
          requestedByUserId: actor.id,
          correctionAmountCents: amount.minorUnits,
          direction: Value(direction),
          reason: cleanReason,
          status: Value('pending_approval'),
          reviewedByUserId: const Value.absent(),
          reviewedAt: const Value.absent(),
          rejectionReason: const Value.absent(),
          resultingBalanceCents: const Value.absent(),
          createdAt: now,
          updatedAt: now,
        ),
      );

      // --- Local audit/sync queue entry ---
      await into(syncQueue).insert(
        SyncQueueCompanion.insert(
          id: const Uuid().v4(),
          shopId: actor.shopId,
          idempotencyKey: const Uuid().v4(),
          entityType: correctionEntityType,
          entityId: correctionId,
          actionType: requestCorrectionActionType,
          payloadJson: jsonEncode({
            'auditCategory': 6,
            'auditEvent': correctionAuditEvent,
            'actorId': actor.id,
            'creditId': creditId,
            'originalPaymentId': originalPaymentId,
            'amountCents': amount.minorUnits,
            'direction': direction,
            'reason': cleanReason,
            'requestedAt': now.toIso8601String(),
            'shopId': actor.shopId,
          }),
          createdAt: now,
          updatedAt: Value(now),
        ),
      );
    });

    if (duplicated) {
      return _resolveRecordedCorrection(
        shopId: actor.shopId,
        idempotencyKey: key,
      );
    }

    final created = await getCorrectionById(actor.shopId, correctionId);
    if (created == null) {
      throw StateError('Failed to retrieve newly created correction $correctionId.');
    }
    return created;
  }

  /// Approves a pending correction request (Shop Owner only).
  ///
  /// Steps:
  /// 1. Authorization: actor must be an active Shop Owner.
  /// 2. Eligibility: the correction must exist in the actor's shop, belong to
  ///    a credit in that shop, and be in `pending_approval` status.
  /// 3. Atomic transaction:
  ///    a. Insert idempotency guard row in `sync_queue`.
  ///    b. Conditionally transition the correction to `approved` (WHERE status
  ///       = 'pending_approval'), recording the reviewer, decision timestamp
  ///       and resulting balance snapshot.
  ///    c. Lift the correction lock and apply the balance adjustment on the
  ///       credit (`balanceCents += correctionAmountCents` for `debit`,
  ///       `balanceCents -= correctionAmountCents` for `credit`).
  ///    d. Insert the local audit/sync queue entry.
  ///
  /// Rejection of a duplicate/already-decided request is refused with
  /// [StateError] so a correction cannot be approved twice.
  ///
  /// Direction-aware balance arithmetic (Story 5.6):
  /// `debit` adds [correctionAmountCents] to the credit balance; `credit`
  /// subtracts it (the partial forgiveness write-down). An approved
  /// credit-direction adjustment exceeding the outstanding balance is rejected
  /// with [StateError], so the credit never carries a negative balance.
  ///
  /// Returns the approved [CreditCorrection].
  ///
  /// Throws [PermissionDeniedException] when the actor is not an active
  /// Shop Owner.
  /// Throws [ArgumentError] when [idempotencyKey] or [correctionId] is blank.
  /// Throws [StateError] when the correction does not exist in the actor's
  /// shop, is not pending, or has already been decided.
  Future<CreditCorrection> approveCorrection({
    required AppUser actor,
    required String idempotencyKey,
    required String correctionId,
    required DateTime reviewedAt,
  }) async {
    // --- Authorization: require an active Shop Owner ---
    if (!actor.isActive) {
      throw const PermissionDeniedException(
        'Access denied: User account is deactivated.',
      );
    }
    AuthorizationGuard.checkOwnerAdministrativeAction(
      isActive: actor.isActive,
      actorRole: actor.role,
      actionDescription: 'approve a correction request',
    );

    // --- Input validation ---
    final key = idempotencyKey.trim();
    if (key.isEmpty) {
      throw ArgumentError.value(
        idempotencyKey,
        'idempotencyKey',
        'idempotencyKey cannot be empty',
      );
    }
    if (correctionId.trim().isEmpty) {
      throw ArgumentError.value(
        correctionId,
        'correctionId',
        'correctionId cannot be empty',
      );
    }

    // --- Idempotency fast path ---
    final claimed = await _findIdempotencyClaim(actor.shopId, key);
    if (claimed != null) {
      return _resolveRecordedCorrection(
        shopId: actor.shopId,
        idempotencyKey: key,
        claim: claimed,
      );
    }

    final now = reviewedAt.toUtc();
    var duplicated = false;

    await attachedDatabase.transaction(() async {
      // --- The correction must exist in the actor's own shop and be pending ---
      final correction = await (select(creditCorrections)
            ..where((c) =>
                c.shopId.equals(actor.shopId) &
                c.id.equals(correctionId) &
                c.status.equals('pending_approval')))
          .getSingleOrNull();
      if (correction == null) {
        final existing = await (select(creditCorrections)
              ..where((c) =>
                  c.shopId.equals(actor.shopId) & c.id.equals(correctionId)))
            .getSingleOrNull();
        if (existing == null) {
          throw StateError(
            'Cannot approve correction: correction ID "$correctionId" not '
            'found in shop "${actor.shopId}".',
          );
        }
        throw StateError(
          'Cannot approve correction: correction ID "$correctionId" is not '
          'pending (current status: ${existing.status}).',
        );
      }

      // --- Idempotency guard row ---
      final guard = await into(syncQueue).insertReturningOrNull(
        SyncQueueCompanion.insert(
          id: const Uuid().v4(),
          shopId: actor.shopId,
          idempotencyKey: key,
          entityType: correctionEntityType,
          entityId: correctionId,
          actionType: approveCorrectionActionType,
          payloadJson: jsonEncode({
            'auditCategory': 7,
            'auditEvent': correctionAuditEvent,
            'action': 'approve',
            'actorId': actor.id,
            'correctionId': correctionId,
            'creditId': correction.creditId,
            'amountCents': correction.correctionAmountCents,
            'reviewedAt': now.toIso8601String(),
            'shopId': actor.shopId,
          }),
          createdAt: now,
          updatedAt: Value(now),
        ),
        mode: InsertMode.insertOrIgnore,
      );

      if (guard == null) {
        duplicated = true;
        return;
      }

      // --- Load the credit inside the transaction ---
      final credit = await creditDaoGetById(actor.shopId, correction.creditId);
      if (credit == null) {
        throw StateError(
          'Cannot approve correction: credit ID "${correction.creditId}" not '
          'found in shop "${actor.shopId}".',
        );
      }

      final isAdjustmentProposal = correction.originalPaymentId == null;
      final adjustmentDelta = correction.direction == directionCredit
          ? -correction.correctionAmountCents
          : correction.correctionAmountCents;
      final newBalanceCents = credit.balanceCents + adjustmentDelta;
      if (newBalanceCents < 0) {
        throw StateError(
          'Cannot approve adjustment: the credit-direction amount of '
          '${correction.correctionAmountCents} minor units exceeds the '
          'outstanding balance of credit ID "${correction.creditId}".',
        );
      }

      // --- Record the immutable ledger entry ---
      //
      // PRD FR-22: an approved reversal records "a linked compensating debit
      // transaction" while "the original payment transaction is permanently
      // preserved without modification or deletion." This entry is the
      // immutable financial record of the reversal; it posts within the same
      // transaction as the credit balance, correction record, lock lift, and
      // sync journal so none of them can diverge on failure.
      //
      // Story 5.6: an adjustment proposal (no original payment) posts
      // `adjustment_credit` (forgiveness) or `adjustment_debit` instead of
      // `compensating_debit`.
      final entryType = isAdjustmentProposal
          ? (correction.direction == directionCredit
              ? 'adjustment_credit'
              : 'adjustment_debit')
          : 'compensating_debit';
      await into(creditLedgerEntries).insert(
        CreditLedgerEntriesCompanion.insert(
          id: const Uuid().v4(),
          shopId: actor.shopId,
          creditId: correction.creditId,
          originalPaymentId: Value(correction.originalPaymentId),
          correctionId: Value(correctionId),
          entryType: entryType,
          amountCents: correction.correctionAmountCents,
          preBalanceCents: credit.balanceCents,
          postBalanceCents: newBalanceCents,
          reason: correction.reason,
          recordedByUserId: actor.id,
          recordedAt: now,
          createdAt: now,
        ),
      );

      // --- Conditionally approve the correction (only if still pending) ---
      final correctedAffected = await (update(creditCorrections)
            ..where((c) =>
                c.shopId.equals(actor.shopId) &
                c.id.equals(correctionId) &
                c.status.equals('pending_approval')))
          .write(CreditCorrectionsCompanion(
        status: Value('approved'),
        reviewedByUserId: Value(actor.id),
        reviewedAt: Value(now),
        rejectionReason: const Value.absent(),
        resultingBalanceCents: Value(newBalanceCents),
        updatedAt: Value(now),
      ));

      if (correctedAffected == 0) {
        // Another writer decided this correction first. Roll back.
        throw StateError(
          'Cannot approve correction: correction ID "$correctionId" was '
          'already decided by a concurrent request.',
        );
      }

      // --- Lift the correction lock and apply the balance adjustment ---
      final creditAffected = await (update(credits)
            ..where((l) =>
                l.shopId.equals(actor.shopId) &
                l.id.equals(correction.creditId) &
                l.correctionPending.equals(true)))
          .write(CreditsCompanion(
        balanceCents: Value(newBalanceCents),
        correctionPending: Value(false),
      ));

      if (creditAffected == 0) {
        // The lock was already lifted by a concurrent writer. Roll back the
        // correction approval to keep state consistent.
        throw StateError(
          'Cannot approve correction: the correction lock on credit ID '
          '"${correction.creditId}" was already lifted concurrently.',
        );
      }

      // --- Local audit/sync queue entry ---
      await into(syncQueue).insert(
        SyncQueueCompanion.insert(
          id: const Uuid().v4(),
          shopId: actor.shopId,
          idempotencyKey: const Uuid().v4(),
          entityType: correctionEntityType,
          entityId: correctionId,
          actionType: approveCorrectionActionType,
          payloadJson: jsonEncode({
            'auditCategory': 7,
            'auditEvent': correctionAuditEvent,
            'action': 'approve',
            'actorId': actor.id,
            'correctionId': correctionId,
            'creditId': correction.creditId,
            'amountCents': correction.correctionAmountCents,
            'direction': correction.direction,
            'previousBalanceCents': credit.balanceCents,
            'newBalanceCents': newBalanceCents,
            'reviewedAt': now.toIso8601String(),
            'shopId': actor.shopId,
          }),
          createdAt: now,
          updatedAt: Value(now),
        ),
      );
    });

    if (duplicated) {
      return _resolveRecordedCorrection(
        shopId: actor.shopId,
        idempotencyKey: key,
      );
    }

    final approved = await getCorrectionById(actor.shopId, correctionId);
    if (approved == null) {
      throw StateError('Failed to retrieve approved correction $correctionId.');
    }
    return approved;
  }

  /// Rejects a pending correction request (Shop Owner only).
  ///
  /// Steps:
  /// 1. Authorization: actor must be an active Shop Owner.
  /// 2. Eligibility: the correction must exist in the actor's shop, belong to
  ///    a credit in that shop, and be in `pending_approval` status.
  /// 3. Atomic transaction:
  ///    a. Insert idempotency guard row in `sync_queue`.
  ///    b. Conditionally transition the correction to `rejected`, recording the
  ///       mandatory rejection reason, reviewer and decision timestamp.
  ///    c. Lift the correction lock on the credit. The credit balance is NOT
  ///       altered.
  ///    d. Insert the local audit/sync queue entry.
  ///
  /// Returns the rejected [CreditCorrection].
  ///
  /// Throws [PermissionDeniedException] when the actor is not an active
  /// Shop Owner.
  /// Throws [ArgumentError] when [idempotencyKey], [correctionId] or
  /// [rejectionReason] is blank.
  /// Throws [StateError] when the correction does not exist in the actor's
  /// shop, is not pending, or has already been decided.
  Future<CreditCorrection> rejectCorrection({
    required AppUser actor,
    required String idempotencyKey,
    required String correctionId,
    required String rejectionReason,
    required DateTime reviewedAt,
  }) async {
    // --- Authorization: require an active Shop Owner ---
    if (!actor.isActive) {
      throw const PermissionDeniedException(
        'Access denied: User account is deactivated.',
      );
    }
    AuthorizationGuard.checkOwnerAdministrativeAction(
      isActive: actor.isActive,
      actorRole: actor.role,
      actionDescription: 'reject a correction request',
    );

    // --- Input validation ---
    final key = idempotencyKey.trim();
    if (key.isEmpty) {
      throw ArgumentError.value(
        idempotencyKey,
        'idempotencyKey',
        'idempotencyKey cannot be empty',
      );
    }
    if (correctionId.trim().isEmpty) {
      throw ArgumentError.value(
        correctionId,
        'correctionId',
        'correctionId cannot be empty',
      );
    }
    final cleanRejectionReason = rejectionReason.trim();
    if (cleanRejectionReason.isEmpty) {
      throw ArgumentError.value(
        rejectionReason,
        'rejectionReason',
        'A mandatory rejection reason is required',
      );
    }

    // --- Idempotency fast path ---
    final claimed = await _findIdempotencyClaim(actor.shopId, key);
    if (claimed != null) {
      return _resolveRecordedCorrection(
        shopId: actor.shopId,
        idempotencyKey: key,
        claim: claimed,
      );
    }

    final now = reviewedAt.toUtc();
    var duplicated = false;

    await attachedDatabase.transaction(() async {
      // --- The correction must exist in the actor's own shop and be pending ---
      final correction = await (select(creditCorrections)
            ..where((c) =>
                c.shopId.equals(actor.shopId) &
                c.id.equals(correctionId) &
                c.status.equals('pending_approval')))
          .getSingleOrNull();
      if (correction == null) {
        final existing = await (select(creditCorrections)
              ..where((c) =>
                  c.shopId.equals(actor.shopId) & c.id.equals(correctionId)))
            .getSingleOrNull();
        if (existing == null) {
          throw StateError(
            'Cannot reject correction: correction ID "$correctionId" not '
            'found in shop "${actor.shopId}".',
          );
        }
        throw StateError(
          'Cannot reject correction: correction ID "$correctionId" is not '
          'pending (current status: ${existing.status}).',
        );
      }

      // --- Idempotency guard row ---
      final guard = await into(syncQueue).insertReturningOrNull(
        SyncQueueCompanion.insert(
          id: const Uuid().v4(),
          shopId: actor.shopId,
          idempotencyKey: key,
          entityType: correctionEntityType,
          entityId: correctionId,
          actionType: rejectCorrectionActionType,
          payloadJson: jsonEncode({
            'auditCategory': 7,
            'auditEvent': correctionAuditEvent,
            'action': 'reject',
            'actorId': actor.id,
            'correctionId': correctionId,
            'creditId': correction.creditId,
            'amountCents': correction.correctionAmountCents,
            'direction': correction.direction,
            'rejectionReason': cleanRejectionReason,
            'reviewedAt': now.toIso8601String(),
            'shopId': actor.shopId,
          }),
          createdAt: now,
          updatedAt: Value(now),
        ),
        mode: InsertMode.insertOrIgnore,
      );

      if (guard == null) {
        duplicated = true;
        return;
      }

      // --- Conditionally reject the correction (only if still pending) ---
      final rejectedAffected = await (update(creditCorrections)
            ..where((c) =>
                c.shopId.equals(actor.shopId) &
                c.id.equals(correctionId) &
                c.status.equals('pending_approval')))
          .write(CreditCorrectionsCompanion(
        status: Value('rejected'),
        reviewedByUserId: Value(actor.id),
        reviewedAt: Value(now),
        rejectionReason: Value(cleanRejectionReason),
        resultingBalanceCents: const Value.absent(),
        updatedAt: Value(now),
      ));

      if (rejectedAffected == 0) {
        throw StateError(
          'Cannot reject correction: correction ID "$correctionId" was '
          'already decided by a concurrent request.',
        );
      }

      // --- Lift the correction lock. Balance is intentionally unchanged. ---
      final creditAffected = await (update(credits)
            ..where((l) =>
                l.shopId.equals(actor.shopId) &
                l.id.equals(correction.creditId) &
                l.correctionPending.equals(true)))
          .write(CreditsCompanion(
        correctionPending: Value(false),
      ));

      if (creditAffected == 0) {
        throw StateError(
          'Cannot reject correction: the correction lock on credit ID '
          '"${correction.creditId}" was already lifted concurrently.',
        );
      }

      // --- Local audit/sync queue entry ---
      await into(syncQueue).insert(
        SyncQueueCompanion.insert(
          id: const Uuid().v4(),
          shopId: actor.shopId,
          idempotencyKey: const Uuid().v4(),
          entityType: correctionEntityType,
          entityId: correctionId,
          actionType: rejectCorrectionActionType,
          payloadJson: jsonEncode({
            'auditCategory': 7,
            'auditEvent': correctionAuditEvent,
            'action': 'reject',
            'actorId': actor.id,
            'correctionId': correctionId,
            'creditId': correction.creditId,
            'amountCents': correction.correctionAmountCents,
            'direction': correction.direction,
            'rejectionReason': cleanRejectionReason,
            'reviewedAt': now.toIso8601String(),
            'shopId': actor.shopId,
          }),
          createdAt: now,
          updatedAt: Value(now),
        ),
      );
    });

    if (duplicated) {
      return _resolveRecordedCorrection(
        shopId: actor.shopId,
        idempotencyKey: key,
      );
    }

    final rejected = await getCorrectionById(actor.shopId, correctionId);
    if (rejected == null) {
      throw StateError('Failed to retrieve rejected correction $correctionId.');
    }
    return rejected;
  }

  /// Records a Shop Owner manual balance adjustment (debit or credit) on [creditId].
  ///
  /// PRD FR-22: manual balance adjustments are controlled, immutable ledger
  /// entries linked to the credit. A debit increases the outstanding balance;
  /// a credit decreases it. The original payment history is never altered.
  ///
  /// Steps:
  /// 1. Authorization: actor must be an active Shop Owner.
  /// 2. Input validation: idempotency key, credit id, amount and reason must be
  ///    present; amount must be positive; adjustment type must be a manual
  ///    adjustment (not `compensating_debit`).
  /// 3. Eligibility: the credit must exist in the actor's shop and must not
  ///    have a pending correction (the Story 5.3/5.5 correction lock blocks
  ///    balance-changing transactions against an unverified balance).
  /// 4. Atomic transaction:
  ///    a. Insert idempotency guard row in `sync_queue` (unique constraint on
  ///       `(shop_id, idempotency_key)` prevents duplicates).
  ///    b. Insert the immutable ledger entry (`adjustment_debit` or
  ///       `adjustment_credit`) with pre/post balance snapshot.
  ///    c. Conditionally update the credit balance (WHERE correction_pending =
  ///       false).
  ///    d. Insert the local audit/sync queue entry.
  ///
  /// Returns the created [CreditLedgerEntry].
  ///
  /// Throws [PermissionDeniedException] when the actor is deactivated or is
  /// not a Shop Owner.
  /// Throws [ArgumentError] when [idempotencyKey], [creditId] or [reason] is
  /// blank, when [amount] is not positive, or when [adjustmentType] is
  /// `compensating_debit`.
  /// Throws [StateError] when the credit does not exist in the actor's shop,
  /// when a correction is pending on the credit, when a credit would make the
  /// balance negative, or when the credit state changed concurrently.
  Future<CreditLedgerEntry> adjustBalance({
    required AppUser actor,
    required String idempotencyKey,
    required String creditId,
    required Money amount,
    required CreditLedgerEntryType adjustmentType,
    required String reason,
    required DateTime recordedAt,
  }) async {
    // --- Authorization: require an active Shop Owner ---
    if (!actor.isActive) {
      throw const PermissionDeniedException(
        'Access denied: User account is deactivated.',
      );
    }
    AuthorizationGuard.checkOwnerAdministrativeAction(
      isActive: actor.isActive,
      actorRole: actor.role,
      actionDescription: 'adjust a credit balance',
    );

    // --- Input validation ---
    final key = idempotencyKey.trim();
    if (key.isEmpty) {
      throw ArgumentError.value(
        idempotencyKey,
        'idempotencyKey',
        'idempotencyKey cannot be empty',
      );
    }
    if (creditId.trim().isEmpty) {
      throw ArgumentError.value(
        creditId,
        'creditId',
        'creditId cannot be empty',
      );
    }
    if (amount.minorUnits <= 0) {
      throw ArgumentError.value(
        amount.minorUnits,
        'amount',
        'Adjustment amount must be a positive value in minor units',
      );
    }
    // Manual adjustments use adjustment_debit / adjustment_credit only;
    // compensating_debit is reserved for approved corrections.
    if (adjustmentType == CreditLedgerEntryType.compensatingDebit) {
      throw ArgumentError.value(
        adjustmentType,
        'adjustmentType',
        'compensating_debit is reserved for approved corrections; use '
            'requestCorrection/approveCorrection instead.',
      );
    }
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw ArgumentError.value(
        reason,
        'reason',
        'A mandatory business rationale is required for a balance adjustment',
      );
    }

    // --- Idempotency fast path ---
    final claimed = await _findIdempotencyClaim(actor.shopId, key);
    if (claimed != null) {
      return _resolveRecordedAdjustment(
        shopId: actor.shopId,
        idempotencyKey: key,
        claim: claimed,
      );
    }

    final now = recordedAt.toUtc();
    var duplicated = false;
    final adjustmentId = const Uuid().v4();

    await attachedDatabase.transaction(() async {
      // --- The credit must exist in the actor's own shop ---
      final credit = await creditDaoGetById(actor.shopId, creditId);
      if (credit == null) {
        throw StateError(
          'Cannot adjust balance: credit ID "$creditId" not found in shop '
          '"${actor.shopId}".',
        );
      }

      // --- Story 5.3 / 5.5 correction lock: while a correction is pending,
      //     balance adjustments are blocked against the unverified balance. ---
      if (credit.correctionPending) {
        throw StateError(
          'Cannot adjust balance: credit ID "$creditId" has a pending correction '
          'request. Balance adjustments are blocked until the correction is '
          'approved or rejected.',
        );
      }

      // --- Compute the new balance based on adjustment type ---
      int newBalanceCents;
      switch (adjustmentType) {
        case CreditLedgerEntryType.adjustmentDebit:
          newBalanceCents = credit.balanceCents + amount.minorUnits;
          break;
        case CreditLedgerEntryType.adjustmentCredit:
          newBalanceCents = credit.balanceCents - amount.minorUnits;
          if (newBalanceCents < 0) {
            throw StateError(
              'Cannot adjust balance: credit of ${amount.minorUnits} would '
              'make the balance of credit ID "$creditId" negative '
              '(current balance: ${credit.balanceCents}).',
            );
          }
          break;
        case CreditLedgerEntryType.compensatingDebit:
          // Unreachable: rejected above, but keep the switch exhaustive.
          throw ArgumentError.value(
            adjustmentType,
            'adjustmentType',
            'Unsupported adjustment type.',
          );
      }

      // --- Idempotency guard row ---
      final guard = await into(syncQueue).insertReturningOrNull(
        SyncQueueCompanion.insert(
          id: const Uuid().v4(),
          shopId: actor.shopId,
          idempotencyKey: key,
          entityType: adjustmentEntityType,
          entityId: creditId,
          actionType: adjustBalanceActionType,
          payloadJson: jsonEncode({
            'auditCategory': 7,
            'auditEvent': adjustmentAuditEvent,
            'action': 'adjust_balance',
            'actorId': actor.id,
            'creditId': creditId,
            'adjustmentType': adjustmentType.value,
            'amountCents': amount.minorUnits,
            'reason': cleanReason,
            'recordedAt': now.toIso8601String(),
            'shopId': actor.shopId,
          }),
          createdAt: now,
          updatedAt: Value(now),
        ),
        mode: InsertMode.insertOrIgnore,
      );

      if (guard == null) {
        // Another submission with the same idempotency key already claimed it.
        duplicated = true;
        return;
      }

      // --- Record the immutable ledger entry ---
      await into(creditLedgerEntries).insert(
        CreditLedgerEntriesCompanion.insert(
          id: adjustmentId,
          shopId: actor.shopId,
          creditId: creditId,
          originalPaymentId: const Value.absent(),
          correctionId: const Value.absent(),
          entryType: adjustmentType.value,
          amountCents: amount.minorUnits,
          preBalanceCents: credit.balanceCents,
          postBalanceCents: newBalanceCents,
          reason: cleanReason,
          recordedByUserId: actor.id,
          recordedAt: now,
          createdAt: now,
        ),
      );

      // --- Conditionally update the credit balance ---
      final affected = await (update(credits)
            ..where((l) =>
                l.shopId.equals(actor.shopId) &
                l.id.equals(creditId) &
                l.correctionPending.equals(false)))
        .write(CreditsCompanion(
      balanceCents: Value(newBalanceCents),
    ));

      if (affected == 0) {
        // Another writer modified the credit first. Roll back this transaction.
        throw StateError(
          'Unable to adjust balance: the credit state changed concurrently '
          'for credit ID "$creditId".',
        );
      }

      // --- Local audit/sync queue entry ---
      await into(syncQueue).insert(
        SyncQueueCompanion.insert(
          id: const Uuid().v4(),
          shopId: actor.shopId,
          idempotencyKey: const Uuid().v4(),
          entityType: adjustmentEntityType,
          entityId: adjustmentId,
          actionType: adjustBalanceActionType,
          payloadJson: jsonEncode({
            'auditCategory': 7,
            'auditEvent': adjustmentAuditEvent,
            'action': 'adjust_balance',
            'actorId': actor.id,
            'creditId': creditId,
            'adjustmentType': adjustmentType.value,
            'amountCents': amount.minorUnits,
            'previousBalanceCents': credit.balanceCents,
            'newBalanceCents': newBalanceCents,
            'recordedAt': now.toIso8601String(),
            'shopId': actor.shopId,
          }),
          createdAt: now,
          updatedAt: Value(now),
        ),
      );
    });

    if (duplicated) {
      return _resolveRecordedAdjustment(
        shopId: actor.shopId,
        idempotencyKey: key,
      );
    }

    final created = await getLedgerEntryById(actor.shopId, adjustmentId);
    if (created == null) {
      throw StateError('Failed to retrieve newly created ledger entry $adjustmentId.');
    }
    return created;
  }

  /// Retrieves a ledger entry by id strictly scoped within [shopId].
  Future<CreditLedgerEntry?> getLedgerEntryById(
    String shopId,
    String ledgerEntryId,
  ) async {
    final entry = await (select(creditLedgerEntries)
          ..where((e) =>
              e.shopId.equals(shopId) & e.id.equals(ledgerEntryId)))
        .getSingleOrNull();
    return entry != null ? _toDomainLedger(entry) : null;
  }

  /// Retrieves all ledger entries for a credit strictly scoped within [shopId].
  Future<List<CreditLedgerEntry>> getLedgerEntriesByCredit(
    String shopId,
    String creditId, {
    int? limit,
  }) async {
    final query = select(creditLedgerEntries)
      ..where((e) => e.shopId.equals(shopId) & e.creditId.equals(creditId))
      ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]);
    if (limit != null) {
      query.limit(limit);
    }
    final entries = await query.get();
    return entries.map(_toDomainLedger).toList(growable: false);
  }

  /// Resolves the outcome of a balance adjustment already recorded under
  /// [idempotencyKey].
  Future<CreditLedgerEntry> _resolveRecordedAdjustment({
    required String shopId,
    required String idempotencyKey,
    SyncQueueRecord? claim,
  }) async {
    final claimed =
        claim ?? await _findIdempotencyClaim(shopId, idempotencyKey);

    if (claimed == null ||
        claimed.entityType != adjustmentEntityType ||
        claimed.actionType != adjustBalanceActionType) {
      throw StateError(
        'Idempotency key "$idempotencyKey" is already in use by another '
        'operation.',
      );
    }

    // Reconstruct the adjustment fingerprint from the queued payload so the
    // existing ledger entry created for this intent can be located exactly.
    final payload = jsonDecode(claimed.payloadJson) as Map<dynamic, dynamic>;
    final entryType = payload['adjustmentType'] as String?;
    final amountCents = payload['amountCents'] as int?;
    final recordedByUserId = payload['actorId'] as String?;
    final reason = payload['reason'] as String?;

    if (entryType == null || amountCents == null || recordedByUserId == null) {
      throw StateError(
        'Idempotency key "$idempotencyKey" references an incomplete '
        'adjustment record.',
      );
    }

    // The guard row references the affected credit (entityId = creditId).
    final query = select(creditLedgerEntries)
          ..where((e) =>
              e.shopId.equals(shopId) &
              e.creditId.equals(claimed.entityId) &
              e.entryType.equals(entryType) &
              e.amountCents.equals(amountCents) &
              e.reason.equals(reason ?? '') &
              e.recordedByUserId.equals(recordedByUserId))
        ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]);
    final entry = await query.getSingleOrNull();
    if (entry == null) {
      throw StateError(
        'Idempotency key "$idempotencyKey" references a missing ledger entry.',
      );
    }
    return _toDomainLedger(entry);
  }

  /// Retrieves a correction by id strictly scoped within [shopId].
  Future<CreditCorrection?> getCorrectionById(String shopId, String correctionId) async {
    final entry = await (select(creditCorrections)
          ..where((c) =>
              c.shopId.equals(shopId) & c.id.equals(correctionId)))
        .getSingleOrNull();
    return entry != null ? _toDomain(entry) : null;
  }

  /// Retrieves all corrections for [creditId] strictly scoped within [shopId].
  Future<List<CreditCorrection>> getCorrectionsByCredit(
    String shopId,
    String creditId, {
    int? limit,
  }) async {
    final query = select(creditCorrections)
      ..where((c) => c.shopId.equals(shopId) & c.creditId.equals(creditId))
      ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]);
    if (limit != null) {
      query.limit(limit);
    }
    final entries = await query.get();
    return entries.map(_toDomain).toList(growable: false);
  }

  /// Retrieves all corrections in [shopId] matching [status].
  Future<List<CreditCorrection>> getCorrectionsByStatus(
    String shopId,
    String status, {
    int? limit,
  }) async {
    final query = select(creditCorrections)
      ..where((c) => c.shopId.equals(shopId) & c.status.equals(status))
      ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]);
    if (limit != null) {
      query.limit(limit);
    }
    final entries = await query.get();
    return entries.map(_toDomain).toList(growable: false);
  }

  /// Returns the local audit/sync record that claims [idempotencyKey] within
  /// [shopId], or `null` when the key has not been used yet.
  Future<SyncQueueRecord?> _findIdempotencyClaim(
    String shopId,
    String idempotencyKey,
  ) async {
    final query = select(syncQueue)
      ..where((s) =>
          s.shopId.equals(shopId) & s.idempotencyKey.equals(idempotencyKey));
    return query.getSingleOrNull();
  }

  /// Resolves the outcome of a correction operation already recorded under
  /// [idempotencyKey].
  Future<CreditCorrection> _resolveRecordedCorrection({
    required String shopId,
    required String idempotencyKey,
    SyncQueueRecord? claim,
  }) async {
    final claimed =
        claim ?? await _findIdempotencyClaim(shopId, idempotencyKey);

    if (claimed == null ||
        claimed.entityType != correctionEntityType ||
        (claimed.actionType != requestCorrectionActionType &&
            claimed.actionType != approveCorrectionActionType &&
            claimed.actionType != rejectCorrectionActionType)) {
      throw StateError(
        'Idempotency key "$idempotencyKey" is already in use by another '
        'operation.',
      );
    }

    final correction =
        await getCorrectionById(shopId, claimed.entityId);
    if (correction == null) {
      throw StateError(
        'Idempotency key "$idempotencyKey" references a missing correction.',
      );
    }

    // Only return the resolved result when the recorded operation matches the
    // requested action and the correction really is in the expected state.
    final action = claimed.actionType;
    if (action == approveCorrectionActionType &&
        correction.status != CreditCorrectionStatus.approved) {
      throw StateError(
        'Idempotency key "$idempotencyKey" refers to an approval that did not '
        'complete for correction "${claimed.entityId}".',
      );
    }
    if (action == rejectCorrectionActionType &&
        correction.status != CreditCorrectionStatus.rejected) {
      throw StateError(
        'Idempotency key "$idempotencyKey" refers to a rejection that did not '
        'complete for correction "${claimed.entityId}".',
      );
    }

    return correction;
  }

  /// Helper to fetch a credit by id within a shop (avoids constructing a second
  /// DAO inside each transaction branch).
  Future<Credit?> creditDaoGetById(String shopId, String creditId) async {
    final entry = await (select(credits)
          ..where((l) => l.shopId.equals(shopId) & l.id.equals(creditId)))
        .getSingleOrNull();
    if (entry == null) return null;
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
      creditType: CreditType.fromValue(entry.creditType),
    );
  }
}

/// Status of a credit correction request (Story 5.5).
enum CreditCorrectionStatus {
  pendingApproval('pending_approval'),
  approved('approved'),
  rejected('rejected');

  final String value;
  const CreditCorrectionStatus(this.value);

  static CreditCorrectionStatus fromValue(String value) {
    for (final status in CreditCorrectionStatus.values) {
      if (status.value == value) {
        return status;
      }
    }
    throw ArgumentError.value(
      value,
      'value',
      'Invalid CreditCorrectionStatus string representation',
    );
  }
}

/// Clean architecture domain entity representing a credit correction request
/// (Story 5.5).
@immutable
class CreditCorrection {
  final String id;
  final String shopId;
  final String creditId;
  final String? originalPaymentId;
  final String requestedByUserId;
  final DateTime createdAt;
  final int correctionAmountCents;

  /// Direction the approved adjustment moves the credit balance: `debit`
  /// (increase) or `credit` (decrease — the forgiveness write-down).
  final String direction;
  final String reason;
  final CreditCorrectionStatus status;
  final String? reviewedByUserId;
  final DateTime? reviewedAt;
  final String? rejectionReason;
  final int? resultingBalanceCents;
  final DateTime updatedAt;

  const CreditCorrection({
    required this.id,
    required this.shopId,
    required this.creditId,
    this.originalPaymentId,
    required this.requestedByUserId,
    required this.createdAt,
    required this.correctionAmountCents,
    this.direction = 'debit',
    required this.reason,
    required this.status,
    this.reviewedByUserId,
    this.reviewedAt,
    this.rejectionReason,
    this.resultingBalanceCents,
    required this.updatedAt,
  });

  bool get isPending => status == CreditCorrectionStatus.pendingApproval;
  bool get isApproved => status == CreditCorrectionStatus.approved;
  bool get isRejected => status == CreditCorrectionStatus.rejected;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreditCorrection &&
        other.id == id &&
        other.shopId == shopId &&
        other.creditId == creditId &&
        other.originalPaymentId == originalPaymentId &&
        other.requestedByUserId == requestedByUserId &&
        other.createdAt == createdAt &&
        other.correctionAmountCents == correctionAmountCents &&
        other.direction == direction &&
        other.reason == reason &&
        other.status == status &&
        other.reviewedByUserId == reviewedByUserId &&
        other.reviewedAt == reviewedAt &&
        other.rejectionReason == rejectionReason &&
        other.resultingBalanceCents == resultingBalanceCents &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        shopId,
        creditId,
        originalPaymentId,
        requestedByUserId,
        createdAt,
        correctionAmountCents,
        direction,
        reason,
        status,
        reviewedByUserId,
        reviewedAt,
        rejectionReason,
        resultingBalanceCents,
        updatedAt,
      );
}

/// Kind of financial ledger entry (Story 5.5, PRD FR-22).
enum CreditLedgerEntryType {
  compensatingDebit('compensating_debit'),
  adjustmentDebit('adjustment_debit'),
  adjustmentCredit('adjustment_credit');

  final String value;
  const CreditLedgerEntryType(this.value);

  static CreditLedgerEntryType fromValue(String value) {
    for (final type in CreditLedgerEntryType.values) {
      if (type.value == value) {
        return type;
      }
    }
    throw ArgumentError.value(
      value,
      'value',
      'Invalid CreditLedgerEntryType string representation',
    );
  }
}

/// Clean architecture domain entity representing an immutable financial
/// ledger entry (Story 5.5, PRD FR-22).
///
/// A compensating debit entry records a payment reversal: it adds the
/// reversed amount back to the outstanding balance while the original
/// payment record is permanently preserved. Manual adjustments
/// (`adjustmentDebit`, `adjustmentCredit`) share the same vocabulary.
@immutable
class CreditLedgerEntry {
  final String id;
  final String shopId;
  final String creditId;
  final String? originalPaymentId;
  final String? correctionId;
  final CreditLedgerEntryType entryType;
  final int amountCents;
  final int preBalanceCents;
  final int postBalanceCents;
  final String reason;
  final String recordedByUserId;
  final DateTime recordedAt;
  final DateTime createdAt;

  const CreditLedgerEntry({
    required this.id,
    required this.shopId,
    required this.creditId,
    this.originalPaymentId,
    this.correctionId,
    required this.entryType,
    required this.amountCents,
    required this.preBalanceCents,
    required this.postBalanceCents,
    required this.reason,
    required this.recordedByUserId,
    required this.recordedAt,
    required this.createdAt,
  });

  bool get isCompensatingDebit => entryType == CreditLedgerEntryType.compensatingDebit;
  bool get isAdjustmentDebit => entryType == CreditLedgerEntryType.adjustmentDebit;
  bool get isAdjustmentCredit => entryType == CreditLedgerEntryType.adjustmentCredit;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreditLedgerEntry &&
        other.id == id &&
        other.shopId == shopId &&
        other.creditId == creditId &&
        other.originalPaymentId == originalPaymentId &&
        other.correctionId == correctionId &&
        other.entryType == entryType &&
        other.amountCents == amountCents &&
        other.preBalanceCents == preBalanceCents &&
        other.postBalanceCents == postBalanceCents &&
        other.reason == reason &&
        other.recordedByUserId == recordedByUserId &&
        other.recordedAt == recordedAt &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        shopId,
        creditId,
        originalPaymentId,
        correctionId,
        entryType,
        amountCents,
        preBalanceCents,
        postBalanceCents,
        reason,
        recordedByUserId,
        recordedAt,
        createdAt,
      );
}

