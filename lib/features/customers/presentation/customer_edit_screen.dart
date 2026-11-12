import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/customer_dao.dart';
import 'package:credit_system/features/customers/domain/models/customer.dart';

/// Customer profile editing screen.
///
/// Reached from the "Edit" action on [CustomerProfileScreen]. Allows staff with
/// the `registerCustomers` permission to amend the permitted profile details
/// (name, NIC, phone, address) while preserving immutable identity columns.
///
/// Pops with the updated [Customer] on success, or `null` when cancelled.
class CustomerEditScreen extends StatefulWidget {
  const CustomerEditScreen({
    super.key,
    required this.shopId,
    required this.customer,
    required this.currentUser,
    this.database,
  });

  /// The active shop tenant UUID.
  final String shopId;

  /// The customer being edited.
  final Customer customer;

  /// The authenticated actor performing the edit.
  final AppUser currentUser;

  /// Optional injected [AppDatabase] for testing.
  final AppDatabase? database;

  @override
  State<CustomerEditScreen> createState() => _CustomerEditScreenState();
}

class _CustomerEditScreenState extends State<CustomerEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _fullNameController;
  late final TextEditingController _nicController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;

  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(text: widget.customer.fullName);
    _nicController = TextEditingController(text: widget.customer.nic);
    _phoneController = TextEditingController(text: widget.customer.phone);
    _addressController = TextEditingController(text: widget.customer.address);
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _nicController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    final db = widget.database ?? AppDatabase();

    try {
      final updated = widget.customer.copyWith(
        fullName: _fullNameController.text.trim(),
        nic: _nicController.text.trim(),
        phone: _phoneController.text.trim(),
        address: _addressController.text.trim(),
        updatedAt: DateTime.now().toUtc(),
      );

      await CustomerDao(db).updateCustomer(updated);

      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = 'Failed to save customer: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Customer')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      border: Border.all(color: Colors.red),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Colors.red.shade800),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                TextFormField(
                  key: const Key('edit_customer_full_name_field'),
                  controller: _fullNameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Full name is required'
                      : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  key: const Key('edit_customer_nic_field'),
                  controller: _nicController,
                  decoration: const InputDecoration(
                    labelText: 'NIC Number',
                    hintText: 'e.g. 851234567V or 198512345678',
                    border: OutlineInputBorder(),
                  ),
                  // NIC is optional; validate the format only when provided.
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) return null;
                    return Customer.isValidNicFormat(value)
                        ? null
                        : 'Enter a valid NIC (9 digits + V/X or 12 digits)';
                  },
                ),
                const SizedBox(height: 12),

                TextFormField(
                  key: const Key('edit_customer_phone_field'),
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    hintText: 'e.g. 0771234567 or +94771234567',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Phone is required' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  key: const Key('edit_customer_address_field'),
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'Residential Address',
                    border: OutlineInputBorder(),
                  ),
                  // Residential address is optional.
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('save_customer_button'),
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save Changes'),
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

