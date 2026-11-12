import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/core/permissions/authorization_guard.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/customer_photo_exception_dao.dart';
import 'package:credit_system/features/customers/domain/models/customer.dart';
import 'package:credit_system/features/customers/domain/models/customer_photo_exception.dart';
import 'package:credit_system/features/customers/domain/services/customer_photo_exception_service.dart';

void main() {
  late AppDatabase db;
  late CustomerPhotoExceptionDao dao;
  late CustomerPhotoExceptionService service;

  const testShopId = 'shop-serv-test';
  const otherShopId = 'shop-serv-other';

  late AppUser shopOwnerUser;
  late AppUser counterStaffUser;
  late AppUser unauthorizedStaffUser;
  late AppUser deactivatedOwnerUser;

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);
    dao = CustomerPhotoExceptionDao(db);
    service = CustomerPhotoExceptionService(exceptionDao: dao);

    final now = DateTime.now().toUtc();
    // Seed shop
    await db.into(db.shops).insert(
      ShopEntry(
        id: testShopId,
        name: 'Service Test Jewellers',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );

    shopOwnerUser = AppUser(
      id: 'user-owner-1',
      shopId: testShopId,
      username: 'owner.user',
      fullName: 'Sunil Perera (Owner)',
      role: AppRole.shopOwner,
      isActive: true,
    );
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: shopOwnerUser.id,
        shopId: testShopId,
        username: shopOwnerUser.username,
        fullName: shopOwnerUser.fullName,
        role: shopOwnerUser.role.key,
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );

    counterStaffUser = AppUser(
      id: 'user-staff-1',
      shopId: testShopId,
      username: 'staff.user',
      fullName: 'Kasun Bandara (Staff)',
      role: AppRole.cashier,
      isActive: true,
    );
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: counterStaffUser.id,
        shopId: testShopId,
        username: counterStaffUser.username,
        fullName: counterStaffUser.fullName,
        role: counterStaffUser.role.key,
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );

    unauthorizedStaffUser = AppUser(
      id: 'user-unauth-1',
      shopId: testShopId,
      username: 'unauth.user',
      fullName: 'Restricted Staff',
      role: AppRole.custom,
      isActive: true,
      customPermissions: const {AppPermission.viewCustomers}, // Missing registerCustomers!
    );
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: unauthorizedStaffUser.id,
        shopId: testShopId,
        username: unauthorizedStaffUser.username,
        fullName: unauthorizedStaffUser.fullName,
        role: unauthorizedStaffUser.role.key,
        isActive: true,
        sessionVersion: 1,
        permissions: 'viewCustomers',
        createdAt: now,
        updatedAt: now,
      ),
    );

    deactivatedOwnerUser = AppUser(
      id: 'user-deact-owner',
      shopId: testShopId,
      username: 'deact.owner',
      fullName: 'Deactivated Owner',
      role: AppRole.shopOwner,
      isActive: false,
    );
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: deactivatedOwnerUser.id,
        shopId: testShopId,
        username: deactivatedOwnerUser.username,
        fullName: deactivatedOwnerUser.fullName,
        role: deactivatedOwnerUser.role.key,
        isActive: false,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('CustomerPhotoExceptionService Workflow & RBAC Tests (Story 2.3)', () {
    test('REQUEST: Authorized staff member can request photo exception with mandatory reason', () async {
      final exception = await service.requestPhotoException(
        shopId: testShopId,
        targetCustomerId: 'cust-uuid-201',
        customerNic: '198512345678',
        requester: counterStaffUser,
        reason: 'Camera hardware malfunction; verified physical NIC.',
      );

      expect(exception.shopId, equals(testShopId));
      expect(exception.targetCustomerId, equals('cust-uuid-201'));
      expect(exception.customerNic, equals('198512345678'));
      expect(exception.requestedByUserId, equals(counterStaffUser.id));
      expect(exception.requestReason, equals('Camera hardware malfunction; verified physical NIC.'));
      expect(exception.status, equals(PhotoExceptionStatus.pendingOwnerApproval));
      expect(exception.reviewedByUserId, isNull);

      final inDb = await dao.getExceptionById(testShopId, exception.id);
      expect(inDb, isNotNull);
      expect(inDb!.status, equals(PhotoExceptionStatus.pendingOwnerApproval));
    });

    test('REQUEST: Staff lacking registerCustomers permission cannot request exception', () async {
      expect(
        () => service.requestPhotoException(
          shopId: testShopId,
          targetCustomerId: 'cust-uuid-202',
          customerNic: '198512345678',
          requester: unauthorizedStaffUser,
          reason: 'Camera hardware failure',
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('REQUEST: Empty or whitespace request reason is strictly blocked', () async {
      expect(
        () => service.requestPhotoException(
          shopId: testShopId,
          targetCustomerId: 'cust-uuid-203',
          customerNic: '198512345678',
          requester: counterStaffUser,
          reason: '    ',
        ),
        throwsA(isA<CustomerValidationException>()),
      );
    });

    test('APPROVAL: Counter staff is strictly blocked from approving photo exception', () async {
      final exception = await service.requestPhotoException(
        shopId: testShopId,
        targetCustomerId: 'cust-uuid-204',
        customerNic: '198512345678',
        requester: counterStaffUser,
        reason: 'Hardware failure',
      );

      // Staff attempts self-approval or peer approval -> must fail
      expect(
        () => service.approvePhotoException(
          shopId: testShopId,
          exceptionId: exception.id,
          approver: counterStaffUser,
          reviewNotes: 'Staff self-approval attempt',
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('APPROVAL: Deactivated Shop Owner is blocked from approving', () async {
      final exception = await service.requestPhotoException(
        shopId: testShopId,
        targetCustomerId: 'cust-uuid-205',
        customerNic: '198512345678',
        requester: counterStaffUser,
        reason: 'Hardware failure',
      );

      expect(
        () => service.approvePhotoException(
          shopId: testShopId,
          exceptionId: exception.id,
          approver: deactivatedOwnerUser,
          reviewNotes: 'Approval by inactive owner',
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('APPROVAL: Active Shop Owner successfully approves with mandatory notes', () async {
      final exception = await service.requestPhotoException(
        shopId: testShopId,
        targetCustomerId: 'cust-uuid-206',
        customerNic: '198512345678',
        requester: counterStaffUser,
        reason: 'Camera driver corrupted; physical NIC card verified by counter staff',
      );

      final approved = await service.approvePhotoException(
        shopId: testShopId,
        exceptionId: exception.id,
        approver: shopOwnerUser,
        reviewNotes: 'Reviewed physical NIC copy in person. Exception approved for onboarding.',
      );

      expect(approved.status, equals(PhotoExceptionStatus.approved));
      expect(approved.reviewedByUserId, equals(shopOwnerUser.id));
      expect(approved.reviewNotes, contains('Reviewed physical NIC copy in person'));
      expect(approved.reviewedAt, isNotNull);

      final inDb = await dao.getExceptionById(testShopId, exception.id);
      expect(inDb!.status, equals(PhotoExceptionStatus.approved));
      expect(inDb.reviewedByUserId, equals(shopOwnerUser.id));
    });

    test('APPROVAL: Empty approval review notes are strictly rejected', () async {
      final exception = await service.requestPhotoException(
        shopId: testShopId,
        targetCustomerId: 'cust-uuid-207',
        customerNic: '198512345678',
        requester: counterStaffUser,
        reason: 'Hardware failure',
      );

      expect(
        () => service.approvePhotoException(
          shopId: testShopId,
          exceptionId: exception.id,
          approver: shopOwnerUser,
          reviewNotes: '   ',
        ),
        throwsA(isA<CustomerValidationException>()),
      );
    });

    test('REJECTION: Shop Owner rejects exception with mandatory rejection note', () async {
      final exception = await service.requestPhotoException(
        shopId: testShopId,
        targetCustomerId: 'cust-uuid-208',
        customerNic: '198512345678',
        requester: counterStaffUser,
        reason: 'Camera failure',
      );

      final rejected = await service.rejectPhotoException(
        shopId: testShopId,
        exceptionId: exception.id,
        reviewer: shopOwnerUser,
        reviewNotes: 'Cannot approve without backup web camera; bring spare camera from office.',
      );

      expect(rejected.status, equals(PhotoExceptionStatus.rejected));
      expect(rejected.reviewedByUserId, equals(shopOwnerUser.id));
      expect(rejected.reviewNotes, contains('Cannot approve without backup web camera'));
      expect(rejected.reviewedAt, isNotNull);

      final inDb = await dao.getExceptionById(testShopId, exception.id);
      expect(inDb!.status, equals(PhotoExceptionStatus.rejected));
    });

    test('REJECTION: Counter staff is strictly blocked from rejecting photo exception', () async {
      final exception = await service.requestPhotoException(
        shopId: testShopId,
        targetCustomerId: 'cust-uuid-209',
        customerNic: '198512345678',
        requester: counterStaffUser,
        reason: 'Hardware failure',
      );

      expect(
        () => service.rejectPhotoException(
          shopId: testShopId,
          exceptionId: exception.id,
          reviewer: counterStaffUser,
          reviewNotes: 'Staff rejection attempt',
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('STATE INTEGRITY: Cannot re-approve or re-reject an already processed exception', () async {
      final exception = await service.requestPhotoException(
        shopId: testShopId,
        targetCustomerId: 'cust-uuid-210',
        customerNic: '198512345678',
        requester: counterStaffUser,
        reason: 'Hardware failure',
      );

      await service.approvePhotoException(
        shopId: testShopId,
        exceptionId: exception.id,
        approver: shopOwnerUser,
        reviewNotes: 'First approval',
      );

      // Attempting to approve again -> must throw StateError
      expect(
        () => service.approvePhotoException(
          shopId: testShopId,
          exceptionId: exception.id,
          approver: shopOwnerUser,
          reviewNotes: 'Second approval attempt',
        ),
        throwsA(isA<StateError>()),
      );

      // Attempting to reject an approved exception -> must throw StateError
      expect(
        () => service.rejectPhotoException(
          shopId: testShopId,
          exceptionId: exception.id,
          reviewer: shopOwnerUser,
          reviewNotes: 'Post-approval rejection attempt',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('TENANT BOUNDARY: Cross-shop request or approval attempts are strictly blocked', () async {
      // 1. Staff of testShopId attempts to request in otherShopId -> rejected
      expect(
        () => service.requestPhotoException(
          shopId: otherShopId,
          targetCustomerId: 'cust-uuid-cross',
          customerNic: '198512345678',
          requester: counterStaffUser,
          reason: 'Cross shop request attempt',
        ),
        throwsA(isA<PermissionDeniedException>()),
      );

      // Create valid exception in testShopId
      final exception = await service.requestPhotoException(
        shopId: testShopId,
        targetCustomerId: 'cust-uuid-cross-appr',
        customerNic: '198512345678',
        requester: counterStaffUser,
        reason: 'Hardware failure',
      );

      // 2. Owner of testShopId attempts to approve in otherShopId -> rejected
      expect(
        () => service.approvePhotoException(
          shopId: otherShopId,
          exceptionId: exception.id,
          approver: shopOwnerUser,
          reviewNotes: 'Cross shop approval attempt',
        ),
        throwsA(isA<PermissionDeniedException>()),
      );

      // 3. User attempts to query pending exceptions in otherShopId -> rejected
      expect(
        () => service.getPendingExceptions(
          otherShopId,
          viewer: counterStaffUser,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });
  });
}

