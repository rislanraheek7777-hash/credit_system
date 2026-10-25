import 'package:meta/meta.dart';
import '../../../../core/money/money.dart';

/// Exception thrown when receipt snapshot invariants are violated.
class ReceiptValidationException implements Exception {
  final String message;
  const ReceiptValidationException(this.message);
  @override
  String toString() => 'ReceiptValidationException: $message';
}

/// Payment type enumeration used across the payment and receipt layers.
enum PaymentType {
  partialPayment('partial'),
  fullSettlement('full_settlement');

  final String name;
  const PaymentType(this.name);
}

/// Exception thrown when a payment exceeds the outstanding balance or the loan
/// is ineligible for payment.
class LoanOverpaymentException implements Exception {
  final String message;
  const LoanOverpaymentException(this.message);
  @override
  String toString() => 'LoanOverpaymentException: $message';
}

/// Immutable domain entity representing a payment receipt snapshot (Story 5-4,
/// PRD FR-24).
///
/// Captures the shop branding and transaction details at the exact moment of
/// payment confirmation. Re-rendering a receipt always uses this snapshot —
/// live shop or customer edits never alter a previously issued receipt.
@immutable
class Receipt {
  /// Canonical UUIDv4 primary key.
  final String id;

  /// Associated shop tenant boundary.
  final String shopId;

  /// Associated loan agreement.
  final String loanId;

  /// Unique human-readable receipt number.
  final String receiptNumber;

  /// Payment amount in integer minor units (cents), strictly positive.
  final int amountCents;

  /// Outstanding balance in minor units before this payment was applied.
  final int preBalanceCents;

  /// Outstanding balance in minor units after this payment was applied.
  final int postBalanceCents;

  /// Payment type: partial or full settlement.
  final PaymentType paymentType;

  /// UTC timestamp when the payment was confirmed.
  final DateTime recordedAt;

  /// User UUID of the staff member who recorded the payment.
  final String recordedByUserId;

  /// Customer borrower identifier.
  final String customerId;

  /// Customer full name at time of payment.
  final String customerName;

  /// Customer NIC at time of payment.
  final String customerNic;

  /// Shop branding snapshot: shop name.
  final String shopName;

  /// Shop branding snapshot: business address.
  final String? shopAddress;

  /// Shop branding snapshot: contact phone.
  final String? shopPhone;

  /// Shop branding snapshot: tax/registration number.
  final String? shopTaxId;

  /// Shop branding snapshot: receipt footer notes.
  final String? shopFooterNotes;

  /// Client-generated UUIDv4 idempotency key.
  final String idempotencyKey;

  Receipt({
    required this.id,
    required this.shopId,
    required this.loanId,
    required this.receiptNumber,
    required this.amountCents,
    required this.preBalanceCents,
    required this.postBalanceCents,
    required this.paymentType,
    required DateTime recordedAt,
    required this.recordedByUserId,
    required this.customerId,
    required this.customerName,
    required this.customerNic,
    required this.shopName,
    this.shopAddress,
    this.shopPhone,
    this.shopTaxId,
    this.shopFooterNotes,
    required this.idempotencyKey,
  })  : recordedAt = recordedAt.toUtc() {
    if (id.trim().isEmpty) {
      throw ReceiptValidationException('Receipt ID cannot be empty');
    }
    if (shopId.trim().isEmpty) {
      throw ReceiptValidationException('Shop ID cannot be empty');
    }
    if (loanId.trim().isEmpty) {
      throw ReceiptValidationException('Loan ID cannot be empty');
    }
    if (receiptNumber.trim().isEmpty) {
      throw ReceiptValidationException('Receipt number cannot be empty');
    }
    if (amountCents <= 0) {
      throw ReceiptValidationException('Amount must be positive');
    }
    if (recordedByUserId.trim().isEmpty) {
      throw ReceiptValidationException('Recorded by user ID cannot be empty');
    }
    if (customerId.trim().isEmpty) {
      throw ReceiptValidationException('Customer ID cannot be empty');
    }
    if (shopName.trim().isEmpty) {
      throw ReceiptValidationException('Shop name cannot be empty');
    }
    if (idempotencyKey.trim().isEmpty) {
      throw ReceiptValidationException('Idempotency key cannot be empty');
    }
  }

  /// Whether this payment was a full settlement (balance reduced to zero).
  bool get isFullSettlement => paymentType == PaymentType.fullSettlement;

  /// The payment amount formatted for display (e.g. `Rs. 1,500.50`).
  String get amountFormatted => Money.fromCents(amountCents).format();

  /// The pre-payment balance formatted for display.
  String get preBalanceFormatted => Money.fromCents(preBalanceCents).format();

  /// The post-payment balance formatted for display.
  String get postBalanceFormatted => Money.fromCents(postBalanceCents).format();

  /// The recorded timestamp as a formatted date/time string.
  String get recordedAtFormatted {
    final utc = recordedAt.toUtc();
    return '${_two(utc.day)}/${_two(utc.month)}/${utc.year} '
        '${_two(utc.hour)}:${_two(utc.minute)} UTC';
  }

  /// The short payment type label for display.
  String get paymentTypeLabel {
    switch (paymentType) {
      case PaymentType.partialPayment:
        return 'Partial Payment';
      case PaymentType.fullSettlement:
        return 'Full Settlement';
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Receipt &&
        other.id == id &&
        other.receiptNumber == receiptNumber;
  }

  @override
  int get hashCode => Object.hash(id, receiptNumber);

  String _two(int value) => value.toString().padLeft(2, '0');
}
