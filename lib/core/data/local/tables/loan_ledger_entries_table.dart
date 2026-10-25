import 'package:drift/drift.dart';

import 'app_users_table.dart';
import 'loan_corrections_table.dart';
import 'loans_table.dart';
import 'payments_table.dart';
import 'shops_table.dart';

/// Local SQLite schema for immutable financial ledger entries (Story 5.5).
///
/// Records compensating debit entries and controlled manual balance
/// adjustments linked to a loan. Every entry is scoped to a shop tenant and
/// references the loan it affects and (when applicable) the original payment
/// or correction request it relates to.
///
/// The original payment record is never overwritten or deleted; a ledger
/// entry is a separate, append-only compensating record (PRD FR-22, FR-24).
///
/// Binds: PRD FR-22 (double-entry arithmetic, controlled adjustments),
/// FR-24 (immutable history); AD-1 (tenant isolation); AD-2 (integer minor
/// units); Story 5.5 AC-3 (compensating debit on approved reversal).
///
/// NOTE (scope): Manual balance adjustments (`adjustment_debit`,
/// `adjustment_credit`) share the same entry type vocabulary but their own
/// request/approval flow is not part of the core correction workflow. The
/// table is modeled to support them once their business rules are approved.
@DataClassName('LoanLedgerEntryEntry')
@TableIndex(name: 'idx_ledger_entries_shop_id', columns: {#shopId})
@TableIndex(name: 'idx_ledger_entries_shop_loan', columns: {#shopId, #loanId})
@TableIndex(name: 'idx_ledger_entries_shop_entry_type',
    columns: {#shopId, #entryType})
@TableIndex(name: 'idx_ledger_entries_shop_correction',
    columns: {#shopId, #correctionId})
class LoanLedgerEntries extends Table {
  /// Canonical UUIDv4 primary key.
  TextColumn get id => text()();

  /// Tenant shop association (immutable foreign key boundary).
  TextColumn get shopId =>
      text().references(Shops, #id, onDelete: KeyAction.restrict)();

  /// Associated loan agreement (immutable foreign key boundary).
  TextColumn get loanId =>
      text().references(Loans, #id, onDelete: KeyAction.restrict)();

  /// Original erroneous payment being corrected (nullable for manual
  /// adjustments that do not reference a payment).
  TextColumn get originalPaymentId =>
      text().nullable().references(Payments, #id, onDelete: KeyAction.restrict)();

  /// Correction request this entry implements (nullable for manual
  /// adjustments not triggered by a correction request).
  @ReferenceName('ledgerEntriesForCorrection')
  TextColumn get correctionId =>
      text().nullable().references(LoanCorrections, #id, onDelete: KeyAction.restrict)();

  /// Kind of ledger entry:
  /// - `compensating_debit`: Reverses an erroneous confirmed payment; adds
  ///   the reversed amount back to the outstanding balance.
  /// - `adjustment_debit`: Manual balance increase (Shop Owner only).
  /// - `adjustment_credit`: Manual balance decrease (Shop Owner only).
  TextColumn get entryType => text()();

  /// Adjustment amount in minor units (cents), strictly positive.
  IntColumn get amountCents => integer()();

  /// Outstanding balance in minor units before this entry was applied.
  IntColumn get preBalanceCents => integer()();

  /// Outstanding balance in minor units after this entry was applied.
  IntColumn get postBalanceCents => integer()();

  /// Mandatory, non-empty business rationale for the entry.
  TextColumn get reason => text().withLength(min: 1)();

  /// User UUID of the Shop Owner who recorded the entry.
  @ReferenceName('ledgerEntriesByUser')
  TextColumn get recordedByUserId =>
      text().references(AppUsers, #id, onDelete: KeyAction.restrict)();

  /// UTC timestamp when the entry was recorded.
  DateTimeColumn get recordedAt => dateTime()();

  /// UTC creation timestamp.
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (amount_cents > 0)',
    "CHECK (entry_type IN ('compensating_debit', 'adjustment_debit', 'adjustment_credit'))",
    'CHECK (pre_balance_cents >= 0)',
    'CHECK (post_balance_cents >= 0)',
    'CHECK (length(trim(reason)) > 0)',
    // A credit adjustment cannot reduce the balance below zero.
    "CHECK (entry_type <> 'adjustment_credit' OR pre_balance_cents >= amount_cents)",
  ];
}
