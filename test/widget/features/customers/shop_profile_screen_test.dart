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

