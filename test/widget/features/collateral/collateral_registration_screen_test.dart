import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/collateral/presentation/collateral_registration_screen.dart';

void main() {
  testWidgets('CollateralRegistrationScreen renders with required fields', (
    WidgetTester tester,
  ) async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    final db = AppDatabase.forTesting(inMemoryExecutor);

    const shopId = 'shop-uuid-widget';
    const customerId = 1;

    final now = DateTime.now().toUtc();
    await db.into(db.shops).insert(
      ShopEntry(
        id: shopId,
        name: 'Widget Test Shop',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.customers).insert(
      CustomerEntry(
        id: customerId,
        shopId: shopId,
        fullName: 'Widget Customer',
        nic: '851234567V',
        phone: '0771234567',
        address: '1 Widget Street',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: 'cashier-id',
        shopId: shopId,
        username: 'cashier',
        fullName: 'Counter Cashier',
        role: 'cashier',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final cashierUser = AppUser(
      id: 'cashier-id',
      shopId: shopId,
      username: 'cashier',
      fullName: 'Counter Cashier',
      role: AppRole.cashier,
      isActive: true,
      sessionVersion: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CollateralRegistrationScreen(
          database: db,
          currentUser: cashierUser,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Register Collateral Item'), findsOneWidget);
    expect(find.text('Item Reference ID'), findsOneWidget);
    expect(find.text('Shop ID'), findsOneWidget);
    expect(find.text('Customer ID'), findsOneWidget);
    expect(find.text('Credit ID (optional)'), findsOneWidget);
    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Condition Grade'), findsOneWidget);
    expect(find.text('Weight (grams)'), findsOneWidget);
    expect(find.text('Estimated Value (LKR)'), findsOneWidget);
    expect(find.text('Item Photograph (Mandatory)'), findsOneWidget);
    expect(find.text('Photo URI'), findsOneWidget);
    expect(find.text('Register Item'), findsOneWidget);

    await db.close();
  });

  testWidgets('CollateralRegistrationScreen disables register without photo', (
    WidgetTester tester,
  ) async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    final db = AppDatabase.forTesting(inMemoryExecutor);

    const shopId = 'shop-uuid-widget-2';
    const customerId = 1;

    final now = DateTime.now().toUtc();
    await db.into(db.shops).insert(
      ShopEntry(
        id: shopId,
        name: 'Widget Test Shop 2',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.customers).insert(
      CustomerEntry(
        id: customerId,
        shopId: shopId,
        fullName: 'Widget Customer 2',
        nic: '851234567V',
        phone: '0771234567',
        address: '1 Widget Street',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: 'cashier-id',
        shopId: shopId,
        username: 'cashier',
        fullName: 'Counter Cashier',
        role: 'cashier',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final cashierUser = AppUser(
      id: 'cashier-id',
      shopId: shopId,
      username: 'cashier',
      fullName: 'Counter Cashier',
      role: AppRole.cashier,
      isActive: true,
      sessionVersion: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CollateralRegistrationScreen(
          database: db,
          currentUser: cashierUser,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final textFields = find.byType(TextFormField);
    expect(textFields, findsAtLeastNWidgets(10));

    await tester.enterText(textFields.at(0), 'COLL-001');
    await tester.enterText(textFields.at(1), shopId);
    await tester.enterText(textFields.at(2), customerId.toString());
    await tester.enterText(textFields.at(4), 'gold');
    await tester.enterText(textFields.at(5), 'Test item');
    await tester.enterText(textFields.at(6), 'Good');
    await tester.enterText(textFields.at(7), '5.5');
    await tester.enterText(textFields.at(8), '1000.00');

    await tester.pumpAndSettle();

    final registerButton = find.byKey(const Key('register_collateral_button'));
    expect(registerButton, findsOneWidget);

    await tester.tap(registerButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.textContaining('registered successfully'), findsNothing);

    await db.close();
  });

  testWidgets('CollateralRegistrationScreen triggers photo compression on button tap', (
    WidgetTester tester,
  ) async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    final db = AppDatabase.forTesting(inMemoryExecutor);

    const shopId = 'shop-uuid-widget-3';
    const customerId = 1;

    final now = DateTime.now().toUtc();
    await db.into(db.shops).insert(
      ShopEntry(
        id: shopId,
        name: 'Widget Test Shop 3',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.customers).insert(
      CustomerEntry(
        id: customerId,
        shopId: shopId,
        fullName: 'Widget Customer 3',
        nic: '851234567V',
        phone: '0771234567',
        address: '1 Widget Street',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: 'cashier-id',
        shopId: shopId,
        username: 'cashier',
        fullName: 'Counter Cashier',
        role: 'cashier',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final cashierUser = AppUser(
      id: 'cashier-id',
      shopId: shopId,
      username: 'cashier',
      fullName: 'Counter Cashier',
      role: AppRole.cashier,
      isActive: true,
      sessionVersion: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CollateralRegistrationScreen(
          database: db,
          currentUser: cashierUser,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final textFields = find.byType(TextFormField);
    expect(textFields, findsAtLeastNWidgets(10));

    await tester.enterText(textFields.at(0), 'COLL-002');
    await tester.enterText(textFields.at(1), shopId);
    await tester.enterText(textFields.at(2), customerId.toString());
    await tester.enterText(textFields.at(4), 'gold');
    await tester.enterText(textFields.at(5), 'Test item with photo');
    await tester.enterText(textFields.at(6), 'Good');
    await tester.enterText(textFields.at(7), '5.5');
    await tester.enterText(textFields.at(8), '1000.00');

    await tester.pumpAndSettle();

    final compressButton = find.text('Compress & Store Photo');
    expect(compressButton, findsOneWidget);

    // Tap compress - should not crash and should trigger async processing
    await tester.tap(compressButton, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // App should remain responsive (no crash)
    expect(find.text('Register Collateral Item'), findsOneWidget);

    await db.close();
  });

  testWidgets('CollateralRegistrationScreen requests photo exception', (
    WidgetTester tester,
  ) async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    final db = AppDatabase.forTesting(inMemoryExecutor);

    const shopId = 'shop-uuid-widget-4';
    const customerId = 1;

    final now = DateTime.now().toUtc();
    await db.into(db.shops).insert(
      ShopEntry(
        id: shopId,
        name: 'Widget Test Shop 4',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.customers).insert(
      CustomerEntry(
        id: customerId,
        shopId: shopId,
        fullName: 'Widget Customer 4',
        nic: '851234567V',
        phone: '0771234567',
        address: '1 Widget Street',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: 'cashier-id',
        shopId: shopId,
        username: 'cashier',
        fullName: 'Counter Cashier',
        role: 'cashier',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final cashierUser = AppUser(
      id: 'cashier-id',
      shopId: shopId,
      username: 'cashier',
      fullName: 'Counter Cashier',
      role: AppRole.cashier,
      isActive: true,
      sessionVersion: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CollateralRegistrationScreen(
          database: db,
          currentUser: cashierUser,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final textFields = find.byType(TextFormField);
    expect(textFields, findsAtLeastNWidgets(11));

    await tester.enterText(textFields.at(0), 'COLL-003');
    await tester.enterText(textFields.at(1), shopId);
    await tester.enterText(textFields.at(2), customerId.toString());
    await tester.enterText(textFields.at(4), 'electronics');
    await tester.enterText(textFields.at(5), 'Test item exception');
    await tester.enterText(textFields.at(6), 'Fair');
    await tester.enterText(textFields.at(7), '2.0');
    await tester.enterText(textFields.at(8), '500.00');

    await tester.pumpAndSettle();

    await tester.enterText(textFields.at(10), 'Camera hardware failure');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Request Photo Exception'), warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // App should remain responsive (no crash)
    expect(find.text('Register Collateral Item'), findsOneWidget);

    await db.close();
  });
}

