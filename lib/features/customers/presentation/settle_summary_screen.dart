import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/credit_dao.dart';
import 'package:credit_system/features/customers/data/daos/customer_dao.dart';
import 'package:credit_system/features/customers/data/daos/overdue_dao.dart';
import 'package:credit_system/features/customers/data/daos/payment_dao.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:credit_system/features/customers/domain/models/credit_term.dart';
import 'package:credit_system/features/customers/domain/models/receipt.dart';
import 'package:credit_system/features/customers/domain/services/receipt_service.dart';
import 'package:credit_system/features/customers/data/services/receipt_pdf_service.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_dao.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';
import 'package:credit_system/features/customers/presentation/adjustment_proposal_screen.dart';
import 'package:credit_system/features/customers/presentation/correction_adjustment_screen.dart';
import 'package:credit_system/features/customers/presentation/correction_request_screen.dart';
import 'package:credit_system/features/customers/presentation/correction_review_screen.dart';
import 'package:credit_system/features/customers/presentation/voucher_pdf_viewer_web.dart'
    if (dart.library.io) 'voucher_pdf_viewer_mobile.dart';
import 'package:uuid/uuid.dart';

/// Dedicated settle summary for one credit, opened by the per-card Settle
/// action on the customer profile.
///
/// Shows everything a staff member needs to confirm a settlement at the
/// counter in one place: the borrower, the credit identity (reference,
/// principal, agreed term, due date, status), the outstanding balance in
/// large type, and the collateral still at stake (settlement never returns
/// pledged items).
///
/// The amount field is pre-filled to the credit's full outstanding balance.
/// Tapping **Settle** opens a bottom sheet of settlement options:
///
/// - **Settle in full** — posts the full outstanding balance through the
///   existing payment path (receipts, idempotency, overpayment protection,
///   correction lock, audit unchanged). A confirmed full settlement pops
///   with the committed [Receipt] so the profile can confirm it.
/// - **Partial settlement** — dismisses the sheet and focuses the amount
///   field for a lower amount; with a partial amount entered it posts an
///   ordinary partial payment, which stays on this screen.
/// - **Request Balance Adjustment** — Story 5.6 partial-forgiveness proposal
///   (staff-initiated, Shop Owner approves).
/// - **Extend due date** — FR-26 extension (Shop Owner only, new date plus a
///   mandatory reason), reusing [OverdueDao.grantDueDateExtension].
class SettleSummaryScreen extends StatefulWidget {
  /// The active shop tenant UUID.
  final String shopId;

  /// The credit agreement to settle.
  final String creditId;

  /// The authenticated actor recording the settlement.
  final AppUser currentUser;

  /// Optional injected [AppDatabase] for testing.
  final AppDatabase? database;

  const SettleSummaryScreen({
    super.key,
    required this.shopId,
    required this.creditId,
    required this.currentUser,
    this.database,
  });

  @override
  State<SettleSummaryScreen> createState() => _SettleSummaryScreenState();
}

class _SettleSummaryScreenState extends State<SettleSummaryScreen> {
  late final AppDatabase _db;
  late final CreditDao _creditDao;
  late final CustomerDao _customerDao;
  late final PaymentDao _paymentDao;
  late final CollateralDao _collateralDao;
  late final ReceiptService _receiptService = ReceiptService();
  late final ReceiptPdfService _pdfService;

  Credit? _credit;
  String? _customerName;
  List<CollateralItem> _collateralItems = const [];
  ShopTimeZone _shopTimeZone = ShopTimeZone.defaultTimeZone();
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;
  String? _paymentError;
  String? _successMessage;
  Receipt? _receipt;
  Uint8List? _receiptBytes;
  String? _receiptFilePath;

