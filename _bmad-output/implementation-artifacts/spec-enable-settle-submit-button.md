---
title: 'Enable Settle Submit Button'
type: 'bugfix'
created: '2026-11-24'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: '8fd3727d4e3faa6f8c3cab8fea2b8871fb42b41d'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** On the settle summary screen the Settle confirm button is hidden (not merely disabled) for credits the UI considers ineligible or actors without `recordPayments`, so the user cannot submit a settlement they came to perform.

**Approach:** Make that confirm button visible and tappable in the blocked state, keeping validation feedback, tenant isolation, idempotency and the existing write path intact.

## Decisions

- **D1 (target):** The control is `settle_confirm_button` in `lib/features/customers/presentation/settle_summary_screen.dart`. This renegotiates the earlier deliberate behavior where ineligible credits showed an explanation instead of the button (asserted by `customer_profile_screen_test.dart:1611`).
- **D2 (both gates):** Remove the `canPay` gating of the amount field and the confirm button so both are always shown. `onPressed` stays null only while `_isSubmitting`. The existing "not eligible" / "no permission" text remains as informational copy. `PaymentDao.recordPayment` and `ReceiptService.isEligibleForPayment` are unchanged, so a blocked tap still fails with the existing error and posts nothing.

## Boundaries & Constraints

**Always:** Any accepted submit continues through `PaymentDao.recordPayment` with the actor's session-derived `shopId` and a client idempotency key. Invalid input still produces an inline explanation instead of a silent no-op. No financial operation may be posted twice.

**Never:** No schema/migration, permission-catalog, ledger, audit-event or owner-approval-flow change. Do not reintroduce the owner-approval/correction buttons into the settle screen (already removed by `spec-remove-balance-adjustment-approval-from-settle`). Do not weaken the DAO-level overpayment, over-balance or correction-pending guards.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| HAPPY_PATH | Disbursed active/overdue credit, balance > 0, actor with `recordPayments` | Amount field and Settle button visible; button tappable; full/partial row posts through `PaymentDao.recordPayment` | N/A |
| INELIGIBLE_CREDIT | Settled / zero-balance / pending-disbursement credit | Amount field and Settle button still visible and tappable; nothing is posted | DAO/payment eligibility error shown in the existing error widget |
| NO_PERMISSION | Eligible credit, active actor without `recordPayments` | Amount field and Settle button still visible and tappable; nothing is posted | Existing `PermissionDeniedException` surfaced as an error |
| IN_FLIGHT | `_isSubmitting == true` | Button shows spinner and is disabled (unchanged) | N/A |
| LOCKED | Credit has a pending payment correction | Nothing is posted | Existing correction-pending error |

</frozen-after-approval>

## Code Map

- `lib/features/customers/presentation/settle_summary_screen.dart` -- only file that needs a production change. `canPay` :612 = `_creditEligible` + `_canRecordPayment`; it gates the whole amount-field/button section :752-796. `_creditEligible` :195-196 delegates to `ReceiptService.isEligibleForPayment`; `_canRecordPayment` :188-191 checks active + `recordPayments`. `settle_confirm_button` :774-775 already has the right `onPressed` (`_isSubmitting ? null : _openSettleSheet`); keep it. Sheet rows :359-406 already post through `_recordPayment`. Keep the "not eligible" and "no permission" copy :785-796 as informational text, and keep the amount prefill :149-151.
- `lib/features/customers/data/daos/payment_dao.dart` -- `recordPayment` :105-121 authorizes active + `recordPayments` and throws `PermissionDeniedException`; unchanged, so a blocked tap cannot post.
- `lib/features/customers/domain/services/receipt_service.dart` -- `isEligibleForPayment` :70-75 and `validateAmount` guard the DAO path; unchanged.
- `test/widget/features/customers/customer_profile_screen_test.dart` -- settle group :994+; the ineligible-credit case :1516-1614 asserts `settle_confirm_button findsNothing` :1611 and must now assert presence/tappability plus the existing explanatory copy. Direct-pump style for `SettleSummaryScreen` is already used in this file by the three receipt-preview regression tests added for the prior spec.
- `test/widget/features/customers/payment_screen_test.dart` -- :121-138 pins active/permission gates on the entry point; not a target.
- `lib/features/customers/presentation/credit_settle_action.dart` -- per-card action defined (:43, :74-79) but never instantiated in `lib/`; `customer_profile_screen.dart` passes `onSettle` but never consumes it in `build` (:90-165). Deferred separately (`deferred-work.md`: unwired Settle action); out of scope here.
- `_bmad-output/implementation-artifacts/spec-remove-balance-adjustment-approval-from-settle.md` (done) -- settle approval buttons already removed; its ineligibility backstop is renegotiated by D2.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- unwired Settle action :258-260/:274-276, dropped settle eligibility gate :89-91, prefill clobbering :165-167.

