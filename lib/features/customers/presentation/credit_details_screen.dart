import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/customer_dao.dart';
import 'package:credit_system/features/customers/data/daos/credit_dao.dart';
import 'package:credit_system/features/customers/data/daos/overdue_dao.dart';
import 'package:credit_system/features/customers/domain/models/customer.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:credit_system/features/customers/domain/models/credit_term.dart';
import 'package:credit_system/features/customers/presentation/credit_draft_agreement_action.dart';

/// Credit details screen listing every credit agreement of the active shop.
/// Reached from the main navigation bar's "Credit Details" option. Exposes the
/// shop's credit portfolio with summary metrics, state-aware action menus,
/// and individual credit cards with rich contextual information.
class CreditDetailsScreen extends StatefulWidget {
  const CreditDetailsScreen({
    super.key,
    required this.shopId,
    required this.currentUser,
    this.database,
  });

  /// The active shop tenant UUID.
  final String shopId;

  /// The authenticated actor viewing credit details.
  final AppUser currentUser;

  /// Optional injected [AppDatabase] for testing.
  final AppDatabase? database;

  @override
  State<CreditDetailsScreen> createState() => _CreditDetailsScreenState();
}

class _CreditDetailsScreenState extends State<CreditDetailsScreen> {
  late CustomerDao _customerDao;
  late CreditDao _creditDao;

