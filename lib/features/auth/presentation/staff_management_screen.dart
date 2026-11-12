import 'dart:async';

import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/core/permissions/authorization_guard.dart';
import 'package:credit_system/features/auth/data/daos/user_dao.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/auth/presentation/staff_form_screen.dart';

/// Staff management screen implementing Story 1.7 AC-1.
///
/// Displays active staff accounts strictly within the active shop tenant.
/// Only Shop Owners may access this screen. Tapping a staff member opens the
/// staff form for editing; the "Add Staff" button opens it for creation.
///
/// All administrative actions are enforced by [AuthorizationGuard]
/// in the action handlers — not merely by hiding or disabling buttons.
class StaffManagementScreen extends StatefulWidget {
  /// The active shop tenant UUID.
  final String shopId;

  /// The currently authenticated actor performing administrative actions.
  final AppUser currentUser;

  /// Optional injected [AppDatabase] for testing.
  final AppDatabase? database;

  const StaffManagementScreen({
    super.key,
    required this.shopId,
    required this.currentUser,
    this.database,
  });

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  late AppDatabase _db;
  late UserDao _userDao;

  List<AppUser> _users = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _db = widget.database ?? AppDatabase();
    _userDao = UserDao(_db);
    _loadStaff();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadStaff() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Enforce owner authorization — not just UI hiding.
      AuthorizationGuard.checkOwnerAdministrativeAction(
        isActive: widget.currentUser.isActive,
        actorRole: widget.currentUser.role,
        actionDescription: 'view staff management',
      );

      final users = await _userDao.getUsersByShopId(widget.shopId);

      if (!mounted) return;

      setState(() {
        _users = users.where((u) => u.isActive).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _refresh() async {
    await _loadStaff();
  }

  void _onAddStaff() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => StaffFormScreen(
          shopId: widget.shopId,
          currentUser: widget.currentUser,
          database: widget.database,
        ),
      ),
    ).then((_) => _refresh());
  }

  void _onEditStaff(AppUser user) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => StaffFormScreen(
          shopId: widget.shopId,
          currentUser: widget.currentUser,
          user: user,
          database: widget.database,
        ),
      ),
    ).then((_) => _refresh());
  }

  String _permissionsSummary(Set<AppPermission> permissions) {
    if (permissions.length >= AppPermission.values.length) {
      return 'All permissions';
    }
    return '${permissions.length} permissions';
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
        appBar: AppBar(title: const Text('Staff Management')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _refresh,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Add Staff',
            onPressed: _onAddStaff,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Staff Accounts',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_users.isEmpty)
              const Center(
                child: Text(
                  'No staff accounts found',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            if (_users.isNotEmpty) ...[
              Expanded(
                child: ListView.builder(
                  itemCount: _users.length,
                  itemBuilder: (context, index) {
                    final user = _users[index];
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          radius: 24,
                          child: Icon(Icons.person),
                        ),
                        title: Text(user.fullName),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${user.username}  •  ${user.role.displayName}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              _permissionsSummary(
                                user.effectivePermissions,
                              ),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _onEditStaff(user),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

