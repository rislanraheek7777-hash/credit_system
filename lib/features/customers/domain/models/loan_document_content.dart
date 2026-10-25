import 'package:meta/meta.dart';

import '../../../../core/money/money.dart';
import '../../../collateral/domain/models/collateral_item.dart';
import 'customer.dart';
import 'customer_masking.dart';
import 'loan.dart';
import 'loan_term.dart';

/// Mandatory text fixed by Story 4.4 / PRD FR-20.
///
/// These strings are contracts, not editable template options. They are kept in
/// the domain layer so PDF, on-screen, and future thermal renderers can share the
/// same resolved content.
const String kDraftWatermark =
    '*** DRAFT / PENDING DISBURSEMENT - NOT A CASH RECEIPT ***';

/// Exact preliminary due-date disclosure required on every draft.
const String kPreliminaryDueDateDisclosure =
    'Preliminary Due Date (Subject to Confirmation on Cash Handover) - '
    'Non-binding until disbursement confirmation.';

/// Exact statement that no cash has been handed over for a draft.
const String kDraftCashNotDisbursedDisclosure =
    'Cash has NOT been disbursed. This document is not a receipt and is not '
    'binding until cash handover is confirmed.';

/// Proposed zero-interest disclosure for the official executed ticket.
const String kZeroInterestDisclosure =
    'ZERO-INTEREST LOAN. The disbursed principal is the total amount repayable. '
    'No interest, fee, or compounding charge is added. The outstanding balance '
    'equals the principal until payments are recorded.';

/// Review-only signature label for a draft agreement.
const String kDraftSignatureLabel =
    'For customer review only - not an executed agreement';

/// Resolved, renderer-agnostic content for one loan document.
///
/// Renderers must print exactly these lines; they must not re-query live rows or
/// choose to unmask values that were already resolved here.
///
/// This is a minimal repair of the existing Story 4.4 scaffold. It does not
/// implement the unapproved `loan_documents` / `loan_document_events` snapshot
/// architecture.
@immutable
class LoanDocumentContent {
  const LoanDocumentContent({
    required this.title,
    required this.reference,
    required this.headerLines,
    required this.bodyLines,
    required this.footerLines,
    this.watermark,
  });

  /// Human-readable document title (no customer PII).
  final String title;

  /// Stable document reference: `DRAFT-...` or `VCH-...`.
  final String reference;

  /// Shop branding snapshot lines.
  final List<String> headerLines;

  /// Document body lines.
  final List<String> bodyLines;

  /// Footer/disclosure lines.
  final List<String> footerLines;

  /// Watermark repeated in the header and footer, or `null` for official tickets.
  final String? watermark;

  /// Every printable line, in document order.
  List<String> get allLines => List.unmodifiable([
        ...headerLines,
        ...bodyLines,
        ...footerLines,
      ]);
}

/// Builds the pre-disbursement draft agreement content.
///
/// The caller must have already verified that [loan] is in
/// `pending_disbursement` workflow status.
///
/// [shopTimeZone] is required because loan date columns store *instants*, while
/// the agreement prints *calendar* dates. A due date stored as the instant of
/// local midnight (for example `2026-11-13T18:30Z` in `Asia/Colombo`) must be
/// rendered as `2026-11-14`, never as the UTC calendar date.
LoanDocumentContent buildDraftDocumentContent({
  required Loan loan,
  required ShopTimeZone shopTimeZone,
  required String shopName,
  required String shopAddress,
  required String shopPhone,
  required String shopTaxId,
  required String disbursingStaffId,
  required bool showRawPII,
  Customer? customer,
  List<CollateralItem> collateralItems = const [],
  DateTime? generatedAt,
}) {
  final reference = 'DRAFT-${_shortId(loan.id, 8)}';

  return LoanDocumentContent(
    title: 'LOAN AGREEMENT - DRAFT (PENDING DISBURSEMENT)',
    reference: reference,
    watermark: kDraftWatermark,
    headerLines: _shopHeaderLines(
      shopName: shopName,
      shopAddress: shopAddress,
      shopPhone: shopPhone,
      shopTaxId: shopTaxId,
    ),
    bodyLines: [
      'Draft Reference: $reference',
      'Loan Reference: ${_loanReference(loan)}',
      'Customer Name: ${_orNotRecorded(customer?.fullName)}',
      'Customer ID: ${loan.customerId}',
      'Customer NIC: ${documentMaskNic(customer?.nic, showRawPII: showRawPII)}',
      'Customer Phone: '
          '${documentMaskPhone(customer?.phone, showRawPII: showRawPII)}',
      'Origination Date: '
          '${_formatCalendarDate(loan.createdAt, shopTimeZone)}',
      'Preliminary Due Date (Pending Disbursement): '
          '${_formatCalendarDate(loan.dueDate, shopTimeZone)}',
      kPreliminaryDueDateDisclosure,
      kDraftCashNotDisbursedDisclosure,
      'Principal Amount: ${_money(loan.principalCents)}',
      'Current Outstanding Balance: ${_money(loan.balanceCents)}',
      'Agreed Term: ${_agreedTerm(loan, shopTimeZone)}',
      'Collateral Summary:',
      ..._collateralLines(collateralItems),
      'Generating Staff ID: ${_orNotRecorded(disbursingStaffId)}',
    ],
    footerLines: [
      kDraftWatermark,
      kPreliminaryDueDateDisclosure,
      kDraftCashNotDisbursedDisclosure,
      kDraftSignatureLabel,
      'Generated (UTC): ${_formatTimestamp(generatedAt ?? DateTime.now())}',
    ],
  );
}

