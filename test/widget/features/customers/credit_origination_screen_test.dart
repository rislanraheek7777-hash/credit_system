import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_dao.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';
import 'package:credit_system/features/collateral/presentation/collateral_registration_screen.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:credit_system/features/customers/domain/models/credit_term.dart';
import 'package:credit_system/features/customers/domain/services/credit_submission_idempotency.dart';
import 'package:credit_system/features/customers/presentation/credit_origination_screen.dart';

import '../../../support/customers_test_support.dart';

const String shopId = '11111111-1111-1111-1111-111111111201';
const customerId = 1;
const String staffId = '11111111-1111-1111-1111-111111111203';
const String itemOneId = 'coll-item-1';
const String itemTwoId = 'coll-item-2';

/// Pumps until the screen shows an inline error, or the origination route
/// closes after a successful submission, and returns the outcome.
///
/// A successful submission closes the route with the created agreement as its
/// result, so the screen itself is gone by the time the outcome is known. The
/// error text is included so a failure is legible.
Future<String> pumpUntilOutcome(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    final error = find.byKey(const Key('origination_error_display'));
    if (error.evaluate().isNotEmpty) {
      return 'error: ${tester.widget<Text>(error).data}';
    }
    if (find.byType(CreditOriginationScreen).evaluate().isEmpty) {
      return 'success';
    }
  }
  fail('pumpUntilOutcome: the route never closed and no error was displayed.');
}

/// Pumps until the origination form is on screen and the pushed route's
/// transition has settled, so every control is hit-testable.
Future<void> pumpUntilFormReady(WidgetTester tester) async {
  await pumpUntil(
    tester,
    () => find.byKey(const Key('submit_credit_button')).evaluate().isNotEmpty,
  );
  await tester.pumpAndSettle();
}

/// Hosts the origination screen over a dummy home route.
///
/// The origination screen closes itself with the created agreement once the
/// submission succeeds, so it needs a route underneath to pop back to. The
/// agreement it closed with is captured in [poppedCredit].
class _OriginationHost extends StatefulWidget {
  const _OriginationHost({
    required this.shopId,
    required this.customerId,
    required this.currentUser,
    required this.database,
    this.idempotency,
  });

  final String shopId;
  final int customerId;
  final AppUser currentUser;
  final AppDatabase database;
  final CreditSubmissionIdempotency? idempotency;

  @override
  State<_OriginationHost> createState() => _OriginationHostState();
}

class _OriginationHostState extends State<_OriginationHost> {
  /// The agreement the origination route closed with, if any.
  Credit? poppedCredit;

  /// Opens the origination screen over the dummy home route.
  void openOrigination() {
    Navigator.of(context)
        .push<Credit>(
          MaterialPageRoute(
            builder: (_) => CreditOriginationScreen(
              shopId: widget.shopId,
              customerId: widget.customerId,
              currentUser: widget.currentUser,
              database: widget.database,
              idempotency: widget.idempotency,
            ),
          ),
        )
        .then((credit) {
          if (!mounted) return;
          setState(() => poppedCredit = credit);
        });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) openOrigination();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          poppedCredit == null
              ? 'Origination Host'
              : 'Created ${poppedCredit!.id}',
        ),
      ),
    );
  }
}

