---
title: 'Post Settle Adjustment Immediately Without Owner Approval'
type: 'feature'
created: '2026-11-23'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: '8fd3727d4e3faa6f8c3cab8fea2b8871fb42b41d'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The "Settle" entry points on the customer profile and payment screen open `AdjustmentProposalScreen`, whose submit button is labelled "Submit for Shop Owner approval", requires `requestCorrections`, and records a `pending_approval` correction that locks the credit until a Shop Owner decides. The human wants the submit to be usable by anyone and to take effect immediately, with no approval step.

**Approach:** Post the submitted adjustment directly to the immutable ledger through the existing balance-adjustment write path, for any active authenticated actor, with no permission gate and no pending-approval record. Update all related copy so the UI no longer promises a future owner decision.

## Decisions

- **D1 (who):** "Anyone" means any active, authenticated user in the shop tenant — no `requestCorrections` or owner-role requirement. Deactivated accounts are still rejected.
- **D2 (what posts):** The adjustment is applied immediately as an immutable `adjustment_credit` / `adjustment_debit` ledger entry with pre/post balance snapshot, sync/audit entry (`adjust_balance`, category 7), and the credit transitions to `settled` when the balance reaches zero — identical to the existing direct adjustment write path.
- **D3 (submit UI):** The submit button reads "Submit". Form subtitles, field labels, previews and the trailing note describe an immediate change, not a proposal awaiting approval.
- **D4 (unchanged):** Payment-correction requests and their owner-approval/lock flow, the correction review queue, the `CorrectionAdjustmentScreen`, all permissions, schema, ledger rules, and the settle summary screen (already stripped of approval buttons) are untouched.

## Boundaries & Constraints

**Always:**
- Tenant isolation: every read/write is scoped to the actor's `shopId`; the DAO never trusts a UI-supplied shop.
- Idempotency: a client UUID still guards against duplicate submissions and re-transmits resolve to the already-recorded ledger entry.
- The correction-pending lock still blocks adjustments (and payments) while a genuine payment correction is pending; it is enforced in the DAO.
- Reason remains mandatory; over-balance forgiveness and invalid/ineligible credits are rejected with the existing errors.
- Full/partial settlement, receipts, audit and the FR-26 owner-only extension stay exactly as they are.

**Never:**
- No schema/migration, permission-catalog, ledger-semantics or audit-event change.
- Do not remove the owner-approval flow for payment corrections, nor modify the correction review queue or `CorrectionAdjustmentScreen`.
- Do not change the existing owner-only `adjustBalance` authorization contract — add a separate immediate path instead.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| HAPPY_PATH | Cashier (no `requestCorrections`), eligible credit, credit-direction 200.00, reason | Ledger entry `adjustment_credit` posted immediately; balance drops by 200.00; no `pending_approval` correction row; no lock | N/A |
| DEBIT | Manager, higher desired balance | `adjustment_debit` posted immediately; balance increases | N/A |
| FULL_WRITE_OFF | Desired balance 0.00 | Balance becomes 0; credit status `settled` in same transaction | N/A |
| LOCKED | Credit with a pending payment correction | Adjustment refused; no ledger entry | Existing correction-pending `StateError` |
| INELIGIBLE | Cancelled / undisbursed / settled credit | Submit disabled; nothing posted | Existing "not eligible" message |
| DEACTIVATED | Deactivated actor | Submit rejected by the DAO | `PermissionDeniedException` |
| IDEMPOTENCY | Same key submitted twice | One ledger entry; second resolves to first | N/A |

</frozen-after-approval>

## Code Map

- `lib/features/customers/data/daos/correction_dao.dart` -- `adjustBalance` L1009-1249 is the owner-gated immediate write path (auth L1018-1028, shared body L1030-1249). Reuse its validation/transaction/audit body; add an active-actor-gated entry point that calls it via a shared private helper. `requestCorrection` L163 (permission gate + `pending_approval` + lock) is what the submit calls today and must stop calling.
- `lib/features/customers/presentation/adjustment_proposal_screen.dart` -- `_canRequestAdjustment` L94-98, permission check L281-287, `requestCorrection` call L315-324, approval copy L13-37/L474-486/L523/L556/L573/L601/L606-609. Submit button key `submit_adjustment_button` L590.
- `lib/features/customers/presentation/payment_screen.dart` L260 and `customer_profile_screen.dart` L373 -- success snackbars still say "Adjustment proposed. Awaiting Shop Owner approval." after the form pops `true`.
- `lib/features/customers/presentation/credit_adjustment_action.dart` L9 -- card-action doc still describes owner approval.
- `test/widget/features/customers/adjustment_proposal_screen_test.dart` -- asserts `pending_approval` rows and a later owner `approveCorrection`; rewrite to assert immediate ledger entries, plus a cashier (no `requestCorrections`) happy-path case.
- `test/unit/features/customers/correction_dao_test.dart` L702+ -- existing `adjustBalance (Shop Owner only)` group; add a parallel group for the new immediate method and keep the owner group green.
- `_bmad-output/implementation-artifacts/spec-5-6-staff-proposed-owner-approved-balance-adjustments-partial-forgiveness.md` -- `done` historical spec whose owner-approval mandate for this submit is superseded here; leave unchanged.

