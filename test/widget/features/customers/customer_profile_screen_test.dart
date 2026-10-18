import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/features/customers/data/daos/customer_dao.dart';
import 'package:credit_system/features/customers/data/daos/loan_dao.dart';
import 'package:credit_system/features/customers/domain/models/customer.dart';
import 'package:credit_system/features/customers/domain/models/loan.dart';
import 'package:credit_system/features/customers/presentation/customer_profile_screen.dart';

void main() {
  testWidgets('CustomerProfileScreen displays customer details', (
    WidgetTester tester,
  ) async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    final db = AppDatabase.forTesting(inMemoryExecutor);
    final customerDao = CustomerDao(db);
    final loanDao = LoanDao(db);

    const shopId = 'shop-123';
    const customerId = 'cust-456';

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
    await loanDao.createLoan(
      Loan(
        id: 'loan-1',
        shopId: shopId,
        customerId: customerId,
        principalCents: 500000,
        balanceCents: 300000,
        status: LoanStatus.active,
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
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Customer Profile'), findsOneWidget);
    expect(find.text('Sunil Perera'), findsOneWidget);
    expect(find.text('NIC: 8512****567V'), findsOneWidget);
    expect(find.text('Phone: 077 **** 567'), findsOneWidget);
    expect(find.text('Loans'), findsOneWidget);
    expect(find.text('Active (1)'), findsOneWidget);

    await db.close();
  });

  testWidgets('CustomerProfileScreen shows sensitive data when authorized', (
    WidgetTester tester,
  ) async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    final db = AppDatabase.forTesting(inMemoryExecutor);

    const shopId = 'shop-123';
    const customerId = 'cust-456';

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

  testWidgets('CustomerProfileScreen shows no loans when none exist', (
    WidgetTester tester,
  ) async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    final db = AppDatabase.forTesting(inMemoryExecutor);

    const shopId = 'shop-123';
    const customerId = 'cust-456';

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
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No loans found'), findsOneWidget);

    await db.close();
  });

  testWidgets('CustomerProfileScreen shows loan status badges', (
    WidgetTester tester,
  ) async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    final db = AppDatabase.forTesting(inMemoryExecutor);
    final loanDao = LoanDao(db);

    const shopId = 'shop-123';
    const customerId = 'cust-456';

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
    await loanDao.createLoan(
      Loan(
        id: 'loan-active-1',
        shopId: shopId,
        customerId: customerId,
        principalCents: 500000,
        balanceCents: 300000,
        status: LoanStatus.active,
        dueDate: now.add(const Duration(days: 30)),
        createdAt: now,
      ),
    );
    await loanDao.createLoan(
      Loan(
        id: 'loan-overdue-1',
        shopId: shopId,
        customerId: customerId,
        principalCents: 300000,
        balanceCents: 200000,
        status: LoanStatus.overdue,
        dueDate: now.subtract(const Duration(days: 5)),
        createdAt: now,
      ),
    );
    await loanDao.createLoan(
      Loan(
        id: 'loan-settled-1',
        shopId: shopId,
        customerId: customerId,
        principalCents: 200000,
        balanceCents: 0,
        status: LoanStatus.settled,
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
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Active (1)'), findsOneWidget);
    expect(find.text('Overdue (1)'), findsOneWidget);
    expect(find.text('Settled (1)'), findsOneWidget);

    await db.close();
  });
}
