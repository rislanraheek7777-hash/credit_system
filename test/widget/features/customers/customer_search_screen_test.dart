import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/features/customers/presentation/customer_search_screen.dart';

void main() {
  testWidgets('CustomerSearchScreen renders search form', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CustomerSearchScreen(shopId: 'shop-123'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Search Customers'), findsOneWidget);
    expect(find.text('Search by NIC, phone, or name'), findsOneWidget);
    expect(find.text('Enter at least 2 characters'), findsOneWidget);
  });

  testWidgets('Shared-phone confirmation absent initially', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CustomerSearchScreen(shopId: 'shop-123'),
      ),
    );
    await tester.pumpAndSettle();

    // The confirmation button should not be visible initially
    expect(
      find.text('Confirm separate individual sharing phone number'),
      findsNothing,
    );
  });
}
