# Story 4.3 — Decoupled Cash Disbursement Confirmation & Official Due Date Calculation Engine

**Epic:** Epic 4 — Credit Agreement Lifecycle & Disbursement
**Story ID:** 4.3
**Status:** Phase 1 approved (qualified: 15-failure baseline comparison not fully verified). D1-D9 and D11 enforced via runtime throws; F4-A completed. Q-4/Q-5/Q-6 approved for v14 migration. AC-4 design approved (R4/R5/R6) but not yet implemented. Q-1 and D10 remain open.
**AC-4 (cancellation) — approved design, not yet implemented** — see "Approved AC-4 design (R4/R5/R6)".
**Dependencies:** Story 4.1 (Credit Agreement Data Model), Story 4.2 (Credit Term Selection & Preliminary Due Date Display)
**Traceability:** FR-6, FR-19, FR-31 (Event #4 for the disbursement; Event #2 for the cancellation), AD-3, AD-6

---

## Acceptance Criteria (authoritative source: `planning-artifacts/epics.md`)

**AC-1 — Cash disbursement confirmation**
> **Given** a credit agreement in `Active / Pending Disbursement`
> **When** authorized staff with `confirmCreditDisbursement` permission confirms physical cash handover
> **Then** the credit transitions to `Financial Status: Active / Disbursed`, `Overall Workflow Status: Active`
> **And** records the confirmed cash disbursement timestamp and disbursing staff ID
> **And** an audit event (Category 4: `Confirmed cash disbursement`) is **queued for append** to `audit_events` as an append-only local record carrying the category, the action type, the disbursing staff ID, the confirmed timestamp and the calculated official due date. The authoritative append to the server-side `audit_events` table is performed by the server-side audit writer upon synchronization (audit-writer work, not this story).

**AC-2 — Official due date from a preset term**
> **Then** the system calculates the Official Calendar Due Date by adding the agreed preset calendar days to the confirmed disbursement date in `Asia/Colombo`:
> `Official Calendar Due Date = Disbursement Date (in Shop Local Time) + N calendar days`
> *(TC-1: 30-day → Nov 14; TC-2: 60-day → Dec 14; TC-3: 90-day → Jan 13.)*

**AC-3 — Official due date from a custom term**
> **Then** the system validates that `Custom Due Date > Disbursement Date (in Shop Local Time)`:
> - If valid (TC-4): the custom date is confirmed and saved.
> - If delayed such that the custom due date is on or before the disbursement date (TC-5): disbursement confirmation is programmatically blocked.

**AC-4 — Cancellation of an abandoned agreement** — *approved design (R4/R5/R6); not yet implemented.*

---

## Product decisions applied to this story

- **R1 — canonical audit catalogue.** The PRD FR-31 ordinals and labels are authoritative. This story already emits `auditCategory: 2` (origination) and `auditCategory: 4` (disbursement) per the PRD ordinals, which is the correct convention under R1. The `AuditService` alignment is implementation work not yet performed.
- **R3 — AC-1 amended.** The disbursement event is queued for append to `audit_events` as an append-only local record; the authoritative append is performed by the server-side audit writer upon synchronization and is not part of this story.
- **R4 — cancellation audit classification.** Category 2 (`Credit agreement origination and cancellation`) with action type `cancel_credit_agreement`; not Category 4.
- **R5 — no automatic cancellation or expiry.** Manual Shop Owner cancellation with a mandatory reason; a non-destructive worklist for abandoned agreements.
- **R6 — collateral custody of a cancelled agreement.** The pledged items remain in the shop's custody; no automatic release; Story 3.4 gains a documented cancelled-credit custody state.
- **U-1 — offline policy (approved).** Disbursement and cancellation of an undisbursed agreement are permitted while offline via the R2 journal, marked `Pending Server Confirmation` until server acknowledgement, and reconciled on sync; other high-risk actions remain locked offline.
- **U-2 — worklist threshold (approved).** Pending-disbursement agreements surface on the Shop Owner worklist after 7 calendar days, evaluated in the shop's configured time zone.

**U-5 domain portion (resolved):** D1–D9 and D11 are now enforced via runtime throws in the `Credit` constructor (replacing debug-only asserts). D10 is deferred pending Q-1. F4-A (`CreditDao.createCredit` removal) completed. The DB-level portion (Tier 1 CHECKs) remains a separately reviewed v14 migration plan.

**Still open for this story:** U-5 DB-level (Tier 1 CHECKs, v14 migration), C-1 and C-2 (audit-category gaps for Stories 1.6 and 6.1, deferred to those stories).

---

## Implementation

### Decoupling (the core requirement)

Cash disbursement is a **separate operation** from credit agreement creation:

- `CreditDao.confirmCreditDisbursement(...)` is a distinct data operation. It never
  calls `createCredit`, never calls `createCreditAgreement`, and never creates a
  second credit agreement.
- It never records a payment. The agreed `principal_cents` and the outstanding
  `balance_cents` are **not** modified; only the workflow status, the due date
  and the disbursement record change. A disbursement moves cash *out*; a payment
  reduces the obligation. They are not modelled as the same thing.

### Domain — `lib/features/customers/domain/models/credit.dart`

- `CreditWorkflowStatus.cancelled` and `CreditStatus.cancelled` added (the
  architecture spine's `CreditFinancialState` includes `cancelled`).
- `Credit` now carries the **agreed term** (`termPresetDays`, `customDueDate`)
  and the **disbursement record** (`disbursedAt`, `disbursedByUserId`), plus
  the cancellation fields (`cancelledAt`, `cancellationReason`).
- `Credit.assertDisbursementAllowed()` refuses a disbursement unless the
  agreement is still `Pending Disbursement` — this is what makes a second
  disbursement impossible.
- `Credit.withDisbursement(...)` applies the transition: financial status stays
  `active`, workflow status becomes `disbursed`, and the **official** due date
  replaces the preliminary one.
- `CreditDisbursementStateException` signals a refused transition.

### Domain — `lib/features/customers/domain/models/credit_term.dart`

- `OfficialDueDateCalculator` finalises the official due date from the
  **agreed term** and the **confirmed disbursement date**, in the shop's
  operational time zone:
  - preset → `Disbursement Date (shop local) + N calendar days`;
  - custom → confirmed only when strictly after the disbursement date;
    otherwise `OfficialDueDateValidationException` blocks the disbursement.
- All arithmetic is calendar-date arithmetic on `LocalCalendarDate`, so a
  daylight-saving transition can never shift the result.

### Data operation — `lib/features/customers/data/daos/credit_dao.dart`

`CreditDao.confirmCreditDisbursement({actor, idempotencyKey, creditId, disbursedAt})`:

| Safeguard | Implementation |
|---|---|
| Active actor | `!actor.isActive` → `PermissionDeniedException` |
| Permission | `AuthorizationGuard.checkPermission(permission: AppPermission.confirmCreditDisbursement)` at the operation boundary. Cashier does **not** hold it; Manager and Shop Owner do. |
| Shop scoping | The credit is loaded with `getCreditById(actor.shopId, creditId)`; a credit in another shop is invisible → `StateError`. |
| No double disbursement | `credit.assertDisbursementAllowed()` — a disbursed or cancelled agreement is refused. |
| Atomicity | The idempotency guard, the credit update and the audit/event record are written in **one** `attachedDatabase.transaction`. A failure rolls all three back. |
| Retry safety | The `(shop_id, idempotency_key)` unique index on `sync_queue` is authoritative. `insertReturningOrNull` with `InsertMode.insertOrIgnore` returns `null` when another writer won the race, and the loser returns the already-disbursed credit. |
| Money invariants | `principal_cents` and `balance_cents` are never written by this operation. |
| Audit/event record | A `sync_queue` row with `action_type = 'confirm_credit_disbursement'`, `entity_type = 'credit'`, `entity_id = <credit id>`, and a payload carrying `auditCategory: 4` (PRD FR-31), `auditEvent: 'confirmed_cash_disbursement'`, the actor id, the confirmed timestamp and the calculated official due date. |

`CreditDao.createCreditAgreement(...)` gained optional `termPresetDays` and
`customDueDate` parameters so the **agreed term is persisted at origination**.
This is required because the official due date is finalised from the agreed term
and the disbursement date — never from the preliminary due date. The parameters
are additive and backward compatible; the operation rejects supplying both, or
a term that is not one of the approved presets.

### Schema — `lib/core/data/local/tables/credits_table.dart` (version 12 → 13)

`credits` gains `term_preset_days`, `custom_due_date`, `disbursed_at`,
`disbursed_by_user_id`, `cancelled_at` and `cancellation_reason`, plus
`'cancelled'` in the `status` and `workflow_status` CHECK constraints.

**Migration** (`app_database.dart`, `from < 13`): SQLite cannot add a CHECK
constraint in place, so the table is rebuilt row-by-row. Foreign keys stay
enforced for the whole migration, so the rebuild **defers** FK resolution to the
end of the migration transaction (`PRAGMA defer_foreign_keys = ON`) and
disables SQLite's reference-rewriting rename behaviour
(`PRAGMA legacy_alter_table = ON`). This keeps the
`collateral_items.credit_id → credits` foreign key intact across the swap — the
same hazard that **F5** documents for the v10 → v11 collateral rebuild.

A disbursement record is all-or-nothing
(`CHECK ((disbursed_at IS NULL) = (disbursed_by_user_id IS NULL))`). The
stronger "disbursed implies a record" rule is enforced by the operation layer,
because credits that predate the disbursement workflow are legitimately backfilled
to `disbursed` by the v12 migration without a record.

### Presentation — `lib/features/customers/presentation/credit_disbursement_screen.dart`

`CreditDisbursementScreen` confirms the physical cash handover and clearly
distinguishes the two states:

- **Awaiting Cash Disbursement** — the due date is labelled
  `Preliminary Due Date (Pending Disbursement)`.
- **Cash Disbursed** — the due date is labelled `Official Calendar Due Date`,
  and the confirmed timestamp and the disbursing staff member are shown.

The confirm control is disabled without the `confirmCreditDisbursement`
permission, and the DAO enforces it regardless of the UI state. The screen
never creates a credit agreement and never records a payment.

---

## Approved AC-4 design (R4 / R5 / R6) — not yet implemented

### AC-4 — Cancellation of an abandoned agreement

**Status: approved design — implementation pending (not deferred on a category
ruling).**

Everything AC-4 specifies is implementable, and the domain and schema support is
**already in place** (`CreditStatus.cancelled`, `CreditWorkflowStatus.cancelled`,
`cancelled_at`, `cancellation_reason`, and the `status <> 'cancelled' OR
(cancelled_at IS NOT NULL AND cancellation_reason IS NOT NULL …)` CHECK
constraint), so **no further migration is needed for the agreement state
itself**.

**Approved ruling R4 — audit classification.** The cancellation of an
undisbursed agreement is recorded as an audit event in FR-31 **Category 2**
(`Credit agreement origination and cancellation`) with action type
`cancel_credit_agreement`. It is **not** recorded under Category 4 (`Confirmed
cash disbursement`), because no cash was disbursed. Category 2 is the parent
of the action types `credit_agreement_origination`, `cancel_credit_agreement` and
`credit_term_reagreed`; the `action_type` is the distinguishing field within the
category. This keeps the `event_category` range at 1–14 and requires **no**
server migration and **no** data migration.

**Approved ruling R5 — no automatic cancellation or expiry.** An agreement
awaiting disbursement is **never cancelled automatically**: there is no timeout
and no auto-expiry. An abandoned agreement is cancelled **manually by the
Shop Owner** with a mandatory reason, transitioning to `Financial Status:
Cancelled / Undisbursed`, `Overall Workflow Status: Cancelled`. To keep
abandoned agreements visible without mutating them, the system surfaces a
**non-destructive worklist** of agreements still awaiting disbursement; the
worklist reports an agreement and never changes its state. The worklist
surfaces an agreement after **7 calendar days**, evaluated in the shop's
configured time zone (U-2, approved).

**Approved ruling U-1 — offline policy.** Cash disbursement and cancellation
of an undisbursed agreement are **permitted while offline**. The business
mutation and its R2 journal entry are written in the same local ACID
transaction; the agreement state transitions immediately in the local database
and the event is marked `Pending Server Confirmation` until server
acknowledgement. Other high-risk administrative actions (approving corrections,
due-date extensions, administrative closures) remain locked offline.

**Reconciliation behaviour (R2/U-1).** On connectivity, each
`PendingServerAck` journal entry is appended to `audit_events` by the
server-side audit writer (Story 1.3 / 1.8); a rejected entry is surfaced as
`failed` with `lastError` and is never silently dropped; an entry is removed
from the local journal only after server acknowledgement. A device lost before
synchronization leaves a permanent gap, which FR-32's RPO does not cover; this
is an accepted risk of the offline-first model.

**Approved ruling R6 — collateral custody.** The pledged items of a cancelled
agreement **remain in the shop's custody** and are **not** automatically
released to the customer. Cancelling an agreement changes the agreement's own
state; it is not a collateral return, and no item custody transition is
performed as part of the cancellation. Story 3.4 gains a documented
cancelled-credit custody state (implementation work, not part of this story).

**Remaining before implementation:** the DB-level invariant set for the
cancelled state beyond the reason CHECK (U-5). U-1 and U-2 are now approved
and recorded above.

---

## Open findings (status updated by the Phase 1 review)

| ID | Status |
|---|---|
| **F1** — the audit event category mapping conflicts between the PRD FR-31 catalogue ordinal and the `AuditService` taxonomy. **Ruled by R1:** the PRD FR-31 ordinals and labels are the authoritative event-category contract; the `AuditService` taxonomy must align to them and a single canonical source is required. This story already records `auditCategory: 4` (disbursement) and `auditCategory: 2` (origination) per the PRD ordinals, which is the correct convention under R1; the `AuditService` alignment is implementation work not yet performed. | **Ruled — not yet implemented** |
| **F2** — `Credit.assertPaymentsAllowed()` does not block a payment against a `settled` credit. **Ruled by R8:** payments are refused against a `settled` credit with a distinct error, plus FR-21 overpayment enforcement in the operation layer. This story implements no payment recording; the guard change lands with Story 5.1. | **Ruled — deferred to Story 5.1** |
| **F5** — the v10 → v11 `collateral_items` rebuild drops a parent table with foreign keys enforced and an untested populated child table. **Reported resolved** for the tested scenarios: the rebuild now runs inside a transaction with `PRAGMA defer_foreign_keys = ON` and `PRAGMA legacy_alter_table = ON`, switches both off inside the transaction, and runs `PRAGMA foreign_key_check` before COMMIT; `drift_migration_v11_test.dart` covers a populated child table, retained FK enforcement, no dangling references, a half-migrated repair, and a second-launch idempotency check. | **Reported resolved — not independently verified in this review** |

---

## Tests

| File | Coverage |
|---|---|
| `test/unit/features/customers/credit_disbursement_dao_test.dart` | AC-1/2/3: successful confirmation; the state transition; the disbursing staff id and timestamp; the audit/event entry with PRD FR-31 category 4; no second agreement and no payment effect; TC-1/2/3 preset due dates; TC-4 valid custom date; TC-5 same-day and past custom date blocked; shop-time-zone finalisation; unauthorized actor; inactive actor; cross-shop credit; already-disbursed refusal; same-key retry; blank key; atomic rollback when the audit/event write fails; agreed-term recording and rejection of invalid terms. |
| `test/unit/features/customers/credit_term_test.dart` | `OfficialDueDateCalculator`: TC-1/2/3; time-of-day independence; daylight-saving transition; shop zone vs UTC; TC-4; TC-5; no recorded term. |
| `test/widget/features/customers/credit_disbursement_screen_test.dart` | pending vs completed disbursement; the preliminary vs official due-date labels; the agreed term; the disbursing staff and timestamp; no second confirmation; persisted state; permission-disabled control; deactivated actor; cross-shop credit not found. |
| `test/unit/core/data/local/drift_database_test.dart` | The v12 → v13 migration: the credits table is rebuilt, financial balances and statuses are preserved, the new columns are empty for pre-existing agreements, **a child foreign key into `credits` survives the rebuild**, the credits indexes are recreated, and the rebuilt table accepts a disbursement record. |
| `test/unit/core/data/local/drift_migration_v11_test.dart` | The v10 → v11 collateral rebuild under a populated child table: every collateral item and its credit binding survive, populated photo-exception rows survive, customer/credit/audit/sync records survive, Story 3.4 custody and discrepancy tables are created, foreign-key enforcement stays active, no dangling reference remains, and a half-migrated database is repaired. |
| `test/unit/core/data/local/drift_migration_v13_test.dart` | The v12 → v13 credits rebuild: collateral items stay bound to their agreement, customer/collateral/credit/audit records survive, the rebuild is idempotent, foreign-key enforcement stays active, no dangling reference remains, and the rebuilt table matches a fresh installation. |
| `test/unit/features/customers/credit_disbursement_concurrency_test.dart` | T4: two confirmations with different idempotency keys targeting the same eligible agreement cannot both succeed; the eligibility check is part of the write, serialized by SQLite's write lock; a single disbursement record and a single category-4 audit/event record result. |
| `test/unit/features/customers/credit_disbursement_idempotency_test.dart` | T2: an idempotency record is a claim, not proof; a key claimed by a different operation or a different agreement can never be turned into a false successful disbursement. |
| `test/widget/features/customers/credit_disbursement_idempotency_test.dart` | T2 customer-facing consequence: the UI does not surface a false success from a reused key. |
| `test/unit/features/customers/credit_legacy_agreement_test.dart` | T6: a legacy agreement produced by the v12 → v13 upgrade cannot be disbursed and leaves no trace of the attempt; the refusal path is a safe refusal pending an approved re-agreement policy. |
| `test/unit/features/customers/official_due_date_test.dart` | AC-2: the three approved examples, month/year and leap-year boundaries, daylight-saving boundary, and shop-zone rendering of the official due date. |
| `test/widget/features/customers/official_due_date_display_test.dart` | T3: the official due date is rendered in the shop's operational time zone, not as the UTC calendar date of the stored instant. |

---

## Verification results

| Check | Result |
|---|---|
| `flutter analyze lib/ test/` | Reported: no issues found (not re-run in this review). |
| `flutter test` (full suite) | Reported: `+606 / −15` — the same 15 pre-existing baseline failures (7 PostgreSQL integration, 7 collateral photo-exception widget timing, 1 template smoke). **No new failures.** This count predates the eight additional test files listed above and was not re-run in this review; the reported figures are treated as reported, not independently verified. |

