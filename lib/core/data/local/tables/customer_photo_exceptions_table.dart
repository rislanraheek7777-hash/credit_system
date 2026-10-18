import 'package:drift/drift.dart';
import 'shops_table.dart';
import 'app_users_table.dart';

/// Local SQLite schema for customer photo KYC exception requests and decisions (Story 2.3, FR-9, AD-6).
///
/// Binds:
/// - Request by authorized counter staff with documented mandatory reason.
/// - Approval or rejection solely by the Shop Owner.
/// - Dual binding to `targetCustomerId` and `customerNic`.
/// - Single-use consumption flag to prevent reuse attacks.
@DataClassName('CustomerPhotoExceptionEntry')
@TableIndex(name: 'idx_photo_exceptions_shop_status', columns: {#shopId, #status})
@TableIndex(name: 'idx_photo_exceptions_customer', columns: {#shopId, #targetCustomerId})
@TableIndex(name: 'idx_photo_exceptions_nic', columns: {#shopId, #customerNic})
class CustomerPhotoExceptions extends Table {
  /// Canonical UUIDv4 primary key.
  TextColumn get id => text()();

  /// Associated shop tenant UUID boundary.
  TextColumn get shopId =>
      text().references(Shops, #id, onDelete: KeyAction.restrict)();

  /// Target customer UUID identifier generated for this onboarding session.
  TextColumn get targetCustomerId => text()();

  /// Normalized National Identity Card (NIC) number of the customer.
  TextColumn get customerNic => text().withLength(min: 1, max: 50)();

  /// User UUID of the staff member who initiated the exception request.
  @ReferenceName('requestedExceptions')
  TextColumn get requestedByUserId =>
      text().references(AppUsers, #id, onDelete: KeyAction.restrict)();

  /// Mandatory documented business justification for requesting the exception.
  TextColumn get requestReason => text().withLength(min: 1)();

  /// Status of the exception request:
  /// - 'pending_owner_approval': Awaiting Shop Owner decision.
  /// - 'approved': Approved by Shop Owner; eligible for customer profile creation.
  /// - 'rejected': Rejected by Shop Owner; profile creation blocked.
  /// - 'consumed': Used once to register the customer; cannot be reused.
  TextColumn get status =>
      text().withDefault(const Constant('pending_owner_approval'))();

  /// User UUID of the Shop Owner who approved or rejected the request (null while pending).
  @ReferenceName('reviewedExceptions')
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