/// Builds the official executed loan agreement & cash disbursement voucher.
///
/// The caller must have already verified that [loan] is `disbursed` and that the
/// confirmed cash-handover timestamp exists.
///
/// [shopTimeZone] resolves every *calendar* date in this document. Actual
/// cash-handover and generation timestamps remain UTC instants and are printed
/// as such.
LoanDocumentContent buildOfficialVoucherContent({
  required Loan loan,
  required ShopTimeZone shopTimeZone,
  required String shopName,
  required String shopAddress,
  required String shopPhone,
  required String shopTaxId,
  required String disbursingStaffId,
  required DateTime confirmedDueDate,
  required String documentSnapshotId,
  required bool showRawPII,
  Customer? customer,
  List<CollateralItem> collateralItems = const [],
  String? shopFooterNotes,
  DateTime? generatedAt,
}) {
  final reference = _voucherReference(
    shopId: loan.shopId,
    documentSnapshotId: documentSnapshotId,
    disbursedAt: loan.disbursedAt,
    confirmedDueDate: confirmedDueDate,
    shopTimeZone: shopTimeZone,
  );

  return LoanDocumentContent(
    title: 'LOAN AGREEMENT & CASH DISBURSEMENT VOUCHER',
    reference: reference,
    headerLines: _shopHeaderLines(
      shopName: shopName,
      shopAddress: shopAddress,
      shopPhone: shopPhone,
      shopTaxId: shopTaxId,
    ),
    bodyLines: [
      'OFFICIAL - CASH DISBURSED',
      'Document Number: $reference',
      'Snapshot ID: $documentSnapshotId',
      'Loan Reference: ${_loanReference(loan)}',
      'Customer Name: ${_orNotRecorded(customer?.fullName)}',
      'Customer Identifier: ${loan.customerId}',
      'Customer NIC: ${documentMaskNic(customer?.nic, showRawPII: showRawPII)}',
      'Customer Phone: '
          '${documentMaskPhone(customer?.phone, showRawPII: showRawPII)}',
      'Origination Date: '
          '${_formatCalendarDate(loan.createdAt, shopTimeZone)}',
      'Confirmed Cash Disbursement: ${_formatTimestamp(loan.disbursedAt)}',
      'Disbursing Staff ID: ${_orNotRecorded(disbursingStaffId)}',
      'Official Confirmed Due Date: '
          '${_formatCalendarDate(confirmedDueDate, shopTimeZone)}',
      'Disbursed Principal Amount: ${_money(loan.principalCents)}',
      'Initial Outstanding Balance: ${_money(loan.balanceCents)}',
      'Agreed Term: ${_agreedTerm(loan, shopTimeZone)}',
      'Itemized Collateral Details:',
      ..._collateralLines(collateralItems),
      kZeroInterestDisclosure,
    ],
    footerLines: [
      'Shop Footer Notes: ${_orNotRecorded(shopFooterNotes)}',
      'Snapshot ID: $documentSnapshotId',
      'Generated (UTC): ${_formatTimestamp(generatedAt ?? DateTime.now())}',
    ],
  );
}

