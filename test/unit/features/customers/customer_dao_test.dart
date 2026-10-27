import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/features/customers/data/daos/customer_dao.dart';
import 'package:credit_system/features/customers/domain/models/customer.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  late AppDatabase db;
  late CustomerDao customerDao;

  const shopAlphaId = 'shop-alpha-101';
  const shopBetaId = 'shop-beta-202';

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);
    customerDao = db.customerDao;

    // Seed two distinct shop tenants
    final now = DateTime.now().toUtc();
    await db.into(db.shops).insert(
      ShopEntry(
        id: shopAlphaId,
        name: 'Alpha Jewellers',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.shops).insert(
      ShopEntry(
        id: shopBetaId,
        name: 'Beta Jewellers',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('CustomerDao - Local CRUD & Persistence', () {
    test('createCustomer inserts record with normalized NIC and returns domain entity on query', () async {
      final now = DateTime.now().toUtc();
      // The id placeholder (0) is replaced by the database-assigned
      // auto-increment id on insert.
      final customer = Customer(
        id: 0,
        shopId: shopAlphaId,
        fullName: 'Nimal Perera',
        nic: ' 851234567v ', // whitespace & lowercase 'v'
        phone: '+94 77 123 4567',
        address: '15 Main St, Colombo 11',
        photoUri: '/storage/photos/cust-1.jpg',
        photoHash: 'hash123',
        createdAt: now,
        updatedAt: now,
      );

      final newId = await customerDao.createCustomer(customer);
      expect(newId, greaterThan(0));

      // Verify in database via getCustomerById
      final inDb = await customerDao.getCustomerById(shopAlphaId, newId);
      expect(inDb, isNotNull);
      expect(inDb!.id, equals(newId));
      expect(inDb.shopId, equals(shopAlphaId));
      expect(inDb.fullName, equals('Nimal Perera'));
      expect(inDb.nic, equals('851234567V')); // normalized
      expect(inDb.phone, equals('+94 77 123 4567'));
      expect(inDb.address, equals('15 Main St, Colombo 11'));
      expect(inDb.photoUri, equals('/storage/photos/cust-1.jpg'));
      expect(inDb.photoHash, equals('hash123'));
    });

    test('createCustomer blocks duplicate NIC within same shop via unique constraint', () async {
      final now = DateTime.now().toUtc();
      final customer1 = Customer(
        id: 0,
        shopId: shopAlphaId,
        fullName: 'First Holder',
        nic: '851234567V',
        phone: '+94 77 111 1111',
        address: 'Address 1',
        createdAt: now,
        updatedAt: now,
      );
      await customerDao.createCustomer(customer1);

      final customer2 = Customer(
        id: 0,
        shopId: shopAlphaId,
        fullName: 'Duplicate Holder',
        nic: ' 851234567v ', // normalizes to same NIC
        phone: '+94 77 222 2222',
        address: 'Address 2',
        createdAt: now,
        updatedAt: now,
      );

      expect(
        () => customerDao.createCustomer(customer2),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test('createCustomer allows identical NIC in different shop tenant', () async {
      final now = DateTime.now().toUtc();
      final custAlpha = Customer(
        id: 0,
        shopId: shopAlphaId,
        fullName: 'Alpha Customer',
        nic: '851234567V',
        phone: '+94 77 111 1111',
        address: 'Address Alpha',
        createdAt: now,
        updatedAt: now,
      );
      final alphaId = await customerDao.createCustomer(custAlpha);

      final custBeta = Customer(
        id: 0,
        shopId: shopBetaId,
        fullName: 'Beta Customer',
        nic: '851234567V',
        phone: '+94 77 222 2222',
        address: 'Address Beta',
        createdAt: now,
        updatedAt: now,
      );
      final betaId = await customerDao.createCustomer(custBeta);

      final retrievedAlpha = await customerDao.getCustomerById(shopAlphaId, alphaId);
      final retrievedBeta = await customerDao.getCustomerById(shopBetaId, betaId);

      expect(retrievedAlpha, isNotNull);
      expect(retrievedBeta, isNotNull);
      expect(retrievedAlpha!.shopId, equals(shopAlphaId));
      expect(retrievedBeta!.shopId, equals(shopBetaId));
      expect(retrievedAlpha.nic, equals(retrievedBeta.nic));
    });

    test('getCustomerByNic normalizes input and respects shop boundary', () async {
      final now = DateTime.now().toUtc();
      final cust = Customer(
        id: 0,
        shopId: shopAlphaId,
        fullName: 'Alpha Person',
        nic: '851234567V',
        phone: '+94 77 333 3333',
        address: 'Address Alpha',
        createdAt: now,
        updatedAt: now,
      );
      await customerDao.createCustomer(cust);

      // Retrieve using lowercase and whitespace
      final found = await customerDao.getCustomerByNic(shopAlphaId, '  851234567v  ');
      expect(found, isNotNull);
      expect(found!.fullName, equals('Alpha Person'));

      // Look up same NIC in Beta shop -> returns null
      final notFoundInBeta = await customerDao.getCustomerByNic(shopBetaId, '851234567V');
      expect(notFoundInBeta, isNull);
    });

    test('getCustomerById returns null on cross-shop lookup', () async {
      final now = DateTime.now().toUtc();
      final custAlpha = Customer(
        id: 0,
        shopId: shopAlphaId,
        fullName: 'Alpha Person',
        nic: '901234567V',
        phone: '+94 77 444 4444',
        address: 'Address Alpha',
        createdAt: now,
        updatedAt: now,
      );
      final alphaId = await customerDao.createCustomer(custAlpha);

      // Correct shop lookup
      final retrieved = await customerDao.getCustomerById(shopAlphaId, alphaId);
      expect(retrieved, isNotNull);
      expect(retrieved!.id, equals(alphaId));

      // Cross-shop lookup (requesting Alpha customer with Beta shopId)
      final crossShopRetrieved = await customerDao.getCustomerById(shopBetaId, alphaId);
      expect(crossShopRetrieved, isNull);
    });

    test('getCustomersByShopId returns only customers belonging to specified shop', () async {
      final now = DateTime.now().toUtc();
      await customerDao.createCustomer(
        Customer(
          id: 0,
          shopId: shopAlphaId,
          fullName: 'Kamal Alpha',
          nic: '801234567V',
          phone: '+94 77 555 5555',
          address: 'Address 1',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await customerDao.createCustomer(
        Customer(
          id: 0,
          shopId: shopAlphaId,
          fullName: 'Amal Alpha',
          nic: '811234567V',
          phone: '+94 77 666 6666',
          address: 'Address 2',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await customerDao.createCustomer(
        Customer(
          id: 0,
          shopId: shopBetaId,
          fullName: 'Sunil Beta',
          nic: '821234567V',
          phone: '+94 77 777 7777',
          address: 'Address 3',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final alphaCustomers = await customerDao.getCustomersByShopId(shopAlphaId);
      expect(alphaCustomers.length, equals(2));
      expect(alphaCustomers.map((c) => c.fullName), containsAll(['Amal Alpha', 'Kamal Alpha']));

      final betaCustomers = await customerDao.getCustomersByShopId(shopBetaId);
      expect(betaCustomers.length, equals(1));
      expect(betaCustomers.first.fullName, equals('Sunil Beta'));
    });

    test('searchCustomers filters by name, NIC, or phone within shop scope', () async {
      final now = DateTime.now().toUtc();
      await customerDao.createCustomer(
        Customer(
          id: 0,
          shopId: shopAlphaId,
          fullName: 'Sunil Weerasinghe',
          nic: '198512345678',
          phone: '+94 77 111 2222',
          address: 'Address 1',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await customerDao.createCustomer(
        Customer(
          id: 0,
          shopId: shopAlphaId,
          fullName: 'Sunil Fernando',
          nic: '199012345678',
          phone: '+94 77 333 4444',
          address: 'Address 2',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await customerDao.createCustomer(
        Customer(
          id: 0,
          shopId: shopAlphaId,
          fullName: 'Kanthi Perera',
          nic: '751234567V',
          phone: '+94 77 555 6666',
          address: 'Address 3',
          createdAt: now,
          updatedAt: now,
        ),
      );
      // Beta customer with same name "Sunil"
      await customerDao.createCustomer(
        Customer(
          id: 0,
          shopId: shopBetaId,
          fullName: 'Sunil Jayasuriya',
          nic: '198212345678',
          phone: '+94 77 777 8888',
          address: 'Address Beta',
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Search by partial name "sunil" in Alpha
      final searchByName = await customerDao.searchCustomers(shopAlphaId, 'sunil');
      expect(searchByName.length, equals(2));
      expect(searchByName.every((c) => c.shopId == shopAlphaId), isTrue);

      // Search by partial NIC "7512" in Alpha
      final searchByNic = await customerDao.searchCustomers(shopAlphaId, '7512');
      expect(searchByNic.length, equals(1));
      expect(searchByNic.first.fullName, equals('Kanthi Perera'));

      // Search by partial phone "555 6666" in Alpha
      final searchByPhone = await customerDao.searchCustomers(shopAlphaId, '555 6666');
      expect(searchByPhone.length, equals(1));
      expect(searchByPhone.first.fullName, equals('Kanthi Perera'));

      // Search with empty query returns all
      final searchEmpty = await customerDao.searchCustomers(shopAlphaId, '');
      expect(searchEmpty.length, equals(3));
    });

    test('updateCustomer modifies profile and enforces shop scope and unique constraint', () async {
      final now = DateTime.now().toUtc();
      final customer = Customer(
        id: 0,
        shopId: shopAlphaId,
        fullName: 'Original Customer',
        nic: '851234567V',
        phone: '+94 77 000 0000',
        address: 'Old Address',
        createdAt: now,
        updatedAt: now,
      );
      final newId = await customerDao.createCustomer(customer);
      final persisted = await customerDao.getCustomerById(shopAlphaId, newId);

      final updatedCustomer = persisted!.copyWith(
        fullName: 'Modified Customer',
        nic: '198512345678',
        phone: '+94 77 111 1111',
        address: '45 Lotus Rd, Colombo 01',
        photoUri: '/photos/new.jpg',
        photoHash: 'hash-updated',
      );

      await customerDao.updateCustomer(updatedCustomer);

      final retrieved = await customerDao.getCustomerById(shopAlphaId, newId);
      expect(retrieved, isNotNull);
      expect(retrieved!.fullName, equals('Modified Customer'));
      expect(retrieved.nic, equals('198512345678'));
      expect(retrieved.phone, equals('+94 77 111 1111'));
      expect(retrieved.address, equals('45 Lotus Rd, Colombo 01'));
      expect(retrieved.photoUri, equals('/photos/new.jpg'));
      expect(retrieved.photoHash, equals('hash-updated'));

      // Verify cross-shop update throws StateError
      final crossShopAttempt = updatedCustomer.copyWith(shopId: shopBetaId);
      expect(
        () => customerDao.updateCustomer(crossShopAttempt),
        throwsA(isA<StateError>()),
      );
    });

    test('updateCustomer rejects duplicate NIC within same shop', () async {
      final now = DateTime.now().toUtc();
      final cust1 = Customer(
        id: 0,
        shopId: shopAlphaId,
        fullName: 'Customer One',
        nic: '851234567V',
        phone: '+94 77 111 1111',
        address: 'Address 1',
        createdAt: now,
        updatedAt: now,
      );
      await customerDao.createCustomer(cust1);

      final cust2 = Customer(
        id: 0,
        shopId: shopAlphaId,
        fullName: 'Customer Two',
        nic: '901234567V',
        phone: '+94 77 222 2222',
        address: 'Address 2',
        createdAt: now,
        updatedAt: now,
      );
      final cust2Id = await customerDao.createCustomer(cust2);
      final persistedCust2 = (await customerDao.getCustomerById(shopAlphaId, cust2Id))!;

      // Attempting to update cust2's NIC to cust1's NIC
      final duplicateAttempt = persistedCust2.copyWith(nic: '851234567V');
      expect(
        () => customerDao.updateCustomer(duplicateAttempt),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test('createCustomer fails with SqliteException when shopId does not exist in shops (foreign key constraint)', () async {
      final now = DateTime.now().toUtc();
      final orphanCustomer = Customer(
        id: 0,
        shopId: 'nonexistent-shop-uuid',
        fullName: 'Orphan Borrower',
        nic: '851234567V',
        phone: '+94 77 888 9999',
        address: 'Unknown Street',
        createdAt: now,
        updatedAt: now,
      );

      expect(
        () => customerDao.createCustomer(orphanCustomer),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test('updateCustomer preserves immutable identity and does not modify id or shopId or createdAt', () async {
      final creationTime = DateTime.utc(2026, 1, 15, 10, 30);
      final original = Customer(
        id: 0,
        shopId: shopAlphaId,
        fullName: 'Original Name',
        nic: '851234567V',
        phone: '+94 77 000 1111',
        address: '10 Flower Rd, Colombo 07',
        createdAt: creationTime,
        updatedAt: creationTime,
      );
      final newId = await customerDao.createCustomer(original);
      final persisted = (await customerDao.getCustomerById(shopAlphaId, newId))!;

      // Update fields with a modified customer object
      final modified = persisted.copyWith(
        fullName: 'New Name',
        phone: '+94 77 999 8888',
        address: '20 Flower Rd, Colombo 07',
      );
      await customerDao.updateCustomer(modified);

      final retrieved = await customerDao.getCustomerById(shopAlphaId, newId);
      expect(retrieved, isNotNull);
      expect(retrieved!.id, equals(newId));
      expect(retrieved.shopId, equals(shopAlphaId));
      expect(retrieved.fullName, equals('New Name'));
      expect(retrieved.phone, equals('+94 77 999 8888'));
      expect(retrieved.address, equals('20 Flower Rd, Colombo 07'));
      expect(retrieved.createdAt, equals(creationTime));
      expect(retrieved.updatedAt.isAfter(creationTime), isTrue);
    });
  });

  group('CustomerDao - Duplicate Detection (Story 2.4)', () {
    test('findCustomersByPhone finds existing customer with equivalent normalized phone', () async {
      final now = DateTime.now().toUtc();
      final newId = await customerDao.createCustomer(
        Customer(
          id: 0,
          shopId: shopAlphaId,
          fullName: 'Shared Phone User',
          nic: '851234567V',
          phone: '0771234567',
          address: '1 Main St',
          createdAt: now,
          updatedAt: now,
        ),
      );

      // International format of the same number must match
      final matches = await customerDao.findCustomersByPhone(shopAlphaId, '+94771234567');
      expect(matches.length, equals(1));
      expect(matches.first.id, equals(newId));
    });

    test('findCustomersByPhone returns empty when no phone match in shop', () async {
      final now = DateTime.now().toUtc();
      await customerDao.createCustomer(
        Customer(
          id: 0,
          shopId: shopAlphaId,
          fullName: 'Different Phone',
          nic: '901234567V',
          phone: '0771112222',
          address: '1 Main St',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final matches = await customerDao.findCustomersByPhone(shopAlphaId, '+94771234567');
      expect(matches, isEmpty);
    });

    test('findCustomersByPhone is strictly shop-scoped — no cross-shop leakage', () async {
      final now = DateTime.now().toUtc();
      // Same normalized phone in two different shops
      final alphaId = await customerDao.createCustomer(
        Customer(
          id: 0,
          shopId: shopAlphaId,
          fullName: 'Alpha Customer',
          nic: '851234567V',
          phone: '0771234567',
          address: '1 Main St',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final betaId = await customerDao.createCustomer(
        Customer(
          id: 0,
          shopId: shopBetaId,
          fullName: 'Beta Customer',
          nic: '901234567V',
          phone: '+94771234567',
          address: '1 Main St',
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Querying Alpha must return only Alpha's customer, not Beta's
      final alphaMatches = await customerDao.findCustomersByPhone(shopAlphaId, '0771234567');
      expect(alphaMatches.length, equals(1));
      expect(alphaMatches.first.id, equals(alphaId));

      // Querying Beta must return only Beta's customer, not Alpha's
      final betaMatches = await customerDao.findCustomersByPhone(shopBetaId, '+94771234567');
      expect(betaMatches.length, equals(1));
      expect(betaMatches.first.id, equals(betaId));
    });

    test('findCustomersByPhone returns all customers sharing a phone in the same shop', () async {
      final now = DateTime.now().toUtc();
      final sharedAId = await customerDao.createCustomer(
        Customer(
          id: 0,
          shopId: shopAlphaId,
          fullName: 'Family Member A',
          nic: '851234567V',
          phone: '0771234567',
          address: '1 Main St',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final sharedBId = await customerDao.createCustomer(
        Customer(
          id: 0,
          shopId: shopAlphaId,
          fullName: 'Family Member B',
          nic: '901234567V',
          phone: '+94771234567',
          address: '1 Main St',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final matches = await customerDao.findCustomersByPhone(shopAlphaId, '0771234567');
      expect(matches.length, equals(2));
      expect(matches.map((c) => c.id), containsAll([sharedAId, sharedBId]));
    });

    test('getCustomerByNic blocks duplicate NIC within same shop', () async {
      final now = DateTime.now().toUtc();
      final nicOwnerId = await customerDao.createCustomer(
        Customer(
          id: 0,
          shopId: shopAlphaId,
          fullName: 'NIC Owner',
          nic: '851234567V',
          phone: '0771111111',
          address: '1 Main St',
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Same NIC, different formatting — must be found
      final found = await customerDao.getCustomerByNic(shopAlphaId, ' 851234567v ');
      expect(found, isNotNull);
      expect(found!.id, equals(nicOwnerId));

      // Same NIC in different shop — must not be found
      final notFound = await customerDao.getCustomerByNic(shopBetaId, '851234567V');
      expect(notFound, isNull);
    });
  });
}
