import 'package:meta/meta.dart';

/// Communication channel for delinquency follow-ups (Story 6.3, FR-27).
enum FollowUpChannel {
  phoneCall('phone_call', 'Phone Call'),
  inPerson('in_person', 'In-Person Counter Visit'),
  physicalNotice('physical_notice', 'Physical Notice');

  final String value;
  final String displayName;
  const FollowUpChannel(this.value, this.displayName);

  static FollowUpChannel fromValue(String value) {
    for (final channel in FollowUpChannel.values) {
      if (channel.value == value) return channel;
    }
    throw ArgumentError.value(value, 'value', 'Invalid FollowUpChannel representation');
  }
}

/// Clean architecture domain model representing a customer follow-up entry (Story 6.3, FR-27).
@immutable
class CustomerFollowUp {
  final String id;
  final String shopId;
  final String loanId;
  final String customerId;
  final String staffId;
  final FollowUpChannel channel;
  final String notes;
  final DateTime? promisedPaymentDate;
  final DateTime createdAt;

  CustomerFollowUp({
    required this.id,
    required this.shopId,
    required this.loanId,
    required this.customerId,
    required this.staffId,
    required this.channel,
    required this.notes,
    DateTime? promisedPaymentDate,
    required DateTime createdAt,
  })  : promisedPaymentDate = promisedPaymentDate?.toUtc(),
        createdAt = createdAt.toUtc() {
    if (notes.trim().isEmpty) {
      throw ArgumentError.value(notes, 'notes', 'Notes cannot be empty');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomerFollowUp &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          shopId == other.shopId &&
          loanId == other.loanId &&
          customerId == other.customerId &&
          staffId == other.staffId &&
          channel == other.channel &&
          notes == other.notes &&
          promisedPaymentDate == other.promisedPaymentDate &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        shopId,
        loanId,
        customerId,
        staffId,
        channel,
        notes,
        promisedPaymentDate,
        createdAt,
      );
}
