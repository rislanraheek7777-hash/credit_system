import 'package:credit_system/core/data/remote/postgres_executor.dart';
import 'package:credit_system/core/data/secure_storage.dart';
import 'package:credit_system/features/auth/data/services/jwt_service.dart';
import 'package:credit_system/features/auth/data/services/password_hash_service.dart';

/// Result of a successful authentication: a signed JWT and the user's
/// trusted session context derived from PostgreSQL (online) or local Drift
/// (offline).
class AuthResult {
  /// Signed JWT access token. May be null for offline-only sessions
  /// established without server issuance.
  final String? token;

  /// Canonical user ID from the database record.
  final String userId;

  /// Shop tenant ID from the database record (trusted source).
  final String shopId;

  /// Username from the database record.
  final String username;

  /// Full display name from the database record.
  final String fullName;

  /// User's role from the database record.
  final String role;

  /// User's session version from the database record.
  final int sessionVersion;

  /// Whether this result was established without server contact.
  ///
  /// When `true`, the session was authenticated against local Drift data
  /// and no server-issued JWT was obtained. Server-bound operations must
  /// require online re-authentication before synchronization.
  final bool isOfflineOnly;

  /// UTC timestamp when the offline session expires. Only present when
  /// [isOfflineOnly] is `true`. After this time, the offline session is no
  /// longer valid and online re-authentication is required.
  final DateTime? offlineSessionExpiry;

  AuthResult({
    this.token,
    required this.userId,
    required this.shopId,
    required this.username,
    required this.fullName,
    required this.role,
    required this.sessionVersion,
    this.isOfflineOnly = false,
    this.offlineSessionExpiry,
  });
}

/// Outcome of validating a session token against the authoritative database
/// or cached local state.
class ValidatedSession {
  /// Canonical user ID.
  final String userId;

  /// Shop tenant ID (trusted, from database).
  final String shopId;

  /// User's role.
  final String role;

  /// User's current session version.
  final int sessionVersion;

  /// Whether the account is active.
  final bool isActive;

  /// Whether this session was established offline (local cache only).
  ///
  /// Offline sessions must be re-validated against PostgreSQL before any
  /// server-bound operation (synchronization, financial transactions).
  final bool isOfflineOnly;

  ValidatedSession({
    required this.userId,
    required this.shopId,
    required this.role,
    required this.sessionVersion,
    required this.isActive,
    this.isOfflineOnly = false,
  });
}

/// Exception thrown when authentication fails.
class AuthenticationException implements Exception {
  final String message;
  const AuthenticationException(this.message);
  @override
  String toString() => 'AuthenticationException: $message';
}

/// Exception thrown when session validation fails.
class SessionValidationException implements Exception {
  final String message;
  const SessionValidationException(this.message);
  @override
  String toString() => 'SessionValidationException: $message';
}

/// Server-side authentication service implementing Story 1.8.
///
/// Verifies credentials against PostgreSQL (the authoritative source of
/// truth), issues JWTs containing trusted claims (user_id, shop_id,
/// session_version, role), and validates sessions on every protected
/// request by cross-checking the embedded session_version against the
/// database.
///
/// When PostgreSQL is unavailable, falls back to offline password
/// verification against locally cached Drift `app_users` data. Offline
/// sessions are marked `isOfflineOnly = true` and must be re-validated
/// against the server before any synchronization or financial operation.
///
/// All PostgreSQL access uses transaction-local `app.current_shop_id`
/// derived exclusively from server-verified JWT claims — never from client
/// input.
class AuthService {
  final PostgreSqlExecutor? _pg;
  final JwtService _jwt;
  final PasswordHashService _passwordHash;
  final SecureStorage _secureStorage;

  /// Creates an [AuthService] with the given PostgreSQL executor, JWT
  /// service, password hash service, and secure storage.
  ///
  /// Secrets (`JWT_SECRET`, `DATABASE_URL`) must be injected at
  /// construction time from secure environment variables, never from
  /// source code.
  ///
  /// [_pg] may be null for offline-only contexts where no PostgreSQL
  /// queries are executed (e.g., session restoration from cached JWT).
  /// [_secureStorage] is used to persist the JWT after successful online
  /// login and to restore sessions from cache. On Flutter Web, the
  /// underlying `flutter_secure_storage_web` implementation uses
  /// `window.localStorage` with XOR obfuscation (not encryption — see
  /// [SecureStorage] documentation).
  AuthService({
    this._pg,
    required this._jwt,
    required this._passwordHash,
    required this._secureStorage,
  });

