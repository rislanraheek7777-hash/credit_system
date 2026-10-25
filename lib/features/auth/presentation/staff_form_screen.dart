import 'dart:async';

import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/core/permissions/authorization_guard.dart';
import 'package:credit_system/features/auth/data/daos/user_dao.dart';
import 'package:credit_system/features/auth/data/services/password_hash_service.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:uuid/uuid.dart';

/// Staff form screen implementing Story 1.7 AC-2.
///
/// Creates or edits staff user accounts with full name, username, initial
/// password, role selection, and granular permission controls for all 14
/// approved permissions.
///
/// Only Shop Owners may access this screen. Authorization is enforced in the
/// action handlers via [AuthorizationGuard], not merely by UI hiding.
///
/// Role templates are applied consistently: selecting a predefined role
/// (Shop Owner, Manager, Cashier) applies its approved permission set;
/// Custom role allows granular per-permission selection.
///
/// Privilege escalation is prevented: non-owners cannot assign the Shop Owner
/// role or permissions they do not possess, and an owner cannot deactivate
/// themselves or change their own role to remove owner status.
class StaffFormScreen extends StatefulWidget {
  /// The active shop tenant UUID.
  final String shopId;

  /// The currently authenticated actor performing administrative actions.
  final AppUser currentUser;

  /// The user to edit, or null to create a new staff account.
  final AppUser? user;

  /// Optional injected [AppDatabase] for testing.
  final AppDatabase? database;

  const StaffFormScreen({
    super.key,
    required this.shopId,
    required this.currentUser,
    this.user,
    this.database,
  });

  @override
  State<StaffFormScreen> createState() => _StaffFormScreenState();
}

class _StaffFormScreenState extends State<StaffFormScreen> {
  late AppDatabase _db;
  late UserDao _userDao;
  late PasswordHashService _passwordService;

  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  AppRole _selectedRole = AppRole.cashier;
  Set<AppPermission> _selectedPermissions = {};

  bool _isLoading = false;
  String? _error;
  String? _success;

  bool get _isEditing => widget.user != null;

  @override
  void initState() {
    super.initState();
    _db = widget.database ?? AppDatabase();
    _userDao = UserDao(_db);
    _passwordService = PasswordHashService();
    _initializeForm();
  }

  @override
  void dispose() {
    _db.close();
    _fullNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _initializeForm() {
    if (widget.user != null) {
      final user = widget.user!;
      _fullNameController.text = user.fullName;
      _usernameController.text = user.username;
      _selectedRole = user.role;
      _selectedPermissions = Set.of(user.effectivePermissions);
    } else {
      _selectedRole = AppRole.cashier;
      _selectedPermissions =
          Set.of(RolePermissionTemplates.cashierPermissions);
    }
  }

  void _onRoleChanged(AppRole? role) {
    if (role == null) return;
    setState(() {
      _selectedRole = role;
      if (role != AppRole.custom) {
        _selectedPermissions = Set.of(
          RolePermissionTemplates.defaultPermissionsForRole(role),
        );
      }
    });
  }

  void _onPermissionChanged(AppPermission permission, bool? value) {
    setState(() {
      if (value == true) {
        _selectedPermissions.add(permission);
      } else {
        _selectedPermissions.remove(permission);
      }
    });
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _success = null;
    });

