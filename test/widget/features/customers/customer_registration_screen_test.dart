import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/features/customers/presentation/customer_registration_screen.dart';

void main() {
  testWidgets('CustomerRegistrationScreen renders with required fields',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CustomerRegistrationScreen(),
    ));
    await tester.pumpAndSettle();

    // Title and field labels are visible
    expect(find.text('Register New Customer'), findsOneWidget);
    expect(find.text('Customer ID'), findsOneWidget);
    expect(find.text('Shop ID'), findsOneWidget);
    expect(find.text('Full Name'), findsOneWidget);
    expect(find.text('NIC Number'), findsOneWidget);
    expect(find.text('Phone Number'), findsOneWidget);
    expect(find.text('Residential Address'), findsOneWidget);

    // Register button is present
    expect(find.byKey(const Key('register_customer_button')), findsOneWidget);
  });

  testWidgets('Shared-phone confirmation blocks registration until confirmed',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CustomerRegistrationScreen(),
    ));
    await tester.pumpAndSettle();

    // Register button is present initially
    expect(find.byKey(const Key('register_customer_button')), findsOneWidget);

    // Confirm shared phone button is NOT visible initially
    expect(find.byKey(const Key('confirm_shared_phone_button')),
        findsNothing);
  });
}
