import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:credit_system/core/data/local/app_database.dart';

/// Regression coverage for the schema version 10 -> 11 rebuild of the
/// `collateral_items` table (Story 3.4, finding F5).
///
/// `collateral_photo_exceptions.collateral_item_id` references
/// `collateral_items(id)` with `ON DELETE RESTRICT`. The rebuild drops and
/// recreates `collateral_items`, so with foreign-key enforcement enabled the
/// `RESTRICT` action of every referencing photo-exception row fires and the
/// upgrade aborts.
///
/// These tests exercise the migration the way a *device* runs it:
///
/// - a persistent database file (not an in-memory database),
/// - foreign-key enforcement switched on in the connection setup callback,
///   exactly as `AppDatabaseConnection.openSandboxedConnection` does,
/// - a version 10 schema that carries the real foreign keys and a populated
///   `collateral_photo_exceptions` table.
void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('credit_system_v11_migration');
    dbFile = File(p.join(tempDir.path, 'credit_system.sqlite'));
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// Opens the database exactly the way the running application does: a
  /// persistent file with `PRAGMA foreign_keys = ON` applied by the connection
  /// setup callback, which Drift runs *before* any migration.
  AppDatabase openWithDeviceSemantics(File file) {
    final executor = NativeDatabase(
      file,
      setup: (db) => db.execute('PRAGMA foreign_keys = ON;'),
    );
    return AppDatabase.forTesting(executor);
  }

  group('schema version 10 -> 11 rebuild of the collateral_items table', () {
    test(
        'completes with foreign-key enforcement enabled and a populated '
        'collateral photo exception', () async {
      seedV10Database(dbFile);

      // Opening the database runs the migration. It must not throw.
      final db = openWithDeviceSemantics(dbFile);
      addTearDown(() async => db.close());

      final items = await db.select(db.collateralItems).get();
      expect(items, hasLength(3));
      expect(items.every((i) => i.shopId == 'shop-v10'), isTrue);
    });

    test('preserves every collateral item and its credit binding', () async {
      seedV10Database(dbFile);

      final db = openWithDeviceSemantics(dbFile);
      addTearDown(() async => db.close());

      final items = await db.select(db.collateralItems).get();
      expect(items, hasLength(3));

      final bound = items.where((i) => i.creditId != null).toList();
      expect(bound, hasLength(2));
      expect(bound.every((i) => i.creditId == 'credit-v10'), isTrue,
          reason: 'The pledged items must still reference their agreement.');

      final gold = await (db.select(db.collateralItems)
            ..where((i) => i.id.equals('coll-v10-a')))
          .getSingle();
      expect(gold.itemReferenceId, equals('COLL-V10-A'));
      expect(gold.category, equals('gold'));
      expect(gold.description, equals('22K gold necklace'));
      expect(gold.conditionGrade, equals('Good'));
      expect(gold.weightMilligrams, equals(5500));
      expect(gold.estimatedValueCents, equals(1500000));
      expect(gold.custodyStatus, equals('in_custody'));
      expect(gold.photoUri, equals('/photos/coll-a.jpg'));
      expect(gold.photoHash, equals('hash-coll-a'));

      // A pre-v11 custody state must survive the rebuild unchanged.
      final held = await (db.select(db.collateralItems)
            ..where((i) => i.id.equals('coll-v10-c')))
          .getSingle();
      expect(held.custodyStatus, equals('exception_held'));
    });

    test('preserves the populated collateral photo exception rows', () async {
      seedV10Database(dbFile);

      final db = openWithDeviceSemantics(dbFile);
      addTearDown(() async => db.close());

      final exceptions =
          await db.select(db.collateralPhotoExceptions).get();
      expect(exceptions, hasLength(2));

      final first = await (db.select(db.collateralPhotoExceptions)
            ..where((e) => e.id.equals('cpe-v10-a')))
          .getSingle();
      expect(first.collateralItemId, equals('coll-v10-a'),
          reason: 'The child row must still reference its collateral item.');
      expect(first.requestReason, equals('Camera hardware malfunction.'));
      expect(first.status, equals('pending_owner_approval'));
      expect(first.requestedByUserId, equals('user-v10'));
    });

    test('preserves customer, credit and audit/sync records', () async {
      seedV10Database(dbFile);

      final db = openWithDeviceSemantics(dbFile);
      addTearDown(() async => db.close());

      final customer = await (db.select(db.customers)
            ..where((c) => c.nic.equals('198512345678')))
          .getSingle();
      expect(customer.id, equals(1),
          reason: 'Legacy TEXT ids are remapped to rowids during v20.');
      expect(customer.fullName, equals('V10 Customer'));
      expect(customer.nic, equals('198512345678'));

      final credit = await (db.select(db.credits)
            ..where((l) => l.id.equals('credit-v10')))
          .getSingle();
      expect(credit.principalCents, equals(500000));
      expect(credit.balanceCents, equals(500000));
      expect(credit.status, equals('active'));
      expect(credit.workflowStatus, equals('disbursed'),
          reason: 'Credits that predate the disbursement workflow are backfilled '
              'to "disbursed" by the schema version 12 step.');

      final syncRows = await db.select(db.syncQueue).get();
      expect(syncRows, hasLength(2));
      expect(
        syncRows.map((r) => r.actionType),
        containsAll(<String>['create_customer', 'create_credit']),
      );
    });

    test('creates the story 3.4 custody and discrepancy tables', () async {
      seedV10Database(dbFile);

      final db = openWithDeviceSemantics(dbFile);
      addTearDown(() async => db.close());

      // The tables are created by the schema version 11 step.
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name IN ('collateral_custody_events', 'collateral_discrepancies');",
          )
          .get();
      expect(tables.map((r) => r.read<String>('name')),
          containsAll(<String>['collateral_custody_events', 'collateral_discrepancies']));

      // ... and they accept rows that reference the rebuilt collateral table.
      await db.into(db.collateralCustodyEvents).insert(
        CollateralCustodyEventsCompanion.insert(
          id: 'cce-v10-new',
          shopId: 'shop-v10',
          collateralItemId: 'coll-v10-a',
          reportedByUserId: 'user-v10',
          previousStatus: 'in_custody',
          newStatus: 'handover_requested',
          reason: 'Customer requested release',
          createdAt: DateTime.now().toUtc(),
        ),
      );
      expect(await db.select(db.collateralCustodyEvents).get(), hasLength(1));
    });

    test('reopens successfully at the current schema version', () async {
      seedV10Database(dbFile);

      final first = openWithDeviceSemantics(dbFile);
      await first.select(first.collateralItems).get();
      await first.close();

      expect(readUserVersion(dbFile), equals(22));

      final second = openWithDeviceSemantics(dbFile);
      addTearDown(() async => second.close());

      expect(second.schemaVersion, equals(22));
      final item = await (second.select(second.collateralItems)
            ..where((c) => c.id.equals('coll-v10-a')))
          .getSingle();
      expect(item.creditId, equals('credit-v10'),
          reason: 'The child reference must survive a full close/reopen cycle.');

      final exception = await (second.select(second.collateralPhotoExceptions)
            ..where((e) => e.id.equals('cpe-v10-a')))
          .getSingle();
      expect(exception.collateralItemId, equals('coll-v10-a'));
    });

    test('a second launch does not re-run the migration', () async {
      seedV10Database(dbFile);

      final first = openWithDeviceSemantics(dbFile);
      // Force the database open so the migration runs.
      expect(await first.select(first.collateralItems).get(), hasLength(3));
      await first.close();

      expect(readUserVersion(dbFile), equals(22),
          reason: 'Drift must record the new schema version after the '
              'migration committed.');

      final second = openWithDeviceSemantics(dbFile);
      addTearDown(() async => second.close());

      expect(await second.select(second.collateralItems).get(), hasLength(3));
      expect(
          await second.select(second.collateralPhotoExceptions).get(),
          hasLength(2));
      expect(readUserVersion(dbFile), equals(22));
    });

    test('repairs a database left half-migrated by a failed attempt',
        () async {
      seedV10Database(dbFile, withOrphanStagingTable: true);

      final db = openWithDeviceSemantics(dbFile);
      addTearDown(() async => db.close());

      // The orphan staging table from the failed attempt is gone ...
      final staging = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = '_collateral_items_v11';",
          )
          .get();
      expect(staging, isEmpty);

      // ... and the authoritative rows were migrated, not lost.
      expect(await db.select(db.collateralItems).get(), hasLength(3));
      expect(
          await db.select(db.collateralPhotoExceptions).get(), hasLength(2));
    });

    test('leaves foreign-key enforcement active after the migration',
        () async {
      seedV10Database(dbFile);

      final db = openWithDeviceSemantics(dbFile);
      addTearDown(() async => db.close());

      final enabled = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(enabled.read<bool>('foreign_keys'), isTrue,
          reason: 'The migration must not leave the connection without foreign '
              'key enforcement.');

      // A photo exception that points at a non-existent item must be refused.
      await expectLater(
        db.into(db.collateralPhotoExceptions).insert(
          CollateralPhotoExceptionsCompanion.insert(
            id: 'cpe-dangling',
            shopId: 'shop-v10',
            collateralItemId: 'coll-does-not-exist',
            requestedByUserId: 'user-v10',
            requestReason: 'Dangling reference',
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ),
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test('leaves no dangling foreign-key reference behind', () async {
      seedV10Database(dbFile);

      final db = openWithDeviceSemantics(dbFile);
      addTearDown(() async => db.close());

      final violations = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violations, isEmpty,
          reason: 'The rebuilt table must not leave dangling references.');
    });

    test('produces the same collateral_items schema as a fresh installation',
        () async {
      seedV10Database(dbFile);
      final upgraded = openWithDeviceSemantics(dbFile);
      await upgraded.select(upgraded.collateralItems).get();
      final upgradedSchema = await _describeTable(upgraded, 'collateral_items');
      await upgraded.close();

      // A brand new database is created straight at the current schema version.
      final freshFile = File(p.join(tempDir.path, 'fresh.sqlite'));
      final fresh = openWithDeviceSemantics(freshFile);
      addTearDown(() async => fresh.close());
      await fresh.select(fresh.collateralItems).get();

      expect(
        upgradedSchema,
        equals(await _describeTable(fresh, 'collateral_items')),
        reason: 'An upgraded database must end up with the same columns, '
            'foreign keys and indexes as a freshly installed one.',
      );
    });
  });
}

