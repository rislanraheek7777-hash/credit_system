import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/remote/migration_runner.dart';

void main() {
  group('PostgreSQL DDL Migration Contract Tests (001_initial_schema.sql)', () {
    late String upSql;
    late String downSql;

    setUpAll(() async {
      final upFile = File(
        'lib/core/data/remote/migrations/001_initial_schema.sql',
      );
      final downFile = File(
        'lib/core/data/remote/migrations/001_initial_schema_down.sql',
      );

      expect(
        await upFile.exists(),
        isTrue,
        reason: '001_initial_schema.sql must exist',
      );
      expect(
        await downFile.exists(),
        isTrue,
        reason: '001_initial_schema_down.sql must exist',
      );

      upSql = await upFile.readAsString();
      downSql = await downFile.readAsString();
    });

    test('REQUIRED TABLES: defines all required foundational tables', () {
      final requiredTables = [
        'schema_migrations',
        'shops',
        'app_users',
        'audit_events',
        'sync_queue',
      ];

      for (final table in requiredTables) {
        expect(
          upSql.contains(
            RegExp(
              'CREATE TABLE (IF NOT EXISTS )?$table\\b',
              caseSensitive: false,
            ),
          ),
          isTrue,
          reason: '001_initial_schema.sql must create table $table',
        );
      }
    });

    test('MONETARY INVARIANT (AD-2, FR-22): strictly prohibits floating-point types for financial columns', () {
      final prohibitedTypes = ['DOUBLE PRECISION', 'FLOAT8', 'FLOAT4', 'REAL'];

      // Strip SQL line comments (-- ...) and block comments (/* ... */)
      final ddlStatementsOnly = upSql
          .replaceAll(RegExp(r'--.*$', multiLine: true), '')
          .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');

      for (final type in prohibitedTypes) {
        expect(
          ddlStatementsOnly.toUpperCase().contains(type),
          isFalse,
          reason:
              '001_initial_schema.sql DDL statements must NEVER contain prohibited floating-point type $type',
        );
      }
    });

    test('TIMESTAMP CONVENTION: strictly uses TIMESTAMPTZ instead of naive TIMESTAMP', () {
      // Find all column definitions with TIMESTAMP
      final naiveTimestampMatches =
          RegExp(
                r'\bTIMESTAMP\b(?!\s+WITH\s+TIME\s+ZONE)',
                caseSensitive: false,
              )
              .allMatches(upSql)
              .where(
                (m) => !upSql
                    .substring(m.start - 10, m.end + 10)
                    .toUpperCase()
                    .contains('TIMESTAMPTZ'),
              )
              .toList();

      expect(
        naiveTimestampMatches.isEmpty,
        isTrue,
        reason: 'All timestamp columns must use TIMESTAMPTZ for timezone-aware evaluation',
      );
    });

    test('IDENTIFIER CONVENTION: uses UUID primary keys and foreign keys', () {
      expect(
        upSql.contains(RegExp(r'id UUID PRIMARY KEY', caseSensitive: false)),
        isTrue,
      );
      expect(
        upSql.contains(
          RegExp(
            r'shop_id UUID NOT NULL REFERENCES shops\(id\)',
            caseSensitive: false,
          ),
        ),
        isTrue,
      );
    });

    test('TENANT ISOLATION (AD-1, FR-4): enables and FORCES Row-Level Security on tenant-owned tables', () {
      final rlsTables = ['shops', 'app_users', 'audit_events', 'sync_queue'];

      for (final table in rlsTables) {
        expect(
          upSql.contains(
            RegExp(
              'ALTER TABLE $table ENABLE ROW LEVEL SECURITY;',
              caseSensitive: false,
            ),
          ),
          isTrue,
          reason: 'RLS must be enabled on $table',
        );
        expect(
          upSql.contains(
            RegExp(
              'ALTER TABLE $table FORCE ROW LEVEL SECURITY;',
              caseSensitive: false,
            ),
          ),
          isTrue,
          reason:
              'RLS must be FORCED on $table so table owners cannot bypass policies',
        );
      }
    });

    test('TENANT ISOLATION POLICY: binds strictly to server-authenticated app.current_shop_id session claim', () {
      expect(
        upSql.contains("current_setting('app.current_shop_id', true)::uuid"),
        isTrue,
        reason: 'RLS policies must derive shop_id from authenticated server session, never client inputs',
      );
    });

    test('AUDIT IMMUTABILITY (AD-6, FR-31): enforces trigger blocking UPDATE and DELETE on audit_events', () {
      expect(
        upSql.contains('CREATE OR REPLACE FUNCTION reject_audit_tampering()'),
        isTrue,
      );
      expect(upSql.contains('CREATE TRIGGER trg_audit_immutable'), isTrue);
      expect(upSql.contains('BEFORE UPDATE OR DELETE ON audit_events'), isTrue);
      expect(upSql.contains('RAISE EXCEPTION'), isTrue);
    });

    test('ROLLBACK CLEANLINESS: 001_initial_schema_down.sql drops objects in reverse dependency order', () {
      expect(
        downSql.contains(
          'DROP TRIGGER IF EXISTS trg_audit_immutable ON audit_events;',
        ),
        isTrue,
      );
      expect(
        downSql.contains('DROP FUNCTION IF EXISTS reject_audit_tampering();'),
        isTrue,
      );
      expect(
        downSql.contains('DROP TABLE IF EXISTS sync_queue CASCADE;'),
        isTrue,
      );
      expect(
        downSql.contains('DROP TABLE IF EXISTS audit_events CASCADE;'),
        isTrue,
      );
      expect(
        downSql.contains('DROP TABLE IF EXISTS app_users CASCADE;'),
        isTrue,
      );
      expect(downSql.contains('DROP TABLE IF EXISTS shops CASCADE;'), isTrue);
      expect(
        downSql.contains('DROP TABLE IF EXISTS schema_migrations CASCADE;'),
        isTrue,
      );
    });
  });

  group('MigrationRunner - Logic, Checksum & Lifecycle Contract Tests', () {
    late _MockSqlExecutor mockExecutor;
    late MigrationRunner runner;

    setUp(() {
      mockExecutor = _MockSqlExecutor();
      runner = MigrationRunner(mockExecutor);
    });

    test('computes deterministic SHA-256 checksums regardless of CRLF or LF line endings', () {
      const sqlLf = 'CREATE TABLE test (\n  id INTEGER PRIMARY KEY\n);\n';
      const sqlCrlf =
          'CREATE TABLE test (\r\n  id INTEGER PRIMARY KEY\r\n);\r\n';

      final hashLf = MigrationRunner.computeChecksum(sqlLf);
      final hashCrlf = MigrationRunner.computeChecksum(sqlCrlf);

      expect(hashLf, equals(hashCrlf));
      expect(hashLf.length, equals(64));
    });

    test('initializes schema_migrations table and executes migration inside transaction', () async {
      const migration = MigrationDefinition(
        version: 1,
        name: '001_initial_schema',
        upSql: 'CREATE TABLE dummy (id INT);',
        downSql: 'DROP TABLE dummy;',
      );

      final applied = await runner.applyMigration(migration);
      expect(applied, isTrue);

      final appliedList = await runner.getAppliedMigrations();
      expect(appliedList.length, equals(1));
      expect(appliedList.first.version, equals(1));
      expect(appliedList.first.name, equals('001_initial_schema'));
      expect(appliedList.first.checksum, equals(migration.checksum));
    });

    test('IDEMPOTENCY: applying already applied migration with same checksum is a safe no-op', () async {
      const migration = MigrationDefinition(
        version: 1,
        name: '001_initial_schema',
        upSql: 'CREATE TABLE dummy (id INT);',
        downSql: 'DROP TABLE dummy;',
      );

      await runner.applyMigration(migration);
      final secondRun = await runner.applyMigration(migration);

      expect(
        secondRun,
        isFalse,
        reason: 'Already applied migration must not re-execute',
      );
      final appliedList = await runner.getAppliedMigrations();
      expect(appliedList.length, equals(1));
    });

    test('TAMPER DETECTION: throws MigrationChecksumMismatchException if migration file changed post-application', () async {
      const originalMigration = MigrationDefinition(
        version: 1,
        name: '001_initial_schema',
        upSql: 'CREATE TABLE dummy (id INT);',
        downSql: 'DROP TABLE dummy;',
      );

      await runner.applyMigration(originalMigration);

      // Now someone modifies the SQL
      const tamperedMigration = MigrationDefinition(
        version: 1,
        name: '001_initial_schema',
        upSql: 'CREATE TABLE dummy (id INT, tampered_column TEXT);',
        downSql: 'DROP TABLE dummy;',
      );

      expect(
        () => runner.applyMigration(tamperedMigration),
        throwsA(isA<MigrationChecksumMismatchException>()),
      );
    });

    test('ORDERING: throws MigrationSequenceException if migrations are not in ascending version order', () async {
      final unorderedMigrations = [
        const MigrationDefinition(
          version: 2,
          name: '002_second',
          upSql: '',
          downSql: '',
        ),
        const MigrationDefinition(
          version: 1,
          name: '001_first',
          upSql: '',
          downSql: '',
        ),
      ];

      expect(
        () => runner.applyAll(unorderedMigrations),
        throwsA(isA<MigrationSequenceException>()),
      );
    });

    test(
      'ROLLBACK: cleanly reverts applied migration and removes tracking entry',
      () async {
        const migration = MigrationDefinition(
          version: 1,
          name: '001_initial_schema',
          upSql: 'CREATE TABLE dummy (id INT);',
          downSql: 'DROP TABLE dummy;',
        );

        await runner.applyMigration(migration);
        expect((await runner.getAppliedMigrations()).length, equals(1));

        final rolledBack = await runner.rollbackMigration(migration);
        expect(rolledBack, isTrue);

        expect((await runner.getAppliedMigrations()).isEmpty, isTrue);
      },
    );
  });
}

