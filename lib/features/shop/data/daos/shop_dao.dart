import 'package:drift/drift.dart';
import '../../../../core/data/local/app_database.dart';
import '../../../../core/data/local/tables/shops_table.dart';
import '../../domain/models/shop_profile.dart';

part 'shop_dao.g.dart';

/// Exception thrown when an attempt is made to change the base currency of a shop
/// after financial transactions have been recorded.
class CurrencyLockedException implements Exception {
  final String message;
  const CurrencyLockedException(this.message);

  @override
  String toString() => 'CurrencyLockedException: $message';
}

/// Data Access Object for Shop tenant configuration and profile management (Story 1.6).
@DriftAccessor(tables: [Shops])
class ShopDao extends DatabaseAccessor<AppDatabase> with _$ShopDaoMixin {
  ShopDao(super.db);

  /// Converts a Drift [ShopEntry] row into a domain [ShopProfile].
  ShopProfile _toDomain(ShopEntry entry) {
    return ShopProfile(
      id: entry.id,
      name: entry.name,
      currencyCode: entry.currencyCode,
      timezone: entry.timezone,
      businessAddress: entry.businessAddress,
      contactPhone: entry.contactPhone,
      contactEmail: entry.contactEmail,
      registrationNumber: entry.registrationNumber,
      logoUri: entry.logoUri,
      receiptHeaderNotes: entry.receiptHeaderNotes,
      receiptFooterNotes: entry.receiptFooterNotes,
      createdAt: entry.createdAt,
      updatedAt: entry.updatedAt,
    );
  }

  /// Converts a domain [ShopProfile] into a Drift [ShopsCompanion] for insert or update.
  ShopsCompanion _toCompanion(ShopProfile profile) {
    return ShopsCompanion(
      id: Value(profile.id),
      name: Value(profile.name),
      currencyCode: Value(profile.currencyCode),
      timezone: Value(profile.timezone),
      businessAddress: Value(profile.businessAddress),
      contactPhone: Value(profile.contactPhone),
      contactEmail: Value(profile.contactEmail),
      registrationNumber: Value(profile.registrationNumber),
      logoUri: Value(profile.logoUri),
      receiptHeaderNotes: Value(profile.receiptHeaderNotes),
      receiptFooterNotes: Value(profile.receiptFooterNotes),
      createdAt: Value(profile.createdAt),
      updatedAt: Value(profile.updatedAt),
    );
  }

  /// Retrieves a shop by its unique [shopId], returning null if not found.
  Future<ShopProfile?> getShopById(String shopId) async {
    final query = select(shops)..where((s) => s.id.equals(shopId));
    final entry = await query.getSingleOrNull();
    return entry != null ? _toDomain(entry) : null;
  }

  /// Inserts a new shop profile into the database.
  Future<void> createShop(ShopProfile profile) async {
    await into(shops).insert(_toCompanion(profile));
  }

  /// Checks whether any financial transactions exist locally for the specified [shopId].
  ///
  /// IMPORTANT ARCHITECTURE & SECURITY NOTICE:
  /// Local currency locking via this method is an offline heuristic safeguard and
  /// cannot guarantee detection of all financial transactions across all scenarios
  /// (e.g., pruned `sync_queue` entries, or multi-terminal transactions recorded on
  /// other devices and not yet synchronized to this local device).
  ///
  /// In the current local database schema (v1 & v2), business financial ledger tables
  /// (`loans`, `payments`, `disbursements`, etc.) have not yet been introduced
  /// (scheduled for Epics 4 and 5).
  ///
  /// Authoritative, permanent currency locking MUST be enforced by the trusted backend
  /// and database constraints (e.g., PostgreSQL foreign keys, triggers, or RLS rules)
  /// when the financial ledger is implemented in Epics 4 and 5.
  ///
  /// This local query inspects:
  /// 1. Any queued financial transactions in `sync_queue` for this shop (`entity_type` IN ('loan', 'payment', 'disbursement', 'reversal')).
  /// 2. If future tables exist in `sqlite_master`, dynamically checks their row counts.
  Future<bool> hasFinancialTransactions(String shopId) async {
    // 1. Check sync_queue for pending or confirmed financial entities
    final financialEntities = ['loan', 'payment', 'disbursement', 'reversal'];
    final queueCount = await (select(db.syncQueue)
          ..where((q) =>
              q.shopId.equals(shopId) & q.entityType.isIn(financialEntities)))
        .get();

    if (queueCount.isNotEmpty) {
      return true;
    }

    // 2. Check if any future financial transaction tables exist in SQLite catalog
    final tableCheck = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('loans', 'payments', 'transactions');",
    ).get();

    for (final row in tableCheck) {
      final tableName = row.read<String>('name');
      final txCount = await customSelect(
        'SELECT COUNT(*) as c FROM $tableName WHERE shop_id = ?;',
        variables: [Variable.withString(shopId)],
      ).getSingle();

      if (txCount.read<int>('c') > 0) {
        return true;
      }
    }

    return false;
  }

  /// Updates an existing shop profile.
  ///
  /// Enforces Story 1.6 Acceptance Criterion:
  /// "Once any financial transaction (loan agreement, disbursement, payment, or reversal)
  /// exists within the shop tenant, the underlying base ledger currency code is strictly
  /// locked and cannot be altered."
  Future<void> updateShopProfile(ShopProfile updatedProfile) async {
    final existing = await getShopById(updatedProfile.id);
    if (existing == null) {
      throw StateError('Cannot update non-existent shop with ID: ${updatedProfile.id}');
    }

    // Check currency lock rule
    if (existing.currencyCode != updatedProfile.currencyCode) {
      final hasTransactions = await hasFinancialTransactions(updatedProfile.id);
      if (hasTransactions) {
        throw CurrencyLockedException(
          'Base currency is locked to ${existing.currencyCode} because financial transactions exist for this shop.',
        );
      }
    }

    final companion = _toCompanion(updatedProfile.copyWith(updatedAt: DateTime.now().toUtc()));

    await (update(shops)..where((s) => s.id.equals(updatedProfile.id))).write(companion);
  }
}
