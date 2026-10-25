import 'package:drift/drift.dart';
import '../../../../core/data/local/app_database.dart';
import '../../../../core/data/local/tables/app_users_table.dart';
import '../../../../core/permissions/app_permission.dart';
import '../services/password_hash_service.dart';
import '../../domain/models/app_user.dart';

part 'user_dao.g.dart';

/// Data Access Object for Counter Staff and User administration (Story 1.7).
@DriftAccessor(tables: [AppUsers])
class UserDao extends DatabaseAccessor<AppDatabase> with _$UserDaoMixin {
  UserDao(super.db);

  final PasswordHashService _passwordHashService = PasswordHashService();

  /// Converts a Drift [AppUserEntry] row into a domain [AppUser].
  AppUser _toDomain(AppUserEntry entry) {
    return AppUser(
      id: entry.id,
      shopId: entry.shopId,
      username: entry.username,
      fullName: entry.fullName,
      role: AppRole.fromKey(entry.role),
      isActive: entry.isActive,
      sessionVersion: entry.sessionVersion,
      customPermissions: AppUser.parsePermissions(entry.permissions),
      passwordHash: entry.passwordHash,
      createdAt: entry.createdAt,
      updatedAt: entry.updatedAt,
    );
  }

  /// Converts a domain [AppUser] into a Drift [AppUsersCompanion] for insert or update.
  AppUsersCompanion _toCompanion(AppUser user) {
    return AppUsersCompanion(
      id: Value(user.id),
      shopId: Value(user.shopId),
      username: Value(user.username),
      fullName: Value(user.fullName),
      role: Value(user.role.key),
      isActive: Value(user.isActive),
      sessionVersion: Value(user.sessionVersion),
      permissions: Value(user.serializePermissions()),
      passwordHash: Value(user.passwordHash),
      createdAt: Value(user.createdAt),
      updatedAt: Value(user.updatedAt),
    );
  }

  /// Retrieves a user by their unique [userId], returning null if not found.
  Future<AppUser?> getUserById(String userId) async {
    final query = select(appUsers)..where((u) => u.id.equals(userId));
    final entry = await query.getSingleOrNull();
    return entry != null ? _toDomain(entry) : null;
  }

  /// Retrieves a user by their tenant [shopId] and [username], returning null if not found.
  Future<AppUser?> getUserByUsername(String shopId, String username) async {
    final query = select(appUsers)
      ..where((u) => u.shopId.equals(shopId) & u.username.equals(username));
    final entry = await query.getSingleOrNull();
    return entry != null ? _toDomain(entry) : null;
  }

