import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:credit_system/core/data/local/app_database.dart';

/// Regression coverage for the schema version 26 -> 27 migration (soft delete
/// for customers).
///
/// The migration adds the nullable `deleted_at` column to `customers` so a
/// customer profile can be retained for audit integrity while being soft
/// deleted from all lists, search and pickers. Existing rows are left
/// untouched; `deleted_at` stays NULL for every live customer.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'credit_system_v27_migration',
    );
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

  /// Seeds a genuine version 26 database: the customers table as of v26
  /// (no `deleted_at` column) holding one live customer row.
  void seedV26Database(File file) {
    final db = sqlite.sqlite3.open(file.path);
    db.execute('PRAGMA foreign_keys = OFF;');
    db.execute('''
      CREATE TABLE "customers" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        "shop_id" TEXT NOT NULL REFERENCES "shops" ("id"),
        "full_name" TEXT NOT NULL CHECK (length(full_name) BETWEEN 1 AND 255),
        "nic" TEXT CHECK (nic IS NULL OR length(nic) <= 50),
        "phone" TEXT NOT NULL CHECK (length(phone) BETWEEN 1 AND 50),
        "address" TEXT,
        "photo_uri" TEXT,
        "photo_hash" TEXT,
        "created_at" INTEGER NOT NULL,
        "updated_at" INTEGER NOT NULL,
        UNIQUE ("shop_id", "nic")
      );
      CREATE INDEX IF NOT EXISTS "idx_customers_shop_id"
        ON "customers" ("shop_id");
      CREATE INDEX IF NOT EXISTS "idx_customers_shop_nic"
        ON "customers" ("shop_id", "nic");
      CREATE INDEX IF NOT EXISTS "idx_customers_shop_phone"
        ON "customers" ("shop_id", "phone");
      PRAGMA user_version = 26;
    ''');

    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    db.execute('''
      INSERT INTO "customers" (
        "shop_id", "full_name", "nic", "phone", "address",
        "created_at", "updated_at"
      ) VALUES (
        'shop-v27', 'Kamala Silva', '198765432V', '0712345678',
        '12 Galle Road, Colombo',
        $now, $now
      );
    ''');
    db.close();
  }

  group('schema version 26 -> 27 migration (customers.deleted_at)', () {
    test('a genuine version 26 database upgrades to version 27', () async {
      final file = File(p.join(tempDir.path, 'v26_to_v27.sqlite'));
      seedV26Database(file);

      expect(readUserVersion(file), equals(26));

      final db = openWithDeviceSemantics(file);
      final tableInfo = await db
          .customSelect('PRAGMA table_info("customers")')
          .get();
      await db.close();

      expect(readUserVersion(file), equals(27));
      expect(db.schemaVersion, equals(27));
      expect(
        tableInfo.any((row) => row.read<String>('name') == 'deleted_at'),
        isTrue,
      );

      // The pre-existing row is intact and not soft-deleted.
      final raw = sqlite.sqlite3.open(file.path);
      try {
        final rows = raw.select(
          'SELECT full_name, nic, deleted_at FROM customers '
          "WHERE shop_id = 'shop-v27'",
        );
        expect(rows.single['full_name'], equals('Kamala Silva'));
        expect(rows.single['nic'], equals('198765432V'));
        expect(rows.single['deleted_at'], isNull);
      } finally {
        raw.close();
      }
    });

    test(
      'the deleted_at column is readable and writable after upgrade',
      () async {
        final file = File(p.join(tempDir.path, 'v27_roundtrip.sqlite'));
        seedV26Database(file);

        final db = openWithDeviceSemantics(file);
        await db.customStatement(
          "UPDATE customers SET deleted_at = strftime('%s', 'now') "
          "WHERE shop_id = 'shop-v27'",
        );
        final rows = await db
            .customSelect(
              "SELECT deleted_at FROM customers WHERE shop_id = 'shop-v27'",
            )
            .get();
        await db.close();

        expect(rows.single.read<int?>('deleted_at'), isNotNull);
      },
    );

    test(
      're-opening an already migrated database does not re-run the migration',
      () async {
        final file = File(p.join(tempDir.path, 'v27_reopen.sqlite'));
        seedV26Database(file);

        final first = openWithDeviceSemantics(file);
        await first.customSelect('PRAGMA table_info("customers")').get();
        await first.close();
        expect(readUserVersion(file), equals(27));

        final second = openWithDeviceSemantics(file);
        final tableInfo = await second
            .customSelect('PRAGMA table_info("customers")')
            .get();
        await second.close();
        expect(readUserVersion(file), equals(27));
        expect(second.schemaVersion, equals(27));
        expect(
          tableInfo.where((row) => row.read<String>('name') == 'deleted_at'),
          hasLength(1),
        );
      },
    );
  });
}
