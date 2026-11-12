import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/features/admin/platform_admin_guard.dart';

void main() {
  group('PlatformAdminGuard', () {
    test('canAccessTable default-deny for platform_admin protected tables', () {
      expect(PlatformAdminGuard.canAccessTable('platform_admin', 'customers'), isFalse);
      expect(PlatformAdminGuard.canAccessTable('platform_admin', 'credits'), isFalse);
      expect(PlatformAdminGuard.canAccessTable('shop_owner', 'customers'), isTrue);
      expect(PlatformAdminGuard.canAccessTable('platform_admin', 'shops'), isTrue);
    });

    test('auditBlockedAttempt writes Category 14 event to sync_queue', () async {
      final db = AppDatabase.forTesting(AppDatabaseConnection.openInMemoryConnection());
      final now = DateTime.now().toUtc();
      await db.into(db.shops).insert(ShopEntry(
        id: 'shop-pag-01',
        name: 'Test Shop',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ));

      await PlatformAdminGuard.auditBlockedAttempt(
        'actor-1',
        'customers',
        shopId: 'shop-pag-01',
        db: db,
      );

      final rows = await db.select(db.syncQueue).get();
      expect(rows, hasLength(1));
      expect(rows.first.actionType, equals(PlatformAdminGuard.platformAdminBlockedAccessActionType));
      expect(rows.first.payloadJson, contains('"eventCategory":14'));
      expect(rows.first.payloadJson, contains('actor-1'));
      expect(rows.first.payloadJson, contains('customers'));

      await db.close();
    });

    test('auditBlockedAttempt propagates audit failures', () async {
      final db = AppDatabase.forTesting(AppDatabaseConnection.openInMemoryConnection());
      // shop does not exist -> FK violation
      await expectLater(
        PlatformAdminGuard.auditBlockedAttempt(
          'actor-1',
          'customers',
          shopId: 'missing-shop',
          db: db,
        ),
        throwsA(anything),
      );
      await db.close();
    });

    test('auditBlockedAttempt requires an audit sink', () async {
      await expectLater(
        PlatformAdminGuard.auditBlockedAttempt(
          'actor-1',
          'customers',
          shopId: 'shop-pag-01',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

