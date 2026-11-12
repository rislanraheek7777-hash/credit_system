import 'package:drift/drift.dart';
import '../../errors/monetary_exceptions.dart';
import '../../money/money.dart';

/// Drift [TypeConverter] that maps between the Dart [Money] domain value object
/// and a 64-bit integer ([int]) representing minor units (cents) in SQLite.
///
/// In alignment with Architecture Decisions AD-1 and AD-2, and PRD FR-22:
/// - Monetary amounts are persisted strictly as 64-bit signed integers in minor units (`INTEGER`).
/// - Floating-point representations (`double` / `REAL`) are strictly forbidden in persistence.
/// - **Currency Invariant Enforcement:** When serializing to a minor-units-only column,
///   the converter strictly validates that the [Money] instance matches [expectedCurrency].
///   Attempting to persist a mismatched currency throws [IncompatibleCurrencyException]
///   rather than silently discarding currency information.
class MoneyConverter extends TypeConverter<Money, int> {
  /// The currency this converter expects and enforces for the column (default: 'LKR').
  final String expectedCurrency;

  const MoneyConverter({this.expectedCurrency = Money.defaultCurrency});

  @override
  Money fromSql(int fromDb) {
    return Money(fromDb, currency: expectedCurrency);
  }

  @override
  int toSql(Money value) {
    if (value.currency != expectedCurrency) {
      throw IncompatibleCurrencyException(
        value.currency,
        expectedCurrency,
        'Cannot persist Money with currency "${value.currency}" into a database column configured strictly for "$expectedCurrency"',
      );
    }
    return value.minorUnits;
  }
}

/// Nullable version of [MoneyConverter] for optional database columns.
class NullableMoneyConverter extends NullAwareTypeConverter<Money, int> {
  /// The currency this converter expects and enforces for the column (default: 'LKR').
  final String expectedCurrency;

  const NullableMoneyConverter({this.expectedCurrency = Money.defaultCurrency});

  @override
  Money requireFromSql(int fromDb) {
    return Money(fromDb, currency: expectedCurrency);
  }

  @override
  int requireToSql(Money value) {
    if (value.currency != expectedCurrency) {
      throw IncompatibleCurrencyException(
        value.currency,
        expectedCurrency,
        'Cannot persist Money with currency "${value.currency}" into a database column configured strictly for "$expectedCurrency"',
      );
    }
    return value.minorUnits;
  }
}

