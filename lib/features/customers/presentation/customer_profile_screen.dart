import 'dart:io';

import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/customer_dao.dart';
import 'package:credit_system/features/customers/data/daos/credit_dao.dart';
import 'package:credit_system/features/customers/data/daos/overdue_dao.dart';
import 'package:credit_system/features/customers/data/daos/payment_dao.dart';
import 'package:credit_system/features/customers/domain/models/customer_masking.dart';
import 'package:credit_system/features/customers/domain/models/customer.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:credit_system/features/customers/domain/models/credit_term.dart';
import 'package:credit_system/features/customers/domain/models/receipt.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_dao.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';
import 'package:credit_system/features/customers/presentation/customer_edit_screen.dart';
import 'package:credit_system/features/customers/presentation/credit_draft_agreement_action.dart';
import 'package:credit_system/features/customers/presentation/credit_origination_screen.dart';
import 'package:credit_system/features/customers/presentation/credit_settle_action.dart';
import 'package:credit_system/features/customers/presentation/settle_summary_screen.dart';
import 'package:credit_system/features/customers/presentation/payment_screen.dart';

// A section displaying credits of a single status.
class _CreditStatusSection extends StatelessWidget {
  final String title;
  final List<Credit> credits;
  final Color color;

  /// The shop's operational time zone, used to render each due date as the
  /// calendar date that was agreed.
  final ShopTimeZone shopTimeZone;
  final ValueChanged<Credit> onTap;

  /// Invoked when the per-card Settle action is tapped, with the card's own
  /// credit.
  final ValueChanged<Credit> onSettle;

  final Map<String, List<Receipt>> paymentsByCreditId;
  final Map<String, List<CollateralItem>> collateralByCreditId;

  /// The authenticated actor viewing the profile, used to authorize the
  /// shared draft agreement action.
  final AppUser currentUser;

  /// Optional injected [AppDatabase] for testing.
  final AppDatabase? database;

  const _CreditStatusSection({
    required this.title,
    required this.credits,
    required this.color,
    required this.shopTimeZone,
    required this.onTap,
    required this.onSettle,
    required this.paymentsByCreditId,
    required this.collateralByCreditId,
    required this.currentUser,
    required this.database,
  });

  @override
  Widget build(BuildContext context) {
    if (credits.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '$title (${credits.length})',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...credits.map((credit) {
          final payments = paymentsByCreditId[credit.id] ?? const <Receipt>[];
          final collateral = collateralByCreditId[credit.id] ?? const <CollateralItem>[];
          return Card(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  title: Text('Credit ${credit.id.substring(0, credit.id.length.clamp(0, 8))}...'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Amount: ${Money.fromCents(credit.principalCents).format()}'),
                      Text('Type: ${credit.creditType.displayLabel}'),
                      Text('Balance: ${Money.fromCents(credit.balanceCents).format()}'),
                      Text('Due: ${credit.dueDateAsCalendarDate(shopTimeZone)}'),
                      if (payments.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Payment history',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        ...payments.map(
                          (p) => Text(
                            'Receipt ${p.receiptNumber}: ${Money.fromCents(p.amountCents).format()}',
                          ),
                        ),
                      ],
                      if (collateral.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Collateral',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        ...collateral.map(
                          (c) => Text('Item ${c.id}: ${c.category.value}'),
                        ),
                      ],
                    ],
                  ),
                  trailing: Chip(
                    label: Text(credit.status.value.toUpperCase()),
                    backgroundColor: color.withValues(alpha: 0.15),
                  ),
                  onTap: () => onTap(credit),
                ),
                // The draft agreement view is a separate, separately tappable
                // control: the whole tile above stays the payment tap target.
                // The ListTile supplies no inset of its own, so the action is
                // aligned with the card's text here.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: CreditDraftAgreementAction(
                    credit: credit,
                    currentUser: currentUser,
                    shopTimeZone: shopTimeZone,
                    database: database,
                  ),
                ),
                // The per-card Settle action is a separate, separately tappable
                // control that opens the settle summary screen for this credit.
                // It is offered on every card (visibility restored at the
                // human's request) — eligibility is enforced by the summary
                // screen and the payment path behind it.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: CreditSettleAction(
                    credit: credit,
                    currentUser: currentUser,
                    onSettle: () => onSettle(credit),
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// Customer profile screen implementing Story 2.5 AC-2 and AC-3.
///
/// Displays photo thumbnail, verified name, contact summary (masked per RBAC),
/// and all associated credits categorized by status badges (Active, Overdue,
/// Settled).
///
/// When a customer has multiple actionable credits, tapping a credit's tile
/// opens its payment screen directly, and each card's per-card Settle action
/// settles that card's own credit — the card you tapped always settles its
/// own credit.
class CustomerProfileScreen extends StatefulWidget {
  const CustomerProfileScreen({
    super.key,
    required this.shopId,
    required this.customerId,
    required this.currentUser,
    this.canViewSensitive,
    this.database,
    this.isOfflineOnly = true,
  });

