import 'package:drift/drift.dart';

import 'app_users_table.dart';
import 'customers_table.dart';
import 'loans_table.dart';
import 'shops_table.dart';

/// Local SQLite schema for customer delinquency follow-up logs (Story 6.3, FR-27).
///
/// Records contact attempts, notes, channels, and optional promised payment dates.
@DataClassName('CustomerFollowUpEntry')
@TableIndex(name: 'idx_customer_follow_ups_shop_id', columns: {#shopId})
@TableIndex(name: 'idx_customer_follow_ups_shop_loan', columns: {#shopId, #loanId})
class CustomerFollowUps extends Table {
  /// Canonical UUIDv4 primary key.
  TextColumn get id => text()();

  /// Tenant shop association (immutable foreign key boundary).
  TextColumn get shopId =>
      text().references(Shops, #id, onDelete: KeyAction.restrict)();

  /// Associated loan agreement (immutable foreign key boundary).
  TextColumn get loanId =>
      text().references(Loans, #id, onDelete: KeyAction.restrict)();

  /// Associated customer borrower.
  IntColumn get customerId =>
      integer().references(Customers, #id, onDelete: KeyAction.restrict)();

  /// Staff member who performed the follow-up.
  TextColumn get staffId =>
      text().references(AppUsers, #id, onDelete: KeyAction.restrict)();

  /// Communication channel: 'phone_call', 'in_person', 'physical_notice'.
  TextColumn get channel => text()();

  /// Interaction notes.
  TextColumn get notes => text().withLength(min: 1)();

  /// Optional promised payment date (stored in UTC).
  DateTimeColumn get promisedPaymentDate => dateTime().nullable()();

  /// UTC timestamp when follow-up was recorded.
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'CHECK (length(trim(notes)) > 0)',
        "CHECK (channel IN ('phone_call', 'in_person', 'physical_notice'))",
      ];
}
