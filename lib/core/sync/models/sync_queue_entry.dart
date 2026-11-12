import 'dart:convert';
import 'package:uuid/uuid.dart';

/// Standard UUID generator instance.
const _uuid = Uuid();

/// Standard UUID format validator regex.
final _uuidRegex = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Synchronization status lifecycle for offline queue operations.
///
/// Binds: Architecture Decisions AD-1 and AD-4; PRD FR-4, FR-23.
enum SyncStatus {
  /// Operation successfully persisted in local SQLite; awaiting cloud server transmission and acknowledgment.
  pendingServerAck('pending_server_ack'),

  /// Authoritative PostgreSQL server confirmed transaction durability and assigned sequence/receipt numbers.
  /// This state is terminal. Confirmed operations cannot be altered or retried.
  confirmedByServer('confirmed_by_server'),

  /// Transmission or cloud processing failed. Eligible for scheduled or manual retry.
  failed('failed');

  final String value;
  const SyncStatus(this.value);

  /// Resolves [SyncStatus] from raw database text.
  static SyncStatus fromValue(String value) {
    for (final status in SyncStatus.values) {
      if (status.value == value) {
        return status;
      }
    }
    throw ArgumentError.value(value, 'value', 'Invalid SyncStatus string representation');
  }
}

/// Thrown when an illegal state transition is attempted on a [SyncQueueEntry].
class InvalidSyncStatusTransitionException implements Exception {
  final SyncStatus from;
  final SyncStatus to;
  final String reason;

  const InvalidSyncStatusTransitionException(this.from, this.to, [this.reason = '']);

  @override
  String toString() =>
      'InvalidSyncStatusTransitionException: Cannot transition from "${from.value}" to "${to.value}". $reason';
}

/// Domain entity representing a queued operational mutation awaiting cloud synchronization.
///
/// ==============================================================================
/// Architectural Invariant - Asymmetric Transaction Boundaries (AD-1):
/// ==============================================================================
/// 1. Decoupled ACID Transactions:
///    - Local SQLite commit: When a counter action is performed, local database
///      changes and this [SyncQueueEntry] are committed within a single local SQLite
///      ACID transaction.
///    - Remote PostgreSQL commit: The remote cloud synchronization executes in a
///      completely separate, asynchronous server transaction.
/// 2. Non-Distributed Guarantee:
///    - Local commit does NOT imply remote server acceptance.
///    - Queued items remain strictly in [SyncStatus.pendingServerAck] until an explicit,
///      signed acknowledgement is received from the cloud PostgreSQL instance.
/// 3. Idempotency Invariant:
///    - The [idempotencyKey] generated at creation is permanent and invariant.
///    - Retries across network drops or timeouts MUST reuse the exact same [idempotencyKey].
///    - The PostgreSQL server enforces UNIQUE(shop_id, idempotency_key) to silently discard duplicates.
/// ==============================================================================
class SyncQueueEntry {
  /// Canonical UUIDv4 identifier of the queue record.
  final String id;

  /// Foreign key identifying the originating shop tenant.
  final String shopId;

  /// Client-generated UUIDv4 idempotency key to prevent duplicate processing.
  final String idempotencyKey;

  /// Target entity category (e.g. 'credit', 'payment', 'customer', 'collateral').
  final String entityType;

  /// Canonical UUIDv4 identifier of the target domain entity.
  final String entityId;

  /// Operation verb (e.g. 'create_credit', 'disburse_credit', 'record_payment').
  final String actionType;

  /// Unmodifiable operational mutation parameters.
  final Map<String, dynamic> payload;

  /// Current lifecycle synchronization status.
  final SyncStatus status;

  /// Count of failed transmission attempts.
  final int retryCount;

  /// Diagnostic error message from the most recent failed transmission.
  final String? lastError;

  /// UTC timestamp when the local operation was originally queued.
  final DateTime createdAt;

  /// UTC timestamp of the most recent status transition or retry attempt.
  final DateTime? updatedAt;

