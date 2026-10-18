import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/core/permissions/authorization_guard.dart';

void main() {
  group('AuthorizationGuard - Deny-by-Default & Granular RBAC Tests (Story 1.7)', () {
    test('DENY-BY-DEFAULT: denies action when permission toggle is absent', () {
      final cashierPerms = RolePermissionTemplates.cashierPermissions;

      // Cashier has recordPayments
      expect(
        AuthorizationGuard.hasPermission(
          isActive: true,
          effectivePermissions: cashierPerms,
          permission: AppPermission.recordPayments,
        ),
        isTrue,
      );

      // Cashier lacks approveCorrections
      expect(
        AuthorizationGuard.hasPermission(
          isActive: true,
          effectivePermissions: cashierPerms,
          permission: AppPermission.approveCorrections,
        ),
        isFalse,
      );

      expect(
        () => AuthorizationGuard.checkPermission(
          isActive: true,
          effectivePermissions: cashierPerms,
          permission: AppPermission.approveCorrections,
          actionDescription: 'approve payment correction',
        ),
        throwsA(isA<PermissionDeniedException>().having(
          (e) => e.message,
          'message',
          contains('approveCorrections'),
        )),
      );
    });

    test('INACTIVE ACCOUNT: unconditionally denies any action when isActive = false', () {
      final ownerPerms = RolePermissionTemplates.shopOwnerPermissions;

      // Deactivated user cannot execute any action even if role is Owner
      expect(
        AuthorizationGuard.hasPermission(
          isActive: false,
          effectivePermissions: ownerPerms,
          permission: AppPermission.recordPayments,
        ),
        isFalse,
      );

      expect(
        () => AuthorizationGuard.checkPermission(
          isActive: false,
          effectivePermissions: ownerPerms,
          permission: AppPermission.recordPayments,
        ),
        throwsA(isA<PermissionDeniedException>().having(
          (e) => e.message,
          'message',
          contains('deactivated'),
        )),
      );
    });

    test('OWNER ADMINISTRATIVE ACTIONS: only Shop Owner can perform administrative governance', () {
      // Shop Owner passes
      expect(
        () => AuthorizationGuard.checkOwnerAdministrativeAction(
          isActive: true,
          actorRole: AppRole.shopOwner,
          actionDescription: 'create new staff member',
        ),
        returnsNormally,
      );

      // Manager fails with 403 Forbidden
      expect(
        () => AuthorizationGuard.checkOwnerAdministrativeAction(
          isActive: true,
          actorRole: AppRole.manager,
          actionDescription: 'create new staff member',
        ),
        throwsA(isA<PermissionDeniedException>().having(
          (e) => e.message,
          'message',
          contains('403 Forbidden: Only a Shop Owner can create new staff member'),
        )),
      );

      // Cashier fails with 403 Forbidden
      expect(
        () => AuthorizationGuard.checkOwnerAdministrativeAction(
          isActive: true,
          actorRole: AppRole.cashier,
          actionDescription: 'deactivate staff account',
        ),
        throwsA(isA<PermissionDeniedException>().having(
          (e) => e.message,
          'message',
          contains('403 Forbidden: Only a Shop Owner can deactivate staff account'),
        )),
      );
    });

    test('PRIVILEGE ESCALATION: non-owners cannot assign roles or permissions', () {
      expect(
        () => AuthorizationGuard.validateStaffAssignment(
          actorIsActive: true,
          actorRole: AppRole.manager, // Manager attempting to assign
          actorEffectivePermissions: RolePermissionTemplates.managerPermissions,
          targetRole: AppRole.cashier,
          targetPermissions: RolePermissionTemplates.cashierPermissions,
        ),
        throwsA(isA<PrivilegeEscalationException>().having(
          (e) => e.message,
          'message',
          contains('Only Shop Owners can manage staff accounts'),
        )),
      );
    });

    test('All 14 permissions evaluate independently under AuthorizationGuard', () {
      final ownerPerms = RolePermissionTemplates.shopOwnerPermissions;
      for (final perm in AppPermission.values) {
        expect(
          AuthorizationGuard.hasPermission(
            isActive: true,
            effectivePermissions: ownerPerms,
            permission: perm,
          ),
          isTrue,
        );

        // Single-permission user has only that permission
        final singlePerm = {perm};
        for (final testPerm in AppPermission.values) {
          final expected = testPerm == perm;
          expect(
            AuthorizationGuard.hasPermission(
              isActive: true,
              effectivePermissions: singlePerm,
              permission: testPerm,
            ),
            equals(expected),
          );
        }
      }
    });
  });
}
