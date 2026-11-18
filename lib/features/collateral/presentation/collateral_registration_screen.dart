import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_dao.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';

/// Collateral registration screen (Story 3.4).
///
/// Single-item registration flow: fill in the reference, category, weight
/// (optional) and estimated value, tap "Register Item", and the route closes
/// with the created [CollateralItem] as its result. The calling flow (credit
/// origination) reloads its receipt list and confirms the registration — the
/// confirmation belongs on the landing screen, not on one that has just
/// unmounted.
///
/// - Shop-scoped validation and tenant isolation (tenant resolved from the
///   authenticated [currentUser]; never typed into the form)
/// - Customer and credit ids are resolved automatically: the borrower's
///   customers-table auto-increment id is supplied by the calling flow, and
///   the credit id is auto-generated (UUIDv4) and bound to the items by the
///   credit origination transaction — neither is shown as a form field
class CollateralRegistrationScreen extends StatefulWidget {
  const CollateralRegistrationScreen({
    super.key,
    required this.currentUser,
    required this.customerId,
    this.creditId,
    this.database,
  });

  /// The authenticated actor registering the item.
  final AppUser currentUser;

  /// The borrower this collateral is registered for.
  ///
  /// Resolved by the calling flow from the customers table's auto-increment
  /// primary key (the customer who gets the credit) — never typed into the
  /// form. The customers table assigns the id automatically on insert.
  final int customerId;

  /// Optional credit the item is pledged to.
  ///
  /// Normally `null` at registration time: the credit does not exist yet.
  /// The credit origination transaction auto-generates the credit id
  /// (UUIDv4) and binds the pledged items to it automatically.
  final String? creditId;

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
  final _descriptionController = TextEditingController();
  final _conditionController = TextEditingController();
  final _weightController = TextEditingController();
  final _estimatedValueController = TextEditingController();

  /// Currently selected collateral category (selection tags).
  CollateralItemCategory? _selectedCategory;

  bool _isLoading = false;
  String? _statusMessage;

  CollateralDao _buildDao(AppDatabase db) => CollateralDao(db);

  /// Parses the (optional) weight field.
  ///
  /// Returns `null` when the field is blank (weight is optional). Throws
  /// [CollateralItemValidationException] on invalid input; callers should
  /// catch it and show the message.
  int? _parseWeight() {
    final text = _weightController.text.trim();
    if (text.isEmpty) {
      return null; // Optional: no weight recorded.
    }
    return CollateralItem.parseWeightGrams(text);
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

  /// Returns the trimmed text, or `null` when it is blank. Used for the
  /// optional free-text fields.
  static String? _nullIfBlank(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Resolves the selected category tag, or shows an error when none is
  /// selected.
  CollateralItemCategory? _parseCategory() {
    final category = _selectedCategory;
    if (category == null) {
      setState(() => _statusMessage = 'Category is required');
      return null;
    }
    return category;
  }

  Future<void> _registerItem() async {
    if (!_formKey.currentState!.validate()) return;

    int? weightMg;
    try {
      weightMg = _parseWeight();
    } on CollateralItemValidationException catch (e) {
      setState(() => _statusMessage = e.message);
      return;
    }

    final valueCents = _parseEstimatedValue();
    if (valueCents == null) return;

    final customerId = widget.customerId;
    if (customerId <= 0) {
      setState(
        () => _statusMessage =
            'A valid customer context is required to register collateral',
      );
      return;
    }

    final category = _parseCategory();
    if (category == null) return;

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final db = widget.database ?? AppDatabase();
      final dao = _buildDao(db);

      final item = CollateralItem(
        id: _itemReferenceController.text.trim().isNotEmpty
            ? _itemReferenceController.text.trim()
            : String.fromEnvironment(
                'ITEM_ID',
                defaultValue: 'item-${DateTime.now().millisecondsSinceEpoch}',
              ),
        shopId: widget.currentUser.shopId,
        customerId: customerId,
        creditId: widget.creditId,
        itemReferenceId: _itemReferenceController.text.trim(),
        category: category,
        description: _nullIfBlank(_descriptionController.text),
        conditionGrade: _nullIfBlank(_conditionController.text),
        weightMilligrams: weightMg,
        estimatedValueCents: valueCents,
      );

      await dao.createCollateralItem(item);

      if (!mounted) return;
      // Hand the created receipt back to the caller and close this route; the
      // confirmation belongs on the screen the staff member lands on.
      Navigator.of(context).pop(item);
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
    _descriptionController.dispose();
    _conditionController.dispose();
    _weightController.dispose();
    _estimatedValueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                      color: Colors.red.withValues(alpha: 0.15),
                      border: Border.all(color: Colors.red),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _statusMessage!,
                      style: TextStyle(color: Colors.red.shade800),
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

                const Text(
                  'Category',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: CollateralItemCategory.values
                      .map(
                        (category) => ChoiceChip(
                          key: Key('category_chip_${category.value}'),
                          label: Text(category.label),
                          selected: _selectedCategory == category,
                          onSelected: (_) =>
                              setState(() => _selectedCategory = category),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    hintText: 'e.g. 22K gold necklace with pendant',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _conditionController,
                  decoration: const InputDecoration(
                    labelText: 'Condition Grade (optional)',
                    hintText: 'e.g. Like New, Good, Fair, Poor',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _weightController,
                  decoration: const InputDecoration(
                    labelText: 'Weight (grams, optional)',
                    hintText: 'e.g. 5.5',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final text = v?.trim() ?? '';
                    if (text.isEmpty) return null; // Optional.
                    try {
                      CollateralItem.parseWeightGrams(text);
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
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    key: const Key('register_collateral_button'),
                    onTap: _isLoading ? null : _registerItem,
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
                              'Register Item',
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
