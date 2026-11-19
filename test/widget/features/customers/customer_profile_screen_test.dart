import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_dao.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';
import 'package:credit_system/features/customers/data/daos/customer_dao.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:credit_system/features/customers/domain/models/credit_term.dart';
import 'package:credit_system/features/customers/presentation/credit_draft_agreement_action.dart';
import 'package:credit_system/features/customers/presentation/credit_origination_screen.dart';
import 'package:credit_system/features/customers/presentation/credit_draft_agreement_view_screen.dart';
import 'package:credit_system/features/customers/domain/models/credit_document_content.dart';
import 'package:credit_system/features/customers/presentation/credit_settle_action.dart';
import 'package:credit_system/features/customers/presentation/customer_profile_screen.dart';
import 'package:credit_system/features/customers/presentation/settle_summary_screen.dart';

import '../../../support/customers_test_support.dart';

/// The shop whose zone is deliberately far from the approved default, so a
/// date rendered in the shop's own zone is always distinguishable from the
/// same instant rendered in `Asia/Colombo`.
const String remoteZoneShopId = 'shop-remote-zone';

/// The borrower of the remote-zone shop.
const int remoteZoneCustomerId = 457;

void main() {
  Widget profileScreen({
    required AppDatabase db,
    String shopId = testShopId,
    int customerId = testCustomerId,
    AppRole role = AppRole.cashier,
    Set<AppPermission>? customPermissions,
    bool isActive = true,
    String? actorShopId,
    bool canViewSensitive = false,
  }) {
    return MaterialApp(
      home: CustomerProfileScreen(
        shopId: shopId,
        customerId: customerId,
        canViewSensitive: canViewSensitive,
        database: db,
        currentUser: AppUser(
          id: testUserId,
          shopId: actorShopId ?? shopId,
          username: 'testuser',
          fullName: 'Test User',
          role: role,
          isActive: isActive,
          customPermissions: customPermissions,
        ),
      ),
    );
  }

  testWidgets('CustomerProfileScreen displays customer details', (
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
        dueDate: now.add(const Duration(days: 30)),
        createdAt: now,
      ),
    );

    await tester.pumpWidget(
      profileScreen(
        db: db,
        shopId: shopId,
        customerId: customerId,
        role: AppRole.manager,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Customer Profile'), findsOneWidget);
    expect(find.text('Sunil Perera'), findsOneWidget);
    expect(find.text('NIC: 8512****567V'), findsOneWidget);
    expect(find.text('Phone: 077 **** 567'), findsOneWidget);
    expect(find.text('Credit details'), findsOneWidget);
    expect(find.text('Active (1)'), findsOneWidget);

    await db.close();
  });

  testWidgets('CustomerProfileScreen shows sensitive data when authorized', (
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

    await tester.pumpWidget(
      profileScreen(
        db: db,
        shopId: shopId,
        customerId: customerId,
        role: AppRole.manager,
        canViewSensitive: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sunil Perera'), findsOneWidget);
    expect(find.text('NIC: 851234567V'), findsOneWidget);
    expect(find.text('Phone: 0771234567'), findsOneWidget);
    expect(find.text('Address: 1 Main St, Colombo'), findsOneWidget);

    await db.close();
  });

  testWidgets('CustomerProfileScreen shows no credits when none exist', (
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

    await tester.pumpWidget(
      profileScreen(
        db: db,
        shopId: shopId,
        customerId: customerId,
        role: AppRole.manager,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No credit details found'), findsOneWidget);

    await db.close();
  });

  testWidgets('CustomerProfileScreen shows credit status badges', (
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
        id: 'credit-active-1',
        shopId: shopId,
        customerId: customerId,
        principalCents: 500000,
        balanceCents: 300000,
        status: CreditStatus.active,
        dueDate: now.add(const Duration(days: 30)),
        createdAt: now,
      ),
    );
    await insertCredit(db,
      Credit(
        id: 'credit-overdue-1',
        shopId: shopId,
        customerId: customerId,
        principalCents: 300000,
        balanceCents: 200000,
        status: CreditStatus.overdue,
        dueDate: now.subtract(const Duration(days: 5)),
        createdAt: now,
      ),
    );
    await insertCredit(db,
      Credit(
        id: 'credit-settled-1',
        shopId: shopId,
        customerId: customerId,
        principalCents: 200000,
        balanceCents: 0,
        status: CreditStatus.settled,
        workflowStatus: CreditWorkflowStatus.disbursed,
        dueDate: now.subtract(const Duration(days: 10)),
        createdAt: now,
        settledAt: now,
      ),
    );

    await tester.pumpWidget(
      profileScreen(
        db: db,
        shopId: shopId,
        customerId: customerId,
        role: AppRole.manager,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Active (1)'), findsOneWidget);
    expect(find.text('Overdue (1)'), findsOneWidget);
    expect(find.text('Settled (1)'), findsOneWidget);

    await db.close();
  });

  testWidgets('CustomerProfileScreen shows Edit action', (
    WidgetTester tester,
  ) async {
    final db = await openTestDatabase();

    const shopId = 'shop-123';
    const customerId = 456;

    await seedShopAndCustomer(db, shopId: shopId, customerId: customerId);

    await tester.pumpWidget(
      profileScreen(
        db: db,
        shopId: shopId,
        customerId: customerId,
        role: AppRole.manager,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('edit_customer_button')), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);

    await db.close();
  });

  testWidgets('CustomerProfileScreen shows Add Credit action and opens origination', (
    WidgetTester tester,
  ) async {
    final db = await openTestDatabase();

    const shopId = 'shop-123';
    const customerId = 456;

    await seedShopAndCustomer(db, shopId: shopId, customerId: customerId);

    await tester.pumpWidget(
      profileScreen(
        db: db,
        shopId: shopId,
        customerId: customerId,
        role: AppRole.cashier,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('add_credit_button')), findsOneWidget);
    expect(find.text('Add Credit'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add_credit_button')));
    await tester.pumpAndSettle();

    expect(find.text('Credit Origination'), findsOneWidget);

    await db.close();
  });

  testWidgets('CustomerProfileScreen hides Add Credit action without createCredits', (
    WidgetTester tester,
  ) async {
    final db = await openTestDatabase();

    const shopId = 'shop-123';
    const customerId = 456;

    await seedShopAndCustomer(db, shopId: shopId, customerId: customerId);

    await tester.pumpWidget(
      profileScreen(
        db: db,
        shopId: shopId,
        customerId: customerId,
        role: AppRole.custom,
        customPermissions: {AppPermission.viewCustomers},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('add_credit_button')), findsNothing);
    expect(find.text('Add Credit'), findsNothing);

    await db.close();
  });

  testWidgets('Edit action opens the edit form and saves profile changes', (
    WidgetTester tester,
  ) async {
    final db = await openTestDatabase();

    const shopId = 'shop-123';
    const customerId = 456;

    await seedShopAndCustomer(db, shopId: shopId, customerId: customerId);

    await tester.pumpWidget(
      profileScreen(
        db: db,
        shopId: shopId,
        customerId: customerId,
        role: AppRole.manager,
        canViewSensitive: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('edit_customer_button')));
    await tester.pumpAndSettle();

    expect(find.text('Edit Customer'), findsOneWidget);
    expect(find.text('Sunil Perera'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('edit_customer_full_name_field')),
      'Sunil Perera Silva',
    );
    await tester.tap(find.byKey(const Key('save_customer_button')));
    await tester.pumpAndSettle();

    // Back on the profile, showing the updated name.
    expect(find.text('Customer Profile'), findsOneWidget);
    expect(find.text('Sunil Perera Silva'), findsOneWidget);

    final row = await (db.select(db.customers)
          ..where((c) => c.id.equals(customerId)))
        .getSingle();
    expect(row.fullName, 'Sunil Perera Silva');

    await db.close();
  });

  group('CustomerProfileScreen - credit origination return', () {
    const shopId = 'shop-123';
    const customerId = 456;

    /// Drives the origination route to a successful submission and waits for
    /// the profile to be shown again.
    Future<void> createCredit(
      WidgetTester tester, {
      String principal = '5000.00',
    }) async {
      await tester.tap(find.byKey(const Key('add_credit_button')));
      await pumpUntil(tester,
          () => find.byKey(const Key('submit_credit_button')).evaluate().isNotEmpty);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('principal_amount_field')),
        principal,
      );
      await tester.tap(find.byKey(const Key('term_preset_30')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('submit_credit_button')));
      await pumpUntil(tester,
          () => find.byType(CreditOriginationScreen).evaluate().isEmpty);
    }

    testWidgets('a created credit closes the origination route and is '
        'confirmed with a SnackBar', (WidgetTester tester) async {
      final db = await openTestDatabase();
      useLargeSurface(tester);
      await seedShopAndCustomer(db, shopId: shopId, customerId: customerId);

      await tester.pumpWidget(
        profileScreen(db: db, shopId: shopId, customerId: customerId),
      );
      await tester.pumpAndSettle();

      await createCredit(tester);

      // The origination route closes and the customer profile is shown again.
      expect(find.byType(CustomerProfileScreen), findsOneWidget);
      expect(find.text('Credit Origination'), findsNothing);

      // The confirmation is a SnackBar on the profile.
      await pumpUntil(tester,
          () => find.textContaining('Credit agreement created.').evaluate().isNotEmpty);

      // The expected date is read from the persisted agreement, so the
      // assertion cannot drift across a shop-zone midnight.
      final credits = await db.select(db.credits).get();
      expect(credits, hasLength(1));
      final persistedDueDate =
          ShopTimeZone.defaultTimeZone().localDateOf(credits.first.dueDate).isoDate;
      expect(
        find.text(
          'Credit agreement created. Preliminary due date: $persistedDueDate.',
        ),
        findsOneWidget,
      );

      // The profile's credit list includes the newly created agreement.
      await pumpUntil(tester, () => find.text('Active (1)').evaluate().isNotEmpty);
      expect(credits.first.customerId, equals(customerId));

      await db.close();
    });

    testWidgets('the confirmation date is rendered in the shop time zone', (
      WidgetTester tester,
    ) async {
      final db = await openTestDatabase();
      useLargeSurface(tester);
      await seedShopAndCustomer(
        db,
        shopId: remoteZoneShopId,
        customerId: remoteZoneCustomerId,
        timezone: 'Pacific/Kiritimati',
      );

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: remoteZoneShopId,
          customerId: remoteZoneCustomerId,
        ),
      );
      await tester.pumpAndSettle();

      await createCredit(tester);
      await pumpUntil(tester,
          () => find.textContaining('Credit agreement created.').evaluate().isNotEmpty);

      final credits = await db.select(db.credits).get();
      expect(credits, hasLength(1));

      final shopZone = ShopTimeZone('Pacific/Kiritimati');
      final shopZoneDate = shopZone.localDateOf(credits.first.dueDate).isoDate;
      final defaultZoneDate =
          ShopTimeZone.defaultTimeZone().localDateOf(credits.first.dueDate).isoDate;
      expect(
        shopZoneDate,
        isNot(equals(defaultZoneDate)),
        reason: 'The fixture must make the shop zone distinguishable from the '
            'approved default, otherwise this case proves nothing.',
      );

      expect(
        find.text(
          'Credit agreement created. Preliminary due date: $shopZoneDate.',
        ),
        findsOneWidget,
      );

      await db.close();
    });

    testWidgets('a second agreement can be created for the same customer', (
      WidgetTester tester,
    ) async {
      final db = await openTestDatabase();
      useLargeSurface(tester);
      await seedShopAndCustomer(db, shopId: shopId, customerId: customerId);

      await tester.pumpWidget(
        profileScreen(db: db, shopId: shopId, customerId: customerId),
      );
      await tester.pumpAndSettle();

      await createCredit(tester);
      await pumpUntil(tester, () => find.text('Active (1)').evaluate().isNotEmpty);

      // The profile is shown again and offers origination a second time.
      expect(find.byKey(const Key('add_credit_button')), findsOneWidget);
      await createCredit(tester, principal: '7000.00');
      await pumpUntil(tester, () => find.text('Active (2)').evaluate().isNotEmpty);

      final credits = await db.select(db.credits).get();
      expect(credits, hasLength(2));
      expect(
        credits.every((credit) => credit.customerId == customerId),
        isTrue,
      );

      // Each agreement was created under its own idempotency key (F3): a
      // genuinely new submission never reuses the previous one's key.
      final createEvents = (await db.select(db.syncQueue).get())
          .where((e) => e.actionType == 'create_credit')
          .toList();
      expect(createEvents, hasLength(2));
      expect(
        createEvents.first.idempotencyKey,
        isNot(equals(createEvents.last.idempotencyKey)),
      );

      await db.close();
    });

    testWidgets('backing out of origination shows no confirmation SnackBar', (
      WidgetTester tester,
    ) async {
      final db = await openTestDatabase();
      useLargeSurface(tester);
      await seedShopAndCustomer(db, shopId: shopId, customerId: customerId);

      await tester.pumpWidget(
        profileScreen(db: db, shopId: shopId, customerId: customerId),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add_credit_button')));
      await pumpUntil(tester,
          () => find.byKey(const Key('submit_credit_button')).evaluate().isNotEmpty);
      await tester.pumpAndSettle();

      // Back out without submitting anything.
      Navigator.of(tester.element(find.byType(CreditOriginationScreen))).pop();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(CustomerProfileScreen), findsOneWidget);
      expect(find.textContaining('Credit agreement created.'), findsNothing);
      expect(await db.select(db.credits).get(), isEmpty);

      await db.close();
    });

    testWidgets('a failed submission keeps the origination screen open and '
        'shows no confirmation SnackBar', (WidgetTester tester) async {
      final db = await openTestDatabase();
      useLargeSurface(tester);
      await seedShopAndCustomer(db, shopId: shopId, customerId: customerId);

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
          // Staff of another tenant hold createCredits, so the origination
          // flow is offered, but the DAO refuses the submission because the
          // borrower does not belong to their shop.
          actorShopId: 'shop-other-tenant',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add_credit_button')));
      await pumpUntil(tester,
          () => find.byKey(const Key('submit_credit_button')).evaluate().isNotEmpty);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('principal_amount_field')),
        '5000.00',
      );
      await tester.tap(find.byKey(const Key('term_preset_30')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('submit_credit_button')));
      await pumpUntil(tester,
          () => find.byKey(const Key('origination_error_display')).evaluate().isNotEmpty);

      // The origination screen is still open with its inline error.
      expect(find.byType(CreditOriginationScreen), findsOneWidget);
      expect(find.byKey(const Key('origination_error_display')), findsOneWidget);

      // No credit was created, so there is nothing to confirm.
      expect(await db.select(db.credits).get(), isEmpty);
      expect(find.textContaining('Credit agreement created.'), findsNothing);

      await db.close();
    });
  });

  group('CustomerProfileScreen - draft agreement action', () {
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
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
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
      expect(find.text(kDraftSignatureLabel), findsOneWidget);
      expect(find.textContaining('Rs. 5,000.00'), findsWidgets);

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

    testWidgets('the view lists only the items pledged to this credit', (
      WidgetTester tester,
    ) async {
      final db = await seedPendingCredit(tester);

      final collateralDao = CollateralDao(db);
      // The other item receipt is pledged to a different agreement, so the
      // view must not list it.
      await insertCredit(db,
        Credit(
          id: 'credit-other-1',
          shopId: shopId,
          customerId: customerId,
          principalCents: 100000,
          balanceCents: 100000,
          status: CreditStatus.active,
          workflowStatus: CreditWorkflowStatus.pendingDisbursement,
          dueDate: DateTime.now().toUtc().add(const Duration(days: 60)),
          createdAt: DateTime.now().toUtc(),
        ),
      );
      await collateralDao.createCollateralItem(
        CollateralItem(
          id: 'coll-pledged',
          shopId: shopId,
          customerId: customerId,
          creditId: pendingCreditId,
          itemReferenceId: 'COLL-PLEDGED-777',
          category: CollateralItemCategory.gold,
          description: '22K gold necklace',
          conditionGrade: 'Like New',
          weightMilligrams: 5500,
          estimatedValueCents: 1500000,
        ),
      );
      await collateralDao.createCollateralItem(
        CollateralItem(
          id: 'coll-other',
          shopId: shopId,
          customerId: customerId,
          creditId: 'credit-other-1',
          itemReferenceId: 'COLL-OTHER-888',
          category: CollateralItemCategory.electronics,
          description: 'Laptop',
          conditionGrade: 'Good',
          weightMilligrams: 1500000,
          estimatedValueCents: 400000,
        ),
      );

      await tester.pumpWidget(
        profileScreen(db: db, shopId: shopId, customerId: customerId),
      );
      await tester.pumpAndSettle();

      await openDraftAgreement(tester, pendingCreditId);

      expect(
        find.textContaining('COLL-PLEDGED-777'),
        findsOneWidget,
        reason: 'The view must list the items pledged to this agreement.',
      );
      expect(
        find.textContaining('COLL-OTHER-888'),
        findsNothing,
        reason: "The view must not list the borrower's other item receipts.",
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

      await tester.pumpWidget(
        profileScreen(db: db, shopId: shopId, customerId: customerId),
      );
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
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
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
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
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

    testWidgets('an agreement created through the profile can be viewed from '
        'the same profile', (WidgetTester tester) async {
      final db = await openTestDatabase();
      useLargeSurface(tester);
      await seedShopAndCustomer(db, shopId: shopId, customerId: customerId);

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
        ),
      );
      await tester.pumpAndSettle();

      // Create the agreement through the origination route.
      await tester.tap(find.byKey(const Key('add_credit_button')));
      await pumpUntil(tester,
          () => find.byKey(const Key('submit_credit_button')).evaluate().isNotEmpty);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('principal_amount_field')),
        '5000.00',
      );
      await tester.tap(find.byKey(const Key('term_preset_30')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('submit_credit_button')));
      await pumpUntil(tester,
          () => find.byType(CreditOriginationScreen).evaluate().isEmpty);
      await pumpUntil(tester, () => find.text('Active (1)').evaluate().isNotEmpty);

      final credits = await db.select(db.credits).get();
      expect(credits, hasLength(1));
      final createdCreditId = credits.first.id;

      // The new agreement offers the draft action straight away.
      expect(
        find.byKey(CreditDraftAgreementAction.buttonKey(createdCreditId)),
        findsOneWidget,
      );

      await openDraftAgreement(tester, createdCreditId);

      expect(
        find.byType(CreditDraftAgreementViewScreen),
        findsOneWidget,
      );

      final draftEvents = (await db.select(db.syncQueue).get())
          .where((e) => e.actionType == 'generate_credit_draft')
          .toList();
      expect(draftEvents, hasLength(1));
      expect(draftEvents.first.entityId, equals(createdCreditId));

      await db.close();
    });

    testWidgets('a refusal is surfaced inline and opens nothing', (
      WidgetTester tester,
    ) async {
      final db = await seedPendingCredit(tester);

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
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

  group('CustomerProfileScreen - settle action', () {
    const shopId = 'shop-123';
    const customerId = 456;
    const settleCreditId = 'credit-settle-1';

    /// Seeds a shop, a borrower and one disbursed, payment-eligible credit.
    Future<AppDatabase> seedDisbursedCredit(
      WidgetTester tester, {
      String creditId = settleCreditId,
      int principalCents = 500000,
      int balanceCents = 300000,
    }) async {
      final db = await openTestDatabase();
      useLargeSurface(tester);
      await seedShopAndCustomer(db, shopId: shopId, customerId: customerId);

      final now = DateTime.now().toUtc();
      // The payment path snapshots the recording actor and the payments table
      // holds a foreign key to the actor row, so the actor must exist.
      await db.into(db.appUsers).insert(
        AppUserEntry(
          id: testUserId,
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
          id: creditId,
          shopId: shopId,
          customerId: customerId,
          principalCents: principalCents,
          balanceCents: balanceCents,
          status: CreditStatus.active,
          workflowStatus: CreditWorkflowStatus.disbursed,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
        ),
      );
      return db;
    }

    testWidgets('an eligible credit offers the Settle action', (
      WidgetTester tester,
    ) async {
      final db = await seedDisbursedCredit(tester);

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
          role: AppRole.manager,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(CreditSettleAction.buttonKey(settleCreditId)),
        findsOneWidget,
      );
      expect(find.text('Settle'), findsOneWidget);

      await db.close();
    });

    testWidgets('tapping Settle opens the settle summary screen showing the '
        'borrower, credit identity, outstanding balance and collateral at '
        'stake, and confirming records a full settlement', (
      WidgetTester tester,
    ) async {
      final db = await seedDisbursedCredit(tester);

      await CollateralDao(db).createCollateralItem(
        CollateralItem(
          id: 'coll-settle-1',
          shopId: shopId,
          customerId: customerId,
          creditId: settleCreditId,
          itemReferenceId: 'COLL-SETTLE-777',
          category: CollateralItemCategory.gold,
          description: '22K gold necklace',
          conditionGrade: 'Like New',
          weightMilligrams: 5500,
          estimatedValueCents: 1500000,
        ),
      );

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
          role: AppRole.shopOwner,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(CreditSettleAction.buttonKey(settleCreditId)),
      );
      await pumpUntil(
        tester,
        () =>
            find.byKey(const Key('settle_amount_input')).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      expect(find.byType(SettleSummaryScreen), findsOneWidget);

      // The borrower, credit identity, big balance and collateral at stake
      // are all shown.
      expect(find.byKey(const Key('settle_customer_name')), findsOneWidget);
      expect(find.text('Sunil Perera'), findsOneWidget);
      expect(find.byKey(const Key('settle_credit_reference')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('settle_outstanding_balance')))
            .data,
        equals('Rs. 3,000.00'),
      );
      expect(
        find.text('Collateral at stake: 1 of 1 items still in custody'),
        findsOneWidget,
      );
      expect(find.textContaining('COLL-SETTLE-777'), findsOneWidget);
      expect(
        find.text('Settlement does not return pledged items.'),
        findsOneWidget,
      );

      final amountField = tester.widget<TextField>(
        find.byKey(const Key('settle_amount_input')),
      );
      expect(
        amountField.controller!.text,
        equals('3000.00'),
        reason: 'The full outstanding balance must be pre-filled.',
      );

      await tester.tap(find.byKey(const Key('settle_confirm_button')));
      await pumpUntil(
        tester,
        () => find.byKey(const Key('settle_sheet_full')).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      // The option sheet leads with a full settlement of the balance.
      expect(find.text('Settle in full — Rs. 3,000.00'), findsOneWidget);
      await tester.tap(find.byKey(const Key('settle_sheet_full')));
      await pumpUntil(
        tester,
        () => find.byType(SettleSummaryScreen).evaluate().isEmpty,
      );
      await tester.pumpAndSettle();

      // Back on the profile with a confirmation.
      expect(find.byType(CustomerProfileScreen), findsOneWidget);
      await pumpUntil(
        tester,
        () => find.textContaining('Credit settled').evaluate().isNotEmpty,
      );

      // The credit list was refreshed: balance 0 and Settled.
      final row = await (db.select(
        db.credits,
      )..where((c) => c.id.equals(settleCreditId))).getSingle();
      expect(row.balanceCents, equals(0));
      expect(row.status, equals('settled'));
      expect(find.text('Settled (1)'), findsOneWidget);
      expect(find.text('Balance: Rs. 0.00'), findsOneWidget);

      // The receipt row is committed and remains available from history.
      final payments = await db.select(db.payments).get();
      expect(payments, hasLength(1));
      expect(payments.single.paymentType, equals('full_settlement'));

      await db.close();
    });

    testWidgets('tapping Settle on one of several eligible credits settles '
        'exactly that credit', (WidgetTester tester) async {
      final db = await seedDisbursedCredit(tester);

      final now = DateTime.now().toUtc();
      await insertCredit(db,
        Credit(
          id: 'credit-settle-2',
          shopId: shopId,
          customerId: customerId,
          principalCents: 900000,
          balanceCents: 250000,
          status: CreditStatus.active,
          workflowStatus: CreditWorkflowStatus.disbursed,
          dueDate: now.add(const Duration(days: 45)),
          createdAt: now,
        ),
      );

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
          role: AppRole.manager,
        ),
      );
      await tester.pumpAndSettle();

      // Settle the second card's credit — not the first actionable one.
      await tester.tap(
        find.byKey(CreditSettleAction.buttonKey('credit-settle-2')),
      );
      await pumpUntil(
        tester,
        () =>
            find.byKey(const Key('settle_amount_input')).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      expect(find.byType(SettleSummaryScreen), findsOneWidget);
      final screen = tester.widget<SettleSummaryScreen>(
        find.byType(SettleSummaryScreen),
      );
      expect(
        screen.creditId,
        equals('credit-settle-2'),
        reason:
            'Tapping a card\'s Settle action must settle that card\'s credit.',
      );

      // The pre-filled amount is that credit's balance, not another credit's.
      final amountField = tester.widget<TextField>(
        find.byKey(const Key('settle_amount_input')),
      );
      expect(amountField.controller!.text, equals('2500.00'));

      await db.close();
    });

    testWidgets('the settle screen offers the balance-adjustment (forgiveness) '
        'option', (WidgetTester tester) async {
      final db = await seedDisbursedCredit(tester);

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
          role: AppRole.manager,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(CreditSettleAction.buttonKey(settleCreditId)),
      );
      await pumpUntil(
        tester,
        () =>
            find.byKey(const Key('settle_amount_input')).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      // Settle opens the options sheet; the adjustment proposal lives there.
      await tester.tap(find.byKey(const Key('settle_confirm_button')));
      await pumpUntil(
        tester,
        () => find
            .byKey(const Key('request_adjustment_button'))
            .evaluate()
            .isNotEmpty,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('request_adjustment_button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('request_adjustment_button')));
      await pumpUntil(
        tester,
        () => find
            .byKey(const Key('adjustment_amount_input'))
            .evaluate()
            .isNotEmpty,
      );
      await tester.pumpAndSettle();

      expect(find.text('Request Balance Adjustment'), findsWidgets);

      await db.close();
    });

    testWidgets('ineligible credits still offer Settle, and the summary '
        'screen explains why they cannot be settled', (
      WidgetTester tester,
    ) async {
      final db = await openTestDatabase();
      useLargeSurface(tester);
      await seedShopAndCustomer(db, shopId: shopId, customerId: customerId);

      final now = DateTime.now().toUtc();
      // Pending disbursement.
      await insertCredit(db,
        Credit(
          id: 'credit-pending',
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
      // Settled.
      await insertCredit(db,
        Credit(
          id: 'credit-settled',
          shopId: shopId,
          customerId: customerId,
          principalCents: 500000,
          balanceCents: 0,
          status: CreditStatus.settled,
          workflowStatus: CreditWorkflowStatus.disbursed,
          dueDate: now.subtract(const Duration(days: 5)),
          createdAt: now,
          settledAt: now,
        ),
      );
      // Disbursed but zero balance.
      await insertCredit(db,
        Credit(
          id: 'credit-zero-balance',
          shopId: shopId,
          customerId: customerId,
          principalCents: 500000,
          balanceCents: 0,
          status: CreditStatus.active,
          workflowStatus: CreditWorkflowStatus.disbursed,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
        ),
      );

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
          role: AppRole.manager,
        ),
      );
      await tester.pumpAndSettle();

      // The settle button is visible on every card for a recordPayments
      // holder (visibility rule restored at the human's request); the
      // summary screen is the eligibility backstop.
      expect(
        find.byKey(CreditSettleAction.buttonKey('credit-pending')),
        findsOneWidget,
      );
      expect(
        find.byKey(CreditSettleAction.buttonKey('credit-settled')),
        findsOneWidget,
      );
      expect(
        find.byKey(CreditSettleAction.buttonKey('credit-zero-balance')),
        findsOneWidget,
      );

      // Tapping Settle on an ineligible credit opens the summary screen,
      // which refuses payment and explains why.
      await tester.tap(
        find.byKey(CreditSettleAction.buttonKey('credit-zero-balance')),
      );
      await pumpUntil(
        tester,
        () => find
            .text('This credit is not eligible for payment recording.')
            .evaluate()
            .isNotEmpty,
      );
      expect(
        find.text('This credit is not eligible for payment recording.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('settle_confirm_button')), findsNothing);

      await db.close();
    });

    testWidgets('an actor without recordPayments is offered no Settle action', (
      WidgetTester tester,
    ) async {
      final db = await seedDisbursedCredit(tester);

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
          role: AppRole.custom,
          customPermissions: {AppPermission.viewCustomers},
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(CreditSettleAction.buttonKey(settleCreditId)),
        findsNothing,
      );
      expect(find.text('Settle'), findsNothing);

      await db.close();
    });

    testWidgets('a deactivated account is offered no Settle action', (
      WidgetTester tester,
    ) async {
      final db = await seedDisbursedCredit(tester);

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
          role: AppRole.shopOwner,
          isActive: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(CreditSettleAction.buttonKey(settleCreditId)),
        findsNothing,
      );
      expect(find.text('Settle'), findsNothing);

      await db.close();
    });

    testWidgets('lowering the pre-filled amount records a partial payment and '
        'does not return to the profile', (WidgetTester tester) async {
      final db = await seedDisbursedCredit(tester);

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
          role: AppRole.manager,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(CreditSettleAction.buttonKey(settleCreditId)),
      );
      await pumpUntil(
        tester,
        () =>
            find.byKey(const Key('settle_amount_input')).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      // Lower the amount via the Partial settlement option, then confirm
      // through the sheet — no auto-return, recorded as a partial payment.
      await tester.tap(find.byKey(const Key('settle_confirm_button')));
      await pumpUntil(
        tester,
        () =>
            find.byKey(const Key('settle_sheet_partial')).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settle_sheet_partial')));
      await tester.pumpAndSettle();

      final clearedField = tester.widget<TextField>(
        find.byKey(const Key('settle_amount_input')),
      );
      expect(clearedField.controller!.text, isEmpty);

      await tester.enterText(
        find.byKey(const Key('settle_amount_input')),
        '1000.00',
      );
      await tester.tap(find.byKey(const Key('settle_confirm_button')));
      await pumpUntil(
        tester,
        () =>
            find.textContaining('Record partial payment').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settle_sheet_partial')));
      await pumpUntil(
        tester,
        () => find
            .byKey(const Key('settle_success_display'))
            .evaluate()
            .isNotEmpty,
      );

      // The summary screen stays open — a partial payment never auto-returns.
      expect(find.byType(SettleSummaryScreen), findsOneWidget);

      final row = await (db.select(
        db.credits,
      )..where((c) => c.id.equals(settleCreditId))).getSingle();
      expect(row.balanceCents, equals(200000));
      expect(row.status, equals('active'));
      expect(
        (await db.select(db.payments).get()).single.paymentType,
        equals('partial'),
      );

      await db.close();
    });

    testWidgets('a balance changed after render is blocked by the overpayment '
        'guard', (WidgetTester tester) async {
      final db = await seedDisbursedCredit(tester);

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
          role: AppRole.manager,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(CreditSettleAction.buttonKey(settleCreditId)),
      );
      await pumpUntil(
        tester,
        () =>
            find.byKey(const Key('settle_amount_input')).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      // The balance drops after the screen was rendered and pre-filled.
      await (db.update(db.credits)..where((c) => c.id.equals(settleCreditId)))
          .write(const CreditsCompanion(balanceCents: Value(100000)));

      await tester.tap(find.byKey(const Key('settle_confirm_button')));
      await pumpUntil(
        tester,
        () => find.byKey(const Key('settle_sheet_full')).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settle_sheet_full')));
      await pumpUntil(
        tester,
        () => find
            .byKey(const Key('settle_validation_error_display'))
            .evaluate()
            .isNotEmpty,
      );

      final error = tester.widget<Text>(
        find.byKey(const Key('settle_validation_error_display')),
      );
      expect(error.data, contains('exceeds the outstanding balance'));

      // Nothing was recorded and the screen stayed open.
      expect(await db.select(db.payments).get(), isEmpty);
      expect(find.byType(SettleSummaryScreen), findsOneWidget);

      await db.close();
    });

    testWidgets('a pending correction blocks settlement with the existing '
        'correction-pending error', (WidgetTester tester) async {
      final db = await seedDisbursedCredit(tester);

      // Activate the Story 5.5 correction lock on the credit.
      await (db.update(db.credits)
            ..where((c) => c.id.equals(settleCreditId)))
          .write(const CreditsCompanion(correctionPending: Value(true)));

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
          role: AppRole.manager,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(CreditSettleAction.buttonKey(settleCreditId)),
      );
      await pumpUntil(
        tester,
        () =>
            find.byKey(const Key('settle_amount_input')).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settle_confirm_button')));
      await pumpUntil(
        tester,
        () => find.byKey(const Key('settle_sheet_full')).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settle_sheet_full')));
      await pumpUntil(
        tester,
        () =>
            find.byKey(const Key('settle_error_display')).evaluate().isNotEmpty,
      );

      final error = tester.widget<Text>(
        find.byKey(const Key('settle_error_display')),
      );
      expect(error.data, contains('pending correction'));

      // Nothing was recorded and the screen stayed open.
      expect(await db.select(db.payments).get(), isEmpty);
      expect(find.byType(SettleSummaryScreen), findsOneWidget);

      await db.close();
    });

    testWidgets('the sheet offers a due date extension to a Shop Owner, and it '
        'updates the credit through the standard extension path', (
      WidgetTester tester,
    ) async {
      final db = await seedDisbursedCredit(tester);
      // A collateral item makes the profile tall enough to fill the test
      // surface — the configuration in which the modal bottom sheet renders
      // inside the 3000px test view.
      await CollateralDao(db).createCollateralItem(
        CollateralItem(
          id: 'coll-settle-extend',
          shopId: shopId,
          customerId: customerId,
          creditId: settleCreditId,
          itemReferenceId: 'COLL-EXTEND-777',
          category: CollateralItemCategory.gold,
          description: '22K gold necklace',
          conditionGrade: 'Like New',
          weightMilligrams: 5500,
          estimatedValueCents: 1500000,
        ),
      );

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
          role: AppRole.shopOwner,
        ),
      );
      await tester.pumpAndSettle();

      final before = await (db.select(
        db.credits,
      )..where((c) => c.id.equals(settleCreditId))).getSingle();

      await tester.tap(
        find.byKey(CreditSettleAction.buttonKey(settleCreditId)),
      );
      await pumpUntil(
        tester,
        () =>
            find.byKey(const Key('settle_amount_input')).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settle_confirm_button')));
      await pumpUntil(
        tester,
        () =>
            find.byKey(const Key('settle_sheet_extend')).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      // The sheet exposes the owner-only extension option.
      expect(find.byKey(const Key('settle_sheet_extend')), findsOneWidget);
      expect(find.byKey(const Key('settle_sheet_full')), findsOneWidget);
      expect(find.byKey(const Key('settle_sheet_partial')), findsOneWidget);
      expect(
        find.byKey(const Key('request_adjustment_button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('settle_sheet_extend')));
      await pumpUntil(
        tester,
        () => find.text('Extend due date').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      // Accept the pre-chosen date (today + 30 days), then supply the reason.
      await tester.tap(find.text('OK'));
      await pumpUntil(
        tester,
        () =>
            find.byKey(const Key('extend_reason_field')).evaluate().isNotEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('extend_reason_field')),
        'Customer requested more time',
      );
      await tester.tap(find.byKey(const Key('extend_confirm_button')));
      await pumpUntil(
        tester,
        () => find.textContaining('Due date extended to').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      // The standard extension path persisted the change and an audit entry.
      final after = await (db.select(
        db.credits,
      )..where((c) => c.id.equals(settleCreditId))).getSingle();
      expect(
        after.dueDate.millisecondsSinceEpoch,
        greaterThan(before.dueDate.millisecondsSinceEpoch),
      );
      expect(after.status, equals('active'));
      final extensions = await db.select(db.dueDateExtensions).get();
      expect(extensions, hasLength(1));
      expect(extensions.single.reason, equals('Customer requested more time'));

      await db.close();
    });

    testWidgets('the due date extension option is hidden from non-owners', (
      WidgetTester tester,
    ) async {
      final db = await seedDisbursedCredit(tester);

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
          role: AppRole.manager,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(CreditSettleAction.buttonKey(settleCreditId)),
      );
      await pumpUntil(
        tester,
        () =>
            find.byKey(const Key('settle_amount_input')).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settle_confirm_button')));
      await pumpUntil(
        tester,
        () => find.byKey(const Key('settle_sheet_full')).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settle_sheet_extend')), findsNothing);

      await db.close();
    });
  });

  group('CustomerProfileScreen - soft delete', () {
    const shopId = 'shop-123';
    const customerId = 456;

    Future<void> seedCredit(AppDatabase db) async {
      final now = DateTime.now().toUtc();
      await insertCredit(db,
        Credit(
          id: 'credit-delete-guard-1',
          shopId: shopId,
          customerId: customerId,
          principalCents: 250000,
          balanceCents: 250000,
          status: CreditStatus.active,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
        ),
      );
    }

    OutlinedButton deleteButton(WidgetTester tester) {
      return tester.widget<OutlinedButton>(
        find.byKey(const Key('delete_customer_button')),
      );
    }

    testWidgets('owner with zero credits sees an enabled Delete customer '
        'action', (WidgetTester tester) async {
      final db = await openTestDatabase();
      await seedShopAndCustomer(db, shopId: shopId, customerId: customerId);

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
          role: AppRole.shopOwner,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete_customer_button')), findsOneWidget);
      expect(deleteButton(tester).onPressed, isNotNull);
      expect(
        find.byKey(const Key('delete_customer_blocked_message')),
        findsNothing,
      );

      await db.close();
    });

    testWidgets('non-owner roles do not see the delete action', (
      WidgetTester tester,
    ) async {
      for (final role in [AppRole.cashier, AppRole.manager]) {
        final db = await openTestDatabase();
        await seedShopAndCustomer(db, shopId: shopId, customerId: customerId);

        await tester.pumpWidget(
          profileScreen(
            db: db,
            shopId: shopId,
            customerId: customerId,
            role: role,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('delete_customer_button')),
          findsNothing,
          reason: 'role $role must not see the delete action',
        );

        await db.close();
      }
    });

    testWidgets('custom role with registerCustomers and createCredits still '
        'does not see the delete action', (WidgetTester tester) async {
      final db = await openTestDatabase();
      await seedShopAndCustomer(db, shopId: shopId, customerId: customerId);

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
          role: AppRole.custom,
          customPermissions: {
            AppPermission.registerCustomers,
            AppPermission.createCredits,
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete_customer_button')), findsNothing);

      await db.close();
    });

    testWidgets('owner with credit history sees a disabled action and a '
        'blocking explanation', (WidgetTester tester) async {
      final db = await openTestDatabase();
      await seedShopAndCustomer(db, shopId: shopId, customerId: customerId);
      await seedCredit(db);

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
          role: AppRole.shopOwner,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete_customer_button')), findsOneWidget);
      expect(deleteButton(tester).onPressed, isNull);
      expect(
        find.byKey(const Key('delete_customer_blocked_message')),
        findsOneWidget,
      );
      expect(
        find.text('Cannot delete: this customer has credit history.'),
        findsOneWidget,
      );

      // Tapping the disabled action opens nothing and writes nothing.
      await tester.tap(find.byKey(const Key('delete_customer_button')));
      await tester.pumpAndSettle();
      expect(find.text('Delete Customer'), findsNothing);

      final row = await (db.select(
        db.customers,
      )..where((c) => c.id.equals(customerId))).getSingle();
      expect(row.deletedAt, isNull);

      await db.close();
    });

    testWidgets('owner confirming the deletion soft-deletes the customer, '
        'records an audit event and pops back', (WidgetTester tester) async {
      final db = await openTestDatabase();
      await seedShopAndCustomer(db, shopId: shopId, customerId: customerId);

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
          role: AppRole.shopOwner,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('delete_customer_button')));
      await tester.pumpAndSettle();
      expect(find.text('Delete Customer'), findsOneWidget);
      expect(find.text('This action cannot be undone.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('delete_customer_confirm_button')));
      await tester.pumpAndSettle();

      // Popped back to the search screen (the profile is gone).
      expect(find.text('Customer Profile'), findsNothing);

      // The row is retained, marked deleted, and hidden from search.
      final row = await (db.select(
        db.customers,
      )..where((c) => c.id.equals(customerId))).getSingle();
      expect(row.deletedAt, isNotNull);
      final results = await CustomerDao(db).searchCustomers(shopId, 'Sunil');
      expect(results, isEmpty);
      final all = await CustomerDao(db).getCustomersByShopId(shopId);
      expect(all, isEmpty);

      // An audit/sync queue entry records the soft delete (category 1).
      final queue = await db.select(db.syncQueue).get();
      expect(queue, hasLength(1));
      expect(queue.single.actionType, 'customer_soft_deleted');
      expect(queue.single.entityType, 'customer');
      expect(queue.single.status, 'pending_server_ack');
      final payload =
          jsonDecode(queue.single.payloadJson) as Map<String, dynamic>;
      expect(payload['auditCategory'], 1);
      expect(payload['auditEvent'], 'customer_soft_deleted');
      expect(payload['targetEntityType'], 'customer');
      expect(payload['targetEntityId'], customerId.toString());
      expect(payload['customerId'], customerId);

      await db.close();
    });

    testWidgets('owner declining the confirmation leaves the customer intact', (
      WidgetTester tester,
    ) async {
      final db = await openTestDatabase();
      await seedShopAndCustomer(db, shopId: shopId, customerId: customerId);

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
          role: AppRole.shopOwner,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('delete_customer_button')));
      await tester.pumpAndSettle();
      expect(find.text('Delete Customer'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Customer Profile'), findsOneWidget);
      final row = await (db.select(
        db.customers,
      )..where((c) => c.id.equals(customerId))).getSingle();
      expect(row.deletedAt, isNull);
      final queue = await db.select(db.syncQueue).get();
      expect(queue, isEmpty);

      await db.close();
    });

    testWidgets('owner can delete while offline; the delete is applied '
        'locally and queued for server sync', (WidgetTester tester) async {
      final db = await openTestDatabase();
      await seedShopAndCustomer(db, shopId: shopId, customerId: customerId);

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
          role: AppRole.shopOwner,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('delete_customer_button')));
      await tester.pumpAndSettle();
      expect(find.text('Delete Customer'), findsOneWidget);

      await tester.tap(find.byKey(const Key('delete_customer_confirm_button')));
      await tester.pumpAndSettle();

      final row = await (db.select(
        db.customers,
      )..where((c) => c.id.equals(customerId))).getSingle();
      expect(row.deletedAt, isNotNull);
      final queue = await db.select(db.syncQueue).get();
      expect(queue, hasLength(1));
      expect(queue.single.actionType, 'customer_soft_deleted');
      expect(queue.single.status, 'pending_server_ack');

      await db.close();
    });

    testWidgets('deactivated owner does not see the delete action', (
      WidgetTester tester,
    ) async {
      final db = await openTestDatabase();
      await seedShopAndCustomer(db, shopId: shopId, customerId: customerId);

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
          role: AppRole.shopOwner,
          isActive: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete_customer_button')), findsNothing);
      final row = await (db.select(
        db.customers,
      )..where((c) => c.id.equals(customerId))).getSingle();
      expect(row.deletedAt, isNull);
      final queue = await db.select(db.syncQueue).get();
      expect(queue, isEmpty);

      await db.close();
    });
  });
}
