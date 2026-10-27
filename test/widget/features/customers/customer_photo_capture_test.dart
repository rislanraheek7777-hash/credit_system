import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/core/storage/photo_storage_service.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/customer_dao.dart';
import 'package:credit_system/features/customers/data/daos/customer_photo_exception_dao.dart';
import 'package:credit_system/features/customers/domain/models/customer_photo_exception.dart';
import 'package:credit_system/features/customers/domain/services/customer_photo_exception_service.dart';
import 'package:credit_system/features/customers/presentation/customer_registration_screen.dart';

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late PhotoStorageService storageService;

  const testShopId = 'shop-kyc-01';
  const testStaffId = 'user-staff-01';
  const testCustomerId = 'cust-kyc-01';
  const testNic = '199012345678';
  const testPhone = '0771234567';

  final staffUser = AppUser(
    id: testStaffId,
    shopId: testShopId,
    username: 'counter.staff',
    fullName: 'Counter Staff',
    role: AppRole.cashier,
  );

  final ownerUser = AppUser(
    id: 'user-owner-01',
    shopId: testShopId,
    username: 'shop.owner',
    fullName: 'Shop Owner',
    role: AppRole.shopOwner,
  );

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('customer_photo_test_');
    storageService = PhotoStorageService(baseDirectoryOverride: tempDir);

    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);

    final now = DateTime.now().toUtc();
    await db.into(db.shops).insert(
      ShopEntry(
        id: testShopId,
        name: 'KYC Test Jewellers',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
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
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: ownerUser.id,
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
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    AppUser? user,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        home: CustomerRegistrationScreen(
          database: db,
          currentUser: user ?? staffUser,
          storageService: storageService,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fillFormFields(
    WidgetTester tester, {
    String customerId = testCustomerId,
    String shopId = testShopId,
    String fullName = 'Kumara Silva',
    String nic = testNic,
    String phone = testPhone,
    String address = 'No 45 Temple Road, Colombo',
  }) async {
    // Fill text fields
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Customer ID'),
      customerId,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Shop ID'),
      shopId,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Full Name'),
      fullName,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'NIC Number'),
      nic,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Phone Number'),
      phone,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Residential Address'),
      address,
    );
    await tester.pumpAndSettle();
  }

  group('Story 2.2: Mandatory Customer Photo Capture & Preview', () {
    testWidgets('renders photo capture section with capture and upload actions', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);

      expect(find.byKey(const Key('customer_photo_section')), findsOneWidget);
      expect(find.text('Customer Photograph (Mandatory KYC)'), findsOneWidget);
      expect(find.text('No photograph captured'), findsOneWidget);
      expect(find.byKey(const Key('capture_photo_button')), findsOneWidget);
      expect(find.byKey(const Key('upload_photo_button')), findsOneWidget);
      expect(
        find.byKey(const Key('request_photo_exception_button')),
        findsOneWidget,
      );
    });

    testWidgets('submitting profile without a photograph is programmatically blocked with mandatory error', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);
      await fillFormFields(tester);

      // Verify no photo captured yet
      expect(find.byKey(const Key('customer_photo_preview')), findsNothing);

      // Attempt registration
      await tester.ensureVisible(find.byKey(const Key('register_customer_button')));
      await tester.tap(find.byKey(const Key('register_customer_button')));
      await tester.pumpAndSettle();

      // Blocked with exact AC message: "Customer photograph is mandatory."
      expect(find.text('Customer photograph is mandatory.'), findsOneWidget);
    });

    testWidgets('capturing a photo displays live preview, retake, and clear buttons', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);

      // Tap Capture Photo
      await tester.tap(find.byKey(const Key('capture_photo_button')));
      await tester.pumpAndSettle();

      // Preview should be visible
      expect(find.byKey(const Key('customer_photo_preview')), findsOneWidget);
      expect(find.text('Photo Attached'), findsOneWidget);
      expect(find.byKey(const Key('retake_photo_button')), findsOneWidget);
      expect(find.byKey(const Key('clear_photo_button')), findsOneWidget);

      // Tap Clear
      await tester.tap(find.byKey(const Key('clear_photo_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('customer_photo_preview')), findsNothing);
      expect(find.text('No photograph captured'), findsOneWidget);
    });

    testWidgets('registration succeeds when photo is captured and valid fields provided', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);
      await fillFormFields(tester);

      // Capture photo
      await tester.tap(find.byKey(const Key('capture_photo_button')));
      await tester.pumpAndSettle();

      // Tap Register
      await tester.ensureVisible(find.byKey(const Key('register_customer_button')));
      await tester.tap(find.byKey(const Key('register_customer_button')));
      await tester.pumpAndSettle();

      // Success
      expect(
        find.textContaining('Customer "Kumara Silva" registered successfully'),
        findsOneWidget,
      );

      // Verify in database. The customer's primary key is database-assigned,
      // so the row is looked up by NIC.
      final customerDao = CustomerDao(db);
      final customer = await customerDao.getCustomerByNic(testShopId, testNic);
      expect(customer, isNotNull);
      expect(customer!.fullName, equals('Kumara Silva'));
      expect(customer.photoUri, isNotNull);
      expect(customer.photoHash, isNotNull);
    });
  });

  group('Story 2.3: Customer Photo Exception Integration in Registration', () {
    testWidgets('staff requests photo exception with mandatory business justification', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);
      await fillFormFields(tester);

      // Tap Request Photo Exception button
      await tester.ensureVisible(find.byKey(const Key('request_photo_exception_button')));
      await tester.tap(find.byKey(const Key('request_photo_exception_button')));
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.text('Request Customer Photo Exception'), findsOneWidget);
      expect(find.byKey(const Key('submit_exception_request_button')), findsOneWidget);

      // Submit button is disabled when reason is empty
      await tester.tap(find.byKey(const Key('submit_exception_request_button')));
      await tester.pumpAndSettle();
      expect(find.text('Request Customer Photo Exception'), findsOneWidget);

      // Enter justification reason
      await tester.enterText(
        find.byKey(const Key('photo_exception_reason_field')),
        'Webcam broken at counter 1; physically checked original NIC card',
      );
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(find.byKey(const Key('submit_exception_request_button')));
      await tester.pumpAndSettle();

      // Shows pending status banner
      expect(
        find.textContaining('Photo Exception Request Pending Owner Approval'),
        findsOneWidget,
      );

      // Attempting registration while exception is pending is blocked
      await tester.ensureVisible(find.byKey(const Key('register_customer_button')));
      await tester.tap(find.byKey(const Key('register_customer_button')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Photo exception is in state "pending_owner_approval"'),
        findsOneWidget,
      );
    });

    testWidgets('unblocks registration when photo exception is approved by Shop Owner', (
      WidgetTester tester,
    ) async {
      final exceptionDao = CustomerPhotoExceptionDao(db);
      final exceptionService = CustomerPhotoExceptionService(
        exceptionDao: exceptionDao,
        db: db,
      );

      // 1. Staff requests exception
      final exception = await exceptionService.requestPhotoException(
        shopId: testShopId,
        targetCustomerId: testCustomerId,
        customerNic: testNic,
        requester: staffUser,
        reason: 'Client medical bandage over face; physical NIC verified',
      );

      // 2. Shop Owner approves exception
      await exceptionService.approvePhotoException(
        shopId: testShopId,
        exceptionId: exception.id,
        approver: ownerUser,
        reviewNotes: 'Approved for 1-time medical bandage exemption',
      );

      // 3. Register with approved exception ID and NO photo
      await pumpScreen(tester);
      await fillFormFields(tester);

      // Enter approved exception ID
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Photo Exception ID (optional)'),
        exception.id,
      );
      await tester.pumpAndSettle();

      // Submit registration without capturing a photograph
      await tester.ensureVisible(find.byKey(const Key('register_customer_button')));
      await tester.tap(find.byKey(const Key('register_customer_button')));
      await tester.pumpAndSettle();

      // Successfully registered without photo!
      expect(
        find.textContaining('Customer "Kumara Silva" registered successfully'),
        findsOneWidget,
      );

      // Verify exception was consumed
      final updatedEx = await exceptionDao.getExceptionById(testShopId, exception.id);
      expect(updatedEx!.status, equals(PhotoExceptionStatus.consumed));
    });
  });
}
