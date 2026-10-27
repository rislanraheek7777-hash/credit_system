import 'package:flutter/material.dart';

import '../portfolio_dashboard_page.dart';
import '../../customers/data/daos/loan_dao.dart';

export '../portfolio_dashboard_page.dart';

/// Entry point for the credit-system dashboard under the dashboard module.
///
/// Wraps [PortfolioDashboardPage] so callers can depend on the consolidated
/// `features/dashboard/presentation` path while preserving the existing
/// portfolio implementation.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.loanDao,
    required this.shopId,
  });

  final LoanDao loanDao;
  final String shopId;

  @override
  Widget build(BuildContext context) {
    return PortfolioDashboardPage(loanDao: loanDao, shopId: shopId);
  }
}
