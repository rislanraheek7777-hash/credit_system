import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/data/local/app_database.dart';
import '../../../../core/data/local/tables/customers_table.dart';
import '../../../../core/permissions/authorization_guard.dart';
import '../../../../features/auth/domain/models/app_user.dart';
import '../../domain/models/customer.dart';

part 'customer_dao.g.dart';

/// Data Access Object for Customer borrower identity records (Story 2.1).
@DriftAccessor(tables: [Customers])
class CustomerDao extends DatabaseAccessor<AppDatabase> with _$CustomerDaoMixin {
  CustomerDao(super.db);

  /// `entity_type` used by the local audit/sync queue for customer events.
  static const String customerEntityType = 'customer';

  /// `action_type` used when a customer is soft-deleted.
  static const String softDeleteCustomerActionType = 'customer_soft_deleted';

  /// Audit event name for a customer soft delete (PRD FR-31, category 1:
  /// Customer creation and profile edits).
  static const String customerSoftDeleteAuditEvent = 'customer_soft_deleted';

  /// PRD FR-31 audit category for customer creation/profile edits.
  static const int customerProfileAuditCategory = 1;

  /// Converts a Drift [CustomerEntry] row into a domain [Customer].
  Customer _toDomain(CustomerEntry entry) {
    return Customer(
      id: entry.id,
      shopId: entry.shopId,
      fullName: entry.fullName,
      nic: entry.nic ?? '',
      phone: entry.phone,
      address: entry.address ?? '',
      photoUri: entry.photoUri,
      photoHash: entry.photoHash,
      createdAt: entry.createdAt.toUtc(),
      updatedAt: entry.updatedAt.toUtc(),
      deletedAt: entry.deletedAt?.toUtc(),
    );
  }

  /// Converts a domain [Customer] into a Drift [CustomersCompanion].
  ///
  /// The [id] field is intentionally absent so the database auto-generates the
  /// auto-increment value on insert. On update, the ID is also absent to
  /// preserve the existing record's primary key.
  CustomersCompanion _toCompanion(Customer customer) {
    return CustomersCompanion(
      id: const Value.absent(),
      shopId: Value(customer.shopId),
      fullName: Value(customer.fullName),
      nic: Value(customer.nic.trim().isEmpty
          ? null
          : Customer.normalizeNic(customer.nic)),
      phone: Value(customer.phone),
      address: Value(customer.address.trim().isEmpty ? null : customer.address),
      photoUri: Value(customer.photoUri),
      photoHash: Value(customer.photoHash),
      createdAt: Value(customer.createdAt),
      updatedAt: Value(customer.updatedAt),
    );
  }

  /// Inserts a new customer record into the local SQLite database.
  ///
  /// The database assigns the auto-increment primary key; the generated
  /// [Customer.id] is returned so callers can reference the persisted row.
  ///
  /// Throws [sqlite.SqliteException] if a customer with the same NIC already exists
  /// in the same shop tenant (enforcing the `(shop_id, nic)` unique constraint).
  Future<int> createCustomer(Customer customer) async {
    return into(customers).insert(_toCompanion(customer));
  }

  /// Retrieves a customer by their [customerId] strictly scoped within [shopId].
  ///
  /// Returns `null` if the customer does not exist or belongs to another shop.
  Future<Customer?> getCustomerById(String shopId, int customerId) async {
    final query = select(customers)
      ..where((c) => c.shopId.equals(shopId) & c.id.equals(customerId));
    final entry = await query.getSingleOrNull();
    return entry != null ? _toDomain(entry) : null;
  }

  /// Retrieves a customer by their [nic] number strictly scoped within [shopId].
  ///
  /// Normalizes the search [nic] prior to comparison.
  Future<Customer?> getCustomerByNic(String shopId, String nic) async {
    if (nic.trim().isEmpty) return null;
    final normalized = Customer.normalizeNic(nic);
    final query = select(customers)
      ..where((c) => c.shopId.equals(shopId) & c.nic.equals(normalized));
    final entry = await query.getSingleOrNull();
    return entry != null ? _toDomain(entry) : null;
  }

  /// Finds all customers in [shopId] whose phone number matches [phone]
  /// after normalization.
  ///
  /// Used for shared-phone duplicate detection. A shared phone never
  /// automatically means the same person; callers must confirm explicitly.
  /// Both the stored phone and the search phone are normalized before
  /// comparison so that `0771234567` and `+94771234567` match.
  ///
  /// Strictly scoped to [shopId] — customers in other shops are never returned.
  Future<List<Customer>> findCustomersByPhone(String shopId, String phone) async {
    final normalized = Customer.normalizePhone(phone);
    final customers = await getCustomersByShopId(shopId);
    return customers
        .where((c) => Customer.normalizePhone(c.phone) == normalized)
        .toList();
  }

  /// Retrieves all customer profiles belonging strictly to [shopId].
  ///
  /// Soft-deleted customers (`deleted_at` set) are excluded.
  Future<List<Customer>> getCustomersByShopId(String shopId) async {
    final query = select(customers)
      ..where((c) => c.shopId.equals(shopId) & c.deletedAt.isNull());
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Searches for customers within [shopId] matching a search [query] across name, NIC, or phone.
  ///
  /// Soft-deleted customers (`deleted_at` set) are excluded.
  Future<List<Customer>> searchCustomers(String shopId, String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return getCustomersByShopId(shopId);
    }

    final normalizedQuery = Customer.normalizeNic(trimmed);
    final dbQuery = select(customers)
      ..where((c) =>
          c.shopId.equals(shopId) &
          c.deletedAt.isNull() &
          (c.fullName.like('%$trimmed%') |
              c.nic.like('%$normalizedQuery%') |
              c.phone.like('%$trimmed%')));

    final entries = await dbQuery.get();
    return entries.map(_toDomain).toList();
  }

