---
title: 'Settle Submit Eligible On Amount Entry'
type: 'feature'
created: '2026-11-24'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: '8fd3727d4e3faa6f8c3cab8fea2b8871fb42b41d'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** On the Settle summary screen, tapping **Settle** only opens an options sheet; the amount already entered must be confirmed a second time before anything is posted. The user wants the typed amount to be the submit action itself.

**Approach:** Make the Settle button post the entered amount directly — a full settlement when it equals the balance, an ordinary partial payment when it is lower — reusing the existing payment path. This renegotiates the completed `spec-enable-settle-submit-button.md` decision that the sheet is the confirmation step.

## Decisions

- **D1 (direct submit):** `settle_confirm_button` calls the existing `_recordPayment` path with the entered amount instead of `_openSettleSheet`. Amount validation stays at post time, and the full/partial success behavior (pop with receipt / stay and refresh) is unchanged.
- **D2 (sheet):** The options sheet is no longer opened by the Settle button. A separate "Extend due date" control takes its place on the summary screen.
- **D3 (extension control):** A separate "Extend due date" control replaces the sheet row on the summary screen and is shown to any active actor.
- **D4 (extension authorization):** `OverdueDao.grantDueDateExtension` remains Shop-Owner-only. A non-owner's tap reaches the DAO and its `PermissionDeniedException` is reported through `_extendDueDate`'s existing SnackBar error path; no authorization, permission-catalog or role rule changes.

## Boundaries & Constraints

**Always:** Any accepted payment goes through `PaymentDao.recordPayment` with the actor's session-derived `shopId`, a client idempotency key, and the existing inline error reporting. The amount field stays pre-filled with the full balance and editable. Full settlement still pops with its receipt; a lower amount posts a partial payment and stays on the screen with a refreshed balance and receipt. Extension still goes through `OverdueDao.grantDueDateExtension` unchanged.

**Never:** No schema, migration, permission-catalog, ledger, audit-event or owner-approval-flow change. Do not weaken DAO-level authorization, eligibility, overpayment or correction-lock guards. The adjustment form in `adjustment_proposal_screen.dart` was left unchanged *by this spec*; its Submit-button eligibility behavior was renegotiated on 2026-11-24 by `spec-settle-adjustment-submit-always-enabled.md` (see Spec Change Log).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| FULL_SETTLEMENT | Amount equals the outstanding balance, eligible credit, permitted actor | One full settlement and receipt are posted; screen pops with the receipt | N/A |
| PARTIAL_PAYMENT | Amount lower than the balance | One partial payment is posted; screen stays, balance and receipt refresh | N/A |
| INVALID_INPUT | Empty, zero, negative or over-balance amount | Nothing is posted; inline validation error | Existing `settle_validation_error_display` |
| BLOCKED | Pending correction, settled/cancelled/undisbursed credit, or actor without `recordPayments` | Nothing is posted | Existing eligibility/permission errors inline |
| EXTEND_OWNER | Shop Owner taps the new extension control | Existing FR-26 extension and audit path run unchanged | N/A |
| EXTEND_NON_OWNER | Non-owner taps the new extension control | Control is visible; nothing is extended | Existing `PermissionDeniedException` via the extension SnackBar |

</frozen-after-approval>

## Code Map

