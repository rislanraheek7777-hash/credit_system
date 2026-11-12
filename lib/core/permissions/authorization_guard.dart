import 'app_permission.dart';

/// Exception thrown when an action is rejected due to missing permissions or inactive account.
class PermissionDeniedException implements Exception {
  final String message;
  final String? requiredPermission;

  const PermissionDeniedException(this.message, {this.requiredPermission});

  @override
  String toString() => 'PermissionDeniedException: $message';
}

/// Exception thrown when an unauthorized privilege escalation attempt is detected.
class PrivilegeEscalationException implements Exception {
  final String message;

  const PrivilegeEscalationException(this.message);

  @override
  String toString() => 'PrivilegeEscalationException: $message';
}

/// Authoritative authorization evaluation guard implementing deny-by-default RBAC (Story 1.7).
class AuthorizationGuard {
  const AuthorizationGuard._();

  /// Evaluates whether [user] has the required [permission] under deny-by-default rules.
  ///
  /// Returns `false` if:
  /// - User is deactivated (`!isActive`)
  /// - Permission is not granted in [effectivePermissions]
  static bool hasPermission({
    required bool isActive,
    required Set<AppPermission> effectivePermissions,
    required AppPermission permission,
  }) {
    if (!isActive) return false;
    return effectivePermissions.contains(permission);
  }

  /// Asserts that [user] has the required [permission], throwing [PermissionDeniedException]
  /// if denied.
  static void checkPermission({
    required bool isActive,
    required Set<AppPermission> effectivePermissions,
    required AppPermission permission,
    String? actionDescription,
  }) {
    if (!isActive) {
      throw const PermissionDeniedException(
        'Access denied: User account is deactivated.',
      );
    }
    if (!effectivePermissions.contains(permission)) {
      final action = actionDescription ?? 'perform this action';
      throw PermissionDeniedException(
        'Access denied: Lacking required permission "${permission.key}" to $action.',
        requiredPermission: permission.key,
      );
    }
  }

  /// Asserts that the actor possesses the Shop Owner role required for administrative actions.
  ///
  /// Administrative actions (staff administration, permission modifications, account deactivation,
  /// shop profile updates, correction approvals, due-date extensions) are strictly owner-controlled.
  static void checkOwnerAdministrativeAction({
    required bool isActive,
    required AppRole actorRole,
    required String actionDescription,
  }) {
    if (!isActive) {
      throw const PermissionDeniedException(
        'Access denied: User account is deactivated.',
      );
    }
    if (!actorRole.isOwner) {
      throw PermissionDeniedException(
        '403 Forbidden: Only a Shop Owner can $actionDescription. Non-owner role "${actorRole.displayName}" rejected.',
      );
    }
  }

  /// Validates staff account creation or permission assignment to prevent privilege escalation.
  ///
  /// Enforces Story 1.7 Acceptance Criteria:
  /// - Only Shop Owners can assign roles and configure permissions.
  /// - Non-owners cannot assign the Shop Owner role.
  /// - Non-owners cannot assign permissions they do not possess.
  /// - Staff cannot assign permissions outside the approved 14-permission catalog.
  static void validateStaffAssignment({
    required bool actorIsActive,
    required AppRole actorRole,
    required Set<AppPermission> actorEffectivePermissions,
    required AppRole targetRole,
    required Set<AppPermission> targetPermissions,
  }) {
    if (!actorIsActive) {
      throw const PrivilegeEscalationException(
        'Privilege escalation rejected: Inactive actor cannot assign roles or permissions.',
      );
    }

    // Only Shop Owner may create or reconfigure staff accounts
    if (!actorRole.isOwner) {
      throw const PrivilegeEscalationException(
        'Privilege escalation rejected: Only Shop Owners can manage staff accounts or assign permissions.',
      );
    }

    // Target permissions must belong strictly to the 14-permission catalog
    for (final perm in targetPermissions) {
      if (!AppPermission.values.contains(perm)) {
        throw PrivilegeEscalationException(
          'Privilege escalation rejected: Permission "${perm.key}" is outside the approved 14-permission catalog.',
        );
      }
    }
  }
}

