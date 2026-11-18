import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:credit_system/features/customers/presentation/credit_draft_agreement_action.dart';
import 'package:credit_system/features/customers/presentation/credit_draft_agreement_view_screen.dart';
import 'package:credit_system/features/customers/domain/models/credit_document_content.dart';
import 'package:credit_system/features/customers/presentation/credit_details_screen.dart';

import '../../../support/customers_test_support.dart';

void main() {
  Widget creditDetails({
    required AppDatabase db,
    String shopId = testShopId,
    AppRole role = AppRole.cashier,
    Set<AppPermission>? customPermissions,
    bool isActive = true,
    String? actorShopId,
  }) {
    return MaterialApp(
      home: CreditDetailsScreen(
        shopId: shopId,
        currentUser: AppUser(
          id: testUserId,
          shopId: actorShopId ?? shopId,
          username: 'testuser',
          fullName: 'Test User',
          role: role,
          isActive: isActive,
          customPermissions: customPermissions,
        ),
        database: db,
      ),
    );
  }

  testWidgets('CreditDetailsScreen displays shop credit details', (
    WidgetTester tester,
  ) async {
    final db = await openTestDatabase();

    const shopId = 'shop-123';
    const customerId = 456;

    final now = DateTime.now().toUtc();
    await seedShopAndCustomer(db, shopId: shopId, customerId: customerId);
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: 'user-1',
        shopId: shopId,
        username: 'testuser',
        fullName: 'Test User',
        role: 'manager',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await insertCredit(db,
      Credit(
        id: 'credit-1',
        shopId: shopId,
        customerId: customerId,
        principalCents: 500000,
        balanceCents: 300000,
        status: CreditStatus.active,
        workflowStatus: CreditWorkflowStatus.disbursed,
        dueDate: now.add(const Duration(days: 30)),
        createdAt: now,
      ),
    );

    await tester.pumpWidget(
      creditDetails(
        db: db,
        shopId: shopId,
        role: AppRole.manager,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Credit Details'), findsOneWidget);
    expect(find.textContaining('Sunil Perera'), findsOneWidget);
    expect(find.textContaining('Amount: Rs.'), findsOneWidget);
    expect(find.text('Type: Cash'), findsOneWidget);
    expect(find.textContaining('Balance: Rs.'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);

    await db.close();
  });

  testWidgets('CreditDetailsScreen shows empty state when no credits exist', (
    WidgetTester tester,
  ) async {
    final db = await openTestDatabase();

    const shopId = 'shop-123';

    await seedShopAndCustomer(db, shopId: shopId);

    await tester.pumpWidget(
      creditDetails(
        db: db,
        shopId: shopId,
        role: AppRole.manager,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No credit details found'), findsOneWidget);

    await db.close();
  });

  group('CreditDetailsScreen - draft agreement action', () {
    const shopId = 'shop-123';
    const customerId = 456;
    const pendingCreditId = 'credit-pending-1';

    /// Seeds a shop, a borrower and one pending-disbursement agreement.
    Future<AppDatabase> seedPendingCredit(WidgetTester tester) async {
      final db = await openTestDatabase();
      useLargeSurface(tester);
      await seedShopAndCustomer(db, shopId: shopId, customerId: customerId);

      final now = DateTime.now().toUtc();
      await insertCredit(db,
        Credit(
          id: pendingCreditId,
          shopId: shopId,
          customerId: customerId,
          principalCents: 500000,
          balanceCents: 500000,
          status: CreditStatus.active,
          workflowStatus: CreditWorkflowStatus.pendingDisbursement,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
        ),
      );
      return db;
    }

    testWidgets('a pending-disbursement credit offers the draft action, '
        'records a generate_credit_draft audit event and shows the agreement '
        'on screen without saving anything', (WidgetTester tester) async {
      final db = await seedPendingCredit(tester);

      await tester.pumpWidget(
        creditDetails(
          db: db,
          shopId: shopId,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(CreditDraftAgreementAction.buttonKey(pendingCreditId)),
        findsOneWidget,
      );

      await openDraftAgreement(tester, pendingCreditId);

      // The agreement is shown on screen: title, draft reference, watermark
      // and the pending-disbursement disclosures are all visible.
      expect(
        find.byKey(CreditDraftAgreementAction.viewKey(pendingCreditId)),
        findsOneWidget,
      );
      expect(
        find.text('CREDIT AGREEMENT - DRAFT (PENDING DISBURSEMENT)'),
        findsOneWidget,
      );
      expect(find.textContaining('DRAFT-'), findsWidgets);
      expect(find.text(kDraftWatermark), findsWidgets);

      // No document was saved or handed over: no file path is surfaced
      // anywhere on the view.
      expect(find.textContaining('Saved'), findsNothing);

      // The Category 2 audit event was queued in the sync queue.
      final syncEntries = await db.select(db.syncQueue).get();
      final draftEvents = syncEntries.where((e) =>
          e.entityType == 'credit' &&
          e.actionType == 'generate_credit_draft');
      expect(draftEvents, isNotEmpty);
      expect(draftEvents.first.entityId, equals(pendingCreditId));

      // Back out of the view; the credit list is unchanged.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      await db.close();
    });

    testWidgets('the outcome of one agreement is not shown against another', (
      WidgetTester tester,
    ) async {
      const secondCreditId = 'credit-B1';
      const firstCreditId = 'credit-A1';

      final db = await openTestDatabase();
      useLargeSurface(tester);
      await seedShopAndCustomer(db, shopId: shopId, customerId: customerId);

      final now = DateTime.now().toUtc();
      // The list is ordered by due date, so the first agreement is rendered
      // in the first slot.
      await insertCredit(db,
        Credit(
          id: firstCreditId,
          shopId: shopId,
          customerId: customerId,
          principalCents: 500000,
          balanceCents: 500000,
          status: CreditStatus.active,
          workflowStatus: CreditWorkflowStatus.pendingDisbursement,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
        ),
      );
      await insertCredit(db,
        Credit(
          id: secondCreditId,
          shopId: shopId,
          customerId: customerId,
          principalCents: 500000,
          balanceCents: 500000,
          status: CreditStatus.active,
          workflowStatus: CreditWorkflowStatus.pendingDisbursement,
          dueDate: now.add(const Duration(days: 60)),
          createdAt: now,
        ),
      );

      await tester.pumpWidget(
        creditDetails(
          db: db,
          shopId: shopId,
        ),
      );
      await tester.pumpAndSettle();

      // View the draft of the agreement in the first slot.
      await openDraftAgreement(tester, firstCreditId);
      expect(
        find.byKey(CreditDraftAgreementAction.viewKey(firstCreditId)),
        findsOneWidget,
      );

      // Back out of the view.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      // Move the other agreement ahead of the first one, so the list reuses
      // the first slot for it.
      await (db.update(db.credits)
            ..where((c) => c.id.equals(secondCreditId)))
          .write(CreditsCompanion(dueDate: Value(now.add(const Duration(days: 1)))));

      // Pull the shop's credit list down to refresh it, so the sliver reuses
      // the first slot for the other agreement. The drag has to exceed a
      // quarter of the viewport height before the indicator arms.
      await tester.fling(find.byType(ListView), const Offset(0, 900), 1000);
      await tester.pump();

      await pumpUntil(tester, () {
        final first = find.text('Credit credit-A...');
        final second = find.text('Credit credit-B...');
        if (first.evaluate().isEmpty || second.evaluate().isEmpty) return false;
        return tester.getTopLeft(second).dy < tester.getTopLeft(first).dy;
      });

      // The agreement now in the first slot shows no leftover error of its
      // own from the other agreement's view.
      expect(
        find.byKey(CreditDraftAgreementAction.errorKey(secondCreditId)),
        findsNothing,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(CreditDraftAgreementAction.buttonKey(secondCreditId)),
            )
            .onPressed,
        isNotNull,
        reason: 'The reused slot must not keep a disabled button.',
      );

      await db.close();
    });

    testWidgets('a disbursed credit offers no draft action', (
      WidgetTester tester,
    ) async {
      final db = await openTestDatabase();
      useLargeSurface(tester);
      await seedShopAndCustomer(db, shopId: shopId, customerId: customerId);

      final now = DateTime.now().toUtc();
      await insertCredit(db,
        Credit(
          id: 'credit-disbursed-1',
          shopId: shopId,
          customerId: customerId,
          principalCents: 500000,
          balanceCents: 300000,
          status: CreditStatus.active,
          workflowStatus: CreditWorkflowStatus.disbursed,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
        ),
      );

      await tester.pumpWidget(creditDetails(db: db, shopId: shopId));
      await tester.pumpAndSettle();

      expect(
        find.byKey(CreditDraftAgreementAction.buttonKey('credit-disbursed-1')),
        findsNothing,
      );
      expect(find.text('View Draft Agreement'), findsNothing);

      await db.close();
    });

    testWidgets('an actor without createCredits is offered no draft action', (
      WidgetTester tester,
    ) async {
      final db = await seedPendingCredit(tester);

      await tester.pumpWidget(
        creditDetails(
          db: db,
          shopId: shopId,
          role: AppRole.custom,
          customPermissions: {AppPermission.viewCustomers},
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(CreditDraftAgreementAction.buttonKey(pendingCreditId)),
        findsNothing,
      );
      expect(find.text('View Draft Agreement'), findsNothing);

      await db.close();
    });

    testWidgets('a deactivated account is offered no draft action', (
      WidgetTester tester,
    ) async {
      final db = await seedPendingCredit(tester);

      await tester.pumpWidget(
        creditDetails(
          db: db,
          shopId: shopId,
          role: AppRole.shopOwner,
          isActive: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(CreditDraftAgreementAction.buttonKey(pendingCreditId)),
        findsNothing,
      );
      expect(find.text('View Draft Agreement'), findsNothing);

      await db.close();
    });

    testWidgets('a refusal is surfaced inline and opens nothing', (
      WidgetTester tester,
    ) async {
      final db = await seedPendingCredit(tester);

      await tester.pumpWidget(
        creditDetails(
          db: db,
          shopId: shopId,
          // Staff of another tenant may hold createCredits, but the service
          // refuses to resolve the content for a credit outside their shop.
          actorShopId: 'shop-other-tenant',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(CreditDraftAgreementAction.buttonKey(pendingCreditId)),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(CreditDraftAgreementAction.buttonKey(pendingCreditId)),
      );
      await pumpUntil(tester,
          () => find
              .byKey(CreditDraftAgreementAction.errorKey(pendingCreditId))
              .evaluate()
              .isNotEmpty);

      // The failure is reported inline, without the raw driver detail.
      final error = tester.widget<Text>(
        find.byKey(CreditDraftAgreementAction.errorKey(pendingCreditId)),
      );
      expect(error.data, contains('could not be opened'));
      expect(error.data, isNot(contains('PermissionDeniedException')));

      // The view was never opened and no draft audit event was queued.
      expect(find.byType(CreditDraftAgreementViewScreen), findsNothing);
      final syncEntries = await db.select(db.syncQueue).get();
      expect(
        syncEntries.where((e) => e.actionType == 'generate_credit_draft'),
        isEmpty,
      );

      await db.close();
    });
  });
}