/// Reads `PRAGMA user_version` straight from the database file, which is what
/// the next launch of the application will use to decide whether a migration
/// is required.
int readUserVersion(File file) {
  final raw = sqlite.sqlite3.open(file.path);
  try {
    return raw.select('PRAGMA user_version').first.values.first as int;
  } finally {
    raw.close();
  }
}

/// Captures the columns, foreign keys and indexes of [tableName] in a form
/// that can be compared between two databases.
Future<List<String>> _describeTable(AppDatabase db, String tableName) async {
  final columns = await db.customSelect('PRAGMA table_info("$tableName")').get();
  final foreignKeys =
      await db.customSelect('PRAGMA foreign_key_list("$tableName")').get();
  final indexes = await db.customSelect('PRAGMA index_list("$tableName")').get();

  final columnRows = columns
      .map((r) => '${r.read<String>('name')}:${r.read<String>('type')}:'
          'notnull=${r.read<int>('notnull')}:pk=${r.read<int>('pk')}:'
          'default=${r.readNullable<String>('dflt_value')}')
      .toList()
    ..sort();

  final foreignKeyRows = foreignKeys
      .map((r) => '${r.read<String>('from')}->'
          '${r.read<String>('table')}.${r.read<String>('to')}:'
          'on_delete=${r.read<String>('on_delete')}')
      .toList()
    ..sort();

  final indexRows = indexes
      .map((r) => '${r.read<String>('name')}:unique=${r.read<int>('unique')}:'
          'origin=${r.read<String>('origin')}')
      .toList()
    ..sort();

  return [...columnRows, ...foreignKeyRows, ...indexRows];
}

