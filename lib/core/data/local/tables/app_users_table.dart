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

  /// Optional email address, unique within the shop tenant boundary when set.
  TextColumn get email => text().withLength(min: 0, max: 255).nullable()();

  /// Optional phone number, unique within the shop tenant boundary when set.
  TextColumn get phone => text().withLength(min: 0, max: 50).nullable()();

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

  /// Comma-separated list of granted permission keys for Custom roles (Story 1.7).
  TextColumn get permissions => text().nullable()();

  /// Encrypted password hash for authentication (Story 1.7).
  ///
  /// Nullable to preserve existing users created before password authentication
  /// was introduced. Existing users must have a password set via Shop Owner
  /// administration before they can authenticate.
  TextColumn get passwordHash => text().nullable()();

  /// UTC creation timestamp.
  DateTimeColumn get createdAt => dateTime()();

  /// UTC last-update timestamp.
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {shopId, username},
    // Story 1.10: close the contact-identifier collision so a verified email
    // or phone resolves to exactly one staff account within a tenant.
    {shopId, email},
    {shopId, phone},
  ];

  @override
  List<String> get customConstraints => [
    'CHECK (session_version >= 1)',
  ];
}

