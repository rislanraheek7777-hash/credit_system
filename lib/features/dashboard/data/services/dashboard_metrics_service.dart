import 'package:drift/drift.dart';

import '../../../../core/data/local/app_database.dart';
import '../../domain/models/dashboard_metrics.dart';

/// Reads and watches the shop-scoped aggregate metrics shown on the dashboard.
///
/// A single aggregate query keeps every card consistent with the others. The
/// watched variant re-runs whenever customers, staff accounts, credits, or
/// payments change, so the dashboard reflects new records without a reload.
///
/// Active credit and outstanding include newly created agreements that are still
/// awaiting disbursement (pending disbursement), as well as disbursed and overdue
/// credits, so the dashboard reflects credit creation immediately. Cancelled
/// credits are excluded from counts and sums.
class DashboardMetricsService {
  DashboardMetricsService(this._db);

  final AppDatabase _db;

  static const String _metricsSql = '''
SELECT
  (SELECT COUNT(*) FROM customers WHERE shop_id = ?) AS total_customers,
  (SELECT COUNT(*) FROM app_users WHERE shop_id = ? AND is_active = 1) AS total_staff,
  (SELECT COUNT(*) FROM credits WHERE shop_id = ? AND status <> 'cancelled') AS total_credits,
  (SELECT COALESCE(SUM(principal_cents), 0) FROM credits
    WHERE shop_id = ? AND status IN ('active', 'overdue')
      AND workflow_status IN ('pending_disbursement', 'disbursed', 'overdue')) AS active_credit_cents,
  (SELECT COALESCE(SUM(balance_cents), 0) FROM credits
    WHERE shop_id = ? AND status IN ('active', 'overdue')
      AND workflow_status IN ('pending_disbursement', 'disbursed', 'overdue')) AS outstanding_cents,
  (SELECT COALESCE(SUM(principal_cents - balance_cents), 0) FROM credits
    WHERE shop_id = ? AND status <> 'cancelled') AS collected_cents
''';

  /// Reads the current metrics for [shopId] once.
  Future<DashboardMetrics> loadMetrics(String shopId) async {
    final row = await _query(shopId).getSingle();
    return _toMetrics(row);
  }

  /// Emits the current metrics immediately and again whenever a relevant table
  /// changes. Strictly scoped to [shopId].
  Stream<DashboardMetrics> watchMetrics(String shopId) {
    return _query(shopId).watchSingle().map(_toMetrics);
  }

  Selectable<QueryRow> _query(String shopId) {
    return _db.customSelect(
      _metricsSql,
      variables: [
        for (var i = 0; i < 6; i++) Variable.withString(shopId),
      ],
      readsFrom: {
        _db.customers,
        _db.appUsers,
        _db.credits,
        _db.payments,
      },
    );
  }

  DashboardMetrics _toMetrics(QueryRow row) {
    return DashboardMetrics(
      totalCustomers: row.read<int>('total_customers'),
      totalStaff: row.read<int>('total_staff'),
      totalCredits: row.read<int>('total_credits'),
      activeCreditCents: row.read<int>('active_credit_cents'),
      outstandingCents: row.read<int>('outstanding_cents'),
      collectedCents: row.read<int>('collected_cents'),
    );
  }
}

