import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/permissions/app_permission.dart';

void main() {
  group('14-Permission Catalog Completeness & Invariants (Story 1.7, FR-6, AD-6)', () {
    test('catalog contains exactly the 14 approved operational permissions', () {
      expect(AppPermission.values.length, equals(14));

      final expectedKeys = {
        'registerCustomers',
        'viewCustomers',
        'viewSensitiveCustomerData',
        'createLoans',
        'confirmLoanDisbursement',
        'recordPayments',
        'viewAndReprintReceipts',
        'viewOverdueLoans',
        'recordCustomerNotes',
        'requestCorrections',
        'approveCorrections',
        'confirmCollateralReturn',
        'viewFinancialReports',
        'viewAuditLogs',
      };

      final actualKeys = AppPermission.values.map((p) => p.key).toSet();
      expect(actualKeys, equals(expectedKeys));
    });

    test('fromKey resolves all 14 permissions correctly', () {
      for (final perm in AppPermission.values) {
        expect(AppPermission.fromKey(perm.key), equals(perm));
        expect(AppPermission.tryFromKey(perm.key), equals(perm));
      }
    });

    test('fromKey rejects unauthorized or misspelled permission keys', () {
      expect(
        () => AppPermission.fromKey('deleteDatabase'),
        throwsArgumentError,
      );
      expect(
        () => AppPermission.fromKey('adminSuperuser'),
        throwsArgumentError,
      );
      expect(
        () => AppPermission.fromKey('registerCustomer'), // Missing trailing 's'
        throwsArgumentError,
      );
      expect(AppPermission.tryFromKey('unknownKey'), isNull);
    });
  });

  group('Role Permission Templates (Story 1.7)', () {
    test('Cashier role template has exactly the 6 required counter permissions', () {
      final perms = RolePermissionTemplates.cashierPermissions;
      expect(perms.length, equals(6));
      expect(
        perms,
        containsAll([
          AppPermission.viewCustomers,
          AppPermission.registerCustomers,
          AppPermission.createLoans,
          AppPermission.recordPayments,
          AppPermission.viewAndReprintReceipts,
          AppPermission.recordCustomerNotes,
        ]),
      );
      // Verify Cashier lacks sensitive management permissions
      expect(perms.contains(AppPermission.viewSensitiveCustomerData), isFalse);
      expect(perms.contains(AppPermission.confirmLoanDisbursement), isFalse);
      expect(perms.contains(AppPermission.approveCorrections), isFalse);
      expect(perms.contains(AppPermission.viewAuditLogs), isFalse);
    });

    test('Manager role template has Cashier permissions + 6 management permissions (12 total)', () {
      final perms = RolePermissionTemplates.managerPermissions;
      expect(perms.length, equals(12));

      // Contains all Cashier permissions
      for (final cashierPerm in RolePermissionTemplates.cashierPermissions) {
        expect(perms.contains(cashierPerm), isTrue);
      }

      // Plus management permissions
      expect(perms.contains(AppPermission.viewSensitiveCustomerData), isTrue);
      expect(perms.contains(AppPermission.confirmLoanDisbursement), isTrue);
      expect(perms.contains(AppPermission.viewOverdueLoans), isTrue);
      expect(perms.contains(AppPermission.requestCorrections), isTrue);
      expect(perms.contains(AppPermission.confirmCollateralReturn), isTrue);
      expect(perms.contains(AppPermission.viewFinancialReports), isTrue);

      // Manager specifically does NOT have approveCorrections or viewAuditLogs by default
      expect(perms.contains(AppPermission.approveCorrections), isFalse);
      expect(perms.contains(AppPermission.viewAuditLogs), isFalse);
    });

    test('Shop Owner role template has all 14 permissions', () {
      final perms = RolePermissionTemplates.shopOwnerPermissions;
      expect(perms.length, equals(14));
      expect(perms, containsAll(AppPermission.values));
    });

    test('Custom role default template is empty (assigned explicitly by Shop Owner)', () {
      final perms = RolePermissionTemplates.defaultPermissionsForRole(AppRole.custom);
      expect(perms, isEmpty);
    });

    test('AppRole resolution supports canonical keys and common aliases', () {
      expect(AppRole.fromKey('shop_owner'), equals(AppRole.shopOwner));
      expect(AppRole.fromKey('owner'), equals(AppRole.shopOwner));
      expect(AppRole.fromKey('manager'), equals(AppRole.manager));
      expect(AppRole.fromKey('cashier'), equals(AppRole.cashier));
      expect(AppRole.fromKey('counter_staff'), equals(AppRole.cashier));
      expect(AppRole.fromKey('custom'), equals(AppRole.custom));
      expect(() => AppRole.fromKey('superuser'), throwsArgumentError);
    });
  });
}
