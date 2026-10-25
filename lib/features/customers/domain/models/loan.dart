import 'package:meta/meta.dart';

import 'loan_term.dart';

/// Validation exception thrown when loan invariants are violated.
class LoanValidationException extends ArgumentError {
  LoanValidationException(super.message);
}

/// Exception thrown when a payment is submitted against a loan that has not
/// yet had cash disbursed (Story 4.1, PRD FR-19).
///
/// A loan agreement and its cash disbursement are deliberately decoupled: a
/// freshly originated agreement is `Active / Pending Disbursement`, and the
/// customer's repayment obligation does not begin until cash actually changes
/// hands. Payments on an undisbursed loan are therefore rejected outright.
class LoanPaymentBlockedException implements Exception {
  /// Human-readable reason the payment was refused.
  final String message;

  const LoanPaymentBlockedException([
    this.message = 'Payments cannot be accepted on undisbursed loans.',
  ]);

  @override
  String toString() => 'LoanPaymentBlockedException: $message';
}

/// Exception thrown when a payment is submitted against a loan that has a
/// pending correction request (Story 5.3 AC-3, Story 5.5).
///
/// Payments are blocked until a Shop Owner approves or rejects the pending
/// correction. The lock is enforced inside the payment transaction.
class LoanCorrectionPendingException implements Exception {
  /// Human-readable reason the payment was refused.
  final String message;

  const LoanCorrectionPendingException([
    this.message =
        'Payments cannot be recorded while a correction is pending on this loan.',
  ]);

  @override
  String toString() => 'LoanCorrectionPendingException: $message';
}

/// Exception thrown when a cash disbursement confirmation is attempted on a
/// loan that is not awaiting disbursement (Story 4.3, PRD FR-19).
///
/// A loan that has already been disbursed — or that was cancelled — must never
/// be disbursed a second time.
class LoanDisbursementStateException implements Exception {
  /// Human-readable reason the confirmation was refused.
  final String message;
  const LoanDisbursementStateException(this.message);
  @override
  String toString() => 'LoanDisbursementStateException: $message';
}

/// Exception thrown when a cancellation is attempted on a loan that is not
/// awaiting disbursement (Story 4.3, PRD FR-19, AC-4).
///
/// Only agreements still in `Pending Disbursement` may be cancelled.
class LoanCancellationStateException implements Exception {
  final String message;
  const LoanCancellationStateException(this.message);
  @override
  String toString() => 'LoanCancellationStateException: $message';
}

/// Exception thrown when an overdue transition is attempted on a loan that
/// is not eligible (Story 6.1, PRD FR-25).
///
/// A loan may only transition to overdue when it is disbursed, has a positive
/// outstanding balance, is not settled, and its due date has passed in the
/// shop's local time zone.
class LoanOverdueStateException implements Exception {
  final String message;
  const LoanOverdueStateException(this.message);
  @override
  String toString() => 'LoanOverdueStateException: $message';
}

/// Exception thrown when a re-agreement of the loan term is attempted on a
/// loan that is not awaiting disbursement (Story 4.3, T6).
class LoanTermReagreementException implements Exception {
  final String message;
  const LoanTermReagreementException(this.message);
  @override
  String toString() => 'LoanTermReagreementException: $message';
}


/// Status of a loan agreement.
///
/// Story 2.5 displays the stored status; automated overdue evaluation
/// is owned by Story 6.1 and is intentionally out of scope here.
enum LoanStatus {
  /// Loan is active and within its term.
  active('active'),

  /// Loan is past its due date with an outstanding balance.
  overdue('overdue'),

  /// Loan has been fully settled.
  settled('settled'),

  /// Loan agreement was cancelled before cash was disbursed (Story 4.3).
  cancelled('cancelled');

  final String value;
  const LoanStatus(this.value);

  /// Resolves [LoanStatus] from raw database text.
  static LoanStatus fromValue(String value) {
    for (final status in LoanStatus.values) {
      if (status.value == value) {
        return status;
      }
    }
    throw ArgumentError.value(value, 'value', 'Invalid LoanStatus string representation');
  }
}

