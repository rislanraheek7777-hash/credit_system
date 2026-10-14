import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);
  });

  tearDown(() async {
    await db.close();
  });

  group('AppDatabase - Local Drift Foundations & Schema v1 Tests', () {
    test('schema version is 1 and all tables exist', () {
      expect(db.schemaVersion, equals(1));
      expect(db.allTables.map((t) => t.actualTableName), containsAll(['shops', 'app_users', 'sync_queue']));
    });

    test('SHOPS: inserts and queries shop tenant profile with defaults', () async {
      final now = DateTime.now().toUtc();
      final shop = ShopEntry(
        id: 'shop-uuid-1',
        name: 'Perera Jewellers Colombo',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      );

      await db.into(db.shops).insert(shop);

      final retrieved = await (db.select(db.shops)..where((s) => s.id.equals('shop-uuid-1'))).getSingle();
      expect(retrieved.id, equals('shop-uuid-1'));
      expect(retrieved.name, equals('Perera Jewellers Colombo'));
      expect(retrieved.currencyCode, equals('LKR'));
      expect(retrieved.timezone, equals('Asia/Colombo'));
    });

    test('SHOPS: updates shop name and operational timezone', () async {
      final now = DateTime.now().toUtc();
      await db.into(db.shops).insert(
        ShopEntry(
          id: 'shop-uuid-2',
          name: 'Original Name',
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await (db.update(db.shops)..where((s) => s.id.equals('shop-uuid-2'))).write(
        ShopsCompanion(
          name: const Value('Updated Trade Name'),
          timezone: const Value('Asia/Kolkata'),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

      final updated = await (db.select(db.shops)..where((s) => s.id.equals('shop-uuid-2'))).getSingle();
      expect(updated.name, equals('Updated Trade Name'));
      expect(updated.timezone, equals('Asia/Kolkata'));
    });

    test('APP_USERS: inserts counter staff account with default session_version = 1', () async {
      final now = DateTime.now().toUtc();
      await db.into(db.shops).insert(
        ShopEntry(
          id: 'shop-uuid-3',
          name: 'City Pawn Colombo',
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final user = AppUserEntry(
        id: 'user-uuid-1',
        shopId: 'shop-uuid-3',
        username: 'kasun.counter',
        fullName: 'Kasun Perera',
        role: 'counter_staff',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      );

      await db.into(db.appUsers).insert(user);

      final retrieved = await (db.select(db.appUsers)..where((u) => u.id.equals('user-uuid-1'))).getSingle();
      expect(retrieved.username, equals('kasun.counter'));
      expect(retrieved.role, equals('counter_staff'));
      expect(retrieved.sessionVersion, equals(1));
      expect(retrieved.isActive, isTrue);
    });

    test('APP_USERS: increments session_version to immediately revoke sessions (FR-5)', () async {
      final now = DateTime.now().toUtc();
      await db.into(db.shops).insert(
        ShopEntry(
          id: 'shop-uuid-4',
          name: 'City Pawn Colombo',
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await db.into(db.appUsers).insert(
        AppUserEntry(
          id: 'user-uuid-2',
          shopId: 'shop-uuid-4',
          username: 'staff.revocation.test',
          fullName: 'Revocation Staff',
          role: 'counter_staff',
          isActive: true,
          sessionVersion: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Increment session version on credential change or permission update
      await (db.update(db.appUsers)..where((u) => u.id.equals('user-uuid-2'))).write(
        AppUsersCompanion(
          sessionVersion: const Value(2),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

      final userAfterRevocation = await (db.select(db.appUsers)..where((u) => u.id.equals('user-uuid-2'))).getSingle();
      expect(userAfterRevocation.sessionVersion, equals(2));
    });

    test('FOREIGN KEY: AppUsers insertion fails if referenced shop does not exist', () async {
      final now = DateTime.now().toUtc();
      final orphanUser = AppUserEntry(
        id: 'orphan-user-1',
        shopId: 'non-existent-shop-id',
        username: 'orphan',
        fullName: 'Orphan Staff',
        role: 'counter_staff',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      );

      expect(
        () => db.into(db.appUsers).insert(orphanUser),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test('UNIQUE CONSTRAINT: AppUsers blocks duplicate username within same shop tenant', () async {
      final now = DateTime.now().toUtc();
      await db.into(db.shops).insert(
        ShopEntry(
          id: 'shop-uuid-5',
          name: 'Shop Five',
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await db.into(db.appUsers).insert(
        AppUserEntry(
          id: 'user-a',
          shopId: 'shop-uuid-5',
          username: 'duplicate.user',
          fullName: 'Staff Alpha',
          role: 'counter_staff',
          isActive: true,
          sessionVersion: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(
        () => db.into(db.appUsers).insert(
          AppUserEntry(
            id: 'user-b',
            shopId: 'shop-uuid-5',
            username: 'duplicate.user',
            fullName: 'Staff Beta',
            role: 'counter_staff',
            isActive: true,
            sessionVersion: 1,
            createdAt: now,
            updatedAt: now,
          ),
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test('SYNC_QUEUE: inserts, filters pending items, and confirms server acknowledgement', () async {
      final now = DateTime.now().toUtc();
      await db.into(db.shops).insert(
        ShopEntry(
          id: 'shop-uuid-6',
          name: 'Shop Six',
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final queueItem = SyncQueueRecord(
        id: 'sync-op-1',
        shopId: 'shop-uuid-6',
        idempotencyKey: 'idem-uuid-001',
        entityType: 'loan',
        entityId: 'loan-uuid-101',
        actionType: 'create_loan',
        payloadJson: '{"principal_cents": 5000000, "duration_days": 30}',
        status: 'pending_server_ack',
        retryCount: 0,
        lastError: null,
        createdAt: now,
        updatedAt: null,
      );

      await db.into(db.syncQueue).insert(queueItem);

      // Query only pending server ack items for shop
      final pendingOps = await (db.select(db.syncQueue)
            ..where((q) => q.shopId.equals('shop-uuid-6') & q.status.equals('pending_server_ack')))
          .get();

      expect(pendingOps.length, equals(1));
      expect(pendingOps.first.idempotencyKey, equals('idem-uuid-001'));
      expect(pendingOps.first.status, equals('pending_server_ack'));

      // Transition to confirmed_by_server upon server acknowledgement
      await (db.update(db.syncQueue)..where((q) => q.id.equals('sync-op-1'))).write(
        SyncQueueCompanion(
          status: const Value('confirmed_by_server'),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

      final confirmed = await (db.select(db.syncQueue)..where((q) => q.id.equals('sync-op-1'))).getSingle();
      expect(confirmed.status, equals('confirmed_by_server'));
    });

    test('SYNC_QUEUE: unique idempotency constraint blocks duplicate operations', () async {
      final now = DateTime.now().toUtc();
      await db.into(db.shops).insert(
        ShopEntry(
          id: 'shop-uuid-7',
          name: 'Shop Seven',
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await db.into(db.syncQueue).insert(
        SyncQueueRecord(
          id: 'sync-op-2',
          shopId: 'shop-uuid-7',
          idempotencyKey: 'same-idempotency-key',
          entityType: 'payment',
          entityId: 'payment-1',
          actionType: 'record_payment',
          payloadJson: '{"amount_cents": 100000}',
          status: 'pending_server_ack',
          retryCount: 0,
          lastError: null,
          createdAt: now,
          updatedAt: null,
        ),
      );

      expect(
        () => db.into(db.syncQueue).insert(
          SyncQueueRecord(
            id: 'sync-op-3',
            shopId: 'shop-uuid-7',
            idempotencyKey: 'same-idempotency-key',
            entityType: 'payment',
            entityId: 'payment-2',
            actionType: 'record_payment',
            payloadJson: '{"amount_cents": 100000}',
            status: 'pending_server_ack',
            retryCount: 0,
            lastError: null,
            createdAt: now,
            updatedAt: null,
          ),
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });
  });
}
