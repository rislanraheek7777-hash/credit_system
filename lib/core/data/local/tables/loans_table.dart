import 'package:drift/drift.dart';
import 'customers_table.dart';
import 'shops_table.dart';

/// Local SQLite schema for loan agreements (Story 2.5).
///
/// Stores zero-interest loan agreements scoped to a shop tenant,
/// linked to a customer borrower. Loan lifecycle status is stored
/// as text and enforced by a CHECK constraint.
///
/// Binds: PRD FR-11; AD-1 (tenant isolation).
@DataClassName('LoanEntry')
@TableIndex(name: 'idx_loans_shop_id', columns: {#shopId})
@TableIndex(name: 'idx_loans_shop_customer', columns: {#shopId, #customerId})
@TableIndex(name: 'idx_loans_shop_status', columns: {#shopId, #status})
@TableIndex(name: 'idx_loans_shop_customer_status', columns: {#shopId, #customerId, #status})
class Loans extends Table {
  /// Canonical UUIDv4 primary key.
  TextColumn get id => text()();

  /// Tenant shop association (immutable foreign key boundary).
  TextColumn get shopId =>
      text().references(Shops, #id, onDelete: KeyAction.restrict)();

  /// Associated customer borrower (immutable foreign key boundary).
  TextColumn get customerId =>
      text().references(Customers, #id, onDelete: KeyAction.restrict)();

  /// Original principal in minor units (cents).
  IntColumn get principalCents => integer()();

  /// Outstanding balance in minor units (cents).
  IntColumn get balanceCents => integer()();

  /// Lifecycle status: 'active', 'overdue', 'settled'.
  TextColumn get status =>
      text().withDefault(const Constant('active'))();

  /// Official due date (UTC).
  DateTimeColumn get dueDate => dateTime()();

  /// UTC creation timestamp.
  DateTimeColumn get createdAt => dateTime()();

  /// UTC settlement timestamp (null while not settled).
  DateTimeColumn get settledAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (principal_cents >= 0)",
    "CHECK (balance_cents >= 0)",
    "CHECK (balance_cents <= principal_cents)",
    "CHECK (status IN ('active', 'overdue', 'settled'))",
    "CHECK (status <> 'settled' OR settled_at IS NOT NULL)",
  ];
}
