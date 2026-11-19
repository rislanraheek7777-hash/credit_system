import 'dart:typed_data';
import 'package:meta/meta.dart';
import '../../../../core/data/local/app_database.dart';
import '../../../../core/sync/models/sync_queue_entry.dart';
import '../../../../core/storage/photo_storage_service.dart';
import '../../data/daos/customer_dao.dart';
import '../../data/daos/customer_photo_exception_dao.dart';
import '../models/customer.dart';
import '../models/customer_photo_exception.dart';
import 'customer_photo_compressor.dart';

/// Request payload for registering a new customer profile.
@immutable
class RegisterCustomerRequest {
  /// Pre-onboarding session identifier (e.g. a UUID generated for the
  /// registration session). Used for the photo-exception dual binding and
  /// photo file naming — it is NOT the customer's primary key; the database
  /// assigns an auto-increment id on insert.
  final String id;
  final String shopId;
  final String fullName;
  final String nic;
  final String phone;
  final String address;

  /// Raw customer KYC photograph bytes (from camera capture or file upload).
  /// Optional — registration proceeds without a photograph when omitted.
  final Uint8List? rawPhotoBytes;

  /// Approved customer photo KYC exception identifier (Story 2.3).
  /// Required if [rawPhotoBytes] is omitted. Must be approved and bound to this customer.
  final String? photoExceptionId;

  /// When true, permits registration to proceed despite a shared-phone match.
  /// Set only after staff clicks "Confirm separate individual sharing phone number."
  final bool confirmSharedPhone;

  /// ID of the staff member who confirmed the shared-phone resolution.
  /// Required when [confirmSharedPhone] is true.
  final String? confirmingStaffId;

  const RegisterCustomerRequest({
    required this.id,
    required this.shopId,
    required this.fullName,
    required this.nic,
    required this.phone,
    required this.address,
    this.rawPhotoBytes,
    this.photoExceptionId,
    this.confirmSharedPhone = false,
    this.confirmingStaffId,
  });
}

/// Application service coordinating customer KYC registration and photo processing (Story 2.2, Story 2.3).
///
/// Business Rules:
/// 1. Customer photograph is optional. If photo bytes are provided:
///    - Optimizes/compresses via [CustomerPhotoCompressor] (<= 1600px, <= 500 KB, JPEG).
///    - Persists file in sandboxed app-private storage (`photos/{shopId}/customers/`).
///    - Updates customer metadata with relative path and SHA-256 hash.
/// 2. Reverts and cleans up written photo files if database insertion fails (ACID hygiene).
/// 3. Stores only metadata in SQLite; raw image bytes are strictly excluded from SQL tables.
/// 4. Photo Exception workflow (Story 2.3):
///    - Only approved exceptions bound to the exact [targetCustomerId] and normalized [customerNic]
///      can unblock registration.
///    - Exception is atomically consumed to guarantee single-use.
///    - No caller-controlled boolean or direct parameter is allowed to bypass photo requirements.
class CustomerRegistrationService {
  final CustomerDao customerDao;
  final CustomerPhotoExceptionDao? exceptionDao;
  final CustomerPhotoCompressor compressor;
  final PhotoStorageService storageService;
  final AppDatabase? db;

  const CustomerRegistrationService({
    required this.customerDao,
    this.exceptionDao,
    this.compressor = const CustomerPhotoCompressor(),
    this.storageService = const PhotoStorageService(),
    this.db,
  });