/// Workflow status of a loan agreement (Story 4.1).
///
/// Tracks the disbursement workflow state independently from the financial
/// [LoanStatus]. A loan is created with `pending_disbursement` and transitions
/// to `disbursed` upon confirmed cash disbursement (Story 4.3).
enum LoanWorkflowStatus {
  /// Loan agreement has been created but cash has not yet been disbursed.
  pendingDisbursement('pending_disbursement'),

  /// Cash has been disbursed and confirmed; the loan is fully active.
  disbursed('disbursed'),

  /// The agreement was cancelled before cash was disbursed (Story 4.3).
  cancelled('cancelled'),

  /// The loan is past its due date with an outstanding balance (Story 6.1).
  overdue('overdue');

  final String value;
  const LoanWorkflowStatus(this.value);

  /// Resolves [LoanWorkflowStatus] from raw database text.
  static LoanWorkflowStatus fromValue(String value) {
    for (final status in LoanWorkflowStatus.values) {
      if (status.value == value) {
        return status;
      }
    }
    throw ArgumentError.value(value, 'value', 'Invalid LoanWorkflowStatus string representation');
  }
}

/// Clean architecture domain entity representing a loan agreement (Story 2.5).
///
/// Money is stored in integer minor units (cents) — never as floating point.
@immutable
class Loan {
  /// Canonical UUID primary key.
  final String id;

  /// Associated shop tenant boundary.
  final String shopId;

  /// Associated customer borrower.
  final String customerId;

  /// Original principal in minor units (cents).
  final int principalCents;

  /// Outstanding balance in minor units (cents).
  final int balanceCents;

  /// Current lifecycle status (financial status).
  final LoanStatus status;

  /// Workflow status tracking the disbursement lifecycle independently from
  /// financial status. Created loans start as `pending_disbursement` and
  /// transition to `disbursed` upon confirmed cash disbursement (Story 4.3).
  final LoanWorkflowStatus workflowStatus;

  /// Official due date (UTC).
  final DateTime dueDate;

  /// UTC creation timestamp.
  final DateTime createdAt;

  /// UTC settlement timestamp (null while not settled).
  final DateTime? settledAt;

  /// The agreed standard term in calendar days (30, 60 or 90), or `null` when
  /// a custom calendar due date was agreed (Story 4.3).
  ///
  /// The agreed term is persisted at origination because the *official* due
  /// date is finalised at disbursement from the agreed term and the confirmed
  /// disbursement date — not from the preliminary due date (PRD FR-19).
  final int? termPresetDays;

  /// The agreed custom calendar due date, or `null` when a standard preset
  /// term was agreed (Story 4.3).
  ///
  /// Stored as the UTC instant of local midnight of that calendar date in the
  /// shop's operational time zone.
  final DateTime? customDueDate;

  /// UTC timestamp of the confirmed physical cash handover (null until cash
  /// is disbursed).
  final DateTime? disbursedAt;

  /// User UUID of the staff member who confirmed the cash handover (null
  /// until cash is disbursed).
  final String? disbursedByUserId;

  /// UTC timestamp of the cancellation of an undisbursed agreement (null
  /// while the agreement is live).
  final DateTime? cancelledAt;

  /// Mandatory reason recorded when an undisbursed agreement is cancelled.
  final String? cancellationReason;

  /// Correction-pending flag. When true, payments on this loan are blocked
  /// until a Shop Owner approves or rejects the pending correction
  /// (Story 5.3 AC-3, Story 5.5).
  final bool correctionPending;