  SyncQueueEntry({
    required this.id,
    required this.shopId,
    required this.idempotencyKey,
    required this.entityType,
    required this.entityId,
    required this.actionType,
    required Map<String, dynamic> payload,
    this.status = SyncStatus.pendingServerAck,
    this.retryCount = 0,
    this.lastError,
    required this.createdAt,
    this.updatedAt,
  }) : payload = Map.unmodifiable(payload) {
    _validateUuid(id, 'id');
    _validateUuid(shopId, 'shopId');
    _validateUuid(idempotencyKey, 'idempotencyKey');
    _validateUuid(entityId, 'entityId');

    if (entityType.trim().isEmpty) {
      throw ArgumentError.value(entityType, 'entityType', 'entityType cannot be empty');
    }
    if (actionType.trim().isEmpty) {
      throw ArgumentError.value(actionType, 'actionType', 'actionType cannot be empty');
    }
    if (retryCount < 0) {
      throw ArgumentError.value(retryCount, 'retryCount', 'retryCount cannot be negative');
    }
  }

  /// Factory constructing a fresh queue entry with newly generated UUIDv4 keys.
  factory SyncQueueEntry.create({
    required String shopId,
    required String entityType,
    required String entityId,
    required String actionType,
    required Map<String, dynamic> payload,
    String? id,
    String? idempotencyKey,
    DateTime? createdAt,
  }) {
    return SyncQueueEntry(
      id: id ?? _uuid.v4(),
      shopId: shopId,
      idempotencyKey: idempotencyKey ?? _uuid.v4(),
      entityType: entityType,
      entityId: entityId,
      actionType: actionType,
      payload: payload,
      status: SyncStatus.pendingServerAck,
      retryCount: 0,
      lastError: null,
      createdAt: (createdAt ?? DateTime.now()).toUtc(),
      updatedAt: null,
    );
  }

  /// Serialized JSON string of the payload.
  String get payloadJson => jsonEncode(payload);

  /// Status helpers
  bool get isPendingServerAck => status == SyncStatus.pendingServerAck;
  bool get isConfirmedByServer => status == SyncStatus.confirmedByServer;
  bool get isFailed => status == SyncStatus.failed;

  /// Transitions state to [SyncStatus.confirmedByServer].
  ///
  /// Throws [InvalidSyncStatusTransitionException] if current state is [SyncStatus.failed],
  /// as failed operations must be retried into [SyncStatus.pendingServerAck] before confirmation.
  SyncQueueEntry markConfirmed({DateTime? confirmedAt}) {
    if (status == SyncStatus.confirmedByServer) {
      return this; // Idempotent
    }
    if (status == SyncStatus.failed) {
      throw const InvalidSyncStatusTransitionException(
        SyncStatus.failed,
        SyncStatus.confirmedByServer,
        'Failed operation cannot be confirmed directly without re-transmission.',
      );
    }

    return _copyWith(
      status: SyncStatus.confirmedByServer,
      updatedAt: (confirmedAt ?? DateTime.now()).toUtc(),
    );
  }

  /// Transitions state to [SyncStatus.failed].
  ///
  /// Throws [InvalidSyncStatusTransitionException] if current state is [SyncStatus.confirmedByServer],
  /// as confirmed operations are permanently durable and cannot fail.
  SyncQueueEntry markFailed(String error, {DateTime? failedAt}) {
    if (status == SyncStatus.confirmedByServer) {
      throw const InvalidSyncStatusTransitionException(
        SyncStatus.confirmedByServer,
        SyncStatus.failed,
        'Operation already confirmed by server cannot be marked failed.',
      );
    }

    return _copyWith(
      status: SyncStatus.failed,
      lastError: error,
      updatedAt: (failedAt ?? DateTime.now()).toUtc(),
    );
  }

