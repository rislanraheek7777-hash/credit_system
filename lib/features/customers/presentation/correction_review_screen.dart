import 'dart:async';

import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/core/permissions/authorization_guard.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/correction_dao.dart';
import 'package:credit_system/features/customers/data/daos/credit_dao.dart';
import 'package:uuid/uuid.dart';

/// Screen for Shop Owners to review, approve, or reject pending correction
/// requests (Story 5.5, AC-2, AC-3, AC-4).
///
/// Lists all correction requests awaiting owner decision within the owner's
/// shop tenant. Each pending request can be approved (which records an
/// immutable compensating debit ledger entry and lifts the correction lock)
/// or rejected (which leaves the credit balance unchanged and lifts the lock).
/// All financial effects are performed by the existing [CorrectionDao] methods
/// inside atomic transactions; this screen never alters balances or ledger
/// entries directly.
///
/// Only an authenticated Shop Owner may access this screen; the DAO
/// re-validates ownership on every decision, so hiding the UI is not the only
/// access control.
class CorrectionReviewScreen extends StatefulWidget {
  /// The active shop tenant UUID. Derived from the authenticated session,
  /// never trusted from UI input.
  final String shopId;

  /// The authenticated Shop Owner reviewing corrections.
  final AppUser currentUser;

  /// Optional injected [AppDatabase] for testing.
  final AppDatabase? database;

  const CorrectionReviewScreen({
    super.key,
    required this.shopId,
    required this.currentUser,
    this.database,
  });

  @override
  State<CorrectionReviewScreen> createState() => _CorrectionReviewScreenState();
}

class _CorrectionReviewScreenState extends State<CorrectionReviewScreen> {
  late final CorrectionDao _correctionDao;
  late final CreditDao _creditDao;
  late final AppDatabase _db;

  List<CreditCorrection> _pending = <CreditCorrection>[];
  Map<String, PaymentEntry?> _payments = <String, PaymentEntry?>{};
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;
  String? _successMessage;

  /// Whether the actor is a Shop Owner authorized to review corrections.
  ///
  /// Only Shop Owner holds `approveCorrections` by default, and the DAO's
  /// [AuthorizationGuard.checkOwnerAdministrativeAction] re-enforces the
  /// owner-role check on every decision, so hiding the UI is not the only
  /// access control.
  bool get _canReviewCorrections =>
      widget.currentUser.isActive &&
      widget.currentUser.role == AppRole.shopOwner &&
      widget.currentUser.effectivePermissions.contains(
        AppPermission.approveCorrections,
      );

  @override
  void initState() {
    super.initState();
    _db = widget.database ?? AppDatabase();
    _correctionDao = CorrectionDao(_db);
    _creditDao = CreditDao(_db);
    _load();
  }

