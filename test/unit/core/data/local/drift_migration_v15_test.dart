import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:credit_system/core/data/local/app_database.dart';

/// Regression coverage for the schema version 14 -> 15 rebuild of the `credits`
/// table (Story 4.4).
///
/// The rebuild adds the nullable `documentSnapshotId` TEXT column for the
/// document snapshot identifier at disbursement time. The column stores an
/// identifier only; a full immutable content snapshot remains pending decision
/// D4.4-03. SQLite cannot add a CHECK constraint in place, so the column is
/// added without table rebuild (ALTER TABLE ADD COLUMN).
///
/// These tests exercise the migration the way a *device* runs it:
///
/// - a persistent database file (not an in-memory database),
/// - foreign-key enforcement switched on in the connection setup callback,
///   exactly as `AppDatabaseConnection.openSandboxedConnection` does,
/// - a genuine version 14 schema that carries the Tier 1 CHECK constraints,
///   but **without** the `documentSnapshotId` column.
///
/// Ensure that after the upgrade:
/// - The schema version advances to 15.
/// - Existing credit records are preserved with `documentSnapshotId` = NULL.
/// - The column is readable and writable through the generated Drift API.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'credit_system_v15_migration',
    );
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

  /// Opens the database with Drift's migrations **disabled**, so that opening
  /// it cannot advance the schema version.
  ///
  /// This is what proves that a fixture is genuinely at a given schema
  /// version: the file is read exactly as it is, with nothing rewritten
  /// behind the scenes.
  AppDatabase openWithoutMigrations(File file) {
    final executor = NativeDatabase(
      file,
      setup: (db) => db.execute('PRAGMA foreign_keys = ON;'),
      enableMigrations: false,
    );
    return AppDatabase.forTesting(executor);
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

  /// Seeds a genuine version 14 database on disk. Creates the minimal schema
  /// required for the migration tests: shops, app_users, customers, and credits
  /// tables with their version-14 CHECK constraints. Other tables are created
  /// empty to avoid column/value count mismatches.
  void seedV14Database(File file) {
    final db = sqlite.sqlite3.open(file.path);
    db.execute('''\
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
      );''');
    db.execute('''\
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
      );''');
    db.execute('''\
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
      );''');
    db.execute('''\
      CREATE TABLE "credits" (
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
        "settled_at" INTEGER,
        CHECK (principal_cents >= 0),
        CHECK (balance_cents >= 0),
        CHECK (balance_cents <= principal_cents),
        CHECK (status IN ('active', 'overdue', 'settled', 'cancelled')),
        CHECK (status <> 'settled' OR settled_at IS NOT NULL),
        CHECK (status <> 'cancelled' OR (cancelled_at IS NOT NULL AND cancellation_reason IS NOT NULL AND length(trim(cancellation_reason)) > 0)),
        CHECK (workflow_status IN ('pending_disbursement', 'disbursed', 'cancelled')),
        CHECK (term_preset_days IS NULL OR term_preset_days IN (30, 60, 90)),
        CHECK (NOT (term_preset_days IS NOT NULL AND custom_due_date IS NOT NULL)),
        CHECK ((disbursed_at IS NULL) = (disbursed_by_user_id IS NULL))
      );''');
    db.execute('PRAGMA user_version = 14;');

    const now = 1793000000;
    db.execute('''\
      INSERT INTO "shops" ("id", "name", "currency_code", "timezone", "created_at", "updated_at")
      VALUES ('shop-v14', 'V14 Shop', 'LKR', 'Asia/Colombo', $now, $now);''');
    db.execute(
      '''\
      INSERT INTO "app_users" ("id", "shop_id", "username", "full_name", "role", "is_active", "session_version", "permissions", "password_hash", "created_at", "updated_at")
      VALUES ('user-v14', 'shop-v14', 'v14.staff', 'V14 Staff', 'manager', 1, 1, NULL, NULL, $now, $now);''',
    );
    db.execute(
      '''\
      INSERT INTO "customers" ("id", "shop_id", "full_name", "nic", "phone", "address", "created_at", "updated_at")
      VALUES ('cust-v14', 'shop-v14', 'V14 Customer', '198512345678', '+94 77 123 4567', '1 Main St', $now, $now);''',
    );
    // An agreement awaiting disbursement, with an agreed 30-day term.
    db.execute(
      '''\
      INSERT INTO "credits" ("id", "shop_id", "customer_id", "principal_cents", "balance_cents", "status", "workflow_status", "term_preset_days", "due_date", "created_at")
      VALUES ('credit-v14-pending', 'shop-v14', 'cust-v14', 500000, 500000, 'active', 'pending_disbursement', 30, $now, $now);''',
    );
    // An agreement whose cash was handed over, with a 60-day term and a
    // disbursement record.
    db.execute(
      '''\
      INSERT INTO "credits" ("id", "shop_id", "customer_id", "principal_cents", "balance_cents", "status", "workflow_status", "term_preset_days", "disbursed_at", "disbursed_by_user_id", "due_date", "created_at")
      VALUES ('credit-v14-disbursed', 'shop-v14', 'cust-v14', 750000, 750000, 'active', 'disbursed', 60, $now, 'user-v14', $now, $now);''',
    );
    // A legacy agreement that predates the disbursement workflow: backfilled to
    // 'disbursed' by the version 12 migration and therefore carrying no
    // disbursement record.
    db.execute(
      '''\
      INSERT INTO "credits" ("id", "shop_id", "customer_id", "principal_cents", "balance_cents", "status", "workflow_status", "due_date", "created_at")
      VALUES ('credit-v14-legacy', 'shop-v14', 'cust-v14', 250000, 250000, 'active', 'disbursed', $now, $now);''',
    );

    db.close();
  }

  group('schema version 14 -> 15 migration of the credits table', () {
    test('a genuine version 14 database stays at version 14 when it is reopened without an upgrade', () async {
      final file = File(p.join(tempDir.path, 'v14_no_migration.sqlite'));
      seedV14Database(file);

      expect(
        readUserVersion(file),
        equals(14),
        reason: 'The fixture must start as a genuine version 14 database.',
      );

      // Open the very same file with migrations disabled, so that nothing can
      // advance the schema version behind the scenes.
      final db = openWithoutMigrations(file);
      addTearDown(() async => db.close());

      // Read the credit row through raw sqlite (the typed Drift API expects the
      // `correctionPending` column which is absent from a genuine v14 file).
      final raw = sqlite.sqlite3.open(file.path);
      try {
        final rows = raw.select(
          'SELECT status FROM credits WHERE id = ?',
          ['credit-v14-pending'],
        );
        expect(rows.first.values.first, equals('active'));
      } finally {
        raw.close();
      }

      // The schema version on disk is untouched.
      expect(
        readUserVersion(file),
        equals(14),
        reason: 'Without a migration the database must stay at version 14.',
      );
    });

    test('a genuine version 14 database upgrades to version 15', () async {
      final file = File(p.join(tempDir.path, 'v14_to_v15.sqlite'));
      seedV14Database(file);

      expect(
        readUserVersion(file),
        equals(14),
        reason: 'The fixture must start as a genuine version 14 database.',
      );

      final db = openWithDeviceSemantics(file);
      addTearDown(() async => db.close());

      // Drift opens the database lazily, so the migration only runs once the
      // first query is issued.
      await (db.select(
        db.credits,
      )..where((l) => l.id.equals('credit-v14-pending'))).getSingle();

      expect(
        readUserVersion(file),
        equals(22),
        reason: 'Opening a version 14 database must migrate it to 15.',
      );
      expect(db.schemaVersion, equals(22));
    });

    test(
      'preserves the documentSnapshotId = NULL for existing records',
      () async {
        final file = File(p.join(tempDir.path, 'v15_snapshot_test.sqlite'));
        seedV14Database(file);

        final db = openWithDeviceSemantics(file);
        addTearDown(() async => db.close());

        await (db.select(
          db.credits,
        )..where((l) => l.id.equals('credit-v14-pending'))).getSingle();

        expect(readUserVersion(file), equals(22));

        // All existing credits must have documentSnapshotId = NULL.
        // The column is nullable with no default, so old rows get NULL automatically.
        final pending = await (db.select(
          db.credits,
        )..where((l) => l.id.equals('credit-v14-pending'))).getSingle();
        expect(
          pending.documentSnapshotId,
          isNull,
          reason: 'Pending credit must have documentSnapshotId = NULL.',
        );

        final disbursed = await (db.select(
          db.credits,
        )..where((l) => l.id.equals('credit-v14-disbursed'))).getSingle();
        expect(
          disbursed.documentSnapshotId,
          isNull,
          reason: 'Disbursed credit must have documentSnapshotId = NULL.',
        );

        final legacy = await (db.select(
          db.credits,
        )..where((l) => l.id.equals('credit-v14-legacy'))).getSingle();
        expect(
          legacy.documentSnapshotId,
          isNull,
          reason: 'Legacy credit must have documentSnapshotId = NULL.',
        );
      },
    );

    test('newly inserted credits can set documentSnapshotId', () async {
      final file = File(p.join(tempDir.path, 'v15_new_insert.sqlite'));
      seedV14Database(file);

      final db = openWithDeviceSemantics(file);
      addTearDown(() async => db.close());

      await (db.select(
        db.credits,
      )..where((l) => l.id.equals('credit-v14-pending'))).getSingle();

      expect(readUserVersion(file), equals(22));

      // Insert a new credit with a documentSnapshotId.
      await db
          .into(db.credits)
          .insert(
            CreditsCompanion.insert(
              id: 'credit-v15-new',
              shopId: 'shop-v14',
              customerId: 1,
              principalCents: 500000,
              balanceCents: 500000,
              status: Value('active'),
              workflowStatus: Value('pending_disbursement'),
              termPresetDays: Value(30),
              dueDate: DateTime.now().toUtc(),
              createdAt: DateTime.now().toUtc(),
              documentSnapshotId: Value('snap-2026-10-23-alpha'),
            ),
          );

      final inserted = await (db.select(
        db.credits,
      )..where((l) => l.id.equals('credit-v15-new'))).getSingle();
      expect(
        inserted.documentSnapshotId,
        equals('snap-2026-10-23-alpha'),
        reason: 'Newly inserted credit should persist the documentSnapshotId.',
      );
    });

    test('upgraded database functions correctly on reopening', () async {
      final file = File(p.join(tempDir.path, 'v15_reopen_test.sqlite'));
      seedV14Database(file);

      // First launch: Drift opens lazily, so issue a query to force the
      // migration to run before inspecting `user_version`.
      final first = openWithDeviceSemantics(file);
      addTearDown(() async => first.close());
      await (first.select(
        first.credits,
      )..where((l) => l.id.equals('credit-v14-pending'))).getSingle();

      // Verify the migration ran and persisted version 15 on disk.
      expect(readUserVersion(file), equals(22));

      await first.close();

      // Second launch: migration must not re-run; database must open cleanly.
      final second = openWithDeviceSemantics(file);
      addTearDown(() async => second.close());

      expect(second.schemaVersion, equals(22));
      expect(readUserVersion(file), equals(22));

      // Data must be intact after close/reopen.
      final credit = await (second.select(
        second.credits,
      )..where((l) => l.id.equals('credit-v14-pending'))).getSingle();
      expect(credit.balanceCents, equals(500000));
      expect(credit.termPresetDays, equals(30));
      expect(credit.documentSnapshotId, isNull);
    });
  });
}



