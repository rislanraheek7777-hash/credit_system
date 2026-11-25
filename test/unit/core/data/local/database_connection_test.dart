import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:credit_system/core/data/local/app_database.dart';
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
            'sync-1', 'non-existent-shop', 'idem-1', 'credit', 'credit-1', 'create_credit', '{}', 'pending_server_ack', 0, 1000
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
          'sync-1', 'shop-1', 'idem-1', 'credit', 'credit-1', 'create_credit', '{"principal": 5000000}', 'pending_server_ack', 0, 1000
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
            'sync-2', 'shop-1', 'idem-2', 'credit', 'credit-2', 'create_credit', '{}', 'invalid_status_xyz', 0, 1000
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
            'sync-3', 'shop-1', 'idem-3', 'credit', 'credit-3', 'create_credit', '{}', 'pending_server_ack', -1, 1000
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
          'sync-4', 'shop-1', 'duplicate-key-1', 'credit', 'credit-4', 'create_credit', '{}', 'pending_server_ack', 0, 1000
        );
      ''');

      expect(
        () => rawDb.execute('''
          INSERT INTO sync_queue (
            id, shop_id, idempotency_key, entity_type, entity_id, action_type, payload_json, status, retry_count, created_at
          ) VALUES (
            'sync-5', 'shop-1', 'duplicate-key-1', 'credit', 'credit-5', 'create_credit', '{}', 'pending_server_ack', 0, 1000
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

    test('UNIQUE CONSTRAINT: AppUsers declares shop-scoped contact uniqueness (Story 1.10)', () {
      final db = AppDatabase.forTesting(
        AppDatabaseConnection.openInMemoryConnection(),
      );
      addTearDown(db.close);
      final keyNames = db.appUsers.uniqueKeys
          .map((key) => key.map((column) => column.name).join(','))
          .toList();

      expect(keyNames, contains('shop_id,username'));
      expect(keyNames, contains('shop_id,email'),
          reason: 'verified email must resolve to one account per tenant');
      expect(keyNames, contains('shop_id,phone'),
          reason: 'verified phone must resolve to one account per tenant');
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
group('AppUsers local uniqueness upgrade (Story 1.10, v28 -> v29)', () {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('credit_system_v29_migration');
    dbFile = File(p.join(tempDir.path, 'credit_system.sqlite'));
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  void seedV28Database({
    bool withDuplicates = true,
    bool withDuplicatePhone = false,
  }) {
    final raw = sqlite.sqlite3.open(dbFile.path);
    try {
      raw.execute('PRAGMA user_version = 28;');
      raw.execute('''
        CREATE TABLE shops (
          id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL,
          currency_code TEXT NOT NULL DEFAULT 'LKR', timezone TEXT NOT NULL DEFAULT 'Asia/Colombo',
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
        );
      ''');
      raw.execute('''
        CREATE TABLE app_users (
          id TEXT NOT NULL PRIMARY KEY,
          shop_id TEXT NOT NULL REFERENCES shops(id) ON DELETE RESTRICT,
          username TEXT NOT NULL, email TEXT, phone TEXT,
          full_name TEXT NOT NULL, role TEXT NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1, session_version INTEGER NOT NULL DEFAULT 1,
          permissions TEXT, password_hash TEXT,
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
          UNIQUE (shop_id, username), CHECK (session_version >= 1)
        );
      ''');
      raw.execute("INSERT INTO shops (id, name, currency_code, timezone, created_at, updated_at) VALUES ('shop-a', 'A', 'LKR', 'Asia/Colombo', 1, 1), ('shop-b', 'B', 'LKR', 'Asia/Colombo', 1, 1);");
      raw.execute("INSERT INTO app_users (id, shop_id, username, email, phone, full_name, role, is_active, session_version, created_at, updated_at) VALUES ('u1','shop-a','one','shared@example.com','+94770000001','One','cashier',1,1,1,1);");
      raw.execute("INSERT INTO app_users (id, shop_id, username, email, phone, full_name, role, is_active, session_version, created_at, updated_at) VALUES ('u2','shop-a','two',${withDuplicates ? "'shared@example.com'" : "'two@example.com'" },${withDuplicatePhone ? "'+94770000001'" : "'+94770000002'"},'Two','cashier',1,1,1,1);");
      raw.execute("INSERT INTO app_users (id, shop_id, username, email, phone, full_name, role, is_active, session_version, created_at, updated_at) VALUES ('u3','shop-b','three','shared@example.com','+94770000001','Three','cashier',1,1,1,1);");
    } finally {
      raw.close();
    }
  }

  AppDatabase openWithDeviceSemantics() {
    return AppDatabase.forTesting(
      NativeDatabase(
        dbFile,
        setup: (db) => db.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
  }

  test('v28 upgrade fails closed on duplicate contacts, destroying no data', () async {
    seedV28Database(withDuplicates: true);

    final db = openWithDeviceSemantics();
    await expectLater(
      db.customSelect('SELECT 1').get(),
      throwsA(isA<StateError>().having(
        (e) => e.toString(),
        'message',
        contains('duplicate email'),
      )),
    );
    await db.close();

    final raw = sqlite.sqlite3.open(dbFile.path);
    try {
      final rows = raw.select('SELECT id, email, phone FROM app_users ORDER BY id');
      expect(rows, hasLength(3));
      expect(rows.firstWhere((r) => r['id'] == 'u2')['email'],
          equals('shared@example.com'),
          reason: 'verified contacts must never be nulled silently');
    } finally {
      raw.close();
    }
  });

  test('v28 upgrade fails closed on a duplicate phone within one tenant', () async {
    seedV28Database(withDuplicates: false, withDuplicatePhone: true);

    final db = openWithDeviceSemantics();
    await expectLater(
      db.customSelect('SELECT 1').get(),
      throwsA(isA<StateError>().having(
        (e) => e.toString(),
        'message',
        contains('duplicate phone'),
      )),
    );
    await db.close();
  });

  test('v28 database upgrades to v29 and enforces uniqueness non-destructively', () async {
    seedV28Database(withDuplicates: false);
    final db = openWithDeviceSemantics();
    addTearDown(() async => db.close());

    expect(db.schemaVersion, equals(29));

    final users = await db.select(db.appUsers).get();
    expect(users, hasLength(3));
    final u1 = users.firstWhere((u) => u.id == 'u1');
    final u2 = users.firstWhere((u) => u.id == 'u2');
    final u3 = users.firstWhere((u) => u.id == 'u3');
    expect(u1.email, equals('shared@example.com'));
    expect(u2.email, equals('two@example.com'));
    expect(u1.phone, equals('+94770000001'));
    expect(u2.phone, equals('+94770000002'));
    expect(u3.email, equals('shared@example.com'),
        reason: 'the same contact is allowed in a different tenant');

    final keyNames = db.appUsers.uniqueKeys
        .map((key) => key.map((column) => column.name).join(','))
        .toList();
    expect(keyNames, contains('shop_id,email'));
    expect(keyNames, contains('shop_id,phone'));
  });

  test('upgraded app_users keeps column parity with a generated database',
      () async {
    seedV28Database(withDuplicates: false);
    final upgraded = openWithDeviceSemantics();
    addTearDown(upgraded.close);

    final fresh = AppDatabase.forTesting(
      AppDatabaseConnection.openInMemoryConnection(),
    );
    addTearDown(fresh.close);

    Future<List<String>> columns(AppDatabase db) async {
      final rows =
          await db.customSelect('PRAGMA table_info("app_users")').get();
      return rows.map((row) => row.data['name'] as String).toList();
    }

    expect(await columns(upgraded), equals(await columns(fresh)));
  });

  test('upgraded v29 database rejects duplicate contact inserts', () async {
    seedV28Database(withDuplicates: false);
    final db = openWithDeviceSemantics();
    addTearDown(db.close);

    await expectLater(
      db.customStatement(
        'INSERT INTO app_users (id, shop_id, username, email, full_name, role, '
        'session_version, created_at, updated_at) VALUES '
        "('u4','shop-a','four','shared@example.com','Four','cashier',1,1,1)",
      ),
      throwsA(isA<Exception>()),
    );
    await expectLater(
      db.customStatement(
        'INSERT INTO app_users (id, shop_id, username, phone, full_name, role, '
        'session_version, created_at, updated_at) VALUES '
        "('u5','shop-a','five','+94770000001','Five','cashier',1,1,1)",
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('reopening an upgraded database does not re-run the migration', () async {
    seedV28Database(withDuplicates: false);
    final first = openWithDeviceSemantics();
    await first.select(first.appUsers).get();
    await first.close();

    final second = openWithDeviceSemantics();
    addTearDown(() async => second.close());
    expect((await second.select(second.appUsers).get()), hasLength(3));
  });
  });
}

class _FakeQueryExecutorUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;
  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) async {}
}
