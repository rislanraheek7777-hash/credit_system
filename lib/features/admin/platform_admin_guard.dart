import 'dart:convert';

import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/features/auth/data/services/audit_service.dart';

// Story 1.9: Platform administrator governance — default-deny for tenant PII/financial data.
class PlatformAdminGuard {
  static const _protectedTables = {
    'customers',
    'collateral_items',
    'loans',
    'payments',
    'receipt_snapshots',
  };

  /// Audit event category for security events (PRD FR-31, Category 14).
  static const int platformAdminAuditCategory = 14;

  /// Action type recorded when a platform administrator is blocked from a
  /// protected tenant table.
  static const String platformAdminBlockedAccessActionType =
      'platform_admin_blocked_table_access';

  static bool canAccessTable(String role, String table) {
    if (role == 'platform_admin' && _protectedTables.contains(table)) {
      return false; // default-deny
    }
    return true;
  }

  /// Records a Category 14 security audit event for a blocked platform-admin
  /// access attempt.
  ///
  /// The event is written to the server-side `audit_events` table through
  /// [auditService] (when provided) and to the offline `sync_queue` (when [db]
  /// is provided), following the same dual-write pattern used for other
  /// security events. Audit failures are NOT swallowed: any failure propagates
  /// to the caller so a restricted operation cannot proceed unaudited.
  static Future<void> auditBlockedAttempt(
    String actorId,
    String table, {
    String? shopId,
    AuditService? auditService,
    AppDatabase? db,
  }) async {
    if (actorId.trim().isEmpty) {
      throw ArgumentError('actorId is required');
    }
    if (table.trim().isEmpty) {
      throw ArgumentError('table is required');
    }
    if (auditService == null && db == null) {
      throw ArgumentError(
        'At least one audit sink (auditService or db) is required',
      );
    }

    final resolvedShopId = (shopId ?? '').trim();
    if (resolvedShopId.isEmpty && (auditService != null || db != null)) {
      throw ArgumentError('shopId is required to record the audit event');
    }

    // 1. Server-side append-only audit_events write (authoritative).
    if (auditService != null) {
      await auditService.recordAuditEvent(
        shopId: resolvedShopId,
        eventCategory: platformAdminAuditCategory,
        actionType: platformAdminBlockedAccessActionType,
        actorId: actorId.trim(),
        targetEntityType: table.trim(),
        targetEntityId: table.trim(),
        reason: 'Platform administrator access denied to protected table',
      );
    }

    // 2. Offline-first local queue write.
    if (db != null) {
      final now = DateTime.now().toUtc();
      final idempotencyKey =
          'audit_sec_${resolvedShopId}_${table.trim()}_${now.microsecondsSinceEpoch}';
      await db.into(db.syncQueue).insert(
            SyncQueueCompanion.insert(
              id: idempotencyKey,
              shopId: resolvedShopId,
              idempotencyKey: idempotencyKey,
              entityType: 'security_event',
              entityId: table.trim(),
              actionType: platformAdminBlockedAccessActionType,
              payloadJson: jsonEncode({
                'eventCategory': platformAdminAuditCategory,
                'categoryName': 'security_events',
                'actorId': actorId.trim(),
                'targetEntityType': table.trim(),
                'targetEntityId': table.trim(),
                'reason': 'Platform administrator access denied to protected table',
                'timestamp': now.toIso8601String(),
              }),
              createdAt: now,
            ),
          );
    }
  }
}