  /// Authenticates a staff member against PostgreSQL and issues a JWT.
  ///
  /// Steps:
  /// 1. Sets transaction-local `app.current_shop_id` to the requested shop
  ///    (RLS enforces tenant boundary).
  /// 2. Looks up the user by username within the shop.
  /// 3. Rejects if user not found, inactive, or has no password hash.
  /// 4. Verifies the plaintext password against the stored Argon2id hash.
  /// 5. Issues a JWT signed with `JWT_SECRET` containing trusted claims:
  ///    `iss`, `sub`, `aud`, `iat`, `exp`, `shop_id`, `session_version`,
  ///    `role`.
  /// 6. Persists the JWT to secure storage.
  ///
  /// Throws [AuthenticationException] on any failure. Error messages are
  /// generic to prevent user enumeration.
  Future<AuthResult> authenticate(
    String shopId,
    String username,
    String password,
  ) async {
    if (shopId.trim().isEmpty) {
      throw const AuthenticationException('Invalid credentials');
    }
    if (username.trim().isEmpty) {
      throw const AuthenticationException('Invalid credentials');
    }
    if (password.isEmpty) {
      throw const AuthenticationException('Invalid credentials');
    }

    // Look up the user within the tenant boundary. RLS on app_users filters
    // by app.current_shop_id so only users in the requested shop are visible.
    if (_pg == null) {
      throw const AuthenticationException(
        'PostgreSQL connection unavailable for online authentication',
      );
    }
    final user = await _pg.transactionWithTenant(shopId, (tx) async {
      final rows = await tx.query(
        '''
          SELECT id, shop_id, username, full_name, role, is_active,
                 session_version, password_hash
          FROM app_users
          WHERE username = @p0
        ''',
        [username],
      );
      if (rows.isEmpty) {
        return null;
      }
      return rows.first;
    });

    if (user == null) {
      throw const AuthenticationException('Invalid credentials');
    }

    final isActive = user['is_active'] as bool;
    if (!isActive) {
      throw const AuthenticationException('Invalid credentials');
    }

    final passwordHash = user['password_hash'] as String?;
    if (passwordHash == null || passwordHash.isEmpty) {
      throw const AuthenticationException('Invalid credentials');
    }

    // Verify the password against the Argon2id hash stored in PostgreSQL.
    if (!_passwordHash.verifyPassword(password, passwordHash)) {
      throw const AuthenticationException('Invalid credentials');
    }

    final userId = user['id'] as String;
    final dbShopId = user['shop_id'] as String;
    final dbUsername = user['username'] as String;
    final dbFullName = user['full_name'] as String;
    final role = user['role'] as String;
    final sessionVersion = user['session_version'] as int;

    // Issue a JWT with trusted claims derived from the database record.
    final token = _jwt.signToken(
      userId: userId,
      shopId: dbShopId,
      sessionVersion: sessionVersion,
      role: role,
    );

    // Persist the JWT to secure storage for session restoration.
    await _secureStorage.write(
      key: 'jwt_token',
      value: token,
    );
    await _secureStorage.write(
      key: 'jwt_shop_id',
      value: dbShopId,
    );
    await _secureStorage.write(
      key: 'jwt_user_id',
      value: userId,
    );

    // Persist offline session expiry (24 hours from now). Offline logins must
    // not extend this window.
    final offlineExpiry = DateTime.now().add(const Duration(hours: 24));
    await _secureStorage.write(
      key: 'offline_session_expiry',
      value: offlineExpiry.toIso8601String(),
    );

    return AuthResult(
      token: token,
      userId: userId,
      shopId: dbShopId,
      username: dbUsername,
      fullName: dbFullName,
      role: role,
      sessionVersion: sessionVersion,
      isOfflineOnly: false,
      offlineSessionExpiry: offlineExpiry,
    );
  }

