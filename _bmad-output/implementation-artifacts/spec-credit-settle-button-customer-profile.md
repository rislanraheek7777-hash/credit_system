---
title: 'Credit Settle Button in Customer Profile'
type: 'feature'
created: '2026-11-16'
status: 'in-review'
route: 'dispatch'
baseline_commit: '074918d5ca31581f205f3205ac23e5222d537773'
review_loop_iteration: 1
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Settling a credit from the customer profile requires opening the credit's payment screen and typing the exact outstanding balance by hand. There is no direct settle affordance, so full settlement is slow and easy to mistype.

**Approach:** Add a per-credit-card "Settle" action on the customer profile for payment-eligible credits. Tapping it opens a dedicated **Settle summary screen** that shows the borrower, the credit identity (reference, principal, agreed term, due date, status), the outstanding balance in large type, and the collateral still at stake — with the amount pre-filled to the full outstanding balance. Tapping **Settle** on that screen opens a bottom sheet of **settlement options**: **Settle in full** (posts the outstanding balance), **Partial settlement** (focuses the amount field for a lower amount, then posts it as an ordinary partial payment that stays on screen), **Request Balance Adjustment** (Story 5.6 partial-forgiveness proposal, staff-initiated, Shop Owner approves), and **Extend due date** (FR-26, Shop Owner only — new date plus a mandatory reason; the credit resets to Active). Settlement itself goes through the existing payment path (receipts, idempotency, overpayment protection, correction lock, audit unchanged). A confirmed full settlement returns to the profile with a confirmation. Gated by `recordPayments`, mirroring the draft-agreement action's per-card presentation.

## Boundaries & Constraints

