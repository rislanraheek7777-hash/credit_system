import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_custody_event.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';

void main() {
  group('CollateralCustodyEvent domain model', () {
    test('constructor records and validates a custody transition event', () {
      final now = DateTime.now().toUtc();
      final event = CollateralCustodyEvent(
        id: 'evt-1',
        shopId: 'shop-1',
        collateralItemId: 'coll-1',
        reportedByUserId: 'user-1',
        previousStatus: CollateralCustodyStatus.inCustody,
        newStatus: CollateralCustodyStatus.handoverRequested,
        reason: 'Customer requested return of pledged item',
        createdAt: now,
      );

      expect(event.id, equals('evt-1'));
      expect(event.shopId, equals('shop-1'));
      expect(event.collateralItemId, equals('coll-1'));
      expect(event.reportedByUserId, equals('user-1'));
      expect(event.previousStatus, equals(CollateralCustodyStatus.inCustody));
      expect(event.newStatus, equals(CollateralCustodyStatus.handoverRequested));
      expect(event.reason, equals('Customer requested return of pledged item'));
      expect(event.createdAt, equals(now));
    });

    test('constructor rejects empty required fields', () {
      expect(
        () => CollateralCustodyEvent(
          id: '',
          shopId: 'shop-1',
          collateralItemId: 'coll-1',
          reportedByUserId: 'user-1',
          previousStatus: CollateralCustodyStatus.inCustody,
          newStatus: CollateralCustodyStatus.handoverRequested,
          reason: 'some reason',
        ),
        throwsArgumentError,
      );
      expect(
        () => CollateralCustodyEvent(
          id: 'evt-1',
          shopId: 'shop-1',
          collateralItemId: 'coll-1',
          reportedByUserId: 'user-1',
          previousStatus: CollateralCustodyStatus.inCustody,
          newStatus: CollateralCustodyStatus.handoverRequested,
          reason: '',
        ),
        throwsArgumentError,
      );
    });

    test('copyWith preserves unchanged fields', () {
      final original = CollateralCustodyEvent(
        id: 'evt-1',
        shopId: 'shop-1',
        collateralItemId: 'coll-1',
        reportedByUserId: 'user-1',
        previousStatus: CollateralCustodyStatus.inCustody,
        newStatus: CollateralCustodyStatus.handoverRequested,
        reason: 'original reason',
      );
      final copy = original.copyWith(reason: 'updated reason');
      expect(copy.id, equals(original.id));
      expect(copy.newStatus, equals(original.newStatus));
      expect(copy.reason, equals('updated reason'));
      expect(copy, isNot(original));
    });
  });

  group('CollateralDiscrepancy domain model', () {
    test('constructor records a pending discrepancy and validates decision constraints', () {
      final now = DateTime.now().toUtc();
      final discrepancy = CollateralDiscrepancy(
        id: 'disc-1',
        shopId: 'shop-1',
        collateralItemId: 'coll-1',
        reportedByUserId: 'user-1',
        discrepancyReason:
            'System shows item in custody but physical item is missing',
        createdAt: now,
        updatedAt: now,
      );

      expect(discrepancy.status, equals(CollateralDiscrepancyStatus.pending));
      expect(discrepancy.resolvedByUserId, isNull);
      expect(discrepancy.resolvedAt, isNull);

      // A resolved discrepancy requires reviewer, notes, and timestamp
      expect(
        () => CollateralDiscrepancy(
          id: 'disc-2',
          shopId: 'shop-1',
          collateralItemId: 'coll-1',
          reportedByUserId: 'user-1',
          discrepancyReason: 'reason',
          status: CollateralDiscrepancyStatus.resolved,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );
    });

    test('transitionStatus moves pending → resolved only', () {
      final discrepancy = CollateralDiscrepancy(
        id: 'disc-1',
        shopId: 'shop-1',
        collateralItemId: 'coll-1',
        reportedByUserId: 'user-1',
        discrepancyReason: 'reason',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      expect(
        () => discrepancy.transitionStatus(CollateralDiscrepancyStatus.pending),
        throwsA(isA<CollateralDiscrepancyTransitionException>()),
      );

      final resolved = discrepancy.transitionStatus(CollateralDiscrepancyStatus.resolved);
      expect(resolved.status, equals(CollateralDiscrepancyStatus.resolved));
      expect(resolved.id, equals(discrepancy.id));
      expect(resolved.reportedByUserId, equals(discrepancy.reportedByUserId));
    });

    test('copyWith records the Shop Owner decision fields', () {
      final now = DateTime.now().toUtc();
      final pending = CollateralDiscrepancy(
        id: 'disc-1',
        shopId: 'shop-1',
        collateralItemId: 'coll-1',
        reportedByUserId: 'user-1',
        discrepancyReason: 'missing item',
        createdAt: now,
        updatedAt: now,
      );

      final resolved = pending.copyWith(
        status: CollateralDiscrepancyStatus.resolved,
        resolvedByUserId: 'owner-1',
        resolutionNotes: 'Item located in back room; returned to custody',
        resolvedAt: now,
        updatedAt: now,
      );
      expect(resolved.status, equals(CollateralDiscrepancyStatus.resolved));
      expect(resolved.resolvedByUserId, equals('owner-1'));
      expect(resolved.resolutionNotes, contains('back room'));
      expect(resolved.resolvedAt, equals(now));
      // Original record is preserved unchanged
      expect(pending.status, equals(CollateralDiscrepancyStatus.pending));
      expect(pending.resolvedByUserId, isNull);
    });
  });
}
