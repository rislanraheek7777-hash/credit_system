---
title: 'Story 5.6: Staff-Proposed, Owner-Approved Balance Adjustments (Partial Forgiveness)'
type: 'feature'
created: '2026-11-19'
status: 'done'
route: 'dispatch'
review_loop_iteration: 2
story_key: '5-6-staff-proposed-owner-approved-balance-adjustments-partial-forgiveness'
baseline_commit: 'ab03a93'
context:
  - '_bmad-output/implementation-artifacts/epic-5-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Partial forgiveness — and other legitimate balance adjustments — has no auditable, two-step path at the counter. The in-flight implementation (direction column, `AdjustmentProposalScreen`, payment-screen entry) leaves Story 5.6's ACs unmet and its core pipeline unsafe: no profile-card entry point, no eligibility gate (pending-disbursement/cancelled credits are forgivable), over-balance proposals pass, a full forgiveness strands a zero-balance credit as unsettleable active, approval omits the mandatory justification from the audit event, and a `credit` direction combined with a payment-reversal anchor posts a mistyped movement.

**Approach:** Complete Story 5.6 against the epics ACs on the existing `credit_corrections` + `direction` model (no sibling table, no new permission), hardening the same request→lock→owner-approve→post pipeline end to end, and add the missing profile-credit-card entry (mirroring the 2026-11-18 every-card pattern). Owner-direct `adjustBalance` stays unchanged.

