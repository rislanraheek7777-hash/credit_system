import 'package:flutter/material.dart';

import 'package:credit_system/core/theme/theme_controller.dart';
import 'package:credit_system/features/auth/presentation/login_screen.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/presentation/customer_search_screen.dart';
import 'package:credit_system/features/customers/presentation/credit_details_screen.dart';
import 'package:credit_system/features/dashboard/data/services/dashboard_metrics_service.dart';
import 'package:credit_system/features/dashboard/domain/models/dashboard_metrics.dart';
import 'package:credit_system/features/customers/data/daos/credit_dao.dart';
import 'package:credit_system/features/customers/data/daos/customer_dao.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:credit_system/features/customers/domain/models/customer.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/presentation/loading_screen.dart';
import 'package:credit_system/core/data/remote/postgres_executor.dart';
import 'package:credit_system/core/data/secure_storage.dart';
import 'package:credit_system/features/auth/data/daos/user_dao.dart';
import 'package:credit_system/features/auth/data/services/auth_service.dart';
import 'package:credit_system/features/auth/data/services/jwt_service.dart';
import 'package:credit_system/features/auth/data/services/password_hash_service.dart';

/// Main application shell shown after authentication.
/// Uses a scaffold with a bottom navigation bar for switching between
/// dashboard and customers sections.
class MainApp extends StatefulWidget {
  final String shopId;
  final AppUser currentUser;
  final bool isOfflineOnly;
  final AuthService? authService;
  final VoidCallback? onLogout;

  /// Optional database injection for tests. Production supplies the database
  /// owned by [AuthWrapper] so the dashboard shares the same connection.
  final AppDatabase? database;

  const MainApp({
    super.key,
    required this.shopId,
    required this.currentUser,
    this.isOfflineOnly = false,
    this.authService,
    this.onLogout,
    this.database,
  });

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  int _selectedIndex = 0;

  Future<void> _handleLogout() async {
    try {
      await widget.authService?.logout();
      await widget.authService?.clearCachedSession();
    } catch (_) {
      // Ignore storage errors during logout.
    }
    widget.onLogout?.call();
  }

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
      database: widget.database,
    );

    final customersPage = _CustomersPage(
      shopId: widget.shopId,
      currentUser: widget.currentUser,
      onLogout: _handleLogout,
      database: widget.database,
    );

    final creditDetailsPage = _CreditDetailsPage(
      shopId: widget.shopId,
      currentUser: widget.currentUser,
      database: widget.database,
    );

    final List<Widget> pages = [
      dashboardPage,
      customersPage,
      creditDetailsPage,
    ];

    return Scaffold(
      body: pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        elevation: 8,
        height: 72,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shadowColor: Colors.black26,
        indicatorColor: const Color(0xFF3478F6).withValues(alpha: 0.15),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Customers',
          ),
          NavigationDestination(
            icon: Icon(Icons.credit_score_outlined),
            selectedIcon: Icon(Icons.credit_score),
            label: 'Credit Details',
          ),
        ],
      ),
    );
  }
}

/// Dashboard page shown when Dashboard is selected in the navigation bar.
class _DashboardPage extends StatefulWidget {
  final String shopId;
  final AppUser currentUser;
  final bool isOfflineOnly;
  final AppDatabase? database;

  const _DashboardPage({
    required this.shopId,
    required this.currentUser,
    required this.isOfflineOnly,
    this.database,
  });

