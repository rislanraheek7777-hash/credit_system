import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/core/permissions/authorization_guard.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_dao.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_custody_event.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:credit_system/features/collateral/presentation/collateral_custody_return_screen.dart';

void main() {
  group('CollateralCustodyReturnScreen - Per-Item Physical Handover (Story 3.4)', () {
    late AppDatabase db;
    late CollateralDao dao;

    const shopId = 'shop-return-1';
    const customerId = 1;
    const creditId = 'credit-return-1';
    const cashierId = 'user-cashier-return';
    const ownerId = 'user-owner-return';

    Future<void> seedDatabase() async {
      final now = DateTime.now().toUtc();
      await db.into(db.shops).insert(
        ShopEntry(
          id: shopId,
          name: 'Return Test Shop',
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
          fullName: 'Return Customer',
          nic: '851234567V',
          phone: '0771234567',
          address: '1 Return Street',
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
          id: cashierId,
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
          id: ownerId,
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
    }

    Future<String> createItem({
      required String itemId,
      required String itemReferenceId,
      CollateralCustodyStatus status = CollateralCustodyStatus.inCustody,
      String? itemCreditId,
    }) async {
      final item = CollateralItem(
        id: itemId,
        shopId: shopId,
        customerId: customerId,
        creditId: itemCreditId,
        itemReferenceId: itemReferenceId,
        category: CollateralItemCategory.gold,
        description: 'Test collateral item',
        conditionGrade: 'Good',
        weightMilligrams: 1000,
        estimatedValueCents: 100000,
        custodyStatus: status,
      );
      await dao.createCollateralItem(item);
      return item.id;
    }

    AppUser cashier() => AppUser(
      id: cashierId,
      shopId: shopId,
      username: 'cashier',
      fullName: 'Counter Cashier',
      role: AppRole.cashier,
      isActive: true,
    );

    AppUser owner() => AppUser(
      id: ownerId,
      shopId: shopId,
      username: 'owner',
      fullName: 'Shop Owner',
      role: AppRole.shopOwner,
      isActive: true,
    );

    /// Pumps the screen and waits for the asynchronous load to complete.
    Future<void> pumpScreen(
      WidgetTester tester,
      AppUser currentUser, {
      int? filterCustomerId,
      String? filterCreditId,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CollateralCustodyReturnScreen(
            shopId: shopId,
            currentUser: currentUser,
            customerId: filterCustomerId,
            creditId: filterCreditId,
            database: db,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Enters a mandatory reason and submits the currently open dialog,
    /// then pumps until the async transition completes.
    Future<void> submitReason(WidgetTester tester, String reason) async {
      await tester.enterText(find.byType(TextField).first, reason);
      // Pump so the dialog rebuilds and enables the Submit button once the
      // mandatory reason has been entered.
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
    }

    /// Pumps frames (up to ~5s) until [text] appears on screen, absorbing
    /// asynchronous database writes and UI refreshes after an action.
    Future<void> pumpUntilText(WidgetTester tester, String text) async {
      final stopwatch = Stopwatch()..start();
      while (stopwatch.elapsedMilliseconds < 5000) {
        await tester.pumpAndSettle();
        if (find.textContaining(text).evaluate().isNotEmpty) return;
      }
    }

    setUp(() async {
      final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
      db = AppDatabase.forTesting(inMemoryExecutor);
      dao = CollateralDao(db);
      await seedDatabase();
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('displays items with their current custody state', (
      WidgetTester tester,
    ) async {
      await createItem(
        itemId: 'item-r-1',
        itemReferenceId: 'COLL-R-001',
        status: CollateralCustodyStatus.inCustody,
        itemCreditId: creditId,
      );
      await createItem(
        itemId: 'item-r-2',
        itemReferenceId: 'COLL-R-002',
        status: CollateralCustodyStatus.returned,
        itemCreditId: creditId,
      );

      await pumpScreen(tester, owner());

      expect(
        find.text('Collateral Return - Physical Handover Verification'),
        findsOneWidget,
      );
      expect(find.textContaining('COLL-R-001'), findsOneWidget);
      expect(find.textContaining('COLL-R-002'), findsOneWidget);
      expect(find.text('Custody: in custody'), findsOneWidget);
      expect(find.text('Custody: returned'), findsOneWidget);
      expect(find.text('Credit: $creditId'), findsNWidgets(2));
      expect(find.text('Customer: $customerId'), findsNWidgets(2));
      expect(find.textContaining('Test collateral item'), findsAtLeastNWidgets(2));
    });

    testWidgets('cashier requests a return: inCustody → handoverRequested', (
      WidgetTester tester,
    ) async {
      await createItem(
        itemId: 'item-r-3',
        itemReferenceId: 'COLL-R-003',
        status: CollateralCustodyStatus.inCustody,
      );

      await pumpScreen(tester, cashier());
      expect(find.text('Request Return'), findsOneWidget);

      await tester.tap(find.text('Request Return'));
      await tester.pumpAndSettle();
      await submitReason(tester, 'Customer settled');
      await pumpUntilText(tester, 'Custody: handover requested');

      // State change first, then the success notification.
      expect(find.textContaining('Custody: handover requested'), findsOneWidget);
      expect(find.textContaining('Return request recorded for COLL-R-003'), findsOneWidget);

      final events = await dao.getCustodyEventsByCollateralItemId(
        shopId, 'item-r-3',
      );
      expect(events.length, equals(1));
      expect(events.first.previousStatus, equals(CollateralCustodyStatus.inCustody));
      expect(events.first.newStatus, equals(CollateralCustodyStatus.handoverRequested));
      expect(events.first.reportedByUserId, equals(cashierId));
    });

    testWidgets('cashier reports physical handover: handoverRequested → handoverReported', (
      WidgetTester tester,
    ) async {
      await createItem(
        itemId: 'item-r-4',
        itemReferenceId: 'COLL-R-004',
        status: CollateralCustodyStatus.handoverRequested,
      );

      await pumpScreen(tester, cashier());
      expect(find.text('Report Physical Handover'), findsOneWidget);

      await tester.tap(find.text('Report Physical Handover'));
      await tester.pumpAndSettle();
      await submitReason(tester, 'Handed over at counter');
      await pumpUntilText(tester, 'Custody: handover reported');

      expect(find.textContaining('Physical handover reported for COLL-R-004'), findsOneWidget);
      expect(find.text('Custody: handover reported'), findsOneWidget);
    });

    testWidgets('Shop Owner confirms return: handoverReported → returned', (
      WidgetTester tester,
    ) async {
      await createItem(
        itemId: 'item-r-5',
        itemReferenceId: 'COLL-R-005',
        status: CollateralCustodyStatus.handoverReported,
      );

      await pumpScreen(tester, owner());
      expect(find.text('Confirm Return'), findsOneWidget);

      // Confirm via the confirmation dialog
      await tester.tap(find.text('Confirm Return').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm Return').last);
      await pumpUntilText(tester, 'Return confirmed for COLL-R-005');

      expect(find.textContaining('Return confirmed for COLL-R-005'), findsOneWidget);
      expect(find.text('Custody: returned'), findsOneWidget);
    });

    testWidgets('cashier cannot confirm a return (owner-only action)', (
      WidgetTester tester,
    ) async {
      await createItem(
        itemId: 'item-r-6',
        itemReferenceId: 'COLL-R-006',
        status: CollateralCustodyStatus.handoverReported,
      );

      await pumpScreen(tester, cashier());

      // Owner-only actions are not offered to counter staff
      expect(find.text('Confirm Return'), findsNothing);
      expect(find.text('Reject Handover'), findsNothing);

      // Operation layer still enforces permission if invoked directly
      expect(
        () => dao.transitionCustody(
          shopId, 'item-r-6', CollateralCustodyStatus.returned,
          reportedByUserId: cashierId,
          reason: 'unauthorized',
          actor: cashier(),
          requiredPermission: AppPermission.confirmCollateralReturn,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      final item = await dao.getCollateralItemById(shopId, 'item-r-6');
      expect(item!.custodyStatus, equals(CollateralCustodyStatus.handoverReported));
    });

    testWidgets('cashier cancels a return request: handoverRequested → inCustody', (
      WidgetTester tester,
    ) async {
      await createItem(
        itemId: 'item-r-7',
        itemReferenceId: 'COLL-R-007',
        status: CollateralCustodyStatus.handoverRequested,
      );

      await pumpScreen(tester, cashier());
      expect(find.text('Cancel Request'), findsOneWidget);

      await tester.tap(find.text('Cancel Request'));
      await tester.pumpAndSettle();
      // Confirm the cancellation in the dialog
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      expect(find.text('Custody: in custody'), findsOneWidget);
    });

    testWidgets('cashier reports a discrepancy: item → discrepancy, stays visible', (
      WidgetTester tester,
    ) async {
      await createItem(
        itemId: 'item-r-8',
        itemReferenceId: 'COLL-R-008',
        status: CollateralCustodyStatus.inCustody,
      );

      await pumpScreen(tester, cashier());
      expect(find.text('Report Discrepancy'), findsOneWidget);

      await tester.tap(find.text('Report Discrepancy'));
      await tester.pumpAndSettle();
      await submitReason(
        tester,
        'System shows in custody but item is missing from vault',
      );
      await pumpUntilText(tester, 'Custody: discrepancy');

      expect(find.textContaining('Discrepancy reported for COLL-R-008'), findsOneWidget);
      expect(find.textContaining('Custody: discrepancy'), findsOneWidget);
      expect(find.textContaining('UNRESOLVED DISCREPANCY'), findsOneWidget);

      final discrepancies = await dao.getDiscrepanciesByCollateralItemId(
        shopId, 'item-r-8',
      );
      expect(discrepancies.length, equals(1));
      expect(discrepancies.first.status, equals(CollateralDiscrepancyStatus.pending));
      expect(discrepancies.first.resolvedByUserId, isNull);
    });

    testWidgets('Shop Owner resolves a discrepancy and item moves to the decided state', (
      WidgetTester tester,
    ) async {
      await createItem(
        itemId: 'item-r-9',
        itemReferenceId: 'COLL-R-009',
        status: CollateralCustodyStatus.inCustody,
      );
      // Report a discrepancy via the DAO so a pending discrepancy record exists
      // for the item (resolveDiscrepancy looks it up by item id).
      await dao.reportDiscrepancy(
        shopId, 'item-r-9', cashierId,
        'Item reported damaged on return',
        actor: cashier(),
        requiredPermission: AppPermission.createCredits,
      );

      await pumpScreen(tester, owner());
      expect(find.text('Resolve Discrepancy'), findsOneWidget);

      await tester.tap(find.text('Resolve Discrepancy'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mark as Returned').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resolve').first);
      await tester.pumpAndSettle();
      await pumpUntilText(tester, 'Record Discrepancy Resolution');

      await submitReason(
        tester,
        'Item located; counted and returned to customer',
      );
      await pumpUntilText(tester, 'Discrepancy resolved for COLL-R-009');

      expect(find.textContaining('Discrepancy resolved for COLL-R-009'), findsOneWidget);
      expect(find.text('Custody: returned'), findsOneWidget);
      expect(find.text('UNRESOLVED DISCREPANCY'), findsNothing);

      final all = await dao.getDiscrepanciesByCollateralItemId(shopId, 'item-r-9');
      expect(all.isNotEmpty, isTrue);
      expect(all.first.status, equals(CollateralDiscrepancyStatus.resolved));
      expect(all.first.resolvedByUserId, equals(ownerId));
      expect(all.first.resolutionNotes, contains('located'));
      expect(all.first.resolvedAt, isNotNull);
    });

    testWidgets('items on the same credit transition independently', (
      WidgetTester tester,
    ) async {
      await createItem(
        itemId: 'item-r-10',
        itemReferenceId: 'COLL-R-010',
        status: CollateralCustodyStatus.inCustody,
        itemCreditId: creditId,
      );
      await createItem(
        itemId: 'item-r-11',
        itemReferenceId: 'COLL-R-011',
        status: CollateralCustodyStatus.inCustody,
        itemCreditId: creditId,
      );

      await pumpScreen(tester, cashier());

      // Transition only item-r-10 through request + report
      await tester.tap(find.text('Request Return').first);
      await tester.pumpAndSettle();
      await submitReason(tester, 'item ten return');
      await pumpUntilText(tester, 'Custody: handover requested');

      await tester.tap(find.text('Report Physical Handover').first);
      await tester.pumpAndSettle();
      await submitReason(tester, 'item ten handover');
      await pumpUntilText(tester, 'Custody: handover reported');

      expect(find.text('Custody: handover reported'), findsOneWidget);
      expect(find.text('COLL-R-010 (gold)'), findsOneWidget);

      // Sibling item on the same credit is unchanged and still actionable
      expect(find.textContaining('COLL-R-011'), findsOneWidget);
      expect(find.text('Custody: in custody'), findsOneWidget);
      expect(
        await dao.getCollateralItemById(shopId, 'item-r-11'),
        isNotNull,
      );
      expect(
        (await dao.getCollateralItemById(shopId, 'item-r-11'))!.custodyStatus,
        equals(CollateralCustodyStatus.inCustody),
      );
    });

    testWidgets('returned item is terminal: no further actions offered', (
      WidgetTester tester,
    ) async {
      await createItem(
        itemId: 'item-r-12',
        itemReferenceId: 'COLL-R-012',
        status: CollateralCustodyStatus.returned,
      );

      await pumpScreen(tester, owner());

      expect(find.text('Custody: returned'), findsOneWidget);
      expect(find.text('Request Return'), findsNothing);
      expect(find.text('Confirm Return'), findsNothing);
    });

    testWidgets('tapping an item shows its immutable custody history', (
      WidgetTester tester,
    ) async {
      final itemId = await createItem(
        itemId: 'item-r-13',
        itemReferenceId: 'COLL-R-013',
        status: CollateralCustodyStatus.handoverRequested,
      );
      await dao.transitionCustody(
        shopId, itemId, CollateralCustodyStatus.handoverReported,
        reportedByUserId: cashierId,
        reason: 'history test',
        actor: cashier(),
        requiredPermission: AppPermission.createCredits,
      );

      await pumpScreen(tester, owner());

      await tester.tap(find.textContaining('COLL-R-013').first);
      await tester.pump();

      expect(find.text('Custody History - COLL-R-013'), findsOneWidget);
    });

    testWidgets('Shop Owner places item into Exception / Held: inCustody → exceptionHeld', (
      WidgetTester tester,
    ) async {
      await createItem(
        itemId: 'item-r-14',
        itemReferenceId: 'COLL-R-014',
        status: CollateralCustodyStatus.inCustody,
      );

      await pumpScreen(tester, owner());
      expect(find.text('Exception / Held'), findsOneWidget);

      await tester.tap(find.text('Exception / Held').first);
      await tester.pumpAndSettle();

      await submitReason(
        tester,
        'Police seizure; item cannot be physically returned',
      );
      await pumpUntilText(tester, 'Custody: exception held');

      expect(find.text('Item COLL-R-014 placed into Exception / Held.'), findsOneWidget);
      expect(find.text('Custody: exception held'), findsOneWidget);
    });

    testWidgets('cashier cannot place item into Exception / Held (owner-only)', (
      WidgetTester tester,
    ) async {
      await createItem(
        itemId: 'item-r-15',
        itemReferenceId: 'COLL-R-015',
        status: CollateralCustodyStatus.inCustody,
      );

      await pumpScreen(tester, cashier());

      // Cashier does not see the owner-only Exception / Held button
      expect(find.text('Exception / Held'), findsNothing);

      // Direct DAO call is also rejected
      expect(
        () => dao.closeCollateralException(
          shopId, 'item-r-15',
          actor: cashier(),
          reason: 'Cashier attempts exception hold',
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    testWidgets('item in Exception / Held is terminal: no further actions offered', (
      WidgetTester tester,
    ) async {
      await createItem(
        itemId: 'item-r-16',
        itemReferenceId: 'COLL-R-016',
        status: CollateralCustodyStatus.exceptionHeld,
      );

      await pumpScreen(tester, owner());

      expect(find.text('Custody: exception held'), findsOneWidget);
      expect(find.text('Request Return'), findsNothing);
      expect(find.text('Exception / Held'), findsNothing);
    });

    testWidgets('Shop Owner administratively closes settled credit with exceptionHeld item', (
      WidgetTester tester,
    ) async {
      // Mark credit as settled
      await (db.update(db.credits)..where((l) => l.id.equals(creditId))).write(
        CreditsCompanion(
          status: const Value('settled'),
          workflowStatus: Value(CreditWorkflowStatus.disbursed.value),
          settledAt: Value(DateTime.now().toUtc()),
          balanceCents: const Value(0),
        ),
      );

      await createItem(
        itemId: 'item-r-admin-1',
        itemReferenceId: 'COLL-R-ADMIN-1',
        status: CollateralCustodyStatus.exceptionHeld,
        itemCreditId: creditId,
      );

      await pumpScreen(tester, owner(), filterCreditId: creditId);

      // Button should be visible for owner on settled credit with exception item
      expect(find.byKey(const Key('btn_administrative_closure')), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_administrative_closure')));
      await tester.pumpAndSettle();

      expect(find.text('Close Credit (Collateral Exception)'), findsOneWidget);

      await submitReason(
        tester,
        'Police impounded item COLL-R-ADMIN-1 permanently. Closing account.',
      );
      await pumpUntilText(tester, 'Closed (Collateral Exception)');

      // Success message and banner should appear
      expect(find.text('Credit administratively closed with collateral exception.'), findsOneWidget);
      expect(find.byKey(const Key('credit_closure_banner')), findsOneWidget);
      expect(find.text('Closed (Collateral Exception)'), findsOneWidget);
      expect(find.textContaining('Police impounded item COLL-R-ADMIN-1 permanently'), findsOneWidget);

      // Button should no longer be visible since closure is done
      expect(find.byKey(const Key('btn_administrative_closure')), findsNothing);
    });

    testWidgets('Cashier cannot see administrative closure button', (
      WidgetTester tester,
    ) async {
      await (db.update(db.credits)..where((l) => l.id.equals(creditId))).write(
        CreditsCompanion(
          status: const Value('settled'),
          workflowStatus: Value(CreditWorkflowStatus.disbursed.value),
          settledAt: Value(DateTime.now().toUtc()),
          balanceCents: const Value(0),
        ),
      );

      await createItem(
        itemId: 'item-r-admin-2',
        itemReferenceId: 'COLL-R-ADMIN-2',
        status: CollateralCustodyStatus.exceptionHeld,
        itemCreditId: creditId,
      );

      await pumpScreen(tester, cashier(), filterCreditId: creditId);

      expect(find.byKey(const Key('btn_administrative_closure')), findsNothing);
    });

    testWidgets('Administrative closure button not shown on active (unsettled) credit', (
      WidgetTester tester,
    ) async {
      // Credit is active (balance > 0)
      await createItem(
        itemId: 'item-r-admin-3',
        itemReferenceId: 'COLL-R-ADMIN-3',
        status: CollateralCustodyStatus.exceptionHeld,
        itemCreditId: creditId,
      );

      await pumpScreen(tester, owner(), filterCreditId: creditId);

      expect(find.byKey(const Key('btn_administrative_closure')), findsNothing);
    });

    testWidgets('Administrative closure button not shown if items are still inCustody', (
      WidgetTester tester,
    ) async {
      await (db.update(db.credits)..where((l) => l.id.equals(creditId))).write(
        CreditsCompanion(
          status: const Value('settled'),
          workflowStatus: Value(CreditWorkflowStatus.disbursed.value),
          settledAt: Value(DateTime.now().toUtc()),
          balanceCents: const Value(0),
        ),
      );

      // One item is exceptionHeld, but another is still inCustody
      await createItem(
        itemId: 'item-r-admin-4a',
        itemReferenceId: 'COLL-R-ADMIN-4A',
        status: CollateralCustodyStatus.exceptionHeld,
        itemCreditId: creditId,
      );
      await createItem(
        itemId: 'item-r-admin-4b',
        itemReferenceId: 'COLL-R-ADMIN-4B',
        status: CollateralCustodyStatus.inCustody,
        itemCreditId: creditId,
      );

      await pumpScreen(tester, owner(), filterCreditId: creditId);

      expect(find.byKey(const Key('btn_administrative_closure')), findsNothing);
    });
  });
}

