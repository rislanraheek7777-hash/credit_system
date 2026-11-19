import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/customer_dao.dart';
import 'package:credit_system/features/customers/domain/models/customer.dart';
import 'package:credit_system/features/customers/domain/models/customer_masking.dart';
import 'package:credit_system/features/customers/presentation/customer_profile_screen.dart';
import 'package:credit_system/features/customers/presentation/customer_registration_screen.dart';

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
    this.database,
  });

  /// The active shop tenant UUID.
  final String shopId;

  /// The authenticated actor viewing search results.
  final AppUser currentUser;

  /// Optional injected [AppDatabase] for testing.
  final AppDatabase? database;

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
  void initState() {
    super.initState();
    _loadCustomers();
  }

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

  Future<void> _performSearch(String query, {bool showLoading = true}) async {
    setState(() {
      if (showLoading) _isSearching = true;
      _error = null;
    });

    try {
      final db = widget.database ?? AppDatabase();
      final customerDao = CustomerDao(db);

      final results = await customerDao.searchCustomers(widget.shopId, query);

      if (!mounted) return;

      setState(() {
        _results = results
            .map(
              (c) => CustomerSearchResult(
                id: c.id,
                fullName: c.fullName,
                nic: c.nic,
                phone: c.phone,
                photoUri: c.photoUri,
              ),
            )
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

  Future<void> _loadCustomers({bool showLoading = true}) async {
    final query = _searchController.text.trim();
    if (query.length >= 2) {
      await _performSearch(query, showLoading: showLoading);
      return;
    }
    setState(() {
      if (showLoading) _isSearching = true;
      _error = null;
    });
    try {
      final db = widget.database ?? AppDatabase();
      final customerDao = CustomerDao(db);
      final results = await customerDao.getCustomersByShopId(widget.shopId);
      if (!mounted) return;
      setState(() {
        _results = results
            .map(
              (c) => CustomerSearchResult(
                id: c.id,
                fullName: c.fullName,
                nic: c.nic,
                phone: c.phone,
                photoUri: c.photoUri,
              ),
            )
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

  /// Opens the customer registration form.
  ///
  /// The registration route closes with the created customer as its result.
  /// When a customer was registered the list is reloaded so the new customer
  /// shows up on this screen, and the registration is confirmed with a
  /// SnackBar. Backing out without submitting returns no result, so nothing
  /// is confirmed and the operator's search filter is left untouched.
  Future<void> _openRegistrationForm() async {
    final created = await Navigator.of(context).push<Customer>(
      MaterialPageRoute(
        builder: (context) => CustomerRegistrationScreen(
          currentUser: widget.currentUser,
          database: widget.database,
        ),
      ),
    );

    if (!mounted) return;

    if (created != null) {
      // Clear any active search filter before reloading: the reload re-runs
      // the active query whenever it is at least two characters long, which
      // would repopulate a filtered list that does not contain the customer
      // the confirmation announces. The pending debounce is cancelled with
      // it, so a filter that was typed but not yet applied cannot re-apply
      // the stale query over the reloaded list.
      _debounceTimer?.cancel();
      _searchController.clear();
    }

    // Refresh the customer list so a newly registered customer
    // shows up on this screen.
    await _loadCustomers();

    if (!mounted) return;

    // No result means the staff member backed out without registering
    // anyone, so there is nothing to confirm.
    if (created == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Customer "${created.fullName}" registered successfully '
          '(ID: ${created.id}).',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openRegistrationForm,
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
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: const [
                    Icon(Icons.people_alt, color: Color(0xFF1565C0), size: 28),
                    SizedBox(width: 8),
                    Text(
                      'Customers',
                      style: TextStyle(
                        color: Color(0xFF1565C0),
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Search by NIC, phone, or name',
                    hintText: 'Enter at least 2 characters',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
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
                    child: RefreshIndicator(
                      onRefresh: () => _loadCustomers(showLoading: false),
                      child: _results.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [
                                SizedBox(height: 120),
                                Icon(
                                  Icons.search_off,
                                  size: 48,
                                  color: Colors.grey,
                                ),
                                SizedBox(height: 8),
                                Center(
                                  child: Text(
                                    'No matching customers',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: _results.length,
                              itemBuilder: (context, index) {
                                final result = _results[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: ListTile(
                                    leading: result.photoUri != null
                                        ? CircleAvatar(
                                            backgroundImage: FileImage(
                                              File(result.photoUri!),
                                            ),
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
                                        MaterialPageRoute<bool?>(
                                          builder: (context) =>
                                              CustomerProfileScreen(
                                                shopId: widget.shopId,
                                                customerId: result.id,
                                                currentUser: widget.currentUser,
                                                database: widget.database,
                                              ),
                                        ),
                                      ).then((deleted) {
                                        // The profile pops with `true` only
                                        // after a successful soft delete;
                                        // reload then, not on every visit.
                                        if (deleted == true && mounted) {
                                          _loadCustomers(showLoading: false);
                                        }
                                      });
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
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