  List<Credit> _credits = [];
  final Map<int, Customer?> _customersById = <int, Customer?>{};
  ShopTimeZone _shopTimeZone = ShopTimeZone.defaultTimeZone();
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCredits();
  }

  Future<void> _refresh() => _loadCredits(showLoading: false);

  Future<void> _loadCredits({bool showLoading = true}) async {
    setState(() {
      if (showLoading) _isLoading = true;
      _error = null;
    });

    try {
      final db = widget.database ?? AppDatabase();
      _customerDao = CustomerDao(db);
      _creditDao = CreditDao(db);

      final credits = await _creditDao.getCreditsByShopId(widget.shopId);
      final shopTimeZone = await OverdueDao(db)
          .resolveShopTimeZone(widget.shopId);

      final customersById = <int, Customer?>{};
      for (final credit in credits) {
        customersById[credit.customerId] = await _customerDao.getCustomerById(
          widget.shopId,
          credit.customerId,
        );
      }

      if (!mounted) return;

      setState(() {
        _credits = credits;
        _customersById.addAll(customersById);
        _shopTimeZone = shopTimeZone;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load credit details: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _buildErrorState()
            : _credits.isEmpty
            ? _buildEmptyState()
            : _buildBody(),
      ),
    );
  }

  /// App bar matching the search customers screen style.
  AppBar _buildAppBar() {
    return AppBar(
      title: const Text('Credit Details'),
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
    );
  }

  /// Error state rebuilding UI.
  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            _error!,
            style: const TextStyle(color: Colors.red, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _loadCredits,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  /// Empty state when the shop has no credits yet.
  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            'No credit details found',
            style: TextStyle(
              fontSize: 16,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first credit agreement using the credit origination flow.',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Credit origination not yet implemented from here'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Create First Credit'),
          ),
        ],
      ),
    );
  }

  /// Main body with summary metrics and credit list.
  Widget _buildBody() {
    return CustomScrollView(
      slivers: [
        // --- Summary header ---
        _buildSummaryHeader(),

        // --- Credit list ---
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final credit = _credits[index];
              return _CreditCard(
                credit: credit,
                customer: _customersById[credit.customerId],
                shopTimeZone: _shopTimeZone,
                currentUser: widget.currentUser,
                database: widget.database,
              );
            },
            childCount: _credits.length,
          ),
        ),
      ],
    );
  }

  /// Summary header with key metrics and quick stats.
  Widget _buildSummaryHeader() {
    final colorScheme = Theme.of(context).colorScheme;
    final totalPrincipal =
        _credits.fold<int>(0, (sum, l) => sum + l.principalCents);
    final totalBalance =
        _credits.fold<int>(0, (sum, l) => sum + l.balanceCents);
    final totalCollected = totalPrincipal - totalBalance;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Credit Summary',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _MetricTile(
                    label: 'Total Credits',
                    value: _credits.length.toString(),
                    icon: Icons.account_balance_wallet,
                    color: Colors.blue,
                  ),
                  _MetricTile(
                    label: 'Outstanding',
                    value: '--',
                    icon: Icons.pending_actions,
                    color: Colors.orange,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _MetricTile(
                    label: 'Collected',
                    value: Money.fromCents(totalCollected).format(),
                    icon: Icons.check_circle,
                    color: Colors.green,
                  ),
                  _MetricTile(
                    label: 'Collection Rate',
                    value: totalPrincipal == 0
                        ? '0.0%'
                        : '${(totalCollected / totalPrincipal * 100).toStringAsFixed(1)}%',
                    icon: Icons.trending_up,
                    color: Colors.teal,
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact metric tile shown in the summary header.
class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single credit agreement card within the shop's credit details list.
/// Designed with state-aware actions, rich contextual information, and
/// consistent visual hierarchy matching the portfolio dashboard style.
class _CreditCard extends StatelessWidget {
  final Credit credit;
  final Customer? customer;
  final ShopTimeZone shopTimeZone;

  /// The authenticated actor viewing the credit details.
  final AppUser currentUser;

  /// Optional injected [AppDatabase] for testing.
  final AppDatabase? database;

  const _CreditCard({
    required this.credit,
    required this.customer,
    required this.shopTimeZone,
    required this.currentUser,
    required this.database,
  });

  /// Returns a color that corresponds to the credit's financial status.
  Color _statusColor(CreditStatus status) {
    switch (status) {
      case CreditStatus.active:
        return Colors.green;
      case CreditStatus.overdue:
        return Colors.orange;
      case CreditStatus.settled:
        return Colors.grey;
      case CreditStatus.cancelled:
        return Colors.red;
    }
  }

  /// Returns the badge color with low opacity fill based on status.
  Color _statusBadgeColor(CreditStatus status) {
    switch (status) {
      case CreditStatus.active:
        return Colors.green.withValues(alpha: 0.15);
      case CreditStatus.overdue:
        return Colors.orange.withValues(alpha: 0.15);
      case CreditStatus.settled:
        return Colors.grey.withValues(alpha: 0.15);
      case CreditStatus.cancelled:
        return Colors.red.withValues(alpha: 0.15);
    }
  }

  /// Determines the primary action label and availability based on credit state.
  _CardActionsExtension _getActions(BuildContext context) {
    // Disbursement: only for pending disbursement credits
    final canDisburse = credit.isPendingDisbursement &&
        !credit.isOverdue(shopTimeZone) &&
        !credit.correctionPending;

    // Payment: only for disbursed, active or overdue credits (not settled/cancelled)
    final canPay = credit.isActionable;

    // Extension: only for active credits with a due date approaching or passed
    final canExtend = credit.status == CreditStatus.active &&
        !credit.isOverdue(shopTimeZone) &&
        !credit.correctionPending;

    // Settlement: only for active credits with full balance
    final canSettle = credit.status == CreditStatus.active &&
        credit.balanceCents <= 0 &&
        !credit.isOverdue(shopTimeZone);

    // View draft agreement: always available
    final canViewAgreement = true;

    // Collateral return: only for credits with item receipts (items type)
    final canReturnCollateral =
        credit.creditType == CreditType.items && credit.hasDisbursementRecord;

    return _CardActionsExtension(
      canDisburse: canDisburse,
      canPay: canPay,
      canExtend: canExtend,
      canSettle: canSettle,
      canViewAgreement: canViewAgreement,
      canReturnCollateral: canReturnCollateral,
      credit: credit,
      currentUser: currentUser,
      shopTimeZone: shopTimeZone,
      database: database,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final actions = _getActions(context);
    final statusColor = _statusColor(credit.status);
    final statusBadgeColor = _statusBadgeColor(credit.status);
    final balance = Money.fromCents(credit.balanceCents);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // Navigate to credit detail view - currently just show a snackbar;
          // in a full implementation this would push a CreditDetailViewScreen.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Credit detail view not yet implemented'),
              duration: Duration(seconds: 2),
            ),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header row: credit ID and status badge
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Credit ${credit.id.substring(0, credit.id.length.clamp(0, 8))}...',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusBadgeColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      credit.status.value.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Customer and metadata row
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Customer: ${customer?.fullName ?? 'Unknown'}',
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Type badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: credit.creditType == CreditType.items
                          ? Colors.indigo.withValues(alpha: 0.1)
                          : Colors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      credit.creditType.displayLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: credit.creditType == CreditType.items
                            ? Colors.indigo
                            : Colors.amber,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Balance row - moved after customer as requested
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Balance: ${balance.format(includeSymbol: false)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Due date and term row
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Due: ${credit.dueDateAsCalendarDate(shopTimeZone)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (credit.termPresetDays != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${credit.termPresetDays!.toStringAsFixed(0)} Day${credit.termPresetDays! > 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),

              // Status-specific notes
              if (credit.status == CreditStatus.overdue)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Overdue — payment required',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              if (credit.correctionPending)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.pending,
                        size: 14,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Correction pending — payments blocked',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              if (credit.isPendingDisbursement)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock_clock,
                        size: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Pending disbursement — cash not yet handed over',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              if (credit.status == CreditStatus.settled)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 14,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Settled — fully repaid',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              if (credit.status == CreditStatus.cancelled)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.cancel,
                        size: 14,
                        color: Colors.red,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Cancelled — undisbursed',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.red,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 12),

              // State-aware action menu
              ...actions.build(context),
            ],
          ),
        ),
      ),
    );
  }
}

