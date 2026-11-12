import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:credit_system/features/customers/presentation/customer_profile_screen.dart';

Future<void> insertCredit(AppDatabase db, Credit credit) async {
  await db.into(db.credits).insert(CreditsCompanion(
    id: Value(credit.id),
    shopId: Value(credit.shopId),
    customerId: Value(credit.customerId),
    principalCents: Value(credit.principalCents),
    balanceCents: Value(credit.balanceCents),
    status: Value(credit.status.value),
    workflowStatus: Value(credit.workflowStatus.value),
    termPresetDays: Value(credit.termPresetDays),
    customDueDate: Value(credit.customDueDate),
    disbursedAt: Value(credit.disbursedAt),
    disbursedByUserId: Value(credit.disbursedByUserId),
    cancelledAt: Value(credit.cancelledAt),
    cancellationReason: Value(credit.cancellationReason),
    dueDate: Value(credit.dueDate),
    createdAt: Value(credit.createdAt),
    settledAt: Value(credit.settledAt),
  ));
}

void main() {
  testWidgets('CustomerProfileScreen displays customer details', (
    WidgetTester tester,
  ) async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    final db = AppDatabase.forTesting(inMemoryExecutor);

    const shopId = 'shop-123';
    const customerId = 456;

    final now = DateTime.now().toUtc();
    await db.into(db.shops).insert(
      ShopEntry(
        id: shopId,
        name: 'Test Shop',
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
        fullName: 'Sunil Perera',
        nic: '851234567V',
        phone: '0771234567',
        address: '1 Main St, Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: 'user-1',
        shopId: shopId,
        username: 'testuser',
        fullName: 'Test User',
        role: 'manager',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await insertCredit(db,
      Credit(
        id: 'credit-1',
        shopId: shopId,
        customerId: customerId,
        principalCents: 500000,
        balanceCents: 300000,
        status: CreditStatus.active,
        dueDate: now.add(const Duration(days: 30)),
        createdAt: now,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CustomerProfileScreen(
          shopId: shopId,
          customerId: customerId,
          canViewSensitive: false,
          database: db,
          currentUser: AppUser(
            id: 'user-1',
            shopId: shopId,
            username: 'testuser',
            fullName: 'Test User',
            role: AppRole.manager,
            isActive: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Customer Profile'), findsOneWidget);
    expect(find.text('Sunil Perera'), findsOneWidget);
    expect(find.text('NIC: 8512****567V'), findsOneWidget);
    expect(find.text('Phone: 077 **** 567'), findsOneWidget);
    expect(find.text('Credit details'), findsOneWidget);
    expect(find.text('Active (1)'), findsOneWidget);

    await db.close();
  });

  testWidgets('CustomerProfileScreen shows sensitive data when authorized', (
    WidgetTester tester,
  ) async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    final db = AppDatabase.forTesting(inMemoryExecutor);

    const shopId = 'shop-123';
    const customerId = 456;

    final now = DateTime.now().toUtc();
    await db.into(db.shops).insert(
      ShopEntry(
        id: shopId,
        name: 'Test Shop',
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
        fullName: 'Sunil Perera',
        nic: '851234567V',
        phone: '0771234567',
        address: '1 Main St, Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: 'user-1',
        shopId: shopId,
        username: 'testuser',
        fullName: 'Test User',
        role: 'manager',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CustomerProfileScreen(
          shopId: shopId,
          customerId: customerId,
          canViewSensitive: true,
          database: db,
          currentUser: AppUser(
            id: 'user-1',
            shopId: shopId,
            username: 'testuser',
            fullName: 'Test User',
            role: AppRole.manager,
            isActive: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sunil Perera'), findsOneWidget);
    expect(find.text('NIC: 851234567V'), findsOneWidget);
    expect(find.text('Phone: 0771234567'), findsOneWidget);
    expect(find.text('Address: 1 Main St, Colombo'), findsOneWidget);

    await db.close();
  });

  testWidgets('CustomerProfileScreen shows no credits when none exist', (
    WidgetTester tester,
  ) async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    final db = AppDatabase.forTesting(inMemoryExecutor);

    const shopId = 'shop-123';
    const customerId = 456;

    final now = DateTime.now().toUtc();
    await db.into(db.shops).insert(
      ShopEntry(
        id: shopId,
        name: 'Test Shop',
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
        fullName: 'Sunil Perera',
        nic: '851234567V',
        phone: '0771234567',
        address: '1 Main St, Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: 'user-1',
        shopId: shopId,
        username: 'testuser',
        fullName: 'Test User',
        role: 'manager',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CustomerProfileScreen(
          shopId: shopId,
          customerId: customerId,
          database: db,
          currentUser: AppUser(
            id: 'user-1',
            shopId: shopId,
            username: 'testuser',
            fullName: 'Test User',
            role: AppRole.manager,
            isActive: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No credit details found'), findsOneWidget);

    await db.close();
  });

  testWidgets('CustomerProfileScreen shows credit status badges', (
    WidgetTester tester,
  ) async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    final db = AppDatabase.forTesting(inMemoryExecutor);

    const shopId = 'shop-123';
    const customerId = 456;

    final now = DateTime.now().toUtc();
    await db.into(db.shops).insert(
      ShopEntry(
        id: shopId,
        name: 'Test Shop',
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
        fullName: 'Sunil Perera',
        nic: '851234567V',
        phone: '0771234567',
        address: '1 Main St, Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: 'user-1',
        shopId: shopId,
        username: 'testuser',
        fullName: 'Test User',
        role: 'manager',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await insertCredit(db,
      Credit(
        id: 'credit-active-1',
        shopId: shopId,
        customerId: customerId,
        principalCents: 500000,
        balanceCents: 300000,
        status: CreditStatus.active,
        dueDate: now.add(const Duration(days: 30)),
        createdAt: now,
      ),
    );
    await insertCredit(db,
      Credit(
        id: 'credit-overdue-1',
        shopId: shopId,
        customerId: customerId,
        principalCents: 300000,
        balanceCents: 200000,
        status: CreditStatus.overdue,
        dueDate: now.subtract(const Duration(days: 5)),
        createdAt: now,
      ),
    );
    await insertCredit(db,
      Credit(
        id: 'credit-settled-1',
        shopId: shopId,
        customerId: customerId,
        principalCents: 200000,
        balanceCents: 0,
        status: CreditStatus.settled,
        workflowStatus: CreditWorkflowStatus.disbursed,
        dueDate: now.subtract(const Duration(days: 10)),
        createdAt: now,
        settledAt: now,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CustomerProfileScreen(
          shopId: shopId,
          customerId: customerId,
          database: db,
          currentUser: AppUser(
            id: 'user-1',
            shopId: shopId,
            username: 'testuser',
            fullName: 'Test User',
            role: AppRole.manager,
            isActive: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Active (1)'), findsOneWidget);
    expect(find.text('Overdue (1)'), findsOneWidget);
    expect(find.text('Settled (1)'), findsOneWidget);

    await db.close();
  });

  testWidgets('CustomerProfileScreen shows Edit action', (
    WidgetTester tester,
  ) async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    final db = AppDatabase.forTesting(inMemoryExecutor);

    const shopId = 'shop-123';
    const customerId = 456;

    final now = DateTime.now().toUtc();
    await db.into(db.shops).insert(
      ShopEntry(
        id: shopId,
        name: 'Test Shop',
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
        fullName: 'Sunil Perera',
        nic: '851234567V',
        phone: '0771234567',
        address: '1 Main St, Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CustomerProfileScreen(
          shopId: shopId,
          customerId: customerId,
          database: db,
          currentUser: AppUser(
            id: 'user-1',
            shopId: shopId,
            username: 'testuser',
            fullName: 'Test User',
            role: AppRole.manager,
            isActive: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('edit_customer_button')), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);

    await db.close();
  });

  testWidgets('CustomerProfileScreen shows Add Credit action and opens origination', (
    WidgetTester tester,
  ) async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    final db = AppDatabase.forTesting(inMemoryExecutor);

    const shopId = 'shop-123';
    const customerId = 456;

    final now = DateTime.now().toUtc();
    await db.into(db.shops).insert(
      ShopEntry(
        id: shopId,
        name: 'Test Shop',
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
        fullName: 'Sunil Perera',
        nic: '851234567V',
        phone: '0771234567',
        address: '1 Main St, Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CustomerProfileScreen(
          shopId: shopId,
          customerId: customerId,
          database: db,
          currentUser: AppUser(
            id: 'user-1',
            shopId: shopId,
            username: 'testuser',
            fullName: 'Test User',
            role: AppRole.cashier,
            isActive: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('add_credit_button')), findsOneWidget);
    expect(find.text('Add Credit'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add_credit_button')));
    await tester.pumpAndSettle();

    expect(find.text('Credit Origination'), findsOneWidget);

    await db.close();
  });

  testWidgets('CustomerProfileScreen hides Add Credit action without createCredits', (
    WidgetTester tester,
  ) async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    final db = AppDatabase.forTesting(inMemoryExecutor);

    const shopId = 'shop-123';
    const customerId = 456;

    final now = DateTime.now().toUtc();
    await db.into(db.shops).insert(
      ShopEntry(
        id: shopId,
        name: 'Test Shop',
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
        fullName: 'Sunil Perera',
        nic: '851234567V',
        phone: '0771234567',
        address: '1 Main St, Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CustomerProfileScreen(
          shopId: shopId,
          customerId: customerId,
          database: db,
          currentUser: AppUser(
            id: 'user-1',
            shopId: shopId,
            username: 'testuser',
            fullName: 'Test User',
            role: AppRole.custom,
            isActive: true,
            customPermissions: {AppPermission.viewCustomers},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('add_credit_button')), findsNothing);
    expect(find.text('Add Credit'), findsNothing);

    await db.close();
  });

  testWidgets('Edit action opens the edit form and saves profile changes', (
    WidgetTester tester,
  ) async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    final db = AppDatabase.forTesting(inMemoryExecutor);

    const shopId = 'shop-123';
    const customerId = 456;

    final now = DateTime.now().toUtc();
    await db.into(db.shops).insert(
      ShopEntry(
        id: shopId,
        name: 'Test Shop',
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
        fullName: 'Sunil Perera',
        nic: '851234567V',
        phone: '0771234567',
        address: '1 Main St, Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CustomerProfileScreen(
          shopId: shopId,
          customerId: customerId,
          canViewSensitive: true,
          database: db,
          currentUser: AppUser(
            id: 'user-1',
            shopId: shopId,
            username: 'testuser',
            fullName: 'Test User',
            role: AppRole.manager,
            isActive: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('edit_customer_button')));
    await tester.pumpAndSettle();

    expect(find.text('Edit Customer'), findsOneWidget);
    expect(find.text('Sunil Perera'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('edit_customer_full_name_field')),
      'Sunil Perera Silva',
    );
    await tester.tap(find.byKey(const Key('save_customer_button')));
    await tester.pumpAndSettle();

    // Back on the profile, showing the updated name.
    expect(find.text('Customer Profile'), findsOneWidget);
    expect(find.text('Sunil Perera Silva'), findsOneWidget);

    final row = await (db.select(db.customers)
          ..where((c) => c.id.equals(customerId)))
        .getSingle();
    expect(row.fullName, 'Sunil Perera Silva');

    await db.close();
  });

}

