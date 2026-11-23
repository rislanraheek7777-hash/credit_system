import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/errors/monetary_exceptions.dart';
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
/// Accessible from the customer profile credit cards, the payment screen and
/// the settle summary screen (the settle flow) so a customer who cannot pay
/// in full can have part of the outstanding balance proposed for forgiveness
/// before settlement. The proposal is recorded as `pending_approval` and the
/// credit is locked pending Shop Owner review — nothing posts to the ledger
/// until the Shop Owner approves. A Shop Owner may alternatively execute a
/// direct adjustment via the owner-only `adjust_balance` path (PRD FR-22
/// AC-5, unchanged by this screen).
///
/// Two input modes are offered (FR-22, as amended 2026-11-19):
/// - `amount + direction`: the staff member enters the amount and whether the
///   balance increases (`debit`) or decreases (`credit`, partial forgiveness).
/// - `new effective balance`: the staff member enters the balance the credit
///   should carry after approval; the system derives
///   `delta = current balance − desired balance` and posts the proposal with
///   the derived amount and direction (`credit` when the desired balance is
///   lower, `debit` when higher). The same validations apply — an implied
///   over-balance or below-zero result is rejected with the same errors as
///   manual mode.
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

/// Input modes offered by the proposal screen.
enum AdjustmentInputMode {
  /// Enter an amount and pick a direction explicitly.
  amountAndDirection,

  /// Enter the desired new effective balance; the system derives the delta.
  deriveFromBalance,
}

class _AdjustmentProposalScreenState extends State<AdjustmentProposalScreen> {
  late final CorrectionDao _correctionDao;
  late final CreditDao _creditDao;

  Credit? _credit;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  AdjustmentInputMode _mode = AdjustmentInputMode.amountAndDirection;

  /// `credit` forgives part of the balance; `debit` increases it.
  /// Only used in manual mode; derive mode selects the direction from the
  /// sign of the derived delta.
  String _direction = CorrectionDao.directionCredit;

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _newBalanceController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();

  /// Whether the actor may submit an adjustment proposal.
  bool get _canRequestAdjustment =>
      widget.currentUser.isActive &&
      widget.currentUser.effectivePermissions
          .contains(AppPermission.requestCorrections);

