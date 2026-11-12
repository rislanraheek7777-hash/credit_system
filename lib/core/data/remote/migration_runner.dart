import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Representation of a versioned database migration script pair.
class MigrationDefinition {
  /// Monotonically increasing version number (e.g. 1).
  final int version;

  /// Human-readable identifier matching the migration filename (e.g. '001_initial_schema').
  final String name;

  /// Forward DDL statements.
  final String upSql;

  /// Rollback DDL statements.
  final String downSql;

  const MigrationDefinition({
    required this.version,
    required this.name,
    required this.upSql,
    required this.downSql,
  });

  /// Computed SHA-256 checksum of the forward SQL statements.
  String get checksum => MigrationRunner.computeChecksum(upSql);
}

/// Metadata record of an applied database migration retrieved from `schema_migrations`.
class AppliedMigrationRecord {
  final int version;
  final String name;
  final String checksum;
  final DateTime appliedAt;

  const AppliedMigrationRecord({
    required this.version,
    required this.name,
    required this.checksum,
    required this.appliedAt,
  });
}

/// Base exception for database migration errors.
abstract class MigrationException implements Exception {
  final String message;
  const MigrationException(this.message);

  @override
  String toString() => 'MigrationException: $message';
}

/// Thrown when a migration file has been modified after being applied to the database.
class MigrationChecksumMismatchException extends MigrationException {
  final int version;
  final String expectedChecksum;
  final String recordedChecksum;

  const MigrationChecksumMismatchException({
    required this.version,
    required this.expectedChecksum,
    required this.recordedChecksum,
  }) : super(
         'Checksum mismatch for migration version $version. '
         'Recorded in database: "$recordedChecksum", but local file hash is: "$expectedChecksum". '
         'Altering previously applied migrations is strictly forbidden to prevent schema drift.',
       );
}

/// Thrown when migrations are provided out of sequence or with version gaps.
class MigrationSequenceException extends MigrationException {
  const MigrationSequenceException(super.message);
}

/// Thrown when migration DDL execution fails.
class MigrationExecutionException extends MigrationException {
  final dynamic cause;
  const MigrationExecutionException(super.message, [this.cause]);

  @override
  String toString() => 'MigrationExecutionException: $message (Cause: $cause)';
}

/// Database abstraction allowing the migration runner to execute against
/// real PostgreSQL connections or in-memory simulation harnesses.
abstract class SqlDatabaseExecutor {
  /// Executes a DDL or modification statement, optionally with parameters.
  Future<void> execute(String sql, [List<dynamic>? parameters]);

  /// Executes a query returning rows as a list of maps.
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic>? parameters,
  ]);

  /// Executes [action] inside an atomic database transaction.
  Future<T> transaction<T>(Future<T> Function(SqlDatabaseExecutor tx) action);
}

/// Version-tracked PostgreSQL migration execution harness.
///
/// Binds: Sub-Task 1.2B; Architecture Decisions AD-1, AD-4, AD-7; PRD Non-Functional Requirements.
///
/// Guarantees:
/// 1. Forward idempotency: Already applied migrations with matching checksums are safely skipped.
/// 2. Checksum tamper protection: Modified migration files throw [MigrationChecksumMismatchException].
/// 3. Atomic execution: DDL execution and version registration occur inside a single transaction.
/// 4. Explicit rollback: Safely reverts applied schema changes and cleans up tracking records.
class MigrationRunner {
  final SqlDatabaseExecutor executor;

  const MigrationRunner(this.executor);

  /// Computes a deterministic SHA-256 checksum for the provided SQL text.
  /// Normalizes CRLF and LF line endings to ensure consistent hashes across OS environments.
  static String computeChecksum(String sql) {
    final normalized = sql.replaceAll('\r\n', '\n').trim();
    final bytes = utf8.encode(normalized);
    return sha256.convert(bytes).toString();
  }

  /// Ensures the `schema_migrations` version tracking table exists.
  Future<void> initializeSchemaMigrationsTable() async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        checksum VARCHAR(64) NOT NULL,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    ''');
  }

  /// Retrieves all applied migrations ordered by ascending version number.
  Future<List<AppliedMigrationRecord>> getAppliedMigrations() async {
    await initializeSchemaMigrationsTable();
    final rows = await executor.query(
      'SELECT version, name, checksum, applied_at FROM schema_migrations ORDER BY version ASC;',
    );

    return rows.map((row) {
      return AppliedMigrationRecord(
        version: row['version'] as int,
        name: row['name'] as String,
        checksum: row['checksum'] as String,
        appliedAt: row['applied_at'] is DateTime
            ? row['applied_at'] as DateTime
            : DateTime.parse(row['applied_at'].toString()),
      );
    }).toList();
  }

  /// Applies a single [migration].
  ///
  /// Returns `true` if newly applied, or `false` if already applied with a matching checksum.
  /// Throws [MigrationChecksumMismatchException] if applied with a different checksum.
  Future<bool> applyMigration(MigrationDefinition migration) async {
    await initializeSchemaMigrationsTable();

    final appliedList = await getAppliedMigrations();
    final existing = appliedList.cast<AppliedMigrationRecord?>().firstWhere(
      (m) => m?.version == migration.version,
      orElse: () => null,
    );

    final localChecksum = migration.checksum;

    if (existing != null) {
      if (existing.checksum != localChecksum) {
        throw MigrationChecksumMismatchException(
          version: migration.version,
          expectedChecksum: localChecksum,
          recordedChecksum: existing.checksum,
        );
      }
      return false; // Already applied cleanly
    }

    // Apply inside transaction
    await executor.transaction((tx) async {
      try {
        await tx.execute(migration.upSql);
        await tx.execute(
          "INSERT INTO schema_migrations (version, name, checksum, applied_at) VALUES (@p0, @p1, @p2, NOW());",
          [migration.version, migration.name, localChecksum],
        );
      } catch (e) {
        throw MigrationExecutionException(
          'Failed to apply migration ${migration.version} (${migration.name}): $e',
          e,
        );
      }
    });

    return true;
  }

  /// Reverts a single previously applied [migration].
  ///
  /// Returns `true` if successfully rolled back, or `false` if the migration was not applied.
  Future<bool> rollbackMigration(MigrationDefinition migration) async {
    await initializeSchemaMigrationsTable();

    final appliedList = await getAppliedMigrations();
    final isApplied = appliedList.any((m) => m.version == migration.version);

    if (!isApplied) {
      return false; // Not applied, nothing to roll back
    }

    // Rollback inside transaction
    await executor.transaction((tx) async {
      try {
        await tx.execute(migration.downSql);
        await tx.execute(
          'DELETE FROM schema_migrations WHERE version = ${migration.version};',
        );
      } catch (e) {
        throw MigrationExecutionException(
          'Failed to rollback migration ${migration.version} (${migration.name}): $e',
          e,
        );
      }
    });

    return true;
  }

  /// Applies all [migrations] in strictly ascending version order.
  /// Returns the count of newly applied migrations.
  Future<int> applyAll(List<MigrationDefinition> migrations) async {
    // Validate ordering
    for (int i = 0; i < migrations.length; i++) {
      if (i > 0 && migrations[i].version <= migrations[i - 1].version) {
        throw MigrationSequenceException(
          'Migrations are not in strictly ascending order: '
          'version ${migrations[i].version} cannot follow ${migrations[i - 1].version}.',
        );
      }
    }

    int appliedCount = 0;
    for (final migration in migrations) {
      final wasApplied = await applyMigration(migration);
      if (wasApplied) {
        appliedCount++;
      }
    }
    return appliedCount;
  }
}

