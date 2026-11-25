import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_test;

import 'package:credit_system/core/data/secure_storage.dart';
import 'package:credit_system/features/auth/data/services/auth_service.dart';
import 'package:credit_system/features/auth/data/services/jwt_service.dart';
import 'package:credit_system/features/auth/data/services/otp_gateway.dart';
import 'package:credit_system/features/auth/data/services/password_hash_service.dart';

/// Run with:
///   flutter test --dart-define=CS_RECOVERY_SERVER_URL=https://recovery.example.internal/
///       test/unit/features/auth/gateway_wiring_test.dart
void main() {
  const configuredUrl = String.fromEnvironment('CS_RECOVERY_SERVER_URL');
  const operationId = '11111111-2222-4333-8444-555555555555';

  final configured = configuredUrl.isNotEmpty;

  test('the public backend URL is supplied by --dart-define',
      skip: configured ? false : 'requires --dart-define=CS_RECOVERY_SERVER_URL', () {
    expect(configuredUrl, isNotEmpty,
        reason: 'release builds must define CS_RECOVERY_SERVER_URL');
  });

  test('production default branch builds HttpOtpGateway.fromEnvironment', () {
    // No otpGateway and no gatewayFactory: the only path is the build-time
    // CS_RECOVERY_SERVER_URL constant.
    final service = AuthService(
      jwt: JwtService('test-only-secret'),
      passwordHash: PasswordHashService(),
      secureStorage: _InMemorySecureStorage(),
    );
    final gateway = service.resolvedGatewayForTest;
    if (configured) {
      expect(gateway, isA<HttpOtpGateway>());
      expect((gateway as HttpOtpGateway).serverUrl.toString(),
          startsWith(configuredUrl));
    } else {
      expect(gateway, isNull);
    }
  });

  test('a cleartext client URL is rejected', () {
    expect(
      () => HttpOtpGateway(serverUrl: Uri.parse('http://recovery.internal/')),
      throwsA(isA<OtpDeliveryException>()),
    );
  });

  test('AuthService with no injected gateway uses the environment gateway',
      skip: configured ? false : 'requires --dart-define=CS_RECOVERY_SERVER_URL',
      () async {
    final requests = <http.Request>[];
    final client = http_test.MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/request') {
        return http.Response(
          jsonEncode({
            'storedOperationId': operationId,
            'storedIdempotencyKey': operationId,
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'username': 'staff.anura',
          'userId': '22222222-3333-4444-8555-666666666666',
          'shopId': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          'role': 'cashier',
          'sessionVersion': 4,
        }),
        200,
      );
    });

    final service = AuthService(
      jwt: JwtService('test-only-secret'),
      passwordHash: PasswordHashService(),
      secureStorage: _InMemorySecureStorage(),
      gatewayFactory: () => HttpOtpGateway.fromEnvironment(client: client),
    );

    final ack = await service.requestCredentialRecovery(
      identifier: 'staff.anura',
      channel: RecoveryChannel.email,
      clientOperationId: operationId,
    );
    expect(ack.clientOperationId, equals(operationId));
    expect(requests.single.url.toString(), startsWith(configuredUrl));
    expect(requests.single.url.path, equals('/request'));
    expect(requests.single.headers.containsKey('authorization'), isFalse);
  });
}

class _InMemorySecureStorage implements SecureStorage {
  final Map<String, String> _values = {};

  @override
  Future<bool> write({required String key, required String value}) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<bool> delete({required String key}) async {
    _values.remove(key);
    return true;
  }

  @override
  Future<bool> deleteAll() async {
    _values.clear();
    return true;
  }
}
