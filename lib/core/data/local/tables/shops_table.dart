import 'package:drift/drift.dart';

/// Local SQLite schema for shop tenants.
///
/// Stores shop metadata including operational timezone (IANA identifier,
/// e.g. 'Asia/Colombo') and currency display preference (e.g. 'LKR').
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

  /// UTC creation timestamp.
  DateTimeColumn get createdAt => dateTime()();

  /// UTC last-update timestamp.
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
