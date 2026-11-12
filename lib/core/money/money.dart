import 'package:meta/meta.dart';
import '../errors/monetary_exceptions.dart';

/// Immutable domain Value Object representing monetary amounts in integer minor units (cents).
///
/// In alignment with Architecture Decision AD-2 and PRD FR-22:
/// - Floating-point representations (`double` / `float`) are strictly forbidden.
/// - Amounts are stored internally as 64-bit integer minor units (e.g. 100 cents = 1.00 LKR).
/// - Cross-currency arithmetic and comparisons are strictly rejected without conversion.
/// - Negative amounts are supported for signed ledger adjustments and balance differences,
///   while business rules preventing credit overpayments are enforced in higher domain layers.
@immutable
class Money implements Comparable<Money> {
  /// Default currency code for the system baseline (Sri Lankan Rupees).
  static const String defaultCurrency = 'LKR';

  /// Maximum representable 64-bit signed integer value.
  static const int maxMinorUnits = 9223372036854775807;

  /// Minimum representable 64-bit signed integer value.
  static const int minMinorUnits = -9223372036854775808;

  /// Largest major unit value that can be safely converted to minor units without overflow.
  static const int _maxSafeMajorUnits = 92233720368547758;

  /// The monetary value stored strictly as integer minor units (e.g., cents).
  final int minorUnits;

  /// Standard ISO 4217 currency code (e.g., 'LKR').
  final String currency;

  /// Creates a [Money] instance from the given integer [minorUnits] and [currency].
  const Money(this.minorUnits, {this.currency = defaultCurrency});

  /// Creates a [Money] instance representing zero in the specified [currency].
  const Money.zero([String currency = defaultCurrency]) : this(0, currency: currency);

  /// Creates a [Money] instance directly from integer cents.
  factory Money.fromCents(int cents, {String currency = defaultCurrency}) {
    return Money(cents, currency: currency);
  }

  /// Creates a [Money] instance from major units (e.g. Rupees) and minor units (cents).
  ///
  /// [minorUnits] must be in the range 0 to 99 inclusive.
  /// If [majorUnits] is negative, [minorUnits] will be treated as contributing
  /// to the negative total.
  factory Money.fromMajorUnits(
    int majorUnits, {
    int minorUnits = 0,
    String currency = defaultCurrency,
  }) {
    if (minorUnits < 0 || minorUnits > 99) {
      throw const InvalidMonetaryFormatException(
        'Minor units must be between 0 and 99 inclusive',
      );
    }

    if (majorUnits.abs() > _maxSafeMajorUnits) {
      throw const MonetaryOverflowException(
        'Major units value would cause integer overflow when converted to minor units',
      );
    }

    final int total;
    if (majorUnits < 0) {
      total = (majorUnits * 100) - minorUnits;
    } else {
      total = (majorUnits * 100) + minorUnits;
    }

    return Money(total, currency: currency);
  }

