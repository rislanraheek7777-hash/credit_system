import 'dart:convert';

import 'package:credit_system/core/data/remote/postgres_executor.dart';

/// Exception thrown when audit event recording fails.
class AuditServiceException implements Exception {
  final String message;
  const AuditServiceException(this.message);
  @override
  String toString() => 'AuditServiceException: $message';
}

/// Server-side audit event recording service (Story 1.8, FR-31 / NFR-1).
///
/// Records append-only audit events to the PostgreSQL `audit_events` table
/// within a transaction-scoped tenant context. All writes use
/// `transactionWithTenant` with `app.current_shop_id` derived from trusted
/// server context — never from client input.
///
/// The database trigger `reject_audit_tampering` (installed by migration
/// 001_initial_schema / 002_rls_roles_audit) unconditionally blocks `UPDATE`
/// and `DELETE` on `audit_events`, providing append-only integrity protection
/// at the database engine level.
class AuditService {
  final PostgreSqlExecutor _pg;

  AuditService(this._pg);

  /// Records an audit event to the PostgreSQL `audit_events` table.
  ///
  /// The write executes inside a transaction with `app.current_shop_id` set
  /// to [shopId], ensuring RLS tenant isolation. The `server_timestamp` is
  /// set by the database (`NOW()`) to prevent client timestamp forgery.
  ///
  /// Event categories (1-14) match the PRD's audit event catalog:
  ///  1. Customer creation and profile edits
  ///  2. Customer photo and exception events
  ///  3. Customer search and data access
  ///  4. Collateral intake and appraisal
  ///  5. Collateral custody transitions
  ///  6. Collateral photo exception events
  ///  7. Loan agreement creation and disbursement
  ///  8. Loan payment and settlement
  ///  9. Loan correction requests and approvals
  /// 10. Overdue evaluation and due-date extensions
  /// 11. Customer follow-up and promise-to-pay
  /// 12. Staff account creation, deactivation, and permission modifications
  /// 13. Shop profile configuration and administrative events
  /// 14. Security events: unauthorized access attempts, cross-tenant violations
  ///
  /// Throws [AuditServiceException] if the insert fails.
  Future<void> recordAuditEvent({
    required String shopId,
    required int eventCategory,
    required String actionType,
    required String actorId,
    required String targetEntityType,
    required String targetEntityId,
    Map<String, dynamic>? preState,
    Map<String, dynamic>? postState,
    String? reason,
    String? clientIp,
    String? userAgent,
  }) async {
    if (shopId.trim().isEmpty) {
      throw const AuditServiceException('Shop ID is required');
    }
    if (eventCategory < 1 || eventCategory > 14) {
      throw const AuditServiceException(
        'Event category must be between 1 and 14',
      );
    }
    if (actionType.trim().isEmpty) {
      throw const AuditServiceException('Action type is required');
    }
    if (actorId.trim().isEmpty) {
      throw const AuditServiceException('Actor ID is required');
    }

    try {
      await _pg.transactionWithTenant(shopId, (tx) async {
        await tx.execute(
          '''
            SELECT public.cs_record_audit_event(
              @p0, @p1, @p2, @p3,
              @p4, @p5, @p6, @p7, @p8,
              @p9, @p10
            )
          ''',
          [
            shopId,
            eventCategory,
            actionType,
            actorId,
            targetEntityType,
            targetEntityId,
            preState != null ? jsonEncode(preState) : null,
            postState != null ? jsonEncode(postState) : null,
            reason,
            clientIp,
            userAgent,
          ],
        );
      });
    } catch (e) {
      throw AuditServiceException('Failed to record audit event: $e');
    }
  }
}
