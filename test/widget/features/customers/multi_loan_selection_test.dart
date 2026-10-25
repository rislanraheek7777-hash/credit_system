import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/customers/domain/models/loan.dart';
import 'package:credit_system/features/customers/presentation/customer_profile_screen.dart';

Future<void> insertLoan(AppDatabase db, Loan loan) async {
  await db.into(db.loans).insert(LoansCompanion(
    id: Value(loan.id),
    shopId: Value(loan.shopId),
    customerId: Value(loan.customerId),
    principalCents: Value(loan.principalCents),
    balanceCents: Value(loan.balanceCents),
    status: Value(loan.status.value),
    workflowStatus: Value(loan.workflowStatus.value),
    termPresetDays: Value(loan.termPresetDays),
    customDueDate: Value(loan.customDueDate),
    disbursedAt: Value(loan.disbursedAt),
    disbursedByUserId: Value(loan.disbursedByUserId),
    cancelledAt: Value(loan.cancelledAt),
    cancellationReason: Value(loan.cancellationReason),
    dueDate: Value(loan.dueDate),
    createdAt: Value(loan.createdAt),
    settledAt: Value(loan.settledAt),
  ));
}

void main() {
  testWidgets('Multi-loan selection dialog appears for multiple loans', (
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
    await insertLoan(db,
      Loan(
        id: 'loan-1',
        shopId: shopId,
        customerId: customerId,
        principalCents: 500000,
        balanceCents: 300000,
        status: LoanStatus.active,
        // Story 4.1: a loan is only payment-actionable once cash has been
        // disbursed, so these fixture loans are explicitly disbursed.
        workflowStatus: LoanWorkflowStatus.disbursed,
        dueDate: now.add(const Duration(days: 30)),
        createdAt: now,
      ),
    );
    await insertLoan(db,
      Loan(
        id: 'loan-2',
        shopId: shopId,
        customerId: customerId,
        principalCents: 300000,
        balanceCents: 150000,
        status: LoanStatus.overdue,
        workflowStatus: LoanWorkflowStatus.disbursed,
        dueDate: now.subtract(const Duration(days: 5)),
        createdAt: now,
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

    // Tap on the active loan - should open selection dialog since there are
    // multiple actionable loans
    await tester.tap(find.text('Loan loan-1...').first);
    await tester.pumpAndSettle();

    // Selection dialog should appear
    expect(find.text('Select Loan'), findsOneWidget);
    expect(find.text('Loan loan-1...'), findsAtLeast(1));
    expect(find.text('Loan loan-2...'), findsAtLeast(1));

    // Tap cancel - should dismiss dialog without action
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Select Loan'), findsNothing);

    await db.close();
  });

  testWidgets('Single loan does not show selection dialog', (
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
    await insertLoan(db,
      Loan(
        id: 'loan-1',
        shopId: shopId,
        customerId: customerId,
        principalCents: 500000,
        balanceCents: 300000,
        status: LoanStatus.active,
        // Story 4.1: only disbursed loans are payment-actionable.
        workflowStatus: LoanWorkflowStatus.disbursed,
        dueDate: now.add(const Duration(days: 30)),
        createdAt: now,
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

    // Tap on the single loan - no selection dialog should appear
    await tester.tap(find.text('Loan loan-1...'));
    await tester.pumpAndSettle();

    // Selection dialog should NOT appear
    expect(find.text('Select Loan'), findsNothing);

    await db.close();
  });
}
