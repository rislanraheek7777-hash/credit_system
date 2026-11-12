import 'dart:async';

import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/permissions/authorization_guard.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/customer_photo_exception_dao.dart';
import 'package:credit_system/features/customers/domain/models/customer_photo_exception.dart';
import 'package:credit_system/features/customers/domain/services/customer_photo_exception_service.dart';

/// Shop Owner review screen for customer photo KYC exception requests (Story 2.3, PRD FR-9, AD-6).
///
/// Displays pending customer photo exception requests strictly scoped to the active shop tenant.
/// Only Shop Owners may access this screen or approve/reject requests — enforcement is via
/// [AuthorizationGuard.checkOwnerAdministrativeAction] in action handlers, not merely by hiding buttons.
///
/// Approving an exception unblocks customer profile registration without a photo while recording
/// the Shop Owner actor, decision timestamp, and decision notes, emitting a Category 1 audit entry.
/// Rejecting requires a mandatory rejection reason and leaves customer profile creation blocked.
class CustomerPhotoExceptionReviewScreen extends StatefulWidget {
  /// The active shop tenant UUID.
  final String shopId;

  /// The currently authenticated actor (must be an active Shop Owner).
  final AppUser currentUser;

  /// Optional injected [AppDatabase] for testing.
  final AppDatabase? database;

  const CustomerPhotoExceptionReviewScreen({
    super.key,
    required this.shopId,
    required this.currentUser,
    this.database,
  });

  @override
  State<CustomerPhotoExceptionReviewScreen> createState() =>
      _CustomerPhotoExceptionReviewScreenState();
}

class _CustomerPhotoExceptionReviewScreenState
    extends State<CustomerPhotoExceptionReviewScreen> {
  late AppDatabase _db;
  late CustomerPhotoExceptionDao _exceptionDao;
  late CustomerPhotoExceptionService _exceptionService;

  List<CustomerPhotoException> _exceptions = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _db = widget.database ?? AppDatabase();
    _exceptionDao = CustomerPhotoExceptionDao(_db);
    _exceptionService = CustomerPhotoExceptionService(
      exceptionDao: _exceptionDao,
      db: _db,
    );
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
        actionDescription: 'view customer photo exception reviews',
      );

      final exceptions = await _exceptionService.getPendingExceptions(
        widget.shopId,
        viewer: widget.currentUser,
      );

      if (!mounted) return;

      setState(() {
        _exceptions = exceptions;
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

  /// Prompts for mandatory decision notes.
  Future<String?> _showNotesDialog({
    required String title,
    required String label,
    required String hint,
    required String confirmText,
    Color confirmColor = Colors.blue,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A mandatory decision rationale is required for the audit trail.',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('photo_exception_review_notes_field'),
                controller: controller,
                autofocus: true,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: label,
                  hintText: hint,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const Key('confirm_decision_button'),
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(controller.text.trim()),
              style: TextButton.styleFrom(foregroundColor: confirmColor),
              child: Text(confirmText),
            ),
          ],
        ),
      ),
    );
    return result;
  }

  /// Approves a pending exception request.
  Future<void> _approveException(CustomerPhotoException exception) async {
    final notes = await _showNotesDialog(
      title: 'Approve Customer Photo Exception',
      label: 'Approval Notes',
      hint: 'e.g. Verified manual physical NIC copy; approved hardware waiver',
      confirmText: 'Approve',
      confirmColor: Colors.green,
    );
    if (notes == null || !mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await _exceptionService.approvePhotoException(
        shopId: widget.shopId,
        exceptionId: exception.id,
        approver: widget.currentUser,
        reviewNotes: notes,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Photo exception for customer ${exception.targetCustomerId} approved.',
          ),
          backgroundColor: Colors.green,
        ),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  /// Rejects a pending exception request.
  Future<void> _rejectException(CustomerPhotoException exception) async {
    final reason = await _showNotesDialog(
      title: 'Reject Customer Photo Exception',
      label: 'Rejection Reason',
      hint: 'e.g. Working camera available at counter 2; physical photo mandatory',
      confirmText: 'Reject',
      confirmColor: Colors.red,
    );
    if (reason == null || !mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await _exceptionService.rejectPhotoException(
        shopId: widget.shopId,
        exceptionId: exception.id,
        reviewer: widget.currentUser,
        reviewNotes: reason,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Photo exception for customer ${exception.targetCustomerId} rejected.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Customer Photo Exception Review')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _refresh,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Photo Exception Review'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _refresh,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Customer KYC Photo Exceptions - Pending Shop Owner Review',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tenant: ${widget.shopId.substring(0, 8)}... | Owner: ${widget.currentUser.fullName}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  if (_exceptions.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text(
                          'No pending customer photo exception requests.',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ),
                    ),
                  if (_exceptions.isNotEmpty)
                    Expanded(
                      child: ListView.builder(
                        itemCount: _exceptions.length,
                        itemBuilder: (context, index) {
                          final ex = _exceptions[index];
                          return Card(
                            key: ValueKey(ex.id),
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Customer ID: ${ex.targetCustomerId}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade100,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          ex.status.displayName,
                                          style: TextStyle(
                                            color: Colors.amber.shade900,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text('NIC: ${ex.customerNic}'),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Requested by Staff ID: ${ex.requestedByUserId}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Requested At: ${ex.createdAt.toLocal().toString().split('.').first}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Justification Rationale:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          ex.requestReason,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      OutlinedButton.icon(
                                        key: Key('btn_reject_${ex.id}'),
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.red,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          'Reject',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                        onPressed: () => _rejectException(ex),
                                      ),
                                      const SizedBox(width: 12),
                                      ElevatedButton.icon(
                                        key: Key('btn_approve_${ex.id}'),
                                        icon: const Icon(
                                          Icons.check,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          'Approve Exception',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                        ),
                                        onPressed: () => _approveException(ex),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

