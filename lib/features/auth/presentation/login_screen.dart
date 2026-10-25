import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/remote/postgres_executor.dart';
import 'package:credit_system/core/data/secure_storage.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/data/daos/user_dao.dart';
import 'package:credit_system/features/auth/data/services/auth_service.dart';
import 'package:credit_system/features/auth/data/services/jwt_service.dart';
import 'package:credit_system/features/auth/data/services/password_hash_service.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/shop/presentation/shop_creation_screen.dart';

class LoginScreen extends StatefulWidget {
  final void Function(AppUser user, bool isOfflineOnly) onAuthenticated;

  const LoginScreen({super.key, required this.onAuthenticated});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _shopIdController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _error;
  AuthService? _authService;
  UserDao? _userDao;
  AppDatabase? _appDatabase;
  bool _isOfflineMode = false;

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
    }
  }

  @override
  void dispose() {
    _shopIdController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _appDatabase?.close();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    if (_userDao == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final shopId = _shopIdController.text.trim();
      final username = _usernameController.text.trim();
      final password = _passwordController.text;

      if (_authService != null) {
        try {
          final authResult = await _authService!.authenticate(
            shopId,
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

          widget.onAuthenticated(user, false);
          return;
        } catch (_) {
          // Suppress errors during online auth attempt - fall back to offline
        }
      }

      final localUser = await _userDao!.getUserByUsername(shopId, username);
      if (localUser == null) {
        throw const AuthenticationException('Invalid credentials');
      }

      final authResult = await _authService!.authenticateOffline(
        shopId,
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

      widget.onAuthenticated(user, true);
    } on AuthenticationException {
      rethrow;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Text(
                        'Login',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('shopIdField'),
                        controller: _shopIdController,
                        decoration: const InputDecoration(
                          labelText: 'Shop ID',
                          hintText: 'Enter your shop ID',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Shop ID is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('usernameField'),
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          hintText: 'Enter your username',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Username is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('passwordField'),
                        controller: _passwordController,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          hintText: 'Enter your password',
                          border: OutlineInputBorder(),
                        ),
                        obscureText: true,
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
                                          const ShopCreationScreen(),
                                    ),
                                  );
                                },
                          child: const Text('Create New Shop'),
                        ),
                      ),
                    ],
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
