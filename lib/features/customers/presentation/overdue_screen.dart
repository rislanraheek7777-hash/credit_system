import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/core/permissions/authorization_guard.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/loan_dao.dart';
import 'package:credit_system/features/customers/data/daos/overdue_dao.dart';
import 'package:credit_system/features/customers/domain/models/customer_follow_up.dart';
import 'package:credit_system/features/customers/domain/models/loan.dart';
import 'package:credit_system/features/customers/domain/models/loan_resolution.dart';
import 'package:credit_system/features/customers/domain/models/loan_term.dart';
import 'package:credit_system/features/customers/domain/services/overdue_service.dart';

/// Screen for viewing overdue loans and managing delinquency governance
/// (Stories 6.1, 6.2, 6.3, 6.4; PRD FR-25, FR-26, FR-27, FR-28).
///
/// Supports:
/// - Automated overdue evaluation and display with days-overdue counters (Story 6.1)
/// - Shop Owner due date extensions resetting status to Active (Story 6.2)
/// - Delinquency customer follow-up notes and promise-to-pay logging (Story 6.3)
/// - Structured Shop Owner case resolutions without automated forfeiture (Story 6.4)
///
/// Requires `viewOverdueLoans` permission.
class OverdueScreen extends StatefulWidget {
  /// The active shop tenant UUID.
  final String shopId;

  /// The authenticated actor viewing overdue loans.
  final AppUser currentUser;

  /// Optional injected [AppDatabase] for testing.
  final AppDatabase? database;

  const OverdueScreen({
    super.key,
    required this.shopId,
    required this.currentUser,
    this.database,
  });

  @override
  State<OverdueScreen> createState() => _OverdueScreenState();
}

class _OverdueScreenState extends State<OverdueScreen> {
  late final LoanDao _loanDao;
  late final OverdueDao _overdueDao;
  late final OverdueService _overdueService;

  List<Loan> _loans = [];
  List<Loan> _overdueLoans = [];
  Map<String, CustomerFollowUp?> _latestFollowUps = {};
  Map<String, LoanResolution?> _latestResolutions = {};
  ShopTimeZone? _shopTimeZone;
  bool _isLoading = true;
  String? _error;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    final db = widget.database ?? AppDatabase();
    _loanDao = LoanDao(db);
    _overdueDao = OverdueDao(db);
    _overdueService = OverdueService();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Authorization: require viewOverdueLoans permission
      AuthorizationGuard.checkPermission(
        isActive: widget.currentUser.isActive,
        effectivePermissions: widget.currentUser.effectivePermissions,
        permission: AppPermission.viewOverdueLoans,
        actionDescription: 'view overdue loans',
      );

      final allLoans = await _loanDao.getLoansByShopId(widget.shopId);
      _shopTimeZone = await _loanDao.resolveShopTimeZone(widget.shopId);

      // Evaluate which loans are overdue
      final overdueCandidates = _overdueService.evaluateOverdueLoans(
        allLoans,
        _shopTimeZone!,
      );

      // Transition eligible loans to overdue status
      final transitioned = <Loan>[];
      for (final loan in overdueCandidates) {
        final updated = loan.applyOverdue(shopTimeZone: _shopTimeZone!);
        await _loanDao.updateLoanStatus(
          shopId: widget.shopId,
          loanId: loan.id,
          status: updated.status,
          workflowStatus: updated.workflowStatus,
        );
        transitioned.add(updated);
      }

      // Reload to get current state
      final finalLoans = await _loanDao.getLoansByShopId(widget.shopId);
      final finalOverdue = finalLoans.where((l) => l.status == LoanStatus.overdue).toList();

      // Load follow-ups & resolutions for overdue loans
      final followUpsMap = <String, CustomerFollowUp?>{};
      final resolutionsMap = <String, LoanResolution?>{};
      for (final loan in finalOverdue) {
        final followUps = await _overdueDao.getFollowUps(
          shopId: widget.shopId,
          loanId: loan.id,
        );
        followUpsMap[loan.id] = followUps.isNotEmpty ? followUps.first : null;

        final res = await _overdueDao.getLatestResolution(
          shopId: widget.shopId,
          loanId: loan.id,
        );
        resolutionsMap[loan.id] = res;
      }

