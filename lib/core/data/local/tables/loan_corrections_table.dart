import 'package:drift/drift.dart';

import 'app_users_table.dart';
import 'loans_table.dart';
import 'payments_table.dart';
import 'shops_table.dart';

/// Local SQLite schema for loan payment correction requests (Story 5.5).
///
/// Stores correction requests raised by authorized counter staff and decided
/// solely by the Shop Owner. Every row is scoped to a shop tenant and linked
/// to the affected loan and (optionally) the original erroneous payment.
///
/// The original payment record is never overwritten or deleted. A correction
/// request records:
/// - the requested adjustment amount in minor units (`correctionAmountCents`),
/// - a mandatory non-empty business explanation (`reason`),
/// - the request lifecycle status (`pending_approval`, `approved`, `rejected`),
/// - Shop Owner review metadata (`reviewedByUserId`, `reviewedAt`),
/// - a mandatory rejection reason when the status is `rejected`,
/// - the resulting loan balance after an approved adjustment
///   (`resultingBalanceCents`, a snapshot for audit; set only at approval).
///
/// Binds: PRD FR-6, FR-22, FR-23, FR-31; AD-1 (tenant isolation);
/// AD-2 (integer minor units); Story 5.3 (correction lock).
///
/// NOTE (accounting decision pending): The exact business-rule semantics of
/// `correctionAmountCents` — whether it represents the full original payment
/// amount or only the excess over the correct amount — has not been approved.
/// No compensating financial ledger entry is posted outside this table until
/// that decision is made. See the Story 5.5 open-decisions record.
@DataClassName('LoanCorrectionEntry')
@TableIndex(name: 'idx_loan_corrections_shop_id', columns: {#shopId})
@TableIndex(name: 'idx_loan_corrections_shop_status', columns: {#shopId, #status})
@TableIndex(name: 'idx_loan_corrections_shop_loan', columns: {#shopId, #loanId})
@TableIndex(name: 'idx_loan_corrections_shop_payment', columns: {#shopId, #originalPaymentId})
class LoanCorrections extends Table {
  /// Canonical UUIDv4 primary key.
  TextColumn get id => text()();

  /// Tenant shop association (immutable foreign key boundary).
  TextColumn get shopId =>
      text().references(Shops, #id, onDelete: KeyAction.restrict)();

  /// Associated loan agreement (immutable foreign key boundary).
  TextColumn get loanId =>
      text().references(Loans, #id, onDelete: KeyAction.restrict)();

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
  /// Recorded explicitly; the precise business-rule meaning (full original
  /// payment vs. excess only) is an open accounting decision.
  IntColumn get correctionAmountCents => integer()();

  /// Mandatory, non-empty business explanation for the correction.
  TextColumn get reason => text().withLength(min: 1)();

  /// Lifecycle status of the correction request.
  ///
  /// - `pending_approval`: Awaiting Shop Owner decision; the correction lock
  ///   is active on the loan and new payments are blocked.
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

  /// Resulting loan balance in minor units after an approved adjustment.
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
