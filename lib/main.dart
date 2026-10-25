import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/remote/postgres_executor.dart';
import 'package:credit_system/core/data/secure_storage.dart';
import 'package:credit_system/features/auth/data/daos/user_dao.dart';
import 'package:credit_system/features/auth/data/services/auth_service.dart';
import 'package:credit_system/features/auth/data/services/jwt_service.dart';
import 'package:credit_system/features/auth/data/services/password_hash_service.dart';
import 'package:credit_system/features/auth/presentation/login_screen.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/presentation/customer_search_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Credit System',
      theme: ThemeData(
        colorScheme: .fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const AuthWrapper(),
    );
  }
}

/// Authentication wrapper that shows the login screen until the user
/// is authenticated, then shows the main application.
///
/// On launch, attempts to restore a session from a cached JWT in secure
/// storage. If no valid cached session exists (or `JWT_SECRET` is not
/// available for local verification), shows the login screen.
///
/// The authenticated [AppUser] is supplied by [LoginScreen] after
/// successful server-side or offline authentication. No identity is
/// hardcoded — the shop ID, user ID, role, and permissions all come from
/// the cryptographically verified JWT (online) or the authoritative
/// local Drift record (offline).
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isAuthenticated = false;
  AppUser? _currentUser;
  bool _isOfflineOnly = false;
  bool _isInitializing = true;

  late final AppDatabase _appDatabase;
  late final UserDao _userDao;
  late final AuthService _authService;

  @override
  void initState() {
    super.initState();
    _appDatabase = AppDatabase();
    _userDao = UserDao(_appDatabase);
    _authService = AuthService(
      pg: PostgreSqlExecutor.offline(),
      jwt: JwtService('placeholder-offline-restore'),
      passwordHash: PasswordHashService(),
      secureStorage: FlutterSecureStorageService(),
    );
    _checkExistingAuth();
  }

  @override
  void dispose() {
    _appDatabase.close();
    super.dispose();
  }

  /// Checks for a cached session in secure storage and restores it if
  /// valid.
  ///
  /// Session restoration verifies the JWT signature locally (issuer,
  /// audience, expiration) using `JwtService`. If `JWT_SECRET` is not
  /// available at build time, local JWT verification is not possible and
  /// the login screen is shown instead.
  ///
  /// If the JWT is valid, looks up the user in local Drift `app_users`
  /// and checks `is_active` and `session_version` match. Offline sessions
  /// are marked as offline-only and must be re-validated against
  /// PostgreSQL before any server-bound operation.
  Future<void> _checkExistingAuth() async {
    bool hasCachedToken = false;
    try {
      hasCachedToken = await _authService.hasCachedToken();
    } catch (_) {
      // SecureStorage may not be available on all platforms.
    }

    if (!hasCachedToken || !mounted) {
      setState(() {
        _isAuthenticated = false;
        _isInitializing = false;
      });
      return;
    }

    final String? token = await _authService.readCachedToken();
    if (token == null || token.isEmpty || !mounted) {
      setState(() {
        _isAuthenticated = false;
        _isInitializing = false;
      });
      return;
    }

    // Verify JWT signature locally (no PostgreSQL contact).
    Map<String, dynamic> claims;
    try {
      claims = _authService.verifyTokenLocally(token);
    } catch (_) {
      // Invalid JWT — clear cache and show login screen.
      await _authService.clearCachedSession();
      if (mounted) {
        setState(() {
          _isAuthenticated = false;
          _isInitializing = false;
        });
      }
      return;
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
      await _authService.clearCachedSession();
      if (mounted) {
        setState(() {
          _isAuthenticated = false;
          _isInitializing = false;
        });
      }
      return;
    }

    // Look up the user in local Drift app_users to check is_active and
    // session_version. Enforce tenant boundary: the local record must
    // belong to the shop embedded in the JWT.
    AppUser? localUser;
    try {
      localUser = await _userDao.getUserById(userId);
      if (localUser != null && localUser.shopId != shopId) {
        localUser = null;
      }
    } catch (_) {
      // Local Drift query failed — cannot restore session offline.
      await _authService.clearCachedSession();
      if (mounted) {
        setState(() {
          _isAuthenticated = false;
          _isInitializing = false;
        });
      }
      return;
    }

    if (localUser == null || !mounted) {
      await _authService.clearCachedSession();
      setState(() {
        _isAuthenticated = false;
        _isInitializing = false;
      });
      return;
    }
    final user = localUser; // Safe: null checked above

    if (!user.isActive) {
      await _authService.clearCachedSession();
      setState(() {
        _isAuthenticated = false;
        _isInitializing = false;
      });
      return;
    }

    if (user.sessionVersion != tokenSessionVersion) {
      await _authService.clearCachedSession();
      setState(() {
        _isAuthenticated = false;
        _isInitializing = false;
      });
      return;
    }

    // Session restored successfully from cache.
    setState(() {
      _isAuthenticated = true;
      _currentUser = user;
      _isOfflineOnly = true;
      _isInitializing = false;
    });
  }

  /// Called by [LoginScreen] after successful authentication.
  ///
  /// Stores the authenticated [AppUser] (with trusted shop ID, role, and
  /// session version from the database record) and transitions to the main
  /// application. No identity is hardcoded.
  void _onAuthenticated(AppUser user, bool isOfflineOnly) {
    setState(() {
      _isAuthenticated = true;
      _currentUser = user;
      _isOfflineOnly = isOfflineOnly;
      _isInitializing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_isAuthenticated || _currentUser == null) {
      return LoginScreen(onAuthenticated: _onAuthenticated);
    }

    return MainApp(
      shopId: _currentUser!.shopId,
      currentUser: _currentUser!,
      isOfflineOnly: _isOfflineOnly,
    );
  }

  /// Returns the currently authenticated user.
  ///
  /// The role, shop ID, and permissions are all derived from the
  /// authenticated session — never hardcoded.
  AppUser get currentUser {
    if (_currentUser == null) {
      throw StateError(
        'No authenticated user. Call _onAuthenticated first.',
      );
    }
    return _currentUser!;
  }

  /// Returns whether the current session was established offline only.
  ///
  /// Offline sessions must be re-validated against PostgreSQL before any
  /// server-bound operation.
  bool get isOfflineOnly => _isOfflineOnly;
}

/// Main application shell shown after authentication.
class MainApp extends StatelessWidget {
  final String shopId;
  final AppUser currentUser;
  final bool isOfflineOnly;

  const MainApp({
    super.key,
    required this.shopId,
    required this.currentUser,
    this.isOfflineOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Credit System',
      theme: ThemeData(
        colorScheme: .fromSeed(seedColor: Colors.deepPurple),
      ),
      home: CustomerSearchScreen(shopId: shopId, currentUser: currentUser),
    );
  }
}
