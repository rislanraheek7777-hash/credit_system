/// Base exception for all monetary-related domain errors.
abstract class MonetaryException implements Exception {
  /// Explanatory message of the error.
  final String message;

  const MonetaryException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when an operation is attempted between two incompatible currencies.
class IncompatibleCurrencyException extends MonetaryException {
  final String currencyA;
  final String currencyB;

  const IncompatibleCurrencyException(
    this.currencyA,
    this.currencyB, [
    String? message,
  ]) : super(
          message ??
              'Cannot perform monetary operation between incompatible currencies: "$currencyA" and "$currencyB"',
        );
}

/// Thrown when a string input cannot be parsed into a valid monetary amount
/// (e.g., non-numeric characters, multiple decimals, or more than two decimal places).
class InvalidMonetaryFormatException extends MonetaryException {
  const InvalidMonetaryFormatException(super.message);
}

/// Thrown when an arithmetic operation or parsed value exceeds the bounds of a 64-bit integer.
class MonetaryOverflowException extends MonetaryException {
  const MonetaryOverflowException(super.message);
}