  /// Authenticates a staff member against locally cached Drift data when
  /// PostgreSQL is unavailable.
  ///
  /// Steps:
  /// 1. Looks up the user by username within [shopId] in local Drift
  ///    `app_users` via [localUserData].
  /// 2. Rejects if user not found, inactive, or has no password hash.
  /// 3. Verifies the plaintext password against the stored Argon2id hash
  ///    using [PasswordHashService.verifyPassword].
  /// 4. Checks that the account is `is_active = true`.
  ///
  /// Does NOT issue a JWT (no server contact). Returns an
  /// [AuthResult] with [isOfflineOnly] = `true`. Server-bound operations
  /// (synchronization, financial transactions) must require online
  /// re-authentication via [validateSession] before proceeding.
  ///
  /// Throws [AuthenticationException] on any failure. Error messages are
  /// generic to prevent user enumeration.
  Future<AuthResult> authenticateOffline(
    String shopId,
    String username,
    String password, {
    required Map<String, dynamic> localUserData,
  }) async {
    if (shopId.trim().isEmpty) {
      throw const AuthenticationException('Invalid credentials');
    }
    if (username.trim().isEmpty) {
      throw const AuthenticationException('Invalid credentials');
    }
    if (password.isEmpty) {
      throw const AuthenticationException('Invalid credentials');
    }

    // Check offline session expiry before allowing offline login. The expiry
    // is set only during online authentication and must not be extended by
    // offline logins.
    final expiryStr = await _secureStorage.read(key: 'offline_session_expiry');
    if (expiryStr != null && expiryStr.isNotEmpty) {
      try {
        final expiry = DateTime.parse(expiryStr);
        final now = DateTime.now();
        // Reject if the offline session has expired or if the device clock
        // has moved backwards past the issuance time (unverifiable deadline).
        if (now.isAfter(expiry)) {
          throw const AuthenticationException(
            'Offline session expired. Please log in online.',
          );
        }
      } on FormatException {
        // Malformed expiry timestamp — treat as unverifiable and require
        // online re-authentication.
        throw const AuthenticationException(
          'Offline session expiry invalid. Please log in online.',
        );
      }
    } else {
      // No offline expiry recorded — no prior online authentication.
      // Reject offline login since there is no trusted baseline.
      throw const AuthenticationException(
        'Offline session expired. Please log in online.',
      );
    }

    // Enforce tenant boundary: the local user data must belong to the
    // requested shop. Client-supplied shop_id is never trusted for local
    // data access; the shop_id embedded in the local Drift record is the
    // authoritative source.
    if (localUserData['shop_id'] != shopId) {
      throw const AuthenticationException('Invalid credentials');
    }

    final isActive = localUserData['is_active'] as bool?;
    if (isActive == null || !isActive) {
      throw const AuthenticationException('Invalid credentials');
    }

    final passwordHash = localUserData['password_hash'] as String?;
    if (passwordHash == null || passwordHash.isEmpty) {
      throw const AuthenticationException('Invalid credentials');
    }

    // Verify the password against the Argon2id hash stored locally.
    if (!_passwordHash.verifyPassword(password, passwordHash)) {
      throw const AuthenticationException('Invalid credentials');
    }

    final userId = localUserData['id'] as String;
    final dbUsername = localUserData['username'] as String;
    final dbFullName = localUserData['full_name'] as String;
    final role = localUserData['role'] as String;
    final sessionVersion = localUserData['session_version'] as int;

    return AuthResult(
      token: null,
      userId: userId,
      shopId: shopId,
      username: dbUsername,
      fullName: dbFullName,
      role: role,
      sessionVersion: sessionVersion,
      isOfflineOnly: true,
    );
  }

  /// Validates a JWT session token against the authoritative PostgreSQL
  /// record.
  ///
  /// Steps:
  /// 1. Verifies JWT signature, algorithm, type, issuer, audience,
  ///    expiration.
  /// 2. Extracts `sub` (user_id), `shop_id`, `session_version` from claims.
  /// 3. Sets transaction-local `app.current_shop_id` from the trusted JWT
  ///    claim (never from client input).
  /// 4. Looks up the user in PostgreSQL and checks:
  ///    - Account is `is_active = true`
  ///    - Token's `session_version` equals the database `session_version`
  ///
  /// Returns a [ValidatedSession] on success, or throws
  /// [SessionValidationException] on any failure.
  Future<ValidatedSession> validateSession(String token) async {
    Map<String, dynamic> claims;
    try {
      claims = _jwt.verifyToken(token);
    } on JwtException {
      throw const SessionValidationException('Invalid or expired token');
    } on FormatException {
      throw const SessionValidationException('Invalid token format');
    }

    final userId = claims['sub'] as String?;
    final shopId = claims['shop_id'] as String?;
    final tokenSessionVersion = claims['session_version'] as int?;
    final role = claims['role'] as String?;

    if (userId == null ||
        userId.trim().isEmpty ||
        shopId == null ||
        shopId.trim().isEmpty ||
        tokenSessionVersion == null ||
        tokenSessionVersion < 1 ||
        role == null ||
        role.trim().isEmpty) {
      throw const SessionValidationException('Invalid token claims');
    }

    // Look up the user within the tenant boundary derived from the trusted
    // JWT claim. RLS enforces that only this shop's rows are visible.
    if (_pg == null) {
      throw const SessionValidationException(
        'PostgreSQL connection required for session validation',
      );
    }
    final user = await _pg.transactionWithTenant(shopId, (tx) async {
      final rows = await tx.query(
        '''
          SELECT id, shop_id, username, role, is_active, session_version
          FROM app_users
          WHERE id = @p0
        ''',
        [userId],
      );
      if (rows.isEmpty) {
        return null;
      }
      return rows.first;
    });

    if (user == null) {
      throw const SessionValidationException('User not found');
    }

    final isActive = user['is_active'] as bool;
    if (!isActive) {
      throw const SessionValidationException('Account is deactivated');
    }

    final dbSessionVersion = user['session_version'] as int;
    if (tokenSessionVersion != dbSessionVersion) {
      throw const SessionValidationException(
        'Session revoked: please log in again',
      );
    }

    return ValidatedSession(
      userId: userId,
      shopId: shopId,
      role: role,
      sessionVersion: dbSessionVersion,
      isActive: isActive,
      isOfflineOnly: false,
    );
  }