  /// Retrieves all users belonging strictly to the specified [shopId].
  ///
  /// Enforces tenant boundary isolation (Story 1.7 Acceptance Criteria):
  /// Only staff accounts belonging strictly to the requested `shopId` are returned.
  Future<List<AppUser>> getUsersByShopId(String shopId) async {
    final query = select(appUsers)..where((u) => u.shopId.equals(shopId));
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Inserts a new user account into the local database.
  Future<void> createUser(AppUser user) async {
    await into(appUsers).insert(_toCompanion(user));
  }

  /// Inserts a new user account with a hashed password into the local database.
  ///
  /// Hashes [plaintextPassword] using Argon2id via [PasswordHashService] before
  /// persistence. Only the encoded password hash is stored; the plaintext
  /// password is never persisted.
  ///
  /// Rejects empty or invalid passwords via [PasswordHashService.hashPassword].
  /// Enforces shop-scoped username uniqueness via the database unique constraint
  /// on {shopId, username}.
  Future<void> createUserWithPassword(
    AppUser user,
    String plaintextPassword,
  ) async {
    final passwordHash = _passwordHashService.hashPassword(plaintextPassword);
    final userWithHash = user.copyWith(passwordHash: passwordHash);
    await into(appUsers).insert(_toCompanion(userWithHash));
  }

  /// Updates a user's role and granular permissions within a specific [shopId].
  ///
  /// IMPORTANT ARCHITECTURE & INTEGRATION NOTICE:
  /// Monotonically incrementing [sessionVersion] provides the local persistence and
  /// domain contract for immediate session revocation (PRD FR-5). Runtime enforcement
  /// across active user sessions is pending implementation of the authentication/session
  /// middleware and JWT interceptor layer in upcoming stories.
  ///
  /// Enforces shop boundary isolation: throws [StateError] if the user does not exist
  /// within [shopId], preventing cross-shop tampering.
  Future<void> updateUserPermissions(
    String shopId,
    String userId, {
    required AppRole role,
    Set<AppPermission>? customPermissions,
  }) async {
    final query = select(appUsers)
      ..where((u) => u.shopId.equals(shopId) & u.id.equals(userId));
    final existing = await query.getSingleOrNull();
    if (existing == null) {
      throw StateError('Cannot find user with ID "$userId" in shop "$shopId"');
    }

    final newPermissions = role == AppRole.custom ? customPermissions : null;
    final serialized = newPermissions?.map((p) => p.key).join(',');

    await (update(appUsers)
          ..where((u) => u.shopId.equals(shopId) & u.id.equals(userId)))
        .write(
      AppUsersCompanion(
        role: Value(role.key),
        permissions: Value(serialized),
        sessionVersion: Value(existing.sessionVersion + 1),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// Updates a user's password hash within a specific [shopId].
  ///
  /// Increments [sessionVersion] by 1 to immediately revoke all existing sessions
  /// (PRD FR-5 / Story 1.7 session revocation contract). Enforces shop boundary
  /// isolation: throws [StateError] if the user does not exist within [shopId],
  /// preventing cross-shop tampering.
  Future<void> updateUserPassword(
    String shopId,
    String userId, {
    required String passwordHash,
  }) async {
    final query = select(appUsers)
      ..where((u) => u.shopId.equals(shopId) & u.id.equals(userId));
    final existing = await query.getSingleOrNull();
    if (existing == null) {
      throw StateError('Cannot find user with ID "$userId" in shop "$shopId"');
    }

    await (update(appUsers)
          ..where((u) => u.shopId.equals(shopId) & u.id.equals(userId)))
        .write(
      AppUsersCompanion(
        passwordHash: Value(passwordHash),
        sessionVersion: Value(existing.sessionVersion + 1),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// Deactivates a staff account within a specific [shopId].
  ///
  /// Sets [isActive] to `false` and increments [sessionVersion] by 1.
  /// Enforces shop boundary isolation: throws [StateError] if the user does not exist
  /// within [shopId], preventing cross-shop tampering.
  Future<void> deactivateUser(String shopId, String userId) async {
    final query = select(appUsers)
      ..where((u) => u.shopId.equals(shopId) & u.id.equals(userId));
    final existing = await query.getSingleOrNull();
    if (existing == null) {
      throw StateError('Cannot find user with ID "$userId" in shop "$shopId"');
    }

    await (update(appUsers)
          ..where((u) => u.shopId.equals(shopId) & u.id.equals(userId)))
        .write(
      AppUsersCompanion(
        isActive: const Value(false),
        sessionVersion: Value(existing.sessionVersion + 1),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// Reactivates a staff account within a specific [shopId].
  ///
  /// Enforces shop boundary isolation: throws [StateError] if the user does not exist
  /// within [shopId], preventing cross-shop tampering.
  Future<void> reactivateUser(String shopId, String userId) async {
    final query = select(appUsers)
      ..where((u) => u.shopId.equals(shopId) & u.id.equals(userId));
    final existing = await query.getSingleOrNull();
    if (existing == null) {
      throw StateError('Cannot find user with ID "$userId" in shop "$shopId"');
    }

    await (update(appUsers)
          ..where((u) => u.shopId.equals(shopId) & u.id.equals(userId)))
        .write(
      AppUsersCompanion(
        isActive: const Value(true),
        sessionVersion: Value(existing.sessionVersion + 1),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }
}
