import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/core/permissions/authorization_guard.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_dao.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';
import 'package:credit_system/features/customers/data/daos/customer_dao.dart';
import 'package:credit_system/features/customers/data/daos/credit_dao.dart';
import 'package:credit_system/features/customers/data/daos/overdue_dao.dart';
import 'package:credit_system/features/customers/data/services/document_generation_service_impl.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:credit_system/features/customers/domain/models/credit_term.dart';
import 'package:credit_system/features/customers/domain/services/credit_submission_idempotency.dart';
import 'package:credit_system/features/shop/data/daos/shop_dao.dart';

import 'voucher_pdf_viewer_web.dart' if (dart.library.io) 'voucher_pdf_viewer_mobile.dart';

/// Label for a due date that has not yet been finalised by a confirmed cash
/// disbursement (Story 4.2 / PRD FR-17).
const String preliminaryDueDateLabel =
    'Preliminary Due Date (Pending Disbursement)';

/// Label for a due date that has been finalised by a confirmed cash
/// disbursement (Story 4.3 / PRD FR-19).
const String officialDueDateLabel = 'Official Calendar Due Date';

/// Cash disbursement confirmation screen implementing Story 4.3
/// (PRD FR-19).
///
/// This is a **separate operation** from credit agreement creation: it never
/// creates a credit agreement and never records a payment. It confirms the
/// physical cash handover of an existing `Active / Pending Disbursement`
/// agreement, finalises the official calendar due date, and records the
/// disbursing staff member and the confirmed handover timestamp.
///
/// The screen clearly distinguishes an agreement that is still awaiting
/// disbursement from one whose cash has already been handed over.
class CreditDisbursementScreen extends StatefulWidget {
  /// The active shop tenant UUID.
  final String shopId;

  /// The credit agreement whose cash handover is being confirmed.
  final String creditId;

  /// The authenticated actor confirming the handover.
  final AppUser currentUser;

  /// Optional injected [AppDatabase] for testing.
  final AppDatabase? database;

  /// Optional injected idempotency-key manager for testing.
  final CreditSubmissionIdempotency? idempotency;

  const CreditDisbursementScreen({
    super.key,
    required this.shopId,
    required this.creditId,
    required this.currentUser,
    this.database,
    this.idempotency,
  });

  @override
  State<CreditDisbursementScreen> createState() => _CreditDisbursementScreenState();
}

class _CreditDisbursementScreenState extends State<CreditDisbursementScreen> {
  late final CreditSubmissionIdempotency _idempotency;

  Credit? _credit;
  List<CollateralItem> _collateral = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;
  String? _successMessage;

  /// Whether an official voucher was generated for the confirmed disbursement.
  bool _voucherGenerated = false;

  /// Error from voucher generation (does not roll back the disbursement).
  String? _voucherError;

  /// Generated voucher PDF bytes, retained for preview/download after a
  /// successful generation. Null until a voucher is produced.
  Uint8List? _voucherBytes;

  /// Local file path where the voucher PDF was saved (mobile only). Null on
  /// Web, where the browser handles the download directly.
  String? _voucherFilePath;

  /// The shop's operational time zone.
  ///
  /// The due date is persisted as the UTC instant of shop-local midnight of
  /// the agreed calendar date, so it must be rendered in the shop's own zone
  /// to show the date that was actually agreed (Story 4.3 AC-2).
  ShopTimeZone _shopTimeZone = ShopTimeZone.defaultTimeZone();

