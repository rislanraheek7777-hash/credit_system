import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';
import 'package:credit_system/features/collateral/presentation/collateral_registration_screen.dart';

/// Hosts the registration screen over a dummy home route.
///
/// The registration screen closes itself with the created item once the
/// registration succeeds, so it needs a route underneath to pop back to. The
/// item it closed with is captured in [poppedItem].
class _HostScreen extends StatefulWidget {
  const _HostScreen({
    required this.database,
    required this.currentUser,
    required this.customerId,
  });

  final AppDatabase database;
  final AppUser currentUser;
  final int customerId;

  @override
  State<_HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends State<_HostScreen> {
  /// The item the registration route closed with, if any.
  CollateralItem? poppedItem;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context)
          .push<CollateralItem>(
            MaterialPageRoute(
              builder: (_) => CollateralRegistrationScreen(
                database: widget.database,
                currentUser: widget.currentUser,
                customerId: widget.customerId,
              ),
            ),
          )
          .then((item) {
            if (!mounted) return;
            setState(() => poppedItem = item);
          });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          poppedItem == null
              ? 'Registration Host'
              : 'Registered ${poppedItem!.itemReferenceId}',
        ),
      ),
    );
  }
}

/// Seeds an in-memory database with a shop, customer and cashier user and
/// returns it ready for the host or a bare registration screen.
Future<AppDatabase> _seedDatabase({
  required String shopId,
  required int customerId,
}) async {
  final db = AppDatabase.forTesting(
    AppDatabaseConnection.openInMemoryConnection(),
  );
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
  return db;
}

AppUser _cashierUser(String shopId) => AppUser(
  id: 'cashier-id',
  shopId: shopId,
  username: 'cashier',
  fullName: 'Counter Cashier',
  role: AppRole.cashier,
  isActive: true,
  sessionVersion: 1,
);

