import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/features/customers/data/daos/loan_dao.dart';
import 'package:credit_system/features/customers/domain/models/loan.dart';

void main() {
  late AppDatabase db;
  late LoanDao loanDao;

  const shopAlphaId = '11111111-1111-1111-1111-111111111101';
  const shopBetaId = '11111111-1111-1111-1111-111111111102';
  const customerAlphaId = '11111111-1111-1111-1111-111111111103';
  const customerBetaId = '11111111-1111-1111-1111-111111111104';

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);
    loanDao = LoanDao(db);

    final now = DateTime.now().toUtc();
    await db.into(db.shops).insert(
      ShopEntry(
        id: shopAlphaId,
        name: 'Alpha Jewellers',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.shops).insert(
      ShopEntry(
        id: shopBetaId,
        name: 'Beta Jewellers',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.customers).insert(
      CustomerEntry(
        id: customerAlphaId,
        shopId: shopAlphaId,
        fullName: 'Alpha Customer',
        nic: '851234567V',
        phone: '0771234567',
        address: '1 Main St',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.customers).insert(
      CustomerEntry(
        id: customerBetaId,
        shopId: shopBetaId,
        fullName: 'Beta Customer',
        nic: '901234567V',
        phone: '0779876543',
        address: '2 Main St',
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('LoanDao - Shop-Scoped Queries', () {
    test('createLoan inserts record with correct shop scoping', () async {
      final now = DateTime.now().toUtc();
      await loanDao.createLoan(
        Loan(
          id: 'loan-alpha-1',
          shopId: shopAlphaId,
          customerId: customerAlphaId,
          principalCents: 500000,
          balanceCents: 500000,
          status: LoanStatus.active,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
        ),
      );

      final loans = await loanDao.getLoansByCustomerId(
        shopAlphaId,
        customerAlphaId,
      );
      expect(loans.length, equals(1));
      expect(loans.first.id, equals('loan-alpha-1'));
      expect(loans.first.status, equals(LoanStatus.active));
    });

    test('getLoansByCustomerId is strictly shop-scoped', () async {
      final now = DateTime.now().toUtc();
      await loanDao.createLoan(
        Loan(
          id: 'loan-alpha-1',
          shopId: shopAlphaId,
          customerId: customerAlphaId,
          principalCents: 500000,
          balanceCents: 500000,
          status: LoanStatus.active,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
        ),
      );
      await loanDao.createLoan(
        Loan(
          id: 'loan-beta-1',
          shopId: shopBetaId,
          customerId: customerBetaId,
          principalCents: 300000,
          balanceCents: 300000,
          status: LoanStatus.active,
          dueDate: now.add(const Duration(days: 60)),
          createdAt: now,
        ),
      );

      final alphaLoans = await loanDao.getLoansByCustomerId(
        shopAlphaId,
        customerAlphaId,
      );
      expect(alphaLoans.length, equals(1));
      expect(alphaLoans.first.id, equals('loan-alpha-1'));

      final betaLoans = await loanDao.getLoansByCustomerId(
        shopBetaId,
        customerBetaId,
      );
      expect(betaLoans.length, equals(1));
      expect(betaLoans.first.id, equals('loan-beta-1'));
    });

    test('getLoansByStatus filters by status within shop', () async {
      final now = DateTime.now().toUtc();
      await loanDao.createLoan(
        Loan(
          id: 'loan-active-1',
          shopId: shopAlphaId,
          customerId: customerAlphaId,
          principalCents: 500000,
          balanceCents: 500000,
          status: LoanStatus.active,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
        ),
      );
      await loanDao.createLoan(
        Loan(
          id: 'loan-overdue-1',
          shopId: shopAlphaId,
          customerId: customerAlphaId,
          principalCents: 300000,
          balanceCents: 300000,
          status: LoanStatus.overdue,
          dueDate: now.subtract(const Duration(days: 5)),
          createdAt: now,
        ),
      );
      await loanDao.createLoan(
        Loan(
          id: 'loan-settled-1',
          shopId: shopAlphaId,
          customerId: customerAlphaId,
          principalCents: 200000,
          balanceCents: 0,
          status: LoanStatus.settled,
          dueDate: now.subtract(const Duration(days: 10)),
          createdAt: now,
          settledAt: now,
        ),
      );

      final activeLoans = await loanDao.getLoansByStatus(
        shopAlphaId,
        LoanStatus.active,
      );
      expect(activeLoans.length, equals(1));
      expect(activeLoans.first.status, equals(LoanStatus.active));

      final overdueLoans = await loanDao.getLoansByStatus(
        shopAlphaId,
        LoanStatus.overdue,
      );
      expect(overdueLoans.length, equals(1));
      expect(overdueLoans.first.status, equals(LoanStatus.overdue));

      final settledLoans = await loanDao.getLoansByStatus(
        shopAlphaId,
        LoanStatus.settled,
      );
      expect(settledLoans.length, equals(1));
      expect(settledLoans.first.status, equals(LoanStatus.settled));
    });

    test('getLoansByCustomerAndStatus filters by both customer and status', () async {
      final now = DateTime.now().toUtc();
      await loanDao.createLoan(
        Loan(
          id: 'loan-active-1',
          shopId: shopAlphaId,
          customerId: customerAlphaId,
          principalCents: 500000,
          balanceCents: 500000,
          status: LoanStatus.active,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
        ),
      );
      await loanDao.createLoan(
        Loan(
          id: 'loan-active-2',
          shopId: shopAlphaId,
          customerId: customerBetaId,
          principalCents: 300000,
          balanceCents: 300000,
          status: LoanStatus.active,
          dueDate: now.add(const Duration(days: 60)),
          createdAt: now,
        ),
      );

      final alphaActiveLoans = await loanDao.getLoansByCustomerAndStatus(
        shopAlphaId,
        customerAlphaId,
        LoanStatus.active,
      );
      expect(alphaActiveLoans.length, equals(1));
      expect(alphaActiveLoans.first.id, equals('loan-active-1'));

      final betaActiveLoans = await loanDao.getLoansByCustomerAndStatus(
        shopAlphaId,
        customerBetaId,
        LoanStatus.active,
      );
      expect(betaActiveLoans.length, equals(1));
      expect(betaActiveLoans.first.id, equals('loan-active-2'));
    });

    test('getLoanById returns null for cross-shop lookup', () async {
      final now = DateTime.now().toUtc();
      await loanDao.createLoan(
        Loan(
          id: 'loan-alpha-1',
          shopId: shopAlphaId,
          customerId: customerAlphaId,
          principalCents: 500000,
          balanceCents: 500000,
          status: LoanStatus.active,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
        ),
      );

      final found = await loanDao.getLoanById(shopAlphaId, 'loan-alpha-1');
      expect(found, isNotNull);
      expect(found!.id, equals('loan-alpha-1'));

      final notFound = await loanDao.getLoanById(shopBetaId, 'loan-alpha-1');
      expect(notFound, isNull);
    });
  });
}