  final TextEditingController _amountController = TextEditingController();
  final FocusNode _amountFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _db = widget.database ?? AppDatabase();
    _creditDao = CreditDao(_db);
    _customerDao = CustomerDao(_db);
    _paymentDao = PaymentDao(_db);
    _collateralDao = CollateralDao(_db);
    _pdfService = ReceiptPdfService();
    _load();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final db = _db;
      final credit = await _creditDao.getCreditById(widget.shopId, widget.creditId);
      if (credit == null) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _error = 'Credit agreement not found';
        });
        return;
      }
      final customer = await _customerDao.getCustomerById(
        widget.shopId,
        credit.customerId,
      );
      final items = await _collateralDao.getCollateralItemsByCreditId(
        widget.shopId,
        credit.id,
      );
      final shopTimeZone = await OverdueDao(db).resolveShopTimeZone(widget.shopId);
      if (!mounted) return;
      setState(() {
        _credit = credit;
        _customerName = customer?.fullName;
        _collateralItems = items;
        _shopTimeZone = shopTimeZone;
        _isLoading = false;
        // Pre-fill the outstanding balance so a full settlement can be
        // reviewed and confirmed without typing it. The field stays
        // editable, so lowering it records an ordinary partial payment.
        if (credit.balanceCents > 0) {
          _amountController.text = _balanceText(credit.balanceCents);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load credit: $e';
      });
    }
  }

  static String _balanceText(int balanceCents) {
    final balance = Money.fromCents(balanceCents);
    return '${balance.majorUnits}.${balance.centsPart.toString().padLeft(2, '0')}';
  }

  /// Refreshes the shown credit (and pre-fill) after a partial payment, so
  /// the screen reflects the new balance without a full reload.
  Future<void> _reloadAfterPayment() async {
    try {
      final credit = await _creditDao.getCreditById(widget.shopId, widget.creditId);
      if (!mounted || credit == null) return;
      setState(() {
        _credit = credit;
        if (credit.balanceCents > 0) {
          _amountController.text = _balanceText(credit.balanceCents);
        } else {
          _amountController.clear();
        }
      });
    } catch (_) {
      // The payment is already committed; failing to refresh the shown
      // balance is not an error for the caller.
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

  /// Whether the actor may approve (or directly execute) balance adjustments
  /// and correction resolutions.
  bool get _canApproveCorrections =>
      widget.currentUser.isActive &&
      widget.currentUser.role == AppRole.shopOwner &&
      widget.currentUser.effectivePermissions
          .contains(AppPermission.approveCorrections);

  /// Whether the credit is eligible for settlement (disbursed, active/overdue,
  /// balance > 0) — the same rule the payment path enforces.
  bool get _creditEligible =>
      _credit != null && _receiptService.isEligibleForPayment(_credit!);

  /// The agreed term as shown to the operator.
  String _agreedTermLabel(Credit credit) {
    if (credit.termPresetDays != null) return '${credit.termPresetDays} Days';
    if (credit.customDueDate != null) return 'Custom Date';
    return 'Not recorded';
  }

  Money? _parseAmount(String input) {
    try {
      final money = Money.parse(input.trim());
      if (!money.isPositive) return null;
      return money;
    } catch (_) {
      return null;
    }
  }

  /// The amount currently entered in the field, or null when empty/invalid.
  Money? get _enteredAmount => _parseAmount(_amountController.text);

  /// Whether the actor may grant due date extensions (Shop Owner only, FR-26).
  bool get _canExtendDueDate =>
      widget.currentUser.isActive &&
      widget.currentUser.role == AppRole.shopOwner;

  Future<void> _recordPayment({Money? amountOverride}) async {
    final amountInput = _amountController.text.trim();
    final amount = amountOverride ?? _parseAmount(amountInput);
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

      // A successful full settlement returns to the profile immediately,
      // handing back the committed receipt so the profile can confirm it.
      // The payment and its receipt row are already committed, so the
      // receipt remains available from payment history. The receipt PDF is
      // still generated first; if it fails, stay on this screen so the
      // failure stays visible instead of being silently lost.
      if (receipt.isFullSettlement) {
        await _generateReceiptPdf(receipt);
        if (!mounted) return;
        if (_paymentError != null) return;
        Navigator.of(context).pop(receipt);
        return;
      }

      // Partial payment: stay on this screen like the ordinary payment
      // flow, refreshing the shown balance and receipt.
      await _reloadAfterPayment();
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

  /// Opens the bottom sheet of settlement options for the current credit.
  ///
  /// The sheet is intentionally the confirmation step in place of a plain
  /// "are you sure?" — every option here either posts through the existing
  /// payment path (full / partial), routes to the existing forgiveness
  /// proposal flow, or grants an FR-26 due date extension. Nothing posts
  /// from a sheet row without an explicit tap.
  Future<void> _openSettleSheet() async {
    final credit = _credit;
    if (credit == null) return;
    final balance = Money.fromCents(credit.balanceCents);
    final entered = _enteredAmount;
    final partialEntered =
        entered != null && entered.minorUnits < credit.balanceCents;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Settlement options',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    balance.format(),
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              key: const Key('settle_sheet_full'),
              leading: const Icon(Icons.payments_outlined),
              title: Text('Settle in full — ${balance.format()}'),
              subtitle: const Text('Posts the outstanding balance as a full settlement'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _recordPayment(amountOverride: Money.fromCents(credit.balanceCents));
              },
            ),
            ListTile(
              key: const Key('settle_sheet_partial'),
              leading: Icon(partialEntered ? Icons.payments : Icons.edit_outlined),
              title: Text(
                partialEntered
                    ? 'Record partial payment — ${entered.format()}'
                    : 'Partial settlement',
              ),
              subtitle: Text(
                partialEntered
                    ? 'Records the entered amount as a partial payment'
                    : 'Clears the amount field to enter a partial payment',
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                if (partialEntered) {
                  _recordPayment(amountOverride: entered);
                } else {
                  setState(() => _amountController.clear());
                  _amountFocusNode.requestFocus();
                }
              },
            ),
            if (_canRequestCorrection && !credit.correctionPending)
              ListTile(
                key: const Key('request_adjustment_button'),
                leading: const Icon(Icons.volunteer_activism_outlined),
                title: const Text('Request Balance Adjustment'),
                subtitle: const Text(
                  'Customer cannot pay in full? The Shop Owner approves any forgiveness',
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openAdjustmentProposal();
                },
              ),
            if (_canExtendDueDate && credit.status != CreditStatus.settled)
              ListTile(
                key: const Key('settle_sheet_extend'),
                leading: const Icon(Icons.event_outlined),
                title: const Text('Extend due date'),
                subtitle: const Text(
                  'Shop Owner only — new date plus a mandatory reason (FR-26)',
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _extendDueDate(credit);
                },
              ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('settle_sheet_cancel'),
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  /// Grants an FR-26 due date extension on the current credit from the settle
  /// flow. Shop Owner only; requires a new date strictly after today (shop
  /// local) and a non-empty reason. Reuses [OverdueDao.grantDueDateExtension]
  /// so the sync queue, audit trail and overdue→active reset behave exactly
  /// as they do from the overdue screen.
  Future<void> _extendDueDate(Credit credit) async {
    final today = _shopTimeZone.localDateOf(DateTime.now().toUtc());
    final firstDate = DateTime(today.year, today.month, today.day + 1);
    final dueLocal = _shopTimeZone.localDateOf(credit.dueDate);
    final baseDate = dueLocal.isAfter(today) ? dueLocal : today;
    final initial = DateTime(baseDate.year, baseDate.month, baseDate.day + 30);

    final picked = await showDatePicker(
      context: context,
      helpText: 'Extend due date',
      initialDate: initial,
      firstDate: firstDate,
      lastDate: DateTime(firstDate.year + 10),
    );
    if (picked == null || !mounted) return;

    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reason for extension'),
        content: TextField(
          key: const Key('extend_reason_field'),
          controller: reasonController,
          autofocus: true,
          maxLines: 3,
          maxLength: 255,
          decoration: const InputDecoration(
            labelText: 'Reason (mandatory)',
            hintText: 'e.g. Customer requested more time',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('extend_cancel_button'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('extend_confirm_button'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(reasonController.text),
            child: const Text('Extend'),
          ),
        ],
      ),
    );
    reasonController.dispose();

    if (reason == null) return;
    if (reason.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Extension reason cannot be empty — nothing was changed.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    try {
      await OverdueDao(_db).grantDueDateExtension(
        actor: widget.currentUser,
        idempotencyKey: const Uuid().v4(),
        creditId: credit.id,
        newDueDate: picked,
        reason: reason.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Due date extended to '
            '${_shopTimeZone.localDateOf(picked.toUtc()).isoDate}.',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not extend due date: $e'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// Story 5.6: opens the balance-adjustment proposal flow for the current
  /// credit (partial forgiveness requested because the customer cannot pay in
  /// full). The proposal is staff-initiated and Shop-Owner-approved; on
  /// submission this screen reloads so the correction lock shows and the
  /// option is withdrawn until the owner decides.
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
        title: const Text('Receipt Downloaded'),
        content: const Text('The receipt PDF has been downloaded to your device.'),
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
        appBar: AppBar(title: const Text('Settle Credit')),
        body: Center(child: Text(_error ?? 'Credit not found')),
      );
    }

    final balance = Money.fromCents(credit.balanceCents);
    final canPay = _creditEligible && _canRecordPayment;
    final itemsHeld =
        _collateralItems.where((i) => !i.custodyStatus.isTerminal).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Settle Credit')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              Text(
                _error!,
                key: const Key('settle_error_display'),
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 12),
            ],
            if (_paymentError != null) ...[
              Text(
                _paymentError!,
                key: const Key('settle_validation_error_display'),
                style: const TextStyle(color: Colors.orange),
              ),
              const SizedBox(height: 12),
            ],
            if (_successMessage != null) ...[
              Text(
                _successMessage!,
                key: const Key('settle_success_display'),
                style: const TextStyle(color: Colors.green),
              ),
              const SizedBox(height: 12),
            ],

            // Borrower
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Customer',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _customerName ?? 'Customer not found',
                      key: const Key('settle_customer_name'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Credit identity
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Credit Reference: ${credit.id.substring(0, credit.id.length.clamp(0, 8))}...',
                      key: const Key('settle_credit_reference'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('Amount: ${Money.fromCents(credit.principalCents).format()}'),
                    Text('Term: ${_agreedTermLabel(credit)}'),
                    Text('Due: ${credit.dueDateAsCalendarDate(_shopTimeZone)}'),
                    Text('Status: ${credit.status.value.toUpperCase()}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Outstanding balance, prominent
            const Text(
              'Outstanding Balance',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              balance.format(),
              key: const Key('settle_outstanding_balance'),
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap Settle for settlement options — settle in full, enter a '
              'partial amount, propose a balance adjustment, or extend the due '
              'date.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // Collateral at stake
            if (itemsHeld.isEmpty)
              const Text(
                'No collateral items pledged to this credit.',
                key: Key('settle_collateral_summary'),
                style: TextStyle(color: Colors.grey),
              )
            else ...[
              Text(
                'Collateral at stake: ${itemsHeld.length} of ${_collateralItems.length} items still in custody',
                key: const Key('settle_collateral_summary'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              ...itemsHeld.map(
                (item) => Text(
                  'Item ${item.itemReferenceId}: ${item.category.value}'
                  ' (${item.custodyStatus.value.replaceAll('_', ' ')})',
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Settlement does not return pledged items.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 20),

            // Settlement entry (only when eligible)
            if (canPay) ...[
              const Text(
                'Amount to Settle',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('settle_amount_input'),
                controller: _amountController,
                focusNode: _amountFocusNode,
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
                  key: const Key('settle_confirm_button'),
                  onPressed: _isSubmitting ? null : _openSettleSheet,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Settle'),
                ),
              ),
            ] else
              const Text(
                'This credit is not eligible for payment recording.',
                style: TextStyle(color: Colors.grey),
              ),
            if (!canPay && _creditEligible && !_canRecordPayment) ...[
              const SizedBox(height: 8),
              const Text(
                'You do not have the Record Payments permission.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                key: const Key('settle_cancel_button'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),

            // Receipt preview (only after a partial payment stays on screen)
            if (_receipt != null) ...[
              const SizedBox(height: 16),
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
                                        Money.fromCents(_receipt!.amountCents),
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
                      if (_canApproveCorrections) ...[
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
                      if (_canApproveCorrections) ...[
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
