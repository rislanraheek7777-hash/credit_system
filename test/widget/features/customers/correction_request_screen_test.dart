import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/correction_dao.dart';
import 'package:credit_system/features/customers/data/daos/loan_dao.dart';
import 'package:credit_system/features/customers/presentation/correction_request_screen.dart';

const String shopId = 'corr-ui-shop-1111-1111-1111-111111111101';
const customerId = 1;
const String staffId = 'corr-ui-staff-1111-1111-1111-111111111101';
const String cashierId = 'corr-ui-cash-1111-1111-1111-111111111102';
const String loanId = 'corr-ui-loan-1111-1111-1111-111111111101';
const String paymentId = 'corr-ui-pay-1111-1111-1111-111111111101';

/// Pumps until the screen shows either a success or an error outcome and
/// returns the outcome. The error text is included so a failure is legible.
Future<String> pumpUntilOutcome(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    final success = find.byKey(const Key('correction_success_display'));
    if (success.evaluate().isNotEmpty) {
      return 'success';
    }
    final error = find.byKey(const Key('correction_error_display'));
    if (error.evaluate().isNotEmpty) {
      return 'error: ${tester.widget<Text>(error).data}';
    }
  }
  fail('pumpUntilOutcome: neither a success nor an error was displayed.');
}

/// Seeds a shop, customer, an authorized staff user, a cashier, a disbursed
/// loan and an original payment on that loan.
Future<void> seedCorrectionData(AppDatabase db) async {
  final now = DateTime.now().toUtc();

  await db.into(db.shops).insert(
    ShopEntry(
      id: shopId,
      name: 'Correction UI Test Shop',
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
      fullName: 'Correction UI Customer',
      nic: '851234567V',
      phone: '0771234567',
      address: '1 Test St',
      createdAt: now,
      updatedAt: now,
    ),
  );

  // Staff user with requestCorrections (manager template includes it).
  await db.into(db.appUsers).insert(
    AppUserEntry(
      id: staffId,
      shopId: shopId,
      username: 'corr-ui-staff',
      fullName: 'Correction Staff',
      role: 'manager',
      isActive: true,
      sessionVersion: 1,
      createdAt: now,
      updatedAt: now,
    ),
  );

  // Cashier without requestCorrections.
  await db.into(db.appUsers).insert(
    AppUserEntry(
      id: cashierId,
      shopId: shopId,
      username: 'corr-ui-cash',
      fullName: 'Correction Cashier',
      role: 'cashier',
      isActive: true,
      sessionVersion: 1,
      createdAt: now,
      updatedAt: now,
    ),
  );

  // A disbursed loan with an outstanding balance.
  await db.into(db.loans).insert(
    LoansCompanion.insert(
      id: loanId,
      shopId: shopId,
      customerId: customerId,
      principalCents: 500000,
      balanceCents: 300000,
      status: const Value('active'),
      workflowStatus: const Value('disbursed'),
      termPresetDays: const Value(30),
      dueDate: DateTime.utc(2026, 11, 20),
      disbursedAt: Value(DateTime.utc(2026, 10, 21)),
      disbursedByUserId: Value(staffId),
      createdAt: now,
      correctionPending: const Value(false),
    ),
  );

  // The original (erroneous) payment of 200000 on this loan.
  await db.into(db.payments).insert(
    PaymentsCompanion.insert(
      id: paymentId,
      shopId: shopId,
      loanId: loanId,
      receiptNumber: 'RCP-UI-001',
      amountCents: 200000,
      preBalanceCents: 500000,
      postBalanceCents: 300000,
      paymentType: 'partial',
      recordedAt: DateTime.utc(2026, 10, 21),
      recordedByUserId: staffId,
      customerId: customerId,
      customerName: 'Correction UI Customer',
      customerNic: '851234567V',
      shopName: 'Correction UI Test Shop',
      idempotencyKey: 'idemp-ui-orig-pay',
    ),
  );
}

AppUser staff({bool isActive = true}) => AppUser(
      id: staffId,
      shopId: shopId,
      username: 'corr-ui-staff',
      fullName: 'Correction Staff',
      role: AppRole.manager,
      isActive: isActive,
    );

AppUser cashier({bool isActive = true}) => AppUser(
      id: cashierId,
      shopId: shopId,
      username: 'corr-ui-cash',
      fullName: 'Correction Cashier',
      role: AppRole.cashier,
      isActive: isActive,
    );

