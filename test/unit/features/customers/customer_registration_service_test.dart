import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/storage/photo_storage_service.dart';
import 'package:credit_system/features/customers/data/daos/customer_dao.dart';
import 'package:credit_system/features/customers/data/daos/customer_photo_exception_dao.dart';
import 'package:credit_system/features/customers/domain/models/customer.dart';
import 'package:credit_system/features/customers/domain/models/customer_photo_exception.dart';
import 'package:credit_system/features/customers/domain/services/customer_photo_compressor.dart';
import 'package:credit_system/features/customers/domain/services/customer_registration_service.dart';

void main() {
  late AppDatabase db;
  late CustomerDao customerDao;
  late Directory tempStorageDir;
  late PhotoStorageService storageService;
  late CustomerRegistrationService registrationService;

  const shopAlphaId = '11111111-1111-1111-1111-111111111101';
  const shopBetaId = '11111111-1111-1111-1111-111111111102';

  /// Helper to create valid image bytes
  Uint8List createSampleImageBytes() {
    final image = img.Image(width: 400, height: 400);
    for (int y = 0; y < 400; y++) {
      for (int x = 0; x < 400; x++) {
        image.setPixelRgba(x, y, 200, 100, 50, 255);
      }
    }
    return Uint8List.fromList(img.encodeJpg(image));
  }

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);
    customerDao = db.customerDao;

    tempStorageDir = await Directory.systemTemp.createTemp('customer_reg_test_');
    storageService = PhotoStorageService(baseDirectoryOverride: tempStorageDir);

    registrationService = CustomerRegistrationService(
      customerDao: customerDao,
      compressor: const CustomerPhotoCompressor(),
      storageService: storageService,
    );

    // Seed test shop tenant
    final now = DateTime.now().toUtc();
    await db.into(db.shops).insert(
      ShopEntry(
        id: shopAlphaId,
        name: 'Alpha Jewellers',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.shops).insert(
      ShopEntry(
        id: shopBetaId,
        name: 'Beta Jewellers',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDown(() async {
    await db.close();
    if (await tempStorageDir.exists()) {
      await tempStorageDir.delete(recursive: true);
    }
  });

  group('CustomerRegistrationService - Mandatory Photo & Persistence (Story 2.2)', () {
    test('standard registration without photo fails with exact error "Customer photograph is mandatory."', () async {
      final requestNullPhoto = RegisterCustomerRequest(
        id: 'cust-no-photo-1',
        shopId: shopAlphaId,
        fullName: 'Kamal Perera',
        nic: '851234567V',
        phone: '+94 77 123 4567',
        address: '10 Main St, Colombo',
        rawPhotoBytes: null,
      );

      expect(
        () => registrationService.registerCustomer(requestNullPhoto),
        throwsA(
          isA<CustomerValidationException>().having(
            (e) => e.message,
            'message',
            equals('Customer photograph is mandatory.'),
          ),
        ),
      );

      final requestEmptyPhoto = RegisterCustomerRequest(
        id: 'cust-no-photo-2',
        shopId: shopAlphaId,
        fullName: 'Kamal Perera',
        nic: '851234567V',
        phone: '+94 77 123 4567',
        address: '10 Main St, Colombo',
        rawPhotoBytes: Uint8List(0),
      );

      expect(
        () => registrationService.registerCustomer(requestEmptyPhoto),
        throwsA(
          isA<CustomerValidationException>().having(
            (e) => e.message,
            'message',
            equals('Customer photograph is mandatory.'),
          ),
        ),
      );
    });

    test('successful registration compresses image, stores file on disk, and saves metadata in database', () async {
      final photoBytes = createSampleImageBytes();

      final request = RegisterCustomerRequest(
        id: 'cust-valid-photo-1',
        shopId: shopAlphaId,
        fullName: 'Sunil Silva',
        nic: '901234567V',
        phone: '+94 77 987 6543',
        address: '25 Galle Road, Colombo 03',
        rawPhotoBytes: photoBytes,
      );

      final created = await registrationService.registerCustomer(request);

      // Verify domain entity returned (id assigned by the database)
      expect(created.id, greaterThan(0));
      expect(created.photoUri, isNotNull);
      expect(created.photoHash, isNotNull);
      expect(created.photoUri, startsWith('photos/$shopAlphaId/customers/cust-valid-photo-1_'));
      expect(created.photoUri, endsWith('.jpg'));

      // Verify file exists in sandboxed storage
      final diskFile = await storageService.resolveRelativePath(created.photoUri!);
      expect(await diskFile.exists(), isTrue);
      expect(await diskFile.length(), lessThanOrEqualTo(500 * 1024));

      // Verify database record has only metadata (no binary bytes)
      final inDb = await customerDao.getCustomerById(shopAlphaId, created.id);
      expect(inDb, isNotNull);
      expect(inDb!.photoUri, equals(created.photoUri));
      expect(inDb.photoHash, equals(created.photoHash));
      expect(inDb.fullName, equals('Sunil Silva'));
      expect(inDb.nic, equals('901234567V'));
    });

    test('cleans up orphaned photo file on disk if database insertion fails', () async {
      // First register a customer with an NIC
      final photoBytes = createSampleImageBytes();
      final firstRequest = RegisterCustomerRequest(
        id: 'cust-dup-first',
        shopId: shopAlphaId,
        fullName: 'Existing Customer',
        nic: '851234567V',
        phone: '+94 77 111 2222',
        address: '10 Flower Rd, Colombo',
        rawPhotoBytes: photoBytes,
      );
      await registrationService.registerCustomer(firstRequest);

      // Attempt second registration with same NIC (triggers SQLite unique constraint violation)
      final collidingRequest = RegisterCustomerRequest(
        id: 'cust-dup-second',
        shopId: shopAlphaId,
        fullName: 'Colliding Customer',
        nic: '851234567V',
        phone: '+94 77 333 4444',
        address: '20 Flower Rd, Colombo',
        rawPhotoBytes: photoBytes,
      );

      // Should fail at database stage
      await expectLater(
        () => registrationService.registerCustomer(collidingRequest),
        throwsA(anything),
      );

      // Verify that no orphaned photo file remains on disk for cust-dup-second
      final customerDir = Directory('${tempStorageDir.path}/photos/$shopAlphaId/customers');
      final files = customerDir.listSync().whereType<File>().toList();
      final orphanedFiles = files.where((f) => f.path.contains('cust-dup-second'));
      expect(orphanedFiles, isEmpty);
    });
  });

  group('CustomerRegistrationService - Photo Exception Workflow (Story 2.3)', () {
    late CustomerPhotoExceptionDao exceptionDao;
    const staffId = 'staff-reg-exc';
    const ownerId = 'owner-reg-exc';

    setUp(() async {
      exceptionDao = CustomerPhotoExceptionDao(db);
      registrationService = CustomerRegistrationService(
        customerDao: customerDao,
        exceptionDao: exceptionDao,
        compressor: const CustomerPhotoCompressor(),
        storageService: storageService,
      );

      final now = DateTime.now().toUtc();
      // Seed staff & owner users for FK references
      await db.into(db.appUsers).insert(
        AppUserEntry(
          id: staffId,
          shopId: shopAlphaId,
          username: 'staff.reg',
          fullName: 'Staff Reg',
          role: 'cashier',
          isActive: true,
          sessionVersion: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db.into(db.appUsers).insert(
        AppUserEntry(
          id: ownerId,
          shopId: shopAlphaId,
          username: 'owner.reg',
          fullName: 'Owner Reg',
          role: 'shop_owner',
          isActive: true,
          sessionVersion: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );
    });

    test('successful registration without photo unblocked when valid approved exception is provided', () async {
      final now = DateTime.now().toUtc();
      final exception = CustomerPhotoException(
        id: 'exc-valid-1',
        shopId: shopAlphaId,
        targetCustomerId: 'cust-exc-success-1',
        customerNic: '199012345678',
        requestedByUserId: staffId,
        requestReason: 'Camera hardware failure; physical NIC verified in branch',
        status: PhotoExceptionStatus.approved,
        reviewedByUserId: ownerId,
        reviewNotes: 'Approved by shop owner after physical verification',
        reviewedAt: now,
        createdAt: now,
        updatedAt: now,
      );
      await exceptionDao.createException(exception);

      final request = RegisterCustomerRequest(
        id: 'cust-exc-success-1',
        shopId: shopAlphaId,
        fullName: 'Nimali Fernando',
        nic: '199012345678',
        phone: '+94 77 444 5555',
        address: '50 Lake Road, Kandy',
        rawPhotoBytes: null,
        photoExceptionId: exception.id,
      );

      final created = await registrationService.registerCustomer(request);

      // Verify domain customer created without photo (id assigned by the database)
      expect(created.id, greaterThan(0));
      expect(created.photoUri, isNull);
      expect(created.photoHash, isNull);
      expect(created.fullName, equals('Nimali Fernando'));
      expect(created.nic, equals('199012345678'));

      // Verify persistence in SQLite
      final inDb = await customerDao.getCustomerById(shopAlphaId, created.id);
      expect(inDb, isNotNull);
      expect(inDb!.photoUri, isNull);
      expect(inDb.photoHash, isNull);

      // Verify exception was atomically transitioned to consumed (single-use enforcement)
      final exceptionInDb = await exceptionDao.getExceptionById(shopAlphaId, exception.id);
      expect(exceptionInDb!.status, equals(PhotoExceptionStatus.consumed));
    });

    test('reusing an already consumed exception is strictly blocked', () async {
      final now = DateTime.now().toUtc();
      final exception = CustomerPhotoException(
        id: 'exc-consumed-1',
        shopId: shopAlphaId,
        targetCustomerId: 'cust-consumed-1',
        customerNic: '199012345678',
        requestedByUserId: staffId,
        requestReason: 'Hardware failure',
        status: PhotoExceptionStatus.consumed,
        reviewedByUserId: ownerId,
        reviewNotes: 'Already used',
        reviewedAt: now,
        createdAt: now,
        updatedAt: now,
      );
      await exceptionDao.createException(exception);

      final request = RegisterCustomerRequest(
        id: 'cust-consumed-1',
        shopId: shopAlphaId,
        fullName: 'Replay Attempt Customer',
        nic: '199012345678',
        phone: '+94 77 444 5555',
        address: '50 Lake Road, Kandy',
        rawPhotoBytes: null,
        photoExceptionId: exception.id,
      );

      expect(
        () => registrationService.registerCustomer(request),
        throwsA(
          isA<CustomerValidationException>().having(
            (e) => e.message,
            'message',
            contains('Photo exception is in state "consumed", not "approved"'),
          ),
        ),
      );
    });

    test('registration with pending exception is blocked', () async {
      final now = DateTime.now().toUtc();
      final exception = CustomerPhotoException(
        id: 'exc-pending-1',
        shopId: shopAlphaId,
        targetCustomerId: 'cust-pending-1',
        customerNic: '199012345678',
        requestedByUserId: staffId,
        requestReason: 'Hardware failure',
        status: PhotoExceptionStatus.pendingOwnerApproval,
        createdAt: now,
        updatedAt: now,
      );
      await exceptionDao.createException(exception);

      final request = RegisterCustomerRequest(
        id: 'cust-pending-1',
        shopId: shopAlphaId,
        fullName: 'Pending Customer',
        nic: '199012345678',
        phone: '+94 77 444 5555',
        address: '50 Lake Road, Kandy',
        rawPhotoBytes: null,
        photoExceptionId: exception.id,
      );

      expect(
        () => registrationService.registerCustomer(request),
        throwsA(
          isA<CustomerValidationException>().having(
            (e) => e.message,
            'message',
            contains('Photo exception is in state "pending_owner_approval", not "approved"'),
          ),
        ),
      );
    });

    test('registration with rejected exception is blocked', () async {
      final now = DateTime.now().toUtc();
      final exception = CustomerPhotoException(
        id: 'exc-rejected-1',
        shopId: shopAlphaId,
        targetCustomerId: 'cust-rejected-1',
        customerNic: '199012345678',
        requestedByUserId: staffId,
        requestReason: 'Hardware failure',
        status: PhotoExceptionStatus.rejected,
        reviewedByUserId: ownerId,
        reviewNotes: 'Rejected by owner',
        reviewedAt: now,
        createdAt: now,
        updatedAt: now,
      );
      await exceptionDao.createException(exception);

      final request = RegisterCustomerRequest(
        id: 'cust-rejected-1',
        shopId: shopAlphaId,
        fullName: 'Rejected Customer',
        nic: '199012345678',
        phone: '+94 77 444 5555',
        address: '50 Lake Road, Kandy',
        rawPhotoBytes: null,
        photoExceptionId: exception.id,
      );

      expect(
        () => registrationService.registerCustomer(request),
        throwsA(
          isA<CustomerValidationException>().having(
            (e) => e.message,
            'message',
            contains('Photo exception is in state "rejected", not "approved"'),
          ),
        ),
      );
    });

    test('dual customer binding violation on customerId is blocked', () async {
      final now = DateTime.now().toUtc();
      final exception = CustomerPhotoException(
        id: 'exc-binding-cust-id',
        shopId: shopAlphaId,
        targetCustomerId: 'cust-bound-alpha',
        customerNic: '199012345678',
        requestedByUserId: staffId,
        requestReason: 'Hardware failure',
        status: PhotoExceptionStatus.approved,
        reviewedByUserId: ownerId,
        reviewNotes: 'Approved',
        reviewedAt: now,
        createdAt: now,
        updatedAt: now,
      );
      await exceptionDao.createException(exception);

      final request = RegisterCustomerRequest(
        id: 'cust-bound-beta', // Mismatched customer ID
        shopId: shopAlphaId,
        fullName: 'Mismatched Customer',
        nic: '199012345678',
        phone: '+94 77 444 5555',
        address: '50 Lake Road, Kandy',
        rawPhotoBytes: null,
        photoExceptionId: exception.id,
      );

      expect(
        () => registrationService.registerCustomer(request),
        throwsA(
          isA<CustomerValidationException>().having(
            (e) => e.message,
            'message',
            contains('Dual customer binding violation'),
          ),
        ),
      );
    });

    test('dual customer binding violation on customerNic is blocked', () async {
      final now = DateTime.now().toUtc();
      final exception = CustomerPhotoException(
        id: 'exc-binding-nic',
        shopId: shopAlphaId,
        targetCustomerId: 'cust-bound-same',
        customerNic: '199012345678',
        requestedByUserId: staffId,
        requestReason: 'Hardware failure',
        status: PhotoExceptionStatus.approved,
        reviewedByUserId: ownerId,
        reviewNotes: 'Approved',
        reviewedAt: now,
        createdAt: now,
        updatedAt: now,
      );
      await exceptionDao.createException(exception);

      final request = RegisterCustomerRequest(
        id: 'cust-bound-same',
        shopId: shopAlphaId,
        fullName: 'Mismatched Customer',
        nic: '851234567V', // Mismatched NIC
        phone: '+94 77 444 5555',
        address: '50 Lake Road, Kandy',
        rawPhotoBytes: null,
        photoExceptionId: exception.id,
      );

      expect(
        () => registrationService.registerCustomer(request),
        throwsA(
          isA<CustomerValidationException>().having(
            (e) => e.message,
            'message',
            contains('Dual customer binding violation'),
          ),
        ),
      );
    });

    test('registration fails if photoExceptionId does not exist in shop', () async {
      final request = RegisterCustomerRequest(
        id: 'cust-bound-same',
        shopId: shopAlphaId,
        fullName: 'Missing Exception Customer',
        nic: '851234567V',
        phone: '+94 77 444 5555',
        address: '50 Lake Road, Kandy',
        rawPhotoBytes: null,
        photoExceptionId: 'non-existent-exception-id',
      );

      expect(
        () => registrationService.registerCustomer(request),
        throwsA(
          isA<CustomerValidationException>().having(
            (e) => e.message,
            'message',
            contains('Photo exception ID "non-existent-exception-id" not found'),
          ),
        ),
      );
    });

    test('ATOMIC ROLLBACK: failed customer insertion rolls back and does not leave exception consumed', () async {
      final now = DateTime.now().toUtc();

      // Pre-seed an existing customer with NIC 198012345678 to trigger unique constraint collision
      await customerDao.createCustomer(
        Customer(
          id: 0,
          shopId: shopAlphaId,
          fullName: 'Prior Registered Person',
          nic: '198012345678',
          phone: '+94 77 111 2222',
          address: 'Colombo',
        ),
      );

      // Create an approved exception for target customer ID with the colliding NIC
      final exception = CustomerPhotoException(
        id: 'exc-rollback-test',
        shopId: shopAlphaId,
        targetCustomerId: 'cust-target-collision',
        customerNic: '198012345678',
        requestedByUserId: staffId,
        requestReason: 'Hardware failure',
        status: PhotoExceptionStatus.approved,
        reviewedByUserId: ownerId,
        reviewNotes: 'Approved',
        reviewedAt: now,
        createdAt: now,
        updatedAt: now,
      );
      await exceptionDao.createException(exception);

      final failingRequest = RegisterCustomerRequest(
        id: 'cust-target-collision',
        shopId: shopAlphaId,
        fullName: 'Second Person With Same NIC',
        nic: '198012345678',
        phone: '+94 77 333 4444',
        address: 'Colombo',
        rawPhotoBytes: null,
        photoExceptionId: exception.id,
      );

      // Registration must fail at database level due to duplicate NIC
      await expectLater(
        () => registrationService.registerCustomer(failingRequest),
        throwsA(anything),
      );

      // CRITICAL ASSERTION: The exception must NOT be consumed; transaction rollback preserved 'approved' state
      final exceptionAfterRollback = await exceptionDao.getExceptionById(shopAlphaId, exception.id);
      expect(exceptionAfterRollback, isNotNull);
      expect(exceptionAfterRollback!.status, equals(PhotoExceptionStatus.approved));

      // Target customer was not created — only the pre-seeded row holds the NIC
      final targetCustomers = await (db.select(db.customers)
            ..where((c) => c.shopId.equals(shopAlphaId))
            ..where((c) => c.nic.equals('198012345678')))
          .get();
      expect(targetCustomers, hasLength(1));
      expect(targetCustomers.single.fullName, equals('Prior Registered Person'));
    });

    test('ATOMIC CAS RACE PROTECTION: concurrent attempts to consume same approved exception reject the second', () async {
      final now = DateTime.now().toUtc();
      final exception = CustomerPhotoException(
        id: 'exc-concurrent-cas',
        shopId: shopAlphaId,
        targetCustomerId: 'cust-concurrent-1',
        customerNic: '199512345678',
        requestedByUserId: staffId,
        requestReason: 'Hardware failure',
        status: PhotoExceptionStatus.approved,
        reviewedByUserId: ownerId,
        reviewNotes: 'Approved',
        reviewedAt: now,
        createdAt: now,
        updatedAt: now,
      );
      await exceptionDao.createException(exception);

      // Fire two consume operations concurrently
      var successCount = 0;
      var rejectedCount = 0;

      final results = await Future.wait([
        exceptionDao
            .consumeException(
              shopAlphaId,
              exception.id,
              targetCustomerId: 'cust-concurrent-1',
              customerNic: '199512345678',
            )
            .then((_) => successCount++)
            .catchError((_) => rejectedCount++),
        exceptionDao
            .consumeException(
              shopAlphaId,
              exception.id,
              targetCustomerId: 'cust-concurrent-1',
              customerNic: '199512345678',
            )
            .then((_) => successCount++)
            .catchError((_) => rejectedCount++),
      ]);

      expect(results.length, equals(2));
      expect(successCount, equals(1), reason: 'Exactly one concurrent attempt must succeed');
      expect(rejectedCount, equals(1), reason: 'The second concurrent attempt must be rejected by atomic CAS check');

      // Final status in DB is consumed
      final finalException = await exceptionDao.getExceptionById(shopAlphaId, exception.id);
      expect(finalException!.status, equals(PhotoExceptionStatus.consumed));
    });
  });

  group('CustomerRegistrationService - Duplicate Detection & Shared-Phone (Story 2.4)', () {
    const staffId = '11111111-1111-1111-1111-111111111103';
    const existingCustomerId = '11111111-1111-1111-1111-111111111104';

    setUp(() async {
      // Seed staff user for FK references if needed
      final now = DateTime.now().toUtc();
      await db.into(db.appUsers).insert(
        AppUserEntry(
          id: staffId,
          shopId: shopAlphaId,
          username: 'staff.24',
          fullName: 'Staff 24',
          role: 'counter_staff',
          isActive: true,
          sessionVersion: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );
    });

    test('duplicate NIC within the same shop blocks registration with documented message', () async {
      final photoBytes = createSampleImageBytes();

      // First customer with NIC 851234567V
      await registrationService.registerCustomer(
        RegisterCustomerRequest(
          id: existingCustomerId,
          shopId: shopAlphaId,
          fullName: 'Existing NIC Owner',
          nic: '851234567V',
          phone: '+94 77 111 2222',
          address: '1 Main St, Colombo',
          rawPhotoBytes: photoBytes,
        ),
      );

      // Second registration with same NIC must fail
      await expectLater(
        () => registrationService.registerCustomer(
          RegisterCustomerRequest(
            id: '11111111-1111-1111-1111-111111111105',
            shopId: shopAlphaId,
            fullName: 'Duplicate NIC Attempt',
            nic: '851234567V',
            phone: '+94 77 333 4444',
            address: '2 Main St, Colombo',
            rawPhotoBytes: photoBytes,
          ),
        ),
        throwsA(
          isA<DuplicateNicException>().having(
            (e) => e.message,
            'message',
            equals('Customer profile already exists for this NIC within $shopAlphaId'),
          ),
        ),
      );

      // The existing customer must still be the only one with that NIC
      final existing = await customerDao.getCustomerByNic(shopAlphaId, '851234567V');
      expect(existing, isNotNull);
      expect(existing!.id, greaterThan(0));

      // No duplicate customer was created
      final dupCount = await (db.select(db.customers)
            ..where((c) => c.shopId.equals(shopAlphaId))
            ..where((c) => c.nic.equals('851234567V')))
          .get();
      expect(dupCount, hasLength(1));
    });

    test('duplicate NIC is scoped to the current shop — same NIC in another shop is allowed', () async {
      final photoBytes = createSampleImageBytes();

      await registrationService.registerCustomer(
        RegisterCustomerRequest(
          id: existingCustomerId,
          shopId: shopAlphaId,
          fullName: 'Alpha NIC Owner',
          nic: '851234567V',
          phone: '+94 77 111 2222',
          address: '1 Main St, Colombo',
          rawPhotoBytes: photoBytes,
        ),
      );

      // Same NIC in Beta shop (different shop) must succeed
      final betaCreated = await registrationService.registerCustomer(
        RegisterCustomerRequest(
          id: '11111111-1111-1111-1111-111111111106',
          shopId: shopBetaId,
          fullName: 'Beta Same NIC',
          nic: '851234567V',
          phone: '+94 77 555 6666',
          address: '2 Main St',
          rawPhotoBytes: photoBytes,
        ),
      );

      final betaCust = await customerDao.getCustomerById(shopBetaId, betaCreated.id);
      expect(betaCust, isNotNull);
      expect(betaCust!.shopId, equals(shopBetaId));
    });

    test('shared phone without confirmation throws SharedPhoneDuplicateException', () async {
      final photoBytes = createSampleImageBytes();

      // Existing customer with phone 0771234567
      await registrationService.registerCustomer(
        RegisterCustomerRequest(
          id: existingCustomerId,
          shopId: shopAlphaId,
          fullName: 'Shared Phone Owner',
          nic: '851234567V',
          phone: '0771234567',
          address: '1 Main St, Colombo',
          rawPhotoBytes: photoBytes,
        ),
      );

      // New customer with equivalent phone (+94771234567) but different NIC — no confirmation
      await expectLater(
        () => registrationService.registerCustomer(
          RegisterCustomerRequest(
            id: '11111111-1111-1111-1111-111111111107',
            shopId: shopAlphaId,
            fullName: 'Shared Phone Attempt',
            nic: '901234567V',
            phone: '+94771234567',
            address: '2 Main St, Colombo',
            rawPhotoBytes: photoBytes,
          ),
        ),
        throwsA(isA<SharedPhoneDuplicateException>()),
      );

      // No new customer was created
      final newCust = await customerDao.getCustomerByNic(shopAlphaId, '901234567V');
      expect(newCust, isNull);

      // No sync queue event was recorded
      final queueItems = await (db.select(db.syncQueue)
            ..where((q) => q.actionType.equals('customer_created_shared_phone')))
          .get();
      expect(queueItems.length, equals(0));
    });

    test('shared phone with confirmation creates customer and sync queue event atomically', () async {
      final photoBytes = createSampleImageBytes();

      // Existing customer with phone 0771234567
      final existingCreated = await registrationService.registerCustomer(
        RegisterCustomerRequest(
          id: existingCustomerId,
          shopId: shopAlphaId,
          fullName: 'Shared Phone Owner',
          nic: '851234567V',
          phone: '0771234567',
          address: '1 Main St, Colombo',
          rawPhotoBytes: photoBytes,
        ),
      );
      // New customer with shared phone — WITH explicit confirmation
      final created = await registrationService.registerCustomer(
        RegisterCustomerRequest(
          id: '11111111-1111-1111-1111-111111111108',
          shopId: shopAlphaId,
          fullName: 'Confirmed Shared Phone',
          nic: '901234567V',
          phone: '+94771234567',
          address: '2 Main St, Colombo',
          rawPhotoBytes: photoBytes,
          confirmSharedPhone: true,
          confirmingStaffId: staffId,
        ),
      );

      expect(created.id, greaterThan(0));
      expect(created.shopId, equals(shopAlphaId));
      expect(created.nic, equals('901234567V'));

      // Customer persisted in database
      final inDb = await customerDao.getCustomerById(shopAlphaId, created.id);
      expect(inDb, isNotNull);
      expect(inDb!.phone, equals('+94771234567'));

      // Sync queue event recorded
      final queueItems = await (db.select(db.syncQueue)
            ..where((q) => q.actionType.equals('customer_created_shared_phone')))
          .get();
      expect(queueItems.length, equals(1));

      final event = queueItems.first;
      expect(event.shopId, equals(shopAlphaId));
      expect(event.entityType, equals('customer'));
      expect(event.entityId, equals('11111111-1111-1111-1111-111111111108'));
      expect(event.status, equals('pending_server_ack'));
      expect(event.idempotencyKey, isNotEmpty);

      final payload = jsonDecode(event.payloadJson) as Map<String, dynamic>;
      expect(payload['shop_id'], equals(shopAlphaId));
      expect(payload['new_customer_id'], equals(created.id));
      expect(payload['existing_customer_ids'], contains(existingCreated.id));
      expect(payload['confirming_staff_id'], equals(staffId));
      expect(payload['shared_phone'], equals('+94771234567'));
      expect(payload['confirmed_at'], isNotNull);
    });

    test('shared phone confirmation inserts customer and sync event in one transaction — failed registration leaves neither', () async {
      final photoBytes = createSampleImageBytes();

      // Pre-seed an existing customer with same NIC to trigger unique constraint violation
      await customerDao.createCustomer(
        Customer(
          id: 0,
          shopId: shopAlphaId,
          fullName: 'Prior NIC Holder',
          nic: '198012345678',
          phone: '+94 77 111 2222',
          address: 'Colombo',
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      );

      // Pre-seed an existing customer with shared phone
      await registrationService.registerCustomer(
        RegisterCustomerRequest(
          id: 'cust-phone-owner',
          shopId: shopAlphaId,
          fullName: 'Phone Owner',
          nic: '851234567V',
          phone: '0771234567',
          address: '1 Main St, Colombo',
          rawPhotoBytes: photoBytes,
        ),
      );

      // Attempt registration with shared phone (confirmed) but colliding NIC — must fail
      await expectLater(
        () => registrationService.registerCustomer(
          RegisterCustomerRequest(
            id: '11111111-1111-1111-1111-111111111109',
            shopId: shopAlphaId,
            fullName: 'Failing Registration',
            nic: '198012345678', // collides with pre-seeded customer
            phone: '+94771234567', // shared with cust-phone-owner
            address: 'Colombo',
            rawPhotoBytes: photoBytes,
            confirmSharedPhone: true,
            confirmingStaffId: staffId,
          ),
        ),
        throwsA(anything),
      );

      // No customer was created (the colliding NIC still resolves to the pre-seed)
      final failedCust = await customerDao.getCustomerByNic(shopAlphaId, '198012345678');
      expect(failedCust!.fullName, equals('Prior NIC Holder'));

      // No orphaned sync queue event
      final queueItems = await (db.select(db.syncQueue)
            ..where((q) => q.actionType.equals('customer_created_shared_phone')))
          .get();
      expect(queueItems, isEmpty);
    });

    test('registration with shared phone and invalid phone format is rejected', () async {
      final photoBytes = createSampleImageBytes();

      await expectLater(
        () => registrationService.registerCustomer(
          RegisterCustomerRequest(
            id: 'cust-invalid-phone',
            shopId: shopAlphaId,
            fullName: 'Invalid Phone',
            nic: '751234567V',
            phone: 'not-a-phone',
            address: '1 Main St, Colombo',
            rawPhotoBytes: photoBytes,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
