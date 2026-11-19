# Epic 5 Context: Payment Processing, Fixed-Point Ledgers & Receipt Snapshots

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 5 closes the counter transaction lifecycle: staff record partial payments and full settlements with programmatic overpayment protection; balances use exact integer minor units under a double-entry ledger formula in atomic ACID transactions; every confirmed payment yields an immutable receipt snapshot (reprints watermarked and audited); erroneous entries are corrected via request → Shop Owner approval with compensating ledger entries; staff-proposed balance adjustments (partial forgiveness) post only on owner approval. Financial accuracy and an untamperable audit trail are the product's core trust promise — Epics 6 and 7 read this ledger.

## Stories

- Story 5.1: Payment Submission, Anti-Overpayment Validation & Settlement Transition
- Story 5.2: Double-Entry Ledger Formula & Atomic Transaction Persistence
- Story 5.3: Payment Idempotency, Concurrency Control & Correction-Pending Lock
- Story 5.4: Immutable Receipt Snapshot Model, Watermarked Reprints & Audit Logging
- Story 5.5: Controlled Financial Correction & Shop Owner Reversal Approval Workflow
- Story 5.6: Staff-Proposed, Owner-Approved Balance Adjustments (Partial Forgiveness)

## Requirements & Constraints

- Payment > 0.00; payment exceeding the valid outstanding balance is blocked with an explicit error. Payment < balance → `Partial Payment`; payment == balance → `Full Settlement`, balance exactly zero, status immediately `Settled`.
- Valid Outstanding Balance = Principal (debit) − Σ Payments (credit) + Σ Approved Reversals (debit) ± Σ Approved Adjustments. All math in 64-bit integer minor units (100 cents = 1.00 LKR); Dart `double`/`float` prohibited for money and lint-enforced; max two decimals on input.
- Ledger posting + balance deduction run in one atomic transaction; any failure rolls back completely.
- Mandatory verification scenarios: (1) partial deduction; (2) full settlement → zero + `Settled`; (3) approved reversal adds back exact units; (4) approved debit adjustment (+250.00); (5) approved credit adjustment (−500.00); (6) duplicate submission with same idempotency key commits exactly once; (7) two concurrent 30,000.00 payments vs 50,000.00 → one succeeds, second blocked; (8) staff-proposed credit adjustment (−5,000.00 forgiveness) → pending lock → owner approves → 20,000.00, immutable `adjustment_credit`, rejection leaves balance unchanged.
- Every payment carries a client-generated UUIDv4 idempotency key; re-transmitted requests return the confirmed transaction/receipt without re-posting; concurrency re-evaluates against the updated balance.
- While a correction/adjustment proposal on a credit is pending review, payments are blocked strictly on that credit; other credits remain operational.
- Confirmed payment → immutable receipt snapshot: shop branding (name, address, phone, email, tax/reg no, logo, header/footer notes at payment time) + receipt number, timestamp, type, amount, pre/resulting balance, customer identifier, credit reference, cashier ID. Later shop-profile edits never alter historical receipts. Reprints keep original number/timestamp, add `*** REPRINT ***` watermark + reprint timestamp, log a distinct audit entry, create zero ledger transactions.
- Corrections/adjustments require a mandatory non-empty business reason; originals permanently preserved; compensating immutable entries linked to the original. Staff can never approve their own proposal; rejection requires a mandatory reason, leaves balance unchanged, lifts the lock.
- Adjustment governance is two-step: staff (`requestCorrections`) propose amount+direction (or a desired new effective balance from which the delta derives); only Shop Owner (`approveCorrections`) posts — or owner executes directly. Credit adjustment exceeding the balance is rejected (no negative balances unless explicitly modeled).
- Audit events: payment recording, correction/adjustment request-approve-reject, receipt reprints — with actor IDs, target credit, pre/post balance, timestamps, justifications; arithmetic discrepancies trigger high-severity integrity alerts.
- Out of scope: installment scheduling, multi-currency, customer-facing online receipt portal.

## Technical Decisions

