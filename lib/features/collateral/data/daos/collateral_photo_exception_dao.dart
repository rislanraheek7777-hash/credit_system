import 'package:drift/drift.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/tables/collateral_photo_exceptions_table.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_photo_exception.dart';

part 'collateral_photo_exception_dao.g.dart';

/// Data Access Object for collateral photo exceptions (Story 3.2, FR-15, AD-6).
///
/// All queries are strictly scoped to [shopId] to enforce tenant isolation.
/// A collateral photo exception can only be created, read, or updated within
/// its owning shop.
///
/// Binds: PRD FR-15; AD-1 (tenant isolation); AD-4 (clean architecture).
@DriftAccessor(tables: [CollateralPhotoExceptions])
class CollateralPhotoExceptionDao extends DatabaseAccessor<AppDatabase>
    with _$CollateralPhotoExceptionDaoMixin {
  CollateralPhotoExceptionDao(super.db);

  /// Converts a Drift [CollateralPhotoExceptionEntry] row into a domain
  /// [CollateralPhotoException].
  CollateralPhotoException _toDomain(CollateralPhotoExceptionEntry entry) {
    return CollateralPhotoException(
      id: entry.id,
      shopId: entry.shopId,
      collateralItemId: entry.collateralItemId,
      requestedByUserId: entry.requestedByUserId,
      requestReason: entry.requestReason,
      status: CollateralPhotoExceptionStatus.fromValue(entry.status),
      reviewedByUserId: entry.reviewedByUserId,
      reviewNotes: entry.reviewNotes,
      reviewedAt: entry.reviewedAt?.toUtc(),
      createdAt: entry.createdAt.toUtc(),
      updatedAt: entry.updatedAt.toUtc(),
    );
  }

  /// Converts a domain [CollateralPhotoException] into a Drift
  /// [CollateralPhotoExceptionsCompanion].
  CollateralPhotoExceptionsCompanion _toCompanion(
    CollateralPhotoException exception,
  ) {
    return CollateralPhotoExceptionsCompanion(
      id: Value(exception.id),
      shopId: Value(exception.shopId),
      collateralItemId: Value(exception.collateralItemId),
      requestedByUserId: Value(exception.requestedByUserId),
      requestReason: Value(exception.requestReason),
      status: Value(exception.status.value),
      reviewedByUserId: Value(exception.reviewedByUserId),
      reviewNotes: Value(exception.reviewNotes),
      reviewedAt: Value(exception.reviewedAt),
      createdAt: Value(exception.createdAt),
      updatedAt: Value(exception.updatedAt),
    );
  }

  /// Inserts a new collateral photo exception record into SQLite.
  Future<void> createException(CollateralPhotoException exception) async {
    await into(collateralPhotoExceptions).insert(_toCompanion(exception));
  }

  /// Retrieves an exception by [exceptionId] strictly scoped within [shopId].
  ///
  /// Returns `null` if the exception does not exist or belongs to another shop.
  Future<CollateralPhotoException?> getExceptionById(
    String shopId,
    String exceptionId,
  ) async {
    final query = select(collateralPhotoExceptions)
      ..where((e) =>
          e.shopId.equals(shopId) & e.id.equals(exceptionId));
    final entry = await query.getSingleOrNull();
    return entry != null ? _toDomain(entry) : null;
  }

  /// Retrieves all pending photo exception requests for [shopId], ordered by
  /// creation time.
  Future<List<CollateralPhotoException>> getPendingExceptions(
    String shopId,
  ) async {
    final query = select(collateralPhotoExceptions)
      ..where((e) =>
          e.shopId.equals(shopId) &
          e.status
              .equals(CollateralPhotoExceptionStatus.pendingOwnerApproval.value))
      ..orderBy([(e) => OrderingTerm.asc(e.createdAt)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Retrieves all exception requests for a collateral item within [shopId].
  Future<List<CollateralPhotoException>> getExceptionsByCollateralItemId(
    String shopId,
    String collateralItemId,
  ) async {
    final query = select(collateralPhotoExceptions)
      ..where((e) =>
          e.shopId.equals(shopId) &
          e.collateralItemId.equals(collateralItemId))
      ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Updates an existing photo exception request (e.g. for approval or rejection).
  Future<void> updateException(CollateralPhotoException exception) async {
    final existing = await getExceptionById(exception.shopId, exception.id);
    if (existing == null) {
      throw StateError(
        'Cannot update collateral photo exception: ID "${exception.id}" not found in shop "${exception.shopId}".',
      );
    }

    final companion = CollateralPhotoExceptionsCompanion(
      id: const Value.absent(),
      shopId: const Value.absent(),
      collateralItemId: const Value.absent(),
      requestedByUserId: const Value.absent(),
      requestReason: const Value.absent(),
      status: Value(exception.status.value),
      reviewedByUserId: Value(exception.reviewedByUserId),
      reviewNotes: Value(exception.reviewNotes),
      reviewedAt: Value(exception.reviewedAt),
      createdAt: const Value.absent(),
      updatedAt: Value(DateTime.now().toUtc()),
    );

    await (update(collateralPhotoExceptions)
          ..where((e) =>
              e.shopId.equals(exception.shopId) &
              e.id.equals(exception.id)))
        .write(companion);
  }

  /// Consumes an approved photo exception single-use during collateral registration (Story 3.2).
  ///
  /// Enforces:
  /// 1. Shop isolation: Exception must belong to [shopId].
  /// 2. Dual item binding: Must match [collateralItemId].
  /// 3. Valid approval status: Must be in [CollateralPhotoExceptionStatus.approved] state.
  /// 4. Single-use consumption: Atomically transitions status to [CollateralPhotoExceptionStatus.consumed].
  Future<void> consumeException(
    String shopId,
    String exceptionId, {
    required String collateralItemId,
  }) async {
    final existing = await getExceptionById(shopId, exceptionId);
    if (existing == null) {
      throw StateError(
        'Collateral photo exception ID "$exceptionId" does not exist in shop "$shopId".',
      );
    }

    if (existing.collateralItemId != collateralItemId) {
      throw StateError(
        'Collateral item binding violation: Photo exception "$exceptionId" is bound to '
        'collateral item "${existing.collateralItemId}", '
        'which does not match registration collateral item "$collateralItemId".',
      );
    }

    if (existing.status != CollateralPhotoExceptionStatus.approved) {
      throw StateError(
        'Cannot consume photo exception "$exceptionId": current status is "${existing.status.value}". '
        'Only approved exceptions can be consumed for collateral registration.',
      );
    }

    final now = DateTime.now().toUtc();
    final companion = CollateralPhotoExceptionsCompanion(
      status: Value(CollateralPhotoExceptionStatus.consumed.value),
      updatedAt: Value(now),
    );

    final rowsAffected = await (update(collateralPhotoExceptions)
          ..where((e) =>
              e.shopId.equals(shopId) &
              e.id.equals(exceptionId) &
              e.status.equals(CollateralPhotoExceptionStatus.approved.value)))
        .write(companion);

    if (rowsAffected == 0) {
      throw StateError(
        'Cannot consume photo exception "$exceptionId": it is no longer in approved state or has already been consumed.',
      );
    }
  }
}

