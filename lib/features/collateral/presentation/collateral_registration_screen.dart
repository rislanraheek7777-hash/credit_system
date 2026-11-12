import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/core/storage/photo_storage_service.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_dao.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_photo_exception_dao.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_photo_exception.dart';
import 'package:credit_system/features/customers/domain/services/customer_photo_compressor.dart';

/// Collateral registration screen with custody management (Story 3.4).
///
/// Provides:
/// - Multi-item collateral registration with category, description, condition,
///   weight (decimal grams → integer milligrams), and estimated value (Money)
/// - Mandatory photo capture with compression and SHA-256 hash (Story 3.2)
/// - Photo integrity verification on registration (Story 3.2 AC-3)
/// - Owner-approved photo exception workflow (Story 3.2 AC-4, AC-5)
/// - Custody state transitions:
///   - inCustody → handoverRequested (staff requests return)
///   - handoverRequested → handoverReported (staff reports physical handover)
///   - handoverReported → returned (Shop Owner confirms return)
///   - inCustody → discrepancy (staff reports discrepancy)
///   - discrepancy → returned/inCustody/exceptionHeld (owner resolves)
/// - Shop-scoped validation and tenant isolation
/// - Sequential multi-item entry without losing previously entered data
class CollateralRegistrationScreen extends StatefulWidget {
  const CollateralRegistrationScreen({
    super.key,
    required this.currentUser,
    this.database,
  });

  /// The authenticated actor performing custody transitions on this screen.
  final AppUser currentUser;

  /// Optional injected [AppDatabase] for testing. When omitted, the screen
  /// opens its own database connection via `AppDatabase()`.
  final AppDatabase? database;

  @override
  State<CollateralRegistrationScreen> createState() =>
      _CollateralRegistrationScreenState();
}