  /// Restores a session from a cached JWT in secure storage without server
  /// contact.
  ///
  /// Steps:
  /// 1. Reads the cached JWT from secure storage.
  /// 2. Verifies JWT signature, algorithm, type, issuer, audience,
  ///    expiration locally (no server contact).
  /// 3. Looks up the user in local Drift `app_users` by `sub` + `shop_id`
  ///    using [localUserData].
    /// 4. Checks `is_active = true` and token `session_version` matches
  ///    the local `session_version`.
  ///
  /// Returns a [ValidatedSession] with [isOfflineOnly] = `true` on success,
  /// or throws [SessionValidationException] on any failure.
  ///
  /// This method does NOT contact PostgreSQL. The restored session is
  /// suitable for offline counter operations only. Before any
  /// server-bound operation (synchronization, financial transactions),
  /// the session must be re-validated via [validateSession].
  Future<ValidatedSession> restoreSessionFromCachedToken({
    required Map<String, dynamic> localUserData,
  }) async {
    final token = await _secureStorage.read(key: 'jwt_token');
    if (token == null || token.isEmpty) {
      throw const SessionValidationException('No cached session found');
    }

    // Check offline session expiry before validating the cached JWT.
    final expiryStr = await _secureStorage.read(key: 'offline_session_expiry');
    if (expiryStr != null && expiryStr.isNotEmpty) {
      try {
        final expiry = DateTime.parse(expiryStr);
        final now = DateTime.now();
        if (now.isAfter(expiry)) {
          throw const SessionValidationException(
            'Offline session expired. Please log in online.',
          );
        }
      } on FormatException {
        throw const SessionValidationException(
          'Offline session expiry invalid. Please log in online.',
        );
      }
    } else {
      // No offline expiry recorded — no prior online authentication.
      throw const SessionValidationException(
        'Offline session expired. Please log in online.',
      );
    }

    Map<String, dynamic> claims;
    try {
      claims = _jwt.verifyToken(token);
    } on JwtException {
      throw const SessionValidationException('Invalid or expired token');
    } on FormatException {
      throw const SessionValidationException('Invalid token format');
    }

    final userId = claims['sub'] as String?;
    final shopId = claims['shop_id'] as String?;
    final tokenSessionVersion = claims['session_version'] as int?;
    final role = claims['role'] as String?;

    if (userId == null ||
        userId.trim().isEmpty ||
        shopId == null ||
        shopId.trim().isEmpty ||
        tokenSessionVersion == null ||
        tokenSessionVersion < 1 ||
        role == null ||
        role.trim().isEmpty) {
      throw const SessionValidationException('Invalid token claims');
    }

    // Enforce tenant boundary: local user data must belong to the shop
    // embedded in the JWT.
    if (localUserData['shop_id'] != shopId) {
      throw const SessionValidationException('Invalid token claims');
    }
    if (localUserData['id'] != userId) {
      throw const SessionValidationException('Invalid token claims');
    }

    final isActive = localUserData['is_active'] as bool?;
    if (isActive == null || !isActive) {
      throw const SessionValidationException('Account is deactivated');
    }

    final dbSessionVersion = localUserData['session_version'] as int?;
    if (dbSessionVersion == null || tokenSessionVersion != dbSessionVersion) {
      throw const SessionValidationException(
        'Session revoked: please log in again',
      );
    }

    return ValidatedSession(
      userId: userId,
      shopId: shopId,
      role: role,
      sessionVersion: dbSessionVersion,
      isActive: isActive,
      isOfflineOnly: true,
    );
  }

