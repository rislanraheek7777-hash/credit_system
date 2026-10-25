import 'package:meta/meta.dart';

/// Clean architecture domain model representing an official due date extension (Story 6.2, FR-26).
@immutable
class DueDateExtension {
  final String id;
  final String shopId;
  final String loanId;
  final DateTime previousDueDate;
  final DateTime newDueDate;
  final String reason;
  final String grantedByUserId;
  final DateTime createdAt;

  DueDateExtension({
    required this.id,
    required this.shopId,
    required this.loanId,
    required DateTime previousDueDate,
    required DateTime newDueDate,
    required this.reason,
    required this.grantedByUserId,
    required DateTime createdAt,
  })  : previousDueDate = previousDueDate.toUtc(),
        newDueDate = newDueDate.toUtc(),
        createdAt = createdAt.toUtc() {
    if (reason.trim().isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'Reason cannot be empty');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DueDateExtension &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          shopId == other.shopId &&
          loanId == other.loanId &&
          previousDueDate == other.previousDueDate &&
          newDueDate == other.newDueDate &&
          reason == other.reason &&
          grantedByUserId == other.grantedByUserId &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        shopId,
        loanId,
        previousDueDate,
        newDueDate,
        reason,
        grantedByUserId,
        createdAt,
      );
}
