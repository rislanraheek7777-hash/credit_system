import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/storage/photo_storage_service.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/customer_dao.dart';
import 'package:credit_system/features/customers/data/daos/customer_photo_exception_dao.dart';
import 'package:credit_system/features/customers/domain/models/customer.dart';
import 'package:credit_system/features/customers/domain/services/customer_photo_compressor.dart';
import 'package:credit_system/features/customers/domain/services/customer_registration_service.dart';
import 'package:uuid/uuid.dart';

/// Mask a NIC for display: show first 4 and last 4 characters, masking the middle.
///
/// Example: `198512345678` → `1985****5678`
/// Example: `851234567V`   → `8512****567V`
String _maskNic(String nic) {
  if (nic.length <= 8) return nic;
  return '${nic.substring(0, 4)}****${nic.substring(nic.length - 4)}';
}


/// Customer registration screen implementing Story 2.4 AC-2 and AC-3.
///
/// Provides:
/// - Duplicate NIC blocking with existing profile surfacing (AC-1)
/// - Non-blocking shared-phone warning banner with masked NIC (AC-2)
/// - Explicit "Confirm separate individual sharing phone number" action (AC-3)
/// - Atomic customer + SyncQueue event insertion on confirmation
/// - Shop-scoped validation and cross-shop data leakage prevention
class CustomerRegistrationScreen extends StatefulWidget {
  const CustomerRegistrationScreen({
    super.key,
    this.database,
    this.currentUser,
    this.storageService,
  });

  /// Optional injected [AppDatabase] for testing. When omitted, the screen
  /// opens its own database connection via `AppDatabase()`.
  final AppDatabase? database;

  /// Optional authenticated user performing the registration.
  final AppUser? currentUser;

  /// Optional injected [PhotoStorageService] for hermetic test storage.
  final PhotoStorageService? storageService;

  @override
  State<CustomerRegistrationScreen> createState() =>
      _CustomerRegistrationScreenState();
}

class _CustomerRegistrationScreenState
    extends State<CustomerRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

  final _fullNameController = TextEditingController();
  String? _sessionId;
  final _nicController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _confirmingStaffIdController = TextEditingController();

  bool _isLoading = false;
  String? _statusMessage;
  bool _isSuccess = false;

  SharedPhoneDuplicateException? _pendingSharedPhoneException;
  bool _sharedPhoneConfirmed = false;

  CustomerRegistrationService _buildService(AppDatabase db) {
    return CustomerRegistrationService(
      customerDao: CustomerDao(db),
      exceptionDao: CustomerPhotoExceptionDao(db),
      compressor: const CustomerPhotoCompressor(),
      storageService: widget.storageService ?? const PhotoStorageService(),
      db: db,
    );
  }

  /// Returns a compressible photo byte list, or null when a photo exception
  /// ID is provided (Story 2.3 path) or when no photo has been captured.
  Future<void> _register({required bool confirmSharedPhone}) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _statusMessage = null;
      _isSuccess = false;
    });

    try {
      final db = widget.database ?? AppDatabase();
      final service = _buildService(db);

      final shopId = widget.currentUser?.shopId ?? '';
      _sessionId ??= const Uuid().v4();
      final request = RegisterCustomerRequest(
        id: _sessionId!,
        shopId: shopId,
        fullName: _fullNameController.text.trim(),
        nic: _nicController.text.trim(),
        phone: _phoneController.text.trim(),
        address: _addressController.text.trim(),
        rawPhotoBytes: null,
        photoExceptionId: null,
        confirmSharedPhone: confirmSharedPhone,
        confirmingStaffId: confirmSharedPhone
            ? (widget.currentUser?.id ?? 'staff-counter')
            : null,
      );

      final customer = await service.registerCustomer(request);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSuccess = true;
          _statusMessage =
              'Customer "${customer.fullName}" registered successfully (ID: ${customer.id}).';
          _pendingSharedPhoneException = null;
          _sharedPhoneConfirmed = false;
        });
      }
    } on DuplicateNicException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = e.message;
          _pendingSharedPhoneException = null;
          _sharedPhoneConfirmed = false;
        });
      }
      // Surface the existing profile so staff can open it instead of duplicating.
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Existing Customer Profile'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ID: ${e.existingCustomer.id}'),
                Text('Name: ${e.existingCustomer.fullName}'),
                Text('NIC: ${_maskNic(e.existingCustomer.nic)}'),
                Text('Phone: ${e.existingCustomer.phone}'),
                const SizedBox(height: 16),
                const Text(
                  'A customer with this NIC already exists in this shop. '
                  'Open the existing profile instead of creating a duplicate.',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } on SharedPhoneDuplicateException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _pendingSharedPhoneException = e;
          _sharedPhoneConfirmed = false;
        });
      }
    } on CustomerValidationException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = e.message;
          _pendingSharedPhoneException = null;
          _sharedPhoneConfirmed = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Registration failed: $e';
          _pendingSharedPhoneException = null;
          _sharedPhoneConfirmed = false;
        });
      }
    }
  }

  Future<void> _confirmSharedPhone() async {
    if (_pendingSharedPhoneException == null) return;

    setState(() {
      _sharedPhoneConfirmed = true;
    });

    await _register(confirmSharedPhone: true);
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _nicController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _confirmingStaffIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusBgColor = _isSuccess
        ? Colors.green.withValues(alpha: 0.15)
        : Colors.red.withValues(alpha: 0.15);

    return Scaffold(
      appBar: AppBar(title: const Text('Customer Registration')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                const Text(
                'Register New Customer',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // Shared-phone warning banner (AC-2)
              if (_pendingSharedPhoneException != null &&
                  !_sharedPhoneConfirmed) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    border: Border.all(color: Colors.amber),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Shared Phone Number Detected',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Phone number shared with existing customer '
                        '${_pendingSharedPhoneException!.existingCustomers.first.fullName} '
                        '(masked NIC: ${_maskNic(_pendingSharedPhoneException!.existingCustomers.first.nic)}).',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'A shared phone never automatically means the same person. '
                        'Confirm below to register this as a distinct individual.',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: GestureDetector(
                          key: const Key('confirm_shared_phone_button'),
                          onTap: _isLoading ? null : _confirmSharedPhone,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade700,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              'Confirm separate individual sharing phone number',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Status / error messages
              if (_statusMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: statusBgColor,
                    border: Border.all(
                      color: _isSuccess ? Colors.green : Colors.red,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusMessage!,
                    style: TextStyle(
                      color: _isSuccess
                          ? Colors.green.shade800
                          : Colors.red.shade800,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              TextFormField(
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
                controller: _nicController,
                decoration: const InputDecoration(
                  labelText: 'NIC Number',
                  hintText: 'e.g. 851234567V or 198512345678',
                  border: OutlineInputBorder(),
                ),
                // NIC is optional.
                validator: (v) => null,
              ),
              const SizedBox(height: 12),

              TextFormField(
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
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Residential Address',
                  border: OutlineInputBorder(),
                ),
                // Residential address is optional.
                validator: (v) => null,
              ),
              const SizedBox(height: 12),

              const SizedBox(height: 20),

              // RBAC note
              const Text(
                'Requires `registerCustomers` permission (Cashier, Manager, or Shop Owner).',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  key: const Key('register_customer_button'),
                  onTap: _isLoading || _pendingSharedPhoneException != null
                      ? null
                      : () => _register(confirmSharedPhone: false),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Register Customer',
                            style: TextStyle(color: Colors.white),
                          ),
                  ),
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

