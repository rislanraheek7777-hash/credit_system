/// Formal specification and contract for financial column representation in PostgreSQL and SQLite.
///
/// Binds: PRD FR-3, FR-18, FR-21, FR-22, FR-24; Architecture Decisions AD-1, AD-2.
class FinancialColumnContract {
  // --- Supported Numeric Bounds (Exact 64-bit Signed Integer Parity) ---

  /// Maximum representable 64-bit signed integer value ($2^{63}-1$).
  ///
  /// Exactly matches:
  /// - Dart 64-bit `int` (`Money.maxMinorUnits`)
  /// - SQLite `INTEGER` (64-bit signed)
  /// - PostgreSQL `BIGINT` (-9223372036854775808 to +9223372036854775807)
  static const int maxMinorUnits = 9223372036854775807;

  /// Minimum representable 64-bit signed integer value ($-2^{63}$).
  static const int minMinorUnits = -9223372036854775808;

  /// Standard minor unit scale for Sri Lankan Rupees (`LKR`): 100 minor units per major unit.
  static const int minorUnitsPerRupee = 100;

  // --- Strict Prohibition of Floating-Point Types ---

  /// Prohibited PostgreSQL column data types for financial values:
  /// - `DOUBLE PRECISION` (FLOAT8): Prohibited due to IEEE 754 precision drift.
  /// - `REAL` (FLOAT4): Prohibited.
  /// - `NUMERIC` without fixed minor-unit semantics: Prohibited for base ledger fields
  ///   to maintain exact binary/integer alignment across Drift SQLite and PostgreSQL.
  static const List<String> prohibitedSqlTypes = [
    'DOUBLE PRECISION',
    'FLOAT8',
    'REAL',
    'FLOAT4',
    'FLOAT',
  ];

  /// The only authoritative column type for monetary minor units in PostgreSQL:
  static const String postgresAuthoritativeType = 'BIGINT';

  /// The only authoritative column type for monetary minor units in SQLite:
  static const String sqliteAuthoritativeType = 'INTEGER';

  // --- Standard PostgreSQL DDL Templates ---

  /// Standard DDL snippet for a non-negative principal amount column in PostgreSQL:
  static const String postgresPrincipalColumnDdl =
      'principal_minor_units BIGINT NOT NULL CHECK (principal_minor_units >= 0)';

  /// Standard DDL snippet for an outstanding balance column in PostgreSQL:
  static const String postgresBalanceColumnDdl =
      'outstanding_balance_minor_units BIGINT NOT NULL CHECK (outstanding_balance_minor_units >= 0)';

  /// Standard DDL snippet for a signed ledger adjustment column in PostgreSQL:
  static const String postgresAdjustmentColumnDdl =
      'adjustment_minor_units BIGINT NOT NULL';

  /// Standard DDL snippet for a confirmed payment amount column in PostgreSQL:
  static const String postgresPaymentColumnDdl =
      'amount_minor_units BIGINT NOT NULL CHECK (amount_minor_units > 0)';
}

