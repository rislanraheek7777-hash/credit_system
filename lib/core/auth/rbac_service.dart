// RBAC service with basic permission matrix
class RbacService {
  static const _rolePermissions = <String, Set<String>>{
    'admin': {
      'view_shop', 'edit_shop', 'manage_staff', 'view_credits', 'create_credit',
      'approve_credit', 'disburse_credit', 'view_payments', 'record_payment',
      'reverse_payment', 'view_reports', 'export_data', 'manage_settings', 'audit_view',
    },
    'staff': {
      'view_shop', 'view_credits', 'create_credit', 'view_payments', 'record_payment',
    },
    'viewer': {'view_shop', 'view_credits', 'view_payments', 'view_reports'},
  };

  bool hasPermission(String role, String permission) {
    return _rolePermissions[role]?.contains(permission) ?? false;
  }
}
