import 'package:drift/drift.dart';
import 'customers_table.dart';
import 'credits_table.dart';
import 'shops_table.dart';

/// Local SQLite schema for multi-item collateral (Story 3.1, FR-13/FR-14/FR-16).
///
/// Stores pledged collateral items scoped to a shop tenant, linked to a customer
/// borrower and optionally to a credit (nullable until Epic 4 enforces binding).
///
/// Custody state is stored as text and enforced by a CHECK constraint.
/// Weight is stored as integer milligrams to avoid floating-point precision loss.
/// Estimated value is stored as integer cents via [Money] conventions.
///
/// Binds: PRD FR-13, FR-14, FR-16; AD-1 (tenant isolation); AD-2 (integer precision); AD-3 (custody FSM).
@DataClassName('CollateralItemEntry')
@TableIndex(name: 'idx_collateral_shop_id', columns: {#shopId})
@TableIndex(name: 'idx_collateral_shop_customer', columns: {#shopId, #customerId})
@TableIndex(name: 'idx_collateral_shop_credit', columns: {#shopId, #creditId})
@TableIndex(name: 'idx_collateral_shop_custody', columns: {#shopId, #custodyStatus})
@TableIndex(name: 'idx_collateral_shop_category', columns: {#shopId, #category})
class CollateralItems extends Table {
  /// Canonical UUIDv4 primary key.
  TextColumn get id => text()();

  /// Tenant shop association (immutable foreign key boundary).
  TextColumn get shopId =>
      text().references(Shops, #id, onDelete: KeyAction.restrict)();

  /// Associated customer borrower (immutable foreign key boundary, required).
  IntColumn get customerId =>
      integer().references(Customers, #id, onDelete: KeyAction.restrict)();

  /// Optional associated credit (nullable until Epic 4 enforces credit-collateral binding).
  TextColumn get creditId =>
      text().references(Credits, #id, onDelete: KeyAction.restrict).nullable()();

  /// Unique item reference within the shop (e.g., "COLL-001").
  TextColumn get itemReferenceId => text().withLength(min: 1, max: 100)();

  /// Collateral item category: 'gold', 'electronics', 'sports', 'dress',
  /// 'grocery', 'cosmetic', 'medicine', 'valuables', or 'other'.
  TextColumn get category =>
      text().withLength(min: 1, max: 50)();

  /// Human-readable description of the pledged item. Optional (Story 3.5).
  TextColumn get description => text().withLength(max: 1000).nullable()();

  /// Condition grade (free text, e.g., "Like New", "Good", "Fair", "Poor").
  /// Optional (Story 3.5).
  TextColumn get conditionGrade => text().withLength(max: 100).nullable()();

  /// Weight in integer milligrams (e.g., 5.5 g → 5500 mg).
  /// Stored as integer to avoid floating-point precision loss.
  /// Optional (Story 3.5): NULL means the weight was not recorded.
  IntColumn get weightMilligrams => integer().nullable()();

  /// Estimated collateral value in integer minor units (cents).
  /// Follows [Money] conventions — never Dart `double`.
  IntColumn get estimatedValueCents => integer()();

  /// Optional local file URI or sandboxed path to the item photograph.
  TextColumn get photoUri => text().nullable()();

  /// Optional SHA-256 hash of the item photograph.
  TextColumn get photoHash => text().nullable()();

  /// Custody state: 'in_custody', 'handover_requested', 'handover_reported',
  /// 'returned', 'exception_held', or 'discrepancy' (Story 3.4).
  TextColumn get custodyStatus =>
      text().withDefault(const Constant('in_custody'))();

  /// UTC creation timestamp.
  DateTimeColumn get createdAt => dateTime()();

  /// UTC last-update timestamp.
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {shopId, itemReferenceId},
  ];

  @override
  List<String> get customConstraints => [
    "CHECK (weight_milligrams > 0)",
    "CHECK (estimated_value_cents >= 0)",
    "CHECK (category IN ('gold', 'electronics', 'sports', 'dress', 'grocery', 'cosmetic', 'medicine', 'valuables', 'other'))",
    "CHECK (custody_status IN ('in_custody', 'handover_requested', 'handover_reported', 'returned', 'exception_held', 'discrepancy'))",
  ];
}

