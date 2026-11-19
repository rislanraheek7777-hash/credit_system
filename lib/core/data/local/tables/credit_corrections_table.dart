import 'package:drift/drift.dart';

import 'app_users_table.dart';
import 'credits_table.dart';
import 'payments_table.dart';
import 'shops_table.dart';

/// Local SQLite schema for credit payment correction requests (Story 5.5).
///
/// Stores correction requests raised by authorized counter staff and decided
/// solely by the Shop Owner. Every row is scoped to a shop tenant and linked
/// to the affected credit and (optionally) the original erroneous payment.
///
/// The original payment record is never overwritten or deleted. A correction
/// request records:
/// - the requested adjustment amount in minor units (`correctionAmountCents`),
/// - a mandatory non-empty business explanation (`reason`),
/// - the request lifecycle status (`pending_approval`, `approved`, `rejected`),
/// - Shop Owner review metadata (`reviewedByUserId`, `reviewedAt`),
/// - a mandatory rejection reason when the status is `rejected`,
/// - the resulting credit balance after an approved adjustment
///   (`resultingBalanceCents`, a snapshot for audit; set only at approval).
///
/// Binds: PRD FR-6, FR-22, FR-23, FR-31; AD-1 (tenant isolation);
/// AD-2 (integer minor units); Story 5.3 (correction lock).
///
/// NOTE (Story 5.6): For payment-correction reversals the exact meaning of
/// `correctionAmountCents` (full original payment vs. excess only) is open;
/// the `direction` column always resolves which way the approved adjustment
/// moves the balance (`debit` increases it, `credit` decreases it).
@DataClassName('CreditCorrectionEntry')
@TableIndex(name: 'idx_credit_corrections_shop_id', columns: {#shopId})
@TableIndex(name: 'idx_credit_corrections_shop_status', columns: {#shopId, #status})
@TableIndex(name: 'idx_credit_corrections_shop_credit', columns: {#shopId, #creditId})
@TableIndex(name: 'idx_credit_corrections_shop_payment', columns: {#shopId, #originalPaymentId})
class CreditCorrections extends Table {
  /// Canonical UUIDv4 primary key.
  TextColumn get id => text()();

  /// Tenant shop association (immutable foreign key boundary).
  TextColumn get shopId =>
      text().references(Shops, #id, onDelete: KeyAction.restrict)();

  /// Associated credit agreement (immutable foreign key boundary).
  TextColumn get creditId =>
      text().references(Credits, #id, onDelete: KeyAction.restrict)();

  /// Original erroneous payment being corrected (nullable to also support
  /// Shop Owner manual balance adjustments that do not reference a payment).
  TextColumn get originalPaymentId =>
      text().nullable().references(Payments, #id, onDelete: KeyAction.restrict)();

  /// User UUID of the counter staff member who submitted the correction request.
  @ReferenceName('requestedCorrections')
  TextColumn get requestedByUserId =>
      text().references(AppUsers, #id, onDelete: KeyAction.restrict)();

  /// Requested adjustment amount in minor units (cents), strictly positive.
  ///
  /// The direction of the balance movement is recorded explicitly in
  /// [direction] (resolved by Story 5.6; the Story 5.5 open decision about the
  /// meaning of this amount is closed for adjustments).
  IntColumn get correctionAmountCents => integer()();

  /// Direction the approved adjustment moves the credit balance.
  ///
  /// - `debit`: increases the outstanding balance (a payment-reversal
  ///   correction, or an owner/staff proposal to charge more, e.g. an
  ///   undercharge).
  /// - `credit`: decreases the outstanding balance (a partial forgiveness
  ///   write-down requested because the customer cannot pay in full).
  ///
  /// Legacy rows default to `debit`, preserving the pre-Story-5.6 behaviour
  /// where approval applied `balance += amount`.
  TextColumn get direction => text().withDefault(const Constant('debit'))();

  /// Mandatory, non-empty business explanation for the correction.
  TextColumn get reason => text().withLength(min: 1)();

  /// Lifecycle status of the correction request.
  ///
  /// - `pending_approval`: Awaiting Shop Owner decision; the correction lock
  ///   is active on the credit and new payments are blocked.
  /// - `approved`: Approved by Shop Owner; the compensating adjustment has
  ///   been applied and the lock is lifted.
  /// - `rejected`: Rejected by Shop Owner; the balance is unchanged and the
  ///   lock is lifted.
  TextColumn get status =>
      text().withDefault(const Constant('pending_approval'))();

  /// User UUID of the Shop Owner who approved or rejected the request
  /// (null while pending).
  @ReferenceName('reviewedCorrections')
  TextColumn get reviewedByUserId =>
      text().nullable().references(AppUsers, #id, onDelete: KeyAction.restrict)();

  /// UTC timestamp of the Shop Owner's decision (null while pending).
  DateTimeColumn get reviewedAt => dateTime().nullable()();

  /// Mandatory rejection reason, required when [status] is `rejected`.
  /// Empty/null for `pending_approval` and `approved`.
  TextColumn get rejectionReason => text().nullable()();

  /// Resulting credit balance in minor units after an approved adjustment.
  ///
  /// Snapshot recorded at approval for audit. Null while the request is
  /// pending or rejected (rejection leaves the balance unchanged).
  IntColumn get resultingBalanceCents => integer().nullable()();

  /// UTC timestamp when the request was initiated.
  DateTimeColumn get createdAt => dateTime()();

  /// UTC timestamp of the last status change.
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (correction_amount_cents > 0)',
    "CHECK (direction IN ('debit', 'credit'))",
    "CHECK (status IN ('pending_approval', 'approved', 'rejected'))",
    // A mandatory non-empty business explanation is required to request a
    // correction (Story 5.5 AC-1).
    'CHECK (length(trim(reason)) > 0)',
    // Rejection requires a mandatory reason; approval/review require a
    // reviewer and a decision timestamp.
    "CHECK (status <> 'rejected' OR (rejection_reason IS NOT NULL AND length(trim(rejection_reason)) > 0))",
    "CHECK (status <> 'approved' OR (reviewed_by_user_id IS NOT NULL AND reviewed_at IS NOT NULL))",
    "CHECK (status <> 'rejected' OR (reviewed_by_user_id IS NOT NULL AND reviewed_at IS NOT NULL))",
    // A non-null resulting balance must be non-negative.
    'CHECK (resulting_balance_cents IS NULL OR resulting_balance_cents >= 0)',
  ];
}

