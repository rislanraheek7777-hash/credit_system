import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/core/storage/photo_storage_service.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/customer_dao.dart';
import 'package:credit_system/features/customers/domain/models/customer.dart';
import 'package:credit_system/features/customers/presentation/customer_registration_screen.dart';

import '../../../support/customers_test_support.dart';

/// A dummy host route that pushes the registration screen over itself and
/// reports the result the route closed with.
///
/// A successful registration now closes the registration route, so the screen
/// needs a route to return to — a root route has nothing to pop back to.
class _RegistrationHost extends StatefulWidget {
  const _RegistrationHost({
    required this.database,
    required this.currentUser,
    required this.storageService,
    required this.onResult,
  });

  final AppDatabase database;
  final AppUser currentUser;
  final PhotoStorageService storageService;
  final ValueChanged<Customer?> onResult;

  @override
  State<_RegistrationHost> createState() => _RegistrationHostState();
}

class _RegistrationHostState extends State<_RegistrationHost> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final result = await Navigator.of(context).push<Customer>(
              MaterialPageRoute(
                builder: (_) => CustomerRegistrationScreen(
                  database: widget.database,
                  currentUser: widget.currentUser,
                  storageService: widget.storageService,
                ),
              ),
            );
            widget.onResult(result);
          },
          child: const Text('Open registration'),
        ),
      ),
    );
  }
}

/// The customer photograph is optional, and the registration screen no longer
/// offers a capture control for it.
///
/// The screen used to present a "Capture Photo" button that wrote a generated
/// placeholder image as the customer's KYC photograph — the capture was a mock,
/// never a real camera or file-picker capture. That mock was removed, so the
/// screen offers no photograph controls at all and registration proceeds without
/// a photograph.
///
/// The photograph contract itself is not lost: [CustomerRegistrationService]
/// still compresses and stores a photograph when a caller supplies real bytes
/// (`rawPhotoBytes`) and still accepts an approved photo-exception id
/// (`photoExceptionId`). Both paths are covered by the service-level unit tests
/// `customer_registration_service_test.dart` and
/// `customer_photo_exception_service_test.dart`; this file only pins what the
/// screen offers.
///
/// **These assertions pin the CURRENT ABSENCE of the capture controls.**
/// Implementing PRD Story 2.2 — the mandatory customer KYC photograph — will
/// deliberately break every assertion in this file, because the capture,
/// upload, preview, retake and clear controls will reappear on the
/// registration screen. That is the intended signal: this file is the
/// tripwire for the missing capture UI, not a claim that the requirement is
/// met. The requirement itself, and the orphaned
/// `CustomerPhotoExceptionReviewScreen`, are tracked in the deferred-work
/// ledger (`_bmad-output/implementation-artifacts/deferred-work.md`, entries
/// sourced from `spec-credit-origination-return-to-customer-profile.md`).
/// When Story 2.2 is implemented, replace these assertions with ones that
/// pin the new capture flow instead of deleting the file.
void main() {
  late AppDatabase db;
  late Directory tempDir;
  late PhotoStorageService storageService;

  const testShopId = 'shop-kyc-01';
  const testStaffId = 'user-staff-01';
  const testNic = '199012345678';
  const testPhone = '0771234567';

  final staffUser = AppUser(
    id: testStaffId,
    shopId: testShopId,
    username: 'counter.staff',
    fullName: 'Counter Staff',
    role: AppRole.cashier,
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
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// Pushes the registration screen over a dummy host route.
  ///
  /// The returned completer completes with the result the route closed with:
  /// the created customer on a successful registration, and nothing when the
  /// staff member backs out.
  Future<Completer<Customer?>> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final completer = Completer<Customer?>();

    await tester.pumpWidget(
      MaterialApp(
        home: _RegistrationHost(
          database: db,
          currentUser: staffUser,
          storageService: storageService,
          onResult: (customer) {
            if (!completer.isCompleted) completer.complete(customer);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open registration'));
    await tester.pumpAndSettle();

    return completer;
  }

  Future<void> fillFormFields(
    WidgetTester tester, {
    String fullName = 'Kumara Silva',
    String nic = testNic,
    String phone = testPhone,
    String address = 'No 45 Temple Road, Colombo',
  }) async {
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

  group('Customer registration - optional photograph', () {
    testWidgets('the screen offers no photograph capture controls', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);

      expect(find.byKey(const Key('customer_photo_section')), findsNothing);
      expect(find.byKey(const Key('capture_photo_button')), findsNothing);
      expect(find.byKey(const Key('upload_photo_button')), findsNothing);
      expect(find.byKey(const Key('customer_photo_preview')), findsNothing);
      expect(find.byKey(const Key('retake_photo_button')), findsNothing);
      expect(find.byKey(const Key('clear_photo_button')), findsNothing);
      expect(find.text('Customer Photograph (Mandatory KYC)'), findsNothing);
      expect(find.text('No photograph captured'), findsNothing);
    });

    testWidgets('registering without a photograph succeeds and stores no '
        'photo reference', (WidgetTester tester) async {
      final routeResult = await pumpScreen(tester);
      await fillFormFields(tester);

      await tester.ensureVisible(find.byKey(const Key('register_customer_button')));
      await tester.tap(find.byKey(const Key('register_customer_button')));
      await tester.pumpAndSettle();

      // The registration route closes with the created customer; the
      // confirmation belongs to the Customers screen the staff member lands
      // on, so the registration screen shows no success banner of its own.
      await pumpUntil(tester, () => routeResult.isCompleted);
      final created = await routeResult.future;
      expect(created, isNotNull);
      expect(created!.fullName, equals('Kumara Silva'));
      expect(find.byType(CustomerRegistrationScreen), findsNothing);
      expect(
        find.textContaining('Customer "Kumara Silva" registered successfully'),
        findsNothing,
      );

      // The customer is persisted, and no photograph is recorded against it.
      final customerDao = CustomerDao(db);
      final customer = await customerDao.getCustomerByNic(testShopId, testNic);
      expect(customer, isNotNull);
      expect(customer!.fullName, equals('Kumara Silva'));
      expect(customer.photoUri, isNull);
      expect(customer.photoHash, isNull);
    });
  });

  group('Customer registration - photo exception integration', () {
    testWidgets('the screen offers no photo exception request action', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);

      expect(
        find.byKey(const Key('request_photo_exception_button')),
        findsNothing,
      );
      expect(find.text('Request Customer Photo Exception'), findsNothing);
    });

    testWidgets('the screen offers no photo exception id field', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);

      expect(
        find.widgetWithText(TextFormField, 'Photo Exception ID (optional)'),
        findsNothing,
      );
    });
  });
}
