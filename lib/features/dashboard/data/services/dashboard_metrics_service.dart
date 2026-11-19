import 'package:drift/drift.dart';

import '../../../../core/data/local/app_database.dart';
import '../../../customers/domain/models/credit_term.dart';
import '../../domain/models/dashboard_metrics.dart';

/// Reads and watches the shop-scoped aggregate metrics shown on the dashboard.
///
/// A single aggregate query keeps every card consistent with the others. The
/// watched variant re-runs whenever customers, staff accounts, credits, or
/// payments change, so the dashboard reflects new records without a reload.
///
/// Active credit includes newly created agreements that are still
/// awaiting disbursement (pending disbursement), as well as disbursed and overdue
/// credits, so the dashboard reflects credit creation immediately. Cancelled
/// credits are excluded from counts and sums. The overdue sum counts only
/// disbursed, unsettled credits whose official due date has passed in the
/// shop's local time zone.
class DashboardMetricsService {
  DashboardMetricsService(this._db);

  final AppDatabase _db;

  static const String _metricsSql = '''
SELECT
  (SELECT COUNT(*) FROM customers WHERE shop_id = ? AND deleted_at IS NULL) AS total_customers,
  (SELECT COUNT(*) FROM app_users WHERE shop_id = ? AND is_active = 1) AS total_staff,
  (SELECT COUNT(*) FROM credits WHERE shop_id = ? AND status <> 'cancelled') AS total_credits,
  (SELECT COALESCE(SUM(principal_cents), 0) FROM credits
    WHERE shop_id = ? AND status IN ('active', 'overdue')
      AND workflow_status IN ('pending_disbursement', 'disbursed', 'overdue')) AS active_credit_cents,
  (SELECT COALESCE(SUM(principal_cents - balance_cents), 0) FROM credits
    WHERE shop_id = ? AND status <> 'cancelled') AS collected_cents,
  (SELECT COALESCE(SUM(balance_cents), 0) FROM credits
    WHERE shop_id = ? AND status IN ('active', 'overdue')
      AND workflow_status IN ('disbursed', 'overdue')
      AND balance_cents > 0
      AND due_date < ?) AS overdue_cents
''';

  /// Reads the current metrics for [shopId] once.
  Future<DashboardMetrics> loadMetrics(String shopId) async {
    final cutoff = await _overdueCutoff(shopId);
    final row = await _query(shopId, cutoff).getSingle();
    return _toMetrics(row);
  }

  /// Emits the current metrics immediately and again whenever a relevant table
  /// changes. Strictly scoped to [shopId].
  Stream<DashboardMetrics> watchMetrics(String shopId) async* {
    final cutoff = await _overdueCutoff(shopId);
    yield* _query(shopId, cutoff).watchSingle().map(_toMetrics);
  }

  /// Instant of local midnight (00:00) today in the shop's time zone.
  ///
  /// Credits store their official due date as the UTC instant of local
  /// midnight, so any due date strictly before this cutoff is overdue under
  /// the "day after the due date" rule (PRD FR-25). Falls back to the
  /// default shop time zone when the shop row is missing so an unknown shop
  /// still yields a zeroed snapshot rather than an error.
  Future<DateTime> _overdueCutoff(String shopId) async {
    ShopTimeZone timeZone;
    try {
      final entry = await (_db.select(_db.shops)
            ..where((s) => s.id.equals(shopId)))
          .getSingle();
      timeZone = ShopTimeZone(entry.timezone);
    } catch (_) {
      timeZone = ShopTimeZone.defaultTimeZone();
    }
    final today = timeZone.localDateOf(DateTime.now().toUtc());
    return timeZone.instantAtStartOfDay(today);
  }

  Selectable<QueryRow> _query(String shopId, DateTime overdueCutoff) {
    return _db.customSelect(
      _metricsSql,
      variables: [
        for (var i = 0; i < 6; i++) Variable.withString(shopId),
        Variable.withDateTime(overdueCutoff),
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
      collectedCents: row.read<int>('collected_cents'),
      overdueCents: row.read<int>('overdue_cents'),
    );
  }
}

