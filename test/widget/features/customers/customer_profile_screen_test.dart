import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_dao.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:credit_system/features/customers/domain/models/credit_term.dart';
import 'package:credit_system/features/customers/presentation/credit_draft_agreement_action.dart';
import 'package:credit_system/features/customers/presentation/credit_origination_screen.dart';
import 'package:credit_system/features/customers/presentation/customer_profile_screen.dart';

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
    DocumentPresenter? documentPresenter,
  }) {
    return MaterialApp(
      home: CustomerProfileScreen(
        shopId: shopId,
        customerId: customerId,
        canViewSensitive: canViewSensitive,
        database: db,
        documentPresenter: documentPresenter,
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
        'records a generate_credit_draft audit event and hands the document '
        'over', (WidgetTester tester) async {
      final db = await seedPendingCredit(tester);
      final presenter = RecordingDocumentPresenter();

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
          documentPresenter: presenter.call,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(CreditDraftAgreementAction.buttonKey(pendingCreditId)),
        findsOneWidget,
      );

      await generateDraftAgreement(tester, pendingCreditId);

      // The document was handed over as a PDF.
      expect(presenter.bytes, isNotNull);
      expect(pdfText(presenter.bytes!), startsWith('%PDF'));
      expect(presenter.fileName, equals('draft_agreement_$pendingCreditId.pdf'));

      // The saved path is surfaced and the platform hand-off is confirmed.
      expect(
        find.byKey(CreditDraftAgreementAction.savedPathKey(pendingCreditId)),
        findsOneWidget,
      );
      expect(find.text('Draft Agreement Saved'), findsOneWidget);
      expect(find.textContaining(presenter.savedPath!), findsWidgets);

      // The Category 2 audit event was queued in the sync queue.
      final syncEntries = await db.select(db.syncQueue).get();
      final draftEvents = syncEntries.where((e) =>
          e.entityType == 'credit' &&
          e.actionType == 'generate_credit_draft');
      expect(draftEvents, isNotEmpty);
      expect(draftEvents.first.entityId, equals(pendingCreditId));

      await db.close();
    });

    testWidgets('the slip lists only the items pledged to this credit', (
      WidgetTester tester,
    ) async {
      final db = await seedPendingCredit(tester);
      final presenter = RecordingDocumentPresenter();

      final collateralDao = CollateralDao(db);
      // The other item receipt is pledged to a different agreement, so the
      // slip must not list it.
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
      await collateralDao.createCollateralItem(CollateralItem(
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
      ));
      await collateralDao.createCollateralItem(CollateralItem(
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
      ));

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
          documentPresenter: presenter.call,
        ),
      );
      await tester.pumpAndSettle();

      await generateDraftAgreement(tester, pendingCreditId);

      final text = pdfText(presenter.bytes!);
      expect(
        text,
        contains('COLL-PLEDGED-777'),
        reason: 'The slip must list the items pledged to this agreement.',
      );
      expect(
        text,
        isNot(contains('COLL-OTHER-888')),
        reason: "The slip must not list the borrower's other item receipts.",
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
      expect(find.text('View / Print Draft Agreement'), findsNothing);

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
      expect(find.text('View / Print Draft Agreement'), findsNothing);

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
      expect(find.text('View / Print Draft Agreement'), findsNothing);

      await db.close();
    });

    testWidgets('an agreement created through the profile can be printed from '
        'the same profile', (WidgetTester tester) async {
      final db = await openTestDatabase();
      useLargeSurface(tester);
      await seedShopAndCustomer(db, shopId: shopId, customerId: customerId);
      final presenter = RecordingDocumentPresenter();

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
          documentPresenter: presenter.call,
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

      await generateDraftAgreement(tester, createdCreditId);

      expect(presenter.bytes, isNotNull);
      expect(pdfText(presenter.bytes!), startsWith('%PDF'));

      final draftEvents = (await db.select(db.syncQueue).get())
          .where((e) => e.actionType == 'generate_credit_draft')
          .toList();
      expect(draftEvents, hasLength(1));
      expect(draftEvents.first.entityId, equals(createdCreditId));

      await db.close();
    });

    testWidgets('a refusal is surfaced inline and claims no document', (
      WidgetTester tester,
    ) async {
      final db = await seedPendingCredit(tester);
      final presenter = RecordingDocumentPresenter();

      await tester.pumpWidget(
        profileScreen(
          db: db,
          shopId: shopId,
          customerId: customerId,
          // Staff of another tenant may hold createCredits, but the service
          // refuses to generate a slip for a credit outside their shop.
          actorShopId: 'shop-other-tenant',
          documentPresenter: presenter.call,
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
      expect(error.data, contains('could not be generated'));
      expect(error.data, isNot(contains('PermissionDeniedException')));

      // No document was handed over and no draft audit event was queued.
      expect(presenter.bytes, isNull);
      final syncEntries = await db.select(db.syncQueue).get();
      expect(
        syncEntries.where((e) => e.actionType == 'generate_credit_draft'),
        isEmpty,
      );

      await db.close();
    });
  });
}
