import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

import 'audit.dart';
import 'config.dart';
import 'database.dart';
import 'delivery.dart';
import 'otp.dart';
import 'reference.dart';

/// The two-route HTTP contract of the recovery authority.
///
/// `/request` and `/verify` are the only routes. There is no `/deliver`: the
/// code is delivered inside `/request` from the destination stored in
/// PostgreSQL. Every `/request` outcome returns the identical acknowledgement,
/// and every `/verify` failure returns the identical generic error.
class RecoveryRoutes {
  RecoveryRoutes({
    required this._database,
    required this._auditor,
    required this._otp,
    required this._reference,
    required this._delivery,
    required this._passwordHasher,
  });

  final RecoveryDatabase _database;
  final RecoveryAuditor _auditor;
  final OtpAuthority _otp;
  final OperationReference _reference;
  final RecoveryDelivery _delivery;
  final PasswordHasher _passwordHasher;

  static const int _minPasswordLength = 8;
  static const int _maxBodyBytes = 16 * 1024;
  static const int _maxResolverCallsPerWindow = 60;
  static const int _maxDeliveryCallsPerWindow = 30;
  static const int _maxVerifyCallsPerWindow = 20;
  static const int _maxVerifyCallsPerWindowTotal = 200;
  static const Duration _window = Duration(minutes: 15);

  // Operational metadata only: never an OTP, a pepper, or a credential. Keys
  // are pruned when their window empties, and budgets are scoped to an
  // identifier (resolver/verify) or a resolved tenant (delivery).
  final Map<String, Queue<int>> _resolverCalls = <String, Queue<int>>{};
  final Map<String, Queue<int>> _deliveryCalls = <String, Queue<int>>{};
  final Map<String, Queue<int>> _verifyCalls = <String, Queue<int>>{};
  final Map<String, Queue<int>> _verifyGlobalCalls = <String, Queue<int>>{};

  Handler get handler => _handle;

  /// Last-resort boundary: no unexpected failure may escape as a 500 with a
  /// stack trace, provider error, or tenant detail.
  Future<Response> _handle(Request request) async {
    try {
      return await _dispatch(request);
    } catch (_) {
      return _badRequest();
    }
  }

  Future<Response> _dispatch(Request request) async {
    final path = request.url.path.replaceFirst(RegExp(r'^/'), '');

    // Health/readiness are GET-only; unknown paths stay 404 for any method.
    if (path == 'health' || path == 'ready') {
      if (request.method != 'GET') {
        return _methodNotAllowed('GET');
      }
      if (path == 'health') {
        return _json(200, <String, dynamic>{'status': 'ok'});
      }
      try {
        await _database.query('SELECT 1');
        return _json(200, <String, dynamic>{'ready': true});
      } catch (_) {
        return _json(503, <String, dynamic>{'ready': false});
      }
    }

    if (path != 'request' && path != 'verify') {
      return _json(404, <String, dynamic>{'error': 'not_found'});
    }
    if (request.method != 'POST') {
      return _methodNotAllowed('POST');
    }

    Map<String, dynamic> payload;
    try {
      final body = await _readBody(request);
      if (body == null) return _badRequest();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return _badRequest();
      // Coerce every expected field to String? before routing: a non-string
      // JSON value must be a generic 400, never a cast error (500).
      payload = <String, dynamic>{
        for (final key in const <String>[
          'identifier',
          'channel',
          'client_operation_id',
          'idempotency_key',
          'otp',
          'new_password',
        ])
          key: _stringField(decoded, key),
      };
    } catch (_) {
      return _badRequest();
    }

    switch (path) {
      case 'request':
        return await _request(payload);
      case 'verify':
        return await _verify(payload);
      default:
        return _json(404, <String, dynamic>{'error': 'not_found'});
    }
  }

  String? _stringField(Map<String, dynamic> decoded, String key) {
    final value = decoded[key];
    if (value == null) return null;
    if (value is! String) throw const FormatException('non-string field');
    return value;
  }

