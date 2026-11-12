/// The authoritative 14-permission enumeration catalog (PRD FR-6, AD-6, Story 1.7).
///
/// This catalog is strictly fixed: no permission can be added, removed, or redefined
/// outside of this catalog.
enum AppPermission {
  /// Register new customers and edit permitted profile details.
  registerCustomers('registerCustomers'),

  /// Search and view customer contact details and photographs.
  viewCustomers('viewCustomers'),

  /// View unmasked sensitive identity data (full NIC and residential address).
  viewSensitiveCustomerData('viewSensitiveCustomerData'),

  /// Create new credit agreements and register attached pledged items.
  createCredits('createCredits'),

  /// Confirm physical cash disbursement and record disbursement handover.
  confirmCreditDisbursement('confirmCreditDisbursement'),

  /// Record partial payments and full settlements against disbursed credits.
  recordPayments('recordPayments'),

  /// View payment histories and reprint existing payment receipts.
  viewAndReprintReceipts('viewAndReprintReceipts'),

  /// Access and review overdue credit queues and delinquency reports.
  viewOverdueCredits('viewOverdueCredits'),

  /// Record customer interaction notes, follow-up calls, and promises to pay.
  recordCustomerNotes('recordCustomerNotes'),

  /// Submit requests for financial transaction corrections or reversals.
  requestCorrections('requestCorrections'),

  /// Authorize or reject pending financial corrections and reversals (Restricted to Owner by default).
  approveCorrections('approveCorrections'),

  /// Confirm physical handover and release of pledged collateral items back to customer.
  confirmCollateralReturn('confirmCollateralReturn'),

  /// View daily cash collection reports, till summaries, and shop-level financial metrics.
  viewFinancialReports('viewFinancialReports'),

  /// Access and review the shop's append-only, tamper-resistant activity audit trail.
  viewAuditLogs('viewAuditLogs');

  final String key;
  const AppPermission(this.key);

  /// Resolves an [AppPermission] from its canonical string key.
  /// Throws [ArgumentError] if the key does not match the 14-permission catalog.
  static AppPermission fromKey(String key) {
    for (final perm in AppPermission.values) {
      if (perm.key == key) return perm;
    }
    throw ArgumentError.value(
      key,
      'key',
      'Unknown permission. Must be one of the approved 14 permissions in AppPermission catalog.',
    );
  }

  /// Safely resolves an [AppPermission] from its key, returning null if invalid.
  static AppPermission? tryFromKey(String key) {
    for (final perm in AppPermission.values) {
      if (perm.key == key) return perm;
    }
    return null;
  }
}

/// System user roles defining permission templates and administrative governance.
enum AppRole {
  /// Shop Owner: Full access to all 14 permissions and sole authority for administrative actions.
  shopOwner('shop_owner', 'Shop Owner'),

  /// Manager: Senior staff handling credit disbursements, customer identity unmasking, and reports.
  manager('manager', 'Manager'),

  /// Cashier: Counter staff handling customer intake, credit creation, and payments.
  cashier('cashier', 'Cashier'),

  /// Custom: Granular custom permissions explicitly assigned by the Shop Owner.
  custom('custom', 'Custom');

  final String key;
  final String displayName;
  const AppRole(this.key, this.displayName);

  /// Resolves an [AppRole] from a string identifier (case-insensitive, supports aliases).
  static AppRole fromKey(String key) {
    final normalized = key.trim().toLowerCase();
    switch (normalized) {
      case 'shop_owner':
      case 'shopowner':
      case 'owner':
        return AppRole.shopOwner;
      case 'manager':
        return AppRole.manager;
      case 'cashier':
      case 'counter_staff':
      case 'counterstaff':
      case 'staff':
        return AppRole.cashier;
      case 'custom':
        return AppRole.custom;
      default:
        throw ArgumentError.value(key, 'key', 'Unrecognized AppRole identifier.');
    }
  }

  /// Returns whether this role is the privileged Shop Owner.
  bool get isOwner => this == AppRole.shopOwner;
}

/// Approved role permission templates implementing the 14-permission catalog mapping.
class RolePermissionTemplates {
  const RolePermissionTemplates._();

  /// Default permissions for Cashier role.
  static const Set<AppPermission> cashierPermissions = {
    AppPermission.viewCustomers,
    AppPermission.registerCustomers,
    AppPermission.createCredits,
    AppPermission.recordPayments,
    AppPermission.viewAndReprintReceipts,
    AppPermission.recordCustomerNotes,
  };

  /// Default permissions for Manager role (Cashier + management oversight).
  static const Set<AppPermission> managerPermissions = {
    ...cashierPermissions,
    AppPermission.viewSensitiveCustomerData,
    AppPermission.confirmCreditDisbursement,
    AppPermission.viewOverdueCredits,
    AppPermission.requestCorrections,
    AppPermission.confirmCollateralReturn,
    AppPermission.viewFinancialReports,
  };

  /// Default permissions for Shop Owner (All 14 permissions).
  static final Set<AppPermission> shopOwnerPermissions =
      Set<AppPermission>.unmodifiable(AppPermission.values);

  /// Resolves the default permission set for a given [role].
  static Set<AppPermission> defaultPermissionsForRole(AppRole role) {
    switch (role) {
      case AppRole.shopOwner:
        return shopOwnerPermissions;
      case AppRole.manager:
        return managerPermissions;
      case AppRole.cashier:
        return cashierPermissions;
      case AppRole.custom:
        return const <AppPermission>{};
    }
  }
}

