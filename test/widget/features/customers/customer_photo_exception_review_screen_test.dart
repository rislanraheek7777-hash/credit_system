import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/customer_photo_exception_dao.dart';
import 'package:credit_system/features/customers/domain/models/customer_photo_exception.dart';
import 'package:credit_system/features/customers/domain/services/customer_photo_exception_service.dart';
import 'package:credit_system/features/customers/presentation/customer_photo_exception_review_screen.dart';

void main() {
  late AppDatabase db;
  late CustomerPhotoExceptionDao exceptionDao;
  late CustomerPhotoExceptionService exceptionService;

  const testShopId = 'shop-review-01';
  const testStaffId = 'user-staff-01';
  const testOwnerId = 'user-owner-01';
  const testManagerId = 'user-mgr-01';

  final ownerUser = AppUser(
    id: testOwnerId,
    shopId: testShopId,
    username: 'shop.owner',
    fullName: 'Sunil Perera',
    role: AppRole.shopOwner,
  );

  final managerUser = AppUser(
    id: testManagerId,
    shopId: testShopId,
    username: 'shop.manager',
    fullName: 'Manager User',
    role: AppRole.manager,
  );

  final staffUser = AppUser(
    id: testStaffId,
    shopId: testShopId,
    username: 'counter.staff',
    fullName: 'Counter Staff',
    role: AppRole.cashier,
  );

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);
    exceptionDao = CustomerPhotoExceptionDao(db);
    exceptionService = CustomerPhotoExceptionService(
      exceptionDao: exceptionDao,
      db: db,
    );

    final now = DateTime.now().toUtc();
    await db.into(db.shops).insert(
      ShopEntry(
        id: testShopId,
        name: 'Review Test Jewellers',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: testOwnerId,
        shopId: testShopId,
        username: ownerUser.username,
        fullName: ownerUser.fullName,
        role: 'shop_owner',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: testStaffId,
        shopId: testShopId,
        username: staffUser.username,
        fullName: staffUser.fullName,
        role: 'cashier',
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

  Future<void> pumpScreen(
    WidgetTester tester, {
    required AppUser user,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CustomerPhotoExceptionReviewScreen(
          shopId: testShopId,
          currentUser: user,
          database: db,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('CustomerPhotoExceptionReviewScreen - RBAC & Access Control', () {
    testWidgets('non-owner roles (manager, cashier) are rejected with access denied error', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, user: managerUser);

      // Error shown on screen
      expect(
        find.textContaining('Only a Shop Owner can view customer photo exception reviews'),
        findsOneWidget,
      );
    });

    testWidgets('active Shop Owner accesses screen and sees empty state when no requests exist', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, user: ownerUser);

      expect(find.text('Customer Photo Exception Review'), findsOneWidget);
      expect(
        find.text('No pending customer photo exception requests.'),
        findsOneWidget,
      );
    });
  });

  group('CustomerPhotoExceptionReviewScreen - Approval & Rejection Workflow', () {
    testWidgets('Shop Owner approves photo exception, records Category 1 SyncQueue entry', (
      WidgetTester tester,
    ) async {
      // Seed a pending exception
      final ex = await exceptionService.requestPhotoException(
        shopId: testShopId,
        targetCustomerId: 'cust-app-01',
        customerNic: '198512345678',
        requester: staffUser,
        reason: 'Broken webcam on Counter 1; checked physical card',
      );

      await pumpScreen(tester, user: ownerUser);

      // Verify exception card is displayed
      expect(find.text('Customer ID: cust-app-01'), findsOneWidget);
      expect(find.text('NIC: 198512345678'), findsOneWidget);
      expect(find.text('Pending Owner Approval'), findsOneWidget);
      expect(find.text('Broken webcam on Counter 1; checked physical card'), findsOneWidget);
      expect(find.byKey(Key('btn_approve_${ex.id}')), findsOneWidget);
      expect(find.byKey(Key('btn_reject_${ex.id}')), findsOneWidget);

      // Tap Approve
      await tester.tap(find.byKey(Key('btn_approve_${ex.id}')));
      await tester.pumpAndSettle();

      // Decision notes dialog opens
      expect(find.text('Approve Customer Photo Exception'), findsOneWidget);
      expect(find.byKey(const Key('confirm_decision_button')), findsOneWidget);

      // Enter approval notes
      await tester.enterText(
        find.byKey(const Key('photo_exception_review_notes_field')),
        'Approved one-time waiver. Repair order placed for counter 1 webcam.',
      );
      await tester.pumpAndSettle();

      // Submit decision
      await tester.tap(find.byKey(const Key('confirm_decision_button')));
      await tester.pumpAndSettle();

      // SnackBar shows success
      expect(find.textContaining('approved'), findsOneWidget);
      expect(
        find.text('No pending customer photo exception requests.'),
        findsOneWidget,
      );

      // Verify in DB
      final inDb = await exceptionDao.getExceptionById(testShopId, ex.id);
      expect(inDb!.status, equals(PhotoExceptionStatus.approved));
      expect(inDb.reviewedByUserId, equals(ownerUser.id));
      expect(inDb.reviewNotes, contains('Approved one-time waiver'));

      // Verify Category 1 SyncQueue audit entry
      final syncEntries = await (db.select(db.syncQueue)
            ..where((s) => s.shopId.equals(testShopId)))
          .get();
      expect(syncEntries.length, equals(2)); // 1 for request, 1 for approve

      final approveSync = syncEntries.firstWhere(
        (s) => s.actionType == 'approve_customer_photo_exception',
      );
      expect(approveSync.entityType, equals('customer_photo_exception'));
      expect(approveSync.entityId, equals(ex.id));

      final payload = jsonDecode(approveSync.payloadJson) as Map<String, dynamic>;
      expect(payload['auditCategory'], equals(1));
      expect(payload['auditEvent'], equals('customer_photo_exception_approved'));
      expect(payload['actorId'], equals(ownerUser.id));
      expect(payload['targetCustomerId'], equals('cust-app-01'));
    });

    testWidgets('Shop Owner rejects photo exception with mandatory rejection reason', (
      WidgetTester tester,
    ) async {
      final ex = await exceptionService.requestPhotoException(
        shopId: testShopId,
        targetCustomerId: 'cust-rej-01',
        customerNic: '198712345678',
        requester: staffUser,
        reason: 'Staff claims customer refused photo',
      );

      await pumpScreen(tester, user: ownerUser);

      expect(find.text('Customer ID: cust-rej-01'), findsOneWidget);

      // Tap Reject
      await tester.tap(find.byKey(Key('btn_reject_${ex.id}')));
      await tester.pumpAndSettle();

      expect(find.text('Reject Customer Photo Exception'), findsOneWidget);

      // Enter rejection reason
      await tester.enterText(
        find.byKey(const Key('photo_exception_review_notes_field')),
        'Mandatory photo policy cannot be bypassed for personal preference. Request denied.',
      );
      await tester.pumpAndSettle();

      // Confirm
      await tester.tap(find.byKey(const Key('confirm_decision_button')));
      await tester.pumpAndSettle();

      // Success SnackBar and list emptied
      expect(find.textContaining('rejected'), findsOneWidget);
      expect(
        find.text('No pending customer photo exception requests.'),
        findsOneWidget,
      );

      // Verify in DB
      final inDb = await exceptionDao.getExceptionById(testShopId, ex.id);
      expect(inDb!.status, equals(PhotoExceptionStatus.rejected));
      expect(inDb.reviewedByUserId, equals(ownerUser.id));

      // Verify Category 1 SyncQueue entry
      final syncEntries = await (db.select(db.syncQueue)
            ..where((s) => s.shopId.equals(testShopId)))
          .get();
      final rejectSync = syncEntries.firstWhere(
        (s) => s.actionType == 'reject_customer_photo_exception',
      );
      final payload = jsonDecode(rejectSync.payloadJson) as Map<String, dynamic>;
      expect(payload['auditCategory'], equals(1));
      expect(payload['auditEvent'], equals('customer_photo_exception_rejected'));
      expect(payload['actorId'], equals(ownerUser.id));
    });
  });
}