    try {
      AuthorizationGuard.checkOwnerAdministrativeAction(
        isActive: widget.currentUser.isActive,
        actorRole: widget.currentUser.role,
        actionDescription: 'manage staff accounts',
      );

      AuthorizationGuard.validateStaffAssignment(
        actorIsActive: widget.currentUser.isActive,
        actorRole: widget.currentUser.role,
        actorEffectivePermissions: widget.currentUser.effectivePermissions,
        targetRole: _selectedRole,
        targetPermissions: _selectedPermissions,
      );

      if (widget.user != null &&
          widget.user!.id == widget.currentUser.id) {
        if (!_selectedRole.isOwner && widget.currentUser.role.isOwner) {
          throw const PrivilegeEscalationException(
            'Privilege escalation rejected: Shop Owner cannot remove their own owner role.',
          );
        }
        final currentPerms = widget.currentUser.effectivePermissions;
        if (!_selectedPermissions.containsAll(currentPerms) &&
            widget.currentUser.role.isOwner) {
          throw const PrivilegeEscalationException(
            'Privilege escalation rejected: Shop Owner cannot remove their own permissions.',
          );
        }
      }

      final now = DateTime.now().toUtc();

      if (widget.user == null) {
        final password = _passwordController.text.trim();
        if (password.isEmpty) {
          throw const FormatException(
            'Initial password is required for new staff accounts.',
          );
        }

        final newUser = AppUser(
          id: const Uuid().v4(),
          shopId: widget.shopId,
          username: _usernameController.text.trim(),
          fullName: _fullNameController.text.trim(),
          role: _selectedRole,
          isActive: true,
          sessionVersion: 1,
          customPermissions:
              _selectedRole == AppRole.custom
                  ? _selectedPermissions
                  : null,
          createdAt: now,
          updatedAt: now,
        );

        await _userDao.createUserWithPassword(newUser, password);
      } else {
        await _userDao.updateUserPermissions(
          widget.shopId,
          widget.user!.id,
          role: _selectedRole,
          customPermissions:
              _selectedRole == AppRole.custom
                  ? _selectedPermissions
                  : null,
        );

        final newPassword = _passwordController.text.trim();
        if (newPassword.isNotEmpty) {
          final newHash = _passwordService.hashPassword(newPassword);
          await _userDao.updateUserPassword(
            widget.shopId,
            widget.user!.id,
            passwordHash: newHash,
          );
        }
      }

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _success = _isEditing
            ? 'Staff account updated successfully.'
            : 'Staff account created successfully.';
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  String _permissionDescription(AppPermission permission) {
    switch (permission) {
      case AppPermission.registerCustomers:
        return 'Register new customers and edit permitted profile details';
      case AppPermission.viewCustomers:
        return 'Search and view customer contact details';
      case AppPermission.viewSensitiveCustomerData:
        return 'View unmasked sensitive identity data';
      case AppPermission.createLoans:
        return 'Create new loan agreements';
      case AppPermission.confirmLoanDisbursement:
        return 'Confirm physical cash disbursement';
      case AppPermission.recordPayments:
        return 'Record payments against loans';
      case AppPermission.viewAndReprintReceipts:
        return 'View payment histories and reprint receipts';
      case AppPermission.viewOverdueLoans:
        return 'View overdue loan queues';
      case AppPermission.recordCustomerNotes:
        return 'Record customer interaction notes';
      case AppPermission.requestCorrections:
        return 'Submit financial correction requests';
      case AppPermission.approveCorrections:
        return 'Authorize or reject financial corrections';
      case AppPermission.confirmCollateralReturn:
        return 'Confirm physical handover of collateral';
      case AppPermission.viewFinancialReports:
        return 'View financial reports';
      case AppPermission.viewAuditLogs:
        return 'View audit logs';
    }
  }

  List<Widget> _buildPermissionTiles() {
    return AppPermission.values.map((permission) {
      final isChecked = _selectedPermissions.contains(permission);
      return CheckboxListTile(
        title: Text(permission.key),
        subtitle: Text(
          _permissionDescription(permission),
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
        value: isChecked,
        onChanged: (bool? value) =>
            _onPermissionChanged(permission, value),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.currentUser.role.isOwner || !widget.currentUser.isActive) {
      return Scaffold(
        appBar: AppBar(title: const Text('Staff Management')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Access Denied',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Only Shop Owners can manage staff accounts.',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Staff' : 'Add Staff'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.15),
                            border: Border.all(color: Colors.red),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_success != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.15),
                            border: Border.all(color: Colors.green),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _success!,
                            style: const TextStyle(color: Colors.green),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        key: const Key('fullNameField'),
                        controller: _fullNameController,
                        decoration: const InputDecoration(
                          labelText: 'Full Name',
                          hintText: 'Enter staff member full name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Full name is required';
                          }
                          if (value.trim().length > 255) {
                            return 'Full name cannot exceed 255 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('usernameField'),
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          hintText: 'Enter username',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Username is required';
                          }
                          if (value.trim().length > 100) {
                            return 'Username cannot exceed 100 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('passwordField'),
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: _isEditing
                              ? 'New Password (optional)'
                              : 'Initial Password',
                          hintText: _isEditing
                              ? 'Leave blank to keep current password'
                              : 'Enter initial password',
                          border: const OutlineInputBorder(),
                        ),
                        obscureText: true,
                        validator: _isEditing
                            ? null
                            : (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Password is required';
                                }
                                return null;
                              },
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Role',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<AppRole>(
                        initialValue: _selectedRole,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        items: AppRole.values.map((role) {
                          return DropdownMenuItem<AppRole>(
                            value: role,
                            child: Text(role.displayName),
                          );
                        }).toList(),
                        onChanged: _onRoleChanged,
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Permissions',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ..._buildPermissionTiles(),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _onSave,
                          child: _isLoading
                              ? const CircularProgressIndicator()
                              : Text(_isEditing ? 'Update Staff' : 'Create Staff'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      );
  }
}
