import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

class OfflineBackupService {
  Future<void> backup(String dbPath, String backupPath) async {
    final dbFile = File(dbPath);
    final backupFile = File(backupPath);
    await backupFile.parent.create(recursive: true);
    await dbFile.copy(backupPath);
  }

  Future<void> restore(String backupPath, String dbPath) async {
    final backupFile = File(backupPath);
    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
    await backupFile.copy(dbPath);
  }

  Future<bool> verifyIntegrity(String dbPath) async {
    Database? db;
    try {
      db = sqlite3.open(dbPath);
      final result = db.select('PRAGMA integrity_check;');
      return result.isNotEmpty && result.first.values.first == 'ok';
    } catch (_) {
      return false;
    } finally {
      db?.close();
    }
  }
}