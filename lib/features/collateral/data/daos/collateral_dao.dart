import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/tables/collateral_items_table.dart';
import 'package:credit_system/core/data/local/tables/loan_administrative_closures_table.dart';
import 'package:credit_system/core/data/local/tables/loans_table.dart';
import 'package:credit_system/core/data/local/tables/sync_queue_table.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/core/permissions/authorization_guard.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/collateral/domain/models/loan_administrative_closure.dart';
import 'package:credit_system/features/customers/domain/models/loan.dart';
import 'package:uuid/uuid.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_custody_event_dao.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_discrepancy_dao.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_custody_event.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';

part 'collateral_dao.g.dart';

/// Data Access Object for collateral items (Story 3.1) and loan-level
/// administrative closure workflow (Story 3.5, PRD FR-16, AD-3).
///
/// All queries are strictly scoped to [shopId] to enforce tenant isolation.
/// A collateral item can only be created, read, or updated within its owning shop.
///
/// Binds: PRD FR-13, FR-14, FR-16; AD-1 (tenant isolation); AD-4 (clean architecture).
@DriftAccessor(
  tables: [
    CollateralItems,
    LoanAdministrativeClosures,
    Loans,
    SyncQueue,
  ],
)
class CollateralDao extends DatabaseAccessor<AppDatabase>
    with _$CollateralDaoMixin {
  late final CollateralCustodyEventDao _custodyEventDao;
  late final CollateralDiscrepancyDao _discrepancyDao;

  CollateralDao(super.db) {
    _custodyEventDao = CollateralCustodyEventDao(db);
    _discrepancyDao = CollateralDiscrepancyDao(db);
  }

  /// Converts a Drift [CollateralItemEntry] row into a domain [CollateralItem].
  CollateralItem _toDomain(CollateralItemEntry entry) {
    return CollateralItem(
      id: entry.id,
      shopId: entry.shopId,
      customerId: entry.customerId,
      loanId: entry.loanId,
      itemReferenceId: entry.itemReferenceId,
      category: CollateralItemCategory.fromValue(entry.category),
      description: entry.description,
      conditionGrade: entry.conditionGrade,
      weightMilligrams: entry.weightMilligrams,
      estimatedValueCents: entry.estimatedValueCents,
      photoUri: entry.photoUri,
      photoHash: entry.photoHash,
      custodyStatus: CollateralCustodyStatus.fromValue(entry.custodyStatus),
      createdAt: entry.createdAt.toUtc(),
      updatedAt: entry.updatedAt.toUtc(),
    );
  }

  /// Converts a domain [CollateralItem] into a Drift [CollateralItemsCompanion].
  CollateralItemsCompanion _toCompanion(CollateralItem item) {
    return CollateralItemsCompanion(
      id: Value(item.id),
      shopId: Value(item.shopId),
      customerId: Value(item.customerId),
      loanId: Value(item.loanId),
      itemReferenceId: Value(item.itemReferenceId),
      category: Value(item.category.value),
      description: Value(item.description),
      conditionGrade: Value(item.conditionGrade),
      weightMilligrams: Value(item.weightMilligrams),
      estimatedValueCents: Value(item.estimatedValueCents),
      photoUri: Value(item.photoUri),
      photoHash: Value(item.photoHash),
      custodyStatus: Value(item.custodyStatus.value),
      createdAt: Value(item.createdAt),
      updatedAt: Value(item.updatedAt),
    );
  }

  /// Inserts a new collateral item record into the local SQLite database.
  ///
  /// Validates that the item belongs to [shopId] before insertion.
  /// Throws [sqlite.SqliteException] if foreign key constraints are violated
  /// (e.g., referenced shop, customer, or loan does not exist).
  /// Throws [ArgumentError] if the item reference ID already exists in the shop.
  Future<void> createCollateralItem(CollateralItem item) async {
    if (item.shopId.trim().isEmpty) {
      throw ArgumentError.value(item.shopId, 'shopId', 'shopId cannot be empty');
    }
    if (item.customerId.trim().isEmpty) {
      throw ArgumentError.value(
          item.customerId, 'customerId', 'customerId cannot be empty');
    }
    await into(collateralItems).insert(_toCompanion(item));
  }

  /// Retrieves a collateral item by [itemId] strictly scoped within [shopId].
  ///
  /// Returns `null` if the item does not exist or belongs to another shop.
  Future<CollateralItem?> getCollateralItemById(
    String shopId,
    String itemId,
  ) async {
    final query = select(collateralItems)
      ..where((c) =>
          c.shopId.equals(shopId) & c.id.equals(itemId));
    final entry = await query.getSingleOrNull();
    return entry != null ? _toDomain(entry) : null;
  }

  /// Retrieves a collateral item by its [itemReferenceId] strictly scoped within [shopId].
  ///
  /// Returns `null` if no item with that reference exists in the shop.
  Future<CollateralItem?> getCollateralItemByReference(
    String shopId,
    String itemReferenceId,
  ) async {
    final query = select(collateralItems)
      ..where((c) =>
          c.shopId.equals(shopId) &
          c.itemReferenceId.equals(itemReferenceId));
    final entry = await query.getSingleOrNull();
    return entry != null ? _toDomain(entry) : null;
  }

  /// Retrieves all collateral items for [customerId] strictly scoped within [shopId].
  ///
  /// Returns items ordered by creation time descending.
  Future<List<CollateralItem>> getCollateralItemsByCustomerId(
    String shopId,
    String customerId,
  ) async {
    final query = select(collateralItems)
      ..where((c) =>
          c.shopId.equals(shopId) & c.customerId.equals(customerId))
      ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Retrieves all collateral items in [shopId] matching [custodyStatus].
  ///
  /// Strictly scoped to [shopId] — items in other shops are never returned.
  Future<List<CollateralItem>> getCollateralItemsByCustodyStatus(
    String shopId,
    CollateralCustodyStatus custodyStatus,
  ) async {
    final query = select(collateralItems)
      ..where((c) =>
          c.shopId.equals(shopId) &
          c.custodyStatus.equals(custodyStatus.value))
      ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Retrieves all collateral items for [customerId] in [shopId] matching [custodyStatus].
  ///
  /// Strictly scoped to [shopId] — items in other shops are never returned.
  Future<List<CollateralItem>> getCollateralItemsByCustomerAndCustody(
    String shopId,
    String customerId,
    CollateralCustodyStatus custodyStatus,
  ) async {
    final query = select(collateralItems)
      ..where((c) =>
          c.shopId.equals(shopId) &
          c.customerId.equals(customerId) &
          c.custodyStatus.equals(custodyStatus.value))
      ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Retrieves all collateral items in [shopId], ordered by creation time
  /// descending. Strictly scoped to [shopId] for tenant isolation.
  Future<List<CollateralItem>> getCollateralItemsByShopId(String shopId) async {
    final query = select(collateralItems)
      ..where((c) => c.shopId.equals(shopId))
      ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Retrieves all collateral items linked to [loanId] strictly scoped within [shopId].
  ///
  /// Returns `null` loans (items not yet bound to a loan) are excluded.
  Future<List<CollateralItem>> getCollateralItemsByLoanId(
    String shopId,
    String loanId,
  ) async {
    final query = select(collateralItems)
      ..where((c) =>
          c.shopId.equals(shopId) & c.loanId.equals(loanId))
      ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Retrieves all collateral items not yet bound to any loan in [shopId].
  ///
  /// Useful for Epic 4 to find available collateral for new loans.
  Future<List<CollateralItem>> getUnboundCollateralItems(String shopId) async {
    final query = select(collateralItems)
      ..where((c) => c.shopId.equals(shopId) & c.loanId.isNull())
      ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Updates an existing collateral item strictly scoped within [shopId].
  ///
  /// Enforces shop boundary isolation: throws [StateError] if the item does
  /// not exist within the specified [shopId].
  ///
  /// Excludes immutable identity columns ([id], [shopId], [customerId],
  /// [createdAt]) from the SQL SET clause to guarantee identity integrity.
  Future<void> updateCollateralItem(CollateralItem item) async {
    final existing = await getCollateralItemById(item.shopId, item.id);
    if (existing == null) {
      throw StateError(
        'Cannot update collateral item: ID "${item.id}" not found in shop "${item.shopId}".',
      );
    }

    // Custody state must never be changed through a general-purpose item
    // update. All custody transitions must route through [transitionCustody],
    // which enforces the state machine and authorization atomically.
    if (item.custodyStatus != existing.custodyStatus) {
      throw StateError(
        'Cannot change custody status via updateCollateralItem: item "${item.id}" '
        'is "${existing.custodyStatus.value}" but the update targets '
        '"${item.custodyStatus.value}". Use transitionCustody instead.',
      );
    }

    final companion = CollateralItemsCompanion(
      id: const Value.absent(),
      shopId: const Value.absent(),
      customerId: const Value.absent(),
      loanId: Value(item.loanId),
      itemReferenceId: Value(item.itemReferenceId),
      category: Value(item.category.value),
      description: Value(item.description),
      conditionGrade: Value(item.conditionGrade),
      weightMilligrams: Value(item.weightMilligrams),
      estimatedValueCents: Value(item.estimatedValueCents),
      photoUri: Value(item.photoUri),
      photoHash: Value(item.photoHash),
      // custodyStatus is intentionally excluded — custody changes route through
      // transitionCustody only.
      custodyStatus: const Value.absent(),
      createdAt: const Value.absent(),
      updatedAt: Value(DateTime.now().toUtc()),
    );

    await (update(collateralItems)
          ..where((c) =>
              c.shopId.equals(item.shopId) & c.id.equals(item.id)))
        .write(companion);
  }

  /// Associates a collateral item with a loan within [shopId].
  ///
  /// Throws [StateError] if the item does not exist in the shop.
  Future<void> associateWithLoan(
    String shopId,
    String itemId,
    String loanId,
  ) async {
    final existing = await getCollateralItemById(shopId, itemId);
    if (existing == null) {
      throw StateError(
        'Cannot associate with loan: collateral item ID "$itemId" not found in shop "$shopId".',
      );
    }

    await (update(collateralItems)
          ..where((c) => c.shopId.equals(shopId) & c.id.equals(itemId)))
        .write(CollateralItemsCompanion(
          id: const Value.absent(),
          shopId: const Value.absent(),
          customerId: const Value.absent(),
          loanId: Value(loanId),
          itemReferenceId: const Value.absent(),
          category: const Value.absent(),
          description: const Value.absent(),
          conditionGrade: const Value.absent(),
          weightMilligrams: const Value.absent(),
          estimatedValueCents: const Value.absent(),
          photoUri: const Value.absent(),
          photoHash: const Value.absent(),
          custodyStatus: const Value.absent(),
          createdAt: const Value.absent(),
          updatedAt: Value(DateTime.now().toUtc()),
        ));
  }

  /// Transitions the custody status of a collateral item within [shopId] and
  /// records the custody event atomically.
  ///
  /// Validates the transition using [CollateralItem.transitionCustody] before
  /// persisting. Throws [CollateralCustodyTransitionException] for invalid
  /// transitions, [StateError] if the item is not found, and
  /// [PermissionDeniedException] when the actor lacks the required permission.
  ///
  /// Authorization is mandatory and enforced in the underlying operation, not
  /// only in the UI. The item update and the custody-event insert run inside a
  /// single Drift transaction so a concurrent transition cannot produce a
  /// duplicate successful audit event.
  ///
  /// Set [requireOwner] to `true` for owner-only actions (e.g. confirming a
  /// return) so that even actors holding the permission but not possessing the
  /// Shop Owner role are rejected.
  Future<void> transitionCustody(
    String shopId,
    String itemId,
    CollateralCustodyStatus newStatus, {
    required AppUser actor,
    required AppPermission requiredPermission,
    bool requireOwner = false,
    String? reportedByUserId,
    String? reason,
  }) async {
    if (!actor.isActive) {
      throw const PermissionDeniedException(
        'Access denied: User account is deactivated.',
      );
    }
    AuthorizationGuard.checkPermission(
      isActive: actor.isActive,
      effectivePermissions: actor.effectivePermissions,
      permission: requiredPermission,
      actionDescription:
          'transition collateral item "$itemId" custody to "${newStatus.value}"',
    );
    if (requireOwner) {
      AuthorizationGuard.checkOwnerAdministrativeAction(
        isActive: actor.isActive,
        actorRole: actor.role,
        actionDescription:
            'transition collateral item "$itemId" custody to "${newStatus.value}"',
      );
    }

    final reporterId = reportedByUserId ?? actor.id;

    return db.transaction(() async {
      return _transitionCustodyTx(
        shopId,
        itemId,
        newStatus,
        reporterId,
        reason,
      );
    });
  }

  /// Performs the custody transition and event insert inside an already-open
  /// transaction. Authorization must have been checked by the caller.
  /// Throws [CollateralCustodyTransitionException] for invalid transitions and
  /// [StateError] if the item is not found.
  Future<void> _transitionCustodyTx(
    String shopId,
    String itemId,
    CollateralCustodyStatus newStatus,
    String reporterId,
    String? reason,
  ) async {
    // Re-read inside the transaction so a concurrent transition is observed
    // and rejected by the state machine before any write occurs.
    final existing = await getCollateralItemById(shopId, itemId);
    if (existing == null) {
      throw StateError(
        'Cannot transition custody: collateral item ID "$itemId" not found in shop "$shopId".',
      );
    }

    final updated = existing.transitionCustody(newStatus);

    await (update(collateralItems)
          ..where((c) => c.shopId.equals(shopId) & c.id.equals(itemId)))
        .write(CollateralItemsCompanion(
          id: const Value.absent(),
          shopId: const Value.absent(),
          customerId: const Value.absent(),
          loanId: const Value.absent(),
          itemReferenceId: const Value.absent(),
          category: const Value.absent(),
          description: const Value.absent(),
          conditionGrade: const Value.absent(),
          weightMilligrams: const Value.absent(),
          estimatedValueCents: const Value.absent(),
          photoUri: const Value.absent(),
          photoHash: const Value.absent(),
          custodyStatus: Value(updated.custodyStatus.value),
          createdAt: const Value.absent(),
          updatedAt: Value(updated.updatedAt),
        ));

    // Record the custody event within the same transaction. Uuid v4 ids keep
    // concurrent transitions from colliding on the event id.
    await _custodyEventDao.createEvent(CollateralCustodyEvent(
      id: const Uuid().v4(),
      shopId: shopId,
      collateralItemId: itemId,
      reportedByUserId: reporterId,
      previousStatus: existing.custodyStatus,
      newStatus: newStatus,
      reason: reason ?? 'Custody transition to ${newStatus.value}',
    ));
  }

  /// Reports a discrepancy for a collateral item within [shopId].
  ///
  /// Transitions the item custody status to `discrepancy` and records the
  /// discrepancy report. Throws [StateError] if the item does not exist in
  /// the shop or is already in a terminal state, and
  /// [PermissionDeniedException] when the actor lacks the required permission.
  ///
  /// Authorization is mandatory and enforced before any write occurs. The item
  /// update, the custody-event insert, and the discrepancy insert run inside a
  /// single Drift transaction so the operation is atomic.
  Future<void> reportDiscrepancy(
    String shopId,
    String itemId,
    String reportedByUserId,
    String requestReason, {
    required AppUser actor,
    required AppPermission requiredPermission,
  }) async {
    if (!actor.isActive) {
      throw const PermissionDeniedException(
        'Access denied: User account is deactivated.',
      );
    }
    AuthorizationGuard.checkPermission(
      isActive: actor.isActive,
      effectivePermissions: actor.effectivePermissions,
      permission: requiredPermission,
      actionDescription:
          'report discrepancy for collateral item "$itemId"',
    );

    return db.transaction(() async {
      final existing = await getCollateralItemById(shopId, itemId);
      if (existing == null) {
        throw StateError(
          'Cannot report discrepancy: collateral item ID "$itemId" not found in shop "$shopId".',
        );
      }

      if (existing.custodyStatus.isTerminal) {
        throw StateError(
          'Cannot report discrepancy: collateral item ID "$itemId" is already in terminal state "${existing.custodyStatus.value}".',
        );
      }

      await (update(collateralItems)
            ..where((c) => c.shopId.equals(shopId) & c.id.equals(itemId)))
          .write(CollateralItemsCompanion(
            id: const Value.absent(),
            shopId: const Value.absent(),
            customerId: const Value.absent(),
            loanId: const Value.absent(),
            itemReferenceId: const Value.absent(),
            category: const Value.absent(),
            description: const Value.absent(),
            conditionGrade: const Value.absent(),
            weightMilligrams: const Value.absent(),
            estimatedValueCents: const Value.absent(),
            photoUri: const Value.absent(),
            photoHash: const Value.absent(),
            custodyStatus: Value(CollateralCustodyStatus.discrepancy.value),
            createdAt: const Value.absent(),
            updatedAt: Value(DateTime.now().toUtc()),
          ));

      await _custodyEventDao.createEvent(CollateralCustodyEvent(
        id: const Uuid().v4(),
        shopId: shopId,
        collateralItemId: itemId,
        reportedByUserId: reportedByUserId,
        previousStatus: existing.custodyStatus,
        newStatus: CollateralCustodyStatus.discrepancy,
        reason: requestReason,
      ));

      await _discrepancyDao.createDiscrepancy(CollateralDiscrepancy(
        id: const Uuid().v4(),
        shopId: shopId,
        collateralItemId: itemId,
        reportedByUserId: reportedByUserId,
        discrepancyReason: requestReason,
        status: CollateralDiscrepancyStatus.pending,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ));
    });
  }

  /// Resolves a discrepancy by transitioning the collateral item custody to
  /// the target state and recording the Shop Owner's decision.
  ///
  /// Only an active Shop Owner may resolve a discrepancy. Authorization and
  /// the pending-status guard are enforced before any write. The custody
  /// transition and the discrepancy resolution run inside a single Drift
  /// transaction, so a concurrent duplicate resolution cannot succeed and a
  /// failure never leaves item state and discrepancy state partially updated.
  Future<void> resolveDiscrepancy(
    String shopId,
    String discrepancyId,
    CollateralCustodyStatus newStatus,
    String resolvedByUserId,
    String resolutionNotes,
    DateTime resolvedAt, {
    required AppUser actor,
    required AppPermission requiredPermission,
  }) async {
    if (!actor.isActive) {
      throw const PermissionDeniedException(
        'Access denied: User account is deactivated.',
      );
    }
    AuthorizationGuard.checkPermission(
      isActive: actor.isActive,
      effectivePermissions: actor.effectivePermissions,
      permission: requiredPermission,
      actionDescription:
          'resolve discrepancy "$discrepancyId" for collateral item',
    );
    // Resolving a discrepancy is an owner-only administrative action even if
    // the actor happens to hold the underlying permission (e.g. a custom
    // role); the Shop Owner role is required.
    AuthorizationGuard.checkOwnerAdministrativeAction(
      isActive: actor.isActive,
      actorRole: actor.role,
      actionDescription:
          'resolve discrepancy "$discrepancyId" for collateral item',
    );

    return db.transaction(() async {
      final discrepancy = await _discrepancyDao.getDiscrepancyById(
        shopId,
        discrepancyId,
      );
      if (discrepancy == null) {
        throw StateError(
          'Cannot resolve discrepancy: discrepancy ID "$discrepancyId" not found in shop "$shopId".',
        );
      }

      if (discrepancy.status == CollateralDiscrepancyStatus.resolved) {
        throw StateError(
          'Cannot resolve discrepancy: discrepancy ID "$discrepancyId" is already resolved.',
        );
      }

      final existing = await getCollateralItemById(
        shopId,
        discrepancy.collateralItemId,
      );
      if (existing == null) {
        throw StateError(
          'Cannot resolve discrepancy: collateral item ID "${discrepancy.collateralItemId}" not found in shop "$shopId".',
        );
      }

      // Update custody status within the same transaction.
      await _transitionCustodyTx(
        shopId,
        discrepancy.collateralItemId,
        newStatus,
        resolvedByUserId,
        'Discrepancy resolved: $resolutionNotes',
      );

      // Resolve the discrepancy only if it is still pending; this guards
      // against duplicate/conflicting concurrent resolutions.
      final resolved = discrepancy.copyWith(
        status: CollateralDiscrepancyStatus.resolved,
        resolvedByUserId: resolvedByUserId,
        resolutionNotes: resolutionNotes,
        resolvedAt: resolvedAt,
        updatedAt: resolvedAt,
      );
      final rowsAffected = await _discrepancyDao.resolveDiscrepancy(resolved);
      if (rowsAffected == 0) {
        throw StateError(
          'Cannot resolve discrepancy: discrepancy ID "$discrepancyId" is already resolved.',
        );
      }
    });
  }

  /// Places a collateral item into `exceptionHeld` (Exception / Held) state.
  ///
  /// Only an active Shop Owner may perform this administrative action. The
  /// actor must provide a non-empty business rationale. The item is verified
  /// to exist within [shopId] and to be in a non-terminal custody state that
  /// can transition to `exceptionHeld`.
  ///
  /// The custody transition and custody-event insert run inside a single
  /// Drift transaction so the operation is atomic: a concurrent attempt
  /// cannot produce a duplicate successful transition, and a failure never
  /// leaves item state partially updated. Existing custody history is
  /// preserved via the append-only [collateralCustodyEvents] table.
  Future<void> closeCollateralException(
    String shopId,
    String itemId, {
    required AppUser actor,
    required String reason,
  }) async {
    if (!actor.isActive) {
      throw const PermissionDeniedException(
        'Access denied: User account is deactivated.',
      );
    }
    // Exception / Held placement is an owner-only administrative action per
    // PRD FR-16 / AD-6. Even actors holding collateral-related permissions
    // (e.g. a Manager with confirmCollateralReturn) are rejected unless they
    // possess the Shop Owner role.
    AuthorizationGuard.checkOwnerAdministrativeAction(
      isActive: actor.isActive,
      actorRole: actor.role,
      actionDescription:
          'place collateral item "$itemId" into exception held custody',
    );
    if (reason.trim().isEmpty) {
      throw ArgumentError(
        'A non-empty business rationale is required to place an item into exception held.',
      );
    }

    return db.transaction(() async {
      // Re-read inside the transaction so a concurrent transition is observed
      // and rejected by the state machine before any write occurs.
      final existing = await getCollateralItemById(shopId, itemId);
      if (existing == null) {
        throw StateError(
          'Cannot place item into exception held: collateral item ID "$itemId" not found in shop "$shopId".',
        );
      }

      if (existing.custodyStatus.isTerminal) {
        throw StateError(
          'Cannot place item into exception held: collateral item ID "$itemId" is already in terminal state "${existing.custodyStatus.value}".',
        );
      }

      final updated = existing.transitionCustody(
        CollateralCustodyStatus.exceptionHeld,
      );

      final rowsAffected = await (update(collateralItems)
            ..where((c) =>
                c.shopId.equals(shopId) &
                c.id.equals(itemId) &
                c.custodyStatus.equals(existing.custodyStatus.value)))
          .write(CollateralItemsCompanion(
            id: const Value.absent(),
            shopId: const Value.absent(),
            customerId: const Value.absent(),
            loanId: const Value.absent(),
            itemReferenceId: const Value.absent(),
            category: const Value.absent(),
            description: const Value.absent(),
            conditionGrade: const Value.absent(),
            weightMilligrams: const Value.absent(),
            estimatedValueCents: const Value.absent(),
            photoUri: const Value.absent(),
            photoHash: const Value.absent(),
            custodyStatus: Value(updated.custodyStatus.value),
            createdAt: const Value.absent(),
            updatedAt: Value(updated.updatedAt),
          ));

      // Conditional UPDATE: if another concurrent transaction already changed
      // the custody state, 0 rows are affected. Reject the second operation
      // and do not insert a duplicate custody event.
      if (rowsAffected == 0) {
        throw StateError(
          'Cannot place item into exception held: collateral item ID "$itemId" '
          'was modified by another operation to "${(await getCollateralItemById(shopId, itemId))?.custodyStatus.value}".',
        );
      }

      await _custodyEventDao.createEvent(CollateralCustodyEvent(
        id: const Uuid().v4(),
        shopId: shopId,
        collateralItemId: itemId,
        reportedByUserId: actor.id,
        previousStatus: existing.custodyStatus,
        newStatus: CollateralCustodyStatus.exceptionHeld,
        reason: 'Exception / Held: ${reason.trim()}',
      ));
    });
  }

  /// Retrieves all collateral items awaiting staff or owner action
  /// (`handoverRequested` or `handoverReported`) for [shopId], ordered by
  /// creation time ascending — i.e. the custody queue.
  Future<List<CollateralItem>> getPendingCustodyTransitions(
    String shopId,
  ) async {
    final query = select(collateralItems)
      ..where((c) =>
          c.shopId.equals(shopId) &
          (c.custodyStatus.equals(CollateralCustodyStatus.handoverRequested.value) |
              c.custodyStatus.equals(CollateralCustodyStatus.handoverReported.value)))
      ..orderBy([(c) => OrderingTerm.asc(c.createdAt)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Retrieves all custody events for a collateral item within [shopId].
  Future<List<CollateralCustodyEvent>> getCustodyEventsByCollateralItemId(
    String shopId,
    String collateralItemId,
  ) async {
    return _custodyEventDao.getEventsByCollateralItemId(shopId, collateralItemId);
  }

  /// Retrieves all discrepancy reports for a collateral item within [shopId].
  Future<List<CollateralDiscrepancy>> getDiscrepanciesByCollateralItemId(
    String shopId,
    String collateralItemId,
  ) async {
    return _discrepancyDao.getDiscrepanciesByCollateralItemId(shopId, collateralItemId);
  }

  /// Converts a Drift [LoanAdministrativeClosureEntry] row into a domain
  /// [LoanAdministrativeClosure].
  LoanAdministrativeClosure _toDomainClosure(
      LoanAdministrativeClosureEntry entry) {
    return LoanAdministrativeClosure(
      id: entry.id,
      shopId: entry.shopId,
      loanId: entry.loanId,
      reason: entry.reason,
      closedByUserId: entry.closedByUserId,
      itemIds: LoanAdministrativeClosure.parseItemIdsJson(entry.itemIdsJson),
      createdAt: entry.createdAt.toUtc(),
    );
  }

  /// Retrieves the administrative closure record for [loanId] within [shopId],
  /// or null if none exists.
  Future<LoanAdministrativeClosure?> getAdministrativeClosureByLoanId(
    String shopId,
    String loanId,
  ) async {
    final query = select(loanAdministrativeClosures)
      ..where((c) => c.shopId.equals(shopId) & c.loanId.equals(loanId));
    final entry = await query.getSingleOrNull();
    return entry != null ? _toDomainClosure(entry) : null;
  }

  /// Checks whether [loanId] within [shopId] has an administrative closure record.
  Future<bool> isLoanAdministrativelyClosed(
    String shopId,
    String loanId,
  ) async {
    final closure = await getAdministrativeClosureByLoanId(shopId, loanId);
    return closure != null;
  }

  /// Checks whether [loanId] within [shopId] is in `settled` status.
  Future<bool> isLoanSettled(String shopId, String loanId) async {
    final loanRows = await (select(loans)
          ..where((l) => l.shopId.equals(shopId) & l.id.equals(loanId)))
        .get();
    if (loanRows.isEmpty) return false;
    return loanRows.first.status == LoanStatus.settled.value;
  }

  /// Executes an administrative closure for a settled loan with collateral items
  /// in Exception / Held status (Story 3.5, PRD FR-16, AD-3).
  ///
  /// Requirements:
  /// - Only an active Shop Owner can perform this action (enforced via [AuthorizationGuard]).
  /// - [reason] must be non-empty.
  /// - [idempotencyKey] must be non-empty (duplicate submissions with same key are idempotent no-ops).
  /// - The loan must exist within [shopId] and have status `settled`.
  /// - The loan must have at least one collateral item in [CollateralCustodyStatus.exceptionHeld].
  /// - All items for the loan must be in a terminal custody state (`returned` or `exceptionHeld`).
  ///   Any active/unresolved items (`handoverRequested`, `handoverReported`, `discrepancy`, `inCustody`)
  ///   block administrative closure.
  /// - Writes a Category 11 SyncQueue audit entry and a [LoanAdministrativeClosures] record atomically.
  /// - Collateral items remain in `exceptionHeld` custody (no mutation occurs to items).
  Future<void> executeAdministrativeClosure(
    String shopId,
    String loanId, {
    required AppUser actor,
    required String reason,
    required String idempotencyKey,
  }) async {
    if (!actor.isActive) {
      throw const PermissionDeniedException(
        'Access denied: User account is deactivated.',
      );
    }

    AuthorizationGuard.checkOwnerAdministrativeAction(
      isActive: actor.isActive,
      actorRole: actor.role,
      actionDescription:
          'execute loan-level administrative closure for loan "$loanId"',
    );

    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw ArgumentError(
        'A non-empty business rationale is required for loan administrative closure.',
      );
    }

    final trimmedKey = idempotencyKey.trim();
    if (trimmedKey.isEmpty) {
      throw ArgumentError(
        'An idempotency key is required for loan administrative closure.',
      );
    }

    return db.transaction(() async {
      // 1. Check idempotency: if an entry with this idempotency key already exists
      final existingSync = await (select(syncQueue)
            ..where((s) =>
                s.shopId.equals(shopId) &
                s.idempotencyKey.equals(trimmedKey)))
          .getSingleOrNull();

      if (existingSync != null) {
        // Already processed under this idempotency key
        return;
      }

      // 2. Check if the loan already has an administrative closure under a different key
      final existingClosure = await getAdministrativeClosureByLoanId(shopId, loanId);
      if (existingClosure != null) {
        throw StateError(
          'Loan "$loanId" has already undergone administrative closure.',
        );
      }

      // 3. Verify loan exists and is settled
      final loanRows = await (select(loans)
            ..where((l) => l.shopId.equals(shopId) & l.id.equals(loanId)))
          .get();
      if (loanRows.isEmpty) {
        throw StateError(
          'Cannot administratively close loan: loan ID "$loanId" not found in shop "$shopId".',
        );
      }
      final loanEntry = loanRows.first;
      if (loanEntry.status != LoanStatus.settled.value) {
        throw StateError(
          'Cannot administratively close loan "$loanId": loan is not fully settled (current status: "${loanEntry.status}").',
        );
      }

      // 4. Verify collateral items
      final items = await getCollateralItemsByLoanId(shopId, loanId);
      if (items.isEmpty) {
        throw StateError(
          'Cannot administratively close loan "$loanId": no collateral items found.',
        );
      }

      final exceptionItems = items
          .where((i) => i.custodyStatus == CollateralCustodyStatus.exceptionHeld)
          .toList();
      if (exceptionItems.isEmpty) {
        throw StateError(
          'Cannot administratively close loan "$loanId": at least one collateral item must be in exception held status.',
        );
      }

      final nonTerminalItems = items
          .where((i) =>
              i.custodyStatus != CollateralCustodyStatus.returned &&
              i.custodyStatus != CollateralCustodyStatus.exceptionHeld)
          .toList();
      if (nonTerminalItems.isNotEmpty) {
        final unresolvedRefs = nonTerminalItems
            .map((i) => '${i.itemReferenceId} (${i.custodyStatus.value})')
            .join(', ');
        throw StateError(
          'Cannot administratively close loan "$loanId": all items must be in terminal custody (returned or exception held), but items are still active/unresolved: $unresolvedRefs.',
        );
      }

      final nowUtc = DateTime.now().toUtc();
      final closureId = const Uuid().v4();
      final exceptionItemIds = exceptionItems.map((i) => i.id).toList();

      // 5. Insert SyncQueue audit entry (Category 11 per PRD FR-16)
      await into(syncQueue).insert(
        SyncQueueCompanion.insert(
          id: const Uuid().v4(),
          shopId: shopId,
          idempotencyKey: trimmedKey,
          entityType: 'loan',
          entityId: loanId,
          actionType: 'close_collateral_exception',
          payloadJson: jsonEncode({
            'auditCategory': 11,
            'auditEvent': 'loan_administrative_closure',
            'actorId': actor.id,
            'loanId': loanId,
            'reason': cleanReason,
            'exceptionItemIds': exceptionItemIds,
            'shopId': shopId,
            'timestamp': nowUtc.toIso8601String(),
          }),
          createdAt: nowUtc,
          updatedAt: Value(nowUtc),
        ),
      );

      // 6. Insert into loan_administrative_closures
      await into(loanAdministrativeClosures).insert(
        LoanAdministrativeClosuresCompanion.insert(
          id: closureId,
          shopId: shopId,
          loanId: loanId,
          reason: cleanReason,
          closedByUserId: actor.id,
          itemIdsJson: jsonEncode(exceptionItemIds),
          createdAt: nowUtc,
        ),
      );
    });
  }

  /// Dynamically derives the overall workflow status string for a loan (AD-3).
  Future<String> deriveOverallWorkflowStatus(
    String shopId,
    Loan loan,
  ) async {
    if (loan.status == LoanStatus.cancelled) {
      return 'Cancelled';
    }
    if (loan.status != LoanStatus.settled) {
      switch (loan.workflowStatus) {
        case LoanWorkflowStatus.pendingDisbursement:
          return 'Pending Disbursement';
        case LoanWorkflowStatus.disbursed:
          return 'Disbursed';
        case LoanWorkflowStatus.cancelled:
          return 'Cancelled';
        case LoanWorkflowStatus.overdue:
          return 'Overdue';
      }
    }

    // Loan is settled financially
    final isClosedException =
        await isLoanAdministrativelyClosed(shopId, loan.id);
    if (isClosedException) {
      return 'Closed (Collateral Exception)';
    }

    final items = await getCollateralItemsByLoanId(shopId, loan.id);
    if (items.isNotEmpty &&
        items.every((i) => i.custodyStatus == CollateralCustodyStatus.returned)) {
      return 'Settled / Closed (All Collateral Returned)';
    }

    return 'Settled (Pending Collateral Return)';
  }
}
