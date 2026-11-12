import 'package:meta/meta.dart';

/// Structured resolution types for overdue credit cases (Story 6.4, FR-28).
enum CreditResolutionType {
  underReview('under_review', 'Under Review'),
  ownerSettledWrittenOff('owner_settled_written_off', 'Owner Settled / Written Off'),
  collateralRetained('collateral_retained', 'Collateral Retained / Legal Dispute');

  final String value;
  final String displayName;
  const CreditResolutionType(this.value, this.displayName);

  static CreditResolutionType fromValue(String value) {
    for (final type in CreditResolutionType.values) {
      if (type.value == value) return type;
    }
    throw ArgumentError.value(value, 'value', 'Invalid CreditResolutionType representation');
  }
}

/// Clean architecture domain model representing an administrative overdue credit case resolution (Story 6.4, FR-28).
@immutable
class CreditResolution {
  final String id;
  final String shopId;
  final String creditId;
  final CreditResolutionType resolutionType;
  final String reason;
  final String resolvedByUserId;
  final DateTime createdAt;

  CreditResolution({
    required this.id,
    required this.shopId,
    required this.creditId,
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
      other is CreditResolution &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          shopId == other.shopId &&
          creditId == other.creditId &&
          resolutionType == other.resolutionType &&
          reason == other.reason &&
          resolvedByUserId == other.resolvedByUserId &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        shopId,
        creditId,
        resolutionType,
        reason,
        resolvedByUserId,
        createdAt,
      );
}

