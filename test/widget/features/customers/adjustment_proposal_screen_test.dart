import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/correction_dao.dart';
import 'package:credit_system/features/customers/data/daos/credit_dao.dart';
import 'package:credit_system/features/customers/presentation/adjustment_proposal_screen.dart';
import 'package:uuid/uuid.dart';

import '../../../support/customers_test_support.dart';

const String shopId = 'prop-shop-1111-1111-1111-111111111101';
const customerId = 1;
const String ownerId = 'prop-owner-1111-1111-1111-111111111103';
const String managerId = 'prop-mgr-1111-1111-1111-111111111104';
const String creditId = 'prop-credit-1111-1111-1111-111111111105';

/// Seeds a shop, borrower, manager and one disbursed active credit with a
/// 3,000.00 balance.
Future<void> seedProposalData(
  AppDatabase db, {
  int balanceCents = 300000,
  String status = 'active',
  String workflowStatus = 'disbursed',
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
  await db.into(db.appUsers).insert(
    AppUserEntry(
      id: ownerId,
      shopId: shopId,
      username: 'prop-owner',
      fullName: 'Proposal Owner',
      role: 'shop_owner',
      isActive: true,
      sessionVersion: 1,
      createdAt: now,
      updatedAt: now,
    ),
  );
  await db.into(db.appUsers).insert(
    AppUserEntry(
      id: managerId,
      shopId: shopId,
      username: 'prop-mgr',
      fullName: 'Proposal Manager',
      role: 'manager',
      isActive: true,
      sessionVersion: 1,
      createdAt: now,
      updatedAt: now,
    ),
  );
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
      correctionPending: const Value(false),
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
    testWidgets('derives a forgiveness proposal from a lower desired balance',
        (WidgetTester tester) async {
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

      final proposals = await CorrectionDao(db)
          .getCorrectionsByStatus(shopId, 'pending_approval');
      expect(proposals, hasLength(1));
      expect(proposals.single.correctionAmountCents, 200000);
      expect(proposals.single.direction, CorrectionDao.directionCredit);
      expect(proposals.single.originalPaymentId, isNull);
    });

    testWidgets('derives an increase proposal from a higher desired balance',
        (WidgetTester tester) async {
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

      final proposals = await CorrectionDao(db)
          .getCorrectionsByStatus(shopId, 'pending_approval');
      expect(proposals, hasLength(1));
      expect(proposals.single.correctionAmountCents, 100000);
      expect(proposals.single.direction, CorrectionDao.directionDebit);
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

      final proposals = await CorrectionDao(db)
          .getCorrectionsByStatus(shopId, 'pending_approval');
      expect(proposals, isEmpty);
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

      final proposals = await CorrectionDao(db)
          .getCorrectionsByStatus(shopId, 'pending_approval');
      expect(proposals, isEmpty);
    });

    testWidgets('a full-forgiveness desired balance of zero is accepted',
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

      final proposals = await CorrectionDao(db)
          .getCorrectionsByStatus(shopId, 'pending_approval');
      expect(proposals, hasLength(1));
      expect(proposals.single.correctionAmountCents, 300000);
      expect(proposals.single.direction, CorrectionDao.directionCredit);
    });
  });

  group('AdjustmentProposalScreen amount + direction mode', () {
    testWidgets('a debit-direction proposal submits and posts through as adjustment_debit on approval',
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

      final proposals = await CorrectionDao(db)
          .getCorrectionsByStatus(shopId, 'pending_approval');
      expect(proposals, hasLength(1));
      expect(proposals.single.direction, CorrectionDao.directionDebit);
      expect(proposals.single.correctionAmountCents, 25000);

      final approved = await CorrectionDao(db).approveCorrection(
        actor: AppUser(
          id: ownerId,
          shopId: shopId,
          username: 'prop-owner',
          fullName: 'Proposal Owner',
          role: AppRole.shopOwner,
          isActive: true,
        ),
        idempotencyKey: const Uuid().v4(),
        correctionId: proposals.single.id,
        reviewedAt: DateTime.now().toUtc(),
      );
      expect(approved.isApproved, isTrue);

      final ledger = await CorrectionDao(db)
          .getLedgerEntriesByCredit(shopId, creditId);
      expect(ledger, hasLength(1));
      expect(ledger.single.entryType, CreditLedgerEntryType.adjustmentDebit);
      expect(ledger.single.amountCents, 25000);
    });
  });

  group('AdjustmentProposalScreen eligibility', () {
    testWidgets('an ineligible credit reports it instead of submitting',
        (WidgetTester tester) async {
      await db.close();
      final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
      db = AppDatabase.forTesting(inMemoryExecutor);
      await seedProposalData(db, status: 'cancelled', workflowStatus: 'cancelled');

      await openScreen(tester, db);

      await tester.enterText(
        find.byKey(const Key('adjustment_amount_input')),
        '100.00',
      );
      await tester.enterText(
        find.byKey(const Key('adjustment_reason_input')),
        'Attempt on a cancelled credit.',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('submit_adjustment_button')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('not eligible'),
        findsOneWidget,
      );

      final proposals = await CorrectionDao(db)
          .getCorrectionsByStatus(shopId, 'pending_approval');
      expect(proposals, isEmpty);

      final credit = await CreditDao(db).getCreditById(shopId, creditId);
      expect(credit!.correctionPending, isFalse);
    });
  });
}
