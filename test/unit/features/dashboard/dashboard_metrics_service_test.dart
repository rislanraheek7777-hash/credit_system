import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/data/daos/user_dao.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/customer_dao.dart';
import 'package:credit_system/features/customers/data/daos/credit_dao.dart';
import 'package:credit_system/features/customers/domain/models/customer.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:credit_system/features/dashboard/data/services/dashboard_metrics_service.dart';
import 'package:credit_system/features/dashboard/domain/models/dashboard_metrics.dart';
import 'package:credit_system/features/shop/data/daos/shop_dao.dart';
import 'package:credit_system/features/shop/domain/models/shop_profile.dart';
import 'package:credit_system/features/customers/domain/models/credit_term.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DashboardMetricsService service;
  late ShopDao shopDao;
  late CustomerDao customerDao;
  late UserDao userDao;
  late CreditDao creditDao;
  late int alphaCustomerOneId;

  const shopAlphaId = 'shop-alpha-dashboard';
  const shopBetaId = 'shop-beta-dashboard';
  final now = DateTime.utc(2026, 11, 5, 9);

  Future<int> addCustomer(String shopId, String name) {
    return customerDao.createCustomer(
      Customer(
        id: 0,
        shopId: shopId,
        fullName: name,
        nic: '',
        phone: '0770000000',
        address: '',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> addUser(String shopId, String id, {bool active = true}) {
    return userDao.createUser(
      AppUser(
        id: id,
        shopId: shopId,
        username: id,
        fullName: id,
        role: AppRole.cashier,
        isActive: active,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> addCredit({
    required String id,
    required String shopId,
    required int customerId,
    required int principalCents,
    required int balanceCents,
    required CreditStatus status,
    required CreditWorkflowStatus workflowStatus,
    DateTime? dueDate,
    DateTime? settledAt,
    DateTime? cancelledAt,
    String? cancellationReason,
  }) {
    return creditDao.createCredit(
      Credit(
        id: id,
        shopId: shopId,
        customerId: customerId,
        principalCents: principalCents,
        balanceCents: balanceCents,
        status: status,
        workflowStatus: workflowStatus,
        dueDate: dueDate ?? now.add(const Duration(days: 30)),
        createdAt: now,
        settledAt: settledAt,
        cancelledAt: cancelledAt,
        cancellationReason: cancellationReason,
      ),
    );
  }

  Future<void> addPayment({
    required String id,
    required String shopId,
    required String creditId,
    required int customerId,
    required String userId,
  }) {
    return db.into(db.payments).insert(
          PaymentsCompanion.insert(
            id: id,
            shopId: shopId,
            creditId: creditId,
            receiptNumber: 'RCP-$id',
            amountCents: 10000,
            preBalanceCents: 50000,
            postBalanceCents: 40000,
            paymentType: 'partial',
            recordedAt: now,
            recordedByUserId: userId,
            customerId: customerId,
            customerName: 'Customer',
            customerNic: '',
            shopName: 'Shop',
            idempotencyKey: 'idem-$id',
          ),
        );
  }

  setUp(() async {
    db = AppDatabase.forTesting(AppDatabaseConnection.openInMemoryConnection());
    service = DashboardMetricsService(db);
    shopDao = db.shopDao;
    customerDao = db.customerDao;
    userDao = db.userDao;
    creditDao = db.creditDao;

    await shopDao.createShop(ShopProfile(id: shopAlphaId, name: 'Alpha'));
    await shopDao.createShop(ShopProfile(id: shopBetaId, name: 'Beta'));

    final alphaCustomerOne = await addCustomer(shopAlphaId, 'Alpha One');
    alphaCustomerOneId = alphaCustomerOne;
    await addCustomer(shopAlphaId, 'Alpha Two');
    final betaCustomerOne = await addCustomer(shopBetaId, 'Beta One');

    await addUser(shopAlphaId, 'alpha-owner');
    await addUser(shopAlphaId, 'alpha-cashier');
    await addUser(shopAlphaId, 'alpha-inactive', active: false);
    await addUser(shopBetaId, 'beta-owner');

    await addCredit(
      id: 'alpha-active',
      shopId: shopAlphaId,
      customerId: alphaCustomerOne,
      principalCents: 50000,
      balanceCents: 40000,
      status: CreditStatus.active,
      workflowStatus: CreditWorkflowStatus.disbursed,
    );
    await addCredit(
      id: 'alpha-overdue',
      shopId: shopAlphaId,
      customerId: alphaCustomerOne,
      principalCents: 30000,
      balanceCents: 30000,
      status: CreditStatus.overdue,
      workflowStatus: CreditWorkflowStatus.overdue,
      dueDate: DateTime.now().toUtc().subtract(const Duration(days: 10)),
    );
    await addCredit(
      id: 'alpha-settled',
      shopId: shopAlphaId,
      customerId: alphaCustomerOne,
      principalCents: 20000,
      balanceCents: 0,
      status: CreditStatus.settled,
      workflowStatus: CreditWorkflowStatus.disbursed,
      settledAt: now,
    );
    // Agreed but not yet disbursed: counted as a credit agreement and included
    // in active credit/outstanding so the dashboard reflects creation immediately.
    await addCredit(
      id: 'alpha-pending',
      shopId: shopAlphaId,
      customerId: alphaCustomerOne,
      principalCents: 7000,
      balanceCents: 7000,
      status: CreditStatus.active,
      workflowStatus: CreditWorkflowStatus.pendingDisbursement,
    );
    await addCredit(
      id: 'alpha-cancelled',
      shopId: shopAlphaId,
      customerId: alphaCustomerOne,
      principalCents: 10000,
      balanceCents: 10000,
      status: CreditStatus.cancelled,
      workflowStatus: CreditWorkflowStatus.cancelled,
      cancelledAt: now,
      cancellationReason: 'Customer withdrew',
    );
    await addCredit(
      id: 'beta-active',
      shopId: shopBetaId,
      customerId: betaCustomerOne,
      principalCents: 99900,
      balanceCents: 99900,
      status: CreditStatus.active,
      workflowStatus: CreditWorkflowStatus.disbursed,
    );

    await addPayment(
      id: 'alpha-payment',
      shopId: shopAlphaId,
      creditId: 'alpha-active',
      customerId: alphaCustomerOne,
      userId: 'alpha-owner',
    );
    await addPayment(
      id: 'beta-payment',
      shopId: shopBetaId,
      creditId: 'beta-active',
      customerId: betaCustomerOne,
      userId: 'beta-owner',
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('DashboardMetricsService', () {
    test('excludes soft-deleted customers from totalCustomers', () async {
      const softDeleteShopId = 'shop-soft-delete-metrics';
      await shopDao.createShop(
        ShopProfile(id: softDeleteShopId, name: 'Soft Delete Shop'),
      );
      await addCustomer(softDeleteShopId, 'Live Customer');
      final deletedId = await addCustomer(softDeleteShopId, 'Deleted Customer');
      await customerDao.softDeleteCustomer(
        actor: AppUser(
          id: 'soft-delete-owner',
          shopId: softDeleteShopId,
          username: 'owner',
          fullName: 'Owner',
          role: AppRole.shopOwner,
          isActive: true,
        ),
        shopId: softDeleteShopId,
        customerId: deletedId,
      );

      final metrics = await service.loadMetrics(softDeleteShopId);
      expect(metrics.totalCustomers, 1);
    });

    test('aggregates only the requested shop', () async {
      final metrics = await service.loadMetrics(shopAlphaId);

      expect(metrics.totalCustomers, 2);
      expect(metrics.totalStaff, 2);
      expect(metrics.totalCredits, 4);
      expect(metrics.activeCreditCents, 87000);
      expect(metrics.collectedCents, 30000);
      expect(metrics.overdueCents, 30000);
    });

    test('returns an empty snapshot for an unknown shop', () async {
      final metrics = await service.loadMetrics('missing-shop');

      expect(metrics.totalCustomers, 0);
      expect(metrics.totalStaff, 0);
      expect(metrics.totalCredits, 0);
      expect(metrics.activeCreditCents, 0);
      expect(metrics.collectedCents, 0);
      expect(metrics.overdueCents, 0);
    });

    test('overdue counts only past-due, disbursed, unsettled balances', () async {
      final pastDue = DateTime.now().toUtc().subtract(const Duration(days: 5));

      // Past-due and disbursed: must count.
      await addCredit(
        id: 'alpha-overdue-extra',
        shopId: shopAlphaId,
        customerId: alphaCustomerOneId,
        principalCents: 21000,
        balanceCents: 12000,
        status: CreditStatus.active,
        workflowStatus: CreditWorkflowStatus.disbursed,
        dueDate: pastDue,
      );
      // Past-due but still pending disbursement: must not count.
      await addCredit(
        id: 'alpha-overdue-pending',
        shopId: shopAlphaId,
        customerId: alphaCustomerOneId,
        principalCents: 40000,
        balanceCents: 40000,
        status: CreditStatus.active,
        workflowStatus: CreditWorkflowStatus.pendingDisbursement,
        dueDate: pastDue,
      );
      // Past-due but fully repaid: must not count.
      await addCredit(
        id: 'alpha-overdue-settled',
        shopId: shopAlphaId,
        customerId: alphaCustomerOneId,
        principalCents: 15000,
        balanceCents: 0,
        status: CreditStatus.settled,
        workflowStatus: CreditWorkflowStatus.disbursed,
        dueDate: pastDue,
        settledAt: now,
      );

      final metrics = await service.loadMetrics(shopAlphaId);
      expect(metrics.overdueCents, 30000 + 12000);
    });

    test('overdue boundary: due at local midnight today is not yet overdue', () async {
      final zone = ShopTimeZone.defaultTimeZone();
      final nowUtc = DateTime.now().toUtc();
      final dueToday = zone.instantAtStartOfDay(zone.localDateOf(nowUtc));
      final dueYesterday = dueToday.subtract(const Duration(days: 1));

      await addCredit(
        id: 'alpha-boundary-today',
        shopId: shopAlphaId,
        customerId: alphaCustomerOneId,
        principalCents: 20000,
        balanceCents: 20000,
        status: CreditStatus.active,
        workflowStatus: CreditWorkflowStatus.disbursed,
        dueDate: dueToday,
      );
      await addCredit(
        id: 'alpha-boundary-yesterday',
        shopId: shopAlphaId,
        customerId: alphaCustomerOneId,
        principalCents: 15000,
        balanceCents: 15000,
        status: CreditStatus.active,
        workflowStatus: CreditWorkflowStatus.disbursed,
        dueDate: dueYesterday,
      );

      final metrics = await service.loadMetrics(shopAlphaId);
      // Baseline (30000 from alpha-overdue) counts the past-due credit only;
      // the credit due exactly at local midnight today is not overdue.
      expect(metrics.overdueCents, 30000 + 15000);
    });

    test('re-emits when customers, staff, and credits are added', () async {
      final values = <DashboardMetrics>[];
      final subscription = service.watchMetrics(shopAlphaId).listen(values.add);
      addTearDown(subscription.cancel);

      await _waitUntil(() => values.isNotEmpty);
      final initial = values.last;
      expect(initial.totalCustomers, 2);
      expect(initial.totalStaff, 2);
      expect(initial.totalCredits, 4);
      expect(initial.activeCreditCents, 87000);

      await addPayment(
        id: 'alpha-live-payment',
        shopId: shopAlphaId,
        creditId: 'alpha-active',
        customerId: alphaCustomerOneId,
        userId: 'alpha-owner',
      );

      final newCustomerId = await addCustomer(shopAlphaId, 'Alpha Three');
      await _waitUntil(() => values.last.totalCustomers == initial.totalCustomers + 1);

      await addUser(shopAlphaId, 'alpha-manager');
      await _waitUntil(() => values.last.totalStaff == initial.totalStaff + 1);

      await addCredit(
        id: 'alpha-new-credit',
        shopId: shopAlphaId,
        customerId: newCustomerId,
        principalCents: 15000,
        balanceCents: 15000,
        status: CreditStatus.active,
        workflowStatus: CreditWorkflowStatus.disbursed,
      );
      await _waitUntil(() => values.last.totalCredits == initial.totalCredits + 1);

      expect(values.last.activeCreditCents, initial.activeCreditCents + 15000);
    });

    test('re-emits and counts a newly created pending-disbursement credit', () async {
      final values = <DashboardMetrics>[];
      final subscription = service.watchMetrics(shopAlphaId).listen(values.add);
      addTearDown(subscription.cancel);

      await _waitUntil(() => values.isNotEmpty);
      final initial = values.last;

      await addCredit(
        id: 'alpha-new-pending',
        shopId: shopAlphaId,
        customerId: alphaCustomerOneId,
        principalCents: 12000,
        balanceCents: 12000,
        status: CreditStatus.active,
        workflowStatus: CreditWorkflowStatus.pendingDisbursement,
      );
      await _waitUntil(() => values.last.totalCredits == initial.totalCredits + 1);

      expect(values.last.activeCreditCents, initial.activeCreditCents + 12000);
      expect(values.last.collectedCents, initial.collectedCents);

      final beta = await service.loadMetrics(shopBetaId);
      expect(beta.totalCredits, 1);
      expect(beta.activeCreditCents, 99900);
    });
  });
}

Future<void> _waitUntil(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for dashboard metrics to update.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