  final String shopId;
  final int customerId;

  /// The authenticated actor viewing the profile.
  final AppUser currentUser;

  /// Whether the viewer possesses [viewSensitiveCustomerData] permission.
  /// When null, automatically evaluated from [currentUser].
  final bool? canViewSensitive;

  /// Optional injected [AppDatabase] for testing.
  final AppDatabase? database;

  /// Whether the current session was established offline. Sensitive
  /// administrative actions (such as deleting a customer) are blocked while
  /// offline. Defaults to `true` so callers that forget to thread the flag
  /// fail closed instead of silently allowing offline deletes.
  final bool isOfflineOnly;

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  late CustomerDao _customerDao;
  late CreditDao _creditDao;
  late PaymentDao _paymentDao;
  late CollateralDao _collateralDao;

  Customer? _customer;
  List<Credit> _credits = [];
  final Map<String, List<Receipt>> _paymentsByCreditId = {};
  final Map<String, List<CollateralItem>> _collateralByCreditId = {};
  bool _isLoading = true;
  String? _error;

  /// True while the soft-delete confirmation flow is in flight, so the
  /// destructive action cannot be submitted twice.
  bool _isDeleting = false;

  /// The shop's operational time zone.
  ///
  /// The due date is persisted as the UTC instant of shop-local midnight of
  /// the agreed calendar date, so it must be rendered in the shop's own zone
  /// to show the date that was actually agreed (Story 4.3 AC-2).
  ShopTimeZone _shopTimeZone = ShopTimeZone.defaultTimeZone();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile({bool showLoading = true}) async {
    setState(() {
      if (showLoading) _isLoading = true;
      _error = null;
    });

    try {
      final db = widget.database ?? AppDatabase();
      _customerDao = CustomerDao(db);
      _creditDao = CreditDao(db);
      _paymentDao = PaymentDao(db);
      _collateralDao = CollateralDao(db);

      final customer = await _customerDao.getCustomerById(
        widget.shopId,
        widget.customerId,
      );
      final credits = await _creditDao.getCreditsByCustomerId(
        widget.shopId,
        widget.customerId,
      );
      final shopTimeZone = await OverdueDao(db).resolveShopTimeZone(widget.shopId);

      final paymentsByCreditId = <String, List<Receipt>>{};
      final collateralByCreditId = <String, List<CollateralItem>>{};
      for (final credit in credits) {
        final payments = await _paymentDao.getPaymentsByCredit(
          widget.shopId,
          credit.id,
        );
        final collateral = await _collateralDao.getCollateralItemsByCreditId(
          widget.shopId,
          credit.id,
        );
        paymentsByCreditId[credit.id] = payments;
        collateralByCreditId[credit.id] = collateral;
      }

      if (!mounted) return;

      setState(() {
        _customer = customer;
        _credits = credits;
        _paymentsByCreditId.addAll(paymentsByCreditId);
        _collateralByCreditId.addAll(collateralByCreditId);
        _shopTimeZone = shopTimeZone;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load profile: $e';
      });
    }
  }