void main() {
  testWidgets('CollateralRegistrationScreen renders with required fields', (
    WidgetTester tester,
  ) async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    final db = AppDatabase.forTesting(inMemoryExecutor);

    const shopId = 'shop-uuid-widget';
    const customerId = 1;

    final now = DateTime.now().toUtc();
    await db
        .into(db.shops)
        .insert(
          ShopEntry(
            id: shopId,
            name: 'Widget Test Shop',
            currencyCode: 'LKR',
            timezone: 'Asia/Colombo',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.customers)
        .insert(
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
    await db
        .into(db.appUsers)
        .insert(
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
          customerId: customerId,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Register Collateral Item'), findsOneWidget);
    expect(find.text('Item Reference ID'), findsOneWidget);
    expect(find.text('Shop ID'), findsNothing);
    expect(find.text('Customer ID'), findsNothing);
    expect(find.text('Credit ID (optional)'), findsNothing);
    expect(find.text('Category'), findsOneWidget);
    for (final value in [
      'gold',
      'electronics',
      'sports',
      'dress',
      'grocery',
      'cosmetic',
      'medicine',
      'valuables',
      'other',
    ]) {
      expect(find.byKey(Key('category_chip_$value')), findsOneWidget);
    }
    expect(find.text('Description (optional)'), findsOneWidget);
    expect(find.text('Condition Grade (optional)'), findsOneWidget);
    expect(find.text('Weight (grams, optional)'), findsOneWidget);
    expect(find.text('Estimated Value (LKR)'), findsOneWidget);
    expect(find.text('Register Item'), findsOneWidget);

    await db.close();
  });

  testWidgets('CollateralRegistrationScreen registers item without a photo', (
    WidgetTester tester,
  ) async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    final db = AppDatabase.forTesting(inMemoryExecutor);

    const shopId = 'shop-uuid-widget-2';
    const customerId = 1;

    final now = DateTime.now().toUtc();
    await db
        .into(db.shops)
        .insert(
          ShopEntry(
            id: shopId,
            name: 'Widget Test Shop 2',
            currencyCode: 'LKR',
            timezone: 'Asia/Colombo',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.customers)
        .insert(
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
    await db
        .into(db.appUsers)
        .insert(
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
        home: _HostScreen(
          database: db,
          currentUser: cashierUser,
          customerId: customerId,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final textFields = find.byType(TextFormField);
    expect(textFields, findsAtLeastNWidgets(5));

    await tester.enterText(textFields.at(0), 'COLL-001');
    await tester.enterText(textFields.at(1), 'Test item');
    await tester.enterText(textFields.at(2), 'Good');
    await tester.enterText(textFields.at(3), '5.5');
    await tester.enterText(textFields.at(4), '1000.00');

    await tester.ensureVisible(find.byKey(const Key('category_chip_gold')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gold'));

    await tester.pumpAndSettle();

    final registerButton = find.byKey(const Key('register_collateral_button'));
    expect(registerButton, findsOneWidget);

    await tester.ensureVisible(registerButton);
    await tester.pumpAndSettle();
    await tester.tap(registerButton);
    await tester.pumpAndSettle();

    // The route closed with the created item as its result; the host shows it.
    expect(find.byType(CollateralRegistrationScreen), findsNothing);
    final host = tester.state<_HostScreenState>(find.byType(_HostScreen));
    expect(host.poppedItem, isNotNull);
    expect(host.poppedItem!.itemReferenceId, equals('COLL-001'));
    expect(find.text('Registered COLL-001'), findsOneWidget);

    final persisted = await db.select(db.collateralItems).get();
    expect(persisted, hasLength(1));
    expect(persisted.single.itemReferenceId, equals('COLL-001'));

    await db.close();
  });

  testWidgets('validation failures keep the screen open and do not pop', (
    WidgetTester tester,
  ) async {
    final db = await _seedDatabase(
      shopId: 'shop-uuid-widget-3',
      customerId: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: _HostScreen(
          database: db,
          currentUser: _cashierUser('shop-uuid-widget-3'),
          customerId: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final registerButton = find.byKey(const Key('register_collateral_button'));

    // Blank estimated value: the validator complains, the route stays open.
    await tester.ensureVisible(registerButton);
    await tester.pumpAndSettle();
    await tester.tap(registerButton);
    await tester.pumpAndSettle();

    expect(find.byType(CollateralRegistrationScreen), findsOneWidget);
    expect(find.text('Estimated value is required'), findsOneWidget);
    expect(
      await db.select(db.collateralItems).get(),
      isEmpty,
    );

    // Valid scalar fields but no category selected: the inline message
    // appears, the route stays open, nothing persists.
    final textFields = find.descendant(
      of: find.byType(CollateralRegistrationScreen),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(textFields.at(0), 'COLL-002');
    await tester.enterText(textFields.at(4), '1000.00');
    await tester.ensureVisible(registerButton);
    await tester.pumpAndSettle();
    await tester.tap(registerButton);
    await tester.pumpAndSettle();

    expect(find.text('Category is required'), findsOneWidget);
    expect(find.byType(CollateralRegistrationScreen), findsOneWidget);
    expect(await db.select(db.collateralItems).get(), isEmpty);

    await db.close();
  });

  testWidgets('a DAO failure shows an inline error and does not pop', (
    WidgetTester tester,
  ) async {
    final db = await _seedDatabase(
      shopId: 'shop-uuid-widget-4',
      customerId: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: _HostScreen(
          database: db,
          currentUser: _cashierUser('shop-uuid-widget-4'),
          customerId: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final textFields = find.descendant(
      of: find.byType(CollateralRegistrationScreen),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(textFields.at(0), 'COLL-DAO-FAIL');
    await tester.enterText(textFields.at(4), '1000.00');
    await tester.ensureVisible(find.byKey(const Key('category_chip_gold')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('category_chip_gold')));
    await tester.pumpAndSettle();

    final registerButton = find.byKey(const Key('register_collateral_button'));
    await tester.ensureVisible(registerButton);
    await tester.pumpAndSettle();

    // Closing the injected database makes the DAO's write throw, which the
    // screen must catch and surface inline instead of popping.
    await db.close();

    await tester.tap(registerButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('Registration failed'), findsOneWidget);
    expect(find.byType(CollateralRegistrationScreen), findsOneWidget);
  });

  testWidgets('on a root route, the pop dismisses the screen and the item persists', (
    WidgetTester tester,
  ) async {
    final db = await _seedDatabase(
      shopId: 'shop-uuid-widget-5',
      customerId: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CollateralRegistrationScreen(
          database: db,
          currentUser: _cashierUser('shop-uuid-widget-5'),
          customerId: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final textFields = find.byType(TextFormField);
    await tester.enterText(textFields.at(0), 'COLL-ROOT-ROUTE');
    await tester.enterText(textFields.at(4), '1000.00');
    await tester.ensureVisible(find.byKey(const Key('category_chip_gold')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('category_chip_gold')));
    await tester.pumpAndSettle();

    final registerButton = find.byKey(const Key('register_collateral_button'));
    await tester.ensureVisible(registerButton);
    await tester.pumpAndSettle();
    await tester.tap(registerButton);
    await tester.pumpAndSettle();

    // Navigator.pop removes the root route like any other route: the screen
    // is dismissed and the item persists exactly once.
    expect(find.byType(CollateralRegistrationScreen), findsNothing);
    final persisted = await db.select(db.collateralItems).get();
    expect(persisted, hasLength(1));
    expect(persisted.single.itemReferenceId, equals('COLL-ROOT-ROUTE'));

    await db.close();
  });
}