- Feature slice `features/payments`: `domain/` (pure Dart, zero Flutter/Drift imports) → `data/` (Drift tables/DAOs, sync) → `presentation/` (Riverpod `AsyncNotifier`, widgets).
- Money value object (`core/money/`): immutable, `int minorUnits`, LKR default, `isZero`; presentation owns formatting. SQLite `INTEGER`, PostgreSQL `BIGINT`. Roundtrip serialization tested.
- Dual-tier persistence (AD-1): Drift locally, PostgreSQL 16+ authoritative with RLS (`tenant_id = current_setting('app.current_tenant_id')::uuid`). Financial records append-only; corrections/reversals/adjustments are discrete compensating entries, never overwrites. Unique constraints on `(tenant_id, idempotency_key)` and `(tenant_id, client_operation_id)`; writes flagged `PendingServerAck` vs `ConfirmedByServer`. Adjustments post as `adjustment_debit`/`adjustment_credit` entries in the same atomic transaction as the lock lift; stored balance never mutated in place.
- `credit_ledger_entries` already supports the adjustment types; `recordAdjustment` path exists. Story 5.6 decides between adding a `direction` column to `credit_corrections` (Drift migration) vs a sibling `adjustment_requests` table; the open `correctionAmountCents` semantics must be resolved explicitly; unreferenced `correction_adjustment_screen_temp.dart` is deleted in Story 5.6.
- State machines & UI protection (AD-3): `CreditFinancialState` (`pendingDisbursement → active → overdue → settled | cancelled`). Payment buttons observe `AsyncValue.isLoading`, generate the idempotency UUID on first tap, lock until confirmed. `isPaymentLocked` on the credit controller blocks payment inputs for that credit only; same lock covers pending adjustment proposals; adjustment approval is a high-risk admin action locked offline.
- RBAC (AD-6): `recordPayments`, `viewAndReprintReceipts`, `requestCorrections`, `approveCorrections` (Shop Owner default). Dual-layer: Riverpod selectors hide/disable (UX only); server/RLS enforces.
- Audit (AD-6): `audit_events` insert/select-only with trigger rejecting UPDATE/DELETE; reprints log Category-13 events; corrections/adjustments log Category 6/7 with pre/post balance.
- Testing (AD-7): ~70% pure-Dart domain unit tests (Money, ledger formula, the 7+1 scenarios); ~20% integration incl. Drift mid-transaction rollback and concurrency stress; PostgreSQL-backed tests are the real RLS/audit-trigger gate. CI gates for cross-tenant leakage and permission suites.

## UX & Interaction Patterns

- Payment screen: amount parses to Money; validates `0 < amount ≤ balance`; live new-balance preview; idempotent submit disables the button in flight.
- Credit Details: balance hero (monospace outstanding, progress bar, due-date pill). Record Payment hidden/disabled with explicit "Locked for Correction Review" banner when pending; payment history reverse-chronological (receipt #, actor, running balance); reversed entries struck-through with link to reversal.
- Adjustment affordance: staff proposes from credit card / payment screen; pending → lock + banner; owner approves/rejects in the correction queue; rejection reason mandatory.
- Receipt: generated after commit; print/PDF failure reported separately from the financial commit; reprint keeps original identity + `*** REPRINT ***` watermark. Thermal 58/80mm and A4; monospace amounts.

## Cross-Story Dependencies

- Upstream: Story 1.1 Money VO; Story 1.6 shop profile (snapshot source) & timezone; Story 1.7 Shop Owner role; Story 4.3 disbursed credit — payments only against disbursed credits.
- Within Epic 5: 5.1 → 5.2 → 5.3 → 5.4; 5.5 (corrections, `done`); 5.6 (reopened gap — Epic 5 `in-progress`, 5.6 `in-review` as of 2026-11-19, see `spec-5-6-staff-proposed-owner-approved-balance-adjustments-partial-forgiveness.md`). 5.5's owner-direct adjustment AC remains in force.
- Downstream: Epic 6 reads the ledger for overdue evaluation (settled/zero-balance excluded); Epic 7 consumes payment/ledger/receipt data for dashboards, exports, audit viewer.
- Offline: payment writes flow through the sync queue with idempotency; correction/adjustment approvals locked until server-confirmed.
