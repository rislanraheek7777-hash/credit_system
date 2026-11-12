import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';

void main() {
  final now = DateTime.utc(2026, 10, 14, 9, 30);

  Credit buildCredit({
    CreditStatus status = CreditStatus.active,
    CreditWorkflowStatus workflowStatus = CreditWorkflowStatus.pendingDisbursement,
    int principalCents = 500000,
    int balanceCents = 500000,
  }) {
    return Credit(
      id: 'credit-1',
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

  group('Credit - Workflow Status (Story 4.1)', () {
    test('defaults to pending_disbursement when not specified', () {
      final credit = Credit(
        id: 'credit-1',
        shopId: 'shop-1',
        customerId: 1,
        principalCents: 500000,
        balanceCents: 500000,
        status: CreditStatus.active,
        dueDate: now.add(const Duration(days: 30)),
        createdAt: now,
      );

      expect(credit.workflowStatus, equals(CreditWorkflowStatus.pendingDisbursement));
      expect(credit.isPendingDisbursement, isTrue);
      expect(credit.isDisbursed, isFalse);
    });

    test('fromValue resolves persisted workflow status text', () {
      expect(
        CreditWorkflowStatus.fromValue('pending_disbursement'),
        equals(CreditWorkflowStatus.pendingDisbursement),
      );
      expect(
        CreditWorkflowStatus.fromValue('disbursed'),
        equals(CreditWorkflowStatus.disbursed),
      );
    });

    test('fromValue rejects an unknown workflow status', () {
      expect(
        () => CreditWorkflowStatus.fromValue('settled'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('financial status and workflow status are tracked independently', () {
      final credit = buildCredit(
        status: CreditStatus.active,
        workflowStatus: CreditWorkflowStatus.disbursed,
      );

      expect(credit.status, equals(CreditStatus.active));
      expect(credit.workflowStatus, equals(CreditWorkflowStatus.disbursed));
    });

    test('copyWith preserves workflow status when not overridden', () {
      final credit = buildCredit();
      final copy = credit.copyWith(balanceCents: 400000);

      expect(copy.workflowStatus, equals(CreditWorkflowStatus.pendingDisbursement));
      expect(copy.balanceCents, equals(400000));
    });

    test('copyWith can transition the workflow status', () {
      final credit = buildCredit();
      final copy = credit.copyWith(
        workflowStatus: CreditWorkflowStatus.disbursed,
      );

      expect(copy.workflowStatus, equals(CreditWorkflowStatus.disbursed));
    });

    test('equality takes the workflow status into account', () {
      final pending = buildCredit();
      final disbursed = buildCredit(
        workflowStatus: CreditWorkflowStatus.disbursed,
      );

      expect(pending, isNot(equals(disbursed)));
      expect(pending, equals(buildCredit()));
    });
  });

  group('Credit - Payment Block on Undisbursed Credits (Story 4.1, PRD FR-19)', () {
    test('a pending-disbursement credit is not actionable', () {
      final credit = buildCredit(
        status: CreditStatus.active,
        workflowStatus: CreditWorkflowStatus.pendingDisbursement,
      );

      expect(credit.isActionable, isFalse);
    });

    test('a disbursed active credit is actionable', () {
      final credit = buildCredit(
        status: CreditStatus.active,
        workflowStatus: CreditWorkflowStatus.disbursed,
      );

      expect(credit.isActionable, isTrue);
    });

    test('a disbursed overdue credit is still actionable', () {
      final credit = buildCredit(
        status: CreditStatus.overdue,
        workflowStatus: CreditWorkflowStatus.disbursed,
      );

      expect(credit.isActionable, isTrue);
    });

    test('assertPaymentsAllowed blocks payments on undisbursed credits', () {
      final credit = buildCredit(
        status: CreditStatus.active,
        workflowStatus: CreditWorkflowStatus.pendingDisbursement,
      );

      expect(
        credit.assertPaymentsAllowed,
        throwsA(
          isA<CreditPaymentBlockedException>().having(
            (e) => e.message,
            'message',
            'Payments cannot be accepted on undisbursed credits.',
          ),
        ),
      );
    });

    test('assertPaymentsAllowed permits payments once cash is disbursed', () {
      final credit = buildCredit(
        status: CreditStatus.active,
        workflowStatus: CreditWorkflowStatus.disbursed,
      );

      expect(credit.assertPaymentsAllowed, returnsNormally);
    });
  });

  group('Credit - Cross-Field Invariants (U-5, release-mode)', () {
    test('rejects negative principalCents', () {
      expect(
        () => buildCredit(principalCents: -1),
        throwsA(isA<CreditValidationException>()),
      );
    });

    test('rejects negative balanceCents', () {
      expect(
        () => buildCredit(balanceCents: -1),
        throwsA(isA<CreditValidationException>()),
      );
    });

    test('rejects balanceCents exceeding principalCents', () {
      expect(
        () => buildCredit(principalCents: 100, balanceCents: 200),
        throwsA(isA<CreditValidationException>()),
      );
    });

    test('rejects settled credit without settledAt', () {
      expect(
        () => buildCredit(
          status: CreditStatus.settled,
          workflowStatus: CreditWorkflowStatus.disbursed,
        ),
        throwsA(isA<CreditValidationException>()),
      );
    });

    test('rejects cancelled credit without cancelledAt', () {
      expect(
        () => Credit(
          id: 'credit-1',
          shopId: 'shop-1',
          customerId: 1,
          principalCents: 500000,
          balanceCents: 500000,
          status: CreditStatus.cancelled,
          workflowStatus: CreditWorkflowStatus.cancelled,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
          cancellationReason: 'test reason',
        ),
        throwsA(isA<CreditValidationException>()),
      );
    });

    test('rejects cancelled credit without reason', () {
      expect(
        () => Credit(
          id: 'credit-1',
          shopId: 'shop-1',
          customerId: 1,
          principalCents: 500000,
          balanceCents: 500000,
          status: CreditStatus.cancelled,
          workflowStatus: CreditWorkflowStatus.cancelled,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
          cancelledAt: now,
        ),
        throwsA(isA<CreditValidationException>()),
      );
    });

    test('rejects credit with both termPresetDays and customDueDate', () {
      expect(
        () => Credit(
          id: 'credit-1',
          shopId: 'shop-1',
          customerId: 1,
          principalCents: 500000,
          balanceCents: 500000,
          status: CreditStatus.active,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
          termPresetDays: 30,
          customDueDate: now.add(const Duration(days: 60)),
        ),
        throwsA(isA<CreditValidationException>()),
      );
    });

    test('rejects cancelled credit with non-cancelled workflow', () {
      expect(
        () => Credit(
          id: 'credit-1',
          shopId: 'shop-1',
          customerId: 1,
          principalCents: 500000,
          balanceCents: 500000,
          status: CreditStatus.cancelled,
          workflowStatus: CreditWorkflowStatus.disbursed,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
          cancelledAt: now,
          cancellationReason: 'test reason',
        ),
        throwsA(isA<CreditValidationException>()),
      );
    });

    test('rejects cancelled credit with disbursedAt set', () {
      expect(
        () => Credit(
          id: 'credit-1',
          shopId: 'shop-1',
          customerId: 1,
          principalCents: 500000,
          balanceCents: 500000,
          status: CreditStatus.cancelled,
          workflowStatus: CreditWorkflowStatus.cancelled,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
          cancelledAt: now,
          cancellationReason: 'test reason',
          disbursedAt: now,
        ),
        throwsA(isA<CreditValidationException>()),
      );
    });

    test('rejects termPresetDays outside 30/60/90', () {
      expect(
        () => Credit(
          id: 'credit-1',
          shopId: 'shop-1',
          customerId: 1,
          principalCents: 500000,
          balanceCents: 500000,
          status: CreditStatus.active,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
          termPresetDays: 45,
        ),
        throwsA(isA<CreditValidationException>()),
      );
    });

    test('rejects settled credit with non-disbursed workflow', () {
      expect(
        () => Credit(
          id: 'credit-1',
          shopId: 'shop-1',
          customerId: 1,
          principalCents: 500000,
          balanceCents: 0,
          status: CreditStatus.settled,
          workflowStatus: CreditWorkflowStatus.pendingDisbursement,
          dueDate: now.add(const Duration(days: 30)),
          createdAt: now,
          settledAt: now,
        ),
        throwsA(isA<CreditValidationException>()),
      );
    });

    test('copyWith producing invalid combination throws', () {
      final credit = buildCredit(
        status: CreditStatus.active,
        workflowStatus: CreditWorkflowStatus.disbursed,
      );
      expect(
        () => credit.copyWith(status: CreditStatus.cancelled),
        throwsA(isA<CreditValidationException>()),
      );
    });

    test('valid credit construction does not throw', () {
      expect(() => buildCredit(), returnsNormally);
    });
  });
}

