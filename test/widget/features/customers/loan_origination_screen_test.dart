import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_dao.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';
import 'package:credit_system/features/customers/domain/models/loan_term.dart';
import 'package:credit_system/features/customers/domain/services/loan_submission_idempotency.dart';
import 'package:credit_system/features/customers/presentation/loan_origination_screen.dart';

const String shopId = '11111111-1111-1111-1111-111111111201';
const String customerId = '11111111-1111-1111-1111-111111111202';
const String staffId = '11111111-1111-1111-1111-111111111203';
const String itemOneId = 'coll-item-1';
const String itemTwoId = 'coll-item-2';

/// Pumps until [condition] holds, so asynchronous Drift work completes before
/// assertions instead of relying on arbitrary delays.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxIterations = 100,
}) async {
  for (var i = 0; i < maxIterations; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (condition()) return;
  }
  fail('pumpUntil: condition never became true within $maxIterations pumps.');
}

/// Pumps until the screen shows either a success or an error outcome and
/// returns the outcome. The error text is included so a failure is legible.
Future<String> pumpUntilOutcome(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    final success = find.byKey(const Key('origination_success_display'));
    if (success.evaluate().isNotEmpty) {
      return 'success';
    }
    final error = find.byKey(const Key('origination_error_display'));
    if (error.evaluate().isNotEmpty) {
      return 'error: ${tester.widget<Text>(error).data}';
    }
  }
  fail('pumpUntilOutcome: neither a success nor an error was displayed.');
}

