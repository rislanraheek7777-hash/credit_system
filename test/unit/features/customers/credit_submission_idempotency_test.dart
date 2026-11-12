import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/features/customers/domain/services/credit_submission_idempotency.dart';

/// Matches the canonical RFC 4122 version-4 UUID form.
final RegExp uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

CreditSubmissionFingerprint fingerprint({
  int customerId = 1,
  int principalCents = 500000,
  DateTime? dueDate,
  List<String> collateralItemIds = const ['coll-1'],
}) {
  return CreditSubmissionFingerprint(
    customerId: customerId,
    principalCents: principalCents,
    dueDate: dueDate ?? DateTime.utc(2026, 4, 15),
    collateralItemIds: collateralItemIds,
  );
}

void main() {
  group('CreditSubmissionFingerprint', () {
    test('is equal for the same submission content', () {
      expect(fingerprint(), equals(fingerprint()));
      expect(fingerprint().hashCode, equals(fingerprint().hashCode));
    });

    test('ignores the order of the selected collateral items', () {
      expect(
        fingerprint(collateralItemIds: const ['a', 'b']),
        equals(fingerprint(collateralItemIds: const ['b', 'a'])),
      );
    });

    test('differs when the customer differs', () {
      expect(
        fingerprint(customerId: 1),
        isNot(equals(fingerprint(customerId: 2))),
      );
    });

    test('differs when the principal differs', () {
      expect(
        fingerprint(principalCents: 500000),
        isNot(equals(fingerprint(principalCents: 500001))),
      );
    });

    test('differs when the due date differs', () {
      expect(
        fingerprint(dueDate: DateTime.utc(2026, 4, 15)),
        isNot(equals(fingerprint(dueDate: DateTime.utc(2026, 4, 16)))),
      );
    });

    test('is equal and deterministic for an empty collateral item list', () {
      final first = fingerprint(collateralItemIds: const []);
      final second = fingerprint(collateralItemIds: const []);

      expect(first, equals(second));
      expect(first.hashCode, equals(second.hashCode));
      expect(first.canonical, equals(second.canonical));
    });

    test('differs when the collateral set differs', () {
      expect(
        fingerprint(collateralItemIds: const ['a']),
        isNot(equals(fingerprint(collateralItemIds: const ['a', 'b']))),
      );
    });
  });

  group('CreditSubmissionIdempotency - F3 key lifecycle', () {
    late CreditSubmissionIdempotency idempotency;

    setUp(() {
      idempotency = CreditSubmissionIdempotency();
    });

    test('a new submission receives a fresh UUIDv4 key', () {
      final key = idempotency.keyFor(fingerprint());
      expect(key, matches(uuidV4Pattern));
      expect(idempotency.currentKey, equals(key));
    });

    test('a retry of the same submission reuses the key', () {
      final first = idempotency.keyFor(fingerprint());
      final second = idempotency.keyFor(fingerprint());
      expect(second, equals(first));
    });

    test('a retry stays stable across many attempts', () {
      final first = idempotency.keyFor(fingerprint());
      for (var i = 0; i < 5; i++) {
        expect(idempotency.keyFor(fingerprint()), equals(first));
      }
    });

    test('a different customer receives a different key', () {
      final first = idempotency.keyFor(fingerprint(customerId: 1));
      final second = idempotency.keyFor(fingerprint(customerId: 2));
      expect(second, isNot(equals(first)));
    });

    test('a different principal receives a different key', () {
      final first = idempotency.keyFor(fingerprint(principalCents: 500000));
      final second = idempotency.keyFor(fingerprint(principalCents: 750000));
      expect(second, isNot(equals(first)));
    });

    test('a different due date receives a different key', () {
      final first = idempotency.keyFor(
        fingerprint(dueDate: DateTime.utc(2026, 4, 15)),
      );
      final second = idempotency.keyFor(
        fingerprint(dueDate: DateTime.utc(2026, 5, 15)),
      );
      expect(second, isNot(equals(first)));
    });

    test('a different collateral set receives a different key', () {
      final first = idempotency.keyFor(
        fingerprint(collateralItemIds: const ['a']),
      );
      final second = idempotency.keyFor(
        fingerprint(collateralItemIds: const ['a', 'b']),
      );
      expect(second, isNot(equals(first)));
    });

    test('re-selecting the same collateral in a different order reuses the key',
        () {
      final first = idempotency.keyFor(
        fingerprint(collateralItemIds: const ['a', 'b']),
      );
      final second = idempotency.keyFor(
        fingerprint(collateralItemIds: const ['b', 'a']),
      );
      expect(second, equals(first));
    });

    test('reset clears the key so the next submission is a new one', () {
      final first = idempotency.keyFor(fingerprint());
      idempotency.reset();
      expect(idempotency.currentKey, isNull);
      expect(idempotency.boundFingerprint, isNull);

      final second = idempotency.keyFor(fingerprint());
      expect(second, isNot(equals(first)));
      expect(second, matches(uuidV4Pattern));
    });

    test('each issued key is a valid UUIDv4', () {
      for (var i = 0; i < 20; i++) {
        final key = idempotency.keyFor(fingerprint(principalCents: i));
        expect(key, matches(uuidV4Pattern));
      }
    });
  });
}