**Decisions (made at planning):**
- Fix the directly-coupled pipeline defects inside this story, not deferred: proposal-time AND in-transaction over-balance re-check; disbursed/`active`|`overdue`/balance>0 eligibility gate at screen and DAO; full forgiveness (`newBalanceCents == 0`) posts `status = settled` + `settled_at` in the same transaction (no stranded credit); `credit` + `originalPaymentId` combination rejected at validation; approval audit payload gains the mandatory justification; double-tap approve covered by an idempotency test; blank rejection disabled at the dialog; negative post-balance clamped/disabled in the confirm dialog.
- Layout of proposal entry points stays unchanged elsewhere (payment screen, settle sheet); the 2026-11-18 visibility-restore pattern governs the new profile entry.
- `isPaymentLocked` semantics stay on `correctionPending` (per-credit only) — payers on other credits are unaffected; extensions/disbursements stay unlocked (documented, not changed).
- `correction_adjustment_screen_temp.dart` stays deleted (story impl-note).
- No schema/migration changes are required; v26 is final for this story. Category 6 (proposal) vs Category 7 (approve/reject/direct) audit split stays as shipped (FR-31 grouping, not an AC change).
- Human decisions (2026-11-19): staff may propose `debit` per the frozen ACs (option kept, owner approves it like any proposal); FR-22's derive-delta input mode IS to be implemented (enter desired new effective balance, system derives `delta = current - new`, same validation path); the coupled correctness suite is in scope for this story; and the spec stays in one piece (no split at ~3.3–3.7k tokens).
- Human decision 2 (2026-11-19, post-review): the overdue workflow drift is fixed **in this story** — `applyOverdue` and the Overdue screen no longer flip `workflowStatus` (overdue is carried by `status` alone, restoring the payment conditional update's `disbursed` contract); a v28 data-normalize migration (`UPDATE credits SET workflow_status='disbursed' WHERE workflow_status='overdue' AND status='overdue'`) repairs existing drifted rows. The spec's earlier "No schema/migration changes are required; v26 is final" line is amended accordingly (v28, data-only, no DDL).
- Human decision 3 (2026-11-19, post-review): the owner-direct path (`adjustBalance`) gets the same zero-balance settlement flip as the approval path — credit flips to `settled` + `settled_at` + workflow `disbursed` in the same transaction when a full forgiveness zeroes the balance. The "owner-direct path stays unchanged" note is amended to "unchanged apart from the zero-balance settlement flip, per human approval".

## Boundaries & Constraints

**Always:**
- Positive amount in integer minor units; mandatory non-empty reason; direction ∈ `{debit, credit}`; proposals stored in `credit_corrections` with `originalPaymentId = null`.
- Proposal input offers two modes: `amount + direction`, or a desired new effective balance from which the system derives `delta = current - new` (FR-22 amended). The derive mode reuses the same validation (over-balance rejection, no negative balances); the sign of the derived delta selects debit vs credit automatically.
- `requestCorrections` required to propose (screen + DAO); only Shop Owner (`approveCorrections`) approves/rejects or executes directly.
- Credit adjustment exceeding the balance is rejected at proposal time and re-checked inside the transaction; zero is permitted; debit is unbounded in magnitude.
- Proposal sets `correctionPending`; payment recording throws `CreditCorrectionPendingException`; rejection lifts the lock with balance unchanged; approval recalculates atomically and lifts in the same transaction.
- Eligibility (disbursed workflow + status `active`/`overdue` + balance > 0) enforced at screen and DAO.
- Evidence/audit: Category 7 approval event carries actor IDs, target credit, direction, pre/post balance and justification.
- Story 5.6 ACs traceability: FR-6, FR-22, FR-23, FR-31 (Cat 7), AD-1, AD-2, AD-6; settle-forgiveness end-to-end (propose → approve → settle remainder) must pass.

**Never:** no new permission; no raw balance mutation (ledger appends only); no schema JSON/DDL changes (the single v28 data-normalize `UPDATE` was approved 2026-11-19 as decision 2; it adds no column, table, or constraint); settlement-blocked credits remain blocked while pending; no silent fallback money math; no UI-only enforcement.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| HAPPY_PATH | Disbursed active credit; staff `requestCorrections` | Profile card + settle/payment entries offer Request Balance Adjustment; proposal posts `pending_approval`, lock on that credit | N/A |
| STAFF_APPROVE | Any staff (owner excepted) | Blocked — `PermissionDeniedException` | Existing permission error |
| OWNER_APPROVE | Owner approves forgiveness | Immutable `adjustment_credit`, atomic balance recalc, `correctionPending` lifted, Category-7 audit (with reason) | N/A |
| FULL_FORGIVENESS | `newBalanceCents == 0` | Ledger posts; credit transitions to `settled` + `settled_at`; summary confirms | N/A |
| OVER_BALANCE | Forgiveness > balance (screen, DAO pre-read, in-txn re-read) | Rejected; nothing locked | existing `StateError` / inline |
| INELIGIBLE | Pending-disbursement / cancelled / zero balance | Rejected at screen and DAO | Validation message |
| DERIVE_DELTA | Staff enters desired new effective balance | System derives `delta`, posts the proposal with derived amount and direction (debit/credit by sign); same validation as manual mode | Invalid / over-balance / below-zero delta → rejected |
| BAD_COMBO | `direction=credit` + non-null `originalPaymentId` | Rejected at validation | Validation message |
| REJECT | Owner rejects, blank reason | Reject button disabled; DAO rejects blank reason | Validation message |
| PAY_WHILE_PENDING | Payment on the locked credit | Blocked; other credits work | `CreditCorrectionPendingException` |
</frozen-after-approval>

## Code Map

- `lib/features/customers/data/daos/correction_dao.dart` -- proposal/approve/reject core; `requestCorrection` L147-396 (direction validation L230-237, in-txn re-check L268-283, lock L319-334, idempotency L287-316), `approveCorrection` L430-675 (atomic BEGIN L478, delta math L543-554, ledger entries L568-589, lock lift L619-632), `rejectCorrection` L699-893 (mandatory reason L734-741, lock lift L837-851), `adjustBalance` L928-1160 (owner-direct; unchanged). No eligibility check anywhere — add here too.
- `lib/features/customers/presentation/adjustment_proposal_screen.dart` -- proposal UI; debit+credit offered (L305-325), amount L333-344, reason L361-369, `_creditEligibleForAdjustment` L75-79 (missing status gate), over-balance pre-empt L175-182, `submit_adjustment_button` L382.
- `lib/features/customers/presentation/customer_profile_screen.dart` -- profile credit cards; `_settleCredit` settle pattern; NO adjustment entry (add here, gated on `requestCorrections` + `!credit.correctionPending`).
- `lib/features/customers/presentation/correction_review_screen.dart` -- owner approval UI; negative post-balance dialog L134-174 (not clamped), Reject enabled on blank reason L238-256, no double-tap idempotency field L279-330 (client key fresh per call — rely on DAO conditional UPDATE; add test).
- `lib/features/customers/presentation/settle_summary_screen.dart` -- settle-sheet entry `request_adjustment_button` (L415/553-579); keep, no changes.
- `lib/features/customers/presentation/payment_screen.dart` -- entry `request_adjustment_button` (L456-478); keep, no changes.
- `lib/features/customers/domain/services/receipt_service.dart` -- `isEligibleForPayment` (L70) reused for eligibility semantics.
- `lib/features/customers/data/daos/overdue_dao.dart` / `credit_dao.dart` -- no lock checks (extensions/disbursement) — spec decision D3: unchanged, documented.
- `test/unit/features/customers/correction_adjustment_dao_test.dart` -- existing suite (7 tests); extend with: double-tap approve idempotent, zero-newBalance settle path, combination rejection, in-txn over-balance re-check, eligibility rejection.
- `test/widget/features/customers/` -- extend/adjust: review-screen dialog clamps post-balance; reject disabled until reason non-empty; profile-card entry visible/hidden.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- items at lines 125-127, 129-131, 157-159, 161-163, 173-175, 177-179, 181-183, 206-209, 210-213 are this story's supply side; mark resolved in the spec's close-out, do not delete ledger entries.

## Tasks & Acceptance

**Execution:**
- [x] `correction_dao.dart` -- eligibility gate (disbursed workflow + `active`/`overdue` + balance > 0) in `requestCorrection`; in-txn over-balance re-check; `credit`+`originalPaymentId` rejected; zero-balance approval writes `status=settled`/`settled_at` alongside lock lift; Category-7 approval payload gains `reason`.
- [x] `adjustment_proposal_screen.dart` -- implement the derive-delta input mode (toggle between `amount + direction` and `new effective balance`; derive `delta`, derive direction from sign, same validations/pre-empt); enforce status/workflow eligibility (fixes the doc vs code mismatch L73-79); keep amount ≤ balance preview for both directions.
- [x] `correction_review_screen.dart` -- clamp/disable confirm on negative (and request reason-gated Reject disable); keep conditional UPDATE semantics.
- [x] `customer_profile_screen.dart` -- add "Request Balance Adjustment" per-card action gated on `requestCorrections` and `!correctionPending`, mirroring the Settle action placement; on proposal return, reload + snackbar; block visually while lock pending (disabled + lock subtitle).
- [x] `adjustment_proposal_screen.dart` / payment / settle entry points unchanged apart from eligibility gate.
- [x] `correction_adjustment_dao_test.dart` + widget tests -- new scenarios per I/O matrix incl. end-to-end settle-forgiveness already covered; double-tap approve; zero settle; combination rejection.
- [x] `deferred-work.md` list cross-checked; resolution recorded in the spec, not by deleting entries.

**Acceptance Criteria:**
- Given a disbursed active credit with balance > 0 and a staff member with `requestCorrections`, when they tap Request Balance Adjustment on the customer profile card, then the proposal screen requires a non-empty reason, direction and positive integer-minor-unit amount and records a `pending_approval` proposal activating the payment lock on that credit.
- Given a pending adjustment proposal, when a non-owner staff member or Manager attempts to approve it, then the action is blocked (`PermissionDeniedException`).
- Given a Shop Owner reviewing the correction/adjustment queue, when they approve, then an immutable `adjustment_credit` (or `adjustment_debit`) is posted with a linked `correctionId`, `correctionPending` is lifted atomically with the balance write, status flips to `settled` on zero, and a Category-7 audit event is logged with actor IDs, target credit, pre/post balance and the justification.
- Given an owner rejection with a mandatory reason, when confirmed, then `status=rejected`, the balance is unchanged, the lock lifts, and Category-7 is logged. Rejection with a blank reason is rejected by the UI and the DAO.
- Given a credit locked by a pending proposal, when any user records a payment on it, then it is blocked with the existing correction-pending error; payments on other credits succeed.
- Given a forgiveness equal to the full outstanding balance, when approved, then the credit posts normally and transitions to `settled` with `settled_at` in the same transaction.
- Given staff choose the derive-delta mode and enter a desired new effective balance, when they submit, then the system posts a proposal with the derived amount and direction; an implied over-balance or below-zero result is rejected with the same errors as manual mode.
- Given an adjustment exceeding the outstanding balance (credit direction), when proposed or approved, then it is rejected with the existing over-balance error.
- Given a proposal on a pending-disbursement or cancelled credit, when submitted, then it is rejected at screen and DAO.

## Implementation Notes

### 2026-11-19 — Spec Change Log additions (pass 2 close-out)

| Date | Change |
|------|--------|
| 2026-11-19 (post-review) | Human renegotiated the spec three times, in response to review pass 2: (1) the overdue workflow fix is **in scope** - overdue transitions persist `status = 'overdue'` only; the spec's "v26 is final / no schema changes" decision is amended by one data-only v28 normalize migration for existing drifted rows; (2) `adjustBalance` (owner-direct) gains the zero-balance settlement flip for parity with the approval path; (3) the eligibility gate is **carved out** - it applies only to adjustment proposals (`originalPaymentId == null`), so Story 5.5 payment corrections on settled/zero-balance credits keep working. All three amendments are localized to eligibility/settlement semantics; frozen ACs, boundaries and I/O matrix unchanged. |

Reserved for the implementer (append-only). No entries yet. Storage decision already shipped: `credit_corrections` + `direction` (v26); a sibling `adjustment_requests` table would add a parallel state machine for no benefit and is rejected. In-flight settle-sheet and payment-screen entries stay bytecode-compatible — do not regress their widget-test keys.

### Implementation close-out (Story 5.6 build, 2026-11-19)

**Implemented:**
- `correction_dao.dart`: `credit`+`originalPaymentId` rejected at validation; eligibility gate (`disbursed` workflow + `active`/`overdue` + balance > 0, `ReceiptService.isEligibleForPayment` semantics) enforced pre-read and re-checked in-transaction in `requestCorrection`; in-transaction over-balance re-check; full-forgiveness approvals flip `status='settled'` + `settled_at` atomically with the balance/lock write; Category-7 approval audit payload (guard + post-transaction entry) now carries `reason`, pre/post balance and `settled` flag; doc comments updated.
- `adjustment_proposal_screen.dart`: FR-22 derive-delta input mode added (`amount + direction` ⇄ `new effective balance` toggle; `delta = current − desired`; sign selects debit/credit; zero-delta and negative-desired-balance rejected; below-zero result keeps Approve/Submit disabled with the same over-balance error as manual mode); `_creditEligibleForAdjustment` fixed to enforce disbursed/active-or-overdue/positive-balance/no-pending-lock (doc-vs-code mismatch closed); balance-after preview now shown for both directions; `Max:` suffix only for forgiveness; submit disabled while an invalid state exists; doc updated (profile/payment/settle entry points).
- `correction_review_screen.dart`: approve-confirm dialog disables Approve and withholds the "recalculate" arithmetic when post-balance would be negative (warning keyed `review_negative_balance_warning`); reject confirm is disabled until the reason is non-blank (`StatefulBuilder`); conditional UPDATE semantics unchanged.
- `customer_profile_screen.dart` + new `credit_adjustment_action.dart`: per-card "Request Balance Adjustment" action (key `request_adjustment_button_$creditId`, lock notice `request_adjustment_lock_$creditId`), gated on `requestCorrections`, disabled with lock subtitle while `correctionPending`, placed below Settle; on proposal return the profile reloads and confirms via SnackBar.
- Settle-sheet and payment-screen entry points untouched; `correction_adjustment_screen_temp.dart` remains deleted; no schema/migration changes (v26 final).

**Verification:** `flutter analyze` — no issues (zero-lint policy). New/extended unit tests in `correction_adjustment_dao_test.dart` (double-tap approve idempotent; zero-balance forgiveness → settled; credit+payment combo rejected at validation; eligibility refused for pending-disbursement/cancelled/zero-balance; audit payload carries justification + pre/post balance; approval re-check failure rolls back) — 13/13 pass; `correction_dao_test.dart` 31/31; settle-forgiveness end-to-end passes. Widget: new `adjustment_proposal_screen_test.dart` (derive forgiveness/increase, below-zero desired balance, zero-delta no-op, zero target balance, ineligible credit) 6/6; `correction_review_screen_test.dart` 11/11 (incl. new negative-post-balance clamp + reject disabled-until-reason); `customer_profile_screen_test.dart` 44/44 (incl. new visible/hidden/disabled/lock/tap-through adjustment-action group); `correction_request_screen_test.dart`, `correction_adjustment_screen_test.dart`, `multi_credit_selection_test.dart` all pass. Full `flutter test test/unit/features/customers test/widget/features/customers`: 560 passed, 1 pre-existing failure — `customer_photo_capture_test.dart` is a committed **empty (0-byte)** file and fails to load; it imports none of this story's code and was already broken at baseline (noted in deferred-work.md repo-hygiene item).

**deferred-work.md cross-check (entries not deleted; resolutions recorded here):**
- `spec-customer-soft-delete-no-credits.md` L125-127 (eligibility doc≠code) → resolved: screen + DAO now enforce the gate, unit+widget tested.
- L129-131 (in-txn over-balance re-check) → resolved: re-read inside the transaction (`requestCorrection`), plus approval-time negative-balance guard test. Note: the request-time in-transaction branch cannot be isolated from the pre-read on a single in-memory connection; it is defense-in-depth mirroring the pre-check (same error type/message). The approval-time re-check is directly tested (balance shrunk underneath a pending proposal → approval StateError, full rollback).
- L157-159 (staff debit proposals vs frozen partial-forgiveness intent) → resolved by human decision 2026-11-19 recorded in this spec (debit kept per frozen ACs; owner approves like any proposal).
- L161-163 (review dialog negative post-balance) → resolved: confirm disabled + warning, "Recalculate" line withheld.
- L173-175 (full forgiveness strands zero-balance credit) → resolved: approval flips `status='settled'` + `settled_at` in the same transaction (unit-tested).
- L177-179 (`credit` direction + original payment → mistyped compensating_debit) → resolved: rejected at validation with `ArgumentError`; lock never taken.
- L181-183 (cancellation/pending-disbursement credits forgivable) → resolved: DAO + screen reject non-eligible credits (unit-tested for pending-disbursement/cancelled/zero-balance; widget-tested for cancelled).
- `spec-credit-settle-button-customer-profile.md` L206-209 (profile/Credit Details adjustment entry missing) → resolved: per-card profile entry added (this spec's Approach: profile entry governed by the 2026-11-18 every-card pattern). Note: Credit Details surface not added — profile cards only, matching this spec's scope.
- L210-213 (FR-22 derive-delta half-implemented) → resolved: derive-delta mode implemented (toggle, derivation, auto-direction, zero-balance target, shared validation path) and widget-tested.
- L226-228 (over-balance proposals accepted at submit; L227 in spec's range list via 129-131 family) → resolved: proposal-time rejection + in-transaction re-check + submit disabled in the UI.

**Judgment calls / decisions to flag:**
- Eligibility gate is applied uniformly to every `requestCorrection` proposal, including Story 5.5 payment corrections (spec lists the gate unqualified under "Always"). Consequence: a correction on a settled/zero-balance credit is now refused — previously slip-through. Flag if payment corrections on settled credits were intended to stay possible.
- Derive-delta parses thousands separators (`Money.parse` rules) and accepts negatives only to produce the same over-balance error as manual mode; a zero target balance (full forgiveness) is accepted in derive mode only.
- Submit button is disabled (not just error-on-tap) for over-balance/zero-delta/negative desired balance — stricter than the pre-existing tap-then-error pattern, now covered by tests.
- Debit-direction proposals remain offered (frozen ACs, human decision 2026-11-19).
- `settle_credit_card` Settle entry untouched; settle-sheet/payment-screen `request_adjustment_button` keys and behavior unchanged.
- sprint-status.yaml modification in the working tree is pre-existing (not this story); no schema changes, so v26 remains final.

**Risks / incomplete:**
- The approval-time negative-balance path is verified; the request-time in-transaction re-check is not independently triggerable in single-connection unit tests (only via the pre-read), so it is covered by code review + the parallel approval-path test.
- No PostgreSQL/RLS integration test was run for the Category-6/7 payloads (local Drift tests only); server-side audit trigger behavior is unchanged, but the extended payload shape (`direction`, `reason`, `settled`) has not been validated against any server-side schema constraint on `sync_queue` (payload is a JSON blob - no constraint expected).
- `customer_photo_capture_test.dart` remains an empty committed file failing `flutter test` (pre-existing, out of scope).

## Review Triage Log

### Pass 1 (2026-11-19, frozen review, pre-closure check)

| # | Finding | Verdict | Evidence |
|---|---------|---------|----------|
| 1 | Frozen `Always` eligibility gate reads unqualified — applies to all `requestCorrection` proposals incl. Story 5.5 payment corrections on settled/zero-balance credits. | `high`, resolved | Human approved the carve-out on 2026-11-19 (spec renegotiation): eligibility applies only when `originalPaymentId == null` (adjustments). Payment corrections stay on the 5.5 path; `correction_dao.dart` scopes the gate accordingly (request + approval re-check); DAO test added for the settled-credit payment-correction case. |

### Pass 2 (2026-11-19, all three layers re-run after implementation)

| # | Finding | Verdict | Evidence |
|---|---------|---------|----------|
| 2 | 5.6 eligibility gate blocks Story 5.5 payment corrections on settled credits; correction screen then shows misleading "ineligible" text. | `high`, resolved | Same defect as #1; carve-out approved by the human 2026-11-19 — payment corrections (5.5) now exempt from the gate at both request and approval; new regression test proves the path on a settled credit. |
| 3 | A pending `debit` adjustment approved after the credit settled posts `adjustment_debit` onto a `settled` credit — positive balance strands it outside payment/settle flows. | `high`, patched | Approval now re-checks eligibility inside the transaction (stale credits rejected; owner may still reject); zero-balance approvals flip `settled` + `settled_at` + workflow `disbursed`. |
| 4 | A settlement of a credit at the counter via full forgiveness yields no settlement document/receipt — indistinguishable to Epics 6/7. | `medium`, defer | No "settlement semantics" mandate in this build's frozen intent; routed to deferred-work.md (owner call or Epic 7 derived marker). |
| 5 | Reject confirmation prints `resultingBalanceCents ?? 0` — "Leave the credit balance unchanged 0.00" for every pending correction. | `medium`, patched | `resultingBalanceCents` is written only at approval; the dialog now states the effect without the bogus figure. |
| 6 | Request Balance Adjustment renders enabled on ineligible cards (cancelled, pending-disbursement, settled, zero-balance). | `low`, rejected | Frozen every-card visibility pattern; eligibility enforced at screen + DAO (double-gated); pending case renders disabled with a lock notice. |
| 7 | `_submitBlocked` ignores ineligible credits and unparseable desired balance. | `medium`, patched | Now blocks on ineligibility, unparseable amount/desired balance, over-balance, zero-delta, negative desired; `_blockedReason` feeds inline `adjustment_blocked_reason` hint so the disabled button explains itself. |
| 8 | Derive mode: unparseable desired balance ("-5.00") keeps submit enabled. | `medium`, patched | Folded into #7; covered by `below-zero` widget test (`onPressed` is null). |
| 9 | Every audit/sync payload reuses the shared `correctionAuditEvent` constant; request payloads carry no discriminator. | `low`, patched | `'action': 'request'` added to both request-path payloads; approve/reject/adjust_balance discriminators verified present. |
| 10 | Eligibility logic duplicated across surfaces; dead `credit` parameter on `isAvailableFor`. | `medium`, patched | Screen and DAO share `ReceiptService.isEligibleForPayment`; `CreditAdjustmentAction.isAvailableFor(actor)` drops the dead parameter. |
| 11 | AC test gaps — no debit-direction screen test; no overdue-status eligibility fixture; no settled-credit refusal fixture. | `medium`, patched | New debit-submit widget test (proposal→approve→`adjustment_debit` ledger); new overdue-acceptance DAO test; settled/zero/cancelled refusal covered; rollback path covered. |
| 12 | `epic-5-context.md` line records `5.6 backlog` — stale inside a diff that flips it `in-progress`. | `low`, patched | Context updated to `in-review`. |
| 13 | `sprint-status.yaml` stray trailing blank line added. | `low`, patched | Trailing blank trimmed; anchors preserved. |
| 14 | `_requestAdjustment` reloads the full profile on back-out even when no proposal was submitted. | `low`, patched | Reload only after a recorded proposal; back-out returns early, no re-query. |
| 15 | `_parseMoneyAllowingZero` swallows every failure with bare `catch`. | `low`, patched | Narrowed to `MonetaryException`; anything else propagates. |
| 16 | `AdjustmentInputMode.value` never read — dead field. | `low`, patched | Field and ctor parameter dropped. |
| 17 | Reject dialog `TextEditingController` never disposed. | `low`, rejected | Per open dialog, one controller leaks — disposing synchronously breaks the dismissal animation (three widget tests regressed until reverted); documented at the site. |
| 18 | In-transaction re-check untestable on a single in-memory connection; spec should log a manual step instead of implying verified. | `low`, rejected | Already recorded in the spec's Implementation Notes risks; approval-path rollback test covers the failure shape; rule's fix edits this build's spec — refused. |
| 19 | No PostgreSQL/RLS integration run for the extended Category-6/7 payloads (`reason` carries justification). | `medium`, defer | Deferred-work.md — server-side append owns transport validation; justifications are required in the event by FR-31. |
| 20 | Settle-sheet/payment-screen entries unaudited for ineligible-credit visibility. | `low`, rejected | Spec scope locked those entries unchanged (frozen); gates enforce at submit + DAO; residual divergence documented in Implementation Notes. |
| 21 | Full-forgiveness test never asserts consumers downstream of `settled` (overdue queue drop, dashboard). | `low`, rejected | Settled/zero-balance exclusion from overdue evaluation is already pinned by the Epic 6 suites; the adjustment settlement writes the same terminal row (`settled`, balance 0); double-covering adds nothing. |
| 22 | Settlement-forgiveness produces no receipt — same defect family as #4. | `low`, defer | Covered by #4's deferred-work.md entry. |
| 23 | Spec verification note names "1 pre-existing failure" without filing the 0-byte `customer_photo_capture_test.dart` in this story. | `low`, rejected | Already filed in deferred-work.md (repo-hygiene entry, shared with this story's pass-1 triage). |
| 24 | Overdue credits can never be adjusted or pay — `isEligibleForPayment` requires `disbursed`, but overdue persists `workflowStatus='overdue'`; the spec promises overdue eligibility. | `high`, patched | `applyOverdue` and the Overdue screen now persist `status='overdue'` only (workflow stays `disbursed`, restoring the payment conditional update's contract); `OverdueService` transitions only `active` credits (no phantom re-transition); v28 data-normalize migration (`UPDATE … SET workflow_status='disbursed' WHERE workflow_status='overdue' AND status='overdue'`) repairs drifted rows (seed-verified); overdue acceptance unit-tested; customer suites green. |
| 25 | Approval flips `settled` without restoring `workflowStatus='disbursed'` on a credit that was overdue at approval. | `high`, patched | Zero-balance approvals (and `adjustBalance` forgiveness) now write `workflow_status='disbursed'` alongside `status='settled'` + `settled_at`; v28 normalize covers historical rows too. |
| 26 | `preBalance` read once at dialog open; Approve disabled on stale value. | `low`, rejected | Balance is re-read fresh at dialog open; in-transaction reads + DAO negative guard catch mid-dialog drift — no incorrect commit is possible; re-read-at-tap is pure cost. |
| 27 | Owner-direct `adjustBalance` never transitions a full-balance forgiveness to `settled` — the exact unsettleable-state this story fixes survives on that one path. | `high`, patched | Human-approved amendment (2026-11-19, decision 3): `adjustBalance` now flips `settled` + `settled_at` + workflow `disbursed` on zero; unit-tested. |
| 28 | Correction-review screen shows adjustment vocabulary ("…ineligible for an adjustment…") on the payment-correction screen. | `low`, rejected | Cosmetic copy shared from the gate; 5.5 screen copy is Story 5.5 scope; the answer to #1/#2 may sharpen it further. |

Open items carried after this review: #1/#2 (eligibility scope vs 5.5 corrections) — human decision pending.

