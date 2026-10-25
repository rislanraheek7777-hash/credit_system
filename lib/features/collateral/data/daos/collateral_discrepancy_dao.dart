import 'package:drift/drift.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/tables/collateral_custody_events_table.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_custody_event.dart';

part 'collateral_discrepancy_dao.g.dart';

/// Data Access Object for collateral discrepancy reports (Story 3.4).
///
/// All queries are strictly scoped to [shopId] to enforce tenant isolation.
/// A discrepancy can only be created, read, or updated within its owning shop.
///
/// Binds: PRD FR-16; AD-1 (tenant isolation); AD-4 (clean architecture).
@DriftAccessor(tables: [CollateralDiscrepancies])
class CollateralDiscrepancyDao extends DatabaseAccessor<AppDatabase>
    with _$CollateralDiscrepancyDaoMixin {
  CollateralDiscrepancyDao(super.db);

  /// Converts a Drift [CollateralDiscrepancyEntry] row into a domain
  /// [CollateralDiscrepancy].
  CollateralDiscrepancy _toDomain(CollateralDiscrepancyEntry entry) {
    return CollateralDiscrepancy(
      id: entry.id,
      shopId: entry.shopId,
      collateralItemId: entry.collateralItemId,
      reportedByUserId: entry.reportedByUserId,
      discrepancyReason: entry.discrepancyReason,
      status: CollateralDiscrepancyStatus.fromValue(entry.status),
      resolvedByUserId: entry.resolvedByUserId,
      resolutionNotes: entry.resolutionNotes,
      resolvedAt: entry.resolvedAt?.toUtc(),
      createdAt: entry.createdAt.toUtc(),
      updatedAt: entry.updatedAt.toUtc(),
    );
  }

  /// Converts a domain [CollateralDiscrepancy] into a Drift
  /// [CollateralDiscrepanciesCompanion].
  CollateralDiscrepanciesCompanion _toCompanion(
    CollateralDiscrepancy discrepancy,
  ) {
    return CollateralDiscrepanciesCompanion(
      id: Value(discrepancy.id),
      shopId: Value(discrepancy.shopId),
      collateralItemId: Value(discrepancy.collateralItemId),
      reportedByUserId: Value(discrepancy.reportedByUserId),
      discrepancyReason: Value(discrepancy.discrepancyReason),
      status: Value(discrepancy.status.value),
      resolvedByUserId: Value(discrepancy.resolvedByUserId),
      resolutionNotes: Value(discrepancy.resolutionNotes),
      resolvedAt:
          discrepancy.resolvedAt != null
              ? Value(discrepancy.resolvedAt!)
              : const Value.absent(),
      createdAt: Value(discrepancy.createdAt),
      updatedAt: Value(discrepancy.updatedAt),
    );
  }

  /// Inserts a new collateral discrepancy report record into SQLite.
  Future<void> createDiscrepancy(CollateralDiscrepancy discrepancy) async {
    await into(collateralDiscrepancies).insert(_toCompanion(discrepancy));
  }

  /// Retrieves a discrepancy by [discrepancyId] strictly scoped within [shopId].
  ///
  /// Returns `null` if the discrepancy does not exist or belongs to another shop.
  Future<CollateralDiscrepancy?> getDiscrepancyById(
    String shopId,
    String discrepancyId,
  ) async {
    final query = select(collateralDiscrepancies)
      ..where((d) =>
          d.shopId.equals(shopId) & d.id.equals(discrepancyId));
    final entry = await query.getSingleOrNull();
    return entry != null ? _toDomain(entry) : null;
  }

  /// Retrieves all discrepancy reports for [shopId], ordered by creation time.
  Future<List<CollateralDiscrepancy>> getDiscrepanciesByShopId(
    String shopId,
  ) async {
    final query = select(collateralDiscrepancies)
      ..where((d) => d.shopId.equals(shopId))
      ..orderBy([(d) => OrderingTerm.asc(d.createdAt)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Retrieves all discrepancy reports for a collateral item within [shopId].
  Future<List<CollateralDiscrepancy>> getDiscrepanciesByCollateralItemId(
    String shopId,
    String collateralItemId,
  ) async {
    final query = select(collateralDiscrepancies)
      ..where((d) =>
          d.shopId.equals(shopId) &
          d.collateralItemId.equals(collateralItemId))
      ..orderBy([(d) => OrderingTerm.desc(d.createdAt)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Updates a discrepancy resolution (Shop Owner action).
  ///
  /// The update only succeeds while the discrepancy is still `pending`; this
  /// check-and-update guard prevents duplicate or conflicting concurrent
  /// resolutions. Returns the number of rows updated (0 means it was already
  /// resolved by a concurrent transaction).
  Future<int> resolveDiscrepancy(CollateralDiscrepancy discrepancy) async {
    final existing = await getDiscrepancyById(
      discrepancy.shopId,
      discrepancy.id,
    );
    if (existing == null) {
      throw StateError(
        'Cannot update discrepancy: ID "${discrepancy.id}" not found in shop "${discrepancy.shopId}".',
      );
    }

    final companion = CollateralDiscrepanciesCompanion(
      id: const Value.absent(),
      shopId: const Value.absent(),
      collateralItemId: const Value.absent(),
      reportedByUserId: const Value.absent(),
      discrepancyReason: const Value.absent(),
      status: Value(discrepancy.status.value),
      resolvedByUserId: Value(discrepancy.resolvedByUserId),
      resolutionNotes: Value(discrepancy.resolutionNotes),
      resolvedAt:
          discrepancy.resolvedAt != null
              ? Value(discrepancy.resolvedAt!)
              : const Value.absent(),
      createdAt: const Value.absent(),
      updatedAt: Value(DateTime.now().toUtc()),
    );

    final rowsAffected = await (update(collateralDiscrepancies)
          ..where((d) =>
              d.shopId.equals(discrepancy.shopId) &
              d.id.equals(discrepancy.id) &
              d.status.equals(CollateralDiscrepancyStatus.pending.value)))
        .write(companion);
    return rowsAffected;
  }
}