## Tasks & Acceptance

**Execution:**
- [x] `lib/features/customers/data/daos/correction_dao.dart` -- extract the body of `adjustBalance` into a private shared helper; keep `adjustBalance` owner-gated and add an active-actor-gated immediate adjustment entry point that uses the same helper -- posts without approval while preserving idempotency, lock, audit and zero-balance settlement.
- [x] `lib/features/customers/presentation/adjustment_proposal_screen.dart` -- remove the permission getter/check and approval imports, call the immediate DAO path with the direction mapped to `adjustment_credit`/`adjustment_debit`, relabel the submit button and rewrite all proposal/approval copy -- delivers "anyone can submit, applied now".
- [x] `lib/features/customers/presentation/payment_screen.dart` + `customer_profile_screen.dart` + `credit_adjustment_action.dart` -- update post-submit snackbar copy and the card-action doc -- no UI still promises owner approval.
- [x] `test/widget/features/customers/adjustment_proposal_screen_test.dart` + `test/unit/features/customers/correction_dao_test.dart` -- convert pending-approval assertions to immediate-ledger assertions, add cashier happy path, deactivated actor and idempotency cases, and unit tests for the new DAO entry point -- proves the matrix.

**Acceptance Criteria:**
- Given a cashier without `requestCorrections`, when they submit a valid adjustment, then an adjustment ledger entry is committed immediately and no pending correction or lock is created.
- Given a full write-off, when submitted, then the credit is `settled` in the same transaction as the ledger entry.
- Given a pending payment correction, when an adjustment is submitted, then the DAO lock blocks it with the existing error.
- Given any submit, then the audit/sync entry records the actual submitting actor and the existing `adjust_balance` event.
- Given the adjustment screen, when rendered, then no copy mentions Shop Owner approval or a pending decision.

## Implementation Notes

- 2026-11-23: Added `CorrectionDao.postAdjustmentImmediately`, gated only on `actor.isActive`, sharing the extracted `_postBalanceAdjustment` helper with the unchanged owner-only `adjustBalance`. No schema, permission-catalog, ledger or audit-event change.
- 2026-11-23: `AdjustmentProposalScreen` now posts immediately via the new DAO path (direction mapped to `adjustment_credit` / `adjustment_debit`); submit button reads "Submit" and all approval/pending copy was rewritten. The profile card and payment-screen "Settle" entry points are now active-only so a cashier can actually reach the form (D1); payment-correction gates remain unchanged.
- 2026-11-23: Verification — `flutter analyze`: No issues found. Targeted tests: 53/53 pass (11 widget + 42 DAO). `customer_profile_screen_test.dart`: 10 failures, all pre-existing at baseline (unwired per-card Settle action from the sibling spec); no new failures. Every I/O matrix row has a passing covering test.

## Spec Change Log

<!-- Append-only; populated by step-04 during review loops. -->

- 2026-11-23 (review pass 1): no `intent_gap` or `bad_spec` findings, so no frozen-intent change and no loopback. Five `patch` items were applied: stale DAO/profile/action comments corrected, the idempotency key retained per screen instance, and a new payment-screen widget test covering the active-only Settle gate. `defer` entries (pre-existing credit-details work, unwired per-card Settle action, server RLS authorization, stale planning docs) were recorded in the triage log and `deferred-work.md` per route. KEEP: the shared `_postBalanceAdjustment` helper, owner-only `adjustBalance`, and the immediate `postAdjustmentImmediately` entry point all survived re-derivation.

## Review Triage Log

Pass 1 (2026-11-23) — three layers (Blind Hunter N=10, Edge Case Hunter, Verification Gap) against the unified diff since `8fd3727`. That diff also contains pre-existing in-flight work from the sibling settle spec; those findings are deferred, not caused here.