  /// Reads no more than [_maxBodyBytes] before any JSON parsing happens.
  /// Malformed UTF-8 raises [FormatException], caught by [_handle].
  Future<String?> _readBody(Request request) async {
    final builder = BytesBuilder();
    await for (final chunk in request.read()) {
      builder.add(chunk);
      if (builder.length > _maxBodyBytes) return null;
    }
    return utf8.decode(builder.takeBytes(), allowMalformed: false);
  }

  /// Resolves the identifier, reserves a challenge atomically, generates and
  /// hashes the code only after an authoritative `created` status, then
  /// delivers it from the destination held by PostgreSQL.
  Future<Response> _request(Map<String, dynamic> payload) async {
    final identifier = (payload['identifier'] as String? ?? '').trim();
    final channel = payload['channel'] as String? ?? '';
    final operationId = payload['client_operation_id'] as String? ?? '';
    final idempotencyKey = payload['idempotency_key'] as String? ?? '';

    if (identifier.isEmpty ||
        (channel != 'email' && channel != 'sms') ||
        !isUuid(operationId) ||
        !isUuid(idempotencyKey)) {
      return _badRequest();
    }

    // Every outcome — including an audit or lookup failure before the normal
    // transaction try — must return the identical acknowledgement.
    try {
    var auditAttempted = false;
    Future<void> abuseOnce(String action, String reason) async {
      if (auditAttempted) return;
      auditAttempted = true;
      await _auditor.appendAbuse(action: action, reason: reason);
    }

    final identifierHash = base64Url.encode(utf8.encode(identifier.toLowerCase()));
    if (!_allow(_resolverCalls, identifierHash, _maxResolverCallsPerWindow)) {
      await abuseOnce('credential_recovery_resolver_throttled',
          'Resolver request limit exceeded');
      return _ack(operationId, idempotencyKey);
    }

    try {
      final identities = await _database.query(
        'SELECT shop_id, user_id, destination, match_count '
        'FROM public.cs_resolve_recovery_identity(@p0, @p1)',
        [identifier, channel],
      );
      if (identities.isEmpty) return _ack(operationId, idempotencyKey);

      final identity = identities.first;
      final shopId = identity['shop_id'] as String;
      final userId = identity['user_id'] as String;
      final matchCount = identity['match_count'] as int? ?? 1;
      final destination = identity['destination'] as String? ?? '';

      if (matchCount > 1) {
        // Multiple tenants matched, so no real tenant may receive this event.
        await abuseOnce(
            'credential_recovery_identity_rejected', 'Ambiguous recovery identifier');
        return _ack(operationId, idempotencyKey);
      }
      if (!RecoveryDelivery.isValidDestination(channel, destination)) {
        await _auditor.append(
          shopId,
          category: RecoveryCategories.abuse,
          action: 'credential_recovery_invalid_contact',
          targetUserId: userId,
          reason: 'Invalid verified contact channel',
        );
        auditAttempted = true;
        return _ack(operationId, idempotencyKey);
      }

      final rows = await _database.transactionWithTenant(shopId, (tx) async {
        return tx.query(
          'SELECT stored_operation_id, stored_idempotency_key, status '
          'FROM public.cs_create_recovery_challenge('
          '@p0::uuid, @p1::uuid, @p2, @p3, @p4::uuid, @p5::uuid)',
          [shopId, userId, channel, destination, operationId, idempotencyKey],
        );
      });
      if (rows.isEmpty) return _ack(operationId, idempotencyKey);

      final storedOperationId = rows.first['stored_operation_id'] as String;
      final storedIdempotencyKey =
          rows.first['stored_idempotency_key'] as String;
      final status = rows.first['status'] as String;

      if (status != 'created') {
        // A crash between create and finalize leaves a reserved challenge with
        // no reference digest. Re-finalize and re-deliver it so the idempotency
        // key cannot be locked out forever.
        if (status == 'existing') {
          await _recoverUnfinished(
            shopId,
            storedOperationId,
            userId,
            destination,
            channel,
            storedIdempotencyKey,
          );
        }
        return _ack(storedOperationId, storedIdempotencyKey);
      }

      final otp = _otp.generate();
      List<Map<String, dynamic>> finalized;
      try {
        finalized = await _database.transactionWithTenant(shopId, (tx) async {
          final expiry = await tx.query(
            'SELECT expires_at FROM public.credential_recovery_challenges '
            'WHERE client_operation_id = @p0::uuid',
            [storedOperationId],
          );
          if (expiry.isEmpty) return <Map<String, dynamic>>[];
          final digest = _reference.digestFor(
            storedOperationId,
            expiry.first['expires_at'],
          );
          return tx.query(
            'SELECT destination, channel, shop_id, user_id '
            'FROM public.cs_finalize_recovery_challenge(@p0::uuid, @p1, @p2)',
            [storedOperationId, _otp.hash(otp), digest],
          );
        });
      } catch (_) {
        return await _failReservation(
          shopId,
          storedOperationId,
          userId,
          'credential_recovery_finalization_failed',
          'Recovery challenge finalization failed',
          storedIdempotencyKey,
        );
      }
      if (finalized.isEmpty) {
        return await _failReservation(
          shopId,
          storedOperationId,
          userId,
          'credential_recovery_finalization_failed',
          'Recovery challenge finalization failed',
          storedIdempotencyKey,
        );
      }

      final record = finalized.first;
      final storedDestination = record['destination'] as String;
      final storedChannel = record['channel'] as String;
      final deliveryShopId = record['shop_id'] as String;
      final deliveryUserId = record['user_id'] as String;

      if (!_allow(_deliveryCalls, deliveryShopId, _maxDeliveryCallsPerWindow)) {
        return await _failReservation(
          deliveryShopId,
          storedOperationId,
          deliveryUserId,
          'credential_recovery_delivery_throttled',
          'Delivery request limit exceeded',
          storedIdempotencyKey,
        );
      }

      try {
        await _delivery.send(
          channel: storedChannel,
          destination: storedDestination,
          otp: otp,
        );
      } catch (_) {
        return await _failReservation(
          deliveryShopId,
          storedOperationId,
          deliveryUserId,
          'credential_recovery_delivery_failed',
          'Recovery code delivery failed',
          storedIdempotencyKey,
        );
      }

      return _ack(storedOperationId, storedIdempotencyKey);
    } catch (_) {
      // Any unexpected failure still records one security event, then returns
      // the generic acknowledgement — no silent catch paths.
      try {
        await abuseOnce(
          'credential_recovery_request_failed',
          'Credential recovery request failed',
        );
      } catch (_) {
        // Audit channel unavailable; no challenge was issued, keep generic ack.
      }
      return _ack(operationId, idempotencyKey);
    }
    } catch (_) {
      return _ack(operationId, idempotencyKey);
    }
  }