  /// Loads pending correction requests for the shop, strictly shop-scoped so
  /// another shop's requests are never exposed.
  Future<void> _load() async {
    if (!_canReviewCorrections) {
      setState(() {
        _isLoading = false;
        _error = 'You do not have permission to review corrections.';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final pending = await _correctionDao.getCorrectionsByStatus(
        widget.shopId,
        CreditCorrectionStatus.pendingApproval.value,
      );
      final paymentsMap = <String, PaymentEntry?>{};
      for (final c in pending) {
        if (c.originalPaymentId != null) {
          final payment = await (_db.select(_db.payments)
                ..where((p) => p.shopId.equals(widget.shopId))
                ..where((p) => p.id.equals(c.originalPaymentId!)))
              .getSingleOrNull();
          paymentsMap[c.id] = payment;
        }
      }
      if (!mounted) return;
      setState(() {
        _pending = pending;
        _payments = paymentsMap;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load correction queue: $e';
      });
    }
  }

  /// Reloads the queue after a decision so approved/rejected items disappear.
  Future<void> _refresh() async => _load();

  /// Shows a confirmation dialog and, if confirmed, approves [correction].
  /// The dialog explains the financial effect before committing.
  Future<void> _confirmApprove(CreditCorrection correction) async {
    final credit = await _creditDao.getCreditById(widget.shopId, correction.creditId);
    final preBalance = credit?.balanceCents ?? 0;
    final isAdjustment = correction.originalPaymentId == null;
    final isForgiveness = correction.direction == 'credit';
    final delta =
        isForgiveness ? -correction.correctionAmountCents : correction.correctionAmountCents;
    final postBalance = preBalance + delta;
    final negativePostBalance = postBalance < 0;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Approve Correction Request'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Approving this correction will:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              isAdjustment
                  ? Text(
                      isForgiveness
                          ? 'Post an immutable adjustment credit '
                              '(partial forgiveness) of '
                              '${Money.fromCents(correction.correctionAmountCents).format()}.'
                          : 'Post an immutable adjustment debit of '
                              '${Money.fromCents(correction.correctionAmountCents).format()}.',
                    )
                  : Text(
                      'Post an immutable compensating debit of '
                      '${Money.fromCents(correction.correctionAmountCents).format()} '
                      'referencing the original payment.',
                    ),
              Text(
                negativePostBalance
                    ? 'The credit balance cannot become negative.'
                    : 'Recalculate the credit balance from '
                        '${Money.fromCents(preBalance).format()} to '
                        '${Money.fromCents(postBalance).format()}.',
              ),
              if (negativePostBalance) ...[
                const SizedBox(height: 8),
                const Text(
                  'The approval cannot be completed: the post-approval balance '
                  'would be negative. The outstanding balance changed after '
                  'this proposal was raised.',
                  key: Key('review_negative_balance_warning'),
                  style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                ),
              ],
              correction.originalPaymentId == null
                  ? const SizedBox(height: 8)
                  : const Text('Permanently preserve the original erroneous payment.'),
              Text('Lift the correction lock on the credit.'),
              const SizedBox(height: 12),
              const Text(
                'This action cannot be undone.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('review_approve_confirm_button'),
            // Disabled when the approval cannot be executed (negative
            // post-balance) — the same guard the DAO enforces.
            onPressed: negativePostBalance
                ? null
                : () => Navigator.of(dialogContext).pop(true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _approveCorrection(correction);
  }

  /// Shows a confirmation dialog requiring a non-empty rejection reason and,
  /// if confirmed, rejects [correction]. The confirm button stays disabled
  /// until the reason is non-blank.
  Future<void> _confirmReject(CreditCorrection correction) async {
    final reasonController = TextEditingController();
    var reasonIsNonEmpty = false;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Reject Correction Request'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Rejecting this correction will:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Leave the credit balance outstanding (unchanged).',
              ),
              correction.originalPaymentId == null
                  ? const SizedBox(height: 8)
                  : const Text('Permanently preserve the original erroneous payment.'),
              Text('Lift the correction lock on the credit.'),
              const SizedBox(height: 16),
              const Text(
                'Rejection reason *',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('review_reject_reason_input'),
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Mandatory rejection reason',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                onChanged: (value) =>
                    setDialogState(() => reasonIsNonEmpty = value.trim().isNotEmpty),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    key: const Key('review_reject_confirm_button'),
                    onPressed: reasonIsNonEmpty
                        ? () => Navigator.of(dialogContext).pop(true)
                        : null,
                    child: const Text('Reject'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    );
    // Note: the TextEditingController is intentionally kept for the
    // dialog's lifetime here — disposing it synchronously breaks the
    // dismissal animation (it is used by the exiting subtree). One
    // controller per dialog open is negligible.
    if (confirmed != true || !mounted) return;
    await _rejectCorrection(correction, reasonController.text.trim());
  }

  Future<void> _approveCorrection(CreditCorrection correction) async {
    setState(() {
      _isSubmitting = true;
      _error = null;
      _successMessage = null;
    });
    try {
      await _correctionDao.approveCorrection(
        actor: widget.currentUser,
        idempotencyKey: const Uuid().v4(),
        correctionId: correction.id,
        reviewedAt: DateTime.now().toUtc(),
      );
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _successMessage = correction.originalPaymentId == null
            ? 'Adjustment approved. Ledger entry posted and lock lifted.'
            : 'Correction approved. Compensating debit posted and lock lifted.';
      });
      await _refresh();
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
        _error = 'Approval failed: $e';
      });
    }
  }

