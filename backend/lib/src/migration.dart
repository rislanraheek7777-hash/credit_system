import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'database.dart';

/// Explicit, idempotent application of migration 003 from its canonical SQL
/// file. A second DBA/CI run is a no-op; a changed SQL file fails closed.
class MigrationApplier {
  MigrationApplier(this._database);

  static const int version = 3;
  static const String name = '003_credential_recovery';

  final RecoveryDatabase _database;

  /// Returns `true` when newly applied and `false` when already current.
  Future<bool> apply(String sql) async {
    final checksum = computeChecksum(sql);
    return _database.transaction((tx) async {
      await tx.execute(
        'CREATE TABLE IF NOT EXISTS schema_migrations ('
        'version INTEGER PRIMARY KEY, '
        'name VARCHAR(255) NOT NULL, '
        'checksum VARCHAR(64) NOT NULL, '
        'applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW())',
      );
      final applied = await tx.query(
        'SELECT checksum FROM schema_migrations WHERE version = @p0',
        [version],
      );
      if (applied.isNotEmpty) {
        if (applied.first['checksum'] != checksum) {
          throw StateError(
            'Checksum mismatch for migration $version: recorded '
            '${applied.first['checksum']}, local $checksum',
          );
        }
        return false;
      }

      await tx.execute(sql);
      final inserted = await tx.execute(
        'INSERT INTO schema_migrations (version, name, checksum, applied_at) '
        'VALUES (@p0, @p1, @p2, NOW())',
        [version, name, checksum],
      );
      if (inserted != 1) {
        throw StateError('Failed to record migration $version');
      }
      return true;
    });
  }

  /// Matches the client's historical checksum normalization so records written
  /// by either tool remain comparable.
  static String computeChecksum(String sql) =>
      sha256.convert(utf8.encode(sql.replaceAll('\r\n', '\n').trim())).toString();
}
