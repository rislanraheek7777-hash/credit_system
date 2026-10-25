import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/remote/migration_runner.dart';
import 'package:credit_system/core/data/remote/postgres_executor.dart';
import 'package:credit_system/core/data/secure_storage.dart';
import 'package:credit_system/features/auth/data/services/auth_service.dart';
import 'package:credit_system/features/auth/data/services/jwt_service.dart';
import 'package:credit_system/features/auth/data/services/password_hash_service.dart';

/// Mock [PostgreSqlExecutor] for unit testing [AuthService].
///
/// Extends [PostgreSqlExecutor] with an empty connection string (never
/// connects) and overrides [transactionWithTenant], [execute], and [query]
/// to simulate database responses.
class MockPostgreSqlExecutor extends PostgreSqlExecutor {
  MockPostgreSqlExecutor() : super.withConnectionString('');

  /// Captured SET LOCAL app.current_shop_id values (for assertions).
  final List<String> tenantContexts = [];

  /// Captured executed SQL statements (for assertions).
  final List<String> executedStatements = [];

  /// Simulated user record returned by authenticate() / validateSession().
  Map<String, dynamic>? simulatedUser;

  /// Whether the simulated user exists.
  bool userExists = true;

  /// Whether the simulated user is active.
  bool userIsActive = true;

  @override
  Future<T> transactionWithTenant<T>(
    String shopId,
    Future<T> Function(SqlDatabaseExecutor tx) action,
  ) async {
    tenantContexts.add(shopId);
    final mockTx = _MockSqlExecutor(this);
    return await action(mockTx);
  }

  @override
  Future<void> execute(String sql, [List<dynamic>? parameters]) async {
    executedStatements.add(sql);
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic>? parameters,
  ]) async {
    executedStatements.add(sql);
    // Return simulated user if the query matches app_users lookup
    if (sql.contains('FROM app_users') && userExists) {
      return [simulatedUser ?? _defaultUser()];
    }
    return [];
  }

  Map<String, dynamic> _defaultUser() {
    return {
      'id': 'user-uuid-123',
      'shop_id': 'shop-uuid-456',
      'username': 'staff.anura',
      'full_name': 'Anura Kumara',
      'role': 'cashier',
      'is_active': true,
      'session_version': 3,
      'password_hash':
          '\$argon2id\$v=19\$m=65536,t=3,p=4\$salt\$hash',
    };
  }
}

/// Mock [SqlDatabaseExecutor] for use within [MockPostgreSqlExecutor]
/// transaction callbacks.
class _MockSqlExecutor implements SqlDatabaseExecutor {
  final MockPostgreSqlExecutor _pg;

  _MockSqlExecutor(this._pg);

  @override
  Future<void> execute(String sql, [List<dynamic>? parameters]) async {
    _pg.executedStatements.add(sql);
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic>? parameters,
  ]) async {
    _pg.executedStatements.add(sql);
    if (sql.contains('FROM app_users') && _pg.userExists) {
      return [_pg.simulatedUser ?? _pg._defaultUser()];
    }
    return [];
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(SqlDatabaseExecutor tx) action,
  ) {
    return action(this);
  }
}

