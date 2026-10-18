import 'package:meta/meta.dart';
import 'customer.dart';

/// Lifecycle statuses for customer KYC photograph exceptions (Story 2.3, FR-9, AD-6).
enum PhotoExceptionStatus {
  /// Initial state: Counter staff requested an exception; awaiting Shop Owner decision.
  pendingOwnerApproval('pending_owner_approval'),

  /// Shop Owner approved the exception; eligible for single-use customer profile creation.
  approved('approved'),

  /// Shop Owner rejected the exception; customer registration remains blocked.
  rejected('rejected'),

  /// Consumed during customer registration; strictly single-use to prevent reuse attacks.
  consumed('consumed');

  final String value;
  const PhotoExceptionStatus(this.value);

  /// Resolves a [PhotoExceptionStatus] from its canonical database string.
  static PhotoExceptionStatus fromString(String val) {
    for (final status in PhotoExceptionStatus.values) {
      if (status.value == val) return status;
    }
    throw ArgumentError.value(val, 'status', 'Invalid PhotoExceptionStatus value');
  }
}

/// Clean architecture domain entity representing a customer KYC photograph exception (Story 2.3).
///
/// Binds:
/// - Architecture Decision AD-6: Granular RBAC, Owner Approval, Auditable History.
/// - PRD FR-9: Formal photo exception workflow for hardware failure or physical constraints.
/// - Dual Customer Binding: Bound to both [targetCustomerId] and normalized [customerNic].
/// - Single-Use Consumption: Transitions to [PhotoExceptionStatus.consumed] upon profile creation.
@immutable
class CustomerPhotoException {
  /// Canonical UUIDv4 identifier.
  final String id;

  /// Associated shop tenant UUID boundary.
  final String shopId;

  /// Target customer UUID generated for this onboarding session.
  final String targetCustomerId;

  /// Normalized National Identity Card (NIC) number of the customer.
  final String customerNic;

  /// User UUID of the staff member who initiated the exception request.
  final String requestedByUserId;

  /// Mandatory documented business justification for requesting the exception.
  final String requestReason;

  /// Lifecycle status of the exception request.
  final PhotoExceptionStatus status;

  /// User UUID of the Shop Owner who approved or rejected the request (null while pending).
  final String? reviewedByUserId;

  /// Mandatory decision notes or rejection reasons recorded by the Shop Owner (null while pending).
  final String? reviewNotes;

  /// UTC timestamp of the Shop Owner's decision (null while pending).
  final DateTime? reviewedAt;

  /// UTC timestamp when the exception was requested.
  final DateTime createdAt;

  /// UTC timestamp of last status change.
  final DateTime updatedAt;

  CustomerPhotoException({
    required this.id,
    required this.shopId,
    required this.targetCustomerId,
    required String customerNic,
    required this.requestedByUserId,
    required this.requestReason,
    this.status = PhotoExceptionStatus.pendingOwnerApproval,
    this.reviewedByUserId,
    this.reviewNotes,
    this.reviewedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : customerNic = Customer.normalizeNic(customerNic),
        createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc() {
    _validate();
  }

  void _validate() {
    if (id.trim().isEmpty) {
      throw CustomerValidationException('Photo exception ID cannot be empty');
    }
    if (shopId.trim().isEmpty) {
      throw CustomerValidationException('Shop ID cannot be empty');
    }
    if (targetCustomerId.trim().isEmpty) {
      throw CustomerValidationException('Target customer ID cannot be empty');
    }
    if (customerNic.trim().isEmpty) {
      throw CustomerValidationException('Customer NIC cannot be empty');
    }
    if (!Customer.isValidNicFormat(customerNic)) {
      throw CustomerValidationException('Invalid customer NIC format: "$customerNic"');
    }
    if (requestedByUserId.trim().isEmpty) {
      throw CustomerValidationException('Requester user ID cannot be empty');
    }
    if (requestReason.trim().isEmpty) {
      throw CustomerValidationException('Exception request reason is mandatory');
    }

    // Decision constraints for non-pending statuses
    if (status == PhotoExceptionStatus.approved ||
        status == PhotoExceptionStatus.rejected ||
        status == PhotoExceptionStatus.consumed) {
      if (reviewedByUserId == null || reviewedByUserId!.trim().isEmpty) {
        throw CustomerValidationException(
          'Reviewed exceptions must record the reviewer user ID',
        );
      }
      if (reviewNotes == null || reviewNotes!.trim().isEmpty) {
        throw CustomerValidationException(
          'Decision justification notes are mandatory when approving or rejecting an exception',
        );
      }
      if (reviewedAt == null) {
        throw CustomerValidationException(
          'Reviewed exceptions must record the decision timestamp',
        );
      }
    }
  }

  /// Returns a copy of this entity with updated fields.
  CustomerPhotoException copyWith({
    String? id,
    String? shopId,
    String? targetCustomerId,
    String? customerNic,
    String? requestedByUserId,
    String? requestReason,
    PhotoExceptionStatus? status,
    String? reviewedByUserId,
    String? reviewNotes,
    DateTime? reviewedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CustomerPhotoException(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      targetCustomerId: targetCustomerId ?? this.targetCustomerId,
      customerNic: customerNic ?? this.customerNic,
      requestedByUserId: requestedByUserId ?? this.requestedByUserId,
      requestReason: requestReason ?? this.requestReason,
      status: status ?? this.status,
      reviewedByUserId: reviewedByUserId ?? this.reviewedByUserId,
      reviewNotes: reviewNotes ?? this.reviewNotes,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