## Tasks & Acceptance

**Execution:**
- [x] `lib/features/customers/presentation/settle_summary_screen.dart` -- remove `canPay` from the amount-field/confirm-button section gate so both are always shown; keep `onPressed` null only while `_isSubmitting` and keep the existing informational copy -- delivers the requested usable submit action.
- [x] `test/widget/features/customers/customer_profile_screen_test.dart` -- replace the ineligible-absence assertion :1611 with presence/tappability assertions, add a direct-pump case for an actor without `recordPayments`, and add a direct-pump full-settlement case -- proves the I/O matrix.
- [x] `_bmad-output/implementation-artifacts/deferred-work.md` -- no change; record only if this build exposes a new defect beyond the already-filed unwired Settle action.

**Acceptance Criteria:**
- Given an ineligible credit or an actor without `recordPayments`, when the settle summary renders, then the amount field and Settle button are visible and the button is tappable (except while submitting).
- Given a tap on Settle in a blocked state, when the sheet option is chosen, then no payment row is created and the existing eligibility/permission error is shown inline.
- Given an eligible credit and a `recordPayments` actor, when Settle in full is chosen, then exactly one payment and receipt are committed through the unchanged DAO path.

## Implementation Notes

- 2026-11-24: The amount field and `settle_confirm_button` are now unconditional in `settle_summary_screen.dart`; `canPay` survives only for the two informational copy blocks. `onPressed` is untouched (`_isSubmitting ? null : _openSettleSheet`), so the button is hidden/disabled solely while a submit is in flight. No DAO, `ReceiptService`, permission, schema, ledger or audit change.
- 2026-11-24: The ineligible test was converted to a direct pump of `SettleSummaryScreen` because its original card-level assertions could never execute — the per-card Settle action is unwired (already filed in `deferred-work.md`). A no-permission direct-pump case and a full-settlement direct-pump case were added; all three pass.
- 2026-11-24: Matrix audit — HAPPY_PATH (full + partial), INELIGIBLE_CREDIT, NO_PERMISSION and LOCKED rows each have a passing covering test. IN_FLIGHT is a non-regression row: the unchanged `onPressed: _isSubmitting ? null : ...` line is present in the diff; no test drives a deliberately slowed DAO to observe the transient spinner, so that row is verified by code inspection rather than a test.
- 2026-11-24: `flutter analyze` clean; targeted tests 6/6 pass; `--name "settle"` 8 pass / 9 fail, all nine failures are the pre-existing unwired per-card Settle action; `payment_screen_test.dart` 2/2 pass.
- 2026-11-24 (review pass 1 patch): added `_creditEligible` to the `settle_sheet_extend` guard so the FR-26 extension is not offered on credits the payment path rejects, and asserted that in the ineligible direct-pump test (with a Shop Owner actor so the guard is actually exercised). KEEP: the always-visible amount field and confirm button, the unchanged `onPressed`, and the unchanged DAO path.

## Verification

**Commands:**
- `flutter analyze` -- expected: No issues found.
- `flutter test test/widget/features/customers/customer_profile_screen_test.dart --name "ineligible credits still offer Settle|actor without recordPayments still sees|directly pumped summary still records|receipt preview|DAO-enforced"` -- expected: 6/6 pass.
- `flutter test test/widget/features/customers/customer_profile_screen_test.dart --name "settle"` -- expected: 8 pass / 9 fail; all nine failures are the pre-existing unwired per-card Settle action documented in `deferred-work.md`.
- `flutter test test/widget/features/customers/payment_screen_test.dart` -- expected: 2/2 pass (no regression on the entry-point gates).

## Review Triage Log

Pass 1 — three layers (Blind Hunter N=10 from 256.62 kB, Edge Case Hunter, Verification Gap) against the unified diff since `8fd3727`, which also contains uncommitted work present at build start. Verdicts are rendered against the actual code, not the reviewers' severity labels.

