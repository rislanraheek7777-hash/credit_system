import 'dart:convert';

import 'package:credential_recovery_backend/src/config.dart';
import 'package:credential_recovery_backend/src/database.dart';
import 'package:credential_recovery_backend/src/delivery.dart';
import 'package:credential_recovery_backend/src/otp.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_test;

const String testOperationId = '11111111-2222-4333-8444-555555555555';
const String testIdempotencyKey = '22222222-3333-4444-8555-666666666666';
const String testShopId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const String testUserId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

/// In-memory PostgreSQL stand-in that understands exactly the statements the
/// authority issues. It records tenant context and transaction membership so
/// tests can prove the privileged work happens server-side and atomically.
class FakeRecoveryDatabase implements RecoveryDatabase {
  FakeRecoveryDatabase({
    this.createStatus = 'created',
    this.matchCount = 1,
    this.destination = '+94771234567',
    this.enrolled = true,
  });

  String createStatus;
  int matchCount;
  String destination;
  bool enrolled;
  String resolvedShopId = testShopId;
  bool auditFails = false;
  bool zeroRowPasswordUpdate = false;
  bool emptyFinalize = false;
  bool emptyPostRotationContext = false;
  bool rotationTargetMismatch = false;

  String username = 'staff.anura';
  String originalPasswordHash = 'old-argon2-hash';
  bool finalized = false;
  bool deleted = false;
  int transactionCount = 0;
  final List<String> tenantContexts = <String>[];
  final List<List<String>> transactions = <List<String>>[];
  final List<String> directStatements = <String>[];
  final List<Map<String, dynamic>> audits = <Map<String, dynamic>>[];
  final Map<String, Map<String, dynamic>> challenges =
      <String, Map<String, dynamic>>{};
  final Map<String, Map<String, dynamic>> operations =
      <String, Map<String, dynamic>>{};
  final Map<String, Map<String, dynamic>> users =
      <String, Map<String, dynamic>>{};

  List<String>? _currentTransaction;

  List<String> get allSql => [
        ...directStatements,
        for (final statements in transactions) ...statements,
      ];

  void seedUser() {
    users[testUserId] = <String, dynamic>{
      'id': testUserId,
      'shop_id': testShopId,
      'username': username,
      'role': 'cashier',
      'password_hash': originalPasswordHash,
      'session_version': 3,
    };
  }

  @override
  Future<T> transaction<T>(Future<T> Function(SqlExecutor tx) action) async {
    final statements = <String>[];
    final previous = _currentTransaction;
    _currentTransaction = statements;
    transactions.add(statements);

    final challengeSnapshot = <String, Map<String, dynamic>>{
      for (final entry in challenges.entries)
        entry.key: Map<String, dynamic>.from(entry.value),
    };
    final operationSnapshot = <String, Map<String, dynamic>>{
      for (final entry in operations.entries)
        entry.key: Map<String, dynamic>.from(entry.value),
    };
    final userSnapshot = <String, Map<String, dynamic>>{
      for (final entry in users.entries)
        entry.key: Map<String, dynamic>.from(entry.value),
    };
    final auditCount = audits.length;

    try {
      return await action(this);
    } catch (_) {
      // Emulate transaction rollback so tests observe the real fail-closed
      // behavior when an audit append or affected-row check throws.
      challenges
        ..clear()
        ..addAll(challengeSnapshot);
      operations
        ..clear()
        ..addAll(operationSnapshot);
      users
        ..clear()
        ..addAll(userSnapshot);
      audits.removeRange(auditCount, audits.length);
      rethrow;
    } finally {
      _currentTransaction = previous;
    }
  }

  @override
  Future<T> transactionWithTenant<T>(
    String shopId,
    Future<T> Function(SqlExecutor tx) action,
  ) async {
    tenantContexts.add(shopId);
    transactionCount++;
    return transaction(action);
  }

