import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_test;

import 'package:credit_system/features/auth/data/services/otp_gateway.dart';

void main() {
  const endpoint = 'https://recovery.example.internal/';
  const operationId = '11111111-2222-4333-8444-555555555555';

  late http_test.MockClient client;
  late HttpOtpGateway gateway;
  late List<http.Request> requests;
  late List<String> bodies;

  setUp(() {
    requests = <http.Request>[];
    bodies = <String>[];
    client = http_test.MockClient((request) async {
      requests.add(request);
      bodies.add(request.body);
      switch (request.url.path) {
        case '/request':
          return http.Response(
            jsonEncode({
              'storedOperationId': operationId,
              'storedIdempotencyKey': '22222222-3333-4444-8555-666666666666',
            }),
            200,
          );
        case '/verify':
          return http.Response(
            jsonEncode({
              'username': 'staff.anura',
              'userId': '11111111-2222-4333-8444-555555555555',
              'shopId': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
              'role': 'cashier',
              'sessionVersion': 4,
            }),
            200,
          );
        default:
          return http.Response(jsonEncode({'error': 'not_found'}), 404);
      }
    });
    gateway = HttpOtpGateway(serverUrl: Uri.parse(endpoint), client: client);
  });

  test('requestRecovery sends identifiers only and returns stored ids', () async {
    final ack = await gateway.requestRecovery(
      identifier: 'staff.anura',
      channel: RecoveryChannel.sms,
      clientOperationId: operationId,
      idempotencyKey: '22222222-3333-4444-8555-666666666666',
    );

    expect(requests.single.url.path, equals('/request'));
    expect(requests.single.headers.containsKey('authorization'), isFalse);
    expect(jsonDecode(bodies.single), equals({
      'identifier': 'staff.anura',
      'channel': 'sms',
      'client_operation_id': operationId,
      'idempotency_key': '22222222-3333-4444-8555-666666666666',
    }));
    expect(ack.storedOperationId, equals(operationId));
    expect(ack.storedIdempotencyKey,
        equals('22222222-3333-4444-8555-666666666666'));
    // No provider credential, pepper, destination, or OTP is sent by client.
    expect(bodies.single, isNot(contains('otp')));
    expect(bodies.single, isNot(contains('destination')));
  });

  test('verifyRecovery posts operation id, code and new password to /verify',
      () async {
    final ack = await gateway.verifyRecovery(
      clientOperationId: operationId,
      otp: 'backend-generated-code',
      newPassword: 'a-brand-new-password',
    );

    expect(ack.username, equals('staff.anura'));
    expect(ack.userId, equals('11111111-2222-4333-8444-555555555555'));
    expect(ack.shopId, equals('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));
    expect(ack.role, equals('cashier'));
    expect(ack.sessionVersion, equals(4));
    expect(requests.single.url.path, equals('/verify'));
    expect(requests.single.headers.containsKey('authorization'), isFalse);
    expect(jsonDecode(bodies.single), equals({
      'client_operation_id': operationId,
      'otp': 'backend-generated-code',
      'new_password': 'a-brand-new-password',
    }));
  });

  test('the removed /deliver route is never called by the client', () async {
    await gateway.requestRecovery(
      identifier: 'staff.anura',
      channel: RecoveryChannel.email,
      clientOperationId: operationId,
      idempotencyKey: operationId,
    );
    expect(requests.single.url.path, equals('/request'));
    expect(bodies, hasLength(1));
  });

  test('non-2xx responses map to generic delivery failures', () async {
    final failing = HttpOtpGateway(
      serverUrl: Uri.parse(endpoint),
      client: http_test.MockClient((request) async =>
          http.Response(jsonEncode({'error': 'invalid_recovery_code'}), 400)),
    );
    await expectLater(
      failing.verifyRecovery(
        clientOperationId: operationId,
        otp: 'wrong',
        newPassword: 'long-enough-password',
      ),
      throwsA(isA<OtpDeliveryException>()),
    );
    await expectLater(
      failing.requestRecovery(
        identifier: 'staff.anura',
        channel: RecoveryChannel.email,
        clientOperationId: operationId,
        idempotencyKey: operationId,
      ),
      throwsA(isA<OtpDeliveryException>()),
    );
  });

  test('connectivity failures are distinct from a rejected code', () async {
    final failing = HttpOtpGateway(
      serverUrl: Uri.parse(endpoint),
      client: http_test.MockClient((request) async => throw StateError('offline')),
    );
    await expectLater(
      failing.verifyRecovery(
        clientOperationId: operationId,
        otp: 'code',
        newPassword: 'long-enough-password',
      ),
      throwsA(isA<RecoveryEndpointUnavailableException>()),
    );
  });

  test('malformed responses are rejected', () async {
    final failing = HttpOtpGateway(
      serverUrl: Uri.parse(endpoint),
      client: http_test.MockClient(
        (request) async => http.Response('{}', 200),
      ),
    );
    await expectLater(
      failing.verifyRecovery(
        clientOperationId: operationId,
        otp: 'code',
        newPassword: 'long-enough-password',
      ),
      throwsA(isA<OtpDeliveryException>()),
    );
  });

  test('channel parsing fails closed for unknown wire values', () {
    expect(RecoveryChannel.fromKey('EMAIL'), equals(RecoveryChannel.email));
    expect(RecoveryChannel.fromKey('sms'), equals(RecoveryChannel.sms));
    expect(RecoveryChannel.fromKey('push'), isNull);
  });
}
