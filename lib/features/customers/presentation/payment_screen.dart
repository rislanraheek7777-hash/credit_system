import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/credit_dao.dart';
import 'package:credit_system/features/customers/data/daos/payment_dao.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:credit_system/features/customers/domain/models/receipt.dart';
import 'package:credit_system/features/customers/domain/services/receipt_service.dart';
import 'package:credit_system/features/customers/data/services/receipt_pdf_service.dart';
import 'package:credit_system/features/customers/presentation/adjustment_proposal_screen.dart';
import 'package:credit_system/features/customers/presentation/correction_adjustment_screen.dart';
import 'package:credit_system/features/customers/presentation/correction_request_screen.dart';
import 'package:credit_system/features/customers/presentation/correction_review_screen.dart';
import 'package:credit_system/features/customers/presentation/voucher_pdf_viewer_web.dart'
    if (dart.library.io) 'voucher_pdf_viewer_mobile.dart';
import 'package:uuid/uuid.dart';

/// Screen for recording a cash payment against a disbursed credit (Story 5-1,
/// PRD FR-21, FR-22, FR-23).
///
/// Accessible from an eligible credit on the customer profile screen. Supports
/// partial payment and full settlement with validation, idempotency, and
/// atomic persistence. Receipt generation failures do not roll back the
/// committed payment — they are reported separately.
class PaymentScreen extends StatefulWidget {
  /// The active shop tenant UUID.
  final String shopId;

  /// The credit agreement to record a payment against.
  final String creditId;

  /// The authenticated actor recording the payment.
  final AppUser currentUser;

  /// Optional injected [AppDatabase] for testing.
  final AppDatabase? database;

  const PaymentScreen({
    super.key,
    required this.shopId,
    required this.creditId,
    required this.currentUser,
    this.database,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late final CreditDao _creditDao;
  late final PaymentDao _paymentDao;
  late final ReceiptService _receiptService = ReceiptService();
  late final ReceiptPdfService _pdfService;

  Credit? _credit;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;
  String? _successMessage;
  String? _paymentError;
  Receipt? _receipt;
  Uint8List? _receiptBytes;
  String? _receiptFilePath;

  final TextEditingController _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final db = widget.database ?? AppDatabase();
    _creditDao = CreditDao(db);
    _paymentDao = PaymentDao(db);
    _pdfService = ReceiptPdfService();
    _load();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final credit = await _creditDao.getCreditById(widget.shopId, widget.creditId);
      if (!mounted) return;
      setState(() {
        _credit = credit;
        _isLoading = false;
        _error = credit == null ? 'Credit agreement not found' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load credit: $e';
      });
    }
  }

  /// Whether the actor may record payments.
  bool get _canRecordPayment =>
      widget.currentUser.isActive &&
      widget.currentUser.effectivePermissions
          .contains(AppPermission.recordPayments);

  /// Whether the actor may request corrections (staff payment-correction or
  /// Story 5.6 balance-adjustment proposals).
  bool get _canRequestCorrection =>
      widget.currentUser.isActive &&
      widget.currentUser.effectivePermissions
          .contains(AppPermission.requestCorrections);

  /// Whether the actor may review (approve/reject) corrections.
  bool get _canReviewCorrections =>
      widget.currentUser.isActive &&
      widget.currentUser.role == AppRole.shopOwner &&
      widget.currentUser.effectivePermissions
          .contains(AppPermission.approveCorrections);

  /// Whether the actor may adjust credit balances.
  bool get _canAdjustBalance =>
      widget.currentUser.isActive &&
      widget.currentUser.role == AppRole.shopOwner &&
      widget.currentUser.effectivePermissions
          .contains(AppPermission.approveCorrections);

  /// Whether the credit is eligible for payment (disbursed, active/overdue,
  /// balance > 0).
  bool get _creditEligibleForPayment {
    final credit = _credit;
    if (credit == null) return false;
    return _receiptService.isEligibleForPayment(credit);
  }

  /// Parses the amount input and returns [Money] or null if invalid.
  Money? _parseAmount(String input) {
    try {
      final money = Money.parse(input.trim());
      if (!money.isPositive) return null;
      return money;
    } catch (_) {
      return null;
    }
  }

