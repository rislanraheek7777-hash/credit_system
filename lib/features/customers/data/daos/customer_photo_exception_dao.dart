import 'package:drift/drift.dart';
import '../../../../core/data/local/app_database.dart';
import '../../../../core/data/local/tables/customer_photo_exceptions_table.dart';
import '../../domain/models/customer.dart';
import '../../domain/models/customer_photo_exception.dart';

part 'customer_photo_exception_dao.g.dart';

/// Data Access Object for customer photo KYC exceptions (Story 2.3, FR-9, AD-6).
@DriftAccessor(tables: [CustomerPhotoExceptions])
class CustomerPhotoExceptionDao extends DatabaseAccessor<AppDatabase>
    with _$CustomerPhotoExceptionDaoMixin {
  CustomerPhotoExceptionDao(super.db);

  /// Converts a Drift [CustomerPhotoExceptionEntry] row into a domain [CustomerPhotoException].
  CustomerPhotoException _toDomain(CustomerPhotoExceptionEntry entry) {
    return CustomerPhotoException(
      id: entry.id,
      shopId: entry.shopId,
      targetCustomerId: entry.targetCustomerId,
      customerNic: entry.customerNic,
      requestedByUserId: entry.requestedByUserId,
      requestReason: entry.requestReason,
      status: PhotoExceptionStatus.fromString(entry.status),
      reviewedByUserId: entry.reviewedByUserId,
      reviewNotes: entry.reviewNotes,
      reviewedAt: entry.reviewedAt?.toUtc(),
      createdAt: entry.createdAt.toUtc(),
      updatedAt: entry.updatedAt.toUtc(),
    );
  }

  /// Converts a domain [CustomerPhotoException] into a Drift [CustomerPhotoExceptionsCompanion].
  CustomerPhotoExceptionsCompanion _toCompanion(CustomerPhotoException exception) {
    return CustomerPhotoExceptionsCompanion(
      id: Value(exception.id),
      shopId: Value(exception.shopId),
      targetCustomerId: Value(exception.targetCustomerId),
      customerNic: Value(Customer.normalizeNic(exception.customerNic)),
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

  /// Inserts a new customer photo exception record into SQLite.
  Future<void> createException(CustomerPhotoException exception) async {
    await into(customerPhotoExceptions).insert(_toCompanion(exception));
  }

  /// Retrieves an exception by [exceptionId] strictly scoped within [shopId].
  Future<CustomerPhotoException?> getExceptionById(String shopId, String exceptionId) async {
    final query = select(customerPhotoExceptions)
      ..where((e) => e.shopId.equals(shopId) & e.id.equals(exceptionId));
    final entry = await query.getSingleOrNull();
    return entry != null ? _toDomain(entry) : null;
  }

  /// Retrieves all pending photo exception requests for [shopId], ordered by creation time.
  Future<List<CustomerPhotoException>> getPendingExceptions(String shopId) async {
    final query = select(customerPhotoExceptions)
      ..where((e) =>
          e.shopId.equals(shopId) &
          e.status.equals(PhotoExceptionStatus.pendingOwnerApproval.value))
      ..orderBy([(e) => OrderingTerm.asc(e.createdAt)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Retrieves all exception requests for a target customer within [shopId].
  Future<List<CustomerPhotoException>> getExceptionsByCustomerId(
    String shopId,
    String targetCustomerId,
  ) async {
    final query = select(customerPhotoExceptions)
      ..where((e) =>
          e.shopId.equals(shopId) & e.targetCustomerId.equals(targetCustomerId))
      ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Retrieves all exception requests for an NIC within [shopId].
  Future<List<CustomerPhotoException>> getExceptionsByNic(
    String shopId,
    String nic,
  ) async {
    final normalized = Customer.normalizeNic(nic);
    final query = select(customerPhotoExceptions)
      ..where((e) => e.shopId.equals(shopId) & e.customerNic.equals(normalized))
      ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Updates an existing photo exception request (e.g. for approval or rejection).
  Future<void> updateException(CustomerPhotoException exception) async {
    final existing = await getExceptionById(exception.shopId, exception.id);
    if (existing == null) {
      throw StateError(
        'Cannot update photo exception: ID "${exception.id}" not found in shop "${exception.shopId}".',
      );
    }

    final companion = CustomerPhotoExceptionsCompanion(
      id: const Value.absent(),
      shopId: const Value.absent(),
      targetCustomerId: Value(exception.targetCustomerId),
      customerNic: Value(Customer.normalizeNic(exception.customerNic)),
      requestedByUserId: const Value.absent(),
      requestReason: const Value.absent(),
      status: Value(exception.status.value),
      reviewedByUserId: Value(exception.reviewedByUserId),
      reviewNotes: Value(exception.reviewNotes),
      reviewedAt: Value(exception.reviewedAt),
      createdAt: const Value.absent(),
      updatedAt: Value(DateTime.now().toUtc()),
    );

    await (update(customerPhotoExceptions)
          ..where((e) => e.shopId.equals(exception.shopId) & e.id.equals(exception.id)))
        .write(companion);
  }

  /// Consumes an approved photo exception single-use during customer registration (Story 2.3).
  ///
  /// Enforces:
  /// 1. Shop isolation: Exception must belong to [shopId].
  /// 2. Dual customer binding: Must match both [targetCustomerId] and normalized [customerNic].
  /// 3. Valid approval status: Must be in [PhotoExceptionStatus.approved] state.
  /// 4. Single-use consumption: Atomically transitions status to [PhotoExceptionStatus.consumed].
  Future<void> consumeException(
    String shopId,
    String exceptionId, {
    required String targetCustomerId,
    required String customerNic,
  }) async {
    final existing = await getExceptionById(shopId, exceptionId);
    if (existing == null) {
      throw CustomerValidationException(
        'Photo exception ID "$exceptionId" does not exist in shop "$shopId".',
      );
    }

    final normalizedNic = Customer.normalizeNic(customerNic);
    if (existing.targetCustomerId != targetCustomerId ||
        existing.customerNic != normalizedNic) {
      throw CustomerValidationException(
        'Dual customer binding violation: Photo exception "$exceptionId" is bound to '
        'customerId "${existing.targetCustomerId}" and NIC "${existing.customerNic}", '
        'which does not match registration customerId "$targetCustomerId" and NIC "$normalizedNic".',
      );
    }

    if (existing.status != PhotoExceptionStatus.approved) {
      throw CustomerValidationException(
        'Cannot consume photo exception "$exceptionId": current status is "${existing.status.value}". '
        'Only approved exceptions can be consumed for customer registration.',
      );
    }

    final now = DateTime.now().toUtc();
    final companion = CustomerPhotoExceptionsCompanion(
      status: Value(PhotoExceptionStatus.consumed.value),
      updatedAt: Value(now),
    );

    final rowsAffected = await (update(customerPhotoExceptions)
          ..where((e) =>
              e.shopId.equals(shopId) &
              e.id.equals(exceptionId) &
              e.status.equals(PhotoExceptionStatus.approved.value)))
        .write(companion);

    if (rowsAffected == 0) {
      throw CustomerValidationException(
        'Cannot consume photo exception "$exceptionId": it is no longer in approved state or has already been consumed.',
      );
    }
  }
}