  @override
  void initState() {
    super.initState();
    _idempotency = widget.idempotency ?? CreditSubmissionIdempotency();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final db = widget.database ?? AppDatabase();
      final creditDao = CreditDao(db);
      final collateralDao = CollateralDao(db);

      final credit = await creditDao.getCreditById(widget.shopId, widget.creditId);
      final shopTimeZone = await OverdueDao(db).resolveShopTimeZone(widget.shopId);
      final items = credit == null
          ? const <CollateralItem>[]
          : await collateralDao.getCollateralItemsByCreditId(
              widget.shopId,
              credit.id,
            );

      if (!mounted) return;

      setState(() {
        _credit = credit;
        _collateral = items;
        _shopTimeZone = shopTimeZone;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load the credit agreement: $e';
      });
    }
  }

  /// Whether the actor may confirm a cash disbursement.
  bool get _canDisburse =>
      widget.currentUser.isActive &&
      widget.currentUser.effectivePermissions
          .contains(AppPermission.confirmCreditDisbursement);

  /// The agreed term as it should be shown to the operator.
  ///
  /// An agreement created before Story 4.3 carries **no recorded agreed term**
  /// at all, which is different from an agreement with a fixed custom date.
  /// Showing "Custom Date" for such an agreement would misstate it, so the
  /// missing term is shown as such.
  String _agreedTermLabel(Credit credit) {
    if (credit.termPresetDays != null) return '${credit.termPresetDays} Days';
    if (credit.customDueDate != null) return 'Custom Date';
    return 'Not recorded';
  }

  Future<void> _confirm() async {
    final credit = _credit;
    if (credit == null) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
      _successMessage = null;
      _voucherGenerated = false;
      _voucherError = null;
      _voucherBytes = null;
      _voucherFilePath = null;
    });

    try {
      final db = widget.database ?? AppDatabase();
      final creditDao = CreditDao(db);

      // A retry of the same confirmation reuses its key; a genuinely new
      // submission receives a fresh one.
      final fingerprint = CreditSubmissionFingerprint(
        customerId: credit.customerId,
        principalCents: credit.principalCents,
        dueDate: credit.dueDate,
        collateralItemIds: const [],
      );
      final idempotencyKey = _idempotency.keyFor(fingerprint);

      // Capture whether this is a new disbursement (credit was pending) versus
      // an idempotent replay of an already-confirmed handover. A voucher is
      // generated only for a new disbursement, preventing duplicate document
      // events.
      final wasPending = credit.isPendingDisbursement;

      final disbursed = await creditDao.confirmCreditDisbursement(
        actor: widget.currentUser,
        idempotencyKey: idempotencyKey,
        creditId: credit.id,
        disbursedAt: DateTime.now().toUtc(),
      );

      // The cash is now handed over; the next confirmation must use a fresh key.
      _idempotency.reset();

      if (!mounted) return;
      setState(() {
        _credit = disbursed;
        _isSubmitting = false;
        _successMessage =
            'Cash disbursement confirmed. $officialDueDateLabel: '
            '${disbursed.dueDateAsCalendarDate(_shopTimeZone)}';
      });

      // Generate the official voucher only for a new disbursement. Document
      // generation failures do not roll back the disbursement and are reported
      // separately so the confirmed disbursement is never falsely obscured.
      if (wasPending && mounted) {
        await _generateVoucher(disbursed);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = 'Cash disbursement confirmation failed: $e';
      });
      // NOTE: the idempotency key is deliberately NOT reset on failure, so a
      // retry of the same confirmation reuses the same key.
    }
  }

  /// Generates the official voucher for a newly confirmed disbursement.
  ///
  /// The disbursement itself is already committed. If voucher generation fails,
  /// the disbursement is preserved and the failure is surfaced separately — the
  /// screen never claims a voucher was generated when it was not.
  Future<void> _generateVoucher(Credit disbursedCredit) async {
    if (!mounted) return;

    // Deterministic snapshot id derived from the credit id. persistDocumentSnapshot
    // is idempotent for the same id and refuses to overwrite a different one,
    // so retries cannot create duplicate document events.
    final documentSnapshotId = 'snapshot-${disbursedCredit.id}';

    try {
      final db = widget.database ?? AppDatabase();
      final shopDao = ShopDao(db);
      final customerDao = CustomerDao(db);

      final shop = await shopDao.getShopById(widget.shopId);
      final customer = await customerDao.getCustomerById(
          widget.shopId, disbursedCredit.customerId);

      final service = DocumentGenerationServiceImpl();

      // Persist the snapshot reference on the credit row (idempotent for same id).
      await service.persistDocumentSnapshot(
        db: db,
        credit: disbursedCredit,
        documentSnapshotId: documentSnapshotId,
      );

      // Generate the official voucher PDF using confirmed credit values and the
      // shop timezone. The bytes are retained for preview/download; a successful
      // return confirms the voucher was generated.
      final bytes = await service.generateVoucherPdf(
        credit: disbursedCredit,
        actor: widget.currentUser,
        shopTimeZone: _shopTimeZone,
        shopName: shop?.name ?? 'Not recorded',
        shopAddress: shop?.businessAddress ?? 'Not recorded',
        shopPhone: shop?.contactPhone ?? 'Not recorded',
        shopTaxId: shop?.registrationNumber ?? 'Not recorded',
        disbursingStaffId: disbursedCredit.disbursedByUserId ?? 'Not recorded',
        confirmedDueDate: disbursedCredit.dueDate,
        documentSnapshotId: documentSnapshotId,
        customer: customer,
        collateralItems: _collateral,
        shopFooterNotes: shop?.receiptFooterNotes,
      );

      if (!mounted) return;
      setState(() {
        _voucherBytes = bytes;
        _voucherGenerated = true;
        _voucherError = null;
      });
    } on PermissionDeniedException {
      // Authorization failure: do not report a voucher was generated.
      if (!mounted) return;
      setState(() {
        _voucherGenerated = false;
        _voucherError =
            'Voucher not generated: you are not authorized to issue official documents.';
      });
    } on CreditDisbursementStateException {
      if (!mounted) return;
      setState(() {
        _voucherGenerated = false;
        _voucherError =
            'Voucher not generated: the credit is not in a disbursed state.';
      });
    } catch (e) {
      // Any other document-generation failure: disbursement stands, voucher
      // is not reported as generated.
      if (!mounted) return;
      setState(() {
        _voucherGenerated = false;
        _voucherError = 'Voucher generation failed: $e';
      });
    }
  }

  /// Opens or downloads the generated official voucher PDF.
  ///
  /// On Web, triggers a browser download. On Android, saves the PDF to the
  /// app's documents directory and surfaces the file path. The disbursement
  /// itself is never affected by this action.
  Future<void> _viewVoucher() async {
    if (_voucherBytes == null) return;

    final fileName = 'voucher_${_credit!.id}.pdf';
    final savedPath = await viewVoucherPdf(_voucherBytes!, fileName);

    if (!mounted) return;

    if (savedPath != null) {
      setState(() {
        _voucherFilePath = savedPath;
      });
      _showVoucherSavedDialog(savedPath);
    } else {
      _showVoucherDownloadedDialog();
    }
  }

  void _showVoucherSavedDialog(String path) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Official Voucher Saved'),
        content: Text('Voucher PDF saved to:\n$path'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showVoucherDownloadedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Official Voucher Downloaded'),
        content: const Text('The voucher PDF has been downloaded to your device.'),
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
        appBar: AppBar(title: const Text('Confirm Cash Disbursement')),
        body: Center(child: Text('Credit agreement not found')),
      );
    }

    final isDisbursed = credit.isDisbursed;
    final currency = Money.defaultCurrency;

    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Cash Disbursement')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              Text(
                _error!,
                key: const Key('disbursement_error_display'),
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 12),
            ],
            if (_successMessage != null) ...[
              Text(
                _successMessage!,
                key: const Key('disbursement_success_display'),
                style: const TextStyle(color: Colors.green),
              ),
              const SizedBox(height: 12),
            ],
            if (_voucherError != null) ...[
              Text(
                _voucherError!,
                key: const Key('voucher_error_display'),
                style: const TextStyle(color: Colors.orange),
              ),
              const SizedBox(height: 12),
            ],
            if (_voucherGenerated && _voucherError == null) ...[
              Text(
                'Official disbursement voucher generated.',
                key: const Key('voucher_generated_display'),
                style: const TextStyle(color: Colors.green),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  key: const Key('view_voucher_button'),
                  onPressed: _viewVoucher,
                  child: const Text('View Official Voucher'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_voucherFilePath != null) ...[
              Text(
                'Saved: $_voucherFilePath',
                key: const Key('voucher_saved_path_display'),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
            ],

            // --- Disbursement state banner ---
            Card(
              key: const Key('disbursement_state_banner'),
              color: isDisbursed
                  ? Colors.green.withValues(alpha: 0.15)
                  : Colors.amber.withValues(alpha: 0.15),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isDisbursed
                          ? 'Cash Disbursed'
                          : 'Awaiting Cash Disbursement',
                      key: const Key('disbursement_state_display'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Financial Status: ${credit.status.value.toUpperCase()}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      'Workflow Status: ${credit.workflowStatus.value.toUpperCase()}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (isDisbursed && credit.disbursedAt != null) ...[
                      Text(
                        'Cash Handed Over: '
                        '${credit.disbursedAt!.toIso8601String().substring(0, 19)}Z',
                        key: const Key('disbursement_timestamp_display'),
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'Disbursed By: ${credit.disbursedByUserId}',
                        key: const Key('disbursement_actor_display'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // --- Agreement summary ---
            Text(
              'Amount: ${Money(credit.principalCents, currency: currency).format()}',
              style: const TextStyle(fontSize: 14),
            ),
            Text(
              'Outstanding Balance: '
              '${Money(credit.balanceCents, currency: currency).format()}',
              style: const TextStyle(fontSize: 14),
            ),
            Text(
              'Agreed Term: ${_agreedTermLabel(credit)}',
              key: const Key('disbursement_term_display'),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),

            // The due date is labelled as preliminary until the cash has
            // actually been handed over, and as official afterwards. It is
            // rendered as the calendar date in the shop's own time zone,
            // because the persisted instant is shop-local midnight.
            Text(
              isDisbursed
                  ? '$officialDueDateLabel: '
                      '${credit.dueDateAsCalendarDate(_shopTimeZone)}'
                  : '$preliminaryDueDateLabel: '
                      '${credit.dueDateAsCalendarDate(_shopTimeZone)}',
              key: const Key('disbursement_due_date_display'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            if (_collateral.isNotEmpty) ...[
              const Text(
                'Item Receipts',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              for (final item in _collateral)
                Text(
                  '${item.itemReferenceId} - ${item.description ?? 'Unspecified'}',
                  style: const TextStyle(fontSize: 12),
                ),
              const SizedBox(height: 16),
            ],

            if (!isDisbursed)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  key: const Key('confirm_disbursement_button'),
                  onPressed: (!_canDisburse || _isSubmitting) ? null : _confirm,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Confirm Cash Disbursement'),
                ),
              )
            else
              const Text(
                'This agreement has already been disbursed. It cannot be '
                'disbursed again.',
                key: Key('already_disbursed_notice'),
                style: TextStyle(fontSize: 12),
              ),

            if (!isDisbursed && !_canDisburse) ...[
              const SizedBox(height: 8),
              const Text(
                'The `Confirm Credit Disbursement` permission is required to '
                'confirm a cash handover.',
                key: Key('disbursement_permission_notice'),
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


