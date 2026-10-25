import '../../domain/models/loan.dart';
import '../../domain/models/loan_term.dart';

/// Domain service for overdue loan evaluation (Story 6.1, PRD FR-25).
///
/// Evaluates disbursed loans with positive balances against their due dates
/// in the shop's configured time zone, and transitions eligible loans to
/// `overdue` status.
///
/// Loans that are settled (balance = 0) are never marked overdue, regardless
/// of due date. Loans that have not been disbursed are never marked overdue.
class OverdueService {
  OverdueService();

  /// Evaluates [loans] against [shopTimeZone] and returns those that are
  /// overdue and eligible for transition.
  ///
  /// A loan is eligible when:
  /// - It has been disbursed
  /// - Its outstanding balance is greater than zero
  /// - It is not settled
  /// - The current calendar date has passed its due date in the shop's time zone
  List<Loan> evaluateOverdueLoans(
    List<Loan> loans,
    ShopTimeZone shopTimeZone,
  ) {
    return loans.where((loan) {
      if (loan.status == LoanStatus.settled) return false;
      if (loan.balanceCents <= 0) return false;
      if (!loan.isDisbursed) return false;
      return loan.isOverdue(shopTimeZone);
    }).toList();
  }

  /// Transitions [loans] to overdue status using [shopTimeZone].
  ///
  /// Only loans that pass [evaluateOverdueLoans] should be passed here.
  /// Returns the list of loans that were transitioned.
  List<Loan> applyOverdueToLoans(
    List<Loan> loans,
    ShopTimeZone shopTimeZone,
  ) {
    return loans.map((loan) => loan.applyOverdue(shopTimeZone: shopTimeZone)).toList();
  }
}