  @override
  Future<int> execute(String sql, [List<dynamic>? parameters]) async {
    _record(sql);
    final params = parameters ?? const <dynamic>[];

    if (sql.contains('cs_record_recovery_audit')) {
      _appendAudit(params);
      return 1;
    }
    if (sql.contains('DELETE FROM public.credential_recovery_operations')) {
      operations.remove(params[0]);
      return 1;
    }
    if (sql.contains('DELETE FROM public.credential_recovery_challenges')) {
      final key = challenges.keys.firstWhere(
        (id) =>
            challenges[id]!['client_operation_id'] == params[0] ||
            challenges[id]!['id'] == params[0],
        orElse: () => '',
      );
      final removed = key.isNotEmpty && challenges.remove(key) != null;
      if (removed) deleted = true;
      return removed ? 1 : 0;
    }
    if (sql.contains('UPDATE public.credential_recovery_challenges')) {
      final challenge = challenges[testOperationId];
      if (challenge == null) return 0;
      if (sql.contains('attempts = @p0')) {
        challenge['attempts'] = params[0];
        if ((params[0] as int) >= (params[1] as int)) {
          challenge['consumed_at'] = DateTime.now().toUtc();
        }
      } else if (sql.contains('consumed_at = NOW()')) {
        challenge['consumed_at'] = DateTime.now().toUtc();
      }
      return 1;
    }
    if (sql.contains('UPDATE public.app_users')) {
      if (zeroRowPasswordUpdate || rotationTargetMismatch) return 0;
      final user = users[params[1]];
      if (user == null) return 0;
      user['password_hash'] = params[0];
      // Only the real increment statement may change session_version.
      if (sql.contains('session_version = session_version + 1')) {
        user['session_version'] = (user['session_version'] as int) + 1;
      }
      return 1;
    }
    if (sql.contains('INSERT INTO schema_migrations')) {
      _migrationRecords.add(<String, dynamic>{
        'version': params[0],
        'name': params[1],
        'checksum': params[2],
      });
      return 1;
    }
    return 0;
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic>? parameters,
  ]) async {
    _record(sql);
    final params = parameters ?? const <dynamic>[];

    if (sql.contains('cs_record_recovery_audit')) {
      _appendAudit(params);
      return [
        <String, dynamic>{'recorded': null},
      ];
    }
    if (sql.contains('schema_migrations')) {
      return List<Map<String, dynamic>>.from(_migrationRecords);
    }
    if (sql.contains('SELECT expires_at FROM public.credential_recovery_challenges')) {
      final key = challenges.keys.firstWhere(
        (id) => challenges[id]!['client_operation_id'].toString() ==
            params.first.toString(),
        orElse: () => '',
      );
      if (key.isEmpty) return const <Map<String, dynamic>>[];
      return [
        <String, dynamic>{'expires_at': challenges[key]!['expires_at']},
      ];
    }
    if (sql.contains('cs_resolve_recovery_identity')) {
      if (matchCount == 0) return const <Map<String, dynamic>>[];
      return [
        <String, dynamic>{
          'shop_id': resolvedShopId,
          'user_id': testUserId,
          'destination': destination,
          'match_count': matchCount,
        },
      ];
    }
    if (sql.contains('cs_create_recovery_challenge')) {
      final opId = params[4] as String;
      final idem = params[5] as String;
      Map<String, dynamic>? existing = challenges.values.firstWhere(
        (c) => c['client_operation_id'] == opId || c['idempotency_key'] == idem,
        orElse: () => <String, dynamic>{},
      );
      if (existing.isEmpty) {
        existing = operations.values.firstWhere(
          (o) => o['client_operation_id'] == opId || o['idempotency_key'] == idem,
          orElse: () => <String, dynamic>{},
        );
      }
      if (existing.isNotEmpty) {
        return [
          <String, dynamic>{
            'stored_operation_id': existing['client_operation_id'],
            'stored_idempotency_key': existing['idempotency_key'],
            'status': 'existing',
          },
        ];
      }
      if (createStatus == 'created') {
        operations[opId] = <String, dynamic>{
          'client_operation_id': opId,
          'idempotency_key': idem,
          'shop_id': params[0],
        };
        challenges[opId] = <String, dynamic>{
          'id': 'challenge-$opId',
          'client_operation_id': opId,
          'idempotency_key': idem,
          'shop_id': params[0],
          'user_id': params[1],
          'channel': params[2],
          'destination': params[3],
          'otp_hash': 'placeholder-digest',
          'expires_at': DateTime.now().toUtc().add(const Duration(minutes: 5)),
          'attempts': 0,
          'consumed_at': null,
          'delivery_reference_hash': null,
        };
      }
      return [
        <String, dynamic>{
          'stored_operation_id': opId,
          'stored_idempotency_key': idem,
          'status': createStatus,
        },
      ];
    }
    if (sql.contains('cs_finalize_recovery_challenge')) {
      final challenge = challenges[params[0] as String];
      if (challenge == null ||
          challenge['consumed_at'] != null ||
          emptyFinalize) {
        return const <Map<String, dynamic>>[];
      }
      challenge['otp_hash'] = params[1];
      challenge['delivery_reference_hash'] = params[2];
      finalized = true;
      return [
        <String, dynamic>{
          'destination': challenge['destination'],
          'channel': challenge['channel'],
          'shop_id': challenge['shop_id'],
          'user_id': challenge['user_id'],
          'expires_at': challenge['expires_at'],
        },
      ];
    }
    if (sql.contains('cs_load_recovery_for_reference')) {
      final match = challenges[params[0]];
      if (match == null) return const <Map<String, dynamic>>[];
      return [
        <String, dynamic>{
          'client_operation_id': match['client_operation_id'],
          'shop_id': match['shop_id'],
          'user_id': match['user_id'],
        },
      ];
    }
    if (sql.contains('delivery_reference_hash = @p4')) {
      final challenge = challenges[params[0] as String];
      if (challenge == null || challenge['delivery_reference_hash'] != params[4]) {
        return const <Map<String, dynamic>>[];
      }
      final expiry = challenge['expires_at'];
      final unexpired = expiry is DateTime
          ? expiry.toUtc().isAfter(DateTime.now().toUtc())
          : true;
      return [
        <String, dynamic>{
          'id': challenge['id'],
          'attempts': challenge['attempts'],
          'consumed_at': challenge['consumed_at'],
          'otp_hash': challenge['otp_hash'],
          'unexpired': unexpired,
          'enrolled': enrolled,
        },
      ];
    }
    if (sql.contains('FOR UPDATE')) {
      final challenge = challenges[params[0] as String];
      if (challenge == null) return const <Map<String, dynamic>>[];
      return [Map<String, dynamic>.from(challenge)];
    }
    if (sql.contains('unexpired') && sql.contains('enrolled')) {
      final expiry = params[0];
      final unexpired = expiry is DateTime
          ? expiry.toUtc().isAfter(DateTime.now().toUtc())
          : true;
      return [
        <String, dynamic>{'unexpired': unexpired, 'enrolled': enrolled},
      ];
    }
    if (sql.contains('SELECT username, role, session_version FROM public.app_users')) {
      if (emptyPostRotationContext) return const <Map<String, dynamic>>[];
      final user = users[params[0]];
      if (user == null) return const <Map<String, dynamic>>[];
      return [
        <String, dynamic>{
          'username': user['username'],
          'role': user['role'],
          'session_version': user['session_version'],
        },
      ];
    }
    if (sql.contains('SELECT username FROM public.app_users')) {
      final user = users[params[0]];
      if (user == null) return const <Map<String, dynamic>>[];
      return [
        <String, dynamic>{'username': user['username']},
      ];
    }
    return const <Map<String, dynamic>>[];
  }

  @override
  Future<void> close() async {}

  final List<Map<String, dynamic>> _migrationRecords = <Map<String, dynamic>>[];

  void setMigrationRecord(int version, String checksum) {
    _migrationRecords.add(<String, dynamic>{
      'version': version,
      'checksum': checksum,
    });
  }

  void _appendAudit(List<dynamic> params) {
    if (auditFails) throw StateError('audit append failed');
    audits.add(<String, dynamic>{
      'shop_id': params[0],
      'category': params[1],
      'action': params[2],
      'target_user_id': params[3],
      'reason': params[4],
    });
  }

  void _record(String sql) {
    final target = _currentTransaction ?? directStatements;
    target.add(sql);
  }
}

