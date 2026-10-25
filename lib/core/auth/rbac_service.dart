// RBAC service with basic permission matrix
class RbacService {
  static const _rolePermissions = <String, Set<String>>{
    'admin': {
      'view_shop', 'edit_shop', 'manage_staff', 'view_loans', 'create_loan',
      'approve_loan', 'disburse_loan', 'view_payments', 'record_payment',
      'reverse_payment', 'view_reports', 'export_data', 'manage_settings', 'audit_view',
    },
    'staff': {
      'view_shop', 'view_loans', 'create_loan', 'view_payments', 'record_payment',
    },
    'viewer': {'view_shop', 'view_loans', 'view_payments', 'view_reports'},
  };

  bool hasPermission(String role, String permission) {
    return _rolePermissions[role]?.contains(permission) ?? false;
  }
}