  /// Prepares the operation for re-transmission.
  ///
  /// INCREMENTS [retryCount] by 1 and transitions status back to [SyncStatus.pendingServerAck].
  /// CRITICAL: Preserves the exact same [idempotencyKey] across retries to prevent duplicate processing.
  ///
  /// Throws [InvalidSyncStatusTransitionException] if operation is already confirmed.
  SyncQueueEntry retry({DateTime? retriedAt}) {
    if (status == SyncStatus.confirmedByServer) {
      throw const InvalidSyncStatusTransitionException(
        SyncStatus.confirmedByServer,
        SyncStatus.pendingServerAck,
        'Cannot retry an operation already confirmed by server.',
      );
    }

    return _copyWith(
      status: SyncStatus.pendingServerAck,
      retryCount: retryCount + 1,
      updatedAt: (retriedAt ?? DateTime.now()).toUtc(),
    );
  }

  /// Deserializes database record map into a typed [SyncQueueEntry].
  factory SyncQueueEntry.fromMap(Map<String, dynamic> map) {
    final rawPayload = map['payload_json'] ?? map['payload'];
    final Map<String, dynamic> parsedPayload;

    if (rawPayload is Map) {
      parsedPayload = Map<String, dynamic>.from(rawPayload);
    } else if (rawPayload is String) {
      try {
        parsedPayload = Map<String, dynamic>.from(jsonDecode(rawPayload) as Map);
      } catch (e) {
        throw FormatException('Malformed payload_json in sync queue record: $e');
      }
    } else {
      throw const FormatException('Missing or invalid payload in sync queue record');
    }

    return SyncQueueEntry(
      id: map['id'] as String,
      shopId: map['shop_id'] as String,
      idempotencyKey: map['idempotency_key'] as String,
      entityType: map['entity_type'] as String,
      entityId: map['entity_id'] as String,
      actionType: map['action_type'] as String,
      payload: parsedPayload,
      status: SyncStatus.fromValue(map['status'] as String),
      retryCount: map['retry_count'] as int? ?? 0,
      lastError: map['last_error'] as String?,
      createdAt: map['created_at'] is DateTime
          ? map['created_at'] as DateTime
          : DateTime.parse(map['created_at'].toString()),
      updatedAt: map['updated_at'] == null
          ? null
          : (map['updated_at'] is DateTime
              ? map['updated_at'] as DateTime
              : DateTime.parse(map['updated_at'].toString())),
    );
  }

  /// Serializes entity to database row map.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'shop_id': shopId,
      'idempotency_key': idempotencyKey,
      'entity_type': entityType,
      'entity_id': entityId,
      'action_type': actionType,
      'payload_json': payloadJson,
      'status': status.value,
      'retry_count': retryCount,
      'last_error': lastError,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  /// Internal copy helper preserving immutable fields.
  SyncQueueEntry _copyWith({
    SyncStatus? status,
    int? retryCount,
    String? lastError,
    DateTime? updatedAt,
  }) {
    return SyncQueueEntry(
      id: id,
      shopId: shopId,
      idempotencyKey: idempotencyKey,
      entityType: entityType,
      entityId: entityId,
      actionType: actionType,
      payload: payload,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Diagnostic representation that strictly omits payload contents to prevent
  /// personal identity data (NICs, phone numbers, photos, tokens) from leaking into logs.
  String toDiagnosticString() {
    return 'SyncQueueEntry('
        'id: $id, '
        'shopId: $shopId, '
        'idempotencyKey: $idempotencyKey, '
        'entityType: $entityType, '
        'entityId: $entityId, '
        'actionType: $actionType, '
        'status: ${status.value}, '
        'retryCount: $retryCount, '
        'payloadSize: ${payloadJson.length} bytes, '
        'createdAt: ${createdAt.toIso8601String()})';
  }

  @override
  String toString() => toDiagnosticString();

  static void _validateUuid(String value, String fieldName) {
    if (!_uuidRegex.hasMatch(value)) {
      throw ArgumentError.value(
        value,
        fieldName,
        'Must be a valid canonical UUID format (8-4-4-4-12 hex characters)',
      );
    }
  }
}

