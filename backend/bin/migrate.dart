import 'dart:io';

import 'package:credential_recovery_backend/src/database.dart';
import 'package:credential_recovery_backend/src/migration.dart';

/// Explicit operator/CLI path for applying migration 003.
///
///   dart run bin/migrate.dart --path ../lib/core/data/remote/migrations/003_credential_recovery.sql
///
/// The `.sql` file is the single source of truth. This command is never called
/// by the HTTP service or by the Flutter client at startup. Re-running it is a
/// no-op guarded by `schema_migrations`.
Future<void> main(List<String> args) async {
  final path = _migrationPath(args);
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Migration SQL file not found: $path');
    exitCode = 2;
    return;
  }
  final url = Platform.environment['DATABASE_URL'] ?? '';
  if (url.isEmpty) {
    stderr.writeln('DATABASE_URL is required');
    exitCode = 2;
    return;
  }

  final database = PgRecoveryDatabase(url);
  try {
    final applied = await MigrationApplier(database).apply(file.readAsStringSync());
    stdout.writeln(
      applied ? 'Applied migration SQL from $path' : 'Migration 003 already applied; no-op',
    );
  } finally {
    await database.close();
  }
}

String _migrationPath(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '--path' || args[i] == '-p') && i + 1 < args.length) {
      return args[i + 1];
    }
  }
  final positional = args.where((arg) => !arg.startsWith('-')).toList();
  if (positional.isNotEmpty) return positional.first;
  return Platform.environment['CS_RECOVERY_MIGRATION_SQL_PATH'] ??
      '../lib/core/data/remote/migrations/003_credential_recovery.sql';
}
