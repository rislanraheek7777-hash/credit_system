import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/features/shop/data/daos/shop_dao.dart';
import 'package:credit_system/features/shop/domain/models/shop_profile.dart';

/// Shop profile screen implementing Story 1.6 AC-1, AC-2, AC-3.
///
/// Displays shop profile details in a view-only (read-only) format.
/// Editing is disabled because Story 1.7 RBAC enforcement is not yet
/// implemented. Currency lock status is determined by
/// ShopDao.hasFinancialTransactions(), which checks the local sync_queue.
///
/// WARNING: Local currency locking via hasFinancialTransactions() is an
/// offline heuristic safeguard and cannot guarantee detection of all
/// financial transactions across all scenarios (e.g., pruned sync_queue
/// entries, or multi-terminal transactions recorded on other devices
/// and not yet synchronized to this local device).
///
/// Authoritative, permanent currency locking MUST be enforced by the
/// trusted backend and database constraints (e.g., PostgreSQL foreign
/// keys, triggers, or RLS rules) when the financial ledger is implemented
/// in Epics 4 and 5.
class ShopProfileScreen extends StatefulWidget {
  /// The active shop tenant UUID.
  final String shopId;

  /// Optional injected [AppDatabase] for testing. When omitted, the screen
  /// opens its own database connection via `AppDatabase()`.
  final AppDatabase? database;

  const ShopProfileScreen({super.key, required this.shopId, this.database});

  @override
  State<ShopProfileScreen> createState() => _ShopProfileScreenState();
}

class _ShopProfileScreenState extends State<ShopProfileScreen> {
  late AppDatabase _db;
  late ShopDao _shopDao;

  ShopProfile? _profile;
  bool _isLoading = true;
  String? _error;
  bool _currencyLocked = false;

  @override
  void initState() {
    super.initState();
    _db = widget.database ?? AppDatabase();
    _shopDao = ShopDao(_db);
    _loadProfile();
  }

  @override
  void dispose() {
    _db.close();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _shopDao.getShopById(widget.shopId);
      final hasTransactions = await _shopDao.hasFinancialTransactions(widget.shopId);

      if (!mounted) return;

      setState(() {
        _profile = profile;
        _currencyLocked = hasTransactions;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load shop profile: $e';
        _isLoading = false;
      });
    }
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
        appBar: AppBar(title: const Text('Shop Profile')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadProfile,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Shop Profile')),
        body: Center(child: Text('Shop profile not found')),
      );
    }

    final profile = _profile!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shop Profile'),
        actions: [
          // Edit button is disabled until Story 1.7 RBAC is implemented
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: null,
            tooltip: 'Editing disabled — Shop Owner authorization required (Story 1.7 RBAC pending)',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Currency lock warning banner
            if (_currencyLocked)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  border: Border.all(color: Colors.orange),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Currency Locked',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Base currency is locked to ${profile.currencyCode} because '
                      'financial transactions exist for this shop. '
                      'Currency cannot be changed after the first financial transaction.',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Note: Currency locking is enforced locally via sync_queue '
                      'checks. Server-enforced currency locking is deferred to '
                      'PostgreSQL RLS/triggers (Epic 4+).',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.orange.shade700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),

            // Editing disabled banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.15),
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Editing Disabled',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Shop profile editing requires Shop Owner authorization '
                    '(Story 1.7 RBAC — pending). All fields below are read-only.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Shop ID
            _buildFieldRow('Shop ID', profile.id),
            const SizedBox(height: 8),

            // Shop Name
            _buildFieldRow('Shop Name', profile.name),
            const SizedBox(height: 8),

            // Currency Code (with lock indicator)
            _buildFieldRow(
              'Currency Code',
              profile.currencyCode,
              locked: _currencyLocked,
            ),
            const SizedBox(height: 8),

            // Timezone
            _buildFieldRow('Timezone', profile.timezone),
            const SizedBox(height: 8),

            // Business Address
            _buildFieldRow('Business Address', profile.businessAddress ?? 'Not set'),
            const SizedBox(height: 8),

            // Contact Phone
            _buildFieldRow('Contact Phone', profile.contactPhone ?? 'Not set'),
            const SizedBox(height: 8),

            // Contact Email
            _buildFieldRow('Contact Email', profile.contactEmail ?? 'Not set'),
            const SizedBox(height: 8),

            // Registration Number
            _buildFieldRow('Registration Number', profile.registrationNumber ?? 'Not set'),
            const SizedBox(height: 8),

            // Logo URI
            _buildFieldRow('Logo URI', profile.logoUri ?? 'Not set'),
            const SizedBox(height: 8),

            // Receipt Header Notes
            _buildFieldRow('Receipt Header Notes', profile.receiptHeaderNotes ?? 'Not set'),
            const SizedBox(height: 8),

            // Receipt Footer Notes
            _buildFieldRow('Receipt Footer Notes', profile.receiptFooterNotes ?? 'Not set'),
            const SizedBox(height: 16),

            // Timestamps
            _buildFieldRow('Created At', profile.createdAt.toIso8601String()),
            const SizedBox(height: 8),
            _buildFieldRow('Last Updated', profile.updatedAt.toIso8601String()),
            const SizedBox(height: 16),

            // Disabled save button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: null,
                child: const Text('Save Changes (Disabled — Story 1.7 RBAC pending)'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldRow(String label, String value, {bool locked = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            color: locked ? Colors.orange.shade700 : Colors.black87,
            fontWeight: locked ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
