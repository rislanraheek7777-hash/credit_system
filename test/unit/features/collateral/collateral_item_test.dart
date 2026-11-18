import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';

void main() {
  group('CollateralItem Domain Model & Weight Precision', () {
    test('CollateralItem constructor normalizes and validates', () {
      final now = DateTime.now().toUtc();
      final item = CollateralItem(
        id: 'coll-1',
        shopId: 'shop-1',
        customerId: 1,
        itemReferenceId: 'COLL-001',
        category: CollateralItemCategory.gold,
        description: '22K gold necklace',
        conditionGrade: 'Like New',
        weightMilligrams: 5500,
        estimatedValueCents: 1500000,
        createdAt: now,
        updatedAt: now,
      );

      expect(item.id, equals('coll-1'));
      expect(item.shopId, equals('shop-1'));
      expect(item.customerId, equals(1));
      expect(item.itemReferenceId, equals('COLL-001'));
      expect(item.category, equals(CollateralItemCategory.gold));
      expect(item.description, equals('22K gold necklace'));
      expect(item.conditionGrade, equals('Like New'));
      expect(item.weightMilligrams, equals(5500));
      expect(item.estimatedValueCents, equals(1500000));
      expect(item.custodyStatus, equals(CollateralCustodyStatus.inCustody));
      expect(item.photoUri, isNull);
      expect(item.photoHash, isNull);
      expect(item.creditId, isNull);
    });

    test('CollateralItem.estimatedValue returns Money with correct cents', () {
      final item = CollateralItem(
        id: 'coll-2',
        shopId: 'shop-1',
        customerId: 1,
        itemReferenceId: 'COLL-002',
        category: CollateralItemCategory.electronics,
        description: 'Samsung smartphone',
        conditionGrade: 'Good',
        weightMilligrams: 180000,
        estimatedValueCents: 450000,
      );

      final money = item.estimatedValue;
      expect(money, isA<Money>());
      expect(money.minorUnits, equals(450000));
      expect(money.format(), equals('Rs. 4,500.00'));
    });

    test('CollateralItem.parseWeightGrams converts decimal grams to milligrams', () {
      expect(CollateralItem.parseWeightGrams('5.5'), equals(5500));
      expect(CollateralItem.parseWeightGrams('5.500'), equals(5500));
      expect(CollateralItem.parseWeightGrams('5.555'), equals(5555));
      expect(CollateralItem.parseWeightGrams('10'), equals(10000));
      expect(CollateralItem.parseWeightGrams('0.001'), equals(1));
      expect(CollateralItem.parseWeightGrams('100.000'), equals(100000));
    });

    test('CollateralItem.parseWeightGrams rejects invalid input', () {
      expect(() => CollateralItem.parseWeightGrams(''),
          throwsA(isA<CollateralItemValidationException>()));
      expect(() => CollateralItem.parseWeightGrams('   '),
          throwsA(isA<CollateralItemValidationException>()));
      expect(() => CollateralItem.parseWeightGrams('-5.5'),
          throwsA(isA<CollateralItemValidationException>()));
      expect(() => CollateralItem.parseWeightGrams('abc'),
          throwsA(isA<CollateralItemValidationException>()));
      expect(() => CollateralItem.parseWeightGrams('5.5555'),
          throwsA(isA<CollateralItemValidationException>()));
      expect(() => CollateralItem.parseWeightGrams('5..5'),
          throwsA(isA<CollateralItemValidationException>()));
      expect(() => CollateralItem.parseWeightGrams('0'),
          throwsA(isA<CollateralItemValidationException>()));
    });

    test('CollateralItem.formatWeightMilligrams formats milligrams to grams', () {
      expect(CollateralItem.formatWeightMilligrams(5500), equals('5.500 g'));
      expect(CollateralItem.formatWeightMilligrams(10000), equals('10.000 g'));
      expect(CollateralItem.formatWeightMilligrams(1), equals('0.001 g'));
    });

    test('CollateralItem constructor throws on invalid parameters', () {
      final now = DateTime.now().toUtc();

      // Empty ID
      expect(
        () => CollateralItem(
          id: '',
          shopId: 'shop-1',
          customerId: 1,
          itemReferenceId: 'COLL-001',
          category: CollateralItemCategory.gold,
          description: 'Test',
          conditionGrade: 'Good',
          weightMilligrams: 1000,
          estimatedValueCents: 50000,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      // Empty shopId
      expect(
        () => CollateralItem(
          id: 'coll-1',
          shopId: '   ',
          customerId: 1,
          itemReferenceId: 'COLL-001',
          category: CollateralItemCategory.gold,
          description: 'Test',
          conditionGrade: 'Good',
          weightMilligrams: 1000,
          estimatedValueCents: 50000,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      // Empty customerId is no longer representable; a non-positive id is invalid
      expect(
        () => CollateralItem(
          id: 'coll-1',
          shopId: 'shop-1',
          customerId: 0,
          itemReferenceId: 'COLL-001',
          category: CollateralItemCategory.gold,
          description: 'Test',
          conditionGrade: 'Good',
          weightMilligrams: 1000,
          estimatedValueCents: 50000,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      // Zero weight
      expect(
        () => CollateralItem(
          id: 'coll-1',
          shopId: 'shop-1',
          customerId: 1,
          itemReferenceId: 'COLL-001',
          category: CollateralItemCategory.gold,
          description: 'Test',
          conditionGrade: 'Good',
          weightMilligrams: 0,
          estimatedValueCents: 50000,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      // Negative weight
      expect(
        () => CollateralItem(
          id: 'coll-1',
          shopId: 'shop-1',
          customerId: 1,
          itemReferenceId: 'COLL-001',
          category: CollateralItemCategory.gold,
          description: 'Test',
          conditionGrade: 'Good',
          weightMilligrams: -500,
          estimatedValueCents: 50000,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      // Negative estimated value
      expect(
        () => CollateralItem(
          id: 'coll-1',
          shopId: 'shop-1',
          customerId: 1,
          itemReferenceId: 'COLL-001',
          category: CollateralItemCategory.gold,
          description: 'Test',
          conditionGrade: 'Good',
          weightMilligrams: 1000,
          estimatedValueCents: -100,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      // Empty description
      expect(
        () => CollateralItem(
          id: 'coll-1',
          shopId: 'shop-1',
          customerId: 1,
          itemReferenceId: 'COLL-001',
          category: CollateralItemCategory.gold,
          description: '   ',
          conditionGrade: 'Good',
          weightMilligrams: 1000,
          estimatedValueCents: 50000,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      // Empty item reference ID
      expect(
        () => CollateralItem(
          id: 'coll-1',
          shopId: 'shop-1',
          customerId: 1,
          itemReferenceId: '',
          category: CollateralItemCategory.gold,
          description: 'Test',
          conditionGrade: 'Good',
          weightMilligrams: 1000,
          estimatedValueCents: 50000,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );
    });

    test('CollateralItem.copyWith returns updated instance', () {
      final now = DateTime.now().toUtc();
      final original = CollateralItem(
        id: 'coll-3',
        shopId: 'shop-1',
        customerId: 1,
        itemReferenceId: 'COLL-003',
        category: CollateralItemCategory.valuables,
        description: 'Diamond ring',
        conditionGrade: 'Excellent',
        weightMilligrams: 2000,
        estimatedValueCents: 2500000,
        createdAt: now,
        updatedAt: now,
      );

      final updated = original.copyWith(
        description: 'Sapphire ring',
        weightMilligrams: 2500,
        custodyStatus: CollateralCustodyStatus.returned,
      );

      expect(updated.id, equals(original.id));
      expect(updated.description, equals('Sapphire ring'));
      expect(updated.weightMilligrams, equals(2500));
      expect(updated.custodyStatus, equals(CollateralCustodyStatus.returned));
      expect(updated.category, equals(original.category));
      expect(updated.estimatedValueCents, equals(original.estimatedValueCents));
    });

    test('CollateralItem equality and hashCode', () {
      final now = DateTime.now().toUtc();
      final c1 = CollateralItem(
        id: 'coll-4',
        shopId: 'shop-1',
        customerId: 1,
        itemReferenceId: 'COLL-004',
        category: CollateralItemCategory.gold,
        description: 'Gold bar',
        conditionGrade: 'Like New',
        weightMilligrams: 10000,
        estimatedValueCents: 5000000,
        createdAt: now,
        updatedAt: now,
      );
      final c2 = CollateralItem(
        id: 'coll-4',
        shopId: 'shop-1',
        customerId: 1,
        itemReferenceId: 'COLL-004',
        category: CollateralItemCategory.gold,
        description: 'Gold bar',
        conditionGrade: 'Like New',
        weightMilligrams: 10000,
        estimatedValueCents: 5000000,
        createdAt: now,
        updatedAt: now,
      );
      final c3 = CollateralItem(
        id: 'coll-5',
        shopId: 'shop-1',
        customerId: 1,
        itemReferenceId: 'COLL-005',
        category: CollateralItemCategory.gold,
        description: 'Gold bar',
        conditionGrade: 'Like New',
        weightMilligrams: 10000,
        estimatedValueCents: 5000000,
        createdAt: now,
        updatedAt: now,
      );

      expect(c1, equals(c2));
      expect(c1.hashCode, equals(c2.hashCode));
      expect(c1, isNot(equals(c3)));
    });
  });

  group('CollateralCustodyStatus transitions (Story 3.4)', () {
    test('isValidTransition resolves all six custody states', () {
      expect(CollateralCustodyStatus.fromValue('in_custody'),
          equals(CollateralCustodyStatus.inCustody));
      expect(CollateralCustodyStatus.fromValue('handover_requested'),
          equals(CollateralCustodyStatus.handoverRequested));
      expect(CollateralCustodyStatus.fromValue('handover_reported'),
          equals(CollateralCustodyStatus.handoverReported));
      expect(CollateralCustodyStatus.fromValue('returned'),
          equals(CollateralCustodyStatus.returned));
      expect(CollateralCustodyStatus.fromValue('exception_held'),
          equals(CollateralCustodyStatus.exceptionHeld));
      expect(CollateralCustodyStatus.fromValue('discrepancy'),
          equals(CollateralCustodyStatus.discrepancy));
    });

    test('isValidTransition allows the full handover flow', () {
      expect(
        CollateralCustodyStatus.isValidTransition(
          CollateralCustodyStatus.inCustody,
          CollateralCustodyStatus.handoverRequested,
        ),
        isTrue,
      );
      expect(
        CollateralCustodyStatus.isValidTransition(
          CollateralCustodyStatus.handoverRequested,
          CollateralCustodyStatus.handoverReported,
        ),
        isTrue,
      );
      expect(
        CollateralCustodyStatus.isValidTransition(
          CollateralCustodyStatus.handoverReported,
          CollateralCustodyStatus.returned,
        ),
        isTrue,
      );
    });

    test('isValidTransition allows cancellation and rejection paths', () {
      expect(
        CollateralCustodyStatus.isValidTransition(
          CollateralCustodyStatus.handoverRequested,
          CollateralCustodyStatus.inCustody,
        ),
        isTrue,
      );
      expect(
        CollateralCustodyStatus.isValidTransition(
          CollateralCustodyStatus.handoverReported,
          CollateralCustodyStatus.inCustody,
        ),
        isTrue,
      );
    });

    test('isValidTransition allows discrepancy reporting and resolution', () {
      expect(
        CollateralCustodyStatus.isValidTransition(
          CollateralCustodyStatus.inCustody,
          CollateralCustodyStatus.discrepancy,
        ),
        isTrue,
      );
      expect(
        CollateralCustodyStatus.isValidTransition(
          CollateralCustodyStatus.discrepancy,
          CollateralCustodyStatus.returned,
        ),
        isTrue,
      );
      expect(
        CollateralCustodyStatus.isValidTransition(
          CollateralCustodyStatus.discrepancy,
          CollateralCustodyStatus.inCustody,
        ),
        isTrue,
      );
      expect(
        CollateralCustodyStatus.isValidTransition(
          CollateralCustodyStatus.discrepancy,
          CollateralCustodyStatus.exceptionHeld,
        ),
        isTrue,
      );
    });

    test('isValidTransition rejects direct inCustody → returned (handover flow required)', () {
      expect(
        CollateralCustodyStatus.isValidTransition(
          CollateralCustodyStatus.inCustody,
          CollateralCustodyStatus.returned,
        ),
        isFalse,
      );
    });

    test('isValidTransition rejects inCustody → handoverReported (skip steps)', () {
      expect(
        CollateralCustodyStatus.isValidTransition(
          CollateralCustodyStatus.inCustody,
          CollateralCustodyStatus.handoverReported,
        ),
        isFalse,
      );
    });

    test('isValidTransition rejects transitions out of terminal states', () {
      expect(
        CollateralCustodyStatus.isValidTransition(
          CollateralCustodyStatus.returned,
          CollateralCustodyStatus.inCustody,
        ),
        isFalse,
      );
      expect(
        CollateralCustodyStatus.isValidTransition(
          CollateralCustodyStatus.returned,
          CollateralCustodyStatus.discrepancy,
        ),
        isFalse,
      );
      expect(
        CollateralCustodyStatus.isValidTransition(
          CollateralCustodyStatus.exceptionHeld,
          CollateralCustodyStatus.returned,
        ),
        isFalse,
      );
    });

    test('isTerminal returns true for returned and exceptionHeld only', () {
      expect(CollateralCustodyStatus.returned.isTerminal, isTrue);
      expect(CollateralCustodyStatus.exceptionHeld.isTerminal, isTrue);
      expect(CollateralCustodyStatus.inCustody.isTerminal, isFalse);
      expect(CollateralCustodyStatus.handoverRequested.isTerminal, isFalse);
      expect(CollateralCustodyStatus.handoverReported.isTerminal, isFalse);
      expect(CollateralCustodyStatus.discrepancy.isTerminal, isFalse);
    });

    test('transitionCustody performs valid handover flow transitions', () {
      final item = CollateralItem(
        id: 'coll-6',
        shopId: 'shop-1',
        customerId: 1,
        itemReferenceId: 'COLL-006',
        category: CollateralItemCategory.gold,
        description: 'Test item',
        conditionGrade: 'Good',
        weightMilligrams: 1000,
        estimatedValueCents: 100000,
      );

      expect(item.custodyStatus, equals(CollateralCustodyStatus.inCustody));

      final requested = item.transitionCustody(CollateralCustodyStatus.handoverRequested);
      expect(requested.custodyStatus, equals(CollateralCustodyStatus.handoverRequested));

      final reported = requested.transitionCustody(CollateralCustodyStatus.handoverReported);
      expect(reported.custodyStatus, equals(CollateralCustodyStatus.handoverReported));

      final returned = reported.transitionCustody(CollateralCustodyStatus.returned);
      expect(returned.custodyStatus, equals(CollateralCustodyStatus.returned));

      // updatedAt advances on each transition
      expect(returned.updatedAt.compareTo(item.updatedAt) >= 0, isTrue);
    });

    test('transitionCustody allows cancel and owner-reject paths', () {
      final requested = CollateralItem(
        id: 'coll-7',
        shopId: 'shop-1',
        customerId: 1,
        itemReferenceId: 'COLL-007',
        category: CollateralItemCategory.gold,
        description: 'Test item',
        conditionGrade: 'Good',
        weightMilligrams: 1000,
        estimatedValueCents: 100000,
        custodyStatus: CollateralCustodyStatus.handoverRequested,
      );
      expect(
        requested.transitionCustody(CollateralCustodyStatus.inCustody)
            .custodyStatus,
        equals(CollateralCustodyStatus.inCustody),
      );

      final reported = CollateralItem(
        id: 'coll-8',
        shopId: 'shop-1',
        customerId: 1,
        itemReferenceId: 'COLL-008',
        category: CollateralItemCategory.gold,
        description: 'Test item',
        conditionGrade: 'Good',
        weightMilligrams: 1000,
        estimatedValueCents: 100000,
        custodyStatus: CollateralCustodyStatus.handoverReported,
      );
      expect(
        reported.transitionCustody(CollateralCustodyStatus.inCustody)
            .custodyStatus,
        equals(CollateralCustodyStatus.inCustody),
      );
    });

    test('transitionCustody allows discrepancy resolution paths', () {
      final discrepancy = CollateralItem(
        id: 'coll-9',
        shopId: 'shop-1',
        customerId: 1,
        itemReferenceId: 'COLL-009',
        category: CollateralItemCategory.gold,
        description: 'Test item',
        conditionGrade: 'Good',
        weightMilligrams: 1000,
        estimatedValueCents: 100000,
        custodyStatus: CollateralCustodyStatus.discrepancy,
      );
      expect(
        discrepancy.transitionCustody(CollateralCustodyStatus.returned)
            .custodyStatus,
        equals(CollateralCustodyStatus.returned),
      );
      expect(
        discrepancy.transitionCustody(CollateralCustodyStatus.inCustody)
            .custodyStatus,
        equals(CollateralCustodyStatus.inCustody),
      );
      expect(
        discrepancy.transitionCustody(CollateralCustodyStatus.exceptionHeld)
            .custodyStatus,
        equals(CollateralCustodyStatus.exceptionHeld),
      );
    });

    test('transitionCustody throws on invalid transition', () {
      final item = CollateralItem(
        id: 'coll-10',
        shopId: 'shop-1',
        customerId: 1,
        itemReferenceId: 'COLL-010',
        category: CollateralItemCategory.gold,
        description: 'Test item',
        conditionGrade: 'Good',
        weightMilligrams: 1000,
        estimatedValueCents: 100000,
        custodyStatus: CollateralCustodyStatus.returned,
      );

      expect(
        () => item.transitionCustody(CollateralCustodyStatus.inCustody),
        throwsA(isA<CollateralCustodyTransitionException>()),
      );
      expect(
        () => item.transitionCustody(CollateralCustodyStatus.discrepancy),
        throwsA(isA<CollateralCustodyTransitionException>()),
      );
    });

    test('transitionCustody rejects direct inCustody → returned', () {
      final item = CollateralItem(
        id: 'coll-11',
        shopId: 'shop-1',
        customerId: 1,
        itemReferenceId: 'COLL-011',
        category: CollateralItemCategory.gold,
        description: 'Test item',
        conditionGrade: 'Good',
        weightMilligrams: 1000,
        estimatedValueCents: 100000,
      );
      expect(
        () => item.transitionCustody(CollateralCustodyStatus.returned),
        throwsA(isA<CollateralCustodyTransitionException>()),
      );
    });

    test('isValidTransition allows inCustody → exceptionHeld (owner exception hold)', () {
      expect(
        CollateralCustodyStatus.isValidTransition(
          CollateralCustodyStatus.inCustody,
          CollateralCustodyStatus.exceptionHeld,
        ),
        isTrue,
      );
    });

    test('isValidTransition allows handoverReported → exceptionHeld (owner exception hold)', () {
      expect(
        CollateralCustodyStatus.isValidTransition(
          CollateralCustodyStatus.handoverReported,
          CollateralCustodyStatus.exceptionHeld,
        ),
        isTrue,
      );
    });

    test('isValidTransition rejects handoverRequested → exceptionHeld (skip steps)', () {
      expect(
        CollateralCustodyStatus.isValidTransition(
          CollateralCustodyStatus.handoverRequested,
          CollateralCustodyStatus.exceptionHeld,
        ),
        isFalse,
      );
    });

    test('isValidTransition rejects exceptionHeld → returned (terminal)', () {
      expect(
        CollateralCustodyStatus.isValidTransition(
          CollateralCustodyStatus.exceptionHeld,
          CollateralCustodyStatus.returned,
        ),
        isFalse,
      );
    });

    test('isValidTransition rejects exceptionHeld → inCustody (terminal)', () {
      expect(
        CollateralCustodyStatus.isValidTransition(
          CollateralCustodyStatus.exceptionHeld,
          CollateralCustodyStatus.inCustody,
        ),
        isFalse,
      );
    });

    test('transitionCustody performs inCustody → exceptionHeld', () {
      final item = CollateralItem(
        id: 'coll-12',
        shopId: 'shop-1',
        customerId: 1,
        itemReferenceId: 'COLL-012',
        category: CollateralItemCategory.gold,
        description: 'Test item',
        conditionGrade: 'Good',
        weightMilligrams: 1000,
        estimatedValueCents: 100000,
      );

      final held = item.transitionCustody(CollateralCustodyStatus.exceptionHeld);
      expect(held.custodyStatus, equals(CollateralCustodyStatus.exceptionHeld));
      expect(held.custodyStatus.isTerminal, isTrue);
    });

    test('transitionCustody performs handoverReported → exceptionHeld', () {
      final reported = CollateralItem(
        id: 'coll-13',
        shopId: 'shop-1',
        customerId: 1,
        itemReferenceId: 'COLL-013',
        category: CollateralItemCategory.gold,
        description: 'Test item',
        conditionGrade: 'Good',
        weightMilligrams: 1000,
        estimatedValueCents: 100000,
        custodyStatus: CollateralCustodyStatus.handoverReported,
      );

      final held = reported.transitionCustody(CollateralCustodyStatus.exceptionHeld);
      expect(held.custodyStatus, equals(CollateralCustodyStatus.exceptionHeld));
      expect(held.custodyStatus.isTerminal, isTrue);
    });

    test('transitionCustody throws on exceptionHeld → returned (terminal)', () {
      final held = CollateralItem(
        id: 'coll-14',
        shopId: 'shop-1',
        customerId: 1,
        itemReferenceId: 'COLL-014',
        category: CollateralItemCategory.gold,
        description: 'Test item',
        conditionGrade: 'Good',
        weightMilligrams: 1000,
        estimatedValueCents: 100000,
        custodyStatus: CollateralCustodyStatus.exceptionHeld,
      );

      expect(
        () => held.transitionCustody(CollateralCustodyStatus.returned),
        throwsA(isA<CollateralCustodyTransitionException>()),
      );
    });
  });

  group('CollateralItemCategory fromValue', () {
    test('resolves valid categories', () {
      expect(CollateralItemCategory.fromValue('gold'), equals(CollateralItemCategory.gold));
      expect(CollateralItemCategory.fromValue('electronics'), equals(CollateralItemCategory.electronics));
      expect(CollateralItemCategory.fromValue('sports'), equals(CollateralItemCategory.sports));
      expect(CollateralItemCategory.fromValue('dress'), equals(CollateralItemCategory.dress));
      expect(CollateralItemCategory.fromValue('grocery'), equals(CollateralItemCategory.grocery));
      expect(CollateralItemCategory.fromValue('cosmetic'), equals(CollateralItemCategory.cosmetic));
      expect(CollateralItemCategory.fromValue('medicine'), equals(CollateralItemCategory.medicine));
      expect(CollateralItemCategory.fromValue('valuables'), equals(CollateralItemCategory.valuables));
      expect(CollateralItemCategory.fromValue('other'), equals(CollateralItemCategory.other));
    });

    test('exposes selection-tag labels', () {
      expect(CollateralItemCategory.gold.label, equals('Gold'));
      expect(CollateralItemCategory.electronics.label, equals('Electronics'));
      expect(CollateralItemCategory.sports.label, equals('Sports'));
      expect(CollateralItemCategory.dress.label, equals('Dress'));
      expect(CollateralItemCategory.grocery.label, equals('Grocery Item'));
      expect(CollateralItemCategory.cosmetic.label, equals('Cosmetic'));
      expect(CollateralItemCategory.medicine.label, equals('Medicine'));
      expect(CollateralItemCategory.valuables.label, equals('Valuables'));
      expect(CollateralItemCategory.other.label, equals('Other'));
    });

    test('throws on invalid category', () {
      expect(() => CollateralItemCategory.fromValue('jewelry'),
          throwsArgumentError);
    });
  });

  group('CollateralCustodyStatus fromValue', () {
    test('resolves valid statuses', () {
      expect(CollateralCustodyStatus.fromValue('in_custody'), equals(CollateralCustodyStatus.inCustody));
      expect(CollateralCustodyStatus.fromValue('returned'), equals(CollateralCustodyStatus.returned));
      expect(CollateralCustodyStatus.fromValue('exception_held'), equals(CollateralCustodyStatus.exceptionHeld));
    });

    test('throws on invalid status', () {
      expect(() => CollateralCustodyStatus.fromValue('lost'),
          throwsArgumentError);
    });
  });
}

