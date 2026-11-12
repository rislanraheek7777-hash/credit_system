import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Exception thrown when JWT operations fail.
class JwtException implements Exception {
  final String message;
  const JwtException(this.message);

  @override
  String toString() => 'JwtException: $message';
}

/// Service for creating and verifying JWT access tokens using HS256.
///
/// Uses [crypto] for HMAC-SHA256 signing. The secret is provided at
/// construction time and should come from a secure environment variable
/// (e.g. JWT_SECRET), never from source code.
class JwtService {
  final String _secret;

  /// Expected JWT issuer claim value.
  static const String _issuer = 'credit-system';

  /// Expected JWT audience claim value.
  static const String _audience = 'credit-system-client';

  /// Creates a [JwtService] with the given secret key.
  JwtService(this._secret);

  /// Creates a [JwtService] from the JWT_SECRET environment variable.
  ///
  /// Throws [JwtSecretNotFoundException] if the environment variable is not
  /// set.
  JwtService.fromEnv()
      : _secret = const String.fromEnvironment('JWT_SECRET') {
    if (_secret.isEmpty) {
      throw const JwtSecretNotFoundException();
    }
  }

  /// Creates a signed JWT access token with the given claims.
  ///
  /// The JWT includes:
  /// - iss (issuer): credit-system
  /// - sub (subject): user ID
  /// - aud (audience): credit-system-client
  /// - iat (issued at): issuance time in seconds since epoch
  /// - exp (expiration): 15 minutes after issuance
  /// - shop_id: the shop tenant UUID
  /// - session_version: the user's session version at issuance time
  ///
  /// The signature is HMAC-SHA256 using the JWT_SECRET.
  String signToken({
    required String userId,
    required String shopId,
    required int sessionVersion,
    required String role,
  }) {
    final now = DateTime.now().toUtc();
    final exp = now.add(const Duration(minutes: 15));

    final header = {
      'alg': 'HS256',
      'typ': 'JWT',
    };

    final payload = {
      'iss': 'credit-system',
      'sub': userId,
      'aud': 'credit-system-client',
      'iat': now.millisecondsSinceEpoch ~/ 1000,
      'exp': exp.millisecondsSinceEpoch ~/ 1000,
      'shop_id': shopId,
      'session_version': sessionVersion,
      'role': role,
    };

    final headerB64 = _base64UrlEncode(utf8.encode(jsonEncode(header)));
    final payloadB64 = _base64UrlEncode(utf8.encode(jsonEncode(payload)));
    final signingInput = '$headerB64.$payloadB64';
    final signature = _hmacSha256(signingInput);
    final signatureB64 = _base64UrlEncode(signature);

    return '$headerB64.$payloadB64.$signatureB64';
  }

  /// Creates a signed JWT refresh token with the given claims.
  ///
  /// Refresh tokens are longer-lived than access tokens (7 days) and carry
  /// a `typ` claim of `refresh` so they cannot be used as access tokens.
  String signRefreshToken({
    required String userId,
    required String shopId,
    required int sessionVersion,
    required String role,
  }) {
    final now = DateTime.now().toUtc();
    final exp = now.add(const Duration(days: 7));

    final header = {
      'alg': 'HS256',
      'typ': 'JWT',
    };

    final payload = {
      'iss': 'credit-system',
      'sub': userId,
      'aud': 'credit-system-client',
      'iat': now.millisecondsSinceEpoch ~/ 1000,
      'exp': exp.millisecondsSinceEpoch ~/ 1000,
      'shop_id': shopId,
      'session_version': sessionVersion,
      'role': role,
      'typ': 'refresh',
    };

    final headerB64 = _base64UrlEncode(utf8.encode(jsonEncode(header)));
    final payloadB64 = _base64UrlEncode(utf8.encode(jsonEncode(payload)));
    final signingInput = '$headerB64.$payloadB64';
    final signature = _hmacSha256(signingInput);
    final signatureB64 = _base64UrlEncode(signature);

    return '$headerB64.$payloadB64.$signatureB64';
  }

  /// Verifies a JWT refresh token and returns its claims.
  ///
  /// Throws [JwtException] if the token is invalid, expired, has an invalid
  /// signature, or is not a refresh token.
  Map<String, dynamic> verifyRefreshToken(String token) {
    final claims = verifyToken(token);
    if (claims['typ'] != 'refresh') {
      throw JwtException('Invalid JWT type');
    }
    return claims;
  }

  /// Verifies a JWT access token and returns its claims.
  ///
  /// Throws [JwtException] if the token is invalid, expired, or has an
  /// invalid signature.
  Map<String, dynamic> verifyToken(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      throw JwtException('Invalid JWT format');
    }

    final headerB64 = parts[0];
    final payloadB64 = parts[1];
    final signatureB64 = parts[2];

    final signingInput = '$headerB64.$payloadB64';
    final expectedSignature = _hmacSha256(signingInput);
    final providedSignature = _base64UrlDecode(signatureB64);

    if (!_constantTimeEquals(expectedSignature, providedSignature)) {
      throw JwtException('Invalid JWT signature');
    }

    final headerJson = utf8.decode(_base64UrlDecode(headerB64));
    final payloadJson = utf8.decode(_base64UrlDecode(payloadB64));

    final header = jsonDecode(headerJson) as Map<String, dynamic>;
    final payload = jsonDecode(payloadJson) as Map<String, dynamic>;

    if (header['alg'] != 'HS256') {
      throw JwtException('Unsupported JWT algorithm');
    }
    if (header['typ'] != 'JWT') {
      throw JwtException('Invalid JWT type');
    }

    final now = DateTime.now().toUtc();
    final exp = payload['exp'] as int?;
    if (exp == null || exp * 1000 < now.millisecondsSinceEpoch) {
      throw JwtException('Token expired');
    }

    final iss = payload['iss'];
    if (iss == null || iss != _issuer) {
      throw JwtException('Invalid JWT issuer');
    }

    final aud = payload['aud'];
    if (aud == null || aud != _audience) {
      throw JwtException('Invalid JWT audience');
    }

    return Map<String, dynamic>.from(payload);
  }

  String _base64UrlEncode(Uint8List bytes) {
    return base64Url.encode(bytes);
  }

  Uint8List _base64UrlDecode(String input) {
    // base64Url.encode already includes proper padding, so decode directly
    // without adding more (which would create invalid padding).
    return base64Url.decode(input);
  }

  Uint8List _hmacSha256(String data) {
    final key = utf8.encode(_secret);
    final input = utf8.encode(data);
    final hmac = Hmac(sha256, key);
    return Uint8List.fromList(hmac.convert(input).bytes);
  }

  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}

/// Exception thrown when JWT_SECRET environment variable is not set.
class JwtSecretNotFoundException implements Exception {
  const JwtSecretNotFoundException();

  @override
  String toString() => 'JWT_SECRET environment variable is not set';
}

/// Exception thrown when JWT operations fail.
class JwtServiceException implements Exception {
  final String message;
  const JwtServiceException(this.message);

  @override
  String toString() => 'JwtServiceException: $message';
}