void main() {
  group('AuthService - Server-Side Authentication (Story 1.8)', () {
    late MockPostgreSqlExecutor mockPg;
    late JwtService jwtService;
    late PasswordHashService passwordHash;
    late AuthService authService;

    setUp(() {
      mockPg = MockPostgreSqlExecutor();
      jwtService = JwtService('test-secret-key-for-testing-only');
      passwordHash = PasswordHashService();
      authService = AuthService(
        pg: mockPg,
        jwt: jwtService,
        passwordHash: passwordHash,
        secureStorage: MockSecureStorage(),
      );
    });

    test('authenticate verifies credentials against PostgreSQL and issues JWT', () async {
      // Set up a user with a known password hash
      const password = 'secure-password-123';
      final hash = passwordHash.hashPassword(password);
      mockPg.simulatedUser = {
        'id': 'user-uuid-123',
        'shop_id': 'shop-uuid-456',
        'username': 'staff.anura',
        'full_name': 'Anura Kumara',
        'role': 'cashier',
        'is_active': true,
        'session_version': 3,
        'password_hash': hash,
      };

      final result = await authService.authenticate(
        'shop-uuid-456',
        'staff.anura',
        password,
      );

      expect(result.token, isNotEmpty);
      expect(result.userId, equals('user-uuid-123'));
      expect(result.shopId, equals('shop-uuid-456'));
      expect(result.role, equals('cashier'));
      expect(result.sessionVersion, equals(3));
      expect(result.username, equals('staff.anura'));
      expect(result.fullName, equals('Anura Kumara'));

      // Tenant context was set from the requested shopId
      expect(mockPg.tenantContexts, contains('shop-uuid-456'));
    });

    test('authenticate rejects invalid username', () async {
      mockPg.userExists = false;
      mockPg.simulatedUser = null;

      await expectLater(
        authService.authenticate('shop-uuid-456', 'nonexistent', 'password'),
        throwsA(isA<AuthenticationException>().having(
          (e) => e.message,
          'message',
          equals('Invalid credentials'),
        )),
      );
    });

    test('authenticate rejects wrong password', () async {
      final hash = passwordHash.hashPassword('correct-password');
      mockPg.simulatedUser = {
        'id': 'user-uuid-123',
        'shop_id': 'shop-uuid-456',
        'username': 'staff.anura',
        'full_name': 'Anura Kumara',
        'role': 'cashier',
        'is_active': true,
        'session_version': 1,
        'password_hash': hash,
      };

      await expectLater(
        authService.authenticate('shop-uuid-456', 'staff.anura', 'wrong-password'),
        throwsA(isA<AuthenticationException>()),
      );
    });

    test('authenticate rejects inactive user', () async {
      final hash = passwordHash.hashPassword('password');
      mockPg.simulatedUser = {
        'id': 'user-uuid-123',
        'shop_id': 'shop-uuid-456',
        'username': 'staff.anura',
        'full_name': 'Anura Kumara',
        'role': 'cashier',
        'is_active': false,
        'session_version': 1,
        'password_hash': hash,
      };

      await expectLater(
        authService.authenticate('shop-uuid-456', 'staff.anura', 'password'),
        throwsA(isA<AuthenticationException>()),
      );
    });

    test('authenticate rejects user without password hash', () async {
      mockPg.simulatedUser = {
        'id': 'user-uuid-123',
        'shop_id': 'shop-uuid-456',
        'username': 'staff.anura',
        'full_name': 'Anura Kumara',
        'role': 'cashier',
        'is_active': true,
        'session_version': 1,
        'password_hash': null,
      };

      await expectLater(
        authService.authenticate('shop-uuid-456', 'staff.anura', 'password'),
        throwsA(isA<AuthenticationException>().having(
          (e) => e.message,
          'message',
          equals('Invalid credentials'),
        )),
      );
    });

    test('authenticate rejects empty inputs', () async {
      await expectLater(
        authService.authenticate('', 'staff.anura', 'password'),
        throwsA(isA<AuthenticationException>()),
      );
      await expectLater(
        authService.authenticate('shop-uuid-456', '', 'password'),
        throwsA(isA<AuthenticationException>()),
      );
      await expectLater(
        authService.authenticate('shop-uuid-456', 'staff.anura', ''),
        throwsA(isA<AuthenticationException>()),
      );
    });

    test('validateSession accepts a valid token with matching session version', () async {
      mockPg.simulatedUser = {
        'id': 'user-uuid-123',
        'shop_id': 'shop-uuid-456',
        'username': 'staff.anura',
        'full_name': 'Anura Kumara',
        'role': 'cashier',
        'is_active': true,
        'session_version': 3,
      };

      final token = jwtService.signToken(
        userId: 'user-uuid-123',
        shopId: 'shop-uuid-456',
        sessionVersion: 3,
        role: 'cashier',
      );

      final session = await authService.validateSession(token);

      expect(session.userId, equals('user-uuid-123'));
      expect(session.shopId, equals('shop-uuid-456'));
      expect(session.role, equals('cashier'));
      expect(session.sessionVersion, equals(3));
      expect(session.isActive, isTrue);
    });

    test('validateSession rejects token with revoked session version', () async {
      // DB has session_version 5, but token carries version 3
      mockPg.simulatedUser = {
        'id': 'user-uuid-123',
        'shop_id': 'shop-uuid-456',
        'username': 'staff.anura',
        'full_name': 'Anura Kumara',
        'role': 'cashier',
        'is_active': true,
        'session_version': 5,
      };

      final token = jwtService.signToken(
        userId: 'user-uuid-123',
        shopId: 'shop-uuid-456',
        sessionVersion: 3,
        role: 'cashier',
      );

      await expectLater(
        authService.validateSession(token),
        throwsA(isA<SessionValidationException>().having(
          (e) => e.message,
          'message',
          contains('Session revoked'),
        )),
      );
    });

    test('validateSession rejects token for deactivated user', () async {
      mockPg.simulatedUser = {
        'id': 'user-uuid-123',
        'shop_id': 'shop-uuid-456',
        'username': 'staff.anura',
        'full_name': 'Anura Kumara',
        'role': 'cashier',
        'is_active': false,
        'session_version': 3,
      };

      final token = jwtService.signToken(
        userId: 'user-uuid-123',
        shopId: 'shop-uuid-456',
        sessionVersion: 3,
        role: 'cashier',
      );

      await expectLater(
        authService.validateSession(token),
        throwsA(isA<SessionValidationException>().having(
          (e) => e.message,
          'message',
          contains('Account is deactivated'),
        )),
      );
    });

    test('validateSession rejects token for non-existent user', () async {
      mockPg.userExists = false;

      final token = jwtService.signToken(
        userId: 'nonexistent-user',
        shopId: 'shop-uuid-456',
        sessionVersion: 1,
        role: 'cashier',
      );

      await expectLater(
        authService.validateSession(token),
        throwsA(isA<SessionValidationException>()),
      );
    });

    test('validateSession rejects token with missing role claim', () async {
      // Build a token with valid signature but missing role claim
      final tamperedToken = _buildTamperedAuthToken(jwtService, removeKey: 'role');

      await expectLater(
        authService.validateSession(tamperedToken),
        throwsA(isA<SessionValidationException>().having(
          (e) => e.message,
          'message',
          equals('Invalid token claims'),
        )),
      );
    });

    test('validateSession accepts token with non-standard role claim', () async {
      mockPg.simulatedUser = {
        'id': 'user-uuid-123',
        'shop_id': 'shop-uuid-456',
        'username': 'staff.anura',
        'full_name': 'Anura Kumara',
        'role': 'cashier',
        'is_active': true,
        'session_version': 1,
      };

      // Build a token with valid signature but non-standard role
      final tamperedToken = _buildTamperedAuthToken(jwtService, role: 'not_a_real_role');

      // validateSession accepts any non-empty role string; AppRole validation
      // happens at SessionGuard level which handles invalid roles gracefully.
      final session = await authService.validateSession(tamperedToken);
      expect(session.role, equals('not_a_real_role'));
    });

    test('validateSession rejects invalid token signature', () async {
      await expectLater(
        authService.validateSession('invalid.token.format'),
        throwsA(isA<SessionValidationException>()),
      );
    });

    test('validateSession sets tenant context from trusted JWT claim', () async {
      mockPg.simulatedUser = {
        'id': 'user-uuid-123',
        'shop_id': 'shop-uuid-456',
        'username': 'staff.anura',
        'full_name': 'Anura Kumara',
        'role': 'cashier',
        'is_active': true,
        'session_version': 1,
      };

      final token = jwtService.signToken(
        userId: 'user-uuid-123',
        shopId: 'shop-uuid-456',
        sessionVersion: 1,
        role: 'cashier',
      );

      await authService.validateSession(token);

      // Tenant context derived from JWT claim (trusted), not client input
      expect(mockPg.tenantContexts, contains('shop-uuid-456'));
    });

    test('revokeSession deactivates user and increments session version', () async {
      mockPg.simulatedUser = {
        'id': 'user-uuid-123',
        'shop_id': 'shop-uuid-456',
        'username': 'staff.anura',
        'full_name': 'Anura Kumara',
        'role': 'cashier',
        'is_active': true,
        'session_version': 1,
      };

      await authService.revokeSession('shop-uuid-456', 'user-uuid-123');

      // Verify UPDATE was executed (deactivation + session version increment)
      final updateSql = mockPg.executedStatements.where(
        (s) => s.contains('UPDATE app_users'),
      );
      expect(updateSql.isNotEmpty, isTrue);

      // Verify audit function was executed (SECURITY DEFINER function owned by cs_audit_writer)
      final auditSql = mockPg.executedStatements.where(
        (s) => s.contains('cs_record_audit_event'),
      );
      expect(auditSql.isNotEmpty, isTrue);
    });

    test('revokeSession throws StateError for non-existent user', () async {
      mockPg.userExists = false;

      await expectLater(
        authService.revokeSession('shop-uuid-456', 'nonexistent-user'),
        throwsA(isA<StateError>()),
      );
    });

    test('authenticateOffline rejects when offline session expired', () async {
      final mockStorage = MockSecureStorage();
      // Set offline session expiry to 1 hour ago
      await mockStorage.write(
        key: 'offline_session_expiry',
        value: DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
      );

      final expiredAuthService = AuthService(
        pg: mockPg,
        jwt: jwtService,
        passwordHash: passwordHash,
        secureStorage: mockStorage,
      );

      mockPg.simulatedUser = {
        'id': 'user-uuid-123',
        'shop_id': 'shop-uuid-456',
        'username': 'staff.anura',
        'full_name': 'Anura Kumara',
        'role': 'cashier',
        'is_active': true,
        'session_version': 3,
        'password_hash': '\$argon2id\$v=19\$m=65536,t=3,p=4\$salt\$hash',
      };

      await expectLater(
        expiredAuthService.authenticateOffline(
          'shop-uuid-456',
          'staff.anura',
          'password',
          localUserData: {
            'id': 'user-uuid-123',
            'shop_id': 'shop-uuid-456',
            'username': 'staff.anura',
            'full_name': 'Anura Kumara',
            'role': 'cashier',
            'is_active': true,
            'session_version': 3,
            'password_hash': '\$argon2id\$v=19\$m=65536,t=3,p=4\$salt\$hash',
          },
        ),
        throwsA(isA<AuthenticationException>().having(
          (e) => e.message,
          'message',
          equals('Offline session expired. Please log in online.'),
        )),
      );
    });

    test('authenticateOffline rejects when no offline session recorded', () async {
      final mockStorage = MockSecureStorage();
      // No offline_session_expiry recorded - no prior online authentication

      final expiredAuthService = AuthService(
        pg: mockPg,
        jwt: jwtService,
        passwordHash: passwordHash,
        secureStorage: mockStorage,
      );

      mockPg.simulatedUser = {
        'id': 'user-uuid-123',
        'shop_id': 'shop-uuid-456',
        'username': 'staff.anura',
        'full_name': 'Anura Kumara',
        'role': 'cashier',
        'is_active': true,
        'session_version': 3,
        'password_hash': '\$argon2id\$v=19\$m=65536,t=3,p=4\$salt\$hash',
      };

      await expectLater(
        expiredAuthService.authenticateOffline(
          'shop-uuid-456',
          'staff.anura',
          'password',
          localUserData: {
            'id': 'user-uuid-123',
            'shop_id': 'shop-uuid-456',
            'username': 'staff.anura',
            'full_name': 'Anura Kumara',
            'role': 'cashier',
            'is_active': true,
            'session_version': 3,
            'password_hash': '\$argon2id\$v=19\$m=65536,t=3,p=4\$salt\$hash',
          },
        ),
        throwsA(isA<AuthenticationException>().having(
          (e) => e.message,
          'message',
          equals('Offline session expired. Please log in online.'),
        )),
      );
    });

    test('authenticateOffline rejects shop mismatch', () async {
      final mockStorage = MockSecureStorage();
      await mockStorage.write(
        key: 'offline_session_expiry',
        value: DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
      );

      final expiredAuthService = AuthService(
        pg: mockPg,
        jwt: jwtService,
        passwordHash: passwordHash,
        secureStorage: mockStorage,
      );

      mockPg.simulatedUser = {
        'id': 'user-uuid-123',
        'shop_id': 'shop-uuid-456',
        'username': 'staff.anura',
        'full_name': 'Anura Kumara',
        'role': 'cashier',
        'is_active': true,
        'session_version': 3,
        'password_hash': '\$argon2id\$v=19\$m=65536,t=3,p=4\$salt\$hash',
      };

      await expectLater(
        expiredAuthService.authenticateOffline(
          'shop-uuid-999', // Mismatched shop ID
          'staff.anura',
          'password',
          localUserData: {
            'id': 'user-uuid-123',
            'shop_id': 'shop-uuid-456',
            'username': 'staff.anura',
            'full_name': 'Anura Kumara',
            'role': 'cashier',
            'is_active': true,
            'session_version': 3,
            'password_hash': '\$argon2id\$v=19\$m=65536,t=3,p=4\$salt\$hash',
          },
        ),
        throwsA(isA<AuthenticationException>().having(
          (e) => e.message,
          'message',
          equals('Invalid credentials'),
        )),
      );
    });

    test('clearCachedSession clears JWT but does not deactivate account', () async {
      mockPg.simulatedUser = {
        'id': 'user-uuid-123',
        'shop_id': 'shop-uuid-456',
        'username': 'staff.anura',
        'full_name': 'Anura Kumara',
        'role': 'cashier',
        'is_active': true,
        'session_version': 3,
        'password_hash': '\$argon2id\$v=19\$m=65536,t=3,p=4\$salt\$hash',
      };

      // First authenticate online to set cached JWT
      mockPg.simulatedUser = {
        'id': 'user-uuid-123',
        'shop_id': 'shop-uuid-456',
        'username': 'staff.anura',
        'full_name': 'Anura Kumara',
        'role': 'cashier',
        'is_active': true,
        'session_version': 3,
        'password_hash': passwordHash.hashPassword('password'),
      };

      await authService.authenticate(
        'shop-uuid-456',
        'staff.anura',
        'password',
      );

      // Verify JWT is cached
      expect(await authService.hasCachedToken(), isTrue);

      // Clear cached session (logout)
      await authService.clearCachedSession();

      // Verify JWT is cleared
      expect(await authService.hasCachedToken(), isFalse);

      // Verify user is still active in the mock (not deactivated)
      expect(mockPg.simulatedUser!['is_active'], isTrue);
      expect(mockPg.simulatedUser!['session_version'], equals(3));
    });

    test('validateSession rejects token with expired JWT', () async {
      // Build a token with expired exp claim by modifying the JWT payload
      final validToken = jwtService.signToken(
        userId: 'user-uuid-123',
        shopId: 'shop-uuid-456',
        sessionVersion: 3,
        role: 'cashier',
      );
      final parts = validToken.split('.');
      final originalPayload = _decodeAuthJwtPayload(parts[1]);
      final modifiedPayload = Map<String, dynamic>.from(originalPayload);
      modifiedPayload['exp'] =
          (DateTime.now().subtract(const Duration(hours: 2)))
              .millisecondsSinceEpoch ~/ 1000;

      final headerB64 = parts[0];
      final payloadB64 = base64Url.encode(utf8.encode(jsonEncode(modifiedPayload)));
      final signingInput = '$headerB64.$payloadB64';
      final key = utf8.encode('test-secret-key-for-testing-only');
      final hmac = Hmac(sha256, key);
      final sigBytes = Uint8List.fromList(hmac.convert(utf8.encode(signingInput)).bytes);
      final signatureB64 = base64Url.encode(sigBytes);
      final expiredTokenString = '$headerB64.$payloadB64.$signatureB64';

      mockPg.simulatedUser = {
        'id': 'user-uuid-123',
        'shop_id': 'shop-uuid-456',
        'username': 'staff.anura',
        'full_name': 'Anura Kumara',
        'role': 'cashier',
        'is_active': true,
        'session_version': 3,
      };

      await expectLater(
        authService.validateSession(expiredTokenString),
        throwsA(isA<SessionValidationException>().having(
          (e) => e.message,
          'message',
          contains('Invalid or expired token'),
        )),
      );
    });

    test('validateSession accepts token after offline authentication and reconnection', () async {
      mockPg.simulatedUser = {
        'id': 'user-uuid-123',
        'shop_id': 'shop-uuid-456',
        'username': 'staff.anura',
        'full_name': 'Anura Kumara',
        'role': 'cashier',
        'is_active': true,
        'session_version': 3,
        'password_hash': passwordHash.hashPassword('password'),
      };

      // Set offline expiry
      final mockStorage = MockSecureStorage();
      await mockStorage.write(
        key: 'offline_session_expiry',
        value: DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
      );

      final offlineAuthService = AuthService(
        pg: mockPg,
        jwt: jwtService,
        passwordHash: passwordHash,
        secureStorage: mockStorage,
      );

      // Authenticate offline
      final offlineResult = await offlineAuthService.authenticateOffline(
        'shop-uuid-456',
        'staff.anura',
        'password',
        localUserData: {
          'id': 'user-uuid-123',
          'shop_id': 'shop-uuid-456',
          'username': 'staff.anura',
          'full_name': 'Anura Kumara',
          'role': 'cashier',
          'is_active': true,
          'session_version': 3,
          'password_hash': passwordHash.hashPassword('password'),
        },
      );

      expect(offlineResult.isOfflineOnly, isTrue);

      // Now validate online (reconnection)
      final session = await authService.validateSession(
        jwtService.signToken(
          userId: 'user-uuid-123',
          shopId: 'shop-uuid-456',
          sessionVersion: 3,
          role: 'cashier',
        ),
      );

      expect(session.isOfflineOnly, isFalse);
      expect(session.isActive, isTrue);
    });
  });
}

