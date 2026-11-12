import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_photo_exception.dart';

void main() {
  group('CollateralPhotoException Domain Model & Status Transitions', () {
    test('CollateralPhotoException constructor normalizes and validates', () {
      final now = DateTime.now().toUtc();
      final exception = CollateralPhotoException(
        id: 'exc-1',
        shopId: 'shop-1',
        collateralItemId: 'coll-1',
        requestedByUserId: 'staff-1',
        requestReason: 'Camera hardware failure',
        status: CollateralPhotoExceptionStatus.pendingOwnerApproval,
        createdAt: now,
        updatedAt: now,
      );

      expect(exception.id, equals('exc-1'));
      expect(exception.shopId, equals('shop-1'));
      expect(exception.collateralItemId, equals('coll-1'));
      expect(exception.requestedByUserId, equals('staff-1'));
      expect(exception.requestReason, equals('Camera hardware failure'));
      expect(exception.status,
          equals(CollateralPhotoExceptionStatus.pendingOwnerApproval));
      expect(exception.photoExceptionStatusValue,
          equals('pending_owner_approval'));
      expect(exception.reviewedByUserId, isNull);
      expect(exception.reviewNotes, isNull);
      expect(exception.reviewedAt, isNull);
    });

    test('CollateralPhotoException constructor throws on invalid parameters', () {
      final now = DateTime.now().toUtc();

      // Empty ID
      expect(
        () => CollateralPhotoException(
          id: '',
          shopId: 'shop-1',
          collateralItemId: 'coll-1',
          requestedByUserId: 'staff-1',
          requestReason: 'Reason',
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      // Empty shopId
      expect(
        () => CollateralPhotoException(
          id: 'exc-1',
          shopId: '   ',
          collateralItemId: 'coll-1',
          requestedByUserId: 'staff-1',
          requestReason: 'Reason',
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      // Empty collateralItemId
      expect(
        () => CollateralPhotoException(
          id: 'exc-1',
          shopId: 'shop-1',
          collateralItemId: '',
          requestedByUserId: 'staff-1',
          requestReason: 'Reason',
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      // Empty requester ID
      expect(
        () => CollateralPhotoException(
          id: 'exc-1',
          shopId: 'shop-1',
          collateralItemId: 'coll-1',
          requestedByUserId: '',
          requestReason: 'Reason',
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      // Empty reason
      expect(
        () => CollateralPhotoException(
          id: 'exc-1',
          shopId: 'shop-1',
          collateralItemId: 'coll-1',
          requestedByUserId: 'staff-1',
          requestReason: '   ',
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );
    });

    test('CollateralPhotoException approved status requires reviewer and notes', () {
      final now = DateTime.now().toUtc();

      // Approved without reviewedByUserId
      expect(
        () => CollateralPhotoException(
          id: 'exc-1',
          shopId: 'shop-1',
          collateralItemId: 'coll-1',
          requestedByUserId: 'staff-1',
          requestReason: 'Reason',
          status: CollateralPhotoExceptionStatus.approved,
          reviewedByUserId: null,
          reviewNotes: 'Approved',
          reviewedAt: now,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      // Approved without reviewNotes
      expect(
        () => CollateralPhotoException(
          id: 'exc-1',
          shopId: 'shop-1',
          collateralItemId: 'coll-1',
          requestedByUserId: 'staff-1',
          requestReason: 'Reason',
          status: CollateralPhotoExceptionStatus.approved,
          reviewedByUserId: 'owner-1',
          reviewNotes: null,
          reviewedAt: now,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      // Approved without reviewedAt
      expect(
        () => CollateralPhotoException(
          id: 'exc-1',
          shopId: 'shop-1',
          collateralItemId: 'coll-1',
          requestedByUserId: 'staff-1',
          requestReason: 'Reason',
          status: CollateralPhotoExceptionStatus.approved,
          reviewedByUserId: 'owner-1',
          reviewNotes: 'Approved',
          reviewedAt: null,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );
    });

    test('CollateralPhotoException.copyWith returns updated instance', () {
      final now = DateTime.now().toUtc();
      final original = CollateralPhotoException(
        id: 'exc-2',
        shopId: 'shop-1',
        collateralItemId: 'coll-2',
        requestedByUserId: 'staff-1',
        requestReason: 'Original reason',
        status: CollateralPhotoExceptionStatus.pendingOwnerApproval,
        createdAt: now,
        updatedAt: now,
      );

      final updated = original.copyWith(
        status: CollateralPhotoExceptionStatus.approved,
        reviewedByUserId: 'owner-1',
        reviewNotes: 'Approved by owner',
        reviewedAt: now,
      );

      expect(updated.id, equals(original.id));
      expect(updated.status, equals(CollateralPhotoExceptionStatus.approved));
      expect(updated.reviewedByUserId, equals('owner-1'));
      expect(updated.reviewNotes, equals('Approved by owner'));
      expect(updated.requestReason, equals(original.requestReason));
    });

    test('CollateralPhotoException equality and hashCode', () {
      final now = DateTime.now().toUtc();
      final e1 = CollateralPhotoException(
        id: 'exc-3',
        shopId: 'shop-1',
        collateralItemId: 'coll-3',
        requestedByUserId: 'staff-1',
        requestReason: 'Camera failure',
        status: CollateralPhotoExceptionStatus.pendingOwnerApproval,
        createdAt: now,
        updatedAt: now,
      );
      final e2 = CollateralPhotoException(
        id: 'exc-3',
        shopId: 'shop-1',
        collateralItemId: 'coll-3',
        requestedByUserId: 'staff-1',
        requestReason: 'Camera failure',
        status: CollateralPhotoExceptionStatus.pendingOwnerApproval,
        createdAt: now,
        updatedAt: now,
      );
      final e3 = CollateralPhotoException(
        id: 'exc-4',
        shopId: 'shop-1',
        collateralItemId: 'coll-3',
        requestedByUserId: 'staff-1',
        requestReason: 'Camera failure',
        status: CollateralPhotoExceptionStatus.pendingOwnerApproval,
        createdAt: now,
        updatedAt: now,
      );

      expect(e1, equals(e2));
      expect(e1.hashCode, equals(e2.hashCode));
      expect(e1, isNot(equals(e3)));
    });
  });

  group('CollateralPhotoExceptionStatus transitions', () {
    test('isValidTransition allows pendingOwnerApproval → approved', () {
      expect(
        CollateralPhotoExceptionStatus.isValidTransition(
          CollateralPhotoExceptionStatus.pendingOwnerApproval,
          CollateralPhotoExceptionStatus.approved,
        ),
        isTrue,
      );
    });

    test('isValidTransition allows pendingOwnerApproval → rejected', () {
      expect(
        CollateralPhotoExceptionStatus.isValidTransition(
          CollateralPhotoExceptionStatus.pendingOwnerApproval,
          CollateralPhotoExceptionStatus.rejected,
        ),
        isTrue,
      );
    });

    test('isValidTransition allows approved → consumed', () {
      expect(
        CollateralPhotoExceptionStatus.isValidTransition(
          CollateralPhotoExceptionStatus.approved,
          CollateralPhotoExceptionStatus.consumed,
        ),
        isTrue,
      );
    });

    test('isValidTransition rejects pendingOwnerApproval → pendingOwnerApproval', () {
      expect(
        CollateralPhotoExceptionStatus.isValidTransition(
          CollateralPhotoExceptionStatus.pendingOwnerApproval,
          CollateralPhotoExceptionStatus.pendingOwnerApproval,
        ),
        isFalse,
      );
    });

    test('isValidTransition rejects rejected → approved (terminal)', () {
      expect(
        CollateralPhotoExceptionStatus.isValidTransition(
          CollateralPhotoExceptionStatus.rejected,
          CollateralPhotoExceptionStatus.approved,
        ),
        isFalse,
      );
    });

    test('isValidTransition rejects consumed → rejected (terminal)', () {
      expect(
        CollateralPhotoExceptionStatus.isValidTransition(
          CollateralPhotoExceptionStatus.consumed,
          CollateralPhotoExceptionStatus.rejected,
        ),
        isFalse,
      );
    });

    test('isTerminal returns true for rejected and consumed', () {
      expect(CollateralPhotoExceptionStatus.rejected.isTerminal, isTrue);
      expect(CollateralPhotoExceptionStatus.consumed.isTerminal, isTrue);
      expect(
        CollateralPhotoExceptionStatus.pendingOwnerApproval.isTerminal,
        isFalse,
      );
      expect(CollateralPhotoExceptionStatus.approved.isTerminal, isFalse);
    });

    test('transitionStatus performs valid transition', () {
      final exception = CollateralPhotoException(
        id: 'exc-5',
        shopId: 'shop-1',
        collateralItemId: 'coll-5',
        requestedByUserId: 'staff-1',
        requestReason: 'Camera failure',
        status: CollateralPhotoExceptionStatus.pendingOwnerApproval,
      );

      expect(
        exception.status,
        equals(CollateralPhotoExceptionStatus.pendingOwnerApproval),
      );

      final approved = exception.transitionStatus(
        CollateralPhotoExceptionStatus.approved,
      );
      expect(approved.status, equals(CollateralPhotoExceptionStatus.approved));
      expect(approved.updatedAt.compareTo(exception.updatedAt) >= 0, isTrue);
    });

    test('transitionStatus throws on invalid transition', () {
      final exception = CollateralPhotoException(
        id: 'exc-6',
        shopId: 'shop-1',
        collateralItemId: 'coll-6',
        requestedByUserId: 'staff-1',
        requestReason: 'Camera failure',
        status: CollateralPhotoExceptionStatus.pendingOwnerApproval,
      );

      // pending → consumed is invalid (must go through approved first)
      expect(
        () => exception.transitionStatus(
          CollateralPhotoExceptionStatus.consumed,
        ),
        throwsA(isA<CollateralPhotoExceptionTransitionException>()),
      );
    });
  });

  group('CollateralPhotoExceptionStatus fromValue', () {
    test('resolves valid statuses', () {
      expect(
        CollateralPhotoExceptionStatus.fromValue(
          'pending_owner_approval',
        ),
        equals(CollateralPhotoExceptionStatus.pendingOwnerApproval),
      );
      expect(
        CollateralPhotoExceptionStatus.fromValue('approved'),
        equals(CollateralPhotoExceptionStatus.approved),
      );
      expect(
        CollateralPhotoExceptionStatus.fromValue('rejected'),
        equals(CollateralPhotoExceptionStatus.rejected),
      );
      expect(
        CollateralPhotoExceptionStatus.fromValue('consumed'),
        equals(CollateralPhotoExceptionStatus.consumed),
      );
    });

    test('throws on invalid status', () {
      expect(
        () => CollateralPhotoExceptionStatus.fromValue('unknown'),
        throwsArgumentError,
      );
    });
  });
}

/// Convenience getter for testing the status value as a string.
extension CollateralPhotoExceptionStatusTesting on CollateralPhotoException {
  String get photoExceptionStatusValue => status.value;
}