| # | Finding | Verdict | Evidence |
|---|---------|---------|----------|
| 1 | EC: DAO has no status/workflow eligibility guard | `low` | True at DAO level: `_postBalanceAdjustment` (correction_dao.dart:1148-1182) checks only existence, the correction lock and non-negative balance. Not reachable from either screen, which gate eligibility. The false claim that the DAO enforces it is real; grouped with #7/#13. |
| 2 | EC: `recordedAt` accepted unvalidated | `false` | Both public entry points are called only with `DateTime.now().toUtc()` from their screens; no caller supplies a chosen timestamp, so backdated ledger rows are not reachable. |
| 3 | EC: principal display removed from credit cards | `medium`, defer | Real user-visible loss, but pre-existing working-tree work from the sibling spec (its triage #9/#15/#17), outside this story's intent. |
| 4 | VG: payment-screen active-only gate has no test | `medium`, patch | Confirmed: no payment-screen widget test exists; `multi_credit_selection_test.dart` checks navigation only. D1's core AC can regress on this entry point with a green suite. |
| 5 | VG: balance format change unpinned | `low`, defer | Pre-existing credit-details change; stale assertion at `credit_details_screen_test.dart:91` was already unreachable at baseline. |
| 6 | VG (other): `tester.fling` finds no ListView | `low`, defer | Pre-existing failure in the same untouched credit-details test file. |
| 7 | BH: no DAO eligibility guard, inconsistent settled credit | `low` | Same root cause as #1; the settled-credit write is unreachable through the UI. |
| 8 | BH: contradicts PRD FR-22, no change proposal | `medium`, defer | The human-approved frozen Intent/Decisions in this spec are the renegotiation record; updating historical PRD/UX artifacts was not part of the approved intent. |
| 9 | BH: no server-side RLS authorization for cashier adjustments | `medium`, defer | D4 explicitly excludes permission-catalog/server changes; server enforcement is a separate work stream. |
| 10 | BH: per-card Settle action unwired, 10 red settle tests | `high`, defer | Pre-existing at baseline and documented in the sibling spec's Implementation Notes #18; this story neither caused nor fixed it. |
| 11 | BH: payment-screen changes untested | `medium`, patch | Same root cause as #4. |
| 12 | BH: stale comments in `customer_profile_screen.dart` | `low`, patch | Confirmed at :151-152 and :181-182: still describe `requestCorrections` gating and pending-proposal lock after the action was made active-only and immediate. |
| 13 | BH: stale DAO comments after the refactor | `low` | Confirmed at correction_dao.dart:1157, 1244-1246: "Story 5.6", "owner adjustment", "mirroring the approval path" on a path now shared with cashiers; grouped with #1/#7. |
| 14 | BH: audit payload cannot distinguish owner vs cashier | `false` | The payload records `actorId` of the actual submitter (correction_dao.dart:1205). The approved intent removes approval, so there is no approver to record; adding a bypass marker adds public surface. |
| 15 | BH: no confirmation step / no debit cap | `false` | D3 explicitly makes Submit a single immediate action; uncapped debit adjustments are pre-existing adjustment semantics, and capping would be new intent. |
| 16 | BH: fresh idempotency key on every attempt | `medium`, patch | Confirmed at adjustment_proposal_screen.dart:298. The removed pending-correction lock was the only other duplicate guard, so a retry after an ambiguous commit can now double-post. |
| 17 | BH: unrelated credit-details change in diff | `medium`, defer | Same root cause as #3. |
| 18 | BH: proposal-era naming survives | `low`, reject | Real but cosmetic; a rename spans public classes, widget keys and test files — not a direct correction, and no user-visible harm. |
| 19 | BH: spec in-review / UX docs still describe approval | `low`, defer | `in-review` is normal review-stage state (finalized at present). Stale UX docs share root cause with #8 and are outside the approved code-scope intent. |

**Grouping/routing:** #1/#7/#13 (stale DAO/eligibility claims), #12 (stale profile comments), #16 (idempotency key) and #4/#11 (payment-screen test) are patch. Defer groups: #3/#5/#6/#17 (pre-existing credit-details work), #8/#19 (planning-doc renegotiation), #9 (server RLS), #10 (unwired Settle action). #2/#14/#15 are refuted; #18 is rejected as low-with-large-fix. No `intent_gap` or `bad_spec` survives, so no loopback: all patches go to the existing implementation agent, then verification is re-run.

## Verification

**Commands:**
- `flutter analyze` -- expected: No issues found.
- `flutter test test/widget/features/customers/adjustment_proposal_screen_test.dart` -- expected: all pass with immediate-post assertions.
- `flutter test test/unit/features/customers/correction_dao_test.dart` -- expected: owner `adjustBalance` group and new immediate group all pass.
- `flutter test test/widget/features/customers/customer_profile_screen_test.dart` -- expected: no new failures.