  /// Parses a user-entered monetary string (e.g. `"1500.50"`, `"-250"`, `"1,500.00"`).
  ///
  /// **Strict Validation Rules:**
  /// - Strips leading/trailing whitespace.
  /// - Supports an optional leading `+` or `-` sign.
  /// - Allows well-formed thousand separator commas in the integer portion (e.g. `"1,500.50"`).
  /// - Rejects inputs with more than two decimal places (e.g. `"1500.555"`) without silent rounding.
  /// - Rejects non-numeric strings or multiple decimal points.
  /// - Throws [MonetaryOverflowException] if the parsed integer exceeds 64-bit limits.
  /// - Throws [InvalidMonetaryFormatException] on any other format error.
  static Money parse(String input, {String currency = defaultCurrency}) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const InvalidMonetaryFormatException('Monetary input string cannot be empty');
    }

    bool isNegative = false;
    String cleanStr = trimmed;

    if (cleanStr.startsWith('+')) {
      cleanStr = cleanStr.substring(1).trim();
    } else if (cleanStr.startsWith('-')) {
      isNegative = true;
      cleanStr = cleanStr.substring(1).trim();
    }

    if (cleanStr.isEmpty) {
      throw const InvalidMonetaryFormatException('Monetary input contains only a sign without digits');
    }

    final parts = cleanStr.split('.');
    if (parts.length > 2) {
      throw InvalidMonetaryFormatException(
        'Monetary input contains multiple decimal points: "$input"',
      );
    }

    final String integerStr = parts[0];
    final String? decimalStr = parts.length == 2 ? parts[1] : null;

    // Validate decimal digits if present
    int cents = 0;
    if (decimalStr != null) {
      if (decimalStr.isEmpty) {
        throw InvalidMonetaryFormatException(
          'Monetary input cannot have a trailing decimal point without digits: "$input"',
        );
      }
      if (decimalStr.length > 2) {
        throw InvalidMonetaryFormatException(
          'Monetary input cannot have more than 2 decimal places: "$input"',
        );
      }
      if (!RegExp(r'^\d+$').hasMatch(decimalStr)) {
        throw InvalidMonetaryFormatException(
          'Monetary decimal part contains non-digit characters: "$input"',
        );
      }

      if (decimalStr.length == 1) {
        cents = int.parse(decimalStr) * 10;
      } else {
        cents = int.parse(decimalStr);
      }
    }

    // Validate and parse integer/major units
    int major = 0;
    if (integerStr.isNotEmpty) {
      // Must match either pure digits or well-grouped thousands (e.g. 1,000,000)
      if (!RegExp(r'^(?:\d{1,3}(?:,\d{3})+|\d+)$').hasMatch(integerStr)) {
        throw InvalidMonetaryFormatException(
          'Monetary integer part contains invalid format or separators: "$input"',
        );
      }

      final digitsOnly = integerStr.replaceAll(',', '');
      final parsedMajor = int.tryParse(digitsOnly);
      if (parsedMajor == null) {
        throw MonetaryOverflowException(
          'Monetary value exceeds 64-bit integer limit: "$input"',
        );
      }
      if (parsedMajor > _maxSafeMajorUnits) {
        throw MonetaryOverflowException(
          'Monetary value exceeds 64-bit minor units capacity: "$input"',
        );
      }
      major = parsedMajor;
    } else {
      if (decimalStr == null) {
        throw const InvalidMonetaryFormatException('No numeric digits found in input');
      }
    }

    final totalCents = (major * 100) + cents;
    final signedCents = isNegative ? -totalCents : totalCents;

    return Money(signedCents, currency: currency);
  }

  /// Parses a user-entered monetary string, returning `null` if the string is invalid.
  static Money? tryParse(String input, {String currency = defaultCurrency}) {
    try {
      return parse(input, currency: currency);
    } catch (_) {
      return null;
    }
  }

  // --- State Queries ---

  /// Whether this amount is exactly zero.
  bool get isZero => minorUnits == 0;

  /// Whether this amount is strictly positive (> 0).
  bool get isPositive => minorUnits > 0;

  /// Whether this amount is strictly negative (< 0).
  bool get isNegative => minorUnits < 0;

  /// Returns the absolute value of this monetary amount.
  Money abs() => Money(minorUnits.abs(), currency: currency);

  /// Returns the major unit component (e.g., Rupees) by integer division.
  int get majorUnits => minorUnits ~/ 100;

  /// Returns the minor unit component (e.g., cents, 0 to 99).
  int get centsPart => (minorUnits % 100).abs();

  // --- Arithmetic Operators ---

  /// Adds two [Money] instances of the same currency.
  ///
  /// Throws [IncompatibleCurrencyException] if the currencies do not match.
  /// Throws [MonetaryOverflowException] if addition overflows 64-bit integer bounds.
  Money operator +(Money other) {
    _assertSameCurrency(other);

    // Overflow check for a + b
    if (other.minorUnits > 0 && minorUnits > maxMinorUnits - other.minorUnits) {
      throw const MonetaryOverflowException('Addition resulted in 64-bit integer overflow');
    }
    if (other.minorUnits < 0 && minorUnits < minMinorUnits - other.minorUnits) {
      throw const MonetaryOverflowException('Addition resulted in 64-bit integer underflow');
    }

    return Money(minorUnits + other.minorUnits, currency: currency);
  }

  /// Subtracts one [Money] instance from another of the same currency.
  ///
  /// Returns a negative [Money] if [other] is larger than `this`.
  /// Throws [IncompatibleCurrencyException] if the currencies do not match.
  /// Throws [MonetaryOverflowException] if subtraction overflows 64-bit integer bounds.
  Money operator -(Money other) {
    _assertSameCurrency(other);

    // Overflow check for a - b
    if (other.minorUnits < 0 && minorUnits > maxMinorUnits + other.minorUnits) {
      throw const MonetaryOverflowException('Subtraction resulted in 64-bit integer overflow');
    }
    if (other.minorUnits > 0 && minorUnits < minMinorUnits + other.minorUnits) {
      throw const MonetaryOverflowException('Subtraction resulted in 64-bit integer underflow');
    }

    return Money(minorUnits - other.minorUnits, currency: currency);
  }

  /// Multiplies this monetary amount by an integer scalar factor.
  ///
  /// Throws [MonetaryOverflowException] if the multiplication overflows.
  Money operator *(int factor) {
    if (factor == 0 || minorUnits == 0) {
      return Money.zero(currency);
    }
    if (factor == 1) {
      return this;
    }

    final product = minorUnits * factor;
    // Check overflow: if product / factor != minorUnits, overflow occurred
    if (product ~/ factor != minorUnits) {
      throw const MonetaryOverflowException('Multiplication resulted in 64-bit integer overflow');
    }

    return Money(product, currency: currency);
  }

  /// Unary negation of this monetary amount.
  Money operator -() {
    if (minorUnits == minMinorUnits) {
      throw const MonetaryOverflowException('Negation of minimum integer overflows 64-bit bounds');
    }
    return Money(-minorUnits, currency: currency);
  }

  // --- Comparison & Equality ---

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  bool operator <(Money other) => compareTo(other) < 0;
  bool operator <=(Money other) => compareTo(other) <= 0;
  bool operator >(Money other) => compareTo(other) > 0;
  bool operator >=(Money other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Money &&
        other.minorUnits == minorUnits &&
        other.currency == currency;
  }

  @override
  int get hashCode => Object.hash(minorUnits, currency);

  // --- Presentation Formatting ---

  /// Formats this monetary amount into a clean, human-readable string.
  ///
  /// Examples:
  /// - `150050` with LKR -> `"Rs. 1,500.50"`
  /// - `-150050` with LKR -> `"-Rs. 1,500.50"`
  /// - `0` with LKR -> `"Rs. 0.00"`
  /// - With `includeSymbol: false` -> `"1,500.50 LKR"`
  String format({
    bool includeSymbol = true,
    String? customSymbol,
    bool symbolAsPrefix = true,
  }) {
    final absUnits = minorUnits.abs();
    final major = absUnits ~/ 100;
    final cents = absUnits % 100;
    final centsStr = cents.toString().padLeft(2, '0');

    // Comma-formatted major digits
    final majorStr = major.toString();
    final buffer = StringBuffer();
    final length = majorStr.length;
    for (int i = 0; i < length; i++) {
      if (i > 0 && (length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(majorStr[i]);
    }
    final numberFormatted = '$buffer.$centsStr';

    final sign = isNegative ? '-' : '';

    if (!includeSymbol) {
      return '$sign$numberFormatted $currency';
    }

    final symbol = customSymbol ?? _defaultSymbolFor(currency);

    if (symbolAsPrefix) {
      return '$sign$symbol $numberFormatted';
    } else {
      return '$sign$numberFormatted $symbol';
    }
  }

  /// Default presentation string (e.g. `"Rs. 1,500.50"` or `"-Rs. 1,500.50"`).
  String toFormattedString() => format();

  @override
  String toString() => 'Money($minorUnits cents, $currency)';

  // --- Internal Helpers ---

  void _assertSameCurrency(Money other) {
    if (currency != other.currency) {
      throw IncompatibleCurrencyException(currency, other.currency);
    }
  }

  static String _defaultSymbolFor(String currency) {
    switch (currency) {
      case 'LKR':
        return 'Rs.';
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      default:
        return currency;
    }
  }
}

