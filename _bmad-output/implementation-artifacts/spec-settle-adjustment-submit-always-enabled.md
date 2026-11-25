---
title: 'Settle Adjustment Submit Always Enabled'
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

**Problem:** On the balance-adjustment form titled **Settle** (reached from the customer-profile adjustment action / settle flow), the Submit button is disabled and the form shows "This credit is not eligible for a balance adjustment." whenever the UI judges the credit ineligible (undisbursed, cancelled, settled, zero balance or pending correction). The operator cannot press Submit to attempt the adjustment they came to make.

**Approach:** Mirror the earlier settle-summary fix (`spec-enable-settle-submit-button.md`): keep the Submit button visible and tappable and remove the upfront eligibility copy, with no eligibility gate in the DAO either — tapping Submit posts the adjustment for any credit in the shop. The correction lock, over-balance guard and all other write-path protections stay unchanged.

## Decisions

- **D1 (target):** `submit_adjustment_button` in `lib/features/customers/presentation/adjustment_proposal_screen.dart`. The `_creditEligibleForAdjustment` gate is removed from `_submitBlocked`, `_blockedReason` and `_submitAdjustment`. Submit is disabled only for invalid input (unparseable amount, negative or over-balance derived target, no-op delta) and while `_isSubmitting`.
- **D2 (copy):** "This credit is not eligible for a balance adjustment." and the pending-correction variant are absent from the form. Input-validation reasons remain; a blocked DAO tap surfaces only the existing inline error widget.
- **D3 (no DAO gate):** `postAdjustmentImmediately` applies no payment-eligibility check — no `enforceEligibility` flag and no `ReceiptService.isEligibleForPayment` call in the adjustment path. Undisbursed, cancelled, settled and zero-balance credits accept the adjustment. Tenant scope, idempotency, correction lock, over-balance guard, mandatory reason, audit/sync entries and zero-balance settlement are unchanged.
- **D4 (renegotiation):** Supersedes the "Leave the adjustment form in `adjustment_proposal_screen.dart` unchanged" boundary in `spec-settle-submit-eligible-on-amount-entry.md` (human-approved 2026-11-24). It also supersedes this spec's initial in-transaction eligibility backstep, removed after the user observed the resulting "not in an adjustable state" error following a Submit tap (2026-11-24).

## Boundaries & Constraints

**Always:** Any accepted adjustment still goes through `CorrectionDao.postAdjustmentImmediately` with the session-derived shop tenant, the per-screen idempotency key, the correction lock, the over-balance guard, the mandatory reason and the immutable ledger + audit/sync entries. A tap on an ineligible credit posts normally; a tap blocked by a pending correction, over-balance or a deactivated actor reuses the existing inline error widget.

**Never:** No schema/migration, permission-catalog, ledger or audit-event change. Do not weaken any remaining DAO guard (tenant scope, correction lock, over-balance, idempotency, deactivated-actor check). Do not add a payment-eligibility gate back to the form or the immediate-adjustment DAO path, and do not reintroduce the eligibility message. Do not change the owner-direct `adjustBalance` path, the owner-approval correction flow, or `ReceiptService.isEligibleForPayment`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| HAPPY_PATH | Eligible credit, valid amount + non-empty reason | Submit enabled and posts one immediate adjustment | N/A |
| INELIGIBLE | Undisbursed / cancelled / settled / zero-balance credit | Button visible and tappable; no eligibility message; one adjustment posts with no error | N/A |
| LOCKED | Pending payment correction | Submit tappable; nothing posted | DAO pending-correction `StateError`, inline |
| INVALID_INPUT | Empty / zero / negative amount, implied over-balance, no-op derived delta | Submit stays disabled; existing inline validation reason shown | `adjustment_blocked_reason` |
| DEACTIVATED | Inactive actor | Nothing posted | Existing `PermissionDeniedException`, inline |
| IN_FLIGHT | `_isSubmitting == true` | Spinner, button disabled | N/A |

</frozen-after-approval>

## Code Map

