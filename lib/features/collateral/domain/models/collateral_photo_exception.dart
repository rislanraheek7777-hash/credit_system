import 'package:meta/meta.dart';

/// Validation exception thrown when collateral photo exception invariants are violated.
class CollateralPhotoExceptionValidationException extends ArgumentError {
  CollateralPhotoExceptionValidationException(super.message);
}

/// Exception thrown when an illegal photo exception state transition is attempted.
class CollateralPhotoExceptionTransitionException implements Exception {
  final String from;
  final String to;
  final String reason;

  const CollateralPhotoExceptionTransitionException(
    this.from,
    this.to, {
    this.reason = '',
  });

  @override
  String toString() =>
      'CollateralPhotoExceptionTransitionException: Cannot transition status from "$from" to "$to". $reason';
}

/// Collateral photo exception lifecycle status (Story 3.2, FR-15, AD-6).
///
/// Valid transitions:
///   `pendingOwnerApproval` → `approved`
///   `pendingOwnerApproval` → `rejected`
///   `approved` → `consumed` (single-use during registration)
///
/// Invalid transitions throw [CollateralPhotoExceptionTransitionException].
enum CollateralPhotoExceptionStatus {
  pendingOwnerApproval('pending_owner_approval'),
  approved('approved'),
  rejected('rejected'),
  consumed('consumed');

  final String value;
  const CollateralPhotoExceptionStatus(this.value);

  /// Resolves [CollateralPhotoExceptionStatus] from raw database text.
  static CollateralPhotoExceptionStatus fromValue(String value) {
    for (final status in CollateralPhotoExceptionStatus.values) {
      if (status.value == value) {
        return status;
      }
    }
    throw ArgumentError.value(
      value,
      'value',
      'Invalid collateral photo exception status',
    );
  }

  /// Whether this is a terminal state (no further transitions allowed).
  bool get isTerminal =>
      this == rejected || this == consumed;

  /// Whether a transition from [current] to [target] is valid.
  static bool isValidTransition(
    CollateralPhotoExceptionStatus current,
    CollateralPhotoExceptionStatus target,
  ) {
    if (current.isTerminal) {
      return false;
    }
    if (current == pendingOwnerApproval) {
      return target == approved || target == rejected;
    }
    if (current == approved) {
      return target == consumed;
    }
    return false;
  }
}

/// Clean architecture domain entity representing a collateral photo exception request (Story 3.2).
///
/// Binds:
/// - FR-15: Mandatory Collateral Photographs & Shop Owner Exception Workflow.
/// - AD-6: Granular RBAC, Owner Approval, Auditable History.
/// - Dual Binding: Exception bound to both `shopId` and `collateralItemId`.
/// - Single-Use Consumption: Transitions to [CollateralPhotoExceptionStatus.consumed] upon registration.
@immutable
class CollateralPhotoException {
  /// Canonical UUIDv4 identifier.
  final String id;

  /// Associated shop tenant UUID boundary.
  final String shopId;

  /// Associated collateral item UUID.
  final String collateralItemId;

  /// User UUID of the staff member who initiated the exception request.
  final String requestedByUserId;

  /// Mandatory documented business justification for requesting the exception.
  final String requestReason;

  /// Lifecycle status of the exception request.
  final CollateralPhotoExceptionStatus status;

  /// User UUID of the Shop Owner who approved or rejected the request (null while pending).
  final String? reviewedByUserId;

  /// Mandatory decision notes or rejection reasons recorded by the Shop Owner.
  final String? reviewNotes;

  /// UTC timestamp of the Shop Owner's decision (null while pending).
  final DateTime? reviewedAt;

  /// UTC timestamp when the exception was requested.
  final DateTime createdAt;

  /// UTC timestamp of last status change.
  final DateTime updatedAt;