/// Deterministic password hasher: tests assert calls, not Argon2 cost.
class FakePasswordHasher implements PasswordHasher {
  int calls = 0;

  @override
  String hash(String password) {
    calls++;
    return 'rotated-argon2-hash';
  }
}

/// Captures outbound provider traffic and can simulate a provider failure.
FakeDeliveryCapture captureDelivery({bool fail = false}) {
  final bodies = <String>[];
  final client = http_test.MockClient((request) async {
    bodies.add(request.body);
    if (fail) return http.Response('{}', 502);
    return http.Response('{}', 200);
  });
  final config = SmtpConfig(
    host: 'smtp.example.test',
    port: 465,
    username: '',
    password: '',
    from: 'noreply@example.test',
    useTls: true,
  );
  final sms = SmsConfig(
    endpoint: 'https://sms.example.test/send',
    sender: 'CreditSystem',
    apiKey: 'server-only-key',
  );
  return FakeDeliveryCapture(
    bodies: bodies,
    delivery: RecoveryDelivery(config, sms, httpClient: client),
  );
}

class FakeDeliveryCapture {
  FakeDeliveryCapture({required this.bodies, required this.delivery});

  final List<String> bodies;
  final RecoveryDelivery delivery;

  List<Map<String, dynamic>> get sent =>
      bodies.map((body) => jsonDecode(body) as Map<String, dynamic>).toList();
}

Map<String, String> validEnvironment() => <String, String>{
      'DATABASE_URL': 'postgres://user:pass@localhost:5432/credit',
      'CS_RECOVERY_OTP_PEPPER': 'server-only-pepper',
      'CS_RECOVERY_ABUSE_SHOP_ID': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      'CS_RECOVERY_SMTP_HOST': 'smtp.example.test',
      'CS_RECOVERY_SMTP_PORT': '465',
      'CS_RECOVERY_SMTP_USER': 'smtp-user',
      'CS_RECOVERY_SMTP_PASSWORD': 'smtp-password',
      'CS_RECOVERY_EMAIL_FROM': 'noreply@example.test',
      'CS_RECOVERY_SMS_ENDPOINT': 'https://sms.example.test/send',
      'CS_RECOVERY_SMS_SENDER': 'CreditSystem',
      'CS_RECOVERY_SMS_API_KEY': 'server-only-key',
    };
