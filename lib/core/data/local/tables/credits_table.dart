import 'package:drift/drift.dart';

import 'app_users_table.dart';
import 'customers_table.dart';
import 'shops_table.dart';

/// Local SQLite schema for credit agreements (Story 2.5).
///
/// Stores zero-interest credit agreements scoped to a shop tenant,
/// linked to a customer borrower. Credit lifecycle status is stored
/// as text and enforced by a CHECK constraint.
///
/// Binds: PRD FR-11; AD-1 (tenant isolation).
@DataClassName('CreditEntry')
@TableIndex(name: 'idx_credits_shop_id', columns: {#shopId})
@TableIndex(name: 'idx_credits_shop_customer', columns: {#shopId, #customerId})
@TableIndex(name: 'idx_credits_shop_status', columns: {#shopId, #status})
@TableIndex(
  name: 'idx_credits_shop_customer_status',
  columns: {#shopId, #customerId, #status},
)
class Credits extends Table {
  /// Canonical UUIDv4 primary key.
  TextColumn get id => text()();

  /// Tenant shop association (immutable foreign key boundary).
  TextColumn get shopId =>
      text().references(Shops, #id, onDelete: KeyAction.restrict)();

  /// Associated customer borrower (immutable foreign key boundary).
  IntColumn get customerId => integer().references(Customers, #id, onDelete: KeyAction.restrict)();

  /// Original principal in minor units (cents).
  IntColumn get principalCents => integer()();

  /// Outstanding balance in minor units (cents).
  IntColumn get balanceCents => integer()();

  /// Lifecycle status: 'active', 'overdue', 'settled', 'cancelled'.
  TextColumn get status => text().withDefault(const Constant('active'))();

  /// Workflow status: 'pending_disbursement', 'disbursed', 'cancelled'.
  TextColumn get workflowStatus =>
      text().withDefault(const Constant('pending_disbursement'))();

  /// The agreed standard term in calendar days (30, 60 or 90).
  ///
  /// Null when a custom calendar due date was agreed instead. Persisted at
  /// origination because the *official* due date is finalised at disbursement
  /// from the agreed term and the confirmed disbursement date (Story 4.3,
  /// PRD FR-19).
  IntColumn get termPresetDays => integer().nullable()();

  /// The agreed custom calendar due date.
  ///
  /// Stored as the UTC instant of local midnight of that calendar date in the
  /// shop's operational time zone. Null when a standard preset term was
  /// agreed (Story 4.3).
  DateTimeColumn get customDueDate => dateTime().nullable()();

  /// UTC timestamp of the confirmed physical cash handover.
  ///
  /// Null until cash is disbursed. Cash-out reporting considers only credits
  /// with a confirmed disbursement (PRD FR-19).
  DateTimeColumn get disbursedAt => dateTime().nullable()();

  /// User UUID of the staff member who confirmed the cash handover.
  TextColumn get disbursedByUserId => text().nullable().references(
    AppUsers,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// UTC timestamp of the cancellation of an undisbursed agreement.
  DateTimeColumn get cancelledAt => dateTime().nullable()();

  /// Mandatory reason recorded when an undisbursed agreement is cancelled.
  TextColumn get cancellationReason => text().nullable()();

  /// Official due date timestamp.
  DateTimeColumn get dueDate => dateTime()();

  /// UTC creation timestamp.
  DateTimeColumn get createdAt => dateTime()();

  /// UTC settlement timestamp (null while not settled).
  DateTimeColumn get settledAt => dateTime().nullable()();

  /// Correction-pending flag. When true, payments on this credit are blocked
  /// until a Shop Owner approves or rejects the pending correction
  /// (Story 5.3 AC-3, Story 5.5).
  BoolColumn get correctionPending => boolean().withDefault(const Constant(false))();

  /// Type of the credit agreement: 'cash' (monetary amount only) or 'items'
  /// (amount plus one or more item receipts attached at origination).
  ///
  /// Set once at origination and never reclassified afterwards.
  TextColumn get creditType =>
      text().withDefault(const Constant('cash'))();

  /// Document snapshot identifier, set at disbursement time.
  ///
  /// The current Story 4.4 scaffold stores only this identifier. It does not
  /// persist the branding, customer, credit, or collateral content required to
  /// reproduce a previously issued document, so this column must not be treated
  /// as proof of immutable content. Full snapshot persistence remains pending
  /// decision D4.4-03.
  TextColumn get documentSnapshotId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (principal_cents >= 0)",
    "CHECK (balance_cents >= 0)",
    "CHECK (balance_cents <= principal_cents)",
    "CHECK (status IN ('active', 'overdue', 'settled', 'cancelled'))",
    "CHECK (status <> 'settled' OR settled_at IS NOT NULL)",
    "CHECK (status <> 'cancelled' OR (cancelled_at IS NOT NULL AND cancellation_reason IS NOT NULL AND length(trim(cancellation_reason)) > 0))",
    "CHECK (workflow_status IN ('pending_disbursement', 'disbursed', 'cancelled', 'overdue'))",
    "CHECK (term_preset_days IS NULL OR term_preset_days IN (30, 60, 90))",
    "CHECK (NOT (term_preset_days IS NOT NULL AND custom_due_date IS NOT NULL))",
    // A disbursement record is all-or-nothing. Credits that predate the
    // disbursement workflow (backfilled to 'disbursed' by the v12 migration)
    // legitimately carry no record, so the "disbursed implies a record" rule is
    // enforced by the operation layer rather than here.
    "CHECK ((disbursed_at IS NULL) = (disbursed_by_user_id IS NULL))",
    // Tier 1 cross-field invariants (v14 migration, Phase 2). These enforce
    // the cancelled/settled state machine at the persistence boundary, not
    // solely through Dart assert statements (which are stripped in release).
    "CHECK (status <> 'cancelled' OR workflow_status = 'cancelled')",
    "CHECK (status <> 'cancelled' OR disbursed_at IS NULL)",
    "CHECK (status <> 'cancelled' OR disbursed_by_user_id IS NULL)",
    "CHECK (status <> 'settled' OR workflow_status = 'disbursed')",
    "CHECK (status = 'cancelled' OR (cancelled_at IS NULL AND (cancellation_reason IS NULL OR length(trim(cancellation_reason)) = 0)))",
    "CHECK (credit_type IN ('cash', 'items'))",
    "CHECK (status = 'settled' OR settled_at IS NULL)",
  ];
}