  CollateralPhotoException({
    required this.id,
    required this.shopId,
    required this.collateralItemId,
    required this.requestedByUserId,
    required this.requestReason,
    this.status = CollateralPhotoExceptionStatus.pendingOwnerApproval,
    this.reviewedByUserId,
    this.reviewNotes,
    this.reviewedAt,
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
  CollateralPhotoException._statusOnly({
    required this.id,
    required this.shopId,
    required this.collateralItemId,
    required this.requestedByUserId,
    required this.requestReason,
    required this.status,
    this.reviewedByUserId,
    this.reviewNotes,
    this.reviewedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  void _validate() {
    if (id.trim().isEmpty) {
      throw CollateralPhotoExceptionValidationException(
        'Collateral photo exception ID cannot be empty',
      );
    }
    if (shopId.trim().isEmpty) {
      throw CollateralPhotoExceptionValidationException(
        'Shop ID cannot be empty',
      );
    }
    if (collateralItemId.trim().isEmpty) {
      throw CollateralPhotoExceptionValidationException(
        'Collateral item ID cannot be empty',
      );
    }
    if (requestedByUserId.trim().isEmpty) {
      throw CollateralPhotoExceptionValidationException(
        'Requester user ID cannot be empty',
      );
    }
    if (requestReason.trim().isEmpty) {
      throw CollateralPhotoExceptionValidationException(
        'Exception request reason is mandatory',
      );
    }

    // Decision constraints for non-pending statuses
    if (status == CollateralPhotoExceptionStatus.approved ||
        status == CollateralPhotoExceptionStatus.rejected ||
        status == CollateralPhotoExceptionStatus.consumed) {
      if (reviewedByUserId == null || reviewedByUserId!.trim().isEmpty) {
        throw CollateralPhotoExceptionValidationException(
          'Reviewed exceptions must record the reviewer user ID',
        );
      }
      if (reviewNotes == null || reviewNotes!.trim().isEmpty) {
        throw CollateralPhotoExceptionValidationException(
          'Decision justification notes are mandatory when approving or rejecting an exception',
        );
      }
      if (reviewedAt == null) {
        throw CollateralPhotoExceptionValidationException(
          'Reviewed exceptions must record the decision timestamp',
        );
      }
    }
  }

  /// Transitions status to [newStatus]. Throws [CollateralPhotoExceptionTransitionException]
  /// if the transition is invalid.
  CollateralPhotoException transitionStatus(
    CollateralPhotoExceptionStatus newStatus,
  ) {
    if (!CollateralPhotoExceptionStatus.isValidTransition(status, newStatus)) {
      throw CollateralPhotoExceptionTransitionException(
        status.value,
        newStatus.value,
        reason: 'Invalid photo exception state transition',
      );
    }
    return CollateralPhotoException._statusOnly(
      id: id,
      shopId: shopId,
      collateralItemId: collateralItemId,
      requestedByUserId: requestedByUserId,
      requestReason: requestReason,
      status: newStatus,
      reviewedByUserId: reviewedByUserId,
      reviewNotes: reviewNotes,
      reviewedAt: reviewedAt,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  /// Returns a copy of this entity with updated fields.
  CollateralPhotoException copyWith({
    String? id,
    String? shopId,
    String? collateralItemId,
    String? requestedByUserId,
    String? requestReason,
    CollateralPhotoExceptionStatus? status,
    String? reviewedByUserId,
    String? reviewNotes,
    DateTime? reviewedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CollateralPhotoException(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      collateralItemId: collateralItemId ?? this.collateralItemId,
      requestedByUserId: requestedByUserId ?? this.requestedByUserId,
      requestReason: requestReason ?? this.requestReason,
      status: status ?? this.status,
      reviewedByUserId: reviewedByUserId ?? this.reviewedByUserId,
      reviewNotes: reviewNotes ?? this.reviewNotes,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CollateralPhotoException &&
        other.id == id &&
        other.shopId == shopId &&
        other.collateralItemId == collateralItemId &&
        other.requestedByUserId == requestedByUserId &&
        other.requestReason == requestReason &&
        other.status == status &&
        other.reviewedByUserId == reviewedByUserId &&
        other.reviewNotes == reviewNotes &&
        other.reviewedAt == reviewedAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        shopId,
        collateralItemId,
        requestedByUserId,
        requestReason,
        status,
        reviewedByUserId,
        reviewNotes,
        reviewedAt,
      );

  @override
  String toString() {
    return 'CollateralPhotoException(id: $id, itemId: $collateralItemId, status: ${status.value}, reason: $requestReason)';
  }
}
