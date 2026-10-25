import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/features/auth/data/services/jwt_service.dart';

void main() {
  group('JwtService - JWT Issuance & Verification (Story 1.8)', () {
    late JwtService jwtService;

    setUp(() {
      jwtService = JwtService('test-secret-key-for-testing-only');
    });

    test('signToken creates a JWT with all required claims', () {
      final token = jwtService.signToken(
        userId: 'user-uuid-123',
        shopId: 'shop-uuid-456',
        sessionVersion: 3,
        role: 'shop_owner',
      );

      // JWT must have three parts: header.payload.signature
      final parts = token.split('.');
      expect(parts.length, equals(3));

      // Decode and verify the payload claims
      final payload = _decodeJwtPayload(parts[1]);
      expect(payload['iss'], equals('credit-system'));
      expect(payload['aud'], equals('credit-system-client'));
      expect(payload['sub'], equals('user-uuid-123'));
      expect(payload['shop_id'], equals('shop-uuid-456'));
      expect(payload['session_version'], equals(3));
      expect(payload['role'], equals('shop_owner'));
      expect(payload['iat'], isA<int>());
      expect(payload['exp'], isA<int>());
      expect(payload['exp']!, greaterThan(payload['iat']!));
    });

    test('signToken sets expiration to 15 minutes after issuance', () {
      final before = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final token = jwtService.signToken(
        userId: 'user-1',
        shopId: 'shop-1',
        sessionVersion: 1,
        role: 'cashier',
      );
      final after = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

      final payload = _decodeJwtPayload(token.split('.')[1]);
      final exp = payload['exp'] as int;
      final iat = payload['iat'] as int;

      // Expiration should be roughly 15 minutes (900 seconds) after issuance
      expect(exp - iat, equals(900));
      // Issued at should be between before and after
      expect(iat, greaterThanOrEqualTo(before));
      expect(iat, lessThanOrEqualTo(after));
    });

    test('verifyToken accepts a valid token', () {
      final token = jwtService.signToken(
        userId: 'user-1',
        shopId: 'shop-1',
        sessionVersion: 1,
        role: 'cashier',
      );

      final claims = jwtService.verifyToken(token);
      expect(claims['sub'], equals('user-1'));
      expect(claims['shop_id'], equals('shop-1'));
      expect(claims['role'], equals('cashier'));
    });

    test('verifyToken rejects a tampered signature', () {
      final token = jwtService.signToken(
        userId: 'user-1',
        shopId: 'shop-1',
        sessionVersion: 1,
        role: 'cashier',
      );

      // Tamper with the signature part using valid base64url-encoded bytes
      final parts = token.split('.');
      final wrongSig = base64Url.encode(utf8.encode('wrong-signature-bytes'));
      final tamperedToken = '${parts[0]}.${parts[1]}.$wrongSig';

      expect(
        () => jwtService.verifyToken(tamperedToken),
        throwsA(isA<JwtException>().having(
          (e) => e.message,
          'message',
          contains('Invalid JWT signature'),
        )),
      );
    });

    test('verifyToken rejects token with wrong issuer', () {
      // Build a token with a valid signature but wrong issuer
      final tamperedToken = _buildTamperedToken(
        jwtService,
        {'iss': 'wrong-issuer'},
      );

      expect(
        () => jwtService.verifyToken(tamperedToken),
        throwsA(isA<JwtException>().having(
          (e) => e.message,
          'message',
          contains('Invalid JWT issuer'),
        )),
      );
    });

    test('verifyToken rejects token with wrong audience', () {
      final tamperedToken = _buildTamperedToken(
        jwtService,
        {'aud': 'wrong-audience'},
      );

      expect(
        () => jwtService.verifyToken(tamperedToken),
        throwsA(isA<JwtException>().having(
          (e) => e.message,
          'message',
          contains('Invalid JWT audience'),
        )),
      );
    });

    test('verifyToken rejects token with missing issuer', () {
      final tamperedToken = _buildTamperedToken(
        jwtService,
        {'iss': null},
        removeKey: 'iss',
      );

      expect(
        () => jwtService.verifyToken(tamperedToken),
        throwsA(isA<JwtException>().having(
          (e) => e.message,
          'message',
          contains('Invalid JWT issuer'),
        )),
      );
    });

    test('verifyToken rejects token with missing audience', () {
      final tamperedToken = _buildTamperedToken(
        jwtService,
        {'aud': null},
        removeKey: 'aud',
      );

      expect(
        () => jwtService.verifyToken(tamperedToken),
        throwsA(isA<JwtException>().having(
          (e) => e.message,
          'message',
          contains('Invalid JWT audience'),
        )),
      );
    });

    test('verifyToken accepts a freshly issued non-expired token', () {
      final token = jwtService.signToken(
        userId: 'user-1',
        shopId: 'shop-1',
        sessionVersion: 1,
        role: 'cashier',
      );

      expect(
        () => jwtService.verifyToken(token),
        returnsNormally,
      );
    });

    test('two tokens signed with same secret both verify successfully', () {
      final token1 = jwtService.signToken(
        userId: 'user-1',
        shopId: 'shop-1',
        sessionVersion: 1,
        role: 'cashier',
      );
      final token2 = jwtService.signToken(
        userId: 'user-1',
        shopId: 'shop-1',
        sessionVersion: 1,
        role: 'cashier',
      );

      expect(
        () => jwtService.verifyToken(token1),
        returnsNormally,
      );
      expect(
        () => jwtService.verifyToken(token2),
        returnsNormally,
      );
    });

    test('JwtService constructor accepts an explicit secret', () {
      expect(() => JwtService('explicit-secret'), returnsNormally);
    });
  });
}

/// Builds a JWT token by taking a valid token from [jwtService], replacing
/// the payload claims with [overrides], and re-signing with the same secret.
///
/// If [removeKey] is specified, that key is removed from the payload instead
/// of being overridden.
String _buildTamperedToken(
  JwtService jwtService,
  Map<String, dynamic> overrides, {
  String? removeKey,
}) {
  final validToken = jwtService.signToken(
    userId: 'user-1',
    shopId: 'shop-1',
    sessionVersion: 1,
    role: 'cashier',
  );
  final parts = validToken.split('.');

  // Decode the original payload
  final originalPayload = _decodeJwtPayload(parts[1]);

  // Apply overrides or remove key
  final modifiedPayload = Map<String, dynamic>.from(originalPayload);
  if (removeKey != null) {
    modifiedPayload.remove(removeKey);
  }
  overrides.forEach((key, value) {
    if (value == null) {
      modifiedPayload.remove(key);
    } else {
      modifiedPayload[key] = value;
    }
  });

  // Re-encode payload and compute fresh signature
  final headerB64 = parts[0];
  final payloadB64 = base64Url.encode(utf8.encode(jsonEncode(modifiedPayload)));
  final signingInput = '$headerB64.$payloadB64';

  final key = utf8.encode('test-secret-key-for-testing-only');
  final hmac = Hmac(sha256, key);
  final sigBytes = Uint8List.fromList(hmac.convert(utf8.encode(signingInput)).bytes);
  final signatureB64 = base64Url.encode(sigBytes);

  return '$headerB64.$payloadB64.$signatureB64';
}

/// Helper to decode a base64url JWT payload segment.
Map<String, dynamic> _decodeJwtPayload(String base64UrlPayload) {
  // base64Url.encode already includes proper padding; decode directly.
  final jsonStr = utf8.decode(base64Url.decode(base64UrlPayload));
  return jsonDecode(jsonStr) as Map<String, dynamic>;
}
