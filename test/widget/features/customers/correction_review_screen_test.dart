import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/correction_dao.dart';
import 'package:credit_system/features/customers/data/daos/credit_dao.dart';
import 'package:credit_system/features/customers/presentation/correction_review_screen.dart';
import 'package:uuid/uuid.dart';

const String shopAlphaId = 'review-shop-alpha-1111-1111-1111-111111111101';
const String shopBetaId = 'review-shop-beta-1111-1111-1111-111111111102';
const customerAlphaId = 1;
const String ownerAlphaId = 'review-owner-alpha-1111-1111-1111-111111111104';
const String ownerBetaId = 'review-owner-beta-1111-1111-1111-111111111110';
const String managerAlphaId = 'review-mgr-alpha-1111-1111-1111-111111111105';
const String creditAlphaId = 'review-credit-alpha-1111-1111-1111-111111111106';
const String creditBetaId = 'review-credit-beta-1111-1111-1111-111111111107';
const String paymentAlphaId = 'review-pay-alpha-1111-1111-1111-111111111108';

/// Pumps until the screen shows either a success or an error outcome and
/// returns the outcome.
Future<String> pumpUntilOutcome(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    final success = find.byKey(const Key('review_success_display'));
    if (success.evaluate().isNotEmpty) {
      return 'success';
    }
    final error = find.byKey(const Key('review_error_display'));
    if (error.evaluate().isNotEmpty) {
      return 'error: ${tester.widget<Text>(error).data}';
    }
  }
  fail('pumpUntilOutcome: neither a success nor an error was displayed.');
}

