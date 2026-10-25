import 'package:meta/meta.dart';

/// Structured resolution types for overdue loan cases (Story 6.4, FR-28).
enum LoanResolutionType {
  underReview('under_review', 'Under Review'),
  ownerSettledWrittenOff('owner_settled_written_off', 'Owner Settled / Written Off'),
  collateralRetained('collateral_retained', 'Collateral Retained / Legal Dispute');

  final String value;
  final String displayName;
  const LoanResolutionType(this.value, this.displayName);

  static LoanResolutionType fromValue(String value) {
    for (final type in LoanResolutionType.values) {
      if (type.value == value) return type;
    }
    throw ArgumentError.value(value, 'value', 'Invalid LoanResolutionType representation');
  }
}

/// Clean architecture domain model representing an administrative overdue loan case resolution (Story 6.4, FR-28).
@immutable
class LoanResolution {
  final String id;
  final String shopId;
  final String loanId;
  final LoanResolutionType resolutionType;
  final String reason;
  final String resolvedByUserId;
  final DateTime createdAt;

  LoanResolution({
    required this.id,
    required this.shopId,
    required this.loanId,
    required this.resolutionType,
    required this.reason,
    required this.resolvedByUserId,
    required DateTime createdAt,
  }) : createdAt = createdAt.toUtc() {
    if (reason.trim().isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'Reason cannot be empty');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoanResolution &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          shopId == other.shopId &&
          loanId == other.loanId &&
          resolutionType == other.resolutionType &&
          reason == other.reason &&
          resolvedByUserId == other.resolvedByUserId &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        shopId,
        loanId,
        resolutionType,
        reason,
        resolvedByUserId,
        createdAt,
      );
}