  /// Completes a challenge that was reserved but never finalized/delivered
  /// (e.g. the process crashed between those steps).
  Future<void> _recoverUnfinished(
    String shopId,
    String operationId,
    String userId,
    String destination,
    String channel,
    String idempotencyKey,
  ) async {
    try {
      final rows = await _database.transactionWithTenant(shopId, (tx) async {
        return tx.query(
          'SELECT expires_at, delivery_reference_hash, consumed_at '
          'FROM public.credential_recovery_challenges '
          'WHERE client_operation_id = @p0::uuid FOR UPDATE',
          [operationId],
        );
      });
      if (rows.isEmpty || rows.first['delivery_reference_hash'] != null) return;
      if (rows.first['consumed_at'] != null) return;
      final expiry = rows.first['expires_at'];
      if (expiry is DateTime &&
          !expiry.toUtc().isAfter(DateTime.now().toUtc())) {
        return;
      }
      final otp = _otp.generate();
      await _database.transactionWithTenant(shopId, (tx) async {
        await tx.query(
          'SELECT destination FROM public.cs_finalize_recovery_challenge('
          '@p0::uuid, @p1, @p2)',
          [
            operationId,
            _otp.hash(otp),
            _reference.digestFor(operationId, expiry),
          ],
        );
      });
      if (!_allow(_deliveryCalls, shopId, _maxDeliveryCallsPerWindow)) {
        await _failReservation(
          shopId,
          operationId,
          userId,
          'credential_recovery_delivery_throttled',
          'Delivery request limit exceeded',
          idempotencyKey,
        );
        return;
      }
      try {
        await _delivery.send(
          channel: channel,
          destination: destination,
          otp: otp,
        );
      } catch (_) {
        await _failReservation(
          shopId,
          operationId,
          userId,
          'credential_recovery_delivery_failed',
          'Recovery code delivery failed',
          idempotencyKey,
        );
      }
    } catch (_) {
      await _failReservation(
        shopId,
        operationId,
        userId,
        'credential_recovery_request_failed',
        'Credential recovery request failed',
        idempotencyKey,
      );
    }
  }

