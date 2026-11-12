import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/data/daos/user_dao.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/auth/presentation/staff_management_screen.dart';
import 'package:credit_system/features/shop/data/daos/shop_dao.dart';
import 'package:credit_system/features/shop/domain/models/shop_profile.dart';

void main() {
  group('StaffManagementScreen - Staff Listing (Story 1.7)', () {
    late AppDatabase db;
    late UserDao userDao;
    late ShopDao shopDao;
    final owner = AppUser(
      id: 'owner-001',
      shopId: 'shop-alpha-100',
      username: 'owner',
      fullName: 'Shop Owner',
      role: AppRole.shopOwner,
      isActive: true,
      sessionVersion: 1,
    );
    final cashier = AppUser(
      id: 'cashier-001',
      shopId: 'shop-alpha-100',
      username: 'cashier',
      fullName: 'Cashier User',
      role: AppRole.cashier,
      isActive: true,
      sessionVersion: 1,
    );

    setUp(() async {
      final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
      db = AppDatabase.forTesting(inMemoryExecutor);
      userDao = UserDao(db);
      shopDao = ShopDao(db);

      await shopDao.createShop(
        ShopProfile(id: 'shop-alpha-100', name: 'Alpha Jewellers'),
      );
      await shopDao.createShop(
        ShopProfile(id: 'shop-beta-200', name: 'Beta Jewellers'),
      );

      await userDao.createUserWithPassword(owner, 'ownerpass123');
      await userDao.createUserWithPassword(cashier, 'cashierpass123');
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('displays staff list for current shop', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StaffManagementScreen(
            shopId: 'shop-alpha-100',
            currentUser: owner,
            database: db,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Staff Management'), findsOneWidget);
      expect(find.text('Shop Owner'), findsOneWidget);
      expect(find.text('Cashier User'), findsOneWidget);
    });

    testWidgets('shows empty state when no staff exist', (
      WidgetTester tester,
    ) async {
      await shopDao.createShop(
        ShopProfile(id: 'shop-empty-300', name: 'Empty Shop'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: StaffManagementScreen(
            shopId: 'shop-empty-300',
            currentUser: owner,
            database: db,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No staff accounts found'), findsOneWidget);
    });

    testWidgets('rejects non-owner access', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StaffManagementScreen(
            shopId: 'shop-alpha-100',
            currentUser: cashier,
            database: db,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Non-owner should see access denied screen (no Add Staff button)
      expect(find.text('Add Staff'), findsNothing);
    });

    testWidgets('shows only staff for current shop', (
      WidgetTester tester,
    ) async {
      await userDao.createUserWithPassword(
        AppUser(
          id: 'cashier-beta',
          shopId: 'shop-beta-200',
          username: 'beta.cashier',
          fullName: 'Beta Cashier',
          role: AppRole.cashier,
        ),
        'betapass123',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: StaffManagementScreen(
            shopId: 'shop-alpha-100',
            currentUser: owner,
            database: db,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Shop Owner'), findsOneWidget);
      expect(find.text('Cashier User'), findsOneWidget);
      expect(find.text('Beta Cashier'), findsNothing);
    });

    testWidgets('navigates to staff form on add staff', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StaffManagementScreen(
            shopId: 'shop-alpha-100',
            currentUser: owner,
            database: db,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.person_add));
      await tester.pumpAndSettle();

      expect(find.text('Add Staff'), findsOneWidget);
      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Initial Password'), findsOneWidget);
    });
  });
}

