import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/features/shop/data/daos/shop_dao.dart';
import 'package:credit_system/features/shop/domain/models/shop_profile.dart';

void main() {
  late AppDatabase db;
  late ShopDao shopDao;

  setUp(() {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);
    shopDao = ShopDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('ShopDao Local Persistence & Offline Retrieval Tests (Story 1.6)', () {
    test('creates and retrieves shop profile with default timezone and currency', () async {
      final profile = ShopProfile(
        id: 'shop-uuid-101',
        name: 'Galle Gems & Credit',
      );

      await shopDao.createShop(profile);

      final retrieved = await shopDao.getShopById('shop-uuid-101');
      expect(retrieved, isNotNull);
      expect(retrieved!.id, equals('shop-uuid-101'));
      expect(retrieved.name, equals('Galle Gems & Credit'));
      expect(retrieved.currencyCode, equals('LKR'));
      expect(retrieved.timezone, equals('Asia/Colombo'));
      expect(retrieved.businessAddress, isNull);
    });

    test('creates, updates, and retrieves full shop profile with branding and contact info', () async {
      final initial = ShopProfile(
        id: 'shop-uuid-102',
        name: 'Lanka Pawnbrokers Ltd',
        businessAddress: '45 Main Street, Kandy',
        contactPhone: '+94 81 222 3344',
        contactEmail: 'contact@lankapawn.lk',
        registrationNumber: 'REG-98765',
        logoUri: '/app/logos/lanka_pawn.png',
        receiptHeaderNotes: 'Approved Gold Credit Counter',
        receiptFooterNotes: 'Safe custody insured by ABC Insurance Ltd.',
      );

      await shopDao.createShop(initial);

      final fetched = await shopDao.getShopById('shop-uuid-102');
      expect(fetched!.businessAddress, equals('45 Main Street, Kandy'));
      expect(fetched.contactPhone, equals('+94 81 222 3344'));
      expect(fetched.contactEmail, equals('contact@lankapawn.lk'));
      expect(fetched.registrationNumber, equals('REG-98765'));
      expect(fetched.logoUri, equals('/app/logos/lanka_pawn.png'));
      expect(fetched.receiptHeaderNotes, equals('Approved Gold Credit Counter'));
      expect(fetched.receiptFooterNotes, equals('Safe custody insured by ABC Insurance Ltd.'));

      // Update shop profile branding
      final updated = fetched.copyWith(
        name: 'Lanka Pawnbrokers & Microcredit',
        businessAddress: '47 Main Street, Kandy (New Wing)',
        receiptFooterNotes: 'Gold redemption policy updated. Please retain receipt.',
      );

      await shopDao.updateShopProfile(updated);

      final reFetched = await shopDao.getShopById('shop-uuid-102');
      expect(reFetched!.name, equals('Lanka Pawnbrokers & Microcredit'));
      expect(reFetched.businessAddress, equals('47 Main Street, Kandy (New Wing)'));
      expect(reFetched.receiptFooterNotes, contains('policy updated'));
      expect(reFetched.contactPhone, equals('+94 81 222 3344')); // Preserved
    });

    test('currency can be modified when no financial transactions exist', () async {
      final profile = ShopProfile(
        id: 'shop-uuid-103',
        name: 'International Trade Counter',
        currencyCode: 'LKR',
      );

      await shopDao.createShop(profile);

      // No financial transactions exist -> currency change is permitted
      final updated = profile.copyWith(currencyCode: 'USD');
      await shopDao.updateShopProfile(updated);

      final retrieved = await shopDao.getShopById('shop-uuid-103');
      expect(retrieved!.currencyCode, equals('USD'));
    });

    test('currency change is LOCKED when financial transactions exist in sync_queue', () async {
      final profile = ShopProfile(
        id: 'shop-uuid-104',
        name: 'Colombo Active Lending Shop',
        currencyCode: 'LKR',
      );

      await shopDao.createShop(profile);

      // Simulate an offline financial transaction recorded in sync_queue
      await db.into(db.syncQueue).insert(
        SyncQueueCompanion.insert(
          id: 'tx-sync-uuid-1',
          shopId: 'shop-uuid-104',
          idempotencyKey: 'idemp-key-001',
          entityType: 'credit',
          entityId: 'credit-uuid-001',
          actionType: 'create',
          payloadJson: '{"principalCents": 100000}',
          createdAt: DateTime.now().toUtc(),
        ),
      );

      // Verify transaction detection
      expect(await shopDao.hasFinancialTransactions('shop-uuid-104'), isTrue);

      // Attempt to change currency code from LKR to USD
      final currencyChangeAttempt = profile.copyWith(currencyCode: 'USD');

      expect(
        () => shopDao.updateShopProfile(currencyChangeAttempt),
        throwsA(isA<CurrencyLockedException>().having(
          (e) => e.message,
          'message',
          contains('Base currency is locked to LKR because financial transactions exist'),
        )),
      );

      // Verify currency remained locked in database
      final reFetched = await shopDao.getShopById('shop-uuid-104');
      expect(reFetched!.currencyCode, equals('LKR'));
    });
  });
}