/// Container for per-credit action capabilities.
class _CardActionsExtension {
  final bool canDisburse;
  final bool canPay;
  final bool canExtend;
  final bool canSettle;
  final bool canViewAgreement;
  final bool canReturnCollateral;
  final Credit credit;
  final AppUser currentUser;
  final ShopTimeZone shopTimeZone;
  final AppDatabase? database;

  _CardActionsExtension({
    required this.canDisburse,
    required this.canPay,
    required this.canExtend,
    required this.canSettle,
    required this.canViewAgreement,
    required this.canReturnCollateral,
    required this.credit,
    required this.currentUser,
    required this.shopTimeZone,
    required this.database,
  });

  /// Build the action widgets that are appropriate for this credit's state.
  List<Widget> build(BuildContext context) {
    final widgets = <Widget>[];

    // Payment action
    if (canPay) {
      widgets.add(_PaymentAction(
        credit: credit,
        onPressed: () => _handlePay(context),
      ));
    }

    // Settlement action
    if (canSettle) {
      widgets.add(_SettlementAction(
        credit: credit,
        onPressed: () => _handleSettle(context),
      ));
    }

    // View draft agreement - always available
    if (canViewAgreement) {
      widgets.add(CreditDraftAgreementAction(
        credit: credit,
        currentUser: currentUser,
        shopTimeZone: shopTimeZone,
        database: database,
      ));
    }

    // Collateral return
    if (canReturnCollateral) {
      widgets.add(_CollateralReturnAction(
        credit: credit,
        onPressed: () => _handleCollateralReturn(context),
      ));
    }

    return widgets;
  }

  // --- Action handlers -------------------------------------------------------

  void _handlePay(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Payment recording not yet implemented from detail card'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _handleSettle(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Settlement not yet implemented'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _handleCollateralReturn(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Collateral return not yet implemented'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

/// Payment action widget shown on disbursed, active or overdue credits.
class _PaymentAction extends StatelessWidget {
  final Credit credit;
  final VoidCallback onPressed;

  const _PaymentAction({
    required this.credit,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      child: const Text('Record Payment'),
    );
  }
}

/// Settlement action widget shown on active credits with zero balance.
class _SettlementAction extends StatelessWidget {
  final Credit credit;
  final VoidCallback onPressed;

  const _SettlementAction({
    required this.credit,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      child: const Text('Mark as Settled'),
    );
  }
}

/// Collateral return action widget shown on item-type credits with disbursement record.
class _CollateralReturnAction extends StatelessWidget {
  final Credit credit;
  final VoidCallback onPressed;

  const _CollateralReturnAction({
    required this.credit,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      child: const Text('Return Collateral'),
    );
  }
}