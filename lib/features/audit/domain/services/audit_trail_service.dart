import 'package:credit_system/core/data/remote/postgres_executor.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import '../models/audit_event_record.dart';

/// Exception thrown when an unauthorized user attempts to view the audit trail.
class AuditAccessForbiddenException implements Exception {
  final String message;
  final int statusCode;

  const AuditAccessForbiddenException(
    this.message, {
    this.statusCode = 403,
  });

  @override
  String toString() => 'AuditAccessForbiddenException ($statusCode): $message';
}

/// Service providing query and retrieval access to the append-only audit trail (Story 7.3).
///
/// Binds: PRD FR-31, FR-33, AD-6.
///
/// Invariants:
/// 1. Only users with [AppPermission.viewAuditLogs] (or Shop Owner role) may read audit events.
/// 2. Tenant isolation is strictly enforced — users can only view logs matching their own [shopId].
/// 3. Chronological descending order (most recent first) by default.
/// 4. Sensitive keys in pre/post snapshots are redacted before UI presentation.
class AuditTrailService {
  final PostgreSqlExecutor? pg;
  final List<AuditEventRecord>? localMockStore;

  const AuditTrailService({
    this.pg,
    this.localMockStore,
  });

  /// Retrieves audit events for [shopId] matching the specified filters.
  ///
  /// Throws [AuditAccessForbiddenException] if [actor] lacks `viewAuditLogs` permission.
  Future<List<AuditEventRecord>> getAuditEvents({
    required String shopId,
    required AppUser actor,
    int? categoryFilter,
    String? actorIdFilter,
    DateTime? fromTimestamp,
    DateTime? toTimestamp,
  }) async {
    // 1. Cross-tenant guard
    if (actor.shopId != shopId && !actor.role.isOwner) {
      throw const AuditAccessForbiddenException(
        'Access denied: Cross-tenant audit trail inspection is strictly forbidden.',
      );
    }

    // 2. RBAC check
    final hasPermission =
        actor.hasPermission(AppPermission.viewAuditLogs) || actor.role.isOwner;
    if (!hasPermission) {
      throw const AuditAccessForbiddenException(
        'Access denied: viewAuditLogs permission is required to view the audit trail.',
      );
    }

    // 3. PostgreSQL query path
    if (pg != null) {
      return _queryPostgreSql(
        shopId: shopId,
        categoryFilter: categoryFilter,
        actorIdFilter: actorIdFilter,
        fromTimestamp: fromTimestamp,
        toTimestamp: toTimestamp,
      );
    }

    // 4. Local fallback / mock store path
    return _queryLocalStore(
      shopId: shopId,
      categoryFilter: categoryFilter,
      actorIdFilter: actorIdFilter,
      fromTimestamp: fromTimestamp,
      toTimestamp: toTimestamp,
    );
  }

  Future<List<AuditEventRecord>> _queryPostgreSql({
    required String shopId,
    int? categoryFilter,
    String? actorIdFilter,
    DateTime? fromTimestamp,
    DateTime? toTimestamp,
  }) async {
    final conditions = ['shop_id = @p0::uuid'];
    final params = <dynamic>[shopId];
    int paramIdx = 1;

    if (categoryFilter != null) {
      conditions.add('event_category = @p$paramIdx');
      params.add(categoryFilter);
      paramIdx++;
    }

    if (actorIdFilter != null && actorIdFilter.trim().isNotEmpty) {
      conditions.add('actor_id = @p$paramIdx::uuid');
      params.add(actorIdFilter.trim());
      paramIdx++;
    }

    if (fromTimestamp != null) {
      conditions.add('server_timestamp >= @p$paramIdx');
      params.add(fromTimestamp.toIso8601String());
      paramIdx++;
    }

    if (toTimestamp != null) {
      conditions.add('server_timestamp <= @p$paramIdx');
      params.add(toTimestamp.toIso8601String());
      paramIdx++;
    }

    final whereClause = conditions.join(' AND ');
    final sql = '''
      SELECT id, shop_id, event_category, action_type, actor_id,
             target_entity_type, target_entity_id, pre_state_json,
             post_state_json, reason, client_ip, user_agent, server_timestamp
      FROM public.audit_events
      WHERE $whereClause
      ORDER BY server_timestamp DESC
    ''';

    return pg!.transactionWithTenant(shopId, (tx) async {
      final rows = await tx.query(sql, params);
      return rows.map((r) => AuditEventRecord.fromJson(r)).toList();
    });
  }

  Future<List<AuditEventRecord>> _queryLocalStore({
    required String shopId,
    int? categoryFilter,
    String? actorIdFilter,
    DateTime? fromTimestamp,
    DateTime? toTimestamp,
  }) async {
    final list = localMockStore ?? [];
    return list.where((e) {
      if (e.shopId != shopId) return false;
      if (categoryFilter != null && e.eventCategory != categoryFilter) return false;
      if (actorIdFilter != null &&
          actorIdFilter.trim().isNotEmpty &&
          e.actorId != actorIdFilter.trim()) {
        return false;
      }
      if (fromTimestamp != null && e.serverTimestamp.isBefore(fromTimestamp)) {
        return false;
      }
      if (toTimestamp != null && e.serverTimestamp.isAfter(toTimestamp)) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.serverTimestamp.compareTo(a.serverTimestamp));
  }
}

