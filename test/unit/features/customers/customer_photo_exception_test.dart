import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/features/customers/domain/models/customer.dart';
import 'package:credit_system/features/customers/domain/models/customer_photo_exception.dart';

void main() {
  group('CustomerPhotoException Domain Model Tests (Story 2.3)', () {
    test('creates valid pending photo exception with normalized NIC', () {
      final now = DateTime.now().toUtc();
      final exception = CustomerPhotoException(
        id: 'exc-uuid-1',
        shopId: 'shop-uuid-1',
        targetCustomerId: 'cust-uuid-1',
        customerNic: ' 199012345678 ',
        requestedByUserId: 'user-staff-1',
        requestReason: 'Camera hardware malfunction; physical card manually checked.',
        createdAt: now,
        updatedAt: now,
      );

      expect(exception.id, equals('exc-uuid-1'));
      expect(exception.shopId, equals('shop-uuid-1'));
      expect(exception.targetCustomerId, equals('cust-uuid-1'));
      expect(exception.customerNic, equals('199012345678')); // normalized
      expect(exception.requestedByUserId, equals('user-staff-1'));
      expect(exception.requestReason, equals('Camera hardware malfunction; physical card manually checked.'));
      expect(exception.status, equals(PhotoExceptionStatus.pendingOwnerApproval));
      expect(exception.reviewedByUserId, isNull);
      expect(exception.reviewNotes, isNull);
      expect(exception.reviewedAt, isNull);
    });

    test('validates approved exception requires reviewerId, reviewNotes, and reviewedAt', () {
      final now = DateTime.now().toUtc();

      // Missing reviewerId
      expect(
        () => CustomerPhotoException(
          id: 'exc-uuid-2',
          shopId: 'shop-uuid-1',
          targetCustomerId: 'cust-uuid-2',
          customerNic: '901234567V',
          requestedByUserId: 'user-staff-1',
          requestReason: 'Hardware failure',
          status: PhotoExceptionStatus.approved,
          reviewedByUserId: null,
          reviewNotes: 'Approved by owner',
          reviewedAt: now,
        ),
        throwsA(isA<CustomerValidationException>()),
      );

      // Missing reviewNotes
      expect(
        () => CustomerPhotoException(
          id: 'exc-uuid-3',
          shopId: 'shop-uuid-1',
          targetCustomerId: 'cust-uuid-2',
          customerNic: '901234567V',
          requestedByUserId: 'user-staff-1',
          requestReason: 'Hardware failure',
          status: PhotoExceptionStatus.approved,
          reviewedByUserId: 'owner-id',
          reviewNotes: '   ',
          reviewedAt: now,
        ),
        throwsA(isA<CustomerValidationException>()),
      );

      // Missing reviewedAt
      expect(
        () => CustomerPhotoException(
          id: 'exc-uuid-4',
          shopId: 'shop-uuid-1',
          targetCustomerId: 'cust-uuid-2',
          customerNic: '901234567V',
          requestedByUserId: 'user-staff-1',
          requestReason: 'Hardware failure',
          status: PhotoExceptionStatus.approved,
          reviewedByUserId: 'owner-id',
          reviewNotes: 'Approved by owner',
          reviewedAt: null,
        ),
        throwsA(isA<CustomerValidationException>()),
      );

      // Complete approved exception succeeds
      final approved = CustomerPhotoException(
        id: 'exc-uuid-5',
        shopId: 'shop-uuid-1',
        targetCustomerId: 'cust-uuid-2',
        customerNic: '901234567V',
        requestedByUserId: 'user-staff-1',
        requestReason: 'Hardware failure',
        status: PhotoExceptionStatus.approved,
        reviewedByUserId: 'owner-id',
        reviewNotes: 'Approved by owner after inspecting physical NIC',
        reviewedAt: now,
      );
      expect(approved.status, equals(PhotoExceptionStatus.approved));
      expect(approved.reviewedByUserId, equals('owner-id'));
    });

    test('validates rejected exception requires non-empty review notes', () {
      final now = DateTime.now().toUtc();
      expect(
        () => CustomerPhotoException(
          id: 'exc-uuid-6',
          shopId: 'shop-uuid-1',
          targetCustomerId: 'cust-uuid-2',
          customerNic: '901234567V',
          requestedByUserId: 'user-staff-1',
          requestReason: 'Hardware failure',
          status: PhotoExceptionStatus.rejected,
          reviewedByUserId: 'owner-id',
          reviewNotes: '',
          reviewedAt: now,
        ),
        throwsA(isA<CustomerValidationException>()),
      );
    });

    test('rejects empty request justification reason', () {
      expect(
        () => CustomerPhotoException(
          id: 'exc-uuid-7',
          shopId: 'shop-uuid-1',
          targetCustomerId: 'cust-uuid-1',
          customerNic: '901234567V',
          requestedByUserId: 'user-staff-1',
          requestReason: '   ',
        ),
        throwsA(isA<CustomerValidationException>()),
      );
    });

    test('rejects invalid NIC format', () {
      expect(
        () => CustomerPhotoException(
          id: 'exc-uuid-8',
          shopId: 'shop-uuid-1',
          targetCustomerId: 'cust-uuid-1',
          customerNic: 'INVALID-NIC',
          requestedByUserId: 'user-staff-1',
          requestReason: 'Hardware error',
        ),
        throwsA(isA<CustomerValidationException>()),
      );
    });

    test('copyWith updates fields while maintaining immutability', () {
      final now = DateTime.now().toUtc();
      final exception = CustomerPhotoException(
        id: 'exc-uuid-9',
        shopId: 'shop-uuid-1',
        targetCustomerId: 'cust-uuid-1',
        customerNic: '901234567V',
        requestedByUserId: 'user-staff-1',
        requestReason: 'Camera hardware malfunction',
        createdAt: now,
        updatedAt: now,
      );

      final decisionTime = now.add(const Duration(minutes: 5));
      final approved = exception.copyWith(
        status: PhotoExceptionStatus.approved,
        reviewedByUserId: 'owner-uuid-1',
        reviewNotes: 'Verified via physical document',
        reviewedAt: decisionTime,
        updatedAt: decisionTime,
      );

      expect(approved.id, equals(exception.id));
      expect(approved.status, equals(PhotoExceptionStatus.approved));
      expect(approved.reviewedByUserId, equals('owner-uuid-1'));
      expect(approved.reviewNotes, equals('Verified via physical document'));
      expect(approved.reviewedAt, equals(decisionTime));
    });
  });
}