  /// Registers and persists a new customer profile.
  ///
  /// Customer photograph is optional: registration proceeds without a photograph
  /// when [request.rawPhotoBytes] is null or empty and no [request.photoExceptionId] is provided.
  Future<Customer> registerCustomer(RegisterCustomerRequest request) async {
    final hasPhotoBytes =
        request.rawPhotoBytes != null && request.rawPhotoBytes!.isNotEmpty;
    final hasExceptionId =
        request.photoExceptionId != null && request.photoExceptionId!.trim().isNotEmpty;

    // 1a. Phone format validation — reject ambiguous or invalid inputs rather than guessing.
    if (!Customer.isValidPhoneFormat(request.phone)) {
      throw CustomerValidationException(
        'Invalid phone number: "${request.phone}".',
      );
    }

    // 1b. Duplicate NIC detection — scoped to the current shop.
    // A duplicate NIC blocks registration; the existing profile is surfaced
    // so staff can open it instead of creating a duplicate. A soft-deleted
    // holder is an unreachable dead-end, so it gets an honest message about
    // the NIC being unreusable.
    final existingByNic = await customerDao.getCustomerByNic(request.shopId, request.nic);
    if (existingByNic != null) {
      if (existingByNic.deletedAt != null) {
        throw DuplicateNicException(
          existingByNic,
          message:
              'A deleted customer record already holds this NIC within ${request.shopId}. NICs cannot be reused. Contact the shop owner.',
        );
      }
      throw DuplicateNicException(
        existingByNic,
        message:
            'Customer profile already exists for this NIC within ${request.shopId}',
      );
    }

    // 1c. Shared-phone detection — scoped to the current shop.
    // A matching phone with a different NIC is a non-blocking warning.
    // Registration proceeds only after explicit staff confirmation.
    final sharedPhoneCustomers =
        await customerDao.findCustomersByPhone(request.shopId, request.phone);
    final hasSharedPhoneMatch = sharedPhoneCustomers.isNotEmpty;
    if (hasSharedPhoneMatch &&
        (!request.confirmSharedPhone || request.confirmingStaffId == null)) {
      throw SharedPhoneDuplicateException(
        sharedPhoneCustomers,
        request.phone,
        message: 'Phone number shared with existing customer',
      );
    }

    // 2. Photo Exception Workflow (Story 2.3)
    if (!hasPhotoBytes && hasExceptionId) {
      if (exceptionDao == null) {
        throw StateError(
          'CustomerPhotoExceptionDao must be provided to process photo exceptions.',
        );
      }

      final exception = await exceptionDao!.getExceptionById(
        request.shopId,
        request.photoExceptionId!,
      );
      if (exception == null) {
        throw CustomerValidationException(
          'Photo exception ID "${request.photoExceptionId}" not found in shop "${request.shopId}".',
        );
      }

      // Dual customer binding verification
      final normalizedNic = Customer.normalizeNic(request.nic);
      if (exception.targetCustomerId != request.id ||
          exception.customerNic != normalizedNic) {
        throw CustomerValidationException(
          'Dual customer binding violation: Photo exception "${request.photoExceptionId}" is bound to '
          'customerId "${exception.targetCustomerId}" and NIC "${exception.customerNic}", '
          'which does not match registration customerId "${request.id}" and NIC "$normalizedNic".',
        );
      }

      // Approval status verification
      if (exception.status != PhotoExceptionStatus.approved) {
        throw CustomerValidationException(
          'Customer profile creation blocked: Photo exception is in state "${exception.status.value}", '
          'not "${PhotoExceptionStatus.approved.value}".',
        );
      }

      // Shop Owner approval verification
      if (exception.reviewedByUserId == null ||
          exception.reviewedByUserId!.trim().isEmpty) {
        throw CustomerValidationException(
          'Customer profile creation blocked: Photo exception lacks Shop Owner approval record.',
        );
      }

      // Construct domain Customer entity without photograph metadata.
      // The pre-onboarding session id ([RegisterCustomerRequest.id]) is only
      // used for the photo-exception dual binding; the database assigns the
      // auto-increment primary key on insert.
      const pendingId = 0;
      final customer = Customer(
        id: pendingId,
        shopId: request.shopId,
        fullName: request.fullName,
        nic: request.nic,
        phone: request.phone,
        address: request.address,
        photoUri: null,
        photoHash: null,
      );

      // Persist customer record and consume exception within an atomic database transaction
      final database = db ?? customerDao.attachedDatabase;
      var createdId = pendingId;
      await database.transaction(() async {
        createdId = await customerDao.createCustomer(customer);
        if (hasSharedPhoneMatch) {
          await _recordSharedPhoneSyncEvent(
            database,
            request,
            sharedPhoneCustomers,
            createdId,
          );
        }
        await exceptionDao!.consumeException(
          request.shopId,
          request.photoExceptionId!,
          targetCustomerId: request.id,
          customerNic: request.nic,
        );
      });

      return customer.copyWith(id: createdId);
    }

    // 3. Standard Camera / Photo Flow (Story 2.2) — photograph is optional.
    String? relativePath;
    String? photoHash;
    if (hasPhotoBytes) {
      final compressionResult = await compressor.compress(request.rawPhotoBytes!);

      relativePath = await storageService.saveCustomerPhoto(
        shopId: request.shopId,
        customerId: request.id,
        bytes: compressionResult.bytes,
      );
      photoHash = compressionResult.sha256Hash;
    }

    // The pre-onboarding session id ([RegisterCustomerRequest.id]) names the
    // stored photo file; the database assigns the customer's auto-increment
    // primary key on insert.
    final customer = Customer(
      id: 0,
      shopId: request.shopId,
      fullName: request.fullName,
      nic: request.nic,
      phone: request.phone,
      address: request.address,
      photoUri: relativePath,
      photoHash: photoHash,
    );

    try {
      final database = db ?? customerDao.attachedDatabase;
      var createdId = 0;
      await database.transaction(() async {
        createdId = await customerDao.createCustomer(customer);
        if (hasSharedPhoneMatch) {
          await _recordSharedPhoneSyncEvent(
            database,
            request,
            sharedPhoneCustomers,
            createdId,
          );
        }
      });
      return customer.copyWith(id: createdId);
    } catch (e) {
      if (relativePath != null) {
        await storageService.deletePhotoIfExists(relativePath);
      }
      rethrow;
    }
  }

