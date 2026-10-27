import 'dart:async';

import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_dao.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_custody_event.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';
import 'package:credit_system/features/collateral/domain/models/loan_administrative_closure.dart';
import 'package:uuid/uuid.dart';

/// Collateral custody return screen (Story 3.4).
///
/// Displays collateral items with their current custody state and drives the
/// per-item physical handover workflow:
///
///   `inCustody` --staff requests return--> `handoverRequested`
///                                --staff reports physical handover-->
///   `handoverRequested` --Shop Owner confirms return--> `returned` (terminal)
///                       --Shop Owner rejects handover--> `inCustody`
///   `inCustody` --staff reports discrepancy--> `discrepancy`
///   `discrepancy` --Shop Owner resolves--> `returned` / `inCustody` / `exceptionHeld`
///
/// Custody transitions and discrepancy resolutions are recorded as immutable
/// custody events / discrepancy records. Authorization is enforced in the
/// underlying DAO operations, not only by hiding buttons:
/// - staff requesting/reporting a handover requires `createLoans`
/// - Shop Owner confirming a return requires `confirmCollateralReturn`
/// - Shop Owner resolving a discrepancy requires `approveCorrections`
///
/// Each item's custody state is independent, even when several items belong
/// to the same loan.
class CollateralCustodyReturnScreen extends StatefulWidget {
  /// The active shop tenant UUID.
  final String shopId;

  /// The currently authenticated actor.
  final AppUser currentUser;

  /// Optional customer scope: only this customer's items are displayed.
  final int? customerId;

  /// Optional loan scope: only this loan's items are displayed.
  final String? loanId;

  /// Optional injected [AppDatabase] for testing.
  final AppDatabase? database;

  const CollateralCustodyReturnScreen({
    super.key,
    required this.shopId,
    required this.currentUser,
    this.customerId,
    this.loanId,
    this.database,
  });

  @override
  State<CollateralCustodyReturnScreen> createState() =>
      _CollateralCustodyReturnScreenState();
}

