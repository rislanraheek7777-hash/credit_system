import '../../../../core/money/money.dart';
import '../../domain/models/loan.dart';
import '../../domain/models/receipt.dart';

/// Domain service for receipt generation business logic (Story 5-4, PRD FR-24).
///
/// Responsible for creating immutable [Receipt] snapshots from committed
/// payment data. Does not perform PDF rendering — that is the responsibility
/// of the data-layer receipt renderer.
class ReceiptService {
  ReceiptService();

  /// Builds an immutable [Receipt] domain model from a committed payment.
  ///
  /// The snapshot captures shop branding and transaction details at the exact
  /// moment of payment confirmation so that re-rendering a receipt never
  /// silently changes historical transaction details (PRD FR-24).
  Receipt buildReceipt({
    required String id,
    required String shopId,
    required String loanId,
    required String receiptNumber,
    required Money amount,
    required int preBalanceCents,
    required int postBalanceCents,
    required bool isFullSettlement,
    required DateTime recordedAt,
    required String recordedByUserId,
    required String customerId,
    required String customerName,
    required String customerNic,
    required String shopName,
    String? shopAddress,
    String? shopPhone,
    String? shopTaxId,
    String? shopFooterNotes,
    required String idempotencyKey,
  }) {
    return Receipt(
      id: id,
      shopId: shopId,
      loanId: loanId,
      receiptNumber: receiptNumber,
      amountCents: amount.minorUnits,
      preBalanceCents: preBalanceCents,
      postBalanceCents: postBalanceCents,
      paymentType: isFullSettlement
          ? PaymentType.fullSettlement
          : PaymentType.partialPayment,
      recordedAt: recordedAt,
      recordedByUserId: recordedByUserId,
      customerId: customerId,
      customerName: customerName,
      customerNic: customerNic,
      shopName: shopName,
      shopAddress: shopAddress,
      shopPhone: shopPhone,
      shopTaxId: shopTaxId,
      shopFooterNotes: shopFooterNotes,
      idempotencyKey: idempotencyKey,
    );
  }

  /// Whether a [Loan] is eligible for payment recording (PRD FR-21).
  ///
  /// A loan is eligible when:
  /// - Cash has been disbursed (workflow status `disbursed`)
  /// - Financial status is `active` or `overdue`
  /// - Outstanding balance is greater than zero
  bool isEligibleForPayment(Loan loan) {
    return loan.isDisbursed &&
        (loan.status == LoanStatus.active ||
            loan.status == LoanStatus.overdue) &&
        loan.balanceCents > 0;
  }

  /// Validates that a proposed payment amount does not exceed the outstanding
  /// balance (PRD FR-21 overpayment block).
  ///
  /// Returns the validated amount in minor units, or throws
  /// [ArgumentError] if the amount is not positive, or
  /// [LoanOverpaymentException] if the amount exceeds the balance.
  int validateAmount({
    required int amountCents,
    required int balanceCents,
  }) {
    if (amountCents <= 0) {
      throw ArgumentError('Payment amount must be positive.');
    }
    if (amountCents > balanceCents) {
      throw LoanOverpaymentException(
        'Payment of Rs. ${(amountCents / 100).toStringAsFixed(2)} exceeds the '
        'outstanding balance of Rs. ${(balanceCents / 100).toStringAsFixed(2)}.',
      );
    }
    return amountCents;
  }
}