  /// Records a `customer_created_shared_phone` SyncQueue event atomically with
  /// customer registration. Follows existing SyncQueue conventions:
  /// UUIDv4 idempotency key, `pending_server_ack` status, JSON payload.
  ///
  /// `sync_queue.entity_id` is a UUID both locally (`SyncQueueEntry`
  /// validation) and server-side (`entity_id UUID NOT NULL`), so the queue row
  /// is keyed by the pre-onboarding session id ([RegisterCustomerRequest.id]).
  /// The database-assigned integer customer id travels in the payload as
  /// `new_customer_id`.
  ///
  /// Only called when shared-phone confirmation has occurred.
  Future<void> _recordSharedPhoneSyncEvent(
    AppDatabase database,
    RegisterCustomerRequest request,
    List<Customer> existingCustomers,
    int createdCustomerId,
  ) async {
    final now = DateTime.now().toUtc();

    final entry = SyncQueueEntry.create(
      shopId: request.shopId,
      entityType: 'customer',
      entityId: request.id,
      actionType: 'customer_created_shared_phone',
      payload: {
        'shop_id': request.shopId,
        'new_customer_id': createdCustomerId,
        'existing_customer_ids': existingCustomers.map((c) => c.id).toList(),
        'confirming_staff_id': request.confirmingStaffId,
        'shared_phone': request.phone,
        'normalized_phone': Customer.normalizePhone(request.phone),
        'confirmed_at': now.toIso8601String(),
      },
      createdAt: now,
    );

    await database.into(database.syncQueue).insert(SyncQueueRecord(
      id: entry.id,
      shopId: entry.shopId,
      idempotencyKey: entry.idempotencyKey,
      entityType: entry.entityType,
      entityId: entry.entityId,
      actionType: entry.actionType,
      payloadJson: entry.payloadJson,
      status: entry.status.value,
      retryCount: entry.retryCount,
      lastError: entry.lastError,
      createdAt: entry.createdAt,
      updatedAt: entry.updatedAt,
    ));
  }
}

