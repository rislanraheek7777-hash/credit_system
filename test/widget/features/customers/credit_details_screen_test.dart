import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:credit_system/features/customers/presentation/credit_details_screen.dart';

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
  testWidgets('CreditDetailsScreen displays shop credit details', (
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
        workflowStatus: CreditWorkflowStatus.disbursed,
        dueDate: now.add(const Duration(days: 30)),
        createdAt: now,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CreditDetailsScreen(
          shopId: shopId,
          currentUser: AppUser(
            id: 'user-1',
            shopId: shopId,
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

    expect(find.text('Credit Details'), findsOneWidget);
    expect(find.textContaining('Sunil Perera'), findsOneWidget);
    expect(find.textContaining('Principal: Rs.'), findsOneWidget);
    expect(find.textContaining('Balance: Rs.'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);

    await db.close();
  });

  testWidgets('CreditDetailsScreen shows empty state when no credits exist', (
    WidgetTester tester,
  ) async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    final db = AppDatabase.forTesting(inMemoryExecutor);

    const shopId = 'shop-123';

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

    await tester.pumpWidget(
      MaterialApp(
        home: CreditDetailsScreen(
          shopId: shopId,
          currentUser: AppUser(
            id: 'user-1',
            shopId: shopId,
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

    expect(find.text('No credit details found'), findsOneWidget);

    await db.close();
  });
}

