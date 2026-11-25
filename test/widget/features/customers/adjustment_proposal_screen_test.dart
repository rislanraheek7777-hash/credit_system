import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/correction_dao.dart';
import 'package:credit_system/features/customers/data/daos/credit_dao.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:credit_system/features/customers/presentation/adjustment_proposal_screen.dart';

import '../../../support/customers_test_support.dart';

const String shopId = 'prop-shop-1111-1111-1111-111111111101';
const customerId = 1;
const String ownerId = 'prop-owner-1111-1111-1111-111111111103';
const String managerId = 'prop-mgr-1111-1111-1111-111111111104';
const String cashierId = 'prop-cash-1111-1111-1111-111111111106';
const String creditId = 'prop-credit-1111-1111-1111-111111111105';

/// Seeds a shop, borrower, staff users and one disbursed active credit with a
/// 3,000.00 balance.
Future<void> seedProposalData(
  AppDatabase db, {
  int balanceCents = 300000,
  String status = 'active',
  String workflowStatus = 'disbursed',
  bool correctionPending = false,
}) async {
  final now = DateTime.now().toUtc();
  await db.into(db.shops).insert(
    ShopEntry(
      id: shopId,
      name: 'Proposal Test Shop',
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
      fullName: 'Proposal Customer',
      nic: '851234567V',
      phone: '0771234567',
      address: '1 Test St',
      createdAt: now,
      updatedAt: now,
    ),
  );
  for (final user in [
    (id: ownerId, username: 'prop-owner', role: 'shop_owner'),
    (id: managerId, username: 'prop-mgr', role: 'manager'),
    (id: cashierId, username: 'prop-cash', role: 'cashier'),
  ]) {
    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: user.id,
        shopId: shopId,
        username: user.username,
        fullName: user.username,
        role: user.role,
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
  await db.into(db.credits).insert(
    CreditsCompanion.insert(
      id: creditId,
      shopId: shopId,
      customerId: customerId,
      principalCents: 500000,
      balanceCents: balanceCents,
      status: Value(status),
      workflowStatus: Value(workflowStatus),
      termPresetDays: const Value(30),
      dueDate: DateTime.utc(2026, 11, 20),
      disbursedAt: status == 'cancelled'
          ? const Value.absent()
          : Value(DateTime.utc(2026, 10, 21)),
      disbursedByUserId: status == 'cancelled'
          ? const Value.absent()
          : Value(ownerId),
      cancelledAt:
          status == 'cancelled' ? Value(now) : const Value.absent(),
      cancellationReason: status == 'cancelled'
          ? const Value('Cancelled before disbursement')
          : const Value.absent(),
      createdAt: now,
      correctionPending: Value(correctionPending),
    ),
  );
}

AppUser manager({bool isActive = true}) => AppUser(
      id: managerId,
      shopId: shopId,
      username: 'prop-mgr',
      fullName: 'Proposal Manager',
      role: AppRole.manager,
      isActive: isActive,
    );

/// A cashier has no `requestCorrections` permission, but may still submit an
/// immediate adjustment.
AppUser cashier({bool isActive = true}) => AppUser(
      id: cashierId,
      shopId: shopId,
      username: 'prop-cash',
      fullName: 'Proposal Cashier',
      role: AppRole.cashier,
      isActive: isActive,
    );

Future<void> openScreen(
  WidgetTester tester,
  AppDatabase db, {
  AppUser? actor,
}) async {
  useLargeSurface(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: AdjustmentProposalScreen(
        key: UniqueKey(),
        shopId: shopId,
        creditId: creditId,
        currentUser: actor ?? manager(),
        database: db,
      ),
    ),
  );
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find
        .byKey(const Key('adjustment_input_mode_toggle'))
        .evaluate()
        .isNotEmpty) {
      break;
    }
  }
  await tester.pumpAndSettle();
}

/// The adjustment posts immediately: exactly one ledger entry, no pending
/// correction record and no lock on the credit.
Future<void> expectImmediateAdjustment(
  AppDatabase db, {
  required String entryType,
  required int amountCents,
  required int postBalanceCents,
  required String actorId,
}) async {
  final dao = CorrectionDao(db);
  final ledger = await dao.getLedgerEntriesByCredit(shopId, creditId);
  expect(ledger, hasLength(1));
  expect(ledger.single.entryType.value, entryType);
  expect(ledger.single.amountCents, amountCents);
  expect(ledger.single.preBalanceCents, 300000);
  expect(ledger.single.postBalanceCents, postBalanceCents);
  expect(ledger.single.recordedByUserId, actorId);
  expect(ledger.single.reason, isNotEmpty);

  final proposals =
      await dao.getCorrectionsByStatus(shopId, 'pending_approval');
  expect(proposals, isEmpty);

  final credit = await CreditDao(db).getCreditById(shopId, creditId);
  expect(credit!.correctionPending, isFalse);
  expect(credit.balanceCents, postBalanceCents);
}

