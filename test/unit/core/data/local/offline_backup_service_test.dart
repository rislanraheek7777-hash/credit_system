import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:credit_system/core/data/local/offline_backup_service.dart';

void main() {
  group('OfflineBackupService', () {
    late Directory tempDir;
    late OfflineBackupService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('offline_backup_test_');
      service = OfflineBackupService();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('backup copies database file to backup path', () async {
      final dbPath = p.join(tempDir.path, 'source.db');
      final backupPath = p.join(tempDir.path, 'backups', 'backup.db');
      await File(dbPath).writeAsString('db-content');

      await service.backup(dbPath, backupPath);

      final backupFile = File(backupPath);
      expect(await backupFile.exists(), isTrue);
      expect(await backupFile.readAsString(), equals('db-content'));
    });

    test('restore replaces target with backup contents', () async {
      final dbPath = p.join(tempDir.path, 'target.db');
      final backupPath = p.join(tempDir.path, 'backup.db');
      await File(dbPath).writeAsString('old-db');
      await File(backupPath).writeAsString('restored-db');

      await service.restore(backupPath, dbPath);

      expect(await File(dbPath).readAsString(), equals('restored-db'));
    });

    test('restore creates target when missing', () async {
      final dbPath = p.join(tempDir.path, 'missing.db');
      final backupPath = p.join(tempDir.path, 'backup.db');
      await File(backupPath).writeAsString('restored-db');

      await service.restore(backupPath, dbPath);

      expect(await File(dbPath).readAsString(), equals('restored-db'));
    });

    test('verifyIntegrity returns true for valid sqlite db', () async {
      final dbPath = p.join(tempDir.path, 'valid.db');
      final db = sqlite3.open(dbPath);
      db.execute('CREATE TABLE t (id INTEGER);');
      db.close();

      expect(await service.verifyIntegrity(dbPath), isTrue);
    });

    test('verifyIntegrity returns false for corrupt file', () async {
      final dbPath = p.join(tempDir.path, 'corrupt.db');
      await File(dbPath).writeAsString('not-a-sqlite-db');

      expect(await service.verifyIntegrity(dbPath), isFalse);
    });
  });
}
