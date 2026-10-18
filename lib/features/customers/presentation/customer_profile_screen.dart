import 'dart:io';

import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/features/customers/data/daos/customer_dao.dart';
import 'package:credit_system/features/customers/data/daos/loan_dao.dart';
import 'package:credit_system/features/customers/domain/models/customer_masking.dart';
import 'package:credit_system/features/customers/domain/models/customer.dart';
import 'package:credit_system/features/customers/domain/models/loan.dart';

/// Customer profile screen implementing Story 2.5 AC-2 and AC-3.
///
/// Displays photo thumbnail, verified name, contact summary (masked per RBAC),
/// and all associated loans categorized by status badges (Active, Overdue,
/// Settled).
///
/// When a customer has multiple actionable loans, tapping an action button
/// opens a multi-loan selection dialog requiring explicit target loan selection.
class CustomerProfileScreen extends StatefulWidget {
  const CustomerProfileScreen({
    super.key,
    required this.shopId,
    required this.customerId,
    this.canViewSensitive = false,
    this.database,
  });

  final String shopId;
  final String customerId;

  /// Whether the viewer possesses [viewSensitiveCustomerData] permission.
  /// When false, NIC/phone/address are masked per Story 2.5 AC-1.
  final bool canViewSensitive;

  /// Optional injected [AppDatabase] for testing.
  final AppDatabase? database;

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  late CustomerDao _customerDao;
  late LoanDao _loanDao;

  Customer? _customer;
  List<Loan> _loans = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final db = widget.database ?? AppDatabase();
      _customerDao = CustomerDao(db);
      _loanDao = LoanDao(db);

      final customer = await _customerDao.getCustomerById(
        widget.shopId,
        widget.customerId,
      );
      final loans = await _loanDao.getLoansByCustomerId(
        widget.shopId,
        widget.customerId,
      );

      await db.close();

      if (!mounted) return;

      setState(() {
        _customer = customer;
        _loans = loans;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load profile: $e';
      });
    }
  }

  void _onLoanAction(BuildContext context, Loan loan) {
    final actionableLoans = _loans.where((l) => l.isActionable).toList();

    if (actionableLoans.length > 1) {
      // Multiple eligible loans — require explicit selection
      _showMultiLoanSelectionDialog(context, actionableLoans);
    } else if (actionableLoans.length == 1) {
      // Single eligible loan — proceed directly
      _proceedToLoanAction(context, actionableLoans.first);
    }
    // Zero actionable loans — no action available
  }

  void _showMultiLoanSelectionDialog(
    BuildContext context,
    List<Loan> loans,
  ) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Select Loan'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: loans.length,
              itemBuilder: (context, index) {
                final loan = loans[index];
                return ListTile(
                  title: Text('Loan ${loan.id.substring(0, loan.id.length.clamp(0, 8))}...'),
                  subtitle: Text(
                    'Status: ${loan.status.value.toUpperCase()}  |  '
                    'Balance: ${loan.balanceCents / 100}',
                  ),
                  trailing: Chip(
                    label: Text(loan.status.value.toUpperCase()),
                    backgroundColor: _statusChipColor(loan.status),
                  ),
                  onTap: () {
                    Navigator.of(dialogContext).pop(loan.id);
                    _proceedToLoanAction(context, loan);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Color _statusChipColor(LoanStatus status) {
    switch (status) {
      case LoanStatus.active:
        return Colors.green.withValues(alpha: 0.15);
      case LoanStatus.overdue:
        return Colors.orange.withValues(alpha: 0.15);
      case LoanStatus.settled:
        return Colors.grey.withValues(alpha: 0.15);
    }
  }

  void _proceedToLoanAction(BuildContext context, Loan loan) {
    // Placeholder for loan action navigation (payment, detail, collateral return)
    // These are handled by later stories (5.x, 6.x). For Story 2.5, we simply
    // confirm the selection was made.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Selected loan: ${loan.id.substring(0, loan.id.length.clamp(0, 8))}...'),
        duration: const Duration(seconds: 2),
      ),
    );
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
        appBar: AppBar(title: const Text('Customer Profile')),
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

    if (_customer == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Customer Profile')),
        body: Center(child: Text('Customer not found')),
      );
    }

    final customer = _customer!;
    final activeLoans = _loans.where((l) => l.status == LoanStatus.active).toList();
    final overdueLoans = _loans.where((l) => l.status == LoanStatus.overdue).toList();
    final settledLoans = _loans.where((l) => l.status == LoanStatus.settled).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Profile'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo thumbnail
            Center(
              child: CircleAvatar(
                radius: 50,
                backgroundImage: customer.photoUri != null
                    ? FileImage(File(customer.photoUri!))
                    : null,
                child: customer.photoUri == null
                    ? const Icon(Icons.person, size: 50)
                    : null,
              ),
            ),
            const SizedBox(height: 16),

            // Name
            Text(
              customer.fullName,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            // Contact summary (masked per RBAC)
            Text(
              'NIC: ${widget.canViewSensitive ? customer.nic : maskNic(customer.nic)}',
            ),
            Text(
              'Phone: ${widget.canViewSensitive ? customer.phone : maskPhone(customer.phone)}',
            ),
            Text(
              'Address: ${widget.canViewSensitive ? customer.address : kAddressWithheld}',
            ),
            const SizedBox(height: 24),

            // Loans section
            const Text(
              'Loans',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            if (_loans.isEmpty)
              const Text('No loans found'),
            if (_loans.isNotEmpty) ...[
              _LoanStatusSection(
                title: 'Active',
                loans: activeLoans,
                color: Colors.green,
                onTap: (loan) => _onLoanAction(context, loan),
              ),
              _LoanStatusSection(
                title: 'Overdue',
                loans: overdueLoans,
                color: Colors.orange,
                onTap: (loan) => _onLoanAction(context, loan),
              ),
              _LoanStatusSection(
                title: 'Settled',
                loans: settledLoans,
                color: Colors.grey,
                onTap: (loan) => _onLoanAction(context, loan),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A section displaying loans of a single status.
class _LoanStatusSection extends StatelessWidget {
  final String title;
  final List<Loan> loans;
  final Color color;
  final ValueChanged<Loan> onTap;

  const _LoanStatusSection({
    required this.title,
    required this.loans,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (loans.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '$title (${loans.length})',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...loans.map((loan) => Card(
          child: ListTile(
            title: Text('Loan ${loan.id.substring(0, loan.id.length.clamp(0, 8))}...'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Principal: ${loan.principalCents / 100}'),
                Text('Balance: ${loan.balanceCents / 100}'),
                Text('Due: ${loan.dueDate.toString().substring(0, 10)}'),
              ],
            ),
            trailing: Chip(
              label: Text(loan.status.value.toUpperCase()),
              backgroundColor: color.withValues(alpha: 0.15),
            ),
            onTap: () => onTap(loan),
          ),
        )),
        const SizedBox(height: 16),
      ],
    );
  }
}
