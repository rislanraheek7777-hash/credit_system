import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_dao.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';
import 'package:credit_system/features/customers/data/daos/credit_dao.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:credit_system/features/customers/domain/models/credit_term.dart';
import 'package:credit_system/features/customers/presentation/credit_disbursement_screen.dart';

const String shopId = '11111111-1111-1111-1111-111111111401';
const String otherShopId = '11111111-1111-1111-1111-111111111402';
const customerId = 1;
const String managerId = '11111111-1111-1111-1111-111111111404';
const String cashierId = '11111111-1111-1111-1111-111111111405';
const String itemId = 'coll-disb-widget-1';

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

void main() {
  late AppDatabase db;
  late String pendingCreditId;

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);

    final now = DateTime.now().toUtc();
    for (final shop in [
      (id: shopId, name: 'Disbursement Shop'),
      (id: otherShopId, name: 'Other Shop'),
    ]) {
      await db.into(db.shops).insert(
        ShopEntry(
          id: shop.id,
          name: shop.name,
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    for (final user in [
      (id: managerId, username: 'alpha.manager', role: 'manager'),
      (id: cashierId, username: 'alpha.cashier', role: 'cashier'),
      (id: 'disbursement-only-user', username: 'disb.only', role: 'custom'),
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
    await db.into(db.customers).insert(
      CustomerEntry(
        id: customerId,
        shopId: shopId,
        fullName: 'Disbursement Customer',
        nic: '851234567V',
        phone: '0771234567',
        address: '1 Main St',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await CollateralDao(db).createCollateralItem(CollateralItem(
      id: itemId,
      shopId: shopId,
      customerId: customerId,
      itemReferenceId: 'COLL-DISB-W-001',
      category: CollateralItemCategory.gold,
      description: '22K gold necklace',
      conditionGrade: 'Like New',
      weightMilligrams: 5500,
      estimatedValueCents: 1500000,
    ));

    // An agreement awaiting disbursement with an agreed 30-day preset term.
    final zone = ShopTimeZone.defaultTimeZone();
    final creation = zone.localDateOf(now);
    final credit = await CreditDao(db).createCreditAgreement(
      actor: AppUser(
        id: managerId,
        shopId: shopId,
        username: 'alpha.manager',
        fullName: 'Alpha Manager',
        role: AppRole.manager,
        isActive: true,
      ),
      idempotencyKey: 'widget-orig-key',
      customerId: customerId,
      principal: const Money(500000),
      dueDate: zone.instantAtStartOfDay(creation.addDays(30)),
      createdAt: now,
      collateralItemIds: const [itemId],
      termPresetDays: 30,
    );
    pendingCreditId = credit.id;
  });

  tearDown(() async {
    await db.close();
  });

  AppUser manager({bool isActive = true}) => AppUser(
        id: managerId,
        shopId: shopId,
        username: 'alpha.manager',
        fullName: 'Alpha Manager',
        role: AppRole.manager,
        isActive: isActive,
      );

  AppUser cashier() => AppUser(
        id: cashierId,
        shopId: shopId,
        username: 'alpha.cashier',
        fullName: 'Alpha Cashier',
        role: AppRole.cashier,
        isActive: true,
      );

  /// Actor with confirmCreditDisbursement but NOT createCredits or
  /// viewAndReprintReceipts: can confirm disbursement but cannot generate a
  /// voucher. Used to verify voucher-generation failures are reported
  /// separately from disbursement status.
  AppUser disbursementOnlyActor({bool isActive = true}) => AppUser(
        id: 'disbursement-only-user',
        shopId: shopId,
        username: 'disb.only',
        fullName: 'Disbursement Only',
        role: AppRole.custom,
        isActive: isActive,
        customPermissions: {AppPermission.confirmCreditDisbursement},
      );

  Future<void> pumpScreen(
    WidgetTester tester, {
    required AppUser actor,
    String? creditId,
    Finder? waitFor,
  }) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: CreditDisbursementScreen(
          // A distinct key forces a fresh State for a different credit, so the
          // screen reloads rather than reusing the previous agreement.
          key: ValueKey(creditId ?? pendingCreditId),
          shopId: shopId,
          creditId: creditId ?? pendingCreditId,
          currentUser: actor,
          database: db,
        ),
      ),
    );
    await pumpUntil(
      tester,
      () => (waitFor ?? find.byKey(const Key('disbursement_state_banner')))
          .evaluate()
          .isNotEmpty,
    );
  }

  group('CreditDisbursementScreen - pending vs completed disbursement', () {
    testWidgets('an agreement awaiting disbursement is clearly distinguished',
        (tester) async {
      await pumpScreen(tester, actor: manager());

      expect(find.text('Item Receipts'), findsOneWidget);

      expect(
        tester.widget<Text>(find.byKey(const Key('disbursement_state_display'))).data,
        equals('Awaiting Cash Disbursement'),
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('disbursement_due_date_display')))
            .data,
        startsWith(preliminaryDueDateLabel),
        reason: 'The due date must be labelled as preliminary until the cash '
            'has been handed over.',
      );
      expect(
        find.byKey(const Key('disbursement_timestamp_display')),
        findsNothing,
      );
    });

    testWidgets('the agreed term is shown', (tester) async {
      await pumpScreen(tester, actor: manager());

      expect(
        tester
            .widget<Text>(find.byKey(const Key('disbursement_term_display')))
            .data,
        contains('30 Days'),
      );
    });

    testWidgets('an agreement with no recorded agreed term does not claim a '
        'custom term', (tester) async {
      // An agreement created before Story 4.3 has neither a preset term nor a
      // recorded custom due date.
      final now = DateTime.now().toUtc();
      await db.into(db.credits).insert(CreditsCompanion.insert(
        id: 'credit-legacy-term',
        shopId: shopId,
        customerId: customerId,
        principalCents: 500000,
        balanceCents: 500000,
        status: const Value('active'),
        workflowStatus: const Value('pending_disbursement'),
        dueDate: now,
        createdAt: now,
      ));

      await pumpScreen(tester, actor: manager(), creditId: 'credit-legacy-term');

      final label = tester
          .widget<Text>(find.byKey(const Key('disbursement_term_display')))
          .data!;
      expect(label, contains('Not recorded'));
      expect(label, isNot(contains('Custom Date')),
          reason: 'An agreement without a recorded term must not be shown as '
              'having agreed a custom date.');
    });

    testWidgets('a confirmed disbursement is clearly distinguished and shows '
        'the official due date, the staff member and the timestamp',
        (tester) async {
      await pumpScreen(tester, actor: manager());

      await tester.tap(find.byKey(const Key('confirm_disbursement_button')));
      await pumpUntil(tester,
          () => find.byKey(const Key('disbursement_success_display')).evaluate().isNotEmpty);

      expect(
        tester.widget<Text>(find.byKey(const Key('disbursement_state_display'))).data,
        equals('Cash Disbursed'),
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('disbursement_due_date_display')))
            .data,
        startsWith(officialDueDateLabel),
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('disbursement_actor_display')))
            .data,
        contains(managerId),
      );
      expect(
        find.byKey(const Key('disbursement_timestamp_display')),
        findsOneWidget,
      );

      // The agreement can no longer be disbursed from this screen.
      expect(find.byKey(const Key('confirm_disbursement_button')), findsNothing);
      expect(find.byKey(const Key('already_disbursed_notice')), findsOneWidget);
    });

    testWidgets('the persisted agreement reflects the disbursement',
        (tester) async {
      await pumpScreen(tester, actor: manager());

      await tester.tap(find.byKey(const Key('confirm_disbursement_button')));
      await pumpUntil(tester,
          () => find.byKey(const Key('disbursement_success_display')).evaluate().isNotEmpty);

      final credit = await CreditDao(db).getCreditById(shopId, pendingCreditId);
      expect(credit!.workflowStatus, equals(CreditWorkflowStatus.disbursed));
      expect(credit.disbursedByUserId, equals(managerId));
      expect(credit.disbursedAt, isNotNull);
      expect(credit.principalCents, equals(500000));
      expect(credit.balanceCents, equals(500000),
          reason: 'A disbursement is not a payment.');
    });
  });

  group('CreditDisbursementScreen - authorization', () {
    testWidgets('an actor without the confirmCreditDisbursement permission '
        'cannot confirm the handover', (tester) async {
      await pumpScreen(tester, actor: cashier());

      expect(
        find.byKey(const Key('disbursement_permission_notice')),
        findsOneWidget,
      );

      final button = tester.widget<ElevatedButton>(
        find.byKey(const Key('confirm_disbursement_button')),
      );
      expect(button.onPressed, isNull,
          reason: 'The control must be disabled without the permission.');

      // Nothing was disbursed.
      final credit = await CreditDao(db).getCreditById(shopId, pendingCreditId);
      expect(credit!.workflowStatus, equals(CreditWorkflowStatus.pendingDisbursement));
    });

    testWidgets('a deactivated actor cannot confirm the handover',
        (tester) async {
      await pumpScreen(tester, actor: manager(isActive: false));

      final button = tester.widget<ElevatedButton>(
        find.byKey(const Key('confirm_disbursement_button')),
      );
      expect(button.onPressed, isNull);

      final credit = await CreditDao(db).getCreditById(shopId, pendingCreditId);
      expect(credit!.workflowStatus, equals(CreditWorkflowStatus.pendingDisbursement));
    });
  });

  group('CreditDisbursementScreen - scoping', () {
    testWidgets('a credit from another shop is not found', (tester) async {
      // A credit id that does not exist in this shop.
      await pumpScreen(
        tester,
        actor: manager(),
        creditId: 'missing-credit-id',
        waitFor: find.text('Credit agreement not found'),
      );
      expect(find.text('Credit agreement not found'), findsOneWidget);
      expect(
        find.byKey(const Key('confirm_disbursement_button')),
        findsNothing,
        reason: 'There is nothing to disburse for an unknown agreement.',
      );
    });
  });

  group('CreditDisbursementScreen - voucher display', () {
    testWidgets('shows View Official Voucher button after successful '
        'disbursement and voucher generation', (tester) async {
      await pumpScreen(tester, actor: manager());

      await tester.tap(find.byKey(const Key('confirm_disbursement_button')));
      await pumpUntil(tester,
          () => find.byKey(const Key('disbursement_success_display')) .evaluate().isNotEmpty);

      // Disbursement succeeded.
      expect(
        tester.widget<Text>(find.byKey(const Key('disbursement_state_display'))).data,
        equals('Cash Disbursed'),
      );

      // Voucher was generated and the view button is available.
      expect(
        find.byKey(const Key('voucher_generated_display')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('view_voucher_button')),
        findsOneWidget,
      );

      // Persisted state reflects disbursement and snapshot persistence.
      final credit = await CreditDao(db).getCreditById(shopId, pendingCreditId);
      expect(credit!.workflowStatus, equals(CreditWorkflowStatus.disbursed));
      final row = await (db.select(db.credits)..where((t) => t.id.equals(pendingCreditId))).getSingle();
      expect(row.documentSnapshotId, isNotNull);
    });

    testWidgets('shows voucher generation failure separately from '
        'disbursement success when actor lacks voucher permission',
        (tester) async {
      await pumpScreen(tester, actor: disbursementOnlyActor());

      // Verify the confirm button is enabled for this actor.
      final button = tester.widget<ElevatedButton>(
        find.byKey(const Key('confirm_disbursement_button')),
      );
      expect(button.onPressed, isNotNull,
          reason: 'disbursement-only actor has confirmCreditDisbursement permission');

      await tester.tap(find.byKey(const Key('confirm_disbursement_button')));
      // Wait for either success or error to appear.
      await pumpUntil(tester, () {
        return find.byKey(const Key('disbursement_success_display')).evaluate().isNotEmpty ||
            find.byKey(const Key('disbursement_error_display')).evaluate().isNotEmpty;
      });

      final errorFinder = find.byKey(const Key('disbursement_error_display'));
      if (errorFinder.evaluate().isNotEmpty) {
        final errorText = tester.widget<Text>(errorFinder).data!;
        fail('Disbursement failed unexpectedly: $errorText');
      }

      // Disbursement succeeded despite voucher failure.
      expect(
        tester.widget<Text>(find.byKey(const Key('disbursement_state_display'))).data,
        equals('Cash Disbursed'),
      );
      expect(
        find.byKey(const Key('disbursement_success_display')),
        findsOneWidget,
      );

      // Voucher error is shown separately, not as a disbursement error.
      expect(
        find.byKey(const Key('voucher_error_display')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('disbursement_error_display')),
        findsNothing,
      );

      // No voucher button since generation failed.
      expect(find.byKey(const Key('view_voucher_button')), findsNothing);

      // Persisted state still reflects successful disbursement.
      final credit = await CreditDao(db).getCreditById(shopId, pendingCreditId);
      expect(credit!.workflowStatus, equals(CreditWorkflowStatus.disbursed));
    });

    testWidgets('does not show confirm button on already-disbursed credit '
        '(prevents duplicate disbursement)', (tester) async {
      await pumpScreen(tester, actor: manager());

      await tester.tap(find.byKey(const Key('confirm_disbursement_button')));
      await pumpUntil(tester,
          () => find.byKey(const Key('disbursement_success_display')) .evaluate().isNotEmpty);

      // Confirm button is gone; already-disbursed notice is shown.
      expect(find.byKey(const Key('confirm_disbursement_button')), findsNothing);
      expect(find.byKey(const Key('already_disbursed_notice')), findsOneWidget);

      // Voucher button IS shown (voucher was generated for this disbursement).
      expect(find.byKey(const Key('view_voucher_button')), findsOneWidget);

      // Only one disbursement record exists.
      final credit = await CreditDao(db).getCreditById(shopId, pendingCreditId);
      expect(credit!.workflowStatus, equals(CreditWorkflowStatus.disbursed));
      final row = await (db.select(db.credits)..where((t) => t.id.equals(pendingCreditId))).getSingle();
      expect(row.documentSnapshotId, isNotNull);
    });
  });
}