  Loan({
    required this.id,
    required this.shopId,
    required this.customerId,
    required this.principalCents,
    required this.balanceCents,
    required this.status,
    this.workflowStatus = LoanWorkflowStatus.pendingDisbursement,
    required DateTime dueDate,
    required DateTime createdAt,
    DateTime? settledAt,
    this.termPresetDays,
    DateTime? customDueDate,
    DateTime? disbursedAt,
    this.disbursedByUserId,
    DateTime? cancelledAt,
    this.cancellationReason,
    this.correctionPending = false,
  })  : dueDate = DateTime.fromMillisecondsSinceEpoch(dueDate.millisecondsSinceEpoch, isUtc: true),
        createdAt = DateTime.fromMillisecondsSinceEpoch(createdAt.millisecondsSinceEpoch, isUtc: true),
        settledAt = settledAt != null
            ? DateTime.fromMillisecondsSinceEpoch(settledAt.millisecondsSinceEpoch, isUtc: true)
            : null,
        customDueDate = customDueDate != null
            ? DateTime.fromMillisecondsSinceEpoch(customDueDate.millisecondsSinceEpoch, isUtc: true)
            : null,
        disbursedAt = disbursedAt != null
            ? DateTime.fromMillisecondsSinceEpoch(disbursedAt.millisecondsSinceEpoch, isUtc: true)
            : null,
        cancelledAt = cancelledAt != null
            ? DateTime.fromMillisecondsSinceEpoch(cancelledAt.millisecondsSinceEpoch, isUtc: true)
            : null {
    // Runtime validation (replaces debug-only asserts; fires in all build modes).
    if (termPresetDays != null && ![30, 60, 90].contains(termPresetDays)) {
      throw LoanValidationException(
        'termPresetDays must be null or one of 30, 60, 90',
      );
    }
    if (principalCents < 0) {
      throw LoanValidationException('principalCents cannot be negative');
    }
    if (balanceCents < 0) {
      throw LoanValidationException('balanceCents cannot be negative');
    }
    if (balanceCents > principalCents) {
      throw LoanValidationException('balanceCents cannot exceed principalCents');
    }
    if (status == LoanStatus.settled && settledAt == null) {
      throw LoanValidationException('settled loans must have a settledAt timestamp');
    }
    if (status == LoanStatus.cancelled &&
        (cancelledAt == null ||
            (cancellationReason ?? '').trim().isEmpty)) {
      throw LoanValidationException(
        'cancelled loans must have a cancelledAt timestamp and a reason',
      );
    }
    if (termPresetDays != null && customDueDate != null) {
      throw LoanValidationException(
        'a loan agrees to either a preset term or a custom date, not both',
      );
    }
    if (status == LoanStatus.cancelled &&
        workflowStatus != LoanWorkflowStatus.cancelled) {
      throw LoanValidationException(
        'cancelled loans must have the cancelled workflow status',
      );
    }
    if (status == LoanStatus.cancelled && disbursedAt != null) {
      throw LoanValidationException(
        'cancelled loans must be undisbursed (disbursedAt must be null)',
      );
    }
    // D10 (cancelled ⇒ balanceCents == principalCents) deferred pending Q-1.
    if (status == LoanStatus.settled &&
        workflowStatus != LoanWorkflowStatus.disbursed) {
      throw LoanValidationException(
        'settled loans must have the disbursed workflow status',
      );
    }
  }

  /// Returns true if the loan is eligible for customer actions
  /// (payment, detail view, collateral return).
  ///
  /// A loan is actionable when it is financially active (or overdue) AND cash
  /// has been disbursed. Loans in `pending_disbursement` workflow status
  /// cannot accept payments (Story 4.1, PRD FR-19).
  bool get isActionable =>
      (status == LoanStatus.active || status == LoanStatus.overdue) &&
      workflowStatus == LoanWorkflowStatus.disbursed;

  /// Whether cash has been disbursed for this loan.
  ///
  /// A loan is only `disbursed` after Story 4.3 records a confirmed physical
  /// cash handover. Until then the agreement is `pending_disbursement`.
  bool get isDisbursed => workflowStatus == LoanWorkflowStatus.disbursed;

  /// Whether cash disbursement is still outstanding for this loan.
  bool get isPendingDisbursement =>
      workflowStatus == LoanWorkflowStatus.pendingDisbursement;

