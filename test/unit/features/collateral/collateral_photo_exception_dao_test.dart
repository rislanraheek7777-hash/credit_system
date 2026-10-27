import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_photo_exception_dao.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_dao.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_photo_exception.dart';

void main() {
  late AppDatabase db;
  late CollateralPhotoExceptionDao exceptionDao;
  late CollateralDao collateralDao;

  const shopId = 'shop-uuid-exc';
  const customerId = 1;
  const staffId = 'staff-uuid-exc';
  const ownerId = 'owner-uuid-exc';
  const itemId = 'coll-uuid-exc';

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);
    exceptionDao = CollateralPhotoExceptionDao(db);
    collateralDao = CollateralDao(db);

    final now = DateTime.now().toUtc();
    // Seed shop
    await db.into(db.shops).insert(
      ShopEntry(
        id: shopId,
        name: 'Exception Test Shop',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );
    // Seed customer
    await db.into(db.customers).insert(
      CustomerEntry(
        id: customerId,
        shopId: shopId,
        fullName: 'Exception Customer',
        nic: '851234567V',
        phone: '0771234567',
        address: '1 Exception Street',
        createdAt: now,
        updatedAt: now,
      ),
    );
    // Seed staff user
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: staffId,
        shopId: shopId,
        username: 'staff.exc',
        fullName: 'Exception Staff',
        role: 'cashier',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
    // Seed owner user
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: ownerId,
        shopId: shopId,
        username: 'owner.exc',
        fullName: 'Exception Owner',
        role: 'shop_owner',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
    // Seed collateral item
    await collateralDao.createCollateralItem(CollateralItem(
      id: itemId,
      shopId: shopId,
      customerId: customerId,
      itemReferenceId: 'COLL-EXC-001',
      category: CollateralItemCategory.gold,
      description: 'Test item for exception',
      conditionGrade: 'Good',
      weightMilligrams: 1000,
      estimatedValueCents: 100000,
    ));
  });

  tearDown(() async {
    await db.close();
  });

  group('CollateralPhotoExceptionDao - CRUD & Persistence', () {
    test('createException inserts record and returns domain entity on query', () async {
      final now = DateTime.now().toUtc();
      final exception = CollateralPhotoException(
        id: 'exc-dao-001',
        shopId: shopId,
        collateralItemId: itemId,
        requestedByUserId: staffId,
        requestReason: 'Camera hardware failure; physical inspection completed',
        status: CollateralPhotoExceptionStatus.pendingOwnerApproval,
        createdAt: now,
        updatedAt: now,
      );

      await exceptionDao.createException(exception);

      final inDb = await exceptionDao.getExceptionById(shopId, exception.id);
      expect(inDb, isNotNull);
      expect(inDb!.id, equals('exc-dao-001'));
      expect(inDb.shopId, equals(shopId));
      expect(inDb.collateralItemId, equals(itemId));
      expect(inDb.requestedByUserId, equals(staffId));
      expect(inDb.requestReason,
          equals('Camera hardware failure; physical inspection completed'));
      expect(inDb.status,
          equals(CollateralPhotoExceptionStatus.pendingOwnerApproval));
      expect(inDb.reviewedByUserId, isNull);
      expect(inDb.reviewNotes, isNull);
      expect(inDb.reviewedAt, isNull);
    });

    test('getExceptionById returns null for wrong shop', () async {
      const otherShopId = 'shop-other';
      await db.into(db.shops).insert(
        ShopEntry(
          id: otherShopId,
          name: 'Other Shop',
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      );

      final exception = CollateralPhotoException(
        id: 'exc-dao-002',
        shopId: shopId,
        collateralItemId: itemId,
        requestedByUserId: staffId,
        requestReason: 'Test reason',
        status: CollateralPhotoExceptionStatus.pendingOwnerApproval,
      );
      await exceptionDao.createException(exception);

      final found = await exceptionDao.getExceptionById(otherShopId, exception.id);
      expect(found, isNull);
    });

    test('getPendingExceptions returns only pending items', () async {
      final now = DateTime.now().toUtc();
      await exceptionDao.createException(CollateralPhotoException(
        id: 'exc-dao-003',
        shopId: shopId,
        collateralItemId: itemId,
        requestedByUserId: staffId,
        requestReason: 'Pending exception 1',
        status: CollateralPhotoExceptionStatus.pendingOwnerApproval,
        createdAt: now,
        updatedAt: now,
      ));
      await exceptionDao.createException(CollateralPhotoException(
        id: 'exc-dao-004',
        shopId: shopId,
        collateralItemId: itemId,
        requestedByUserId: staffId,
        requestReason: 'Approved exception',
        status: CollateralPhotoExceptionStatus.approved,
        reviewedByUserId: ownerId,
        reviewNotes: 'Approved',
        reviewedAt: now,
        createdAt: now,
        updatedAt: now,
      ));

      final pending = await exceptionDao.getPendingExceptions(shopId);
      expect(pending.length, equals(1));
      expect(pending.first.status,
          equals(CollateralPhotoExceptionStatus.pendingOwnerApproval));
    });

    test('getExceptionsByCollateralItemId returns items for that item', () async {
      final now = DateTime.now().toUtc();
      await exceptionDao.createException(CollateralPhotoException(
        id: 'exc-dao-005',
        shopId: shopId,
        collateralItemId: itemId,
        requestedByUserId: staffId,
        requestReason: 'Item exception 1',
        status: CollateralPhotoExceptionStatus.pendingOwnerApproval,
        createdAt: now,
        updatedAt: now,
      ));

      const otherItemId = 'coll-other-item';
      await collateralDao.createCollateralItem(CollateralItem(
        id: otherItemId,
        shopId: shopId,
        customerId: customerId,
        itemReferenceId: 'COLL-OTHER',
        category: CollateralItemCategory.electronics,
        description: 'Other item',
        conditionGrade: 'Fair',
        weightMilligrams: 2000,
        estimatedValueCents: 200000,
      ));
      await exceptionDao.createException(CollateralPhotoException(
        id: 'exc-dao-006',
        shopId: shopId,
        collateralItemId: otherItemId,
        requestedByUserId: staffId,
        requestReason: 'Item exception 2',
        status: CollateralPhotoExceptionStatus.pendingOwnerApproval,
        createdAt: now,
        updatedAt: now,
      ));

      final items = await exceptionDao.getExceptionsByCollateralItemId(shopId, itemId);
      expect(items.length, equals(1));
      expect(items.every((e) => e.collateralItemId == itemId), isTrue);
    });

    test('updateException approves and records reviewer', () async {
      final now = DateTime.now().toUtc();
      final exception = CollateralPhotoException(
        id: 'exc-dao-007',
        shopId: shopId,
        collateralItemId: itemId,
        requestedByUserId: staffId,
        requestReason: 'Camera failure',
        status: CollateralPhotoExceptionStatus.pendingOwnerApproval,
        createdAt: now,
        updatedAt: now,
      );
      await exceptionDao.createException(exception);

      final approved = exception.copyWith(
        status: CollateralPhotoExceptionStatus.approved,
        reviewedByUserId: ownerId,
        reviewNotes: 'Approved after physical verification',
        reviewedAt: now,
      );
      await exceptionDao.updateException(approved);

      final inDb = await exceptionDao.getExceptionById(shopId, exception.id);
      expect(inDb!.status, equals(CollateralPhotoExceptionStatus.approved));
      expect(inDb.reviewedByUserId, equals(ownerId));
      expect(inDb.reviewNotes, equals('Approved after physical verification'));
    });

    test('updateException rejects pending exception with reviewer and reason', () async {
      final now = DateTime.now().toUtc();
      final exception = CollateralPhotoException(
        id: 'exc-dao-012',
        shopId: shopId,
        collateralItemId: itemId,
        requestedByUserId: staffId,
        requestReason: 'Camera failure',
        status: CollateralPhotoExceptionStatus.pendingOwnerApproval,
        createdAt: now,
        updatedAt: now,
      );
      await exceptionDao.createException(exception);

      final rejected = exception.copyWith(
        status: CollateralPhotoExceptionStatus.rejected,
        reviewedByUserId: ownerId,
        reviewNotes: 'Photo can be provided; customer has working camera',
        reviewedAt: now,
      );
      await exceptionDao.updateException(rejected);

      final inDb = await exceptionDao.getExceptionById(shopId, exception.id);
      expect(inDb!.status, equals(CollateralPhotoExceptionStatus.rejected));
      expect(inDb.reviewedByUserId, equals(ownerId));
      expect(inDb.reviewNotes,
          equals('Photo can be provided; customer has working camera'));
    });

    test('updateException throws StateError for non-existent exception', () async {
      final exception = CollateralPhotoException(
        id: 'exc-dao-nonexistent',
        shopId: shopId,
        collateralItemId: itemId,
        requestedByUserId: staffId,
        requestReason: 'Test',
        status: CollateralPhotoExceptionStatus.pendingOwnerApproval,
      );

      expect(
        () => exceptionDao.updateException(exception),
        throwsA(isA<StateError>()),
      );
    });

    test('consumeException transitions approved → consumed', () async {
      final now = DateTime.now().toUtc();
      final exception = CollateralPhotoException(
        id: 'exc-dao-008',
        shopId: shopId,
        collateralItemId: itemId,
        requestedByUserId: staffId,
        requestReason: 'Camera failure',
        status: CollateralPhotoExceptionStatus.approved,
        reviewedByUserId: ownerId,
        reviewNotes: 'Approved',
        reviewedAt: now,
        createdAt: now,
        updatedAt: now,
      );
      await exceptionDao.createException(exception);

      await exceptionDao.consumeException(shopId, exception.id, collateralItemId: itemId);

      final inDb = await exceptionDao.getExceptionById(shopId, exception.id);
      expect(inDb!.status, equals(CollateralPhotoExceptionStatus.consumed));
    });

    test('consumeException throws on wrong collateral item binding', () async {
      final now = DateTime.now().toUtc();
      final exception = CollateralPhotoException(
        id: 'exc-dao-009',
        shopId: shopId,
        collateralItemId: itemId,
        requestedByUserId: staffId,
        requestReason: 'Camera failure',
        status: CollateralPhotoExceptionStatus.approved,
        reviewedByUserId: ownerId,
        reviewNotes: 'Approved',
        reviewedAt: now,
        createdAt: now,
        updatedAt: now,
      );
      await exceptionDao.createException(exception);

      expect(
        () => exceptionDao.consumeException(
          shopId,
          exception.id,
          collateralItemId: 'wrong-item-id',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('consumeException throws on non-approved status', () async {
      final now = DateTime.now().toUtc();
      final exception = CollateralPhotoException(
        id: 'exc-dao-010',
        shopId: shopId,
        collateralItemId: itemId,
        requestedByUserId: staffId,
        requestReason: 'Camera failure',
        status: CollateralPhotoExceptionStatus.pendingOwnerApproval,
        createdAt: now,
        updatedAt: now,
      );
      await exceptionDao.createException(exception);

      expect(
        () => exceptionDao.consumeException(shopId, exception.id, collateralItemId: itemId),
        throwsA(isA<StateError>()),
      );
    });

    test('insert with invalid collateral item FK throws', () async {
      const invalidItemId = 'coll-nonexistent';
      final exception = CollateralPhotoException(
        id: 'exc-dao-011',
        shopId: shopId,
        collateralItemId: invalidItemId,
        requestedByUserId: staffId,
        requestReason: 'Test',
        status: CollateralPhotoExceptionStatus.pendingOwnerApproval,
      );

      expect(
        () => exceptionDao.createException(exception),
        throwsA(isA<Exception>()),
      );
    });
  });
}
