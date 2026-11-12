import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:credit_system/core/data/local/app_database.dart';

/// Regression coverage for the schema version 17 -> 18 migration (Story 5.5).
///
/// The migration creates the `credit_ledger_entries` table for immutable
/// financial ledger entries (compensating debits and controlled adjustments)
/// linked to a credit. No existing customer, credit, payment, or correction data
/// is touched.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'credit_system_v18_migration',
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

  /// Seeds a genuine version 17 database on disk.
  ///
  /// Carries every column introduced by migrations up through v17 including
  /// `correctionPending` on credits and the `credit_corrections` table, but **not**
  /// the `credit_ledger_entries` table (which the v18 migration creates).
  void seedV17Database(File file) {
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
        "correction_pending" INTEGER NOT NULL DEFAULT 0,
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
    db.execute('''\
      CREATE TABLE "credit_corrections" (
        "id" TEXT NOT NULL PRIMARY KEY,
        "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
        "credit_id" TEXT NOT NULL REFERENCES "credits" ("id") ON DELETE RESTRICT,
        "original_payment_id" TEXT REFERENCES "payments" ("id") ON DELETE RESTRICT,
        "requested_by_user_id" TEXT NOT NULL REFERENCES "app_users" ("id") ON DELETE RESTRICT,
        "correction_amount_cents" INTEGER NOT NULL,
        "reason" TEXT NOT NULL,
        "status" TEXT NOT NULL DEFAULT 'pending_approval',
        "reviewed_by_user_id" TEXT REFERENCES "app_users" ("id") ON DELETE RESTRICT,
        "reviewed_at" INTEGER,
        "rejection_reason" TEXT,
        "resulting_balance_cents" INTEGER,
        "created_at" INTEGER NOT NULL,
        "updated_at" INTEGER NOT NULL,
        CHECK (correction_amount_cents > 0),
        CHECK (status IN ('pending_approval', 'approved', 'rejected')),
        CHECK (length(trim(reason)) > 0),
        CHECK (status <> 'rejected' OR (rejection_reason IS NOT NULL AND length(trim(rejection_reason)) > 0)),
        CHECK (status <> 'approved' OR (reviewed_by_user_id IS NOT NULL AND reviewed_at IS NOT NULL)),
        CHECK (status <> 'rejected' OR (reviewed_by_user_id IS NOT NULL AND reviewed_at IS NOT NULL)),
        CHECK (resulting_balance_cents IS NULL OR resulting_balance_cents >= 0)
      );''');
    db.execute('PRAGMA user_version = 17;');

    const now = 1793000000;
    db.execute('''\
      INSERT INTO "shops" ("id", "name", "currency_code", "timezone", "created_at", "updated_at")
      VALUES ('shop-v17', 'V17 Shop', 'LKR', 'Asia/Colombo', $now, $now);''');
    db.execute('''\
      INSERT INTO "app_users" ("id", "shop_id", "username", "full_name", "role", "is_active", "session_version", "permissions", "password_hash", "created_at", "updated_at")
      VALUES ('user-v17', 'shop-v17', 'v17.owner', 'V17 Owner', 'shop_owner', 1, 1, NULL, NULL, $now, $now);''');
    db.execute('''\
      INSERT INTO "customers" ("id", "shop_id", "full_name", "nic", "phone", "address", "created_at", "updated_at")
      VALUES ('cust-v17', 'shop-v17', 'V17 Customer', '198512345678', '+94 77 123 4567', '1 Main St', $now, $now);''');
    db.execute('''\
      INSERT INTO "credits" ("id", "shop_id", "customer_id", "principal_cents", "balance_cents", "status", "workflow_status", "term_preset_days", "disbursed_at", "disbursed_by_user_id", "due_date", "created_at", "correction_pending")
      VALUES ('credit-v17-active', 'shop-v17', 'cust-v17', 500000, 300000, 'active', 'disbursed', 30, $now, 'user-v17', $now, $now, 0);''');
    db.execute('''\
      INSERT INTO "credit_corrections" ("id", "shop_id", "credit_id", "original_payment_id", "requested_by_user_id", "correction_amount_cents", "reason", "status", "created_at", "updated_at")
      VALUES ('corr-v17-1', 'shop-v17', 'credit-v17-active', NULL, 'user-v17', 200000, 'Typographical error.', 'pending_approval', $now, $now);''');

    db.close();
  }

  group('schema version 17 -> 18 migration (Story 5.5 ledger entries)', () {
    test('a genuine version 17 database stays at version 17 when reopened without an upgrade', () async {
      final file = File(p.join(tempDir.path, 'v17_no_migration.sqlite'));
      seedV17Database(file);

      expect(
        readUserVersion(file),
        equals(17),
        reason: 'The fixture must start as a genuine version 17 database.',
      );

      final db = openWithoutMigrations(file);
      addTearDown(() async => db.close());

      // Existing credit data is readable exactly as it is, without the ledger
      // entries table.
      final raw = sqlite.sqlite3.open(file.path);
      try {
        final rows = raw.select(
          'SELECT balance_cents, correction_pending FROM credits WHERE id = ?',
          ['credit-v17-active'],
        );
        expect(rows.first.values.first, equals(300000));
        expect(rows.first.values.elementAt(1), equals(0));
      } finally {
        raw.close();
      }

      // The schema version on disk is untouched without a migration.
      expect(readUserVersion(file), equals(17));
    });

    test('a genuine version 17 database upgrades to version 18', () async {
      final file = File(p.join(tempDir.path, 'v17_to_v18.sqlite'));
      seedV17Database(file);

      expect(readUserVersion(file), equals(17));

      final db = openWithDeviceSemantics(file);
      addTearDown(() async => db.close());

      // Drift opens lazily; issue a query to force the migration to run.
      await (db.select(db.credits)
            ..where((l) => l.id.equals('credit-v17-active')))
          .getSingle();

      expect(readUserVersion(file), equals(22));
      expect(db.schemaVersion, equals(22));
    });

    test('preserves existing credit and correction data and creates the ledger entries table after upgrade', () async {
      final file = File(p.join(tempDir.path, 'v18_ledger_table.sqlite'));
      seedV17Database(file);

      final db = openWithDeviceSemantics(file);
      addTearDown(() async => db.close());

      await (db.select(db.credits)
            ..where((l) => l.id.equals('credit-v17-active')))
          .getSingle();

      expect(readUserVersion(file), equals(22));

      // Existing data is preserved.
      final active = await (db.select(db.credits)
            ..where((l) => l.id.equals('credit-v17-active')))
          .getSingle();
      expect(active.balanceCents, equals(300000));
      expect(active.correctionPending, isFalse);

      final correction = await (db.select(db.creditCorrections)
            ..where((c) => c.id.equals('corr-v17-1')))
          .getSingle();
      expect(correction.status, equals('pending_approval'));
      expect(correction.correctionAmountCents, equals(200000));

      // The ledger entries table exists and is usable.
      await db.into(db.creditLedgerEntries).insertReturningOrNull(
        CreditLedgerEntriesCompanion.insert(
          id: 'ledger-v18-1',
          shopId: 'shop-v17',
          creditId: 'credit-v17-active',
          originalPaymentId: const Value.absent(),
          correctionId: const Value.absent(),
          entryType: 'compensating_debit',
          amountCents: 200000,
          preBalanceCents: 300000,
          postBalanceCents: 500000,
          reason: 'Compensating debit for approved correction.',
          recordedByUserId: 'user-v17',
          recordedAt: DateTime.fromMillisecondsSinceEpoch(1793000000, isUtc: true),
          createdAt: DateTime.fromMillisecondsSinceEpoch(1793000000, isUtc: true),
        ),
      );

      final inserted = await (db.select(db.creditLedgerEntries)
            ..where((e) => e.id.equals('ledger-v18-1')))
          .getSingle();
      expect(inserted.shopId, equals('shop-v17'));
      expect(inserted.entryType, equals('compensating_debit'));
      expect(inserted.amountCents, equals(200000));
      expect(inserted.preBalanceCents, equals(300000));
      expect(inserted.postBalanceCents, equals(500000));

      // The ledger indexes were created.
      final indexRows = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'credit_ledger_entries';",
      ).get();
      final indexNames = indexRows.map((r) => r.read<String>('name')).toList();
      expect(indexNames, containsAll([
        'idx_ledger_entries_shop_id',
        'idx_ledger_entries_shop_credit',
        'idx_ledger_entries_shop_entry_type',
        'idx_ledger_entries_shop_correction',
      ]));
    });

    test('payments table CHECK constraints remain intact after upgrade', () async {
      final file = File(p.join(tempDir.path, 'v18_payment_constraints.sqlite'));
      seedV17Database(file);

      final db = openWithDeviceSemantics(file);
      addTearDown(() async => db.close());

      await (db.select(db.credits)
            ..where((l) => l.id.equals('credit-v17-active')))
          .getSingle();

      // A non-positive payment amount is still rejected by the payments table
      // CHECK constraint.
      expect(
        () async {
          await db.into(db.payments).insert(
            PaymentsCompanion.insert(
              id: 'pay-bad',
              shopId: 'shop-v17',
              creditId: 'credit-v17-active',
              receiptNumber: 'RCP-BAD',
              amountCents: -100,
              preBalanceCents: 300000,
              postBalanceCents: 300100,
              paymentType: 'partial',
              recordedAt: DateTime.fromMillisecondsSinceEpoch(1793000000, isUtc: true),
              recordedByUserId: 'user-v17',
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