  /// The due date rendered as a calendar date in the shop's operational time
  /// zone.
  ///
  /// The due date is persisted as the UTC instant of **shop-local midnight**
  /// of the agreed calendar date. In a zone east of UTC that instant falls on
  /// the previous UTC day, so the calendar date must always be resolved in
  /// the shop's own zone. Reading the UTC calendar date of the stored instant
  /// would show a due date one day earlier than the date that was agreed
  /// (Story 4.3 AC-2, PRD FR-19).
  String dueDateAsCalendarDate(ShopTimeZone shopTimeZone) =>
      shopTimeZone.localDateOf(dueDate).isoDate;

  /// Whether this agreement was cancelled before cash was disbursed.
  bool get isCancelled =>
      status == LoanStatus.cancelled &&
      workflowStatus == LoanWorkflowStatus.cancelled;

  /// Whether this agreement is overdue: past due date with positive balance,
  /// and not yet settled.
  ///
  /// A loan is overdue when:
  /// - The calendar date has passed the due date in the shop's time zone
  /// - The outstanding balance is greater than zero
  /// - The loan is not settled
  ///
  /// Throws [UnsupportedShopTimeZoneException] if the shop's time zone cannot
  /// be resolved.
  bool isOverdue(ShopTimeZone shopTimeZone) {
    if (status == LoanStatus.settled) return false;
    if (balanceCents <= 0) return false;
    final today = shopTimeZone.localDateOf(DateTime.now().toUtc());
    final due = shopTimeZone.localDateOf(dueDate);
    return today.isAfter(due);
  }

  /// Whether cash has been confirmed as handed over to the borrower.
  bool get hasDisbursementRecord => disbursedAt != null;

  /// Asserts that this agreement may have its cash disbursement confirmed.
  ///
  /// A disbursement is only permitted while the agreement is `Pending
  /// Disbursement`. An already-disbursed or cancelled agreement is refused,
  /// which is what prevents a second disbursement (Story 4.3, PRD FR-19).
  ///
  /// Throws [LoanDisbursementStateException] when the agreement is not
  /// awaiting disbursement.
  void assertDisbursementAllowed() {
    if (!isPendingDisbursement) {
      throw LoanDisbursementStateException(
        'Loan $id is not awaiting disbursement (workflow status: '
        '${workflowStatus.value}). Cash disbursement confirmation is refused.',
      );
    }
  }

  /// Returns a copy of this loan with a confirmed cash disbursement applied.
  ///
  /// The financial status stays [LoanStatus.active] and the workflow status
  /// becomes [LoanWorkflowStatus.disbursed] (PRD FR-19). The [officialDueDate]
  /// replaces the preliminary due date that was stored at origination.
  ///
  /// Throws [LoanDisbursementStateException] when the agreement is not
  /// awaiting disbursement.
  Loan withDisbursement({
    required DateTime disbursedAt,
    required String disbursedByUserId,
    required DateTime officialDueDate,
  }) {
    assertDisbursementAllowed();
    return copyWith(
      status: LoanStatus.active,
      workflowStatus: LoanWorkflowStatus.disbursed,
      dueDate: officialDueDate,
      disbursedAt: disbursedAt,
      disbursedByUserId: disbursedByUserId,
    );
  }

  /// Returns a copy of this loan with an overdue status applied (Story 6.1).
  ///
  /// Transitions financial status and workflow status to `overdue`. Only
  /// permitted when:
  /// - The loan has been disbursed
  /// - The outstanding balance is greater than zero
  /// - The loan is not settled
  /// - The current date has passed the due date in the shop's time zone
  ///
  /// Throws [LoanOverdueStateException] when the loan is not eligible for
  /// overdue transition.
  Loan applyOverdue({required ShopTimeZone shopTimeZone}) {
    if (status == LoanStatus.settled) {
      throw LoanOverdueStateException(
        'Loan $id is settled and cannot transition to overdue.',
      );
    }
    if (balanceCents <= 0) {
      throw LoanOverdueStateException(
        'Loan $id has no outstanding balance and cannot transition to overdue.',
      );
    }
    if (!isDisbursed) {
      throw LoanOverdueStateException(
        'Loan $id has not been disbursed and cannot transition to overdue.',
      );
    }
    if (!isOverdue(shopTimeZone)) {
      throw LoanOverdueStateException(
        'Loan $id is not yet overdue. Due date: ${dueDateAsCalendarDate(shopTimeZone)}.',
      );
    }
    return copyWith(
      status: LoanStatus.overdue,
      workflowStatus: LoanWorkflowStatus.overdue,
    );
  }

