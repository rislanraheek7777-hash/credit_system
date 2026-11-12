import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/correction_dao.dart';
import 'package:credit_system/features/customers/data/daos/credit_dao.dart';
import 'package:credit_system/features/customers/presentation/correction_adjustment_screen.dart';
import 'package:uuid/uuid.dart';

const String shopId = 'adj-shop-1111-1111-1111-111111111101';
const customerId = 1;
const String ownerId = 'adj-owner-1111-1111-111111111103';
const String managerId = 'adj-mgr-1111-1111-111111111104';
const String creditId = 'adj-credit-1111-1111-111111111105';

Future<void> seedAdjustmentData(AppDatabase db) async {
  final now = DateTime.now().toUtc();
  await db.into(db.shops).insert(
    ShopEntry(
      id: shopId,
      name: 'Adjustment Test Shop',
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
      fullName: 'Adjustment Customer',
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
      username: 'adj-owner',
      fullName: 'Adjustment Owner',
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
      username: 'adj-mgr',
      fullName: 'Adjustment Manager',
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
      balanceCents: 300000,
      status: const Value('active'),
      workflowStatus: const Value('disbursed'),
      termPresetDays: const Value(30),
      dueDate: DateTime.utc(2026, 11, 20),
      disbursedAt: Value(DateTime.utc(2026, 10, 21)),
      disbursedByUserId: Value(ownerId),
      createdAt: now,
      correctionPending: const Value(false),
    ),
  );
}

AppUser owner({bool isActive = true}) => AppUser(
  id: ownerId,
  shopId: shopId,
  username: 'adj-owner',
  fullName: 'Adjustment Owner',
  role: AppRole.shopOwner,
  isActive: isActive,
);

AppUser manager({bool isActive = true}) => AppUser(
  id: managerId,
  shopId: shopId,
  username: 'adj-mgr',
  fullName: 'Adjustment Manager',
  role: AppRole.manager,
  isActive: isActive,
);

Future<CreditCorrection> seedPendingCorrection(AppDatabase db) async {
  return CorrectionDao(db).requestCorrection(
    actor: manager(),
    idempotencyKey: const Uuid().v4(),
    creditId: creditId,
    originalPaymentId: 'review-pay-alpha-1111-1111-1111-111111111108',
    amount: Money.fromCents(200000),
    reason: 'Typographical error: entered 35,000 instead of 3,500.',
    requestedAt: DateTime.utc(2026, 10, 22),
  );
}