| # | Finding | Verdict | Evidence |
|---|---------|---------|----------|
| 1 | BH: scratch/log files (`output.txt`, `summary.txt`, `test_output.txt`, `_tmp/claims credit details.txt`) are in the diff and unreadable/mojibake. | `low` | Real developer noise, but all four were already staged additions in the working tree at build start (initial `git status` shows `A` for each) and are not caused by this story. |
| 2 | BH: `summary.txt` and `test_output.txt` duplicate the same 188-line log. | `low` | Same pre-existing artifacts as #1; no new file was created by this build. |
| 3 | BH: committed test logs are stale relative to the rewritten tests. | `low` | Same root cause as #1; the logs predate the ineligible-test rewrite made by this story. |
| 4 | BH: failure counts contradict across artifacts (7/9, 10, 34/10). | `false` | They are separate runs at different times/scopes; this build re-ran `--name "settle"` and observed 7 pass / 9 fail, matching the spec. |
| 5 | BH: spec `in-review` while notes claim work complete. | `false` | `in-review` is the required workflow state set at the start of step 4; it is not a claim of completion. |
| 6 | BH: `IN_FLIGHT` matrix row has no test. | `low` | True and recorded in Implementation Notes, but observing the transient spinner requires a deliberately slowed DAO; the fix is more than a direct correction and the row is a non-regression guard on an unchanged line. Rejected per the low-finding rule. |
| 7 | BH: eligible credit without `recordPayments` shows two contradictory messages. | `false` | The pre-change code had the same two independent blocks: an `else` for `!canPay` plus a separate `!canPay && _creditEligible && !_canRecordPayment` block. The diff preserves both conditions verbatim, so this is not introduced here. |
| 8 | BH: `postAdjustmentImmediately` has no server-side RLS authorization. | `medium` | Real but pre-existing sibling-spec work, explicitly deferred in the prior spec's triage #9; no auth/permission surface was changed here. |
| 9 | BH: `postAdjustmentImmediately` does not re-check credit eligibility in the transaction. | `low` | Real but pre-existing sibling-spec work, already deferred in that spec's triage #1/#7; this story changes no DAO code. |
| 10 | BH: `recordedAt` accepted unvalidated by DAO entry points. | `false` | Both public callers pass `DateTime.now().toUtc()` (`adjustment_proposal_screen.dart:312`, `settle_summary_screen.dart:271`); no caller-supplied timestamp is reachable, as the prior spec's triage #2 established. |
| 11 | BH: idempotency key is per screen instance, so a retry after ambiguous commit can double-post. | `low` | Real but pre-existing sibling-spec work; the prior spec deliberately patched to retain the per-instance key (triage #16), and this story does not touch that screen. |
| 12 | BH: irreversible immediate adjustment has no confirmation step. | `false` | The prior spec's frozen decision D3 explicitly makes Submit a single immediate action; its triage #15 refuted the same claim. No new intent here. |
| 13 | BH: this spec lacks a "Renegotiation of prior frozen specs" section. | `low` | True as a documentation-traceability gap, but the fix is to edit this build's spec, which is prohibited during triage. Rejected. |
| 14 | BH: `credit_details_screen.dart` principal removal / no-symbol balance is inaccurate and unverified. | `medium` | Real user-visible change, but pre-existing working-tree work from the sibling spec already deferred there (triage #9/#15/#17). |
| 15 | BH: contradictory "Settle" labels survive on adjustment entry points. | `low` | Real but pre-existing sibling-spec work, already filed in `deferred-work.md` as stale Settle labels. |
| 16 | BH: `adjust_balance` audit payload cannot distinguish cashier from owner. | `false` | The payload records the actual submitter's `actorId`; the prior spec's triage #14 refuted the same claim. |
| 17 | VG: credit-details balance/principal display has no effective verification. | `medium` | Same finding as #14 with harder evidence (stale assertion at `credit_details_screen_test.dart:89`); pre-existing, already deferred. |
| 18 | VG: screen-level idempotency-key reuse unverified. | `low` | Same root cause as #11; the prior spec's DAO test supplies its own key and no widget test drives two submits, but this is pre-existing work outside this story. |
| 19 | VG (Other): per-card Settle action is unwired, so the newly visible button is unreachable in the real flow. | `high` | Confirmed: `CreditSettleAction` has zero instantiations in `lib/`, `onSettle` is passed but unused, ~9 settle tests fail at that key. Pre-existing at baseline and already filed in `deferred-work.md`; the human explicitly declined the reachability option (Q1-D). |
| 20 | EC: owner can extend the due date on an ineligible credit from the newly reachable sheet, posting an FR-26 extension/audit the payment path rejects. | `medium` | Verified at `settle_summary_screen.dart:391`: the guard is `_canExtendDueDate && credit.status != CreditStatus.settled` — it does **not** include `_creditEligible` as the reviewer's quoted snippet claimed. `OverdueDao.grantDueDateExtension` rejects only settled/cancelled (`:157`), so a pending-disbursement or zero-balance credit can be extended. Exposed by this change (the sheet is now reachable for such credits). |

**Grouping/routing:** #8/#9/#11/#18 share the pre-existing sibling-spec adjustment path; #14/#17/#15/#19 are pre-existing working-tree defects already filed; #1/#2/#3 are pre-existing scratch artifacts. Those groups route to `defer`. #4/#5/#7/#10/#12/#16 are refuted; #6/#13 are rejected by rule; #20 is a genuine regression exposed by this change and routes to `patch` (add `_creditEligible` to the extension-row guard plus a regression assertion). No `intent_gap` or `bad_spec` survives, so there is no loopback.
