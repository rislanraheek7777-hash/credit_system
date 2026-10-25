import 'package:drift/drift.dart';

import 'app_users_table.dart';
import 'loans_table.dart';
import 'shops_table.dart';

/// Local SQLite schema for loan-level administrative closures with collateral
/// exception (Story 3.5, PRD FR-16, AD-3).
///
/// When a settled loan has collateral items permanently in `exceptionHeld`
/// custody (e.g. police seizure, vault theft, irreparable condition), the Shop
/// Owner may administratively close the loan-level collateral account. The
/// closure record captures the owner's mandatory sign-off reason and the list
/// of exception-held item IDs at closure time.
///
/// The loan's overall workflow status is *derived dynamically* (AD-3): if a
/// settled loan has an administrative closure record, its displayed status is
/// "Closed (Collateral Exception)" — no new column is added to [Loans].
@DataClassName('LoanAdministrativeClosureEntry')
@TableIndex(
  name: 'idx_loan_admin_closures_shop_id',
  columns: {#shopId},
)
@TableIndex(
  name: 'idx_loan_admin_closures_shop_loan',
  columns: {#shopId, #loanId},
)
class LoanAdministrativeClosures extends Table {
  /// Canonical UUIDv4 primary key.
  TextColumn get id => text()();

  /// Tenant shop association (immutable foreign key boundary).
  TextColumn get shopId =>
      text().references(Shops, #id, onDelete: KeyAction.restrict)();

  /// Associated loan agreement. A loan may only have one administrative
  /// closure; uniqueness is enforced at the application layer (the DAO checks
  /// for an existing closure before inserting).
  TextColumn get loanId =>
      text().references(Loans, #id, onDelete: KeyAction.restrict)();

  /// Mandatory business rationale for the administrative closure.
  TextColumn get reason => text().withLength(min: 1)();

  /// User UUID of the Shop Owner who authorised the closure.
  TextColumn get closedByUserId =>
      text().references(AppUsers, #id, onDelete: KeyAction.restrict)();

  /// JSON array of collateral item UUIDs that were in `exceptionHeld` at the
  /// time of closure. Stored as a JSON string for auditability — the items
  /// themselves remain in `exceptionHeld` custody.
  TextColumn get itemIdsJson => text()();

  /// UTC creation timestamp.
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'CHECK (length(trim(reason)) > 0)',
        "CHECK (length(item_ids_json) > 2)", // must be a non-empty JSON array
      ];
}
