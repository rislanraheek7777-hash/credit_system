import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:credit_system/features/customers/presentation/customer_profile_screen.dart';
import 'package:credit_system/features/customers/presentation/payment_screen.dart';

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
  Future<AppDatabase> seedTwoCredits({String role = 'manager'}) async {
    final db = AppDatabase.forTesting(
      AppDatabaseConnection.openInMemoryConnection(),
    );
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
        role: role,
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
    return db;
  }

  Widget profileFor(AppDatabase db, String role) {
    return MaterialApp(
      home: CustomerProfileScreen(
        shopId: 'shop-123',
        customerId: 1,
        database: db,
        currentUser: AppUser(
          id: 'user-1',
          shopId: 'shop-123',
          username: 'testuser',
          fullName: 'Test User',
          role: AppRole.values.byName(role),
          isActive: true,
        ),
      ),
    );
  }

  testWidgets('tapping an eligible credit card opens payment recording for that card', (
    WidgetTester tester,
  ) async {
    final db = await seedTwoCredits();

    await tester.pumpWidget(profileFor(db, 'manager'));
    await tester.pumpAndSettle();

    expect(find.text('Active (1)'), findsOneWidget);
    expect(find.text('Overdue (1)'), findsOneWidget);

    // Tap the overdue card - payment recording opens for credit-2, not credit-1.
    await tester.ensureVisible(find.text('Credit credit-2...').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Credit credit-2...').first);
    await tester.pumpAndSettle();

    expect(find.byType(PaymentScreen), findsOneWidget);
    expect(
      tester.widget<PaymentScreen>(find.byType(PaymentScreen)).creditId,
      'credit-2',
    );

    await db.close();
  });

  testWidgets('tapping the active card opens payment recording for that card', (
    WidgetTester tester,
  ) async {
    final db = await seedTwoCredits();

    await tester.pumpWidget(profileFor(db, 'manager'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Credit credit-1...').first);
    await tester.pumpAndSettle();

    expect(find.byType(PaymentScreen), findsOneWidget);
    expect(
      tester.widget<PaymentScreen>(find.byType(PaymentScreen)).creditId,
      'credit-1',
    );

    await db.close();
  });

  testWidgets('a recordPayments-less actor is told why the tile is inert', (
    WidgetTester tester,
  ) async {
    final db = await seedTwoCredits(role: 'custom');

    await tester.pumpWidget(profileFor(db, 'custom'));
    await tester.pumpAndSettle();

    // Custom role holds no permissions; the tile gives feedback rather than
    // navigating or dead-ending silently.
    await tester.tap(find.text('Credit credit-1...').first);
    await tester.pumpAndSettle();

    expect(find.byType(PaymentScreen), findsNothing);
    expect(
      find.text('You do not have permission to record payments.'),
      findsOneWidget,
    );

    await db.close();
  });
}
