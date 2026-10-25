import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/data/services/auth_service.dart';

/// Exception thrown when a protected operation is rejected due to missing
/// permissions, inactive account, or failed session validation.
class SessionGuardException implements Exception {
  final String message;
  final String? requiredPermission;

  const SessionGuardException(this.message, {this.requiredPermission});

  @override
  String toString() => 'SessionGuardException: $message';
}

/// Server-side session guard enforcing RBAC and session validity on every
/// protected request (Story 1.8).
///
/// Wraps [AuthService] to validate JWT sessions (signature, expiration,
/// issuer, audience, session_version, active status) and then enforce
/// deny-by-default role-based access control using the 14-permission catalog.
///
/// All shop membership validation is derived from trusted JWT claims —
/// never from client-supplied values.
class SessionGuard {
  final AuthService _authService;

  SessionGuard(this._authService);

  /// Validates the session token and asserts that the user holds the required
  /// [permission].
  ///
  /// Steps:
  /// 1. Validates the JWT session via [AuthService.validateSession] (checks
  ///    signature, exp, iss, aud, session_version, is_active).
  /// 2. Confirms the authenticated user's shop matches the requested [shopId]
  ///    (prevents cross-shop access using a valid token from another tenant).
  /// 3. Evaluates deny-by-default RBAC: the user's effective permissions
  ///    (derived from their role) must contain [permission].
  ///
  /// Returns the [ValidatedSession] on success.
  ///
  /// Throws [SessionGuardException] if:
  /// - The token is invalid, expired, or revoked (`401` equivalent)
  /// - The user's shop does not match [shopId] (`403` equivalent)
  /// - The user lacks the required permission (`403` equivalent)
  /// - The account is deactivated (`401` equivalent)
  Future<ValidatedSession> requirePermission(
    String token,
    AppPermission permission,
    String shopId,
  ) async {
    ValidatedSession session;
    try {
      session = await _authService.validateSession(token);
    } on SessionValidationException catch (e) {
      throw SessionGuardException(e.message);
    }

    // Trusted shop-membership validation: the shop embedded in the JWT must
    // match the shop context of the request. Client-supplied shop_id is never
    // trusted; only the JWT claim (derived from the database at login) is used.
    if (session.shopId != shopId) {
      throw SessionGuardException(
        'Access denied: shop mismatch. Token belongs to shop "${session.shopId}" '
        'but request targets shop "$shopId".',
      );
    }

    // Resolve effective permissions from the user's role.
    final effectivePermissions = _effectivePermissionsForRole(session.role);

    // Deny-by-default: inactive accounts cannot perform any action.
    if (!session.isActive) {
      throw const SessionGuardException(
        'Access denied: User account is deactivated.',
      );
    }

    if (!effectivePermissions.contains(permission)) {
      throw SessionGuardException(
        'Access denied: Lacking required permission "${permission.key}" '
        'to perform this action.',
        requiredPermission: permission.key,
      );
    }

    return session;
  }

  /// Validates the session token and asserts that the user holds the required
  /// [role].
  ///
  /// Used for Shop Owner–restricted administrative actions (staff management,
  /// permission changes, deactivation, shop profile changes, correction
  /// approvals, due-date extensions).
  Future<ValidatedSession> requireRole(
    String token,
    AppRole role, {
    String? shopId,
  }) async {
    ValidatedSession session;
    try {
      session = await _authService.validateSession(token);
    } on SessionValidationException catch (e) {
      throw SessionGuardException(e.message);
    }

    if (shopId != null && session.shopId != shopId) {
      throw SessionGuardException(
        'Access denied: shop mismatch. Token belongs to shop "${session.shopId}" '
        'but request targets shop "$shopId".',
      );
    }

    if (!session.isActive) {
      throw const SessionGuardException(
        'Access denied: User account is deactivated.',
      );
    }

    final actorRole = AppRole.fromKey(session.role);
    if (actorRole != role) {
      throw SessionGuardException(
        'Access denied: Only ${role.displayName} can perform this action. '
        'Actor role "${actorRole.displayName}" rejected.',
      );
    }

    return session;
  }

  /// Resolves the effective permission set for a given role key string.
  ///
  /// Delegates to [RolePermissionTemplates.defaultPermissionsForRole] as the
  /// single authoritative permission policy. For custom roles, returns an empty
  /// set (custom permissions are evaluated separately by the caller if needed).
  Set<AppPermission> _effectivePermissionsForRole(String roleKey) {
    try {
      final role = AppRole.fromKey(roleKey);
      return RolePermissionTemplates.defaultPermissionsForRole(role);
    } on ArgumentError {
      return const <AppPermission>{};
    }
  }
}