/// Creates a faithful version 10 database on disk, exactly as a device would
/// hold it after Stories 3.1 and 3.2 shipped: the real foreign keys, the
/// pre-v11 custody state vocabulary, a credit with pledged collateral bound to
/// it, populated collateral photo exceptions referencing that collateral, and
/// local audit/sync records.
void seedV10Database(File file, {bool withOrphanStagingTable = false}) {
  final db = sqlite.sqlite3.open(file.path);
  db.execute('''
    CREATE TABLE "shops" (
      "id" TEXT NOT NULL PRIMARY KEY,
      "name" TEXT NOT NULL,
      "currency_code" TEXT NOT NULL DEFAULT 'LKR',
      "timezone" TEXT NOT NULL DEFAULT 'Asia/Colombo',
      "business_address" TEXT,
      "contact_phone" TEXT,
      "contact_email" TEXT,
      "registration_number" TEXT,
      "logo_uri" TEXT,
      "receipt_header_notes" TEXT,
      "receipt_footer_notes" TEXT,
      "created_at" INTEGER NOT NULL,
      "updated_at" INTEGER NOT NULL
    );
    CREATE TABLE "app_users" (
      "id" TEXT NOT NULL PRIMARY KEY,
      "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
      "username" TEXT NOT NULL,
      "full_name" TEXT NOT NULL,
      "role" TEXT NOT NULL,
      "is_active" INTEGER NOT NULL DEFAULT 1,
      "session_version" INTEGER NOT NULL DEFAULT 1,
      "permissions" TEXT,
      "password_hash" TEXT,
      "created_at" INTEGER NOT NULL,
      "updated_at" INTEGER NOT NULL
    );
    CREATE TABLE "sync_queue" (
      "id" TEXT NOT NULL PRIMARY KEY,
      "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
      "idempotency_key" TEXT NOT NULL,
      "entity_type" TEXT NOT NULL,
      "entity_id" TEXT NOT NULL,
      "action_type" TEXT NOT NULL,
      "payload_json" TEXT NOT NULL,
      "status" TEXT NOT NULL DEFAULT 'pending_server_ack',
      "retry_count" INTEGER NOT NULL DEFAULT 0,
      "last_error" TEXT,
      "created_at" INTEGER NOT NULL,
      "updated_at" INTEGER,
      UNIQUE ("shop_id", "idempotency_key")
    );
    CREATE UNIQUE INDEX "idx_sync_queue_idempotency" ON "sync_queue" ("shop_id", "idempotency_key");
    CREATE TABLE "customers" (
      "id" TEXT NOT NULL PRIMARY KEY,
      "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
      "full_name" TEXT NOT NULL,
      "nic" TEXT NOT NULL,
      "phone" TEXT NOT NULL,
      "address" TEXT NOT NULL,
      "photo_uri" TEXT,
      "photo_hash" TEXT,
      "created_at" INTEGER NOT NULL,
      "updated_at" INTEGER NOT NULL
    );
    CREATE TABLE "customer_photo_exceptions" (
      "id" TEXT NOT NULL PRIMARY KEY,
      "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
      "target_customer_id" TEXT NOT NULL,
      "customer_nic" TEXT NOT NULL,
      "requested_by_user_id" TEXT NOT NULL REFERENCES "app_users" ("id") ON DELETE RESTRICT,
      "request_reason" TEXT NOT NULL,
      "status" TEXT NOT NULL DEFAULT 'pending_owner_approval',
      "reviewed_by_user_id" TEXT REFERENCES "app_users" ("id") ON DELETE RESTRICT,
      "review_notes" TEXT,
      "reviewed_at" INTEGER,
      "created_at" INTEGER NOT NULL,
      "updated_at" INTEGER NOT NULL
    );
    CREATE TABLE "credits" (
      "id" TEXT NOT NULL PRIMARY KEY,
      "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
      "customer_id" TEXT NOT NULL REFERENCES "customers" ("id") ON DELETE RESTRICT,
      "principal_cents" INTEGER NOT NULL,
      "balance_cents" INTEGER NOT NULL,
      "status" TEXT NOT NULL DEFAULT 'active',
      "due_date" INTEGER NOT NULL,
      "created_at" INTEGER NOT NULL,
      "settled_at" INTEGER
    );
    CREATE TABLE "collateral_items" (
      "id" TEXT NOT NULL PRIMARY KEY,
      "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
      "customer_id" TEXT NOT NULL REFERENCES "customers" ("id") ON DELETE RESTRICT,
      "credit_id" TEXT REFERENCES "credits" ("id") ON DELETE RESTRICT,
      "item_reference_id" TEXT NOT NULL,
      "category" TEXT NOT NULL,
      "description" TEXT NOT NULL,
      "condition_grade" TEXT NOT NULL,
      "weight_milligrams" INTEGER NOT NULL,
      "estimated_value_cents" INTEGER NOT NULL,
      "photo_uri" TEXT,
      "photo_hash" TEXT,
      "custody_status" TEXT NOT NULL DEFAULT 'in_custody',
      "created_at" INTEGER NOT NULL,
      "updated_at" INTEGER NOT NULL,
      UNIQUE ("shop_id", "item_reference_id"),
      CHECK (weight_milligrams > 0),
      CHECK (estimated_value_cents >= 0),
      CHECK (category IN ('gold', 'electronics', 'valuables')),
      CHECK (custody_status IN ('in_custody', 'returned', 'exception_held'))
    );
    CREATE TABLE "collateral_photo_exceptions" (
      "id" TEXT NOT NULL PRIMARY KEY,
      "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
      "collateral_item_id" TEXT NOT NULL REFERENCES "collateral_items" ("id") ON DELETE RESTRICT,
      "requested_by_user_id" TEXT NOT NULL REFERENCES "app_users" ("id") ON DELETE RESTRICT,
      "request_reason" TEXT NOT NULL,
      "status" TEXT NOT NULL DEFAULT 'pending_owner_approval',
      "reviewed_by_user_id" TEXT REFERENCES "app_users" ("id") ON DELETE RESTRICT,
      "review_notes" TEXT,
      "reviewed_at" INTEGER,
      "created_at" INTEGER NOT NULL,
      "updated_at" INTEGER NOT NULL,
      CHECK (status IN ('pending_owner_approval', 'approved', 'rejected', 'consumed'))
    );
    PRAGMA user_version = 10;
  ''');

  const now = 1791000000;
  db.execute('''
    INSERT INTO "shops" ("id", "name", "currency_code", "timezone", "created_at", "updated_at")
    VALUES ('shop-v10', 'V10 Shop', 'LKR', 'Asia/Colombo', $now, $now);
  ''');
  db.execute('''
    INSERT INTO "app_users" ("id", "shop_id", "username", "full_name", "role", "is_active", "session_version", "permissions", "password_hash", "created_at", "updated_at")
    VALUES ('user-v10', 'shop-v10', 'v10.staff', 'V10 Staff', 'manager', 1, 1, NULL, NULL, $now, $now);
  ''');
  db.execute('''
    INSERT INTO "customers" ("id", "shop_id", "full_name", "nic", "phone", "address", "created_at", "updated_at")
    VALUES ('cust-v10', 'shop-v10', 'V10 Customer', '198512345678', '+94 77 123 4567', '45 Park Road', $now, $now);
  ''');
  db.execute('''
    INSERT INTO "customer_photo_exceptions" ("id", "shop_id", "target_customer_id", "customer_nic", "requested_by_user_id", "request_reason", "status", "created_at", "updated_at")
    VALUES ('cpe-cust-v10', 'shop-v10', 'cust-v10', '198512345678', 'user-v10', 'Customer photo missing', 'pending_owner_approval', $now, $now);
  ''');
  db.execute('''
    INSERT INTO "credits" ("id", "shop_id", "customer_id", "principal_cents", "balance_cents", "status", "due_date", "created_at")
    VALUES ('credit-v10', 'shop-v10', 'cust-v10', 500000, 500000, 'active', $now, $now);
  ''');
  db.execute('''
    INSERT INTO "collateral_items" ("id", "shop_id", "customer_id", "credit_id", "item_reference_id", "category", "description", "condition_grade", "weight_milligrams", "estimated_value_cents", "photo_uri", "photo_hash", "custody_status", "created_at", "updated_at")
    VALUES ('coll-v10-a', 'shop-v10', 'cust-v10', 'credit-v10', 'COLL-V10-A', 'gold', '22K gold necklace', 'Good', 5500, 1500000, '/photos/coll-a.jpg', 'hash-coll-a', 'in_custody', $now, $now);
  ''');
  db.execute('''
    INSERT INTO "collateral_items" ("id", "shop_id", "customer_id", "credit_id", "item_reference_id", "category", "description", "condition_grade", "weight_milligrams", "estimated_value_cents", "photo_uri", "photo_hash", "custody_status", "created_at", "updated_at")
    VALUES ('coll-v10-b', 'shop-v10', 'cust-v10', 'credit-v10', 'COLL-V10-B', 'electronics', 'Laptop', 'Fair', 1200, 400000, NULL, NULL, 'in_custody', $now, $now);
  ''');
  db.execute('''
    INSERT INTO "collateral_items" ("id", "shop_id", "customer_id", "credit_id", "item_reference_id", "category", "description", "condition_grade", "weight_milligrams", "estimated_value_cents", "photo_uri", "photo_hash", "custody_status", "created_at", "updated_at")
    VALUES ('coll-v10-c', 'shop-v10', 'cust-v10', NULL, 'COLL-V10-C', 'valuables', 'Watch', 'Like New', 300, 900000, NULL, NULL, 'exception_held', $now, $now);
  ''');
  // The populated child rows that trip the ON DELETE RESTRICT action.
  db.execute('''
    INSERT INTO "collateral_photo_exceptions" ("id", "shop_id", "collateral_item_id", "requested_by_user_id", "request_reason", "status", "created_at", "updated_at")
    VALUES ('cpe-v10-a', 'shop-v10', 'coll-v10-a', 'user-v10', 'Camera hardware malfunction.', 'pending_owner_approval', $now, $now);
  ''');
  db.execute('''
    INSERT INTO "collateral_photo_exceptions" ("id", "shop_id", "collateral_item_id", "requested_by_user_id", "request_reason", "status", "created_at", "updated_at")
    VALUES ('cpe-v10-b', 'shop-v10', 'coll-v10-b', 'user-v10', 'Photo blur cannot be retaken.', 'approved', $now, $now);
  ''');
  db.execute('''
    INSERT INTO "sync_queue" ("id", "shop_id", "idempotency_key", "entity_type", "entity_id", "action_type", "payload_json", "status", "retry_count", "created_at")
    VALUES ('sync-v10-a', 'shop-v10', '00000000-0000-4000-8000-000000000011', 'customer', 'cust-v10', 'create_customer', '{"auditCategory":1}', 'pending_server_ack', 0, $now);
  ''');
  db.execute('''
    INSERT INTO "sync_queue" ("id", "shop_id", "idempotency_key", "entity_type", "entity_id", "action_type", "payload_json", "status", "retry_count", "created_at")
    VALUES ('sync-v10-b', 'shop-v10', '00000000-0000-4000-8000-000000000012', 'credit', 'credit-v10', 'create_credit', '{"auditCategory":2}', 'pending_server_ack', 0, $now);
  ''');

  if (withOrphanStagingTable) {
    // Exactly the state a device is left in when the rebuild fails with
    // foreign-key enforcement enabled: the staging table survives, the
    // authoritative "collateral_items" table is still intact.
    db.execute('''
      CREATE TABLE "_collateral_items_v11" (
        "id" TEXT NOT NULL PRIMARY KEY,
        "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
        "customer_id" TEXT NOT NULL REFERENCES "customers" ("id") ON DELETE RESTRICT,
        "credit_id" TEXT REFERENCES "credits" ("id") ON DELETE RESTRICT,
        "item_reference_id" TEXT NOT NULL,
        "category" TEXT NOT NULL,
        "description" TEXT NOT NULL,
        "condition_grade" TEXT NOT NULL,
        "weight_milligrams" INTEGER NOT NULL,
        "estimated_value_cents" INTEGER NOT NULL,
        "photo_uri" TEXT,
        "photo_hash" TEXT,
        "custody_status" TEXT NOT NULL DEFAULT 'in_custody',
        "created_at" INTEGER NOT NULL,
        "updated_at" INTEGER NOT NULL,
        UNIQUE ("shop_id", "item_reference_id")
      );
    ''');
    db.execute('''
      INSERT INTO "_collateral_items_v11" ("id", "shop_id", "customer_id", "credit_id", "item_reference_id", "category", "description", "condition_grade", "weight_milligrams", "estimated_value_cents", "photo_uri", "photo_hash", "custody_status", "created_at", "updated_at")
      VALUES ('coll-v10-a', 'shop-v10', 'cust-v10', 'credit-v10', 'COLL-V10-A', 'gold', '22K gold necklace', 'Good', 5500, 1500000, '/photos/coll-a.jpg', 'hash-coll-a', 'in_custody', $now, $now);
    ''');
  }

  db.close();
}