  /// Returns a copy of this loan with an updated due date following an
  /// official due date extension (Story 6.2, FR-26).
  ///
  /// Resets overdue status back to [LoanStatus.active] and [LoanWorkflowStatus.disbursed].
  /// Cannot be applied to settled or cancelled loans.
  Loan withDueDateExtension({required DateTime newDueDate}) {
    if (status == LoanStatus.settled) {
      throw StateError('Cannot extend due date for a settled loan.');
    }
    if (status == LoanStatus.cancelled) {
      throw StateError('Cannot extend due date for a cancelled loan.');
    }
    return copyWith(
      status: LoanStatus.active,
      workflowStatus: LoanWorkflowStatus.disbursed,
      dueDate: newDueDate.toUtc(),
    );
  }

  /// Asserts that a payment may be recorded against this loan.
  ///
  /// PRD FR-19 strictly blocks payment submission on any loan still in
  /// `Active / Pending Disbursement`. Callers that accept payments must invoke
  /// this guard before posting a payment so the block is enforced in the
  /// authoritative operation rather than only in the UI.
  ///
  /// Throws [LoanPaymentBlockedException] when cash has not been disbursed.
  void assertPaymentsAllowed() {
    if (!isDisbursed) {
      throw const LoanPaymentBlockedException();
    }
  }

  /// Asserts that this agreement may be cancelled (AC-4, PRD FR-19).
  ///
  /// Cancellation is only permitted while the agreement is still
  /// `Pending Disbursement`. A disbursed or already-cancelled agreement is
  /// refused.
  ///
  /// Throws [LoanCancellationStateException] when the agreement is not
  /// awaiting disbursement.
  void assertCancellationAllowed() {
    if (!isPendingDisbursement) {
      throw LoanCancellationStateException(
        'Loan $id is not awaiting disbursement (workflow status: '
        '${workflowStatus.value}). Cancellation is refused.',
      );
    }
  }

  /// Returns a copy of this [Loan] with a cancellation applied (AC-4).
  ///
  /// The financial status becomes [LoanStatus.cancelled] and the workflow
  /// status becomes [LoanWorkflowStatus.cancelled]. The principal and balance
  /// are left untouched (a cancelled agreement never disbursed cash).
  ///
  /// Throws [LoanCancellationStateException] when the agreement is not
  /// awaiting disbursement.
  Loan withCancellation({
    required DateTime cancelledAt,
    required String cancellationReason,
  }) {
    assertCancellationAllowed();
    if (cancellationReason.trim().isEmpty) {
      throw LoanCancellationStateException(
        'A mandatory cancellation reason is required.',
      );
    }
    return copyWith(
      status: LoanStatus.cancelled,
      workflowStatus: LoanWorkflowStatus.cancelled,
      cancelledAt: cancelledAt,
      cancellationReason: cancellationReason.trim(),
    );
  }

  /// Asserts that a new agreed term may be recorded on this agreement (T6).
  ///
  /// Re-agreement is only permitted while the agreement is still
  /// `Pending Disbursement`. A disbursed or cancelled agreement is refused.
  ///
  /// Throws [LoanTermReagreementException] when the agreement is not
  /// awaiting disbursement.
  void assertTermReagreementAllowed() {
    if (!isPendingDisbursement) {
      throw LoanTermReagreementException(
        'Loan $id is not awaiting disbursement (workflow status: '
        '${workflowStatus.value}). Term re-agreement is refused.',
      );
    }
  }

