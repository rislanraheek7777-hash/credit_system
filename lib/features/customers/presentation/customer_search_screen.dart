import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/features/customers/data/daos/customer_dao.dart';
import 'package:credit_system/features/customers/domain/models/customer_masking.dart';
import 'package:credit_system/features/customers/presentation/customer_profile_screen.dart';

/// Customer search screen implementing Story 2.5 AC-1.
///
/// Searches customers by NIC, phone, or name fragment (minimum 2 characters)
/// strictly within the active shop. Results display masked sensitive fields
/// unless the viewer possesses [viewSensitiveCustomerData].
class CustomerSearchScreen extends StatefulWidget {
  const CustomerSearchScreen({super.key, required this.shopId});

  /// The active shop tenant UUID.
  final String shopId;

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
      appBar: AppBar(
        title: const Text('Search Customers'),
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
  final String id;
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
  });
}