void main() {
  late AppDatabase db;

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);

    final now = DateTime.now().toUtc();
    await db
        .into(db.shops)
        .insert(
          ShopEntry(
            id: shopId,
            name: 'Origination Test Shop',
            currencyCode: 'LKR',
            timezone: 'Asia/Colombo',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.appUsers)
        .insert(
          AppUserEntry(
            id: staffId,
            shopId: shopId,
            username: 'origination.cashier',
            fullName: 'Origination Cashier',
            role: 'cashier',
            isActive: true,
            sessionVersion: 1,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.customers)
        .insert(
          CustomerEntry(
            id: customerId,
            shopId: shopId,
            fullName: 'Origination Customer',
            nic: '851234567V',
            phone: '0771234567',
            address: '1 Test Street',
            createdAt: now,
            updatedAt: now,
          ),
        );

    final collateralDao = CollateralDao(db);
    await collateralDao.createCollateralItem(
      CollateralItem(
        id: itemOneId,
        shopId: shopId,
        customerId: customerId,
        itemReferenceId: 'COLL-ORIG-001',
        category: CollateralItemCategory.gold,
        description: '22K gold necklace',
        conditionGrade: 'Like New',
        weightMilligrams: 5500,
        estimatedValueCents: 1500000,
      ),
    );
    await collateralDao.createCollateralItem(
      CollateralItem(
        id: itemTwoId,
        shopId: shopId,
        customerId: customerId,
        itemReferenceId: 'COLL-ORIG-002',
        category: CollateralItemCategory.electronics,
        description: 'Laptop',
        conditionGrade: 'Good',
        weightMilligrams: 1500000,
        estimatedValueCents: 400000,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  AppUser cashier() => AppUser(
    id: staffId,
    shopId: shopId,
    username: 'origination.cashier',
    fullName: 'Origination Cashier',
    role: AppRole.cashier,
    isActive: true,
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    AppUser? actor,
    CreditSubmissionIdempotency? idempotency,
    String? shop,
    int? customer,
  }) async {
    // The origination form is taller than the default 800x600 test surface, so
    // enlarge the viewport to keep every control reachable without scrolling.
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: _OriginationHost(
          shopId: shop ?? shopId,
          customerId: customer ?? customerId,
          currentUser: actor ?? cashier(),
          database: db,
          idempotency: idempotency,
        ),
      ),
    );
    await pumpUntilFormReady(tester);
  }

  /// The agreement the origination route closed with, if any.
  Credit? poppedCredit(WidgetTester tester) => tester
      .state<_OriginationHostState>(find.byType(_OriginationHost))
      .poppedCredit;

  group('CreditOriginationScreen - preset terms (AC-1)', () {
    testWidgets(
      'renders the origination form with all three approved presets',
      (tester) async {
        await pumpScreen(tester);

        expect(find.byKey(const Key('term_preset_30')), findsOneWidget);
        expect(find.byKey(const Key('term_preset_60')), findsOneWidget);
        expect(find.byKey(const Key('term_preset_90')), findsOneWidget);
        expect(find.byKey(const Key('term_custom')), findsOneWidget);
      },
    );

    testWidgets('no preliminary due date is shown before a term is selected', (
      tester,
    ) async {
      await pumpScreen(tester);

      final summary = find.byKey(const Key('preliminary_due_date_display'));
      expect(summary, findsOneWidget);
      expect(find.textContaining(preliminaryDueDateLabel), findsOneWidget);
      expect(tester.widget<Text>(summary).data, contains('Not selected'));
    });

    for (final preset in CreditTermPreset.values) {
      testWidgets('selecting the ${preset.calendarDays} day preset displays the '
          'preliminary due date (Pending Disbursement)', (tester) async {
        await pumpScreen(tester);

        await tester.tap(find.byKey(Key('term_preset_${preset.calendarDays}')));
        await tester.pump();

        final summary = tester.widget<Text>(
          find.byKey(const Key('preliminary_due_date_display')),
        );
        expect(summary.data, startsWith(preliminaryDueDateLabel));

        // The displayed date is the creation date + preset calendar days in the
        // shop's time zone.
        final credits = await db.select(db.credits).get();
        expect(credits, isEmpty);

        final zone = ShopTimeZone.defaultTimeZone();
        final createdDate = zone.localDateOf(DateTime.now().toUtc());
        final expected = createdDate.addDays(preset.calendarDays);
        expect(summary.data, contains(expected.isoDate));
      });
    }

    testWidgets('the summary reports the selected term', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('term_preset_60')));
      await tester.pump();

      expect(
        tester
            .widget<Text>(find.byKey(const Key('selected_term_display')))
            .data,
        contains('60 Days'),
      );
    });
  });

  group('CreditOriginationScreen - custom due date (AC-2)', () {
    testWidgets('accepts a custom date strictly after the creation date', (
      tester,
    ) async {
      await pumpScreen(tester);

      final zone = ShopTimeZone.defaultTimeZone();
      final creationDate = zone.localDateOf(DateTime.now().toUtc());
      final custom = creationDate.addDays(5).isoDate;

      await tester.enterText(
        find.byKey(const Key('custom_due_date_field')),
        custom,
      );
      await tester.tap(find.byKey(const Key('apply_custom_due_date_button')));
      await tester.pump();

      expect(
        tester
            .widget<Text>(find.byKey(const Key('preliminary_due_date_display')))
            .data,
        contains(custom),
      );
      expect(find.byKey(const Key('origination_error_display')), findsNothing);
    });

    testWidgets('rejects a same-day custom date', (tester) async {
      await pumpScreen(tester);

      final zone = ShopTimeZone.defaultTimeZone();
      final creationDate = zone.localDateOf(DateTime.now().toUtc());

      await tester.enterText(
        find.byKey(const Key('custom_due_date_field')),
        creationDate.isoDate,
      );
      await tester.tap(find.byKey(const Key('apply_custom_due_date_button')));
      await tester.pump();

      expect(
        find.byKey(const Key('origination_error_display')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('preliminary_due_date_display')))
            .data,
        contains('Not selected'),
      );
    });

    testWidgets('rejects a past custom date', (tester) async {
      await pumpScreen(tester);

      final zone = ShopTimeZone.defaultTimeZone();
      final creationDate = zone.localDateOf(DateTime.now().toUtc());
      final past = creationDate.addDays(-3).isoDate;

      await tester.enterText(
        find.byKey(const Key('custom_due_date_field')),
        past,
      );
      await tester.tap(find.byKey(const Key('apply_custom_due_date_button')));
      await tester.pump();

      expect(
        find.byKey(const Key('origination_error_display')),
        findsOneWidget,
      );
    });

    testWidgets('rejects a malformed custom date', (tester) async {
      await pumpScreen(tester);

      await tester.enterText(
        find.byKey(const Key('custom_due_date_field')),
        '30-11-2026',
      );
      await tester.tap(find.byKey(const Key('apply_custom_due_date_button')));
      await tester.pump();

      expect(
        find.byKey(const Key('origination_error_display')),
        findsOneWidget,
      );
    });
  });

  group('CreditOriginationScreen - live summary (AC-3 / UX-DR-4)', () {
    testWidgets('the total estimated collateral value updates as items are '
        'selected and deselected', (tester) async {
      await pumpScreen(tester);

      Text totalText() => tester.widget<Text>(
        find.byKey(const Key('total_collateral_value_display')),
      );

      expect(
        totalText().data,
        startsWith('Total Estimated Item Receipt Value:'),
      );
      expect(totalText().data, contains('0.00'));

      await tester.tap(find.byKey(Key('collateral_item_$itemOneId')));
      await tester.pump();
      expect(totalText().data, contains('15,000.00'));

      await tester.tap(find.byKey(Key('collateral_item_$itemTwoId')));
      await tester.pump();
      expect(totalText().data, contains('19,000.00'));

      await tester.tap(find.byKey(Key('collateral_item_$itemOneId')));
      await tester.pump();
      expect(totalText().data, contains('4,000.00'));
    });

    testWidgets('the preliminary due date updates when the term changes', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('term_preset_30')));
      await tester.pump();
      final first = tester
          .widget<Text>(find.byKey(const Key('preliminary_due_date_display')))
          .data;

      await tester.tap(find.byKey(const Key('term_preset_90')));
      await tester.pump();
      final second = tester
          .widget<Text>(find.byKey(const Key('preliminary_due_date_display')))
          .data;

      expect(first, isNot(equals(second)));
    });
  });

  group('CreditOriginationScreen - submission (F4, F3)', () {
    testWidgets(
      'creates exactly one credit through createCreditAgreement and binds '
      'the pledged collateral',
      (tester) async {
        await pumpScreen(tester);

        await tester.enterText(
          find.byKey(const Key('principal_amount_field')),
          '5000.00',
        );
        await tester.tap(find.byKey(const Key('term_preset_30')));
        await tester.pump();
        await tester.tap(find.byKey(Key('collateral_item_$itemOneId')));
        await tester.pump();

        await tester.tap(find.byKey(const Key('submit_credit_button')));
        final outcome = await pumpUntilOutcome(tester);
        expect(
          outcome,
          equals('success'),
          reason: 'Submission failed with: $outcome',
        );

        final credits = await db.select(db.credits).get();
        expect(credits.length, equals(1));
        expect(credits.first.principalCents, equals(500000));
        expect(
          credits.first.balanceCents,
          equals(500000),
          reason: 'Zero-interest: the balance equals the principal exactly.',
        );
        expect(credits.first.shopId, equals(shopId));
        expect(credits.first.customerId, equals(customerId));
        expect(credits.first.workflowStatus, equals('pending_disbursement'));

        // The route closed with the created agreement as its result.
        final created = poppedCredit(tester);
        expect(
          created,
          isNotNull,
          reason: 'A successful submission must close the route.',
        );
        expect(created!.id, equals(credits.first.id));

        // The pledged item is bound to the new agreement.
        final item = await db.select(db.collateralItems).get();
        final bound = item.firstWhere((i) => i.id == itemOneId);
        expect(bound.creditId, equals(credits.first.id));

        // Exactly one audit/sync record was written.
        final auditRows = await db.select(db.syncQueue).get();
        expect(auditRows.length, equals(1));
        expect(auditRows.first.entityType, equals('credit'));
        expect(auditRows.first.entityId, equals(credits.first.id));
      },
    );

    testWidgets('the stored due date is the creation date plus the preset '
        'calendar days in the shop time zone', (tester) async {
      await pumpScreen(tester);

      await tester.enterText(
        find.byKey(const Key('principal_amount_field')),
        '5000.00',
      );
      await tester.tap(find.byKey(const Key('term_preset_60')));
      await tester.pump();
      await tester.tap(find.byKey(Key('collateral_item_$itemOneId')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('submit_credit_button')));
      final outcome = await pumpUntilOutcome(tester);
      expect(
        outcome,
        equals('success'),
        reason: 'Submission failed with: $outcome',
      );

      final credits = await db.select(db.credits).get();
      final zone = ShopTimeZone.defaultTimeZone();
      final creation = zone.localDateOf(credits.first.createdAt);
      final expected = creation.addDays(60);
      expect(zone.localDateOf(credits.first.dueDate), equals(expected));
    });

    testWidgets('an actor without createCredits is rejected by the DAO and no '
        'credit is created (actor propagation, F4)', (tester) async {
      final unprivileged = AppUser(
        id: staffId,
        shopId: shopId,
        username: 'origination.viewer',
        fullName: 'Origination Viewer',
        role: AppRole.custom,
        customPermissions: const {},
        isActive: true,
      );

      await pumpScreen(tester, actor: unprivileged);

      await tester.enterText(
        find.byKey(const Key('principal_amount_field')),
        '5000.00',
      );
      await tester.tap(find.byKey(const Key('term_preset_30')));
      await tester.pump();
      await tester.tap(find.byKey(Key('collateral_item_$itemOneId')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('submit_credit_button')));
      await pumpUntil(
        tester,
        () => find
            .byKey(const Key('origination_error_display'))
            .evaluate()
            .isNotEmpty,
      );

      final credits = await db.select(db.credits).get();
      expect(credits, isEmpty);
      final auditRows = await db.select(db.syncQueue).get();
      expect(auditRows, isEmpty);
    });

    testWidgets('a deactivated actor is rejected and no credit is created '
        '(actor propagation, F4)', (tester) async {
      final deactivated = AppUser(
        id: staffId,
        shopId: shopId,
        username: 'origination.cashier',
        fullName: 'Origination Cashier',
        role: AppRole.cashier,
        isActive: false,
      );

      await pumpScreen(tester, actor: deactivated);

      await tester.enterText(
        find.byKey(const Key('principal_amount_field')),
        '5000.00',
      );
      await tester.tap(find.byKey(const Key('term_preset_30')));
      await tester.pump();
      await tester.tap(find.byKey(Key('collateral_item_$itemOneId')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('submit_credit_button')));
      await pumpUntil(
        tester,
        () => find
            .byKey(const Key('origination_error_display'))
            .evaluate()
            .isNotEmpty,
      );

      expect(await db.select(db.credits).get(), isEmpty);
    });

    testWidgets('creates a credit with zero item receipts', (tester) async {
      await pumpScreen(tester);

      // The section uses the Item Receipt terminology.
      expect(find.text('Item Receipts'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('principal_amount_field')),
        '5000.00',
      );
      await tester.tap(find.byKey(const Key('term_preset_30')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('submit_credit_button')));
      final outcome = await pumpUntilOutcome(tester);
      expect(
        outcome,
        equals('success'),
        reason: 'Zero-item origination failed with: $outcome',
      );

      final credits = await db.select(db.credits).get();
      expect(credits.length, equals(1));
      expect(credits.first.principalCents, equals(500000));
      expect(credits.first.balanceCents, equals(500000));

      // No item was bound to the new agreement.
      final items = await db.select(db.collateralItems).get();
      expect(
        items.every((i) => i.creditId == null),
        isTrue,
        reason: 'No item receipt may be bound when none was selected.',
      );
    });

    testWidgets('renders an Add Item Receipt button under the Item Receipts '
        'section', (tester) async {
      await pumpScreen(tester);

      expect(find.text('Item Receipts'), findsOneWidget);
      expect(find.byKey(const Key('add_item_receipt_button')), findsOneWidget);
    });

    testWidgets('registering an item from the receipt flow returns to the '
        'origination screen with a confirmation naming the item and the new '
        'receipt listed unchecked', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('add_item_receipt_button')));
      await tester.pumpAndSettle();
      expect(find.byType(CollateralRegistrationScreen), findsOneWidget);

      final registrationFields = find.descendant(
        of: find.byType(CollateralRegistrationScreen),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(registrationFields.at(0), 'COLL-NEW-001');
      await tester.enterText(registrationFields.at(4), '2500.00');

      await tester.ensureVisible(find.byKey(const Key('category_chip_gold')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gold'));
      await tester.pumpAndSettle();

      final registerButton = find.byKey(
        const Key('register_collateral_button'),
      );
      await tester.ensureVisible(registerButton);
      await tester.pumpAndSettle();
      await tester.tap(registerButton);
      await tester.pumpAndSettle();

      // The registration route closed; origination is back on screen.
      expect(find.byType(CollateralRegistrationScreen), findsNothing);
      expect(find.byType(CreditOriginationScreen), findsOneWidget);

      // A SnackBar confirms the registration and names the item.
      expect(
        find.text('Item Receipt "COLL-NEW-001" registered.'),
        findsOneWidget,
      );

      // The new receipt appears in the list, unchecked, and nothing was
      // auto-selected, so the credit type stays Cash.
      expect(find.text('COLL-NEW-001'), findsOneWidget);
      final tile = tester.widget<CheckboxListTile>(
        find.byKey(const Key('collateral_item_COLL-NEW-001')),
      );
      expect(tile.value, isFalse);
      expect(
        tester.widget<Text>(find.byKey(const Key('credit_type_display'))).data,
        'Cash',
      );
    });

    testWidgets('tapping Add Item Receipt navigates to the collateral '
        'registration screen', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('add_item_receipt_button')));
      await tester.pumpAndSettle();

      expect(find.byType(CollateralRegistrationScreen), findsOneWidget);

      // Return to the origination screen; the item list is reloaded on return.
      Navigator.of(tester.element(find.byType(CollateralRegistrationScreen)))
          .pop();
      await tester.pumpAndSettle();

      expect(find.byType(CollateralRegistrationScreen), findsNothing);

      // A back-out closes the route with no result, so no confirmation
      // SnackBar is shown.
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('staff can register a second receipt after the first and '
        'both appear in the list, unchecked', (tester) async {
      await pumpScreen(tester);

      Future<void> registerReceipt(String ref, String amount) async {
        await tester.tap(find.byKey(const Key('add_item_receipt_button')));
        await tester.pumpAndSettle();
        expect(find.byType(CollateralRegistrationScreen), findsOneWidget);

        final fields = find.descendant(
          of: find.byType(CollateralRegistrationScreen),
          matching: find.byType(TextFormField),
        );
        await tester.enterText(fields.at(0), ref);
        await tester.enterText(fields.at(4), amount);
        await tester.ensureVisible(
          find.byKey(const Key('category_chip_gold')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('category_chip_gold')));
        await tester.pumpAndSettle();

        final registerButton = find.byKey(
          const Key('register_collateral_button'),
        );
        await tester.ensureVisible(registerButton);
        await tester.pumpAndSettle();
        await tester.tap(registerButton);
        await tester.pumpAndSettle();
      }

      await registerReceipt('COLL-NEW-101', '1000.00');
      expect(
        find.text('Item Receipt "COLL-NEW-101" registered.'),
        findsOneWidget,
      );

      await registerReceipt('COLL-NEW-102', '2000.00');
      // ScaffoldMessenger queues SnackBars: letting the 4s first SnackBar
      // elapse lets the second take its place before asserting on it.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(
        find.text('Item Receipt "COLL-NEW-102" registered.'),
        findsOneWidget,
      );

      // Both receipts are listed, unchecked, and neither was auto-selected.
      for (final ref in ['COLL-NEW-101', 'COLL-NEW-102']) {
        expect(find.text(ref), findsOneWidget);
        final tile = tester.widget<CheckboxListTile>(
          find.byKey(Key('collateral_item_$ref')),
        );
        expect(tile.value, isFalse);
      }
    });

    testWidgets(
      'shows the optional item receipt empty state when the customer has no '
      'registered items',
      (tester) async {
        await (db.delete(db.collateralItems)).go();
        await pumpScreen(tester);

        expect(find.text('Item Receipts'), findsOneWidget);
        expect(
          find.text(
            'No item receipts recorded for this customer. '
            'Item receipts are optional.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('submission is blocked when no term is selected', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.enterText(
        find.byKey(const Key('principal_amount_field')),
        '5000.00',
      );
      await tester.tap(find.byKey(Key('collateral_item_$itemOneId')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('submit_credit_button')));
      await pumpUntil(
        tester,
        () => find
            .byKey(const Key('origination_error_display'))
            .evaluate()
            .isNotEmpty,
      );

      expect(await db.select(db.credits).get(), isEmpty);
    });

    testWidgets('submission is blocked for a non-positive principal', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.enterText(
        find.byKey(const Key('principal_amount_field')),
        '0',
      );
      await tester.tap(find.byKey(const Key('term_preset_30')));
      await tester.pump();
      await tester.tap(find.byKey(Key('collateral_item_$itemOneId')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('submit_credit_button')));
      await tester.pump();

      expect(await db.select(db.credits).get(), isEmpty);
    });
    testWidgets('the draft agreement action is not offered on the origination '
        'screen — it relocates to the credit lists', (tester) async {
      // An actor without createCredits is refused by the DAO, so the
      // submission fails and the origination screen stays mounted. That is
      // the only way to inspect the screen after a submission attempt: a
      // successful submission closes the route.
      final unprivileged = AppUser(
        id: staffId,
        shopId: shopId,
        username: 'origination.viewer',
        fullName: 'Origination Viewer',
        role: AppRole.custom,
        customPermissions: const {},
        isActive: true,
      );

      await pumpScreen(tester, actor: unprivileged);

      await tester.enterText(
        find.byKey(const Key('principal_amount_field')),
        '5000.00',
      );
      await tester.tap(find.byKey(const Key('term_preset_30')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('submit_credit_button')));
      await pumpUntil(
        tester,
        () => find
            .byKey(const Key('origination_error_display'))
            .evaluate()
            .isNotEmpty,
      );

      // The screen is still open, and it offers no draft agreement action.
      expect(find.byType(CreditOriginationScreen), findsOneWidget);
      expect(
        find.byKey(const Key('view_draft_agreement_button')),
        findsNothing,
      );
      expect(find.text('View Draft Agreement'), findsNothing);
    });
  });

  group('CreditOriginationScreen - idempotency key lifecycle (F3)', () {
    testWidgets(
      'a retry of an unchanged failed submission reuses the same key',
      (tester) async {
        final idempotency = CreditSubmissionIdempotency();
        await pumpScreen(tester, idempotency: idempotency);

        await tester.enterText(
          find.byKey(const Key('principal_amount_field')),
          '5000.00',
        );
        await tester.tap(find.byKey(const Key('term_preset_30')));
        await tester.pump();
        await tester.tap(find.byKey(Key('collateral_item_$itemOneId')));
        await tester.pump();

        // Pre-pledge the item so the first attempt fails in the DAO.
        await db
            .into(db.credits)
            .insert(
              CreditEntry(
                id: '11111111-1111-1111-1111-111111111299',
                shopId: shopId,
                customerId: customerId,
                principalCents: 100000,
                balanceCents: 100000,
                status: 'active',
                workflowStatus: 'disbursed',
                dueDate: DateTime.now().toUtc().add(const Duration(days: 30)),
                createdAt: DateTime.now().toUtc(),
                correctionPending: false,
                creditType: 'cash',
              ),
            );
        await (db.update(
          db.collateralItems,
        )..where((c) => c.id.equals(itemOneId))).write(
          const CollateralItemsCompanion(
            creditId: Value('11111111-1111-1111-1111-111111111299'),
          ),
        );

        await tester.tap(find.byKey(const Key('submit_credit_button')));
        await pumpUntil(
          tester,
          () => find
              .byKey(const Key('origination_error_display'))
              .evaluate()
              .isNotEmpty,
        );

        final keyAfterFailure = idempotency.currentKey;
        expect(keyAfterFailure, isNotNull);
        expect(
          await db.select(db.credits).get(),
          hasLength(1),
          reason:
              'Only the pre-existing fixture credit is present; the failed '
              'submission must not have created an agreement.',
        );
        expect(
          await db.select(db.syncQueue).get(),
          isEmpty,
          reason: 'The failed submission must not have left an audit record.',
        );

        // Release the item and retry the unchanged submission.
        await (db.update(db.collateralItems)
              ..where((c) => c.id.equals(itemOneId)))
            .write(const CollateralItemsCompanion(creditId: Value(null)));

        await tester.tap(find.byKey(const Key('submit_credit_button')));
        final retryOutcome = await pumpUntilOutcome(tester);
        expect(
          retryOutcome,
          equals('success'),
          reason: 'The retried submission failed with: $retryOutcome',
        );

        // The successful attempt used the SAME key as the failed attempt.
        final auditRows = await db.select(db.syncQueue).get();
        expect(auditRows.length, equals(1));
        expect(
          auditRows.first.idempotencyKey,
          equals(keyAfterFailure),
          reason: 'A retry of an unchanged submission must reuse its key.',
        );

        final credits = await db.select(db.credits).get();
        expect(
          credits.length,
          equals(2),
          reason: 'The fixture credit plus exactly one created agreement.',
        );
      },
    );

    testWidgets('a new submission after a success receives a fresh key', (
      tester,
    ) async {
      final idempotency = CreditSubmissionIdempotency();
      await pumpScreen(tester, idempotency: idempotency);

      await tester.enterText(
        find.byKey(const Key('principal_amount_field')),
        '5000.00',
      );
      await tester.tap(find.byKey(const Key('term_preset_30')));
      await tester.pump();
      await tester.tap(find.byKey(Key('collateral_item_$itemOneId')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('submit_credit_button')));
      final outcome = await pumpUntilOutcome(tester);
      expect(
        outcome,
        equals('success'),
        reason: 'Submission failed with: $outcome',
      );

      final firstKey =
          (await db.select(db.syncQueue).get()).first.idempotencyKey;
      expect(
        idempotency.currentKey,
        isNull,
        reason: 'The key is cleared after a successful agreement.',
      );

      // The successful submission closed the route, so a genuinely new
      // submission is made from a freshly opened origination screen that shares
      // the same idempotency-key manager.
      tester
          .state<_OriginationHostState>(find.byType(_OriginationHost))
          .openOrigination();
      await pumpUntilFormReady(tester);

      // A genuinely new submission (different principal) must not reuse the key.
      await tester.enterText(
        find.byKey(const Key('principal_amount_field')),
        '9000.00',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('term_preset_30')));
      await tester.pump();
      // Pledging the item again fails — it is already bound to the agreement
      // created above — so the submission stays on the screen.
      await tester.tap(find.byKey(Key('collateral_item_$itemOneId')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('submit_credit_button')));
      await pumpUntil(
        tester,
        () => find
            .byKey(const Key('origination_error_display'))
            .evaluate()
            .isNotEmpty,
      );

      final secondKey = idempotency.currentKey;
      expect(secondKey, isNotNull);
      expect(
        secondKey,
        isNot(equals(firstKey)),
        reason: 'A new submission must receive a fresh idempotency key.',
      );
    });
  });

  group('CreditOriginationSummary - shop time zone rendering (H-1)', () {
    // 2026-05-14T15:00Z is 2026-05-15 in Asia/Tokyo (UTC+9) but 2026-05-14
    // in Asia/Colombo (UTC+05:30), so the two zones disagree on the calendar
    // day. This is the exact condition under which the H-1 defect was
    // observable.
    final instantWhereZonesDisagree = DateTime.utc(2026, 5, 14, 15);

    testWidgets('renders the preliminary due date in the shop time zone, not '
        'the default zone', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CreditOriginationSummary(
              term: const CreditTerm.preset(CreditTermPreset.thirtyDays),
              preliminaryDueDate: instantWhereZonesDisagree,
              totalCollateralValueCents: 1500000,
              currencyCode: 'LKR',
              timeZoneIdentifier: 'Asia/Tokyo',
            ),
          ),
        ),
      );
      await tester.pump();

      final displayed = tester
          .widget<Text>(find.byKey(const Key('preliminary_due_date_display')))
          .data!;

      expect(
        displayed,
        contains('2026-05-15'),
        reason:
            'The date must be rendered in the shop time zone '
            '(Asia/Tokyo).',
      );
      expect(
        displayed,
        isNot(contains('2026-05-14')),
        reason: 'Rendering in the default Asia/Colombo zone is the H-1 defect.',
      );
    });

    testWidgets('falls back to the approved default when the configured zone '
        'cannot be resolved', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CreditOriginationSummary(
              term: const CreditTerm.preset(CreditTermPreset.thirtyDays),
              preliminaryDueDate: instantWhereZonesDisagree,
              totalCollateralValueCents: 1500000,
              currencyCode: 'LKR',
              timeZoneIdentifier: 'Not/A_Zone',
            ),
          ),
        ),
      );
      await tester.pump();

      final displayed = tester
          .widget<Text>(find.byKey(const Key('preliminary_due_date_display')))
          .data!;
      expect(
        displayed,
        contains('2026-05-14'),
        reason:
            'An unresolvable zone falls back to Asia/Colombo, matching '
            'the origination screen.',
      );
    });
  });

  group('CreditOriginationScreen - non-default shop time zone (H-1)', () {
    const String tokyoShopId = '11111111-1111-1111-1111-111111111211';
    const tokyoCustomerId = 2;
    const String tokyoStaffId = '11111111-1111-1111-1111-111111111213';
    const String tokyoItemId = 'coll-tokyo-1';

    setUp(() async {
      final now = DateTime.now().toUtc();
      await db
          .into(db.shops)
          .insert(
            ShopEntry(
              id: tokyoShopId,
              name: 'Tokyo Test Shop',
              currencyCode: 'LKR',
              timezone: 'Asia/Tokyo',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.appUsers)
          .insert(
            AppUserEntry(
              id: tokyoStaffId,
              shopId: tokyoShopId,
              username: 'tokyo.cashier',
              fullName: 'Tokyo Cashier',
              role: 'cashier',
              isActive: true,
              sessionVersion: 1,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.customers)
          .insert(
            CustomerEntry(
              id: tokyoCustomerId,
              shopId: tokyoShopId,
              fullName: 'Tokyo Customer',
              nic: '951234567V',
              phone: '0772223333',
              address: '2 Shibuya Street',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await CollateralDao(db).createCollateralItem(
        CollateralItem(
          id: tokyoItemId,
          shopId: tokyoShopId,
          customerId: tokyoCustomerId,
          itemReferenceId: 'COLL-TYO-001',
          category: CollateralItemCategory.gold,
          description: '22K gold bangle',
          conditionGrade: 'Like New',
          weightMilligrams: 9000,
          estimatedValueCents: 2000000,
        ),
      );
    });

    testWidgets('the summary displays the same calendar date that is persisted '
        'for the credit', (tester) async {
      final tokyoZone = ShopTimeZone('Asia/Tokyo');
      final colomboZone = ShopTimeZone.defaultTimeZone();

      await pumpScreen(
        tester,
        shop: tokyoShopId,
        customer: tokyoCustomerId,
        actor: AppUser(
          id: tokyoStaffId,
          shopId: tokyoShopId,
          username: 'tokyo.cashier',
          fullName: 'Tokyo Cashier',
          role: AppRole.cashier,
          isActive: true,
        ),
      );

      await tester.enterText(
        find.byKey(const Key('principal_amount_field')),
        '5000.00',
      );
      await tester.tap(find.byKey(const Key('term_preset_30')));
      await tester.pump();
      await tester.tap(find.byKey(Key('collateral_item_$tokyoItemId')));
      await tester.pump();

      // The live preview must already show the shop-zone calendar date.
      final previewed = tester
          .widget<Text>(find.byKey(const Key('preliminary_due_date_display')))
          .data!;
      final colomboRendering = colomboZone
          .localDateOf(
            tokyoZone.instantAtStartOfDay(
              tokyoZone.localDateOf(DateTime.now().toUtc()).addDays(30),
            ),
          )
          .isoDate;
      expect(
        previewed,
        isNot(contains(colomboRendering)),
        reason:
            'A Tokyo shop must not preview the due date in the '
            'Asia/Colombo calendar.',
      );

      await tester.tap(find.byKey(const Key('submit_credit_button')));
      final outcome = await pumpUntilOutcome(tester);
      expect(
        outcome,
        equals('success'),
        reason: 'Submission failed with: $outcome',
      );

      final credits = await db.select(db.credits).get();
      expect(credits.length, equals(1));

      // The persisted due date rendered in the shop zone must be exactly the
      // date the summary previewed.
      final shopZoneDate = tokyoZone.localDateOf(credits.first.dueDate).isoDate;
      expect(
        previewed,
        contains(shopZoneDate),
        reason: 'The summary must display the due date in the shop zone.',
      );

      // The route closed with the created agreement, whose due date is the
      // same calendar date the summary previewed.
      final created = poppedCredit(tester);
      expect(
        created,
        isNotNull,
        reason: 'A successful submission must close the route.',
      );
      expect(
        tokyoZone.localDateOf(created!.dueDate).isoDate,
        equals(shopZoneDate),
        reason: 'The closed route must carry the shop-zone due date.',
      );
    });
  });
}
