import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/features/shop/data/daos/shop_dao.dart';
import 'package:credit_system/features/shop/domain/models/shop_profile.dart';
import 'package:credit_system/features/shop/presentation/shop_profile_screen.dart';

void main() {
  group('ShopProfileScreen View-Only Widget Tests (Story 1.6)', () {
    late AppDatabase db;
    late ShopDao shopDao;

    setUp(() async {
      final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
      db = AppDatabase.forTesting(inMemoryExecutor);
      shopDao = ShopDao(db);

      // Insert a test shop profile
      await shopDao.createShop(
        ShopProfile(
          id: 'shop-test-001',
          name: 'Test Shop',
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          businessAddress: '123 Test Street',
          contactPhone: '+94 11 234 5678',
          contactEmail: 'test@shop.lk',
          registrationNumber: 'REG-001',
          logoUri: '/app/logos/test.png',
          receiptHeaderNotes: 'Test header',
          receiptFooterNotes: 'Test footer',
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('displays shop profile with default values', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ShopProfileScreen(shopId: 'shop-test-001', database: db),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Shop Profile'), findsOneWidget);
      expect(find.text('shop-test-001'), findsOneWidget);
      expect(find.text('Test Shop'), findsOneWidget);
      expect(find.text('LKR'), findsOneWidget);
      expect(find.text('Asia/Colombo'), findsOneWidget);
      expect(find.text('123 Test Street'), findsOneWidget);
      expect(find.text('+94 11 234 5678'), findsOneWidget);
      expect(find.text('test@shop.lk'), findsOneWidget);
      expect(find.text('REG-001'), findsOneWidget);
      expect(find.text('/app/logos/test.png'), findsOneWidget);
      expect(find.text('Test header'), findsOneWidget);
      expect(find.text('Test footer'), findsOneWidget);
    });

    testWidgets('shows editing disabled banner', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ShopProfileScreen(shopId: 'shop-test-001', database: db),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Editing Disabled'), findsOneWidget);
    });

    testWidgets('save button is disabled', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ShopProfileScreen(shopId: 'shop-test-001', database: db),
        ),
      );
      await tester.pumpAndSettle();

      final saveButton = find.byWidgetPredicate(
        (widget) => widget is ElevatedButton &&
            widget.onPressed == null &&
            (widget.child as Text).data == 'Save Changes (Disabled — Story 1.7 RBAC pending)',
      );
      expect(saveButton, findsOneWidget);
    });

    testWidgets('shows currency locked when sync_queue has financial transaction', (
      WidgetTester tester,
    ) async {
      // Insert a financial transaction in sync_queue
      await db.into(db.syncQueue).insert(
        SyncQueueCompanion(
          id: Value('tx-sync-001'),
          shopId: Value('shop-test-001'),
          idempotencyKey: Value('idemp-001'),
          entityType: Value('loan'),
          entityId: Value('loan-001'),
          actionType: Value('create'),
          payloadJson: Value('{"principalCents": 100000}'),
          createdAt: Value(DateTime.now().toUtc()),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ShopProfileScreen(shopId: 'shop-test-001', database: db),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Currency Locked'), findsOneWidget);
      expect(find.textContaining('financial transactions exist'), findsOneWidget);
    });

    testWidgets('shows currency unlocked when no financial transactions', (
      WidgetTester tester,
    ) async {
      // No sync_queue entries for this shop
      await tester.pumpWidget(
        MaterialApp(
          home: ShopProfileScreen(shopId: 'shop-test-001', database: db),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Currency Locked'), findsNothing);
      expect(find.text('LKR'), findsOneWidget);
    });

    testWidgets('all profile fields are displayed', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ShopProfileScreen(shopId: 'shop-test-001', database: db),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Test Shop'), findsOneWidget);
      expect(find.text('LKR'), findsOneWidget);
      expect(find.text('Asia/Colombo'), findsOneWidget);
      expect(find.text('123 Test Street'), findsOneWidget);
      expect(find.text('+94 11 234 5678'), findsOneWidget);
      expect(find.text('test@shop.lk'), findsOneWidget);
      expect(find.text('REG-001'), findsOneWidget);
      expect(find.text('/app/logos/test.png'), findsOneWidget);
      expect(find.text('Test header'), findsOneWidget);
      expect(find.text('Test footer'), findsOneWidget);
    });

    testWidgets('shows shop profile not found when shop does not exist', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ShopProfileScreen(shopId: 'nonexistent-shop', database: db),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Shop profile not found'), findsOneWidget);
    });

    testWidgets('shows error when DAO read fails', (
      WidgetTester tester,
    ) async {
      // Close the database before pumping, so getShopById throws
      await db.close();

      await tester.pumpWidget(
        MaterialApp(
          home: ShopProfileScreen(shopId: 'shop-test-001', database: db),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to load shop profile'), findsOneWidget);
    });
  });
}
