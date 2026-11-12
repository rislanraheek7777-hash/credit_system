import 'dart:async';

import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/core/permissions/authorization_guard.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/correction_dao.dart';
import 'package:credit_system/features/customers/data/daos/credit_dao.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:uuid/uuid.dart';

/// Screen for Shop Owner manual balance adjustments (Story 5.5, AC-5).
///
/// Allows a Shop Owner to manually increase or decrease a credit's outstanding
/// balance by an integer-cents amount with a mandatory business rationale.
/// Adjustments are recorded as immutable ledger entries; the original payment
/// history is never altered. All financial effects go through
/// [CorrectionDao.adjustBalance] inside an atomic transaction.
///
/// Only an authenticated Shop Owner may access this screen; the DAO
/// re-validates ownership on every adjustment.
class CorrectionAdjustmentScreen extends StatefulWidget {
  /// The active shop tenant UUID. Derived from the authenticated session,
  /// never trusted from UI input.
  final String shopId;

  /// The credit agreement to adjust.
  final String creditId;

  /// The authenticated Shop Owner submitting the adjustment.
  final AppUser currentUser;

  /// Optional injected [AppDatabase] for testing.
  final AppDatabase? database;

  const CorrectionAdjustmentScreen({
    super.key,
    required this.shopId,
    required this.creditId,
    required this.currentUser,
    this.database,
  });

  @override
  State<CorrectionAdjustmentScreen> createState() =>
      _CorrectionAdjustmentScreenState();
}

