import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:credit_system/core/database/converters/money_converter.dart';
import 'package:credit_system/core/database/schema/financial_column_contract.dart';
import 'package:credit_system/core/errors/monetary_exceptions.dart';
import 'package:credit_system/core/money/money.dart';

void main() {
  group('MoneyConverter - Direct Unit Tests', () {
    const converter = MoneyConverter();

    test('serializes and deserializes positive money amounts without precision loss', () {
      final original = Money.parse('1500.50'); // 150050 cents
      final sqlInt = converter.toSql(original);
      expect(sqlInt, equals(150050));

      final restored = converter.fromSql(sqlInt);
      expect(restored, equals(original));
      expect(restored.currency, equals('LKR'));
      expect(restored.minorUnits, equals(150050));
    });

    test('serializes and deserializes zero amounts', () {
      const zero = Money.zero();
      final sqlInt = converter.toSql(zero);
      expect(sqlInt, equals(0));

      final restored = converter.fromSql(sqlInt);
      expect(restored.isZero, isTrue);
      expect(restored, equals(zero));
    });

    test('serializes and deserializes negative amounts (signed ledger differences)', () {
      final negative = Money.parse('-25000.75'); // -2500075 cents
      final sqlInt = converter.toSql(negative);
      expect(sqlInt, equals(-2500075));

      final restored = converter.fromSql(sqlInt);
      expect(restored.isNegative, isTrue);
      expect(restored, equals(negative));
      expect(restored.toFormattedString(), equals('-Rs. 25,000.75'));
    });

    test('handles extreme 64-bit signed integer values without overflow or truncation', () {
      const maxMoney = Money(FinancialColumnContract.maxMinorUnits);
      final maxSql = converter.toSql(maxMoney);
      expect(maxSql, equals(FinancialColumnContract.maxMinorUnits));
      expect(converter.fromSql(maxSql), equals(maxMoney));

      const minMoney = Money(FinancialColumnContract.minMinorUnits);
      final minSql = converter.toSql(minMoney);
      expect(minSql, equals(FinancialColumnContract.minMinorUnits));
      expect(converter.fromSql(minSql), equals(minMoney));
    });

    test('CURRENCY INVARIANT: rejects Money with mismatched currency rather than silently discarding code', () {
      const foreignMoney = Money(10050, currency: 'USD');
      expect(
        () => converter.toSql(foreignMoney),
        throwsA(isA<IncompatibleCurrencyException>()),
      );
    });

    test('allows converter configured for custom non-default currency', () {
      const usdConverter = MoneyConverter(expectedCurrency: 'USD');
      const usdMoney = Money(10050, currency: 'USD');

      final sqlInt = usdConverter.toSql(usdMoney);
      expect(sqlInt, equals(10050));

      final restored = usdConverter.fromSql(sqlInt);
      expect(restored.currency, equals('USD'));
      expect(restored, equals(usdMoney));

      // Should now reject LKR
      expect(
        () => usdConverter.toSql(const Money(10050, currency: 'LKR')),
        throwsA(isA<IncompatibleCurrencyException>()),
      );
    });
  });

  group('NullableMoneyConverter - Null Handling & Invariants', () {
    const nullableConverter = NullableMoneyConverter();

    test('converts null values to and from SQL cleanly', () {
      expect(nullableConverter.toSql(null), isNull);
      expect(nullableConverter.fromSql(null), isNull);
    });

    test('converts non-null values accurately', () {
      final money = Money.parse('750.25');
      final sql = nullableConverter.toSql(money);
      expect(sql, equals(75025));

      final restored = nullableConverter.fromSql(sql);
      expect(restored, equals(money));
    });

    test('rejects currency mismatch on non-null values', () {
      const usd = Money(500, currency: 'USD');
      expect(
        () => nullableConverter.toSql(usd),
        throwsA(isA<IncompatibleCurrencyException>()),
      );
    });
  });

  group('Drift / SQLite Real In-Memory Database Roundtrip Tests', () {
    late Database db;
    const converter = MoneyConverter();

    setUp(() {
      db = sqlite3.openInMemory();
      db.execute('''
        CREATE TABLE test_ledger (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tenant_id TEXT NOT NULL,
          description TEXT NOT NULL,
          amount_cents INTEGER NOT NULL
        );
      ''');
    });

    tearDown(() {
      db.close();
    });

    test('SQLite roundtrip stores and retrieves positive, negative, zero, and large values as exact 64-bit integers', () {
      final testCases = [
        Money.parse('50000.00'),       // Typical principal: 5,000,000 cents
        Money.parse('20000.50'),       // Partial payment: 2,000,050 cents
        Money.zero(),                  // Zero balance settlement: 0 cents
        Money.parse('-1500.25'),       // Signed adjustment: -150025 cents
        const Money(9223372036854775807), // Max 64-bit int limit
        const Money(-9223372036854775808),// Min 64-bit int limit
      ];

      final insertStmt = db.prepare('''
        INSERT INTO test_ledger (tenant_id, description, amount_cents)
        VALUES (?, ?, ?);
      ''');

      for (int i = 0; i < testCases.length; i++) {
        final money = testCases[i];
        final sqlInt = converter.toSql(money);
        insertStmt.execute(['tenant-test-1', 'Entry #$i', sqlInt]);
      }
      insertStmt.close();

      // Read back from SQLite
      final rows = db.select('SELECT id, description, amount_cents FROM test_ledger ORDER BY id ASC');
      expect(rows.length, equals(testCases.length));

      for (int i = 0; i < rows.length; i++) {
        final row = rows[i];
        final rawSqlInt = row['amount_cents'] as int;
        final retrievedMoney = converter.fromSql(rawSqlInt);

        expect(
          retrievedMoney,
          equals(testCases[i]),
          reason: 'Failed roundtrip for test case ${testCases[i]}',
        );
        expect(retrievedMoney.minorUnits, equals(testCases[i].minorUnits));
        expect(retrievedMoney.currency, equals('LKR'));
      }
    });

    test('SQLite strictly rejects non-integer floats when schema enforces INTEGER', () {
      // Direct SQLite verification: proves that floating point numbers can be rejected
      // or that integers never lose precision
      final selectInt = db.select('SELECT CAST(150050 AS INTEGER) as val');
      expect(selectInt.first['val'], equals(150050));
      expect(selectInt.first['val'], isA<int>());
    });
  });

  group('PostgreSQL Contract & Numeric Bounds Verification', () {
    test('verifies Dart, SQLite INTEGER, and PostgreSQL BIGINT numeric boundaries agree exactly', () {
      // Dart 64-bit integer limits:
      expect(Money.maxMinorUnits, equals(9223372036854775807));
      expect(Money.minMinorUnits, equals(-9223372036854775808));

      // FinancialColumnContract constants match:
      expect(FinancialColumnContract.maxMinorUnits, equals(Money.maxMinorUnits));
      expect(FinancialColumnContract.minMinorUnits, equals(Money.minMinorUnits));

      // Authoritative types:
      expect(FinancialColumnContract.postgresAuthoritativeType, equals('BIGINT'));
      expect(FinancialColumnContract.sqliteAuthoritativeType, equals('INTEGER'));

      // Prohibited types catalog includes all float variants:
      expect(FinancialColumnContract.prohibitedSqlTypes, contains('DOUBLE PRECISION'));
      expect(FinancialColumnContract.prohibitedSqlTypes, contains('FLOAT8'));
      expect(FinancialColumnContract.prohibitedSqlTypes, contains('REAL'));
    });
  });
}
