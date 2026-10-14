import 'package:drift/drift.dart';
import 'connection/database_connection.dart';
import 'tables/shops_table.dart';
import 'tables/app_users_table.dart';
import 'tables/sync_queue_table.dart';

part 'app_database.g.dart';

/// Local Drift SQLite database for counter persistence and offline operation queueing.
///
/// Binds: Architecture Decisions AD-1, AD-4, AD-7; PRD FR-4, FR-23.
///
/// Acts as the responsive, offline-capable local storage engine for retail counters.
/// Schema Version: 1
/// Tables:
/// - [Shops]: Tenant profile, operating timezone, and currency preference.
/// - [AppUsers]: Counter staff, permissions, and immediate session revocation (`session_version`).
/// - [SyncQueue]: Asynchronous offline synchronization queue with UUIDv4 idempotency keys.
@DriftDatabase(tables: [Shops, AppUsers, SyncQueue])
class AppDatabase extends _$AppDatabase {
  /// Default constructor connecting via application sandboxed storage.
  AppDatabase() : super(AppDatabaseConnection.openConnection());

  /// Testing constructor allowing dependency injection of an isolated [QueryExecutor]
  /// (e.g. [AppDatabaseConnection.openInMemoryConnection]).
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    beforeOpen: (OpeningDetails details) async {
      // Guarantee SQLite foreign-key enforcement is active on every connection
      await customStatement('PRAGMA foreign_keys = ON;');
    },
  );
}
