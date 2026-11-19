import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/customer_dao.dart';
import 'package:credit_system/features/customers/data/daos/credit_dao.dart';
import 'package:credit_system/features/customers/domain/models/customer.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:credit_system/features/shop/domain/models/shop_profile.dart';
import 'package:credit_system/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late String shopId;
  late CustomerDao customerDao;
  late CreditDao creditDao;
  late int firstCustomerId;
  var dbClosed = false;

  final now = DateTime.utc(2026, 11, 5, 9);

  Future<int> addCustomer(String name) {
    return customerDao.createCustomer(
      Customer(
        id: 0,
        shopId: shopId,
        fullName: name,
        nic: '',
        phone: '0770000000',
        address: '',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> addUser(String id) {
    return db.userDao.createUser(
      AppUser(
        id: id,
        shopId: shopId,
        username: id,
        fullName: id,
        role: AppRole.cashier,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> addCredit({
    required String id,
    required int customerId,
    required int principalCents,
    CreditStatus status = CreditStatus.active,
    CreditWorkflowStatus workflowStatus = CreditWorkflowStatus.disbursed,
  }) {
    return creditDao.createCredit(
      Credit(
        id: id,
        shopId: shopId,
        customerId: customerId,
        principalCents: principalCents,
        balanceCents: principalCents,
        status: status,
        workflowStatus: workflowStatus,
        dueDate: now.add(const Duration(days: 30)),
        createdAt: now,
      ),
    );
  }

  Future<void> closeDb() async {
    if (dbClosed) return;
    dbClosed = true;
    await db.close();
  }

  setUp(() async {
    dbClosed = false;
    shopId = 'shop-dashboard-widget';
    db = AppDatabase.forTesting(
      AppDatabaseConnection.openInMemoryConnection(
        closeStreamsSynchronously: true,
      ),
    );
    customerDao = db.customerDao;
    creditDao = db.creditDao;

    await db.shopDao.createShop(ShopProfile(id: shopId, name: 'Dashboard Shop'));
    await addUser('owner');
    final firstCustomer = await addCustomer('Customer One');
    firstCustomerId = firstCustomer;
    await addCustomer('Customer Two');
    await addCredit(
      id: 'credit-one',
      customerId: firstCustomer,
      principalCents: 50000,
    );
  });

  tearDown(() async {
    await closeDb();
  });

  testWidgets(
      'dashboard cards and active credits list update when credits are added, including pending disbursement',
      (tester) async {
    final owner = AppUser(
      id: 'owner',
      shopId: shopId,
      username: 'owner',
      fullName: 'Owner',
      role: AppRole.shopOwner,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MainApp(shopId: shopId, currentUser: owner, database: db),
      ),
    );

    await _pumpUntilCardValue(tester, 'metric-total-customers', '2');
    await _pumpUntilCardValue(tester, 'metric-total-staff', '1');
    await _pumpUntilCardValue(tester, 'metric-total-credits', '1');
    await _pumpUntilCardValue(tester, 'metric-active-credit', 'Rs. 500.00');
    await _pumpUntilCardValue(tester, 'metric-overdue', 'Rs. 0.00');
    await _pumpUntilCardValue(tester, 'metric-collected', 'Rs. 0.00');
    await _pumpUntilText(tester, 'No active credits', present: false);
    await _pumpUntilText(tester, 'Customer One', present: true);

    await addCustomer('Customer Three');
    await _pumpUntilCardValue(tester, 'metric-total-customers', '3');

    await addUser('second-staff');
    await _pumpUntilCardValue(tester, 'metric-total-staff', '2');

    await addCredit(
      id: 'credit-two',
      customerId: firstCustomerId,
      principalCents: 25000,
    );
    await _pumpUntilCardValue(tester, 'metric-total-credits', '2');
    await _pumpUntilCardValue(tester, 'metric-active-credit', 'Rs. 750.00');
    await _pumpUntilCardValue(tester, 'metric-overdue', 'Rs. 0.00');

    await addCredit(
      id: 'credit-pending',
      customerId: firstCustomerId,
      principalCents: 12000,
      workflowStatus: CreditWorkflowStatus.pendingDisbursement,
    );
    await _pumpUntilCardValue(tester, 'metric-total-credits', '3');
    await _pumpUntilCardValue(tester, 'metric-active-credit', 'Rs. 870.00');
    await _pumpUntilCardValue(tester, 'metric-overdue', 'Rs. 0.00');
    await _pumpUntilText(tester, 'Principal: Rs. 120.00', present: true);
    await _pumpUntilText(tester, 'Balance: Rs. 120.00', present: true);
  });
}

Future<void> _pumpUntilCardValue(
  WidgetTester tester,
  String cardKey,
  String value,
) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    final valueFinder = find.descendant(
      of: find.byKey(ValueKey(cardKey)),
      matching: find.text(value),
    );
    if (valueFinder.evaluate().isNotEmpty) {
      expect(valueFinder, findsOneWidget);
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('Dashboard card "$cardKey" never displayed "$value".');
}

Future<void> _pumpUntilText(
  WidgetTester tester,
  String text, {
  required bool present,
}) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    final finder = find.text(text);
    final isPresent = finder.evaluate().isNotEmpty;
    if (isPresent == present) {
      if (present) {
        expect(finder, findsWidgets);
      } else {
        expect(finder, findsNothing);
      }
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail(
    present
        ? 'Text "$text" never appeared.'
        : 'Text "$text" never disappeared.',
  );
}

