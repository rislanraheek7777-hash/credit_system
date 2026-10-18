import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/features/customers/data/daos/customer_photo_exception_dao.dart';
import 'package:credit_system/features/customers/domain/models/customer.dart';
import 'package:credit_system/features/customers/domain/models/customer_photo_exception.dart';

void main() {
  late AppDatabase db;
  late CustomerPhotoExceptionDao dao;

  const testShopId = 'shop-dao-test';
  const otherShopId = 'shop-dao-other';
  const staffUserId = 'user-dao-staff';
  const ownerUserId = 'user-dao-owner';

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);
    dao = CustomerPhotoExceptionDao(db);

    final now = DateTime.now().toUtc();
    // Seed shops
    await db.into(db.shops).insert(
      ShopEntry(
        id: testShopId,
        name: 'Test Jewellers',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.shops).insert(
      ShopEntry(
        id: otherShopId,
        name: 'Other Jewellers',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );

    // Seed staff & owner users
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: staffUserId,
        shopId: testShopId,
        username: 'staff.one',
        fullName: 'Staff One',
        role: 'cashier',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: ownerUserId,
        shopId: testShopId,
        username: 'owner.one',
        fullName: 'Owner One',
        role: 'shop_owner',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('CustomerPhotoExceptionDao Tests (Story 2.3)', () {
    test('creates and retrieves pending exception by id and shop', () async {
      final now = DateTime.now().toUtc();
      final exception = CustomerPhotoException(
        id: 'exc-dao-1',
        shopId: testShopId,
        targetCustomerId: 'cust-101',
        customerNic: '901234567V',
        requestedByUserId: staffUserId,
        requestReason: 'Camera hardware malfunction',
        createdAt: now,
        updatedAt: now,
      );

      await dao.createException(exception);

      final retrieved = await dao.getExceptionById(testShopId, 'exc-dao-1');
      expect(retrieved, isNotNull);
      expect(retrieved!.id, equals('exc-dao-1'));
      expect(retrieved.shopId, equals(testShopId));
      expect(retrieved.targetCustomerId, equals('cust-101'));
      expect(retrieved.customerNic, equals('901234567V'));
      expect(retrieved.status, equals(PhotoExceptionStatus.pendingOwnerApproval));

      // Cross-shop isolation: querying from otherShopId returns null
      final crossShop = await dao.getExceptionById(otherShopId, 'exc-dao-1');
      expect(crossShop, isNull);
    });

    test('getPendingExceptions returns only pending items for specific shop', () async {
      final now = DateTime.now().toUtc();
      final pending1 = CustomerPhotoException(
        id: 'exc-pend-1',
        shopId: testShopId,
        targetCustomerId: 'cust-102',
        customerNic: '901234567V',
        requestedByUserId: staffUserId,
        requestReason: 'Reason 1',
        createdAt: now,
        updatedAt: now,
      );
      final approved = CustomerPhotoException(
        id: 'exc-appr-1',
        shopId: testShopId,
        targetCustomerId: 'cust-103',
        customerNic: '851234567V',
        requestedByUserId: staffUserId,
        requestReason: 'Reason 2',
        status: PhotoExceptionStatus.approved,
        reviewedByUserId: ownerUserId,
        reviewNotes: 'Approved',
        reviewedAt: now,
        createdAt: now,
        updatedAt: now,
      );

      await dao.createException(pending1);
      await dao.createException(approved);

      final pendingList = await dao.getPendingExceptions(testShopId);
      expect(pendingList.length, equals(1));
      expect(pendingList.first.id, equals('exc-pend-1'));
    });

    test('updateException updates status, review notes, and timestamps', () async {
      final now = DateTime.now().toUtc();
      final exception = CustomerPhotoException(
        id: 'exc-upd-1',
        shopId: testShopId,
        targetCustomerId: 'cust-104',
        customerNic: '901234567V',
        requestedByUserId: staffUserId,
        requestReason: 'Lens broken',
        createdAt: now,
        updatedAt: now,
      );

      await dao.createException(exception);

      final approvedTime = now.add(const Duration(minutes: 2));
      final approved = exception.copyWith(
        status: PhotoExceptionStatus.approved,
        reviewedByUserId: ownerUserId,
        reviewNotes: 'Owner approved after inspecting physical ID',
        reviewedAt: approvedTime,
        updatedAt: approvedTime,
      );

      await dao.updateException(approved);

      final retrieved = await dao.getExceptionById(testShopId, 'exc-upd-1');
      expect(retrieved!.status, equals(PhotoExceptionStatus.approved));
      expect(retrieved.reviewedByUserId, equals(ownerUserId));
      expect(retrieved.reviewNotes, contains('Owner approved'));
    });

    test('consumeException verifies dual customer binding and updates status to consumed', () async {
      final now = DateTime.now().toUtc();
      final approved = CustomerPhotoException(
        id: 'exc-cons-1',
        shopId: testShopId,
        targetCustomerId: 'cust-105',
        customerNic: '901234567V',
        requestedByUserId: staffUserId,
        requestReason: 'Hardware error',
        status: PhotoExceptionStatus.approved,
        reviewedByUserId: ownerUserId,
        reviewNotes: 'Approved by owner',
        reviewedAt: now,
        createdAt: now,
        updatedAt: now,
      );

      await dao.createException(approved);

      // 1. Dual binding violation on customer ID -> must throw
      expect(
        () => dao.consumeException(
          testShopId,
          'exc-cons-1',
          targetCustomerId: 'wrong-customer-id',
          customerNic: '901234567V',
        ),
        throwsA(isA<CustomerValidationException>()),
      );

      // 2. Dual binding violation on NIC -> must throw
      expect(
        () => dao.consumeException(
          testShopId,
          'exc-cons-1',
          targetCustomerId: 'cust-105',
          customerNic: '851234567V', // different NIC
        ),
        throwsA(isA<CustomerValidationException>()),
      );

      // 3. Exact matching dual binding -> succeeds and transitions to consumed
      await dao.consumeException(
        testShopId,
        'exc-cons-1',
        targetCustomerId: 'cust-105',
        customerNic: ' 901234567v ', // case & whitespace insensitive normalization
      );

      final consumed = await dao.getExceptionById(testShopId, 'exc-cons-1');
      expect(consumed!.status, equals(PhotoExceptionStatus.consumed));

      // 4. Attempting to consume again fails (prevent replay attack)
      expect(
        () => dao.consumeException(
          testShopId,
          'exc-cons-1',
          targetCustomerId: 'cust-105',
          customerNic: '901234567V',
        ),
        throwsA(isA<CustomerValidationException>()),
      );
    });

    test('consumeException fails if exception is in pending or rejected state', () async {
      final now = DateTime.now().toUtc();
      final pending = CustomerPhotoException(
        id: 'exc-pend-2',
        shopId: testShopId,
        targetCustomerId: 'cust-106',
        customerNic: '901234567V',
        requestedByUserId: staffUserId,
        requestReason: 'Hardware error',
        createdAt: now,
        updatedAt: now,
      );

      await dao.createException(pending);

      expect(
        () => dao.consumeException(
          testShopId,
          'exc-pend-2',
          targetCustomerId: 'cust-106',
          customerNic: '901234567V',
        ),
        throwsA(isA<CustomerValidationException>()),
      );
    });
  });
}
