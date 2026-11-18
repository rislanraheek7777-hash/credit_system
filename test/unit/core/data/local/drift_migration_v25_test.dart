import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:credit_system/core/data/local/app_database.dart';

/// Regression coverage for the schema version 24 -> 25 migration.
///
/// The migration widens the collateral category vocabulary for the
/// selection-tag UI (gold, electronics, sports, dress, grocery, cosmetic,
/// medicine, valuables, other). SQLite cannot alter a CHECK constraint in
/// place, so `collateral_items` is rebuilt following the v24-style safe
/// rebuild procedure (foreign keys off + legacy_alter_table). Existing rows
/// are preserved verbatim.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir =
        Directory.systemTemp.createTempSync('credit_system_v25_migration');
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

  /// Seeds a genuine version 24 database: the post-v24 schema where
  /// description/condition_grade/weight_milligrams are nullable but the
  /// category CHECK still only admits ('gold', 'electronics', 'valuables').
  void seedV24Database(File file) {
    final db = sqlite.sqlite3.open(file.path);
    db.execute('PRAGMA foreign_keys = ON;');
    db.execute('''
      CREATE TABLE "shops" ("id" TEXT NOT NULL, "name" TEXT NOT NULL,
        "currency_code" TEXT NOT NULL DEFAULT 'LKR',
        "timezone" TEXT NOT NULL DEFAULT 'Asia/Colombo',
        "created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL,
        PRIMARY KEY ("id"));
      CREATE TABLE "customers" ("id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        "shop_id" TEXT NOT NULL REFERENCES shops (id),
        "full_name" TEXT NOT NULL, "nic" TEXT, "phone" TEXT NOT NULL,
        "created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL);
      CREATE TABLE "credits" ("id" TEXT NOT NULL,
        "shop_id" TEXT NOT NULL REFERENCES shops (id) ON DELETE RESTRICT,
        "customer_id" INTEGER NOT NULL REFERENCES customers (id) ON DELETE RESTRICT,
        "principal_cents" INTEGER NOT NULL, "balance_cents" INTEGER NOT NULL,
        "status" TEXT NOT NULL DEFAULT 'active',
        "due_date" INTEGER NOT NULL, "created_at" INTEGER NOT NULL,
        PRIMARY KEY ("id"));
      CREATE TABLE "collateral_items" (
        "id" TEXT NOT NULL,
        "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
        "customer_id" INTEGER NOT NULL REFERENCES "customers" ("id") ON DELETE RESTRICT,
        "credit_id" TEXT REFERENCES "credits" ("id") ON DELETE RESTRICT,
        "item_reference_id" TEXT NOT NULL,
        "category" TEXT NOT NULL,
        "description" TEXT,
        "condition_grade" TEXT,
        "weight_milligrams" INTEGER,
        "estimated_value_cents" INTEGER NOT NULL,
        "photo_uri" TEXT,
        "photo_hash" TEXT,
        "custody_status" TEXT NOT NULL DEFAULT 'in_custody',
        "created_at" INTEGER NOT NULL,
        "updated_at" INTEGER NOT NULL,
        UNIQUE ("shop_id", "item_reference_id"),
        PRIMARY KEY ("id"),
        CHECK (weight_milligrams > 0),
        CHECK (estimated_value_cents >= 0),
        CHECK (category IN ('gold', 'electronics', 'valuables')),
        CHECK (custody_status IN ('in_custody', 'handover_requested', 'handover_reported', 'returned', 'exception_held', 'discrepancy'))
      );
      CREATE INDEX "idx_collateral_shop_id" ON "collateral_items" ("shop_id");
      CREATE INDEX "idx_collateral_shop_customer" ON "collateral_items" ("shop_id", "customer_id");
      CREATE INDEX "idx_collateral_shop_credit" ON "collateral_items" ("shop_id", "credit_id");
      CREATE INDEX "idx_collateral_shop_custody" ON "collateral_items" ("shop_id", "custody_status");
      CREATE INDEX "idx_collateral_shop_category" ON "collateral_items" ("shop_id", "category");
      PRAGMA user_version = 24;
    ''');

    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    db.execute('''
      INSERT INTO "shops" ("id", "name", "created_at", "updated_at")
      VALUES ('shop-v25', 'V25 Shop', $now, $now);
    ''');
    db.execute('''
      INSERT INTO "customers" ("id", "shop_id", "full_name", "phone", "created_at", "updated_at")
      VALUES (1, 'shop-v25', 'V25 Customer', '+94 77 000 1111', $now, $now);
    ''');
    db.execute('''
      INSERT INTO "collateral_items" ("id", "shop_id", "customer_id", "credit_id", "item_reference_id", "category", "description", "condition_grade", "weight_milligrams", "estimated_value_cents", "custody_status", "created_at", "updated_at")
      VALUES ('coll-v25-gold', 'shop-v25', 1, NULL, 'COLL-V25-A', 'gold', 'Gold necklace', 'Good', 5500, 1500000, 'in_custody', $now, $now);
    ''');
    db.execute('''
      INSERT INTO "collateral_items" ("id", "shop_id", "customer_id", "credit_id", "item_reference_id", "category", "description", "condition_grade", "weight_milligrams", "estimated_value_cents", "custody_status", "created_at", "updated_at")
      VALUES ('coll-v25-valuables', 'shop-v25', 1, NULL, 'COLL-V25-B', 'valuables', 'Watch', 'Like New', NULL, 900000, 'handover_requested', $now, $now);
    ''');
    db.close();
  }

  group('schema version 24 -> 25 migration (collateral category CHECK widening)',
      () {
    test('a genuine version 24 database upgrades to version 25', () async {
      final file = File(p.join(tempDir.path, 'v24_to_v25.sqlite'));
      seedV24Database(file);

      expect(readUserVersion(file), equals(24));

      final db = openWithDeviceSemantics(file);
      addTearDown(() async => db.close());

      // Drift opens lazily, so the migration runs on the first query.
      await db.select(db.collateralItems).get();

      expect(readUserVersion(file), equals(25));
      expect(db.schemaVersion, equals(25));
    });

    test('preserves existing collateral rows verbatim', () async {
      final file = File(p.join(tempDir.path, 'v24_data.sqlite'));
      seedV24Database(file);

      final db = openWithDeviceSemantics(file);
      addTearDown(() async => db.close());

      final items = await db.select(db.collateralItems).get();
      expect(items, hasLength(2));

      final gold = items.firstWhere((i) => i.id == 'coll-v25-gold');
      expect(gold.category, equals('gold'));
      expect(gold.description, equals('Gold necklace'));
      expect(gold.conditionGrade, equals('Good'));
      expect(gold.weightMilligrams, equals(5500));
      expect(gold.estimatedValueCents, equals(1500000));
      expect(gold.custodyStatus, equals('in_custody'));

      final valuables = items.firstWhere((i) => i.id == 'coll-v25-valuables');
      expect(valuables.category, equals('valuables'));
      expect(valuables.weightMilligrams, isNull);
      expect(valuables.custodyStatus, equals('handover_requested'));
    });

    test('accepts the widened category vocabulary and rejects unknown values',
        () async {
      final file = File(p.join(tempDir.path, 'v24_terms.sqlite'));
      seedV24Database(file);

      final db = openWithDeviceSemantics(file);
      addTearDown(() async => db.close());
      await db.select(db.collateralItems).get();

      final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      for (final category in [
        'gold',
        'electronics',
        'sports',
        'dress',
        'grocery',
        'cosmetic',
        'medicine',
        'valuables',
        'other',
      ]) {
        await db.customStatement(
          'INSERT INTO "collateral_items" '
          '("id", "shop_id", "customer_id", "item_reference_id", "category", '
          ' "estimated_value_cents", "created_at", "updated_at") '
          'VALUES (\'coll-v25-new-$category\', \'shop-v25\', 1, \'COLL-new-$category\', '
          '\'$category\', 100, $now, $now);',
        );
      }

      await expectLater(
        db.customStatement(
          'INSERT INTO "collateral_items" '
          '("id", "shop_id", "customer_id", "item_reference_id", "category", '
          ' "estimated_value_cents", "created_at", "updated_at") '
          'VALUES (\'coll-v25-bogus\', \'shop-v25\', 1, \'COLL-bogus\', '
          '\'unlisted_category\', 100, $now, $now);',
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test('leaves foreign keys enforcing and recreates the collateral indexes',
        () async {
      final file = File(p.join(tempDir.path, 'v24_fk.sqlite'));
      seedV24Database(file);

      final db = openWithDeviceSemantics(file);
      addTearDown(() async => db.close());

      await db.select(db.collateralItems).get();

      final enabled = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(enabled.read<bool>('foreign_keys'), isTrue,
          reason: 'The migration must restore foreign-key enforcement.');

      final indexes = await db
          .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'index' "
              "AND tbl_name = 'collateral_items'")
          .get();
      final indexNames = indexes.map((r) => r.read<String>('name')).toSet();
      expect(
        indexNames,
        containsAll([
          'idx_collateral_shop_id',
          'idx_collateral_shop_customer',
          'idx_collateral_shop_credit',
          'idx_collateral_shop_custody',
          'idx_collateral_shop_category',
        ]),
      );
    });

    test('a failed rebuild rolls back and leaves the v24 data intact',
        () async {
      final file = File(p.join(tempDir.path, 'v24_rollback.sqlite'));
      seedV24Database(file);

      // Force the migration to fail mid-way: the migration's first statement
      // inside its transaction is `DROP TABLE IF EXISTS
      // "collateral_items_v25"`, which cannot drop a view, so the copy never
      // starts. The failure happens inside Drift's onUpgrade transaction, so
      // everything must roll back.
      final raw = sqlite.sqlite3.open(file.path);
      raw.execute('CREATE VIEW "collateral_items_v25" AS SELECT 1;');
      raw.close();

      final db = openWithDeviceSemantics(file);
      await expectLater(
        db.select(db.collateralItems).get(),
        throwsA(anything),
      );
      await db.close();

      // Drift runs onUpgrade in a transaction: everything rolled back.
      final check = sqlite.sqlite3.open(file.path);
      try {
        expect(
          check.select('PRAGMA user_version').first.values.first,
          equals(24),
        );
        expect(
          check.select('SELECT COUNT(*) FROM "collateral_items"').first.values.first,
          equals(2),
        );
        final tableSql = check
            .select(
                "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'collateral_items'")
            .first
            .values
            .first as String;
        expect(tableSql, contains("'gold', 'electronics', 'valuables'"));
        expect(tableSql, isNot(contains('sports')));
      } finally {
        check.close();
      }
    });

    test('a second launch at version 25 does not re-run the migration',
        () async {
      final file = File(p.join(tempDir.path, 'v24_reopen.sqlite'));
      seedV24Database(file);

      final first = openWithDeviceSemantics(file);
      await first.select(first.collateralItems).get();
      await first.close();

      expect(readUserVersion(file), equals(25));

      final second = openWithDeviceSemantics(file);
      addTearDown(() async => second.close());

      final items = await second.select(second.collateralItems).get();
      expect(items, hasLength(2));
      expect(items.map((i) => i.category),
          containsAll(['gold', 'valuables']));
    });
  });
}