  Future<void> _recordPayment() async {
    final amountInput = _amountController.text.trim();
    final amount = _parseAmount(amountInput);
    if (amount == null) {
      setState(() {
        _paymentError = 'Enter a valid positive payment amount.';
      });
      return;
    }

    final credit = _credit;
    if (credit == null) return;

    // Validate against balance before attempting persistence.
    try {
      _receiptService.validateAmount(
        amountCents: amount.minorUnits,
        balanceCents: credit.balanceCents,
      );
    } on CreditOverpaymentException catch (e) {
      setState(() {
        _paymentError = e.message;
      });
      return;
    } catch (e) {
      setState(() {
        _paymentError = 'Invalid payment amount: $e';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
      _successMessage = null;
      _paymentError = null;
      _receipt = null;
      _receiptBytes = null;
      _receiptFilePath = null;
    });

    try {
      final idempotencyKey = const Uuid().v4();
      final receipt = await _paymentDao.recordPayment(
        actor: widget.currentUser,
        idempotencyKey: idempotencyKey,
        creditId: credit.id,
        amount: amount,
        recordedAt: DateTime.now().toUtc(),
      );

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _receipt = receipt;
        _successMessage =
            'Payment recorded. New balance: ${receipt.postBalanceFormatted}';
        if (receipt.isFullSettlement) {
          _successMessage = '${_successMessage!} — Credit settled.';
        }
      });

      // Generate the receipt PDF. Failures are reported separately — the
      // payment itself is preserved.
      await _generateReceiptPdf(receipt);
    } on CreditOverpaymentException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _paymentError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = 'Payment failed: $e';
      });
    }
  }

  /// Story 5.6: opens the balance-adjustment proposal flow for the current
  /// credit (partial forgiveness requested because the customer cannot pay in
  /// full). The proposal is staff-initiated and Shop-Owner-approved; on
  /// submission the payment screen reloads so the correction lock shows and
  /// the option is withdrawn until the owner decides.
  Future<void> _openAdjustmentProposal() async {
    final proposed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => AdjustmentProposalScreen(
          shopId: widget.shopId,
          creditId: widget.creditId,
          currentUser: widget.currentUser,
          database: widget.database,
        ),
      ),
    );

    if (!mounted) return;

    if (proposed == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Adjustment proposed. Awaiting Shop Owner approval. '
            'Payments are locked on this credit meanwhile.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
      await _load();
    }
  }

  /// Generates the receipt PDF for a committed payment.
  ///
  /// PDF generation failures do not roll back the payment — they are reported
  /// separately so the operator can retry receipt generation without
  /// re-posting the payment.
  Future<void> _generateReceiptPdf(Receipt receipt) async {
    if (!mounted) return;
    try {
      // Use the actor's viewSensitiveCustomerData permission to decide PII
      // visibility. Never trust a caller-supplied flag.
      final showRawPII = widget.currentUser
          .effectivePermissions
          .contains(AppPermission.viewSensitiveCustomerData);

      final bytes = await _pdfService.renderReceiptPdf(
        receipt: receipt,
        showRawPII: showRawPII,
        isReprint: false,
      );

      if (!mounted) return;
      setState(() {
        _receiptBytes = bytes;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _paymentError =
            'Payment recorded, but receipt generation failed: $e. '
            'You can reopen this receipt from payment history.';
      });
    }
  }

  /// Opens or downloads the generated receipt PDF.
  Future<void> _viewReceipt() async {
    if (_receiptBytes == null) return;
    final fileName = 'receipt_${_receipt!.receiptNumber}.pdf';
    final savedPath = await viewVoucherPdf(_receiptBytes!, fileName);
    if (!mounted) return;
    if (savedPath != null) {
      setState(() {
        _receiptFilePath = savedPath;
      });
      _showReceiptSavedDialog(savedPath);
    } else {
      _showReceiptDownloadedDialog();
    }
  }

  void _showReceiptSavedDialog(String path) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Receipt Saved'),
        content: Text('Receipt PDF saved to:\n$path'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showReceiptDownloadedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Receipt Downloaded'),
        content: Text('The receipt PDF has been downloaded to your device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final credit = _credit;
    if (credit == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Record Payment')),
        body: Center(child: Text(_error ?? 'Credit not found')),
      );
    }

    final balance = Money.fromCents(credit.balanceCents);
    final canPay = _creditEligibleForPayment && _canRecordPayment;

    return Scaffold(
      appBar: AppBar(title: const Text('Record Payment')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              Text(
                _error!,
                key: const Key('payment_error_display'),
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 12),
            ],
            if (_paymentError != null) ...[
              Text(
                _paymentError!,
                key: const Key('payment_validation_error_display'),
                style: const TextStyle(color: Colors.orange),
              ),
              const SizedBox(height: 12),
            ],
            if (_successMessage != null) ...[
              Text(
                _successMessage!,
                key: const Key('payment_success_display'),
                style: const TextStyle(color: Colors.green),
              ),
              const SizedBox(height: 12),
            ],
            // Credit summary
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Credit Reference: ${credit.id.substring(0, credit.id.length.clamp(0, 8))}...',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('Amount: ${Money.fromCents(credit.principalCents).format()}'),
                    Text('Outstanding Balance: ${balance.format()}'),
                    Text('Status: ${credit.status.value.toUpperCase()}'),
                    Text('Workflow: ${credit.workflowStatus.value.toUpperCase()}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Payment entry form (only when eligible)
            if (canPay) ...[
              const Text(
                'Payment Amount',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('payment_amount_input'),
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: 'Amount (LKR)',
                  hintText: 'e.g. 1,500.00',
                  border: const OutlineInputBorder(),
                  suffixText: 'Max: ${balance.format()}',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  key: const Key('record_payment_button'),
                  onPressed: _isSubmitting ? null : _recordPayment,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Record Payment'),
                ),
              ),
              if (_canRequestCorrection && !credit.correctionPending) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                const Text(
                  'Settlement options',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Customer cannot pay the full balance? Propose to forgive '
                  'part of it. Nothing posts until the Shop Owner approves; '
                  'payments are locked meanwhile.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const Key('request_adjustment_button'),
                    onPressed: _openAdjustmentProposal,
                    icon: const Icon(Icons.volunteer_activism_outlined),
                    label: const Text('Request Balance Adjustment'),
                  ),
                ),
              ],
            ] else
              const Text(
                'This credit is not eligible for payment recording.',
                style: TextStyle(color: Colors.grey),
              ),
            if (!canPay && _creditEligibleForPayment && !_canRecordPayment) ...[
              const SizedBox(height: 8),
              const Text(
                'You do not have the Record Payments permission.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            // Receipt preview (only after successful payment)
            if (_receipt != null) ...[
              const Text(
                'Receipt',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Receipt Number: ${_receipt!.receiptNumber}'),
                      Text('Amount Paid: ${_receipt!.amountFormatted}'),
                      Text('Pre-Payment Balance: ${_receipt!.preBalanceFormatted}'),
                      Text('Post-Payment Balance: ${_receipt!.postBalanceFormatted}'),
                      Text('Type: ${_receipt!.paymentTypeLabel}'),
                      Text('Recorded At: ${_receipt!.recordedAtFormatted}'),
                      const SizedBox(height: 12),
                      if (_canRequestCorrection) ...[
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            key: const Key('request_correction_button'),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) =>
                                      CorrectionRequestScreen(
                                    shopId: widget.shopId,
                                    creditId: _receipt!.creditId,
                                    originalPaymentId: _receipt!.id,
                                    paymentAmount:
                                        Money.fromCents(
                                          _receipt!.amountCents),
                                    currentUser: widget.currentUser,
                                    database: widget.database,
                                  ),
                                ),
                              );
                            },
                            child: const Text('Request Correction'),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_canReviewCorrections) ...[
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            key: const Key('review_corrections_button'),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) =>
                                      CorrectionReviewScreen(
                                    shopId: widget.shopId,
                                    currentUser: widget.currentUser,
                                    database: widget.database,
                                  ),
                                ),
                              );
                            },
                            child: const Text('Review Corrections'),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_canAdjustBalance) ...[
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            key: const Key('adjust_balance_button'),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) =>
                                      CorrectionAdjustmentScreen(
                                    shopId: widget.shopId,
                                    creditId: _receipt!.creditId,
                                    currentUser: widget.currentUser,
                                    database: widget.database,
                                  ),
                                ),
                              );
                            },
                            child: const Text('Adjust Balance'),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_receiptBytes != null) ...[
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            key: const Key('view_receipt_button'),
                            onPressed: _viewReceipt,
                            child: const Text('View Receipt PDF'),
                          ),
                        ),
                        if (_receiptFilePath != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Saved: $_receiptFilePath',
                            key: const Key('receipt_saved_path_display'),
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

