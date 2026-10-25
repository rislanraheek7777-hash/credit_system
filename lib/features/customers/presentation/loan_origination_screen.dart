import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_dao.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';
import 'package:credit_system/features/customers/data/daos/customer_dao.dart';
import 'package:credit_system/features/customers/data/daos/loan_dao.dart';
import 'package:credit_system/features/customers/data/services/document_generation_service_impl.dart';
import 'package:credit_system/features/customers/domain/models/loan.dart';
import 'package:credit_system/features/customers/domain/models/loan_term.dart';
import 'package:credit_system/features/customers/domain/services/loan_submission_idempotency.dart';
import 'package:credit_system/features/shop/data/daos/shop_dao.dart';
import 'package:credit_system/features/shop/domain/models/shop_profile.dart';
import 'voucher_pdf_viewer_web.dart' if (dart.library.io) 'voucher_pdf_viewer_mobile.dart';

/// The exact label mandated by Story 4.2 AC-1 and PRD FR-17 for a date that
/// has not yet been finalised by cash disbursement.
const String preliminaryDueDateLabel =
    'Preliminary Due Date (Pending Disbursement)';

/// Live loan origination summary (Story 4.2 AC-3, UX-DR-4).
///
/// Displays the preliminary due date and the total estimated collateral
/// value, updating dynamically as term terms or collateral items change.
class LoanOriginationSummary extends StatelessWidget {
  /// The currently selected term, or `null` when none has been chosen.
  final LoanTerm? term;

  /// The computed preliminary due date, or `null` when no term is selected.
  final DateTime? preliminaryDueDate;

  /// The total estimated collateral value in integer minor units.
  final int totalCollateralValueCents;

  /// The shop's ISO 4217 currency code.
  final String currencyCode;

  /// The shop's operational IANA time zone identifier.
  final String timeZoneIdentifier;

  const LoanOriginationSummary({
    super.key,
    required this.term,
    required this.preliminaryDueDate,
    required this.totalCollateralValueCents,
    required this.currencyCode,
    required this.timeZoneIdentifier,
  });

