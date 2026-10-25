import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/models/customer_masking.dart';
import '../../domain/models/receipt.dart';

/// Renders an immutable [Receipt] to PDF bytes using the `pdf` package.
///
/// PDF generation is entirely local and offline-first. Receipt bytes are
/// never stored in SQLite; only the receipt snapshot row persists the
/// transaction data (PRD FR-24).
class ReceiptPdfService {
  /// Renders the [receipt] to PDF bytes.
  ///
  /// The rendered PDF includes:
  /// - Shop branding snapshot (name, address, phone, tax ID, footer notes)
  /// - Receipt reference number
  /// - Loan reference
  /// - Customer identifier (masked NIC per RBAC)
  /// - Payment date/time (UTC)
  /// - Amount paid, pre/post balance
  /// - Payment type (Partial Payment / Full Settlement)
  /// - `*** REPRINT ***` watermark when [isReprint] is true
  ///
  /// [customerNic] and [customerPhone] are always masked using Story 7.2
  /// helpers unless [showRawPII] is true AND the actor holds the sensitive
  /// data permission. The caller-supplied flag is never trusted alone.
  Future<Uint8List> renderReceiptPdf({
    required Receipt receipt,
    required bool showRawPII,
    required bool isReprint,
  }) async {
    final document = pw.Document(
      compress: false,
      title: receipt.receiptNumber,
      author: 'Credit Management System',
      subject: 'Receipt ${receipt.receiptNumber}',
    );

    final maskedNic = _documentSafeMask(receipt.customerNic, showRawPII: showRawPII);

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => _watermarkHeader(isReprint),
        footer: (context) => _footer(receipt, context),
        build: (context) => [
          pw.Text(
            'PAYMENT RECEIPT',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          // Shop branding
          pw.Text(
            receipt.shopName,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          if (receipt.shopAddress != null && receipt.shopAddress!.isNotEmpty)
            pw.Text('Address: ${receipt.shopAddress}'),
          if (receipt.shopPhone != null && receipt.shopPhone!.isNotEmpty)
            pw.Text('Phone: ${receipt.shopPhone}'),
          if (receipt.shopTaxId != null && receipt.shopTaxId!.isNotEmpty)
            pw.Text('Tax/Reg No: ${receipt.shopTaxId}'),
          pw.SizedBox(height: 12),
          pw.Divider(),
          pw.SizedBox(height: 8),
          // Transaction details
          pw.Text('Receipt Number: ${receipt.receiptNumber}'),
          pw.Text('Loan Reference: ${receipt.loanId}'),
          pw.Text('Customer Name: ${receipt.customerName}'),
          pw.Text('Customer NIC: $maskedNic'),
          pw.Text('Payment Type: ${receipt.paymentTypeLabel}'),
          pw.Text('Amount Paid: ${receipt.amountFormatted}'),
          pw.Text('Pre-Payment Balance: ${receipt.preBalanceFormatted}'),
          pw.Text('Post-Payment Balance: ${receipt.postBalanceFormatted}'),
          pw.Text('Recorded At: ${receipt.recordedAtFormatted}'),
          pw.Text('Recorded By: ${receipt.recordedByUserId}'),
          pw.SizedBox(height: 12),
          pw.Divider(),
          pw.SizedBox(height: 8),
          if (receipt.shopFooterNotes != null && receipt.shopFooterNotes!.isNotEmpty)
            pw.Text('Footer Notes: ${receipt.shopFooterNotes}'),
        ],
      ),
    );

    return await document.save();
  }

  /// Fail-closed mask for audit/display values.
  String _documentSafeMask(String value, {required bool showRawPII}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Not recorded';
    if (!showRawPII) {
      if (trimmed.length <= 8) return '****';
      return maskNic(trimmed);
    }
    return trimmed;
  }

  pw.Widget _watermarkHeader(bool isReprint) {
    if (!isReprint) return pw.SizedBox();
    return pw.Container(
      alignment: pw.Alignment.center,
      width: double.infinity,
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Text(
        '*** REPRINT ***',
        style: pw.TextStyle(
          fontSize: 14,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.red,
        ),
      ),
    );
  }

  pw.Widget _footer(Receipt receipt, pw.Context context) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (receipt.shopFooterNotes != null && receipt.shopFooterNotes!.isNotEmpty)
          pw.Container(
            alignment: pw.Alignment.center,
            width: double.infinity,
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Text(
              receipt.shopFooterNotes!,
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey),
            ),
          ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: pw.TextStyle(fontSize: 8, color: PdfColors.grey),
        ),
      ],
    );
  }
}
