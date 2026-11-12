import 'package:meta/meta.dart';

import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';

/// Validation exception thrown when collateral custody event invariants are violated.
class CollateralCustodyEventValidationException extends ArgumentError {
  CollateralCustodyEventValidationException(super.message);
}

/// Clean architecture domain entity representing a custody state transition event (Story 3.4).
///
/// Records the actor, timestamp, previous state, new state, and reason for every
/// custody state transition on a collateral item. Provides an immutable audit trail
/// that cannot be overwritten or deleted.
///
/// Binds:
/// - FR-16: Independent Per-Item Custody Tracking
/// - AD-3: Finite State Machines
/// - AD-6: Granular RBAC & Audit
@immutable
class CollateralCustodyEvent {
  /// Canonical UUIDv4 primary key.
  final String id;

  /// Associated shop tenant UUID boundary.
  final String shopId;

  /// Associated collateral item UUID.
  final String collateralItemId;

  /// User UUID of the staff member who initiated the transition.
  final String reportedByUserId;

  /// Previous custody state before the transition.
  final CollateralCustodyStatus previousStatus;

  /// New custody state after the transition.
  final CollateralCustodyStatus newStatus;

  /// Reason for the custody transition.
  final String reason;

  /// UTC timestamp when the transition was recorded.
  final DateTime createdAt;

  CollateralCustodyEvent({
    required this.id,
    required this.shopId,
    required this.collateralItemId,
    required this.reportedByUserId,
    required this.previousStatus,
    required this.newStatus,
    required this.reason,
    DateTime? createdAt,
  })  : createdAt = createdAt ?? DateTime.now().toUtc() {
    _validate();
  }

  void _validate() {
    if (id.trim().isEmpty) {
      throw CollateralCustodyEventValidationException(
        'Collateral custody event ID cannot be empty',
      );
    }
    if (shopId.trim().isEmpty) {
      throw CollateralCustodyEventValidationException(
        'Shop ID cannot be empty',
      );
    }
    if (collateralItemId.trim().isEmpty) {
      throw CollateralCustodyEventValidationException(
        'Collateral item ID cannot be empty',
      );
    }
    if (reportedByUserId.trim().isEmpty) {
      throw CollateralCustodyEventValidationException(
        'Reported by user ID cannot be empty',
      );
    }
    if (reason.trim().isEmpty) {
      throw CollateralCustodyEventValidationException(
        'Custody transition reason cannot be empty',
      );
    }
  }

  /// Returns a copy of this entity with updated fields.
  CollateralCustodyEvent copyWith({
    String? id,
    String? shopId,
    String? collateralItemId,
    String? reportedByUserId,
    CollateralCustodyStatus? previousStatus,
    CollateralCustodyStatus? newStatus,
    String? reason,
    DateTime? createdAt,
  }) {
    return CollateralCustodyEvent(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      collateralItemId: collateralItemId ?? this.collateralItemId,
      reportedByUserId: reportedByUserId ?? this.reportedByUserId,
      previousStatus: previousStatus ?? this.previousStatus,
      newStatus: newStatus ?? this.newStatus,
      reason: reason ?? this.reason,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CollateralCustodyEvent &&
        other.id == id &&
        other.shopId == shopId &&
        other.collateralItemId == collateralItemId &&
        other.reportedByUserId == reportedByUserId &&
        other.previousStatus == previousStatus &&
        other.newStatus == newStatus &&
        other.reason == reason &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        shopId,
        collateralItemId,
        reportedByUserId,
        previousStatus,
        newStatus,
        reason,
        createdAt,
      );

  @override
  String toString() {
    return 'CollateralCustodyEvent(id: $id, itemId: $collateralItemId, '
        'from: ${previousStatus.value}, to: ${newStatus.value}, '
        'reportedBy: $reportedByUserId, reason: $reason)';
  }
}

/// Validation exception thrown when collateral discrepancy invariants are violated.
class CollateralDiscrepancyValidationException extends ArgumentError {
  CollateralDiscrepancyValidationException(super.message);
}

/// Discrepancy report lifecycle status.
///
/// Valid transitions:
///   `pending` → `resolved` (with resolution)
///
/// Invalid transitions throw [CollateralDiscrepancyTransitionException].
enum CollateralDiscrepancyStatus {
  pending('pending'),
  resolved('resolved');