void main() {
  late AppDatabase db;

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);
    await seedProposalData(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('AdjustmentProposalScreen derive-delta mode', () {
    testWidgets('derives and immediately posts a forgiveness from a lower '
        'desired balance', (WidgetTester tester) async {
      await openScreen(tester, db);

      await tester.tap(find.byKey(const Key('adjustment_mode_derive')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('adjustment_new_balance_input')),
        '1,000.00',
      );
      await tester.enterText(
        find.byKey(const Key('adjustment_reason_input')),
        'Customer cannot pay in full this month.',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('adjustment_derived_delta_preview')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('submit_adjustment_button')));
      await tester.pumpAndSettle();

      await expectImmediateAdjustment(
        db,
        entryType: 'adjustment_credit',
        amountCents: 200000,
        postBalanceCents: 100000,
        actorId: managerId,
      );
    });

    testWidgets('derives and immediately posts an increase from a higher '
        'desired balance', (WidgetTester tester) async {
      await openScreen(tester, db);

      await tester.tap(find.byKey(const Key('adjustment_mode_derive')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('adjustment_new_balance_input')),
        '4,000.00',
      );
      await tester.enterText(
        find.byKey(const Key('adjustment_reason_input')),
        'Undercharged at disbursement.',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('submit_adjustment_button')));
      await tester.pumpAndSettle();

      await expectImmediateAdjustment(
        db,
        entryType: 'adjustment_debit',
        amountCents: 100000,
        postBalanceCents: 400000,
        actorId: managerId,
      );
    });

    testWidgets('a below-zero desired balance is rejected with the over-balance error',
        (WidgetTester tester) async {
      await openScreen(tester, db);

      await tester.tap(find.byKey(const Key('adjustment_mode_derive')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('adjustment_new_balance_input')),
        '-5.00',
      );
      await tester.enterText(
        find.byKey(const Key('adjustment_reason_input')),
        'Invalid forgiveness target.',
      );
      await tester.pumpAndSettle();

      // The submit button stays disabled for an implied negative result.
      final submit = tester.widget<ElevatedButton>(
        find.byKey(const Key('submit_adjustment_button')),
      );
      expect(submit.onPressed, isNull);

      expect(await CorrectionDao(db).getLedgerEntriesByCredit(shopId, creditId),
          isEmpty);
    });

    testWidgets('a desired balance equal to the current balance derives a no-op and cannot submit',
        (WidgetTester tester) async {
      await openScreen(tester, db);

      await tester.tap(find.byKey(const Key('adjustment_mode_derive')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('adjustment_new_balance_input')),
        '3,000.00',
      );
      await tester.enterText(
        find.byKey(const Key('adjustment_reason_input')),
        'No-op attempt.',
      );
      await tester.pumpAndSettle();

      final submit = tester.widget<ElevatedButton>(
        find.byKey(const Key('submit_adjustment_button')),
      );
      expect(submit.onPressed, isNull);

      expect(await CorrectionDao(db).getLedgerEntriesByCredit(shopId, creditId),
          isEmpty);
    });

    testWidgets('a full-forgiveness desired balance of zero settles the credit '
        'in the same transaction as the ledger entry',
        (WidgetTester tester) async {
      await openScreen(tester, db);

      await tester.tap(find.byKey(const Key('adjustment_mode_derive')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('adjustment_new_balance_input')),
        '0.00',
      );
      await tester.enterText(
        find.byKey(const Key('adjustment_reason_input')),
        'Insolvent customer; forgive everything.',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('submit_adjustment_button')));
      await tester.pumpAndSettle();

      await expectImmediateAdjustment(
        db,
        entryType: 'adjustment_credit',
        amountCents: 300000,
        postBalanceCents: 0,
        actorId: managerId,
      );
      final credit = await CreditDao(db).getCreditById(shopId, creditId);
      expect(credit!.status, CreditStatus.settled);
      expect(credit.settledAt, isNotNull);
    });
  });

  group('AdjustmentProposalScreen amount + direction mode', () {
    testWidgets('a debit-direction adjustment posts as adjustment_debit '
        'immediately, with no owner approval step',
        (WidgetTester tester) async {
      await openScreen(tester, db);

      // Default mode is amount + direction with credit selected; switch to debit.
      await tester.tap(find.byKey(const Key('adjustment_direction_debit')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('adjustment_amount_input')),
        '250.00',
      );
      await tester.enterText(
        find.byKey(const Key('adjustment_reason_input')),
        'Undercharge discovered at checkout.',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('submit_adjustment_button')));
      await tester.pumpAndSettle();

      await expectImmediateAdjustment(
        db,
        entryType: 'adjustment_debit',
        amountCents: 25000,
        postBalanceCents: 325000,
        actorId: managerId,
      );
    });

    testWidgets('a cashier without requestCorrections can submit an immediate '
        'adjustment', (WidgetTester tester) async {
      await openScreen(tester, db, actor: cashier());

      await tester.enterText(
        find.byKey(const Key('adjustment_amount_input')),
        '200.00',
      );
      await tester.enterText(
        find.byKey(const Key('adjustment_reason_input')),
        'Customer paid in cash at the counter.',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('submit_adjustment_button')));
      await tester.pumpAndSettle();

      await expectImmediateAdjustment(
        db,
        entryType: 'adjustment_credit',
        amountCents: 20000,
        postBalanceCents: 280000,
        actorId: cashierId,
      );
    });

    testWidgets('a deactivated actor is rejected by the DAO and nothing posts',
        (WidgetTester tester) async {
      await openScreen(tester, db, actor: manager(isActive: false));

      await tester.enterText(
        find.byKey(const Key('adjustment_amount_input')),
        '100.00',
      );
      await tester.enterText(
        find.byKey(const Key('adjustment_reason_input')),
        'Attempt by a deactivated account.',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('submit_adjustment_button')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('User account is deactivated'),
        findsOneWidget,
      );
      expect(await CorrectionDao(db).getLedgerEntriesByCredit(shopId, creditId),
          isEmpty);
      final credit = await CreditDao(db).getCreditById(shopId, creditId);
      expect(credit!.balanceCents, 300000);
    });

    testWidgets('the submit button and copy describe an immediate change, not '
        'an owner decision', (WidgetTester tester) async {
      await openScreen(tester, db);

      expect(find.text('Submit'), findsOneWidget);
      expect(find.textContaining('Shop Owner'), findsNothing);
      expect(find.textContaining('approv'), findsNothing);
      expect(find.textContaining('immediately'), findsWidgets);
    });
  });

  group('AdjustmentProposalScreen eligibility', () {
    testWidgets('an ineligible credit posts the adjustment when Submit is '
        'tapped, with no eligibility notice', (WidgetTester tester) async {
      await db.close();
      final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
      db = AppDatabase.forTesting(inMemoryExecutor);
      await seedProposalData(db, status: 'cancelled', workflowStatus: 'cancelled');

      await openScreen(tester, db);

      expect(
        find.text('This credit is not eligible for a balance adjustment.'),
        findsNothing,
      );

      await tester.enterText(
        find.byKey(const Key('adjustment_amount_input')),
        '100.00',
      );
      await tester.enterText(
        find.byKey(const Key('adjustment_reason_input')),
        'Attempt on a cancelled credit.',
      );
      await tester.pumpAndSettle();

      final submit = tester.widget<ElevatedButton>(
        find.byKey(const Key('submit_adjustment_button')),
      );
      expect(submit.onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('submit_adjustment_button')));
      await tester.pumpAndSettle();

      expect(
        find.text('This credit is not eligible for a balance adjustment.'),
        findsNothing,
      );
      expect(find.textContaining('not in an adjustable state'), findsNothing);

      await expectImmediateAdjustment(
        db,
        entryType: 'adjustment_credit',
        amountCents: 10000,
        postBalanceCents: 290000,
        actorId: managerId,
      );
    });

    testWidgets('a pending payment correction is rejected by the DAO when '
        'Submit is tapped', (WidgetTester tester) async {
      await db.close();
      final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
      db = AppDatabase.forTesting(inMemoryExecutor);
      await seedProposalData(db, correctionPending: true);

      await openScreen(tester, db);

      await tester.enterText(
        find.byKey(const Key('adjustment_amount_input')),
        '100.00',
      );
      await tester.enterText(
        find.byKey(const Key('adjustment_reason_input')),
        'Attempt while a payment correction is pending.',
      );
      await tester.pumpAndSettle();

      final submit = tester.widget<ElevatedButton>(
        find.byKey(const Key('submit_adjustment_button')),
      );
      expect(submit.onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('submit_adjustment_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('pending correction'), findsOneWidget);
      expect(await CorrectionDao(db).getLedgerEntriesByCredit(shopId, creditId),
          isEmpty);
    });
  });
}
