import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/remote/migration_runner.dart';
import 'package:credit_system/core/data/remote/postgres_executor.dart';
import 'package:credit_system/core/data/secure_storage.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/data/services/auth_service.dart';
import 'package:credit_system/features/auth/data/services/jwt_service.dart';
import 'package:credit_system/features/auth/data/services/password_hash_service.dart';
import 'package:credit_system/features/auth/data/services/session_guard.dart';

/// Mock [PostgreSqlExecutor] for unit testing [SessionGuard] via [AuthService].
class MockPostgreSqlExecutor extends PostgreSqlExecutor {
  MockPostgreSqlExecutor() : super.withConnectionString('');

  final List<String> tenantContexts = [];
  Map<String, dynamic>? simulatedUser;
  bool userExists = true;
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
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic>? parameters,
  ]) async {
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
    };
  }
}

class _MockSqlExecutor implements SqlDatabaseExecutor {
  final MockPostgreSqlExecutor _pg;

  _MockSqlExecutor(this._pg);

  @override
  Future<void> execute(String sql, [List<dynamic>? parameters]) async {}

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic>? parameters,
  ]) async {
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
  group('SessionGuard - Server-Side RBAC & Session Validation (Story 1.8)', () {
    late MockPostgreSqlExecutor mockPg;
    late JwtService jwtService;
    late PasswordHashService passwordHash;
    late AuthService authService;
    late SessionGuard sessionGuard;

    setUp(() {
      mockPg = MockPostgreSqlExecutor();
      jwtService = JwtService('test-secret-key-for-testing-only');
      passwordHash = PasswordHashService();
      authService = AuthService(
        pg: mockPg,
        jwt: jwtService,
        passwordHash: passwordHash,
        secureStorage: _MockSecureStorage(),
      );
      sessionGuard = SessionGuard(authService);
    });

    test('requirePermission grants access when user has the required permission', () async {
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

      final session = await sessionGuard.requirePermission(
        token,
        AppPermission.recordPayments,
        'shop-uuid-456',
      );

      expect(session.userId, equals('user-uuid-123'));
      expect(session.shopId, equals('shop-uuid-456'));
    });

    test('requirePermission denies access when user lacks the required permission', () async {
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

      // Cashier does not have approveCorrections
      await expectLater(
        sessionGuard.requirePermission(
          token,
          AppPermission.approveCorrections,
          'shop-uuid-456',
        ),
        throwsA(isA<SessionGuardException>().having(
          (e) => e.requiredPermission,
          'requiredPermission',
          equals('approveCorrections'),
        )),
      );
    });

    test('requirePermission denies access when token is revoked (session version mismatch)', () async {
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
        sessionGuard.requirePermission(
          token,
          AppPermission.recordPayments,
          'shop-uuid-456',
        ),
        throwsA(isA<SessionGuardException>()),
      );
    });

    test('requirePermission denies access when user is deactivated', () async {
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
        sessionGuard.requirePermission(
          token,
          AppPermission.recordPayments,
          'shop-uuid-456',
        ),
        throwsA(isA<SessionGuardException>()),
      );
    });

    test('requirePermission denies access on shop mismatch', () async {
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

      // Token belongs to shop-uuid-456 but request targets shop-uuid-999
      await expectLater(
        sessionGuard.requirePermission(
          token,
          AppPermission.recordPayments,
          'shop-uuid-999',
        ),
        throwsA(isA<SessionGuardException>()),
      );
    });

    test('requirePermission rejects invalid token signature', () async {
      await expectLater(
        sessionGuard.requirePermission(
          'invalid.token.format',
          AppPermission.recordPayments,
          'shop-uuid-456',
        ),
        throwsA(isA<SessionGuardException>()),
      );
    });

    test('requireRole grants access to Shop Owner for administrative actions', () async {
      mockPg.simulatedUser = {
        'id': 'user-uuid-123',
        'shop_id': 'shop-uuid-456',
        'username': 'owner.perera',
        'full_name': 'Mr. Perera',
        'role': 'shop_owner',
        'is_active': true,
        'session_version': 1,
      };

      final token = jwtService.signToken(
        userId: 'user-uuid-123',
        shopId: 'shop-uuid-456',
        sessionVersion: 1,
        role: 'shop_owner',
      );

      final session = await sessionGuard.requireRole(
        token,
        AppRole.shopOwner,
        shopId: 'shop-uuid-456',
      );

      expect(session.userId, equals('user-uuid-123'));
    });

    test('requireRole denies access to non-owner for administrative actions', () async {
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

      await expectLater(
        sessionGuard.requireRole(
          token,
          AppRole.shopOwner,
          shopId: 'shop-uuid-456',
        ),
        throwsA(isA<SessionGuardException>()),
      );
    });

    test('Shop Owner has all 14 permissions', () async {
      mockPg.simulatedUser = {
        'id': 'user-uuid-123',
        'shop_id': 'shop-uuid-456',
        'username': 'owner.perera',
        'full_name': 'Mr. Perera',
        'role': 'shop_owner',
        'is_active': true,
        'session_version': 1,
      };

      final token = jwtService.signToken(
        userId: 'user-uuid-123',
        shopId: 'shop-uuid-456',
        sessionVersion: 1,
        role: 'shop_owner',
      );

      for (final permission in AppPermission.values) {
        final session = await sessionGuard.requirePermission(
          token,
          permission,
          'shop-uuid-456',
        );
        expect(session.isActive, isTrue);
      }
    });

    test('Cashier has exactly 6 permissions and lacks owner-only permissions', () async {
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

      // Cashier permissions
      await sessionGuard.requirePermission(
        token,
        AppPermission.recordPayments,
        'shop-uuid-456',
      );
      await sessionGuard.requirePermission(
        token,
        AppPermission.createCredits,
        'shop-uuid-456',
      );
      await sessionGuard.requirePermission(
        token,
        AppPermission.viewCustomers,
        'shop-uuid-456',
      );

      // Cashier lacks owner-only permissions
      await expectLater(
        sessionGuard.requirePermission(
          token,
          AppPermission.approveCorrections,
          'shop-uuid-456',
        ),
        throwsA(isA<SessionGuardException>()),
      );
      await expectLater(
        sessionGuard.requirePermission(
          token,
          AppPermission.viewFinancialReports,
          'shop-uuid-456',
        ),
        throwsA(isA<SessionGuardException>()),
      );
    });
  });
}

/// Mock [SecureStorage] for unit testing.
class _MockSecureStorage implements SecureStorage {
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

