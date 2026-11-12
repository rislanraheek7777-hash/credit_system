import 'package:drift/drift.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/tables/collateral_custody_events_table.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_custody_event.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';

part 'collateral_custody_event_dao.g.dart';

/// Data Access Object for collateral custody events (Story 3.4).
///
/// All queries are strictly scoped to [shopId] to enforce tenant isolation.
/// A custody event can only be created, read, or updated within its owning shop.
///
/// Binds: PRD FR-16; AD-1 (tenant isolation); AD-4 (clean architecture).
@DriftAccessor(tables: [CollateralCustodyEvents])
class CollateralCustodyEventDao extends DatabaseAccessor<AppDatabase>
    with _$CollateralCustodyEventDaoMixin {
  CollateralCustodyEventDao(super.db);

  /// Converts a Drift [CollateralCustodyEventEntry] row into a domain
  /// [CollateralCustodyEvent].
  CollateralCustodyEvent _toDomain(CollateralCustodyEventEntry entry) {
    return CollateralCustodyEvent(
      id: entry.id,
      shopId: entry.shopId,
      collateralItemId: entry.collateralItemId,
      reportedByUserId: entry.reportedByUserId,
      previousStatus: CollateralCustodyStatus.fromValue(entry.previousStatus),
      newStatus: CollateralCustodyStatus.fromValue(entry.newStatus),
      reason: entry.reason,
      createdAt: entry.createdAt.toUtc(),
    );
  }

  /// Converts a domain [CollateralCustodyEvent] into a Drift
  /// [CollateralCustodyEventsCompanion].
  CollateralCustodyEventsCompanion _toCompanion(
    CollateralCustodyEvent event,
  ) {
    return CollateralCustodyEventsCompanion(
      id: Value(event.id),
      shopId: Value(event.shopId),
      collateralItemId: Value(event.collateralItemId),
      reportedByUserId: Value(event.reportedByUserId),
      previousStatus: Value(event.previousStatus.value),
      newStatus: Value(event.newStatus.value),
      reason: Value(event.reason),
      createdAt: Value(event.createdAt),
    );
  }

  /// Inserts a new collateral custody event record into SQLite.
  Future<void> createEvent(CollateralCustodyEvent event) async {
    await into(collateralCustodyEvents).insert(_toCompanion(event));
  }

  /// Retrieves all custody events for a collateral item within [shopId],
  /// ordered by creation time ascending.
  Future<List<CollateralCustodyEvent>> getEventsByCollateralItemId(
    String shopId,
    String collateralItemId,
  ) async {
    final query = select(collateralCustodyEvents)
      ..where((e) =>
          e.shopId.equals(shopId) &
          e.collateralItemId.equals(collateralItemId))
      ..orderBy([(e) => OrderingTerm.asc(e.createdAt)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Retrieves all custody events for [shopId], ordered by creation time.
  Future<List<CollateralCustodyEvent>> getEventsByShopId(String shopId) async {
    final query = select(collateralCustodyEvents)
      ..where((e) => e.shopId.equals(shopId))
      ..orderBy([(e) => OrderingTerm.asc(e.createdAt)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }
}