Future<void> openScreen(
  WidgetTester tester,
  AppDatabase db, {
    required AppUser actor,
  }) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CorrectionAdjustmentScreen(
        key: UniqueKey(),
        shopId: shopId,
        creditId: creditId,
        currentUser: actor,
        database: db,
      ),
    ),
  );
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byKey(const Key('adjustment_submit_button')).evaluate().isNotEmpty) {
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
    await seedAdjustmentData(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('CorrectionAdjustmentScreen', () {
    testWidgets('owner can open the screen for a valid credit',
        (WidgetTester tester) async {
      await openScreen(tester, db, actor: owner());

      expect(find.byKey(const Key('adjustment_submit_button')),
          findsOneWidget);
      expect(find.textContaining('Outstanding balance: Rs. 3,000.00'),
          findsOneWidget);
    });

    testWidgets('non-owner cannot adjust balance',
        (WidgetTester tester) async {
      await openScreen(tester, db, actor: manager());
      expect(find.textContaining('You do not have permission'),
          findsOneWidget);
      expect(find.byKey(const Key('adjustment_submit_button')), findsNothing);
    });

    testWidgets('owner can perform a valid debit adjustment',
        (WidgetTester tester) async {
      await openScreen(tester, db, actor: owner());
      await tester.enterText(
          find.byKey(const Key('adjustment_amount_input')), '1000.00');
      await tester.enterText(
          find.byKey(const Key('adjustment_reason_input')), 'Rounding reconciliation.');
      await tester.tap(
          find.byKey(Key('adjustment_type_adjustment_debit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adjustment_submit_button')));
      await tester.pumpAndSettle();

      final outcome = await _pumpUntilOutcome(tester);
      expect(outcome, equals('success'));

      final correctionDao = CorrectionDao(db);
      final entries = await correctionDao.getLedgerEntriesByCredit(
          shopId, creditId);
      expect(entries, hasLength(1));
      expect(entries.first.entryType,
          equals(CreditLedgerEntryType.adjustmentDebit));
      expect(entries.first.amountCents, equals(100000));

      final creditDao = CreditDao(db);
      final credit = await creditDao.getCreditById(shopId, creditId);
      expect(credit?.balanceCents, equals(400000));
    });

    testWidgets('owner can perform a valid credit adjustment',
        (WidgetTester tester) async {
      await openScreen(tester, db, actor: owner());
      await tester.enterText(
          find.byKey(const Key('adjustment_amount_input')), '500.00');
      await tester.enterText(
          find.byKey(const Key('adjustment_reason_input')), 'Dispute settlement credit.');
      await tester.tap(
          find.byKey(Key('adjustment_type_adjustment_credit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adjustment_submit_button')));
      await tester.pumpAndSettle();

      final outcome = await _pumpUntilOutcome(tester);
      expect(outcome, equals('success'));

      final correctionDao = CorrectionDao(db);
      final entries = await correctionDao.getLedgerEntriesByCredit(
          shopId, creditId);
      expect(entries, hasLength(1));
      expect(entries.first.entryType,
          equals(CreditLedgerEntryType.adjustmentCredit));
      expect(entries.first.amountCents, equals(50000));

      final creditDao = CreditDao(db);
      final credit = await creditDao.getCreditById(shopId, creditId);
      expect(credit?.balanceCents, equals(250000));
    });

    testWidgets('invalid amount is rejected',
        (WidgetTester tester) async {
      await openScreen(tester, db, actor: owner());
      await tester.enterText(
          find.byKey(const Key('adjustment_amount_input')), '0');
      await tester.enterText(
          find.byKey(const Key('adjustment_reason_input')), 'Test reason.');
      await tester.tap(
          find.byKey(Key('adjustment_type_adjustment_debit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adjustment_submit_button')));
      await tester.pumpAndSettle();
      final outcome = await _pumpUntilOutcome(tester);
      expect(outcome.startsWith('error:'), isTrue);
    });

    testWidgets('invalid rationale is rejected',
        (WidgetTester tester) async {
      await openScreen(tester, db, actor: owner());
      await tester.enterText(
          find.byKey(const Key('adjustment_amount_input')), '100.00');
      await tester.enterText(
          find.byKey(const Key('adjustment_reason_input')), '   ');
      await tester.tap(
          find.byKey(Key('adjustment_type_adjustment_debit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adjustment_submit_button')));
      await tester.pumpAndSettle();
      final outcome = await _pumpUntilOutcome(tester);
      expect(outcome.startsWith('error:'), isTrue);
    });

    testWidgets('adjustment type is required',
        (WidgetTester tester) async {
      await openScreen(tester, db, actor: owner());
      await tester.enterText(
          find.byKey(const Key('adjustment_amount_input')), '100.00');
      await tester.enterText(
          find.byKey(const Key('adjustment_reason_input')), 'Test reason.');
      await tester.tap(find.byKey(const Key('adjustment_submit_button')));
      await tester.pumpAndSettle();

      final correctionDao = CorrectionDao(db);
      final entries = await correctionDao.getLedgerEntriesByCredit(
          shopId, creditId);
      expect(entries, isEmpty);

      final creditDao = CreditDao(db);
      final credit = await creditDao.getCreditById(shopId, creditId);
      expect(credit?.balanceCents, equals(300000));
    });

    testWidgets('adjustment is blocked while correction is pending',
        (WidgetTester tester) async {
      await db
          .customSelect(
              'UPDATE credits SET correction_pending = 1 WHERE id = ?',
              variables: [Variable<String>(creditId)])
          .get();
      final lockedCredit = await CreditDao(db).getCreditById(shopId, creditId);
      expect(lockedCredit?.correctionPending, isTrue);

      await openScreen(tester, db, actor: owner());

      await tester.enterText(
          find.byKey(const Key('adjustment_amount_input')), '100.00');
      await tester.enterText(
          find.byKey(const Key('adjustment_reason_input')), 'Locked attempt.');
      await tester.tap(
          find.byKey(Key('adjustment_type_adjustment_debit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adjustment_submit_button')));
      await tester.pumpAndSettle();

      final correctionDao = CorrectionDao(db);
      final entries = await correctionDao.getLedgerEntriesByCredit(
          shopId, creditId);
      expect(entries, isEmpty);

      final creditDao = CreditDao(db);
      final credit = await creditDao.getCreditById(shopId, creditId);
      expect(credit?.balanceCents, equals(300000));
    });

    testWidgets('duplicate taps do not submit repeated adjustments',
        (WidgetTester tester) async {
      await openScreen(tester, db, actor: owner());

      await tester.enterText(
          find.byKey(const Key('adjustment_amount_input')), '100.00');
      await tester.enterText(
          find.byKey(const Key('adjustment_reason_input')), 'Duplicate tap test.');
      await tester.tap(
          find.byKey(Key('adjustment_type_adjustment_debit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adjustment_submit_button')));
      await tester.pumpAndSettle();
      await _pumpUntilOutcome(tester);

      final entries = await CorrectionDao(db).getLedgerEntriesByCredit(
          shopId, creditId);
      expect(entries, hasLength(1));

      final creditDao = CreditDao(db);
      final credit = await creditDao.getCreditById(shopId, creditId);
      expect(credit?.balanceCents, equals(310000));
    });
  });
}

Future<String> _pumpUntilOutcome(WidgetTester tester) async {
  for (var i = 0; i < 300; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();
    final success = find.byKey(const Key('adjustment_success_display'));
    if (success.evaluate().isNotEmpty) {
      return 'success';
    }
    final error = find.byKey(const Key('adjustment_error_display'));
    if (error.evaluate().isNotEmpty) {
      return 'error: ${tester.widget<Text>(error).data}';
    }
  }
  fail('_pumpUntilOutcome: neither a success nor an error was displayed.');
}
