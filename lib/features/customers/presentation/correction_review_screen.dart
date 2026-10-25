import 'dart:async';

import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/core/permissions/authorization_guard.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/correction_dao.dart';
import 'package:credit_system/features/customers/data/daos/loan_dao.dart';
import 'package:uuid/uuid.dart';

/// Screen for Shop Owners to review, approve, or reject pending correction
/// requests (Story 5.5, AC-2, AC-3, AC-4).
///
/// Lists all correction requests awaiting owner decision within the owner's
/// shop tenant. Each pending request can be approved (which records an
/// immutable compensating debit ledger entry and lifts the correction lock)
/// or rejected (which leaves the loan balance unchanged and lifts the lock).
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
  late final LoanDao _loanDao;
  late final AppDatabase _db;

  List<LoanCorrection> _pending = <LoanCorrection>[];
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
    _loanDao = LoanDao(_db);
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
        LoanCorrectionStatus.pendingApproval.value,
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
  Future<void> _confirmApprove(LoanCorrection correction) async {
    final loan = await _loanDao.getLoanById(widget.shopId, correction.loanId);
    final preBalance = loan?.balanceCents ?? 0;
    final postBalance = preBalance + correction.correctionAmountCents;
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
              Text(
                'Post an immutable compensating debit of '
                '${Money.fromCents(correction.correctionAmountCents).format()} '
                'referencing the original payment.',
              ),
              Text(
                'Recalculate the loan balance from '
                '${Money.fromCents(preBalance).format()} to '
                '${Money.fromCents(postBalance).format()}.',
              ),
              Text('Permanently preserve the original erroneous payment.'),
              Text('Lift the correction lock on the loan.'),
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
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _approveCorrection(correction);
  }

  /// Shows a confirmation dialog requiring a non-empty rejection reason and,
  /// if confirmed, rejects [correction].
  Future<void> _confirmReject(LoanCorrection correction) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
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
              Text(
                'Leave the loan balance unchanged '
                '${Money.fromCents(correction.resultingBalanceCents ?? 0).format()}.',
              ),
              Text('Permanently preserve the original erroneous payment.'),
              Text('Lift the correction lock on the loan.'),
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
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('Reject'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await _rejectCorrection(correction, reasonController.text.trim());
  }

  Future<void> _approveCorrection(LoanCorrection correction) async {
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
        _successMessage =
            'Correction approved. Compensating debit posted and lock lifted.';
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
    LoanCorrection correction,
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
        _successMessage =
            'Correction rejected. Balance unchanged and lock lifted.';
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
                          'Loan ${correction.loanId.substring(0, correction.loanId.length.clamp(0, 8))}...',
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
              'staff for loans in your shop. Approving records a compensating '
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
