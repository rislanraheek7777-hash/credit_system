import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/data/local/tables/app_users_table.dart';
import 'package:credit_system/core/data/local/tables/shops_table.dart';
import 'package:credit_system/core/data/local/tables/sync_queue_table.dart';

void main() {
  group('AppDatabaseConnection - In-Memory and Sandboxed Execution', () {
    test('openInMemoryConnection enables SQLite foreign keys by default', () async {
      final executor = AppDatabaseConnection.openInMemoryConnection();
      await executor.ensureOpen(_FakeQueryExecutorUser());

      final result = await executor.runSelect('PRAGMA foreign_keys;', []);
      expect(result.first['foreign_keys'], equals(1));

      await executor.close();
    });

    test('openSandboxedConnection creates file in specified directory and enables foreign keys', () async {
      final tempDir = await Directory.systemTemp.createTemp('credit_system_db_test_');

      try {
        final executor = AppDatabaseConnection.openSandboxedConnection(
          overrideDirectory: tempDir,
          dbName: 'test_sandboxed.sqlite',
        );
        await executor.ensureOpen(_FakeQueryExecutorUser());

        final result = await executor.runSelect('PRAGMA foreign_keys;', []);
        expect(result.first['foreign_keys'], equals(1));

        final expectedFile = File('${tempDir.path}${Platform.pathSeparator}test_sandboxed.sqlite');
        expect(await expectedFile.exists(), isTrue);

        await executor.close();
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('openConnection dispatches correctly based on inMemory parameter', () async {
      final inMemExecutor = AppDatabaseConnection.openConnection(inMemory: true);
      await inMemExecutor.ensureOpen(_FakeQueryExecutorUser());

      final inMemResult = await inMemExecutor.runSelect('PRAGMA foreign_keys;', []);
      expect(inMemResult.first['foreign_keys'], equals(1));
      await inMemExecutor.close();
    });
  });

  group('Drift Table Contracts - SQLite Schema & Constraint Verification', () {
    late sqlite.Database rawDb;

    setUp(() {
      rawDb = sqlite.sqlite3.openInMemory();
      rawDb.execute('PRAGMA foreign_keys = ON;');

      // Create Shops table
      rawDb.execute('''
        CREATE TABLE shops (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          currency_code TEXT NOT NULL DEFAULT 'LKR',
          timezone TEXT NOT NULL DEFAULT 'Asia/Colombo',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
      ''');

      // Create AppUsers table matching AppUsers drift definition
      rawDb.execute('''
        CREATE TABLE app_users (
          id TEXT NOT NULL PRIMARY KEY,
          shop_id TEXT NOT NULL REFERENCES shops(id) ON DELETE RESTRICT,
          username TEXT NOT NULL,
          full_name TEXT NOT NULL,
          role TEXT NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1,
          session_version INTEGER NOT NULL DEFAULT 1,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          UNIQUE(shop_id, username),
          CHECK (session_version >= 1)
        );
      ''');

      // Create SyncQueue table matching SyncQueue drift definition
      rawDb.execute('''
        CREATE TABLE sync_queue (
          id TEXT NOT NULL PRIMARY KEY,
          shop_id TEXT NOT NULL REFERENCES shops(id) ON DELETE RESTRICT,
          idempotency_key TEXT NOT NULL,
          entity_type TEXT NOT NULL,
          entity_id TEXT NOT NULL,
          action_type TEXT NOT NULL,
          payload_json TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending_server_ack',
          retry_count INTEGER NOT NULL DEFAULT 0,
          last_error TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER,
          UNIQUE(shop_id, idempotency_key),
          CHECK (status IN ('pending_server_ack', 'confirmed_by_server', 'failed')),
          CHECK (retry_count >= 0)
        );
      ''');
    });

    tearDown(() {
      rawDb.close();
    });

    test('FOREIGN KEY: SyncQueue insertion fails if referenced shop does not exist', () {
      expect(
        () => rawDb.execute('''
          INSERT INTO sync_queue (
            id, shop_id, idempotency_key, entity_type, entity_id, action_type, payload_json, status, retry_count, created_at
          ) VALUES (
            'sync-1', 'non-existent-shop', 'idem-1', 'loan', 'loan-1', 'create_loan', '{}', 'pending_server_ack', 0, 1000
          );
        '''),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test('FOREIGN KEY: SyncQueue insertion succeeds when referenced shop exists', () {
      rawDb.execute('''
        INSERT INTO shops (id, name, currency_code, timezone, created_at, updated_at)
        VALUES ('shop-1', 'Perera Jewellers', 'LKR', 'Asia/Colombo', 1000, 1000);
      ''');

      rawDb.execute('''
        INSERT INTO sync_queue (
          id, shop_id, idempotency_key, entity_type, entity_id, action_type, payload_json, status, retry_count, created_at
        ) VALUES (
          'sync-1', 'shop-1', 'idem-1', 'loan', 'loan-1', 'create_loan', '{"principal": 5000000}', 'pending_server_ack', 0, 1000
        );
      ''');

      final rows = rawDb.select("SELECT id, status, retry_count FROM sync_queue WHERE id = 'sync-1';");
      expect(rows.length, equals(1));
      expect(rows.first['status'], equals('pending_server_ack'));
      expect(rows.first['retry_count'], equals(0));
    });

    test('CHECK CONSTRAINT: SyncQueue rejects invalid status values', () {
      rawDb.execute('''
        INSERT INTO shops (id, name, currency_code, timezone, created_at, updated_at)
        VALUES ('shop-1', 'Perera Jewellers', 'LKR', 'Asia/Colombo', 1000, 1000);
      ''');

      expect(
        () => rawDb.execute('''
          INSERT INTO sync_queue (
            id, shop_id, idempotency_key, entity_type, entity_id, action_type, payload_json, status, retry_count, created_at
          ) VALUES (
            'sync-2', 'shop-1', 'idem-2', 'loan', 'loan-2', 'create_loan', '{}', 'invalid_status_xyz', 0, 1000
          );
        '''),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test('CHECK CONSTRAINT: SyncQueue rejects negative retry_count', () {
      rawDb.execute('''
        INSERT INTO shops (id, name, currency_code, timezone, created_at, updated_at)
        VALUES ('shop-1', 'Perera Jewellers', 'LKR', 'Asia/Colombo', 1000, 1000);
      ''');

      expect(
        () => rawDb.execute('''
          INSERT INTO sync_queue (
            id, shop_id, idempotency_key, entity_type, entity_id, action_type, payload_json, status, retry_count, created_at
          ) VALUES (
            'sync-3', 'shop-1', 'idem-3', 'loan', 'loan-3', 'create_loan', '{}', 'pending_server_ack', -1, 1000
          );
        '''),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test('UNIQUE CONSTRAINT: SyncQueue rejects duplicate idempotency_key within same shop', () {
      rawDb.execute('''
        INSERT INTO shops (id, name, currency_code, timezone, created_at, updated_at)
        VALUES ('shop-1', 'Perera Jewellers', 'LKR', 'Asia/Colombo', 1000, 1000);
      ''');

      rawDb.execute('''
        INSERT INTO sync_queue (
          id, shop_id, idempotency_key, entity_type, entity_id, action_type, payload_json, status, retry_count, created_at
        ) VALUES (
          'sync-4', 'shop-1', 'duplicate-key-1', 'loan', 'loan-4', 'create_loan', '{}', 'pending_server_ack', 0, 1000
        );
      ''');

      expect(
        () => rawDb.execute('''
          INSERT INTO sync_queue (
            id, shop_id, idempotency_key, entity_type, entity_id, action_type, payload_json, status, retry_count, created_at
          ) VALUES (
            'sync-5', 'shop-1', 'duplicate-key-1', 'loan', 'loan-5', 'create_loan', '{}', 'pending_server_ack', 0, 1000
          );
        '''),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test('CHECK CONSTRAINT: AppUsers enforces session_version >= 1', () {
      rawDb.execute('''
        INSERT INTO shops (id, name, currency_code, timezone, created_at, updated_at)
        VALUES ('shop-1', 'Perera Jewellers', 'LKR', 'Asia/Colombo', 1000, 1000);
      ''');

      // Valid session_version = 1
      rawDb.execute('''
        INSERT INTO app_users (
          id, shop_id, username, full_name, role, is_active, session_version, created_at, updated_at
        ) VALUES (
          'user-1', 'shop-1', 'kasun', 'Kasun Perera', 'counter_staff', 1, 1, 1000, 1000
        );
      ''');

      // Invalid session_version = 0 should fail
      expect(
        () => rawDb.execute('''
          INSERT INTO app_users (
            id, shop_id, username, full_name, role, is_active, session_version, created_at, updated_at
          ) VALUES (
            'user-2', 'shop-1', 'sunil', 'Sunil Silva', 'counter_staff', 1, 0, 1000, 1000
          );
        '''),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test('UNIQUE CONSTRAINT: AppUsers rejects duplicate username within same shop', () {
      rawDb.execute('''
        INSERT INTO shops (id, name, currency_code, timezone, created_at, updated_at)
        VALUES ('shop-1', 'Perera Jewellers', 'LKR', 'Asia/Colombo', 1000, 1000);
      ''');

      rawDb.execute('''
        INSERT INTO app_users (
          id, shop_id, username, full_name, role, is_active, session_version, created_at, updated_at
        ) VALUES (
          'user-1', 'shop-1', 'kasun', 'Kasun Perera', 'counter_staff', 1, 1, 1000, 1000
        );
      ''');

      expect(
        () => rawDb.execute('''
          INSERT INTO app_users (
            id, shop_id, username, full_name, role, is_active, session_version, created_at, updated_at
          ) VALUES (
            'user-3', 'shop-1', 'kasun', 'Another Kasun', 'counter_staff', 1, 1, 1000, 1000
          );
        '''),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test('Table classes instantiate cleanly and expose expected custom constraints', () {
      final shops = Shops();
      expect(shops, isA<Table>());

      final users = AppUsers();
      expect(users, isA<Table>());
      expect(users.customConstraints, contains('CHECK (session_version >= 1)'));

      final queue = SyncQueue();
      expect(queue, isA<Table>());
      expect(queue.customConstraints, contains("CHECK (status IN ('pending_server_ack', 'confirmed_by_server', 'failed'))"));
      expect(queue.customConstraints, contains('CHECK (retry_count >= 0)'));
    });
  });
}

class _FakeQueryExecutorUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) async {}
}
