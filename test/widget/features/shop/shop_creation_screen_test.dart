import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/features/shop/presentation/shop_creation_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);
  });

  tearDown(() async {
    await db.close();
  });

  group('ShopCreationScreen Widget Tests (Story 1.6)', () {
    testWidgets('renders shop creation form with all fields', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: ShopCreationScreen(database: db)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create Shop Profile'), findsOneWidget);
      expect(find.text('Shop Name'), findsOneWidget);
      expect(find.text('Time Zone'), findsOneWidget);
      expect(find.text('Currency Code'), findsOneWidget);
      expect(find.text('Business Address'), findsOneWidget);
      expect(find.text('Contact Phone'), findsOneWidget);
      expect(find.text('Contact Email'), findsOneWidget);
      expect(find.text('Registration/Tax Number'), findsOneWidget);
      expect(find.byKey(const Key('shop_creation_submit_button')), findsOneWidget);
    });

    testWidgets('shows error when shop name is empty', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: ShopCreationScreen(database: db)),
      );
      await tester.pumpAndSettle();

      final buttonFinder = find.byKey(const Key('shop_creation_submit_button'));
      await tester.ensureVisible(buttonFinder);
      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();

      expect(find.text('Shop name is required'), findsOneWidget);
    });

    testWidgets('rejects invalid currency code (not 3 letters)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: ShopCreationScreen(database: db)),
      );
      await tester.pumpAndSettle();

      final nameFinder = find.byKey(const Key('shop_creation_name_field'));
      await tester.enterText(nameFinder, 'Alpha Gold');

      final currencyFinder = find.byKey(const Key('shop_creation_currency_field'));
      await tester.enterText(currencyFinder, 'US');

      final buttonFinder = find.byKey(const Key('shop_creation_submit_button'));
      await tester.ensureVisible(buttonFinder);
      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();

      expect(
        find.text('Currency code must be 3 letters (e.g. LKR)'),
        findsOneWidget,
      );
    });

    testWidgets('shows success message after shop creation', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: ShopCreationScreen(database: db)),
      );
      await tester.pumpAndSettle();

      final nameFinder = find.byKey(const Key('shop_creation_name_field'));
      await tester.enterText(nameFinder, 'Test Shop');

      final timezoneFinder = find.byKey(const Key('shop_creation_timezone_field'));
      await tester.enterText(timezoneFinder, 'Asia/Colombo');

      final currencyFinder = find.byKey(const Key('shop_creation_currency_field'));
      await tester.enterText(currencyFinder, 'LKR');

      final buttonFinder = find.byKey(const Key('shop_creation_submit_button'));
      await tester.ensureVisible(buttonFinder);
      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();

      expect(find.textContaining('Shop created successfully'), findsOneWidget);
      expect(find.textContaining('Shop ID:'), findsOneWidget);
    });
  });
}
