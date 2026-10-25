import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/customer_dao.dart';
import 'package:credit_system/features/customers/domain/models/customer.dart';
import 'package:credit_system/features/customers/domain/services/customer_data_masking_service.dart';

void main() {
  late AppDatabase db;
  late CustomerDao customerDao;
  late CustomerPhotoUrlSigner photoSigner;
  late CustomerDataMaskingService maskingService;

  const testShopId = 'shop-masking-01';
  const testOtherShopId = 'shop-other-02';
  const testCustomerId = 'cust-mask-001';
  const testSecret = 'test-secret-key-for-hmac-sha256-signing';

  final now = DateTime.now().toUtc();

  final customer = Customer(
    id: testCustomerId,
    shopId: testShopId,
    fullName: 'Anura Kumara',
    nic: '198512345678',
    phone: '+94771234567',
    address: 'No. 12/B, Flower Road, Colombo 07',
    photoUri: 'photos/shop-masking-01/customers/cust-mask-001_160000.jpg',
    photoHash: 'hash-abc-123',
    createdAt: now,
    updatedAt: now,
  );

  // 1. Cashier: possesses viewCustomers, but lacks viewSensitiveCustomerData
  final cashierUser = AppUser(
    id: 'user-cashier-01',
    shopId: testShopId,
    username: 'cashier.test',
    fullName: 'Cashier User',
    role: AppRole.cashier,
  );

  // 2. Manager: possesses viewSensitiveCustomerData
  final managerUser = AppUser(
    id: 'user-manager-01',
    shopId: testShopId,
    username: 'manager.test',
    fullName: 'Manager User',
    role: AppRole.manager,
  );

  // 3. Shop Owner: has all permissions
  final ownerUser = AppUser(
    id: 'user-owner-01',
    shopId: testShopId,
    username: 'owner.test',
    fullName: 'Shop Owner User',
    role: AppRole.shopOwner,
  );

  // 4. Custom user with NO customer viewing permission
  final unauthorizedUser = AppUser(
    id: 'user-custom-01',
    shopId: testShopId,
    username: 'custom.unauthorized',
    fullName: 'Unauthorized User',
    role: AppRole.custom,
    customPermissions: const {AppPermission.viewFinancialReports},
  );

  // 5. User from another shop
  final otherShopUser = AppUser(
    id: 'user-other-shop-01',
    shopId: testOtherShopId,
    username: 'other.shop.staff',
    fullName: 'Other Shop Staff',
    role: AppRole.cashier,
  );

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);

    await db.into(db.shops).insert(
      ShopEntry(
        id: testShopId,
        name: 'Masking Test Jewellers',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await db.into(db.shops).insert(
      ShopEntry(
        id: testOtherShopId,
        name: 'Other Shop',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );

    customerDao = CustomerDao(db);
    await customerDao.createCustomer(customer);

    photoSigner = const CustomerPhotoUrlSigner(secretKey: testSecret);
    maskingService = CustomerDataMaskingService(
      customerDao: customerDao,
      photoSigner: photoSigner,
      db: db,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Story 2.6: Server-Side Customer Data Masking & RBAC Enforcement', () {
    test('AC-1: Cashier with viewCustomers but without viewSensitiveCustomerData receives masked PII', () async {
      // Act
      final result = await maskingService.getCustomerProfile(
        shopId: testShopId,
        customerId: testCustomerId,
        actor: cashierUser,
      );

      // Assert: NIC masked (1985****5678)
      expect(result.nic, equals('1985****5678'));
      // Assert: Phone masked (+94 77 **** 123)
      expect(result.phone, equals('+94 77 **** 567'));
      // Assert: Residential address omitted
      expect(result.address, isNull);
      // Assert: Photo URL omitted
      expect(result.photoUri, isNull);
      // Assert: isMasked is true
      expect(result.isMasked, isTrue);
      // Non-sensitive fields preserved
      expect(result.id, equals(testCustomerId));
      expect(result.fullName, equals('Anura Kumara'));
      expect(result.photoHash, equals('hash-abc-123'));
    });

    test('AC-2: Manager possessing viewSensitiveCustomerData receives unmasked PII and signed photo URL', () async {
      // Act
      final result = await maskingService.getCustomerProfile(
        shopId: testShopId,
        customerId: testCustomerId,
        actor: managerUser,
      );

      // Assert: Full unmasked NIC
      expect(result.nic, equals('198512345678'));
      // Assert: Full unmasked phone
      expect(result.phone, equals('+94771234567'));
      // Assert: Full residential address
      expect(result.address, equals('No. 12/B, Flower Road, Colombo 07'));
      // Assert: Cryptographically signed photo URL
      expect(result.photoUri, isNotNull);
      expect(result.photoUri, startsWith('/api/v1/photos/customer?'));
      expect(result.photoUri, contains('sig='));
      expect(result.photoUri, contains('expires='));
      expect(result.isMasked, isFalse);
    });

    test('AC-2: Shop Owner receives full unmasked PII and signed photo URL', () async {
      // Act
      final result = await maskingService.getCustomerProfile(
        shopId: testShopId,
        customerId: testCustomerId,
        actor: ownerUser,
      );

      // Assert
      expect(result.nic, equals('198512345678'));
      expect(result.phone, equals('+94771234567'));
      expect(result.address, equals('No. 12/B, Flower Road, Colombo 07'));
      expect(result.photoUri, contains('sig='));
      expect(result.isMasked, isFalse);
    });

    test('AC-3: Unauthorized actor lacking viewCustomers receives 403 Forbidden and logs Category 14 audit event', () async {
      // Act & Assert
      expect(
        () => maskingService.getCustomerProfile(
          shopId: testShopId,
          customerId: testCustomerId,
          actor: unauthorizedUser,
        ),
        throwsA(isA<CustomerAccessForbiddenException>().having(
          (e) => e.statusCode,
          'statusCode',
          equals(403),
        )),
      );

      // Verify Category 14 security audit event in local SyncQueue
      final queuedEvents = await db.select(db.syncQueue).get();
      final secEvent = queuedEvents.firstWhere(
        (e) => e.entityType == 'security_event',
      );
      expect(secEvent.shopId, equals(testShopId));
      expect(secEvent.actionType, equals('unauthorized_customer_profile_access'));
      expect(secEvent.payloadJson, contains('"eventCategory":14'));
      expect(secEvent.payloadJson, contains('viewCustomers'));
    });

    test('AC-3: Cross-tenant customer profile access attempt receives 403 Forbidden and logs security audit event', () async {
      // Act & Assert
      expect(
        () => maskingService.getCustomerProfile(
          shopId: testShopId,
          customerId: testCustomerId,
          actor: otherShopUser,
        ),
        throwsA(isA<CustomerAccessForbiddenException>().having(
          (e) => e.statusCode,
          'statusCode',
          equals(403),
        )),
      );

      // Verify Category 14 security audit event in local SyncQueue
      final queuedEvents = await db.select(db.syncQueue).get();
      final secEvent = queuedEvents.firstWhere(
        (e) => e.actionType == 'unauthorized_cross_tenant_customer_access',
      );
      expect(secEvent.shopId, equals(testShopId));
      expect(secEvent.payloadJson, contains('"eventCategory":14'));
      expect(secEvent.payloadJson, contains('Cross-tenant'));
    });

    test('Photo URL Signature & Verification - Valid short-lived URL (< 15 mins) is accepted', () async {
      final expiry15Min = DateTime.now().toUtc().add(const Duration(minutes: 15));
      final signedUrl = photoSigner.generateSignedUrl(
        shopId: testShopId,
        customerId: testCustomerId,
        photoUri: customer.photoUri!,
        expiresAt: expiry15Min,
      );

      final uri = Uri.parse(signedUrl);
      final expires = int.parse(uri.queryParameters['expires']!);
      final sig = uri.queryParameters['sig']!;

      final resolvedUri = await maskingService.authorizePhotoAccess(
        shopId: testShopId,
        customerId: testCustomerId,
        photoUri: customer.photoUri!,
        expiresEpochSeconds: expires,
        signature: sig,
        actor: managerUser,
      );

      expect(resolvedUri, equals(customer.photoUri));
    });

    test('Photo URL Signature & Verification - Expired or tampered signature returns 403 and records Category 14 audit event', () async {
      // Expired 1 second ago
      final pastExpiry = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
      final signedUrl = photoSigner.generateSignedUrl(
        shopId: testShopId,
        customerId: testCustomerId,
        photoUri: customer.photoUri!,
        expiresAt: pastExpiry,
      );

      final uri = Uri.parse(signedUrl);
      final expires = int.parse(uri.queryParameters['expires']!);
      final sig = uri.queryParameters['sig']!;

      expect(
        () => maskingService.authorizePhotoAccess(
          shopId: testShopId,
          customerId: testCustomerId,
          photoUri: customer.photoUri!,
          expiresEpochSeconds: expires,
          signature: sig,
          actor: cashierUser,
        ),
        throwsA(isA<CustomerAccessForbiddenException>().having(
          (e) => e.statusCode,
          'statusCode',
          equals(403),
        )),
      );

      // Verify Category 14 audit event
      final queuedEvents = await db.select(db.syncQueue).get();
      final secEvent = queuedEvents.firstWhere(
        (e) => e.actionType == 'unauthorized_customer_photo_access_invalid_signature',
      );
      expect(secEvent.payloadJson, contains('"eventCategory":14'));
    });
  });
}
