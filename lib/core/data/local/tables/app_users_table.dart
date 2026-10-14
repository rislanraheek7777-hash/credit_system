import 'package:drift/drift.dart';
import 'shops_table.dart';

/// Local SQLite schema for counter staff and shop owner accounts.
///
/// Implements shop-scoped username uniqueness, session version tracking
/// for instantaneous revocation, and account activation flags.
@DataClassName('AppUserEntry')
@TableIndex(name: 'idx_app_users_shop_id', columns: {#shopId})
class AppUsers extends Table {
  /// Canonical UUIDv4 primary key.
  TextColumn get id => text()();

  /// Tenant foreign key association.
  TextColumn get shopId =>
      text().references(Shops, #id, onDelete: KeyAction.restrict)();

  /// Username unique within the shop tenant boundary.
  TextColumn get username => text().withLength(min: 1, max: 100)();

  /// Full display name of the user.
  TextColumn get fullName => text().withLength(min: 1, max: 255)();

  /// System role identifier (e.g. 'shop_owner', 'counter_staff').
  TextColumn get role => text()();

  /// Account activation state. Deactivated users cannot log in.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Session version counter (monotonically increasing integer, starts at 1).
  ///
  /// Incremented whenever the account is deactivated, credentials change, or
  /// permissions are modified, immediately revoking all active sessions.
  IntColumn get sessionVersion =>
      integer().withDefault(const Constant(1))();

  /// UTC creation timestamp.
  DateTimeColumn get createdAt => dateTime()();

  /// UTC last-update timestamp.
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {shopId, username},
  ];

  @override
  List<String> get customConstraints => [
    'CHECK (session_version >= 1)',
  ];
}
