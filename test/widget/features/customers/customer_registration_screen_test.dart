import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/customers/domain/models/customer.dart';
import 'package:credit_system/features/customers/presentation/customer_registration_screen.dart';

import '../../../support/customers_test_support.dart';

/// A dummy host route that pushes the registration screen over itself and
/// reports the result the route closed with.
///
/// A successful registration now closes the registration route, so the screen
/// needs a route to return to — a root route has nothing to pop back to.
class _RegistrationHost extends StatefulWidget {
  const _RegistrationHost({
    required this.database,
    required this.currentUser,
    required this.onResult,
  });

  final AppDatabase database;
  final AppUser currentUser;
  final ValueChanged<Customer?> onResult;

  @override
  State<_RegistrationHost> createState() => _RegistrationHostState();
}

class _RegistrationHostState extends State<_RegistrationHost> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final result = await Navigator.of(context).push<Customer>(
              MaterialPageRoute(
                builder: (_) => CustomerRegistrationScreen(
                  database: widget.database,
                  currentUser: widget.currentUser,
                ),
              ),
            );
            widget.onResult(result);
          },
          child: const Text('Open registration'),
        ),
      ),
    );
  }
}

void main() {
  late AppDatabase db;

  // The shared-phone path writes a sync-queue event, and a sync-queue entry
  // validates the shop id as a canonical UUID.
  const shopId = '3f8a1c2e-5b6d-4e7f-9a0b-1c2d3e4f5a6b';

  final staffUser = AppUser(
    id: testUserId,
    shopId: shopId,
    username: 'counter.staff',
    fullName: 'Counter Staff',
    role: AppRole.cashier,
  );

  setUp(() async {
    db = await openTestDatabase();
    await seedShopAndCustomer(db, shopId: shopId);
  });

  tearDown(() async {
    await db.close();
  });

  /// Pushes the registration screen over the dummy host route.
  Future<void> openRegistration(
    WidgetTester tester, {
    required ValueChanged<Customer?> onResult,
  }) async {
    useLargeSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: _RegistrationHost(
          database: db,
          currentUser: staffUser,
          onResult: onResult,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open registration'));
    await tester.pumpAndSettle();
  }

  /// Fills the registration form with a valid, unshared customer.
  Future<void> fillForm(
    WidgetTester tester, {
    String fullName = 'Nimal Perera',
    String nic = '199012345678',
    String phone = '0779876543',
  }) async {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Full Name'),
      fullName,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'NIC Number'),
      nic,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Phone Number'),
      phone,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('CustomerRegistrationScreen renders with required fields',
      (WidgetTester tester) async {
    await openRegistration(tester, onResult: (_) {});

    // Title and field labels are visible
    expect(find.text('Register New Customer'), findsOneWidget);
    // Customer ID and Shop ID are now auto-derived; not shown.
    expect(find.text('Full Name'), findsOneWidget);
    expect(find.text('NIC Number'), findsOneWidget);
    expect(find.text('Phone Number'), findsOneWidget);
    expect(find.text('Residential Address'), findsOneWidget);

    // Register button is present
    expect(find.byKey(const Key('register_customer_button')), findsOneWidget);
  });

  testWidgets('Shared-phone confirmation blocks registration until confirmed',
      (WidgetTester tester) async {
    await openRegistration(tester, onResult: (_) {});

    // Register button is present initially
    expect(find.byKey(const Key('register_customer_button')), findsOneWidget);

    // Confirm shared phone button is NOT visible initially
    expect(find.byKey(const Key('confirm_shared_phone_button')),
        findsNothing);
  });

  testWidgets(
      'a successful registration closes the route with the created customer',
      (WidgetTester tester) async {
    Customer? result;
    var returned = false;

    await openRegistration(tester, onResult: (customer) {
      result = customer;
      returned = true;
    });

    await fillForm(tester);

    await tester.ensureVisible(find.byKey(const Key('register_customer_button')));
    await tester.tap(find.byKey(const Key('register_customer_button')));

    // The route closed with the created customer as its result.
    await pumpUntil(
      tester,
      () => returned && find.byType(CustomerRegistrationScreen).evaluate().isEmpty,
    );
    expect(result, isNotNull);
    expect(result!.fullName, equals('Nimal Perera'));
    expect(result!.id, greaterThan(0));

    // The registration screen is gone, and so is its inline success banner:
    // the confirmation belongs to the Customers screen.
    expect(find.byType(CustomerRegistrationScreen), findsNothing);
    expect(find.textContaining('registered successfully'), findsNothing);
  });

  testWidgets(
      'a failed registration keeps the screen open and returns no result',
      (WidgetTester tester) async {
    Customer? result;
    var returned = false;

    await openRegistration(tester, onResult: (customer) {
      result = customer;
      returned = true;
    });

    // A duplicate NIC of the seeded customer is rejected by the service.
    await fillForm(tester, nic: '851234567V', phone: '0779876543');

    await tester.ensureVisible(find.byKey(const Key('register_customer_button')));
    await tester.tap(find.byKey(const Key('register_customer_button')));
    await tester.pumpAndSettle();

    // The existing profile is surfaced instead of a duplicate being created.
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Existing Customer Profile'), findsOneWidget);

    // The screen stays open and the route closes with no result.
    expect(find.byType(CustomerRegistrationScreen), findsOneWidget);
    expect(returned, isFalse);
    expect(result, isNull);
    expect(find.textContaining('registered successfully'), findsNothing);
  });

  testWidgets(
      'a confirmed shared phone closes the route with the created customer',
      (WidgetTester tester) async {
    Customer? result;
    var returned = false;

    await openRegistration(tester, onResult: (customer) {
      result = customer;
      returned = true;
    });

    // The phone of the seeded customer is shared; the service asks for an
    // explicit confirmation before registering a distinct individual.
    await fillForm(tester, phone: '0771234567');

    await tester.ensureVisible(find.byKey(const Key('register_customer_button')));
    await tester.tap(find.byKey(const Key('register_customer_button')));
    await tester.pumpAndSettle();

    // The warning banner asks for confirmation, and nothing was registered.
    expect(find.byKey(const Key('confirm_shared_phone_button')), findsOneWidget);
    expect(returned, isFalse);

    await tester.tap(find.byKey(const Key('confirm_shared_phone_button')));

    // The confirmed registration closes the route with the created customer.
    await pumpUntil(
      tester,
      () => returned && find.byType(CustomerRegistrationScreen).evaluate().isEmpty,
    );
    expect(result, isNotNull);
    expect(result!.fullName, equals('Nimal Perera'));
    expect(find.byType(CustomerRegistrationScreen), findsNothing);
    expect(find.textContaining('registered successfully'), findsNothing);
  });
}