class _CorrectionAdjustmentScreenState
    extends State<CorrectionAdjustmentScreen> {
  late final CorrectionDao _correctionDao;
  late final CreditDao _creditDao;

  Credit? _credit;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;
  String? _successMessage;

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();

  CreditLedgerEntryType? _selectedAdjustmentType;

  /// Whether the actor may submit balance adjustments.
  bool get _canAdjustBalance =>
      widget.currentUser.isActive &&
      widget.currentUser.role == AppRole.shopOwner &&
      widget.currentUser.effectivePermissions
          .contains(AppPermission.approveCorrections);

  /// Whether the credit exists, is in this shop, and is not correction-locked.
  bool get _creditEligibleForAdjustment =>
      _credit != null &&
      _credit!.shopId == widget.shopId &&
      !_credit!.correctionPending;

  @override
  void initState() {
    super.initState();
    final db = widget.database ?? AppDatabase();
    _correctionDao = CorrectionDao(db);
    _creditDao = CreditDao(db);
    _load();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final credit = await _creditDao.getCreditById(widget.shopId, widget.creditId);
      if (!mounted) return;
      setState(() {
        _credit = credit;
        _isLoading = false;
        _error = credit == null ? 'Credit agreement not found' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load credit: $e';
      });
    }
  }

  /// Parses the amount input and returns [Money] or null if invalid.
  Money? _parseAmount(String input) {
    try {
      final money = Money.parse(input.trim());
      if (!money.isPositive) return null;
      return money;
    } catch (_) {
      return null;
    }
  }

  Future<void> _submitAdjustment() async {
    final amountInput = _amountController.text.trim();
    final amount = _parseAmount(amountInput);
    if (amount == null) {
      setState(() {
        _error = 'Enter a valid positive adjustment amount.';
      });
      return;
    }

    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() {
        _error = 'A mandatory business rationale is required.';
      });
      return;
    }

    if (_selectedAdjustmentType == null) {
      setState(() {
        _error = 'Select a debit or credit adjustment type.';
      });
      return;
    }

    final credit = _credit;
    if (credit == null) {
      setState(() {
        _error = 'Credit agreement not found.';
      });
      return;
    }

    if (!_canAdjustBalance) {
      setState(() {
        _error = 'You do not have permission to adjust credit balances.';
      });
      return;
    }

    if (!_creditEligibleForAdjustment) {
      setState(() {
        _error =
            'A correction is pending on this credit. Balance adjustments are '
            'blocked until the correction is approved or rejected.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
      _successMessage = null;
    });

    try {
      await _correctionDao.adjustBalance(
        actor: widget.currentUser,
        idempotencyKey: const Uuid().v4(),
        creditId: widget.creditId,
        amount: amount,
        adjustmentType: _selectedAdjustmentType!,
        reason: reason,
        recordedAt: DateTime.now().toUtc(),
      );

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _successMessage =
            'Adjustment applied. New balance: '
            '${Money.fromCents(_adjustedBalance(_credit!, amount)).format()}';
      });
    } on PermissionDeniedException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = 'Adjustment failed: $e';
      });
    }
  }

  /// Computes the post-adjustment balance for display in the confirmation.
  int _adjustedBalance(Credit credit, Money amount) {
    switch (_selectedAdjustmentType) {
      case CreditLedgerEntryType.adjustmentDebit:
        return credit.balanceCents + amount.minorUnits;
      case CreditLedgerEntryType.adjustmentCredit:
        return credit.balanceCents - amount.minorUnits;
      case CreditLedgerEntryType.compensatingDebit:
      case null:
        return credit.balanceCents;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final credit = _credit;
    if (credit == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Adjust Balance')),
        body: Center(child: Text(_error ?? 'Credit not found')),
      );
    }

    final balance = Money.fromCents(credit.balanceCents);
    final canSubmit =
        _canAdjustBalance &&
        _creditEligibleForAdjustment &&
        !_isSubmitting &&
        _selectedAdjustmentType != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Adjust Balance')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              Text(
                _error!,
                key: const Key('adjustment_error_display'),
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 12),
            ],
            if (_successMessage != null) ...[
              Text(
                _successMessage!,
                key: const Key('adjustment_success_display'),
                style: const TextStyle(color: Colors.green),
              ),
              const SizedBox(height: 12),
            ],
            // Credit context
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Credit agreement',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Credit ID: ${credit.id.substring(0, credit.id.length.clamp(0, 8))}...',
                    ),
                    Text('Outstanding balance: ${balance.format()}'),
                    if (credit.correctionPending)
                      const Text(
                        'Correction pending — adjustments blocked.',
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Adjustment type
            const Text(
              'Adjustment type',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _adjustmentTypeChip(
                  CreditLedgerEntryType.adjustmentDebit,
                  'Debit',
                  'Increase balance',
                  _canAdjustBalance && _creditEligibleForAdjustment &&
                      !_isSubmitting,
                ),
                const SizedBox(width: 12),
                _adjustmentTypeChip(
                  CreditLedgerEntryType.adjustmentCredit,
                  'Credit',
                  'Decrease balance',
                  _canAdjustBalance && _creditEligibleForAdjustment &&
                      !_isSubmitting,
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Adjustment amount
            const Text(
              'Amount (LKR)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('adjustment_amount_input'),
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Adjustment amount',
                hintText: 'e.g. 500.00',
                border: OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            // Business rationale
            const Text(
              'Business rationale *',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('adjustment_reason_input'),
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for adjustment',
                hintText: 'e.g. rounding reconciliation',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            if (_canAdjustBalance) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  key: const Key('adjustment_submit_button'),
                  onPressed: canSubmit ? _submitAdjustment : null,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Apply Adjustment'),
                ),
              ),
            ],
            if (!_canAdjustBalance) ...[
              const SizedBox(height: 8),
              const Text(
                'You do not have permission to adjust credit balances.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
            if (_canAdjustBalance && !_creditEligibleForAdjustment) ...[
              const SizedBox(height: 8),
              const Text(
                'Adjustments are blocked while a correction is pending.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// A selectable adjustment type chip.
  Widget _adjustmentTypeChip(
    CreditLedgerEntryType type,
    String label,
    String subtitle,
    bool canSubmit,
  ) {
    final isSelected = _selectedAdjustmentType == type;
    return ChoiceChip(
      key: Key('adjustment_type_${type.value}'),
      label: Text(label),
      selected: isSelected,
      onSelected: canSubmit
          ? (_) => setState(() => _selectedAdjustmentType = type)
          : null,
      avatar: Text(
        type == CreditLedgerEntryType.adjustmentDebit ? '+' : '-',
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.black54,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

