import 'dart:convert';

import 'package:http/http.dart' as http;

/// Verified contact channel selected by a staff member for credential recovery.
enum RecoveryChannel {
  email('email'),
  sms('sms');

  final String key;
  const RecoveryChannel(this.key);

  static RecoveryChannel? fromKey(String value) {
    for (final channel in RecoveryChannel.values) {
      if (channel.key == value.toLowerCase()) return channel;
    }
    return null;
  }
}

/// Generic failure. No endpoint, credential, destination, or code is included.
class OtpDeliveryException implements Exception {
  final String message;
  const OtpDeliveryException(this.message);
  @override
  String toString() => 'OtpDeliveryException: $message';
}

/// The recovery service could not be reached. Distinct from a rejected code so
/// the client can block offline without leaking whether an account exists.
class RecoveryEndpointUnavailableException extends OtpDeliveryException {
  const RecoveryEndpointUnavailableException()
      : super('Recovery endpoint unavailable');
}

/// Acknowledgement of an authoritative challenge reservation.
///
/// Carries only the ids stored by the backend. Never carries an OTP, a
/// peppered digest, a destination, or a username.
class RecoveryRequestAck {
  final String storedOperationId;
  final String storedIdempotencyKey;

  const RecoveryRequestAck({
    required this.storedOperationId,
    required this.storedIdempotencyKey,
  });
}

/// Result of a successful backend verification. The username is disclosed
/// only by the backend, and only after the password has been rotated.
class RecoveryVerifyAck {
  final String username;
  final String userId;
  final String shopId;
  final String role;
  final int sessionVersion;

  const RecoveryVerifyAck({
    required this.username,
    required this.userId,
    required this.shopId,
    required this.role,
    required this.sessionVersion,
  });
}

/// Thin client boundary for the standalone recovery authority.
///
/// The client never generates, hashes, stores, or self-verifies a code: it
/// holds no provider credentials, sender identities, pepper, or privileged
/// database connection.
abstract class OtpGateway {
  /// Reserves a challenge on the server and returns its authoritative ids.
  Future<RecoveryRequestAck> requestRecovery({
    required String identifier,
    required RecoveryChannel channel,
    required String clientOperationId,
    required String idempotencyKey,
  });

  /// Asks the server to verify the code and atomically reset the password.
  Future<RecoveryVerifyAck> verifyRecovery({
    required String clientOperationId,
    required String otp,
    required String newPassword,
  });
}

/// Thin HTTP adapter with a hard timeout and no secrets.
class HttpOtpGateway implements OtpGateway {
  static const String serverUrlEnv = 'CS_RECOVERY_SERVER_URL';
  static const Duration requestTimeout = Duration(seconds: 10);

  final Uri _serverUrl;
  final http.Client _client;

  HttpOtpGateway({required Uri serverUrl, http.Client? client})
      : _client = client ?? http.Client(),
        _serverUrl = _requireHttps(serverUrl);

  static Uri _requireHttps(Uri url) {
    if (url.scheme != 'https') {
      throw const RecoveryEndpointUnavailableException();
    }
    return url;
  }

  /// Only the endpoint URL is read from the client environment — never a
  /// credential, sender identity, or pepper.
  factory HttpOtpGateway.fromEnvironment({http.Client? client}) {
    final url = const String.fromEnvironment(serverUrlEnv);
    if (url.isEmpty) {
      throw const RecoveryEndpointUnavailableException();
    }
    return HttpOtpGateway(serverUrl: Uri.parse(url), client: client);
  }

  @override
  Future<RecoveryRequestAck> requestRecovery({
    required String identifier,
    required RecoveryChannel channel,
    required String clientOperationId,
    required String idempotencyKey,
  }) async {
    final response = await _post('/request', <String, String>{
      'identifier': identifier,
      'channel': channel.key,
      'client_operation_id': clientOperationId,
      'idempotency_key': idempotencyKey,
    });
    final body = _decode(response);
    final operationId = body['storedOperationId'] as String?;
    final idempotency = body['storedIdempotencyKey'] as String?;
    if (operationId == null || idempotency == null) {
      throw const OtpDeliveryException('Invalid recovery endpoint response');
    }
    return RecoveryRequestAck(
      storedOperationId: operationId,
      storedIdempotencyKey: idempotency,
    );
  }

  @override
  Future<RecoveryVerifyAck> verifyRecovery({
    required String clientOperationId,
    required String otp,
    required String newPassword,
  }) async {
    final response = await _post('/verify', <String, String>{
      'client_operation_id': clientOperationId,
      'otp': otp,
      'new_password': newPassword,
    });
    final body = _decode(response);
    final username = body['username'] as String?;
    final userId = body['userId'] as String?;
    final shopId = body['shopId'] as String?;
    final role = body['role'] as String?;
    final sessionVersion = body['sessionVersion'] as int?;
    if (username == null ||
        username.isEmpty ||
        userId == null ||
        shopId == null ||
        role == null ||
        sessionVersion == null) {
      throw const OtpDeliveryException('Invalid recovery endpoint response');
    }
    return RecoveryVerifyAck(
      username: username,
      userId: userId,
      shopId: shopId,
      role: role,
      sessionVersion: sessionVersion,
    );
  }

  Future<http.Response> _post(
    String path,
    Map<String, String> payload,
  ) async {
    try {
      final response = await _client
          .post(
            _serverUrl.resolve(path),
            headers: <String, String>{
              'content-type': 'application/json',
              'accept': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const OtpDeliveryException('Recovery request failed');
      }
      return response;
    } on OtpDeliveryException {
      rethrow;
    } catch (_) {
      throw const RecoveryEndpointUnavailableException();
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const OtpDeliveryException('Invalid recovery endpoint response');
    }
  }

  /// Exposed for the CI wiring assertion only.
  Uri get serverUrl => _serverUrl;

  void close() => _client.close();
}
