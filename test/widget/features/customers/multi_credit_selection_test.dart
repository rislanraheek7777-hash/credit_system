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
  testWidgets('Multi-credit selection dialog appears for multiple credits', (
    WidgetTester tester,
  ) async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    final db = AppDatabase.forTesting(inMemoryExecutor);

    const shopId = 'shop-123';
    const customerId = 1;

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
        // Story 4.1: a credit is only payment-actionable once cash has been
        // disbursed, so these fixture credits are explicitly disbursed.
        workflowStatus: CreditWorkflowStatus.disbursed,
        dueDate: now.add(const Duration(days: 30)),
        createdAt: now,
      ),
    );
    await insertCredit(db,
      Credit(
        id: 'credit-2',
        shopId: shopId,
        customerId: customerId,
        principalCents: 300000,
        balanceCents: 150000,
        status: CreditStatus.overdue,
        workflowStatus: CreditWorkflowStatus.disbursed,
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

    // Tap on the active credit - should open selection dialog since there are
    // multiple actionable credits
    await tester.tap(find.text('Credit credit-1...').first);
    await tester.pumpAndSettle();

    // Selection dialog should appear
    expect(find.text('Select Credit'), findsOneWidget);
    expect(find.text('Credit credit-1...'), findsAtLeast(1));
    expect(find.text('Credit credit-2...'), findsAtLeast(1));

    // Tap cancel - should dismiss dialog without action
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Select Credit'), findsNothing);

    await db.close();
  });

  testWidgets('Single credit does not show selection dialog', (
    WidgetTester tester,
  ) async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    final db = AppDatabase.forTesting(inMemoryExecutor);

    const shopId = 'shop-123';
    const customerId = 1;

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
        // Story 4.1: only disbursed credits are payment-actionable.
        workflowStatus: CreditWorkflowStatus.disbursed,
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

    // Tap on the single credit - no selection dialog should appear
    await tester.tap(find.text('Credit credit-1...'));
    await tester.pumpAndSettle();

    // Selection dialog should NOT appear
    expect(find.text('Select Credit'), findsNothing);

    await db.close();
  });
}