- `lib/features/customers/presentation/settle_summary_screen.dart` -- sole production target. `settle_confirm_button` :780-790 currently calls `_openSettleSheet`; change it to parse `settle_amount_input` :764-775 and call `_recordPayment` directly. `_recordPayment` :223-316 already validates the amount with `ReceiptService.validateAmount`, posts via `PaymentDao`, pops on full settlement :291-297, and refreshes on partial :299-302 — reuse it, do not reimplement. `_openSettleSheet` :324-414 exists only for this button; retire its full/partial rows and keep `_extendDueDate` :421-511. Add a separate extension control visible to any active actor that calls `_extendDueDate` (its existing SnackBar error path reports a non-owner's `PermissionDeniedException` at :502-510 — verify and preserve it). Keep prefill :146-151, `canPay` copy :614 and error widgets :623-646.
- `lib/features/customers/data/daos/payment_dao.dart` -- `recordPayment` :105-121 authorizes active + `recordPayments`; eligibility, overpayment and correction lock enforced at :163-234. Unchanged.
- `lib/features/customers/domain/services/receipt_service.dart` -- `isEligibleForPayment` :70-75 and `validateAmount` :83-97. Unchanged.
- `lib/features/customers/data/daos/overdue_dao.dart` -- `grantDueDateExtension` :128-197 keeps the Shop-Owner-only check at :138-140. Unchanged.
- `test/widget/features/customers/customer_profile_screen_test.dart` -- settle group :994+ must be rewritten where it taps `settle_confirm_button` then a sheet row: ineligible :1516, no-permission :1645, full settlement :1716, partial :1823, overpayment :1900, pending correction :1955, owner extension :2009, non-owner extension :2118. Keep the DAO-enforced regression cases and add direct-amount cases.
- `lib/features/customers/presentation/adjustment_proposal_screen.dart` -- the other "Settle"-titled form; out of scope and unchanged.
- `_bmad-output/implementation-artifacts/spec-enable-settle-submit-button.md` (done) -- established the always-visible button and sheet as confirmation; this spec renegotiates the sheet-confirmation decision only.
- `_bmad-output/implementation-artifacts/spec-enable-settle-submit-button.md` (done) -- removed `canPay` gating so amount field and button are always shown; explicitly kept `onPressed` unchanged and the options sheet as confirmation.

## Tasks & Acceptance

**Execution:**
- [x] `lib/features/customers/presentation/settle_summary_screen.dart` -- make `settle_confirm_button` post the entered amount through `_recordPayment`; retire the options sheet but keep `_extendDueDate` reachable via a new always-visible extension control -- delivers direct submit from the typed amount.
- [x] `test/widget/features/customers/customer_profile_screen_test.dart` -- rewrite the settle-group tests that tapped sheet rows into direct-amount cases, and assert the extension control is visible to non-owners but rejected by the DAO -- proves the I/O matrix.
- [x] `_bmad-output/implementation-artifacts/deferred-work.md` -- no change unless the rewrite exposes a new defect beyond the already-filed unwired Settle action.

**Acceptance Criteria:**
- Given an amount equal to the balance, when Settle is tapped, then exactly one full settlement and receipt are posted and the screen returns to the profile.
- Given a lower amount, when Settle is tapped, then exactly one partial payment is posted and the screen stays with a refreshed balance and receipt.
- Given an invalid or blocked amount/credit/actor, when Settle is tapped, then nothing is posted and the existing inline error is shown.
- Given a non-owner, when the extension control is tapped, then nothing is extended and the existing permission error is surfaced.

## Review Triage Log

Pass 1 — three layers (Blind Hunter N=10 from 285.104 kB, Edge Case Hunter, Verification Gap) against the unified diff since `8fd3727`, which also contains the two completed sibling specs and their working-tree artifacts. Verdicts are rendered against the actual code and this spec's approved frozen block.

| # | Finding | Verdict | Evidence |
|---|---------|---------|----------|
| 1 | BH: scratch/log artifacts (`output.txt`, `summary.txt`, `test_output.txt`, `_tmp/claims credit details.txt`) in diff, unreadable mojibake. | `low` | Real developer noise, but all four were staged additions before this build and are not caused by this story; already filed by the sibling spec. |
| 2 | BH: `summary.txt` and `test_output.txt` are duplicate logs. | `low` | Same pre-existing artifacts as #1. |
| 3 | BH: failure counts contradict across artifacts. | `false` | They are separate runs at different scopes/times; this build re-ran `--name "settle"` and observed 15 pass / 2 fail, matching the spec. |
| 4 | BH: change contradicts the sibling spec's frozen `onPressed` / "keep the sheet" notes. | `false` | This spec's approved frozen D1/D2 explicitly renegotiate that decision ("renegotiates the completed `spec-enable-settle-submit-button.md` decision that the sheet is the confirmation step"); the diff implements THIS spec. |
| 5 | BH: sheet removal contradicts the sibling spec's D1/boundaries. | `false` | Same renegotiation as #4; this spec's D2 explicitly retires the sheet. |
| 6 | BH: removing the sheet removes the confirmation step. | `false` | D1 explicitly requires a single tap to post the typed amount; removal of confirmation is the approved intent, not a defect. |
| 7 | BH: extension control visible to non-owners contradicts owner-only FR-26 specs. | `false` | D3/D4 and the human's Q2/Q3 answers explicitly chose "UI for anyone, DAO stays owner-only"; `OverdueDao` is unchanged. |
| 8 | BH: `IN_FLIGHT` matrix row has no test. | `false` | That row belongs to the sibling spec; this spec's matrix has no IN_FLIGHT row and its notes never claim one. |
| 9 | BH: ineligible-credit test taps with an empty amount and only reaches the "positive" validation error, never the eligibility error. | `low` | True: the BLOCKED row's ineligible-credit sub-case is unverified (the row is otherwise covered by passing pending-correction and no-permission tests). The fix is a direct test extension, so it survives and routes to `patch`. |
| 10 | BH: contradictory "not eligible" copy for a no-permission actor. | `low` | Pre-existing wording from the sibling spec, unchanged by this story and already filed there. |
| 11 | BH: `credit_details_screen.dart` principal/no-symbol change unverified. | `medium` | Real but pre-existing working-tree work from the sibling specs, already filed twice in `deferred-work.md`. |
| 12 | BH: no `.gitignore` change for scratch logs. | `low` | Same pre-existing artifacts as #1; not caused by this story. |
| 13 | BH: sibling spec has `review_loop_iteration: 0` and no `Spec Change Log` despite a recorded patch. | `low` | Real documentation inconsistency in the previous build, untouched here; fix would edit another spec. |
| 14 | BH: sibling spec lacks a "Renegotiation of prior frozen specs" section. | `low` | Same pre-existing documentation hygiene as #13. |
| 15 | BH: `deferred-work.md` accumulates duplicate entries. | `low` | Pre-existing documentation hygiene, not caused by this story. |
| 16 | BH: per-card Settle action unwired, screen unreachable, ~9 tests red. | `high` | Confirmed at baseline and already filed; the human explicitly declined the reachability option in the prior build. |
| 17 | BH: `postAdjustmentImmediately` no in-transaction eligibility re-check. | `low` | Pre-existing sibling-spec work; this story changes no DAO code. |
| 18 | BH: permissionless adjustment has no server-side RLS predicate. | `medium` | Pre-existing sibling-spec work, already deferred there; out of this UI story's scope. |
| 19 | BH: misleading "Settle" labels on adjustment entry points. | `low` | Pre-existing sibling-spec work, already filed. |
| 20 | EC: "always-visible extension control" claim contradicts the credit-state/`isActive` guard. | `false` | D3's "any active actor" is an actor-role statement (Q2/Q3), not a credit-state statement; the `_creditEligible && status != settled` guard is the preserved prior review patch and `isActive` matches "active actor". |

**Grouping/routing:** #9 is a genuine verification gap exposed by this story and routes to `patch` (extend the ineligible test with a valid amount so it reaches the eligibility error). #1/#2/#10/#11/#12/#13/#14/#15/#16/#17/#18/#19 are pre-existing working-tree or sibling-spec issues already filed in `deferred-work.md`; the high-severity reachability item (#16) was explicitly declined by the human. #3/#4/#5/#6/#7/#8/#20 are refuted. Verification Gap reported no gaps. No `intent_gap` or `bad_spec` survives, so no loopback.

## Implementation Notes

- 2026-11-24: `settle_confirm_button` now calls `_recordPayment()` directly; `_openSettleSheet` and its full/partial/cancel rows were retired, along with the unused `_enteredAmount` / role-gated `_canExtendDueDate` getters. `_recordPayment`'s `amountOverride` parameter was removed (the sheet was its only caller); its validation and posting logic is unchanged.
- 2026-11-24: A separate `settle_extend_due_date_button` replaces the sheet row, shown to any active actor on eligible, unsettled credits. The Shop-Owner-only rule stays in `OverdueDao.grantDueDateExtension`; a non-owner's tap surfaces the existing `PermissionDeniedException` via `_extendDueDate`'s SnackBar path. The credit-state guard from the prior review patch was preserved to avoid re-exposing extension on ineligible/settled credits.
- 2026-11-24: Matrix audit — FULL_SETTLEMENT, PARTIAL_PAYMENT, INVALID_INPUT, BLOCKED, EXTEND_OWNER and EXTEND_NON_OWNER each have a passing test. All rewritten direct-amount cases pass.
- 2026-11-24 (review pass 1 patch): the ineligible-credit test now also taps with a valid amount, reaching the "exceeds the outstanding balance" eligibility error, so the BLOCKED row's ineligible sub-case is actually exercised. KEEP: direct `onPressed: _recordPayment`, retired options sheet, always-visible-but-DAO-authorized extension control, unchanged DAO paths.
- 2026-11-24: `flutter analyze` clean; `--name "settle"` 15 pass / 2 fail — both failures are the pre-existing unwired per-card Settle action documented in `deferred-work.md`; `payment_screen_test.dart` 2/2 pass.

## Verification

**Commands:**
- `flutter analyze` -- expected: No issues found.
- `flutter test test/widget/features/customers/customer_profile_screen_test.dart --name "settle"` -- expected: 15 pass / 2 fail; both failures are the pre-existing unwired per-card Settle action documented in `deferred-work.md`.
- `flutter test test/widget/features/customers/payment_screen_test.dart` -- expected: 2/2 pass (no regression on entry-point gates).

## Spec Change Log

| Date | Change |
|------|--------|
| 2026-11-24 | Human-approved renegotiation of the frozen `Never` bullet: the "leave the adjustment form unchanged" constraint is superseded by `spec-settle-adjustment-submit-always-enabled.md`. That follow-up makes the form's Submit button always tappable, removes the "not eligible for a balance adjustment" copy, and removes eligibility gating from `CorrectionDao.postAdjustmentImmediately` so a tap posts the adjustment. All other frozen bullets remain in force. |
