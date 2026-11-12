import 'package:drift/drift.dart';

/// Local SQLite schema for shop tenants.
///
/// Stores shop metadata including operational timezone (IANA identifier,
/// e.g. 'Asia/Colombo'), currency display preference (e.g. 'LKR'), and
/// comprehensive business profile and receipt branding configurations (Story 1.6).
@DataClassName('ShopEntry')
class Shops extends Table {
  /// Canonical UUIDv4 primary key.
  TextColumn get id => text()();

  /// Registered legal or trading name of the shop.
  TextColumn get name => text().withLength(min: 1, max: 255)();

  /// Primary operating currency code (ISO 4217, 3 uppercase characters).
  TextColumn get currencyCode =>
      text().withDefault(const Constant('LKR')).withLength(min: 3, max: 3)();

  /// Operational IANA timezone identifier for midnight boundary evaluation.
  TextColumn get timezone =>
      text().withDefault(const Constant('Asia/Colombo'))();

  /// Type of shop (e.g. Retail, Wholesale, Service).
  TextColumn get shopType => text().nullable()();

  /// Physical or business street address of the retail shop.
  TextColumn get businessAddress => text().nullable()();

  /// Contact telephone number for shop enquiries.
  TextColumn get contactPhone => text().nullable()();

  /// Official contact email address.
  TextColumn get contactEmail => text().nullable()();

  /// Official business registration or tax identification number.
  TextColumn get registrationNumber => text().nullable()();

  /// Local URI or sandboxed path to the shop's logo image asset.
  TextColumn get logoUri => text().nullable()();

  /// Custom notes or terms printed at the top of customer receipt slips.
  TextColumn get receiptHeaderNotes => text().nullable()();

  /// Custom notes, return policies, or closing greetings at the bottom of receipts.
  TextColumn get receiptFooterNotes => text().nullable()();

  /// UTC creation timestamp.
  DateTimeColumn get createdAt => dateTime()();

  /// UTC last-update timestamp.
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