  /// Returns a copy of this [Loan] with a re-agreed term recorded (T6).
  ///
  /// At most one of [termPresetDays] and [customDueDate] may be supplied.
  /// The agreed term replaces any previously recorded term.
  ///
  /// Throws [LoanTermReagreementException] when the agreement is not
  /// awaiting disbursement or when both term forms are supplied.
  Loan withAgreedTerm({
    int? termPresetDays,
    DateTime? customDueDate,
  }) {
    assertTermReagreementAllowed();
    if (termPresetDays != null && customDueDate != null) {
      throw LoanTermReagreementException(
        'A loan agrees to either a preset term or a custom date, not both',
      );
    }
    if (termPresetDays != null) {
      final preset = LoanTermPreset.fromCalendarDays(termPresetDays);
      if (preset == null) {
        throw LoanTermReagreementException(
          'termPresetDays must be one of the approved presets (30, 60, 90)',
        );
      }
    }
    // Construct directly (not via copyWith) so the old term is fully replaced:
    // copyWith uses ?? which cannot clear a previously set term.
    return Loan(
      id: id,
      shopId: shopId,
      customerId: customerId,
      principalCents: principalCents,
      balanceCents: balanceCents,
      status: status,
      workflowStatus: workflowStatus,
      dueDate: dueDate,
      createdAt: createdAt,
      settledAt: settledAt,
      termPresetDays: termPresetDays,
      customDueDate: customDueDate,
      disbursedAt: disbursedAt,
      disbursedByUserId: disbursedByUserId,
      cancelledAt: cancelledAt,
      cancellationReason: cancellationReason,
    );
  }

  /// Returns a copy of this [Loan] with the given fields replaced.
  Loan copyWith({
    String? id,
    String? shopId,
    String? customerId,
    int? principalCents,
    int? balanceCents,
    LoanStatus? status,
    LoanWorkflowStatus? workflowStatus,
    DateTime? dueDate,
    DateTime? createdAt,
    DateTime? settledAt,
    int? termPresetDays,
    DateTime? customDueDate,
    DateTime? disbursedAt,
    String? disbursedByUserId,
    DateTime? cancelledAt,
    String? cancellationReason,
    bool? correctionPending,
  }) {
    return Loan(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      customerId: customerId ?? this.customerId,
      principalCents: principalCents ?? this.principalCents,
      balanceCents: balanceCents ?? this.balanceCents,
      status: status ?? this.status,
      workflowStatus: workflowStatus ?? this.workflowStatus,
      dueDate: dueDate ?? this.dueDate,
      createdAt: createdAt ?? this.createdAt,
      settledAt: settledAt ?? this.settledAt,
      termPresetDays: termPresetDays ?? this.termPresetDays,
      customDueDate: customDueDate ?? this.customDueDate,
      disbursedAt: disbursedAt ?? this.disbursedAt,
      disbursedByUserId: disbursedByUserId ?? this.disbursedByUserId,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      correctionPending: correctionPending ?? this.correctionPending,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Loan &&
        other.id == id &&
        other.shopId == shopId &&
        other.customerId == customerId &&
        other.principalCents == principalCents &&
        other.balanceCents == balanceCents &&
        other.status == status &&
        other.workflowStatus == workflowStatus &&
        other.dueDate == dueDate &&
        other.createdAt == createdAt &&
        other.settledAt == settledAt &&
        other.termPresetDays == termPresetDays &&
        other.customDueDate == customDueDate &&
        other.disbursedAt == disbursedAt &&
        other.disbursedByUserId == disbursedByUserId &&
        other.cancelledAt == cancelledAt &&
        other.cancellationReason == cancellationReason &&
        other.correctionPending == correctionPending;
  }

  @override
  int get hashCode => Object.hash(
        id,
        shopId,
        customerId,
        principalCents,
        balanceCents,
        status,
        workflowStatus,
        dueDate,
        createdAt,
        settledAt,
        termPresetDays,
        customDueDate,
        disbursedAt,
        disbursedByUserId,
        cancelledAt,
        cancellationReason,
        correctionPending,
      );
}