  /// Deletes an orphaned challenge and appends exactly one Category 14 event,
  /// then returns the generic acknowledgement. If the tenant-scoped append
  /// cannot complete, one abuse-shop event is attempted instead.
  Future<Response> _failReservation(
    String shopId,
    String operationId,
    String userId,
    String action,
    String reason,
    String idempotencyKey,
  ) async {
    try {
      await _database.transactionWithTenant(shopId, (tx) async {
        // Clear the idempotency ledger too, so a retry with the same key can
        // reserve a fresh challenge instead of replaying a deleted one.
        await tx.execute(
          'DELETE FROM public.credential_recovery_operations '
          'WHERE client_operation_id = @p0::uuid',
          [operationId],
        );
        await tx.execute(
          'DELETE FROM public.credential_recovery_challenges '
          'WHERE client_operation_id = @p0::uuid',
          [operationId],
        );
        await _auditor.appendInTransaction(
          tx,
          shopId: shopId,
          category: RecoveryCategories.abuse,
          action: action,
          targetUserId: userId,
          reason: reason,
        );
      });
    } catch (_) {
      // Fallback must also remove the finalized challenge and its ledger row;
      // appending an event alone would leave a live, undelivered challenge.
      try {
        await _database.transactionWithTenant(shopId, (tx) async {
          await tx.execute(
            'DELETE FROM public.credential_recovery_operations '
            'WHERE client_operation_id = @p0::uuid',
            [operationId],
          );
          await tx.execute(
            'DELETE FROM public.credential_recovery_challenges '
            'WHERE client_operation_id = @p0::uuid',
            [operationId],
          );
        });
      } catch (_) {
        // Best effort: the caller still receives only the generic ack.
      }
      try {
        await _auditor.appendAbuse(action: action, reason: reason);
      } catch (_) {
        // A single append was attempted; nothing further can be disclosed.
      }
    }
    return _ack(operationId, idempotencyKey);
  }

