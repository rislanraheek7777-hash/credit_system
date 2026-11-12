import '../../domain/models/credit.dart';
import '../../domain/models/credit_term.dart';

/// Domain service for overdue credit evaluation (Story 6.1, PRD FR-25).
///
/// Evaluates disbursed credits with positive balances against their due dates
/// in the shop's configured time zone, and transitions eligible credits to
/// `overdue` status.
///
/// Credits that are settled (balance = 0) are never marked overdue, regardless
/// of due date. Credits that have not been disbursed are never marked overdue.
class OverdueService {
  OverdueService();

  /// Evaluates [credits] against [shopTimeZone] and returns those that are
  /// overdue and eligible for transition.
  ///
  /// A credit is eligible when:
  /// - It has been disbursed
  /// - Its outstanding balance is greater than zero
  /// - It is not settled
  /// - The current calendar date has passed its due date in the shop's time zone
  List<Credit> evaluateOverdueCredits(
    List<Credit> credits,
    ShopTimeZone shopTimeZone,
  ) {
    return credits.where((credit) {
      if (credit.status == CreditStatus.settled) return false;
      if (credit.balanceCents <= 0) return false;
      if (!credit.isDisbursed) return false;
      return credit.isOverdue(shopTimeZone);
    }).toList();
  }

  /// Transitions [credits] to overdue status using [shopTimeZone].
  ///
  /// Only credits that pass [evaluateOverdueCredits] should be passed here.
  /// Returns the list of credits that were transitioned.
  List<Credit> applyOverdueToCredits(
    List<Credit> credits,
    ShopTimeZone shopTimeZone,
  ) {
    return credits.map((credit) => credit.applyOverdue(shopTimeZone: shopTimeZone)).toList();
  }
}

