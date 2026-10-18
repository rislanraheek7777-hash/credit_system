import 'package:meta/meta.dart';
import '../../../../core/permissions/app_permission.dart';

/// Validation exception thrown when user domain invariants are violated.
class AppUserValidationException implements Exception {
  final String message;
  const AppUserValidationException(this.message);

  @override
  String toString() => 'AppUserValidationException: $message';
}

/// Clean architecture domain entity representing a counter staff or shop owner user (Story 1.7).
@immutable
class AppUser {
  /// Canonical UUID primary key.
  final String id;

  /// Associated shop tenant UUID boundary.
  final String shopId;

  /// Unique username within this shop tenant boundary.
  final String username;

  /// Full display name of the staff member.
  final String fullName;

  /// Assigned system role.
  final AppRole role;

  /// Account active state. Deactivated users cannot authenticate or act.
  final bool isActive;

  /// Monotonically increasing session version (starts at 1).
  ///
  /// Incremented upon password change, permission modification, or deactivation
  /// to invalidate in-flight JWT tokens / active sessions.
  final int sessionVersion;

  /// Optional custom permission overrides for [AppRole.custom].
  final Set<AppPermission>? customPermissions;

  /// UTC creation timestamp.
  final DateTime createdAt;

  /// UTC last-update timestamp.
  final DateTime updatedAt;

  AppUser({
    required this.id,
    required this.shopId,
    required this.username,
    required this.fullName,
    required this.role,
    this.isActive = true,
    this.sessionVersion = 1,
    this.customPermissions,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc() {
    _validate();
  }

  /// Validates domain entity invariants.
  void _validate() {
    if (id.trim().isEmpty) {
      throw const AppUserValidationException('User ID cannot be empty');
    }
    if (shopId.trim().isEmpty) {
      throw const AppUserValidationException('Shop ID cannot be empty');
    }
    if (username.trim().isEmpty) {
      throw const AppUserValidationException('Username cannot be empty');
    }
    if (username.length > 100) {
      throw const AppUserValidationException('Username cannot exceed 100 characters');
    }
    if (fullName.trim().isEmpty) {
      throw const AppUserValidationException('Full name cannot be empty');
    }
    if (fullName.length > 255) {
      throw const AppUserValidationException('Full name cannot exceed 255 characters');
    }
    if (sessionVersion < 1) {
      throw const AppUserValidationException('Session version must be >= 1');
    }
  }

  /// Evaluates effective permissions for this user.
  ///
  /// - For [AppRole.custom], returns the explicitly configured [customPermissions].
  /// - For built-in roles ([AppRole.shopOwner], [AppRole.manager], [AppRole.cashier]),
  ///   returns the approved role template.
  Set<AppPermission> get effectivePermissions {
    if (role == AppRole.custom) {
      return customPermissions ?? const <AppPermission>{};
    }
    return RolePermissionTemplates.defaultPermissionsForRole(role);
  }

  /// Deny-by-default permission check.
  bool hasPermission(AppPermission permission) {
    if (!isActive) return false;
    return effectivePermissions.contains(permission);
  }

  /// Checks whether an in-flight session version matches the user's active version.
  ///
  /// Enforces FR-5 / Story 1.7 session revocation validation contract:
  /// Any active token whose embedded session version is less than [sessionVersion],
  /// or when [isActive] is false, is invalid.
  bool isSessionValid(int tokenSessionVersion) {
    if (!isActive) return false;
    return tokenSessionVersion == sessionVersion;
  }

  /// Serializes permissions to a comma-separated string for local SQLite storage.
  String? serializePermissions() {
    if (role != AppRole.custom || customPermissions == null) {
      return null;
    }
    return customPermissions!.map((p) => p.key).join(',');
  }

  /// Deserializes a comma-separated string from local SQLite into a set of [AppPermission].
  static Set<AppPermission>? parsePermissions(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final perms = <AppPermission>{};
    for (final item in raw.split(',')) {
      final trimmed = item.trim();
      if (trimmed.isNotEmpty) {
        final perm = AppPermission.tryFromKey(trimmed);
        if (perm != null) {
          perms.add(perm);
        }
      }
    }
    return perms;
  }

  /// Returns a copy of this [AppUser] with the specified fields replaced.
  AppUser copyWith({
    String? id,
    String? shopId,
    String? username,
    String? fullName,
    AppRole? role,
    bool? isActive,
    int? sessionVersion,
    Set<AppPermission>? customPermissions,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AppUser(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      sessionVersion: sessionVersion ?? this.sessionVersion,
      customPermissions: customPermissions ?? this.customPermissions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppUser &&
        other.id == id &&
        other.shopId == shopId &&
        other.username == username &&
        other.fullName == fullName &&
        other.role == role &&
        other.isActive == isActive &&
        other.sessionVersion == sessionVersion;
  }

  @override
  int get hashCode => Object.hash(
        id,
        shopId,
        username,
        fullName,
        role,
        isActive,
        sessionVersion,
      );
}
