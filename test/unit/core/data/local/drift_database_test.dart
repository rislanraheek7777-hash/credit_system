import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);
  });

  tearDown(() async {
    await db.close();
  });

  group('AppDatabase - Local Drift Foundations & Schema v7 Tests', () {
    test('schema version is 20 and all tables exist', () {
      expect(db.schemaVersion, equals(27));
      expect(
        db.allTables.map((t) => t.actualTableName),
        containsAll([
          'shops',
          'app_users',
          'sync_queue',
          'customers',
          'customer_photo_exceptions',
          'credits',
          'credit_corrections',
          'credit_ledger_entries',
          'due_date_extensions',
          'customer_follow_ups',
          'credit_resolutions',
        ]),
      );
    });

    test('SHOPS (v2): supports all 7 nullable profile and receipt branding fields', () async {
      final now = DateTime.now().toUtc();
      final shop = ShopEntry(
        id: 'shop-uuid-v2',
        name: 'Colombo Prime Gold',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        businessAddress: '100 York Street, Colombo 01',
        contactPhone: '+94 11 200 3000',
        contactEmail: 'contact@colomboprime.lk',
        registrationNumber: 'BR-778899',
        logoUri: '/data/logos/colombo_prime.png',
        receiptHeaderNotes: 'Welcome to Colombo Prime Gold Credit',
        receiptFooterNotes: 'All collateral securely vaulted under 24/7 CCTV surveillance.',
        createdAt: now,
        updatedAt: now,
      );

      await db.into(db.shops).insert(shop);

      final retrieved = await (db.select(db.shops)..where((s) => s.id.equals('shop-uuid-v2'))).getSingle();
      expect(retrieved.businessAddress, equals('100 York Street, Colombo 01'));
      expect(retrieved.contactPhone, equals('+94 11 200 3000'));
      expect(retrieved.contactEmail, equals('contact@colomboprime.lk'));
      expect(retrieved.registrationNumber, equals('BR-778899'));
      expect(retrieved.logoUri, equals('/data/logos/colombo_prime.png'));
      expect(retrieved.receiptHeaderNotes, equals('Welcome to Colombo Prime Gold Credit'));
      expect(retrieved.receiptFooterNotes, contains('24/7 CCTV'));
    });

    test('APP_USERS (v3): supports nullable permissions column for custom roles', () async {
      final now = DateTime.now().toUtc();
      await db.into(db.shops).insert(
        ShopEntry(
          id: 'shop-v3-test',
          name: 'V3 Jewellers',
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final user = AppUserEntry(
        id: 'user-v3-custom',
        shopId: 'shop-v3-test',
        username: 'custom.staff',
        fullName: 'Custom Staff',
        role: 'custom',
        isActive: true,
        sessionVersion: 1,
        permissions: 'viewCustomers,createCredits,recordPayments',
        createdAt: now,
        updatedAt: now,
      );
      await db.into(db.appUsers).insert(user);

      final retrieved = await (db.select(db.appUsers)..where((u) => u.id.equals('user-v3-custom'))).getSingle();
      expect(retrieved.permissions, equals('viewCustomers,createCredits,recordPayments'));
    });

    test('CUSTOMERS (v4): inserts and queries customer profile in shop scope', () async {
      final now = DateTime.now().toUtc();
      await db.into(db.shops).insert(
        ShopEntry(
          id: 'shop-v4-cust',
          name: 'V4 Jewellers',
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final customer = CustomerEntry(
        id: 1,
        shopId: 'shop-v4-cust',
        fullName: 'Kamal Silva',
        nic: '851234567V',
        phone: '+94 77 123 4567',
        address: '12 Galle Road, Colombo 03',
        photoUri: '/photos/cust-v4-1.jpg',
        photoHash: 'hash-abc',
        createdAt: now,
        updatedAt: now,
      );
      await db.into(db.customers).insert(customer);

      final retrieved = await (db.select(db.customers)..where((c) => c.id.equals(1))).getSingle();
      expect(retrieved.id, equals(1));
      expect(retrieved.shopId, equals('shop-v4-cust'));
      expect(retrieved.fullName, equals('Kamal Silva'));
      expect(retrieved.nic, equals('851234567V'));
      expect(retrieved.phone, equals('+94 77 123 4567'));
      expect(retrieved.address, equals('12 Galle Road, Colombo 03'));
      expect(retrieved.photoUri, equals('/photos/cust-v4-1.jpg'));
      expect(retrieved.photoHash, equals('hash-abc'));
    });

    test('CUSTOMER_PHOTO_EXCEPTIONS (v5): inserts and queries photo exception in shop scope', () async {
      final now = DateTime.now().toUtc();
      await db.into(db.shops).insert(
        ShopEntry(
          id: 'shop-v5-exc',
          name: 'V5 Jewellers',
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await db.into(db.appUsers).insert(
        AppUserEntry(
          id: 'user-v5-staff',
          shopId: 'shop-v5-exc',
          username: 'v5.staff',
          fullName: 'Staff V5',
          role: 'cashier',
          isActive: true,
          sessionVersion: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final exception = CustomerPhotoExceptionEntry(
        id: 'exc-v5-1',
        shopId: 'shop-v5-exc',
        targetCustomerId: 'cust-target-1',
        customerNic: '851234567V',
        requestedByUserId: 'user-v5-staff',
        requestReason: 'Camera hardware malfunction; physical NIC card verified.',
        status: 'pending_owner_approval',
        createdAt: now,
        updatedAt: now,
      );

      await db.into(db.customerPhotoExceptions).insert(exception);

      final retrieved = await (db.select(db.customerPhotoExceptions)
            ..where((e) => e.id.equals('exc-v5-1')))
          .getSingle();
      expect(retrieved.id, equals('exc-v5-1'));
      expect(retrieved.shopId, equals('shop-v5-exc'));
      expect(retrieved.targetCustomerId, equals('cust-target-1'));
      expect(retrieved.customerNic, equals('851234567V'));
      expect(retrieved.requestedByUserId, equals('user-v5-staff'));
      expect(retrieved.requestReason, contains('Camera hardware malfunction'));
      expect(retrieved.status, equals('pending_owner_approval'));
      expect(retrieved.reviewedByUserId, isNull);
    });

    test('MIGRATION: verifies upgrade from schema version 1 to 8 preserves existing data and creates customers and photo exceptions with indexes', () async {
      // Step 1: Open raw sqlite3 in-memory database and construct the exact Version 1 schema
      final rawSqliteDb = sqlite.sqlite3.openInMemory();
      rawSqliteDb.execute('''
        CREATE TABLE "shops" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "name" TEXT NOT NULL,
          "currency_code" TEXT NOT NULL DEFAULT 'LKR',
          "timezone" TEXT NOT NULL DEFAULT 'Asia/Colombo',
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL
        );
        CREATE TABLE "app_users" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL,
          "username" TEXT NOT NULL,
          "full_name" TEXT NOT NULL,
          "role" TEXT NOT NULL,
          "is_active" INTEGER NOT NULL DEFAULT 1,
          "session_version" INTEGER NOT NULL DEFAULT 1,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL
        );
        CREATE TABLE "sync_queue" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL,
          "idempotency_key" TEXT NOT NULL UNIQUE,
          "entity_type" TEXT NOT NULL,
          "entity_id" TEXT NOT NULL,
          "action_type" TEXT NOT NULL,
          "payload_json" TEXT NOT NULL,
          "status" TEXT NOT NULL DEFAULT 'pending_server_ack',
          "retry_count" INTEGER NOT NULL DEFAULT 0,
          "last_error" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER
        );
        PRAGMA user_version = 1;
      ''');

      // Insert pre-existing shop, user, and sync_queue records into v1 schema
      final nowEpoch = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      rawSqliteDb.execute('''
        INSERT INTO "shops" ("id", "name", "currency_code", "timezone", "created_at", "updated_at")
        VALUES ('shop-v1-existing', 'Original Jewellers', 'LKR', 'Asia/Colombo', $nowEpoch, $nowEpoch);
      ''');
      rawSqliteDb.execute('''
        INSERT INTO "app_users" ("id", "shop_id", "username", "full_name", "role", "is_active", "session_version", "created_at", "updated_at")
        VALUES ('user-v1-existing', 'shop-v1-existing', 'v1.user', 'V1 User', 'counter_staff', 1, 1, $nowEpoch, $nowEpoch);
      ''');
      rawSqliteDb.execute('''
        INSERT INTO "sync_queue" ("id", "shop_id", "idempotency_key", "entity_type", "entity_id", "action_type", "payload_json", "status", "retry_count", "created_at")
        VALUES ('sync-v1-record', 'shop-v1-existing', 'idemp-v1-key', 'credit', 'credit-uuid-1', 'create_credit', '{"amount": 1000}', 'pending_server_ack', 0, $nowEpoch);
      ''');

      // Step 2: Open with Drift AppDatabase which targets schemaVersion = 5
      // This automatically triggers the onUpgrade(m, 1, 5) migration
      final executor = NativeDatabase.opened(rawSqliteDb);
      final upgradedDb = AppDatabase.forTesting(executor);

      // Verify the pre-existing shop survived and new columns are present and default to NULL
      final existingShop = await (upgradedDb.select(upgradedDb.shops)
            ..where((s) => s.id.equals('shop-v1-existing')))
          .getSingle();
      expect(existingShop.id, equals('shop-v1-existing'));
      expect(existingShop.name, equals('Original Jewellers'));
      expect(existingShop.currencyCode, equals('LKR'));
      expect(existingShop.timezone, equals('Asia/Colombo'));
      expect(existingShop.businessAddress, isNull);
      expect(existingShop.contactPhone, isNull);

      // Verify the pre-existing user survived and permissions column is present and defaults to NULL
      final existingUser = await (upgradedDb.select(upgradedDb.appUsers)
            ..where((u) => u.id.equals('user-v1-existing')))
          .getSingle();
      expect(existingUser.id, equals('user-v1-existing'));
      expect(existingUser.username, equals('v1.user'));
      expect(existingUser.passwordHash, isNull);
      expect(existingUser.permissions, isNull);

      // Verify pre-existing sync_queue record survived without modification
      final existingSync = await (upgradedDb.select(upgradedDb.syncQueue)
            ..where((s) => s.id.equals('sync-v1-record')))
          .getSingle();
      expect(existingSync.id, equals('sync-v1-record'));
      expect(existingSync.shopId, equals('shop-v1-existing'));
      expect(existingSync.idempotencyKey, equals('idemp-v1-key'));
      expect(existingSync.entityType, equals('credit'));
      expect(existingSync.payloadJson, equals('{"amount": 1000}'));
      expect(existingSync.status, equals('pending_server_ack'));

      // Verify SQLite customers indexes were created
      final customerIndexRows = await upgradedDb.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'customers';").get();
      final customerIndexNames = customerIndexRows.map((r) => r.read<String>('name')).toList();
      expect(customerIndexNames, containsAll(['idx_customers_shop_id', 'idx_customers_shop_nic', 'idx_customers_shop_phone']));

      // Verify SQLite customer_photo_exceptions indexes were created
      final photoIndexRows = await upgradedDb.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'customer_photo_exceptions';").get();
      final photoIndexNames = photoIndexRows.map((r) => r.read<String>('name')).toList();
      expect(photoIndexNames, containsAll(['idx_photo_exceptions_shop_status', 'idx_photo_exceptions_customer', 'idx_photo_exceptions_nic']));

      // Verify creating a customer in the newly created customers table works
      final now = DateTime.now().toUtc();
      await upgradedDb.into(upgradedDb.customers).insert(
        CustomerEntry(
          id: 1,
          shopId: 'shop-v1-existing',
          fullName: 'Migrated Customer',
          nic: '901234567V',
          phone: '+94 77 123 4567',
          address: '123 Main St, Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final createdCustomer = await (upgradedDb.select(upgradedDb.customers)
            ..where((c) => c.id.equals(1)))
          .getSingle();
      expect(createdCustomer.fullName, equals('Migrated Customer'));
      expect(createdCustomer.nic, equals('901234567V'));

      // Verify inserting into customer_photo_exceptions works
      await upgradedDb.into(upgradedDb.customerPhotoExceptions).insert(
        CustomerPhotoExceptionEntry(
          id: 'exc-v1-migrated',
          shopId: 'shop-v1-existing',
          targetCustomerId: 'cust-migrated-1',
          customerNic: '901234567V',
          requestedByUserId: 'user-v1-existing',
          requestReason: 'Camera hardware failure during v1->v5 migration test',
          status: 'pending_owner_approval',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final createdException = await (upgradedDb.select(upgradedDb.customerPhotoExceptions)
            ..where((e) => e.id.equals('exc-v1-migrated')))
          .getSingle();
      expect(createdException.id, equals('exc-v1-migrated'));
      expect(createdException.status, equals('pending_owner_approval'));

      await upgradedDb.close();
    });

    test('MIGRATION: verifies upgrade from schema version 2 to 8 preserves existing data and adds permissions, customers & photo exceptions with indexes', () async {
      final rawSqliteDb = sqlite.sqlite3.openInMemory();
      rawSqliteDb.execute('''
        CREATE TABLE "shops" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "name" TEXT NOT NULL,
          "currency_code" TEXT NOT NULL DEFAULT 'LKR',
          "timezone" TEXT NOT NULL DEFAULT 'Asia/Colombo',
          "business_address" TEXT,
          "contact_phone" TEXT,
          "contact_email" TEXT,
          "registration_number" TEXT,
          "logo_uri" TEXT,
          "receipt_header_notes" TEXT,
          "receipt_footer_notes" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL
        );
        CREATE TABLE "app_users" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL,
          "username" TEXT NOT NULL,
          "full_name" TEXT NOT NULL,
          "role" TEXT NOT NULL,
          "is_active" INTEGER NOT NULL DEFAULT 1,
          "session_version" INTEGER NOT NULL DEFAULT 1,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL
        );
        CREATE TABLE "sync_queue" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL,
          "idempotency_key" TEXT NOT NULL UNIQUE,
          "entity_type" TEXT NOT NULL,
          "entity_id" TEXT NOT NULL,
          "action_type" TEXT NOT NULL,
          "payload_json" TEXT NOT NULL,
          "status" TEXT NOT NULL DEFAULT 'pending_server_ack',
          "retry_count" INTEGER NOT NULL DEFAULT 0,
          "last_error" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER
        );
        PRAGMA user_version = 2;
      ''');

      final nowEpoch = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      rawSqliteDb.execute('''
        INSERT INTO "shops" ("id", "name", "currency_code", "timezone", "created_at", "updated_at")
        VALUES ('shop-v2', 'V2 Shop', 'LKR', 'Asia/Colombo', $nowEpoch, $nowEpoch);
      ''');
      rawSqliteDb.execute('''
        INSERT INTO "app_users" ("id", "shop_id", "username", "full_name", "role", "is_active", "session_version", "created_at", "updated_at")
        VALUES ('user-v2-existing', 'shop-v2', 'v2.manager', 'V2 Manager', 'manager', 1, 2, $nowEpoch, $nowEpoch);
      ''');
      rawSqliteDb.execute('''
        INSERT INTO "sync_queue" ("id", "shop_id", "idempotency_key", "entity_type", "entity_id", "action_type", "payload_json", "status", "retry_count", "created_at")
        VALUES ('sync-v2-record', 'shop-v2', 'idemp-v2-key', 'payment', 'pay-uuid-2', 'record_payment', '{"amount": 500}', 'confirmed_by_server', 0, $nowEpoch);
      ''');

      final executor = NativeDatabase.opened(rawSqliteDb);
      final upgradedDb = AppDatabase.forTesting(executor);

      final user = await (upgradedDb.select(upgradedDb.appUsers)
            ..where((u) => u.id.equals('user-v2-existing')))
          .getSingle();
      expect(user.id, equals('user-v2-existing'));
      expect(user.sessionVersion, equals(2));
      expect(user.permissions, isNull);
      expect(user.passwordHash, isNull);

      // Verify pre-existing sync_queue record survived without modification
      final existingSync = await (upgradedDb.select(upgradedDb.syncQueue)
            ..where((s) => s.id.equals('sync-v2-record')))
          .getSingle();
      expect(existingSync.id, equals('sync-v2-record'));
      expect(existingSync.shopId, equals('shop-v2'));
      expect(existingSync.idempotencyKey, equals('idemp-v2-key'));
      expect(existingSync.status, equals('confirmed_by_server'));

      // Verify SQLite customers indexes were created
      final customerIndexRows = await upgradedDb.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'customers';").get();
      final customerIndexNames = customerIndexRows.map((r) => r.read<String>('name')).toList();
      expect(customerIndexNames, containsAll(['idx_customers_shop_id', 'idx_customers_shop_nic', 'idx_customers_shop_phone']));

      // Verify SQLite customer_photo_exceptions indexes were created
      final photoIndexRows = await upgradedDb.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'customer_photo_exceptions';").get();
      final photoIndexNames = photoIndexRows.map((r) => r.read<String>('name')).toList();
      expect(photoIndexNames, containsAll(['idx_photo_exceptions_shop_status', 'idx_photo_exceptions_customer', 'idx_photo_exceptions_nic']));

      // Verify customers table exists and allows insertion
      final now = DateTime.now().toUtc();
      await upgradedDb.into(upgradedDb.customers).insert(
        CustomerEntry(
          id: 202,
          shopId: 'shop-v2',
          fullName: 'Customer Post Upgrade',
          nic: '199012345678',
          phone: '+94 77 123 4567',
          address: '123 Main St, Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final cust = await (upgradedDb.select(upgradedDb.customers)
            ..where((c) => c.id.equals(202)))
          .getSingle();
      expect(cust.nic, equals('199012345678'));

      // Verify inserting into customer_photo_exceptions works
      await upgradedDb.into(upgradedDb.customerPhotoExceptions).insert(
        CustomerPhotoExceptionEntry(
          id: 'exc-v2-migrated',
          shopId: 'shop-v2',
          targetCustomerId: 'cust-v2-upgraded',
          customerNic: '199012345678',
          requestedByUserId: 'user-v2-existing',
          requestReason: 'Physical constraint documented; v2->v5 migration test',
          status: 'pending_owner_approval',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final exc = await (upgradedDb.select(upgradedDb.customerPhotoExceptions)
            ..where((e) => e.id.equals('exc-v2-migrated')))
          .getSingle();
      expect(exc.id, equals('exc-v2-migrated'));

      await upgradedDb.close();
    });

    test('MIGRATION: verifies upgrade from schema version 3 to 8 preserves existing data and creates customers & photo exceptions with indexes', () async {
      final rawSqliteDb = sqlite.sqlite3.openInMemory();
      rawSqliteDb.execute('''
        CREATE TABLE "shops" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "name" TEXT NOT NULL,
          "currency_code" TEXT NOT NULL DEFAULT 'LKR',
          "timezone" TEXT NOT NULL DEFAULT 'Asia/Colombo',
          "business_address" TEXT,
          "contact_phone" TEXT,
          "contact_email" TEXT,
          "registration_number" TEXT,
          "logo_uri" TEXT,
          "receipt_header_notes" TEXT,
          "receipt_footer_notes" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL
        );
        CREATE TABLE "app_users" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL,
          "username" TEXT NOT NULL,
          "full_name" TEXT NOT NULL,
          "role" TEXT NOT NULL,
          "is_active" INTEGER NOT NULL DEFAULT 1,
          "session_version" INTEGER NOT NULL DEFAULT 1,
          "permissions" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL
        );
        CREATE TABLE "sync_queue" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL,
          "idempotency_key" TEXT NOT NULL UNIQUE,
          "entity_type" TEXT NOT NULL,
          "entity_id" TEXT NOT NULL,
          "action_type" TEXT NOT NULL,
          "payload_json" TEXT NOT NULL,
          "status" TEXT NOT NULL,
          "retry_count" INTEGER NOT NULL DEFAULT 0,
          "last_error" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER
        );
        PRAGMA user_version = 3;
      ''');

      final nowEpoch = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      rawSqliteDb.execute('''
        INSERT INTO "shops" ("id", "name", "currency_code", "timezone", "created_at", "updated_at")
        VALUES ('shop-v3-orig', 'V3 Original Shop', 'LKR', 'Asia/Colombo', $nowEpoch, $nowEpoch);
      ''');
      rawSqliteDb.execute('''
        INSERT INTO "app_users" ("id", "shop_id", "username", "full_name", "role", "is_active", "session_version", "permissions", "created_at", "updated_at")
        VALUES ('user-v3-orig', 'shop-v3-orig', 'v3.user', 'V3 Staff', 'custom', 1, 3, 'viewCustomers,createCredits', $nowEpoch, $nowEpoch);
      ''');
      rawSqliteDb.execute('''
        INSERT INTO "sync_queue" ("id", "shop_id", "idempotency_key", "entity_type", "entity_id", "action_type", "payload_json", "status", "retry_count", "created_at")
        VALUES ('sync-v3-record', 'shop-v3-orig', 'idemp-v3-key', 'customer', 'cust-uuid-3', 'create_customer', '{"name": "Prior Customer"}', 'pending_server_ack', 0, $nowEpoch);
      ''');

      final executor = NativeDatabase.opened(rawSqliteDb);
      final upgradedDb = AppDatabase.forTesting(executor);

      final user = await (upgradedDb.select(upgradedDb.appUsers)
            ..where((u) => u.id.equals('user-v3-orig')))
          .getSingle();
      expect(user.permissions, equals('viewCustomers,createCredits'));
      expect(user.passwordHash, isNull);

      // Verify pre-existing sync_queue record survived without modification
      final existingSync = await (upgradedDb.select(upgradedDb.syncQueue)
            ..where((s) => s.id.equals('sync-v3-record')))
          .getSingle();
      expect(existingSync.id, equals('sync-v3-record'));
      expect(existingSync.shopId, equals('shop-v3-orig'));
      expect(existingSync.idempotencyKey, equals('idemp-v3-key'));
      expect(existingSync.entityType, equals('customer'));
      expect(existingSync.status, equals('pending_server_ack'));

      // Verify SQLite customers indexes were created
      final customerIndexRows = await upgradedDb.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'customers';").get();
      final customerIndexNames = customerIndexRows.map((r) => r.read<String>('name')).toList();
      expect(customerIndexNames, containsAll(['idx_customers_shop_id', 'idx_customers_shop_nic', 'idx_customers_shop_phone']));

      // Verify SQLite customer_photo_exceptions indexes were created
      final photoIndexRows = await upgradedDb.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'customer_photo_exceptions';").get();
      final photoIndexNames = photoIndexRows.map((r) => r.read<String>('name')).toList();
      expect(photoIndexNames, containsAll(['idx_photo_exceptions_shop_status', 'idx_photo_exceptions_customer', 'idx_photo_exceptions_nic']));

      // Check customers table exists and supports insertion
      final now = DateTime.now().toUtc();
      await upgradedDb.into(upgradedDb.customers).insert(
        CustomerEntry(
          id: 301,
          shopId: 'shop-v3-orig',
          fullName: 'Customer V3 Upgrade',
          nic: '851234567V',
          phone: '+94 77 123 4567',
          address: '123 Main St, Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final cust = await (upgradedDb.select(upgradedDb.customers)
            ..where((c) => c.id.equals(301)))
          .getSingle();
      expect(cust.id, equals(301));
      expect(cust.nic, equals('851234567V'));

      // Verify inserting into customer_photo_exceptions works
      await upgradedDb.into(upgradedDb.customerPhotoExceptions).insert(
        CustomerPhotoExceptionEntry(
          id: 'exc-v3-migrated',
          shopId: 'shop-v3-orig',
          targetCustomerId: 'cust-v3-upgraded',
          customerNic: '851234567V',
          requestedByUserId: 'user-v3-orig',
          requestReason: 'Camera lens shattered; physical NIC verified; v3->v5 test',
          status: 'pending_owner_approval',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final exc = await (upgradedDb.select(upgradedDb.customerPhotoExceptions)
            ..where((e) => e.id.equals('exc-v3-migrated')))
          .getSingle();
      expect(exc.id, equals('exc-v3-migrated'));

      await upgradedDb.close();
    });

    test('MIGRATION: verifies upgrade from schema version 4 to 8 preserves existing data and creates photo exceptions with indexes', () async {
      final rawSqliteDb = sqlite.sqlite3.openInMemory();
      rawSqliteDb.execute('''
        CREATE TABLE "shops" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "name" TEXT NOT NULL,
          "currency_code" TEXT NOT NULL DEFAULT 'LKR',
          "timezone" TEXT NOT NULL DEFAULT 'Asia/Colombo',
          "business_address" TEXT,
          "contact_phone" TEXT,
          "contact_email" TEXT,
          "registration_number" TEXT,
          "logo_uri" TEXT,
          "receipt_header_notes" TEXT,
          "receipt_footer_notes" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL
        );
        CREATE TABLE "app_users" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL,
          "username" TEXT NOT NULL,
          "full_name" TEXT NOT NULL,
          "role" TEXT NOT NULL,
          "is_active" INTEGER NOT NULL DEFAULT 1,
          "session_version" INTEGER NOT NULL DEFAULT 1,
          "permissions" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL
        );
        CREATE TABLE "sync_queue" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL,
          "idempotency_key" TEXT NOT NULL UNIQUE,
          "entity_type" TEXT NOT NULL,
          "entity_id" TEXT NOT NULL,
          "action_type" TEXT NOT NULL,
          "payload_json" TEXT NOT NULL,
          "status" TEXT NOT NULL,
          "retry_count" INTEGER NOT NULL DEFAULT 0,
          "last_error" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER
        );
        CREATE TABLE "customers" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL,
          "full_name" TEXT NOT NULL,
          "nic" TEXT NOT NULL,
          "phone" TEXT NOT NULL,
          "address" TEXT NOT NULL,
          "photo_uri" TEXT,
          "photo_hash" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL
        );
        CREATE INDEX "idx_customers_shop_id" ON "customers" ("shop_id");
        CREATE UNIQUE INDEX "idx_customers_shop_nic" ON "customers" ("shop_id", "nic");
        PRAGMA user_version = 4;
      ''');

      final nowEpoch = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      rawSqliteDb.execute('''
        INSERT INTO "shops" ("id", "name", "currency_code", "timezone", "created_at", "updated_at")
        VALUES ('shop-v4-orig', 'V4 Original Shop', 'LKR', 'Asia/Colombo', $nowEpoch, $nowEpoch);
      ''');
      rawSqliteDb.execute('''
        INSERT INTO "app_users" ("id", "shop_id", "username", "full_name", "role", "is_active", "session_version", "created_at", "updated_at")
        VALUES ('user-v4-orig', 'shop-v4-orig', 'v4.cashier', 'V4 Cashier', 'cashier', 1, 1, $nowEpoch, $nowEpoch);
      ''');
      rawSqliteDb.execute('''
        INSERT INTO "customers" ("id", "shop_id", "full_name", "nic", "phone", "address", "photo_uri", "photo_hash", "created_at", "updated_at")
        VALUES ('cust-v4-existing', 'shop-v4-orig', 'V4 Existing Customer', '198512345678', '+94 77 999 8888', '45 Park Road', '/photos/cust.jpg', 'hash-v4', $nowEpoch, $nowEpoch);
      ''');

      final executor = NativeDatabase.opened(rawSqliteDb);
      final upgradedDb = AppDatabase.forTesting(executor);

      // Verify pre-existing customer survived without loss.
      // The legacy TEXT id is remapped to the rowid during the v20 migration,
      // so the single pre-existing customer becomes id 1.
      final existingCustomer = await (upgradedDb.select(upgradedDb.customers)
            ..where((c) => c.nic.equals('198512345678')))
          .getSingle();
      expect(existingCustomer.id, equals(1));
      expect(existingCustomer.fullName, equals('V4 Existing Customer'));
      expect(existingCustomer.nic, equals('198512345678'));
      expect(existingCustomer.photoUri, equals('/photos/cust.jpg'));

      // Verify pre-existing user survived with password_hash column available
      final existingUser = await (upgradedDb.select(upgradedDb.appUsers)
            ..where((u) => u.id.equals('user-v4-orig')))
          .getSingle();
      expect(existingUser.passwordHash, isNull);

      // Verify SQLite customer_photo_exceptions indexes were created
      final photoIndexRows = await upgradedDb.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'customer_photo_exceptions';").get();
      final photoIndexNames = photoIndexRows.map((r) => r.read<String>('name')).toList();
      expect(photoIndexNames, containsAll([
        'idx_photo_exceptions_shop_status',
        'idx_photo_exceptions_customer',
        'idx_photo_exceptions_nic',
      ]));

      // Verify inserting into customer_photo_exceptions works
      final now = DateTime.now().toUtc();
      await upgradedDb.into(upgradedDb.customerPhotoExceptions).insert(
        CustomerPhotoExceptionEntry(
          id: 'exc-v4-upgraded',
          shopId: 'shop-v4-orig',
          targetCustomerId: 'cust-target-v4',
          customerNic: '199212345678',
          requestedByUserId: 'user-v4-orig',
          requestReason: 'Hardware camera driver failure; physical NIC verified; v4->v5 test',
          status: 'pending_owner_approval',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final exc = await (upgradedDb.select(upgradedDb.customerPhotoExceptions)
            ..where((e) => e.id.equals('exc-v4-upgraded')))
          .getSingle();
      expect(exc.id, equals('exc-v4-upgraded'));
      expect(exc.status, equals('pending_owner_approval'));

      await upgradedDb.close();
    });

    test('MIGRATION: verifies upgrade from schema version 5 to 8 preserves existing data and adds the shared-phone index', () async {
      final rawSqliteDb = sqlite.sqlite3.openInMemory();
      rawSqliteDb.execute('''
        CREATE TABLE "shops" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "name" TEXT NOT NULL,
          "currency_code" TEXT NOT NULL DEFAULT 'LKR',
          "timezone" TEXT NOT NULL DEFAULT 'Asia/Colombo',
          "business_address" TEXT,
          "contact_phone" TEXT,
          "contact_email" TEXT,
          "registration_number" TEXT,
          "logo_uri" TEXT,
          "receipt_header_notes" TEXT,
          "receipt_footer_notes" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL
        );
        CREATE TABLE "app_users" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL,
          "username" TEXT NOT NULL,
          "full_name" TEXT NOT NULL,
          "role" TEXT NOT NULL,
          "is_active" INTEGER NOT NULL DEFAULT 1,
          "session_version" INTEGER NOT NULL DEFAULT 1,
          "permissions" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL
        );
        CREATE TABLE "sync_queue" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL,
          "idempotency_key" TEXT NOT NULL UNIQUE,
          "entity_type" TEXT NOT NULL,
          "entity_id" TEXT NOT NULL,
          "action_type" TEXT NOT NULL,
          "payload_json" TEXT NOT NULL,
          "status" TEXT NOT NULL DEFAULT 'pending_server_ack',
          "retry_count" INTEGER NOT NULL DEFAULT 0,
          "last_error" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER
        );
        CREATE TABLE "customers" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL,
          "full_name" TEXT NOT NULL,
          "nic" TEXT NOT NULL,
          "phone" TEXT NOT NULL,
          "address" TEXT NOT NULL,
          "photo_uri" TEXT,
          "photo_hash" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL
        );
        CREATE INDEX "idx_customers_shop_id" ON "customers" ("shop_id");
        CREATE UNIQUE INDEX "idx_customers_shop_nic" ON "customers" ("shop_id", "nic");
        CREATE TABLE "customer_photo_exceptions" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL,
          "target_customer_id" TEXT NOT NULL,
          "customer_nic" TEXT NOT NULL,
          "requested_by_user_id" TEXT NOT NULL,
          "request_reason" TEXT NOT NULL,
          "status" TEXT NOT NULL DEFAULT 'pending_owner_approval',
          "reviewed_by_user_id" TEXT,
          "review_notes" TEXT,
          "reviewed_at" INTEGER,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL
        );
        CREATE INDEX "idx_photo_exceptions_shop_status" ON "customer_photo_exceptions" ("shop_id", "status");
        CREATE INDEX "idx_photo_exceptions_customer" ON "customer_photo_exceptions" ("shop_id", "target_customer_id");
        CREATE INDEX "idx_photo_exceptions_nic" ON "customer_photo_exceptions" ("shop_id", "customer_nic");
        PRAGMA user_version = 5;
      ''');

      final nowEpoch = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      rawSqliteDb.execute('''
        INSERT INTO "shops" ("id", "name", "currency_code", "timezone", "created_at", "updated_at")
        VALUES ('shop-v5-orig', 'V5 Original Shop', 'LKR', 'Asia/Colombo', $nowEpoch, $nowEpoch);
      ''');
      rawSqliteDb.execute('''
        INSERT INTO "app_users" ("id", "shop_id", "username", "full_name", "role", "is_active", "session_version", "permissions", "created_at", "updated_at")
        VALUES ('user-v5-orig', 'shop-v5-orig', 'v5.staff', 'V5 Staff', 'counter_staff', 1, 1, NULL, $nowEpoch, $nowEpoch);
      ''');
      rawSqliteDb.execute('''
        INSERT INTO "customers" ("id", "shop_id", "full_name", "nic", "phone", "address", "photo_uri", "photo_hash", "created_at", "updated_at")
        VALUES ('cust-v5-existing', 'shop-v5-orig', 'V5 Existing Customer', '198512345678', '+94 77 999 8888', '45 Park Road', '/photos/cust.jpg', 'hash-v5', $nowEpoch, $nowEpoch);
      ''');

      final executor = NativeDatabase.opened(rawSqliteDb);
      final upgradedDb = AppDatabase.forTesting(executor);

      // Verify pre-existing customer survived without loss.
      // The legacy TEXT id is remapped to the rowid during the v20 migration.
      final existingCustomer = await (upgradedDb.select(upgradedDb.customers)
            ..where((c) => c.nic.equals('198512345678')))
          .getSingle();
      expect(existingCustomer.id, equals(1));
      expect(existingCustomer.fullName, equals('V5 Existing Customer'));
      expect(existingCustomer.nic, equals('198512345678'));

      // Verify pre-existing user survived with password_hash column available
      final existingUser = await (upgradedDb.select(upgradedDb.appUsers)
            ..where((u) => u.id.equals('user-v5-orig')))
          .getSingle();
      expect(existingUser.passwordHash, isNull);

      // Verify the new v6 shared-phone index was created
      final customerIndexRows = await upgradedDb.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'customers';").get();
      final customerIndexNames = customerIndexRows.map((r) => r.read<String>('name')).toList();
      expect(customerIndexNames, containsAll([
        'idx_customers_shop_id',
        'idx_customers_shop_nic',
        'idx_customers_shop_phone',
      ]));

      // Verify inserting a customer with a phone works after migration
      final now = DateTime.now().toUtc();
      await upgradedDb.into(upgradedDb.customers).insert(
        CustomerEntry(
          id: 99,
          shopId: 'shop-v5-orig',
          fullName: 'V6 New Customer',
          nic: '199012345678',
          phone: '0771234567',
          address: '78 Lake Road, Kandy',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final newCust = await (upgradedDb.select(upgradedDb.customers)
            ..where((c) => c.id.equals(99)))
          .getSingle();
      expect(newCust.phone, equals('0771234567'));

      await upgradedDb.close();
    });

    test('MIGRATION: verifies upgrade from schema version 6 to 8 preserves existing data and adds credits table with indexes', () async {
      final rawSqliteDb = sqlite.sqlite3.openInMemory();
      rawSqliteDb.execute('''
        CREATE TABLE "shops" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "name" TEXT NOT NULL,
          "currency_code" TEXT NOT NULL DEFAULT 'LKR',
          "timezone" TEXT NOT NULL DEFAULT 'Asia/Colombo',
          "business_address" TEXT,
          "contact_phone" TEXT,
          "contact_email" TEXT,
          "registration_number" TEXT,
          "logo_uri" TEXT,
          "receipt_header_notes" TEXT,
          "receipt_footer_notes" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL
        );
        CREATE TABLE "app_users" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL,
          "username" TEXT NOT NULL,
          "full_name" TEXT NOT NULL,
          "role" TEXT NOT NULL,
          "is_active" INTEGER NOT NULL DEFAULT 1,
          "session_version" INTEGER NOT NULL DEFAULT 1,
          "permissions" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL
        );
        CREATE TABLE "sync_queue" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL,
          "idempotency_key" TEXT NOT NULL UNIQUE,
          "entity_type" TEXT NOT NULL,
          "entity_id" TEXT NOT NULL,
          "action_type" TEXT NOT NULL,
          "payload_json" TEXT NOT NULL,
          "status" TEXT NOT NULL DEFAULT 'pending_server_ack',
          "retry_count" INTEGER NOT NULL DEFAULT 0,
          "last_error" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER
        );
        CREATE TABLE "customers" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL,
          "full_name" TEXT NOT NULL,
          "nic" TEXT NOT NULL,
          "phone" TEXT NOT NULL,
          "address" TEXT NOT NULL,
          "photo_uri" TEXT,
          "photo_hash" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL
        );
        CREATE INDEX "idx_customers_shop_id" ON "customers" ("shop_id");
        CREATE UNIQUE INDEX "idx_customers_shop_nic" ON "customers" ("shop_id", "nic");
        CREATE INDEX "idx_customers_shop_phone" ON "customers" ("shop_id", "phone");
        CREATE TABLE "customer_photo_exceptions" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL,
          "target_customer_id" TEXT NOT NULL,
          "customer_nic" TEXT NOT NULL,
          "requested_by_user_id" TEXT NOT NULL,
          "request_reason" TEXT NOT NULL,
          "status" TEXT NOT NULL DEFAULT 'pending_owner_approval',
          "reviewed_by_user_id" TEXT,
          "review_notes" TEXT,
          "reviewed_at" INTEGER,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL
        );
        CREATE INDEX "idx_photo_exceptions_shop_status" ON "customer_photo_exceptions" ("shop_id", "status");
        CREATE INDEX "idx_photo_exceptions_customer" ON "customer_photo_exceptions" ("shop_id", "target_customer_id");
        CREATE INDEX "idx_photo_exceptions_nic" ON "customer_photo_exceptions" ("shop_id", "customer_nic");
        PRAGMA user_version = 6;
      ''');

      final nowEpoch = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      rawSqliteDb.execute('''
        INSERT INTO "shops" ("id", "name", "currency_code", "timezone", "created_at", "updated_at")
        VALUES ('shop-v6-orig', 'V6 Original Shop', 'LKR', 'Asia/Colombo', $nowEpoch, $nowEpoch);
      ''');
      rawSqliteDb.execute('''
        INSERT INTO "app_users" ("id", "shop_id", "username", "full_name", "role", "is_active", "session_version", "permissions", "created_at", "updated_at")
        VALUES ('user-v6-orig', 'shop-v6-orig', 'v6.staff', 'V6 Staff', 'counter_staff', 1, 1, NULL, $nowEpoch, $nowEpoch);
      ''');
      rawSqliteDb.execute('''
        INSERT INTO "customers" ("id", "shop_id", "full_name", "nic", "phone", "address", "photo_uri", "photo_hash", "created_at", "updated_at")
        VALUES (1, 'shop-v6-orig', 'V6 Existing Customer', '198512345678', '+94 77 999 8888', '45 Park Road', '/photos/cust.jpg', 'hash-v6', $nowEpoch, $nowEpoch);
      ''');

      final executor = NativeDatabase.opened(rawSqliteDb);
      final upgradedDb = AppDatabase.forTesting(executor);

      // Verify pre-existing customer survived without loss
      final existingCustomer = await (upgradedDb.select(upgradedDb.customers)
            ..where((c) => c.id.equals(1)))
          .getSingle();
      expect(existingCustomer.fullName, equals('V6 Existing Customer'));
      expect(existingCustomer.nic, equals('198512345678'));

      // Verify pre-existing user survived with password_hash column available
      final existingUser = await (upgradedDb.select(upgradedDb.appUsers)
            ..where((u) => u.id.equals('user-v6-orig')))
          .getSingle();
      expect(existingUser.passwordHash, isNull);

      // Verify the new v7 credits table and indexes were created
      final creditIndexRows = await upgradedDb.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'credits';").get();
      final creditIndexNames = creditIndexRows.map((r) => r.read<String>('name')).toList();
      expect(creditIndexNames, containsAll([
        'idx_credits_shop_id',
        'idx_credits_shop_customer',
        'idx_credits_shop_status',
        'idx_credits_shop_customer_status',
      ]));

      // Verify inserting a credit works after migration
      final now = DateTime.now().toUtc();
      await upgradedDb.into(upgradedDb.credits).insert(
        CreditEntry(
          id: 'credit-v7-new',
          shopId: 'shop-v6-orig',
          customerId: 1,
          principalCents: 500000,
          balanceCents: 500000,
          status: 'active',
          workflowStatus: CreditWorkflowStatus.pendingDisbursement.value,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
          correctionPending: false,
        creditType: 'cash',
        ),
      );

      final newCredit = await (upgradedDb.select(upgradedDb.credits)
            ..where((l) => l.id.equals('credit-v7-new')))
          .getSingle();
      expect(newCredit.status, equals('active'));
      expect(newCredit.customerId, equals(1));

      await upgradedDb.close();
    });

    test('MIGRATION: verifies upgrade from schema version 7 to 8 adds password_hash column', () async {
      final rawSqliteDb = sqlite.sqlite3.openInMemory();
      rawSqliteDb.execute('''
        CREATE TABLE "shops" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "name" TEXT NOT NULL,
          "currency_code" TEXT NOT NULL DEFAULT 'LKR',
          "timezone" TEXT NOT NULL DEFAULT 'Asia/Colombo',
          "business_address" TEXT,
          "contact_phone" TEXT,
          "contact_email" TEXT,
          "registration_number" TEXT,
          "logo_uri" TEXT,
          "receipt_header_notes" TEXT,
          "receipt_footer_notes" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL
        );
        CREATE TABLE "app_users" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL,
          "username" TEXT NOT NULL,
          "full_name" TEXT NOT NULL,
          "role" TEXT NOT NULL,
          "is_active" INTEGER NOT NULL DEFAULT 1,
          "session_version" INTEGER NOT NULL DEFAULT 1,
          "permissions" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL
        );
        CREATE TABLE "sync_queue" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL,
          "idempotency_key" TEXT NOT NULL UNIQUE,
          "entity_type" TEXT NOT NULL,
          "entity_id" TEXT NOT NULL,
          "action_type" TEXT NOT NULL,
          "payload_json" TEXT NOT NULL,
          "status" TEXT NOT NULL DEFAULT 'pending_server_ack',
          "retry_count" INTEGER NOT NULL DEFAULT 0,
          "last_error" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER
        );
        CREATE TABLE "customers" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL,
          "full_name" TEXT NOT NULL,
          "nic" TEXT NOT NULL,
          "phone" TEXT NOT NULL,
          "address" TEXT NOT NULL,
          "photo_uri" TEXT,
          "photo_hash" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL
        );
        CREATE INDEX "idx_customers_shop_id" ON "customers" ("shop_id");
        CREATE UNIQUE INDEX "idx_customers_shop_nic" ON "customers" ("shop_id", "nic");
        CREATE INDEX "idx_customers_shop_phone" ON "customers" ("shop_id", "phone");
        CREATE TABLE "customer_photo_exceptions" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL,
          "target_customer_id" TEXT NOT NULL,
          "customer_nic" TEXT NOT NULL,
          "requested_by_user_id" TEXT NOT NULL,
          "request_reason" TEXT NOT NULL,
          "status" TEXT NOT NULL DEFAULT 'pending_owner_approval',
          "reviewed_by_user_id" TEXT,
          "review_notes" TEXT,
          "reviewed_at" INTEGER,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL
        );
        CREATE INDEX "idx_photo_exceptions_shop_status" ON "customer_photo_exceptions" ("shop_id", "status");
        CREATE INDEX "idx_photo_exceptions_customer" ON "customer_photo_exceptions" ("shop_id", "target_customer_id");
        CREATE INDEX "idx_photo_exceptions_nic" ON "customer_photo_exceptions" ("shop_id", "customer_nic");
        CREATE TABLE "credits" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL,
          "customer_id" TEXT NOT NULL,
          "principal_cents" INTEGER NOT NULL,
          "balance_cents" INTEGER NOT NULL,
          "status" TEXT NOT NULL,
          "due_date" INTEGER NOT NULL,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL,
          "settled_at" INTEGER
        );
        CREATE INDEX "idx_credits_shop_id" ON "credits" ("shop_id");
        CREATE INDEX "idx_credits_shop_customer" ON "credits" ("shop_id", "customer_id");
        CREATE INDEX "idx_credits_shop_status" ON "credits" ("shop_id", "status");
        CREATE INDEX "idx_credits_shop_customer_status" ON "credits" ("shop_id", "customer_id", "status");
        PRAGMA user_version = 7;
      ''');

      final nowEpoch = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      rawSqliteDb.execute('''
        INSERT INTO "shops" ("id", "name", "currency_code", "timezone", "created_at", "updated_at")
        VALUES ('shop-v7-orig', 'V7 Original Shop', 'LKR', 'Asia/Colombo', $nowEpoch, $nowEpoch);
      ''');
      rawSqliteDb.execute('''
        INSERT INTO "app_users" ("id", "shop_id", "username", "full_name", "role", "is_active", "session_version", "permissions", "created_at", "updated_at")
        VALUES ('user-v7-orig', 'shop-v7-orig', 'v7.staff', 'V7 Staff', 'counter_staff', 1, 1, NULL, $nowEpoch, $nowEpoch);
      ''');
      rawSqliteDb.execute('''
        INSERT INTO "customers" ("id", "shop_id", "full_name", "nic", "phone", "address", "photo_uri", "photo_hash", "created_at", "updated_at")
        VALUES ('cust-v7-existing', 'shop-v7-orig', 'V7 Existing Customer', '198512345678', '+94 77 999 8888', '45 Park Road', '/photos/cust.jpg', 'hash-v7', $nowEpoch, $nowEpoch);
      ''');
      rawSqliteDb.execute('''
        INSERT INTO "credits" ("id", "shop_id", "customer_id", "principal_cents", "balance_cents", "status", "due_date", "created_at", "updated_at")
        VALUES ('credit-v7-existing', 'shop-v7-orig', 'cust-v7-existing', 500000, 500000, 'active', $nowEpoch, $nowEpoch, $nowEpoch);
      ''');

      final executor = NativeDatabase.opened(rawSqliteDb);
      final upgradedDb = AppDatabase.forTesting(executor);

      // Verify pre-existing user survived with password_hash column available and null by default
      final existingUser = await (upgradedDb.select(upgradedDb.appUsers)
            ..where((u) => u.id.equals('user-v7-orig')))
          .getSingle();
      expect(existingUser.username, equals('v7.staff'));
      expect(existingUser.passwordHash, isNull);

      // Verify pre-existing customer survived without loss.
      // The legacy TEXT id is remapped to the rowid during the v20 migration.
      final existingCustomer = await (upgradedDb.select(upgradedDb.customers)
            ..where((c) => c.nic.equals('198512345678')))
          .getSingle();
      expect(existingCustomer.id, equals(1));
      expect(existingCustomer.fullName, equals('V7 Existing Customer'));
      expect(existingCustomer.nic, equals('198512345678'));

      // Verify pre-existing credit survived without loss
      final existingCredit = await (upgradedDb.select(upgradedDb.credits)
            ..where((l) => l.id.equals('credit-v7-existing')))
          .getSingle();
      expect(existingCredit.status, equals('active'));
      expect(existingCredit.customerId, equals(1));
      // Story 4.1 (schema v12): credits that predate the disbursement workflow
      // were already payable under the Story 2.5 model, so the migration
      // backfills them to 'disbursed' rather than blocking their payments.
      expect(existingCredit.workflowStatus, equals('disbursed'));

      // Verify inserting a user with password_hash set works after migration
      final now = DateTime.now().toUtc();
      await upgradedDb.into(upgradedDb.appUsers).insert(
        AppUserEntry(
          id: 'user-v8-new',
          shopId: 'shop-v7-orig',
          username: 'v8.newuser',
          fullName: 'V8 New User',
          role: 'cashier',
          isActive: true,
          sessionVersion: 1,
          permissions: 'viewCustomers',
          passwordHash: 'scrypt:hashed-password',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final newUser = await (upgradedDb.select(upgradedDb.appUsers)
            ..where((u) => u.id.equals('user-v8-new')))
          .getSingle();
      expect(newUser.passwordHash, equals('scrypt:hashed-password'));

      await upgradedDb.close();
    });

    test('MIGRATION: verifies upgrade from schema version 12 to 13 rebuilds the '
        'credits table, preserves balances and keeps child foreign keys intact',
        () async {
      // A v12 database that already holds a credit and a collateral item bound
      // to it. The child row is what exercises the foreign-key safety of the
      // credits table rebuild.
      final rawSqliteDb = sqlite.sqlite3.openInMemory();
      rawSqliteDb.execute('''
        CREATE TABLE "shops" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "name" TEXT NOT NULL,
          "currency_code" TEXT NOT NULL DEFAULT 'LKR',
          "timezone" TEXT NOT NULL DEFAULT 'Asia/Colombo',
          "business_address" TEXT,
          "contact_phone" TEXT,
          "contact_email" TEXT,
          "registration_number" TEXT,
          "logo_uri" TEXT,
          "receipt_header_notes" TEXT,
          "receipt_footer_notes" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL
        );
        CREATE TABLE "app_users" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
          "username" TEXT NOT NULL,
          "full_name" TEXT NOT NULL,
          "role" TEXT NOT NULL,
          "is_active" INTEGER NOT NULL DEFAULT 1,
          "session_version" INTEGER NOT NULL DEFAULT 1,
          "permissions" TEXT,
          "password_hash" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL
        );
        CREATE TABLE "sync_queue" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
          "idempotency_key" TEXT NOT NULL,
          "entity_type" TEXT NOT NULL,
          "entity_id" TEXT NOT NULL,
          "action_type" TEXT NOT NULL,
          "payload_json" TEXT NOT NULL,
          "status" TEXT NOT NULL DEFAULT 'pending_server_ack',
          "retry_count" INTEGER NOT NULL DEFAULT 0,
          "last_error" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER,
          UNIQUE ("shop_id", "idempotency_key")
        );
        CREATE UNIQUE INDEX "idx_sync_queue_idempotency" ON "sync_queue" ("shop_id", "idempotency_key");
        CREATE TABLE "customers" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
          "full_name" TEXT NOT NULL,
          "nic" TEXT NOT NULL,
          "phone" TEXT NOT NULL,
          "address" TEXT NOT NULL,
          "photo_uri" TEXT,
          "photo_hash" TEXT,
          "created_at" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL
        );
        CREATE TABLE "credits" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
          "customer_id" TEXT NOT NULL REFERENCES "customers" ("id") ON DELETE RESTRICT,
          "principal_cents" INTEGER NOT NULL,
          "balance_cents" INTEGER NOT NULL,
          "status" TEXT NOT NULL DEFAULT 'active',
          "workflow_status" TEXT NOT NULL DEFAULT 'pending_disbursement',
          "due_date" INTEGER NOT NULL,
          "created_at" INTEGER NOT NULL,
          "settled_at" INTEGER
        );
        CREATE TABLE "collateral_items" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
          "customer_id" TEXT NOT NULL REFERENCES "customers" ("id") ON DELETE RESTRICT,
          "credit_id" TEXT REFERENCES "credits" ("id") ON DELETE RESTRICT,
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
          "updated_at" INTEGER NOT NULL
        );
        PRAGMA user_version = 12;
      ''');

      final nowEpoch = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      rawSqliteDb.execute('''
        INSERT INTO "shops" ("id", "name", "currency_code", "timezone", "created_at", "updated_at")
        VALUES ('shop-v12', 'V12 Shop', 'LKR', 'Asia/Colombo', $nowEpoch, $nowEpoch);
      ''');
      rawSqliteDb.execute('''
        INSERT INTO "app_users" ("id", "shop_id", "username", "full_name", "role", "is_active", "session_version", "permissions", "password_hash", "created_at", "updated_at")
        VALUES ('user-v12', 'shop-v12', 'v12.staff', 'V12 Staff', 'manager', 1, 1, NULL, NULL, $nowEpoch, $nowEpoch);
      ''');
      rawSqliteDb.execute('''
        INSERT INTO "customers" ("id", "shop_id", "full_name", "nic", "phone", "address", "created_at", "updated_at")
        VALUES ('cust-v12', 'shop-v12', 'V12 Customer', '198512345678', '+94 77 123 4567', '45 Park Road', $nowEpoch, $nowEpoch);
      ''');
      rawSqliteDb.execute('''
        INSERT INTO "credits" ("id", "shop_id", "customer_id", "principal_cents", "balance_cents", "status", "workflow_status", "due_date", "created_at")
        VALUES ('credit-v12', 'shop-v12', 'cust-v12', 500000, 500000, 'active', 'pending_disbursement', $nowEpoch, $nowEpoch);
      ''');
      rawSqliteDb.execute('''
        INSERT INTO "collateral_items" ("id", "shop_id", "customer_id", "credit_id", "item_reference_id", "category", "description", "condition_grade", "weight_milligrams", "estimated_value_cents", "custody_status", "created_at", "updated_at")
        VALUES ('coll-v12', 'shop-v12', 'cust-v12', 'credit-v12', 'COLL-V12-001', 'gold', '22K gold necklace', 'Good', 5500, 1500000, 'in_custody', $nowEpoch, $nowEpoch);
      ''');

      // Foreign keys are enabled exactly as they are on a real device
      // connection (see AppDatabaseConnection.openSandboxedConnection, which
      // sets `PRAGMA foreign_keys = ON` in the connection setup callback).
      // Without this the `collateral_items.credit_id -> credits` RESTRICT
      // constraint is never enforced during the migration, which is exactly
      // why this test used to pass while the v12 -> v13 rebuild failed on a
      // device.
      final executor = NativeDatabase.opened(
        rawSqliteDb,
        setup: (db) => db.execute('PRAGMA foreign_keys = ON;'),
      );
      final upgradedDb = AppDatabase.forTesting(executor);

      // The pre-existing credit survived the rebuild with its financial
      // balances, statuses and due date unchanged.
      final credit = await (upgradedDb.select(upgradedDb.credits)
            ..where((l) => l.id.equals('credit-v12')))
          .getSingle();
      expect(credit.principalCents, equals(500000));
      expect(credit.balanceCents, equals(500000),
          reason: 'The migration must not change financial balances.');
      expect(credit.status, equals('active'));
      expect(credit.workflowStatus, equals('pending_disbursement'));

      // The new columns exist and are empty for a pre-existing agreement.
      expect(credit.termPresetDays, isNull);
      expect(credit.customDueDate, isNull);
      expect(credit.disbursedAt, isNull);
      expect(credit.disbursedByUserId, isNull);
      expect(credit.cancelledAt, isNull);
      expect(credit.cancellationReason, isNull);

      // The child foreign key into "credits" survived the table rebuild.
      final item = await (upgradedDb.select(upgradedDb.collateralItems)
            ..where((c) => c.id.equals('coll-v12')))
          .getSingle();
      expect(item.creditId, equals('credit-v12'),
          reason: 'Rebuilding the parent table must keep child rows bound.');

      // The credits indexes were recreated.
      final creditIndexRows = await upgradedDb.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'credits';").get();
      final creditIndexNames = creditIndexRows.map((r) => r.read<String>('name')).toList();
      expect(creditIndexNames, containsAll([
        'idx_credits_shop_id',
        'idx_credits_shop_customer',
        'idx_credits_shop_status',
        'idx_credits_shop_customer_status',
      ]));

      // The rebuilt table accepts a disbursement record.
      final now = DateTime.now().toUtc();
      await (upgradedDb.update(upgradedDb.credits)
            ..where((l) => l.id.equals('credit-v12')))
          .write(CreditsCompanion(
        workflowStatus: const Value('disbursed'),
        disbursedAt: Value(now),
        disbursedByUserId: const Value('user-v12'),
        termPresetDays: const Value(30),
      ));

      final disbursed = await (upgradedDb.select(upgradedDb.credits)
            ..where((l) => l.id.equals('credit-v12')))
          .getSingle();
      expect(disbursed.workflowStatus, equals('disbursed'));
      expect(disbursed.disbursedAt, isNotNull);
      expect(disbursed.termPresetDays, equals(30));

      await upgradedDb.close();
    });

    test('SHOPS: inserts and queries shop tenant profile with defaults', () async {
      final now = DateTime.now().toUtc();
      final shop = ShopEntry(
        id: 'shop-uuid-1',
        name: 'Perera Jewellers Colombo',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      );

      await db.into(db.shops).insert(shop);

      final retrieved = await (db.select(db.shops)..where((s) => s.id.equals('shop-uuid-1'))).getSingle();
      expect(retrieved.id, equals('shop-uuid-1'));
      expect(retrieved.name, equals('Perera Jewellers Colombo'));
      expect(retrieved.currencyCode, equals('LKR'));
      expect(retrieved.timezone, equals('Asia/Colombo'));
    });

    test('SHOPS: updates shop name and operational timezone', () async {
      final now = DateTime.now().toUtc();
      await db.into(db.shops).insert(
        ShopEntry(
          id: 'shop-uuid-2',
          name: 'Original Name',
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await (db.update(db.shops)..where((s) => s.id.equals('shop-uuid-2'))).write(
        ShopsCompanion(
          name: const Value('Updated Trade Name'),
          timezone: const Value('Asia/Kolkata'),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

      final updated = await (db.select(db.shops)..where((s) => s.id.equals('shop-uuid-2'))).getSingle();
      expect(updated.name, equals('Updated Trade Name'));
      expect(updated.timezone, equals('Asia/Kolkata'));
    });

    test('APP_USERS: inserts counter staff account with default session_version = 1', () async {
      final now = DateTime.now().toUtc();
      await db.into(db.shops).insert(
        ShopEntry(
          id: 'shop-uuid-3',
          name: 'City Pawn Colombo',
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final user = AppUserEntry(
        id: 'user-uuid-1',
        shopId: 'shop-uuid-3',
        username: 'kasun.counter',
        fullName: 'Kasun Perera',
        role: 'counter_staff',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      );

      await db.into(db.appUsers).insert(user);

      final retrieved = await (db.select(db.appUsers)..where((u) => u.id.equals('user-uuid-1'))).getSingle();
      expect(retrieved.username, equals('kasun.counter'));
      expect(retrieved.role, equals('counter_staff'));
      expect(retrieved.sessionVersion, equals(1));
      expect(retrieved.isActive, isTrue);
    });

    test('APP_USERS: increments session_version to immediately revoke sessions (FR-5)', () async {
      final now = DateTime.now().toUtc();
      await db.into(db.shops).insert(
        ShopEntry(
          id: 'shop-uuid-4',
          name: 'City Pawn Colombo',
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await db.into(db.appUsers).insert(
        AppUserEntry(
          id: 'user-uuid-2',
          shopId: 'shop-uuid-4',
          username: 'staff.revocation.test',
          fullName: 'Revocation Staff',
          role: 'counter_staff',
          isActive: true,
          sessionVersion: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Increment session version on credential change or permission update
      await (db.update(db.appUsers)..where((u) => u.id.equals('user-uuid-2'))).write(
        AppUsersCompanion(
          sessionVersion: const Value(2),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

      final userAfterRevocation = await (db.select(db.appUsers)..where((u) => u.id.equals('user-uuid-2'))).getSingle();
      expect(userAfterRevocation.sessionVersion, equals(2));
    });

    test('FOREIGN KEY: AppUsers insertion fails if referenced shop does not exist', () async {
      final now = DateTime.now().toUtc();
      final orphanUser = AppUserEntry(
        id: 'orphan-user-1',
        shopId: 'non-existent-shop-id',
        username: 'orphan',
        fullName: 'Orphan Staff',
        role: 'counter_staff',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      );

      expect(
        () => db.into(db.appUsers).insert(orphanUser),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test('UNIQUE CONSTRAINT: AppUsers blocks duplicate username within same shop tenant', () async {
      final now = DateTime.now().toUtc();
      await db.into(db.shops).insert(
        ShopEntry(
          id: 'shop-uuid-5',
          name: 'Shop Five',
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await db.into(db.appUsers).insert(
        AppUserEntry(
          id: 'user-a',
          shopId: 'shop-uuid-5',
          username: 'duplicate.user',
          fullName: 'Staff Alpha',
          role: 'counter_staff',
          isActive: true,
          sessionVersion: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(
        () => db.into(db.appUsers).insert(
          AppUserEntry(
            id: 'user-b',
            shopId: 'shop-uuid-5',
            username: 'duplicate.user',
            fullName: 'Staff Beta',
            role: 'counter_staff',
            isActive: true,
            sessionVersion: 1,
            createdAt: now,
            updatedAt: now,
          ),
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test('SYNC_QUEUE: inserts, filters pending items, and confirms server acknowledgement', () async {
      final now = DateTime.now().toUtc();
      await db.into(db.shops).insert(
        ShopEntry(
          id: 'shop-uuid-6',
          name: 'Shop Six',
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final queueItem = SyncQueueRecord(
        id: 'sync-op-1',
        shopId: 'shop-uuid-6',
        idempotencyKey: 'idem-uuid-001',
        entityType: 'credit',
        entityId: 'credit-uuid-101',
        actionType: 'create_credit',
        payloadJson: '{"principal_cents": 5000000, "duration_days": 30}',
        status: 'pending_server_ack',
        retryCount: 0,
        lastError: null,
        createdAt: now,
        updatedAt: null,
      );

      await db.into(db.syncQueue).insert(queueItem);

      // Query only pending server ack items for shop
      final pendingOps = await (db.select(db.syncQueue)
            ..where((q) => q.shopId.equals('shop-uuid-6') & q.status.equals('pending_server_ack')))
          .get();

      expect(pendingOps.length, equals(1));
      expect(pendingOps.first.idempotencyKey, equals('idem-uuid-001'));
      expect(pendingOps.first.status, equals('pending_server_ack'));

      // Transition to confirmed_by_server upon server acknowledgement
      await (db.update(db.syncQueue)..where((q) => q.id.equals('sync-op-1'))).write(
        SyncQueueCompanion(
          status: const Value('confirmed_by_server'),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

      final confirmed = await (db.select(db.syncQueue)..where((q) => q.id.equals('sync-op-1'))).getSingle();
      expect(confirmed.status, equals('confirmed_by_server'));
    });

    test('SYNC_QUEUE: unique idempotency constraint blocks duplicate operations', () async {
      final now = DateTime.now().toUtc();
      await db.into(db.shops).insert(
        ShopEntry(
          id: 'shop-uuid-7',
          name: 'Shop Seven',
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await db.into(db.syncQueue).insert(
        SyncQueueRecord(
          id: 'sync-op-2',
          shopId: 'shop-uuid-7',
          idempotencyKey: 'same-idempotency-key',
          entityType: 'payment',
          entityId: 'payment-1',
          actionType: 'record_payment',
          payloadJson: '{"amount_cents": 100000}',
          status: 'pending_server_ack',
          retryCount: 0,
          lastError: null,
          createdAt: now,
          updatedAt: null,
        ),
      );

      expect(
        () => db.into(db.syncQueue).insert(
          SyncQueueRecord(
            id: 'sync-op-3',
            shopId: 'shop-uuid-7',
            idempotencyKey: 'same-idempotency-key',
            entityType: 'payment',
            entityId: 'payment-2',
            actionType: 'record_payment',
            payloadJson: '{"amount_cents": 100000}',
            status: 'pending_server_ack',
            retryCount: 0,
            lastError: null,
            createdAt: now,
            updatedAt: null,
          ),
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test('FOREIGN KEY: Customers insertion fails if referenced shop does not exist', () async {
      final now = DateTime.now().toUtc();
      final orphanCustomer = CustomerEntry(
        id: 999,
        shopId: 'non-existent-shop-id',
        fullName: 'Orphan Customer',
        nic: '901234567V',
        phone: '+94 77 123 4567',
        address: '123 Main St, Colombo',
        createdAt: now,
        updatedAt: now,
      );

      expect(
        () => db.into(db.customers).insert(orphanCustomer),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test('UNIQUE CONSTRAINT: Customers blocks duplicate NIC within same shop, permits across different shops', () async {
      final now = DateTime.now().toUtc();
      await db.into(db.shops).insert(
        ShopEntry(
          id: 'shop-cust-alpha',
          name: 'Shop Alpha',
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db.into(db.shops).insert(
        ShopEntry(
          id: 'shop-cust-beta',
          name: 'Shop Beta',
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Insert customer in Shop Alpha
      await db.into(db.customers).insert(
        CustomerEntry(
          id: 10,
          shopId: 'shop-cust-alpha',
          fullName: 'Saman Kumara',
          nic: '851234567V',
          phone: '+94 77 123 4567',
          address: '123 Main St, Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Attempt duplicate NIC in Shop Alpha -> must fail
      expect(
        () => db.into(db.customers).insert(
          CustomerEntry(
            id: 11,
            shopId: 'shop-cust-alpha',
            fullName: 'Duplicate Saman',
            nic: '851234567V',
            phone: '+94 77 123 4567',
            address: '123 Main St, Colombo',
            createdAt: now,
            updatedAt: now,
          ),
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );

      // Same NIC in Shop Beta -> must succeed (shop isolation)
      await db.into(db.customers).insert(
        CustomerEntry(
          id: 1,
          shopId: 'shop-cust-beta',
          fullName: 'Saman Kumara at Beta',
          nic: '851234567V',
          phone: '+94 77 123 4567',
          address: '123 Main St, Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final betaCust = await (db.select(db.customers)..where((c) => c.id.equals(1))).getSingle();
      expect(betaCust.shopId, equals('shop-cust-beta'));
      expect(betaCust.nic, equals('851234567V'));
    });

    test('FOREIGN KEY: CustomerPhotoExceptions insertion fails if referenced shop does not exist', () async {
      final now = DateTime.now().toUtc();
      final orphanException = CustomerPhotoExceptionEntry(
        id: 'orphan-exc-1',
        shopId: 'non-existent-shop-id',
        targetCustomerId: 'target-1',
        customerNic: '901234567V',
        requestedByUserId: 'any-user',
        requestReason: 'Reason',
        status: 'pending_owner_approval',
        createdAt: now,
        updatedAt: now,
      );

      expect(
        () => db.into(db.customerPhotoExceptions).insert(orphanException),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test('FOREIGN KEY: CustomerPhotoExceptions insertion fails if requestedByUserId does not exist', () async {
      final now = DateTime.now().toUtc();
      await db.into(db.shops).insert(
        ShopEntry(
          id: 'shop-fk-exc',
          name: 'FK Exception Shop',
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final orphanUserException = CustomerPhotoExceptionEntry(
        id: 'orphan-user-exc-1',
        shopId: 'shop-fk-exc',
        targetCustomerId: 'target-1',
        customerNic: '901234567V',
        requestedByUserId: 'non-existent-user-id',
        requestReason: 'Reason',
        status: 'pending_owner_approval',
        createdAt: now,
        updatedAt: now,
      );

      expect(
        () => db.into(db.customerPhotoExceptions).insert(orphanUserException),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test('CHECK CONSTRAINT: CustomerPhotoExceptions blocks invalid status strings', () async {
      final now = DateTime.now().toUtc();
      await db.into(db.shops).insert(
        ShopEntry(
          id: 'shop-check-exc',
          name: 'Check Exception Shop',
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db.into(db.appUsers).insert(
        AppUserEntry(
          id: 'user-check-exc',
          shopId: 'shop-check-exc',
          username: 'check.user',
          fullName: 'Check User',
          role: 'cashier',
          isActive: true,
          sessionVersion: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final invalidStatusException = CustomerPhotoExceptionEntry(
        id: 'invalid-status-exc',
        shopId: 'shop-check-exc',
        targetCustomerId: 'target-1',
        customerNic: '901234567V',
        requestedByUserId: 'user-check-exc',
        requestReason: 'Reason',
        status: 'arbitrary_bypass_status',
        createdAt: now,
        updatedAt: now,
      );

      expect(
        () => db.into(db.customerPhotoExceptions).insert(invalidStatusException),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });
  });
}

