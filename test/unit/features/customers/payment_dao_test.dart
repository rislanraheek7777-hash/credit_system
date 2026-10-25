import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/loan_dao.dart';
import 'package:credit_system/features/customers/data/daos/payment_dao.dart';
import 'package:credit_system/features/customers/data/services/receipt_pdf_service.dart';
import 'package:credit_system/features/customers/domain/models/loan.dart';
import 'package:credit_system/features/customers/domain/models/receipt.dart';
import 'package:credit_system/features/customers/domain/services/receipt_service.dart';
import 'package:uuid/uuid.dart';

const String shopId = 'pay-shop-1111-1111-1111-111111111101';
const String otherShopId = 'pay-shop-1111-1111-1111-111111111102';
const String customerId = 'pay-cust-1111-1111-1111-111111111101';
const String managerId = 'pay-mgr-1111-1111-1111-111111111101';
const String cashierId = 'pay-cash-1111-1111-1111-111111111101';
const String loanId = 'pay-loan-1111-1111-1111-111111111101';

Future<void> seedData(AppDatabase db) async {
  final now = DateTime.utc(2026, 10, 20);

  await db.into(db.shops).insert(
    ShopEntry(
      id: shopId,
      name: 'Payment Test Shop',
      currencyCode: 'LKR',
      timezone: 'Asia/Colombo',
      businessAddress: '123 Test Street',
      contactPhone: '+94771234567',
      registrationNumber: 'REG-123',
      receiptHeaderNotes: 'Header notes',
      receiptFooterNotes: 'Footer notes',
      createdAt: now,
      updatedAt: now,
    ),
  );
  await db.into(db.shops).insert(
    ShopEntry(
      id: otherShopId,
      name: 'Other Shop',
      currencyCode: 'LKR',
      timezone: 'Asia/Colombo',
      createdAt: now,
      updatedAt: now,
    ),
  );

  for (final user in [
    (id: managerId, username: 'paymgr', role: 'manager'),
    (id: cashierId, username: 'paycash', role: 'cashier'),
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
      fullName: 'Payment Customer',
      nic: '851234567V',
      phone: '0771234567',
      address: '1 Test St',
      createdAt: now,
      updatedAt: now,
    ),
  );

  // Create a disbursed loan with principal 500000 (Rs. 5,000.00) and balance 500000
  await db.into(db.loans).insert(
    LoansCompanion.insert(
      id: loanId,
      shopId: shopId,
      customerId: customerId,
      principalCents: 500000,
      balanceCents: 500000,
      status: const Value('active'),
      workflowStatus: const Value('disbursed'),
      termPresetDays: const Value(30),
      dueDate: DateTime.utc(2026, 11, 20),
      disbursedAt: Value(DateTime.utc(2026, 10, 21)),
      disbursedByUserId: Value(managerId),
      createdAt: now,
    ),
  );
}

AppUser manager({bool isActive = true}) => AppUser(
      id: managerId,
      shopId: shopId,
      username: 'paymgr',
      fullName: 'Payment Manager',
      role: AppRole.manager,
      isActive: isActive,
    );

AppUser cashier({bool isActive = true}) => AppUser(
      id: cashierId,
      shopId: shopId,
      username: 'paycash',
      fullName: 'Payment Cashier',
      role: AppRole.cashier,
      isActive: isActive,
    );

