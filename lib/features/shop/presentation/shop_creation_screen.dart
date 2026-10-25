import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/features/shop/data/daos/shop_dao.dart';
import 'package:credit_system/features/shop/domain/models/shop_profile.dart';

/// Screen for creating a new shop profile (Story 1.6, PRD FR-1).
///
/// This is the entry point for a new shop tenant. It collects the shop's
/// legal profile and operational settings, creates the shop in local Drift
/// SQLite storage, and transitions to the login screen so staff accounts can
/// be created.
///
/// Offline-first: the shop is created locally and can be synchronized to the
/// cloud later. No PostgreSQL provisioning is required at creation time.
class ShopCreationScreen extends StatefulWidget {
  /// Optional injected [AppDatabase] for testing.
  final AppDatabase? database;

  const ShopCreationScreen({super.key, this.database});

  @override
  State<ShopCreationScreen> createState() => _ShopCreationScreenState();
}

class _ShopCreationScreenState extends State<ShopCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _shopNameController = TextEditingController();
  final _businessAddressController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _registrationNumberController = TextEditingController();
  final _timezoneController = TextEditingController(text: 'Asia/Colombo');
  final _currencyCodeController = TextEditingController(text: 'LKR');

  bool _isLoading = false;
  String? _error;
  String? _successMessage;

  @override
  void dispose() {
    _shopNameController.dispose();
    _businessAddressController.dispose();
    _contactPhoneController.dispose();
    _contactEmailController.dispose();
    _registrationNumberController.dispose();
    _timezoneController.dispose();
    _currencyCodeController.dispose();
    super.dispose();
  }

  Future<void> _createShop() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final db = widget.database ?? AppDatabase();
      final shopDao = ShopDao(db);

      final shopId = const Uuid().v4();
      final now = DateTime.now().toUtc();

      final shop = ShopProfile(
        id: shopId,
        name: _shopNameController.text.trim(),
        currencyCode: _currencyCodeController.text.trim().toUpperCase(),
        timezone: _timezoneController.text.trim(),
        businessAddress: _businessAddressController.text.trim().isEmpty
            ? null
            : _businessAddressController.text.trim(),
        contactPhone: _contactPhoneController.text.trim().isEmpty
            ? null
            : _contactPhoneController.text.trim(),
        contactEmail: _contactEmailController.text.trim().isEmpty
            ? null
            : _contactEmailController.text.trim(),
        registrationNumber:
            _registrationNumberController.text.trim().isEmpty
                ? null
                : _registrationNumberController.text.trim(),
        createdAt: now,
        updatedAt: now,
      );

      await shopDao.createShop(shop);
      if (widget.database == null) {
        await db.close();
      }

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _successMessage =
            'Shop created successfully. Shop ID: $shopId. You can now log in.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to create shop: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Shop'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Create Shop Profile',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter your shop details to get started. The shop will be created '
                'locally and can be synchronized to the cloud later.',
                style: TextStyle(color: Colors.grey),
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
              if (_successMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    border: Border.all(color: Colors.green),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _successMessage!,
                    style: const TextStyle(color: Colors.green),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Your shop has been created. You can now close this screen and '
                  'log in using your shop ID.',
                  style: TextStyle(color: Colors.grey),
                ),
              ] else ...[
                TextFormField(
                  key: const Key('shop_creation_name_field'),
                  controller: _shopNameController,
                  decoration: const InputDecoration(
                    labelText: 'Shop Name',
                    hintText: 'e.g. Alpha Jewellers',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Shop name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('shop_creation_timezone_field'),
                  controller: _timezoneController,
                  decoration: const InputDecoration(
                    labelText: 'Time Zone',
                    hintText: 'e.g. Asia/Colombo',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Time zone is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('shop_creation_currency_field'),
                  controller: _currencyCodeController,
                  decoration: const InputDecoration(
                    labelText: 'Currency Code',
                    hintText: 'e.g. LKR',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Currency code is required';
                    }
                    if (value.trim().length != 3) {
                      return 'Currency code must be 3 letters (e.g. LKR)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _businessAddressController,
                  decoration: const InputDecoration(
                    labelText: 'Business Address',
                    hintText: 'Optional',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _contactPhoneController,
                  decoration: const InputDecoration(
                    labelText: 'Contact Phone',
                    hintText: 'Optional',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _contactEmailController,
                  decoration: const InputDecoration(
                    labelText: 'Contact Email',
                    hintText: 'Optional',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _registrationNumberController,
                  decoration: const InputDecoration(
                    labelText: 'Registration/Tax Number',
                    hintText: 'Optional',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    key: const Key('shop_creation_submit_button'),
                    onPressed: _isLoading ? null : _createShop,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create Shop'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
