import 'package:flutter/material.dart';

import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/auth/presentation/staff_management_screen.dart';
import 'package:credit_system/features/customers/data/daos/loan_dao.dart';
import 'package:credit_system/features/customers/presentation/overdue_screen.dart';
import 'package:credit_system/features/customers/presentation/shop_profile_screen.dart';
import 'package:credit_system/features/dashboard/presentation/dashboard_screen.dart';

/// Central settings hub for the credit system application.
///
/// Groups configuration and navigation entry points behind a single
/// "Settings" surface so the main screens stay uncluttered.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.shopId,
    required this.currentUser,
    this.database,
  });

  final String shopId;
  final AppUser currentUser;
  final AppDatabase? database;

  @override
  Widget build(BuildContext context) {
    final options = <_SettingOption>[
      _SettingOption(
        icon: Icons.store_outlined,
        title: 'Shop Profile',
        subtitle: 'Branding, contact details, timezone and currency',
        onTap: () => _open(
          context,
          ShopProfileScreen(
            shopId: shopId,
            currentUser: currentUser,
            database: database,
          ),
        ),
      ),
      if (currentUser.role == AppRole.shopOwner)
        _SettingOption(
          icon: Icons.group_add_outlined,
          title: 'Staff Management',
          subtitle: 'Create and manage staff accounts',
          onTap: () => _open(
            context,
            StaffManagementScreen(shopId: shopId, currentUser: currentUser),
          ),
        ),
      _SettingOption(
        icon: Icons.dashboard_outlined,
        title: 'Portfolio Dashboard',
        subtitle: 'Loan portfolio and collection overview',
        onTap: () {
          final db = database ?? AppDatabase();
          final loanDao = LoanDao(db);
          _open(
            context,
            DashboardScreen(loanDao: loanDao, shopId: shopId),
          );
        },
      ),
      if (currentUser.hasPermission(AppPermission.viewOverdueLoans))
        _SettingOption(
          icon: Icons.warning_amber_outlined,
          title: 'Overdue Loans',
          subtitle: 'Review delinquent accounts',
          onTap: () => _open(
            context,
            OverdueScreen(shopId: shopId, currentUser: currentUser),
          ),
        ),
      _SettingOption(
        icon: Icons.info_outline,
        title: 'About',
        subtitle: 'Credit System v1.0.0',
        onTap: () => showAboutDialog(
          context: context,
          applicationName: 'Credit System',
          applicationVersion: '1.0.0',
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: options.length,
separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          return Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListTile(
              leading: Icon(option.icon),
              title: Text(option.title),
              subtitle: Text(option.subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: option.onTap,
            ),
          );
        },
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }
}

class _SettingOption {
  const _SettingOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}
