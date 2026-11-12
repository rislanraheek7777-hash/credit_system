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
  }) {
    return creditDao.createCredit(
      Credit(
        id: id,
        shopId: shopId,
        customerId: customerId,
        principalCents: principalCents,
        balanceCents: principalCents,
        status: CreditStatus.active,
        workflowStatus: CreditWorkflowStatus.disbursed,
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

  testWidgets('dashboard cards update when customers, staff, and credits are added',
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
    await _pumpUntilCardValue(tester, 'metric-active-credit', r'$500.00');
    await _pumpUntilCardValue(tester, 'metric-outstanding', r'$500.00');
    await _pumpUntilCardValue(tester, 'metric-collected', r'$0.00');
    await _pumpUntilCardValue(tester, 'metric-ratio', '0.00');

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
    await _pumpUntilCardValue(tester, 'metric-active-credit', r'$750.00');
    await _pumpUntilCardValue(tester, 'metric-outstanding', r'$750.00');
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

