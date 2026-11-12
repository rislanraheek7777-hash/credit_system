import 'dart:io';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_dao.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';
import 'package:credit_system/features/customers/data/daos/credit_dao.dart';
import 'package:credit_system/features/customers/domain/models/credit_term.dart';
import 'package:credit_system/features/customers/presentation/customer_profile_screen.dart';
import 'package:credit_system/features/customers/presentation/credit_disbursement_screen.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the customer-facing rendering of the official
/// calendar due date (Story 4.3, finding T3).
///
/// The official due date is persisted as the UTC instant of **shop-local
/// midnight** of the agreed calendar date. For `Asia/Colombo` (UTC+05:30)
/// that instant is 18:30 UTC on the **previous** day, so rendering the UTC
/// calendar date of the stored instant loses a day: 2026-11-14 would be shown
/// as 2026-11-13.
///
/// The correct rendering is the calendar date in the shop's own time zone,
/// which is the pattern the Story 4.2 origination screen already uses.
void main() {
  const shopId = '11111111-1111-1111-1111-111111111501';
  const customerId = 1;
  const managerId = '11111111-1111-1111-1111-111111111504';

  late AppDatabase db;

  /// The calendar date the official due date must be rendered as.
  const expectedOfficialDate = '2026-11-14';

  final zone = ShopTimeZone.defaultTimeZone();

  AppUser manager() => AppUser(
        id: managerId,
        shopId: shopId,
        username: 'due.manager',
        fullName: 'Due Manager',
        role: AppRole.manager,
        isActive: true,
      );

  /// The instant the shop-local calendar date 2026-11-14 starts at.
  DateTime officialDueDateInstant() =>
      zone.instantAtStartOfDay(const LocalCalendarDate(2026, 11, 14));

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);

    final now = DateTime.now().toUtc();
    await db.into(db.shops).insert(ShopEntry(
      id: shopId,
      name: 'Due Date Shop',
      currencyCode: 'LKR',
      timezone: 'Asia/Colombo',
      createdAt: now,
      updatedAt: now,
    ));
    await db.into(db.appUsers).insert(AppUserEntry(
      id: managerId,
      shopId: shopId,
      username: 'due.manager',
      fullName: 'Due Manager',
      role: 'manager',
      isActive: true,
      sessionVersion: 1,
      createdAt: now,
      updatedAt: now,
    ));
    await db.into(db.customers).insert(CustomerEntry(
      id: customerId,
      shopId: shopId,
      fullName: 'Due Date Customer',
      nic: '851234567V',
      phone: '0771234567',
      address: '1 Main St',
      createdAt: now,
      updatedAt: now,
    ));
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedCredit({
    required String creditId,
    required String workflowStatus,
    required DateTime dueDate,
  }) async {
    final now = DateTime.now().toUtc();
    await db.into(db.credits).insert(CreditsCompanion.insert(
      id: creditId,
      shopId: shopId,
      customerId: customerId,
      principalCents: 500000,
      balanceCents: 500000,
      status: const Value('active'),
      workflowStatus: Value(workflowStatus),
      termPresetDays: const Value(30),
      disbursedAt:
          workflowStatus == 'disbursed' ? Value(now) : const Value(null),
      disbursedByUserId: workflowStatus == 'disbursed'
          ? const Value(managerId)
          : const Value(null),
      dueDate: dueDate,
      createdAt: now,
    ));
  }

  Future<void> pumpScreen(WidgetTester tester, String creditId) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      home: CreditDisbursementScreen(
        key: ValueKey(creditId),
        shopId: shopId,
        creditId: creditId,
        currentUser: manager(),
        database: db,
      ),
    ));

    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find
          .byKey(const Key('disbursement_state_banner'))
          .evaluate()
          .isNotEmpty) {
        return;
      }
    }
    fail('The disbursement screen did not finish loading.');
  }

  testWidgets(
      'the official due date of a disbursed agreement is rendered as the '
      'shop-local calendar date', (tester) async {
    await seedCredit(
      creditId: 'credit-official',
      workflowStatus: 'disbursed',
      dueDate: officialDueDateInstant(),
    );

    await pumpScreen(tester, 'credit-official');

    final displayed = tester
        .widget<Text>(find.byKey(const Key('disbursement_due_date_display')))
        .data!;

    expect(displayed, contains(officialDueDateLabel));
    expect(
      displayed,
      contains(expectedOfficialDate),
      reason: 'The official due date must be rendered as the shop-local '
          'calendar date, not the UTC calendar date of the stored instant.',
    );
    expect(
      displayed,
      isNot(contains('2026-11-13')),
      reason: 'The UTC calendar date of the stored instant is one day earlier '
          'than the agreed calendar date and must never be shown.',
    );
  });

  testWidgets(
      'the preliminary due date of a pending agreement is rendered as the '
      'shop-local calendar date', (tester) async {
    await seedCredit(
      creditId: 'credit-pending',
      workflowStatus: 'pending_disbursement',
      dueDate: officialDueDateInstant(),
    );

    await pumpScreen(tester, 'credit-pending');

    final displayed = tester
        .widget<Text>(find.byKey(const Key('disbursement_due_date_display')))
        .data!;

    expect(displayed, contains(preliminaryDueDateLabel));
    expect(displayed, contains(expectedOfficialDate));
    expect(displayed, isNot(contains('2026-11-13')));
  });

  testWidgets(
      'the success banner renders the official due date as the shop-local '
      'calendar date', (tester) async {
    await seedCredit(
      creditId: 'credit-banner',
      workflowStatus: 'pending_disbursement',
      dueDate: officialDueDateInstant(),
    );

    await pumpScreen(tester, 'credit-banner');

    await tester.tap(find.byKey(const Key('confirm_disbursement_button')));
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find
          .byKey(const Key('disbursement_success_display'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }

    final banner = tester
        .widget<Text>(find.byKey(const Key('disbursement_success_display')))
        .data!;

    // The banner must show the same calendar date as the due-date row, and
    // that date must be the shop-local one.
    final persisted = await (db.select(db.credits)
          ..where((l) => l.id.equals('credit-banner')))
        .getSingle();
    final expected = zone.localDateOf(persisted.dueDate).isoDate;

    expect(banner, contains(expected));
    expect(
      expected,
      isNot('2026-11-13'),
      reason: 'The persisted instant must be shop-local midnight, so its UTC '
          'calendar date differs from the agreed calendar date.',
    );
  });

  testWidgets(
      'the customer profile screen renders the due date as the shop-local '
      'calendar date', (tester) async {
    await seedCredit(
      creditId: 'credit-profile',
      workflowStatus: 'pending_disbursement',
      dueDate: officialDueDateInstant(),
    );

    await tester.pumpWidget(MaterialApp(
      home: CustomerProfileScreen(
        shopId: shopId,
        customerId: customerId,
        database: db,
        currentUser: manager(),
      ),
    ));
    await tester.pumpAndSettle();

    final dueLines = tester
        .widgetList<Text>(find.textContaining('Due: '))
        .map((t) => t.data!)
        .toList();
    expect(dueLines, isNotEmpty);
    expect(dueLines.first, equals('Due: 2026-11-14'));
  });

  testWidgets(
      'the screen resolves the shop\'s own time zone rather than a fixed one',
      (tester) async {
    // A shop in New York (UTC-05:00). At 2026-11-14T02:00Z the New York
    // calendar date is 2026-11-13, while the Colombo calendar date is
    // 2026-11-14 — so a hard-coded zone would render the wrong day.
    await db.into(db.shops).insertOnConflictUpdate(ShopEntry(
      id: shopId,
      name: 'Due Date Shop',
      currencyCode: 'LKR',
      timezone: 'America/New_York',
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    ));

    await seedCredit(
      creditId: 'credit-new-york',
      workflowStatus: 'pending_disbursement',
      dueDate: DateTime.utc(2026, 11, 14, 2),
    );

    await pumpScreen(tester, 'credit-new-york');

    final displayed = tester
        .widget<Text>(find.byKey(const Key('disbursement_due_date_display')))
        .data!;

    expect(displayed, contains('2026-11-13'),
        reason: 'The New York calendar date of the stored instant is '
            '2026-11-13.');
    expect(displayed, isNot(contains('2026-11-14')),
        reason: 'The Colombo calendar date must not leak into a New York shop.');
  });

  testWidgets(
      'the calculated, the persisted and the rendered official due date agree',
      (tester) async {
    // An item receipt is attached to exercise the item-binding path.
    await CollateralDao(db).createCollateralItem(CollateralItem(
      id: 'coll-chain-1',
      shopId: shopId,
      customerId: customerId,
      itemReferenceId: 'COLL-CHAIN-001',
      category: CollateralItemCategory.gold,
      description: '22K gold necklace',
      conditionGrade: 'Like New',
      weightMilligrams: 5500,
      estimatedValueCents: 1500000,
    ));

    final creditDao = CreditDao(db);
    final created = await creditDao.createCreditAgreement(
      actor: manager(),
      idempotencyKey: 'chain-origin',
      customerId: customerId,
      principal: const Money(500000),
      dueDate: officialDueDateInstant(),
      createdAt: DateTime.now().toUtc(),
      collateralItemIds: const ['coll-chain-1'],
      termPresetDays: 30,
    );

    // A 30-day preset disbursed on 2026-10-15 must produce 2026-11-14.
    final disbursed = await creditDao.confirmCreditDisbursement(
      actor: manager(),
      idempotencyKey: 'chain-disbursement',
      creditId: created.id,
      disbursedAt: DateTime.utc(2026, 10, 15, 6),
    );

    // 1. The calculation.
    final calculated = zone.localDateOf(disbursed.dueDate).isoDate;
    expect(calculated, equals('2026-11-14'));

    // 2. The persisted value.
    final persisted = await (db.select(db.credits)
          ..where((l) => l.id.equals(created.id)))
        .getSingle();
    expect(zone.localDateOf(persisted.dueDate).isoDate, equals('2026-11-14'));

    // 3. The rendered value.
    await pumpScreen(tester, created.id);
    final displayed = tester
        .widget<Text>(find.byKey(const Key('disbursement_due_date_display')))
        .data!;
    expect(displayed, contains('2026-11-14'));
    expect(displayed, contains(officialDueDateLabel));
  });

  testWidgets(
      'the official due date survives a close and reopen of the database',
      (tester) async {
    // A persistent file, so the database can genuinely be closed and reopened
    // the way an application restart would.
    final tempDir = Directory.systemTemp.createTempSync('credit_system_due');
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });
    final file = File(p.join(tempDir.path, 'credit_system.sqlite'));

    final first = AppDatabase.forTesting(NativeDatabase(
      file,
      setup: (db) => db.execute('PRAGMA foreign_keys = ON;'),
    ));

    final now = DateTime.now().toUtc();
    await first.into(first.shops).insert(ShopEntry(
      id: shopId,
      name: 'Due Date Shop',
      currencyCode: 'LKR',
      timezone: 'Asia/Colombo',
      createdAt: now,
      updatedAt: now,
    ));
    await first.into(first.appUsers).insert(AppUserEntry(
      id: managerId,
      shopId: shopId,
      username: 'due.manager',
      fullName: 'Due Manager',
      role: 'manager',
      isActive: true,
      sessionVersion: 1,
      createdAt: now,
      updatedAt: now,
    ));
    await first.into(first.customers).insert(CustomerEntry(
      id: customerId,
      shopId: shopId,
      fullName: 'Due Date Customer',
      nic: '851234567V',
      phone: '0771234567',
      address: '1 Main St',
      createdAt: now,
      updatedAt: now,
    ));
    await CollateralDao(first).createCollateralItem(CollateralItem(
      id: 'coll-reopen-1',
      shopId: shopId,
      customerId: customerId,
      itemReferenceId: 'COLL-REOPEN-001',
      category: CollateralItemCategory.gold,
      description: '22K gold necklace',
      conditionGrade: 'Like New',
      weightMilligrams: 5500,
      estimatedValueCents: 1500000,
    ));

    final creditDao = CreditDao(first);
    final created = await creditDao.createCreditAgreement(
      actor: manager(),
      idempotencyKey: 'reopen-origin',
      customerId: customerId,
      principal: const Money(500000),
      dueDate: officialDueDateInstant(),
      createdAt: now,
      collateralItemIds: const ['coll-reopen-1'],
      termPresetDays: 30,
    );
    await creditDao.confirmCreditDisbursement(
      actor: manager(),
      idempotencyKey: 'reopen-disbursement',
      creditId: created.id,
      disbursedAt: DateTime.utc(2026, 10, 15, 6),
    );

    // Close the database completely, then reopen it.
    await first.close();

    final reopened = AppDatabase.forTesting(NativeDatabase(
      file,
      setup: (db) => db.execute('PRAGMA foreign_keys = ON;'),
    ));
    addTearDown(() async => reopened.close());

    // The reloaded agreement still carries the agreed calendar date ...
    final reloaded =
        await CreditDao(reopened).getCreditById(shopId, created.id);
    expect(reloaded, isNotNull);
    expect(
      reloaded!.dueDateAsCalendarDate(ShopTimeZone.defaultTimeZone()),
      equals('2026-11-14'),
    );

    // ... and the reopened database renders that same date.
    await tester.pumpWidget(MaterialApp(
      home: CreditDisbursementScreen(
        key: ValueKey(created.id),
        shopId: shopId,
        creditId: created.id,
        currentUser: manager(),
        database: reopened,
      ),
    ));
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find
          .byKey(const Key('disbursement_state_banner'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }

    final displayed = tester
        .widget<Text>(find.byKey(const Key('disbursement_due_date_display')))
        .data!;
    expect(displayed, contains('2026-11-14'));
    expect(displayed, contains(officialDueDateLabel));
  });
}




