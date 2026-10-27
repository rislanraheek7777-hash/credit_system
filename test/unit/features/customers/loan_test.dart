import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/features/customers/domain/models/loan.dart';

void main() {
  final now = DateTime.utc(2026, 10, 14, 9, 30);

  Loan buildLoan({
    LoanStatus status = LoanStatus.active,
    LoanWorkflowStatus workflowStatus = LoanWorkflowStatus.pendingDisbursement,
    int principalCents = 500000,
    int balanceCents = 500000,
  }) {
    return Loan(
      id: 'loan-1',
      shopId: 'shop-1',
      customerId: 1,
      principalCents: principalCents,
      balanceCents: balanceCents,
      status: status,
      workflowStatus: workflowStatus,
      dueDate: now.add(const Duration(days: 30)),
      createdAt: now,
    );
  }

  group('Loan - Workflow Status (Story 4.1)', () {
    test('defaults to pending_disbursement when not specified', () {
      final loan = Loan(
        id: 'loan-1',
        shopId: 'shop-1',
        customerId: 1,
        principalCents: 500000,
        balanceCents: 500000,
        status: LoanStatus.active,
        dueDate: now.add(const Duration(days: 30)),
        createdAt: now,
      );

      expect(loan.workflowStatus, equals(LoanWorkflowStatus.pendingDisbursement));
      expect(loan.isPendingDisbursement, isTrue);
      expect(loan.isDisbursed, isFalse);
    });

    test('fromValue resolves persisted workflow status text', () {
      expect(
        LoanWorkflowStatus.fromValue('pending_disbursement'),
        equals(LoanWorkflowStatus.pendingDisbursement),
      );
      expect(
        LoanWorkflowStatus.fromValue('disbursed'),
        equals(LoanWorkflowStatus.disbursed),
      );
    });

    test('fromValue rejects an unknown workflow status', () {
      expect(
        () => LoanWorkflowStatus.fromValue('settled'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('financial status and workflow status are tracked independently', () {
      final loan = buildLoan(
        status: LoanStatus.active,
        workflowStatus: LoanWorkflowStatus.disbursed,
      );

      expect(loan.status, equals(LoanStatus.active));
      expect(loan.workflowStatus, equals(LoanWorkflowStatus.disbursed));
    });

    test('copyWith preserves workflow status when not overridden', () {
      final loan = buildLoan();
      final copy = loan.copyWith(balanceCents: 400000);

      expect(copy.workflowStatus, equals(LoanWorkflowStatus.pendingDisbursement));
      expect(copy.balanceCents, equals(400000));
    });

    test('copyWith can transition the workflow status', () {
      final loan = buildLoan();
      final copy = loan.copyWith(
        workflowStatus: LoanWorkflowStatus.disbursed,
      );

      expect(copy.workflowStatus, equals(LoanWorkflowStatus.disbursed));
    });

    test('equality takes the workflow status into account', () {
      final pending = buildLoan();
      final disbursed = buildLoan(
        workflowStatus: LoanWorkflowStatus.disbursed,
      );

      expect(pending, isNot(equals(disbursed)));
      expect(pending, equals(buildLoan()));
    });
  });

  group('Loan - Payment Block on Undisbursed Loans (Story 4.1, PRD FR-19)', () {
    test('a pending-disbursement loan is not actionable', () {
      final loan = buildLoan(
        status: LoanStatus.active,
        workflowStatus: LoanWorkflowStatus.pendingDisbursement,
      );

      expect(loan.isActionable, isFalse);
    });

    test('a disbursed active loan is actionable', () {
      final loan = buildLoan(
        status: LoanStatus.active,
        workflowStatus: LoanWorkflowStatus.disbursed,
      );

      expect(loan.isActionable, isTrue);
    });

    test('a disbursed overdue loan is still actionable', () {
      final loan = buildLoan(
        status: LoanStatus.overdue,
        workflowStatus: LoanWorkflowStatus.disbursed,
      );

      expect(loan.isActionable, isTrue);
    });

    test('assertPaymentsAllowed blocks payments on undisbursed loans', () {
      final loan = buildLoan(
        status: LoanStatus.active,
        workflowStatus: LoanWorkflowStatus.pendingDisbursement,
      );

      expect(
        loan.assertPaymentsAllowed,
        throwsA(
          isA<LoanPaymentBlockedException>().having(
            (e) => e.message,
            'message',
            'Payments cannot be accepted on undisbursed loans.',
          ),
        ),
      );
    });

    test('assertPaymentsAllowed permits payments once cash is disbursed', () {
      final loan = buildLoan(
        status: LoanStatus.active,
        workflowStatus: LoanWorkflowStatus.disbursed,
      );

      expect(loan.assertPaymentsAllowed, returnsNormally);
    });
  });

  group('Loan - Cross-Field Invariants (U-5, release-mode)', () {
    test('rejects negative principalCents', () {
      expect(
        () => buildLoan(principalCents: -1),
        throwsA(isA<LoanValidationException>()),
      );
    });

    test('rejects negative balanceCents', () {
      expect(
        () => buildLoan(balanceCents: -1),
        throwsA(isA<LoanValidationException>()),
      );
    });

    test('rejects balanceCents exceeding principalCents', () {
      expect(
        () => buildLoan(principalCents: 100, balanceCents: 200),
        throwsA(isA<LoanValidationException>()),
      );
    });

    test('rejects settled loan without settledAt', () {
      expect(
        () => buildLoan(
          status: LoanStatus.settled,
          workflowStatus: LoanWorkflowStatus.disbursed,
        ),
        throwsA(isA<LoanValidationException>()),
      );
    });

    test('rejects cancelled loan without cancelledAt', () {
      expect(
        () => Loan(
          id: 'loan-1',
          shopId: 'shop-1',
          customerId: 1,
          principalCents: 500000,
          balanceCents: 500000,
          status: LoanStatus.cancelled,
          workflowStatus: LoanWorkflowStatus.cancelled,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
          cancellationReason: 'test reason',
        ),
        throwsA(isA<LoanValidationException>()),
      );
    });

    test('rejects cancelled loan without reason', () {
      expect(
        () => Loan(
          id: 'loan-1',
          shopId: 'shop-1',
          customerId: 1,
          principalCents: 500000,
          balanceCents: 500000,
          status: LoanStatus.cancelled,
          workflowStatus: LoanWorkflowStatus.cancelled,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
          cancelledAt: now,
        ),
        throwsA(isA<LoanValidationException>()),
      );
    });

    test('rejects loan with both termPresetDays and customDueDate', () {
      expect(
        () => Loan(
          id: 'loan-1',
          shopId: 'shop-1',
          customerId: 1,
          principalCents: 500000,
          balanceCents: 500000,
          status: LoanStatus.active,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
          termPresetDays: 30,
          customDueDate: now.add(const Duration(days: 60)),
        ),
        throwsA(isA<LoanValidationException>()),
      );
    });

    test('rejects cancelled loan with non-cancelled workflow', () {
      expect(
        () => Loan(
          id: 'loan-1',
          shopId: 'shop-1',
          customerId: 1,
          principalCents: 500000,
          balanceCents: 500000,
          status: LoanStatus.cancelled,
          workflowStatus: LoanWorkflowStatus.disbursed,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
          cancelledAt: now,
          cancellationReason: 'test reason',
        ),
        throwsA(isA<LoanValidationException>()),
      );
    });

    test('rejects cancelled loan with disbursedAt set', () {
      expect(
        () => Loan(
          id: 'loan-1',
          shopId: 'shop-1',
          customerId: 1,
          principalCents: 500000,
          balanceCents: 500000,
          status: LoanStatus.cancelled,
          workflowStatus: LoanWorkflowStatus.cancelled,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
          cancelledAt: now,
          cancellationReason: 'test reason',
          disbursedAt: now,
        ),
        throwsA(isA<LoanValidationException>()),
      );
    });

    test('rejects termPresetDays outside 30/60/90', () {
      expect(
        () => Loan(
          id: 'loan-1',
          shopId: 'shop-1',
          customerId: 1,
          principalCents: 500000,
          balanceCents: 500000,
          status: LoanStatus.active,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
          termPresetDays: 45,
        ),
        throwsA(isA<LoanValidationException>()),
      );
    });

    test('rejects settled loan with non-disbursed workflow', () {
      expect(
        () => Loan(
          id: 'loan-1',
          shopId: 'shop-1',
          customerId: 1,
          principalCents: 500000,
          balanceCents: 0,
          status: LoanStatus.settled,
          workflowStatus: LoanWorkflowStatus.pendingDisbursement,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
          settledAt: now,
        ),
        throwsA(isA<LoanValidationException>()),
      );
    });

    test('copyWith producing invalid combination throws', () {
      final loan = buildLoan(
        status: LoanStatus.active,
        workflowStatus: LoanWorkflowStatus.disbursed,
      );
      expect(
        () => loan.copyWith(status: LoanStatus.cancelled),
        throwsA(isA<LoanValidationException>()),
      );
    });

    test('valid loan construction does not throw', () {
      expect(() => buildLoan(), returnsNormally);
    });
  });
}