/// Builds a JWT token with valid signature for testing validateSession.
/// Takes a valid token from [jwtService], modifies the payload claims, and
/// re-signs with the same secret.
///
/// If [removeKey] is specified, that key is removed from the payload instead
/// of being overridden.
String _buildTamperedAuthToken(
  JwtService jwtService, {
  String? removeKey,
  String? role,
}) {
  final validToken = jwtService.signToken(
    userId: 'user-uuid-123',
    shopId: 'shop-uuid-456',
    sessionVersion: 1,
    role: 'cashier',
  );
  final parts = validToken.split('.');

  // Decode the original payload
  final originalPayload = _decodeAuthJwtPayload(parts[1]);

  // Apply modifications
  final modifiedPayload = Map<String, dynamic>.from(originalPayload);
  if (removeKey != null) {
    modifiedPayload.remove(removeKey);
  }
  if (role != null) {
    modifiedPayload['role'] = role;
  }

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
Map<String, dynamic> _decodeAuthJwtPayload(String base64UrlPayload) {
  final jsonStr = utf8.decode(base64Url.decode(base64UrlPayload));
  return jsonDecode(jsonStr) as Map<String, dynamic>;
}

/// Mock [SecureStorage] for unit testing.
class MockSecureStorage implements SecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<bool> write({required String key, required String value}) async {
    _store[key] = value;
    return true;
  }

  @override
  Future<String?> read({required String key}) async => _store[key];

  @override
  Future<bool> delete({required String key}) async {
    _store.remove(key);
    return true;
  }

  @override
  Future<bool> deleteAll() async {
    _store.clear();
    return true;
  }
}
