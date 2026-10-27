import 'package:drift/drift.dart';
import 'connection/database_connection.dart';
import 'tables/payments_table.dart';
import 'tables/loan_corrections_table.dart';
import 'tables/loan_ledger_entries_table.dart';
import 'tables/due_date_extensions_table.dart';
import 'tables/customer_follow_ups_table.dart';
import 'tables/loan_resolutions_table.dart';
import 'tables/loan_administrative_closures_table.dart';
import 'tables/shops_table.dart';
import 'tables/app_users_table.dart';
import 'tables/sync_queue_table.dart';
import 'tables/customers_table.dart';
import 'tables/customer_photo_exceptions_table.dart';
import 'tables/loans_table.dart';
import 'tables/collateral_items_table.dart';
import 'tables/collateral_photo_exceptions_table.dart';
import 'tables/collateral_custody_events_table.dart';
import '../../../features/shop/data/daos/shop_dao.dart';
import '../../../features/auth/data/daos/user_dao.dart';
import '../../../features/customers/data/daos/customer_dao.dart';
import '../../../features/customers/data/daos/customer_photo_exception_dao.dart';
import '../../../features/customers/data/daos/loan_dao.dart';
import '../../../features/customers/data/daos/payment_dao.dart';
import '../../../features/customers/data/daos/correction_dao.dart';
import '../../../features/customers/data/daos/overdue_dao.dart';
import '../../../features/collateral/data/daos/collateral_dao.dart';
import '../../../features/collateral/data/daos/collateral_custody_event_dao.dart';
import '../../../features/collateral/data/daos/collateral_discrepancy_dao.dart';
import '../../../features/collateral/data/daos/collateral_photo_exception_dao.dart';

part 'app_database.g.dart';

