import 'package:drift/drift.dart';
import 'shops_table.dart';

/// Local SQLite schema for customer borrower profiles (Story 2.1, FR-8, AD-1).
///
/// Stores reusable KYC customer identity records scoped to a shop tenant,
/// enforcing tenant-level unique NIC constraints.
@DataClassName('CustomerEntry')
@TableIndex(name: 'idx_customers_shop_id', columns: {#shopId})
@TableIndex(name: 'idx_customers_shop_nic', columns: {#shopId, #nic})
@TableIndex(name: 'idx_customers_shop_phone', columns: {#shopId, #phone})
class Customers extends Table {
  /// Auto-increment primary key (hidden: system-generated).
  IntColumn get id => integer().autoIncrement()();

  /// Tenant shop association (immutable foreign key boundary).
  TextColumn get shopId =>
      text().references(Shops, #id, onDelete: KeyAction.restrict)();

  /// Full legal name of the borrower.
  TextColumn get fullName => text().withLength(min: 1, max: 255)();

  /// National Identity Card (NIC) number, normalized to uppercase.
  /// Optional: nullable to allow multiple customers without NIC.
  TextColumn get nic => text().withLength(max: 50).nullable()();

  /// Primary contact telephone number.
  TextColumn get phone => text().withLength(min: 1, max: 50)();

  /// Residential street address.
  /// Optional: nullable to allow customers without an address.
  TextColumn get address => text().nullable()();

  /// Local file URI or sandboxed path to compressed customer KYC photo.
  TextColumn get photoUri => text().nullable()();

  /// Cryptographic SHA-256 hash of the photo file.
  TextColumn get photoHash => text().nullable()();

  /// UTC creation timestamp.
  DateTimeColumn get createdAt => dateTime()();

  /// UTC last-update timestamp.
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {shopId, nic},
  ];
}