  final String value;
  const CollateralDiscrepancyStatus(this.value);

  /// Resolves [CollateralDiscrepancyStatus] from raw database text.
  static CollateralDiscrepancyStatus fromValue(String value) {
    for (final status in CollateralDiscrepancyStatus.values) {
      if (status.value == value) {
        return status;
      }
    }
    throw ArgumentError.value(value, 'value', 'Invalid collateral discrepancy status');
  }

  /// Whether this is a terminal state (no further transitions allowed).
  bool get isTerminal => this == resolved;

  /// Whether a transition from [current] to [target] is valid.
  static bool isValidTransition(
    CollateralDiscrepancyStatus current,
    CollateralDiscrepancyStatus target,
  ) {
    if (current.isTerminal) {
      return false;
    }
    if (current == pending) {
      return target == resolved;
    }
    return false;
  }
}

/// Exception thrown when an illegal discrepancy state transition is attempted.
class CollateralDiscrepancyTransitionException implements Exception {
  final String from;
  final String to;
  final String reason;

  const CollateralDiscrepancyTransitionException(
    this.from,
    this.to, {
    this.reason = '',
  });

  @override
  String toString() =>
      'CollateralDiscrepancyTransitionException: Cannot transition status from "$from" to "$to". $reason';
}

/// Clean architecture domain entity representing a collateral discrepancy report (Story 3.4).
///
/// Records discrepancies between the system state and physical reality of collateral items.
/// Each discrepancy includes the reporter's ID, timestamp, reason, and the Shop Owner's
/// decision (resolution, resolved by, resolution notes, resolved at).
///
/// Binds:
/// - FR-16: Independent Per-Item Custody Tracking
/// - AD-6: Granular RBAC & Audit
@immutable
class CollateralDiscrepancy {
  /// Canonical UUIDv4 primary key.
  final String id;

  /// Associated shop tenant UUID boundary.
  final String shopId;

  /// Associated collateral item UUID.
  final String collateralItemId;

  /// User UUID of the staff member who reported the discrepancy.
  final String reportedByUserId;

  /// Documented reason for the discrepancy.
  final String discrepancyReason;

  /// Lifecycle status of the discrepancy.
  final CollateralDiscrepancyStatus status;

  /// User UUID of the Shop Owner who resolved the discrepancy (null while pending).
  final String? resolvedByUserId;

  /// Resolution notes or decision rationale recorded by the Shop Owner.
  final String? resolutionNotes;

  /// UTC timestamp of the Shop Owner's decision (null while pending).
  final DateTime? resolvedAt;

  /// UTC timestamp when the discrepancy was reported.
  final DateTime createdAt;

  /// UTC timestamp of last status change.
  final DateTime updatedAt;

