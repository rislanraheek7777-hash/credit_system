import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/presentation/loading_screen.dart';
import 'package:credit_system/core/data/remote/postgres_executor.dart';
import 'package:credit_system/core/data/secure_storage.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/data/daos/user_dao.dart';
import 'package:credit_system/features/auth/data/services/auth_service.dart';
import 'package:credit_system/features/auth/data/services/jwt_service.dart';
import 'package:credit_system/features/auth/data/services/password_hash_service.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/auth/presentation/signup_screen.dart';

class LoginScreen extends StatefulWidget {
  final void Function(AppUser user, bool isOfflineOnly) onAuthenticated;
  final void Function(AuthService? service)? onAuthServiceReady;

  const LoginScreen({
    super.key,
    required this.onAuthenticated,
    this.onAuthServiceReady,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _error;
  AuthService? _authService;
  UserDao? _userDao;
  AppDatabase? _appDatabase;
  bool _obscurePassword = true;
  bool _isOfflineMode = false;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _initializeAuthService();
  }

  Future<void> _initializeAuthService() async {
    _appDatabase = AppDatabase();
    _userDao = UserDao(_appDatabase!);

    try {
      _authService = AuthService(
        pg: PostgreSqlExecutor(),
        jwt: JwtService.fromEnv(),
        passwordHash: PasswordHashService(),
        secureStorage: FlutterSecureStorageService(),
      );
    } catch (_) {
      _authService = null;
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _showForgotCredentialsDialog() async {
    if (_userDao == null) return;
    final shopIdController = TextEditingController();
    final newPasswordController = TextEditingController();
    String? message;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Reset shop owner password'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: shopIdController,
                    decoration: const InputDecoration(labelText: 'Shop ID'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'New password'),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 12),
                    Text(message!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final shopId = shopIdController.text.trim();
                    final newPassword = newPasswordController.text;
                    if (shopId.isEmpty || newPassword.isEmpty) {
                      setState(() => message = 'Shop ID and password required');
                      return;
                    }
                    try {
                      final users = await _userDao!.getUsersByShopId(shopId);
                      final owner = users.firstWhere(
                        (u) => u.role == AppRole.shopOwner,
                        orElse: () => throw StateError('not found'),
                      );
                      final hash = PasswordHashService().hashPassword(newPassword);
                      await _userDao!.updateUserPassword(shopId, owner.id, passwordHash: hash);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                      if (!mounted) return;
                      ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(content: Text('Password reset. Username: ${owner.username}')),
                        );
                    } catch (e) {
                      setState(() => message = 'Reset failed: $e');
                    }
                  },
                  child: const Text('Reset'),
                ),
              ],
            );
          },
        );
      },
    );

    shopIdController.dispose();
    newPasswordController.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    if (_userDao == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final username = _usernameController.text.trim();
      final password = _passwordController.text;

      final localUser = await _userDao!.getUserByLoginIdentifierGlobal(username);
      if (localUser == null) {
        throw const AuthenticationException('Invalid credentials');
      }

      if (_authService != null) {
        try {
          final authResult = await _authService!.authenticate(
            localUser.shopId,
            username,
            password,
          );

          if (!mounted) return;

          final user = AppUser(
            id: authResult.userId,
            shopId: authResult.shopId,
            username: authResult.username,
            fullName: authResult.fullName,
            role: AppRole.fromKey(authResult.role),
            isActive: true,
            sessionVersion: authResult.sessionVersion,
          );

          setState(() {
            _isLoading = false;
            _error = null;
            _isOfflineMode = false;
          });

          if (!mounted) return;

          widget.onAuthServiceReady?.call(_authService);
          widget.onAuthenticated(user, false);
          return;
        } catch (_) {
          // Suppress errors during online auth attempt - fall back to offline
        }
      }

      if (_authService != null) {
        final authResult = await _authService!.authenticateOffline(
          localUser.shopId,
          username,
          password,
          localUserData: {
            'id': localUser.id,
            'shop_id': localUser.shopId,
            'username': localUser.username,
            'full_name': localUser.fullName,
            'role': localUser.role.key,
            'is_active': localUser.isActive,
            'session_version': localUser.sessionVersion,
            'password_hash': localUser.passwordHash,
          },
        );

        if (!mounted) return;

        final user = AppUser(
          id: authResult.userId,
          shopId: authResult.shopId,
          username: authResult.username,
          fullName: authResult.fullName,
          role: AppRole.fromKey(authResult.role),
          isActive: true,
          sessionVersion: authResult.sessionVersion,
        );

        setState(() {
          _isLoading = false;
          _error = null;
          _isOfflineMode = true;
        });

        if (!mounted) return;

        widget.onAuthServiceReady?.call(_authService);
        widget.onAuthenticated(user, true);
        return;
      }

      // Fallback when AuthService could not be initialized: verify password locally.
      final hash = localUser.passwordHash;
      if (hash == null ||
          !PasswordHashService().verifyPassword(password, hash)) {
        throw const AuthenticationException('Invalid credentials');
      }

      // Issue a locally signed session so refresh/logout work even without
      // a configured JWT_SECRET / PostgreSQL connection.
      try {
        final jwt = JwtService('placeholder-offline-restore');
        final storage = FlutterSecureStorageService();
        final localAuthService = AuthService(
          pg: PostgreSqlExecutor.offline(),
          jwt: jwt,
          passwordHash: PasswordHashService(),
          secureStorage: storage,
        );
        final token = jwt.signToken(
          userId: localUser.id,
          shopId: localUser.shopId,
          sessionVersion: localUser.sessionVersion,
          role: localUser.role.key,
        );
        final refreshToken = jwt.signRefreshToken(
          userId: localUser.id,
          shopId: localUser.shopId,
          sessionVersion: localUser.sessionVersion,
          role: localUser.role.key,
        );
        await storage.write(key: 'jwt_token', value: token);
        await storage.write(key: 'jwt_shop_id', value: localUser.shopId);
        await storage.write(key: 'jwt_user_id', value: localUser.id);
        await storage.write(key: 'refresh_token', value: refreshToken);
        await storage.write(
          key: 'offline_session_expiry',
          value: DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
        );
        widget.onAuthServiceReady?.call(localAuthService);
      } catch (_) {
        // Best-effort; continue with local session even if storage fails.
      }

      setState(() {
        _isLoading = false;
        _error = null;
        _isOfflineMode = true;
      });

      if (!mounted) return;

      widget.onAuthenticated(localUser, true);
      return;
    } on AuthenticationException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Invalid username or password';
      });
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Invalid username or password';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const LoadingScreen(message: 'Preparing login...');
    }
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Image.asset(
                        'assets/logo.png',
                        width: 80,
                        height: 80,
                        errorBuilder: (context, error, stackTrace) =>
                            const FlutterLogo(size: 80),
                      ),
                      const SizedBox(height: 8),
                      const Icon(Icons.payments_rounded,
                          size: 32, color: Color(0xFF1565C0)),
                      const SizedBox(height: 12),
                      const Text(
                        'Credit System',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1565C0),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const Text(
                        'Sign in to continue',
                        style: TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        key: const Key('usernameField'),
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: 'Email or Phone Number',
                          hintText: 'Enter your email or phone number',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Email or phone number is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('passwordField'),
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          hintText: 'Enter your password',
                          border: OutlineInputBorder(),
                        ).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Password is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.15),
                            border: Border.all(color: Colors.red),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_isOfflineMode) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.15),
                            border: Border.all(color: Colors.orange),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Offline mode: Server synchronization will be '
                            'required before financial operations.',
                            style: TextStyle(color: Colors.orange),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextButton(
                        onPressed: _showForgotCredentialsDialog,
                        child: const Text('Forgot username or password?'),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              _isLoading || _userDao == null
                                  ? null
                                  : _login,
                          child: _isLoading
                              ? const CircularProgressIndicator()
                              : const Text('Login'),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'New shop?',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _isLoading || _userDao == null
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const SignupScreen(),
                                    ),
                                  );
                                },
                          child: const Text('Sign Up'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        ),
    );
  }
}

class AuthenticationException implements Exception {
  final String message;
  const AuthenticationException(this.message);

  @override
  String toString() => 'AuthenticationException: $message';
}


