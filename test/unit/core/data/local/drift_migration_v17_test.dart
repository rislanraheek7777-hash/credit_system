import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:credit_system/core/data/local/app_database.dart';

/// Regression coverage for the schema version 16 -> 17 migration (Story 5.5).
///
/// The migration adds the nullable `correctionPending` flag to `credits` and
/// creates the `credit_corrections` table for controlled financial correction
/// requests and Shop Owner reversal approvals.
///
/// Existing credits keep their current behaviour: `correctionPending` defaults
/// to `false`, so payments remain allowed on all pre-existing credits. No
/// existing customer, credit, or payment data is touched.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'credit_system_v17_migration',
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// Opens the database exactly the way the running application does: a
  /// persistent file with `PRAGMA foreign_keys = ON` applied by the connection
  /// setup callback, exactly as `AppDatabaseConnection.openSandboxedConnection` does.
  AppDatabase openWithDeviceSemantics(File file) {
    final executor = NativeDatabase(
      file,
      setup: (db) => db.execute('PRAGMA foreign_keys = ON;'),
    );
    return AppDatabase.forTesting(executor);
  }

  /// Opens the database with Drift's migrations **disabled**, so that opening
  /// it cannot advance the schema version.
  AppDatabase openWithoutMigrations(File file) {
    final executor = NativeDatabase(
      file,
      setup: (db) => db.execute('PRAGMA foreign_keys = ON;'),
      enableMigrations: false,
    );
    return AppDatabase.forTesting(executor);
  }

  /// Reads `PRAGMA user_version` straight from the database file.
  int readUserVersion(File file) {
    final raw = sqlite.sqlite3.open(file.path);
    try {
      return raw.select('PRAGMA user_version').first.values.first as int;
    } finally {
      raw.close();
    }
  }

  /// Seeds a genuine version 16 database on disk.
  ///
  /// The credits table carries every column introduced by migrations up through
  /// v16 **except** `correctionPending` (which the v16 migration never added —
  /// that is the gap this migration closes).
  void seedV16Database(File file) {
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
        "document_snapshot_id" TEXT,
        CHECK (principal_cents >= 0),
        CHECK (balance_cents >= 0),
        CHECK (balance_cents <= principal_cents),
        CHECK (status IN ('active', 'overdue', 'settled', 'cancelled')),
        CHECK (status <> 'settled' OR settled_at IS NOT NULL),
        CHECK (status <> 'cancelled' OR (cancelled_at IS NOT NULL AND cancellation_reason IS NOT NULL AND length(trim(cancellation_reason)) > 0)),
        CHECK (workflow_status IN ('pending_disbursement', 'disbursed', 'cancelled')),
        CHECK (term_preset_days IS NULL OR term_preset_days IN (30, 60, 90)),
        CHECK (NOT (term_preset_days IS NOT NULL AND custom_due_date IS NOT NULL)),
        CHECK ((disbursed_at IS NULL) = (disbursed_by_user_id IS NULL)),
        CHECK (status <> 'cancelled' OR workflow_status = 'cancelled'),
        CHECK (status <> 'cancelled' OR disbursed_at IS NULL),
        CHECK (status <> 'cancelled' OR disbursed_by_user_id IS NULL),
        CHECK (status <> 'settled' OR workflow_status = 'disbursed'),
        CHECK (status = 'cancelled' OR (cancelled_at IS NULL AND (cancellation_reason IS NULL OR length(trim(cancellation_reason)) = 0))),
        CHECK (status = 'settled' OR settled_at IS NULL)
      );''');
    db.execute('''\
      CREATE TABLE "payments" (
        "id" TEXT NOT NULL PRIMARY KEY,
        "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
        "credit_id" TEXT NOT NULL REFERENCES "credits" ("id") ON DELETE RESTRICT,
        "receipt_number" TEXT NOT NULL,
        "amount_cents" INTEGER NOT NULL,
        "pre_balance_cents" INTEGER NOT NULL,
        "post_balance_cents" INTEGER NOT NULL,
        "payment_type" TEXT NOT NULL,
        "recorded_at" INTEGER NOT NULL,
        "recorded_by_user_id" TEXT NOT NULL REFERENCES "app_users" ("id") ON DELETE RESTRICT,
        "customer_id" TEXT NOT NULL,
        "customer_name" TEXT NOT NULL,
        "customer_nic" TEXT NOT NULL,
        "shop_name" TEXT NOT NULL,
        "shop_address" TEXT,
        "shop_phone" TEXT,
        "shop_tax_id" TEXT,
        "shop_footer_notes" TEXT,
        "idempotency_key" TEXT NOT NULL,
        UNIQUE ("shop_id", "receipt_number"),
        UNIQUE ("shop_id", "idempotency_key"),
        CHECK (amount_cents > 0),
        CHECK (payment_type IN ('partial', 'full_settlement')),
        CHECK (pre_balance_cents >= 0),
        CHECK (post_balance_cents >= 0),
        CHECK (post_balance_cents <= pre_balance_cents)
      );''');
    db.execute('PRAGMA user_version = 16;');

    const now = 1793000000;
    db.execute('''\
      INSERT INTO "shops" ("id", "name", "currency_code", "timezone", "created_at", "updated_at")
      VALUES ('shop-v16', 'V16 Shop', 'LKR', 'Asia/Colombo', $now, $now);''');
    db.execute('''\
      INSERT INTO "app_users" ("id", "shop_id", "username", "full_name", "role", "is_active", "session_version", "permissions", "password_hash", "created_at", "updated_at")
      VALUES ('user-v16', 'shop-v16', 'v16.owner', 'V16 Owner', 'shop_owner', 1, 1, NULL, NULL, $now, $now);''');
    db.execute('''\
      INSERT INTO "customers" ("id", "shop_id", "full_name", "nic", "phone", "address", "created_at", "updated_at")
      VALUES ('cust-v16', 'shop-v16', 'V16 Customer', '198512345678', '+94 77 123 4567', '1 Main St', $now, $now);''');
    // A disbursed credit with an outstanding balance.
    db.execute('''\
      INSERT INTO "credits" ("id", "shop_id", "customer_id", "principal_cents", "balance_cents", "status", "workflow_status", "term_preset_days", "disbursed_at", "disbursed_by_user_id", "due_date", "created_at")
      VALUES ('credit-v16-active', 'shop-v16', 'cust-v16', 500000, 300000, 'active', 'disbursed', 30, $now, 'user-v16', $now, $now);''');
    // A settled credit.
    db.execute('''\
      INSERT INTO "credits" ("id", "shop_id", "customer_id", "principal_cents", "balance_cents", "status", "workflow_status", "term_preset_days", "disbursed_at", "disbursed_by_user_id", "due_date", "created_at", "settled_at")
      VALUES ('credit-v16-settled', 'shop-v16', 'cust-v16', 250000, 0, 'settled', 'disbursed', 60, $now, 'user-v16', $now, $now, $now);''');

    db.close();
  }

  group('schema version 16 -> 17 migration (Story 5.5 corrections)', () {
    test('a genuine version 16 database stays at version 16 when reopened without an upgrade', () async {
      final file = File(p.join(tempDir.path, 'v16_no_migration.sqlite'));
      seedV16Database(file);

      expect(
        readUserVersion(file),
        equals(16),
        reason: 'The fixture must start as a genuine version 16 database.',
      );

      // Open with migrations disabled, so nothing can advance the schema version.
      final db = openWithoutMigrations(file);
      addTearDown(() async => db.close());

      // Read the credit row through raw sqlite (the typed Drift API expects the
      // `correctionPending` column which is absent from a genuine v16 file).
      final raw = sqlite.sqlite3.open(file.path);
      try {
        final rows = raw.select(
          'SELECT balance_cents FROM credits WHERE id = ?',
          ['credit-v16-active'],
        );
        expect(rows.first.values.first, equals(300000));
      } finally {
        raw.close();
      }

      // The schema version on disk is untouched without a migration.
      expect(readUserVersion(file), equals(16));
    });

    test('a genuine version 16 database upgrades to version 17', () async {
      final file = File(p.join(tempDir.path, 'v16_to_v17.sqlite'));
      seedV16Database(file);

      expect(readUserVersion(file), equals(16));

      final db = openWithDeviceSemantics(file);
      addTearDown(() async => db.close());

      // Drift opens lazily; issue a query to force the migration to run.
      await (db.select(db.credits)
            ..where((l) => l.id.equals('credit-v16-active')))
          .getSingle();

      expect(readUserVersion(file), equals(22));
      expect(db.schemaVersion, equals(22));
    });

    test('preserves existing credit data and sets correctionPending = false after upgrade', () async {
      final file = File(p.join(tempDir.path, 'v17_correction_pending.sqlite'));
      seedV16Database(file);

      final db = openWithDeviceSemantics(file);
      addTearDown(() async => db.close());

      await (db.select(db.credits)
            ..where((l) => l.id.equals('credit-v16-active')))
          .getSingle();

      expect(readUserVersion(file), equals(22));

      // Existing credits keep their data and get correctionPending = false.
      final active = await (db.select(db.credits)
            ..where((l) => l.id.equals('credit-v16-active')))
          .getSingle();
      expect(active.balanceCents, equals(300000));
      expect(active.correctionPending, isFalse);

      final settled = await (db.select(db.credits)
            ..where((l) => l.id.equals('credit-v16-settled')))
          .getSingle();
      expect(settled.balanceCents, equals(0));
      expect(settled.correctionPending, isFalse);
    });

    test('creates the credit_corrections table and indexes after upgrade', () async {
      final file = File(p.join(tempDir.path, 'v17_corrections_table.sqlite'));
      seedV16Database(file);

      final db = openWithDeviceSemantics(file);
      addTearDown(() async => db.close());

      await (db.select(db.credits)
            ..where((l) => l.id.equals('credit-v16-active')))
          .getSingle();

      expect(readUserVersion(file), equals(22));

      // The corrections table exists and is usable.
      await db.into(db.creditCorrections).insertReturningOrNull(
        CreditCorrectionsCompanion.insert(
          id: 'corr-v17-1',
          shopId: 'shop-v16',
          creditId: 'credit-v16-active',
          originalPaymentId: const Value.absent(),
          requestedByUserId: 'user-v16',
          correctionAmountCents: 5000,
          reason: 'Typographical error; entered 35000 instead of 3500.',
          status: Value('pending_approval'),
          createdAt: DateTime.fromMillisecondsSinceEpoch(1793000000, isUtc: true),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(1793000000, isUtc: true),
        ),
      );

      final inserted = await (db.select(db.creditCorrections)
            ..where((c) => c.id.equals('corr-v17-1')))
          .getSingle();
      expect(inserted.shopId, equals('shop-v16'));
      expect(inserted.status, equals('pending_approval'));
      expect(inserted.correctionAmountCents, equals(5000));

      // The corrections indexes were created.
      final indexRows = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'credit_corrections';",
      ).get();
      final indexNames = indexRows.map((r) => r.read<String>('name')).toList();
      expect(indexNames, containsAll([
        'idx_credit_corrections_shop_id',
        'idx_credit_corrections_shop_status',
        'idx_credit_corrections_shop_credit',
        'idx_credit_corrections_shop_payment',
      ]));
    });

    test('payments table constraints remain intact after upgrade', () async {
      final file = File(p.join(tempDir.path, 'v17_payment_constraints.sqlite'));
      seedV16Database(file);

      final db = openWithDeviceSemantics(file);
      addTearDown(() async => db.close());

      await (db.select(db.credits)
            ..where((l) => l.id.equals('credit-v16-active')))
          .getSingle();

      // The payments table still enforces its financial CHECK constraints:
      // a non-positive amount is rejected.
      expect(
        () async {
          await db.into(db.payments).insert(
            PaymentsCompanion.insert(
              id: 'pay-bad',
              shopId: 'shop-v16',
              creditId: 'credit-v16-active',
              receiptNumber: 'RCP-BAD',
              amountCents: -100,
              preBalanceCents: 300000,
              postBalanceCents: 300100,
              paymentType: 'partial',
              recordedAt: DateTime.fromMillisecondsSinceEpoch(1793000000, isUtc: true),
              recordedByUserId: 'user-v16',
              customerId: 1,
              customerName: 'Bad',
              customerNic: 'Bad',
              shopName: 'Bad Shop',
              idempotencyKey: 'idemp-bad',
            ),
          );
        },
        throwsA(isA<Exception>()),
      );
    });
  });
}



