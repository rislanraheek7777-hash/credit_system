import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/customers/presentation/customer_profile_screen.dart';
import 'package:credit_system/features/customers/presentation/customer_registration_screen.dart';
import 'package:credit_system/features/customers/presentation/customer_search_screen.dart';

import '../../../support/customers_test_support.dart';

void main() {
  late AppDatabase db;

  // The shared-phone path writes a sync-queue event, and a sync-queue entry
  // validates the shop id as a canonical UUID.
  const shopId = '3f8a1c2e-5b6d-4e7f-9a0b-1c2d3e4f5a6b';

  setUp(() async {
    db = AppDatabase.forTesting(AppDatabaseConnection.openInMemoryConnection());
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
  });

  tearDown(() async {
    await db.close();
  });

  /// Seeds the borrower whose phone number the new customer shares.
  Future<void> seedExistingCustomer() async {
    final now = DateTime.now().toUtc();
    await db.into(db.customers).insert(
      CustomerEntry(
        id: 456,
        shopId: shopId,
        fullName: 'Sunil Perera',
        nic: '851234567V',
        phone: '0771234567',
        address: '1 Main St, Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Widget customersScreen({AppDatabase? database, AppRole role = AppRole.manager}) {
    return MaterialApp(
      home: CustomerSearchScreen(
        shopId: shopId,
        currentUser: AppUser(
          id: 'user-1',
          shopId: shopId,
          username: 'testuser',
          fullName: 'Test User',
          role: role,
          isActive: true,
        ),
        database: database ?? db,
      ),
    );
  }

  /// Opens the registration form from the "Add Customer" FAB.
  Future<void> openRegistrationForm(WidgetTester tester) async {
    await tester.tap(find.byType(FloatingActionButton));
    await pumpUntil(
      tester,
      () => find.byType(CustomerRegistrationScreen).evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
  }

  /// Fills the registration form with a valid customer.
  Future<void> fillFormFields(
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

  /// Fills the registration form with a valid customer and submits it.
  Future<void> fillForm(
    WidgetTester tester, {
    String fullName = 'Nimal Perera',
    String nic = '199012345678',
    String phone = '0779876543',
  }) async {
    await fillFormFields(
      tester,
      fullName: fullName,
      nic: nic,
      phone: phone,
    );

    await tester.ensureVisible(find.byKey(const Key('register_customer_button')));
    await tester.tap(find.byKey(const Key('register_customer_button')));
  }

  testWidgets('CustomerSearchScreen renders search form', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(customersScreen());
    await tester.pumpAndSettle();

    expect(find.text('Search Customers'), findsOneWidget);
    expect(find.text('Search by NIC, phone, or name'), findsOneWidget);
    expect(find.text('Enter at least 2 characters'), findsOneWidget);
  });

  testWidgets('Shared-phone confirmation absent initially', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(customersScreen());
    await tester.pumpAndSettle();

    // The confirmation button should not be visible initially
    expect(
      find.text('Confirm separate individual sharing phone number'),
      findsNothing,
    );
  });

  testWidgets('registering a customer returns to the Customers screen and is '
      'confirmed with a SnackBar', (WidgetTester tester) async {
    await tester.pumpWidget(customersScreen());
    await tester.pumpAndSettle();

    await openRegistrationForm(tester);
    await fillForm(tester);

    // The registration form closes and the Customers screen is shown again.
    await pumpUntil(
      tester,
      () => find.byType(CustomerRegistrationScreen).evaluate().isEmpty,
    );
    expect(find.byType(CustomerSearchScreen), findsOneWidget);
    expect(find.text('Register New Customer'), findsNothing);

    // The list reloaded from the database and contains the new customer.
    await pumpUntil(tester, () => find.text('Nimal Perera').evaluate().isNotEmpty);

    // The confirmation is a SnackBar naming the customer and its id.
    await pumpUntil(tester,
        () => find.textContaining('registered successfully').evaluate().isNotEmpty);

    final created = (await db.select(db.customers).get())
        .firstWhere((customer) => customer.fullName == 'Nimal Perera');
    expect(
      find.text(
        'Customer "Nimal Perera" registered successfully '
        '(ID: ${created.id}).',
      ),
      findsOneWidget,
    );

    // The confirmation stays up for four seconds, matching the
    // credit-origination confirmation on the customer profile.
    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.duration, const Duration(seconds: 4));
  });

  testWidgets('an active search filter is cleared so the new customer is '
      'visible', (WidgetTester tester) async {
    await seedExistingCustomer();
    await tester.pumpWidget(customersScreen());
    await tester.pumpAndSettle();

    // A filter of at least two characters narrows the list down.
    await tester.enterText(find.byType(TextField), 'Su');
    await pumpUntil(tester, () => find.text('Sunil Perera').evaluate().isNotEmpty);
    expect(find.text('Nimal Perera'), findsNothing);

    await openRegistrationForm(tester);
    await fillForm(tester);

    // The registration form closes and the Customers screen is shown again.
    await pumpUntil(
      tester,
      () => find.byType(CustomerRegistrationScreen).evaluate().isEmpty,
    );

    // The filter is cleared, so the full shop list is shown and the newly
    // registered customer is visible.
    await pumpUntil(tester, () => find.text('Nimal Perera').evaluate().isNotEmpty);
    expect(find.text('Sunil Perera'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty);
  });

  testWidgets('a validation error keeps the form open and shows no '
      'confirmation SnackBar', (WidgetTester tester) async {
    await tester.pumpWidget(customersScreen());
    await tester.pumpAndSettle();

    await openRegistrationForm(tester);

    // The form's own phone validator only requires a non-empty phone, so an
    // invalid phone format passes the form and reaches the service, which
    // rejects it with a CustomerValidationException before any DAO call.
    await fillForm(tester, phone: 'abc');

    await pumpUntil(tester,
        () => find.textContaining('Invalid phone number').evaluate().isNotEmpty);

    // The registration form is still open, showing the reason inline.
    expect(find.byType(CustomerRegistrationScreen), findsOneWidget);
    expect(find.textContaining('Invalid phone number'), findsOneWidget);

    // Nothing is confirmed, and nothing was written.
    expect(find.textContaining('registered successfully'), findsNothing);
    expect(await db.select(db.customers).get(), isEmpty);
  });

  testWidgets('an unexpected failure keeps the form open and shows no '
      'confirmation SnackBar', (WidgetTester tester) async {
    // A dedicated database instance, so the shared `db` fixture is untouched
    // and the shared tearDown cannot close this one. Drift's close() is
    // idempotent -- verified empirically -- so the double close below (once
    // to provoke the failure, once in the tear-down) is safe.
    final tempDir =
        Directory.systemTemp.createTempSync('customer_unexpected_error_');
    final path = p.join(tempDir.path, 'unexpected_error.sqlite');

    AppDatabase? failingDb;
    addTearDown(() async {
      await failingDb?.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    // The file-backed executor is built directly rather than through
    // AppDatabaseConnection.openSandboxedConnection: that factory resolves
    // lazily through real file I/O, which never completes inside a widget
    // test's fake-async zone.
    failingDb = AppDatabase.forTesting(
      NativeDatabase(
        File(path),
        setup: (database) => database.execute('PRAGMA foreign_keys = ON;'),
      ),
    );

    final now = DateTime.now().toUtc();
    await failingDb.into(failingDb.shops).insert(
      ShopEntry(
        id: shopId,
        name: 'Test Shop',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(customersScreen(database: failingDb));
    await tester.pumpAndSettle();

    await openRegistrationForm(tester);
    await fillFormFields(tester);

    // Close the database underneath the registration screen: its DAO call now
    // throws an error that is none of the service's documented exceptions,
    // so the screen's generic catch handles it.
    await failingDb.close();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('register_customer_button')));
    await pumpUntil(tester,
        () => find.textContaining('Registration failed:').evaluate().isNotEmpty);

    // The registration form is still open, showing the generic failure inline.
    expect(find.byType(CustomerRegistrationScreen), findsOneWidget);
    expect(find.textContaining('Registration failed:'), findsOneWidget);

    // Nothing is confirmed.
    expect(find.textContaining('registered successfully'), findsNothing);

    // No customer row was created: the file the failed registration would
    // have written to is read directly, so the assertion does not need a
    // second database instance.
    final rawDb = sqlite3.open(path);
    try {
      final rows = rawDb.select('SELECT COUNT(*) AS rows FROM customers');
      expect(rows.first['rows'], equals(0));
    } finally {
      rawDb.close();
    }
  });

  testWidgets('backing out of the registration form shows no confirmation '
      'SnackBar and keeps the active search filter', (
    WidgetTester tester,
  ) async {
    await seedExistingCustomer();
    await tester.pumpWidget(customersScreen());
    await tester.pumpAndSettle();

    // A filter of at least two characters is active before the form is opened.
    await tester.enterText(find.byType(TextField), 'Su');
    await pumpUntil(tester, () => find.text('Sunil Perera').evaluate().isNotEmpty);

    await openRegistrationForm(tester);

    // Back out without submitting anything.
    Navigator.of(tester.element(find.byType(CustomerRegistrationScreen))).pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(CustomerSearchScreen), findsOneWidget);
    expect(find.textContaining('registered successfully'), findsNothing);
    expect(await db.select(db.customers).get(), hasLength(1));

    // Nothing was registered, so the operator's search filter survives.
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text,
        equals('Su'));
    expect(find.text('Sunil Perera'), findsOneWidget);
  });

  testWidgets('a confirmed shared phone registration closes the form and '
      'shows the same confirmation', (WidgetTester tester) async {
    await seedExistingCustomer();
    await tester.pumpWidget(customersScreen());
    await tester.pumpAndSettle();

    await openRegistrationForm(tester);

    // The phone of the seeded customer is shared; the service asks for an
    // explicit confirmation before registering a distinct individual.
    await fillForm(tester, phone: '0771234567');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirm_shared_phone_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm_shared_phone_button')));

    await pumpUntil(
      tester,
      () => find.byType(CustomerRegistrationScreen).evaluate().isEmpty,
    );
    await pumpUntil(tester,
        () => find.textContaining('registered successfully').evaluate().isNotEmpty);

    final created = (await db.select(db.customers).get())
        .firstWhere((customer) => customer.fullName == 'Nimal Perera');
    expect(
      find.text(
        'Customer "Nimal Perera" registered successfully '
        '(ID: ${created.id}).',
      ),
      findsOneWidget,
    );
  });

  testWidgets('deleting the customer from the profile refreshes the list in place', (
    WidgetTester tester,
  ) async {
    await seedExistingCustomer();
    await tester.pumpWidget(customersScreen(role: AppRole.shopOwner));
    await tester.pumpAndSettle();
    expect(find.text('Sunil Perera'), findsOneWidget);

    // Open the profile from the search result.
    await tester.tap(find.text('Sunil Perera'));
    await pumpUntil(
      tester,
      () => find.byType(CustomerProfileScreen).evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();

    // Confirm the soft delete in the profile.
    await tester.tap(find.byKey(const Key('delete_customer_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete_customer_confirm_button')));
    await pumpUntil(
      tester,
      () => find.byType(CustomerProfileScreen).evaluate().isEmpty,
    );
    await tester.pumpAndSettle();

    // The list reloaded in place: the deleted customer no longer appears,
    // with no manual refresh.
    expect(find.byType(CustomerSearchScreen), findsOneWidget);
    expect(find.text('Sunil Perera'), findsNothing);
  });
}
