import 'dart:convert';
import 'package:meta/meta.dart';

/// Clean architecture domain entity representing an append-only audit event record (Story 7.3, FR-31 / NFR-1).
@immutable
class AuditEventRecord {
  /// Canonical UUIDv4 primary key.
  final String id;

  /// Associated shop tenant UUID.
  final String shopId;

  /// Mandatory audit event category number (1-14).
  final int eventCategory;

  /// Verb / operation type within the category.
  final String actionType;

  /// UUID of the authenticated actor who performed the action.
  final String actorId;

  /// Target entity type (e.g. 'customer', 'credit', 'payment', 'collateral_item').
  final String targetEntityType;

  /// Target entity UUID.
  final String targetEntityId;

  /// Snapshot of state before the mutation.
  final Map<String, dynamic>? preStateJson;

  /// Snapshot of state after the mutation.
  final Map<String, dynamic>? postStateJson;

  /// Documented business justification (mandatory for corrections, extensions, photo exceptions).
  final String? reason;

  /// Client IPv4/IPv6 address.
  final String? clientIp;

  /// Client user-agent string.
  final String? userAgent;

  /// Authoritative server-side timestamp.
  final DateTime serverTimestamp;

  const AuditEventRecord({
    required this.id,
    required this.shopId,
    required this.eventCategory,
    required this.actionType,
    required this.actorId,
    required this.targetEntityType,
    required this.targetEntityId,
    this.preStateJson,
    this.postStateJson,
    this.reason,
    this.clientIp,
    this.userAgent,
    required this.serverTimestamp,
  });

  /// The official 14 mandatory audit event category descriptions (FR-31 / Story 7.3).
  static const Map<int, String> categoryTitles = {
    1: 'Customer creation and profile edits',
    2: 'Credit agreement origination and cancellation',
    3: 'Collateral registration and item detail edits',
    4: 'Confirmed cash disbursement',
    5: 'Payment recording (partial and full settlement)',
    6: 'Financial correction requests',
    7: 'Financial correction approvals or rejections',
    8: 'Due date extensions',
    9: 'Customer follow-up notes and promises to pay',
    10: 'Owner decisions on overdue credits and collateral disposition',
    11: 'Collateral physical return confirmations and exception closures',
    12: 'Staff account creation, deactivation, and permission modifications',
    13: 'Receipt reprints',
    14: 'Security events (unauthorized access attempts, cross-tenant violations)',
  };

  /// Returns the human-readable display title for this event's category.
  String get categoryTitle =>
      categoryTitles[eventCategory] ?? 'Category $eventCategory';

  /// Returns a sanitized copy of [preStateJson] strictly excluding passwords,
  /// session tokens, and cryptographic secrets (Story 7.3 AC-2).
  Map<String, dynamic>? get sanitizedPreState => _sanitizeJsonMap(preStateJson);

  /// Returns a sanitized copy of [postStateJson] strictly excluding passwords,
  /// session tokens, and cryptographic secrets (Story 7.3 AC-2).
  Map<String, dynamic>? get sanitizedPostState => _sanitizeJsonMap(postStateJson);

  /// Sensitive field keys that must be strictly redacted.
  static const Set<String> _sensitiveKeys = {
    'password',
    'passwordhash',
    'password_hash',
    'token',
    'jwt',
    'secret',
    'authorization',
    'authtoken',
  };

  static Map<String, dynamic>? _sanitizeJsonMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final sanitized = <String, dynamic>{};
    for (final entry in map.entries) {
      final lowerKey = entry.key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (_sensitiveKeys.contains(lowerKey)) {
        sanitized[entry.key] = '[REDACTED]';
      } else if (entry.value is Map<String, dynamic>) {
        sanitized[entry.key] = _sanitizeJsonMap(entry.value as Map<String, dynamic>);
      } else {
        sanitized[entry.key] = entry.value;
      }
    }
    return sanitized;
  }

  factory AuditEventRecord.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? parseState(dynamic val) {
      if (val == null) return null;
      if (val is Map<String, dynamic>) return val;
      if (val is String && val.trim().isNotEmpty) {
        try {
          return jsonDecode(val) as Map<String, dynamic>;
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    return AuditEventRecord(
      id: json['id'] as String,
      shopId: json['shopId'] ?? json['shop_id'] as String,
      eventCategory: (json['eventCategory'] ?? json['event_category']) as int,
      actionType: (json['actionType'] ?? json['action_type']) as String,
      actorId: (json['actorId'] ?? json['actor_id']) as String,
      targetEntityType: (json['targetEntityType'] ?? json['target_entity_type']) as String,
      targetEntityId: (json['targetEntityId'] ?? json['target_entity_id']) as String,
      preStateJson: parseState(json['preStateJson'] ?? json['pre_state_json']),
      postStateJson: parseState(json['postStateJson'] ?? json['post_state_json']),
      reason: json['reason'] as String?,
      clientIp: (json['clientIp'] ?? json['client_ip']) as String?,
      userAgent: (json['userAgent'] ?? json['user_agent']) as String?,
      serverTimestamp: DateTime.parse(
        (json['serverTimestamp'] ?? json['server_timestamp']) as String,
      ).toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'shopId': shopId,
        'eventCategory': eventCategory,
        'actionType': actionType,
        'actorId': actorId,
        'targetEntityType': targetEntityType,
        'targetEntityId': targetEntityId,
        'preStateJson': sanitizedPreState,
        'postStateJson': sanitizedPostState,
        'reason': reason,
        'clientIp': clientIp,
        'userAgent': userAgent,
        'serverTimestamp': serverTimestamp.toIso8601String(),
      };
}