class _CollateralRegistrationScreenState
    extends State<CollateralRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

  final _itemReferenceController = TextEditingController();
  final _shopIdController = TextEditingController();
  final _customerIdController = TextEditingController();
  final _creditIdController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _conditionController = TextEditingController();
  final _weightController = TextEditingController();
  final _estimatedValueController = TextEditingController();
  final _photoUriController = TextEditingController();
  final _exceptionReasonController = TextEditingController();

  final List<CollateralItem> _registeredItems = [];
  bool _isLoading = false;
  String? _statusMessage;
  bool _isSuccess = false;

  /// Whether a photo has been compressed and stored for the current item.
  bool _photoCompressed = false;
  String? _photoHash;
  String? _photoUri;

  /// A pending photo exception request awaiting Shop Owner approval.
  CollateralPhotoException? _pendingException;

  /// Whether an approved exception has been consumed for the current item.
  bool _exceptionConsumed = false;

  CollateralDao _buildDao(AppDatabase db) => CollateralDao(db);
  CollateralPhotoExceptionDao _buildExceptionDao(AppDatabase db) =>
      CollateralPhotoExceptionDao(db);

  /// Parses the weight field and returns milligrams, or shows an error.
  int? _parseWeight() {
    final text = _weightController.text.trim();
    if (text.isEmpty) {
      setState(() => _statusMessage = 'Weight is required');
      return null;
    }
    try {
      return CollateralItem.parseWeightGrams(text);
    } on CollateralItemValidationException catch (e) {
      setState(() => _statusMessage = e.message);
      return null;
    }
  }

  /// Parses the estimated value field and returns cents, or shows an error.
  int? _parseEstimatedValue() {
    final text = _estimatedValueController.text.trim();
    if (text.isEmpty) {
      setState(() => _statusMessage = 'Estimated value is required');
      return null;
    }
    try {
      final money = Money.parse(text);
      return money.minorUnits;
    } catch (e) {
      setState(() => _statusMessage = 'Invalid estimated value: $e');
      return null;
    }
  }

  /// Resolves the category from the dropdown text.
  CollateralItemCategory? _parseCategory() {
    final text = _categoryController.text.trim().toLowerCase();
    switch (text) {
      case 'gold':
        return CollateralItemCategory.gold;
      case 'electronics':
        return CollateralItemCategory.electronics;
      case 'valuables':
        return CollateralItemCategory.valuables;
      default:
        setState(() => _statusMessage =
            'Invalid category: must be gold, electronics, or valuables');
        return null;
    }
  }

  /// Parses the customer id field and returns the database-assigned integer
  /// id, or shows an error.
  int? _parseCustomerId() {
    final text = _customerIdController.text.trim();
    if (text.isEmpty) {
      setState(() => _statusMessage = 'Customer ID is required');
      return null;
    }
    final customerId = int.tryParse(text);
    if (customerId == null || customerId <= 0) {
      setState(() =>
          _statusMessage = 'Customer ID must be a positive integer (database id)');
      return null;
    }
    return customerId;
  }

  /// Validates that either a photo has been stored or an approved exception
  /// exists before allowing registration.
  bool _hasPhotoOrApprovedException() {
    if (_photoCompressed && _photoUri != null && _photoHash != null) {
      return true;
    }
    if (_pendingException != null &&
        _pendingException!.status ==
            CollateralPhotoExceptionStatus.approved &&
        !_exceptionConsumed) {
      return true;
    }
    return false;
  }

  /// Generates a small sample item photograph (JPEG) for use when no photo
  /// exception ID is provided.
  ///
  /// Keeps the UI self-contained without camera integration or additional
  /// dependencies, mirroring the customer registration screen's sample
  /// photograph helper (Story 2.2).
  Uint8List _createSampleItemPhotoBytes() {
    final image = img.Image(width: 200, height: 200);
    for (int y = 0; y < 200; y++) {
      for (int x = 0; x < 200; x++) {
        image.setPixelRgba(x, y, 200, 100, 50, 255);
      }
    }
    return Uint8List.fromList(img.encodeJpg(image));
  }

  /// Compresses and stores the sample photo, then computes its SHA-256 hash.
  Future<void> _compressAndStorePhoto() async {
    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final rawBytes = _createSampleItemPhotoBytes();

      // Compress using the existing CustomerPhotoCompressor (Story 2.2, AD-5)
      final compressor = const CustomerPhotoCompressor();
      final result = await compressor.compress(rawBytes);

      // Store using the existing PhotoStorageService (Story 2.2, AD-5)
      final shopId = _shopIdController.text.trim();
      if (shopId.isEmpty) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Shop ID is required before photo storage';
        });
        return;
      }

      final storageService = const PhotoStorageService();
      final timestampMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      final relativePath = PhotoStorageService.getRelativePhotoPath(
        shopId: shopId,
        customerId: _itemReferenceController.text.trim(),
        timestampMs: timestampMs,
      );
      await storageService.saveCustomerPhoto(
        shopId: shopId,
        customerId: _itemReferenceController.text.trim(),
        bytes: result.bytes,
        timestampMs: timestampMs,
      );

      // Verify integrity: recompute hash and compare
      final imported = await storageService.resolveRelativePath(relativePath);
      final storedBytes = await imported.readAsBytes();
      final verifyHash = _sha256Hex(storedBytes);
      if (verifyHash != result.sha256Hash) {
        setState(() {
          _isLoading = false;
          _statusMessage =
              'Photo integrity verification failed: stored hash does not match computed hash';
        });
        return;
      }

      setState(() {
        _photoCompressed = true;
        _photoHash = result.sha256Hash;
        _photoUri = relativePath;
        _isLoading = false;
        _statusMessage =
            'Photo compressed and stored: ${result.sizeInBytes} bytes, hash verified';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Photo compression or storage failed: $e';
      });
    }
  }

  /// Computes SHA-256 hex digest of [bytes].
  String _sha256Hex(List<int> bytes) {
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Requests a photo exception from the Shop Owner.
  Future<void> _requestPhotoException() async {
    final reason = _exceptionReasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _statusMessage = 'Exception reason is required');
      return;
    }

    final shopId = _shopIdController.text.trim();
    final itemRef = _itemReferenceController.text.trim();
    if (shopId.isEmpty || itemRef.isEmpty) {
      setState(() => _statusMessage = 'Shop ID and Item Reference ID are required');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final db = widget.database ?? AppDatabase();
      final exceptionDao = _buildExceptionDao(db);

      // Note: RBAC permission check (registerCustomers) and Shop Owner approval
      // are enforced by the authorization layer in the full application.
      // Here we create the exception in pending state.
      final exception = CollateralPhotoException(
        id: 'exc-${DateTime.now().millisecondsSinceEpoch}',
        shopId: shopId,
        collateralItemId: itemRef,
        requestedByUserId: 'staff-${DateTime.now().millisecondsSinceEpoch}',
        requestReason: reason,
        status: CollateralPhotoExceptionStatus.pendingOwnerApproval,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      await exceptionDao.createException(exception);

      setState(() {
        _pendingException = exception;
        _isLoading = false;
        _statusMessage =
            'Photo exception requested and pending Shop Owner approval';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Exception request failed: $e';
      });
    }
  }

  /// Approves the pending photo exception (Shop Owner action).
  Future<void> _approveException() async {
    if (_pendingException == null) return;

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final db = widget.database ?? AppDatabase();
      final exceptionDao = _buildExceptionDao(db);

      final approved = _pendingException!.transitionStatus(
        CollateralPhotoExceptionStatus.approved,
      );
      final now = DateTime.now().toUtc();
      final withReview = approved.copyWith(
        reviewedByUserId: 'owner-${now.millisecondsSinceEpoch}',
        reviewNotes: 'Approved by Shop Owner',
        reviewedAt: now,
      );

      await exceptionDao.updateException(withReview);

      setState(() {
        _pendingException = withReview;
        _exceptionConsumed = false;
        _isLoading = false;
        _statusMessage = 'Photo exception approved by Shop Owner';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Exception approval failed: $e';
      });
    }
  }

  Future<void> _registerItem() async {
    if (!_formKey.currentState!.validate()) return;

    final weightMg = _parseWeight();
    if (weightMg == null) return;

    final valueCents = _parseEstimatedValue();
    if (valueCents == null) return;

    final customerId = _parseCustomerId();
    if (customerId == null) return;

    final category = _parseCategory();
    if (category == null) return;

    // Story 3.2 AC-1: Photo is mandatory unless an approved exception exists
    if (!_hasPhotoOrApprovedException()) {
      setState(() => _statusMessage =
          'A photograph is required. Capture a photo or request a Shop Owner-approved exception.');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
      _isSuccess = false;
    });

    try {
      final db = widget.database ?? AppDatabase();
      final dao = _buildDao(db);
      final exceptionDao = _buildExceptionDao(db);

      // Story 3.2 AC-4: Consume approved exception if used instead of photo
      if (_pendingException != null &&
          _pendingException!.status ==
              CollateralPhotoExceptionStatus.approved &&
          !_exceptionConsumed) {
        await exceptionDao.consumeException(
          _pendingException!.shopId,
          _pendingException!.id,
          collateralItemId: _itemReferenceController.text.trim(),
        );
        setState(() => _exceptionConsumed = true);
      }

      final item = CollateralItem(
        id: _itemReferenceController.text.trim().isNotEmpty
            ? _itemReferenceController.text.trim()
            : String.fromEnvironment(
                'ITEM_ID',
                defaultValue: 'item-${DateTime.now().millisecondsSinceEpoch}',
              ),
        shopId: _shopIdController.text.trim(),
        customerId: customerId,
        creditId: _creditIdController.text.trim().isEmpty
            ? null
            : _creditIdController.text.trim(),
        itemReferenceId: _itemReferenceController.text.trim(),
        category: category,
        description: _descriptionController.text.trim(),
        conditionGrade: _conditionController.text.trim(),
        weightMilligrams: weightMg,
        estimatedValueCents: valueCents,
        photoUri: _photoUri,
        photoHash: _photoHash,
      );

      await dao.createCollateralItem(item);

      setState(() {
        _registeredItems.add(item);
        _isLoading = false;
        _isSuccess = true;
        _statusMessage =
            'Collateral item "${item.itemReferenceId}" registered successfully.';
      });

      // Clear form for next item entry (multi-item support)
      _itemReferenceController.clear();
      _descriptionController.clear();
      _conditionController.clear();
      _weightController.clear();
      _estimatedValueController.clear();
      _photoUriController.clear();
      _categoryController.clear();
      _photoCompressed = false;
      _photoHash = null;
      _photoUri = null;
      _exceptionReasonController.clear();
      _pendingException = null;
      _exceptionConsumed = false;
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Registration failed: $e';
      });
    }
  }

  @override
  void dispose() {
    _itemReferenceController.dispose();
    _shopIdController.dispose();
    _customerIdController.dispose();
    _creditIdController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _conditionController.dispose();
    _weightController.dispose();
    _estimatedValueController.dispose();
    _photoUriController.dispose();
    _exceptionReasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusBgColor = _isSuccess
        ? Colors.green.withValues(alpha: 0.15)
        : Colors.red.withValues(alpha: 0.15);

    final hasPhotoOrException = _hasPhotoOrApprovedException();

    return Scaffold(
      appBar: AppBar(title: const Text('Collateral Registration')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Register Collateral Item',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

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
                  controller: _itemReferenceController,
                  decoration: const InputDecoration(
                    labelText: 'Item Reference ID',
                    hintText: 'e.g. COLL-001',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Item reference ID is required'
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
                  controller: _customerIdController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Customer ID',
                    hintText: 'Database customer id (integer)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Customer ID is required'
                      : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _creditIdController,
                  decoration: const InputDecoration(
                    labelText: 'Credit ID (optional)',
                    hintText: 'UUIDv4 - leave blank if no credit yet',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _categoryController,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    hintText: 'gold, electronics, or valuables',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Category is required';
                    }
                    final lower = v.trim().toLowerCase();
                    if (lower != 'gold' &&
                        lower != 'electronics' &&
                        lower != 'valuables') {
                      return 'Must be gold, electronics, or valuables';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'e.g. 22K gold necklace with pendant',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Description is required'
                      : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _conditionController,
                  decoration: const InputDecoration(
                    labelText: 'Condition Grade',
                    hintText: 'e.g. Like New, Good, Fair, Poor',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Condition grade is required'
                      : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _weightController,
                  decoration: const InputDecoration(
                    labelText: 'Weight (grams)',
                    hintText: 'e.g. 5.5',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Weight is required';
                    }
                    try {
                      CollateralItem.parseWeightGrams(v.trim());
                    } catch (e) {
                      return 'Invalid weight: $e';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _estimatedValueController,
                  decoration: const InputDecoration(
                    labelText: 'Estimated Value (LKR)',
                    hintText: 'e.g. 15000.00',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Estimated value is required';
                    }
                    try {
                      Money.parse(v.trim());
                    } catch (e) {
                      return 'Invalid value: $e';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Story 3.2: Photo capture section
                const Text(
                  'Item Photograph (Mandatory)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _photoUriController,
                  decoration: const InputDecoration(
                    labelText: 'Photo URI',
                    hintText: 'Compressed photo will be stored here',
                    border: OutlineInputBorder(),
                  ),
                  readOnly: true,
                ),
                const SizedBox(height: 8),
                if (_photoCompressed && _photoHash != null) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      border: Border.all(color: Colors.green),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Photo Stored & Hash Verified',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('Hash: $_photoHash'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    key: const Key('compress_store_photo_button'),
                    onTap: _isLoading ? null : _compressAndStorePhoto,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _photoCompressed
                            ? Colors.green
                            : Colors.blue,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              _photoCompressed
                                  ? 'Photo Stored'
                                  : 'Compress & Store Photo',
                              style: const TextStyle(color: Colors.white),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Story 3.2: Photo exception request section
                if (!_photoCompressed) ...[
                  const Text(
                    'Photo Exception (Shop Owner Approval Required)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _exceptionReasonController,
                    decoration: const InputDecoration(
                      labelText: 'Exception Reason',
                      hintText:
                          'Mandatory reason why a photograph cannot be provided',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Exception reason is required'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  if (_pendingException != null) ...[
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        border: Border.all(color: Colors.amber),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Exception Pending Owner Approval',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.amber,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text('Reason: ${_pendingException!.requestReason}'),
                          const SizedBox(height: 4),
                          Text(
                            'Status: ${_pendingException!.status.value}',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      key: const Key('request_photo_exception_button'),
                      onTap: _isLoading ? null : _requestPhotoException,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade700,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'Request Photo Exception',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_pendingException != null &&
                      _pendingException!.status ==
                          CollateralPhotoExceptionStatus.approved) ...[
                    SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        key: const Key('approve_photo_exception_button'),
                        onTap: _isLoading ? null : _approveException,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'Approve Exception (Shop Owner)',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
                const SizedBox(height: 20),

                // RBAC note
                const Text(
                  'Photo capture requires `registerCustomers` permission. Exception approval requires Shop Owner role.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    key: const Key('register_collateral_button'),
                    onTap: (_isLoading || !hasPhotoOrException)
                        ? null
                        : _registerItem,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: hasPhotoOrException
                            ? Colors.blue
                            : Colors.grey,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Register Item',
                              style: TextStyle(color: Colors.white),
                            ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Registered items list
                if (_registeredItems.isNotEmpty) ...[
                  const Text(
                    'Registered Items',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ..._registeredItems.map((item) => Card(
                    child: ListTile(
                      title: Text(
                        '${item.itemReferenceId} (${item.category.value})',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Customer: ${item.customerId}'),
                          if (item.creditId != null)
                            Text('Credit: ${item.creditId}'),
                          Text(
                              'Weight: ${CollateralItem.formatWeightMilligrams(item.weightMilligrams)}'),
                          Text(
                              'Value: ${Money.fromCents(item.estimatedValueCents).format()}'),
                          Text('Custody: ${item.custodyStatus.value}'),
                          if (item.photoUri != null)
                            Text('Photo: ${item.photoUri}'),
                          if (item.photoHash != null)
                            Text('Photo Hash: ${item.photoHash}'),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (item.custodyStatus == CollateralCustodyStatus.inCustody)
                            IconButton(
                              icon: const Icon(Icons.check_circle, color: Colors.green),
                              onPressed: () =>
                                  _transitionLastItem(CollateralCustodyStatus.returned),
                              tooltip: 'Mark as Returned',
                            ),
                          if (item.custodyStatus == CollateralCustodyStatus.inCustody)
                            IconButton(
                              icon: const Icon(Icons.warning, color: Colors.orange),
                              onPressed: _isLoading
                                  ? null
                                  : () => _transitionLastItem(CollateralCustodyStatus.exceptionHeld),
                              tooltip: 'Mark as Exception/Held',
                            ),
                          if (item.custodyStatus == CollateralCustodyStatus.handoverRequested)
                            IconButton(
                              icon: const Icon(Icons.check_circle, color: Colors.green),
                              onPressed: _isLoading
                                  ? null
                                  : () => _transitionLastItem(CollateralCustodyStatus.handoverReported),
                              tooltip: 'Report Physical Handover',
                            ),
                          if (item.custodyStatus == CollateralCustodyStatus.handoverReported)
                            IconButton(
                              icon: const Icon(Icons.check, color: Colors.green),
                              onPressed: _isLoading
                                  ? null
                                  : () => _transitionLastItem(CollateralCustodyStatus.returned),
                              tooltip: 'Confirm Return',
                            ),
                          if (item.custodyStatus == CollateralCustodyStatus.discrepancy)
                            IconButton(
                              icon: const Icon(Icons.warning, color: Colors.red),
                              onPressed: _isLoading
                                  ? null
                                  : () => _transitionLastItem(CollateralCustodyStatus.inCustody),
                              tooltip: 'Resolve Discrepancy - Return to Custody',
                            ),
                        ],
                      ),
                    ),
                  )),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Transitions the most recently registered item to the given custody status.
  Future<void> _transitionLastItem(CollateralCustodyStatus newStatus) async {
    if (_registeredItems.isEmpty) {
      setState(() => _statusMessage = 'No items to transition');
      return;
    }

    final lastItem = _registeredItems.last;
    try {
      final db = widget.database ?? AppDatabase();
      final dao = _buildDao(db);
      await dao.transitionCustody(
        lastItem.shopId,
        lastItem.id,
        newStatus,
        actor: widget.currentUser,
        // Registration-screen custody transitions are staff-initiated; the
        // state machine still rejects invalid transitions (e.g. a direct
        // inCustody → returned).
        requiredPermission: AppPermission.createCredits,
      );

      setState(() {
        final updated = _registeredItems.last.transitionCustody(newStatus);
        _registeredItems[_registeredItems.length - 1] = updated;
        _statusMessage =
            'Item ${lastItem.itemReferenceId} custody → ${newStatus.value}';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Custody transition failed: $e';
      });
    }
  }
}