- `lib/features/customers/presentation/adjustment_proposal_screen.dart` -- sole UI target. The `_creditEligibleForAdjustment` getter and its three uses are gone; `_submitBlocked` / `_blockedReason` cover input validity only. `submit_adjustment_button` :547-559 keeps its unchanged `onPressed` shape.
- `lib/features/customers/data/daos/correction_dao.dart` -- `postAdjustmentImmediately` and the shared `_postBalanceAdjustment` have no eligibility flag or check. The tenant-scoped credit read, correction lock, amount/type validation, idempotency guard, over-balance check, conditional balance update and audit/sync entries remain intact. `adjustBalance` and its owner-only authorization are untouched.
- `lib/features/customers/domain/services/receipt_service.dart` -- unchanged; not called from the adjustment path.
- `test/widget/features/customers/adjustment_proposal_screen_test.dart` -- eligibility tests assert the exact message and "not in an adjustable state" are absent, the button is tappable once a valid amount is entered, and one adjustment posts; the pending-correction test still asserts a DAO rejection with no ledger entry.
- `test/unit/features/customers/correction_dao_test.dart` -- the ineligible-credit case asserts an undisbursed credit still accepts an immediate adjustment and updates the balance; all other DAO guard tests unchanged.
- `_bmad-output/implementation-artifacts/spec-settle-submit-eligible-on-amount-entry.md` (done) -- its frozen "leave the adjustment form unchanged" bullet is renegotiated here; its Spec Change Log records the human decision.

## Tasks & Acceptance

**Execution:**
- [x] `lib/features/customers/presentation/adjustment_proposal_screen.dart` -- remove the UI eligibility gate and both eligibility messages while keeping input validation -- delivers the visible, tappable Submit button.
- [x] `lib/features/customers/data/daos/correction_dao.dart` -- keep the immediate-adjustment path free of an eligibility gate while retaining every other write-path guard -- makes a tap on any credit post successfully.
- [x] Tests in `adjustment_proposal_screen_test.dart` and `correction_dao_test.dart` -- prove the I/O matrix.
- [x] Prior spec artifact updated with the human-approved renegotiation.

**Acceptance Criteria:**
- Given an ineligible credit, when the form renders, then Submit is shown and becomes tappable once valid input is entered, and "This credit is not eligible for a balance adjustment." is absent.
- Given a tap on an ineligible credit, then exactly one immediate adjustment posts with no error message.
- Given a pending correction, deactivated actor or over-balance request, then nothing is posted and the existing inline error is shown.
- Given an eligible credit, then the adjustment still posts immediately with one ledger entry, no pending correction and no lock.

## Implementation Notes

- 2026-11-24: Removed the `_creditEligibleForAdjustment` getter entirely; `_submitBlocked` now blocks only unparseable amounts, over-balance forgiveness, negative derived targets and no-op deltas. `_blockedReason` returns only input-validation explanations.
- 2026-11-24: An in-transaction eligibility backstop (`enforceEligibility`) was briefly added to the adjustment DAO path. The user then observed the "not in an adjustable state" error after tapping Submit and asked for it to be removed; the flag and check were removed. Net behavior: no eligibility guard on `postAdjustmentImmediately`.
- 2026-11-24: The deactivated-actor, cross-shop, idempotency, correction-lock, over-balance and blank-reason guards remain in force, with DAO unit coverage unchanged and one new ineligible-credit acceptance case.
- 2026-11-24: `flutter analyze` clean; adjustment-screen widget tests 11/11; `correction_dao_test.dart` 43/43; profile-level "submitted adjustment posts immediately" regression test passes.

## Verification

**Commands:**
- `flutter analyze` -- No issues found.
- `flutter test test/widget/features/customers/adjustment_proposal_screen_test.dart` -- 11/11 pass.
- `flutter test test/unit/features/customers/correction_dao_test.dart` -- 43/43 pass.
- `flutter test test/widget/features/customers/customer_profile_screen_test.dart --name "submitted adjustment posts immediately"` -- pass (from the preceding build; UI/DAO behavior for eligible credits unchanged).

## Renegotiation of prior frozen specs

- `spec-settle-submit-eligible-on-amount-entry.md` (frozen `Never`, 2026-11-24): "Leave the adjustment form in `adjustment_proposal_screen.dart` unchanged" is superseded by D1–D3 above. The human approved this renegotiation on 2026-11-24; that spec's frozen block and Spec Change Log were updated in place. All other bullets remain in force.
- This spec's own D3 backstop (in-transaction eligibility check) was superseded on 2026-11-24 after the user observed the "not in an adjustable state" error following a Submit tap; the final behavior is D3 as written above.

## Spec Change Log

| Date | Change |
|------|--------|
| 2026-11-24 | Initial bugfix: Submit always tappable, eligibility copy removed, in-transaction DAO eligibility backstop added. |
| 2026-11-24 | Human renegotiation after seeing the backstop's "not in an adjustable state" error: the DAO eligibility check was removed so Submit posts an adjustment on any credit; correction-lock, over-balance and other guards retained. Frozen D3, boundaries, matrix and code map updated to match. |
