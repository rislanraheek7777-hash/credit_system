import 'package:drift/drift.dart';
import 'shops_table.dart';

/// Local SQLite schema for the offline synchronization queue.
///
/// Binds: Architecture Decisions AD-1 and AD-4; PRD FR-4, FR-23.
///
/// Offline counter actions are inserted into this queue as part of local ACID
/// transactions. Every queued item receives a client-generated UUIDv4 idempotency
/// key and defaults to [status] = 'pending_server_ack'.
///
/// Items are transitioned to 'confirmed_by_server' strictly upon receipt of an
/// authoritative signed acknowledgement from the cloud PostgreSQL backend.
@DataClassName('SyncQueueRecord')
@TableIndex(name: 'idx_sync_queue_shop_status', columns: {#shopId, #status})
@TableIndex(name: 'idx_sync_queue_idempotency', columns: {#shopId, #idempotencyKey})
class SyncQueue extends Table {
  /// Canonical UUIDv4 primary key.
  TextColumn get id => text()();

  /// Foreign key referencing the originating shop tenant.
  TextColumn get shopId =>
      text().references(Shops, #id, onDelete: KeyAction.restrict)();

  /// Client-generated UUIDv4 idempotency key to prevent duplicate processing.
  TextColumn get idempotencyKey => text()();

  /// Logical type of the entity being synchronized (e.g. 'loan', 'payment', 'customer').
  TextColumn get entityType => text().withLength(min: 1, max: 100)();

  /// Canonical UUIDv4 identifier of the target domain entity.
  TextColumn get entityId => text()();

  /// Verb / operation type (e.g. 'create_loan', 'disburse_loan', 'record_payment').
  TextColumn get actionType => text().withLength(min: 1, max: 100)();

  /// Serialized JSON payload containing the operational mutation parameters.
  TextColumn get payloadJson => text()();

  /// Lifecycle synchronization status:
  /// - 'pending_server_ack': Operation recorded locally; awaiting cloud server acknowledgment.
  /// - 'confirmed_by_server': Cloud PostgreSQL has confirmed transaction durability.
  /// - 'failed': Sync attempt encountered a fatal error requiring intervention or retry exhaustion.
  TextColumn get status =>
      text().withDefault(const Constant('pending_server_ack'))();

  /// Monotonically increasing count of failed transmission attempts.
  IntColumn get retryCount =>
      integer().withDefault(const Constant(0))();

  /// Diagnostic error message from the most recent failed synchronization attempt.
  TextColumn get lastError => text().nullable()();

  /// UTC timestamp when the local operation was queued.
  DateTimeColumn get createdAt => dateTime()();

  /// UTC timestamp of the last synchronization attempt or status change.
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {shopId, idempotencyKey},
  ];

  @override
  List<String> get customConstraints => [
    "CHECK (status IN ('pending_server_ack', 'confirmed_by_server', 'failed'))",
    'CHECK (retry_count >= 0)',
  ];
}
