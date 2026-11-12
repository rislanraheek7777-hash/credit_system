import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/errors/monetary_exceptions.dart';
import 'package:credit_system/core/money/money.dart';

void main() {
  group('Money - Instantiation & Representation', () {
    test('creates Money with integer minor units (cents) and default LKR currency', () {
      const money = Money(150050);
      expect(money.minorUnits, equals(150050));
      expect(money.currency, equals('LKR'));
      expect(money.majorUnits, equals(1500));
      expect(money.centsPart, equals(50));
      expect(money.isPositive, isTrue);
      expect(money.isNegative, isFalse);
      expect(money.isZero, isFalse);
    });

    test('creates Money.zero with default and custom currency', () {
      const zeroLkr = Money.zero();
      expect(zeroLkr.minorUnits, equals(0));
      expect(zeroLkr.currency, equals('LKR'));
      expect(zeroLkr.isZero, isTrue);
      expect(zeroLkr.isPositive, isFalse);
      expect(zeroLkr.isNegative, isFalse);

      const zeroUsd = Money.zero('USD');
      expect(zeroUsd.currency, equals('USD'));
      expect(zeroUsd.isZero, isTrue);
    });

    test('creates Money using fromCents factory', () {
      final money = Money.fromCents(25000);
      expect(money.minorUnits, equals(25000));
      expect(money.majorUnits, equals(250));
      expect(money.centsPart, equals(0));
    });

    test('creates Money using fromMajorUnits factory with valid parameters', () {
      final money = Money.fromMajorUnits(500, minorUnits: 75);
      expect(money.minorUnits, equals(50075));
      expect(money.majorUnits, equals(500));
      expect(money.centsPart, equals(75));

      final negative = Money.fromMajorUnits(-10, minorUnits: 50);
      expect(negative.minorUnits, equals(-1050));
      expect(negative.isNegative, isTrue);
      expect(negative.centsPart, equals(50));
    });

    test('rejects fromMajorUnits with out-of-range minorUnits', () {
      expect(
        () => Money.fromMajorUnits(100, minorUnits: 100),
        throwsA(isA<InvalidMonetaryFormatException>()),
      );
      expect(
        () => Money.fromMajorUnits(100, minorUnits: -1),
        throwsA(isA<InvalidMonetaryFormatException>()),
      );
    });

    test('rejects fromMajorUnits with major units that would overflow minor units', () {
      expect(
        () => Money.fromMajorUnits(92233720368547759),
        throwsA(isA<MonetaryOverflowException>()),
      );
    });
  });

  group('Money - Parsing & Strict Rounding Prevention', () {
    test('parses exact integers into minor units', () {
      final money = Money.parse('250');
      expect(money.minorUnits, equals(25000));
      expect(money.currency, equals('LKR'));
    });

    test('parses standard two-decimal strings', () {
      final money = Money.parse('1500.50');
      expect(money.minorUnits, equals(150050));
      expect(money.majorUnits, equals(1500));
      expect(money.centsPart, equals(50));
    });

    test('parses single decimal digit as tenths of currency (e.g. .5 = 50 cents)', () {
      final money = Money.parse('100.5');
      expect(money.minorUnits, equals(10050));
      expect(money.centsPart, equals(50));
    });

    test('parses zero and negative zero correctly', () {
      final zero = Money.parse('0');
      expect(zero.minorUnits, equals(0));
      expect(zero.isZero, isTrue);

      final zeroDecimal = Money.parse('0.00');
      expect(zeroDecimal.minorUnits, equals(0));

      final negZero = Money.parse('-0.00');
      expect(negZero.minorUnits, equals(0));
      expect(negZero.isNegative, isFalse);
    });

    test('parses signed positive and negative values', () {
      final positive = Money.parse('+500.25');
      expect(positive.minorUnits, equals(50025));

      final negative = Money.parse('-500.25');
      expect(negative.minorUnits, equals(-50025));
      expect(negative.isNegative, isTrue);
    });

    test('parses comma-separated amounts accurately', () {
      final money = Money.parse('1,500.50');
      expect(money.minorUnits, equals(150050));

      final million = Money.parse('1,000,000.00');
      expect(million.minorUnits, equals(100000000));
    });

    test('handles leading and trailing whitespace gracefully', () {
      final money = Money.parse('   750.20   ');
      expect(money.minorUnits, equals(75020));
    });

    test('STRICT: rejects values with more than two decimal places without silent rounding', () {
      // Must NOT silently round 1500.555 to 1500.56 or truncate to 1500.55
      expect(
        () => Money.parse('1500.555'),
        throwsA(isA<InvalidMonetaryFormatException>()),
      );
      expect(
        () => Money.parse('0.123'),
        throwsA(isA<InvalidMonetaryFormatException>()),
      );
      expect(
        () => Money.parse('10.001'),
        throwsA(isA<InvalidMonetaryFormatException>()),
      );
      expect(Money.tryParse('1500.555'), isNull);
    });

    test('rejects malformed and non-numeric inputs', () {
      expect(() => Money.parse(''), throwsA(isA<InvalidMonetaryFormatException>()));
      expect(() => Money.parse('   '), throwsA(isA<InvalidMonetaryFormatException>()));
      expect(() => Money.parse('-'), throwsA(isA<InvalidMonetaryFormatException>()));
      expect(() => Money.parse('+'), throwsA(isA<InvalidMonetaryFormatException>()));
      expect(() => Money.parse('abc'), throwsA(isA<InvalidMonetaryFormatException>()));
      expect(() => Money.parse('1500..50'), throwsA(isA<InvalidMonetaryFormatException>()));
      expect(() => Money.parse('1.5.0'), throwsA(isA<InvalidMonetaryFormatException>()));
      expect(() => Money.parse('1500.'), throwsA(isA<InvalidMonetaryFormatException>()));
      expect(() => Money.parse('1,,500'), throwsA(isA<InvalidMonetaryFormatException>()));
    });

    test('rejects values that exceed 64-bit integer limits during parsing', () {
      expect(
        () => Money.parse('999999999999999999999999999.00'),
        throwsA(isA<MonetaryOverflowException>()),
      );
    });

    test('tryParse returns null on invalid input instead of throwing', () {
      expect(Money.tryParse('invalid'), isNull);
      expect(Money.tryParse('100.999'), isNull);
      expect(Money.tryParse('100.50'), equals(const Money(10050)));
    });
  });

  group('Money - Arithmetic Operations & Invariants', () {
    test('exact addition of positive amounts', () {
      final a = Money.parse('50000.00'); // 5,000,000 cents
      final b = Money.parse('20000.00'); // 2,000,000 cents
      final sum = a + b;
      expect(sum.minorUnits, equals(7000000));
      expect(sum.toFormattedString(), equals('Rs. 70,000.00'));
    });

    test('exact subtraction with positive remaining balance', () {
      final balance = Money.parse('50000.00');
      final payment = Money.parse('20000.00');
      final remaining = balance - payment;
      expect(remaining.minorUnits, equals(3000000));
      expect(remaining.toFormattedString(), equals('Rs. 30,000.00'));
    });

    test('full settlement subtraction reaches exact zero', () {
      final balance = Money.parse('30000.00');
      final payment = Money.parse('30000.00');
      final remaining = balance - payment;
      expect(remaining.isZero, isTrue);
      expect(remaining.minorUnits, equals(0));
      expect(remaining.toFormattedString(), equals('Rs. 0.00'));
    });

    test('subtraction yielding negative amount succeeds for signed ledger differences', () {
      // In accordance with user guidance: Money value object supports negative amounts
      // for signed differences and adjustments; overpayment blocking belongs in domain service.
      final a = Money.parse('20000.00');
      final b = Money.parse('50000.00');
      final diff = a - b;
      expect(diff.isNegative, isTrue);
      expect(diff.minorUnits, equals(-3000000));
      expect(diff.toFormattedString(), equals('-Rs. 30,000.00'));
    });

    test('unary negation', () {
      final positive = const Money(150050);
      final negated = -positive;
      expect(negated.minorUnits, equals(-150050));
      expect(negated.isNegative, isTrue);

      final backToPos = -negated;
      expect(backToPos.minorUnits, equals(150050));
    });

    test('integer scalar multiplication', () {
      final base = Money.parse('1500.50');
      final tripled = base * 3;
      expect(tripled.minorUnits, equals(450150));

      final zeroed = base * 0;
      expect(zeroed.isZero, isTrue);
    });

    test('absolute value', () {
      final negative = const Money(-150050);
      expect(negative.abs(), equals(const Money(150050)));

      final positive = const Money(150050);
      expect(positive.abs(), equals(const Money(150050)));
    });

    test('detects integer overflow on extreme additions and subtractions', () {
      const nearMax = Money(Money.maxMinorUnits - 10);
      expect(
        () => nearMax + const Money(20),
        throwsA(isA<MonetaryOverflowException>()),
      );

      const nearMin = Money(Money.minMinorUnits + 10);
      expect(
        () => nearMin - const Money(20),
        throwsA(isA<MonetaryOverflowException>()),
      );
    });
  });

  group('Money - Currency Compatibility & Isolation', () {
    test('addition across mismatched currencies throws IncompatibleCurrencyException', () {
      const lkr = Money(5000, currency: 'LKR');
      const usd = Money(5000, currency: 'USD');
      expect(
        () => lkr + usd,
        throwsA(isA<IncompatibleCurrencyException>()),
      );
    });

    test('subtraction across mismatched currencies throws IncompatibleCurrencyException', () {
      const lkr = Money(5000, currency: 'LKR');
      const usd = Money(5000, currency: 'USD');
      expect(
        () => lkr - usd,
        throwsA(isA<IncompatibleCurrencyException>()),
      );
    });

    test('comparison across mismatched currencies throws IncompatibleCurrencyException', () {
      const lkr = Money(5000, currency: 'LKR');
      const usd = Money(5000, currency: 'USD');
      expect(
        () => lkr < usd,
        throwsA(isA<IncompatibleCurrencyException>()),
      );
      expect(
        () => lkr.compareTo(usd),
        throwsA(isA<IncompatibleCurrencyException>()),
      );
    });
  });

  group('Money - Comparisons & Equality', () {
    test('implements value equality (== and hashCode)', () {
      const a = Money(150050, currency: 'LKR');
      const b = Money(150050, currency: 'LKR');
      const diffAmount = Money(200000, currency: 'LKR');
      const diffCurrency = Money(150050, currency: 'USD');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a == diffAmount, isFalse);
      expect(a == diffCurrency, isFalse);
    });

    test('supports relational operators (<, <=, >, >=)', () {
      const smaller = Money(10000);
      const larger = Money(20000);
      const equalToSmaller = Money(10000);

      expect(smaller < larger, isTrue);
      expect(smaller <= larger, isTrue);
      expect(larger > smaller, isTrue);
      expect(larger >= smaller, isTrue);

      expect(smaller <= equalToSmaller, isTrue);
      expect(smaller >= equalToSmaller, isTrue);
      expect(smaller < equalToSmaller, isFalse);
      expect(smaller > equalToSmaller, isFalse);
    });

    test('handles negative comparison ordering', () {
      const negative = Money(-10000);
      const zero = Money.zero();
      const positive = Money(10000);

      expect(negative < zero, isTrue);
      expect(zero < positive, isTrue);
      expect(negative < positive, isTrue);
    });
  });

  group('Money - Presentation Formatting', () {
    test('formats positive amounts with currency symbol and thousand separators', () {
      final small = Money.parse('50.25');
      expect(small.toFormattedString(), equals('Rs. 50.25'));

      final medium = Money.parse('1500.50');
      expect(medium.toFormattedString(), equals('Rs. 1,500.50'));

      final large = Money.parse('1250000.00');
      expect(large.toFormattedString(), equals('Rs. 1,250,000.00'));
    });

    test('formats zero with two decimal places', () {
      final zero = Money.zero();
      expect(zero.toFormattedString(), equals('Rs. 0.00'));
    });

    test('formats negative amounts with leading minus sign before symbol', () {
      final negative = Money.parse('-1500.50');
      expect(negative.toFormattedString(), equals('-Rs. 1,500.50'));
    });

    test('supports formatting without symbol (ISO code suffix)', () {
      final amount = Money.parse('1500.50');
      expect(
        amount.format(includeSymbol: false),
        equals('1,500.50 LKR'),
      );

      final negAmount = Money.parse('-1500.50');
      expect(
        negAmount.format(includeSymbol: false),
        equals('-1,500.50 LKR'),
      );
    });

    test('supports custom currency symbols', () {
      final usd = const Money(150050, currency: 'USD');
      expect(
        usd.format(customSymbol: '\$'),
        equals('\$ 1,500.50'),
      );
    });

    test('toString provides unambiguous developer representation', () {
      const money = Money(150050, currency: 'LKR');
      expect(money.toString(), equals('Money(150050 cents, LKR)'));
    });
  });
}

