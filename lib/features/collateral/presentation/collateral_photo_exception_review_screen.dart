import 'dart:async';

import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/permissions/authorization_guard.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_dao.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_photo_exception_dao.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_photo_exception.dart';

/// Shop Owner review screen for collateral photo exception requests (Story 3.3).
///
/// Displays pending photo exception requests strictly scoped to the active shop
/// tenant, with associated collateral item details. Only Shop Owners may access
/// this screen or approve/reject requests — enforcement is via
/// [AuthorizationGuard] in action handlers, not merely by hiding buttons.
///
/// Approving a request transitions status to `approved` and records the Shop
/// Owner actor, decision timestamp, and decision notes. The approval waives the
/// mandatory-photo requirement but does NOT indicate that a photograph was
/// captured. Rejecting requires a mandatory rejection reason and leaves the
/// collateral item subject to the mandatory-photo rule.
///
/// All decisions persist in local Drift SQLite; the original request record is
/// never deleted or overwritten — decisions append to the record via
/// [CollateralPhotoExceptionDao.updateException].
class CollateralPhotoExceptionReviewScreen extends StatefulWidget {
  /// The active shop tenant UUID.
  final String shopId;

  /// The currently authenticated actor (must be an active Shop Owner).
  final AppUser currentUser;

  /// Optional injected [AppDatabase] for testing.
  final AppDatabase? database;

  const CollateralPhotoExceptionReviewScreen({
    super.key,
    required this.shopId,
    required this.currentUser,
    this.database,
  });

  @override
  State<CollateralPhotoExceptionReviewScreen> createState() =>
      _CollateralPhotoExceptionReviewScreenState();
}

