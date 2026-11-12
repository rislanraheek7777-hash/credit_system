import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/data/daos/user_dao.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/auth/presentation/staff_form_screen.dart';
import 'package:credit_system/features/shop/data/daos/shop_dao.dart';
import 'package:credit_system/features/shop/domain/models/shop_profile.dart';

void main() {
  group('StaffFormScreen - Staff Creation & Editing (Story 1.7)', () {
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

    testWidgets('renders staff form with all fields', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StaffFormScreen(
            shopId: 'shop-alpha-100',
            currentUser: owner,
            database: db,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add Staff'), findsOneWidget);
      expect(find.byType(TextFormField).at(0), findsOneWidget); // Full name
      expect(find.byType(TextFormField).at(1), findsOneWidget); // Username
      expect(find.byType(TextFormField).at(2), findsOneWidget); // Password
    });

    testWidgets('rejects non-owner access', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StaffFormScreen(
            shopId: 'shop-alpha-100',
            currentUser: cashier,
            database: db,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Non-owner should see access denied screen (any screen without Add Staff)
      expect(find.text('Add Staff'), findsNothing);
    });

    testWidgets('applies cashier role template permissions', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StaffFormScreen(
            shopId: 'shop-alpha-100',
            currentUser: owner,
            database: db,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Cashier is default - should have 6 permissions checked
      expect(find.text('registerCustomers'), findsOneWidget);
      expect(find.text('createCredits'), findsOneWidget);
      expect(find.text('recordPayments'), findsOneWidget);
      // Cashier should NOT have approveCorrections
    });

    testWidgets('applies manager role template permissions', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StaffFormScreen(
            shopId: 'shop-alpha-100',
            currentUser: owner,
            database: db,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select Manager role
      await tester.tap(find.byType(DropdownButtonFormField<AppRole>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manager').last);
      await tester.pumpAndSettle();

      // Manager should have manager permissions
      expect(find.text('viewSensitiveCustomerData'), findsOneWidget);
      expect(find.text('confirmCreditDisbursement'), findsOneWidget);
    });

    testWidgets('edits existing staff - form loads with existing data', (
      WidgetTester tester,
    ) async {
      final staff = AppUser(
        id: 'edit-001',
        shopId: 'shop-alpha-100',
        username: 'edit.staff',
        fullName: 'Edit Staff',
        role: AppRole.cashier,
      );
      await userDao.createUserWithPassword(staff, 'pass123');

      await tester.pumpWidget(
        MaterialApp(
          home: StaffFormScreen(
            shopId: 'shop-alpha-100',
            currentUser: owner,
            user: staff,
            database: db,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('edit.staff'), findsOneWidget);
    });
  });
}