  Future<void> _rejectCorrection(
    CreditCorrection correction,
    String rejectionReason,
  ) async {
    setState(() {
      _isSubmitting = true;
      _error = null;
      _successMessage = null;
    });
    try {
      await _correctionDao.rejectCorrection(
        actor: widget.currentUser,
        idempotencyKey: const Uuid().v4(),
        correctionId: correction.id,
        rejectionReason: rejectionReason,
        reviewedAt: DateTime.now().toUtc(),
      );
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _successMessage = correction.originalPaymentId == null
            ? 'Adjustment rejected. Balance unchanged and lock lifted.'
            : 'Correction rejected. Balance unchanged and lock lifted.';
      });
      await _refresh();
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
        _error = 'Rejection failed: $e';
      });
    }
  }

  /// Builds one [Card] per pending correction request, showing review details
  /// and approve/reject actions.
  List<Widget> _buildCorrectionCards(bool canSubmit) {
    return _pending.map((correction) {
      final payment = _payments[correction.id];
      return Card(
        key: Key('review_correction_${correction.id}'),
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Credit ${correction.creditId.substring(0, correction.creditId.length.clamp(0, 8))}...',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Requested by: ${correction.requestedByUserId.substring(0, correction.requestedByUserId.length.clamp(0, 8))}...',
                        ),
                        Text(
                          'Requested: '
                          '${correction.createdAt.toUtc().toIso8601String()}',
                        ),
                        Text(
                          'Type: ${correction.originalPaymentId == null ? (correction.direction == 'credit' ? 'Adjustment proposal (forgiveness)' : 'Adjustment proposal (increase)') : 'Payment correction'}',
                        ),
                        Text(
                          'Correction amount: '
                          '${Money.fromCents(correction.correctionAmountCents).format()}',
                        ),
                        Text('Reason: ${correction.reason}'),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (payment != null) ...[
                        Text(
                          'Original payment: '
                          '${payment.receiptNumber.substring(0, payment.receiptNumber.length.clamp(0, 8))}...',
                        ),
                        Text(
                          'Paid: ${Money.fromCents(payment.amountCents).format()}',
                        ),
                        const SizedBox(height: 8),
                      ],
                      SizedBox(
                        width: 120,
                        child: ElevatedButton(
                          key: Key('review_approve_${correction.id}'),
                          onPressed: canSubmit
                              ? () => _confirmApprove(correction)
                              : null,
                          child: const Text('Approve'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 120,
                        child: OutlinedButton(
                          key: Key('review_reject_${correction.id}'),
                          onPressed: canSubmit
                              ? () => _confirmReject(correction)
                              : null,
                          child: const Text('Reject'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review Corrections')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final canSubmit = _canReviewCorrections && !_isSubmitting;

    return Scaffold(
      appBar: AppBar(title: const Text('Review Corrections')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_successMessage != null) ...[
              Text(
                _successMessage!,
                key: const Key('review_success_display'),
                style: const TextStyle(color: Colors.green),
              ),
              const SizedBox(height: 12),
            ],
            // Header explaining the queue.
            const Text(
              'Pending Correction Requests',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Review and decide on correction requests raised by counter '
              'staff for credits in your shop. Approving records a compensating '
              'debit and adjusts the balance; rejecting leaves the balance '
              'unchanged. In both cases the correction lock is lifted.',
            ),
            const SizedBox(height: 16),
            if (!_canReviewCorrections) ...[
              const Text(
                'You do not have permission to review corrections.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ] else if (_pending.isEmpty) ...[
              const Text(
                'No pending correction requests.',
                style: TextStyle(color: Colors.grey),
              ),
            ] else ...[
              ..._buildCorrectionCards(canSubmit),
            ],
            if (_isSubmitting) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}

