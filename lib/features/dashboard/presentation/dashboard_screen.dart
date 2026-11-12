import 'package:flutter/material.dart';

import '../portfolio_dashboard_page.dart';
import '../../customers/data/daos/credit_dao.dart';

export '../portfolio_dashboard_page.dart';

/// Entry point for the credit-system dashboard under the dashboard module.
///
/// Wraps [PortfolioDashboardPage] so callers can depend on the consolidated
/// `features/dashboard/presentation` path while preserving the existing
/// portfolio implementation.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.creditDao,
    required this.shopId,
  });

  final CreditDao creditDao;
  final String shopId;

  @override
  Widget build(BuildContext context) {
    return PortfolioDashboardPage(creditDao: creditDao, shopId: shopId);
  }
}