      if (!mounted) return;
      setState(() {
        _loans = finalLoans;
        _overdueLoans = finalOverdue;
        _latestFollowUps = followUpsMap;
        _latestResolutions = resolutionsMap;
        _isLoading = false;
        if (transitioned.isNotEmpty) {
          _successMessage = '${transitioned.length} loan(s) transitioned to overdue.';
        }
      });
    } on PermissionDeniedException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load overdue loans: $e';
      });
    }
  }

  int _daysOverdue(Loan loan) {
    if (_shopTimeZone == null) return 0;
    final today = _shopTimeZone!.localDateOf(DateTime.now().toUtc());
    final due = _shopTimeZone!.localDateOf(loan.dueDate);
    return _daysBetween(due, today);
  }

  int _daysBetween(LocalCalendarDate start, LocalCalendarDate end) {
    int jd(int year, int month, int day) {
      int a = (14 - month) ~/ 12;
      int y = year + 4800 - a;
      int m = month + 12 * a - 3;
      return day + (153 * m + 2) ~/ 5 + 365 * y + y ~/ 4 - y ~/ 100 + y ~/ 400 - 32045;
    }

    return jd(end.year, end.month, end.day) - jd(start.year, start.month, start.day);
  }

  // --- Story 6.2: Due Date Extension Dialog ---
  Future<void> _showExtensionDialog(Loan loan) async {
    final formKey = GlobalKey<FormState>();
    final reasonController = TextEditingController();
    DateTime? selectedDate = DateTime.now().add(const Duration(days: 14));
    String? dialogError;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Grant Due Date Extension (${loan.id.substring(0, 8)}...)'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (dialogError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Text(
                            dialogError!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      Text(
                        'Current Due Date: ${loan.dueDateAsCalendarDate(_shopTimeZone!)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text('New Due Date: '),
                          Text(
                            selectedDate != null
                                ? '${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}'
                                : 'Select date',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                          ),
                          const Spacer(),
                          TextButton(
                            key: const Key('extension_date_picker_button'),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDate ?? DateTime.now().add(const Duration(days: 14)),
                                firstDate: DateTime.now().add(const Duration(days: 1)),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  selectedDate = picked;
                                });
                              }
                            },
                            child: const Text('Change Date'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('extension_reason_field'),
                        controller: reasonController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Mandatory Business Justification',
                          hintText: 'e.g. Borrower requested 2 weeks due to medical emergency',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Justification reason is required.';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  key: const Key('submit_extension_button'),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    if (selectedDate == null) {
                      setDialogState(() {
                        dialogError = 'Please select a valid new due date.';
                      });
                      return;
                    }

                    try {
                      await _overdueDao.grantDueDateExtension(
                        actor: widget.currentUser,
                        idempotencyKey: const Uuid().v4(),
                        loanId: loan.id,
                        newDueDate: selectedDate!,
                        reason: reasonController.text.trim(),
                      );
                      if (context.mounted) {
                        Navigator.pop(ctx);
                        setState(() {
                          _successMessage = 'Due date extension granted for Loan ${loan.id.substring(0, 8)}...';
                        });
                        _load();
                      }
                    } catch (e) {
                      setDialogState(() {
                        dialogError = e.toString();
                      });
                    }
                  },
                  child: const Text('Confirm Extension'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- Story 6.3: Customer Follow-Up Dialog ---
  Future<void> _showFollowUpDialog(Loan loan) async {
    final formKey = GlobalKey<FormState>();
    final notesController = TextEditingController();
    FollowUpChannel channel = FollowUpChannel.phoneCall;
    DateTime? promisedDate;
    String? dialogError;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Log Customer Follow-Up (${loan.id.substring(0, 8)}...)'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (dialogError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Text(
                            dialogError!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      DropdownButtonFormField<FollowUpChannel>(
                        key: const Key('follow_up_channel_dropdown'),
                        initialValue: channel,
                        decoration: const InputDecoration(
                          labelText: 'Communication Channel',
                          border: OutlineInputBorder(),
                        ),
                        items: FollowUpChannel.values.map((c) {
                          return DropdownMenuItem(
                            value: c,
                            child: Text(c.displayName),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              channel = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('follow_up_notes_field'),
                        controller: notesController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Detailed Interaction Notes',
                          hintText: 'e.g. Spoke with customer; promised partial payment next Tuesday',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Interaction notes cannot be empty.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text('Promised Pay Date: '),
                          Text(
                            promisedDate != null
                                ? '${promisedDate!.year}-${promisedDate!.month.toString().padLeft(2, '0')}-${promisedDate!.day.toString().padLeft(2, '0')}'
                                : 'None',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: promisedDate != null ? Colors.deepPurple : Colors.grey,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            key: const Key('promised_date_picker_button'),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: promisedDate ?? DateTime.now().add(const Duration(days: 7)),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 180)),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  promisedDate = picked;
                                });
                              }
                            },
                            child: Text(promisedDate != null ? 'Change' : 'Set Date'),
                          ),
                          if (promisedDate != null)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                setDialogState(() {
                                  promisedDate = null;
                                });
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  key: const Key('submit_follow_up_button'),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    try {
                      await _overdueDao.recordFollowUp(
                        actor: widget.currentUser,
                        loanId: loan.id,
                        customerId: loan.customerId,
                        channel: channel,
                        notes: notesController.text.trim(),
                        promisedPaymentDate: promisedDate,
                      );
                      if (context.mounted) {
                        Navigator.pop(ctx);
                        setState(() {
                          _successMessage = 'Follow-up logged for Loan ${loan.id.substring(0, 8)}...';
                        });
                        _load();
                      }
                    } catch (e) {
                      setDialogState(() {
                        dialogError = e.toString();
                      });
                    }
                  },
                  child: const Text('Save Note'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- Story 6.4: Case Resolution Dialog ---
  Future<void> _showResolutionDialog(Loan loan) async {
    final formKey = GlobalKey<FormState>();
    final reasonController = TextEditingController();
    LoanResolutionType resType = LoanResolutionType.underReview;
    String? dialogError;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Owner Case Resolution (${loan.id.substring(0, 8)}...)'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (dialogError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Text(
                            dialogError!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      DropdownButtonFormField<LoanResolutionType>(
                        key: const Key('resolution_type_dropdown'),
                        initialValue: resType,
                        decoration: const InputDecoration(
                          labelText: 'Resolution Decision',
                          border: OutlineInputBorder(),
                        ),
                        items: LoanResolutionType.values.map((t) {
                          return DropdownMenuItem(
                            value: t,
                            child: Text(t.displayName),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              resType = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('resolution_reason_field'),
                        controller: reasonController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Mandatory Business Rationale',
                          hintText: 'e.g. Formal police seizure order served; retaining collateral for legal review.',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Business rationale is required.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Note: Automated forfeiture or auction is strictly disabled. All disposition requires manual owner management.',
                        style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  key: const Key('submit_resolution_button'),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    try {
                      await _overdueDao.recordResolution(
                        actor: widget.currentUser,
                        loanId: loan.id,
                        resolutionType: resType,
                        reason: reasonController.text.trim(),
                      );
                      if (context.mounted) {
                        Navigator.pop(ctx);
                        setState(() {
                          _successMessage = 'Resolution "${resType.displayName}" recorded for Loan ${loan.id.substring(0, 8)}...';
                        });
                        _load();
                      }
                    } catch (e) {
                      setDialogState(() {
                        dialogError = e.toString();
                      });
                    }
                  },
                  child: const Text('Confirm Resolution'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- History & Audit Review Dialog ---
  Future<void> _showLoanHistoryDialog(Loan loan) async {
    final extensions = await _overdueDao.getExtensionHistory(
      shopId: widget.shopId,
      loanId: loan.id,
    );
    final followUps = await _overdueDao.getFollowUps(
      shopId: widget.shopId,
      loanId: loan.id,
    );
    final resolutions = await _overdueDao.getResolutions(
      shopId: widget.shopId,
      loanId: loan.id,
    );

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Governance History (${loan.id.substring(0, 8)}...)'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Resolutions:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  if (resolutions.isEmpty)
                    const Text('No owner resolutions recorded.', style: TextStyle(color: Colors.grey))
                  else
                    ...resolutions.map((r) => ListTile(
                          dense: true,
                          title: Text(r.resolutionType.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${r.reason}\n${r.createdAt.toIso8601String().split('T').first}'),
                        )),
                  const Divider(),
                  const Text('Due Date Extensions:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  if (extensions.isEmpty)
                    const Text('No extensions granted.', style: TextStyle(color: Colors.grey))
                  else
                    ...extensions.map((e) => ListTile(
                          dense: true,
                          title: Text('Extended to ${_shopTimeZone?.localDateOf(e.newDueDate).isoDate ?? e.newDueDate.toIso8601String()}'),
                          subtitle: Text('Reason: ${e.reason}\nGranted at: ${e.createdAt.toIso8601String().split('T').first}'),
                        )),
                  const Divider(),
                  const Text('Customer Follow-Ups:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  if (followUps.isEmpty)
                    const Text('No follow-up notes logged.', style: TextStyle(color: Colors.grey))
                  else
                    ...followUps.map((f) => ListTile(
                          dense: true,
                          title: Text('${f.channel.displayName}${f.promisedPaymentDate != null ? ' (Promised: ${_shopTimeZone?.localDateOf(f.promisedPaymentDate!).isoDate ?? f.promisedPaymentDate!.toIso8601String()})' : ''}'),
                          subtitle: Text('${f.notes}\nStaff: ${f.staffId.substring(0, 8)}... | ${f.createdAt.toIso8601String().split('T').first}'),
                        )),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
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
        appBar: AppBar(title: const Text('Overdue Loans')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final isOwner = widget.currentUser.role == AppRole.shopOwner;

    return Scaffold(
      appBar: AppBar(title: const Text('Overdue Loans')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_successMessage != null) ...[
              Text(
                _successMessage!,
                style: const TextStyle(color: Colors.green),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              'Overdue Loans (${_overdueLoans.length})',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_overdueLoans.isEmpty) ...[
              const Text(
                'No overdue loans.',
                style: TextStyle(color: Colors.grey),
              ),
            ] else
              ..._overdueLoans.map((loan) {
                final daysOverdue = _daysOverdue(loan);
                final latestFollowUp = _latestFollowUps[loan.id];
                final latestRes = _latestResolutions[loan.id];

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.red,
                              child: Icon(Icons.warning, color: Colors.white, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Loan ${loan.id.substring(0, 8)}...',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  Text('Customer: ${loan.customerId}'),
                                  Text('Due: ${loan.dueDateAsCalendarDate(_shopTimeZone!)}'),
                                  Text(
                                    'Days Overdue: $daysOverdue',
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text('Balance: ${Money(loan.balanceCents).format()}'),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Chip(
                                  label: const Text('OVERDUE'),
                                  backgroundColor: Colors.red,
                                  labelStyle: const TextStyle(color: Colors.white),
                                ),
                                if (latestRes != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Chip(
                                      label: Text(
                                        latestRes.resolutionType.displayName.toUpperCase(),
                                        style: const TextStyle(fontSize: 10, color: Colors.white),
                                      ),
                                      backgroundColor: Colors.deepPurple,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),

                        // Priority Follow-Up Reminder (Story 6.3)
                        if (latestFollowUp?.promisedPaymentDate != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.deepPurple.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.deepPurple.shade200),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.event_available, color: Colors.deepPurple, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Promised Pay Date: ${_shopTimeZone?.localDateOf(latestFollowUp!.promisedPaymentDate!).isoDate ?? latestFollowUp!.promisedPaymentDate!.toIso8601String().split('T').first}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.deepPurple,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const Divider(height: 20),

                        // Action Buttons Bar (Stories 6.2, 6.3, 6.4)
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            if (isOwner)
                              OutlinedButton.icon(
                                key: Key('extend_due_date_button_${loan.id}'),
                                icon: const Icon(Icons.calendar_today, size: 16),
                                label: const Text('Extend Due Date'),
                                onPressed: () => _showExtensionDialog(loan),
                              ),
                            OutlinedButton.icon(
                              key: Key('log_follow_up_button_${loan.id}'),
                              icon: const Icon(Icons.note_add, size: 16),
                              label: const Text('Log Follow-Up'),
                              onPressed: () => _showFollowUpDialog(loan),
                            ),
                            if (isOwner)
                              OutlinedButton.icon(
                                key: Key('resolve_case_button_${loan.id}'),
                                icon: const Icon(Icons.gavel, size: 16),
                                label: const Text('Resolve Case'),
                                onPressed: () => _showResolutionDialog(loan),
                              ),
                            TextButton.icon(
                              key: Key('view_history_button_${loan.id}'),
                              icon: const Icon(Icons.history, size: 16),
                              label: const Text('History'),
                              onPressed: () => _showLoanHistoryDialog(loan),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 24),
            Text(
              'All Loans (${_loans.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_loans.isEmpty)
              const Text('No loans found.')
            else
              ..._loans.map((loan) {
                final statusColor = loan.status == LoanStatus.overdue
                    ? Colors.red
                    : loan.status == LoanStatus.settled
                        ? Colors.grey
                        : Colors.green;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(
                      'Loan ${loan.id.substring(0, 8)}...',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Status: ${loan.status.value.toUpperCase()}',
                          style: TextStyle(color: statusColor),
                        ),
                        Text(
                          'Balance: ${Money(loan.balanceCents).format()}',
                        ),
                        if (loan.status == LoanStatus.active &&
                            loan.balanceCents > 0 &&
                            _shopTimeZone != null)
                          Text(
                            'Due: ${loan.dueDateAsCalendarDate(_shopTimeZone!)}',
                          ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
