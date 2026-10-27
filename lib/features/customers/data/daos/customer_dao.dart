import 'package:drift/drift.dart';
import '../../../../core/data/local/app_database.dart';
import '../../../../core/data/local/tables/customers_table.dart';
import '../../domain/models/customer.dart';

part 'customer_dao.g.dart';

/// Data Access Object for Customer borrower identity records (Story 2.1).
@DriftAccessor(tables: [Customers])
class CustomerDao extends DatabaseAccessor<AppDatabase> with _$CustomerDaoMixin {
  CustomerDao(super.db);

  /// Converts a Drift [CustomerEntry] row into a domain [Customer].
  Customer _toDomain(CustomerEntry entry) {
    return Customer(
      id: entry.id,
      shopId: entry.shopId,
      fullName: entry.fullName,
      nic: entry.nic,
      phone: entry.phone,
      address: entry.address,
      photoUri: entry.photoUri,
      photoHash: entry.photoHash,
      createdAt: entry.createdAt.toUtc(),
      updatedAt: entry.updatedAt.toUtc(),
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
      nic: Value(Customer.normalizeNic(customer.nic)),
      phone: Value(customer.phone),
      address: Value(customer.address),
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
  Future<List<Customer>> getCustomersByShopId(String shopId) async {
    final query = select(customers)..where((c) => c.shopId.equals(shopId));
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Searches for customers within [shopId] matching a search [query] across name, NIC, or phone.
  Future<List<Customer>> searchCustomers(String shopId, String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return getCustomersByShopId(shopId);
    }

    final normalizedQuery = Customer.normalizeNic(trimmed);
    final dbQuery = select(customers)
      ..where((c) =>
          c.shopId.equals(shopId) &
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
      nic: Value(Customer.normalizeNic(customer.nic)),
      phone: Value(customer.phone),
      address: Value(customer.address),
      photoUri: Value(customer.photoUri),
      photoHash: Value(customer.photoHash),
      createdAt: const Value.absent(),
      updatedAt: Value(DateTime.now().toUtc()),
    );

    await (update(customers)
          ..where((c) => c.shopId.equals(customer.shopId) & c.id.equals(customer.id)))
        .write(companion);
  }
}