class _CollateralPhotoExceptionReviewScreenState
    extends State<CollateralPhotoExceptionReviewScreen> {
  late AppDatabase _db;
  late CollateralPhotoExceptionDao _exceptionDao;
  late CollateralDao _collateralDao;

  List<CollateralPhotoException> _exceptions = [];
  Map<String, CollateralItem> _itemsById = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _db = widget.database ?? AppDatabase();
    _exceptionDao = CollateralPhotoExceptionDao(_db);
    _collateralDao = CollateralDao(_db);
    _loadExceptions();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadExceptions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Enforce Shop Owner authorization — not just UI hiding.
      AuthorizationGuard.checkOwnerAdministrativeAction(
        isActive: widget.currentUser.isActive,
        actorRole: widget.currentUser.role,
        actionDescription: 'view collateral photo exception reviews',
      );

      final exceptions = await _exceptionDao.getPendingExceptions(
        widget.shopId,
      );

      // Pre-load all collateral items for the exceptions to avoid per-item
      // async lookups during build.
      final itemsById = <String, CollateralItem>{};
      for (final exception in exceptions) {
        final item = await _collateralDao.getCollateralItemById(
          widget.shopId,
          exception.collateralItemId,
        );
        if (item != null) {
          itemsById[exception.collateralItemId] = item;
        }
      }

      if (!mounted) return;

      setState(() {
        _exceptions = exceptions;
        _itemsById = itemsById;
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
    await _loadExceptions();
  }

  /// Approves a pending exception request. Requires confirmation via dialog.
  Future<void> _approveException(CollateralPhotoException exception) async {
    final confirmed = await _showConfirmDialog(
      title: 'Approve Photo Exception',
      message:
          'Approve this photo exception request? This waives the mandatory '
          'photo requirement for collateral item "${exception.collateralItemId}" '
          'but does not indicate that a photograph was captured.',
      confirmText: 'Approve',
      confirmColor: Colors.green,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Re-fetch to ensure we have the latest state (prevents concurrent updates).
      final current = await _exceptionDao.getExceptionById(
        widget.shopId,
        exception.id,
      );
      if (current == null) {
        setState(() => _error = 'Exception request no longer exists.');
        return;
      }
      if (current.status != CollateralPhotoExceptionStatus.pendingOwnerApproval) {
        setState(() => _error =
            'Cannot approve: request is no longer pending (status: ${current.status.value}).');
        return;
      }

      final now = DateTime.now().toUtc();
      final approved = current.transitionStatus(
        CollateralPhotoExceptionStatus.approved,
      );
      final withReview = approved.copyWith(
        reviewedByUserId: widget.currentUser.id,
        reviewNotes: 'Approved by Shop Owner',
        reviewedAt: now,
      );

      await _exceptionDao.updateException(withReview);

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = null;
      });
      await _refresh();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo exception approved.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Approval failed: $e';
      });
    }
  }

  /// Rejects a pending exception request. Requires a rejection reason and confirmation.
  Future<void> _rejectException(CollateralPhotoException exception) async {
    final rejectionReason = await _showRejectionReasonDialog();
    if (rejectionReason == null || !mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Re-fetch to ensure we have the latest state (prevents concurrent updates).
      final current = await _exceptionDao.getExceptionById(
        widget.shopId,
        exception.id,
      );
      if (current == null) {
        setState(() => _error = 'Exception request no longer exists.');
        return;
      }
      if (current.status != CollateralPhotoExceptionStatus.pendingOwnerApproval) {
        setState(() => _error =
            'Cannot reject: request is no longer pending (status: ${current.status.value}).');
        return;
      }

      final now = DateTime.now().toUtc();
      final rejected = current.transitionStatus(
        CollateralPhotoExceptionStatus.rejected,
      );
      final withReview = rejected.copyWith(
        reviewedByUserId: widget.currentUser.id,
        reviewNotes: rejectionReason.trim(),
        reviewedAt: now,
      );

      await _exceptionDao.updateException(withReview);

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = null;
      });
      await _refresh();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo exception rejected.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Rejection failed: $e';
      });
    }
  }

  /// Shows a confirmation dialog. Returns true if confirmed.
  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmText,
    required Color confirmColor,
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

  /// Shows a rejection reason dialog. Returns the reason string or null if cancelled.
  Future<String?> _showRejectionReasonDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Reject Photo Exception'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'A mandatory rejection reason is required. This documents why '
              'the photo exception was denied and leaves the collateral item '
              'subject to the mandatory-photo rule.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Rejection reason',
                hintText: 'e.g. Photo can be provided; customer has camera access',
                border: OutlineInputBorder(),
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
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.of(context).pop(controller.text.trim());
              }
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    return result;
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
        appBar: AppBar(title: const Text('Photo Exception Review')),
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
        title: const Text('Photo Exception Review'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pending Photo Exception Requests',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Review and decide on customer photo exception requests for '
              'collateral items. Only pending requests can be approved or '
              'rejected.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            if (_exceptions.isEmpty)
              const Center(
                child: Text(
                  'No pending photo exception requests.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            if (_exceptions.isNotEmpty) ...[
              Expanded(
                child: ListView.builder(
                  itemCount: _exceptions.length,
                  itemBuilder: (context, index) {
                    final exception = _exceptions[index];
                    final item = _itemsById[exception.collateralItemId];
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          radius: 24,
                          child: Icon(Icons.camera_alt),
                        ),
                        title: Text(
                          exception.collateralItemId,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              'Item: ${item?.itemReferenceId ?? exception.collateralItemId}',
                            ),
                            Text(
                              'Description: ${item?.description ?? 'N/A'}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              'Customer: ${item?.customerId ?? 'N/A'}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              'Requested by: ${exception.requestedByUserId}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              'Reason: ${exception.requestReason}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              'Created: ${exception.createdAt.toIso8601String()}',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                        trailing: SizedBox(
                          width: 110,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  exception.status.value.replaceAll('_', ' '),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                icon: const Icon(
                                  Icons.check,
                                  color: Colors.green,
                                  size: 18,
                                ),
                                onPressed: _isLoading
                                    ? null
                                    : () => _approveException(exception),
                                tooltip: 'Approve',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.red,
                                  size: 18,
                                ),
                                onPressed: _isLoading
                                    ? null
                                    : () => _rejectException(exception),
                                tooltip: 'Reject',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
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

