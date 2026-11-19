import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:credit_system/core/data/local/app_database.dart';

/// Regression coverage for the schema version 25 -> 26 migration (Story 5.6:
/// staff-proposed, owner-approved balance adjustments — partial forgiveness).
///
/// The migration adds the `direction` column to `credit_corrections` so an
/// adjustment proposal can state whether the approved entry increases
/// (`debit`) or decreases (`credit`, the forgiveness write-down) the credit
/// balance. Existing rows default to `debit`, preserving the pre-Story-5.6
/// approval arithmetic (balance += amount).
///
/// Note: the database opens with the current schema version (27), so a v25
/// seed passes through the v26 and v27 migrations on open.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir =
        Directory.systemTemp.createTempSync('credit_system_v26_migration');
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

  /// Seeds a genuine version 25 database: the credit_corrections table as of
  /// v25 (no `direction` column) holding one pending approval row.
  void seedV25Database(File file) {
    final db = sqlite.sqlite3.open(file.path);
    db.execute('PRAGMA foreign_keys = OFF;');
    db.execute('''
      CREATE TABLE "credit_corrections" (
        "id" TEXT NOT NULL,
        "shop_id" TEXT NOT NULL,
        "credit_id" TEXT NOT NULL,
        "original_payment_id" TEXT,
        "requested_by_user_id" TEXT NOT NULL,
        "correction_amount_cents" INTEGER NOT NULL,
        "reason" TEXT NOT NULL,
        "status" TEXT NOT NULL DEFAULT 'pending_approval',
        "reviewed_by_user_id" TEXT,
        "reviewed_at" INTEGER,
        "rejection_reason" TEXT,
        "resulting_balance_cents" INTEGER,
        "created_at" INTEGER NOT NULL,
        "updated_at" INTEGER NOT NULL,
        PRIMARY KEY ("id"),
        CHECK (correction_amount_cents > 0),
        CHECK (status IN ('pending_approval', 'approved', 'rejected')),
        CHECK (length(trim(reason)) > 0),
        CHECK (status <> 'rejected' OR (rejection_reason IS NOT NULL AND length(trim(rejection_reason)) > 0)),
        CHECK (status <> 'approved' OR (reviewed_by_user_id IS NOT NULL AND reviewed_at IS NOT NULL)),
        CHECK (status <> 'rejected' OR (reviewed_by_user_id IS NOT NULL AND reviewed_at IS NOT NULL)),
        CHECK (resulting_balance_cents IS NULL OR resulting_balance_cents >= 0)
      );
      PRAGMA user_version = 25;
    ''');

    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    db.execute('''
      INSERT INTO "credit_corrections" (
        "id", "shop_id", "credit_id", "original_payment_id",
        "requested_by_user_id", "correction_amount_cents", "reason",
        "status", "created_at", "updated_at"
      ) VALUES (
        'corr-v26-1', 'shop-v26', 'credit-v26-1', 'pay-v26-1',
        'staff-v26', 150000, 'Wrong payment amount entered',
        'pending_approval', $now, $now
      );
    ''');
    db.close();
  }

  group('schema version 25 -> 26 migration (credit_corrections.direction)',
      () {
    test('a genuine version 25 database upgrades to version 27', () async {
      final file = File(p.join(tempDir.path, 'v25_to_v26.sqlite'));
      seedV25Database(file);

      expect(readUserVersion(file), equals(25));

      final db = openWithDeviceSemantics(file);
      final tableInfo = await db.customSelect(
        'PRAGMA table_info("credit_corrections")',
      ).get();
      await db.close();

      expect(readUserVersion(file), equals(27));
      expect(db.schemaVersion, equals(27));
      expect(tableInfo.any((row) => row.read<String>('name') == 'direction'),
          isTrue);

      // The pre-existing row defaults to 'debit', preserving the
      // pre-Story-5.6 approval arithmetic.
      final raw = sqlite.sqlite3.open(file.path);
      try {
        final rows = raw.select(
          "SELECT direction FROM credit_corrections WHERE id = 'corr-v26-1'",
        );
        expect(rows.single['direction'], equals('debit'));
      } finally {
        raw.close();
      }
    });

    test('the direction column is readable and writable after upgrade', () async {
      final file = File(p.join(tempDir.path, 'v26_roundtrip.sqlite'));
      seedV25Database(file);

      final db = openWithDeviceSemantics(file);
      await db.customStatement(
        "UPDATE credit_corrections SET direction = 'credit' WHERE id = 'corr-v26-1'",
      );
      final rows = await db.customSelect(
        "SELECT direction FROM credit_corrections WHERE id = 'corr-v26-1'",
      ).get();
      await db.close();

      expect(rows.single.read<String>('direction'), equals('credit'));
    });

    test('re-opening an already migrated database does not re-run the migration',
        () async {
      final file = File(p.join(tempDir.path, 'v26_reopen.sqlite'));
      seedV25Database(file);

      final first = openWithDeviceSemantics(file);
      await first.customSelect('PRAGMA table_info("credit_corrections")').get();
      await first.close();
      expect(readUserVersion(file), equals(27));

      final second = openWithDeviceSemantics(file);
      await second.customSelect('PRAGMA table_info("credit_corrections")').get();
      await second.close();
      expect(readUserVersion(file), equals(27));
      expect(second.schemaVersion, equals(27));
    });
  });
}