/// Local Drift SQLite database for counter persistence and offline operation queueing.
///
/// Binds: Architecture Decisions AD-1, AD-4, AD-6, AD-7; PRD FR-4, FR-5,
/// FR-6, FR-9, FR-23.
///
/// Acts as the responsive, offline-capable local storage engine for retail
/// counters.
///
/// Schema Version: 18 (Story 5: Payment & Receipt; Story 5.5 Corrections &
/// financial ledger entries).
/// Tables:
/// - [Shops]: Tenant profile, operating timezone, currency preference, contact
///   details, receipt notes.
/// - [AppUsers]: Counter staff, permissions catalog, and immediate session
///   revocation (`session_version`).
/// - [SyncQueue]: Asynchronous offline synchronization queue with UUIDv4
///   idempotency keys.
/// - [Customers]: Reusable customer profiles with shop-scoped NIC uniqueness
///   and phone indexing.
/// - [CustomerPhotoExceptions]: Formal KYC photo exception requests, decisions,
///   and single-use tracking.
/// - [Loans]: Zero-interest loan agreements scoped to a shop tenant, linked to
///   a customer borrower.
/// - [CollateralItems]: Pledged collateral items with custody state.
/// - [CollateralPhotoExceptions]: Collateral photo exception requests and
///   decisions.
/// - [CollateralCustodyEvents]: Immutable custody state transition history.
/// - [CollateralDiscrepancies]: Discrepancy reports and shop-owner resolutions.
/// - [LoanCorrections]: Controlled financial correction requests and Shop
///   Owner reversal approvals (Story 5.5).
/// - [LoanLedgerEntries]: Immutable financial ledger entries (compensating
///   debits and controlled adjustments) linked to a loan (Story 5.5, FR-22).
@DriftDatabase(
  tables: [
    Shops,
    AppUsers,
    SyncQueue,
    Customers,
    CustomerPhotoExceptions,
    Loans,
    CollateralItems,
    CollateralPhotoExceptions,
    CollateralCustodyEvents,
    CollateralDiscrepancies,
    Payments,
    LoanCorrections,
    LoanLedgerEntries,
    DueDateExtensions,
    CustomerFollowUps,
    LoanResolutions,
    LoanAdministrativeClosures,
  ],
  daos: [
    ShopDao,
    UserDao,
    CustomerDao,
    CustomerPhotoExceptionDao,
    LoanDao,
    PaymentDao,
    CorrectionDao,
    OverdueDao,
    CollateralDao,
    CollateralCustodyEventDao,
    CollateralDiscrepancyDao,
    CollateralPhotoExceptionDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Default constructor connecting via application sandboxed storage.
  AppDatabase() : super(AppDatabaseConnection.openConnection());

  /// Testing constructor allowing dependency injection of an isolated
  /// [QueryExecutor] (e.g. [AppDatabaseConnection.openInMemoryConnection]).
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 20;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            // Upgrade from Schema Version 1 to Version 2:
            // Add 7 nullable shop profile and branding fields.
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
            // Add permissions column to app_users.
            await m.addColumn(appUsers, appUsers.permissions);
          }
          if (from < 4) {
            // Upgrade from Schema Version 3 to Version 4:
            // Create customers table and associated indexes.
            await m.createTable(customers);
            await m.createIndex(idxCustomersShopId);
            await m.createIndex(idxCustomersShopNic);
          }
          if (from < 5) {
            // Upgrade from Schema Version 4 to Version 5 (Story 2.3):
            // Create customer_photo_exceptions table and associated indexes.
            await m.createTable(customerPhotoExceptions);
            await m.createIndex(idxPhotoExceptionsShopStatus);
            await m.createIndex(idxPhotoExceptionsCustomer);
            await m.createIndex(idxPhotoExceptionsNic);
          }
          if (from < 6) {
            // Upgrade from Schema Version 5 to Version 6 (Story 2.4):
            // Create composite index on customers(shop_id, phone).
            await m.createIndex(idxCustomersShopPhone);
          }
          if (from < 7) {
            // Upgrade from Schema Version 6 to Version 7 (Story 2.5):
            // Create the *historical* loans table as it shipped in Story 2.5.
            //
            // The table must not be created from the current (v15) definition
            // here: later migration steps rebuild it with `alterTable`, which
            // copies only the columns that exist at that point in history. A
            // modern table created here would make those copies ambiguous.
            await customStatement('''
              CREATE TABLE IF NOT EXISTS "loans" (
                "id" TEXT NOT NULL,
                "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
                "customer_id" TEXT NOT NULL REFERENCES "customers" ("id") ON DELETE RESTRICT,
                "principal_cents" INTEGER NOT NULL,
                "balance_cents" INTEGER NOT NULL,
                "status" TEXT NOT NULL DEFAULT 'active',
                "due_date" INTEGER NOT NULL,
                "created_at" INTEGER NOT NULL,
                "settled_at" INTEGER,
                PRIMARY KEY ("id")
              );
            ''');
            await _createLoanIndexes();
          }
          if (from < 8) {
            // Upgrade from Schema Version 7 to Version 8 (Story 1.7):
            // Add password_hash column to app_users for secure authentication.
            await m.addColumn(appUsers, appUsers.passwordHash);
          }
          if (from < 9) {
            // Upgrade from Schema Version 8 to Version 9 (Story 3.1):
            // Create the *historical* collateral_items table, including the
            // three-state custody vocabulary that shipped before Story 3.4.
            await customStatement('''
              CREATE TABLE IF NOT EXISTS "collateral_items" (
                "id" TEXT NOT NULL,
                "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
                "customer_id" TEXT NOT NULL REFERENCES "customers" ("id") ON DELETE RESTRICT,
                "loan_id" TEXT REFERENCES "loans" ("id") ON DELETE RESTRICT,
                "item_reference_id" TEXT NOT NULL,
                "category" TEXT NOT NULL,
                "description" TEXT NOT NULL,
                "condition_grade" TEXT NOT NULL,
                "weight_milligrams" INTEGER NOT NULL,
                "estimated_value_cents" INTEGER NOT NULL,
                "photo_uri" TEXT,
                "photo_hash" TEXT,
                "custody_status" TEXT NOT NULL DEFAULT 'in_custody',
                "created_at" INTEGER NOT NULL,
                "updated_at" INTEGER NOT NULL,
                UNIQUE ("shop_id", "item_reference_id"),
                PRIMARY KEY ("id"),
                CHECK (weight_milligrams > 0),
                CHECK (estimated_value_cents >= 0),
                CHECK (category IN ('gold', 'electronics', 'valuables')),
                CHECK (custody_status IN ('in_custody', 'returned', 'exception_held'))
              );
            ''');
            await _createCollateralIndexes();
          }
          if (from < 10) {
            // Upgrade from Schema Version 9 to Version 10 (Story 3.2):
            // Create collateral photo exception requests.
            await m.createTable(collateralPhotoExceptions);
            await m.createIndex(idxCollateralPhotoExceptionsShopStatus);
            await m.createIndex(idxCollateralPhotoExceptionsItem);
          }
          if (from < 11) {
            // Upgrade from Schema Version 10 to Version 11 (Story 3.4):
            // Rebuild collateral_items with the six-state custody vocabulary and
            // create the custody-event and discrepancy tables.
            await customStatement('DROP TABLE IF EXISTS "_collateral_items_v11";');
            await customStatement('DROP TABLE IF EXISTS "tmp_for_copy_collateral_items";');
            await m.alterTable(TableMigration(collateralItems));
            await _createCollateralIndexes();
            // A version 10 database created before this migration shipped may
            // be missing the photo-exception indexes; recreate idempotently.
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_collateral_photo_exceptions_shop_status" '
              'ON "collateral_photo_exceptions" ("shop_id", "status");',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_collateral_photo_exceptions_item" '
              'ON "collateral_photo_exceptions" ("shop_id", "collateral_item_id");',
            );
            await m.createTable(collateralCustodyEvents);
            await m.createTable(collateralDiscrepancies);
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_custody_events_shop_id" '
              'ON "collateral_custody_events" ("shop_id");',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_custody_events_item_id" '
              'ON "collateral_custody_events" ("shop_id", "collateral_item_id");',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_custody_events_created_at" '
              'ON "collateral_custody_events" ("shop_id", "created_at");',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_collateral_discrepancies_shop_id" '
              'ON "collateral_discrepancies" ("shop_id");',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_collateral_discrepancies_item_id" '
              'ON "collateral_discrepancies" ("shop_id", "collateral_item_id");',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_collateral_discrepancies_status" '
              'ON "collateral_discrepancies" ("shop_id", "status");',
            );
          }
          if (from < 12) {
            // Upgrade from Schema Version 11 to Version 12 (Story 4.1):
            // Add the disbursement workflow status. Agreements created before
            // the workflow existed are treated as already disbursed.
            final loanColumns =
                await customSelect('PRAGMA table_info("loans")').get();
            final hasWorkflowStatus = loanColumns
                .any((row) => row.read<String>('name') == 'workflow_status');
            if (!hasWorkflowStatus) {
              await m.addColumn(loans, loans.workflowStatus);
            }
            await customStatement(
              "UPDATE loans SET workflow_status = 'disbursed' "
              "WHERE workflow_status IS NULL OR workflow_status = '' "
              "OR workflow_status = 'pending_disbursement';",
            );
          }
          if (from < 13) {
            // Upgrade from Schema Version 12 to Version 13 (Story 4.3):
            // Add the agreed term, custom due date, disbursement record and
            // cancellation record columns.
            await customStatement('DROP TABLE IF EXISTS "_loans_v13";');
            await customStatement('DROP TABLE IF EXISTS "tmp_for_copy_loans";');
            await m.alterTable(TableMigration(
              loans,
              newColumns: [
                loans.termPresetDays,
                loans.customDueDate,
                loans.disbursedAt,
                loans.disbursedByUserId,
                loans.cancelledAt,
                loans.cancellationReason,
                loans.documentSnapshotId,
                // Story 5.5: `correctionPending` is part of the current `loans`
                // definition. Listing it here lets Drift add it as a new column
                // during this rebuild (defaulting to `false`) instead of trying
                // to copy it from the old `loans` table, which predates it.
                loans.correctionPending,
              ],
            ));
            await _createLoanIndexes();
          }
          if (from < 14) {
            // Upgrade from Schema Version 13 to Version 14 (Story 4.3 Phase 2):
            // Rebuild the table so the Tier 1 cross-field CHECK constraints are
            // enforced at the persistence boundary. `alterTable` re-creates the
            // current shape, which also introduces `document_snapshot_id`.
            await customStatement('DROP TABLE IF EXISTS "_loans_v14";');
            await customStatement('DROP TABLE IF EXISTS "tmp_for_copy_loans";');
            await m.alterTable(TableMigration(
              loans,
              newColumns: [
                loans.documentSnapshotId,
                // Story 5.5: `correctionPending` is part of the current `loans`
                // definition. Listing it here lets a version 13 database that
                // predates the column migrate through this rebuild (it gets the
                // default `false`) instead of drift trying to `SELECT` it from
                // the old `loans` table, which predates it.
                loans.correctionPending,
              ],
            ));
            await _createLoanIndexes();
          }
          if (from < 15) {
            // Upgrade from Schema Version 14 to Version 15 (Story 4.4):
            // Add the immutable document snapshot identifier.
            //
            // Older upgrade paths already passed through `alterTable`, which
            // builds the current table shape and therefore already added the
            // column. Only add it when it is genuinely absent.
            final loanColumns =
                await customSelect('PRAGMA table_info("loans")').get();
            final hasDocumentSnapshotId = loanColumns.any(
              (row) => row.read<String>('name') == 'document_snapshot_id',
            );
            if (!hasDocumentSnapshotId) {
              await m.addColumn(loans, loans.documentSnapshotId);
            }
            await _createLoanIndexes();
          }
          if (from < 16) {
            // Upgrade from Schema Version 15 to Version 16 (Story 5):
            // Create the payments table for payment receipt snapshots.
            await m.createTable(payments);
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_payments_shop_id" '
              'ON "payments" ("shop_id");',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_payments_shop_loan" '
              'ON "payments" ("shop_id", "loan_id");',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_payments_receipt_number" '
              'ON "payments" ("shop_id", "receipt_number");',
            );
          }
          if (from < 17) {
            // Upgrade from Schema Version 16 to Version 17 (Story 5.5):
            // Add the correction-pending flag to loans and create the
            // loan_corrections table for controlled financial correction
            // requests and Shop Owner reversal approvals.
            //
            // `correctionPending` defaults to false, so existing loans keep
            // their current behaviour (payments allowed). The corrections
            // table is newly created; no existing data is touched.
            //
            // The column may already exist on databases that passed through
            // the version 13 rebuild (where it is listed in `newColumns`),
            // so guard the add with a PRAGMA check rather than assuming it is
            // absent.
            final loanColumns =
                await customSelect('PRAGMA table_info("loans")').get();
            final hasCorrectionPending = loanColumns.any(
              (row) => row.read<String>('name') == 'correction_pending',
            );
            if (!hasCorrectionPending) {
              await m.addColumn(loans, loans.correctionPending);
            }
            await m.createTable(loanCorrections);
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_loan_corrections_shop_id" '
              'ON "loan_corrections" ("shop_id");',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_loan_corrections_shop_status" '
              'ON "loan_corrections" ("shop_id", "status");',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_loan_corrections_shop_loan" '
              'ON "loan_corrections" ("shop_id", "loan_id");',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_loan_corrections_shop_payment" '
              'ON "loan_corrections" ("shop_id", "original_payment_id");',
            );
          }
          if (from < 18) {
            // Upgrade from Schema Version 17 to Version 18 (Story 5.5):
            // Create the loan_ledger_entries table for immutable financial
            // ledger entries (compensating debits and controlled adjustments)
            // linked to a loan. No existing data is touched.
            await m.createTable(loanLedgerEntries);
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_ledger_entries_shop_id" '
              'ON "loan_ledger_entries" ("shop_id");',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_ledger_entries_shop_loan" '
              'ON "loan_ledger_entries" ("shop_id", "loan_id");',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_ledger_entries_shop_entry_type" '
              'ON "loan_ledger_entries" ("shop_id", "entry_type");',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_ledger_entries_shop_correction" '
              'ON "loan_ledger_entries" ("shop_id", "correction_id");',
            );
          }
          if (from < 19) {
            // Upgrade from Schema Version 18 to Version 19 (Epic 6: Stories 6.2, 6.3, 6.4):
            // Create tables for due date extensions, customer follow-up notes, and owner resolutions.
            await m.createTable(dueDateExtensions);
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_due_date_extensions_shop_id" '
              'ON "due_date_extensions" ("shop_id");',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_due_date_extensions_shop_loan" '
              'ON "due_date_extensions" ("shop_id", "loan_id");',
            );

            await m.createTable(customerFollowUps);
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_customer_follow_ups_shop_id" '
              'ON "customer_follow_ups" ("shop_id");',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_customer_follow_ups_shop_loan" '
              'ON "customer_follow_ups" ("shop_id", "loan_id");',
            );

            await m.createTable(loanResolutions);
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_loan_resolutions_shop_id" '
              'ON "loan_resolutions" ("shop_id");',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_loan_resolutions_shop_loan" '
              'ON "loan_resolutions" ("shop_id", "loan_id");',
            );

            await m.createTable(loanAdministrativeClosures);
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_loan_admin_closures_shop_id" '
              'ON "loan_administrative_closures" ("shop_id");',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS "idx_loan_admin_closures_shop_loan" '
              'ON "loan_administrative_closures" ("shop_id", "loan_id");',
            );
          }
          if (from < 20) {
            // Upgrade from Schema Version 19 to 20: add email/phone login identifiers.
            //
            // Guarded by PRAGMA table_info: `addColumn`/`CREATE INDEX` fail
            // outright when `app_users` is absent (partially built or fixture
            // databases), and the column add fails with "duplicate column" when
            // an earlier upgrade path already added it.
            final appUsersInfo =
                await customSelect('PRAGMA table_info("app_users")').get();
            if (appUsersInfo.isNotEmpty) {
              bool hasColumn(String name) => appUsersInfo.any(
                  (row) => row.read<String>('name') == name);
              if (!hasColumn('email')) {
                await m.addColumn(appUsers, appUsers.email);
              }
              if (!hasColumn('phone')) {
                await m.addColumn(appUsers, appUsers.phone);
              }
              await customStatement(
                'CREATE INDEX IF NOT EXISTS "idx_app_users_shop_email" '
                'ON "app_users" ("shop_id", "email");',
              );
              await customStatement(
                'CREATE INDEX IF NOT EXISTS "idx_app_users_shop_phone" '
                'ON "app_users" ("shop_id", "phone");',
              );
            }

            // Customer-identity integer id retype.
            //
            // `Customers.id` changes from a UUID TEXT primary key to an
            // auto-increment INTEGER primary key, and every customer-identity
            // column that references it (`loans.customer_id`,
            // `collateral_items.customer_id`, `customer_follow_ups.customer_id`
            // and the denormalized `payments.customer_id` snapshot) is retyped
            // to INTEGER.
            //
            // Existing rows are preserved without data loss: each legacy
            // customer row keeps its implicit rowid as its new integer id, and
            // referencing columns are remapped from the legacy UUID through a
            // temporary mapping table.
            //
            // Databases that reached the current table shapes through earlier
            // `alterTable` rebuilds (or `createTable` calls on newer upgrade
            // paths) already carry INTEGER customer ids, so every step below
            // is guarded and only runs where legacy ids are genuinely present.
            // Besides the declared column type, the guards also look at the
            // stored values: an upgrade path that rebuilt a table with the
            // current (INTEGER) declaration may still have copied legacy TEXT
            // uuids into it, which SQLite keeps verbatim under INTEGER
            // affinity. A failure inside this block rolls the whole migration
            // back, leaving the database unchanged.
            final foreignKeysEnabled =
                (await customSelect('PRAGMA foreign_keys').getSingle())
                    .read<bool>('foreign_keys');
            final legacyAlterTableEnabled =
                (await customSelect('PRAGMA legacy_alter_table').getSingle())
                    .read<bool>('legacy_alter_table');
            if (foreignKeysEnabled) {
              await customStatement('PRAGMA foreign_keys = OFF;');
            }
            if (!legacyAlterTableEnabled) {
              await customStatement('PRAGMA legacy_alter_table = ON;');
            }

            try {
              await transaction(() async {
                if (await _columnHasTextType('customers', 'id')) {
                  // Rebuild `customers` with the INTEGER auto-increment primary
              // key, reusing each legacy row's rowid as its new integer id.
              //
              // The rebuild follows SQLite's 12-step safe rebuild procedure
              // (https://sqlite.org/lang_altertable.html#otheralter): foreign
              // keys are switched off while the parent table is renamed and
              // dropped (a device connection enforces them from the moment it
              // opens), and `legacy_alter_table` keeps the rename from
              // rewriting the child tables' `REFERENCES` clauses to point at
              // the temporary table name.
              await customStatement(
                'DROP TABLE IF EXISTS "customers_v19_ids";',
              );
              await customStatement(
                'ALTER TABLE "customers" RENAME TO "customers_v19_ids";',
              );
              await m.createTable(customers);
              await customStatement(
                'INSERT INTO "customers" '
                    '("id", "shop_id", "full_name", "nic", "phone", "address", '
                    '"photo_uri", "photo_hash", "created_at", "updated_at") '
                    'SELECT "rowid", "shop_id", "full_name", "nic", "phone", '
                    '"address", "photo_uri", "photo_hash", "created_at", '
                    '"updated_at" FROM "customers_v19_ids";',
              );
              // Legacy UUID -> new integer id mapping used below to remap the
              // referencing tables.
              await customStatement(
                'CREATE TEMP TABLE "_customer_id_remap" '
                    '("old_id" TEXT PRIMARY KEY, "new_id" INTEGER NOT NULL);',
              );
              await customStatement(
                'INSERT INTO "_customer_id_remap" ("old_id", "new_id") '
                    'SELECT "id", "rowid" FROM "customers_v19_ids";',
              );
              await customStatement('DROP TABLE "customers_v19_ids";');
              await _createCustomerIndexes();

            } else if (await _columnHasTextData('loans', 'customer_id') ||
                await _columnHasTextData('collateral_items', 'customer_id') ||
                await _columnHasTextData(
                    'customer_follow_ups', 'customer_id') ||
                await _columnHasTextData('payments', 'customer_id')) {
              // `customers` already carries INTEGER ids (an upgrade path that
              // created it from the current definition) while a referencing
              // table still holds legacy TEXT values copied by an earlier
              // `alterTable` rebuild. Map those through the live customer
              // rows; because the integer primary key is the rowid alias,
              // `id` and `rowid` agree.
              await customStatement(
                'CREATE TEMP TABLE IF NOT EXISTS "_customer_id_remap" '
                    '("old_id" TEXT PRIMARY KEY, "new_id" INTEGER NOT NULL);',
              );
              await customStatement(
                'INSERT OR REPLACE INTO "_customer_id_remap" '
                    '("old_id", "new_id") '
                    'SELECT CAST("id" AS TEXT), "rowid" FROM "customers";',
              );
            }

            if (await _columnHasTextType('loans', 'customer_id') ||
                await _columnHasTextData('loans', 'customer_id')) {
              await customStatement(
                'DROP TABLE IF EXISTS "tmp_for_copy_loans";',
              );
              await customStatement(
                'UPDATE "loans" SET "customer_id" = (SELECT "new_id" '
                    'FROM "_customer_id_remap" '
                    'WHERE "old_id" = "loans"."customer_id");',
              );
              if (await _columnHasTextType('loans', 'customer_id')) {
                await m.alterTable(TableMigration(loans));
                await _createLoanIndexes();
              }
            }

            if (await _columnHasTextType('collateral_items', 'customer_id') ||
                await _columnHasTextData('collateral_items', 'customer_id')) {
              await customStatement(
                'DROP TABLE IF EXISTS "tmp_for_copy_collateral_items";',
              );
              await customStatement(
                'UPDATE "collateral_items" SET "customer_id" = (SELECT "new_id" '
                    'FROM "_customer_id_remap" '
                    'WHERE "old_id" = "collateral_items"."customer_id");',
              );
              if (await _columnHasTextType('collateral_items', 'customer_id')) {
                await m.alterTable(TableMigration(collateralItems));
                await _createCollateralIndexes();
              }
            }

            if (await _columnHasTextType('customer_follow_ups', 'customer_id') ||
                await _columnHasTextData('customer_follow_ups', 'customer_id')) {
              await customStatement(
                'DROP TABLE IF EXISTS "tmp_for_copy_customer_follow_ups";',
              );
              await customStatement(
                'UPDATE "customer_follow_ups" SET "customer_id" = '
                    '(SELECT "new_id" FROM "_customer_id_remap" '
                    'WHERE "old_id" = "customer_follow_ups"."customer_id");',
              );
              if (await _columnHasTextType(
                  'customer_follow_ups', 'customer_id')) {
                await m.alterTable(TableMigration(customerFollowUps));
                await customStatement(
                  'CREATE INDEX IF NOT EXISTS "idx_customer_follow_ups_shop_id" '
                      'ON "customer_follow_ups" ("shop_id");',
                );
                await customStatement(
                  'CREATE INDEX IF NOT EXISTS "idx_customer_follow_ups_shop_loan" '
                      'ON "customer_follow_ups" ("shop_id", "loan_id");',
                );
              }
            }

            if (await _columnHasTextType('payments', 'customer_id') ||
                await _columnHasTextData('payments', 'customer_id')) {
              await customStatement(
                'DROP TABLE IF EXISTS "tmp_for_copy_payments";',
              );
              await customStatement(
                'UPDATE "payments" SET "customer_id" = (SELECT "new_id" '
                    'FROM "_customer_id_remap" '
                    'WHERE "old_id" = "payments"."customer_id");',
              );
              if (await _columnHasTextType('payments', 'customer_id')) {
                await m.alterTable(TableMigration(payments));
                await customStatement(
                  'CREATE INDEX IF NOT EXISTS "idx_payments_shop_id" '
                      'ON "payments" ("shop_id");',
                );
                await customStatement(
                  'CREATE INDEX IF NOT EXISTS "idx_payments_shop_loan" '
                      'ON "payments" ("shop_id", "loan_id");',
                );
                await customStatement(
                  'CREATE INDEX IF NOT EXISTS "idx_payments_receipt_number" '
                      'ON "payments" ("shop_id", "receipt_number");',
                );
              }
            }

            await customStatement(
              'DROP TABLE IF EXISTS "_customer_id_remap";',
            );
          });
        } finally {
          if (!legacyAlterTableEnabled) {
            await customStatement('PRAGMA legacy_alter_table = OFF;');
          }
          if (foreignKeysEnabled) {
            await customStatement('PRAGMA foreign_keys = ON;');
          }
        }
      }
    },
    beforeOpen: (OpeningDetails details) async {
          // Guarantee SQLite foreign-key enforcement is active on every
          // connection.
          await customStatement('PRAGMA foreign_keys = ON;');
        },
      );

  /// Recreates the `loans` indexes idempotently.
  ///
  /// Table rebuilds replay the indexes captured from the old schema, so the
  /// same index may already exist. `Migrator.createIndex` is not idempotent,
  /// hence the raw `IF NOT EXISTS` statements.
  Future<void> _createLoanIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS "idx_loans_shop_id" '
      'ON "loans" ("shop_id");',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS "idx_loans_shop_customer" '
      'ON "loans" ("shop_id", "customer_id");',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS "idx_loans_shop_status" '
      'ON "loans" ("shop_id", "status");',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS "idx_loans_shop_customer_status" '
      'ON "loans" ("shop_id", "customer_id", "status");',
    );
  }

  /// Recreates the `customers` indexes idempotently.
  ///
  /// The v20 customer-id retype drops and rebuilds the `customers` table, so
  /// its indexes must be recreated. `IF NOT EXISTS` keeps the step safe for
  /// upgrade paths that created the table with the current definition.
  Future<void> _createCustomerIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS "idx_customers_shop_id" '
      'ON "customers" ("shop_id");',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS "idx_customers_shop_nic" '
      'ON "customers" ("shop_id", "nic");',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS "idx_customers_shop_phone" '
      'ON "customers" ("shop_id", "phone");',
    );
  }

  /// Whether [column] of [table] currently has a TEXT-affinity type in the
  /// live schema (read via PRAGMA).
  ///
  /// Used by the v20 customer-id retype to skip tables that already carry
  /// INTEGER customer ids because they were created from the current table
  /// definitions on an earlier upgrade path.
  Future<bool> _columnHasTextType(String table, String column) async {
    final info = await customSelect('PRAGMA table_info("$table")').get();
    return info.any(
      (row) =>
          row.read<String>('name') == column &&
          row.read<String>('type').toUpperCase().contains('TEXT'),
    );
  }

  /// Whether [table].[column] currently stores at least one TEXT-affinity
  /// *value*.
  ///
  /// An `alterTable` rebuild on an earlier upgrade path re-creates the table
  /// with the current (INTEGER) declaration but copies legacy TEXT customer
  /// uuids verbatim, which SQLite keeps under INTEGER affinity. The v20
  /// customer-id retype uses this to remap those values even when the column
  /// declaration already looks correct.
  Future<bool> _columnHasTextData(String table, String column) async {
    // Older upgrade paths predate some of these tables (and columns) entirely;
    // probing a missing table/column with typeof() would throw "no such
    // table/column" and abort the migration. PRAGMA table_info returns no rows
    // for a missing table and never errors, so it doubles as the existence
    // check for both.
    final info = await customSelect('PRAGMA table_info("$table")').get();
    final hasColumn = info.any((row) => row.read<String>('name') == column);
    if (!hasColumn) return false;
    final rows = await customSelect(
      'SELECT 1 FROM "$table" WHERE typeof("$column") = \'text\' LIMIT 1;',
    ).get();
    return rows.isNotEmpty;
  }

  /// Recreates the `collateral_items` indexes idempotently.
  Future<void> _createCollateralIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS "idx_collateral_shop_id" '
      'ON "collateral_items" ("shop_id");',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS "idx_collateral_shop_customer" '
      'ON "collateral_items" ("shop_id", "customer_id");',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS "idx_collateral_shop_loan" '
      'ON "collateral_items" ("shop_id", "loan_id");',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS "idx_collateral_shop_custody" '
      'ON "collateral_items" ("shop_id", "custody_status");',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS "idx_collateral_shop_category" '
      'ON "collateral_items" ("shop_id", "category");',
    );
  }
}
