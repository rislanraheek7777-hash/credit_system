import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/presentation/payment_screen.dart';

import '../../../support/customers_test_support.dart';

const String shopId = 'pay-shop-1111-1111-1111-111111111101';
const int customerId = 1;
const String cashierId = 'pay-cash-1111-1111-1111-111111111102';
const String inactiveId = 'pay-inactive-1111-1111-1111-111111111103';
const String creditId = 'pay-credit-1111-1111-1111-111111111104';

/// Seeds a shop, borrower, an active cashier, a deactivated actor and one
/// disbursed active credit with a positive balance (eligible for payment).
Future<void> seedData(AppDatabase db) async {
  final now = DateTime.now().toUtc();
  await db.into(db.shops).insert(
    ShopEntry(
      id: shopId,
      name: 'Payment Test Shop',
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
      fullName: 'Payment Customer',
      nic: '851234567V',
      phone: '0771234567',
      address: '1 Test St',
      createdAt: now,
      updatedAt: now,
    ),
  );
  for (final user in [
    (id: cashierId, username: 'pay-cash', role: 'cashier', isActive: true),
    (id: inactiveId, username: 'pay-inactive', role: 'cashier', isActive: false),
  ]) {
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: user.id,
        shopId: shopId,
        username: user.username,
        fullName: user.username,
        role: user.role,
        isActive: user.isActive,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
  await db.into(db.credits).insert(
    CreditsCompanion.insert(
      id: creditId,
      shopId: shopId,
      customerId: customerId,
      principalCents: 500000,
      balanceCents: 300000,
      status: const Value('active'),
      workflowStatus: const Value('disbursed'),
      termPresetDays: const Value(30),
      dueDate: DateTime.utc(2026, 11, 20),
      disbursedAt: Value(DateTime.utc(2026, 10, 21)),
      disbursedByUserId: Value(cashierId),
      createdAt: now,
      correctionPending: const Value(false),
    ),
  );
}

AppUser cashier({bool isActive = true}) => AppUser(
      id: isActive ? cashierId : inactiveId,
      shopId: shopId,
      username: isActive ? 'pay-cash' : 'pay-inactive',
      fullName: isActive ? 'Payment Cashier' : 'Inactive Cashier',
      role: AppRole.cashier,
      isActive: isActive,
    );

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(AppDatabaseConnection.openInMemoryConnection());
    await seedData(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpScreen(WidgetTester tester, AppUser actor) async {
    useLargeSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: PaymentScreen(
          shopId: shopId,
          creditId: creditId,
          currentUser: actor,
          database: db,
        ),
      ),
    );
    await pumpUntil(
      tester,
      () => find.textContaining('Outstanding Balance').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an active cashier without requestCorrections sees an enabled '
      'Settle adjustment button', (WidgetTester tester) async {
    final actor = cashier();
    expect(actor.effectivePermissions.contains(AppPermission.requestCorrections),
        isFalse);

    await pumpScreen(tester, actor);

    final button = find.byKey(const Key('request_adjustment_button'));
    expect(button, findsOneWidget);
    expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
  });

  testWidgets('a deactivated actor is not offered the Settle adjustment '
      'button', (WidgetTester tester) async {
    await pumpScreen(tester, cashier(isActive: false));

    expect(find.byKey(const Key('request_adjustment_button')), findsNothing);
  });
}
