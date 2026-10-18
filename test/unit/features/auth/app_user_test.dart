import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';

void main() {
  group('AppUser Domain Model & Permission Invariant Tests (Story 1.7)', () {
    test('creates valid Cashier user with default role permissions', () {
      final user = AppUser(
        id: 'user-uuid-101',
        shopId: 'shop-uuid-001',
        username: 'kamal.cashier',
        fullName: 'Kamal Perera',
        role: AppRole.cashier,
      );

      expect(user.id, equals('user-uuid-101'));
      expect(user.shopId, equals('shop-uuid-001'));
      expect(user.username, equals('kamal.cashier'));
      expect(user.fullName, equals('Kamal Perera'));
      expect(user.role, equals(AppRole.cashier));
      expect(user.isActive, isTrue);
      expect(user.sessionVersion, equals(1));
      expect(user.hasPermission(AppPermission.recordPayments), isTrue);
      expect(user.hasPermission(AppPermission.viewCustomers), isTrue);
      expect(user.hasPermission(AppPermission.approveCorrections), isFalse);
      expect(user.effectivePermissions.length, equals(6));
    });

    test('creates valid Custom user with explicitly assigned permissions', () {
      final customPerms = {
        AppPermission.viewCustomers,
        AppPermission.viewOverdueLoans,
        AppPermission.recordCustomerNotes,
      };

      final user = AppUser(
        id: 'user-uuid-102',
        shopId: 'shop-uuid-001',
        username: 'sunil.custom',
        fullName: 'Sunil Silva',
        role: AppRole.custom,
        customPermissions: customPerms,
      );

      expect(user.role, equals(AppRole.custom));
      expect(user.effectivePermissions, equals(customPerms));
      expect(user.hasPermission(AppPermission.viewOverdueLoans), isTrue);
      expect(user.hasPermission(AppPermission.recordPayments), isFalse);
    });

    test('SESSION REVOCATION CONTRACT: isSessionValid strictly requires active account and matching session version', () {
      final user = AppUser(
        id: 'user-uuid-103',
        shopId: 'shop-uuid-001',
        username: 'nimal.staff',
        fullName: 'Nimal Fernando',
        role: AppRole.cashier,
        sessionVersion: 3,
      );

      // Valid session version 3
      expect(user.isSessionValid(3), isTrue);

      // Outdated session version 2 or 1 (revoked)
      expect(user.isSessionValid(2), isFalse);
      expect(user.isSessionValid(1), isFalse);

      // Deactivated user invalidates even matching session versions
      final deactivated = user.copyWith(isActive: false);
      expect(deactivated.isSessionValid(3), isFalse);
    });

    test('VALIDATION: rejects invalid or empty invariants', () {
      expect(
        () => AppUser(
          id: '',
          shopId: 'shop-1',
          username: 'user',
          fullName: 'Name',
          role: AppRole.cashier,
        ),
        throwsA(isA<AppUserValidationException>().having(
          (e) => e.message,
          'message',
          contains('User ID cannot be empty'),
        )),
      );

      expect(
        () => AppUser(
          id: 'user-1',
          shopId: '',
          username: 'user',
          fullName: 'Name',
          role: AppRole.cashier,
        ),
        throwsA(isA<AppUserValidationException>().having(
          (e) => e.message,
          'message',
          contains('Shop ID cannot be empty'),
        )),
      );

      expect(
        () => AppUser(
          id: 'user-1',
          shopId: 'shop-1',
          username: 'user',
          fullName: 'Name',
          role: AppRole.cashier,
          sessionVersion: 0,
        ),
        throwsA(isA<AppUserValidationException>().having(
          (e) => e.message,
          'message',
          contains('Session version must be >= 1'),
        )),
      );
    });

    test('SERIALIZATION: serializes and parses custom permissions cleanly', () {
      final user = AppUser(
        id: 'user-1',
        shopId: 'shop-1',
        username: 'user',
        fullName: 'Name',
        role: AppRole.custom,
        customPermissions: {
          AppPermission.createLoans,
          AppPermission.recordPayments,
        },
      );

      final serialized = user.serializePermissions();
      expect(serialized, isNotNull);
      expect(serialized, contains('createLoans'));
      expect(serialized, contains('recordPayments'));

      final parsed = AppUser.parsePermissions(serialized);
      expect(parsed, equals(user.customPermissions));
    });
  });
}