**Always:**
- The settle amount is exactly the credit's current outstanding balance — full settlement by default, never more (the amount field pre-fills it; **Settle in full** posts the balance exactly).
- Offered only for credits eligible for payment: disbursed, status `active` or `overdue`, balance > 0 (reuse the existing eligibility rule; the summary screen enforces it as the backstop).
- Hidden unless the actor is active and holds `recordPayments`.
- A Settle button appears on each credit card (per-credit, every card for a `recordPayments` holder per the human's 2026-11-18 visibility restore), mirroring the existing draft-agreement action.
- Tapping Settle opens the settle summary screen: borrower, credit identity (reference / principal / term / due date / status), the outstanding balance in large type, and the collateral still at stake (settlement never returns pledged items).
- Tapping **Settle** there opens a bottom sheet of settlement options: **Settle in full** (posts the balance as a full settlement), **Partial settlement** (clears and focuses the amount field; a partial amount entered is then posted via the sheet's **Record partial payment** row), **Request Balance Adjustment** (Story 5.6 forgiveness; only when `requestCorrections` and no pending correction), **Extend due date** (FR-26; Shop Owner only, new date strictly after today plus a mandatory reason; resets the credit to Active).
- Recorded through the existing payment path, preserving validation, concurrency lock, idempotency, receipt, and audit behavior (extensions reuse `OverdueDao.grantDueDateExtension`, including its sync-queue audit entry).
- On a successful full settlement initiated from Settle, return to the customer profile, show a confirmation, and refresh the credit list (balance 0, `Settled`). The receipt is still generated and remains available from payment history.
- An edit option keeps partial-amount entry possible from the summary screen: lowering the pre-filled amount records an ordinary partial payment, recorded exactly as it is today — the screen stays open, no auto-return.

**Never:**
- No new permission, no ledger/DAO/schema changes, no new settlement semantics.
- No partial-amount entry is initiated implicitly — the pre-filled amount is always the full balance; staff must deliberately edit the field to record a partial payment, and partials stay on the screen (no auto-return to the profile).
- No change to collateral custody states; settlement never auto-returns items.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| HAPPY_PATH | Eligible credit; actor holds `recordPayments` | Tapping Settle opens the settle summary screen (borrower, credit identity, outstanding balance, collateral at stake) with the full balance pre-filled; tapping Settle opens the settlement-options sheet; **Settle in full** records the full settlement and returns to the profile with a confirmation | N/A |
| NOT_ELIGIBLE | Pending-disbursement, settled, or zero-balance credit | Settle action is shown (2026-11-18 visibility restore); the summary screen explains the credit is not eligible and offers no settlement form | N/A |
| NO_PERMISSION | Actor lacks `recordPayments`, or account inactive | No Settle action shown | N/A |
| PARTIAL_SETTLE | Staff wants to pay less than the balance | In the sheet: **Partial settlement** clears/focuses the amount field; enter the amount; **Record partial payment** posts it; the summary screen stays open with the refreshed balance and receipt preview | N/A |
| BALANCE_CHANGED | Balance dropped between render and submit | Submission rejected | Existing overpayment error surfaced |
| CORRECTION_LOCK | Credit has a pending correction | Submission rejected | Existing correction-pending error surfaced |
| EXTENSION | Shop Owner extends the due date from the sheet (FR-26) | Date picker (strictly after today, shop local) + mandatory reason; `OverdueDao.grantDueDateExtension` persists the extension, writes the sync-queue audit entry, resets the credit to `active`; snackbar + screen reloads | Owner-only row hidden from non-owners; validation errors surfaced as snackbars |

</frozen-after-approval>

## Code Map

- `lib/features/customers/presentation/customer_profile_screen.dart` -- profile screen. `_CreditStatusSection` (L483) renders each credit as a `ListTile` (L547) whose `onTap` -> `_onCreditAction` (L149) -> `_proceedToCreditAction` (L221) pushes `PaymentScreen`. The per-card Settle action mirrors `CreditDraftAgreementAction`'s padding pattern. `_settleCredit` pushes the settle summary screen and, on pop with a receipt, reloads and confirms via SnackBar.
- `lib/features/customers/presentation/settle_summary_screen.dart` -- the dedicated settle screen: loads credit, borrower (via `credit.customerId`), collateral items and the shop time zone; renders purpose-built summary (large balance, credit identity, collateral at stake) with an editable pre-filled amount field and a **Settle** button posting through `PaymentDao.recordPayment`; a full settlement pops with the receipt; partial payments stay on screen with the receipt preview.
- `lib/features/customers/presentation/credit_draft_agreement_action.dart` -- per-credit action to mirror: static `buttonKey` (L74), `isAvailableFor(Credit, AppUser)` (L97) via `AppUser.hasPermission`.
- `lib/features/customers/presentation/payment_screen.dart` -- unchanged apart from the removal of the settle-mode flag it temporarily carried; the summary screen now owns the settle entry point.
- `lib/features/customers/domain/services/receipt_service.dart` -- `isEligibleForPayment` (L70), `validateAmount` (L83). Reuse; do not change.
- `lib/features/customers/data/daos/payment_dao.dart` -- `recordPayment` (L105): enforces permission, overpayment, concurrency, and the correction lock (L220). Reuse; do not change.
- `lib/features/customers/domain/models/credit.dart` -- `isActionable` (L317), `correctionPending` (L227). Reuse; do not change.
- `lib/core/permissions/app_permission.dart` -- `recordPayments` (L22). Reuse; do not change.
- `test/widget/features/customers/customer_profile_screen_test.dart` -- settle-action tests assert the summary screen end to end.
- `test/widget/features/customers/multi_credit_selection_test.dart` -- existing multi-credit dialog coverage; relevant if placement reuses it.
- `test/support/customers_test_support.dart` -- fixtures: `openTestDatabase`, `seedShopAndCustomer`, `insertCredit`, `pumpUntil`, `useLargeSurface`.

## Tasks & Acceptance

**Execution:**
- [x] `lib/features/customers/presentation/customer_profile_screen.dart` -- add the per-card Settle action (RBAC-gated, shown on every card per the 2026-11-18 visibility restore); `await` the settlement route, reload the profile, and show a confirmation -- delivers the user-facing goal.
- [x] `lib/features/customers/presentation/settle_summary_screen.dart` -- the dedicated settle screen (borrower, credit identity, outstanding balance, collateral at stake; balance pre-filled; **Settle** opens a bottom sheet with settlement options -- settle in full / partial settlement / Request Balance Adjustment / Extend due date) -- removes manual balance entry and gives the settle flow a purpose-built confirmation surface.
- [x] `test/widget/features/customers/customer_profile_screen_test.dart` -- tests for eligible, ineligible, no-permission, prefill, partial-edit, overpayment, correction-lock, due-date-extension (owner + non-owner) and return-to-profile paths -- proves the ACs.

**Acceptance Criteria:**
- Given an active disbursed credit with balance > 0 and an actor holding `recordPayments`, when the profile renders, then a Settle action is shown for that credit.
- Given an ineligible credit, then the Settle action is still shown (2026-11-18 visibility restore) and the summary screen explains the credit is not eligible and offers no settlement form.
- Given an actor without `recordPayments`, or an inactive account, then no Settle action is shown.
- Given an eligible credit, when staff tap Settle, then the summary screen opens with borrower, credit identity, outstanding balance and the collateral at stake, and the amount field is pre-filled to the balance.
- Given staff tap Settle, then a bottom sheet of settlement options opens (Settle in full / Partial settlement / Request Balance Adjustment / Extend due date for Shop Owners).
- Given a full settlement completed from the sheet, then the profile is shown with a confirmation and the credit shows balance 0 / `Settled`.
- Given staff choose Partial settlement, then the amount field is cleared and focused, and the entered partial amount posts as a partial payment with the summary screen staying open.
- Given a Shop Owner extends the due date from the sheet with a new date and reason, then the credit's due date is updated, the status resets to Active, and the audit/sync entries are written by the standard extension path.
- Given the balance changed since the screen rendered, when settle is submitted, then the existing overpayment guard blocks it and surfaces its message.

## Implementation Notes

- The action lives in `lib/features/customers/presentation/credit_settle_action.dart`, mirroring `CreditDraftAgreementAction`: a static `buttonKey(creditId)`, an `isAvailableFor(Credit, AppUser)` gate, and an `OutlinedButton.icon` that owns only its vertical inset (the profile supplies the horizontal inset, so a card without the action gains no dead spacing).
- `isAvailableFor` is `actor.hasPermission(AppPermission.recordPayments)` — the settle button appears on every credit card (visibility rule restored at the human's request on 2026-11-18, overriding the eligible-only frozen intent). Eligibility is enforced by the summary screen (it shows an explanation and no settlement form for an ineligible credit) and by the payment path behind it.
- The profile's `_settleCredit` passes the card's own `credit` directly. It deliberately does not route through `_onCreditAction`, whose multi-credit selection works from the *count* of actionable credits rather than the tapped card.
- Tapping Settle opens `SettleSummaryScreen` (created 2026-11-18): it loads the credit, the borrower (via `credit.customerId`), the pledged collateral items and the shop time zone; renders the customer, credit identity (reference / amount / term / due date / status), the outstanding balance in large type, and the collateral still at stake (items not yet `returned`/`exception_held`, with a note that settlement does not return pledged items). The amount field is pre-filled to the full balance; the **Settle** button records the entered amount through `PaymentDao.recordPayment` — the same validation, overpayment guard, concurrency lock, idempotency, receipt and audit behaviour as any payment. A full settlement generates the receipt PDF and pops with the committed `Receipt` (profile confirms via SnackBar and reloads); a partial payment stays on screen with a success message, the refreshed balance and the receipt preview.
- `PaymentScreen` no longer carries the settle-mode prefill/pop flag — the summary screen owns the settle entry point. `PaymentScreen` is otherwise unchanged.
- Tapping **Settle** opens a bottom sheet of settlement options rather than posting immediately: **Settle in full** posts `credit.balanceCents` via `PaymentDao.recordPayment`; **Partial settlement** clears and focuses the amount field (when a partial amount is already entered, the row reads **Record partial payment** and posts it); **Request Balance Adjustment** routes to `AdjustmentProposalScreen` (shown only when `requestCorrections` and no pending correction); **Extend due date** (Shop Owner only, hidden otherwise) shows a date picker with a mandatory reason and calls `OverdueDao.grantDueDateExtension`, reusing FR-26 validation, the sync-queue audit entry and the overdue→active reset, then reloads the screen.
- The settle beneficiary check in `grantDueDateExtension` enforces Shop Owner role again server-side of the UI — the sheet row is hidden for non-owners, and the DAO re-checks.
- The profile `await`s the push, reloads with `_loadProfile(showLoading: false)`, and shows `Credit settled. Receipt <receiptNumber> recorded.` only when a receipt was returned.
- No new permission, no ledger/DAO/schema change, and no new settlement semantics: the settle path is the existing payment path, so validation, the concurrency lock, idempotency, receipts and audit are unchanged.
- `flutter analyze` is clean.

## Spec Change Log

| Date | Change |
|------|--------|
| 2026-11-18 (2) | Human requested settlement options on the settle flow: tapping **Settle** now opens a bottom sheet with **Settle in full**, **Partial settlement** (fresh amount entry, posts as a partial payment), **Request Balance Adjustment** (forgiveness proposal, unchanged) and **Extend due date** (FR-26, Shop Owner only, new date + mandatory reason via `OverdueDao.grantDueDateExtension`). The summary screen's inline adjustment row moved into the sheet. See `settle_summary_screen.dart` (`_openSettleSheet`, `_extendDueDate`) and the updated tests. |
| 2026-11-18 | Human renegotiated the frozen intent: tapping Settle now opens a dedicated **Settle summary screen** (`settle_summary_screen.dart`) showing the borrower, credit identity (reference / principal / term / due date / status), the outstanding balance in large type, and the collateral still at stake — not the generic payment screen pre-filled. The amount field is pre-filled to the full balance; the **Settle** button opens a bottom sheet of settlement options (see 2026-11-18 (2)); a successful full settlement returns to the profile with the confirmation SnackBar. Partial-amount entry remains possible via the editable field and records as an ordinary partial payment that stays on screen (resolving review-triage intent gap #3: partials from the settle flow are allowed). The `PaymentScreen.settleMode` flag introduced by the original implementation was removed; the summary screen owns the settle entry point. Eligibility backstop moved from the payment screen to the summary screen. |

## Review Triage Log

| # | Finding | Verdict | Evidence |
|---|---------|---------|----------|
| 1 | Settle path skips receipt PDF generation — `_generateReceiptPdf` is bypassed when `settleMode && receipt.isFullSettlement`, so the PDF file is never created from this route. | `false` | The DB receipt row IS generated by `recordPayment` in `payment_dao.dart:218-377` regardless of the settle pop; the spec's "receipt is still generated and remains available from payment history" refers to the DB row, which IS committed and queryable from payment history. The `_generateReceiptPdf` is a separate PDF-rendering step, not the receipt itself. |
| 2 | `receipt.receiptNumber` could be null/empty in the SnackBar label. | `false` | `receiptNumber` is deterministically generated as `'RCP-${_shortId(actor.shopId, 6)}-${_compactDate(recordedAt)}-${_shortId(const Uuid().v4(), 8)}'` in `payment_dao.dart:196-197`; it is always non-empty. The test only checks `find.textContaining('Credit settled')` which passes regardless of the interpolated number. |
| 3 | Spec "Never" bullet contradicts PARTIAL_EDIT matrix and implementation about partial payments from Settle. | `intent_gap` | The "Never" bullet (line 39) states "No partial-amount entry initiated from the profile action; partial payments stay on the existing flow," but the I/O matrix entry `PARTIAL_EDIT` (line 43) and the code in `payment_screen.dart:370-373` and `_settleCredit` (lines 280-282) explicitly support lowering the pre-filled amount to record a partial payment. The captured intent is incomplete — it does not clearly resolve whether partial entries from Settle are allowed. This is root cause inside `<frozen-after-approval>`. |
| 4 | `onSettle` wired into all three `_CreditStatusSection`s unconditionally. | `false` | All three sections (active/orange/grey) can render credits that are payment-eligible (active/overdue with balance > 0). The eligibility gate inside `_settleCredit` and `CreditSettleAction.isAvailableFor` ensures the button only appears for eligible credits; the wiring is appropriate and not dead code. |

## Verification

**Commands:**
- `flutter analyze` -- expected: no new issues. **Result: No issues found! (5.7s)**
- `flutter test test/widget/features/customers/customer_profile_screen_test.dart` -- expected: all tests pass. **Result: `+28: All tests passed!` (8 tests in the new `settle action` group)**
- `flutter test test/widget/features/customers/multi_credit_selection_test.dart` -- **Result: `+2: All tests passed!`** (the profile's multi-credit routing is unchanged).
- `flutter test test/widget/features/customers test/unit/features/customers` -- **Result: `+513: All tests passed!`**

**Supporting runs (2026-11-18, settlement options sheet):**
- `flutter analyze` -- **Result: No issues found!**
- `flutter test test/widget/features/customers/customer_profile_screen_test.dart --name "settle"` -- **Result: `+12: All tests passed!`** (full settle via sheet, partial-settle option, adjustment option in sheet, owner-only Extend due date via sheet with reason, hidden for non-owners).
- Note: the settle-sheet tap tests must call `pumpAndSettle` after `pumpUntil(...)` for the sheet's enter animation to complete — with a zero-duration `pump()` the sheet stays parked below the fold (`AnimationController ... BottomSheet 0.000`) and tiles don't hit-test (widget-test artifact only).

**Supporting runs (2026-11-18, settle summary screen):**
- `flutter analyze` -- **Result: No issues found!**
- `flutter test test/widget/features/customers/customer_profile_screen_test.dart --name "settle"` -- **Result: `+10: All tests passed!`** (10 tests in the `settle action` group, updated to the summary screen; one new collateral-at-stake/customer/balance summary test).
- `flutter test test/widget/features/customers test/unit/features/customers` -- settle-related tests pass; **pre-existing failures unrelated to this change**: 3 profile tests (`credit origination return x2`, `Edit action opens`) fail identically at the base commit `bbfb913`, `payment_dao_test.dart` expects schema 25 while the in-flight Story 5.6 migration bumps to 26, and `customer_photo_capture_test.dart` is a 0-byte file that fails to compile (empty at HEAD).

**Supporting runs:**
- `flutter analyze` -- expected: no new issues. **Result: No issues found! (5.7s)**

## Spec Change Log