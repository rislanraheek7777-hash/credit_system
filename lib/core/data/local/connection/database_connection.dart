import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Platform-aware factory and resolver for local Drift SQLite database connections.
///
/// Binds: Architecture Decisions AD-1, AD-4, AD-7; PRD Non-Functional Requirements.
///
/// Core Responsibilities:
/// 1. Sandboxed Persistence: Opens SQLite databases in the application documents directory
///    via [path_provider] (`getApplicationDocumentsDirectory()`), preventing hard-coded paths.
/// 2. Isolated In-Memory Storage: Generates ephemeral in-memory databases for tests without disk I/O.
/// 3. Foreign-Key Integrity: Explicitly executes `PRAGMA foreign_keys = ON;` on every SQLite connection.
class AppDatabaseConnection {
  const AppDatabaseConnection._();

  /// Default filename for the local application SQLite database.
  static const String defaultDatabaseName = 'credit_system.sqlite';

  /// Creates a persistent, sandboxed [QueryExecutor] for the application.
  ///
  /// Uses [path_provider] to locate the sandboxed application documents directory,
  /// or an optional [overrideDirectory] (useful for headless testing or custom isolated storage).
  ///
  /// Enforces SQLite foreign keys via `PRAGMA foreign_keys = ON;`.
  static QueryExecutor openSandboxedConnection({
    Directory? overrideDirectory,
    String dbName = defaultDatabaseName,
    bool logStatements = false,
  }) {
    return LazyDatabase(() async {
      final Directory folder;
      if (overrideDirectory != null) {
        folder = overrideDirectory;
      } else {
        folder = await getApplicationDocumentsDirectory();
      }

      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }

      final file = File(p.join(folder.path, dbName));

      return NativeDatabase(
        file,
        logStatements: logStatements,
        setup: (database) {
          database.execute('PRAGMA foreign_keys = ON;');
        },
      );
    });
  }

  /// Creates an ephemeral, in-memory [QueryExecutor] exclusively for testing.
  ///
  /// Does not write files to disk. Automatically wiped when closed.
  /// Explicitly activates SQLite foreign-key enforcement via `PRAGMA foreign_keys = ON;`.
  static QueryExecutor openInMemoryConnection({
    bool logStatements = false,
  }) {
    return NativeDatabase.memory(
      logStatements: logStatements,
      setup: (database) {
        database.execute('PRAGMA foreign_keys = ON;');
      },
    );
  }

  /// Authoritative connection resolver for runtime execution.
  ///
  /// Dispatches to [openInMemoryConnection] if [inMemory] is true, or
  /// [openSandboxedConnection] for standard sandboxed device persistence.
  static QueryExecutor openConnection({
    bool inMemory = false,
    Directory? overrideDirectory,
    String dbName = defaultDatabaseName,
    bool logStatements = false,
  }) {
    if (inMemory) {
      return openInMemoryConnection(logStatements: logStatements);
    }
    return openSandboxedConnection(
      overrideDirectory: overrideDirectory,
      dbName: dbName,
      logStatements: logStatements,
    );
  }
}
