import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:credit_system/core/data/local/app_database.dart';

/// Regression coverage for the schema version 18 -> 19 migration (Epic 6: Stories 6.2, 6.3, 6.4).
///
/// The migration creates the `due_date_extensions`, `customer_follow_ups`, and `credit_resolutions`
/// tables for overdue credit governance.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('credit_system_v19_migration');
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

  group('schema version 18 -> 19 migration (Epic 6)', () {
    test('a genuine version 18 database upgrades to version 19 and creates all 3 tables', () async {
      final file = File(p.join(tempDir.path, 'v18_to_v19.sqlite'));
      
      // Create empty db with version 18
      final raw = sqlite.sqlite3.open(file.path);
      raw.execute('PRAGMA user_version = 18;');
      raw.close();

      expect(readUserVersion(file), equals(18));

      final db = openWithDeviceSemantics(file);
      addTearDown(() async => db.close());

      // Trigger lazy open
      await db.customSelect('SELECT 1').get();

      expect(readUserVersion(file), equals(22));
      expect(db.schemaVersion, equals(22));

      // Verify the new tables exist
      final tables = await db.customSelect("SELECT name FROM sqlite_master WHERE type='table'").get();
      final tableNames = tables.map((r) => r.read<String>('name')).toSet();

      expect(tableNames, contains('due_date_extensions'));
      expect(tableNames, contains('customer_follow_ups'));
      expect(tableNames, contains('credit_resolutions'));
      expect(tableNames, contains('credit_administrative_closures'));
    });
  });
}