/// In-memory mock SQL executor simulating PostgreSQL transactional migration state.
class _MockSqlExecutor implements SqlDatabaseExecutor {
  final List<Map<String, dynamic>> _migrationsTable = [];
  final List<String> executedStatements = [];

  @override
  Future<void> execute(String sql, [List<dynamic>? parameters]) async {
    // Record the executed SQL and parameters for test inspection.
    executedStatements.add(sql);
    // Mock INSERT into schema_migrations using provided parameters.
    if (sql.trim().toUpperCase().startsWith('INSERT INTO SCHEMA_MIGRATIONS')) {
      if (parameters != null && parameters.length >= 3) {
        _migrationsTable.add({
          'version': parameters[0],
          'name': parameters[1],
          'checksum': parameters[2],
          'applied_at': DateTime.now().toUtc(),
        });
      }
    } else if (sql.trim().toUpperCase().startsWith(
      'DELETE FROM SCHEMA_MIGRATIONS',
    )) {
      // Support parameterized delete or fallback to parsing version from SQL.
      if (parameters != null && parameters.isNotEmpty) {
        final version = parameters[0];
        _migrationsTable.removeWhere((row) => row['version'] == version);
      } else {
        final versionMatch = RegExp(r'version\s*=\s*(\d+)').firstMatch(sql);
        if (versionMatch != null) {
          final version = int.parse(versionMatch.group(1)!);
          _migrationsTable.removeWhere((row) => row['version'] == version);
        }
      }
    }
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic>? parameters,
  ]) async {
    if (sql.contains('FROM schema_migrations')) {
      return List<Map<String, dynamic>>.from(_migrationsTable);
    }
    return [];
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(SqlDatabaseExecutor tx) action,
  ) async {
    return await action(this);
  }
}
