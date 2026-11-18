// Story 7.1: Shop Owner Real-Time Cash Reconciliation & Portfolio Dashboard
import 'package:flutter/material.dart';

import '../customers/data/daos/credit_dao.dart';
import '../customers/domain/models/credit.dart';

class PortfolioDashboardPage extends StatelessWidget {
  const PortfolioDashboardPage({
    super.key,
    required this.creditDao,
    required this.shopId,
  });

  final CreditDao creditDao;
  final String shopId;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: StreamBuilder<List<Credit>>(
        stream: creditDao.watchCreditsByShopId(shopId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final credits = snapshot.data!;
          final totalPrincipalCents =
              credits.fold<int>(0, (sum, l) => sum + l.principalCents);
          final totalOutstandingCents =
              credits.fold<int>(0, (sum, l) => sum + l.balanceCents);
          final totalCollectedCents =
              totalPrincipalCents - totalOutstandingCents;
          final collectionRate = totalPrincipalCents == 0
              ? 0.0
              : totalCollectedCents / totalPrincipalCents;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 150,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  title: const Text('Portfolio Dashboard'),
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.primary,
                          colorScheme.primaryContainer,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Overview',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 170,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _SummaryCard(
                              title: 'Active Credits',
                              value: credits.length.toString(),
                              icon: Icons.account_balance_wallet_rounded,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            _SummaryCard(
                              title: 'Outstanding',
                              value: _formatCents(totalOutstandingCents),
                              icon: Icons.pending_actions_rounded,
                              color: Colors.orange.shade700,
                            ),
                            const SizedBox(width: 12),
                            _SummaryCard(
                              title: 'Collected',
                              value: _formatCents(totalCollectedCents),
                              icon: Icons.check_circle_rounded,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(width: 12),
                            _SummaryCard(
                              title: 'Collection Rate',
                              value: '${(collectionRate * 100).toStringAsFixed(1)}%',
                              icon: Icons.trending_up_rounded,
                              color: colorScheme.tertiary,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Credit Portfolio',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              if (credits.isEmpty)
                const SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_rounded, size: 64, color: Colors.grey),
                        SizedBox(height: 12),
                        Text(
                          'No credits yet',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final credit = credits[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: CircleAvatar(
                              backgroundColor:
                                  colorScheme.primaryContainer,
                              child: Icon(
                                Icons.receipt_long_rounded,
                                color: colorScheme.primary,
                              ),
                            ),
                            title: Text(
                              'Credit ${credit.id}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _CreditMetricRow(
                                    label: 'Amount',
                                    value: _formatCents(credit.principalCents),
                                  ),
                                  _CreditMetricRow(
                                    label: 'Balance',
                                    value: _formatCents(credit.balanceCents),
                                  ),
                                  _CreditMetricRow(
                                    label: 'Status',
                                    value: credit.status.value,
                                  ),
                                ],
                              ),
                            ),
                            trailing: Icon(
                              Icons.chevron_right_rounded,
                              color: colorScheme.outline,
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: credits.length,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }

  static String _formatCents(int cents) {
    return (cents / 100).toStringAsFixed(2);
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CreditMetricRow extends StatelessWidget {
  const _CreditMetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