  @override
  State<_DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<_DashboardPage> {
  late final DashboardMetricsService _metricsService;
  late Stream<DashboardMetrics> _metricsStream;
  late final CreditDao _creditDao;
  late final CustomerDao _customerDao;
  late Stream<List<Credit>> _creditsStream;
  Map<int, Customer> _customersById = {};

  @override
  void initState() {
    super.initState();
    final database = widget.database ?? AppDatabase();
    _metricsService = DashboardMetricsService(database);
    _metricsStream = _metricsService.watchMetrics(widget.shopId);
    _creditDao = CreditDao(database);
    _customerDao = CustomerDao(database);
    _creditsStream = _creditDao.watchCreditsByShopId(widget.shopId);
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    final customers = await _customerDao.getCustomersByShopId(widget.shopId);
    if (!mounted) return;
    setState(() {
      _customersById = {for (var c in customers) c.id: c};
    });
  }

  @override
  void dispose() {
    // The database is a shared singleton owned by AuthWrapper; do not close it
    // here. It is closed in AuthWrapper.dispose() when the app terminates.
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    final nextStream = _metricsService.watchMetrics(widget.shopId);
    setState(() {
      _metricsStream = nextStream;
    });
  }

  String formatCurrency(int cents) {
    final rupees = cents / 100;
    return 'Rs.${rupees.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: StreamBuilder<DashboardMetrics>(
        stream: _metricsStream,
        builder: (context, snapshot) {
          final metrics = snapshot.data ?? DashboardMetrics.empty;
          final cardWidgets = [
            _MetricCard(
              key: const ValueKey('metric-total-customers'),
              icon: Icons.person_outline,
              label: 'Total Customers',
              value: metrics.totalCustomers.toString(),
              color: Color(0xFF10B981),
            ),
            _MetricCard(
              key: const ValueKey('metric-total-staff'),
              icon: Icons.person,
              label: 'Total Staff',
              value: metrics.totalStaff.toString(),
              color: Color(0xFFF6E05E),
            ),
            _MetricCard(
              key: const ValueKey('metric-total-credits'),
              icon: Icons.credit_score,
              label: 'Total Credits',
              value: metrics.totalCredits.toString(),
              color: Color(0xFF7C3AED),
            ),
            _MetricCard(
              key: const ValueKey('metric-active-credit'),
              icon: Icons.credit_card,
              label: 'Active Credit',
              value: formatCurrency(metrics.activeCreditCents),
              color: Color(0xFF0EA5E9),
            ),
            _MetricCard(
              key: const ValueKey('metric-outstanding'),
              icon: Icons.account_balance_wallet,
              label: 'Outstanding',
              value: formatCurrency(metrics.outstandingCents),
              color: Color(0xFFEF4444),
            ),
            _MetricCard(
              key: const ValueKey('metric-collected'),
              icon: Icons.payments,
              label: 'Collected',
              value: formatCurrency(metrics.collectedCents),
              color: Color(0xFF10B981),
            ),
            _MetricCard(
              key: const ValueKey('metric-ratio'),
              icon: Icons.percent,
              label: 'Ratio',
              value: metrics.ratio.toStringAsFixed(2),
              color: Color(0xFF8B5CF6),
            ),
          ];

          return RefreshIndicator(
            onRefresh: _handleRefresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Shop header info
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(32),
                        bottomRight: Radius.circular(32),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          'Dashboard',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Shop: ${widget.shopId}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (snapshot.hasError)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        'Could not load dashboard metrics: ${snapshot.error}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),

                  // Metrics grid — exactly 2 cards per row, static (no sliding
                  // / no scrolling). If the last row has a single card, it
                  // fills the full row width.
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < cardWidgets.length; i += 2) ...[
                        if (i + 1 < cardWidgets.length)
                          Row(
                            children: [
                              Expanded(child: cardWidgets[i]),
                              const SizedBox(width: 12),
                              Expanded(child: cardWidgets[i + 1]),
                            ],
                          )
                        else
                          Row(
                            children: [
                              Expanded(child: cardWidgets[i]),
                            ],
                          ),
                        if (i + 2 < cardWidgets.length)
                          const SizedBox(height: 12),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Active Credits',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<List<Credit>>(
                    stream: _creditsStream,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Text('Error: ${snapshot.error}');
                      }
                      if (!snapshot.hasData) {
                        return const SizedBox.shrink();
                      }
                      final allCredits = snapshot.data!;
                      final activeCredits = allCredits.where((c) =>
                          (c.status == CreditStatus.active ||
                              c.status == CreditStatus.overdue) &&
                          c.workflowStatus == CreditWorkflowStatus.disbursed
                        ).toList()
                        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
                      if (activeCredits.isEmpty) {
                        return const Text(
                          'No active credits',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        );
                      }
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final credit in activeCredits) ...[
                            Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Text(
                                    credit.id.substring(0, 2).toUpperCase(),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                title: Text(
                                  _customersById[credit.customerId]?.fullName ??
                                      'Customer ${credit.customerId}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        'Principal: ${formatCurrency(credit.principalCents)}'),
                                    Text(
                                        'Balance: ${formatCurrency(credit.balanceCents)}'),
                                    Text(
                                        'Status: ${credit.status.value}'),
                                    Text(
                                        'Due: ${credit.dueDate.toLocal().toString().substring(0, 10)}'),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A metric card widget displaying a single dashboard metric.
class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
    );
  }
}

/// Customers page shown when Customers is selected in the navigation bar.
class _CustomersPage extends StatelessWidget {
  final String shopId;
  final AppUser currentUser;
  final VoidCallback? onLogout;
  final AppDatabase? database;

  const _CustomersPage({
    required this.shopId,
    required this.currentUser,
    this.onLogout,
    this.database,
  });

  @override
  Widget build(BuildContext context) {
    return CustomerSearchScreen(
      shopId: shopId,
      currentUser: currentUser,
      onLogout: onLogout,
      database: database,
    );
  }
}

/// Credit details page shown when Credit Details is selected in the navigation bar.
class _CreditDetailsPage extends StatelessWidget {
  final String shopId;
  final AppUser currentUser;
  final AppDatabase? database;

  const _CreditDetailsPage({
    required this.shopId,
    required this.currentUser,
    this.database,
  });

  @override
  Widget build(BuildContext context) {
    return CreditDetailsScreen(
      shopId: shopId,
      currentUser: currentUser,
      database: database,
    );
  }
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Credit System',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1565C0),
            ),
            cardTheme: CardThemeData(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1565C0),
              brightness: Brightness.dark,
            ),
            cardTheme: CardThemeData(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          themeMode: mode,
          home: const AuthWrapper(),
        );
      },
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
  late AuthService _authService;

