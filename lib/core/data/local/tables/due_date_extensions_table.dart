import 'package:drift/drift.dart';

import 'app_users_table.dart';
import 'loans_table.dart';
import 'shops_table.dart';

/// Local SQLite schema for due date extensions (Story 6.2, FR-26).
///
/// Stores due date extensions granted by the Shop Owner.
/// Preserves an immutable history chain of previous and new due dates,
/// mandatory justification, grantor user ID, and timestamp.
@DataClassName('DueDateExtensionEntry')
@TableIndex(name: 'idx_due_date_extensions_shop_id', columns: {#shopId})
@TableIndex(name: 'idx_due_date_extensions_shop_loan', columns: {#shopId, #loanId})
class DueDateExtensions extends Table {
  /// Canonical UUIDv4 primary key.
  TextColumn get id => text()();

  /// Tenant shop association (immutable foreign key boundary).
  TextColumn get shopId =>
      text().references(Shops, #id, onDelete: KeyAction.restrict)();

  /// Associated loan agreement (immutable foreign key boundary).
  TextColumn get loanId =>
      text().references(Loans, #id, onDelete: KeyAction.restrict)();

  /// Calendar due date prior to this extension (stored in UTC).
  DateTimeColumn get previousDueDate => dateTime()();

  /// Newly granted calendar due date (stored in UTC).
  DateTimeColumn get newDueDate => dateTime()();

  /// Mandatory business justification for granting the extension.
  TextColumn get reason => text().withLength(min: 1)();

  /// User UUID of the Shop Owner who authorized the extension.
  TextColumn get grantedByUserId =>
      text().references(AppUsers, #id, onDelete: KeyAction.restrict)();

  /// UTC creation timestamp of the extension record.
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'CHECK (length(trim(reason)) > 0)',
      ];
}
