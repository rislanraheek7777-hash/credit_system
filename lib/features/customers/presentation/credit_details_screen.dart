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

/// Credit details screen listing every credit agreement of the active shop.
///
/// Reached from the main navigation bar's "Credit Details" option. Exposes the
/// shop's credit portfolio: each agreement's customer, principal, outstanding
/// balance, status, and agreed due date.
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
      appBar: AppBar(title: const Text('Credit Details')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24.0),
                children: [
                  const SizedBox(height: 96),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadCredits,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ],
              )
            : _credits.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('No credit details found')),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                itemCount: _credits.length,
                itemBuilder: (context, index) {
                  final credit = _credits[index];
                  return _CreditCard(
                    credit: credit,
                    customer: _customersById[credit.customerId],
                    shopTimeZone: _shopTimeZone,
                  );
                },
              ),
      ),
    );
  }
}

/// A single credit agreement card within the shop's credit details list.
class _CreditCard extends StatelessWidget {
  final Credit credit;
  final Customer? customer;
  final ShopTimeZone shopTimeZone;

  const _CreditCard({
    required this.credit,
    required this.customer,
    required this.shopTimeZone,
  });

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

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Credit ${credit.id.substring(0, credit.id.length.clamp(0, 8))}...',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Chip(
                  label: Text(credit.status.value.toUpperCase()),
                  backgroundColor: _statusColor(credit.status)
                      .withValues(alpha: 0.15),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Customer: ${customer?.fullName ?? 'Unknown'}'),
            Text('Principal: ${Money.fromCents(credit.principalCents).format()}'),
            Text('Balance: ${Money.fromCents(credit.balanceCents).format()}'),
            Text('Due: ${credit.dueDateAsCalendarDate(shopTimeZone)}'),
          ],
        ),
      ),
    );
  }
}

