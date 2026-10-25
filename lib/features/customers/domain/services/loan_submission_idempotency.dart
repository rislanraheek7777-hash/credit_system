import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

/// A canonical fingerprint of a loan submission's *substance*.
///
/// Two submissions share a fingerprint only when they would create the same
/// loan agreement: the same borrower, the same principal, the same selected
/// due date, and the same pledged collateral set. The fingerprint is what
/// lets the idempotency layer distinguish
///
/// - a **retry of the same submission** (same fingerprint → reuse the key), from
/// - a **new submission** (different fingerprint → issue a fresh key).
///
/// F3 (Story 4.2): "Never reuse a key for a different customer, principal
/// amount, or new submission. Do not generate a new key for every
/// network/database retry of an unchanged submission."
@immutable
class LoanSubmissionFingerprint {
  /// The borrower the agreement is for.
  final String customerId;

  /// The agreed principal in integer minor units.
  final int principalCents;

  /// The selected preliminary due date (UTC instant).
  final DateTime dueDate;

  /// The pledged collateral item identifiers.
  final List<String> collateralItemIds;

  LoanSubmissionFingerprint({
    required this.customerId,
    required this.principalCents,
    required this.dueDate,
    required List<String> collateralItemIds,
  }) : collateralItemIds = List.unmodifiable(
          // Sorted so that selection order does not change the fingerprint.
          [...collateralItemIds]..sort(),
        );

  /// The canonical string form used for comparison.
  String get canonical {
    final buffer = StringBuffer()
      ..write(customerId)
      ..write('|')
      ..write(principalCents)
      ..write('|')
      ..write(dueDate.toUtc().toIso8601String())
      ..write('|')
      ..write(collateralItemIds.join(','));
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is LoanSubmissionFingerprint && other.canonical == canonical;

  @override
  int get hashCode => canonical.hashCode;

  @override
  String toString() => 'LoanSubmissionFingerprint($canonical)';
}

/// Manages the idempotency key lifecycle for the loan origination form
/// (Story 4.2, F3).
///
/// The key is bound to the *substance* of the current submission:
///
/// - The first submission of a given fingerprint issues a fresh UUIDv4 key.
/// - Any further attempt with the **same** fingerprint reuses that key, so a
///   double-click, a network retry, or a transient database error cannot
///   create a second loan agreement.
/// - A submission whose fingerprint **changed** (different customer, different
///   principal, different due date, different collateral set) issues a fresh
///   key, so a new agreement is never conflated with a retry of the previous
///   one.
/// - [reset] is called after a successful agreement so that the next
///   submission starts from a clean slate.
class LoanSubmissionIdempotency {
  final Uuid _uuid;

  String? _key;
  String? _boundFingerprint;

  LoanSubmissionIdempotency({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  /// The key currently bound to a submission, or `null` when none has been
  /// issued yet.
  String? get currentKey => _key;

  /// The fingerprint the current key is bound to, or `null`.
  String? get boundFingerprint => _boundFingerprint;

  /// Returns the idempotency key to use for a submission with [fingerprint].
  ///
  /// Reuses the existing key when [fingerprint] matches the submission the
  /// key was issued for; otherwise issues a fresh UUIDv4 key.
  String keyFor(LoanSubmissionFingerprint fingerprint) {
    final canonical = fingerprint.canonical;
    final existing = _key;
    if (existing != null && _boundFingerprint == canonical) {
      return existing;
    }
    final fresh = _uuid.v4();
    _key = fresh;
    _boundFingerprint = canonical;
    return fresh;
  }

  /// Clears the current key, e.g. after a successful agreement submission.
  void reset() {
    _key = null;
    _boundFingerprint = null;
  }
}