  /// Updates an existing customer profile strictly scoped within [shopId].
  ///
  /// Enforces shop boundary isolation: throws [StateError] if the customer does
  /// not exist within the specified [shopId].
  ///
  /// Excludes immutable identity columns ([id], [shopId], [createdAt]) from the
  /// SQL SET clause to guarantee identity integrity.
  Future<void> updateCustomer(Customer customer) async {
    final existing = await getCustomerById(customer.shopId, customer.id);
    if (existing == null) {
      throw StateError(
        'Cannot update customer: ID "${customer.id}" not found in shop "${customer.shopId}".',
      );
    }

    final companion = CustomersCompanion(
      id: const Value.absent(),
      shopId: const Value.absent(),
      fullName: Value(customer.fullName),
      nic: Value(customer.nic.trim().isEmpty
          ? null
          : Customer.normalizeNic(customer.nic)),
      phone: Value(customer.phone),
      address: Value(customer.address.trim().isEmpty ? null : customer.address),
      photoUri: Value(customer.photoUri),
      photoHash: Value(customer.photoHash),
      createdAt: const Value.absent(),
      updatedAt: Value(DateTime.now().toUtc()),
    );

    await (update(customers)
          ..where((c) => c.shopId.equals(customer.shopId) & c.id.equals(customer.id)))
        .write(companion);
  }

  /// Soft-deletes the customer [customerId] in [shopId].
  ///
  /// Sets `deleted_at` to the current UTC instant. The row is retained for
  /// audit integrity and hidden from all lists, search and pickers; the
  /// profile is unreachable in-app. No credits, collateral, photos, or audit
  /// records are touched, and no hard `DELETE` is ever issued.
  ///
  /// Shop Owner–gated: the actor is re-checked here (server-of-truth style)
  /// with [AuthorizationGuard.checkOwnerAdministrativeAction] — the owner-
  /// administrative pattern — independent of any UI gating.
  ///
  /// Eligibility is re-checked here as well: any credit row for the customer,
  /// in any status (including pending-disbursement workflow agreements),
  /// blocks the deletion.
  ///
  /// Records a local audit/sync queue entry atomically with the update
  /// (category 1 — Customer creation and profile edits — `customer_soft_deleted`,
  /// `pending_server_ack`). Throws [PermissionDeniedException] for inactive or
  /// non-owner actors, and [StateError] when the customer does not exist, is
  /// already deleted, or has at least one credit row.
  Future<void> softDeleteCustomer({
    required AppUser actor,
    required String shopId,
    required int customerId,
  }) async {
    AuthorizationGuard.checkOwnerAdministrativeAction(
      isActive: actor.isActive,
      actorRole: actor.role,
      actionDescription: 'delete a customer',
    );
    if (actor.shopId != shopId) {
      throw PermissionDeniedException(
        'Access denied: Actor shop "${actor.shopId}" does not match shop "$shopId".',
      );
    }

    final now = DateTime.now().toUtc();
    await db.transaction(() async {
      // Re-read everything inside the transaction so a concurrent write
      // cannot race the soft delete.
      final row = await (select(customers)
            ..where(
                (c) => c.shopId.equals(shopId) & c.id.equals(customerId)))
          .getSingleOrNull();
      if (row == null) {
        throw StateError(
          'Cannot delete customer: ID "$customerId" not found in shop "$shopId".',
        );
      }
      if (row.deletedAt != null) {
        throw StateError(
          'Cannot delete customer: customer ID "$customerId" is already deleted.',
        );
      }

      final creditQuery = select(db.credits)
        ..where((credit) =>
            credit.shopId.equals(shopId) &
            credit.customerId.equals(customerId));
      creditQuery.limit(1);
      final creditRows = await creditQuery.get();
      if (creditRows.isNotEmpty) {
        throw StateError(
          'Cannot delete customer: customer ID "$customerId" has at least one '
          'credit agreement (any status). Customers with financial history '
          'must be retained.',
        );
      }

      final affected = await (update(customers)
            ..where((c) =>
                c.shopId.equals(shopId) &
                c.id.equals(customerId) &
                c.deletedAt.isNull()))
          .write(CustomersCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ));
      if (affected == 0) {
        throw StateError(
          'Cannot delete customer: customer ID "$customerId" changed '
          'concurrently. Please retry.',
        );
      }

      // Local audit/sync queue entry (PRD FR-31, category 1). `sync_queue`
      // entity ids are UUIDs server-side. A deterministic v5 UUID keyed to
      // the shop and customer keeps the queued audit row linkable to the
      // deleted customer without parsing the payload; the integer customer id
      // also travels in the payload.
      await into(db.syncQueue).insert(
        SyncQueueCompanion.insert(
          id: const Uuid().v4(),
          shopId: shopId,
          idempotencyKey: const Uuid().v4(),
          entityType: customerEntityType,
          entityId: const Uuid().v5(
            Namespace.url.value,
            'credit-system/customer/$shopId/$customerId',
          ),
          actionType: softDeleteCustomerActionType,
          payloadJson: jsonEncode({
            'auditCategory': customerProfileAuditCategory,
            'auditEvent': customerSoftDeleteAuditEvent,
            'targetEntityType': 'customer',
            'targetEntityId': customerId.toString(),
            'actorId': actor.id,
            'customerId': customerId,
            'shopId': shopId,
            'deletedAt': now.toIso8601String(),
          }),
          createdAt: now,
          updatedAt: Value(now),
        ),
      );
    });
  }
}
