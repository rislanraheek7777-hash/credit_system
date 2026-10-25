import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/customer_dao.dart';
import 'package:credit_system/features/customers/domain/models/customer.dart';
import 'package:credit_system/features/customers/presentation/customer_profile_screen.dart';

void main() {
  late AppDatabase db;

  const testShopId = 'shop-ui-masking-01';
  const testCustomerId = 'cust-ui-001';

  final now = DateTime.now().toUtc();

  final customer = Customer(
    id: testCustomerId,
    shopId: testShopId,
    fullName: 'Sunil Jayawardena',
    nic: '198512345678',
    phone: '+94771234567',
    address: 'No. 88 Temple Passage, Kandy',
    photoUri: 'photos/shop-ui-masking-01/customers/cust-ui-001.jpg',
    photoHash: 'hash-xyz',
    createdAt: now,
    updatedAt: now,
  );

  final cashierUser = AppUser(
    id: 'user-cashier-ui',
    shopId: testShopId,
    username: 'cashier.ui',
    fullName: 'Cashier UI User',
    role: AppRole.cashier,
  );

  final ownerUser = AppUser(
    id: 'user-owner-ui',
    shopId: testShopId,
    username: 'owner.ui',
    fullName: 'Owner UI User',
    role: AppRole.shopOwner,
  );

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);

    await db.into(db.shops).insert(
      ShopEntry(
        id: testShopId,
        name: 'UI Masking Test Jewellers',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final customerDao = CustomerDao(db);
    await customerDao.createCustomer(customer);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required AppUser user,
    bool canViewSensitive = false,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        home: CustomerProfileScreen(
          shopId: testShopId,
          customerId: testCustomerId,
          currentUser: user,
          canViewSensitive: canViewSensitive,
          database: db,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Story 2.6: CustomerProfileScreen UI Masking & RBAC', () {
    testWidgets('renders masked NIC, masked phone, withheld address, and placeholder icon for Cashier', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        user: cashierUser,
        canViewSensitive: false,
      );

      // Verify name
      expect(find.text('Sunil Jayawardena'), findsOneWidget);

      // Verify Masked NIC (1985****5678)
      expect(find.text('NIC: 1985****5678'), findsOneWidget);
      expect(find.text('NIC: 198512345678'), findsNothing);

      // Verify Masked Phone (+94 77 **** 567)
      expect(find.text('Phone: +94 77 **** 567'), findsOneWidget);
      expect(find.text('Phone: +94771234567'), findsNothing);

      // Verify Address withheld
      expect(find.text('Address: Address withheld'), findsOneWidget);
      expect(find.text('Address: No. 88 Temple Passage, Kandy'), findsNothing);

      // Verify generic placeholder icon is shown (CircleAvatar child has Icons.person)
      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('renders unmasked NIC, unmasked phone, full address for Shop Owner', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        user: ownerUser,
        canViewSensitive: true,
      );

      // Verify name
      expect(find.text('Sunil Jayawardena'), findsOneWidget);

      // Verify Full Unmasked NIC
      expect(find.text('NIC: 198512345678'), findsOneWidget);

      // Verify Full Unmasked Phone
      expect(find.text('Phone: +94771234567'), findsOneWidget);

      // Verify Full Residential Address
      expect(find.text('Address: No. 88 Temple Passage, Kandy'), findsOneWidget);
    });
  });
}
