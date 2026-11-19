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
    required this.collectedCents,
    required this.overdueCents,
  });

  /// Placeholder used before the first stream event arrives.
  static const DashboardMetrics empty = DashboardMetrics(
    totalCustomers: 0,
    totalStaff: 0,
    totalCredits: 0,
    activeCreditCents: 0,
    collectedCents: 0,
    overdueCents: 0,
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

  /// Principal already repaid across all non-cancelled credits.
  final int collectedCents;

  /// Sum of outstanding balances for disbursed, unsettled credits whose
  /// official due date has passed in the shop's local time zone.
  ///
  /// Mirrors the overdue evaluation rule used elsewhere in the domain: a
  /// credit is overdue on the calendar day after its due date, not settled,
  /// with a positive balance. Credits still awaiting disbursement are
  /// excluded because their official due date is only fixed at disbursement.
  final int overdueCents;
}

