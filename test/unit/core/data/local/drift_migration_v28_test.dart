import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:credit_system/core/data/local/app_database.dart';

/// Regression coverage for the schema version 27 -> 28 migration (data
/// normalize, no DDL).
///
/// Overdue credits were once persisted with workflow_status = 'overdue',
/// which stranded them from every payment conditional update (all of which
/// target workflow_status = 'disbursed'). The overdue badge is carried by
/// status = 'overdue' alone. The migration rewrites any drifted rows back to
/// 'disbursed'; rows in any other state are left untouched.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'credit_system_v28_migration',
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

  /// Seeds a genuine version 27 database: the credits table as of v27 with
  /// both drifted rows (overdue/overdue) and healthy rows (active/disbursed).
  void seedV27Database(File file) {
    final db = sqlite.sqlite3.open(file.path);
    db.execute('PRAGMA foreign_keys = OFF;');
    db.execute('''
      CREATE TABLE "credits" (
        "id" TEXT NOT NULL PRIMARY KEY,
        "shop_id" TEXT NOT NULL,
        "customer_id" INTEGER NOT NULL,
        "principal_cents" INTEGER NOT NULL CHECK (principal_cents >= 0),
        "balance_cents" INTEGER NOT NULL CHECK (balance_cents >= 0),
        "status" TEXT NOT NULL DEFAULT 'active'
          CHECK (status IN ('active', 'overdue', 'settled', 'cancelled')),
        "workflow_status" TEXT NOT NULL DEFAULT 'pending_disbursement'
          CHECK (workflow_status IN
            ('pending_disbursement', 'disbursed', 'cancelled', 'overdue')),
        "term_preset_days" INTEGER,
        "custom_due_date" INTEGER,
        "disbursed_at" INTEGER,
        "disbursed_by_user_id" TEXT,
        "cancelled_at" INTEGER,
        "cancellation_reason" TEXT,
        "due_date" INTEGER NOT NULL,
        "created_at" INTEGER NOT NULL,
        "settled_at" INTEGER,
        "correction_pending" INTEGER NOT NULL DEFAULT 0
          CHECK (correction_pending IN (0, 1)),
        "credit_type" TEXT NOT NULL DEFAULT 'cash',
        "document_snapshot_id" TEXT
      );
      PRAGMA user_version = 27;
    ''');

    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    db.execute('''
      INSERT INTO "credits" (
        "id", "shop_id", "customer_id", "principal_cents", "balance_cents",
        "status", "workflow_status", "term_preset_days", "due_date",
        "created_at", "correction_pending"
      ) VALUES
        ('v-overdue-1', 'shop-v27', 1, 100000, 50000, 'overdue', 'overdue',
         30, ?, ?, 0),
        ('v-active-1', 'shop-v27', 2, 100000, 100000, 'active', 'disbursed',
         30, ?, ?, 0),
        ('v-settled-1', 'shop-v27', 3, 100000, 0, 'settled', 'overdue',
         30, ?, ?, 0);
    ''', [now + 86400, now, now + 86400, now, now + 86400, now]);

    db.close();
  }

  test('v27 -> v28 normalizes drifted overdue workflow rows and preserves others', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}v27.db');
    seedV27Database(file);

    expect(readUserVersion(file), 27);

    final database = openWithDeviceSemantics(file);
    await database.customSelect('SELECT 1').get(); // force the migration open
    await database.close();

    expect(readUserVersion(file), 28);

    final raw = sqlite.sqlite3.open(file.path);
    try {
      final rows = raw.select(
        'SELECT id, status, workflow_status FROM "credits" ORDER BY id',
      );
      expect(rows, hasLength(3));
      final byId = {
        for (final row in rows)
          row['id'] as String: (row['status'] as String, row['workflow_status'] as String),
      };
      // The drifted overdue row is normalized back to the disbursed workflow;
      // status is untouched so the overdue badge is preserved.
      expect(byId['v-overdue-1'], ('overdue', 'disbursed'));
      expect(byId['v-active-1'], ('active', 'disbursed'));
      // Already-settled credits are not touched by the normalize.
      expect(byId['v-settled-1'], ('settled', 'overdue'));
    } finally {
      raw.close();
    }
  });
}
