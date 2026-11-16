import 'package:meta/meta.dart';

/// Immutable, shop-scoped snapshot of the dashboard summary metrics.
///
/// All money values are integer minor units (cents) to match the rest of the
/// financial domain.
@immutable
class DashboardMetrics {
  const DashboardMetrics({
    required this.totalCustomers,
    required this.totalStaff,
    required this.totalCredits,
    required this.activeCreditCents,
    required this.outstandingCents,
    required this.collectedCents,
  });

  /// Placeholder used before the first stream event arrives.
  static const DashboardMetrics empty = DashboardMetrics(
    totalCustomers: 0,
    totalStaff: 0,
    totalCredits: 0,
    activeCreditCents: 0,
    outstandingCents: 0,
    collectedCents: 0,
  );

  /// Number of customer profiles in the shop.
  final int totalCustomers;

  /// Number of active user accounts in the shop, including the shop owner.
  final int totalStaff;

  /// Number of non-cancelled credit agreements in the shop.
  final int totalCredits;

  /// Sum of principals for credits that are active/overdue and pending
  /// disbursement, disbursed, or overdue (excludes cancelled).
  final int activeCreditCents;

  /// Sum of outstanding balances for credits that are active/overdue and pending
  /// disbursement, disbursed, or overdue (excludes cancelled).
  final int outstandingCents;

  /// Principal already repaid across all non-cancelled credits.
  final int collectedCents;

  /// Collected-to-outstanding ratio, preserving the legacy dashboard formula.
  ///
  /// Returns `0` when there is nothing outstanding.
  double get ratio {
    if (outstandingCents == 0) return 0;
    return collectedCents / outstandingCents;
  }
}