List<String> _shopHeaderLines({
  required String shopName,
  required String shopAddress,
  required String shopPhone,
  required String shopTaxId,
}) {
  return [
    _orNotRecorded(shopName),
    'Address: ${_orNotRecorded(shopAddress)}',
    'Phone: ${_orNotRecorded(shopPhone)}',
    'Tax/Registration No: ${_orNotRecorded(shopTaxId)}',
  ];
}

List<String> _collateralLines(List<CollateralItem> items) {
  if (items.isEmpty) {
    return const ['No collateral items recorded.'];
  }
  return items.map((item) {
    return '${item.itemReferenceId}: ${item.description} '
        '(${item.category.value}, condition ${item.conditionGrade}) - '
        '${CollateralItem.formatWeightMilligrams(item.weightMilligrams)} - '
        '${item.estimatedValue.format()}';
  }).toList(growable: false);
}

String _loanReference(Loan loan) =>
    'LN-${_shortId(loan.id, 10)} (${loan.id})';

String _voucherReference({
  required String shopId,
  required String documentSnapshotId,
  required DateTime? disbursedAt,
  required DateTime confirmedDueDate,
  required ShopTimeZone shopTimeZone,
}) {
  // The document-number date segment is a calendar date, so it must follow the
  // shop's zone. Using the UTC date here would number a voucher for the day
  // before a cash handover that occurred just after local midnight.
  final date = _compactCalendarDate(
    disbursedAt ?? confirmedDueDate,
    shopTimeZone,
  );
  return 'VCH-${_shortId(shopId, 6)}-$date-'
      '${_shortId(documentSnapshotId, 8)}';
}

String _agreedTerm(Loan loan, ShopTimeZone shopTimeZone) {
  if (loan.termPresetDays != null) {
    return '${loan.termPresetDays} calendar days';
  }
  if (loan.customDueDate != null) {
    return 'Custom calendar date '
        '(${_formatCalendarDate(loan.customDueDate!, shopTimeZone)})';
  }
  return 'Not recorded';
}

/// Document-specific NIC mask.
///
/// Story 7.2's [maskNic] returns short values unchanged, so a document must
/// fail closed and fully redact anything it cannot safely mask.
String documentMaskNic(String? nic, {required bool showRawPII}) {
  final value = nic?.trim() ?? '';
  if (value.isEmpty) return 'Not recorded';
  if (showRawPII) return value;
  if (value.length <= 8) return '****';
  return maskNic(value);
}

/// Document-specific phone mask with the same fail-closed rule as
/// [documentMaskNic].
String documentMaskPhone(String? phone, {required bool showRawPII}) {
  final value = phone?.trim() ?? '';
  if (value.isEmpty) return 'Not recorded';
  if (showRawPII) return value;
  final digitCount = value.replaceAll(RegExp(r'[^0-9]'), '').length;
  if (digitCount <= 6) return '****';
  return maskPhone(value);
}

String _orNotRecorded(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? 'Not recorded' : trimmed;
}

String _money(int cents) => Money.fromCents(cents).format();

String _shortId(String value, int length) {
  final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  if (cleaned.isEmpty) return 'UNKNOWN';
  return cleaned.length <= length ? cleaned : cleaned.substring(0, length);
}

/// Renders the **shop-local calendar date** of [instant].
///
/// Loan columns that represent calendar dates are persisted as the instant of
/// local midnight. Formatting the UTC components of that instant yields the
/// previous day for any zone east of UTC, which is the Story 4.4 defect this
/// helper exists to prevent.
String _formatCalendarDate(DateTime instant, ShopTimeZone shopTimeZone) =>
    shopTimeZone.localDateOf(instant).isoDate;

/// Renders [date] (an actual instant) in UTC, preserving its time-of-day.
///
/// This is deliberately separate from [_formatCalendarDate]: a disbursement
/// timestamp is not a calendar date and must keep its full UTC instant.
String _formatTimestamp(DateTime? date) {
  if (date == null) return 'Not recorded';
  final utc = date.toUtc();
  return '${utc.year}-${_two(utc.month)}-${_two(utc.day)} '
      '${_two(utc.hour)}:${_two(utc.minute)} UTC';
}

String _compactCalendarDate(DateTime instant, ShopTimeZone shopTimeZone) {
  final local = shopTimeZone.localDateOf(instant);
  return '${local.year}${_two(local.month)}${_two(local.day)}';
}

String _two(int value) => value.toString().padLeft(2, '0');
