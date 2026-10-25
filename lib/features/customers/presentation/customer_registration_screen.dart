import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/core/storage/photo_storage_service.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/customer_dao.dart';
import 'package:credit_system/features/customers/data/daos/customer_photo_exception_dao.dart';
import 'package:credit_system/features/customers/domain/models/customer.dart';
import 'package:credit_system/features/customers/domain/models/customer_photo_exception.dart';
import 'package:credit_system/features/customers/domain/services/customer_photo_compressor.dart';
import 'package:credit_system/features/customers/domain/services/customer_photo_exception_service.dart';
import 'package:credit_system/features/customers/domain/services/customer_registration_service.dart';

/// Mask a NIC for display: show first 4 and last 4 characters, masking the middle.
///
/// Example: `198512345678` → `1985****5678`
/// Example: `851234567V`   → `8512****567V`
String _maskNic(String nic) {
  if (nic.length <= 8) return nic;
  return '${nic.substring(0, 4)}****${nic.substring(nic.length - 4)}';
}

/// Generate a small sample KYC photograph (JPEG) for use when no photo
/// exception ID is provided. Keeps the UI self-contained without camera
/// integration or additional dependencies.
Uint8List _createSamplePhotoBytes() {
  final image = img.Image(width: 200, height: 200);
  for (int y = 0; y < 200; y++) {
    for (int x = 0; x < 200; x++) {
      image.setPixelRgba(x, y, 200, 100, 50, 255);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image));
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

  final _idController = TextEditingController();
  final _shopIdController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _nicController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _photoExceptionIdController = TextEditingController();
  final _confirmingStaffIdController = TextEditingController();

  Uint8List? _capturedPhotoBytes;
  CustomerPhotoException? _pendingPhotoException;

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
  Uint8List? _resolvePhotoBytes() {
    final exceptionId = _photoExceptionIdController.text.trim();
    if (exceptionId.isNotEmpty) return null;
    return _capturedPhotoBytes;
  }

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

      final request = RegisterCustomerRequest(
        id: _idController.text.trim(),
        shopId: _shopIdController.text.trim(),
        fullName: _fullNameController.text.trim(),
        nic: _nicController.text.trim(),
        phone: _phoneController.text.trim(),
        address: _addressController.text.trim(),
        rawPhotoBytes: _resolvePhotoBytes(),
        photoExceptionId: _photoExceptionIdController.text.trim().isEmpty
            ? null
            : _photoExceptionIdController.text.trim(),
        confirmSharedPhone: confirmSharedPhone,
        confirmingStaffId: _confirmingStaffIdController.text.trim().isEmpty
            ? null
            : _confirmingStaffIdController.text.trim(),
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

      if (widget.database == null) {
        await db.close();
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

  Future<void> _showRequestPhotoExceptionDialog() async {
    final customerId = _idController.text.trim();
    final shopId = _shopIdController.text.trim();
    final nic = _nicController.text.trim();

    if (customerId.isEmpty || shopId.isEmpty || nic.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please fill Customer ID, Shop ID, and NIC before requesting a photo exception.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final reasonController = TextEditingController();
    final confirmedReason = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Request Customer Photo Exception'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Mandatory documented business justification for KYC photo exception (e.g. Camera hardware failure; manual physical NIC copy verified). Requires Shop Owner approval.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('photo_exception_reason_field'),
                controller: reasonController,
                autofocus: true,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Justification Reason',
                  hintText:
                      'e.g. Camera hardware failure; manual physical NIC copy verified',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              key: const Key('submit_exception_request_button'),
              onPressed: reasonController.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(reasonController.text.trim()),
              child: const Text('Submit Request'),
            ),
          ],
        ),
      ),
    );

    if (confirmedReason == null || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final db = widget.database ?? AppDatabase();
      final exceptionDao = CustomerPhotoExceptionDao(db);
      final exceptionService = CustomerPhotoExceptionService(
        exceptionDao: exceptionDao,
        db: db,
      );

      final requester = widget.currentUser ??
          AppUser(
            id: _confirmingStaffIdController.text.trim().isNotEmpty
                ? _confirmingStaffIdController.text.trim()
                : 'staff-counter',
            shopId: shopId,
            username: 'counter.staff',
            fullName: 'Counter Staff',
            role: AppRole.cashier,
          );

      final exception = await exceptionService.requestPhotoException(
        shopId: shopId,
        targetCustomerId: customerId,
        customerNic: nic,
        requester: requester,
        reason: confirmedReason,
      );

      if (mounted) {
        setState(() {
          _photoExceptionIdController.text = exception.id;
          _pendingPhotoException = exception;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Photo exception requested (ID: ${exception.id}); awaiting Shop Owner approval.',
            ),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = e.toString();
        });
      }
    }
  }

  Widget _buildPhotoSection() {
    return Container(
      key: const Key('customer_photo_section'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _capturedPhotoBytes != null
              ? Colors.green.shade400
              : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Customer Photograph (Mandatory KYC)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              if (_capturedPhotoBytes != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Photo Attached',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_capturedPhotoBytes != null) ...[
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  _capturedPhotoBytes!,
                  key: const Key('customer_photo_preview'),
                  height: 160,
                  width: 160,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Preview: ${(_capturedPhotoBytes!.length / 1024).toStringAsFixed(1)} KB (Ready for compression)',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  key: const Key('retake_photo_button'),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retake'),
                  onPressed: () {
                    setState(() {
                      _capturedPhotoBytes = _createSamplePhotoBytes();
                    });
                  },
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  key: const Key('clear_photo_button'),
                  icon: const Icon(Icons.delete_outline,
                      size: 16, color: Colors.red),
                  label:
                      const Text('Clear', style: TextStyle(color: Colors.red)),
                  onPressed: () {
                    setState(() {
                      _capturedPhotoBytes = null;
                    });
                  },
                ),
              ],
            ),
          ] else ...[
            Container(
              height: 110,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: Colors.grey.shade300, style: BorderStyle.solid),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.camera_alt_outlined, size: 36, color: Colors.grey),
                  SizedBox(height: 6),
                  Text(
                    'No photograph captured',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    key: const Key('capture_photo_button'),
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: const Text('Capture Photo'),
                    onPressed: () {
                      setState(() {
                        _capturedPhotoBytes = _createSamplePhotoBytes();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('upload_photo_button'),
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('Upload File'),
                    onPressed: () {
                      setState(() {
                        _capturedPhotoBytes = _createSamplePhotoBytes();
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                key: const Key('request_photo_exception_button'),
                icon: const Icon(Icons.lock_clock, size: 16, color: Colors.amber),
                label: const Text(
                  'Hardware/Physical Issue? Request Photo Exception',
                  style: TextStyle(color: Colors.amber, fontSize: 12),
                ),
                onPressed: _showRequestPhotoExceptionDialog,
              ),
            ),
          ],
          if (_pendingPhotoException != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Photo Exception Request Pending Owner Approval (ID: ${_pendingPhotoException!.id}). Profile registration remains blocked until approved.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.amber.shade900),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _idController.dispose();
    _shopIdController.dispose();
    _fullNameController.dispose();
    _nicController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _photoExceptionIdController.dispose();
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
                controller: _idController,
                decoration: const InputDecoration(
                  labelText: 'Customer ID',
                  hintText: 'UUIDv4',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Customer ID is required'
                    : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _shopIdController,
                decoration: const InputDecoration(
                  labelText: 'Shop ID',
                  hintText: 'UUIDv4',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Shop ID is required'
                    : null,
              ),
              const SizedBox(height: 12),

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
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'NIC is required' : null,
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
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Address is required'
                    : null,
              ),
              const SizedBox(height: 12),

              _buildPhotoSection(),
              const SizedBox(height: 12),

              TextFormField(
                controller: _photoExceptionIdController,
                decoration: const InputDecoration(
                  labelText: 'Photo Exception ID (optional)',
                  hintText: 'Leave blank to use a sample photograph; provide an approved exception ID to skip photo capture',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _confirmingStaffIdController,
                decoration: const InputDecoration(
                  labelText: 'Confirming Staff ID',
                  hintText:
                      'Required when confirming a shared-phone registration',
                  border: OutlineInputBorder(),
                ),
              ),
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
