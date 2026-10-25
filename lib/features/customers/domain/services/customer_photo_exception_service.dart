import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/data/local/app_database.dart';
import '../../../../core/permissions/app_permission.dart';
import '../../../../core/permissions/authorization_guard.dart';
import '../../../auth/domain/models/app_user.dart';
import '../../data/daos/customer_photo_exception_dao.dart';
import '../models/customer.dart';
import '../models/customer_photo_exception.dart';

/// Application service coordinating the Customer Photo Exception Request and Shop Owner Approval workflow (Story 2.3).
///
/// Binds:
/// - PRD FR-9: Photo Exception Request & Shop Owner Approval Workflow.
/// - AD-6: Granular RBAC, Owner Administrative Approval, Auditable History.
/// - Dual Customer Binding: Exception bound to both `targetCustomerId` and normalized `customerNic`.
/// - Single-Use Consumption: Consumed atomically upon customer registration.
class CustomerPhotoExceptionService {
  final CustomerPhotoExceptionDao exceptionDao;
  final AppDatabase? db;
  final Uuid _uuid;

  CustomerPhotoExceptionService({
    required this.exceptionDao,
    this.db,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  /// Requests a new customer photo exception.
  ///
  /// Requirements:
  /// - [requester] must be active and possess [AppPermission.registerCustomers].
  /// - [reason] is mandatory and must not be empty/whitespace.
  /// - [targetCustomerId] and [customerNic] are mandatory and bound to the request.
  /// - Initializes exception in [PhotoExceptionStatus.pendingOwnerApproval].
  Future<CustomerPhotoException> requestPhotoException({
    required String shopId,
    required String targetCustomerId,
    required String customerNic,
    required AppUser requester,
    required String reason,
    String? exceptionId,
  }) async {
    // 1. RBAC Guard: Verify requester is active and authorized
    AuthorizationGuard.checkPermission(
      isActive: requester.isActive,
      effectivePermissions: requester.effectivePermissions,
      permission: AppPermission.registerCustomers,
      actionDescription: 'request customer photo KYC exception',
    );

    // 2. Tenant isolation check
    if (requester.shopId != shopId) {
      throw PermissionDeniedException(
        'Access denied: Staff user "${requester.id}" belongs to shop "${requester.shopId}", not "$shopId".',
      );
    }

    // 3. Validation
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw CustomerValidationException(
        'Documented business justification reason is mandatory for photo exception request.',
      );
    }

    final normalizedNic = Customer.normalizeNic(customerNic);
    if (!Customer.isValidNicFormat(normalizedNic)) {
      throw CustomerValidationException(
        'Invalid customer NIC format: "$customerNic".',
      );
    }

    if (targetCustomerId.trim().isEmpty) {
      throw CustomerValidationException('Target customer ID cannot be empty.');
    }

    // 4. Construct domain model
    final now = DateTime.now().toUtc();
    final exception = CustomerPhotoException(
      id: exceptionId ?? _uuid.v4(),
      shopId: shopId,
      targetCustomerId: targetCustomerId.trim(),
      customerNic: normalizedNic,
      requestedByUserId: requester.id,
      requestReason: trimmedReason,
      status: PhotoExceptionStatus.pendingOwnerApproval,
      createdAt: now,
      updatedAt: now,
    );

    // 5. Persist
    await exceptionDao.createException(exception);

    if (db != null) {
      await db!.into(db!.syncQueue).insert(
        SyncQueueCompanion.insert(
          id: _uuid.v4(),
          shopId: shopId,
          idempotencyKey: _uuid.v4(),
          entityType: 'customer_photo_exception',
          entityId: exception.id,
          actionType: 'request_customer_photo_exception',
          payloadJson: jsonEncode({
            'auditCategory': 1,
            'auditEvent': 'customer_photo_exception_requested',
            'actorId': requester.id,
            'targetCustomerId': exception.targetCustomerId,
            'customerNic': exception.customerNic,
            'reason': trimmedReason,
            'shopId': shopId,
            'timestamp': now.toIso8601String(),
          }),
          createdAt: now,
          updatedAt: Value(now),
        ),
      );
    }

    return exception;
  }

  /// Approves a pending photo exception request.
  ///
  /// Requirements:
  /// - [approver] must be active and have [AppRole.shopOwner] role.
  /// - [reviewNotes] is mandatory and must not be empty.
  /// - The target exception must exist in [shopId] and be in [PhotoExceptionStatus.pendingOwnerApproval].
  /// - Updates status to [PhotoExceptionStatus.approved] with approver identity and timestamp.
  Future<CustomerPhotoException> approvePhotoException({
    required String shopId,
    required String exceptionId,
    required AppUser approver,
    required String reviewNotes,
  }) async {
    // 1. Administrative Guard: Strictly restricted to Shop Owner
    AuthorizationGuard.checkOwnerAdministrativeAction(
      isActive: approver.isActive,
      actorRole: approver.role,
      actionDescription: 'approve customer photo exceptions',
    );

    // 2. Tenant isolation check
    if (approver.shopId != shopId) {
      throw PermissionDeniedException(
        'Access denied: Shop Owner "${approver.id}" belongs to shop "${approver.shopId}", not "$shopId".',
      );
    }

    // 3. Mandatory decision note validation
    final trimmedNotes = reviewNotes.trim();
    if (trimmedNotes.isEmpty) {
      throw CustomerValidationException(
        'Decision approval notes are mandatory when approving a photo exception.',
      );
    }

    // 4. Retrieve existing exception
    final existing = await exceptionDao.getExceptionById(shopId, exceptionId);
    if (existing == null) {
      throw CustomerValidationException(
        'Photo exception ID "$exceptionId" not found in shop "$shopId".',
      );
    }

    // 5. Invariant check: Must be in pending state
    if (existing.status != PhotoExceptionStatus.pendingOwnerApproval) {
      throw StateError(
        'Cannot approve photo exception "$exceptionId": current status is "${existing.status.value}", '
        'expected "${PhotoExceptionStatus.pendingOwnerApproval.value}".',
      );
    }

    final now = DateTime.now().toUtc();
    final approved = existing.copyWith(
      status: PhotoExceptionStatus.approved,
      reviewedByUserId: approver.id,
      reviewNotes: trimmedNotes,
      reviewedAt: now,
      updatedAt: now,
    );

    await exceptionDao.updateException(approved);

    if (db != null) {
      await db!.into(db!.syncQueue).insert(
        SyncQueueCompanion.insert(
          id: _uuid.v4(),
          shopId: shopId,
          idempotencyKey: _uuid.v4(),
          entityType: 'customer_photo_exception',
          entityId: approved.id,
          actionType: 'approve_customer_photo_exception',
          payloadJson: jsonEncode({
            'auditCategory': 1,
            'auditEvent': 'customer_photo_exception_approved',
            'actorId': approver.id,
            'requesterId': existing.requestedByUserId,
            'targetCustomerId': existing.targetCustomerId,
            'customerNic': existing.customerNic,
            'reason': existing.requestReason,
            'reviewNotes': trimmedNotes,
            'shopId': shopId,
            'timestamp': now.toIso8601String(),
          }),
          createdAt: now,
          updatedAt: Value(now),
        ),
      );
    }

    return approved;
  }

  /// Rejects a pending photo exception request.
  ///
  /// Requirements:
  /// - [reviewer] must be active and have [AppRole.shopOwner] role.
  /// - [reviewNotes] is mandatory and must not be empty.
  /// - The target exception must exist in [shopId] and be in [PhotoExceptionStatus.pendingOwnerApproval].
  /// - Updates status to [PhotoExceptionStatus.rejected] with reviewer identity and timestamp.
  Future<CustomerPhotoException> rejectPhotoException({
    required String shopId,
    required String exceptionId,
    required AppUser reviewer,
    required String reviewNotes,
  }) async {
    // 1. Administrative Guard: Strictly restricted to Shop Owner
    AuthorizationGuard.checkOwnerAdministrativeAction(
      isActive: reviewer.isActive,
      actorRole: reviewer.role,
      actionDescription: 'reject customer photo exceptions',
    );

    // 2. Tenant isolation check
    if (reviewer.shopId != shopId) {
      throw PermissionDeniedException(
        'Access denied: Shop Owner "${reviewer.id}" belongs to shop "${reviewer.shopId}", not "$shopId".',
      );
    }

    // 3. Mandatory rejection note validation
    final trimmedNotes = reviewNotes.trim();
    if (trimmedNotes.isEmpty) {
      throw CustomerValidationException(
        'Mandatory rejection note is required when rejecting a photo exception.',
      );
    }

    // 4. Retrieve existing exception
    final existing = await exceptionDao.getExceptionById(shopId, exceptionId);
    if (existing == null) {
      throw CustomerValidationException(
        'Photo exception ID "$exceptionId" not found in shop "$shopId".',
      );
    }

    // 5. Invariant check: Must be in pending state
    if (existing.status != PhotoExceptionStatus.pendingOwnerApproval) {
      throw StateError(
        'Cannot reject photo exception "$exceptionId": current status is "${existing.status.value}", '
        'expected "${PhotoExceptionStatus.pendingOwnerApproval.value}".',
      );
    }

    final now = DateTime.now().toUtc();
    final rejected = existing.copyWith(
      status: PhotoExceptionStatus.rejected,
      reviewedByUserId: reviewer.id,
      reviewNotes: trimmedNotes,
      reviewedAt: now,
      updatedAt: now,
    );

    await exceptionDao.updateException(rejected);

    if (db != null) {
      await db!.into(db!.syncQueue).insert(
        SyncQueueCompanion.insert(
          id: _uuid.v4(),
          shopId: shopId,
          idempotencyKey: _uuid.v4(),
          entityType: 'customer_photo_exception',
          entityId: rejected.id,
          actionType: 'reject_customer_photo_exception',
          payloadJson: jsonEncode({
            'auditCategory': 1,
            'auditEvent': 'customer_photo_exception_rejected',
            'actorId': reviewer.id,
            'requesterId': existing.requestedByUserId,
            'targetCustomerId': existing.targetCustomerId,
            'customerNic': existing.customerNic,
            'reason': existing.requestReason,
            'reviewNotes': trimmedNotes,
            'shopId': shopId,
            'timestamp': now.toIso8601String(),
          }),
          createdAt: now,
          updatedAt: Value(now),
        ),
      );
    }

    return rejected;
  }

  /// Retrieves all pending exception requests for the shop owner review queue.
  Future<List<CustomerPhotoException>> getPendingExceptions(
    String shopId, {
    required AppUser viewer,
  }) async {
    if (!viewer.isActive) {
      throw const PermissionDeniedException('Access denied: User account is deactivated.');
    }
    if (viewer.shopId != shopId) {
      throw PermissionDeniedException(
        'Access denied: User belongs to shop "${viewer.shopId}", not "$shopId".',
      );
    }
    return exceptionDao.getPendingExceptions(shopId);
  }
}