  CollateralDiscrepancy({
    required this.id,
    required this.shopId,
    required this.collateralItemId,
    required this.reportedByUserId,
    required this.discrepancyReason,
    this.status = CollateralDiscrepancyStatus.pending,
    this.resolvedByUserId,
    this.resolutionNotes,
    this.resolvedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc() {
    _validate();
  }

  /// Internal constructor used only for status transitions that do not
  /// require reviewer information (reviewer fields are set separately via
  /// [copyWith] with full validation).
  // ignore: prefer_const_constructors_in_immutables
  CollateralDiscrepancy._statusOnly({
    required this.id,
    required this.shopId,
    required this.collateralItemId,
    required this.reportedByUserId,
    required this.discrepancyReason,
    required this.status,
    this.resolvedByUserId,
    this.resolutionNotes,
    this.resolvedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  void _validate() {
    if (id.trim().isEmpty) {
      throw CollateralDiscrepancyValidationException(
        'Collateral discrepancy ID cannot be empty',
      );
    }
    if (shopId.trim().isEmpty) {
      throw CollateralDiscrepancyValidationException(
        'Shop ID cannot be empty',
      );
    }
    if (collateralItemId.trim().isEmpty) {
      throw CollateralDiscrepancyValidationException(
        'Collateral item ID cannot be empty',
      );
    }
    if (reportedByUserId.trim().isEmpty) {
      throw CollateralDiscrepancyValidationException(
        'Reported by user ID cannot be empty',
      );
    }
    if (discrepancyReason.trim().isEmpty) {
      throw CollateralDiscrepancyValidationException(
        'Discrepancy reason cannot be empty',
      );
    }

    // Decision constraints for resolved status
    if (status == CollateralDiscrepancyStatus.resolved) {
      if (resolvedByUserId == null || resolvedByUserId!.trim().isEmpty) {
        throw CollateralDiscrepancyValidationException(
          'Resolved discrepancies must record the reviewer user ID',
        );
      }
      if (resolutionNotes == null || resolutionNotes!.trim().isEmpty) {
        throw CollateralDiscrepancyValidationException(
          'Decision justification notes are mandatory when resolving a discrepancy',
        );
      }
      if (resolvedAt == null) {
        throw CollateralDiscrepancyValidationException(
          'Resolved discrepancies must record the decision timestamp',
        );
      }
    }
  }

  /// Transitions status to [newStatus]. Throws [CollateralDiscrepancyTransitionException]
  /// if the transition is invalid.
  ///
  /// Reviewer fields (resolved by, notes, timestamp) are intentionally not
  /// touched here — they are set separately by the resolver via [copyWith]
  /// when the Shop Owner records the decision.
  CollateralDiscrepancy transitionStatus(
    CollateralDiscrepancyStatus newStatus,
  ) {
    if (!CollateralDiscrepancyStatus.isValidTransition(status, newStatus)) {
      throw CollateralDiscrepancyTransitionException(
        status.value,
        newStatus.value,
        reason: 'Invalid discrepancy state transition',
      );
    }
    return CollateralDiscrepancy._statusOnly(
      id: id,
      shopId: shopId,
      collateralItemId: collateralItemId,
      reportedByUserId: reportedByUserId,
      discrepancyReason: discrepancyReason,
      status: newStatus,
      resolvedByUserId: resolvedByUserId,
      resolutionNotes: resolutionNotes,
      resolvedAt: resolvedAt,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  /// Returns a copy of this entity with updated fields.
  CollateralDiscrepancy copyWith({
    String? id,
    String? shopId,
    String? collateralItemId,
    String? reportedByUserId,
    String? discrepancyReason,
    CollateralDiscrepancyStatus? status,
    String? resolvedByUserId,
    String? resolutionNotes,
    DateTime? resolvedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CollateralDiscrepancy(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      collateralItemId: collateralItemId ?? this.collateralItemId,
      reportedByUserId: reportedByUserId ?? this.reportedByUserId,
      discrepancyReason: discrepancyReason ?? this.discrepancyReason,
      status: status ?? this.status,
      resolvedByUserId: resolvedByUserId ?? this.resolvedByUserId,
      resolutionNotes: resolutionNotes ?? this.resolutionNotes,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CollateralDiscrepancy &&
        other.id == id &&
        other.shopId == shopId &&
        other.collateralItemId == collateralItemId &&
        other.reportedByUserId == reportedByUserId &&
        other.discrepancyReason == discrepancyReason &&
        other.status == status &&
        other.resolvedByUserId == resolvedByUserId &&
        other.resolutionNotes == resolutionNotes &&
        other.resolvedAt == resolvedAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        shopId,
        collateralItemId,
        reportedByUserId,
        discrepancyReason,
        status,
        resolvedByUserId,
        resolutionNotes,
        resolvedAt,
      );

  @override
  String toString() {
    return 'CollateralDiscrepancy(id: $id, itemId: $collateralItemId, '
        'status: ${status.value}, reason: $discrepancyReason)';
  }
}