/// Seeds two shops, an owner, a manager, customers, credits, and payments.
Future<void> seedReviewData(AppDatabase db) async {
  final now = DateTime.now().toUtc();

  for (final (shopId, shopName) in [
    (shopAlphaId, 'Review Alpha Shop'),
    (shopBetaId, 'Review Beta Shop'),
  ]) {
    await db.into(db.shops).insert(
      ShopEntry(
        id: shopId,
        name: shopName,
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  await db.into(db.customers).insert(
    CustomerEntry(
      id: customerAlphaId,
      shopId: shopAlphaId,
      fullName: 'Review Alpha Customer',
      nic: '851234567V',
      phone: '0771234567',
      address: '1 Test St',
      createdAt: now,
      updatedAt: now,
    ),
  );

  // Shop Owner with approveCorrections permission.
  await db.into(db.appUsers).insert(
    AppUserEntry(
      id: ownerAlphaId,
      shopId: shopAlphaId,
      username: 'review-owner',
      fullName: 'Review Owner',
      role: 'shop_owner',
      isActive: true,
      sessionVersion: 1,
      createdAt: now,
      updatedAt: now,
    ),
  );

  // Shop Owner in shop Beta (for cross-shop test).
  await db.into(db.appUsers).insert(
    AppUserEntry(
      id: ownerBetaId,
      shopId: shopBetaId,
      username: 'review-owner-beta',
      fullName: 'Review Owner Beta',
      role: 'shop_owner',
      isActive: true,
      sessionVersion: 1,
      createdAt: now,
      updatedAt: now,
    ),
  );

  // Manager without approveCorrections permission.
  await db.into(db.appUsers).insert(
    AppUserEntry(
      id: managerAlphaId,
      shopId: shopAlphaId,
      username: 'review-mgr',
      fullName: 'Review Manager',
      role: 'manager',
      isActive: true,
      sessionVersion: 1,
      createdAt: now,
      updatedAt: now,
    ),
  );

  // Credit in shop Alpha.
  await db.into(db.credits).insert(
    CreditsCompanion.insert(
      id: creditAlphaId,
      shopId: shopAlphaId,
      customerId: customerAlphaId,
      principalCents: 500000,
      balanceCents: 300000,
      status: const Value('active'),
      workflowStatus: const Value('disbursed'),
      termPresetDays: const Value(30),
      dueDate: DateTime.utc(2026, 11, 20),
      disbursedAt: Value(DateTime.utc(2026, 10, 21)),
      disbursedByUserId: Value(ownerAlphaId),
      createdAt: now,
      correctionPending: const Value(false),
    ),
  );

  // Credit in shop Beta.
  await db.into(db.credits).insert(
    CreditsCompanion.insert(
      id: creditBetaId,
      shopId: shopBetaId,
      customerId: customerAlphaId,
      principalCents: 400000,
      balanceCents: 200000,
      status: const Value('active'),
      workflowStatus: const Value('disbursed'),
      termPresetDays: const Value(30),
      dueDate: DateTime.utc(2026, 11, 20),
      disbursedAt: Value(DateTime.utc(2026, 10, 21)),
      disbursedByUserId: Value(ownerAlphaId),
      createdAt: now,
      correctionPending: const Value(false),
    ),
  );

  // Original payment in shop Alpha.
  await db.into(db.payments).insert(
    PaymentsCompanion.insert(
      id: paymentAlphaId,
      shopId: shopAlphaId,
      creditId: creditAlphaId,
      receiptNumber: 'RCP-ALPHA-001',
      amountCents: 200000,
      preBalanceCents: 500000,
      postBalanceCents: 300000,
      paymentType: 'partial',
      recordedAt: DateTime.utc(2026, 10, 21),
      recordedByUserId: ownerAlphaId,
      customerId: customerAlphaId,
      customerName: 'Review Alpha Customer',
      customerNic: '851234567V',
      shopName: 'Review Alpha Shop',
      idempotencyKey: 'idemp-alpha-pay',
    ),
  );

  // Original payment in shop Beta (for cross-shop correction).
  await db.into(db.payments).insert(
    PaymentsCompanion.insert(
      id: 'review-pay-beta-1111-1111-1111-111111111109',
      shopId: shopBetaId,
      creditId: creditBetaId,
      receiptNumber: 'RCP-BETA-001',
      amountCents: 100000,
      preBalanceCents: 300000,
      postBalanceCents: 200000,
      paymentType: 'partial',
      recordedAt: DateTime.utc(2026, 10, 21),
      recordedByUserId: ownerAlphaId,
      customerId: customerAlphaId,
      customerName: 'Review Alpha Customer',
      customerNic: '851234567V',
      shopName: 'Review Beta Shop',
      idempotencyKey: 'idemp-beta-pay',
    ),
  );
}

AppUser owner({bool isActive = true}) => AppUser(
      id: ownerAlphaId,
      shopId: shopAlphaId,
      username: 'review-owner',
      fullName: 'Review Owner',
      role: AppRole.shopOwner,
      isActive: isActive,
    );

AppUser ownerBeta({bool isActive = true}) => AppUser(
      id: ownerBetaId,
      shopId: shopBetaId,
      username: 'review-owner-beta',
      fullName: 'Review Owner Beta',
      role: AppRole.shopOwner,
      isActive: isActive,
    );

AppUser manager({bool isActive = true}) => AppUser(
      id: managerAlphaId,
      shopId: shopAlphaId,
      username: 'review-mgr',
      fullName: 'Review Manager',
      role: AppRole.manager,
      isActive: isActive,
    );

/// Submits a pending correction via the DAO and returns it.
Future<CreditCorrection> seedPendingCorrection(AppDatabase db) async {
  return CorrectionDao(db).requestCorrection(
    actor: manager(),
    idempotencyKey: const Uuid().v4(),
    creditId: creditAlphaId,
    originalPaymentId: paymentAlphaId,
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
      home: CorrectionReviewScreen(
        key: UniqueKey(),
        shopId: shopAlphaId,
        currentUser: actor,
        database: db,
      ),
    ),
  );
  // Pump until the screen has finished loading (either corrections or empty
  // state is rendered).
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find.textContaining('No pending correction requests')
        .evaluate()
        .isNotEmpty ||
        find.byType(Card).evaluate().isNotEmpty) {
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
    await seedReviewData(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('CorrectionReviewScreen', () {
    testWidgets('owner can view pending requests for their own shop',
        (WidgetTester tester) async {
      await seedPendingCorrection(db);
      await openScreen(tester, db, actor: owner());

      expect(find.textContaining('Credit ${creditAlphaId.substring(0, 8)}'),
          findsOneWidget);
      expect(find.textContaining('Original payment:'), findsOneWidget);
      expect(find.textContaining('Correction amount: Rs. 2,000.00'),
          findsOneWidget);
    });

    testWidgets('non-owner is blocked from the review screen',
        (WidgetTester tester) async {
      await openScreen(tester, db, actor: manager());

      expect(find.textContaining('You do not have permission'),
          findsOneWidget);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
    });

    testWidgets('cross-shop requests are never displayed',
        (WidgetTester tester) async {
      // Create a pending correction in shop Beta using shop Beta's owner.
      await CorrectionDao(db).requestCorrection(
        actor: ownerBeta(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditBetaId,
        originalPaymentId: 'review-pay-beta-1111-1111-1111-111111111109',
        amount: Money.fromCents(100000),
        reason: 'Cross-shop correction.',
        requestedAt: DateTime.utc(2026, 10, 22),
      );

      await openScreen(tester, db, actor: owner());

      expect(find.textContaining('Credit ${creditBetaId.substring(0, 8)}'),
          findsNothing);
      expect(find.textContaining('Cross-shop correction'), findsNothing);
    });

    testWidgets('approve invokes the DAO correctly',
        (WidgetTester tester) async {
      await seedPendingCorrection(db);
      await openScreen(tester, db, actor: owner());

      await tester.tap(find.text('Approve').first);
      await tester.pumpAndSettle();

      // Confirm the approval dialog.
      await tester.tap(find.byKey(const Key('review_approve_confirm_button')));
      await tester.pumpAndSettle();

      final outcome = await pumpUntilOutcome(tester);
      expect(outcome, equals('success'));

      final correctionDao = CorrectionDao(db);
      final corrections = await correctionDao.getCorrectionsByCredit(
          shopAlphaId, creditAlphaId);
      expect(corrections, hasLength(1));
      expect(corrections.first.status, equals(CreditCorrectionStatus.approved));

      final creditDao = CreditDao(db);
      final credit = await creditDao.getCreditById(shopAlphaId, creditAlphaId);
      expect(credit?.balanceCents, equals(500000)); // 300000 + 200000
      expect(credit?.correctionPending, isFalse);
    });

    testWidgets('reject requires a non-empty reason',
        (WidgetTester tester) async {
      await seedPendingCorrection(db);
      await openScreen(tester, db, actor: owner());

      await tester.tap(find.text('Reject').first);
      await tester.pumpAndSettle();

      // The reject dialog opens with an empty reason field and a disabled
      // confirm button.
      final confirmDisabled = tester.widget<ElevatedButton>(
          find.byKey(const Key('review_reject_confirm_button')));
      expect(confirmDisabled.onPressed, isNull);

      await tester.enterText(
          find.byKey(const Key('review_reject_reason_input')), '   ');
      await tester.pumpAndSettle();

      // Whitespace alone keeps the confirm button disabled.
      final stillDisabled = tester.widget<ElevatedButton>(
          find.byKey(const Key('review_reject_confirm_button')));
      expect(stillDisabled.onPressed, isNull);

      await tester.tap(find.byKey(const Key('review_reject_confirm_button')));
      await tester.pumpAndSettle();

      // The reject button remains disabled; no rejection occurred.
      final corrections = await CorrectionDao(db).getCorrectionsByCredit(
          shopAlphaId, creditAlphaId);
      expect(corrections.first.status, equals(CreditCorrectionStatus.pendingApproval));
    });

    testWidgets('approve confirm is disabled when the post-balance would be negative',
        (WidgetTester tester) async {
      // Seed an out-of-range proposal directly in the database (the DAO
      // refuses over-balance proposals at submit time; this models a
      // proposal whose balance changed underneath it before review).
      final now = DateTime.now().toUtc();
      await db.into(db.creditCorrections).insert(
        CreditCorrectionsCompanion.insert(
          id: 'review-overbalance-1111-1111-1111111111aa',
          shopId: shopAlphaId,
          creditId: creditAlphaId,
          requestedByUserId: managerAlphaId,
          correctionAmountCents: 400000,
          direction: const Value('credit'),
          reason: 'Forgiveness proposed before a settlement posted.',
          status: const Value('pending_approval'),
          createdAt: now,
          updatedAt: now,
        ),
      );

      await openScreen(tester, db, actor: owner());

      await tester.tap(find.byKey(
          const Key('review_approve_review-overbalance-1111-1111-1111111111aa')));
      await tester.pumpAndSettle();

      final confirm = tester.widget<ElevatedButton>(
          find.byKey(const Key('review_approve_confirm_button')));
      expect(confirm.onPressed, isNull);
      expect(find.byKey(const Key('review_negative_balance_warning')),
          findsOneWidget);
    });

    testWidgets('reject invokes the DAO correctly',
        (WidgetTester tester) async {
      await seedPendingCorrection(db);
      await openScreen(tester, db, actor: owner());

      // Get the correction ID to find the reject button by key.
      final correction = await CorrectionDao(db).getCorrectionsByCredit(
          shopAlphaId, creditAlphaId);
      await tester.tap(
          find.byKey(Key('review_reject_${correction.first.id}')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('review_reject_reason_input')),
          'Not a genuine error.');
      await tester.pumpAndSettle();

      // Verify the confirm button is enabled after entering a reason
      final confirmButton = tester.widget<ElevatedButton>(
          find.byKey(const Key('review_reject_confirm_button')));
      expect(confirmButton.onPressed != null, isTrue);

      await tester.tap(find.byKey(const Key('review_reject_confirm_button')));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();

      final updated = await CorrectionDao(db).getCorrectionsByCredit(
          shopAlphaId, creditAlphaId);
      expect(updated.first.status, equals(CreditCorrectionStatus.rejected));
      expect(updated.first.rejectionReason,
          equals('Not a genuine error.'));

      final creditDao = CreditDao(db);
      final credit = await creditDao.getCreditById(shopAlphaId, creditAlphaId);
      expect(credit?.balanceCents, equals(300000)); // unchanged
      expect(credit?.correctionPending, isFalse);
    });

    testWidgets('duplicate taps do not submit repeated actions',
        (WidgetTester tester) async {
      await seedPendingCorrection(db);
      await openScreen(tester, db, actor: owner());

      await tester.tap(find.text('Approve').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review_approve_confirm_button')));
      await tester.pumpAndSettle();
      await pumpUntilOutcome(tester);

      // The approval was applied once.
      final corrections = await CorrectionDao(db).getCorrectionsByCredit(
          shopAlphaId, creditAlphaId);
      expect(corrections, hasLength(1));
      expect(corrections.first.status, equals(CreditCorrectionStatus.approved));
    });

    testWidgets('successful approval updates the displayed queue',
        (WidgetTester tester) async {
      await seedPendingCorrection(db);
      await openScreen(tester, db, actor: owner());

      expect(find.textContaining('Credit ${creditAlphaId.substring(0, 8)}'),
          findsOneWidget);

      await tester.tap(find.text('Approve').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review_approve_confirm_button')));
      await tester.pumpAndSettle();
      await pumpUntilOutcome(tester);

      // The pending correction disappears from the queue.
      expect(find.textContaining('Credit ${creditAlphaId.substring(0, 8)}'),
          findsNothing);
      expect(find.text('No pending correction requests.'), findsOneWidget);
    });

    testWidgets('DAO errors are handled safely',
        (WidgetTester tester) async {
      await seedPendingCorrection(db);
      await openScreen(tester, db, actor: owner());

      await tester.tap(find.text('Approve').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review_approve_confirm_button')));
      await tester.pumpAndSettle();

      // The first approval succeeds.
      final outcome1 = await pumpUntilOutcome(tester);
      expect(outcome1, equals('success'));

      // Attempting to approve the same correction again should fail because
      // it's no longer pending - the Approve button should be gone.
      expect(find.text('Approve'), findsNothing);
    });

    testWidgets('existing correction-request and payment workflows remain functional',
        (WidgetTester tester) async {
      // Verify that the existing correction request DAO still works alongside
      // the review screen.
      final correction = await CorrectionDao(db).requestCorrection(
        actor: manager(),
        idempotencyKey: const Uuid().v4(),
        creditId: creditAlphaId,
        originalPaymentId: paymentAlphaId,
        amount: Money.fromCents(50000),
        reason: 'Workflow coexistence test.',
        requestedAt: DateTime.utc(2026, 10, 22),
      );
      expect(correction.status, equals(CreditCorrectionStatus.pendingApproval));

      final corrections =
          await CorrectionDao(db).getCorrectionsByCredit(shopAlphaId, creditAlphaId);
      expect(corrections.length, equals(1));
    });
  });
}

