import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/core/permissions/authorization_guard.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_dao.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_discrepancy_dao.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_custody_event.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';

void main() {
  late AppDatabase db;
  late CollateralDao collateralDao;
  late CollateralDiscrepancyDao discrepancyDao;
  late AppUser cashier;

  const shopId = 'shop-uuid-collateral';
  const customerId = 1;
  const creditId = 'credit-uuid-collateral';

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);
    collateralDao = CollateralDao(db);
    discrepancyDao = CollateralDiscrepancyDao(db);

    final now = DateTime.now().toUtc();
    // Seed shop, customer, and credit for FK constraints
    await db.into(db.shops).insert(
      ShopEntry(
        id: shopId,
        name: 'Collateral Test Shop',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.customers).insert(
      CustomerEntry(
        id: customerId,
        shopId: shopId,
        fullName: 'Test Customer',
        nic: '851234567V',
        phone: '0771234567',
        address: '1 Test Street',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.credits).insert(
      CreditEntry(
        id: creditId,
        shopId: shopId,
        customerId: customerId,
        principalCents: 100000,
        balanceCents: 100000,
        status: 'active',
        workflowStatus: CreditWorkflowStatus.pendingDisbursement.value,
        dueDate: now.add(const Duration(days: 30)),
        createdAt: now,
        correctionPending: false,
      ),
    );
    // Seed staff/owner users for custody-transition authorization (FK target
    // of custody events and required by transitionCustody).
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: 'user-cashier',
        shopId: shopId,
        username: 'cashier',
        fullName: 'Counter Cashier',
        role: 'cashier',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: 'user-owner',
        shopId: shopId,
        username: 'owner',
        fullName: 'Shop Owner',
        role: 'shop_owner',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
    cashier = AppUser(
      id: 'user-cashier',
      shopId: shopId,
      username: 'cashier',
      fullName: 'Counter Cashier',
      role: AppRole.cashier,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('CollateralDao - Local CRUD & Persistence', () {
    test('createCollateralItem inserts record and returns domain entity on query', () async {
      final now = DateTime.now().toUtc();
      final item = CollateralItem(
        id: 'coll-dao-001',
        shopId: shopId,
        customerId: customerId,
        creditId: creditId,
        itemReferenceId: 'COLL-DAO-001',
        category: CollateralItemCategory.gold,
        description: '22K gold necklace with pendant',
        conditionGrade: 'Like New',
        weightMilligrams: 5500,
        estimatedValueCents: 1500000,
        photoUri: '/photos/coll-001.jpg',
        photoHash: 'sha256hash123',
        createdAt: now,
        updatedAt: now,
      );

      await collateralDao.createCollateralItem(item);

      final inDb = await collateralDao.getCollateralItemById(shopId, item.id);
      expect(inDb, isNotNull);
      expect(inDb!.id, equals('coll-dao-001'));
      expect(inDb.shopId, equals(shopId));
      expect(inDb.customerId, equals(customerId));
      expect(inDb.creditId, equals(creditId));
      expect(inDb.itemReferenceId, equals('COLL-DAO-001'));
      expect(inDb.category, equals(CollateralItemCategory.gold));
      expect(inDb.description, equals('22K gold necklace with pendant'));
      expect(inDb.conditionGrade, equals('Like New'));
      expect(inDb.weightMilligrams, equals(5500));
      expect(inDb.estimatedValueCents, equals(1500000));
      expect(inDb.estimatedValue, equals(Money.fromCents(1500000)));
      expect(inDb.photoUri, equals('/photos/coll-001.jpg'));
      expect(inDb.photoHash, equals('sha256hash123'));
      expect(inDb.custodyStatus, equals(CollateralCustodyStatus.inCustody));
    });

    test('createCollateralItem without creditId stores nullable credit reference', () async {
      final item = CollateralItem(
        id: 'coll-dao-002',
        shopId: shopId,
        customerId: customerId,
        creditId: null,
        itemReferenceId: 'COLL-DAO-002',
        category: CollateralItemCategory.electronics,
        description: 'Samsung Galaxy S21',
        conditionGrade: 'Good',
        weightMilligrams: 180000,
        estimatedValueCents: 450000,
      );

      await collateralDao.createCollateralItem(item);

      final inDb = await collateralDao.getCollateralItemById(shopId, item.id);
      expect(inDb, isNotNull);
      expect(inDb!.creditId, isNull);
    });

    test('getCollateralItemByReference finds item by reference ID', () async {
      final item = CollateralItem(
        id: 'coll-dao-003',
        shopId: shopId,
        customerId: customerId,
        itemReferenceId: 'COLL-DAO-003',
        category: CollateralItemCategory.valuables,
        description: 'Diamond earrings',
        conditionGrade: 'Excellent',
        weightMilligrams: 2000,
        estimatedValueCents: 3000000,
      );
      await collateralDao.createCollateralItem(item);

      final found = await collateralDao.getCollateralItemByReference(shopId, 'COLL-DAO-003');
      expect(found, isNotNull);
      expect(found!.id, equals('coll-dao-003'));
    });

    test('getCollateralItemByReference returns null for wrong shop', () async {
      const otherShopId = 'shop-other';
      await db.into(db.shops).insert(
        ShopEntry(
          id: otherShopId,
          name: 'Other Shop',
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      );

      final item = CollateralItem(
        id: 'coll-dao-004',
        shopId: shopId,
        customerId: customerId,
        itemReferenceId: 'COLL-DAO-004',
        category: CollateralItemCategory.gold,
        description: 'Test item',
        conditionGrade: 'Good',
        weightMilligrams: 1000,
        estimatedValueCents: 100000,
      );
      await collateralDao.createCollateralItem(item);

      final found = await collateralDao.getCollateralItemByReference(otherShopId, 'COLL-DAO-004');
      expect(found, isNull);
    });

    test('getCollateralItemsByCustomerId returns only items for that customer', () async {
      const otherCustomerId = 2;
      final now = DateTime.now().toUtc();
      // Seed the other customer first to satisfy FK constraint
      await db.into(db.customers).insert(
        CustomerEntry(
          id: otherCustomerId,
          shopId: shopId,
          fullName: 'Other Customer',
          nic: '199012345678',
          phone: '0712345678',
          address: 'Other Address',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await collateralDao.createCollateralItem(CollateralItem(
        id: 'coll-dao-005',
        shopId: shopId,
        customerId: customerId,
        itemReferenceId: 'COLL-DAO-005',
        category: CollateralItemCategory.gold,
        description: 'Item 1',
        conditionGrade: 'Good',
        weightMilligrams: 1000,
        estimatedValueCents: 100000,
        createdAt: now,
        updatedAt: now,
      ));
      await collateralDao.createCollateralItem(CollateralItem(
        id: 'coll-dao-006',
        shopId: shopId,
        customerId: customerId,
        itemReferenceId: 'COLL-DAO-006',
        category: CollateralItemCategory.electronics,
        description: 'Item 2',
        conditionGrade: 'Fair',
        weightMilligrams: 2000,
        estimatedValueCents: 200000,
        createdAt: now,
        updatedAt: now,
      ));

      await collateralDao.createCollateralItem(CollateralItem(
        id: 'coll-dao-007',
        shopId: shopId,
        customerId: otherCustomerId,
        itemReferenceId: 'COLL-DAO-007',
        category: CollateralItemCategory.valuables,
        description: 'Other customer item',
        conditionGrade: 'Good',
        weightMilligrams: 3000,
        estimatedValueCents: 300000,
        createdAt: now,
        updatedAt: now,
      ));

      final items = await collateralDao.getCollateralItemsByCustomerId(shopId, customerId);
      expect(items.length, equals(2));
      expect(items.every((i) => i.customerId == customerId), isTrue);
    });

    test('getCollateralItemsByCustodyStatus filters by custody', () async {
      final now = DateTime.now().toUtc();
      await collateralDao.createCollateralItem(CollateralItem(
        id: 'coll-dao-008',
        shopId: shopId,
        customerId: customerId,
        itemReferenceId: 'COLL-DAO-008',
        category: CollateralItemCategory.gold,
        description: 'In custody item',
        conditionGrade: 'Good',
        weightMilligrams: 1000,
        estimatedValueCents: 100000,
        custodyStatus: CollateralCustodyStatus.inCustody,
        createdAt: now,
        updatedAt: now,
      ));
      await collateralDao.createCollateralItem(CollateralItem(
        id: 'coll-dao-009',
        shopId: shopId,
        customerId: customerId,
        itemReferenceId: 'COLL-DAO-009',
        category: CollateralItemCategory.gold,
        description: 'Returned item',
        conditionGrade: 'Good',
        weightMilligrams: 1000,
        estimatedValueCents: 100000,
        custodyStatus: CollateralCustodyStatus.returned,
        createdAt: now,
        updatedAt: now,
      ));

      final inCustody = await collateralDao.getCollateralItemsByCustodyStatus(
        shopId, CollateralCustodyStatus.inCustody);
      expect(inCustody.length, equals(1));
      expect(inCustody.first.itemReferenceId, equals('COLL-DAO-008'));

      final returned = await collateralDao.getCollateralItemsByCustodyStatus(
        shopId, CollateralCustodyStatus.returned);
      expect(returned.length, equals(1));
      expect(returned.first.itemReferenceId, equals('COLL-DAO-009'));
    });

    test('getCollateralItemsByCreditId returns items bound to a credit', () async {
      await collateralDao.createCollateralItem(CollateralItem(
        id: 'coll-dao-010',
        shopId: shopId,
        customerId: customerId,
        creditId: creditId,
        itemReferenceId: 'COLL-DAO-010',
        category: CollateralItemCategory.gold,
        description: 'Credit collateral',
        conditionGrade: 'Good',
        weightMilligrams: 1000,
        estimatedValueCents: 100000,
      ));
      await collateralDao.createCollateralItem(CollateralItem(
        id: 'coll-dao-011',
        shopId: shopId,
        customerId: customerId,
        creditId: null,
        itemReferenceId: 'COLL-DAO-011',
        category: CollateralItemCategory.electronics,
        description: 'Unbound item',
        conditionGrade: 'Good',
        weightMilligrams: 1000,
        estimatedValueCents: 100000,
      ));

      final creditItems = await collateralDao.getCollateralItemsByCreditId(shopId, creditId);
      expect(creditItems.length, equals(1));
      expect(creditItems.first.itemReferenceId, equals('COLL-DAO-010'));

      final unbound = await collateralDao.getUnboundCollateralItems(shopId);
      expect(unbound.length, equals(1));
      expect(unbound.first.itemReferenceId, equals('COLL-DAO-011'));
    });

    test('updateCollateralItem updates fields and preserves identity', () async {
      final now = DateTime.now().toUtc();
      final item = CollateralItem(
        id: 'coll-dao-012',
        shopId: shopId,
        customerId: customerId,
        itemReferenceId: 'COLL-DAO-012',
        category: CollateralItemCategory.gold,
        description: 'Original description',
        conditionGrade: 'Good',
        weightMilligrams: 1000,
        estimatedValueCents: 100000,
        createdAt: now,
        updatedAt: now,
      );
      await collateralDao.createCollateralItem(item);

      final updated = item.copyWith(
        description: 'Updated description',
        conditionGrade: 'Like New',
        weightMilligrams: 1500,
        estimatedValueCents: 150000,
      );
      await collateralDao.updateCollateralItem(updated);

      final inDb = await collateralDao.getCollateralItemById(shopId, item.id);
      expect(inDb!.description, equals('Updated description'));
      expect(inDb.conditionGrade, equals('Like New'));
      expect(inDb.weightMilligrams, equals(1500));
      expect(inDb.estimatedValueCents, equals(150000));
      expect(inDb.itemReferenceId, equals('COLL-DAO-012')); // unchanged
      expect(inDb.customerId, equals(customerId)); // unchanged
    });

    test('updateCollateralItem throws StateError for non-existent item', () async {
      final item = CollateralItem(
        id: 'coll-dao-nonexistent',
        shopId: shopId,
        customerId: customerId,
        itemReferenceId: 'COLL-DAO-NONEXISTENT',
        category: CollateralItemCategory.gold,
        description: 'Test',
        conditionGrade: 'Good',
        weightMilligrams: 1000,
        estimatedValueCents: 100000,
      );

      expect(
        () => collateralDao.updateCollateralItem(item),
        throwsA(isA<StateError>()),
      );
    });

    test('transitionCustody rejects direct inCustody → returned (handover flow required)', () async {
      final item = CollateralItem(
        id: 'coll-dao-013',
        shopId: shopId,
        customerId: customerId,
        itemReferenceId: 'COLL-DAO-013',
        category: CollateralItemCategory.gold,
        description: 'Test item',
        conditionGrade: 'Good',
        weightMilligrams: 1000,
        estimatedValueCents: 100000,
        custodyStatus: CollateralCustodyStatus.inCustody,
      );
      await collateralDao.createCollateralItem(item);

      expect(
        () => collateralDao.transitionCustody(
          shopId, item.id, CollateralCustodyStatus.returned,
          actor: cashier,
          requiredPermission: AppPermission.createCredits),
        throwsA(isA<CollateralCustodyTransitionException>()),
      );
      final inDb = await collateralDao.getCollateralItemById(shopId, item.id);
      expect(inDb!.custodyStatus, equals(CollateralCustodyStatus.inCustody));
    });

    test('transitionCustody allows inCustody → exceptionHeld per FSM (owner-only enforcement via closeCollateralException)', () async {
      final item = CollateralItem(
        id: 'coll-dao-014',
        shopId: shopId,
        customerId: customerId,
        itemReferenceId: 'COLL-DAO-014',
        category: CollateralItemCategory.gold,
        description: 'Test item',
        conditionGrade: 'Good',
        weightMilligrams: 1000,
        estimatedValueCents: 100000,
        custodyStatus: CollateralCustodyStatus.inCustody,
      );
      await collateralDao.createCollateralItem(item);

      // FSM now permits inCustody → exceptionHeld. Owner-only enforcement is
      // enforced by closeCollateralException, not by transitionCustody itself.
      await collateralDao.transitionCustody(
        shopId, item.id, CollateralCustodyStatus.exceptionHeld,
        actor: cashier,
        requiredPermission: AppPermission.createCredits,
      );
      final inDb = await collateralDao.getCollateralItemById(shopId, item.id);
      expect(inDb!.custodyStatus, equals(CollateralCustodyStatus.exceptionHeld));
    });

    test('transitionCustody throws on invalid transition', () async {
      final item = CollateralItem(
        id: 'coll-dao-015',
        shopId: shopId,
        customerId: customerId,
        itemReferenceId: 'COLL-DAO-015',
        category: CollateralItemCategory.gold,
        description: 'Test item',
        conditionGrade: 'Good',
        weightMilligrams: 1000,
        estimatedValueCents: 100000,
        custodyStatus: CollateralCustodyStatus.returned,
      );
      await collateralDao.createCollateralItem(item);

      expect(
        () => collateralDao.transitionCustody(
          shopId, item.id, CollateralCustodyStatus.inCustody,
          actor: cashier,
          requiredPermission: AppPermission.createCredits),
        throwsA(isA<CollateralCustodyTransitionException>()),
      );
    });

    test('transitionCustody throws StateError for non-existent item', () async {
      expect(
        () => collateralDao.transitionCustody(
          shopId, 'coll-dao-nonexistent', CollateralCustodyStatus.returned,
          actor: cashier,
          requiredPermission: AppPermission.createCredits),
        throwsA(isA<StateError>()),
      );
    });

    test('associateWithCredit binds item to a credit', () async {
      const unboundCreditId = 'credit-uuid-unbound';
      await db.into(db.credits).insert(
        CreditEntry(
          id: unboundCreditId,
          shopId: shopId,
          customerId: customerId,
          principalCents: 50000,
          balanceCents: 50000,
          status: 'active',
          workflowStatus: CreditWorkflowStatus.pendingDisbursement.value,
          dueDate: DateTime.now().toUtc().add(const Duration(days: 60)),
          createdAt: DateTime.now().toUtc(),
          correctionPending: false,
        ),
      );

      final item = CollateralItem(
        id: 'coll-dao-016',
        shopId: shopId,
        customerId: customerId,
        creditId: null,
        itemReferenceId: 'COLL-DAO-016',
        category: CollateralItemCategory.gold,
        description: 'Unbound item',
        conditionGrade: 'Good',
        weightMilligrams: 1000,
        estimatedValueCents: 100000,
      );
      await collateralDao.createCollateralItem(item);

      await collateralDao.associateWithCredit(shopId, item.id, unboundCreditId);

      final inDb = await collateralDao.getCollateralItemById(shopId, item.id);
      expect(inDb!.creditId, equals(unboundCreditId));
    });

    test('insert with invalid customer FK throws', () async {
      final item = CollateralItem(
        id: 'coll-dao-017',
        shopId: shopId,
        customerId: 999, // no such customer row; FK must reject the insert
        itemReferenceId: 'COLL-DAO-017',
        category: CollateralItemCategory.gold,
        description: 'Test',
        conditionGrade: 'Good',
        weightMilligrams: 1000,
        estimatedValueCents: 100000,
      );

      expect(
        () => collateralDao.createCollateralItem(item),
        throwsA(isA<Exception>()),
      );
    });

    test('insert with invalid credit FK throws', () async {
      final item = CollateralItem(
        id: 'coll-dao-018',
        shopId: shopId,
        customerId: customerId,
        creditId: 'nonexistent-credit',
        itemReferenceId: 'COLL-DAO-018',
        category: CollateralItemCategory.gold,
        description: 'Test',
        conditionGrade: 'Good',
        weightMilligrams: 1000,
        estimatedValueCents: 100000,
      );

      expect(
        () => collateralDao.createCollateralItem(item),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('CollateralDao - Story 3.4 Per-Item Custody State Machine', () {
    late AppUser cashier;
    late AppUser owner;

    setUp(() async {
      // Each Story 3.4 test gets a fresh in-memory database so the app_users
      // seed below does not collide with the original group's database.
      final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
      db = AppDatabase.forTesting(inMemoryExecutor);
      collateralDao = CollateralDao(db);
      discrepancyDao = CollateralDiscrepancyDao(db);
      final now = DateTime.now().toUtc();
      // Seed shop, customer, and credit for FK constraints
      await db.into(db.shops).insert(
        ShopEntry(
          id: shopId,
          name: 'Story 3.4 Test Shop',
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db.into(db.customers).insert(
        CustomerEntry(
          id: customerId,
          shopId: shopId,
          fullName: 'Story 3.4 Customer',
          nic: '851234567V',
          phone: '0771234567',
          address: '1 Story 3.4 Street',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db.into(db.credits).insert(
        CreditEntry(
          id: creditId,
          shopId: shopId,
          customerId: customerId,
          principalCents: 100000,
          balanceCents: 100000,
          status: 'active',
          workflowStatus: CreditWorkflowStatus.pendingDisbursement.value,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
          correctionPending: false,
        ),
      );
      await db.into(db.appUsers).insert(
        AppUserEntry(
          id: 'user-cashier',
          shopId: shopId,
          username: 'cashier',
          fullName: 'Counter Cashier',
          role: 'cashier',
          isActive: true,
          sessionVersion: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db.into(db.appUsers).insert(
        AppUserEntry(
          id: 'user-owner',
          shopId: shopId,
          username: 'owner',
          fullName: 'Shop Owner',
          role: 'shop_owner',
          isActive: true,
          sessionVersion: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );
      cashier = AppUser(
        id: 'user-cashier',
        shopId: shopId,
        username: 'cashier',
        fullName: 'Counter Cashier',
        role: AppRole.cashier,
      );
      owner = AppUser(
        id: 'user-owner',
        shopId: shopId,
        username: 'owner',
        fullName: 'Shop Owner',
        role: AppRole.shopOwner,
      );
    });

    Future<CollateralItem> createItemInCustody({
      String itemId = 'coll-s34-001',
      String itemReferenceId = 'COLL-S34-001',
      String? creditId,
    }) async {
      final item = CollateralItem(
        id: itemId,
        shopId: shopId,
        customerId: customerId,
        creditId: creditId,
        itemReferenceId: itemReferenceId,
        category: CollateralItemCategory.gold,
        description: '22K gold necklace',
        conditionGrade: 'Like New',
        weightMilligrams: 5500,
        estimatedValueCents: 1500000,
      );
      await collateralDao.createCollateralItem(item);
      return item;
    }

    test('transitionCustody completes the full handover flow and records custody events', () async {
      final item = await createItemInCustody(creditId: creditId);

      await collateralDao.transitionCustody(
        shopId, item.id, CollateralCustodyStatus.handoverRequested,
        reportedByUserId: cashier.id,
        reason: 'Customer settled the credit, collecting item',
        actor: cashier,
        requiredPermission: AppPermission.createCredits,
      );
      expect(
        (await collateralDao.getCollateralItemById(shopId, item.id))!.custodyStatus,
        equals(CollateralCustodyStatus.handoverRequested),
      );

      await collateralDao.transitionCustody(
        shopId, item.id, CollateralCustodyStatus.handoverReported,
        reportedByUserId: cashier.id,
        reason: 'Physical handover reported at counter',
        actor: cashier,
        requiredPermission: AppPermission.createCredits,
      );
      expect(
        (await collateralDao.getCollateralItemById(shopId, item.id))!.custodyStatus,
        equals(CollateralCustodyStatus.handoverReported),
      );

      await collateralDao.transitionCustody(
        shopId, item.id, CollateralCustodyStatus.returned,
        reportedByUserId: owner.id,
        reason: 'Shop Owner confirmed physical return',
        actor: owner,
        requiredPermission: AppPermission.confirmCollateralReturn,
      );
      final inDb = await collateralDao.getCollateralItemById(shopId, item.id);
      expect(inDb!.custodyStatus, equals(CollateralCustodyStatus.returned));

      // Custody event trail is preserved (not overwritten)
      final events = await collateralDao.getCustodyEventsByCollateralItemId(
        shopId, item.id,
      );
      expect(events.length, equals(3));
      expect(events[0].previousStatus, equals(CollateralCustodyStatus.inCustody));
      expect(events[0].newStatus, equals(CollateralCustodyStatus.handoverRequested));
      expect(events[0].reportedByUserId, equals(cashier.id));
      expect(events[1].previousStatus, equals(CollateralCustodyStatus.handoverRequested));
      expect(events[1].newStatus, equals(CollateralCustodyStatus.handoverReported));
      expect(events[2].previousStatus, equals(CollateralCustodyStatus.handoverReported));
      expect(events[2].newStatus, equals(CollateralCustodyStatus.returned));
      expect(events[2].reportedByUserId, equals(owner.id));
    });

    test('transitionCustody rejects transition out of terminal returned state', () async {
      final item = await createItemInCustody();
      // Reach the terminal state through the valid handover flow
      await collateralDao.transitionCustody(
        shopId, item.id, CollateralCustodyStatus.handoverRequested,
        reportedByUserId: cashier.id,
        reason: 'request',
        actor: cashier,
        requiredPermission: AppPermission.createCredits,
      );
      await collateralDao.transitionCustody(
        shopId, item.id, CollateralCustodyStatus.handoverReported,
        reportedByUserId: cashier.id,
        reason: 'reported',
        actor: cashier,
        requiredPermission: AppPermission.createCredits,
      );
      await collateralDao.transitionCustody(
        shopId, item.id, CollateralCustodyStatus.returned,
        reportedByUserId: owner.id,
        reason: 'confirmed',
        actor: owner,
        requiredPermission: AppPermission.confirmCollateralReturn,
      );

      expect(
        () => collateralDao.transitionCustody(
          shopId, item.id, CollateralCustodyStatus.inCustody,
          reportedByUserId: owner.id,
          reason: 'should fail',
          actor: owner,
          requiredPermission: AppPermission.confirmCollateralReturn,
        ),
        throwsA(isA<CollateralCustodyTransitionException>()),
      );
      final inDb = await collateralDao.getCollateralItemById(shopId, item.id);
      expect(inDb!.custodyStatus, equals(CollateralCustodyStatus.returned));
    });

    test('transitionCustody enforces owner-only confirmation permission at the operation layer', () async {
      final item = await createItemInCustody();
      await collateralDao.transitionCustody(
        shopId, item.id, CollateralCustodyStatus.handoverRequested,
        reportedByUserId: cashier.id,
        reason: 'request',
        actor: cashier,
        requiredPermission: AppPermission.createCredits,
      );
      await collateralDao.transitionCustody(
        shopId, item.id, CollateralCustodyStatus.handoverReported,
        reportedByUserId: cashier.id,
        reason: 'reported',
        actor: cashier,
        requiredPermission: AppPermission.createCredits,
      );

      // Cashier lacks confirmCollateralReturn: must be rejected even though
      // the state transition itself is valid.
      expect(
        () => collateralDao.transitionCustody(
          shopId, item.id, CollateralCustodyStatus.returned,
          reportedByUserId: cashier.id,
          reason: 'unauthorized confirm',
          actor: cashier,
          requiredPermission: AppPermission.confirmCollateralReturn,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      final inDb = await collateralDao.getCollateralItemById(shopId, item.id);
      expect(inDb!.custodyStatus, equals(CollateralCustodyStatus.handoverReported));
    });

    test('per-item independence: transitioning one item does not affect sibling items on the same credit', () async {
      final itemA = await createItemInCustody(
        itemId: 'coll-s34-a', itemReferenceId: 'COLL-S34-A', creditId: creditId,
      );
      final itemB = await createItemInCustody(
        itemId: 'coll-s34-b', itemReferenceId: 'COLL-S34-B', creditId: creditId,
      );

      await collateralDao.transitionCustody(
        shopId, itemA.id, CollateralCustodyStatus.handoverRequested,
        reportedByUserId: cashier.id,
        reason: 'item A return requested',
        actor: cashier,
        requiredPermission: AppPermission.createCredits,
      );
      await collateralDao.transitionCustody(
        shopId, itemA.id, CollateralCustodyStatus.handoverReported,
        reportedByUserId: cashier.id,
        reason: 'item A handover reported',
        actor: cashier,
        requiredPermission: AppPermission.createCredits,
      );

      expect(
        (await collateralDao.getCollateralItemById(shopId, itemA.id))!.custodyStatus,
        equals(CollateralCustodyStatus.handoverReported),
      );
      expect(
        (await collateralDao.getCollateralItemById(shopId, itemB.id))!.custodyStatus,
        equals(CollateralCustodyStatus.inCustody),
      );

      // Item B can proceed independently while A is reported (valid flow:
      // request, then report, then owner confirm)
      await collateralDao.transitionCustody(
        shopId, itemB.id, CollateralCustodyStatus.handoverRequested,
        reportedByUserId: owner.id,
        reason: 'item B requested',
        actor: owner,
        requiredPermission: AppPermission.createCredits,
      );
      await collateralDao.transitionCustody(
        shopId, itemB.id, CollateralCustodyStatus.handoverReported,
        reportedByUserId: owner.id,
        reason: 'item B reported',
        actor: owner,
        requiredPermission: AppPermission.createCredits,
      );
      await collateralDao.transitionCustody(
        shopId, itemB.id, CollateralCustodyStatus.returned,
        reportedByUserId: owner.id,
        reason: 'item B confirmed first',
        actor: owner,
        requiredPermission: AppPermission.confirmCollateralReturn,
      );
      expect(
        (await collateralDao.getCollateralItemById(shopId, itemB.id))!.custodyStatus,
        equals(CollateralCustodyStatus.returned),
      );
      expect(
        (await collateralDao.getCollateralItemById(shopId, itemA.id))!.custodyStatus,
        equals(CollateralCustodyStatus.handoverReported),
      );
    });

    test('duplicate return prevention: transitions on a returned item are rejected', () async {
      final item = await createItemInCustody();
      await collateralDao.transitionCustody(
        shopId, item.id, CollateralCustodyStatus.handoverRequested,
        reportedByUserId: cashier.id,
        reason: 'request',
        actor: cashier,
        requiredPermission: AppPermission.createCredits,
      );
      await collateralDao.transitionCustody(
        shopId, item.id, CollateralCustodyStatus.handoverReported,
        reportedByUserId: cashier.id,
        reason: 'reported',
        actor: cashier,
        requiredPermission: AppPermission.createCredits,
      );
      await collateralDao.transitionCustody(
        shopId, item.id, CollateralCustodyStatus.returned,
        reportedByUserId: owner.id,
        reason: 'confirmed',
        actor: owner,
        requiredPermission: AppPermission.confirmCollateralReturn,
      );

      // Any further transition on the terminal state is rejected
      expect(
        () => collateralDao.transitionCustody(
          shopId, item.id, CollateralCustodyStatus.handoverRequested,
          reportedByUserId: cashier.id,
          reason: 'double return',
          actor: cashier,
          requiredPermission: AppPermission.createCredits,
        ),
        throwsA(isA<CollateralCustodyTransitionException>()),
      );
    });

    test('reportDiscrepancy moves item to discrepancy and creates a pending discrepancy record', () async {
      final item = await createItemInCustody();

      await collateralDao.reportDiscrepancy(
        shopId, item.id, cashier.id,
        'System shows in custody but staff report item already handed over',
        actor: cashier,
        requiredPermission: AppPermission.createCredits,
      );

      final inDb = await collateralDao.getCollateralItemById(shopId, item.id);
      expect(inDb!.custodyStatus, equals(CollateralCustodyStatus.discrepancy));

      final discrepancies = await collateralDao.getDiscrepanciesByCollateralItemId(
        shopId, item.id,
      );
      expect(discrepancies.length, equals(1));
      expect(discrepancies.first.status, equals(CollateralDiscrepancyStatus.pending));
      expect(discrepancies.first.reportedByUserId, equals(cashier.id));
      expect(discrepancies.first.discrepancyReason,
          contains('already handed over'));
      expect(discrepancies.first.resolvedByUserId, isNull);

      // A custody event records the transition into discrepancy
      final events = await collateralDao.getCustodyEventsByCollateralItemId(
        shopId, item.id,
      );
      expect(events.any((e) => e.newStatus == CollateralCustodyStatus.discrepancy),
          isTrue);
    });

    test('resolveDiscrepancy lets the Shop Owner decide returned / inCustody / exceptionHeld', () async {
      final item = await createItemInCustody();
      await collateralDao.reportDiscrepancy(
        shopId, item.id, cashier.id,
        'Item reported damaged on return',
        actor: cashier,
        requiredPermission: AppPermission.createCredits,
      );
      final pending = (await collateralDao.getDiscrepanciesByCollateralItemId(
        shopId, item.id,
      )).first;

      await collateralDao.resolveDiscrepancy(
        shopId, pending.id, CollateralCustodyStatus.exceptionHeld,
        owner.id,
        'Item confirmed damaged; held for investigation',
        DateTime.now().toUtc(),
        actor: owner,
        requiredPermission: AppPermission.approveCorrections,
      );

      final inDb = await collateralDao.getCollateralItemById(shopId, item.id);
      expect(inDb!.custodyStatus, equals(CollateralCustodyStatus.exceptionHeld));

      final resolved = await discrepancyDao.getDiscrepancyById(shopId, pending.id);
      expect(resolved!.status, equals(CollateralDiscrepancyStatus.resolved));
      expect(resolved.resolvedByUserId, equals(owner.id));
      expect(resolved.resolutionNotes, contains('damaged'));
      expect(resolved.resolvedAt, isNotNull);
    });

    test('resolveDiscrepancy is rejected for staff without approveCorrections', () async {
      final item = await createItemInCustody();
      await collateralDao.reportDiscrepancy(
        shopId, item.id, cashier.id,
        'discrepancy reason',
        actor: cashier,
        requiredPermission: AppPermission.createCredits,
      );
      final pending = (await collateralDao.getDiscrepanciesByCollateralItemId(
        shopId, item.id,
      )).first;

      expect(
        () => collateralDao.resolveDiscrepancy(
          shopId, pending.id, CollateralCustodyStatus.inCustody,
          cashier.id,
          'staff override attempt',
          DateTime.now().toUtc(),
          actor: cashier,
          requiredPermission: AppPermission.approveCorrections,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      // Item must remain in discrepancy (unresolved, visible)
      expect(
        (await collateralDao.getCollateralItemById(shopId, item.id))!.custodyStatus,
        equals(CollateralCustodyStatus.discrepancy),
      );
    });

    test('getPendingCustodyTransitions lists handoverRequested and handoverReported items', () async {
      final itemA = await createItemInCustody(
        itemId: 'coll-s34-q', itemReferenceId: 'COLL-S34-Q',
      );
      final itemB = await createItemInCustody(
        itemId: 'coll-s34-r', itemReferenceId: 'COLL-S34-R',
      );
      await createItemInCustody(itemId: 'coll-s34-s', itemReferenceId: 'COLL-S34-S');

      await collateralDao.transitionCustody(
        shopId, itemA.id, CollateralCustodyStatus.handoverRequested,
        reportedByUserId: cashier.id,
        reason: 'q',
        actor: cashier,
        requiredPermission: AppPermission.createCredits,
      );
      await collateralDao.transitionCustody(
        shopId, itemB.id, CollateralCustodyStatus.handoverRequested,
        reportedByUserId: cashier.id,
        reason: 'r requested',
        actor: cashier,
        requiredPermission: AppPermission.createCredits,
      );
      await collateralDao.transitionCustody(
        shopId, itemB.id, CollateralCustodyStatus.handoverReported,
        reportedByUserId: cashier.id,
        reason: 'r reported',
        actor: cashier,
        requiredPermission: AppPermission.createCredits,
      );

      final pending = await collateralDao.getPendingCustodyTransitions(shopId);
      expect(pending.length, equals(2));
      expect(pending.any((i) => i.id == itemA.id), isTrue);
      expect(pending.any((i) => i.id == itemB.id), isTrue);
    });

    group('CollateralDao - Story 3.5 Item-Level Exception/Held', () {
      test('closeCollateralException moves inCustody → exceptionHeld and records custody event', () async {
        final item = await createItemInCustody();

        await collateralDao.closeCollateralException(
          shopId, item.id,
          actor: owner,
          reason: 'Police seizure; item cannot be physically returned',
        );

        final inDb = await collateralDao.getCollateralItemById(shopId, item.id);
        expect(inDb!.custodyStatus, equals(CollateralCustodyStatus.exceptionHeld));

        final events = await collateralDao.getCustodyEventsByCollateralItemId(
          shopId, item.id,
        );
        expect(events.length, equals(1));
        expect(events.first.previousStatus, equals(CollateralCustodyStatus.inCustody));
        expect(events.first.newStatus, equals(CollateralCustodyStatus.exceptionHeld));
        expect(events.first.reportedByUserId, equals(owner.id));
        expect(events.first.reason, contains('Police seizure'));
      });

      test('closeCollateralException rejects empty rationale', () async {
        final item = await createItemInCustody();

        expect(
          () => collateralDao.closeCollateralException(
            shopId, item.id,
            actor: owner,
            reason: '',
          ),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => collateralDao.closeCollateralException(
            shopId, item.id,
            actor: owner,
            reason: '   ',
          ),
          throwsA(isA<ArgumentError>()),
        );
        final inDb = await collateralDao.getCollateralItemById(shopId, item.id);
        expect(inDb!.custodyStatus, equals(CollateralCustodyStatus.inCustody));
      });

      test('closeCollateralException rejects cashier (not owner)', () async {
        final item = await createItemInCustody();

        expect(
          () => collateralDao.closeCollateralException(
            shopId, item.id,
            actor: cashier,
            reason: 'Cashier attempts exception hold',
          ),
          throwsA(isA<PermissionDeniedException>()),
        );
        final inDb = await collateralDao.getCollateralItemById(shopId, item.id);
        expect(inDb!.custodyStatus, equals(CollateralCustodyStatus.inCustody));
      });

      test('closeCollateralException rejects inactive owner', () async {
        final item = await createItemInCustody();
        final inactiveOwner = owner.copyWith(isActive: false);

        expect(
          () => collateralDao.closeCollateralException(
            shopId, item.id,
            actor: inactiveOwner,
            reason: 'Inactive owner attempt',
          ),
          throwsA(isA<PermissionDeniedException>()),
        );
        final inDb = await collateralDao.getCollateralItemById(shopId, item.id);
        expect(inDb!.custodyStatus, equals(CollateralCustodyStatus.inCustody));
      });

      test('closeCollateralException rejects wrong shop', () async {
        final item = await createItemInCustody();

        expect(
          () => collateralDao.closeCollateralException(
            'wrong-shop', item.id,
            actor: owner,
            reason: 'Wrong shop attempt',
          ),
          throwsA(isA<StateError>()),
        );
        final inDb = await collateralDao.getCollateralItemById(shopId, item.id);
        expect(inDb!.custodyStatus, equals(CollateralCustodyStatus.inCustody));
      });

      test('closeCollateralException rejects wrong item', () async {
        await createItemInCustody();

        expect(
          () => collateralDao.closeCollateralException(
            shopId, 'coll-nonexistent',
            actor: owner,
            reason: 'Wrong item attempt',
          ),
          throwsA(isA<StateError>()),
        );
      });

      test('closeCollateralException rejects terminal returned state', () async {
        final item = await createItemInCustody();
        await collateralDao.transitionCustody(
          shopId, item.id, CollateralCustodyStatus.handoverRequested,
          reportedByUserId: cashier.id,
          reason: 'request',
          actor: cashier,
          requiredPermission: AppPermission.createCredits,
        );
        await collateralDao.transitionCustody(
          shopId, item.id, CollateralCustodyStatus.handoverReported,
          reportedByUserId: cashier.id,
          reason: 'reported',
          actor: cashier,
          requiredPermission: AppPermission.createCredits,
        );
        await collateralDao.transitionCustody(
          shopId, item.id, CollateralCustodyStatus.returned,
          reportedByUserId: owner.id,
          reason: 'confirmed',
          actor: owner,
          requiredPermission: AppPermission.confirmCollateralReturn,
        );

        expect(
          () => collateralDao.closeCollateralException(
            shopId, item.id,
            actor: owner,
            reason: 'Attempt on returned item',
          ),
          throwsA(isA<StateError>()),
        );
        final inDb = await collateralDao.getCollateralItemById(shopId, item.id);
        expect(inDb!.custodyStatus, equals(CollateralCustodyStatus.returned));
      });

      test('closeCollateralException rejects terminal exceptionHeld state', () async {
        final item = await createItemInCustody();
        await collateralDao.closeCollateralException(
          shopId, item.id,
          actor: owner,
          reason: 'First exception hold',
        );

        expect(
          () => collateralDao.closeCollateralException(
            shopId, item.id,
            actor: owner,
            reason: 'Second exception hold attempt',
          ),
          throwsA(isA<StateError>()),
        );
        final inDb = await collateralDao.getCollateralItemById(shopId, item.id);
        expect(inDb!.custodyStatus, equals(CollateralCustodyStatus.exceptionHeld));
      });

      test('closeCollateralException preserves custody history (append-only)', () async {
        final item = await createItemInCustody();
        await collateralDao.closeCollateralException(
          shopId, item.id,
          actor: owner,
          reason: 'Exception hold reason',
        );

        final events = await collateralDao.getCustodyEventsByCollateralItemId(
          shopId, item.id,
        );
        expect(events.length, equals(1));
        expect(events.first.previousStatus, equals(CollateralCustodyStatus.inCustody));
        expect(events.first.newStatus, equals(CollateralCustodyStatus.exceptionHeld));
        expect(events.first.reason, contains('Exception hold reason'));
        expect(events.first.reportedByUserId, equals(owner.id));
        expect(events.first.createdAt, isNotNull);
      });

      test('closeCollateralException is atomic: failed transition persists nothing', () async {
        final item = await createItemInCustody();
        final beforeStatus = (await collateralDao.getCollateralItemById(shopId, item.id))!.custodyStatus;
        final beforeEvents = await collateralDao.getCustodyEventsByCollateralItemId(shopId, item.id);

        expect(
          () => collateralDao.closeCollateralException(
            shopId, 'coll-nonexistent',
            actor: owner,
            reason: 'Will fail',
          ),
          throwsA(isA<StateError>()),
        );

        final afterStatus = (await collateralDao.getCollateralItemById(shopId, item.id))!.custodyStatus;
        final afterEvents = await collateralDao.getCustodyEventsByCollateralItemId(shopId, item.id);
        expect(afterStatus, equals(beforeStatus));
        expect(afterEvents.length, equals(beforeEvents.length));
      });

      test('closeCollateralException rejects manager (not owner)', () async {
        final now = DateTime.now().toUtc();
        await db.into(db.appUsers).insert(
          AppUserEntry(
            id: 'user-manager',
            shopId: shopId,
            username: 'manager',
            fullName: 'Shift Manager',
            role: 'manager',
            isActive: true,
            sessionVersion: 1,
            createdAt: now,
            updatedAt: now,
          ),
        );
        final manager = AppUser(
          id: 'user-manager',
          shopId: shopId,
          username: 'manager',
          fullName: 'Shift Manager',
          role: AppRole.manager,
        );

        final item = await createItemInCustody();

        expect(
          () => collateralDao.closeCollateralException(
            shopId, item.id,
            actor: manager,
            reason: 'Manager attempts exception hold',
          ),
          throwsA(isA<PermissionDeniedException>()),
        );
        final inDb = await collateralDao.getCollateralItemById(shopId, item.id);
        expect(inDb!.custodyStatus, equals(CollateralCustodyStatus.inCustody));

        final events = await collateralDao.getCustodyEventsByCollateralItemId(shopId, item.id);
        expect(events.length, equals(0));
      });

      test('closeCollateralException concurrent attempts produce exactly one successful transition and one custody event', () async {
        final item = await createItemInCustody();

        // Run two concurrent closeCollateralException calls on the same item.
        // Wrap each in try/catch so we collect both results instead of
        // throwing on the first error.
        final results = await Future.wait([
          collateralDao.closeCollateralException(
            shopId, item.id,
            actor: owner,
            reason: 'Concurrent attempt A',
          ).then((_) => 'success').onError((error, _) => 'error: $error'),
          collateralDao.closeCollateralException(
            shopId, item.id,
            actor: owner,
            reason: 'Concurrent attempt B',
          ).then((_) => 'success').onError((error, _) => 'error: $error'),
        ]);

        // Exactly one should succeed, the other should throw.
        final successCount = results.where((r) => r == 'success').length;
        final errorCount = results.where((r) => r.startsWith('error:')).length;
        expect(successCount, equals(1));
        expect(errorCount, equals(1));

        // Item should be in exceptionHeld state.
        final inDb = await collateralDao.getCollateralItemById(shopId, item.id);
        expect(inDb!.custodyStatus, equals(CollateralCustodyStatus.exceptionHeld));

        // Exactly one custody event should exist.
        final events = await collateralDao.getCustodyEventsByCollateralItemId(
          shopId, item.id,
        );
        expect(events.length, equals(1));
        expect(events.first.previousStatus, equals(CollateralCustodyStatus.inCustody));
        expect(events.first.newStatus, equals(CollateralCustodyStatus.exceptionHeld));
      });

      test('closeCollateralException rejects when item state changed by another operation', () async {
        final item = await createItemInCustody();

        // Simulate another operation changing the item directly in the database
        // (bypassing the FSM), so the item is no longer inCustody.
        await db.customStatement(
          'UPDATE collateral_items SET custody_status = ? WHERE id = ?',
          [CollateralCustodyStatus.handoverRequested.value, item.id],
        );

        // Attempt exception hold — getCollateralItemById returns handoverRequested,
        // which is NOT a valid source for exceptionHeld per the FSM.
        expect(
          () => collateralDao.closeCollateralException(
            shopId, item.id,
            actor: owner,
            reason: 'Attempt on modified item',
          ),
          throwsA(isA<CollateralCustodyTransitionException>()),
        );

        // Item state should be unchanged (still handoverRequested).
        final inDb = await collateralDao.getCollateralItemById(shopId, item.id);
        expect(inDb!.custodyStatus, equals(CollateralCustodyStatus.handoverRequested));

        // No custody event should have been inserted for the failed attempt.
        final events = await collateralDao.getCustodyEventsByCollateralItemId(
          shopId, item.id,
        );
        expect(events.length, equals(0));
      });
    });
  });
}

