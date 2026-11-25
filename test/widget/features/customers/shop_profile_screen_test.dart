import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/customers/presentation/shop_profile_screen.dart';

void main() {
  late AppDatabase db;

  const shopId = 'shop-1';
  const ownerId = 'owner-1';

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);

    final now = DateTime.now().toUtc();

    await db.into(db.shops).insert(
      ShopEntry(
        id: shopId,
        name: 'Alpha Jewellers',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        businessAddress: '1 Main St',
        contactPhone: '0771234567',
        contactEmail: 'alpha@example.com',
        registrationNumber: 'REG-123',
        logoUri: null,
        receiptHeaderNotes: 'Welcome header',
        receiptFooterNotes: 'Thank you footer',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: ownerId,
        shopId: shopId,
        username: 'alpha.owner',
        fullName: 'Alpha Owner',
        role: 'shop_owner',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  AppUser owner() => AppUser(
        id: ownerId,
        shopId: shopId,
        username: 'alpha.owner',
        fullName: 'Alpha Owner',
        role: AppRole.shopOwner,
        isActive: true,
      );

  group('ShopProfileScreen - rendering', () {
    testWidgets('displays shop details', (tester) async {
      final screen = ShopProfileScreen(
        shopId: shopId,
        currentUser: owner(),
        database: db,
      );

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      expect(find.text('Shop ID: shop-1'), findsOneWidget);
      expect(find.text('Asia/Colombo'), findsOneWidget);
      expect(find.text('LKR'), findsOneWidget);
    });

    testWidgets('page background follows dark theme surfaces in dark mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
          darkTheme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          themeMode: ThemeMode.dark,
          home: ShopProfileScreen(
            shopId: shopId,
            currentUser: owner(),
            database: db,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkScheme = Theme.of(
        tester.element(find.text('Shop ID: shop-1')),
      ).colorScheme;

      final gradients = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .map((decoration) => decoration.gradient)
          .whereType<LinearGradient>()
          .toList();

      expect(
        gradients.any(
          (gradient) =>
              gradient.colors.length == 2 &&
              gradient.colors.first == darkScheme.surface &&
              gradient.colors.last == darkScheme.surfaceContainerLow,
        ),
        isTrue,
        reason: 'The shop profile page background must switch to dark surfaces',
      );
    });

    testWidgets('shows error when shop not found', (tester) async {
      final screen = ShopProfileScreen(
        shopId: 'nonexistent',
        currentUser: owner(),
        database: db,
      );

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      expect(find.text('Shop profile not found'), findsOneWidget);
    });
  });
}

