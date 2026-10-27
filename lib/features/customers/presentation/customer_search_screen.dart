import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/customers/data/daos/customer_dao.dart';
import 'package:credit_system/features/customers/domain/models/customer_masking.dart';
import 'package:credit_system/features/customers/presentation/customer_profile_screen.dart';
import 'package:credit_system/features/customers/presentation/customer_registration_screen.dart';
import 'package:credit_system/features/customers/presentation/shop_profile_screen.dart';
import 'package:credit_system/features/dashboard/presentation/dashboard_screen.dart';
import 'package:credit_system/features/settings/presentation/settings_screen.dart';
import 'package:credit_system/features/auth/presentation/staff_management_screen.dart';
import 'package:credit_system/features/customers/presentation/overdue_screen.dart';
import 'package:credit_system/features/customers/data/daos/loan_dao.dart';

/// Customer search screen implementing Story 2.5 AC-1.
///
/// Searches customers by NIC, phone, or name fragment (minimum 2 characters)
/// strictly within the active shop. Results display masked sensitive fields
/// unless the viewer possesses [viewSensitiveCustomerData].
class CustomerSearchScreen extends StatefulWidget {
  const CustomerSearchScreen({
    super.key,
    required this.shopId,
    required this.currentUser,
  });

  /// The active shop tenant UUID.
  final String shopId;

  /// The authenticated actor viewing search results.
  final AppUser currentUser;

  @override
  State<CustomerSearchScreen> createState() => _CustomerSearchScreenState();
}

class _CustomerSearchScreenState extends State<CustomerSearchScreen> {
  final _searchController = TextEditingController();
  Timer? _debounceTimer;

  List<CustomerSearchResult> _results = [];
  bool _isSearching = false;
  String? _error;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    setState(() {
      _error = null;
      if (value.trim().length < 2) {
        _results = [];
        _isSearching = false;
      }
    });
    if (value.trim().length >= 2) {
      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
        _performSearch(value.trim());
      });
    }
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final db = AppDatabase();
      final customerDao = CustomerDao(db);

      final results = await customerDao.searchCustomers(widget.shopId, query);

      await db.close();

      if (!mounted) return;

      setState(() {
        _results = results
            .map((c) => CustomerSearchResult(
                  id: c.id,
                  fullName: c.fullName,
                  nic: c.nic,
                  phone: c.phone,
                  photoUri: c.photoUri,
                ))
            .toList();
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _error = 'Search failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => CustomerRegistrationScreen(
                currentUser: widget.currentUser,
              ),
            ),
          );
        },
        icon: const Icon(Icons.person_add),
        label: const Text('Add Customer'),
      ),
      appBar: AppBar(
        title: const Text('Search Customers'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.dashboard),
            tooltip: 'Dashboard',
            onPressed: () {
              final db = AppDatabase();
              final loanDao = LoanDao(db);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => DashboardScreen(
                    loanDao: loanDao,
                    shopId: widget.shopId,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => SettingsScreen(
                    shopId: widget.shopId,
                    currentUser: widget.currentUser,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.store),
            tooltip: 'Shop Profile',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ShopProfileScreen(
                    shopId: widget.shopId,
                    currentUser: widget.currentUser,
                  ),
                ),
              );
            },
          ),
          if (widget.currentUser.role == AppRole.shopOwner)
            IconButton(
              icon: const Icon(Icons.person_add),
              tooltip: 'Staff Management',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => StaffManagementScreen(
                      shopId: widget.shopId,
                      currentUser: widget.currentUser,
                    ),
                  ),
                );
              },
            ),
          if (widget.currentUser.hasPermission(AppPermission.viewOverdueLoans))
            IconButton(
              icon: const Icon(Icons.warning),
              tooltip: 'Overdue Loans',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => OverdueScreen(
                      shopId: widget.shopId,
                      currentUser: widget.currentUser,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search by NIC, phone, or name',
                hintText: 'Enter at least 2 characters',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 16),
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
                  style: TextStyle(color: Colors.red.shade800),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_isSearching)
              const Center(child: CircularProgressIndicator()),
            if (!_isSearching) ...[
              Expanded(
                child: _results.isEmpty
                    ? const Center(
                        child: Text(
                          'No matching customers',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final result = _results[index];
                          return ListTile(
                            leading: result.photoUri != null
                                ? CircleAvatar(
                                    backgroundImage:
                                        FileImage(File(result.photoUri!)),
                                    radius: 24,
                                  )
                                : const CircleAvatar(
                                    radius: 24,
                                    child: Icon(Icons.person),
                                  ),
                            title: Text(result.fullName),
                            subtitle: Text(
                              'NIC: ${maskNic(result.nic)}  |  Phone: ${maskPhone(result.phone)}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => CustomerProfileScreen(
                                    shopId: widget.shopId,
                                    customerId: result.id,
                                    currentUser: widget.currentUser,
                                  ),
                                ),
                              );
                            },
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

/// Search result summary for display in the customer search list.
class CustomerSearchResult {
  final int id;
  final String fullName;
  final String nic;
  final String phone;
  final String? photoUri;

  CustomerSearchResult({
    required this.id,
    required this.fullName,
    required this.nic,
    required this.phone,
    this.photoUri,
  }) : assert(id >= 0); // Auto-increment ID must be non-negative
}