  /// Verifies the submitted code against the peppered digest in PostgreSQL,
  /// then rotates the password hash and `session_version` inside one
  /// transaction. Every failure is indistinguishable to the caller.
  Future<Response> _verify(Map<String, dynamic> payload) async {
    final operationId = (payload['client_operation_id'] as String? ?? '').trim();
    final otp = (payload['otp'] as String? ?? '').trim();
    final newPassword = payload['new_password'] as String? ?? '';

    if (!isUuid(operationId) ||
        otp.isEmpty ||
        newPassword.length < _minPasswordLength) {
      return _badRequest();
    }

    // Throttle before any audit append or transaction: abusive probes cannot
    // generate unbounded Category 14 events or DB work.
    if (!_allow(
      _verifyCalls,
      base64Url.encode(utf8.encode(operationId.toLowerCase())),
      _maxVerifyCallsPerWindow,
    )) {
      return _failure();
    }
    // Rotating operation ids must not create unlimited audits/DB work.
    if (!_allow(
      _verifyGlobalCalls,
      'global',
      _maxVerifyCallsPerWindowTotal,
    )) {
      return _failure();
    }

    // Uniform failure body even if lookup or the abuse append throws here.
    try {
    var auditAttempted = false;
    Future<void> abuseOnce(String action, String reason) async {
      if (auditAttempted) return;
      auditAttempted = true;
      await _auditor.appendAbuse(action: action, reason: reason);
    }

    final rows = await _database.query(
      'SELECT client_operation_id, shop_id, user_id '
      'FROM public.cs_load_recovery_for_reference(@p0::uuid)',
      [operationId],
    );
    if (rows.isEmpty) {
      await abuseOnce(
        'credential_recovery_invalid_reference',
        'Unknown recovery operation id',
      );
      return _failure();
    }

    final record = rows.first;
    final shopId = record['shop_id'] as String;
    final userId = record['user_id'] as String;

    // Argon2 is deliberately computed before the row is locked.
    final passwordHash = _passwordHasher.hash(newPassword);

    try {
      final context = await _database.transactionWithTenant(shopId, (tx) async {
        // Lock the row and read the expiry so the reference digest can be
        // recomputed from the authoritative expiry value.
        final locked = await tx.query(
          'SELECT id, expires_at, attempts '
          'FROM public.credential_recovery_challenges '
          'WHERE client_operation_id = @p0::uuid FOR UPDATE',
          [operationId],
        );
        if (locked.isEmpty) {
          await _auditFailure(tx, shopId, userId);
          return null;
        }
        final digest = _reference.digestFor(
          operationId,
          locked.first['expires_at'],
        );

        // The digest and SQL-clock expiry are validated in the same statement
        // that locks the challenge. No hash or destination is returned.
        final state = await tx.query(
          'SELECT id, attempts, consumed_at, otp_hash, '
          '(NOW() < @p1::timestamptz) AS unexpired, '
          'EXISTS (SELECT 1 FROM public.app_users u '
          'WHERE u.id = @p2 AND u.shop_id = @p3 '
          'AND u.is_active AND u.password_hash IS NOT NULL) AS enrolled '
          'FROM public.credential_recovery_challenges '
          'WHERE client_operation_id = @p0::uuid '
          'AND delivery_reference_hash = @p4 FOR UPDATE',
          [operationId, locked.first['expires_at'], userId, shopId, digest],
        );
        if (state.isEmpty) {
          // Digest mismatch (or an unusable row) still burns an attempt and
          // consumes the challenge at the threshold — no free probe.
          final attempts = locked.first['attempts'] as int? ?? 0;
          final nextAttempts = attempts >= OtpAuthority.maxAttempts
              ? OtpAuthority.maxAttempts
              : attempts + 1;
          await tx.execute(
            'UPDATE public.credential_recovery_challenges '
            'SET attempts = @p0, '
            'consumed_at = CASE WHEN @p0 >= @p1 THEN NOW() ELSE consumed_at END '
            'WHERE id = @p2',
            [nextAttempts, OtpAuthority.maxAttempts, locked.first['id']],
          );
          await _auditFailure(tx, shopId, userId);
          return null;
        }

        final challenge = state.first;
        final challengeId = challenge['id'] as String;
        final attempts = challenge['attempts'] as int? ?? 0;
        final consumedAt = challenge['consumed_at'];
        final unexpired = challenge['unexpired'] == true;
        final enrolled = challenge['enrolled'] == true;
        final otpMatches = _otp.constantTimeEquals(
          challenge['otp_hash'] as String,
          _otp.hash(otp),
        );

        final valid = otpMatches &&
            unexpired &&
            enrolled &&
            consumedAt == null &&
            attempts < OtpAuthority.maxAttempts;

        if (!valid) {
          final nextAttempts = attempts >= OtpAuthority.maxAttempts
              ? OtpAuthority.maxAttempts
              : attempts + 1;
          final updated = await tx.execute(
            'UPDATE public.credential_recovery_challenges '
            'SET attempts = @p0, '
            'consumed_at = CASE WHEN @p0 >= @p1 THEN NOW() ELSE consumed_at END '
            'WHERE id = @p2',
            [nextAttempts, OtpAuthority.maxAttempts, challengeId],
          );
          if (updated != 1) {
            await tx.execute(
              'DELETE FROM public.credential_recovery_challenges WHERE id = @p0',
              [challengeId],
            );
          }
          await _auditFailure(tx, shopId, userId);
          return null;
        }

        final rotated = await tx.execute(
          'UPDATE public.app_users '
          'SET password_hash = @p0, '
          'session_version = session_version + 1, updated_at = NOW() '
          'WHERE id = @p1 AND shop_id = @p2',
          [passwordHash, userId, shopId],
        );
        if (rotated != 1) {
          await tx.execute(
            'DELETE FROM public.credential_recovery_challenges WHERE id = @p0',
            [challengeId],
          );
          await _auditFailure(tx, shopId, userId);
          return null;
        }

        final consumed = await tx.execute(
          'UPDATE public.credential_recovery_challenges '
          'SET consumed_at = NOW() WHERE id = @p0',
          [challengeId],
        );
        if (consumed != 1) {
          await tx.execute(
            'DELETE FROM public.credential_recovery_challenges WHERE id = @p0',
            [challengeId],
          );
          await _auditFailure(tx, shopId, userId);
          return null;
        }

        await _auditor.appendInTransaction(
          tx,
          shopId: shopId,
          category: RecoveryCategories.success,
          action: 'credential_password_reset',
          targetUserId: userId,
          reason: 'Credential recovery completed and sessions revoked',
        );

        // Minimal trusted context for fresh-device cache seeding. No password
        // hash, permission data, or challenge state is returned.
        final refreshed = await tx.query(
          'SELECT username, role, session_version FROM public.app_users '
          'WHERE id = @p0 AND shop_id = @p1',
          [userId, shopId],
        );
        if (refreshed.isEmpty) {
          // Throwing inside the transaction rolls back the password rotation:
          // the caller must never see failure after a successful reset.
          throw StateError('Trusted post-rotation context is unavailable');
        }
        return <String, dynamic>{
          'userId': userId,
          'shopId': shopId,
          'username': refreshed.first['username'],
          'role': refreshed.first['role'],
          'sessionVersion': refreshed.first['session_version'],
        };
      });

      if (context == null) return _failure();
      return _json(200, context);
    } catch (_) {
      // The failed transaction already prevents the password change. If the
      // audit channel is itself unavailable, keep the generic response rather
      // than escalating to a 500 that would disclose backend state.
      try {
        await abuseOnce(
          'credential_recovery_verification_failed',
          'Credential recovery verification failed',
        );
      } catch (_) {
        // Audit is the failed component; the operation still failed closed.
      }
      return _failure();
    }
    } catch (_) {
      return _failure();
    }
  }

