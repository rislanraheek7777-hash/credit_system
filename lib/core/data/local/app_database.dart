import 'package:drift/drift.dart';
import 'connection/database_connection.dart';
import 'tables/shops_table.dart';
import 'tables/app_users_table.dart';
import 'tables/sync_queue_table.dart';
import 'tables/customers_table.dart';
import 'tables/customer_photo_exceptions_table.dart';
import 'tables/loans_table.dart';
import '../../../../features/shop/data/daos/shop_dao.dart';
import '../../../../features/auth/data/daos/user_dao.dart';
import '../../../../features/customers/data/daos/customer_dao.dart';
import '../../../../features/customers/data/daos/customer_photo_exception_dao.dart';
import '../../../../features/customers/data/daos/loan_dao.dart';

part 'app_database.g.dart';

/// Local Drift SQLite database for counter persistence and offline operation queueing.
///
/// Binds: Architecture Decisions AD-1, AD-4, AD-6, AD-7; PRD FR-4, FR-5, FR-6, FR-9, FR-23.
///
/// Acts as the responsive, offline-capable local storage engine for retail counters.
/// Schema Version: 7 (Story 2.5: Customer Search, Loan Navigation & Multi-Loan Target Selection).
/// Tables:
/// - [Shops]: Tenant profile, operating timezone, currency preference, contact details, receipt notes.
/// - [AppUsers]: Counter staff, permissions catalog, and immediate session revocation (`session_version`).
/// - [Customers]: Reusable customer profiles with shop-scoped NIC uniqueness and phone indexing.
/// - [SyncQueue]: Asynchronous offline synchronization queue with UUIDv4 idempotency keys.
/// - [CustomerPhotoExceptions]: Formal KYC photo exception requests, decisions, and single-use tracking.
/// - [Loans]: Zero-interest loan agreements scoped to a shop tenant, linked to a customer borrower.
@DriftDatabase(
  tables: [Shops, AppUsers, SyncQueue, Customers, CustomerPhotoExceptions, Loans],
  daos: [ShopDao, UserDao, CustomerDao, CustomerPhotoExceptionDao, LoanDao],
)
class AppDatabase extends _$AppDatabase {
  /// Default constructor connecting via application sandboxed storage.
  AppDatabase() : super(AppDatabaseConnection.openConnection());

  /// Testing constructor allowing dependency injection of an isolated [QueryExecutor]
  /// (e.g. [AppDatabaseConnection.openInMemoryConnection]).
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        // Upgrade from Schema Version 1 to Version 2:
        // Add 7 nullable shop profile and branding fields
        await m.addColumn(shops, shops.businessAddress);
        await m.addColumn(shops, shops.contactPhone);
        await m.addColumn(shops, shops.contactEmail);
        await m.addColumn(shops, shops.registrationNumber);
        await m.addColumn(shops, shops.logoUri);
        await m.addColumn(shops, shops.receiptHeaderNotes);
        await m.addColumn(shops, shops.receiptFooterNotes);
      }
      if (from < 3) {
        // Upgrade from Schema Version 2 to Version 3:
        // Add permissions column to app_users
        await m.addColumn(appUsers, appUsers.permissions);
      }
      if (from < 4) {
        // Upgrade from Schema Version 3 to Version 4:
        // Create customers table and associated indexes
        await m.createTable(customers);
        await m.createIndex(idxCustomersShopId);
        await m.createIndex(idxCustomersShopNic);
      }
      if (from < 5) {
        // Upgrade from Schema Version 4 to Version 5 (Story 2.3):
        // Create customer_photo_exceptions table and associated indexes
        await m.createTable(customerPhotoExceptions);
        await m.createIndex(idxPhotoExceptionsShopStatus);
        await m.createIndex(idxPhotoExceptionsCustomer);
        await m.createIndex(idxPhotoExceptionsNic);
      }
      if (from < 6) {
        // Upgrade from Schema Version 5 to Version 6 (Story 2.4):
        // Create composite index on customers(shop_id, phone)
        await m.createIndex(idxCustomersShopPhone);
      }
      if (from < 7) {
        // Upgrade from Schema Version 6 to Version 7 (Story 2.5):
        // Create loans table and associated indexes
        await m.createTable(loans);
        await m.createIndex(idxLoansShopId);
        await m.createIndex(idxLoansShopCustomer);
        await m.createIndex(idxLoansShopStatus);
        await m.createIndex(idxLoansShopCustomerStatus);
      }
      if (from < 8) {
        // Upgrade from Schema Version 7 to Version 8 (Story 1.7):
        // Add password_hash column to app_users for secure authentication.
        final passwordHashColumn = appUsers.passwordHash as GeneratedColumn;
        await m.addColumn(appUsers, passwordHashColumn);
      }
    },
    beforeOpen: (OpeningDetails details) async {
      // Guarantee SQLite foreign-key enforcement is active on every connection
      await customStatement('PRAGMA foreign_keys = ON;');
    },
  );
}