void main() {
  late AppDatabase db;

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);

    final now = DateTime.now().toUtc();
    await db.into(db.shops).insert(
      ShopEntry(
        id: shopId,
        name: 'Origination Test Shop',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.appUsers).insert(
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
    await db.into(db.customers).insert(
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
    await collateralDao.createCollateralItem(CollateralItem(
      id: itemOneId,
      shopId: shopId,
      customerId: customerId,
      itemReferenceId: 'COLL-ORIG-001',
      category: CollateralItemCategory.gold,
      description: '22K gold necklace',
      conditionGrade: 'Like New',
      weightMilligrams: 5500,
      estimatedValueCents: 1500000,
    ));
    await collateralDao.createCollateralItem(CollateralItem(
      id: itemTwoId,
      shopId: shopId,
      customerId: customerId,
      itemReferenceId: 'COLL-ORIG-002',
      category: CollateralItemCategory.electronics,
      description: 'Laptop',
      conditionGrade: 'Good',
      weightMilligrams: 1500000,
      estimatedValueCents: 400000,
    ));
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
    LoanSubmissionIdempotency? idempotency,
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
        home: LoanOriginationScreen(
          shopId: shopId,
          customerId: customerId,
          currentUser: actor ?? cashier(),
          database: db,
          idempotency: idempotency,
        ),
      ),
    );
    await pumpUntil(tester, () => find.byKey(const Key('submit_loan_button')).evaluate().isNotEmpty);
  }

  group('LoanOriginationScreen - preset terms (AC-1)', () {
    testWidgets('renders the origination form with all three approved presets',
        (tester) async {
      await pumpScreen(tester);

      expect(find.byKey(const Key('term_preset_30')), findsOneWidget);
      expect(find.byKey(const Key('term_preset_60')), findsOneWidget);
      expect(find.byKey(const Key('term_preset_90')), findsOneWidget);
      expect(find.byKey(const Key('term_custom')), findsOneWidget);
    });

    testWidgets('no preliminary due date is shown before a term is selected',
        (tester) async {
      await pumpScreen(tester);

      final summary = find.byKey(const Key('preliminary_due_date_display'));
      expect(summary, findsOneWidget);
      expect(
        find.textContaining(preliminaryDueDateLabel),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(summary).data,
        contains('Not selected'),
      );
    });

    for (final preset in LoanTermPreset.values) {
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
        final loans = await db.select(db.loans).get();
        expect(loans, isEmpty);

        final zone = ShopTimeZone.defaultTimeZone();
        final createdDate =
            zone.localDateOf(DateTime.now().toUtc());
        final expected = createdDate.addDays(preset.calendarDays);
        expect(summary.data, contains(expected.isoDate));
      });
    }

    testWidgets('the summary reports the selected term', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('term_preset_60')));
      await tester.pump();

      expect(
        tester.widget<Text>(find.byKey(const Key('selected_term_display'))).data,
        contains('60 Days'),
      );
    });
  });

  group('LoanOriginationScreen - custom due date (AC-2)', () {
    testWidgets('accepts a custom date strictly after the creation date',
        (tester) async {
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
        tester.widget<Text>(find.byKey(const Key('preliminary_due_date_display'))).data,
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

      expect(find.byKey(const Key('origination_error_display')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('preliminary_due_date_display'))).data,
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

      expect(find.byKey(const Key('origination_error_display')), findsOneWidget);
    });

    testWidgets('rejects a malformed custom date', (tester) async {
      await pumpScreen(tester);

      await tester.enterText(
        find.byKey(const Key('custom_due_date_field')),
        '30-11-2026',
      );
      await tester.tap(find.byKey(const Key('apply_custom_due_date_button')));
      await tester.pump();

      expect(find.byKey(const Key('origination_error_display')), findsOneWidget);
    });
  });

  group('LoanOriginationScreen - live summary (AC-3 / UX-DR-4)', () {
    testWidgets('the total estimated collateral value updates as items are '
        'selected and deselected', (tester) async {
      await pumpScreen(tester);

      Text totalText() => tester.widget<Text>(
            find.byKey(const Key('total_collateral_value_display')),
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

    testWidgets('the preliminary due date updates when the term changes',
        (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('term_preset_30')));
      await tester.pump();
      final first =
          tester.widget<Text>(find.byKey(const Key('preliminary_due_date_display'))).data;

      await tester.tap(find.byKey(const Key('term_preset_90')));
      await tester.pump();
      final second =
          tester.widget<Text>(find.byKey(const Key('preliminary_due_date_display'))).data;

      expect(first, isNot(equals(second)));
    });
  });

  group('LoanOriginationScreen - submission (F4, F3)', () {
    testWidgets('creates exactly one loan through createLoanAgreement and binds '
        'the pledged collateral', (tester) async {
      await pumpScreen(tester);

      await tester.enterText(
        find.byKey(const Key('principal_amount_field')),
        '5000.00',
      );
      await tester.tap(find.byKey(const Key('term_preset_30')));
      await tester.pump();
      await tester.tap(find.byKey(Key('collateral_item_$itemOneId')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('submit_loan_button')));
      final outcome = await pumpUntilOutcome(tester);
      expect(outcome, equals('success'),
          reason: 'Submission failed with: $outcome');

      final loans = await db.select(db.loans).get();
      expect(loans.length, equals(1));
      expect(loans.first.principalCents, equals(500000));
      expect(loans.first.balanceCents, equals(500000),
          reason: 'Zero-interest: the balance equals the principal exactly.');
      expect(loans.first.shopId, equals(shopId));
      expect(loans.first.customerId, equals(customerId));
      expect(loans.first.workflowStatus, equals('pending_disbursement'));

      // The pledged item is bound to the new agreement.
      final item = await db.select(db.collateralItems).get();
      final bound = item.firstWhere((i) => i.id == itemOneId);
      expect(bound.loanId, equals(loans.first.id));

      // Exactly one audit/sync record was written.
      final auditRows = await db.select(db.syncQueue).get();
      expect(auditRows.length, equals(1));
      expect(auditRows.first.entityType, equals('loan'));
      expect(auditRows.first.entityId, equals(loans.first.id));
    });

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

      await tester.tap(find.byKey(const Key('submit_loan_button')));
      await pumpUntil(tester, () => find.byKey(const Key('origination_success_display')).evaluate().isNotEmpty);

      final loans = await db.select(db.loans).get();
      final zone = ShopTimeZone.defaultTimeZone();
      final creation = zone.localDateOf(loans.first.createdAt);
      final expected = creation.addDays(60);
      expect(
        zone.localDateOf(loans.first.dueDate),
        equals(expected),
      );
    });

    testWidgets('an actor without createLoans is rejected by the DAO and no '
        'loan is created (actor propagation, F4)', (tester) async {
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

      await tester.tap(find.byKey(const Key('submit_loan_button')));
      await pumpUntil(tester, () => find.byKey(const Key('origination_error_display')).evaluate().isNotEmpty);

      final loans = await db.select(db.loans).get();
      expect(loans, isEmpty);
      final auditRows = await db.select(db.syncQueue).get();
      expect(auditRows, isEmpty);
    });

    testWidgets('a deactivated actor is rejected and no loan is created '
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

      await tester.tap(find.byKey(const Key('submit_loan_button')));
      await pumpUntil(tester, () => find.byKey(const Key('origination_error_display')).evaluate().isNotEmpty);

      expect(await db.select(db.loans).get(), isEmpty);
    });

    testWidgets('submission is blocked when no collateral item is selected',
        (tester) async {
      await pumpScreen(tester);

      await tester.enterText(
        find.byKey(const Key('principal_amount_field')),
        '5000.00',
      );
      await tester.tap(find.byKey(const Key('term_preset_30')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('submit_loan_button')));
      await pumpUntil(tester, () => find.byKey(const Key('origination_error_display')).evaluate().isNotEmpty);

      expect(await db.select(db.loans).get(), isEmpty);
    });

    testWidgets('submission is blocked when no term is selected',
        (tester) async {
      await pumpScreen(tester);

      await tester.enterText(
        find.byKey(const Key('principal_amount_field')),
        '5000.00',
      );
      await tester.tap(find.byKey(Key('collateral_item_$itemOneId')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('submit_loan_button')));
      await pumpUntil(tester, () => find.byKey(const Key('origination_error_display')).evaluate().isNotEmpty);

      expect(await db.select(db.loans).get(), isEmpty);
    });

    testWidgets('submission is blocked for a non-positive principal',
        (tester) async {
      await pumpScreen(tester);

      await tester.enterText(
        find.byKey(const Key('principal_amount_field')),
        '0',
      );
      await tester.tap(find.byKey(const Key('term_preset_30')));
      await tester.pump();
      await tester.tap(find.byKey(Key('collateral_item_$itemOneId')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('submit_loan_button')));
      await tester.pump();

      expect(await db.select(db.loans).get(), isEmpty);
    });
  });

  group('LoanOriginationScreen - idempotency key lifecycle (F3)', () {
    testWidgets('a retry of an unchanged failed submission reuses the same key',
        (tester) async {
      final idempotency = LoanSubmissionIdempotency();
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
      await db.into(db.loans).insert(
        LoanEntry(
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
        ),
      );
      await (db.update(db.collateralItems)
            ..where((c) => c.id.equals(itemOneId)))
          .write(const CollateralItemsCompanion(
        loanId: Value('11111111-1111-1111-1111-111111111299'),
      ));

      await tester.tap(find.byKey(const Key('submit_loan_button')));
      await pumpUntil(tester, () => find.byKey(const Key('origination_error_display')).evaluate().isNotEmpty);

      final keyAfterFailure = idempotency.currentKey;
      expect(keyAfterFailure, isNotNull);
      expect(await db.select(db.loans).get(), hasLength(1),
          reason: 'Only the pre-existing fixture loan is present; the failed '
              'submission must not have created an agreement.');
      expect(await db.select(db.syncQueue).get(), isEmpty,
          reason: 'The failed submission must not have left an audit record.');

      // Release the item and retry the unchanged submission.
      await (db.update(db.collateralItems)
            ..where((c) => c.id.equals(itemOneId)))
          .write(const CollateralItemsCompanion(loanId: Value(null)));

      await tester.tap(find.byKey(const Key('submit_loan_button')));
      await pumpUntil(tester, () => find.byKey(const Key('origination_success_display')).evaluate().isNotEmpty);

      // The successful attempt used the SAME key as the failed attempt.
      final auditRows = await db.select(db.syncQueue).get();
      expect(auditRows.length, equals(1));
      expect(auditRows.first.idempotencyKey, equals(keyAfterFailure),
          reason: 'A retry of an unchanged submission must reuse its key.');

      final loans = await db.select(db.loans).get();
      expect(loans.length, equals(2),
          reason: 'The fixture loan plus exactly one created agreement.');
    });

    testWidgets('a new submission after a success receives a fresh key',
        (tester) async {
      final idempotency = LoanSubmissionIdempotency();
      await pumpScreen(tester, idempotency: idempotency);

      await tester.enterText(
        find.byKey(const Key('principal_amount_field')),
        '5000.00',
      );
      await tester.tap(find.byKey(const Key('term_preset_30')));
      await tester.pump();
      await tester.tap(find.byKey(Key('collateral_item_$itemOneId')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('submit_loan_button')));
      await pumpUntil(tester, () => find.byKey(const Key('origination_success_display')).evaluate().isNotEmpty);

      final firstKey = (await db.select(db.syncQueue).get()).first.idempotencyKey;
      expect(idempotency.currentKey, isNull,
          reason: 'The key is cleared after a successful agreement.');

      // A genuinely new submission (different principal) must not reuse the key.
      await tester.enterText(
        find.byKey(const Key('principal_amount_field')),
        '9000.00',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('submit_loan_button')));
      await pumpUntil(tester, () => find.byKey(const Key('origination_error_display')).evaluate().isNotEmpty);

      final secondKey = idempotency.currentKey;
      expect(secondKey, isNotNull);
      expect(secondKey, isNot(equals(firstKey)),
          reason: 'A new submission must receive a fresh idempotency key.');
    });
  });

  group('LoanOriginationSummary - shop time zone rendering (H-1)', () {
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
            body: LoanOriginationSummary(
              term: const LoanTerm.preset(LoanTermPreset.thirtyDays),
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

      expect(displayed, contains('2026-05-15'),
          reason: 'The date must be rendered in the shop time zone '
              '(Asia/Tokyo).');
      expect(displayed, isNot(contains('2026-05-14')),
          reason: 'Rendering in the default Asia/Colombo zone is the H-1 defect.');
    });

    testWidgets('falls back to the approved default when the configured zone '
        'cannot be resolved', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LoanOriginationSummary(
              term: const LoanTerm.preset(LoanTermPreset.thirtyDays),
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
      expect(displayed, contains('2026-05-14'),
          reason: 'An unresolvable zone falls back to Asia/Colombo, matching '
              'the origination screen.');
    });
  });

  group('LoanOriginationScreen - non-default shop time zone (H-1)', () {
    const String tokyoShopId = '11111111-1111-1111-1111-111111111211';
    const String tokyoCustomerId = '11111111-1111-1111-1111-111111111212';
    const String tokyoStaffId = '11111111-1111-1111-1111-111111111213';
    const String tokyoItemId = 'coll-tokyo-1';

    setUp(() async {
      final now = DateTime.now().toUtc();
      await db.into(db.shops).insert(
        ShopEntry(
          id: tokyoShopId,
          name: 'Tokyo Test Shop',
          currencyCode: 'LKR',
          timezone: 'Asia/Tokyo',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db.into(db.appUsers).insert(
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
      await db.into(db.customers).insert(
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
      await CollateralDao(db).createCollateralItem(CollateralItem(
        id: tokyoItemId,
        shopId: tokyoShopId,
        customerId: tokyoCustomerId,
        itemReferenceId: 'COLL-TYO-001',
        category: CollateralItemCategory.gold,
        description: '22K gold bangle',
        conditionGrade: 'Like New',
        weightMilligrams: 9000,
        estimatedValueCents: 2000000,
      ));
    });

    testWidgets('the summary displays the same calendar date that is persisted '
        'for the loan', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final tokyoZone = ShopTimeZone('Asia/Tokyo');
      final colomboZone = ShopTimeZone.defaultTimeZone();

      await tester.pumpWidget(
        MaterialApp(
          home: LoanOriginationScreen(
            shopId: tokyoShopId,
            customerId: tokyoCustomerId,
            currentUser: AppUser(
              id: tokyoStaffId,
              shopId: tokyoShopId,
              username: 'tokyo.cashier',
              fullName: 'Tokyo Cashier',
              role: AppRole.cashier,
              isActive: true,
            ),
            database: db,
          ),
        ),
      );
      await pumpUntil(tester,
          () => find.byKey(const Key('submit_loan_button')).evaluate().isNotEmpty);

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
      final colomboRendering =
          colomboZone.localDateOf(tokyoZone.instantAtStartOfDay(
            tokyoZone.localDateOf(DateTime.now().toUtc()).addDays(30),
          )).isoDate;
      expect(previewed, isNot(contains(colomboRendering)),
          reason: 'A Tokyo shop must not preview the due date in the '
              'Asia/Colombo calendar.');

      await tester.tap(find.byKey(const Key('submit_loan_button')));
      await pumpUntil(tester,
          () => find.byKey(const Key('origination_success_display')).evaluate().isNotEmpty);

      final loans = await db.select(db.loans).get();
      expect(loans.length, equals(1));

      // The persisted due date rendered in the shop zone must be exactly the
      // date the summary previewed.
      final shopZoneDate =
          tokyoZone.localDateOf(loans.first.dueDate).isoDate;
      final summaryText = tester
          .widget<Text>(find.byKey(const Key('preliminary_due_date_display')))
          .data!;
      final successText = tester
          .widget<Text>(find.byKey(const Key('origination_success_display')))
          .data!;

      expect(summaryText, contains(shopZoneDate),
          reason: 'The summary must display the due date in the shop zone.');
      expect(successText, contains(shopZoneDate),
          reason: 'The success banner must agree with the summary.');
    });

    testWidgets(
        'Story 4.4 - draft agreement button appears only after loan creation and generates draft document',
        (WidgetTester tester) async {
      await pumpScreen(tester);

      // Draft agreement button must NOT exist before loan creation (D4.4-01 Option 1A).
      expect(find.byKey(const Key('view_draft_agreement_button')), findsNothing);

      await tester.enterText(
        find.byKey(const Key('principal_amount_field')),
        '25000.00',
      );
      await tester.tap(find.byKey(const Key('term_preset_30')));
      await tester.pump();
      await tester.tap(find.byKey(Key('collateral_item_$itemOneId')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('submit_loan_button')));
      final outcome = await pumpUntilOutcome(tester);
      expect(outcome, equals('success'),
          reason: 'Submission failed with: $outcome');

      // After creation, draft agreement button must appear.
      expect(find.byKey(const Key('view_draft_agreement_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('view_draft_agreement_button')));
      await tester.pump();
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final err = find.byKey(const Key('draft_error_display'));
        if (err.evaluate().isNotEmpty) {
          final msg = tester.widget<Text>(err).data;
          fail('Draft generation failed with error: $msg');
        }
        if (find.byType(AlertDialog).evaluate().isNotEmpty ||
            find.byKey(const Key('draft_generated_display')).evaluate().isNotEmpty) {
          break;
        }
      }

      // Verify Category 2 audit event was queued in SyncQueue
      final syncEntries = await db.select(db.syncQueue).get();
      final draftEvents = syncEntries.where((e) =>
          e.entityType == 'loan' &&
          e.actionType == 'generate_loan_draft');
      expect(draftEvents, isNotEmpty);
    });
  });
}
