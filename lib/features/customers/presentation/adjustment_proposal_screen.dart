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

/// Story 5.6: staff-proposed, owner-approved balance adjustment.
///
/// Accessible from the payment/settlement screen (the settle flow) so a
/// customer who cannot pay in full can have part of the outstanding balance
/// proposed for forgiveness before settlement. The proposal is recorded as
/// `pending_approval` and the credit is locked pending Shop Owner review —
/// nothing posts to the ledger until the Shop Owner approves. A Shop Owner
/// may alternatively execute a direct adjustment via the owner-only
/// `adjust_balance` path (PRD FR-22 AC-5, unchanged by this screen).
///
/// Forgiveness is never recorded without owner authorization: a staff actor
/// cannot approve their own proposal, and rejection leaves the balance
/// untouched.
class AdjustmentProposalScreen extends StatefulWidget {
  const AdjustmentProposalScreen({
    super.key,
    required this.shopId,
    required this.creditId,
    required this.currentUser,
    this.database,
  });

  /// The active shop tenant UUID. Derived from the authenticated session,
  /// never trusted from UI input.
  final String shopId;

  /// The credit agreement the proposal targets.
  final String creditId;

  /// The authenticated actor submitting the proposal.
  final AppUser currentUser;

  /// Optional injected [AppDatabase] for testing.
  final AppDatabase? database;

  @override
  State<AdjustmentProposalScreen> createState() =>
      _AdjustmentProposalScreenState();
}

class _AdjustmentProposalScreenState extends State<AdjustmentProposalScreen> {
  late final CorrectionDao _correctionDao;
  late final CreditDao _creditDao;

  Credit? _credit;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  /// `credit` forgives part of the balance; `debit` increases it.
  String _direction = CorrectionDao.directionCredit;

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();

  /// Whether the actor may submit an adjustment proposal.
  bool get _canRequestAdjustment =>
      widget.currentUser.isActive &&
      widget.currentUser.effectivePermissions
          .contains(AppPermission.requestCorrections);

  /// Whether the credit is eligible for a new proposal (disbursed, active or
  /// overdue, positive balance, no pending correction).
  bool get _creditEligibleForAdjustment {
    final credit = _credit;
    if (credit == null) return false;
    return !credit.correctionPending && credit.balanceCents > 0;
  }

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
      final credit =
          await _creditDao.getCreditById(widget.shopId, widget.creditId);
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

    if (!_canRequestAdjustment) {
      setState(() {
        _error =
            'You do not have the Request Corrections permission.';
      });
      return;
    }

    if (!_creditEligibleForAdjustment) {
      setState(() {
        _error = credit.correctionPending
            ? 'A correction is already pending on this credit. Adjustment '
                'requests are blocked until the Shop Owner decides it.'
            : 'This credit is not eligible for a balance adjustment.';
      });
      return;
    }

    if (_direction == CorrectionDao.directionCredit &&
        amount.minorUnits > credit.balanceCents) {
      setState(() {
        _error =
            'The forgiven amount cannot exceed the outstanding balance.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final idempotencyKey = const Uuid().v4();
      await _correctionDao.requestCorrection(
        actor: widget.currentUser,
        idempotencyKey: idempotencyKey,
        creditId: widget.creditId,
        originalPaymentId: null,
        amount: amount,
        reason: reason,
        requestedAt: DateTime.now().toUtc(),
        direction: _direction,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
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
        _error = 'Proposal failed: $e';
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
        appBar: AppBar(title: const Text('Request Balance Adjustment')),
        body: Center(child: Text(_error ?? 'Credit not found')),
      );
    }

    final balance = Money.fromCents(credit.balanceCents);
    final amount = _parseAmount(_amountController.text);
    final rawAfter = _direction == CorrectionDao.directionCredit && amount != null
        ? credit.balanceCents - amount.minorUnits
        : null;
    final afterCents =
        rawAfter != null && rawAfter >= 0 ? rawAfter : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Request Balance Adjustment')),
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

            // Credit summary
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Credit Reference: ${credit.id.substring(0, credit.id.length.clamp(0, 8))}...',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('Outstanding Balance: ${balance.format()}'),
                    Text('Status: ${credit.status.value.toUpperCase()}'),
                    Text(
                      'Workflow: ${credit.workflowStatus.value.toUpperCase()}',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'Adjustment type',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            RadioGroup<String>(
              groupValue: _direction,
              onChanged: (value) {
                if (value != null) setState(() => _direction = value);
              },
              child: Column(
                children: [
                  RadioListTile<String>(
                    key: const Key('adjustment_direction_credit'),
                    title: const Text('Forgive part of the balance'),
                    subtitle: const Text(
                      'The credit balance decreases by the amount (partial '
                      'forgiveness). Nothing posts until the Shop Owner approves.',
                    ),
                    value: CorrectionDao.directionCredit,
                  ),
                  RadioListTile<String>(
                    key: const Key('adjustment_direction_debit'),
                    title: const Text('Increase the balance'),
                    subtitle: const Text(
                      'The credit balance increases by the amount (for example, '
                      'an undercharge). Nothing posts until the Shop Owner approves.',
                    ),
                    value: CorrectionDao.directionDebit,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'Amount',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('adjustment_amount_input'),
              controller: _amountController,
              decoration: InputDecoration(
                labelText: 'Amount (LKR)',
                hintText: 'e.g. 1,500.00',
                border: const OutlineInputBorder(),
                suffixText: 'Max: ${balance.format()}',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
            ),
            if (afterCents != null) ...[
              const SizedBox(height: 8),
              Text(
                key: const Key('adjustment_balance_preview'),
                'Balance after approval: '
                '${Money.fromCents(afterCents).format()}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
            const SizedBox(height: 16),

            const Text(
              'Business explanation (mandatory)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('adjustment_reason_input'),
              controller: _reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Why is this adjustment proposed?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            if (rawAfter != null && rawAfter < 0) ...[
              const Text(
                'The forgiven amount cannot exceed the outstanding balance.',
                style: TextStyle(color: Colors.orange),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const Key('submit_adjustment_button'),
                onPressed: _isSubmitting ? null : _submitAdjustment,
                icon: const Icon(Icons.send),
                label: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Submit for Shop Owner approval'),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'The proposal stays pending until the Shop Owner approves or '
              'rejects it. No adjustment posts to the ledger meanwhile, and '
              'payments on this credit are blocked until the decision.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
