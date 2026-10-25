// Story 7.1: Shop Owner Real-Time Cash Reconciliation & Portfolio Dashboard
import 'package:flutter/material.dart';

import '../customers/data/daos/loan_dao.dart';
import '../customers/domain/models/loan.dart';

// Story 7.1: Portfolio dashboard with real-time data stream
class PortfolioDashboardPage extends StatelessWidget {
  const PortfolioDashboardPage({
    super.key,
    required this.loanDao,
    required this.shopId,
  });

  final LoanDao loanDao;
  final String shopId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Portfolio Dashboard')),
      body: StreamBuilder<List<Loan>>(
        stream: loanDao.watchLoansByShopId(shopId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final loans = snapshot.data!;
          final totalPrincipalCents =
              loans.fold<int>(0, (sum, l) => sum + l.principalCents);
          final totalOutstandingCents =
              loans.fold<int>(0, (sum, l) => sum + l.balanceCents);
          final totalCollectedCents = totalPrincipalCents - totalOutstandingCents;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _SummaryCard(
                      title: 'Outstanding Loans',
                      value: loans.length.toString(),
                    ),
                    _SummaryCard(
                      title: 'Outstanding Balance',
                      value: '$totalOutstandingCents cents',
                    ),
                    _SummaryCard(
                      title: 'Collected',
                      value: '$totalCollectedCents cents',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: loans.isEmpty
                    ? const Center(child: Text('No loans'))
                    : ListView.builder(
                        itemCount: loans.length,
                        itemBuilder: (_, i) {
                          final loan = loans[i];
                          return ListTile(
                            title: Text(loan.id),
                            subtitle: Text(
                              'Principal: ${loan.principalCents} cents, '
                              'Balance: ${loan.balanceCents} cents',
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