class _CollateralCustodyReturnScreenState
    extends State<CollateralCustodyReturnScreen> {
  late AppDatabase _db;
  late CollateralDao _collateralDao;

  List<CollateralItem> _items = [];
  LoanAdministrativeClosure? _closure;
  bool _isLoanSettled = false;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _db = widget.database ?? AppDatabase();
    _collateralDao = CollateralDao(_db);
    _loadItems();
  }

  @override
  void dispose() {
    _db.close();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final items = widget.loanId != null
          ? await _collateralDao.getCollateralItemsByLoanId(
              widget.shopId,
              widget.loanId!,
            )
          : widget.customerId != null
              ? await _collateralDao.getCollateralItemsByCustomerId(
                  widget.shopId,
                  widget.customerId!,
                )
              : await _collateralDao.getCollateralItemsByShopId(widget.shopId);

      LoanAdministrativeClosure? closure;
      bool isLoanSettled = false;
      if (widget.loanId != null) {
        closure = await _collateralDao.getAdministrativeClosureByLoanId(
          widget.shopId,
          widget.loanId!,
        );
        isLoanSettled = await _collateralDao.isLoanSettled(
          widget.shopId,
          widget.loanId!,
        );
      }

      if (!mounted) return;

      setState(() {
        _items = items;
        _closure = closure;
        _isLoanSettled = isLoanSettled;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _refresh() async {
    await _loadItems();
  }

  /// Whether the current actor can perform staff-initiated custody actions.
  bool get _canRequestHandover {
    return widget.currentUser.hasPermission(AppPermission.createLoans);
  }

  /// Whether the current actor can perform Shop Owner custody actions.
  /// Confirming or rejecting a return is owner-only even though the
  /// `confirmCollateralReturn` permission is also granted to Managers by
  /// default; the DAO enforces this with `requireOwner: true`.
  bool get _canConfirmReturn {
    return widget.currentUser.role.isOwner &&
        widget.currentUser.hasPermission(AppPermission.confirmCollateralReturn);
  }

  bool get _canResolveDiscrepancy {
    return widget.currentUser.hasPermission(AppPermission.approveCorrections);
  }

  /// Whether the current actor can place an item into Exception / Held.
  /// This is owner-only even though `confirmCollateralReturn` is also held
  /// by Managers; the DAO enforces this via `checkOwnerAdministrativeAction`.
  bool get _canCloseCollateralException {
    return widget.currentUser.role.isOwner;
  }

  /// Whether the Shop Owner can administratively close the loan collateral
  /// account with an exception (Story 3.5, PRD FR-16).
  bool get _canExecuteAdministrativeClosure {
    if (widget.loanId == null) return false;
    if (!widget.currentUser.role.isOwner) return false;
    if (_closure != null) return false;
    if (!_isLoanSettled) return false;
    if (_items.isEmpty) return false;
    final hasException = _items.any(
      (i) => i.custodyStatus == CollateralCustodyStatus.exceptionHeld,
    );
    if (!hasException) return false;
    final allTerminal = _items.every(
      (i) =>
          i.custodyStatus == CollateralCustodyStatus.returned ||
          i.custodyStatus == CollateralCustodyStatus.exceptionHeld,
    );
    return allTerminal;
  }

  Color _custodyColor(CollateralCustodyStatus status) {
    switch (status) {
      case CollateralCustodyStatus.inCustody:
        return Colors.blue;
      case CollateralCustodyStatus.handoverRequested:
        return Colors.amber;
      case CollateralCustodyStatus.handoverReported:
        return Colors.orange;
      case CollateralCustodyStatus.returned:
        return Colors.green;
      case CollateralCustodyStatus.exceptionHeld:
        return Colors.purple;
      case CollateralCustodyStatus.discrepancy:
        return Colors.red;
    }
  }

  /// Shows an error surfaced from a failed operation.
  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(e.toString()),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Shows a short success message.
  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Confirms an action with the actor. Returns true if confirmed.
  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmText,
    Color confirmColor = Colors.green,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: confirmColor),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// Prompts for a mandatory reason. Returns the trimmed reason or null.
  Future<String?> _reasonDialog({
    required String title,
    required String label,
    required String hint,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: label,
                  hintText: hint,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: controller.text.trim().isNotEmpty
                  ? () => Navigator.of(context).pop(controller.text.trim())
                  : null,
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    return result;
  }

  /// Staff requests a return for an item in [inCustody].
  Future<void> _requestReturn(CollateralItem item) async {
    if (!_canRequestHandover) {
      _showError(
        'Access denied: "${AppPermission.createLoans.key}" is required to request a collateral return.',
      );
      return;
    }
    final reason = await _reasonDialog(
      title: 'Request Collateral Return',
      label: 'Reason for return request',
      hint: 'e.g. Customer has settled the loan and is collecting the item',
    );
    if (reason == null || !mounted) return;

    setState(() => _isLoading = true);
    try {
      // Re-fetch to guard against concurrent updates to the same item.
      final current = await _collateralDao.getCollateralItemById(
        widget.shopId,
        item.id,
      );
      if (current == null) {
        _showError('Collateral item no longer exists.');
        return;
      }
      if (current.custodyStatus != CollateralCustodyStatus.inCustody) {
        _showError(
          'Cannot request return: item is no longer in custody (${current.custodyStatus.value}).',
        );
        return;
      }

      await _collateralDao.transitionCustody(
        widget.shopId,
        item.id,
        CollateralCustodyStatus.handoverRequested,
        actor: widget.currentUser,
        requiredPermission: AppPermission.createLoans,
        reason: 'Return requested: $reason',
      );
      _showSuccess('Return request recorded for ${item.itemReferenceId}.');
      await _refresh();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Staff reports the physical handover of an item in [handoverRequested].
  Future<void> _reportHandover(CollateralItem item) async {
    if (!_canRequestHandover) {
      _showError(
        'Access denied: "${AppPermission.createLoans.key}" is required to report a physical handover.',
      );
      return;
    }
    final details = await _reasonDialog(
      title: 'Report Physical Handover',
      label: 'Handover details',
      hint: 'e.g. Handed to customer at counter at 10:15 AM',
    );
    if (details == null || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final current = await _collateralDao.getCollateralItemById(
        widget.shopId,
        item.id,
      );
      if (current == null) {
        _showError('Collateral item no longer exists.');
        return;
      }
      if (current.custodyStatus != CollateralCustodyStatus.handoverRequested) {
        _showError(
          'Cannot report handover: item has not been requested for return (${current.custodyStatus.value}).',
        );
        return;
      }

      await _collateralDao.transitionCustody(
        widget.shopId,
        item.id,
        CollateralCustodyStatus.handoverReported,
        actor: widget.currentUser,
        requiredPermission: AppPermission.createLoans,
        reason: 'Physical handover reported: $details',
      );
      _showSuccess('Physical handover reported for ${item.itemReferenceId}.');
      await _refresh();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Staff cancels a pending return request (handoverRequested → inCustody).
  Future<void> _cancelRequest(CollateralItem item) async {
    if (!_canRequestHandover) {
      _showError(
        'Access denied: "${AppPermission.createLoans.key}" is required to cancel a return request.',
      );
      return;
    }
    final confirmed = await _confirmAction(
      title: 'Cancel Return Request',
      message:
          'Cancel the return request for "${item.itemReferenceId}"? The item remains in shop custody.',
      confirmText: 'Cancel',
      confirmColor: Colors.amber,
    );
    if (!confirmed || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await _collateralDao.transitionCustody(
        widget.shopId,
        item.id,
        CollateralCustodyStatus.inCustody,
        actor: widget.currentUser,
        requiredPermission: AppPermission.createLoans,
        reason: 'Return request cancelled by staff',
      );
      _showSuccess('Return request cancelled for ${item.itemReferenceId}.');
      await _refresh();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Shop Owner confirms a reported physical handover (handoverReported → returned).
  Future<void> _confirmReturn(CollateralItem item) async {
    if (!_canConfirmReturn) {
      _showError(
        'Access denied: only a Shop Owner ("${AppPermission.confirmCollateralReturn.key}") can confirm a collateral return.',
      );
      return;
    }
    final confirmed = await _confirmAction(
      title: 'Confirm Collateral Return',
      message:
          'Confirm the physical return of "${item.itemReferenceId}"? This releases the pledged item to the customer and cannot be undone.',
      confirmText: 'Confirm Return',
      confirmColor: Colors.green,
    );
    if (!confirmed || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final current = await _collateralDao.getCollateralItemById(
        widget.shopId,
        item.id,
      );
      if (current == null) {
        _showError('Collateral item no longer exists.');
        return;
      }
      if (current.custodyStatus != CollateralCustodyStatus.handoverReported) {
        _showError(
          'Cannot confirm return: no physical handover has been reported for this item (${current.custodyStatus.value}).',
        );
        return;
      }

      await _collateralDao.transitionCustody(
        widget.shopId,
        item.id,
        CollateralCustodyStatus.returned,
        actor: widget.currentUser,
        requiredPermission: AppPermission.confirmCollateralReturn,
        requireOwner: true,
        reason:
            'Shop Owner confirmed physical return of collateral item ${item.itemReferenceId}',
      );
      _showSuccess('Return confirmed for ${item.itemReferenceId}.');
      await _refresh();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Shop Owner rejects a reported handover (handoverReported → inCustody).
  Future<void> _rejectHandover(CollateralItem item) async {
    if (!_canConfirmReturn) {
      _showError(
        'Access denied: only a Shop Owner can reject a reported handover.',
      );
      return;
    }
    final notes = await _reasonDialog(
      title: 'Reject Reported Handover',
      label: 'Rejection reason',
      hint: 'e.g. Item condition does not match records; handover not verified',
    );
    if (notes == null || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final current = await _collateralDao.getCollateralItemById(
        widget.shopId,
        item.id,
      );
      if (current == null) {
        _showError('Collateral item no longer exists.');
        return;
      }
      if (current.custodyStatus != CollateralCustodyStatus.handoverReported) {
        _showError(
          'Cannot reject handover: item is not in reported-handover state (${current.custodyStatus.value}).',
        );
        return;
      }

      await _collateralDao.transitionCustody(
        widget.shopId,
        item.id,
        CollateralCustodyStatus.inCustody,
        actor: widget.currentUser,
        requiredPermission: AppPermission.confirmCollateralReturn,
        requireOwner: true,
        reason: 'Shop Owner rejected reported handover: $notes',
      );
      _showSuccess('Handover rejected for ${item.itemReferenceId}; item returned to custody.');
      await _refresh();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Staff reports a discrepancy between system state and physical reality.
  Future<void> _reportDiscrepancy(CollateralItem item) async {
    if (!_canRequestHandover) {
      _showError(
        'Access denied: "${AppPermission.createLoans.key}" is required to report a discrepancy.',
      );
      return;
    }
    if (item.custodyStatus.isTerminal) {
      _showError(
        'Cannot report discrepancy: item is in terminal state "${item.custodyStatus.value}".',
      );
      return;
    }
    final reason = await _reasonDialog(
      title: 'Report Custody Discrepancy',
      label: 'Discrepancy reason',
      hint: 'e.g. System shows item in custody but staff report it was already handed over',
    );
    if (reason == null || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await _collateralDao.reportDiscrepancy(
        widget.shopId,
        item.id,
        widget.currentUser.id,
        reason,
        actor: widget.currentUser,
        requiredPermission: AppPermission.createLoans,
      );
      _showSuccess(
        'Discrepancy reported for ${item.itemReferenceId}; awaiting Shop Owner review.',
      );
      await _refresh();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Shop Owner resolves a pending discrepancy for an item in [discrepancy].
  Future<void> _resolveDiscrepancy(CollateralItem item) async {
    if (!_canResolveDiscrepancy) {
      _showError(
        'Access denied: only a Shop Owner ("${AppPermission.approveCorrections.key}") can resolve a discrepancy.',
      );
      return;
    }

    final decision = await showDialog<CollateralCustodyStatus?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DiscrepancyResolutionDialog(item: item),
    );
    if (decision == null || !mounted) return;

    final notes = await _reasonDialog(
      title: 'Record Discrepancy Resolution',
      label: 'Resolution notes',
      hint: 'e.g. Item located in vault; physical count matches system record',
    );
    if (notes == null || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final now = DateTime.now().toUtc();
      await _collateralDao.resolveDiscrepancy(
        widget.shopId,
        // The discrepancy id is looked up inside resolveDiscrepancy via the item;
        // pass the pending discrepancy for this item.
        await _pendingDiscrepancyId(item.id),
        decision,
        widget.currentUser.id,
        notes,
        now,
        actor: widget.currentUser,
        requiredPermission: AppPermission.approveCorrections,
      );
      _showSuccess(
        'Discrepancy resolved for ${item.itemReferenceId} (${decision.value}).',
      );
      await _refresh();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Shop Owner places an item into Exception / Held with a mandatory
  /// business rationale. Owner-only at the operation layer.
  Future<void> _closeCollateralException(CollateralItem item) async {
    if (!_canCloseCollateralException) {
      _showError(
        'Access denied: only a Shop Owner can place an item into Exception / Held.',
      );
      return;
    }
    final reason = await _reasonDialog(
      title: 'Place Item into Exception / Held',
      label: 'Business rationale',
      hint:
          'e.g. Police seizure, vault theft, or physical condition dispute — item cannot be physically returned',
    );
    if (reason == null || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await _collateralDao.closeCollateralException(
        widget.shopId,
        item.id,
        actor: widget.currentUser,
        reason: reason,
      );
      _showSuccess(
        'Item ${item.itemReferenceId} placed into Exception / Held.',
      );
      await _refresh();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Shop Owner administratively closes the loan-level collateral custody
  /// account with an exception (Story 3.5, PRD FR-16).
  Future<void> _executeAdministrativeClosure() async {
    if (!_canExecuteAdministrativeClosure) return;

    final reason = await _reasonDialog(
      title: 'Close Loan (Collateral Exception)',
      label: 'Mandatory Sign-off Rationale',
      hint:
          'e.g. Police seizure impounded item; remainder returned to borrower. Closing collateral account.',
    );
    if (reason == null || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final idempotencyKey = const Uuid().v4();
      await _collateralDao.executeAdministrativeClosure(
        widget.shopId,
        widget.loanId!,
        actor: widget.currentUser,
        reason: reason,
        idempotencyKey: idempotencyKey,
      );
      _showSuccess('Loan administratively closed with collateral exception.');
      await _refresh();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildClosureBanner() {
    return Container(
      key: const Key('loan_closure_banner'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.purple.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock, color: Colors.purple, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Closed (Collateral Exception)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.purple,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Rationale: ${_closure!.reason}',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            'Closed by owner on ${_closure!.createdAt.toLocal().toString().split('.').first}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildAdministrativeClosureButton() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: ElevatedButton.icon(
        key: const Key('btn_administrative_closure'),
        icon: const Icon(Icons.assignment_turned_in, color: Colors.white),
        label: const Text('Administratively Close Loan (Collateral Exception)'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.purple.shade700,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onPressed: _isLoading ? null : _executeAdministrativeClosure,
      ),
    );
  }

  /// Id of the pending discrepancy for [itemId], if any.
  Future<String> _pendingDiscrepancyId(String itemId) async {
    final discrepancies = await _collateralDao.getDiscrepanciesByCollateralItemId(
      widget.shopId,
      itemId,
    );
    final pending = discrepancies.firstWhere(
      (d) => d.status == CollateralDiscrepancyStatus.pending,
      orElse: () => throw StateError(
        'No pending discrepancy found for collateral item $itemId',
      ),
    );
    return pending.id;
  }

  /// Shows the immutable custody event history for [item].
  void _showHistory(CollateralItem item) {
    showDialog<dynamic>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Custody History - ${item.itemReferenceId}'),
        content: FutureBuilder<List<CollateralCustodyEvent>>(
          future: _collateralDao.getCustodyEventsByCollateralItemId(
            widget.shopId,
            item.id,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final events = snapshot.data ?? const <CollateralCustodyEvent>[];
            if (events.isEmpty) {
              return const Text('No custody events recorded.');
            }
            return SizedBox(
              height: 300,
              child: ListView.builder(
                itemCount: events.length,
                itemBuilder: (context, index) {
                  final event = events[index];
                  return ListTile(
                    dense: true,
                    title: Text(
                      '${event.previousStatus.value} → ${event.newStatus.value}',
                    ),
                    subtitle: Text(
                      'by ${event.reportedByUserId.substring(0, 8)}... '
                          '| ${event.reason} '
                          '| ${event.createdAt.toIso8601String()}',
                    ),
                  );
                },
              ),
            );
          },
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

  /// Action buttons for a single item, scoped to its current custody state.
  Widget _itemActions(CollateralItem item) {
    final buttons = <Widget>[];

    switch (item.custodyStatus) {
      case CollateralCustodyStatus.inCustody:
        if (_canRequestHandover) {
          buttons.add(
            TextButton.icon(
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('Request Return'),
              onPressed: () => _requestReturn(item),
            ),
          );
        }
        if (_canRequestHandover) {
          buttons.add(
            TextButton.icon(
              icon: const Icon(Icons.warning, size: 18, color: Colors.red),
              label: const Text('Report Discrepancy'),
              onPressed: () => _reportDiscrepancy(item),
            ),
          );
        }
        if (_canCloseCollateralException) {
          buttons.add(
            TextButton.icon(
              icon: const Icon(Icons.lock, size: 18, color: Colors.purple),
              label: const Text('Exception / Held'),
              onPressed: () => _closeCollateralException(item),
            ),
          );
        }
        break;
      case CollateralCustodyStatus.handoverRequested:
        if (_canRequestHandover) {
          buttons.add(
            TextButton.icon(
              icon: const Icon(Icons.done, size: 18),
              label: const Text('Report Physical Handover'),
              onPressed: () => _reportHandover(item),
            ),
          );
          buttons.add(
            TextButton.icon(
              icon: const Icon(Icons.cancel, size: 18, color: Colors.amber),
              label: const Text('Cancel Request'),
              onPressed: () => _cancelRequest(item),
            ),
          );
        }
        if (_canRequestHandover) {
          buttons.add(
            TextButton.icon(
              icon: const Icon(Icons.warning, size: 18, color: Colors.red),
              label: const Text('Report Discrepancy'),
              onPressed: () => _reportDiscrepancy(item),
            ),
          );
        }
        break;
      case CollateralCustodyStatus.handoverReported:
        if (_canConfirmReturn) {
          buttons.add(
            TextButton.icon(
              icon: const Icon(Icons.check_circle, size: 18, color: Colors.green),
              label: const Text('Confirm Return'),
              onPressed: () => _confirmReturn(item),
            ),
          );
          buttons.add(
            TextButton.icon(
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Reject Handover'),
              onPressed: () => _rejectHandover(item),
            ),
          );
        }
        if (_canCloseCollateralException) {
          buttons.add(
            TextButton.icon(
              icon: const Icon(Icons.lock, size: 18, color: Colors.purple),
              label: const Text('Exception / Held'),
              onPressed: () => _closeCollateralException(item),
            ),
          );
        }
        if (_canRequestHandover) {
          buttons.add(
            TextButton.icon(
              icon: const Icon(Icons.warning, size: 18, color: Colors.red),
              label: const Text('Report Discrepancy'),
              onPressed: () => _reportDiscrepancy(item),
            ),
          );
        }
        break;
      case CollateralCustodyStatus.discrepancy:
        if (_canResolveDiscrepancy) {
          buttons.add(
            TextButton.icon(
              icon: const Icon(Icons.gavel, size: 18),
              label: const Text('Resolve Discrepancy'),
              onPressed: () => _resolveDiscrepancy(item),
            ),
          );
        }
        break;
      case CollateralCustodyStatus.returned:
      case CollateralCustodyStatus.exceptionHeld:
        // Terminal states — no further actions.
        break;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: buttons,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Collateral Return')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _refresh,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Collateral Return'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _refresh,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Collateral Return - Physical Handover Verification',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Items scoped to shop ${widget.shopId.substring(0, 8)}... '
              '${widget.loanId != null ? 'for loan ${widget.loanId!.substring(0, 8)}...' : widget.customerId != null ? 'for customer ${widget.customerId}' : ''}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            if (_closure != null) _buildClosureBanner(),
            if (_canExecuteAdministrativeClosure)
              _buildAdministrativeClosureButton(),
            if (_items.isEmpty)
              const Center(
                child: Text(
                  'No collateral items found.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            if (_items.isNotEmpty) ...[
              Expanded(
                child: ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final unresolved = item.custodyStatus ==
                        CollateralCustodyStatus.discrepancy;
                    return Card(
                      key: ValueKey(item.id),
                      child: InkWell(
                        onTap: () => _showHistory(item),
                        borderRadius: BorderRadius.circular(8),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${item.itemReferenceId} (${item.category.value})',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        if (item.loanId != null)
                                          Text(
                                            'Loan: ${item.loanId}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        Text(
                                          'Customer: ${item.customerId}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Description: ${item.description}',
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                        Text(
                                          'Condition: ${item.conditionGrade}',
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _custodyColor(
                                              item.custodyStatus,
                                            ).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(
                                              color: _custodyColor(
                                                item.custodyStatus,
                                              ),
                                            ),
                                          ),
                                          child: Text(
                                            'Custody: ${item.custodyStatus.value.replaceAll('_', ' ')}'
                                            '${unresolved ? '  ·  UNRESOLVED DISCREPANCY' : ''}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: _custodyColor(
                                                item.custodyStatus,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Flexible so the action buttons wrap on
                                  // narrow screens instead of overflowing the row.
                                  Flexible(
                                    fit: FlexFit.loose,
                                    child: _itemActions(item),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  'Tap to view custody history',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Dialog through which a Shop Owner decides how to resolve a discrepancy.
class _DiscrepancyResolutionDialog extends StatefulWidget {
  final CollateralItem item;

  const _DiscrepancyResolutionDialog({required this.item});

  @override
  State<_DiscrepancyResolutionDialog> createState() =>
      _DiscrepancyResolutionDialogState();
}

class _DiscrepancyResolutionDialogState
    extends State<_DiscrepancyResolutionDialog> {
  CollateralCustodyStatus? _decision;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Resolve Discrepancy - ${widget.item.itemReferenceId}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Decide the outcome of the discrepancy report for this item:',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.check_circle, color: Colors.green),
            title: const Text('Mark as Returned'),
            subtitle: const Text(
              'Item was physically returned; custody ends.',
            ),
            onTap: () =>
                setState(() => _decision = CollateralCustodyStatus.returned),
          ),
          ListTile(
            leading: const Icon(Icons.inventory, color: Colors.blue),
            title: const Text('Return to Custody'),
            subtitle: const Text(
              'Item remains in shop custody; discrepancy closed.',
            ),
            onTap: () =>
                setState(() => _decision = CollateralCustodyStatus.inCustody),
          ),
          ListTile(
            leading: const Icon(Icons.lock, color: Colors.purple),
            title: const Text('Hold as Exception'),
            subtitle: const Text(
              'Item held pending investigation (exception held).',
            ),
            onTap: () =>
                setState(() => _decision = CollateralCustodyStatus.exceptionHeld),
          ),
          const SizedBox(height: 12),
          if (_decision == null)
            const Text(
              'Select a decision to continue.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _decision == null ? null : () => Navigator.of(context).pop(_decision),
          child: const Text('Resolve'),
        ),
      ],
    );
  }
}