  /// Whether the credit is eligible for a new proposal (disbursed, active or
  /// overdue, positive balance, no pending correction). Mirrors
  /// `ReceiptService.isEligibleForPayment` and the DAO gate.
  bool get _creditEligibleForAdjustment {
    final credit = _credit;
    if (credit == null) return false;
    return !credit.correctionPending &&
        credit.isDisbursed &&
        (credit.status == CreditStatus.active ||
            credit.status == CreditStatus.overdue) &&
        credit.balanceCents > 0;
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
    _newBalanceController.dispose();
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
  /// Zero is not accepted here; use [_parseMoneyAllowingZero] for the
  /// derive-delta mode where a zero target balance is legitimate.
  Money? _parseAmount(String input) {
    try {
      final money = Money.parse(input.trim());
      if (!money.isPositive) return null;
      return money;
    } catch (_) {
      return null;
    }
  }

  /// Parses a monetary input that may be zero or negative (the derive-delta
  /// mode reports out-of-range values inline rather than silently).
  Money? _parseMoneyAllowingZero(String input) {
    try {
      return Money.parse(input.trim());
    } on MonetaryException {
      // Malformed input collapses to null by design; anything else is a bug.
      return null;
    }
  }

  /// Whether the submit button must stay disabled because the current inputs
  /// cannot produce a valid proposal. The reason is mirrored inline so a
  /// blocked button always explains itself.
  bool _submitBlocked(Credit credit) {
    // An ineligible credit cannot be proposed against.
    if (!_creditEligibleForAdjustment) return true;
    if (_mode == AdjustmentInputMode.amountAndDirection) {
      final amount = _parseAmount(_amountController.text);
      if (amount == null) return true; // unparseable input
      return _direction == CorrectionDao.directionCredit &&
          amount.minorUnits > credit.balanceCents;
    }
    final desired = _parseMoneyAllowingZero(_newBalanceController.text);
    if (desired == null) return true; // unparseable input
    if (desired.minorUnits < 0) return true; // implied over-balance
    return credit.balanceCents - desired.minorUnits == 0; // no-op delta
  }

  /// A short human explanation for why submit is disabled, or null when the
  /// form is submittable.
  String? _blockedReason(Credit credit) {
    if (!_creditEligibleForAdjustment) {
      return credit.correctionPending
          ? 'An adjustment or correction is already pending on this credit.'
          : 'This credit is not eligible for a balance adjustment.';
    }
    if (_mode == AdjustmentInputMode.amountAndDirection) {
      final amount = _parseAmount(_amountController.text);
      if (amount == null) return 'Enter a valid positive adjustment amount.';
      return _direction == CorrectionDao.directionCredit &&
              amount.minorUnits > credit.balanceCents
          ? 'The forgiven amount cannot exceed the outstanding balance.'
          : null;
    }
    final desired = _parseMoneyAllowingZero(_newBalanceController.text);
    if (desired == null) return 'Enter a valid new effective balance.';
    if (desired.minorUnits < 0) {
      return 'The forgiven amount cannot exceed the outstanding balance.';
    }
    return credit.balanceCents - desired.minorUnits == 0
        ? 'The desired balance equals the current outstanding balance.'
        : null;
  }

  Future<void> _submitAdjustment() async {
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

    // Resolve the effective amount + direction for the active input mode.
    Money? amount;
    var direction = _direction;
    if (_mode == AdjustmentInputMode.amountAndDirection) {
      amount = _parseAmount(_amountController.text);
      if (amount == null) {
        setState(() {
          _error = 'Enter a valid positive adjustment amount.';
        });
        return;
      }
    } else {
      final desired = _parseMoneyAllowingZero(_newBalanceController.text);
      if (desired == null) {
        setState(() {
          _error = 'Enter a valid new effective balance (e.g. 1,500.00).';
        });
        return;
      }
      if (desired.minorUnits < 0) {
        setState(() {
          _error =
              'The forgiven amount cannot exceed the outstanding balance.';
        });
        return;
      }
      final delta = credit.balanceCents - desired.minorUnits;
      if (delta == 0) {
        setState(() {
          _error = 'The desired balance equals the current outstanding '
              'balance — no adjustment is needed.';
        });
        return;
      }
      if (delta > 0) {
        direction = CorrectionDao.directionCredit;
        amount = Money.fromCents(delta);
      } else {
        direction = CorrectionDao.directionDebit;
        amount = Money.fromCents(-delta);
      }
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

    if (direction == CorrectionDao.directionCredit &&
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
        direction: direction,
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
        appBar: AppBar(title: const Text('Settle')),
        body: Center(child: Text(_error ?? 'Credit not found')),
      );
    }

    final balance = Money.fromCents(credit.balanceCents);
    final isAmountMode = _mode == AdjustmentInputMode.amountAndDirection;
    final amount = _parseAmount(_amountController.text);
    final desired = _parseMoneyAllowingZero(_newBalanceController.text);
    final derivedDelta = desired == null ? null : credit.balanceCents - desired.minorUnits;

    // Balance preview after the proposal would be approved, shown for both
    // directions in manual mode and always in derive mode.
    int? afterCents;
    if (isAmountMode && amount != null) {
      afterCents = _direction == CorrectionDao.directionCredit
          ? credit.balanceCents - amount.minorUnits
          : credit.balanceCents + amount.minorUnits;
    } else if (!isAmountMode && desired != null && desired.minorUnits >= 0) {
      afterCents = desired.minorUnits;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Settle')),
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
              'How would you like to enter the adjustment?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              key: const Key('adjustment_input_mode_toggle'),
              spacing: 8,
              children: [
                ChoiceChip(
                  key: const Key('adjustment_mode_amount'),
                  label: const Text('Amount + direction'),
                  avatar: const Icon(Icons.edit_outlined),
                  selected: _mode == AdjustmentInputMode.amountAndDirection,
                  onSelected: (_) => setState(() {
                    _mode = AdjustmentInputMode.amountAndDirection;
                    _error = null;
                  }),
                ),
                ChoiceChip(
                  key: const Key('adjustment_mode_derive'),
                  label: const Text('New effective balance'),
                  avatar: const Icon(Icons.calculate_outlined),
                  selected: _mode == AdjustmentInputMode.deriveFromBalance,
                  onSelected: (_) => setState(() {
                    _mode = AdjustmentInputMode.deriveFromBalance;
                    _error = null;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (isAmountMode) ...[
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
                  suffixText: _direction == CorrectionDao.directionCredit
                      ? 'Max: ${balance.format()}'
                      : null,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
            ] else ...[
              const Text(
                'New effective balance',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('adjustment_new_balance_input'),
                controller: _newBalanceController,
                decoration: InputDecoration(
                  labelText: 'Balance the credit should carry after approval (LKR)',
                  hintText: 'e.g. 1,500.00 (0.00 forgives the whole balance)',
                  border: const OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              const Text(
                'The system derives the adjustment from the current balance: '
                'a lower desired balance posts a forgiveness (credit), a '
                'higher one an increase (debit).',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              if (derivedDelta != null && desired != null && desired.minorUnits >= 0) ...[
                const SizedBox(height: 8),
                Text(
                  key: const Key('adjustment_derived_delta_preview'),
                  derivedDelta == 0
                      ? 'Derived adjustment: none — the desired balance equals '
                          'the current balance.'
                      : 'Derived adjustment: '
                          '${Money.fromCents(derivedDelta.abs()).format()} '
                          '${derivedDelta > 0 ? 'forgiveness (credit)' : 'increase (debit)'}.',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ],

            if (afterCents != null && afterCents >= 0) ...[
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

            if (_blockedReason(credit) != null) ...[
              Text(
                _blockedReason(credit)!,
                key: const Key('adjustment_blocked_reason'),
                style: const TextStyle(color: Colors.orange, fontSize: 12),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const Key('submit_adjustment_button'),
                onPressed: _isSubmitting || _submitBlocked(credit)
                    ? null
                    : _submitAdjustment,
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
