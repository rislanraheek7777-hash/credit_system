import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'database.dart';

/// The only two event categories used by recovery. No new permission or
/// category is introduced by this service.
abstract final class RecoveryCategories {
  static const int success = 12;
  static const int abuse = 14;
}

/// Appends recovery events through migration 003's audit function.
///
/// Every append runs with `app.current_shop_id` pinned to the resolved tenant
/// (or the reserved abuse shop). Failures are propagated: a recovery step must
/// not succeed when its required audit event could not be recorded.
class RecoveryAuditor {
  RecoveryAuditor(this._database, this._abuseShopId);

  final RecoveryDatabase _database;
  final String _abuseShopId;

  /// Opens a tenant-scoped transaction for a standalone audit event.
  Future<void> append(
    String shopId, {
    required int category,
    required String action,
    required String targetUserId,
    required String reason,
  }) {
    return _database.transactionWithTenant(shopId, (tx) {
      return appendInTransaction(
        tx,
        shopId: shopId,
        category: category,
        action: action,
        targetUserId: targetUserId,
        reason: reason,
      );
    });
  }

  /// Appends inside an already open tenant-scoped transaction so the event
  /// shares the atomic boundary of the reset it describes.
  Future<void> appendInTransaction(
    SqlExecutor tx, {
    required String shopId,
    required int category,
    required String action,
    required String targetUserId,
    required String reason,
  }) async {
    final rows = await tx.query(
      'SELECT public.cs_record_recovery_audit('
      '@p0, @p1, @p2, @p3, @p4, NULL, NULL) AS recorded',
      [shopId, category, action, targetUserId, reason],
    );
    if (rows.isEmpty) {
      throw StateError('Recovery audit append returned no row');
    }
  }

  /// Security events that cannot be attributed to one tenant are filed under
  /// the reserved platform shop, never under a real tenant's audit trail.
  Future<void> appendAbuse({
    required String action,
    required String reason,
  }) {
    return append(
      _abuseShopId,
      category: RecoveryCategories.abuse,
      action: action,
      targetUserId: systemActorId(_abuseShopId),
      reason: reason,
    );
  }

  Future<void> appendAbuseInTransaction(
    SqlExecutor tx, {
    required String action,
    required String reason,
  }) {
    return appendInTransaction(
      tx,
      shopId: _abuseShopId,
      category: RecoveryCategories.abuse,
      action: action,
      targetUserId: systemActorId(_abuseShopId),
      reason: reason,
    );
  }

  /// Mirrors the deterministic UUIDv5-shaped actor generated inside
  /// `cs_record_recovery_audit` so the target-id foreign key is satisfied.
  static String systemActorId(String shopId) {
    final digest = md5.convert(utf8.encode('$shopId|cs_recovery_system_actor')).toString();
    return '${digest.substring(0, 8)}-${digest.substring(8, 12)}-5'
        '${digest.substring(12, 15)}-8${digest.substring(16, 19)}-'
        '${digest.substring(19, 31)}';
  }
}