  @override
  Widget build(BuildContext context) {
    final dueDate = preliminaryDueDate;
    final dueDateText = dueDate == null
        ? 'Not selected'
        : _formatLocalDate(dueDate);

    final collateralTotal = Money(
      totalCollateralValueCents,
      currency: currencyCode,
    ).format();

    return Card(
      key: const Key('loan_origination_summary'),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Loan Summary',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Selected Term: ${term?.displayLabel ?? 'Not selected'}',
              key: const Key('selected_term_display'),
            ),
            const SizedBox(height: 8),
            Text(
              '$preliminaryDueDateLabel: $dueDateText',
              key: const Key('preliminary_due_date_display'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Total Estimated Collateral Value: $collateralTotal',
              key: const Key('total_collateral_value_display'),
            ),
            const SizedBox(height: 4),
            Text(
              'Time zone: $timeZoneIdentifier',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  /// Renders [instant] as a calendar date in the shop's time zone.
  ///
  /// Uses the shop's configured IANA identifier so the displayed date always
  /// matches the date that was calculated in — and persisted in — that zone.
  /// An unresolvable identifier falls back to the approved default, mirroring
  /// the origination screen's own resolution.
  String _formatLocalDate(DateTime instant) {
    final shopZone = _resolveTimeZone();
    return shopZone.localDateOf(instant).isoDate;
  }

  /// Resolves [timeZoneIdentifier] to a usable shop time zone.
  ShopTimeZone _resolveTimeZone() {
    try {
      return ShopTimeZone(timeZoneIdentifier);
    } on UnsupportedShopTimeZoneException {
      return ShopTimeZone.defaultTimeZone();
    }
  }
}

/// Loan origination screen implementing Story 4.2 (PRD FR-17).
///
/// Provides term selection (30/60/90 calendar-day presets or a custom
/// calendar due date), live preliminary due-date calculation in the shop's
/// operational time zone, a live collateral valuation summary, and submission
/// of the agreement through [LoanDao.createLoanAgreement].
///
/// The authenticated [currentUser] is passed straight through as the `actor`
/// so that the DAO's own authorization and transaction behaviour applies
/// (F4). The idempotency key is managed by [LoanSubmissionIdempotency] so a
/// retry of the same submission reuses its key while a genuinely new
/// submission receives a fresh one (F3).
class LoanOriginationScreen extends StatefulWidget {
  /// The active shop tenant UUID.
  final String shopId;

  /// The borrower the agreement is created for.
  final String customerId;

  /// The authenticated actor performing the origination.
  final AppUser currentUser;

  /// Optional injected [AppDatabase] for testing.
  final AppDatabase? database;

  /// Optional injected idempotency-key manager for testing (F3).
  ///
  /// When omitted, the screen creates its own [LoanSubmissionIdempotency].
  /// Injecting one allows tests to observe the key lifecycle directly.
  final LoanSubmissionIdempotency? idempotency;

  const LoanOriginationScreen({
    super.key,
    required this.shopId,
    required this.customerId,
    required this.currentUser,
    this.database,
    this.idempotency,
  });

  @override
  State<LoanOriginationScreen> createState() => _LoanOriginationScreenState();
}

class _LoanOriginationScreenState extends State<LoanOriginationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _principalController = TextEditingController();
  final _customDateController = TextEditingController();

  /// The agreement creation date; captured once so the live preview and the
  /// persisted agreement agree.
  late final DateTime _creationDate;

  late final LoanSubmissionIdempotency _idempotency;

  List<CollateralItem> _collateralItems = [];
  final Set<String> _selectedCollateralIds = <String>{};
  LoanTerm? _term;
  ShopProfile? _shop;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;
  String? _successMessage;
  Loan? _createdLoan;
  bool _isGeneratingDraft = false;
  bool _draftGenerated = false;
  String? _draftError;
  String? _draftFilePath;

  @override
  void initState() {
    super.initState();
    _creationDate = DateTime.now().toUtc();
    _idempotency = widget.idempotency ?? LoanSubmissionIdempotency();
    _load();
  }

  @override
  void dispose() {
    _principalController.dispose();
    _customDateController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final db = widget.database ?? AppDatabase();
      final shopDao = ShopDao(db);
      final collateralDao = CollateralDao(db);

      final shop = await shopDao.getShopById(widget.shopId);
      final items = await collateralDao.getCollateralItemsByCustomerId(
        widget.shopId,
        widget.customerId,
      );

      if (!mounted) return;

      setState(() {
        _shop = shop;
        _collateralItems = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load origination context: $e';
      });
    }
  }

  /// The shop's operational time zone, defaulting to the approved
  /// `Asia/Colombo` when the shop has not configured one.
  ShopTimeZone get _shopTimeZone {
    final identifier = _shop?.timezone ?? ShopTimeZone.defaultIdentifier;
    try {
      return ShopTimeZone(identifier);
    } on UnsupportedShopTimeZoneException {
      return ShopTimeZone.defaultTimeZone();
    }
  }

  String get _currencyCode => _shop?.currencyCode ?? Money.defaultCurrency;

  /// The parsed principal amount, or `null` when absent/invalid.
  Money? get _principal {
    final text = _principalController.text.trim();
    if (text.isEmpty) return null;
    return Money.tryParse(text, currency: _currencyCode);
  }

  /// The computed preliminary due date for the selected term, or `null`.
  DateTime? get _preliminaryDueDate {
    final term = _term;
    if (term == null) return null;
    try {
      return PreliminaryDueDateCalculator(shopTimeZone: _shopTimeZone)
          .preliminaryDueDateFor(_creationDate, term);
    } on LoanTermValidationException {
      return null;
    }
  }

  /// The total estimated value of the selected collateral items.
  int get _totalCollateralValueCents {
    var total = 0;
    for (final item in _collateralItems) {
      if (_selectedCollateralIds.contains(item.id)) {
        total += item.estimatedValueCents;
      }
    }
    return total;
  }

  void _selectPreset(LoanTermPreset preset) {
    setState(() {
      _term = LoanTerm.preset(preset);
      _customDateController.clear();
      _error = null;
    });
  }

  void _selectCustomDate(LocalCalendarDate date) {
    setState(() {
      _term = LoanTerm.custom(date);
      _customDateController.text = date.isoDate;
      _error = null;
    });
  }

  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null || !mounted) return;
    _selectCustomDate(LocalCalendarDate.fromDateTime(picked));
  }

  /// Validates the custom date typed into the ISO text field.
  ///
  /// Enforces `Custom Due Date > Agreement Creation Date` (PRD FR-17) before
  /// the term is applied, so an invalid date never becomes the selected term.
  void _applyTypedCustomDate() {
    final text = _customDateController.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Custom due date is required.');
      return;
    }
    try {
      final parsed = LocalCalendarDate.parseIso(text);
      PreliminaryDueDateCalculator(shopTimeZone: _shopTimeZone)
          .validateCustomDate(_creationDate, parsed);
      _selectCustomDate(parsed);
    } on LoanTermValidationException catch (e) {
      setState(() => _error = e.message);
    } on FormatException {
      setState(() => _error = 'Custom due date must be in YYYY-MM-DD format.');
    }
  }

  void _toggleCollateral(String itemId) {
    setState(() {
      if (!_selectedCollateralIds.remove(itemId)) {
        _selectedCollateralIds.add(itemId);
      }
      _error = null;
    });
  }

  /// Submits the agreement through [LoanDao.createLoanAgreement].
  ///
  /// The idempotency key is bound to the submission's fingerprint (F3), and
  /// the authenticated user is passed straight through as the actor (F4).
  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final term = _term;
    final principal = _principal;
    final dueDate = _preliminaryDueDate;

    if (term == null) {
      setState(() => _error = 'Select a loan term before submitting.');
      return;
    }
    if (principal == null || !principal.isPositive) {
      setState(() => _error = 'Enter a valid positive principal amount.');
      return;
    }
    if (dueDate == null) {
      setState(() =>
          _error = 'The selected term does not yield a valid preliminary due date.');
      return;
    }
    if (_selectedCollateralIds.isEmpty) {
      setState(() => _error = 'Select at least one collateral item.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final db = widget.database ?? AppDatabase();
      final loanDao = LoanDao(db);

      final fingerprint = LoanSubmissionFingerprint(
        customerId: widget.customerId,
        principalCents: principal.minorUnits,
        dueDate: dueDate,
        collateralItemIds: _selectedCollateralIds.toList(),
      );
      final idempotencyKey = _idempotency.keyFor(fingerprint);

      final loan = await loanDao.createLoanAgreement(
        actor: widget.currentUser,
        idempotencyKey: idempotencyKey,
        customerId: widget.customerId,
        principal: principal,
        dueDate: dueDate,
        createdAt: _creationDate,
        collateralItemIds: _selectedCollateralIds.toList(),
        // The agreed term is persisted so that Story 4.3 can finalise the
        // official due date from the confirmed disbursement date.
        termPresetDays: term.preset?.calendarDays,
        customDueDate: term.isCustom
            ? _shopTimeZone.instantAtStartOfDay(term.customDate!)
            : null,
      );

      // The agreement now exists; a subsequent submission must use a fresh key.
      _idempotency.reset();

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _createdLoan = loan;
        _draftGenerated = false;
        _draftError = null;
        _draftFilePath = null;
        _successMessage =
            'Loan agreement ${loan.id} created. Due date (preliminary): '
            '${_shopTimeZone.localDateOf(loan.dueDate).isoDate}.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = 'Loan agreement creation failed: $e';
      });
      // NOTE: the idempotency key is deliberately NOT reset on failure, so a
      // retry of the same submission reuses the same key (F3).
    }
  }

  Future<void> _viewDraftAgreement() async {
    if (_createdLoan == null) return;
    setState(() {
      _isGeneratingDraft = true;
      _draftError = null;
    });

    try {
      final db = widget.database ?? AppDatabase();
      final shopDao = ShopDao(db);
      final customerDao = CustomerDao(db);

      final shop = await shopDao.getShopById(widget.shopId);
      final customer =
          await customerDao.getCustomerById(widget.shopId, widget.customerId);
      final collateralList = _collateralItems
          .where((item) => _selectedCollateralIds.contains(item.id))
          .toList();

      final service = DocumentGenerationServiceImpl();
      final bytes = await service.generateDraftPdf(
        loan: _createdLoan!,
        actor: widget.currentUser,
        shopTimeZone: _shopTimeZone,
        shopName: shop?.name ?? 'Not recorded',
        shopAddress: shop?.businessAddress ?? 'Not recorded',
        shopPhone: shop?.contactPhone ?? 'Not recorded',
        shopTaxId: shop?.registrationNumber ?? 'Not recorded',
        disbursingStaffId: widget.currentUser.id,
        customer: customer,
        collateralItems: collateralList,
      );

      await service.recordDocumentAuditEvent(
        db: db,
        shopId: widget.shopId,
        actorId: widget.currentUser.id,
        actionType: DocumentGenerationServiceImpl.draftGeneratedActionType,
        customerId: widget.customerId,
        loanId: _createdLoan!.id,
        isDraft: true,
      );

      final fileName = 'draft_agreement_${_createdLoan!.id}.pdf';
      final savedPath = await viewVoucherPdf(bytes, fileName);

      if (!mounted) return;
      setState(() {
        _isGeneratingDraft = false;
        _draftGenerated = true;
        _draftFilePath = savedPath;
      });

      if (savedPath != null) {
        _showDraftSavedDialog(savedPath);
      } else {
        _showDraftDownloadedDialog();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGeneratingDraft = false;
        _draftError = 'Failed to generate draft agreement: $e';
      });
    }
  }

  void _showDraftSavedDialog(String path) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Draft Agreement Saved'),
        content: Text('Draft agreement PDF saved to:\n$path'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showDraftDownloadedDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Draft Agreement Downloaded'),
        content: const Text(
          'The draft agreement PDF has been downloaded to your device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
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

    return Scaffold(
      appBar: AppBar(title: const Text('Loan Origination')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[
                Text(
                  _error!,
                  key: const Key('origination_error_display'),
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 12),
              ],
              if (_successMessage != null) ...[
                Text(
                  _successMessage!,
                  key: const Key('origination_success_display'),
                  style: const TextStyle(color: Colors.green),
                ),
                const SizedBox(height: 12),
              ],
              if (_createdLoan != null) ...[
                if (_draftError != null) ...[
                  Text(
                    _draftError!,
                    key: const Key('draft_error_display'),
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 8),
                ],
                if (_draftGenerated && _draftError == null) ...[
                  const Text(
                    'Draft agreement slip generated.',
                    key: Key('draft_generated_display'),
                    style: TextStyle(color: Colors.green),
                  ),
                  const SizedBox(height: 8),
                ],
                ElevatedButton.icon(
                  key: const Key('view_draft_agreement_button'),
                  onPressed: _isGeneratingDraft ? null : _viewDraftAgreement,
                  icon: _isGeneratingDraft
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.description_outlined),
                  label: const Text('View / Print Draft Agreement'),
                ),
                if (_draftFilePath != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Saved: $_draftFilePath',
                    key: const Key('draft_saved_path_display'),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
                const SizedBox(height: 16),
              ],

              // --- Principal ---
              const Text(
                'Principal Amount',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('principal_amount_field'),
                controller: _principalController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Principal Amount ($_currencyCode)',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Principal amount is required';
                  final money = Money.tryParse(text, currency: _currencyCode);
                  if (money == null) return 'Invalid monetary amount';
                  if (!money.isPositive) {
                    return 'Principal amount must be a positive amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // --- Term selection ---
              const Text(
                'Loan Term',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final preset in LoanTermPreset.values)
                    ChoiceChip(
                      key: Key('term_preset_${preset.calendarDays}'),
                      label: Text(preset.label),
                      selected: _term?.preset == preset,
                      onSelected: (_) => _selectPreset(preset),
                    ),
                  ChoiceChip(
                    key: const Key('term_custom'),
                    label: const Text('Custom Date'),
                    selected: _term?.isCustom ?? false,
                    onSelected: (_) => _pickCustomDate(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('custom_due_date_field'),
                      controller: _customDateController,
                      decoration: const InputDecoration(
                        labelText: 'Custom Due Date (YYYY-MM-DD)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    key: const Key('apply_custom_due_date_button'),
                    onPressed: _applyTypedCustomDate,
                    child: const Text('Apply'),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // --- Collateral selection ---
              const Text(
                'Pledged Collateral',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (_collateralItems.isEmpty)
                const Text('No collateral items registered for this customer.'),
              for (final item in _collateralItems)
                CheckboxListTile(
                  key: Key('collateral_item_${item.id}'),
                  dense: true,
                  value: _selectedCollateralIds.contains(item.id),
                  onChanged: (_) => _toggleCollateral(item.id),
                  title: Text(item.itemReferenceId),
                  subtitle: Text(
                    '${item.description} — '
                    '${Money(item.estimatedValueCents, currency: _currencyCode).format()}',
                  ),
                ),
              const SizedBox(height: 16),

              // --- Live summary (AC-3 / UX-DR-4) ---
              LoanOriginationSummary(
                term: _term,
                preliminaryDueDate: _preliminaryDueDate,
                totalCollateralValueCents: _totalCollateralValueCents,
                currencyCode: _currencyCode,
                timeZoneIdentifier: _shop?.timezone ??
                    ShopTimeZone.defaultIdentifier,
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  key: const Key('submit_loan_button'),
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create Loan Agreement'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
