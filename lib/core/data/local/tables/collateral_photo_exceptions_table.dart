import 'package:drift/drift.dart';
import 'app_users_table.dart';
import 'collateral_items_table.dart';
import 'shops_table.dart';

/// Local SQLite schema for collateral photo exception requests and decisions (Story 3.2, FR-15, AD-6).
///
/// Binds:
/// - Request by authorized counter staff with documented mandatory reason.
/// - Approval or rejection solely by the Shop Owner.
/// - Bound to a specific collateral item within the shop tenant.
/// - Single-use consumption flag to prevent reuse attacks.
///
/// Unlike [CustomerPhotoExceptions] (bound to targetCustomerId + customerNic),
/// this table is bound to collateral_item_id since collateral items are
/// distinct entities from customer profiles.
@DataClassName('CollateralPhotoExceptionEntry')
@TableIndex(name: 'idx_collateral_photo_exceptions_shop_status', columns: {#shopId, #status})
@TableIndex(name: 'idx_collateral_photo_exceptions_item', columns: {#shopId, #collateralItemId})
class CollateralPhotoExceptions extends Table {
  /// Canonical UUIDv4 primary key.
  TextColumn get id => text()();

  /// Associated shop tenant UUID boundary.
  TextColumn get shopId =>
      text().references(Shops, #id, onDelete: KeyAction.restrict)();

  /// Associated collateral item UUID boundary.
  TextColumn get collateralItemId =>
      text().references(CollateralItems, #id, onDelete: KeyAction.restrict)();

  /// User UUID of the staff member who initiated the exception request.
  @ReferenceName('requestedCollateralPhotoExceptions')
  TextColumn get requestedByUserId =>
      text().references(AppUsers, #id, onDelete: KeyAction.restrict)();

  /// Mandatory documented business justification for requesting the exception.
  TextColumn get requestReason => text().withLength(min: 1)();

  /// Status of the exception request:
  /// - 'pending_owner_approval': Awaiting Shop Owner decision.
  /// - 'approved': Approved by Shop Owner; eligible for registration without photo.
  /// - 'rejected': Rejected by Shop Owner; photo still required.
  /// - 'consumed': Used once during collateral registration; cannot be reused.
  TextColumn get status =>
      text().withDefault(const Constant('pending_owner_approval'))();

  /// User UUID of the Shop Owner who approved or rejected the request (null while pending).
  @ReferenceName('reviewedCollateralPhotoExceptions')
  TextColumn get reviewedByUserId =>
      text().nullable().references(AppUsers, #id, onDelete: KeyAction.restrict)();

  /// Mandatory decision notes or rejection reasons recorded by the Shop Owner.
  TextColumn get reviewNotes => text().nullable()();

  /// UTC timestamp of the Shop Owner's decision.
  DateTimeColumn get reviewedAt => dateTime().nullable()();

  /// UTC timestamp when the request was initiated.
  DateTimeColumn get createdAt => dateTime()();

  /// UTC timestamp of last status change.
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (status IN ('pending_owner_approval', 'approved', 'rejected', 'consumed'))",
  ];
}