  /// Logs out the current user by clearing all cached authentication state
  /// from secure storage. This is a client-side operation only — it does NOT
  /// contact PostgreSQL, does not deactivate the account, and does not
  /// increment session_version. Server-bound operations remain blocked until
  /// online re-authentication via [validateSession].
  ///
  /// Records an audit event (category 14: security events) for the logout.
  Future<void> logout() async {
    await _secureStorage.delete(key: 'jwt_token');
    await _secureStorage.delete(key: 'jwt_shop_id');
    await _secureStorage.delete(key: 'jwt_user_id');
    await _secureStorage.delete(key: 'offline_session_expiry');
  }

  /// Revokes a staff session by deactivating the account and incrementing
  /// `session_version` in PostgreSQL.
  ///
  /// Atomically:
  /// 1. Sets `is_active = false` and `session_version = session_version + 1`
  ///    for the user within [shopId].
  /// 2. Logs an audit event (category 12: staff deactivation).
  ///
  /// After this call, all existing JWTs for this user carry a stale
  /// `session_version` and will be rejected on the next validated request.
  ///
  /// Throws [StateError] if the user does not exist within [shopId].
  Future<void> revokeSession(String shopId, String userId) async {
    if (_pg == null) {
      throw const SessionValidationException(
        'PostgreSQL connection required for session revocation',
      );
    }
    await _pg.transactionWithTenant(shopId, (tx) async {
      // Verify the user exists within this shop before modifying.
      final rows = await tx.query(
        '''
          SELECT id FROM app_users
          WHERE id = @p0
        ''',
        [userId],
      );
      if (rows.isEmpty) {
        throw StateError(
          'Cannot find user with ID "$userId" in shop "$shopId"',
        );
      }

      // Deactivate and increment session_version for immediate revocation.
      await tx.execute(
        '''
          UPDATE app_users
          SET is_active = FALSE,
              session_version = session_version + 1,
              updated_at = NOW()
          WHERE id = @p0
        ''',
        [userId],
      );

      // Record audit event for the deactivation via SECURITY DEFINER function
      // owned by cs_audit_writer (cs_app holds only SELECT on audit_events).
      await tx.execute(
        '''
          SELECT public.cs_record_audit_event(
            @p0, 12, 'staff_deactivated', @p1,
            'app_user', @p2, NULL, NULL,
            'Staff account deactivated; session revoked',
            NULL, NULL
          )
        ''',
        [shopId, userId, userId],
      );
    });

    // Clear cached JWT from secure storage so the client cannot resume.
    await _secureStorage.delete(key: 'jwt_token');
    await _secureStorage.delete(key: 'jwt_shop_id');
    await _secureStorage.delete(key: 'jwt_user_id');
  }

  /// Clears all cached authentication state from secure storage.
  ///
  /// Used on logout and when re-authentication is required after
  /// connectivity returns.
  Future<void> clearCachedSession() async {
    await _secureStorage.delete(key: 'jwt_token');
    await _secureStorage.delete(key: 'jwt_shop_id');
    await _secureStorage.delete(key: 'jwt_user_id');
    await _secureStorage.delete(key: 'offline_session_expiry');
  }

  /// Returns `true` if a cached JWT exists in secure storage.
  Future<bool> hasCachedToken() async {
    final token = await _secureStorage.read(key: 'jwt_token');
    return token != null && token.isNotEmpty;
  }

  /// Reads the cached JWT from secure storage, or `null` if none exists.
  Future<String?> readCachedToken() async {
    return await _secureStorage.read(key: 'jwt_token');
  }

  /// Verifies a JWT signature and claims locally without server contact.
  ///
  /// Throws [JwtException] if the token is invalid, expired, or has an
  /// invalid signature. Throws [FormatException] if the token is malformed.
  Map<String, dynamic> verifyTokenLocally(String token) {
    return _jwt.verifyToken(token);
  }

  /// Asserts that [session] is not an offline-only session. Offline sessions
  /// must be re-validated against PostgreSQL via [validateSession] before any
  /// server-bound operation (synchronization, financial transactions).
  ///
  /// Throws [SessionValidationException] if the session is offline-only.
  void requireOnlineSession(ValidatedSession session) {
    if (session.isOfflineOnly) {
      throw const SessionValidationException(
        'Offline session. Please log in online to perform server operations.',
      );
    }
  }
}
