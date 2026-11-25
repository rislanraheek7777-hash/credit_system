import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/features/auth/data/daos/user_dao.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/shop/data/daos/shop_dao.dart';
import 'package:credit_system/features/shop/domain/models/shop_profile.dart';
import 'package:credit_system/core/permissions/app_permission.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, this.database});

  /// Injectable for widget tests; production builds use a real [AppDatabase].
  final AppDatabase? database;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  AppDatabase? _db;
  UserDao? _userDao;
  ShopDao? _shopDao;

  @override
  void initState() {
    super.initState();
    _db = widget.database ?? AppDatabase();
    _userDao = UserDao(_db!);
    _shopDao = ShopDao(_db!);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match')),
      );
      return;
    }
    if (_userDao == null) return;

    setState(() => _isLoading = true);
    try {
      final username = _usernameController.text.trim();
      final email = _emailController.text.trim();
      final phone = _phoneController.text.trim();
      final user = AppUser(
        id: const Uuid().v4(),
        shopId: 'default-shop',
        username: username,
        email: email.isEmpty ? null : email,
        phone: phone.isEmpty ? null : phone,
        fullName: _nameController.text.trim(),
        role: AppRole.shopOwner,
        isActive: true,
        sessionVersion: 1,
      );
      await _shopDao!.getShopById('default-shop').then((shop) async {
        if (shop == null) {
          await _shopDao!.createShop(ShopProfile(id: 'default-shop', name: 'Default Shop'));
        }
      });
      await _userDao!.createUserWithPassword(user, _passwordController.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signup successful. Please login.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Signup failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign Up')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('signupUsernameField'),
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  hintText: 'Enter username',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Username is required';
                  }
                  if (v.trim().length > 100) {
                    return 'Username cannot exceed 100 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Phone Number'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Password is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirm Password'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Confirm password is required' : null,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  key: const Key('signup_button'),
                  onPressed: _isLoading ? null : _signup,
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Sign Up'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
