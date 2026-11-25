import 'dart:convert';

import 'package:credential_recovery_backend/src/audit.dart';
import 'package:credential_recovery_backend/src/otp.dart';
import 'package:credential_recovery_backend/src/reference.dart';
import 'package:credential_recovery_backend/src/routes.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  const abuseShopId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  const pepper = 'server-only-pepper';
  const newPassword = 'a-brand-new-password';

  late FakeRecoveryDatabase db;
  late FakeDeliveryCapture capture;
  late FakePasswordHasher hasher;
  late Handler handler;

  RecoveryRoutes buildRoutes() => RecoveryRoutes(
        database: db,
        auditor: RecoveryAuditor(db, abuseShopId),
        otp: OtpAuthority(pepper),
        reference: OperationReference(pepper),
        delivery: capture.delivery,
        passwordHasher: hasher,
      );

  setUp(() {
    db = FakeRecoveryDatabase();
    db.seedUser();
    capture = captureDelivery();
    hasher = FakePasswordHasher();
    handler = buildRoutes().handler;
  });

  Future<Response> post(String path, Map<String, dynamic> body) async => await handler(
        Request(
          'POST',
          Uri.parse('http://localhost$path'),
          headers: const <String, String>{'content-type': 'application/json'},
          body: jsonEncode(body),
        ),
      );

  Future<Map<String, dynamic>> jsonBody(Response response) async =>
      jsonDecode(await response.readAsString()) as Map<String, dynamic>;

  Map<String, dynamic> requestBody() => <String, dynamic>{
        'identifier': 'staff.anura',
        'channel': 'sms',
        'client_operation_id': testOperationId,
        'idempotency_key': testIdempotencyKey,
      };

  Future<String> requestCode() async {
    final response = await post('/request', requestBody());
    expect(response.statusCode, 200);
    return capture.sent.single['otp'] as String;
  }

  Map<String, dynamic> verifyBody(String otp) => <String, dynamic>{
        'client_operation_id': testOperationId,
        'otp': otp,
        'new_password': newPassword,
      };

  group('/request contract', () {
    test('matched and unmatched identifiers return the identical body and status',
        () async {
      final matched = await post('/request', requestBody());
      final matchedBody = await jsonBody(matched);
      db.matchCount = 0;
      final unmatched = await post('/request', requestBody());
      final unmatchedBody = await jsonBody(unmatched);

      expect(matched.statusCode, equals(unmatched.statusCode));
      expect(matchedBody, equals(unmatchedBody));
      expect(matchedBody.keys.toSet(),
          equals({'storedOperationId', 'storedIdempotencyKey'}));
      expect(matchedBody['storedOperationId'], equals(testOperationId));
      expect(matchedBody['storedIdempotencyKey'], equals(testIdempotencyKey));
      for (final forbidden in ['otp', 'otpHash', 'destination', 'username', 'shopId']) {
        expect(matchedBody.containsKey(forbidden), isFalse);
      }
    });

    test('the backend generates, hashes and delivers only after created status',
        () async {
      final otp = await requestCode();

      expect(otp, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(capture.sent, hasLength(1));
      expect(capture.sent.single['to'], equals(db.destination));
      expect(db.finalized, isTrue);
      final otpHash = db.challenges[testOperationId]!['otp_hash'] as String;
      expect(otpHash, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(otpHash, isNot(equals(otp)));
      expect(
        db.challenges[testOperationId]!['delivery_reference_hash'],
        isA<String>(),
      );
    });

    test('replay and rate-limit statuses never deliver a second code', () async {
      db.createStatus = 'existing';
      final replay = await post('/request', requestBody());
      expect(await jsonBody(replay), equals({
        'storedOperationId': testOperationId,
        'storedIdempotencyKey': testIdempotencyKey,
      }));
      expect(capture.sent, isEmpty);
      expect(db.finalized, isFalse);

      db.createStatus = 'rate_limited';
      await post('/request', requestBody());
      expect(capture.sent, isEmpty);
    });

    test('ambiguous identifiers append exactly one abuse event and no challenge',
        () async {
      db.matchCount = 2;
      await post('/request', requestBody());

      expect(capture.sent, isEmpty);
      expect(db.challenges, isEmpty);
      final category14 = db.audits.where((audit) => audit['category'] == 14);
      expect(category14, hasLength(1));
      expect(category14.single['shop_id'], equals(abuseShopId));
      expect(category14.single['action'],
          equals('credential_recovery_identity_rejected'));
      // No real tenant's audit trail receives another tenant's event.
      expect(category14.single['shop_id'], isNot(equals(testShopId)));
    });

    test('an invalid stored destination is rejected without provider contact',
        () async {
      db.destination = 'bad\r\nRCPT TO:<victim@example.com>';
      await post('/request', requestBody());

      expect(capture.sent, isEmpty);
      expect(db.challenges, isEmpty);
      expect(
        db.audits.any((a) =>
            a['category'] == 14 &&
            a['action'] == 'credential_recovery_invalid_contact'),
        isTrue,
      );
    });

    test('provider failure deletes the challenge under tenant scope and audits once',
        () async {
      final failing = captureDelivery(fail: true);
      handler = RecoveryRoutes(
        database: db,
        auditor: RecoveryAuditor(db, abuseShopId),
        otp: OtpAuthority(pepper),
        reference: OperationReference(pepper),
        delivery: failing.delivery,
        passwordHasher: hasher,
      ).handler;

      final response = await post('/request', requestBody());
      expect(response.statusCode, equals(200));
      expect(await jsonBody(response), equals({
        'storedOperationId': testOperationId,
        'storedIdempotencyKey': testIdempotencyKey,
      }));
      expect(db.deleted, isTrue);
      expect(db.challenges, isEmpty);
      expect(db.tenantContexts, contains(testShopId));
      final failures = db.audits.where(
          (a) => a['action'] == 'credential_recovery_delivery_failed');
      expect(failures, hasLength(1));
      expect(failures.single['category'], equals(14));
      expect(failures.single['shop_id'], equals(testShopId));
    });

    test('retry after a failed delivery creates a fresh challenge and code',
        () async {
      handler = RecoveryRoutes(
        database: db,
        auditor: RecoveryAuditor(db, abuseShopId),
        otp: OtpAuthority(pepper),
        reference: OperationReference(pepper),
        delivery: captureDelivery(fail: true).delivery,
        passwordHasher: hasher,
      ).handler;
      await post('/request', requestBody());
      expect(db.challenges, isEmpty);
      expect(db.operations, isEmpty);

      handler = buildRoutes().handler;
      await post('/request', requestBody());
      expect(db.challenges, isNotEmpty);
      expect(capture.sent, hasLength(1));
      expect(capture.sent.single['otp'], matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('malformed identifiers get a generic 400 and no provider work', () async {
      final response = await post('/request', <String, dynamic>{
        ...requestBody(),
        'client_operation_id': 'not-a-uuid',
      });
      expect(response.statusCode, equals(400));
      expect(await jsonBody(response), equals({'error': 'invalid_request'}));
      expect(capture.sent, isEmpty);
    });

    test('the removed /deliver route does not exist', () async {
      final response = await post('/deliver', <String, dynamic>{
        'reference': testOperationId,
      });
      expect(response.statusCode, equals(404));
      expect(capture.sent, isEmpty);
    });
  });

  group('/verify contract', () {
    test('valid code rotates hash and session_version atomically and returns username',
        () async {
      final otp = await requestCode();
      final beforeTransactions = db.transactionCount;

      final response = await post('/verify', verifyBody(otp));
      expect(response.statusCode, equals(200));
      final body = await jsonBody(response);
      expect(body['username'], equals('staff.anura'));
      expect(body['userId'], equals(testUserId));
      expect(body['shopId'], equals(testShopId));
      expect(body['role'], equals('cashier'));
      expect(body['sessionVersion'], equals(4));
      expect(body.containsKey('passwordHash'), isFalse);
      expect(body.containsKey('otpHash'), isFalse);

      expect(db.transactionCount, equals(beforeTransactions + 1));
      expect(db.tenantContexts, contains(testShopId));
      final user = db.users[testUserId]!;
      expect(user['password_hash'], equals('rotated-argon2-hash'));
      expect(user['password_hash'], isNot(equals(db.originalPasswordHash)));
      expect(user['session_version'], equals(4));
      expect(hasher.calls, equals(1));
      expect(db.challenges[testOperationId]!['consumed_at'], isNotNull);

      final success = db.audits.where((a) => a['category'] == 12);
      expect(success, hasLength(1));
      expect(success.single['action'], equals('credential_password_reset'));
      for (final audit in db.audits) {
        expect(audit['reason'].toString(), isNot(contains(newPassword)));
        expect(audit['reason'].toString(), isNot(contains(otp)));
      }
    });

    test('wrong, expired, consumed and over-cap codes are indistinguishable',
        () async {
      final otp = await requestCode();
      final failures = <Map<String, dynamic>>[];

      Future<void> expectFailure(String submittedOtp) async {
        final response = await post('/verify', verifyBody(submittedOtp));
        expect(response.statusCode, equals(400));
        failures.add(await jsonBody(response));
      }

      await expectFailure('definitely-wrong-code');
      expect(db.challenges[testOperationId]!['attempts'], equals(1));

      db.challenges[testOperationId]!['expires_at'] =
          DateTime.now().toUtc().subtract(const Duration(minutes: 1));
      await expectFailure(otp);

      db.challenges[testOperationId]!['expires_at'] =
          DateTime.now().toUtc().add(const Duration(minutes: 5));
      db.challenges[testOperationId]!['attempts'] = 5;
      await expectFailure(otp);
      expect(db.challenges[testOperationId]!['attempts'], equals(5),
          reason: 'CHECK (attempts <= 5) must never be violated');

      db.challenges[testOperationId]!['attempts'] = 0;
      db.challenges[testOperationId]!['consumed_at'] =
          DateTime.now().toUtc().subtract(const Duration(minutes: 1));
      await expectFailure(otp);

      expect(failures, hasLength(4));
      for (final failure in failures) {
        expect(failure, equals({'error': 'invalid_recovery_code'}));
      }
      final category14 =
          db.audits.where((audit) => audit['category'] == 14).toList();
      expect(category14, hasLength(4));
      expect(
        category14
            .where((a) => a['action'] == 'credential_password_reset_failed')
            .length,
        equals(4),
      );
      expect(db.users[testUserId]!['password_hash'],
          equals(db.originalPasswordHash));
      // Argon2 is computed before the FOR UPDATE transaction by design.
      expect(hasher.calls, equals(4));
    });

    test('an unknown operation id is a generic failure with one abuse event',
        () async {
      final response = await post('/verify', <String, dynamic>{
        ...verifyBody('some-code'),
        'client_operation_id': '99999999-9999-4999-8999-999999999999',
      });
      expect(response.statusCode, equals(400));
      expect(await jsonBody(response), equals({'error': 'invalid_recovery_code'}));
      expect(db.audits, hasLength(1));
      expect(db.audits.single['shop_id'], equals(abuseShopId));
      expect(db.audits.single['category'], equals(14));
      expect(db.allSql, isNot(contains('UPDATE public.app_users')));
    });

    test('missing otp or short password is rejected before any database work',
        () async {
      final missingOtp = await post('/verify', <String, dynamic>{
        ...verifyBody(''),
      });
      expect(missingOtp.statusCode, equals(400));
      final shortPassword = await post('/verify', <String, dynamic>{
        ...verifyBody('code'),
        'new_password': 'short',
      });
      expect(shortPassword.statusCode, equals(400));
      expect(db.allSql, isEmpty);
      expect(db.audits, isEmpty);
    });

    test('verification after restart works from PostgreSQL state alone', () async {
      final otp = await requestCode();

      // Simulate a fresh process: a new routes instance with no in-memory OTP.
      final restarted = buildRoutes();
      final response = await restarted.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/verify'),
          headers: const <String, String>{'content-type': 'application/json'},
          body: jsonEncode(verifyBody(otp)),
        ),
      );
      expect(response.statusCode, equals(200));
      expect((await jsonBody(response))['username'], equals('staff.anura'));
    });
  });

  group('loopback 1 corrections', () {
    test('replay with a different caller key returns the stored idempotency key',
        () async {
      await requestCode();
      final replay = await post('/request', <String, dynamic>{
        ...requestBody(),
        'idempotency_key': '55555555-6666-4777-8888-999999999999',
      });
      final ack = await jsonBody(replay);
      expect(ack['storedOperationId'], equals(testOperationId));
      expect(ack['storedIdempotencyKey'], equals(testIdempotencyKey));
      expect(capture.sent, hasLength(1));
    });

    test('an unenrolled account fails verification with one Category 14 event',
        () async {
      final otp = await requestCode();
      db.enrolled = false;
      final response = await post('/verify', verifyBody(otp));
      expect(response.statusCode, equals(400));
      expect(db.audits, hasLength(1));
      expect(db.audits.single['category'], equals(14));
      expect(db.audits.single['shop_id'], equals(testShopId));
      expect(db.users[testUserId]!['password_hash'],
          equals(db.originalPasswordHash));
    });

    test('zero-row finalize deletes the challenge and audits exactly once',
        () async {
      db.emptyFinalize = true;
      await post('/request', requestBody());
      expect(db.deleted, isTrue);
      expect(db.challenges, isEmpty);
      expect(db.operations, isEmpty,
          reason: 'a failed reservation must not poison its idempotency key');
      final failures = db.audits.where(
          (a) => a['action'] == 'credential_recovery_finalization_failed');
      expect(failures, hasLength(1));
      expect(failures.single['category'], equals(14));
      expect(failures.single['shop_id'], equals(testShopId));
    });

    test('zero-row password rotation consumes nothing and audits exactly once',
        () async {
      final otp = await requestCode();
      db.zeroRowPasswordUpdate = true;
      final response = await post('/verify', verifyBody(otp));
      expect(response.statusCode, equals(400));
      expect(db.challenges, isEmpty);
      expect(db.users[testUserId]!['password_hash'],
          equals(db.originalPasswordHash));
      expect(db.audits.where((a) => a['category'] == 14), hasLength(1));
    });

    test('un-attributable audits run in the abuse shop tenant context',
        () async {
      db.matchCount = 2;
      await post('/request', requestBody());
      expect(db.tenantContexts, contains(abuseShopId));
      expect(db.audits.single['shop_id'], equals(abuseShopId));
    });

    test('audits propagate failures instead of being silently swallowed',
        () async {
      final otp = await requestCode();
      db.auditFails = true;
      final response = await post('/verify', verifyBody(otp));
      expect(response.statusCode, equals(400));
      expect(db.users[testUserId]!['password_hash'],
          equals(db.originalPasswordHash));
    });

    test('405 advertises POST and oversized bodies are rejected before decoding',
        () async {
      final wrongMethod = await handler(
        Request('GET', Uri.parse('http://localhost/request')),
      );
      expect(wrongMethod.statusCode, equals(405));
      expect(wrongMethod.headers['allow'], equals('POST'));

      final oversized = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/request'),
          body: 'x' * (16 * 1024 + 1),
        ),
      );
      expect(oversized.statusCode, equals(400));
      expect(db.allSql, isEmpty);
    });

    test('delivery budget is per tenant, not a single global queue', () async {
      const otherShop = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
      for (var i = 0; i < 30; i++) {
        final suffix = i.toString().padLeft(12, '0');
        await post('/request', <String, dynamic>{
          ...requestBody(),
          'client_operation_id': '11111111-2222-4333-8444-$suffix',
          'idempotency_key': '22222222-3333-4444-8555-$suffix',
        });
      }
      expect(capture.sent, hasLength(30));

      // The next request in the same tenant exhausts its delivery budget.
      await post('/request', requestBody());
      expect(capture.sent, hasLength(30));
      expect(
        db.audits.any((a) => a['action'] == 'credential_recovery_delivery_throttled'),
        isTrue,
      );

      // A different tenant starts with its own budget.
      db.resolvedShopId = otherShop;
      await post('/request', <String, dynamic>{
        ...requestBody(),
        'client_operation_id': '77777777-8888-4999-aaaa-bbbbbbbbbbbb',
        'idempotency_key': '88888888-9999-4aaa-bbbb-cccccccccccc',
      });
      expect(capture.sent, hasLength(31),
          reason: 'a fresh tenant must not inherit another tenant\'s budget');
    });
  });

  group('loopback 2 corrections', () {
    test('reference digest is bound to the challenge expiry', () async {
      await requestCode();
      final challenge = db.challenges[testOperationId]!;
      expect(
        challenge['delivery_reference_hash'],
        equals(OperationReference(pepper).digestFor(
          testOperationId,
          challenge['expires_at'],
        )),
      );
    });

    test('/verify throttles abusive probes before creating Category 14 events',
        () async {
      const unknown = '99999999-9999-4999-8999-999999999999';
      for (var i = 0; i < 20; i++) {
        final response = await post('/verify', <String, dynamic>{
          ...verifyBody('some-code'),
          'client_operation_id': unknown,
        });
        expect(response.statusCode, equals(400));
      }
      final appended = db.audits.length;
      expect(appended, equals(20));

      final throttled = await post('/verify', <String, dynamic>{
        ...verifyBody('some-code'),
        'client_operation_id': unknown,
      });
      expect(throttled.statusCode, equals(400));
      expect(db.audits, hasLength(appended),
          reason: 'throttled probes must not append more security events');
    });

    test('malformed UTF-8 and non-string fields are generic 400s, never 500s',
        () async {
      final malformed = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/request'),
          body: Stream.value(<int>[0xff, 0xfe, 0x80]),
        ),
      );
      expect(malformed.statusCode, equals(400));
      expect(await jsonBody(malformed), equals({'error': 'invalid_request'}));

      final wrongType = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/request'),
          body: jsonEncode(<String, dynamic>{
            ...requestBody(),
            'identifier': 42,
          }),
        ),
      );
      expect(wrongType.statusCode, equals(400));
      expect(await jsonBody(wrongType), equals({'error': 'invalid_request'}));
      expect(db.allSql, isEmpty);
    });

    test('session_version changes only via the explicit increment SQL', () async {
      final otp = await requestCode();
      final before = db.users[testUserId]!['session_version'];
      await post('/verify', verifyBody(otp));
      expect(db.users[testUserId]!['session_version'], equals((before as int) + 1));
    });

    test('expired codes still increment the attempt counter', () async {
      final otp = await requestCode();
      final expiredAt =
          DateTime.now().toUtc().subtract(const Duration(minutes: 1));
      db.challenges[testOperationId]!['expires_at'] = expiredAt;
      db.challenges[testOperationId]!['delivery_reference_hash'] =
          OperationReference(pepper).digestFor(testOperationId, expiredAt);
      final response = await post('/verify', verifyBody(otp));
      expect(response.statusCode, equals(400));
      expect(db.challenges[testOperationId]!['attempts'], equals(1));
      expect(db.audits.where((a) => a['category'] == 14), hasLength(1));
    });

    test('unreadable post-rotation context rolls the reset back', () async {
      final otp = await requestCode();
      db.emptyPostRotationContext = true;
      final response = await post('/verify', verifyBody(otp));
      expect(response.statusCode, equals(400));
      expect(db.users[testUserId]!['password_hash'],
          equals(db.originalPasswordHash));
      expect(db.users[testUserId]!['session_version'], equals(3));
    });

    test('global verify cap stops rotating operation ids', () async {
      for (var i = 0; i < 200; i++) {
        final suffix = i.toString().padLeft(12, '0');
        await post('/verify', <String, dynamic>{
          ...verifyBody('some-code'),
          'client_operation_id': 'aaaa1111-2222-4333-8444-$suffix',
        });
      }
      final appended = db.audits.length;
      expect(appended, equals(200));

      await post('/verify', <String, dynamic>{
        ...verifyBody('some-code'),
        'client_operation_id': 'bbbb1111-2222-4333-8444-cccccccccccc',
      });
      expect(db.audits, hasLength(appended));
    });

    test('health and readiness routes are available', () async {
      final health = await handler(
        Request('GET', Uri.parse('http://localhost/health')),
      );
      expect(health.statusCode, equals(200));
      expect(await jsonBody(health), equals({'status': 'ok'}));

      final ready = await handler(
        Request('GET', Uri.parse('http://localhost/ready')),
      );
      expect(ready.statusCode, equals(200));
      expect(await jsonBody(ready), equals({'ready': true}));
    });
  });

  group('loopback 5 corrections', () {
    test('POST /health is 405 with Allow: GET; unknown paths stay 404',
        () async {
      final wrong = await handler(
        Request('POST', Uri.parse('http://localhost/health'), body: '{}'),
      );
      expect(wrong.statusCode, equals(405));
      expect(wrong.headers['allow'], equals('GET'));

      final missing = await handler(
        Request('GET', Uri.parse('http://localhost/unknown')),
      );
      expect(missing.statusCode, equals(404));
    });

    test('cross-tenant rotation target affects no rows and audits once',
        () async {
      final otp = await requestCode();
      db.rotationTargetMismatch = true;
      final response = await post('/verify', verifyBody(otp));
      expect(response.statusCode, equals(400));
      expect(db.users[testUserId]!['password_hash'],
          equals(db.originalPasswordHash));
      expect(db.audits.where((a) => a['category'] == 14), hasLength(1));
    });

    test('digest mismatch burns an attempt and consumes at the threshold',
        () async {
      final otp = await requestCode();
      db.challenges[testOperationId]!['delivery_reference_hash'] = 'wrong-digest';
      final response = await post('/verify', verifyBody(otp));
      expect(response.statusCode, equals(400));
      expect(db.challenges[testOperationId]!['attempts'], equals(1));
      expect(db.audits.where((a) => a['category'] == 14), hasLength(1));

      db.challenges[testOperationId]!['attempts'] = 4;
      await post('/verify', verifyBody(otp));
      expect(db.challenges[testOperationId]!['consumed_at'], isNotNull);
    });

    test('cleanup fallback removes the challenge even when its audit fails',
        () async {
      db.auditFails = true;
      db.emptyFinalize = true;
      await post('/request', requestBody());
      expect(db.challenges, isEmpty);
      expect(db.operations, isEmpty);
    });

    test('an unfinished reservation is re-finalized and re-delivered',
        () async {
      await requestCode();
      expect(capture.sent, hasLength(1));
      db.challenges[testOperationId]!['delivery_reference_hash'] = null;
      db.createStatus = 'existing';

      await post('/request', requestBody());
      expect(capture.sent, hasLength(2));
      expect(db.challenges[testOperationId]!['delivery_reference_hash'], isNotNull);
    });

    test('61 resolver calls yield exactly one throttle event and no more SQL',
        () async {
      for (var i = 0; i < 60; i++) {
        await post('/request', <String, dynamic>{
          ...requestBody(),
          'client_operation_id':
              '11111111-2222-4333-8444-${i.toString().padLeft(12, '0')}',
          'idempotency_key':
              '22222222-3333-4444-8555-${i.toString().padLeft(12, '0')}',
        });
      }
      final resolverQueries = db.allSql
          .where((sql) => sql.contains('cs_resolve_recovery_identity'))
          .length;
      expect(resolverQueries, equals(60));

      await post('/request', requestBody());
      expect(
        db.audits.where(
            (a) => a['action'] == 'credential_recovery_resolver_throttled'),
        hasLength(1),
      );
      expect(
        db.allSql.where((sql) => sql.contains('cs_resolve_recovery_identity')),
        hasLength(resolverQueries),
      );
    });
  });
}