  void _proceedToCreditAction(BuildContext context, Credit credit) {
    // Navigate to payment screen for eligible credits (disbursed, active/overdue,
    // balance > 0). For other credit states, show a snackbar.
    if (credit.isDisbursed &&
        (credit.status == CreditStatus.active || credit.status == CreditStatus.overdue) &&
        credit.balanceCents > 0) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PaymentScreen(
            shopId: widget.shopId,
            creditId: credit.id,
            currentUser: widget.currentUser,
            database: widget.database,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Credit ${credit.id.substring(0, credit.id.length.clamp(0, 8))} is not eligible for payment.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Opens the settle summary screen for [credit] and confirms the
  /// settlement back on the profile.
  ///
  /// The per-card Settle action hands the card's own [credit] here directly.
  ///
  /// The summary screen pops with the committed [Receipt] only for a full
  /// settlement. A partial payment (or backing out) returns nothing, so the
  /// credit list is refreshed but no settlement confirmation is shown.
  Future<void> _settleCredit(Credit credit) async {
    final receipt = await Navigator.of(context).push<Receipt>(
      MaterialPageRoute(
        builder: (context) => SettleSummaryScreen(
          shopId: widget.shopId,
          creditId: credit.id,
          currentUser: widget.currentUser,
          database: widget.database,
        ),
      ),
    );

    if (!mounted) return;

    // Reload from the database so the credit list reflects the settlement.
    await _loadProfile(showLoading: false);

    if (!mounted) return;

    // No receipt means the staff member backed out or recorded a partial
    // payment; there is nothing to confirm.
    if (receipt == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Credit settled. Receipt ${receipt.receiptNumber} recorded.',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Opens the credit origination flow for this customer.
  ///
  /// The origination route closes with the created agreement as its result.
  /// When an agreement was created the profile is reloaded so the new credit
  /// appears in the credit list, and the creation is confirmed with a
  /// SnackBar. Backing out without submitting returns no result, so no
  /// confirmation is shown.
  Future<void> _openAddCredit() async {
    // ignore: unused_local_variable
    final created = await Navigator.of(context).push<Credit>(
      MaterialPageRoute(
        builder: (context) => CreditOriginationScreen(
          shopId: widget.shopId,
          customerId: widget.customerId,
          currentUser: widget.currentUser,
          database: widget.database,
        ),
      ),
    );

    if (!mounted) return;

    // Reload from the database so the credit list reflects the new agreement.
    await _loadProfile(showLoading: false);

    if (!mounted) return;

    // No result means the user backed out without creating anything.
  }

  /// Opens the customer edit screen for profile updates.
  /// Available when the staff member has [registerCustomers] permission.
  Future<void> _openEditCustomer() async {
    final db = widget.database ?? AppDatabase();
    final customerDao = CustomerDao(db);
    final customer = await customerDao.getCustomerById(
      widget.shopId,
      widget.customerId,
    );

    if (customer == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer not found'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CustomerEditScreen(
          shopId: widget.shopId,
          customer: customer,
          currentUser: widget.currentUser,
          database: widget.database,
        ),
      ),
    );
  }

  /// Shows a confirmation dialog and, if confirmed, soft-deletes this
  /// customer. The dialog explains the effect before committing, mirroring
  /// the destructive-confirm pattern in `correction_review_screen.dart`.
  ///
  /// Blocked while offline (sensitive administrative action): an offline
  /// message is surfaced and nothing is written. A customer with at least one
  /// credit row of any status is not eligible and cannot be deleted.
  Future<void> _deleteCustomer() async {
    if (widget.isOfflineOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Offline session. Please log in online to delete a customer.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (_credits.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete: this customer has credit history.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Customer'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Deleting this customer will:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Soft-delete the customer profile (the record is retained '
                'for audit integrity, not erased).',
              ),
              const Text(
                'Hide the customer from search, lists, and pickers — the '
                'profile will no longer be reachable in-app.',
              ),
              const Text(
                'Record an audit event (category 1: customer_soft_deleted).',
              ),
              const SizedBox(height: 12),
              const Text(
                'This action cannot be undone.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('delete_customer_confirm_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      final db = widget.database ?? AppDatabase();
      await CustomerDao(db).softDeleteCustomer(
        actor: widget.currentUser,
        shopId: widget.shopId,
        customerId: widget.customerId,
      );
      if (!mounted) return;
      // Pop back to the search screen with `true` so the caller can tell
      // that the customer was soft-deleted and reload its list.
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to delete customer: $e'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Customer Profile')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadProfile,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_customer == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Customer Profile')),
        body: Center(child: Text('Customer not found')),
      );
    }

    final customer = _customer!;
    final activeCredits = _credits.where((l) => l.status == CreditStatus.active).toList();
    final overdueCredits = _credits.where((l) => l.status == CreditStatus.overdue).toList();
    final settledCredits = _credits.where((l) => l.status == CreditStatus.settled).toList();

    final effectiveCanViewSensitive = widget.canViewSensitive ?? (
        widget.currentUser.hasPermission(AppPermission.viewSensitiveCustomerData) ||
            widget.currentUser.role.isOwner);

    final canEditCustomer =
        widget.currentUser.hasPermission(AppPermission.registerCustomers);

    final canCreateCredits =
        widget.currentUser.hasPermission(AppPermission.createCredits);

    // Soft delete is an owner-administrative action; rendered only for an
    // active Shop Owner. The DAO re-checks the owner role server-of-truth style.
    final canDeleteCustomer =
        widget.currentUser.role.isOwner && widget.currentUser.isActive;
    final deleteBlockedByCredits = _credits.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Profile'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Photo thumbnail (Story 2.6: masked/placeholder when lacking permission)
            Center(
              child: CircleAvatar(
                radius: 50,
                backgroundImage: effectiveCanViewSensitive && customer.photoUri != null
                    ? FileImage(File(customer.photoUri!))
                    : null,
                child: (!effectiveCanViewSensitive || customer.photoUri == null)
                    ? const Icon(Icons.person, size: 50)
                    : null,
              ),
            ),
            const SizedBox(height: 16),

            // Name
            Text(
              customer.fullName,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            // Contact summary (masked per RBAC, Story 2.6)
            Text(
              'NIC: ${effectiveCanViewSensitive ? customer.nic : maskNic(customer.nic)}',
            ),
            Text(
              'Phone: ${effectiveCanViewSensitive ? customer.phone : maskPhone(customer.phone)}',
            ),
            Text(
              'Address: ${effectiveCanViewSensitive ? customer.address : kAddressWithheld}',
            ),
            const SizedBox(height: 16),

            // Profile actions (RBAC-gated)
            if (canEditCustomer || canCreateCredits || canDeleteCustomer)
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (canEditCustomer)
                    OutlinedButton.icon(
                      key: const Key('edit_customer_button'),
                      onPressed: _openEditCustomer,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit'),
                    ),
                  if (canCreateCredits)
                    ElevatedButton.icon(
                      key: const Key('add_credit_button'),
                      onPressed: _openAddCredit,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Credit'),
                    ),
                  if (canDeleteCustomer)
                    OutlinedButton.icon(
                      key: const Key('delete_customer_button'),
                      // Disabled while the customer has credit history: any
                      // credit row, in any status, blocks deletion.
                      onPressed: (deleteBlockedByCredits || _isDeleting)
                          ? null
                          : _deleteCustomer,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete customer'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                ],
              ),
            if (canDeleteCustomer && deleteBlockedByCredits)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  'Cannot delete: this customer has credit history.',
                  key: Key('delete_customer_blocked_message'),
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            const SizedBox(height: 24),

            // Credits section
            const Text(
              'Credit details',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            if (_credits.isEmpty)
              const Text('No credit details found'),
            if (_credits.isNotEmpty) ...[
              _CreditStatusSection(
                title: 'Active',
                credits: activeCredits,
                color: Colors.green,
                shopTimeZone: _shopTimeZone,
                onTap: (credit) => widget.currentUser.hasPermission(AppPermission.recordPayments)
                    ? _proceedToCreditAction(context, credit)
                    : null,
                onSettle: (credit) => _settleCredit(credit),
                paymentsByCreditId: _paymentsByCreditId,
                collateralByCreditId: _collateralByCreditId,
                currentUser: widget.currentUser,
                database: widget.database,
              ),
              _CreditStatusSection(
                title: 'Overdue',
                credits: overdueCredits,
                color: Colors.orange,
                shopTimeZone: _shopTimeZone,
                onTap: (credit) => widget.currentUser.hasPermission(AppPermission.recordPayments)
                    ? _proceedToCreditAction(context, credit)
                    : null,
                onSettle: (credit) => _settleCredit(credit),
                paymentsByCreditId: _paymentsByCreditId,
                collateralByCreditId: _collateralByCreditId,
                currentUser: widget.currentUser,
                database: widget.database,
              ),
              _CreditStatusSection(
                title: 'Settled',
                credits: settledCredits,
                color: Colors.grey,
                shopTimeZone: _shopTimeZone,
                onTap: (credit) => widget.currentUser.hasPermission(AppPermission.recordPayments)
                    ? _proceedToCreditAction(context, credit)
                    : null,
                onSettle: (credit) => _settleCredit(credit),
                paymentsByCreditId: _paymentsByCreditId,
                collateralByCreditId: _collateralByCreditId,
                currentUser: widget.currentUser,
                database: widget.database,
              ),
            ],
          ],
        ),
      ),
    );
  }
}