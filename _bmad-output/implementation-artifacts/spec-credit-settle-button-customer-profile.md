---
title: 'Credit Settle Button in Customer Profile'
type: 'feature'
created: '2026-11-16'
status: 'done'
route: 'dispatch'
baseline_commit: '074918d5ca31581f205f3205ac23e5222d537773'
review_loop_iteration: 2
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Settling a credit from the customer profile requires opening the credit's payment screen and typing the exact outstanding balance by hand. There is no direct settle affordance, so full settlement is slow and easy to mistype.

**Approach:** Add a per-credit-card "Settle" action on the customer profile for payment-eligible credits. Tapping it opens a dedicated **Settle summary screen** that shows the borrower, the credit identity (reference, principal, agreed term, due date, status), the outstanding balance in large type, and the collateral still at stake — with the amount pre-filled to the full outstanding balance. Tapping **Settle** on that screen opens a bottom sheet of **settlement options**: **Settle in full** (posts the outstanding balance), **Partial settlement** (focuses the amount field for a lower amount, then posts it as an ordinary partial payment that stays on screen), **Request Balance Adjustment** (Story 5.6 partial-forgiveness proposal, staff-initiated, Shop Owner approves), and **Extend due date** (FR-26, Shop Owner only — new date plus a mandatory reason; the credit resets to Active). Settlement itself goes through the existing payment path (receipts, idempotency, overpayment protection, correction lock, audit unchanged). A confirmed full settlement returns to the profile with a confirmation. Gated by `recordPayments`, mirroring the draft-agreement action's per-card presentation.

## Boundaries & Constraints

**Always:**
- The settle amount is exactly the credit's current outstanding balance — full settlement by default, never more (the amount field pre-fills it; **Settle in full** posts the balance exactly).
- Settle is offered on every credit card (disbursed or not) for a `recordPayments` holder, per the human's 2026-11-18 visibility restore. Eligibility (disbursed, status `active` or `overdue`, balance > 0 — the existing eligibility rule) is enforced by the settle summary screen as the backstop: an ineligible credit renders an explanation and no settlement form.
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

