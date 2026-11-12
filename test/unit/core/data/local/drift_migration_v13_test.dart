import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:credit_system/core/data/local/app_database.dart';

/// Regression coverage for the schema version 12 -> 13 rebuild of the `credits`
/// table (Story 4.3).
///
/// The rebuild is destructive to the identity of the `credits` table, and
/// `collateral_items.credit_id` references `credits(id)` with `ON DELETE
/// RESTRICT`. These tests exercise the migration the way a *device* runs it:
///
/// - a persistent database file (not an in-memory database),
/// - foreign-key enforcement switched on in the connection setup callback,
///   exactly as `AppDatabaseConnection.openSandboxedConnection` does,
/// - a version 12 schema that carries the real foreign keys.
///
/// Without foreign-key enforcement the rebuild's `DROP TABLE "credits"` never
/// trips the `RESTRICT` action, so a migration test that omits it passes while
/// the same migration fails on a device.
void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('credit_system_v13_migration');
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

  group('schema version 12 -> 13 rebuild of the credits table', () {
    test(
        'completes with foreign-key enforcement enabled and populated child '
        'rows', () async {
      seedV12Database(dbFile);

      // Opening the database runs the migration. It must not throw.
      final db = openWithDeviceSemantics(dbFile);
      addTearDown(() async => db.close());

      final credit = await (db.select(db.credits)
            ..where((l) => l.id.equals('credit-v12')))
          .getSingle();
      expect(credit.principalCents, equals(500000));
      expect(credit.balanceCents, equals(500000));
      expect(credit.status, equals('active'));
      expect(credit.workflowStatus, equals('pending_disbursement'));
      expect(credit.termPresetDays, isNull);
      expect(credit.customDueDate, isNull);
      expect(credit.disbursedAt, isNull);
      expect(credit.disbursedByUserId, isNull);
      expect(credit.cancelledAt, isNull);
      expect(credit.cancellationReason, isNull);
    });

    test('keeps every collateral item bound to its agreement', () async {
      seedV12Database(dbFile);

      final db = openWithDeviceSemantics(dbFile);
      addTearDown(() async => db.close());

      final items = await db.select(db.collateralItems).get();
      expect(items, hasLength(3));

      final bound = items.where((i) => i.creditId != null).toList();
      expect(bound, hasLength(2),
          reason: 'Both pledged items must still reference their agreement.');
      expect(
        bound.every((i) => i.creditId == 'credit-v12'),
        isTrue,
        reason: 'Rebuilding the parent table must keep the child rows bound.',
      );

      final unbound = items.firstWhere((i) => i.creditId == null);
      expect(unbound.id, equals('coll-v12-unbound'));
    });

    test('preserves existing customer, collateral, credit and audit records',
        () async {
      seedV12Database(dbFile);

      final db = openWithDeviceSemantics(dbFile);
      addTearDown(() async => db.close());

      // Customer data. The legacy TEXT id is remapped to the rowid (1).
      final customer = await (db.select(db.customers)
            ..where((c) => c.nic.equals('198512345678')))
          .getSingle();
      expect(customer.id, equals(1));
      expect(customer.fullName, equals('V12 Customer'));
      expect(customer.nic, equals('198512345678'));
      expect(customer.phone, equals('+94 77 123 4567'));

      // Staff data.
      final user = await (db.select(db.appUsers)
            ..where((u) => u.id.equals('user-v12')))
          .getSingle();
      expect(user.username, equals('v12.staff'));
      expect(user.role, equals('manager'));

      // Credit data.
      expect(await db.select(db.credits).get(), hasLength(1));

      // Collateral data.
      expect(await db.select(db.collateralItems).get(), hasLength(3));

      // Grandchild rows: the collateral photo exception and the custody event
      // both reference a collateral item, which references the credit.
      expect(await db.select(db.collateralPhotoExceptions).get(), hasLength(1));
      expect(await db.select(db.collateralCustodyEvents).get(), hasLength(1));

      // Local audit/sync records.
      final syncRows = await db.select(db.syncQueue).get();
      expect(syncRows, hasLength(2));
      expect(
        syncRows.map((r) => r.actionType),
        containsAll(<String>['create_credit', 'confirm_credit_disbursement']),
      );
      expect(syncRows.firstWhere((r) => r.actionType == 'create_credit').entityId,
          equals('credit-v12'));
    });

    test('reopens successfully at the current schema version', () async {
      seedV12Database(dbFile);

      final first = openWithDeviceSemantics(dbFile);
      await (first.select(first.credits)..where((l) => l.id.equals('credit-v12')))
          .getSingle();
      await first.close();

      // The migration must have recorded the new schema version on disk.
      expect(readUserVersion(dbFile), equals(22));

      // Second launch on the same file: the migration must not run again and
      // the database must open cleanly.
      final second = openWithDeviceSemantics(dbFile);
      addTearDown(() async => second.close());

      expect(second.schemaVersion, equals(22));
      final credit = await (second.select(second.credits)
            ..where((l) => l.id.equals('credit-v12')))
          .getSingle();
      expect(credit.balanceCents, equals(500000));

      final item = await (second.select(second.collateralItems)
            ..where((c) => c.id.equals('coll-v12-a')))
          .getSingle();
      expect(item.creditId, equals('credit-v12'),
          reason: 'The child reference must survive a full close/reopen cycle.');
    });

    test('a second launch does not re-run the migration', () async {
      seedV12Database(dbFile);

      final first = openWithDeviceSemantics(dbFile);
      // Force the database open so the migration runs.
      expect(await first.select(first.credits).get(), hasLength(1));
      await first.close();

      expect(readUserVersion(dbFile), equals(22),
          reason: 'Drift must record the new schema version after the '
              'migration committed.');

      final second = openWithDeviceSemantics(dbFile);
      addTearDown(() async => second.close());

      expect(await second.select(second.credits).get(), hasLength(1));
      expect(await second.select(second.collateralItems).get(), hasLength(3));
      expect(readUserVersion(dbFile), equals(22));
    });

    test('repairs a database left half-migrated by a failed attempt',
        () async {
      seedV12Database(dbFile, withOrphanStagingTable: true);

      final db = openWithDeviceSemantics(dbFile);
      addTearDown(() async => db.close());

      // The orphan staging table from the failed attempt is gone ...
      final staging = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = '_credits_v13';",
          )
          .get();
      expect(staging, isEmpty);

      // ... and the authoritative rows were migrated, not lost.
      final credit = await (db.select(db.credits)
            ..where((l) => l.id.equals('credit-v12')))
          .getSingle();
      expect(credit.balanceCents, equals(500000));
      expect(await db.select(db.collateralItems).get(), hasLength(3));
    });

    test('leaves foreign-key enforcement active after the migration',
        () async {
      seedV12Database(dbFile);

      final db = openWithDeviceSemantics(dbFile);
      addTearDown(() async => db.close());

      final enabled = await db
          .customSelect('PRAGMA foreign_keys')
          .getSingle();
      expect(enabled.read<bool>('foreign_keys'), isTrue,
          reason: 'The migration must not leave the connection without foreign '
              'key enforcement.');

      // A child row that points at a non-existent agreement must be refused.
      await expectLater(
        db.into(db.collateralItems).insert(CollateralItemsCompanion.insert(
          id: 'coll-dangling',
          shopId: 'shop-v12',
          customerId: 1,
          creditId: const Value('credit-does-not-exist'),
          itemReferenceId: 'COLL-DANGLING',
          category: 'gold',
          description: 'Dangling item',
          conditionGrade: 'Good',
          weightMilligrams: 1000,
          estimatedValueCents: 1000,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        )),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test('leaves no dangling foreign-key reference behind', () async {
      seedV12Database(dbFile);

      final db = openWithDeviceSemantics(dbFile);
      addTearDown(() async => db.close());

      final violations = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violations, isEmpty,
          reason: 'The rebuilt table must not leave dangling references.');
    });

    test('produces the same credits schema as a fresh installation', () async {
      seedV12Database(dbFile);
      final upgraded = openWithDeviceSemantics(dbFile);
      await (upgraded.select(upgraded.credits)).get();
      final upgradedSchema = await _describeTable(upgraded, 'credits');
      await upgraded.close();

      // A brand new database is created straight at the current schema version.
      final freshFile = File(p.join(tempDir.path, 'fresh.sqlite'));
      final fresh = openWithDeviceSemantics(freshFile);
      addTearDown(() async => fresh.close());
      await (fresh.select(fresh.credits)).get();

      expect(
        upgradedSchema,
        equals(await _describeTable(fresh, 'credits')),
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

/// Creates a faithful version 12 database on disk, exactly as a device would
/// hold it after Stories 4.1 and 4.2 shipped: the real foreign keys, a credit
/// with pledged collateral bound to it, a grandchild photo-exception and
/// custody-event row, and local audit/sync records.
void seedV12Database(File file, {bool withOrphanStagingTable = false}) {
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
    CREATE TABLE "credits" (
      "id" TEXT NOT NULL PRIMARY KEY,
      "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
      "customer_id" TEXT NOT NULL REFERENCES "customers" ("id") ON DELETE RESTRICT,
      "principal_cents" INTEGER NOT NULL,
      "balance_cents" INTEGER NOT NULL,
      "status" TEXT NOT NULL DEFAULT 'active',
      "workflow_status" TEXT NOT NULL DEFAULT 'pending_disbursement',
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
      UNIQUE ("shop_id", "item_reference_id")
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
    CREATE TABLE "collateral_custody_events" (
      "id" TEXT NOT NULL PRIMARY KEY,
      "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
      "collateral_item_id" TEXT NOT NULL REFERENCES "collateral_items" ("id") ON DELETE RESTRICT,
      "reported_by_user_id" TEXT NOT NULL REFERENCES "app_users" ("id") ON DELETE RESTRICT,
      "previous_status" TEXT NOT NULL,
      "new_status" TEXT NOT NULL,
      "reason" TEXT NOT NULL,
      "created_at" INTEGER NOT NULL
    );
    PRAGMA user_version = 12;
  ''');

  const now = 1792000000;
  db.execute('''
    INSERT INTO "shops" ("id", "name", "currency_code", "timezone", "created_at", "updated_at")
    VALUES ('shop-v12', 'V12 Shop', 'LKR', 'Asia/Colombo', $now, $now);
  ''');
  db.execute('''
    INSERT INTO "app_users" ("id", "shop_id", "username", "full_name", "role", "is_active", "session_version", "permissions", "password_hash", "created_at", "updated_at")
    VALUES ('user-v12', 'shop-v12', 'v12.staff', 'V12 Staff', 'manager', 1, 1, NULL, NULL, $now, $now);
  ''');
  db.execute('''
    INSERT INTO "customers" ("id", "shop_id", "full_name", "nic", "phone", "address", "created_at", "updated_at")
    VALUES ('cust-v12', 'shop-v12', 'V12 Customer', '198512345678', '+94 77 123 4567', '45 Park Road', $now, $now);
  ''');
  db.execute('''
    INSERT INTO "credits" ("id", "shop_id", "customer_id", "principal_cents", "balance_cents", "status", "workflow_status", "due_date", "created_at")
    VALUES ('credit-v12', 'shop-v12', 'cust-v12', 500000, 500000, 'active', 'pending_disbursement', $now, $now);
  ''');
  db.execute('''
    INSERT INTO "collateral_items" ("id", "shop_id", "customer_id", "credit_id", "item_reference_id", "category", "description", "condition_grade", "weight_milligrams", "estimated_value_cents", "custody_status", "created_at", "updated_at")
    VALUES ('coll-v12-a', 'shop-v12', 'cust-v12', 'credit-v12', 'COLL-V12-A', 'gold', '22K gold necklace', 'Good', 5500, 1500000, 'in_custody', $now, $now);
  ''');
  db.execute('''
    INSERT INTO "collateral_items" ("id", "shop_id", "customer_id", "credit_id", "item_reference_id", "category", "description", "condition_grade", "weight_milligrams", "estimated_value_cents", "custody_status", "created_at", "updated_at")
    VALUES ('coll-v12-b', 'shop-v12', 'cust-v12', 'credit-v12', 'COLL-V12-B', 'electronics', 'Laptop', 'Fair', 1200, 400000, 'in_custody', $now, $now);
  ''');
  db.execute('''
    INSERT INTO "collateral_items" ("id", "shop_id", "customer_id", "credit_id", "item_reference_id", "category", "description", "condition_grade", "weight_milligrams", "estimated_value_cents", "custody_status", "created_at", "updated_at")
    VALUES ('coll-v12-unbound', 'shop-v12', 'cust-v12', NULL, 'COLL-V12-C', 'valuables', 'Watch', 'Like New', 300, 900000, 'in_custody', $now, $now);
  ''');
  db.execute('''
    INSERT INTO "collateral_photo_exceptions" ("id", "shop_id", "collateral_item_id", "requested_by_user_id", "request_reason", "status", "created_at", "updated_at")
    VALUES ('cpe-v12', 'shop-v12', 'coll-v12-a', 'user-v12', 'Camera failure', 'pending_owner_approval', $now, $now);
  ''');
  db.execute('''
    INSERT INTO "collateral_custody_events" ("id", "shop_id", "collateral_item_id", "reported_by_user_id", "previous_status", "new_status", "reason", "created_at")
    VALUES ('cce-v12', 'shop-v12', 'coll-v12-a', 'user-v12', 'in_custody', 'handover_requested', 'Customer requested release', $now);
  ''');
  db.execute('''
    INSERT INTO "sync_queue" ("id", "shop_id", "idempotency_key", "entity_type", "entity_id", "action_type", "payload_json", "status", "retry_count", "created_at")
    VALUES ('sync-v12-a', 'shop-v12', '00000000-0000-4000-8000-000000000001', 'credit', 'credit-v12', 'create_credit', '{"auditCategory":2}', 'pending_server_ack', 0, $now);
  ''');
  db.execute('''
    INSERT INTO "sync_queue" ("id", "shop_id", "idempotency_key", "entity_type", "entity_id", "action_type", "payload_json", "status", "retry_count", "created_at")
    VALUES ('sync-v12-b', 'shop-v12', '00000000-0000-4000-8000-000000000002', 'credit', 'credit-v12', 'confirm_credit_disbursement', '{"auditCategory":4}', 'pending_server_ack', 0, $now);
  ''');

  if (withOrphanStagingTable) {
    // Exactly the state a device is left in when the rebuild fails with
    // foreign-key enforcement enabled: the staging table survives, the
    // authoritative "credits" table is still intact.
    db.execute('''
      CREATE TABLE "_credits_v13" (
        "id" TEXT NOT NULL PRIMARY KEY,
        "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
        "customer_id" TEXT NOT NULL REFERENCES "customers" ("id") ON DELETE RESTRICT,
        "principal_cents" INTEGER NOT NULL,
        "balance_cents" INTEGER NOT NULL,
        "status" TEXT NOT NULL DEFAULT 'active',
        "workflow_status" TEXT NOT NULL DEFAULT 'pending_disbursement',
        "term_preset_days" INTEGER,
        "custom_due_date" INTEGER,
        "disbursed_at" INTEGER,
        "disbursed_by_user_id" TEXT REFERENCES "app_users" ("id") ON DELETE RESTRICT,
        "cancelled_at" INTEGER,
        "cancellation_reason" TEXT,
        "due_date" INTEGER NOT NULL,
        "created_at" INTEGER NOT NULL,
        "settled_at" INTEGER
      );
    ''');
    db.execute('''
      INSERT INTO "_credits_v13" ("id", "shop_id", "customer_id", "principal_cents", "balance_cents", "status", "workflow_status", "due_date", "created_at")
      VALUES ('credit-v12', 'shop-v12', 'cust-v12', 500000, 500000, 'active', 'pending_disbursement', $now, $now);
    ''');
  }

  db.close();
}



