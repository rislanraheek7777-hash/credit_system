import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import '../../../../core/data/local/app_database.dart';
import '../../../../core/permissions/app_permission.dart';
import '../../../auth/data/services/audit_service.dart';
import '../../../auth/domain/models/app_user.dart';
import '../../data/daos/customer_dao.dart';
import '../models/customer_masking.dart';

/// Exception thrown when an unauthorized user attempts to access customer data or photos (Story 2.6 AC-3).
class CustomerAccessForbiddenException implements Exception {
  final String message;
  final int statusCode;

  const CustomerAccessForbiddenException(
    this.message, {
    this.statusCode = 403,
  });

  @override
  String toString() => 'CustomerAccessForbiddenException ($statusCode): $message';
}

/// DTO representing a customer profile response with server-enforced masking metadata (Story 2.6).
@immutable
class CustomerProfileDto {
  final int id;
  final String shopId;
  final String fullName;
  final String nic;
  final String phone;
  final String? address;
  final String? photoUri;
  final String? photoHash;
  final bool isMasked;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CustomerProfileDto({
    required this.id,
    required this.shopId,
    required this.fullName,
    required this.nic,
    required this.phone,
    required this.address,
    required this.photoUri,
    required this.photoHash,
    required this.isMasked,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'shopId': shopId,
        'fullName': fullName,
        'nic': nic,
        'phone': phone,
        'address': address,
        'photoUri': photoUri,
        'photoHash': photoHash,
        'isMasked': isMasked,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}

/// Cryptographic signed URL generator and validator for customer photographs (Story 2.6 AC-2 & AC-3).
///
/// Produces short-lived signed URLs valid for <= 15 minutes using HMAC-SHA256.
class CustomerPhotoUrlSigner {
  final String secretKey;

  /// Default validity duration: 15 minutes (PRD FR-6, Story 2.6 AC-2).
  static const Duration defaultValidity = Duration(minutes: 15);

  const CustomerPhotoUrlSigner({required this.secretKey});

  /// Generates a signed photo URL for [photoUri] valid until [expiresAt].
  String generateSignedUrl({
    required String shopId,
    required String customerId,
    required String photoUri,
    DateTime? expiresAt,
  }) {
    final expiry = expiresAt ?? DateTime.now().toUtc().add(defaultValidity);
    final expiryEpochSeconds = expiry.millisecondsSinceEpoch ~/ 1000;

    final dataToSign = '$shopId:$customerId:$photoUri:$expiryEpochSeconds';
    final hmac = Hmac(sha256, utf8.encode(secretKey));
    final signature = hmac.convert(utf8.encode(dataToSign)).toString();

    final queryParams = Uri(
      queryParameters: {
        'shopId': shopId,
        'customerId': customerId,
        'photoUri': photoUri,
        'expires': expiryEpochSeconds.toString(),
        'sig': signature,
      },
    ).query;

    return '/api/v1/photos/customer?$queryParams';
  }

  /// Validates a signed URL. Returns true if signature is valid and timestamp has not expired.
  bool verifySignedUrl({
    required String shopId,
    required String customerId,
    required String photoUri,
    required int expiresEpochSeconds,
    required String signature,
  }) {
    final nowEpochSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    if (nowEpochSeconds > expiresEpochSeconds) {
      return false; // Expired
    }

    final dataToSign = '$shopId:$customerId:$photoUri:$expiresEpochSeconds';
    final hmac = Hmac(sha256, utf8.encode(secretKey));
    final expectedSignature = hmac.convert(utf8.encode(dataToSign)).toString();

    return signature == expectedSignature;
  }
}

/// Server-side customer retrieval service with RBAC enforcement and PII masking (Story 2.6).
///
/// Rules:
/// 1. If caller lacks `viewCustomers` permission: 403 Forbidden + Category 14 security audit event.
/// 2. If caller has `viewCustomers` but lacks `viewSensitiveCustomerData`:
///    - Returns masked NIC (`1985****5678`)
///    - Returns masked telephone (`+94 77 **** 123` or `077 **** 123`)
///    - Omits residential address (`null`)
///    - Omits photo URI (`null`)
///    - `isMasked` = true
/// 3. If caller has `viewSensitiveCustomerData` (or Shop Owner role):
///    - Returns unmasked NIC
///    - Returns unmasked telephone
///    - Returns unmasked residential address
///    - Returns cryptographically signed photo URL valid for <= 15 minutes
///    - `isMasked` = false
/// 4. Direct photo access without valid signature or permission: 403 Forbidden + Category 14 event.
class CustomerDataMaskingService {
  final CustomerDao customerDao;
  final CustomerPhotoUrlSigner photoSigner;
  final AuditService? auditService;
  final AppDatabase? db;

  const CustomerDataMaskingService({
    required this.customerDao,
    required this.photoSigner,
    this.auditService,
    this.db,
  });

  /// Retrieves and masks customer data according to [actor]'s permissions.
  Future<CustomerProfileDto> getCustomerProfile({
    required String shopId,
    required int customerId,
    required AppUser actor,
  }) async {
    // Cross-tenant guard
    if (actor.shopId != shopId && !actor.role.isOwner) {
      await _recordSecurityAuditEvent(
        shopId: shopId,
        actorId: actor.id,
        actionType: 'unauthorized_cross_tenant_customer_access',
        targetCustomerId: customerId.toString(),
        reason: 'Cross-tenant customer profile access attempt denied',
      );
      throw const CustomerAccessForbiddenException(
        'Access denied: Cross-tenant access is strictly forbidden.',
      );
    }

    // RBAC: Requires at least viewCustomers
    final hasViewPermission =
        actor.hasPermission(AppPermission.viewCustomers) || actor.role.isOwner;
    if (!hasViewPermission) {
      await _recordSecurityAuditEvent(
        shopId: shopId,
        actorId: actor.id,
        actionType: 'unauthorized_customer_profile_access',
        targetCustomerId: customerId.toString(),
        reason: 'User lacks viewCustomers permission',
      );
      throw const CustomerAccessForbiddenException(
        'Access denied: viewCustomers permission is required.',
      );
    }

    final customer = await customerDao.getCustomerById(shopId, customerId);
    if (customer == null) {
      throw StateError('Customer "$customerId" not found in shop "$shopId".');
    }

    // Check if actor has sensitive data viewing permission
    final canViewSensitive =
        actor.hasPermission(AppPermission.viewSensitiveCustomerData) ||
            actor.role.isOwner;

    if (canViewSensitive) {
      // AC-2: Full unmasked profile + signed photo URL valid <= 15 mins
      String? signedPhotoUrl;
      if (customer.photoUri != null && customer.photoUri!.isNotEmpty) {
        signedPhotoUrl = photoSigner.generateSignedUrl(
          shopId: shopId,
          customerId: customer.id.toString(),
          photoUri: customer.photoUri!,
        );
      }

      return CustomerProfileDto(
        id: customer.id,
        shopId: customer.shopId,
        fullName: customer.fullName,
        nic: customer.nic,
        phone: customer.phone,
        address: customer.address,
        photoUri: signedPhotoUrl,
        photoHash: customer.photoHash,
        isMasked: false,
        createdAt: customer.createdAt,
        updatedAt: customer.updatedAt,
      );
    } else {
      // AC-1: Masked NIC, masked telephone, omitted address and omitted photo URL
      return CustomerProfileDto(
        id: customer.id,
        shopId: customer.shopId,
        fullName: customer.fullName,
        nic: maskNic(customer.nic),
        phone: maskPhone(customer.phone),
        address: null,
        photoUri: null,
        photoHash: customer.photoHash,
        isMasked: true,
        createdAt: customer.createdAt,
        updatedAt: customer.updatedAt,
      );
    }
  }

  /// Authorizes access to a customer photograph file via signed URL or actor permissions (AC-3).
  Future<String> authorizePhotoAccess({
    required String shopId,
    required String customerId,
    required String photoUri,
    required int expiresEpochSeconds,
    required String signature,
    required AppUser actor,
  }) async {
    final isValidSignature = photoSigner.verifySignedUrl(
      shopId: shopId,
      customerId: customerId,
      photoUri: photoUri,
      expiresEpochSeconds: expiresEpochSeconds,
      signature: signature,
    );

    if (!isValidSignature) {
      await _recordSecurityAuditEvent(
        shopId: shopId,
        actorId: actor.id,
        actionType: 'unauthorized_customer_photo_access_invalid_signature',
        targetCustomerId: customerId,
        reason: 'Expired, invalid, or tampered photo signature URL',
      );
      throw const CustomerAccessForbiddenException(
        'Access denied: Photo URL signature is invalid or expired.',
      );
    }

    return photoUri;
  }

  /// Records a Category 14 Security Audit Event into PostgreSQL and/or SQLite SyncQueue.
  Future<void> _recordSecurityAuditEvent({
    required String shopId,
    required String actorId,
    required String actionType,
    required String targetCustomerId,
    required String reason,
  }) async {
    // 1. PostgreSQL append-only audit event if remote executor available
    if (auditService != null) {
      try {
        await auditService!.recordAuditEvent(
          shopId: shopId,
          eventCategory: 14,
          actionType: actionType,
          actorId: actorId,
          targetEntityType: 'customer',
          targetEntityId: targetCustomerId,
          reason: reason,
        );
      } catch (_) {
        // Continue to queue locally if remote fails
      }
    }

    // 2. Offline SyncQueue recording in SQLite
    if (db != null) {
      try {
        final now = DateTime.now().toUtc();
        final idempotencyKey =
            'audit_sec_${shopId}_${targetCustomerId}_${now.microsecondsSinceEpoch}';
        await db!.into(db!.syncQueue).insert(
          SyncQueueCompanion.insert(
            id: idempotencyKey,
            shopId: shopId,
            idempotencyKey: idempotencyKey,
            entityType: 'security_event',
            entityId: targetCustomerId,
            actionType: actionType,
            payloadJson: jsonEncode({
              'eventCategory': 14,
              'categoryName': 'security_events',
              'actorId': actorId,
              'targetEntityType': 'customer',
              'targetEntityId': targetCustomerId,
              'reason': reason,
              'timestamp': now.toIso8601String(),
            }),
            createdAt: now,
          ),
        );
      } catch (_) {
        // Best effort
      }
    }
  }
}
