import 'package:flutter/material.dart';

import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/auth/presentation/staff_management_screen.dart';
import 'package:credit_system/features/customers/presentation/shop_profile_screen.dart';
import 'package:credit_system/core/theme/theme_controller.dart';

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
    this.onLogout,
  });

  final String shopId;
  final AppUser currentUser;
  final AppDatabase? database;

  /// Invoked after the user confirms logging out.
  final VoidCallback? onLogout;

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
        icon: Icons.info_outline,
        title: 'About',
        subtitle: 'Credit System v1.0.0',
        onTap: () => showAboutDialog(
          context: context,
          applicationName: 'Credit System',
          applicationVersion: '1.0.0',
        ),
      ),
      if (onLogout != null)
        _SettingOption(
          icon: Icons.logout,
          title: 'Logout',
          subtitle: 'Sign out of this shop account',
          isDestructive: true,
          onTap: () => _confirmLogout(context),
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ValueListenableBuilder<ThemeMode>(
                valueListenable: appThemeMode,
                builder: (context, mode, _) {
                  return SwitchListTile(
                    title: const Text('Dark mode'),
                    subtitle: const Text('Toggle dark theme'),
                    value: mode == ThemeMode.dark,
                    onChanged: (value) {
                      appThemeMode.value = value
                          ? ThemeMode.dark
                          : ThemeMode.light;
                    },
                  );
                },
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
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
                    leading: Icon(
                      option.icon,
                      color: option.isDestructive
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                    title: Text(option.title),
                    subtitle: Text(option.subtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: option.onTap,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    // Leave settings before the session is cleared so the login screen is
    // not covered by this route.
    Navigator.of(context).pop();
    onLogout?.call();
  }
}

class _SettingOption {
  const _SettingOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDestructive;
}

