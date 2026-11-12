import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/customers/presentation/customer_search_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(AppDatabaseConnection.openInMemoryConnection());
    final now = DateTime.now().toUtc();
    await db.into(db.shops).insert(
      ShopEntry(
        id: 'shop-123',
        name: 'Test Shop',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('CustomerSearchScreen renders search form', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CustomerSearchScreen(
          shopId: 'shop-123',
          currentUser: AppUser(
            id: 'user-1',
            shopId: 'shop-123',
            username: 'testuser',
            fullName: 'Test User',
            role: AppRole.manager,
            isActive: true,
          ),
          database: db,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Search Customers'), findsOneWidget);
    expect(find.text('Search by NIC, phone, or name'), findsOneWidget);
    expect(find.text('Enter at least 2 characters'), findsOneWidget);
  });

  testWidgets('Shared-phone confirmation absent initially', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CustomerSearchScreen(
          shopId: 'shop-123',
          currentUser: AppUser(
            id: 'user-1',
            shopId: 'shop-123',
            username: 'testuser',
            fullName: 'Test User',
            role: AppRole.manager,
            isActive: true,
          ),
          database: db,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The confirmation button should not be visible initially
    expect(
      find.text('Confirm separate individual sharing phone number'),
      findsNothing,
    );
  });
}

