import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/sync/models/sync_queue_entry.dart';

void main() {
  const testShopId = '11111111-1111-4111-8111-111111111111';
  const testEntityId = '22222222-2222-4222-8222-222222222222';

  group('SyncQueueEntry - Creation & Idempotency Key Invariants', () {
    test('SyncQueueEntry.create generates canonical UUIDv4 id and idempotencyKey', () {
      final entry = SyncQueueEntry.create(
        shopId: testShopId,
        entityType: 'credit',
        entityId: testEntityId,
        actionType: 'create_credit',
        payload: {'principal_minor_units': 5000000},
      );

      final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
      expect(uuidRegex.hasMatch(entry.id), isTrue);
      expect(uuidRegex.hasMatch(entry.idempotencyKey), isTrue);
      expect(entry.status, equals(SyncStatus.pendingServerAck));
      expect(entry.retryCount, equals(0));
      expect(entry.isPendingServerAck, isTrue);
      expect(entry.isConfirmedByServer, isFalse);
      expect(entry.isFailed, isFalse);
    });

    test('IDEMPOTENCY INVARIANT: retry preserves exact same idempotencyKey across multiple attempts', () {
      final entry = SyncQueueEntry.create(
        shopId: testShopId,
        entityType: 'payment',
        entityId: testEntityId,
        actionType: 'record_payment',
        payload: {'amount_minor_units': 200000},
      );

      final originalId = entry.id;
      final originalIdempotencyKey = entry.idempotencyKey;

      // First failure and retry
      final failedEntry = entry.markFailed('Network timeout');
      expect(failedEntry.isFailed, isTrue);
      expect(failedEntry.idempotencyKey, equals(originalIdempotencyKey));

      final retriedOnce = failedEntry.retry();
      expect(retriedOnce.status, equals(SyncStatus.pendingServerAck));
      expect(retriedOnce.retryCount, equals(1));
      expect(retriedOnce.id, equals(originalId));
      expect(retriedOnce.idempotencyKey, equals(originalIdempotencyKey), reason: 'Idempotency key must never change on retry');

      // Second failure and retry
      final secondFailure = retriedOnce.markFailed('Server busy');
      final retriedTwice = secondFailure.retry();
      expect(retriedTwice.retryCount, equals(2));
      expect(retriedTwice.idempotencyKey, equals(originalIdempotencyKey), reason: 'Idempotency key must stay permanent across all retries');
    });

    test('VALIDATION: rejects malformed UUID identifiers', () {
      expect(
        () => SyncQueueEntry.create(
          shopId: 'not-a-uuid',
          entityType: 'credit',
          entityId: testEntityId,
          actionType: 'create_credit',
          payload: {},
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => SyncQueueEntry.create(
          shopId: testShopId,
          entityType: 'credit',
          entityId: 'invalid-entity-uuid',
          actionType: 'create_credit',
          payload: {},
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('VALIDATION: rejects empty entityType or actionType', () {
      expect(
        () => SyncQueueEntry.create(
          shopId: testShopId,
          entityType: '',
          entityId: testEntityId,
          actionType: 'create_credit',
          payload: {},
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => SyncQueueEntry.create(
          shopId: testShopId,
          entityType: 'credit',
          entityId: testEntityId,
          actionType: '   ',
          payload: {},
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('SyncQueueEntry - Lifecycle & Status Transition Invariants', () {
    test('pending_server_ack -> confirmed_by_server is valid and sets updatedAt', () {
      final entry = SyncQueueEntry.create(
        shopId: testShopId,
        entityType: 'credit',
        entityId: testEntityId,
        actionType: 'create_credit',
        payload: {},
      );

      final confirmedAt = DateTime.utc(2026, 10, 14, 14, 0, 0);
      final confirmed = entry.markConfirmed(confirmedAt: confirmedAt);

      expect(confirmed.status, equals(SyncStatus.confirmedByServer));
      expect(confirmed.isConfirmedByServer, isTrue);
      expect(confirmed.isPendingServerAck, isFalse);
      expect(confirmed.isFailed, isFalse);
      expect(confirmed.updatedAt, equals(confirmedAt));
    });

    test('markConfirmed on already confirmed entry is idempotent', () {
      final entry = SyncQueueEntry.create(
        shopId: testShopId,
        entityType: 'credit',
        entityId: testEntityId,
        actionType: 'create_credit',
        payload: {},
      ).markConfirmed();

      final reconfirmed = entry.markConfirmed();
      expect(reconfirmed.status, equals(SyncStatus.confirmedByServer));
    });

    test('ILLEGAL TRANSITION: failed -> confirmed_by_server directly throws InvalidSyncStatusTransitionException', () {
      final failedEntry = SyncQueueEntry.create(
        shopId: testShopId,
        entityType: 'credit',
        entityId: testEntityId,
        actionType: 'create_credit',
        payload: {},
      ).markFailed('HTTP 500');

      expect(failedEntry.isFailed, isTrue);
      expect(
        () => failedEntry.markConfirmed(),
        throwsA(isA<InvalidSyncStatusTransitionException>()),
      );
    });

    test('ILLEGAL TRANSITION: confirmed_by_server cannot transition to failed', () {
      final confirmedEntry = SyncQueueEntry.create(
        shopId: testShopId,
        entityType: 'credit',
        entityId: testEntityId,
        actionType: 'create_credit',
        payload: {},
      ).markConfirmed();

      expect(
        () => confirmedEntry.markFailed('Late network glitch'),
        throwsA(isA<InvalidSyncStatusTransitionException>()),
      );
    });

    test('ILLEGAL TRANSITION: confirmed_by_server cannot be retried', () {
      final confirmedEntry = SyncQueueEntry.create(
        shopId: testShopId,
        entityType: 'credit',
        entityId: testEntityId,
        actionType: 'create_credit',
        payload: {},
      ).markConfirmed();

      expect(
        () => confirmedEntry.retry(),
        throwsA(isA<InvalidSyncStatusTransitionException>()),
      );
    });
  });

  group('SyncQueueEntry - Serialization & Malformed Input Handling', () {
    test('toMap and fromMap serialize and deserialize cleanly', () {
      final original = SyncQueueEntry.create(
        shopId: testShopId,
        entityType: 'credit',
        entityId: testEntityId,
        actionType: 'create_credit',
        payload: {
          'principal_minor_units': 5000000,
          'duration_days': 30,
          'customer_name': 'Sunil Silva',
        },
      );

      final map = original.toMap();
      final restored = SyncQueueEntry.fromMap(map);

      expect(restored.id, equals(original.id));
      expect(restored.shopId, equals(original.shopId));
      expect(restored.idempotencyKey, equals(original.idempotencyKey));
      expect(restored.entityType, equals(original.entityType));
      expect(restored.entityId, equals(original.entityId));
      expect(restored.actionType, equals(original.actionType));
      expect(restored.payload, equals(original.payload));
      expect(restored.status, equals(original.status));
      expect(restored.retryCount, equals(original.retryCount));
      expect(restored.createdAt, equals(original.createdAt));
    });

    test('fromMap parses raw JSON string in payload_json correctly', () {
      final map = {
        'id': '33333333-3333-4333-8333-333333333333',
        'shop_id': testShopId,
        'idempotency_key': '44444444-4444-4444-8444-444444444444',
        'entity_type': 'collateral',
        'entity_id': testEntityId,
        'action_type': 'intake_item',
        'payload_json': '{"weight_grams": 12.45, "hallmark": "22K"}',
        'status': 'pending_server_ack',
        'retry_count': 0,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      final entry = SyncQueueEntry.fromMap(map);
      expect(entry.payload['weight_grams'], equals(12.45));
      expect(entry.payload['hallmark'], equals('22K'));
    });

    test('fromMap throws FormatException when payload_json is malformed JSON', () {
      final map = {
        'id': '33333333-3333-4333-8333-333333333333',
        'shop_id': testShopId,
        'idempotency_key': '44444444-4444-4444-8444-444444444444',
        'entity_type': 'credit',
        'entity_id': testEntityId,
        'action_type': 'create_credit',
        'payload_json': '{unquoted_broken_json: 123',
        'status': 'pending_server_ack',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      expect(
        () => SyncQueueEntry.fromMap(map),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('SyncQueueEntry - Diagnostic Privacy Protection', () {
    test('DIAGNOSTIC PRIVACY: toString and toDiagnosticString strictly omit sensitive payload data', () {
      final sensitiveEntry = SyncQueueEntry.create(
        shopId: testShopId,
        entityType: 'customer',
        entityId: testEntityId,
        actionType: 'register_customer',
        payload: {
          'nic': '198512345678',
          'phone': '+94771234567',
          'address': 'No. 45 Temple Road Colombo',
          'auth_token': 'secret_bearer_token_xyz',
          'password': 'super_secret_password',
        },
      );

      final diagnosticStr = sensitiveEntry.toDiagnosticString();
      final defaultToString = sensitiveEntry.toString();

      // Ensure NO sensitive data appears in string representations
      expect(diagnosticStr.contains('198512345678'), isFalse);
      expect(diagnosticStr.contains('+94771234567'), isFalse);
      expect(diagnosticStr.contains('Temple Road'), isFalse);
      expect(diagnosticStr.contains('secret_bearer_token'), isFalse);
      expect(diagnosticStr.contains('super_secret_password'), isFalse);

      expect(defaultToString.contains('198512345678'), isFalse);
      expect(defaultToString.contains('+94771234567'), isFalse);

      // Verify that diagnostic info contains metadata and payload byte size only
      expect(diagnosticStr.contains('payloadSize:'), isTrue);
      expect(diagnosticStr.contains('entityType: customer'), isTrue);
      expect(diagnosticStr.contains('actionType: register_customer'), isTrue);
    });
  });
}