void main() {
  late AppDatabase db;
  late PaymentDao paymentDao;
  late ReceiptService receiptService;
  late ReceiptPdfService pdfService;

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);
    await seedData(db);
    paymentDao = PaymentDao(db);
    receiptService = ReceiptService();
    pdfService = ReceiptPdfService();
  });

  tearDown(() async {
    await db.close();
  });

  group('PaymentDao - recordPayment', () {
    test('partial payment reduces outstanding balance correctly', () async {
      final receipt = await paymentDao.recordPayment(
        actor: manager(),
        idempotencyKey: Uuid().v4(),
        loanId: loanId,
        amount: const Money(200000), // Rs. 2,000.00
        recordedAt: DateTime.utc(2026, 10, 22),
      );

      expect(receipt.amountCents, 200000);
      expect(receipt.preBalanceCents, 500000);
      expect(receipt.postBalanceCents, 300000);
      expect(receipt.isFullSettlement, isFalse);
      expect(receipt.paymentTypeLabel, 'Partial Payment');

      // Verify loan balance updated
      final loanDao = LoanDao(db);
      final loan = await loanDao.getLoanById(shopId, loanId);
      expect(loan!.balanceCents, 300000);
      expect(loan.status, LoanStatus.active);
    });

    test('full settlement results in zero balance and settled status', () async {
      final receipt = await paymentDao.recordPayment(
        actor: manager(),
        idempotencyKey: Uuid().v4(),
        loanId: loanId,
        amount: const Money(500000), // Rs. 5,000.00 (full balance)
        recordedAt: DateTime.utc(2026, 10, 22),
      );

      expect(receipt.postBalanceCents, 0);
      expect(receipt.isFullSettlement, isTrue);
      expect(receipt.paymentTypeLabel, 'Full Settlement');

      final loanDao = LoanDao(db);
      final loan = await loanDao.getLoanById(shopId, loanId);
      expect(loan!.balanceCents, 0);
      expect(loan.status, LoanStatus.settled);
      expect(loan.settledAt, isNotNull);
    });

    test('zero payment amount is rejected', () async {
      await expectLater(
        paymentDao.recordPayment(
          actor: manager(),
          idempotencyKey: Uuid().v4(),
          loanId: loanId,
          amount: const Money(0),
          recordedAt: DateTime.utc(2026, 10, 22),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('negative payment amount is rejected', () async {
      await expectLater(
        paymentDao.recordPayment(
          actor: manager(),
          idempotencyKey: Uuid().v4(),
          loanId: loanId,
          amount: const Money(-1000),
          recordedAt: DateTime.utc(2026, 10, 22),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('excessive payment amount (overpayment) is rejected', () async {
      await expectLater(
        paymentDao.recordPayment(
          actor: manager(),
          idempotencyKey: Uuid().v4(),
          loanId: loanId,
          amount: const Money(600000), // exceeds balance of 500000
          recordedAt: DateTime.utc(2026, 10, 22),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('payment against undisbursed loan is rejected', () async {
      // Create a pending disbursement loan
      await db.into(db.loans).insert(
        LoansCompanion.insert(
          id: 'pay-loan-pending',
          shopId: shopId,
          customerId: customerId,
          principalCents: 100000,
          balanceCents: 100000,
          status: const Value('active'),
          workflowStatus: const Value('pending_disbursement'),
          termPresetDays: const Value(30),
          dueDate: DateTime.utc(2026, 11, 20),
          createdAt: DateTime.utc(2026, 10, 20),
        ),
      );

      await expectLater(
        paymentDao.recordPayment(
          actor: manager(),
          idempotencyKey: Uuid().v4(),
          loanId: 'pay-loan-pending',
          amount: const Money(50000),
          recordedAt: DateTime.utc(2026, 10, 22),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('payment against settled loan is rejected', () async {
      // First settle the loan
      await paymentDao.recordPayment(
        actor: manager(),
        idempotencyKey: Uuid().v4(),
        loanId: loanId,
        amount: const Money(500000),
        recordedAt: DateTime.utc(2026, 10, 22),
      );

      // Try another payment
      await expectLater(
        paymentDao.recordPayment(
          actor: manager(),
          idempotencyKey: Uuid().v4(),
          loanId: loanId,
          amount: const Money(10000),
          recordedAt: DateTime.utc(2026, 10, 23),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('unauthorized actor (no recordPayments) is rejected', () async {
      final noPerm = AppUser(
        id: 'pay-noperm',
        shopId: shopId,
        username: 'paynoperm',
        fullName: 'No Perm',
        role: AppRole.custom,
        isActive: true,
        customPermissions: {AppPermission.viewCustomers},
      );

      await expectLater(
        paymentDao.recordPayment(
          actor: noPerm,
          idempotencyKey: Uuid().v4(),
          loanId: loanId,
          amount: const Money(10000),
          recordedAt: DateTime.utc(2026, 10, 22),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('cross-shop loan access is rejected', () async {
      // Create a loan in another shop
      await db.into(db.loans).insert(
        LoansCompanion.insert(
          id: 'pay-loan-other-shop',
          shopId: otherShopId,
          customerId: customerId,
          principalCents: 100000,
          balanceCents: 100000,
          status: const Value('active'),
          workflowStatus: const Value('disbursed'),
          termPresetDays: const Value(30),
          dueDate: DateTime.utc(2026, 11, 20),
          disbursedAt: Value(DateTime.utc(2026, 10, 21)),
          disbursedByUserId: Value(managerId),
          createdAt: DateTime.utc(2026, 10, 20),
        ),
      );

      await expectLater(
        paymentDao.recordPayment(
          actor: manager(),
          idempotencyKey: Uuid().v4(),
          loanId: 'pay-loan-other-shop',
          amount: const Money(10000),
          recordedAt: DateTime.utc(2026, 10, 22),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('duplicate idempotency key does not create duplicate payment', () async {
      final key = const Uuid().v4();

      final receipt1 = await paymentDao.recordPayment(
        actor: manager(),
        idempotencyKey: key,
        loanId: loanId,
        amount: const Money(100000),
        recordedAt: DateTime.utc(2026, 10, 22),
      );

      final receipt2 = await paymentDao.recordPayment(
        actor: manager(),
        idempotencyKey: key,
        loanId: loanId,
        amount: const Money(100000),
        recordedAt: DateTime.utc(2026, 10, 22),
      );

      expect(receipt2.receiptNumber, receipt1.receiptNumber);
      expect(receipt2.amountCents, receipt1.amountCents);

      // Verify only one payment row exists
      final payments = await paymentDao.getPaymentsByLoan(shopId, loanId);
      expect(payments, hasLength(1));

      // Verify balance was only reduced once
      final loanDao = LoanDao(db);
      final loan = await loanDao.getLoanById(shopId, loanId);
      expect(loan!.balanceCents, 400000);
    });

    test('receipt generation failure does not lose committed payment', () async {
      // This test verifies that even if PDF generation fails,
      // the payment and receipt row are still committed.
      final receipt = await paymentDao.recordPayment(
        actor: manager(),
        idempotencyKey: Uuid().v4(),
        loanId: loanId,
        amount: const Money(100000),
        recordedAt: DateTime.utc(2026, 10, 22),
      );

      // Payment is committed
      expect(receipt.receiptNumber, isNotEmpty);
      expect(receipt.amountCents, 100000);

      // Receipt row exists in database
      final retrieved = await paymentDao.getReceiptByNumber(
        shopId,
        receipt.receiptNumber,
      );
      expect(retrieved, isNotNull);
      expect(retrieved!.postBalanceCents, 400000);

      // PDF generation can be attempted separately (may fail in test env
      // due to font issues, but payment is preserved)
      try {
        await pdfService.renderReceiptPdf(
          receipt: receipt,
          showRawPII: false,
          isReprint: false,
        );
      } catch (_) {
        // PDF generation failure doesn't affect payment
      }

      // Payment still intact
      final loanDao = LoanDao(db);
      final loan = await loanDao.getLoanById(shopId, loanId);
      expect(loan!.balanceCents, 400000);
    });

    test('payment history and receipt snapshots persist', () async {
      await paymentDao.recordPayment(
        actor: manager(),
        idempotencyKey: Uuid().v4(),
        loanId: loanId,
        amount: const Money(150000),
        recordedAt: DateTime.utc(2026, 10, 22),
      );

      final payments = await paymentDao.getPaymentsByLoan(shopId, loanId);
      expect(payments, hasLength(1));
      expect(payments.first.receiptNumber, isNotEmpty);
      expect(payments.first.customerName, 'Payment Customer');
      expect(payments.first.shopName, 'Payment Test Shop');
      expect(payments.first.amountFormatted, 'Rs. 1,500.00');
    });

    test('concurrent payments cannot overpay the same loan', () async {
      // Reset loan balance to 100000 for this test
      final loanDao = LoanDao(db);
      await (db.update(db.loans)
            ..where((l) => l.id.equals(loanId)))
          .write(LoansCompanion(
        balanceCents: Value(100000),
        status: Value(LoanStatus.active.value),
      ));

      // Two concurrent payments of 100000 each against a 100000 balance.
      // Wrap each call in try/catch so both complete independently.
      final results = <Receipt?>[];
      await Future.wait([
        paymentDao.recordPayment(
          actor: manager(),
          idempotencyKey: Uuid().v4(),
          loanId: loanId,
          amount: const Money(100000),
          recordedAt: DateTime.utc(2026, 10, 22),
        ).then((r) => results.add(r)).onError((e, _) => results.add(null)),
        paymentDao.recordPayment(
          actor: manager(),
          idempotencyKey: Uuid().v4(),
          loanId: loanId,
          amount: const Money(100000),
          recordedAt: DateTime.utc(2026, 10, 22),
        ).then((r) => results.add(r)).onError((e, _) => results.add(null)),
      ]);

      // Exactly one should succeed
      final successful = results.whereType<Receipt>().length;
      expect(successful, 1);

      // Balance should be 0 (only one payment of 100000 applied)
      final loan = await loanDao.getLoanById(shopId, loanId);
      expect(loan!.balanceCents, 0);
      expect(loan.status, LoanStatus.settled);

      // Only one payment record should exist
      final payments = await paymentDao.getPaymentsByLoan(shopId, loanId);
      expect(payments, hasLength(1));
    });

    test('reused idempotency key with different loan is rejected', () async {
      final key = const Uuid().v4();

      await paymentDao.recordPayment(
        actor: manager(),
        idempotencyKey: key,
        loanId: loanId,
        amount: const Money(100000),
        recordedAt: DateTime.utc(2026, 10, 22),
      );

      // Same key, different loan - should be rejected
      await expectLater(
        paymentDao.recordPayment(
          actor: manager(),
          idempotencyKey: key,
          loanId: 'different-loan',
          amount: const Money(50000),
          recordedAt: DateTime.utc(2026, 10, 22),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('reused idempotency key with different amount returns original receipt', () async {
      final key = const Uuid().v4();

      final receipt1 = await paymentDao.recordPayment(
        actor: manager(),
        idempotencyKey: key,
        loanId: loanId,
        amount: const Money(100000),
        recordedAt: DateTime.utc(2026, 10, 22),
      );

      // Same key, different amount - should return original receipt (not create new payment)
      final receipt2 = await paymentDao.recordPayment(
        actor: manager(),
        idempotencyKey: key,
        loanId: loanId,
        amount: const Money(200000), // different amount
        recordedAt: DateTime.utc(2026, 10, 22),
      );

      expect(receipt2.receiptNumber, receipt1.receiptNumber);
      expect(receipt2.amountCents, receipt1.amountCents);
    });

    test('schema version is 19 and payments table is accessible', () async {
      // Verify the database is at schema version 19
      expect(db.schemaVersion, 19);

      // Verify the payments table exists and is queryable
      final count = await db.customSelect(
        'SELECT COUNT(*) as c FROM payments',
      ).getSingle();
      expect(count.read<int>('c'), 0);

      // Insert a payment and verify it's retrievable
      await paymentDao.recordPayment(
        actor: manager(),
        idempotencyKey: Uuid().v4(),
        loanId: loanId,
        amount: const Money(250000),
        recordedAt: DateTime.utc(2026, 10, 22),
      );

      final count2 = await db.customSelect(
        'SELECT COUNT(*) as c FROM payments',
      ).getSingle();
      expect(count2.read<int>('c'), 1);
    });
  });

  group('ReceiptService - validation and eligibility', () {
    test('isEligibleForPayment returns true for disbursed active loan with balance', () async {
      final loanDao = LoanDao(db);
      final loan = await loanDao.getLoanById(shopId, loanId);
      expect(receiptService.isEligibleForPayment(loan!), isTrue);
    });

    test('isEligibleForPayment returns false for pending disbursement loan', () async {
      final pendingLoan = Loan(
        id: 'pending',
        shopId: shopId,
        customerId: customerId,
        principalCents: 100000,
        balanceCents: 100000,
        status: LoanStatus.active,
        workflowStatus: LoanWorkflowStatus.pendingDisbursement,
        dueDate: DateTime.utc(2026, 11, 20),
        createdAt: DateTime.utc(2026, 10, 20),
      );
      expect(receiptService.isEligibleForPayment(pendingLoan), isFalse);
    });

    test('isEligibleForPayment returns false for settled loan', () async {
      final settledLoan = Loan(
        id: 'settled',
        shopId: shopId,
        customerId: customerId,
        principalCents: 100000,
        balanceCents: 0,
        status: LoanStatus.settled,
        workflowStatus: LoanWorkflowStatus.disbursed,
        dueDate: DateTime.utc(2026, 11, 20),
        disbursedAt: DateTime.utc(2026, 10, 21),
        disbursedByUserId: managerId,
        settledAt: DateTime.utc(2026, 10, 22),
        createdAt: DateTime.utc(2026, 10, 20),
      );
      expect(receiptService.isEligibleForPayment(settledLoan), isFalse);
    });

    test('validateAmount rejects zero amount', () async {
      expect(
        () => receiptService.validateAmount(amountCents: 0, balanceCents: 100000),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('validateAmount rejects overpayment', () async {
      expect(
        () => receiptService.validateAmount(
          amountCents: 600000,
          balanceCents: 500000,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('validateAmount accepts valid partial payment', () async {
      final result = receiptService.validateAmount(
        amountCents: 200000,
        balanceCents: 500000,
      );
      expect(result, 200000);
    });

    test('validateAmount accepts full settlement', () async {
      final result = receiptService.validateAmount(
        amountCents: 500000,
        balanceCents: 500000,
      );
      expect(result, 500000);
    });
  });

  group('Receipt - model', () {
    test('receipt formatted strings are correct', () {
      final receipt = Receipt(
        id: 'receipt-1',
        shopId: shopId,
        loanId: loanId,
        receiptNumber: 'RCP-123',
        amountCents: 200000,
        preBalanceCents: 500000,
        postBalanceCents: 300000,
        paymentType: PaymentType.partialPayment,
        recordedAt: DateTime.utc(2026, 10, 22, 14, 30),
        recordedByUserId: managerId,
        customerId: customerId,
        customerName: 'Test Customer',
        customerNic: '851234567V',
        shopName: 'Test Shop',
        shopAddress: '123 Test St',
        shopPhone: '+94771234567',
        shopTaxId: 'REG-123',
        shopFooterNotes: 'Thank you',
        idempotencyKey: 'key-1',
      );

      expect(receipt.amountFormatted, 'Rs. 2,000.00');
      expect(receipt.preBalanceFormatted, 'Rs. 5,000.00');
      expect(receipt.postBalanceFormatted, 'Rs. 3,000.00');
      expect(receipt.paymentTypeLabel, 'Partial Payment');
      expect(receipt.isFullSettlement, isFalse);
      expect(receipt.recordedAtFormatted, contains('22/10/2026'));
    });

    test('full settlement receipt is marked correctly', () {
      final receipt = Receipt(
        id: 'receipt-2',
        shopId: shopId,
        loanId: loanId,
        receiptNumber: 'RCP-456',
        amountCents: 500000,
        preBalanceCents: 500000,
        postBalanceCents: 0,
        paymentType: PaymentType.fullSettlement,
        recordedAt: DateTime.utc(2026, 10, 22),
        recordedByUserId: managerId,
        customerId: customerId,
        customerName: 'Test Customer',
        customerNic: '851234567V',
        shopName: 'Test Shop',
        idempotencyKey: 'key-2',
      );

      expect(receipt.isFullSettlement, isTrue);
      expect(receipt.paymentTypeLabel, 'Full Settlement');
    });
  });
}
