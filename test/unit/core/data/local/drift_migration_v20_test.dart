import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:credit_system/core/data/local/app_database.dart';

/// Regression coverage for the schema version 19 -> 20 migration
/// (customer identity: String/UUID -> auto-increment int).
///
/// The migration rebuilds `customers` with an INTEGER auto-increment primary
/// key (reusing each legacy row's rowid), remaps every legacy TEXT uuid to
/// that integer in `loans`, `collateral_items`, `customer_follow_ups` and
/// `payments`, and preserves all row data.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('credit_system_v20_migration');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  AppDatabase openWithDeviceSemantics(File file) {
    final executor = NativeDatabase(
      file,
      setup: (db) => db.execute('PRAGMA foreign_keys = ON;'),
    );
    return AppDatabase.forTesting(executor);
  }

  int readUserVersion(File file) {
    final raw = sqlite.sqlite3.open(file.path);
    try {
      return raw.select('PRAGMA user_version').first.values.first as int;
    } finally {
      raw.close();
    }
  }

  /// Seeds a genuine version 19 database: the pre-conversion schema where
  /// `customers.id` and every `customer_id` reference are TEXT uuids.
  ///
  /// The table shapes are the exact v20 schema (dumped from a fresh
  /// database) with the customer identity columns reverted to TEXT.
  void seedV19Database(File file) {
    final db = sqlite.sqlite3.open(file.path);
    db.execute('PRAGMA foreign_keys = ON;');
    db.execute('''
      CREATE TABLE "shops" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "currency_code" TEXT NOT NULL DEFAULT 'LKR', "timezone" TEXT NOT NULL DEFAULT 'Asia/Colombo', "business_address" TEXT NULL, "contact_phone" TEXT NULL, "contact_email" TEXT NULL, "registration_number" TEXT NULL, "logo_uri" TEXT NULL, "receipt_header_notes" TEXT NULL, "receipt_footer_notes" TEXT NULL, "created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, PRIMARY KEY ("id"));
      CREATE TABLE "app_users" ("id" TEXT NOT NULL, "shop_id" TEXT NOT NULL REFERENCES shops (id) ON DELETE RESTRICT, "username" TEXT NOT NULL, "full_name" TEXT NOT NULL, "role" TEXT NOT NULL, "is_active" INTEGER NOT NULL DEFAULT 1 CHECK ("is_active" IN (0, 1)), "session_version" INTEGER NOT NULL DEFAULT 1, "permissions" TEXT NULL, "password_hash" TEXT NULL, "created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, PRIMARY KEY ("id"), UNIQUE ("shop_id", "username"), CHECK (session_version >= 1));
      CREATE TABLE "customers" ("id" TEXT NOT NULL, "shop_id" TEXT NOT NULL REFERENCES shops (id) ON DELETE RESTRICT, "full_name" TEXT NOT NULL, "nic" TEXT NOT NULL, "phone" TEXT NOT NULL, "address" TEXT NOT NULL, "photo_uri" TEXT NULL, "photo_hash" TEXT NULL, "created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, PRIMARY KEY ("id"), UNIQUE ("shop_id", "nic"));
      CREATE INDEX "idx_customers_shop_id" ON "customers" ("shop_id");
      CREATE INDEX "idx_customers_shop_nic" ON "customers" ("shop_id", "nic");
      CREATE INDEX "idx_customers_shop_phone" ON "customers" ("shop_id", "phone");
      CREATE TABLE "loans" ("id" TEXT NOT NULL, "shop_id" TEXT NOT NULL REFERENCES shops (id) ON DELETE RESTRICT, "customer_id" TEXT NOT NULL REFERENCES customers (id) ON DELETE RESTRICT, "principal_cents" INTEGER NOT NULL, "balance_cents" INTEGER NOT NULL, "status" TEXT NOT NULL DEFAULT 'active', "workflow_status" TEXT NOT NULL DEFAULT 'pending_disbursement', "term_preset_days" INTEGER NULL, "custom_due_date" INTEGER NULL, "disbursed_at" INTEGER NULL, "disbursed_by_user_id" TEXT NULL REFERENCES app_users (id) ON DELETE RESTRICT, "cancelled_at" INTEGER NULL, "cancellation_reason" TEXT NULL, "due_date" INTEGER NOT NULL, "created_at" INTEGER NOT NULL, "settled_at" INTEGER NULL, "correction_pending" INTEGER NOT NULL DEFAULT 0 CHECK ("correction_pending" IN (0, 1)), "document_snapshot_id" TEXT NULL, PRIMARY KEY ("id"), CHECK (principal_cents >= 0), CHECK (balance_cents >= 0), CHECK (balance_cents <= principal_cents), CHECK (status IN ('active', 'overdue', 'settled', 'cancelled')), CHECK (status <> 'settled' OR settled_at IS NOT NULL), CHECK (status <> 'cancelled' OR (cancelled_at IS NOT NULL AND cancellation_reason IS NOT NULL AND length(trim(cancellation_reason)) > 0)), CHECK (workflow_status IN ('pending_disbursement', 'disbursed', 'cancelled', 'overdue')), CHECK (term_preset_days IS NULL OR term_preset_days IN (30, 60, 90)), CHECK (NOT (term_preset_days IS NOT NULL AND custom_due_date IS NOT NULL)), CHECK ((disbursed_at IS NULL) = (disbursed_by_user_id IS NULL)), CHECK (status <> 'cancelled' OR workflow_status = 'cancelled'), CHECK (status <> 'cancelled' OR disbursed_at IS NULL), CHECK (status <> 'cancelled' OR disbursed_by_user_id IS NULL), CHECK (status <> 'settled' OR workflow_status = 'disbursed'), CHECK (status = 'cancelled' OR (cancelled_at IS NULL AND (cancellation_reason IS NULL OR length(trim(cancellation_reason)) = 0))), CHECK (status = 'settled' OR settled_at IS NULL));
      CREATE INDEX "idx_loans_shop_id" ON "loans" ("shop_id");
      CREATE INDEX "idx_loans_shop_customer" ON "loans" ("shop_id", "customer_id");
      CREATE INDEX "idx_loans_shop_status" ON "loans" ("shop_id", "status");
      CREATE INDEX "idx_loans_shop_customer_status" ON "loans" ("shop_id", "customer_id", "status");
      CREATE TABLE "collateral_items" ("id" TEXT NOT NULL, "shop_id" TEXT NOT NULL REFERENCES shops (id) ON DELETE RESTRICT, "customer_id" TEXT NOT NULL REFERENCES customers (id) ON DELETE RESTRICT, "loan_id" TEXT NULL REFERENCES loans (id) ON DELETE RESTRICT, "item_reference_id" TEXT NOT NULL, "category" TEXT NOT NULL, "description" TEXT NOT NULL, "condition_grade" TEXT NOT NULL, "weight_milligrams" INTEGER NOT NULL, "estimated_value_cents" INTEGER NOT NULL, "photo_uri" TEXT NULL, "photo_hash" TEXT NULL, "custody_status" TEXT NOT NULL DEFAULT 'in_custody', "created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, PRIMARY KEY ("id"), UNIQUE ("shop_id", "item_reference_id"), CHECK (weight_milligrams > 0), CHECK (estimated_value_cents >= 0), CHECK (category IN ('gold', 'electronics', 'valuables')), CHECK (custody_status IN ('in_custody', 'handover_requested', 'handover_reported', 'returned', 'exception_held', 'discrepancy')));
      CREATE INDEX "idx_collateral_shop_id" ON "collateral_items" ("shop_id");
      CREATE INDEX "idx_collateral_shop_customer" ON "collateral_items" ("shop_id", "customer_id");
      CREATE INDEX "idx_collateral_shop_loan" ON "collateral_items" ("shop_id", "loan_id");
      CREATE TABLE "customer_follow_ups" ("id" TEXT NOT NULL, "shop_id" TEXT NOT NULL REFERENCES shops (id) ON DELETE RESTRICT, "loan_id" TEXT NOT NULL REFERENCES loans (id) ON DELETE RESTRICT, "customer_id" TEXT NOT NULL REFERENCES customers (id) ON DELETE RESTRICT, "staff_id" TEXT NOT NULL REFERENCES app_users (id) ON DELETE RESTRICT, "channel" TEXT NOT NULL, "notes" TEXT NOT NULL, "promised_payment_date" INTEGER NULL, "created_at" INTEGER NOT NULL, PRIMARY KEY ("id"), CHECK (length(trim(notes)) > 0), CHECK (channel IN ('phone_call', 'in_person', 'physical_notice')));
      CREATE INDEX "idx_customer_follow_ups_shop_id" ON "customer_follow_ups" ("shop_id");
      CREATE INDEX "idx_customer_follow_ups_shop_loan" ON "customer_follow_ups" ("shop_id", "loan_id");
      CREATE TABLE "payments" ("id" TEXT NOT NULL, "shop_id" TEXT NOT NULL REFERENCES shops (id) ON DELETE RESTRICT, "loan_id" TEXT NOT NULL REFERENCES loans (id) ON DELETE RESTRICT, "receipt_number" TEXT NOT NULL, "amount_cents" INTEGER NOT NULL, "pre_balance_cents" INTEGER NOT NULL, "post_balance_cents" INTEGER NOT NULL, "payment_type" TEXT NOT NULL, "recorded_at" INTEGER NOT NULL, "recorded_by_user_id" TEXT NOT NULL REFERENCES app_users (id) ON DELETE RESTRICT, "customer_id" TEXT NOT NULL, "customer_name" TEXT NOT NULL, "customer_nic" TEXT NOT NULL, "shop_name" TEXT NOT NULL, "shop_address" TEXT NULL, "shop_phone" TEXT NULL, "shop_tax_id" TEXT NULL, "shop_footer_notes" TEXT NULL, "idempotency_key" TEXT NOT NULL, PRIMARY KEY ("id"), UNIQUE ("shop_id", "receipt_number"), UNIQUE ("shop_id", "idempotency_key"), CHECK (amount_cents > 0), CHECK (payment_type IN ('partial', 'full_settlement')), CHECK (pre_balance_cents >= 0), CHECK (post_balance_cents >= 0), CHECK (post_balance_cents <= pre_balance_cents));
      CREATE INDEX "idx_payments_shop_id" ON "payments" ("shop_id");
      CREATE INDEX "idx_payments_shop_loan" ON "payments" ("shop_id", "loan_id");
      CREATE INDEX "idx_payments_receipt_number" ON "payments" ("shop_id", "receipt_number");
      PRAGMA user_version = 19;
    ''');

    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    db.execute('''
      INSERT INTO "shops" ("id", "name", "currency_code", "timezone", "created_at", "updated_at")
      VALUES ('shop-v19', 'V19 Shop', 'LKR', 'Asia/Colombo', $now, $now);
    ''');
    db.execute('''
      INSERT INTO "app_users" ("id", "shop_id", "username", "full_name", "role", "is_active", "session_version", "created_at", "updated_at")
      VALUES ('user-v19', 'shop-v19', 'v19.staff', 'V19 Staff', 'manager', 1, 1, $now, $now);
    ''');
    db.execute('''
      INSERT INTO "customers" ("id", "shop_id", "full_name", "nic", "phone", "address", "photo_uri", "photo_hash", "created_at", "updated_at")
      VALUES ('cust-v19-alpha', 'shop-v19', 'V19 Alpha Customer', '198512345678', '+94 77 111 2222', '1 Main St', '/photos/alpha.jpg', 'hash-alpha', $now, $now);
    ''');
    db.execute('''
      INSERT INTO "customers" ("id", "shop_id", "full_name", "nic", "phone", "address", "photo_uri", "photo_hash", "created_at", "updated_at")
      VALUES ('cust-v19-beta', 'shop-v19', 'V19 Beta Customer', '198587654321', '+94 77 333 4444', '2 Main St', NULL, NULL, $now, $now);
    ''');
    db.execute('''
      INSERT INTO "loans" ("id", "shop_id", "customer_id", "principal_cents", "balance_cents", "status", "workflow_status", "due_date", "created_at")
      VALUES ('loan-v19-alpha', 'shop-v19', 'cust-v19-alpha', 500000, 500000, 'active', 'disbursed', $now, $now);
    ''');
    db.execute('''
      INSERT INTO "loans" ("id", "shop_id", "customer_id", "principal_cents", "balance_cents", "status", "workflow_status", "due_date", "created_at")
      VALUES ('loan-v19-beta', 'shop-v19', 'cust-v19-beta', 250000, 250000, 'active', 'disbursed', $now, $now);
    ''');
    db.execute('''
      INSERT INTO "collateral_items" ("id", "shop_id", "customer_id", "loan_id", "item_reference_id", "category", "description", "condition_grade", "weight_milligrams", "estimated_value_cents", "custody_status", "created_at", "updated_at")
      VALUES ('coll-v19-alpha', 'shop-v19', 'cust-v19-alpha', 'loan-v19-alpha', 'COLL-V19-A', 'gold', 'Gold necklace', 'Good', 5500, 1500000, 'in_custody', $now, $now);
    ''');
    db.execute('''
      INSERT INTO "collateral_items" ("id", "shop_id", "customer_id", "loan_id", "item_reference_id", "category", "description", "condition_grade", "weight_milligrams", "estimated_value_cents", "custody_status", "created_at", "updated_at")
      VALUES ('coll-v19-unbound', 'shop-v19', 'cust-v19-beta', NULL, 'COLL-V19-B', 'valuables', 'Watch', 'Like New', 300, 900000, 'in_custody', $now, $now);
    ''');
    db.execute('''
      INSERT INTO "customer_follow_ups" ("id", "shop_id", "loan_id", "customer_id", "staff_id", "channel", "notes", "created_at")
      VALUES ('follow-v19-alpha', 'shop-v19', 'loan-v19-alpha', 'cust-v19-alpha', 'user-v19', 'phone_call', 'Called about repayment', $now);
    ''');
    db.execute('''
      INSERT INTO "payments" ("id", "shop_id", "loan_id", "receipt_number", "amount_cents", "pre_balance_cents", "post_balance_cents", "payment_type", "recorded_at", "recorded_by_user_id", "customer_id", "customer_name", "customer_nic", "shop_name", "idempotency_key")
      VALUES ('pay-v19-alpha', 'shop-v19', 'loan-v19-alpha', 'RCP-V19-1', 100000, 500000, 400000, 'partial', $now, 'user-v19', 'cust-v19-alpha', 'V19 Alpha Customer', '198512345678', 'V19 Shop', 'idem-v19-1');
    ''');
    db.close();
  }

  group('schema version 19 -> 20 migration (customer id int conversion)', () {
    test('a genuine version 19 database upgrades to version 20', () async {
      final file = File(p.join(tempDir.path, 'v19_to_v20.sqlite'));
      seedV19Database(file);

      expect(readUserVersion(file), equals(19));

      final db = openWithDeviceSemantics(file);
      addTearDown(() async => db.close());

      // Drift opens lazily, so the migration runs on the first query.
      await db.select(db.customers).get();

      expect(readUserVersion(file), equals(20));
      expect(db.schemaVersion, equals(20));
    });

    test('preserves all customer data and converts ids to rowid-based integers',
        () async {
      final file = File(p.join(tempDir.path, 'v19_data.sqlite'));
      seedV19Database(file);

      final db = openWithDeviceSemantics(file);
      addTearDown(() async => db.close());

      final customers = await db.select(db.customers).get();
      expect(customers, hasLength(2));

      final alpha = await (db.select(db.customers)
            ..where((c) => c.nic.equals('198512345678')))
          .getSingle();
      // The single pre-existing customer keeps its rowid as the new int id.
      expect(alpha.id, equals(1));
      expect(alpha.fullName, equals('V19 Alpha Customer'));
      expect(alpha.phone, equals('+94 77 111 2222'));
      expect(alpha.photoUri, equals('/photos/alpha.jpg'));
      expect(alpha.photoHash, equals('hash-alpha'));

      final beta = await (db.select(db.customers)
            ..where((c) => c.nic.equals('198587654321')))
          .getSingle();
      expect(beta.id, equals(2));
      expect(beta.fullName, equals('V19 Beta Customer'));
      expect(beta.photoUri, isNull);
    });

    test('remaps every referencing table to the converted integer ids',
        () async {
      final file = File(p.join(tempDir.path, 'v19_refs.sqlite'));
      seedV19Database(file);

      final db = openWithDeviceSemantics(file);
      addTearDown(() async => db.close());

      final alphaLoan = await (db.select(db.loans)
            ..where((l) => l.id.equals('loan-v19-alpha')))
          .getSingle();
      expect(alphaLoan.customerId, equals(1));
      expect(alphaLoan.principalCents, equals(500000));
      expect(alphaLoan.workflowStatus, equals('disbursed'));

      final betaLoan = await (db.select(db.loans)
            ..where((l) => l.id.equals('loan-v19-beta')))
          .getSingle();
      expect(betaLoan.customerId, equals(2));

      final alphaCollateral = await (db.select(db.collateralItems)
            ..where((c) => c.id.equals('coll-v19-alpha')))
          .getSingle();
      expect(alphaCollateral.customerId, equals(1));
      expect(alphaCollateral.loanId, equals('loan-v19-alpha'));
      expect(alphaCollateral.estimatedValueCents, equals(1500000));

      // An unbound collateral item (loan_id NULL) survives with its customer
      // reference remapped too.
      final unboundCollateral = await (db.select(db.collateralItems)
            ..where((c) => c.id.equals('coll-v19-unbound')))
          .getSingle();
      expect(unboundCollateral.customerId, equals(2));
      expect(unboundCollateral.loanId, isNull);

      final followUp = await (db.select(db.customerFollowUps)
            ..where((f) => f.id.equals('follow-v19-alpha')))
          .getSingle();
      expect(followUp.customerId, equals(1));
      expect(followUp.loanId, equals('loan-v19-alpha'));

      final payment = await (db.select(db.payments)
            ..where((p) => p.id.equals('pay-v19-alpha')))
          .getSingle();
      expect(payment.customerId, equals(1));
      expect(payment.amountCents, equals(100000));
      expect(payment.receiptNumber, equals('RCP-V19-1'));
    });

    test('leaves foreign keys enforcing after the rebuild and cleans up temp state',
        () async {
      final file = File(p.join(tempDir.path, 'v19_fk.sqlite'));
      seedV19Database(file);

      final db = openWithDeviceSemantics(file);
      addTearDown(() async => db.close());

      await db.select(db.customers).get();

      final enabled =
          await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(enabled.read<bool>('foreign_keys'), isTrue,
          reason: 'The migration must restore foreign-key enforcement.');

      // A child row referencing a non-existent customer must be refused.
      await expectLater(
        db.into(db.loans).insert(LoansCompanion.insert(
              id: 'loan-dangling',
              shopId: 'shop-v19',
              customerId: 999,
              principalCents: 1000,
              balanceCents: 1000,
              status: const Value('active'),
              dueDate: DateTime.now().toUtc(),
              createdAt: DateTime.now().toUtc(),
            )),
        throwsA(isA<sqlite.SqliteException>()),
      );

      // The temporary remap table and the legacy copy are dropped.
      final tables = await db
          .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table'")
          .get();
      final tableNames = tables.map((r) => r.read<String>('name')).toSet();
      expect(tableNames, isNot(contains('_customer_id_remap')));
      expect(tableNames, isNot(contains('customers_v19_ids')));
    });

    test('indexes are recreated on the rebuilt tables', () async {
      final file = File(p.join(tempDir.path, 'v19_indexes.sqlite'));
      seedV19Database(file);

      final db = openWithDeviceSemantics(file);
      addTearDown(() async => db.close());

      await db.select(db.customers).get();

      Future<Set<String>> indexNamesFor(String table) async {
        final rows = await db
            .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = '$table'")
            .get();
        return rows.map((r) => r.read<String>('name')).toSet();
      }

      expect(
        await indexNamesFor('customers'),
        containsAll([
          'idx_customers_shop_id',
          'idx_customers_shop_nic',
          'idx_customers_shop_phone',
        ]),
      );
      expect(
        await indexNamesFor('loans'),
        containsAll([
          'idx_loans_shop_id',
          'idx_loans_shop_customer',
          'idx_loans_shop_status',
          'idx_loans_shop_customer_status',
        ]),
      );
      expect(
        await indexNamesFor('payments'),
        containsAll([
          'idx_payments_shop_id',
          'idx_payments_shop_loan',
          'idx_payments_receipt_number',
        ]),
      );
    });

    test('a failed conversion rolls back and leaves the v19 data intact',
        () async {
      final file = File(p.join(tempDir.path, 'v19_rollback.sqlite'));
      seedV19Database(file);

      // Force the migration to fail mid-way: the loans remap UPDATE aborts.
      final raw = sqlite.sqlite3.open(file.path);
      raw.execute('''
        CREATE TRIGGER "fail_loans_customer_update"
        BEFORE UPDATE OF "customer_id" ON "loans"
        BEGIN SELECT RAISE(ABORT, 'forced migration failure'); END;
      ''');
      raw.close();

      final db = openWithDeviceSemantics(file);
      await expectLater(
        db.select(db.customers).get(),
        throwsA(anything),
      );
      await db.close();

      // Drift runs onUpgrade in a transaction: everything rolled back.
      final check = sqlite.sqlite3.open(file.path);
      try {
        expect(
          check.select('PRAGMA user_version').first.values.first,
          equals(19),
        );
        expect(
          check.select('SELECT typeof("id") FROM "customers" LIMIT 1').first
              .values.first,
          equals('text'),
        );
        expect(
          check
              .select('SELECT "customer_id" FROM "loans" ORDER BY "id" LIMIT 1')
              .first
              .values
              .first,
          equals('cust-v19-alpha'),
        );
        expect(
          check.select('SELECT COUNT(*) FROM "customers"').first.values.first,
          equals(2),
        );
      } finally {
        check.close();
      }
    });

    test('upgrades app_users with email/phone columns and indexes', () async {
      final file = File(p.join(tempDir.path, 'v19_appusers.sqlite'));
      seedV19Database(file);

      final db = openWithDeviceSemantics(file);
      addTearDown(() async => db.close());
      await db.select(db.customers).get();

      final raw = sqlite.sqlite3.open(file.path);
      try {
        final columns = raw
            .select('PRAGMA table_info("app_users")')
            .map((r) => r['name'] as String)
            .toList();
        expect(columns, contains('email'));
        expect(columns, contains('phone'));

        final indexes = raw
            .select("SELECT name FROM sqlite_master WHERE type='index' "
                "AND tbl_name='app_users'")
            .map((r) => r['name'] as String)
            .toList();
        expect(indexes, contains('idx_app_users_shop_email'));
        expect(indexes, contains('idx_app_users_shop_phone'));
      } finally {
        raw.close();
      }
    });

    test('a second launch at version 20 does not re-run the conversion',
        () async {
      final file = File(p.join(tempDir.path, 'v19_reopen.sqlite'));
      seedV19Database(file);

      final first = openWithDeviceSemantics(file);
      await first.select(first.customers).get();
      await first.close();

      expect(readUserVersion(file), equals(20));

      final second = openWithDeviceSemantics(file);
      addTearDown(() async => second.close());

      final customers = await second.select(second.customers).get();
      expect(customers, hasLength(2));
      expect(customers.map((c) => c.id), containsAll([1, 2]));

      final loans = await second.select(second.loans).get();
      expect(loans.map((l) => l.customerId), containsAll([1, 2]));
    });
  });
}