  @override
  void initState() {
    super.initState();
    _appDatabase = AppDatabase();
    _userDao = UserDao(_appDatabase);
    JwtService jwtService;
    try {
      jwtService = JwtService.fromEnv();
    } catch (_) {
      jwtService = JwtService('placeholder-offline-restore');
    }
    _authService = AuthService(
      pg: PostgreSqlExecutor.offline(),
      jwt: jwtService,
      passwordHash: PasswordHashService(),
      secureStorage: FlutterSecureStorageService(),
    );
    _checkExistingAuth();
  }

  @override
  void dispose() {
    AppDatabase.dispose();
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
    // Show the loading screen for a few seconds on startup.
    await Future.delayed(const Duration(seconds: 4));
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

  /// Logs out the current user and returns to the login screen.
  Future<void> _logout() async {
    try {
      await _authService.logout();
      await _authService.clearCachedSession();
    } catch (_) {
      // Ignore storage errors during logout.
    }
    if (!mounted) return;
    setState(() {
      _isAuthenticated = false;
      _currentUser = null;
      _isOfflineOnly = false;
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
      return const LoadingScreen(message: 'Preparing your workspace...');
    }

    if (!_isAuthenticated || _currentUser == null) {
      return LoginScreen(
        onAuthenticated: _onAuthenticated,
        onAuthServiceReady: (service) {
          if (service != null) {
            _authService = service;
          }
        },
      );
    }

    return MainApp(
      shopId: _currentUser!.shopId,
      currentUser: _currentUser!,
      isOfflineOnly: _isOfflineOnly,
      authService: _authService,
      onLogout: _logout,
      database: _appDatabase,
    );
  }

  /// Returns the currently authenticated user.
  ///
  /// The role, shop ID, and permissions are all derived from the
  /// authenticated session — never hardcoded.
  AppUser get currentUser {
    if (_currentUser == null) {
      throw StateError('No authenticated user. Call _onAuthenticated first.');
    }
    return _currentUser!;
  }

  /// Returns whether the current session was established offline only.
  ///
  /// Offline sessions must be re-validated against PostgreSQL before any
  /// server-bound operation.
  bool get isOfflineOnly => _isOfflineOnly;
}