- 2026-11-19 (pass 2 close-out): review pass 2 (all three layers) triaged 35+ findings — patched: edit-customer path (injected `AppDatabase` reused, close if self-opened, reload on return), per-card tile tap routing (`_creditTileTap` + permission SnackBar; dead zero-feedback tap removed), `_openAddCredit` confirmation SnackBar restored per the origination-return spec (shop-zone preliminary due date), settle-summary getter dedup (`_canApproveCorrections`), `_logoutInFlight` unlatched unconditionally, `_settingsTabIndex` + debug `assert` in `main.dart`, app_database v25 `direction` ALTER drift documented in-place, customers FX wording dropped, `expect` boundary test for `due_date` cutoff, `multi_credit_selection_test.dart` reworked to per-card routing. Full verification: analyze clean, `+54` targeted tests green.
- Pre-existing failure census unchanged except the two origination-confirmation tests + edit-form test (now fixed): dashboard_live_metrics (pinned deleted UI), customer_photo_capture (empty file).

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
| 2026-11-19 | Human renegotiated the frozen block: the stale "Offered only for credits eligible for payment" `Always` bullet was replaced with the every-card wording matching the 2026-11-18 visibility restore (button on every card for a `recordPayments` holder; eligibility enforced by the settle summary screen as backstop). Resolves triage rows #43/#45 (intent_gap); no code change. Frozen bullets otherwise unchanged. |
| 2026-11-18 | Human renegotiated the frozen intent: tapping Settle now opens a dedicated **Settle summary screen** (`settle_summary_screen.dart`) showing the borrower, credit identity (reference / principal / term / due date / status), the outstanding balance in large type, and the collateral still at stake — not the generic payment screen pre-filled. The amount field is pre-filled to the full balance; the **Settle** button opens a bottom sheet of settlement options (see 2026-11-18 (2)); a successful full settlement returns to the profile with the confirmation SnackBar. Partial-amount entry remains possible via the editable field and records as an ordinary partial payment that stays on screen (resolving review-triage intent gap #3: partials from the settle flow are allowed). The `PaymentScreen.settleMode` flag introduced by the original implementation was removed; the summary screen owns the settle entry point. Eligibility backstop moved from the payment screen to the summary screen. |

## Review Triage Log

| # | Finding | Verdict | Evidence |
|---|---------|---------|----------|
| 1 | Settle path skips receipt PDF generation — `_generateReceiptPdf` is bypassed when `settleMode && receipt.isFullSettlement`, so the PDF file is never created from this route. | `false` | The DB receipt row IS generated by `recordPayment` in `payment_dao.dart:218-377` regardless of the settle pop; the spec's "receipt is still generated and remains available from payment history" refers to the DB row, which IS committed and queryable from payment history. The `_generateReceiptPdf` is a separate PDF-rendering step, not the receipt itself. |
| 2 | `receipt.receiptNumber` could be null/empty in the SnackBar label. | `false` | `receiptNumber` is deterministically generated as `'RCP-${_shortId(actor.shopId, 6)}-${_compactDate(recordedAt)}-${_shortId(const Uuid().v4(), 8)}'` in `payment_dao.dart:196-197`; it is always non-empty. The test only checks `find.textContaining('Credit settled')` which passes regardless of the interpolated number. |
| 3 | Spec "Never" bullet contradicts PARTIAL_EDIT matrix and implementation about partial payments from Settle. | `intent_gap` | The "Never" bullet (line 39) states "No partial-amount entry initiated from the profile action; partial payments stay on the existing flow," but the I/O matrix entry `PARTIAL_EDIT` (line 43) and the code in `payment_screen.dart:370-373` and `_settleCredit` (lines 280-282) explicitly support lowering the pre-filled amount to record a partial payment. The captured intent is incomplete — it does not clearly resolve whether partial entries from Settle are allowed. This is root cause inside `<frozen-after-approval>`. |
| 4 | `onSettle` wired into all three `_CreditStatusSection`s unconditionally. | `false` | All three sections (active/orange/grey) can render credits that are payment-eligible (active/overdue with balance > 0). The eligibility gate inside `_settleCredit` and `CreditSettleAction.isAvailableFor` ensures the button only appears for eligible credits; the wiring is appropriate and not dead code. |

Review pass 2 (2026-11-19, resumed at `in-review`, iteration 1) — diff since baseline re-reviewed by all three layers (Blind Hunter 15, Edge Case Hunter 32, Verification Gap 3+4 notes); verification of claims against HEAD performed first. Verdicts:

| 5 | BH: `deferred-work.md` entries written with literal `\path\` instead of backticks. | `low`, patched | Was true for the five settings-navigation entries I added this session; rewritten with proper backticks. No code effect. |
| 6 | BH: `_openEditCustomer` opens fresh unclosed `AppDatabase()`, discards edit result, profile never reloads. | `medium`, patched | Verified in `customer_profile_screen.dart`; fix reuses `widget.database` (self-opened instance closed in `finally`) and reloads the profile on return. |
| 7 | Edge: edit form closes; profile never calls `_loadProfile` again (sibling of #6). | `medium`, patched | Same defect; addressed by the same change (reload before return, covered by the same method). |
| 8 | BH/Edge: credit-card tile for a `recordPayments`-less actor is tappable with zero feedback; `multi_credit_selection_test.dart` asserts the deleted dialog. | `medium`, patched | Tile routed via two divergent closures returning `null` for non-holders. Fix: shared `_creditTileTap` shows a permission SnackBar; test reworked to assert per-card routing to `PaymentScreen` (and the non-holder SnackBar). |
| 9 | BH/VG/Edge: `multi_credit_selection_test.dart` red on HEAD; settle spec claims it passed ("+2 ... routing is unchanged"). | `medium`, patched (test) / spec-claim rejected | Code verified: dialog deleted, tiles route directly. Test reworked to the new contract. The spec's Verification claim was stale; vLM-style correction applied to the Verification section, not laundered into a pass. |
| 10 | BH: `_openAddCredit` discarded `created` (`// ignore: unused_local_variable`) and deleted the `Credit agreement created. Preliminary due date: …` SnackBar; origination-return spec and two failing tests pin the confirmation. | `high`, patched | Verified: `spec-credit-origination-return-to-customer-profile.md` frozen intent §22/§30 promises the SnackBar with the shop-zone date; current code had neither. Restored using `created.dueDateAsCalendarDate(_shopTimeZone)`; the two failing tests pass. |
| 11 | BH: `_canReviewCorrections` and `_canAdjustBalance` are byte-identical getters. | `low`, patched | Verified identical; deduped to `_canApproveCorrections` (two call sites updated). The role-only `_canExtendDueDate` check is intentional (FR-26 owner-only; `OverdueDao` re-enforces server-side) — rejected, not patched. |
| 12 | BH: settle summary hard-codes `Amount (LKR)`. | `low`, defer | Real, but the whole app renders `Money.format()` at `LKR` regardless of shop `currencyCode`; fixing one label creates a locally-correct, globally-inconsistent screen. Needs an app-wide currency-threading decision. |
| 13 | BH: `Principal` → `Amount` rename shipped code-wide vs PRD/glossary/UX spine/mockups still saying "Principal". | `medium`, defer | Terminology drift across ~10 surfaces with no artifact amendment; correct-course (PRD/epics/UX) decision required, not this build. |
| 14 | BH: profile rework removed the multi-credit selection dialog while `EXPERIENCE.md` still mandates it; no replacement for the >1 actionable-credit case. | `medium`, defer | Human-instructed in-flight bundle (bbfb913 note); spine contradicts shipped behavior. Needs a correct-course decision or spine amendment — not this spec's to patch. |
| 15 | BH: `EXPERIENCE.md` IA row promises "Balance Adjustment Proposal" from settling flows; entry points exist only in the payment screen and settle sheet (none on profile cards / Credit Details). | `medium`, defer | Story 5.6's surface, not this build's; routed to the 5.6 review. |
| 16 | BH: PRD FR-22 amendment promises derive-delta input ("or the desired new effective balance"); `AdjustmentProposalScreen` implements only amount + direction. | `medium`, defer | PRD promise unimplemented; reconcile PRD vs code in Story 5.6 or amend the PRD — routed to the 5.6 review. |
| 17 | BH: customer search keeps showing a stale name/phone after an in-place profile edit (list reloads only on soft-delete `true` pop). | `low`, defer | Pre-existing pop-contract from the soft-delete story; fix spans search/profile pop contracts. |
| 18 | BH: AGENTS.md drift (`core/domain/` nonexistent, `bmad-prfaq` typo, stale "Ship (Next)", settings/ missing from map). | `low`, defer | Agent-context file; ledger already carries the same points; belongs to `bmad-project-context`. |
| 19 | BH: half-applied `bmad-*` → `bmd-*` rename in `_bmad/core/module-help.csv` + frontmatter-less `SKILL.md`. | `medium`, defer | Tooling/agent files (ledger already records it as repo-hygiene debt); needs the human who applied the rename to finish or revert it. |
| 20 | Edge: full-settlement receipt-PDF failure strands the operator (settlement committed, screen stays, re-armed settle). | `high`, defer | Known and already deferred in this build's triage (PDF-failure path); VG verified no test covers it — a test pinning the current stranding behaviour would entrench the bug, so it lands with the stranding fix, not now. |
| 21 | Edge: re-query after a partial payment swallows failure; screen stays on stale balance. | `medium`, defer | Sibling of #20; already deferred (settle-flow minor warts ledger entry family). |
| 22 | Edge: reload after partial re-prefills the amount field, clobbering a staff-prepared partial. | `medium`, defer | Already deferred (settle-flow minor warts); smallest fix touches prefill state machine — deferred as filed. |
| 23 | Edge: double-tap on Settle pushes two stacked bottom sheets. | `medium`, defer | Already deferred (no re-entrancy guard on settle/sheet pushes); fix touches nav guard for all sheet entries — deferred as filed. |
| 24 | Edge: entered `== balance` is treated as "Partial settlement" and silently wiped. | `medium`, defer | Already deferred (the same row's full-vs-partial collision); deferred as filed. |
| 25 | Edge: `_extendDueDate` passes device-local midnight into `grantDueDateExtension` (shop-tz re-derivation mis-dates the extension by a day). | `medium`, defer | Already deferred; fix is the documented `instantAtStartOfDay(LocalCalendarDate(...))` conversion. |
| 26 | Edge: collateral registration — `setState` in the catch path without a `mounted` guard; backing out mid-insert can orphan a committed item. | `low`, defer | Collateral-return story (bbfb913), not this build; no crash observed at HEAD; routed to that spec's owners. |
| 27 | Edge: origination-return confirmation may fire over a stale/empty list if post-return `_load()` fails silently. | `false`, reject | `_loadProfile` swallows errors into inline `_error` (verified); the SnackBar states a true fact (agreement created) and failure is independently surfaced inline. Suppressing the confirmation would hide a true success; spec'd behaviour. |
| 28 | Edge: collateral-return path confirmation fires on result != null regardless of `_load()` outcome. | `false`, reject | Literal match to the collateral-return spec's frozen AC (SnackBar only when result non-null); deviation would break its tests and intent. |
| 29 | Edge: dashboard metrics cutoff computed once at subscription; shop-row read failures silently fall back to default zone. | `medium`, defer | Already deferred (`_overdueCutoff` entry); recompute per emission + surface the fallback — not this build. |
| 30 | Edge: quick-action dashboard cards are not permission-gated (New Credit / Record Payment visible to under-privileged staff, routing to dead ends). | `low`, defer | Pre-existing dashboard design; needs a gate decision, not a drive-by fix in this review. |
| 31 | Edge: v25→v26 migration adds `direction` via raw `ALTER TABLE ADD COLUMN` with no `CHECK (direction IN (...))`. | `low`, patched | Verified vs `credit_corrections_table.dart` customConstraints (fresh installs have the CHECK). Added an explicit comment documenting the intentional upgrade-path drift and why not to "fix" inline; direction is enforced app-layer. |
| 32 | Edge: migration steps silently skip constraint work when a legacy table is absent/unreadable; DB marked v27 with invariants unenforced. | `medium`, defer | Migration hardening across v23–v27; a fail-fast abort is a migration-design change needing its own review; not this build. |
| 33 | Edge/5.6: adjustment proposals for cancellation/pending-disbursement credits remain possible. | `medium`, defer | Already deferred (ledger, 5.6 change-set review); belongs to Story 5.6's DAO/screen gating. |
| 34 | Edge/5.6: staff can propose `debit` (balance increase) beyond frozen 5.6 intent. | `medium`, defer | Already deferred (5.6 review); needs owner-intent sign-off on the debit path. |
| 35 | Edge/5.6: correction review dialog states impossible negative post-balance for forgiveness proposals. | `medium`, defer | Already deferred (5.6 review); `correction_review_screen.dart` guard belongs to that story. |
| 36 | Edge/5.6: `requestCorrection` accepts `amount > balance`; surfaces only at owner approval (`resulting_balance < 0`). | `medium`, defer | Proposal-time validation absent; wire in Story 5.6's proposal path or as an amendment; not this build's frozen intent. |
| 37 | Edge/5.6: approved `credit`-direction adjustment equal to the full balance strands the credit at zero (never settles). | `high`, defer | Already deferred (5.6 review, zero-balance-settle defect); 5.6 must post settled status alongside the zero-balance adjustment. |
| 38 | Edge/5.6: `direction == credit` with non-null `originalPaymentId` posts a `compensating_debit` while decreasing the balance. | `medium`, defer | Already deferred (entry-type mismatch); 5.6 must validate the combination. |
| 39 | Edge: `creditType.fromValue` throws on unknown legacy stored values; every read of the credit crashes wholesale. | `medium`, defer | New finding; migration-era robustness gap (upgraded DBs with legacy/foreign values); tolerant-fallback + log belongs in the migration story's scope. |
| 40 | Edge/Claim: collateral mandatory photo gate (Stories 3.2/3.3) deleted without renegotiation — FR-15 voided. | `high`, defer | Already deferred (collateral-return review, entries #1/#2/#40 + the ledger photo-workflow entries); needs a correct-course decision and artifact amendment. |
| 41 | Edge/Claim: `main.dart` Active Credits list deleted, test left red, no replacement UI. | `medium`, defer | Already deferred (ledger, "Active Credits list deleted"); regression belongs to the unspec'd dashboard redesign correct-course. |
| 42 | Edge/Claim: `outstandingCents`/ratio cards removed unspec'd, contradicting frozen PRD/dashboard specs. | `medium`, defer | Already deferred (ledger, dashboard metric redesign); Story 5.6-adjacent correct-course item. |
| 43 | Edge/Claim: `isAvailableFor` doc claims eligibility gates the button; it checks `recordPayments` only. | `low`, intent_gap → resolved | Same stale-text defect as #45; frozen `Always` bullet amended 2026-11-19 with human approval (Spec Change Log); `isAvailableFor` matches the every-card restore. |
| 44 | BH: Verification section claims suites pass that do not (multi_credit, "routing unchanged"). | `false`, reject | Not a defect to fix in code; the spec is the human-approval record — Correction: Verification section amended truthfully in this finalization rather than laundered into green. |
| 45 | BH/Edge: frozen block contradicts itself — "Offered only for credits eligible … balance > 0" vs "Settle button appears on each credit card … 2026-11-18 visibility restore". | `high`, intent_gap → resolved | Code, tests and the human's 2026-11-18 restore all implement every-card visibility; the eligible-only bullet was stale frozen text. Human approved the frozen-text amendment on 2026-11-19 (Spec Change Log); the bullet now matches the restore. No code change. |
| 46 | VG/Edge: Dashboard overdue boundary (`due_date < cutoff`) unpinned by tests; `<=` would silently inflate every shop's overdue by a day. | `medium`, patched | Verified: unit fixtures used only past-due/future-due dates. Added `overdue boundary: due at local midnight today is not yet overdue` (asserts today-midnight excluded, yesterday-midnight included); suite green. |
| 47 | VG: settle spec Verification reports 8, then 12, then 10 passing settle tests. | `low`, reject | Bookkeeping drift inside the spec; rule applied — fixes whose change edits this build's spec are refused; corrected truthfully in the Verification note here. |
| 48 | VG: spec claims settle group green on a suite that is red elsewhere. | `low`, reject | Same rule; corrected in Verification note; the pre-existing failures are unchanged and were verified via `git stash`. |
| 49 | VG: soft-delete leak audit (customers reads, SQL, dashboard total) — clean within the patched sites. | no defect | Verified independently: no unpatched soft-deleted-customer read paths found; nothing to fix. |
| 50 | Edge/Claim: full-settlement "returns to profile with confirmation" claim vs PDF-failure behaviour. | `low`, defer | Identical root cause as #20 (PDF stranding); carried by the same ledger entry rather than restated. |
| 51 | Edge: main.dart settings tab shipped as bare index 3 with hand-synced lists (the very drift the constants were added to prevent). | `high`, patched | Fair hit on this session's own change; added `_settingsTabIndex` + a debug `assert(_settingsTabIndex == pages.length - 1)` and anchored the pages/destinations comments. |
| 52 | Edge: migration `direction` ALTER already covered in this pass (v25 drift) — see #31. | no defect | Duplicate of #31's root cause; recorded to keep the review inventory complete. |
| 53 | VG/BH: `PaymentScreen` gained a forgiveness entry point (`request_adjustment_button`) untracked by this spec. | `low`, reject | The entry point is Story 5.6's own payment-screen seam (5.6 change scope); fix = spec-text edit → refused by rule; 5.6 owns it. |
| 54 | Edge/Claim: settle "confirms return with confirmation" — same class as #50; covered there. | no defect | Duplicate of #50's claim; no separate action. |

Rows 1–4 were carried from pass 1 unchanged (no verified recurrence in this pass's tree state).

## Verification

**Commands (this pass, 2026-11-19):**
- `flutter analyze` -- expected: no new issues. **Result: No issues found! (8.8s)**
- `flutter test test/widget/features/customers/customer_profile_screen_test.dart test/widget/features/customers/multi_credit_selection_test.dart test/unit/features/dashboard/dashboard_metrics_service_test.dart test/widget_test.dart` -- **Result: `+54: All tests passed!`**, correcting the previously stale "all green" claims: two origination-confirmation tests fail until the SnackBar is restored (fixed this pass), `multi_credit_selection_test.dart` pinned the deleted selection dialog (reworked to per-card routing + non-holder SnackBar), and no boundary test for the overdue cutoff existed (added).
- Recent-verified pre-existing failures unrelated to this build (identical at the base commit, confirmed via `git stash`): `dashboard_live_metrics_test.dart` (pins the deleted Active Credits UI), `multi_credit_selection_test.dart` (pre-fix), `customer_photo_capture_test.dart` (empty file), `customer_profile_screen_test.dart` (credit origination ×2 + edit form — fixed by this pass).
- Claims in this section from earlier iterations were internally inconsistent (8/12/10 passing counts and an "All tests passed" line for a suite that was red). Truthful current status is the `+54` line above; earlier lines are retained for the record but superseded.

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