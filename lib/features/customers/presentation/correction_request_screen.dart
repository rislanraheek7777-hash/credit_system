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

/// Screen for requesting a payment correction (Story 5.5, AC-1).
///
/// Accessible from the payment receipt screen immediately after a payment has
/// been recorded, so the correction always references the actual original
/// payment being corrected. The original payment record is never modified or
/// deleted; the correction request records a mandatory business explanation
/// and activates the correction lock on the credit until a Shop Owner approves
/// or rejects it.
///
/// Only an actor holding [AppPermission.requestCorrections] may submit a
/// request. The correction amount corresponds to the payment amount being
/// corrected, consistent with PRD FR-22 (a reversal adds back the reversed
/// payment amount).
class CorrectionRequestScreen extends StatefulWidget {
  /// The active shop tenant UUID. Derived from the authenticated session,
  /// never trusted from UI input.
  final String shopId;

  /// The credit agreement the corrected payment belongs to.
  final String creditId;

  /// The original erroneous payment being corrected. Must belong to
  /// [creditId] within [shopId]; validated by [CorrectionDao.requestCorrection].
  final String originalPaymentId;

  /// The amount of the original payment being corrected, in integer cents.
  /// Pre-fills the correction amount field.
  final Money paymentAmount;

  /// The authenticated actor submitting the request.
  final AppUser currentUser;

  /// Optional injected [AppDatabase] for testing.
  final AppDatabase? database;

  const CorrectionRequestScreen({
    super.key,
    required this.shopId,
    required this.creditId,
    required this.originalPaymentId,
    required this.paymentAmount,
    required this.currentUser,
    this.database,
  });

  @override
  State<CorrectionRequestScreen> createState() =>
      _CorrectionRequestScreenState();
}

class _CorrectionRequestScreenState extends State<CorrectionRequestScreen> {
  late final CorrectionDao _correctionDao;
  late final CreditDao _creditDao;

  Credit? _credit;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;
  String? _successMessage;

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();

  /// Whether the actor may submit correction requests.
  bool get _canRequestCorrection =>
      widget.currentUser.isActive &&
      widget.currentUser.effectivePermissions
          .contains(AppPermission.requestCorrections);

  /// Whether the credit is eligible for a new correction request (not already
  /// correction-locked).
  bool get _creditEligibleForCorrection =>
      _credit != null && !_credit!.correctionPending;

  @override
  void initState() {
    super.initState();
    final db = widget.database ?? AppDatabase();
    _correctionDao = CorrectionDao(db);
    _creditDao = CreditDao(db);
    // Pre-fill the correction amount with the original payment amount. Per
    // PRD FR-22, the reversal amount is the reversed payment amount.
    _amountController.text = _formatMinorUnits(widget.paymentAmount.minorUnits);
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

  /// Formats integer minor units as a plain decimal number for text input
  /// (e.g. `350000` -> `"3500.00"`), using the project's integer-cents
  /// convention without floating point.
  String _formatMinorUnits(int minorUnits) {
    final absUnits = minorUnits.abs();
    final major = absUnits ~/ 100;
    final cents = absUnits % 100;
    return '${major.toString()}.${cents.toString().padLeft(2, '0')}';
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

  Future<void> _requestCorrection() async {
    final amountInput = _amountController.text.trim();
    final amount = _parseAmount(amountInput);
    if (amount == null) {
      setState(() {
        _error = 'Enter a valid positive correction amount.';
      });
      return;
    }

    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() {
        _error = 'A mandatory business explanation is required.';
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

    if (!_canRequestCorrection) {
      setState(() {
        _error =
            'You do not have the Request Corrections permission.';
      });
      return;
    }

    if (!_creditEligibleForCorrection) {
      setState(() {
        _error =
            'A correction is already pending on this credit. Requests are blocked '
            'until the Shop Owner approves or rejects it.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final idempotencyKey = const Uuid().v4();
      await _correctionDao.requestCorrection(
        actor: widget.currentUser,
        idempotencyKey: idempotencyKey,
        creditId: widget.creditId,
        originalPaymentId: widget.originalPaymentId,
        amount: amount,
        reason: reason,
        requestedAt: DateTime.now().toUtc(),
      );

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _successMessage =
            'Correction requested. The credit is locked pending Shop Owner approval.';
      });
    } on PermissionDeniedException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = e.message;
      });
    } on ArgumentError catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = 'Invalid input: ${e.message}';
      });
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = 'Request failed: $e';
      });
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
        appBar: AppBar(title: const Text('Request Correction')),
        body: Center(child: Text(_error ?? 'Credit not found')),
      );
    }

    final balance = Money.fromCents(credit.balanceCents);
    final canSubmit =
        _canRequestCorrection && _creditEligibleForCorrection && !_isSubmitting;

    return Scaffold(
      appBar: AppBar(title: const Text('Request Correction')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              Text(
                _error!,
                key: const Key('correction_error_display'),
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 12),
            ],
            if (_successMessage != null) ...[
              Text(
                _successMessage!,
                key: const Key('correction_success_display'),
                style: const TextStyle(color: Colors.green),
              ),
              const SizedBox(height: 12),
            ],
            // Payment being corrected context
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Payment being corrected',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Original payment ID: ${widget.originalPaymentId.substring(0, widget.originalPaymentId.length.clamp(0, 8))}...',
                    ),
                    Text(
                      'Amount: ${widget.paymentAmount.format()}',
                    ),
                    Text(
                      'Credit balance: ${balance.format()}',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Correction amount (pre-filled with original payment amount)
            const Text(
              'Correction amount (LKR)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('correction_amount_input'),
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Amount to reverse',
                hintText: 'e.g. 3,500.00',
                border: OutlineInputBorder(),
                helperText: 'Per policy, this is the amount of the original payment being corrected.',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            // Mandatory business reason
            const Text(
              'Business explanation *',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('correction_reason_input'),
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'Explain the error (e.g. entered 35,000 instead of 3,500)',
                hintText: 'Mandatory business explanation',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const Key('request_correction_button'),
                onPressed: canSubmit ? _requestCorrection : null,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Request Correction'),
              ),
            ),
            if (!_canRequestCorrection) ...[
              const SizedBox(height: 8),
              const Text(
                'You do not have the Request Corrections permission.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
            if (_canRequestCorrection && !_creditEligibleForCorrection) ...[
              const SizedBox(height: 8),
              const Text(
                'A correction is already pending on this credit.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

