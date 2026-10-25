import 'dart:convert';

import 'package:meta/meta.dart';

/// Clean architecture domain model representing a loan-level administrative
/// closure with collateral exception (Story 3.5, PRD FR-16, AD-3).
///
/// When a settled loan has collateral items permanently stuck in
/// `exceptionHeld` custody, the Shop Owner may administratively close the
/// loan's collateral account. This record captures the closure decision,
/// the owner's mandatory sign-off reason, and the list of exception-held
/// item IDs at the time of closure.
///
/// Items remain in `exceptionHeld` — no custody status change occurs.
/// The loan's overall workflow status is *derived dynamically*: if this
/// record exists for a settled loan, the UI displays "Closed (Collateral
/// Exception)" instead of the raw workflow status.
@immutable
class LoanAdministrativeClosure {
  final String id;
  final String shopId;
  final String loanId;
  final String reason;
  final String closedByUserId;

  /// The collateral item UUIDs that were in `exceptionHeld` at closure time.
  final List<String> itemIds;

  final DateTime createdAt;

  LoanAdministrativeClosure({
    required this.id,
    required this.shopId,
    required this.loanId,
    required this.reason,
    required this.closedByUserId,
    required this.itemIds,
    required DateTime createdAt,
  }) : createdAt = createdAt.toUtc() {
    if (reason.trim().isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'Reason cannot be empty');
    }
    if (itemIds.isEmpty) {
      throw ArgumentError.value(
        itemIds,
        'itemIds',
        'At least one exception-held item ID is required',
      );
    }
  }

  /// Serializes [itemIds] to a JSON string for persistence.
  String get itemIdsJson => jsonEncode(itemIds);

  /// Deserializes a JSON string to a list of item IDs.
  static List<String> parseItemIdsJson(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! List) {
      throw FormatException(
        'Expected a JSON array for itemIdsJson, got: $json',
      );
    }
    return decoded.cast<String>();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoanAdministrativeClosure &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          shopId == other.shopId &&
          loanId == other.loanId &&
          reason == other.reason &&
          closedByUserId == other.closedByUserId &&
          _listEquals(itemIds, other.itemIds) &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        shopId,
        loanId,
        reason,
        closedByUserId,
        Object.hashAll(itemIds),
        createdAt,
      );

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
