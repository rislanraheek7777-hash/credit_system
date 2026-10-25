import 'package:drift/drift.dart';
import 'app_users_table.dart';
import 'collateral_items_table.dart';
import 'shops_table.dart';

/// Local SQLite schema for collateral custody state change events (Story 3.4).
///
/// Records every custody state transition on a collateral item, including
/// the actor, timestamp, previous state, new state, and reason. Provides an
/// immutable audit trail that cannot be overwritten or deleted.
///
/// Unlike [CollateralItems] (which stores only the current custody state),
/// this table preserves the complete history of all custody transitions.
@DataClassName('CollateralCustodyEventEntry')
@TableIndex(name: 'idx_custody_events_shop_id', columns: {#shopId})
@TableIndex(name: 'idx_custody_events_item_id', columns: {#shopId, #collateralItemId})
@TableIndex(name: 'idx_custody_events_created_at', columns: {#shopId, #createdAt})
class CollateralCustodyEvents extends Table {
  /// Canonical UUIDv4 primary key.
  TextColumn get id => text()();

  /// Associated shop tenant UUID boundary.
  TextColumn get shopId =>
      text().references(Shops, #id, onDelete: KeyAction.restrict)();

  /// Associated collateral item UUID boundary.
  TextColumn get collateralItemId =>
      text().references(CollateralItems, #id, onDelete: KeyAction.restrict)();

  /// User UUID of the staff member who initiated the transition.
  @ReferenceName('requestedCustodyEvents')
  TextColumn get reportedByUserId =>
      text().references(AppUsers, #id, onDelete: KeyAction.restrict)();

  /// Previous custody state before the transition.
  TextColumn get previousStatus => text()();

  /// New custody state after the transition.
  TextColumn get newStatus => text()();

  /// Reason for the custody transition.
  TextColumn get reason => text().withLength(min: 1)();

  /// UTC timestamp when the transition was recorded.
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (previous_status IN ('in_custody', 'handover_requested', 'handover_reported', 'returned', 'exception_held', 'discrepancy'))",
    "CHECK (new_status IN ('in_custody', 'handover_requested', 'handover_reported', 'returned', 'exception_held', 'discrepancy'))",
  ];
}

/// Local SQLite schema for collateral discrepancy reports (Story 3.4).
///
/// Records discrepancies between the system state and physical reality of
/// collateral items, including the reporter, timestamp, reason, and the
/// Shop Owner's decision (resolution, resolved by, resolution notes, resolved at).
///
/// Unlike [CollateralCustodyEvents] (which records state transitions), this
/// table records discrepancy reports and their resolutions separately.
@DataClassName('CollateralDiscrepancyEntry')
@TableIndex(name: 'idx_collateral_discrepancies_shop_id', columns: {#shopId})
@TableIndex(name: 'idx_collateral_discrepancies_item_id', columns: {#shopId, #collateralItemId})
@TableIndex(name: 'idx_collateral_discrepancies_status', columns: {#shopId, #status})
class CollateralDiscrepancies extends Table {
  /// Canonical UUIDv4 primary key.
  TextColumn get id => text()();

  /// Associated shop tenant UUID boundary.
  TextColumn get shopId =>
      text().references(Shops, #id, onDelete: KeyAction.restrict)();

  /// Associated collateral item UUID boundary.
  TextColumn get collateralItemId =>
      text().references(CollateralItems, #id, onDelete: KeyAction.restrict)();

  /// User UUID of the staff member who reported the discrepancy.
  @ReferenceName('reportedCollateralDiscrepancies')
  TextColumn get reportedByUserId =>
      text().references(AppUsers, #id, onDelete: KeyAction.restrict)();

  /// Documented reason for the discrepancy.
  TextColumn get discrepancyReason => text().withLength(min: 1)();

  /// Status of the discrepancy request:
  /// - 'pending': Awaiting Shop Owner decision.
  /// - 'resolved': Resolved by Shop Owner.
  TextColumn get status => text()();

  /// User UUID of the Shop Owner who resolved the discrepancy (null while pending).
  @ReferenceName('resolvedCollateralDiscrepancies')
  TextColumn get resolvedByUserId =>
      text().nullable().references(AppUsers, #id, onDelete: KeyAction.restrict)();

  /// Resolution notes or decision rationale recorded by the Shop Owner.
  TextColumn get resolutionNotes => text().nullable()();

  /// UTC timestamp of the Shop Owner's decision (null while pending).
  DateTimeColumn get resolvedAt => dateTime().nullable()();

  /// UTC timestamp when the discrepancy was reported.
  DateTimeColumn get createdAt => dateTime()();

  /// UTC timestamp of last status change.
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (status IN ('pending', 'resolved'))",
  ];
}
