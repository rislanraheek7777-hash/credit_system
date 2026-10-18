import 'package:meta/meta.dart';

/// Validation exception thrown when loan invariants are violated.
class LoanValidationException extends ArgumentError {
  LoanValidationException(super.message);
}

/// Status of a loan agreement.
///
/// Story 2.5 displays the stored status; automated overdue evaluation
/// is owned by Story 6.1 and is intentionally out of scope here.
enum LoanStatus {
  /// Loan is active and within its term.
  active('active'),

  /// Loan is past its due date with an outstanding balance.
  overdue('overdue'),

  /// Loan has been fully settled.
  settled('settled');

  final String value;
  const LoanStatus(this.value);

  /// Resolves [LoanStatus] from raw database text.
  static LoanStatus fromValue(String value) {
    for (final status in LoanStatus.values) {
      if (status.value == value) {
        return status;
      }
    }
    throw ArgumentError.value(value, 'value', 'Invalid LoanStatus string representation');
  }
}

/// Clean architecture domain entity representing a loan agreement (Story 2.5).
///
/// Money is stored in integer minor units (cents) — never as floating point.
@immutable
class Loan {
  /// Canonical UUID primary key.
  final String id;

  /// Associated shop tenant boundary.
  final String shopId;

  /// Associated customer borrower.
  final String customerId;

  /// Original principal in minor units (cents).
  final int principalCents;

  /// Outstanding balance in minor units (cents).
  final int balanceCents;

  /// Current lifecycle status.
  final LoanStatus status;

  /// Official due date (UTC).
  final DateTime dueDate;

  /// UTC creation timestamp.
  final DateTime createdAt;

  /// UTC settlement timestamp (null while not settled).
  final DateTime? settledAt;

  Loan({
    required this.id,
    required this.shopId,
    required this.customerId,
    required this.principalCents,
    required this.balanceCents,
    required this.status,
    required DateTime dueDate,
    required DateTime createdAt,
    DateTime? settledAt,
  })  : assert(principalCents >= 0, 'principalCents cannot be negative'),
        assert(balanceCents >= 0, 'balanceCents cannot be negative'),
        assert(balanceCents <= principalCents,
            'balanceCents cannot exceed principalCents'),
        assert(
          status != LoanStatus.settled || settledAt != null,
          'settled loans must have a settledAt timestamp',
        ),
        dueDate = dueDate.toUtc(),
        createdAt = createdAt.toUtc(),
        settledAt = settledAt?.toUtc();

  /// Returns true if the loan is eligible for customer actions
  /// (payment, detail view, collateral return).
  bool get isActionable => status == LoanStatus.active ||
      status == LoanStatus.overdue;

  /// Returns a copy of this [Loan] with the given fields replaced.
  Loan copyWith({
    String? id,
    String? shopId,
    String? customerId,
    int? principalCents,
    int? balanceCents,
    LoanStatus? status,
    DateTime? dueDate,
    DateTime? createdAt,
    DateTime? settledAt,
  }) {
    return Loan(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      customerId: customerId ?? this.customerId,
      principalCents: principalCents ?? this.principalCents,
      balanceCents: balanceCents ?? this.balanceCents,
      status: status ?? this.status,
      dueDate: dueDate ?? this.dueDate,
      createdAt: createdAt ?? this.createdAt,
      settledAt: settledAt ?? this.settledAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Loan &&
        other.id == id &&
        other.shopId == shopId &&
        other.customerId == customerId &&
        other.principalCents == principalCents &&
        other.balanceCents == balanceCents &&
        other.status == status &&
        other.dueDate == dueDate &&
        other.createdAt == createdAt &&
        other.settledAt == settledAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        shopId,
        customerId,
        principalCents,
        balanceCents,
        status,
        dueDate,
        createdAt,
        settledAt,
      );
}
