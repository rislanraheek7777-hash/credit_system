import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import '../domain/models/audit_event_record.dart';
import '../domain/services/audit_trail_service.dart';

/// Screen for browsing and inspecting append-only audit trail logs across all 14 mandatory categories (Story 7.3).
class AuditTrailViewerScreen extends StatefulWidget {
  final String shopId;
  final AppUser currentUser;
  final AuditTrailService service;

  const AuditTrailViewerScreen({
    super.key,
    required this.shopId,
    required this.currentUser,
    required this.service,
  });

  @override
  State<AuditTrailViewerScreen> createState() => _AuditTrailViewerScreenState();
}

class _AuditTrailViewerScreenState extends State<AuditTrailViewerScreen> {
  final _actorFilterController = TextEditingController();
  int? _selectedCategory;
  bool _isLoading = true;
  String? _errorMessage;
  List<AuditEventRecord> _events = [];

  bool get _isAuthorized =>
      widget.currentUser.hasPermission(AppPermission.viewAuditLogs) ||
      widget.currentUser.role.isOwner;

  @override
  void initState() {
    super.initState();
    if (_isAuthorized) {
      _loadAuditEvents();
    } else {
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    _actorFilterController.dispose();
    super.dispose();
  }

  Future<void> _loadAuditEvents() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final records = await widget.service.getAuditEvents(
        shopId: widget.shopId,
        actor: widget.currentUser,
        categoryFilter: _selectedCategory,
        actorIdFilter: _actorFilterController.text.trim().isEmpty
            ? null
            : _actorFilterController.text.trim(),
      );

      if (mounted) {
        setState(() {
          _events = records;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _inspectRecord(AuditEventRecord record) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('audit_record_detail_dialog'),
        title: Text('${record.categoryTitle} (${record.actionType})'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailRow('Event ID', record.id),
                _detailRow('Tenant ID', record.shopId),
                _detailRow('Category', 'Category ${record.eventCategory}'),
                _detailRow('Action Type', record.actionType),
                _detailRow('Actor User ID', record.actorId),
                _detailRow(
                  'Target Entity',
                  '${record.targetEntityType} / ${record.targetEntityId}',
                ),
                if (record.reason != null && record.reason!.isNotEmpty)
                  _detailRow('Business Reason', record.reason!),
                if (record.clientIp != null)
                  _detailRow('Client IP', record.clientIp!),
                _detailRow(
                  'Server Timestamp',
                  record.serverTimestamp.toIso8601String(),
                ),
                const Divider(height: 24),
                const Text(
                  'Pre-State Snapshot (Sanitized):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    record.sanitizedPreState != null
                        ? const JsonEncoder.withIndent('  ')
                            .convert(record.sanitizedPreState)
                        : '(None)',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Post-State Snapshot (Sanitized):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    record.sanitizedPostState != null
                        ? const JsonEncoder.withIndent('  ')
                            .convert(record.sanitizedPostState)
                        : '(None)',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
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

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Color _categoryBadgeColor(int category) {
    switch (category) {
      case 1:
        return Colors.blue;
      case 2:
      case 4:
        return Colors.green;
      case 3:
      case 11:
        return Colors.orange;
      case 5:
        return Colors.teal;
      case 6:
      case 7:
        return Colors.purple;
      case 8:
      case 9:
      case 10:
        return Colors.indigo;
      case 12:
        return Colors.brown;
      case 13:
        return Colors.blueGrey;
      case 14:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthorized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Audit Trail')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.gpp_bad, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text(
                'Access Denied: viewAuditLogs permission required',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'You do not possess the required permissions to inspect shop audit logs.',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Trail Viewer'),
        actions: [
          IconButton(
            key: const Key('refresh_audit_button'),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Logs',
            onPressed: _loadAuditEvents,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter section
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<int?>(
                        key: const Key('audit_category_dropdown'),
                        initialValue: _selectedCategory,
                        decoration: const InputDecoration(
                          labelText: 'Event Category',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('All Categories (1-14)'),
                          ),
                          ...AuditEventRecord.categoryTitles.entries.map(
                            (e) => DropdownMenuItem<int?>(
                              value: e.key,
                              child: Text(
                                '${e.key}. ${e.value}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (cat) {
                          setState(() => _selectedCategory = cat);
                          _loadAuditEvents();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        key: const Key('audit_actor_filter_field'),
                        controller: _actorFilterController,
                        decoration: InputDecoration(
                          labelText: 'Filter by Actor ID',
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.search, size: 20),
                            onPressed: _loadAuditEvents,
                          ),
                        ),
                        onSubmitted: (_) => _loadAuditEvents(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Log List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      )
                    : _events.isEmpty
                        ? const Center(
                            child: Text(
                              'No audit records found matching criteria.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.separated(
                            key: const Key('audit_log_list_view'),
                            itemCount: _events.length,
                            separatorBuilder: (context, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final event = _events[index];
                              final badgeColor =
                                  _categoryBadgeColor(event.eventCategory);

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      badgeColor.withValues(alpha: 0.15),
                                  child: Text(
                                    '#${event.eventCategory}',
                                    style: TextStyle(
                                      color: badgeColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  event.actionType,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  'Actor: ${event.actorId}  |  Target: ${event.targetEntityType}/${event.targetEntityId}\n'
                                  'Time: ${event.serverTimestamp.toLocal()}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: Colors.grey,
                                ),
                                onTap: () => _inspectRecord(event),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