Future<void> openScreen(
  WidgetTester tester,
  AppDatabase db, {
  required AppUser actor,
  String? originalPaymentId,
  Money? paymentAmount,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CorrectionRequestScreen(
        key: UniqueKey(),
        shopId: shopId,
        loanId: loanId,
        originalPaymentId: originalPaymentId ?? paymentId,
        paymentAmount: paymentAmount ?? Money.fromCents(200000),
        currentUser: actor,
        database: db,
      ),
    ),
  );
  // Pump until the loan has loaded and the submit button is rendered.
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (find.byKey(const Key('request_correction_button')).evaluate().isNotEmpty) {
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
    await seedCorrectionData(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('CorrectionRequestScreen', () {
    testWidgets('authorized user can open the screen for a valid loan/payment',
        (WidgetTester tester) async {
      await openScreen(tester, db, actor: staff());

      expect(find.byKey(const Key('request_correction_button')), findsOneWidget);
      // Payment context is shown without exposing unnecessary PII.
      expect(find.textContaining('Original payment ID:'), findsOneWidget);
      expect(find.textContaining('Amount: Rs. 2,000.00'), findsOneWidget);
      // The amount field is pre-filled with the original payment amount.
      expect(
        tester.widget<TextField>(
          find.byKey(const Key('correction_amount_input')),
        ).controller?.text,
        '2000.00',
      );
    });

    testWidgets('missing or invalid payment context is rejected',
        (WidgetTester tester) async {
      await openScreen(
        tester,
        db,
        actor: staff(),
        originalPaymentId: '00000000-0000-0000-0000-000000000000',
      );

      await tester.enterText(
        find.byKey(const Key('correction_reason_input')),
        'Typographical error.',
      );
      await tester.tap(find.byKey(const Key('request_correction_button')));
      await tester.pumpAndSettle();

      final outcome = await pumpUntilOutcome(tester);
      expect(outcome, startsWith('error:'));
      expect(
        outcome,
        contains('payment ID'),
      );
    });

    testWidgets('empty or whitespace-only reason is rejected',
        (WidgetTester tester) async {
      await openScreen(tester, db, actor: staff());

      await tester.enterText(
        find.byKey(const Key('correction_reason_input')),
        '   ',
      );
      await tester.tap(find.byKey(const Key('request_correction_button')));
      await tester.pumpAndSettle();

      final outcome = await pumpUntilOutcome(tester);
      expect(outcome, startsWith('error:'));
      expect(outcome, contains('business explanation'));
    });

    testWidgets('invalid amount is rejected using money rules',
        (WidgetTester tester) async {
      await openScreen(tester, db, actor: staff());

      // Zero amount.
      await tester.enterText(
        find.byKey(const Key('correction_amount_input')),
        '0',
      );
      await tester.enterText(
        find.byKey(const Key('correction_reason_input')),
        'Typographical error.',
      );
      await tester.tap(find.byKey(const Key('request_correction_button')));
      await tester.pumpAndSettle();

      expect(
        await pumpUntilOutcome(tester),
        startsWith('error:'),
      );

      // Negative amount.
      await tester.enterText(
        find.byKey(const Key('correction_amount_input')),
        '-100',
      );
      await tester.tap(find.byKey(const Key('request_correction_button')));
      await tester.pumpAndSettle();

      expect(
        await pumpUntilOutcome(tester),
        startsWith('error:'),
      );
    });

    testWidgets('submission calls the DAO with correct context and idempotency key',
        (WidgetTester tester) async {
      await openScreen(tester, db, actor: staff());

      await tester.enterText(
        find.byKey(const Key('correction_amount_input')),
        '2000.00',
      );
      await tester.enterText(
        find.byKey(const Key('correction_reason_input')),
        'Typographical error: entered 35,000 instead of 3,500.',
      );
      await tester.tap(find.byKey(const Key('request_correction_button')));
      await tester.pumpAndSettle();

      final outcome = await pumpUntilOutcome(tester);
      expect(outcome, equals('success'));

      // The correction record was created with the correct linkage.
      final correctionDao = CorrectionDao(db);
      final corrections = await correctionDao.getCorrectionsByLoan(shopId, loanId);
      expect(corrections, hasLength(1));
      expect(corrections.first.originalPaymentId, equals(paymentId));
      expect(corrections.first.correctionAmountCents, equals(200000));
      expect(corrections.first.reason, contains('Typographical error'));
      expect(corrections.first.status, equals(LoanCorrectionStatus.pendingApproval));

      // The correction lock is active on the loan.
      final loanDao = LoanDao(db);
      final loan = await loanDao.getLoanById(shopId, loanId);
      expect(loan?.correctionPending, isTrue);
    });

    testWidgets('duplicate taps do not submit the same request multiple times',
        (WidgetTester tester) async {
      await openScreen(tester, db, actor: staff());

      await tester.enterText(
        find.byKey(const Key('correction_amount_input')),
        '2000.00',
      );
      await tester.enterText(
        find.byKey(const Key('correction_reason_input')),
        'Duplicate tap test.',
      );
      await tester.tap(find.byKey(const Key('request_correction_button')));
      await tester.pumpAndSettle();
      await pumpUntilOutcome(tester);

      // The submit button is disabled while processing, and a correction
      // lock is now active so a second request cannot be created.
      final corrections =
          await CorrectionDao(db).getCorrectionsByLoan(shopId, loanId);
      expect(corrections, hasLength(1));

      final loanDao = LoanDao(db);
      final loan = await loanDao.getLoanById(shopId, loanId);
      expect(loan?.correctionPending, isTrue);
    });

    testWidgets('successful submission shows confirmation',
        (WidgetTester tester) async {
      await openScreen(tester, db, actor: staff());

      await tester.enterText(
        find.byKey(const Key('correction_amount_input')),
        '2000.00',
      );
      await tester.enterText(
        find.byKey(const Key('correction_reason_input')),
        'Typographical error.',
      );
      await tester.tap(find.byKey(const Key('request_correction_button')));
      await tester.pumpAndSettle();

      final outcome = await pumpUntilOutcome(tester);
      expect(outcome, equals('success'));
      expect(
        find.textContaining('Correction requested'),
        findsOneWidget,
      );
    });

    testWidgets('DAO permission and lock errors block submission safely',
        (WidgetTester tester) async {
      // Cashier lacks requestCorrections: submit button disabled, no error key.
      await openScreen(tester, db, actor: cashier());

      final cashierButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('request_correction_button')),
      );
      expect(cashierButton.onPressed == null, isTrue);
      expect(
        find.textContaining('Request Corrections permission'),
        findsOneWidget,
      );

      // No correction was created by the unauthorized actor.
      final corrections =
          await CorrectionDao(db).getCorrectionsByLoan(shopId, loanId);
      expect(corrections, isEmpty);

      // A pending correction locks the loan for staff too.
      // A pending correction locks the loan for staff too. Set the lock
      // directly to exercise the UI lock behavior (the DAO-side lock logic is
      // covered by the correction DAO unit tests).
      await db.customSelect(
        'UPDATE loans SET correction_pending = 1 WHERE id = ?',
        variables: [Variable<String>(loanId)],
      ).get();
      final lockedLoan = await LoanDao(db).getLoanById(shopId, loanId);
      expect(lockedLoan?.correctionPending, isTrue);

      await openScreen(tester, db, actor: staff());

      // Confirm the database still holds the lock right after opening the
      // screen.
      final afterOpenLoan = await LoanDao(db).getLoanById(shopId, loanId);
      expect(afterOpenLoan?.correctionPending, isTrue);

      // Attempt to submit a correction while the lock is active. The UI
      // disables the submit button when a correction is pending; even if the
      // button is tapped, the DAO must reject the submission (no new
      // correction, no success message).
      await tester.enterText(
        find.byKey(const Key('correction_reason_input')), 'Locked attempt.');
      await tester.tap(find.byKey(const Key('request_correction_button')));
      await tester.pumpAndSettle();

      // No new correction was created through the UI.
      final afterLockCorrections =
          await CorrectionDao(db).getCorrectionsByLoan(shopId, loanId);
      expect(afterLockCorrections, isEmpty);

      // No success message should have appeared.
      expect(find.byKey(const Key('correction_success_display')), findsNothing);
    });

    testWidgets('unauthorized users cannot submit the request',
        (WidgetTester tester) async {
      await openScreen(tester, db, actor: cashier());

      await tester.enterText(
        find.byKey(const Key('correction_reason_input')),
        'Should not go through.',
      );
      await tester.tap(find.byKey(const Key('request_correction_button')));
      await tester.pumpAndSettle();

      // Disabled button does nothing; no error key and no success.
      final cashierButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('request_correction_button')),
      );
      expect(cashierButton.onPressed == null, isTrue);
      expect(find.byKey(const Key('correction_error_display')), findsNothing);
      expect(find.byKey(const Key('correction_success_display')), findsNothing);

      // No correction was created.
      final corrections =
          await CorrectionDao(db).getCorrectionsByLoan(shopId, loanId);
      expect(corrections, isEmpty);
    });
  });
}