  Future<void> _auditFailure(
    SqlExecutor tx,
    String shopId,
    String userId,
  ) {
    return _auditor.appendInTransaction(
      tx,
      shopId: shopId,
      category: RecoveryCategories.abuse,
      action: 'credential_password_reset_failed',
      targetUserId: userId,
      reason: 'Credential recovery verification failed',
    );
  }

  Response _ack(String operationId, String idempotencyKey) => _json(200, {
        'storedOperationId': operationId,
        'storedIdempotencyKey': idempotencyKey,
      });

  Response _failure() =>
      _json(400, <String, dynamic>{'error': 'invalid_recovery_code'});

  Response _badRequest() =>
      _json(400, <String, dynamic>{'error': 'invalid_request'});

  Response _methodNotAllowed(String allowed) => _json(
        405,
        <String, dynamic>{'error': 'method_not_allowed'},
        headers: <String, String>{'allow': allowed},
      );

  Response _json(
    int status,
    Map<String, dynamic> body, {
    Map<String, String> headers = const <String, String>{},
  }) =>
      Response(
        status,
        headers: <String, String>{
          'content-type': 'application/json',
          ...headers,
        },
        body: jsonEncode(body),
      );

  /// Applies one per-key sliding window and removes expired/empty buckets so
  /// stale identifier hashes cannot accumulate indefinitely.
  bool _allow(Map<String, Queue<int>> buckets, String key, int limit) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - _window.inMilliseconds;
    // Prune every bucket on every call, not only the one being consulted.
    for (final entry in buckets.entries.toList()) {
      final queue = entry.value;
      while (queue.isNotEmpty && queue.first < cutoff) {
        queue.removeFirst();
      }
      if (queue.isEmpty) buckets.remove(entry.key);
    }
    final calls = buckets.putIfAbsent(key, Queue<int>.new);
    if (calls.length >= limit) return false;
    calls.add(now);
    return true;
  }
}
