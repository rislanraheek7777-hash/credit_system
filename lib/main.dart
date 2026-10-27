import 'package:flutter/material.dart';

import 'package:credit_system/features/auth/presentation/login_screen.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/presentation/customer_search_screen.dart';
import 'package:drift/drift.dart' hide Column;
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


/// Main application shell shown after authentication.
/// Uses a scaffold with a bottom navigation bar for switching between
/// dashboard and customers sections.
class MainApp extends StatefulWidget {
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
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  int _selectedIndex = 0;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashboardPage = _DashboardPage(
      shopId: widget.shopId,
      currentUser: widget.currentUser,
      isOfflineOnly: widget.isOfflineOnly,
    );

    final customersPage = _CustomersPage(
      shopId: widget.shopId,
      currentUser: widget.currentUser,
    );

    final List<Widget> pages = [
      dashboardPage,
      customersPage,
    ];

    return Scaffold(
      body: pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        elevation: 1,
        backgroundColor: Theme.of(context).colorScheme.surface,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
          (Set<WidgetState> states) => const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF1E293B),
          ),
        ),
        indicatorColor: const Color(0xFF3478F6),
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Customers',
          ),
        ],
      ),
    );
  }
}

/// Dashboard page shown when Dashboard is selected in the navigation bar.
class _DashboardPage extends StatelessWidget {
  final String shopId;
  final AppUser currentUser;
  final bool isOfflineOnly;

  const _DashboardPage({
    required this.shopId,
    required this.currentUser,
    required this.isOfflineOnly,
  });

  
        'Dashboard\nShop: $shopId\n 
        int _getTotalTransactions(AppDatabase db) {
      int getTotalTransactions(AppDatabase db) {
    

  /// Gets total number of customers for this shop.
  int getTotalCustomers(AppDatabase db) {
    final count = select(db.customers)..where((c) => c.shopId.equals(shopId)).getSingle();
    return count ?? 0;
  }

  /// Gets total number of active staff for this shop.
  int getTotalStaff(AppDatabase db) {
    final count = select(db.appUsers)..where((u) => u.shopId.equals(shopId) & u.isActive.equals(true)).getSingle();
    return count ?? 0;
  }

  /// Gets total income (full settlement payments) for this shop.
  int getTotalIncome(AppDatabase db) {
    final payments = select(db.payments)..where((p) => p.shopId.equals(shopId) & p.paymentType.equals('full_settlement')).get();
    int income = 0;
    for (final p in payments) {
      income += p.amountCents ?? 0;
    }
    return income;
  }

  /// Gets total outgoing (partial payments) for this shop.
  int getTotalOutgoing(AppDatabase db) {
    final payments = select(db.payments)..where((p) => p.shopId.equals(shopId) & p.paymentType.equals('partial')).get();
    int outgoing = 0;
    for (final p in payments) {
      outgoing += p.amountCents ?? 0;
    }
    return outgoing;
  }

  String formatCurrency(int cents) {
    final dollars = cents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final db = AppDatabase();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shop header info
          Text(
            'Dashboard',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Shop: $shopId',
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 24),

          // Metrics grid
          Row(
            children: [
              _MetricCard(
                icon: Icons.receipt,
                label: 'Total Transactions',
                value: getTotalTransactions(db).toString(),
                color: Color(0xFF3478F6),
              ),
              const SizedBox(width: 12),
              _MetricCard(
                icon: Icons.person_outline,
                label: 'Total Customers',
                value: getTotalCustomers(db).toString(),
                color: Color(0xFF10B981),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _MetricCard(
                icon: Icons.person,
                label: 'Total Staff',
                value: getTotalStaff(db).toString(),
                color: Color(0xFFF6E05E),
              ),
              const SizedBox(width: 12),
              _MetricCard(
                icon: Icons.trending_up,
                label: 'Income',
                value: formatCurrency(getTotalIncome(db)),
                color: Color(0xFFEF4444),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _MetricCard(
                icon: Icons.arrow_downward,
                label: 'Outgoing',
                value: formatCurrency(getTotalOutgoing(db)),
                color: Color(0xFF8B5CF6),
              ),
            ],
          ),
        ],
      ),
    );
  }

/// A metric card widget displaying a single dashboard metric.
class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
}

/// Customers page shown when Customers is selected in the navigation bar.
class _CustomersPage extends StatelessWidget {
  final String shopId;
  final AppUser currentUser;

  const _CustomersPage({
    required this.shopId,
    required this.currentUser,
  });

  @override
  Widget build(BuildContext context) {
    return CustomerSearchScreen(shopId: shopId, currentUser: currentUser);
  }
}

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
