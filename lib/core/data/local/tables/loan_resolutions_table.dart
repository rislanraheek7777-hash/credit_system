import 'package:drift/drift.dart';

import 'app_users_table.dart';
import 'loans_table.dart';
import 'shops_table.dart';

/// Local SQLite schema for structured owner overdue case resolutions (Story 6.4, FR-28).
///
/// Records Shop Owner administrative case resolutions:
/// - `under_review`: Account flagged for investigation / notice
/// - `owner_settled_written_off`: Commercial write-off or negotiated closure
/// - `collateral_retained`: Collateral retained or legal/police disposition
@DataClassName('LoanResolutionEntry')
@TableIndex(name: 'idx_loan_resolutions_shop_id', columns: {#shopId})
@TableIndex(name: 'idx_loan_resolutions_shop_loan', columns: {#shopId, #loanId})
class LoanResolutions extends Table {
  /// Canonical UUIDv4 primary key.
  TextColumn get id => text()();

  /// Tenant shop association (immutable foreign key boundary).
  TextColumn get shopId =>
      text().references(Shops, #id, onDelete: KeyAction.restrict)();

  /// Associated loan agreement (unique per loan or latest resolution).
  TextColumn get loanId =>
      text().references(Loans, #id, onDelete: KeyAction.restrict)();

  /// Resolution type: 'under_review', 'owner_settled_written_off', 'collateral_retained'.
  TextColumn get resolutionType => text()();

  /// Mandatory business rationale for the resolution.
  TextColumn get reason => text().withLength(min: 1)();

  /// User UUID of the Shop Owner who decided the resolution.
  TextColumn get resolvedByUserId =>
      text().references(AppUsers, #id, onDelete: KeyAction.restrict)();

  /// UTC creation timestamp.
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'CHECK (length(trim(reason)) > 0)',
        "CHECK (resolution_type IN ('under_review', 'owner_settled_written_off', 'collateral_retained'))",
      ];
}
