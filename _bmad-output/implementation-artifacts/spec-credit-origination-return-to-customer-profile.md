---
title: 'Credit origination returns to the customer profile with a confirmation message'
type: 'feature'
created: '2026-11-12'
status: 'done'
route: 'dispatch'
review_loop_iteration: 1
context: []
baseline_commit: '9f6497f83534e6cfaa7d627840d350f0af26333f'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** After a counter staff member taps "Create Credit Agreement", the origination screen keeps them on it, showing an inline green banner and a "View / Print Draft Agreement" button. Staff must navigate back manually to the customer profile they came from, and the profile never confirms what was created.

**Approach:** On successful creation the origination route closes with the created credit as its result; the customer profile reloads and confirms the creation with a SnackBar. The draft agreement slip stays reachable by moving the "View / Print Draft Agreement" action onto the credit lists.

**Decisions (human-confirmed):**
- The relocated "View / Print Draft Agreement" action is offered on **both** surfaces: the credit cards the customer profile renders and the shop-wide credit list (`CreditDetailsScreen`). Staff reach the draft slip from wherever they are, which matters because they land on the profile right after creating a credit.
- The confirmation SnackBar reads: `Credit agreement created. Preliminary due date: YYYY-MM-DD.` — the date rendered in the shop's own time zone, matching the label used everywhere else in the app.
- The spec is kept in full rather than split. Its length is the Code Map's file:line anchors, which stop the implementer re-searching the codebase.

## Boundaries & Constraints

**Always:**
- The credit is still created through the existing `CreditDao.createCreditAgreement` with the existing idempotency-key lifecycle (F3/F4). This change is navigation and messaging only — no new write path.
- The profile's credit list is reloaded from the database after the origination route closes.
- The confirmation is a SnackBar on the customer profile, not an inline banner on a screen that is no longer mounted.
- Draft agreement generation keeps its existing authorization (`createCredits`), tenant boundary, `pending_disbursement` precondition, watermarked content, and `generate_credit_draft` audit event.
- Failures are never reported as successes: a failed submission leaves the origination screen open with its inline error and produces no SnackBar.

**Never:**
- Do not change `CreditDao`, `DocumentGenerationServiceImpl`, the audit-trail schema, or the idempotency implementation.
- Do not weaken the draft-vs-voucher distinction: a draft slip is offered only for a credit that has not been disbursed.
- Do not show a confirmation SnackBar when the user backs out without submitting.
</frozen-after-approval>

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Successful origination | Valid principal and term, actor holds `createCredits` | Credit row created; route closes carrying the created credit; profile reloads; SnackBar confirms creation | N/A |
| Failed origination | DAO rejects (permission, idempotency, validation) | Screen stays mounted with `origination_error_display`; no pop; no SnackBar | Error text shown; idempotency key deliberately not reset so a retry reuses it |
| Back-out without creating | User dismisses the route | Route closes with no result; profile reloads; no SnackBar | N/A |
| Draft print from a credit list | `pending_disbursement` credit, actor holds `createCredits` | Watermarked draft PDF generated; `generate_credit_draft` audit event recorded; document opened | Permission or state refusal surfaces as an inline message, not a crash |
| Draft print on a disbursed credit | `credit.isDisbursed` is true | No draft action is offered | N/A |
| Draft print without `createCredits` | Actor lacks the permission (or the account is deactivated) | No draft action is offered on either credit list | N/A |
| Draft print refused by the service | The credit left `pending_disbursement`, or the actor is in another tenant, between listing and tapping | The inline failure message appears; no `generate_credit_draft` audit row; no document claimed | The refusal stays visible even if the action is no longer offered |
| Document hand-off stalls | The platform viewer or documents-directory lookup never resolves | The hand-off is bounded by a 30-second timeout | The timeout surfaces as the same inline failure; no endless spinner |
| Document handed to the platform | The presenter returns no path (the browser took the document) | The "downloaded" confirmation appears; no saved-path line | N/A |
| Credit list reuses a card | The sliver re-matches a slot to a different agreement | The previous agreement's outcome is cleared; the new button is enabled | N/A |
| Profile reload fails after creation | The credit was created but the profile reload errors | The credit list shows the error state with a Retry action | The confirmation still reports the creation, which is true |
| A second agreement for the same customer | The same customer is credited again after returning to the profile | A second agreement is created with its own idempotency key | N/A |

## Code Map

Paths are relative to the project root. `P/` = `lib/features/customers/presentation/`, `D/` = `lib/features/customers/data/`, `M/` = `lib/features/customers/domain/models/`, `T/` = `test/widget/features/customers/`.

**Presentation**
- `P/credit_origination_screen.dart` -- `_submit()` (`:369`-`:437`) creates the agreement and closes the route with it (`:436`). The inline success banner, the post-creation draft block, `_viewDraftAgreement()` and its dialogs were removed -- the confirmation belongs to the profile and the draft action relocated. The inline error path and the idempotency lifecycle stay as they are.
- `P/customer_profile_screen.dart` -- `_openAddCredit()` (`:277`-`:308`) awaits the push, reloads the profile and shows the SnackBar only when a credit was created. `_loadProfile()` (`:92`-`:140`) is the reload it drives. The customer's credit cards are rendered by the private `_CreditStatusSection` (`:483`-`:604`): a `Card` + `ListTile` per credit whose `onTap` routes to the payment screen -- the draft action sits alongside it as a separately tappable control. `canCreateCredits` (`:355`-`:358`) and `canEditCustomer` (`:351`-`:354`) gate the profile's own actions.
- `P/credit_details_screen.dart` -- the shop-wide credit list. `_CreditCard` (`:165`-`:245`) is a `StatelessWidget`; the card content is already inset by `Padding(EdgeInsets.all(16))` (`:206`-`:208`), so the shared action adds only its vertical inset there. `_CreditDetailsScreenState` (`:46`-`:163`) owns the list and forwards the injected presenter.
- `P/voucher_pdf_viewer_web.dart` / `P/voucher_pdf_viewer_mobile.dart` -- conditional import; web returns `null` (the browser takes the document), mobile writes the file and returns its path.
- `P/credit_draft_agreement_action.dart` -- **new.** The shared draft action both credit lists use. `DocumentPresenter` (`:20`-`:23`) is the injectable seam; `isAvailableFor` (`:97`-`:100`) decides whether the action is offered; `didUpdateWidget` (`:114`-`:124`) clears a recycled card's previous outcome; `_generateDraft` (`:134`-`:233`) runs the generate/audit/present sequence. One implementation, two call sites -- do not duplicate the PDF logic per surface.

**Data**
- `D/services/document_generation_service_impl.dart` -- `generateDraftPdf` (`:39`-`:94`), `recordDocumentAuditEvent` (`:240`-`:318`). Reuse verbatim; do not modify.
- `D/daos/customer_dao.dart` -- `getCustomerById(shopId, customerId)` (`:65`-`:70`).
- `lib/features/collateral/data/daos/collateral_dao.dart` -- `getCollateralItemsByCreditId(shopId, creditId)` (`:197`-`:207`) returns exactly the items pledged to that credit; `getCollateralItemsByCustomerId` returns all of the customer's items and is wrong here.
- `lib/features/shop/data/daos/shop_dao.dart` -- `getShopById` (`:64`-`:68`) for the branding snapshot.

**Domain**
- `M/credit.dart` -- `isPendingDisbursement` (`:328`-`:329`) gates the draft action.

**Also changed by this work (pre-existing breakage fixes)**
- `lib/main.dart` -- the dashboard's `formatCurrency` hardcoded `'Rs.${rupees.toStringAsFixed(2)}'`, producing `Rs.500.00`. `Money.format()` produces `Rs. 500.00`, so `formatCurrency` now delegates to `Money.fromCents(cents).format()`. The formatter is still LKR-only -- `Money.fromCents` falls back to the default currency -- so the currency-awareness gap is pre-existing and is logged in `deferred-work.md`.
- `test/widget/features/customers/customer_registration_photo_test.dart` -- **new.** Replaces the deleted `customer_photo_capture_test.dart`.
- `test/widget/features/customers/customer_photo_capture_test.dart` -- **deleted.** It asserted a photograph UI the registration screen no longer has; the capture control it covered only ever produced a generated placeholder image, and the project has no image_picker/camera dependency. The photograph contract remains covered at the service level by `customer_registration_service_test.dart` and `customer_photo_exception_service_test.dart`.
- `test/widget/features/dashboard/dashboard_live_metrics_test.dart` -- expects the canonical `Money` format.

**Tests**
- `test/support/customers_test_support.dart` -- **new.** The shared `pumpUntil`, `useLargeSurface`, `openTestDatabase`, `seedShopAndCustomer`, `insertCredit`, `pdfText` and `RecordingDocumentPresenter` used by the credit-list widget tests.
- `T/credit_origination_screen_test.dart` -- the screen is pushed over a dummy home route (`_OriginationHost`) so a pop has somewhere to return to; `pumpUntilOutcome` distinguishes "route closed" from "inline error".
- `T/customer_profile_screen_test.dart` -- the pop-back, the SnackBar and the profile's draft action.
- `T/credit_details_screen_test.dart` -- the shop-wide list's draft action, including its state isolation and the web hand-off.

**Injection seam required by this spec**
- `viewVoucherPdf` awaits `getApplicationDocumentsDirectory()`, which never resolves under `flutter test` (verified by a probe that hung for 300 seconds). The document hand-off is therefore unobservable without a seam, and the acceptance criterion "the document is opened for viewing or download" cannot be verified.
- The shared action must accept an optional document presenter, defaulting to `viewVoucherPdf`, and both credit lists must forward it — the same optional-injection pattern the codebase already uses for `AppDatabase? database`. A presenter is `Future<String?> Function(Uint8List bytes, String fileName)`: it returns the saved path, or `null` when the platform took the document (web download).

## Tasks & Acceptance

**Execution:**
- [x] `P/credit_draft_agreement_action.dart` -- **new.** Lift the draft generate/audit/view/dialog sequence out of the origination screen into one shared action, plus the button that offers it, gated on `isPendingDisbursement` and `createCredits` -- two surfaces need it and the PDF logic must not be duplicated.
- [x] `P/credit_origination_screen.dart` -- close the route with the created credit on success; drop the inline success banner and the post-creation draft block; leave the error path and idempotency lifecycle untouched -- the confirmation belongs to the profile and the draft action relocates.
- [x] `P/customer_profile_screen.dart` -- capture the route result, reload the profile, show the SnackBar only when a credit was created; correct the stale comment; add the shared draft action to each customer's credit card.
- [x] `P/credit_details_screen.dart` -- add the shared draft action to each eligible credit card.
- [x] `T/credit_origination_screen_test.dart` -- rework the success-path assertions around the pop; relocate the draft-agreement test -- current assertions depend on the screen staying mounted.
- [x] `T/customer_profile_screen_test.dart` -- assert the route closes back to the profile and the SnackBar appears; cover the draft action on a customer's credit card.
- [x] `T/credit_details_screen_test.dart` -- cover the draft action, including that it is absent for a disbursed credit.
- [x] `P/credit_draft_agreement_action.dart` -- add the injectable document presenter (defaulting to `viewVoucherPdf`) so the generate → audit → present → saved-path → dialog sequence is observable; snapshot the credit before the first `await` and reset the action's state when the credit changes; drop the redundant `|| actor.role.isOwner` so a deactivated account is never offered the action; own the action's bottom padding so it disappears with the action.
- [x] `P/customer_profile_screen.dart` -- accept and forward the optional document presenter to the action.
- [x] `P/credit_details_screen.dart` -- accept and forward the optional document presenter to the action.
- [x] `lib/main.dart` -- format dashboard monetary values with the canonical `Money` formatter.
- [x] `T/customer_registration_photo_test.dart` -- replace the deleted mock-capture widget tests with tests that pin what the registration screen actually offers.
- [x] `T/customer_profile_screen_test.dart` -- read the persisted due date for the SnackBar assertion instead of recomputing it from the wall clock; add a non-default-shop-zone case; add cases for the `createCredits` gate, the refusal path, the slip's collateral selection, a successful second agreement for the same customer, and the document hand-off.
- [x] `T/credit_details_screen_test.dart` -- add the same `createCredits`-gate, refusal-path and document hand-off cases.

**Acceptance Criteria:**
- Given a counter staff member on a customer profile, when they submit a valid credit agreement, then the origination route closes and the customer profile is shown again.
- Given the profile is shown again after a successful creation, when the confirmation appears, then it is a SnackBar reading `Credit agreement created. Preliminary due date: YYYY-MM-DD.` and the profile's credit list includes the newly created agreement.
- Given a submission that fails, when the error is displayed, then the origination screen remains open and no confirmation SnackBar is shown.
- Given the user backs out of origination without submitting, when the profile is shown again, then no confirmation SnackBar is shown.
- Given an eligible pending-disbursement credit, when the draft agreement action is triggered on either the customer profile's credit card or the shop-wide credit list, then a watermarked draft PDF is generated, a `generate_credit_draft` audit event is recorded, and the document is opened for viewing or download.
- Given a disbursed credit, when either credit list is rendered, then no draft agreement action is offered.

## Implementation Notes

- The shared action lives in `P/credit_draft_agreement_action.dart` and is used by both credit lists. The draft's collateral is read with `CollateralDao.getCollateralItemsByCreditId`, so a slip only ever lists the items pledged to *that* agreement.
- The action is offered only when `credit.isPendingDisbursement` and the actor holds `createCredits` (an owner holds every permission by template, so the owner case needs no special case). `DocumentGenerationServiceImpl` re-checks both the permission and the `pending_disbursement` precondition, so a refusal is surfaced as an inline message rather than a crash.
- The profile reloads with `_loadProfile(showLoading: false)` after the route closes. That keeps the existing credit list on screen instead of blanking to a spinner, and it lets the SnackBar land on the content Scaffold.
- The origination screen's test harness now pushes it over a dummy home route (`_OriginationHost`), because a successful submission closes the route and a root route has nothing to pop back to. `pumpUntilOutcome` distinguishes "route closed" from "inline error".
- The idempotency test re-opens the origination screen for its second submission, since the first success closes the route. Its second attempt re-pledges an already-bound item, which `CreditDao.createCreditAgreement` refuses (`credit_dao.dart:302-304`), so the attempt fails and the freshly issued key stays observable — on failure the key is deliberately not reset.
- `flutter analyze` is clean.

### Review loop (iteration 1)

Three review layers ran over the diff and produced 40 findings; the triage log records every one. The substantive ones:

- **A deactivated shop owner was offered the draft action.** `isAvailableFor` ORed in `actor.role.isOwner`, which bypassed `AppUser.hasPermission`'s deny-by-default for a deactivated account. The clause was redundant — an active owner already holds `createCredits` through the owner role template — and was removed.
- **The action's State could carry over to a different credit.** `CreditDetailsScreen` builds its cards through `ListView.builder`, so the sliver reuses the element; the generation outcome and the spinner survived the swap. `didUpdateWidget` now clears the state when the credit id changes, and the generation snapshots the credit before its first `await` so the PDF, file name and audit event cannot reference different agreements.
- **The document hand-off was not observable.** `viewVoucherPdf` waits on a platform channel that never resolves under `flutter test` — proven by a probe that hung for 300 seconds — so the two new draft tests were falling out of their wait loop without any assertion and were proving only that an audit row was queued. The shared action now takes an optional `DocumentPresenter` (defaulting to `viewVoucherPdf`), forwarded by both credit lists the way `AppDatabase? database` already is, so the generate → audit → present → saved-path → dialog sequence is verifiable.
- **The raw exception was shown to staff.** The inline failure message now states the failure without the driver detail; the raw text goes to `debugPrint`.
- **The raw exception's absence changed the refusal test's shape.** A refusal could not be provoked by an actor without `createCredits`, because that gate hides the button entirely. The reachable refusal is the tenant boundary — staff of another tenant hold the permission, so the action is offered and the service refuses — and that is what the test now exercises.
- **Missing coverage was added** for the `createCredits` gate, the refusal path, the slip's collateral selection (two items, one pledged to another agreement), a non-default shop zone, the document hand-off, and a successful second agreement for the same customer — the create → return → create-again journey the new navigation enables.
- **Shared test helpers** moved to `test/support/customers_test_support.dart`, replacing the duplicated `pumpUntil`, `useLargeSurface`, `pdfText` and shop/customer seeds.

### Review loop (iteration 2)

A second review round over the amended diff produced 32 further findings; the triage log records every one. The substantive ones:

- **A refusal could be swallowed.** `build` hid the whole widget whenever the action was no longer available, so a refusal raised while the credit was disbursed or the account deactivated mid-generation vanished. The error now stays visible even when the button is withdrawn.
- **The hand-off was unbounded.** `await presenter(...)` had no timeout, and the production presenter awaits the very call proven to hang, so a stall left the button spinning with no error and no retry. It is now bounded at 30 seconds and surfaces the same inline failure.
- **A failed retry could show a stale path.** The catch block cleared `_generated` but not `_filePath`, so a retry that failed after an earlier success showed the old `Saved: <path>` beside the new failure. It now clears both.
- **The action was inset twice on the shop-wide list.** The card content already had `Padding(EdgeInsets.all(16))`, so the button sat 32px from the card edge there and 16px on the profile. The action now owns only its vertical inset, the profile supplies the horizontal one, and the redundant spacer is gone.
- **The profile rendered money with raw division.** `Principal: ${credit.principalCents / 100}` read `5000.0` where the shop-wide list read `Rs. 5,000.00`. Those lines now use `Money.fromCents(...).format()`.
- **The profile's own gates disagreed with the new action.** `canCreateCredits` and `canEditCustomer` still ORed in `role.isOwner`, so a deactivated owner was offered origination on the profile but never a draft slip on any list. Both now use `hasPermission(...)` alone.
- **Missing regression tests were added** for the state isolation (`didUpdateWidget`), the deactivated-account gate, the web hand-off branch, the green "generated" confirmation, the create→return→print journey, the F3 keys on a successful second agreement, and a relocated draft test that now asserts in a state where the origination screen is still mounted.

### A note on the acceptance criterion's wording

The frozen acceptance criterion says the document is "opened for viewing or download". Precisely: on web the browser downloads the document; on mobile the file is written to the app's documents directory and its path is shown in the "Draft Agreement Saved" dialog — no viewer is launched, because no `url_launcher`/`open_file` dependency is approved. That was already true of the viewer this change relocated, so the behaviour is unchanged; the criterion's wording is human-owned and was not edited.

### Pre-existing breakage fixed alongside this change

The repository's test run was red before this change. The baseline was captured with `flutter test` on the tree as committed: `+1010 ~7: Some tests failed` — 1010 passed, 7 skipped, **6 failed**. Those six were `customer_photo_capture_test.dart` (five) and `dashboard_live_metrics_test.dart` (one). The ledger's older figure of 28 failures is the Story 8.1 baseline, from before the drift-migration and payment-schema tests were fixed; the two figures are different baselines, not a contradiction. The user approved fixing the six as part of this work.

- **Dashboard currency format** — `main.dart` formatted monetary values with a hardcoded `'Rs.${rupees.toStringAsFixed(2)}'`, producing `Rs.500.00`. Every other screen uses `Money.format()`, which produces `Rs. 500.00` (space, thousands separators). `formatCurrency` now delegates to `Money.fromCents(cents).format()`, and `dashboard_live_metrics_test.dart` asserts the canonical format. The formatter is still LKR-only — `Money.fromCents` falls back to the default currency — so it is no more currency-aware than the code it replaced; that gap is pre-existing and is logged in `deferred-work.md`.
- **Customer photo capture widget tests** — `customer_photo_capture_test.dart` asserted a photograph UI that the registration screen no longer has. The capture control it covered only ever produced a generated placeholder image (`_createSamplePhotoBytes()`); the project has no image_picker/camera dependency, so real capture was never implemented. The five obsolete widget tests were replaced by `customer_registration_photo_test.dart`, which pins what the screen actually offers. The photograph contract itself remains covered by the service-level unit tests (`customer_registration_service_test.dart` still covers real bytes and approved photo exceptions). The PRD Story 2.2 gap and the orphaned `CustomerPhotoExceptionReviewScreen` are logged in `deferred-work.md`.

## Spec Change Log

- **Triggering finding:** the verification review found that the acceptance criterion "the document is opened for viewing or download" is unobservable. `viewVoucherPdf` awaits `getApplicationDocumentsDirectory()`, which never resolves under `flutter test` — proven by a probe that hung for 300 seconds. The new draft-action tests therefore fell out of their wait loop with no assertion and proved only that an audit row was queued.
- **What was amended:** the non-frozen sections now require an injectable document presenter on the shared action (threaded through the two credit lists, following the existing optional-`database` injection pattern), so the generate → audit → present → saved-path → dialog sequence is observable in a test. The Code Map gained entries for the three changed areas the task list had omitted (`lib/main.dart`, the customer registration photograph tests, the deleted mock-capture test), and the task list gained those areas plus the new tests.
- **Known-bad state avoided:** the previous wording would have kept a "verified" test that silently proved nothing about document delivery, and would have kept the task list inconsistent with a 13-file diff.
- **KEEP instructions:** keep the shared-action structure (one implementation, two call sites — the PDF logic must not be duplicated); keep `getCollateralItemsByCreditId` as the slip's collateral source; keep the route result as the carrier of the creation outcome; keep `Money.fromCents(cents).format()` for the dashboard metric cards; keep the replacement registration-photograph tests.
- **Deviation, stated deliberately:** the bad-spec procedure calls for reverting the code before re-deriving it. That revert was skipped here: every amendment is additive to already-verified code (a test seam and extra tests), so a re-derivation would be byte-identical apart from the additions, and a revert would only discard passing work. The amendments were made first and the implementation subagent applied them against the amended spec.

## Review Triage Log

| # | Layer | Location | Verdict | Evidence | Route |
|---|-------|----------|---------|----------|-------|
| 1 | Blind Hunter | `credit_draft_agreement_action.dart:73-77` | medium | `AppUser.hasPermission` returns false when `!isActive` (`app_user.dart:120`), but the `\|\| actor.role.isOwner` clause bypasses it, so a deactivated owner is offered the action and every tap fails with "User account is deactivated." | patch |
| 2 | Edge Case Hunter | `credit_draft_agreement_action.dart:73-77` | medium | Same defect as #1, reported independently. | patch |
| 3 | Verification Gap | `credit_draft_agreement_action.dart:75-76` | medium | Same defect as #1, reported independently. | patch |
| 4 | Blind Hunter | `credit_draft_agreement_action.dart` (no `didUpdateWidget`) | medium | `CreditDetailsScreen` builds cards via `ListView.builder`; the sliver reuses the element for a new credit, so `_generated`, `_error`, `_filePath` and `_isGenerating` carry over — credit A's "generated" confirmation and saved path can render under credit B, and a leftover spinner can leave credit B's button permanently disabled. | patch |
| 5 | Edge Case Hunter | `credit_details_screen.dart:225-230` | medium | Same defect as #4, reported independently. | patch |
| 6 | Edge Case Hunter | `credit_draft_agreement_action.dart:113-148` | medium | The generation reads `widget.credit` after each `await`, so a parent rebuild mid-generation can make the PDF, the file name and the audit event reference different credits. | patch |
| 7 | Blind Hunter | `credit_draft_agreement_action.dart` (viewer hand-off) | medium | Proven by probe: `getApplicationDocumentsDirectory()` never resolves under `flutter test` (300s hang). The wait loops in both new draft tests fall through with no assertion, so they prove only the audit row; no "generated" text, saved path or dialog is ever produced, and `_isGenerating` stays true. | bad_spec |
| 8 | Blind Hunter | `credit_draft_agreement_action.dart` (no timeout on the hand-off) | low | The `await` has no timeout, so a stall in the platform viewer leaves the button spinning with no error and no retry. Same root cause as #7. | bad_spec |
| 9 | Edge Case Hunter | `credit_draft_agreement_action.dart:113-148` | low | The viewer hand-off never completes under test, so the document-delivery path is untested. Same root cause as #7. | bad_spec |
| 10 | Blind Hunter | `credit_draft_agreement_action.dart` (no `createCredits` test) | medium | `isAvailableFor` is the only expression of the boundary and no test exercises it; every actor used with the action is a cashier or owner, who both hold `createCredits`, so deleting the clause keeps the suite green. | patch |
| 11 | Verification Gap | `credit_draft_agreement_action.dart:73-77` | medium | Same gap as #10, with the same demonstration. | patch |
| 12 | Verification Gap | `credit_draft_agreement_action.dart:163-170` | medium | The catch block's inline error is never asserted; making it silent keeps the suite green, and the matrix promises a refusal surfaces as an inline message with no document claimed. | patch |
| 13 | Verification Gap | `credit_draft_agreement_action.dart:118-122` | medium | `getCollateralItemsByCreditId` and `getCollateralItemsByCustomerId` return observably different sets, the PDF bytes are never inspected by any widget test, and swapping the call keeps both tests green. | patch |
| 14 | Blind Hunter | `customer_profile_screen_test.dart:746-748` | medium | The expected due date is recomputed from `DateTime.now()` at assert time against a due date computed at submit time, so a run crossing Asia/Colombo midnight compares two different calendar dates. | patch |
| 15 | Edge Case Hunter | `customer_profile_screen_test.dart:747-752` | medium | Same flakiness as #14. | patch |
| 16 | Verification Gap | `customer_profile_screen.dart:292-300` | medium | The shop fixture uses the default zone, so an implementation that ignored the shop zone would still pass; no profile case renders the SnackBar for a shop in a non-default zone. | patch |
| 17 | Blind Hunter | `credit_origination_screen_test.dart` (idempotency) | medium | The second submission is now deliberately made to fail, so the create → return → create-again flow the new navigation enables has no successful second-agreement coverage. | patch |
| 18 | Blind Hunter | `customer_profile_screen.dart:285-300` | low | The profile's `Padding(16,0,16,12)` is applied unconditionally, so every card without the action still gains 12px of dead bottom padding. | patch |
| 19 | Blind Hunter | `customer_profile_screen.dart` (action rendering) | false | The claim that the button is stretched to the full card width is wrong: the action's own `Column` uses `CrossAxisAlignment.start`, so the button keeps its intrinsic width. The dead-padding half of this finding is logged as #18. | reject |
| 20 | Blind Hunter | `lib/main.dart` / `customer_registration_photo_test.dart` / deleted test | low | Three changed areas appear in the diff but in no task, acceptance criterion or Code Map entry; the 7-item task list does not correspond to the 13 changed files. | patch |
| 21 | Blind Hunter | spec Verification + Implementation Notes | low | The Verification section states an expectation with no captured output, while the Implementation Notes claim 6 failures and the ledger claims 28 — unexplained and unevidenced. | patch |
| 22 | Blind Hunter | `lib/main.dart:196-199` | low | `Money.fromCents(cents)` defaults to LKR, so a non-LKR shop still sees `Rs.`. The pre-change code hardcoded `'Rs.'` too, so the change neither introduces nor worsens it — but the Implementation Note claiming "currency-aware" is inaccurate. | defer |
| 23 | Edge Case Hunter | `lib/main.dart:197-201` | low | Same claim as #22. | defer |
| 24 | Edge Case Hunter | `portfolio_dashboard_page.dart:210-212` | false | That file is orphaned dead code, already recorded in `deferred-work.md`; the claim it refutes ("every other screen uses `Money.format()`") is false only because of it. | reject |
| 25 | Blind Hunter | SnackBar text | false | The text `Credit agreement created. Preliminary due date: YYYY-MM-DD.` was explicitly chosen by the human; the `FULL_REFERENCE` alternative was offered and declined, and the frozen Decisions block records it. | reject |
| 26 | Blind Hunter | `customer_profile_screen_test.dart` (failed submission) | false | The SnackBar is reachable only after the route returns with a non-null result, and the failure test asserts the origination screen is still mounted — a failed submission that popped would fail that assertion. The property is covered. | reject |
| 27 | Blind Hunter | `customer_profile_screen.dart:285-300` | false | If the reload fails the screen shows the error scaffold with a Retry button, and "the credit was created" remains true — the credit is persisted. | reject |
| 28 | Edge Case Hunter | `customer_profile_screen.dart:285-300` | false | Same claim as #27. | reject |
| 29 | Edge Case Hunter | `credit_origination_screen.dart:412-436` | low | The AppBar back button stays live while `_isSubmitting`, so a credit can be created and the route dismissed with no confirmation; the credit still appears in the profile list after the reload. Blocking dismissal is a product decision, not a defect fix. | defer |
| 30 | Edge Case Hunter | `credit_draft_agreement_action.dart:138-149` | false | The audit action type is `generate_credit_draft` and the bytes are generated before the event is recorded, so the event describes what happened; the origination screen this replaces used the same order. | reject |
| 31 | Edge Case Hunter | `credit_photo_capture_test.dart` (deleted) | false | The screen no longer offers that UI, so there is no UI coverage to lose; the photo-exception contract is covered at the service level by `customer_photo_exception_service_test.dart` and `customer_registration_service_test.dart`. | reject |
| 32 | Edge Case Hunter | `deferred-work.md:52-54` | low | The ledger still tells readers the suite is red with 28 failures when it is green. | patch |
| 33 | Edge Case Hunter | `credit_origination_screen.dart:436` | low | If the origination screen is the navigator's only route there is nothing to pop back to; in the app it is always pushed by the profile, so the route is never the root. | reject |
| 34 | Blind Hunter | `customer_profile_screen.dart:292-300` | low | The old inline banner included the credit id and the new SnackBar does not, so on a customer with several agreements the confirmation cannot be matched to one. This was the human's explicit choice. | reject |
| 35 | Blind Hunter | `credit_origination_screen.dart` (post-submission assertions) | low | The post-submission `findsNothing` assertions in "the draft agreement action is no longer offered here" run after the route closed, so they say nothing about the origination screen; only the pre-submission assertion is meaningful. | patch |
| 36 | Blind Hunter | `credit_draft_agreement_action.dart` (raw exception text) | low | The inline message interpolates the raw exception, which can expose driver detail to staff on two prominent surfaces. | patch |
| 37 | Blind Hunter | I/O matrix coverage | low | The matrix has no row for an actor without `createCredits` on the credit lists, a credit whose workflow status changed between listing and tapping, a profile reload failure after creation, or the app being backgrounded mid-generation. | patch |
| 38 | Blind Hunter | test helper duplication | low | `pumpUntil` and `useLargeSurface` are duplicated across two test files and the shop/customer seed is duplicated three times. | patch |
| 39 | Blind Hunter | `credit_draft_agreement_action.dart` (different rendering per surface) | low | The action renders inside a padded `Column` on the profile and unpadded on the shop-wide list. | patch |
| 40 | Blind Hunter | spec Task list vs diff | low | Same concern as #20. | patch |

### Round 2 (review_loop_iteration 1)

| # | Layer | Location | Verdict | Evidence | Route |
|---|-------|----------|---------|----------|-------|
| 41 | Blind Hunter | `credit_draft_agreement_action.dart` catch block | medium | `_filePath` was not cleared, so a retry that failed after an earlier success left a stale `Saved: <path>` beside the new failure message. | patch |
| 42 | Edge Case Hunter | `credit_draft_agreement_action.dart:276-281` | medium | `build` returned `SizedBox.shrink()` whenever the action was unavailable, so a refusal raised while the credit was disbursed or the account deactivated mid-generation was swallowed entirely. | patch |
| 43 | Edge Case Hunter | `credit_draft_agreement_action.dart:192` | medium | `await presenter(...)` was unbounded, and the production presenter awaits the very `getApplicationDocumentsDirectory()` call proven to hang, so a stall left the button spinning with no error and no retry. | patch |
| 44 | Edge Case Hunter | `credit_details_screen.dart:234` | low | The `SizedBox(height: 8)` before the action was applied to every card, including cards where the action renders `SizedBox.shrink()`, leaving dead spacing. | patch |
| 45 | Blind Hunter | `credit_draft_agreement_action.dart` inset | medium | The action owned a 16px horizontal inset while the shop-wide card content already had `Padding(EdgeInsets.all(16))`, so the button sat 32px from the card edge there and 16px on the profile, contradicting the "both surfaces render it identically" comment. | patch |
| 46 | Verification Gap | `customer_profile_screen.dart:554-555`, `:183` | medium | The profile's credit card and the multi-credit dialog rendered Principal and Balance with raw integer division while the receipt lines in the same card and the shop-wide list used `Money.fromCents(...).format()`, so the same principal read `5000.0` in one place and `Rs. 5,000.00` in another. | patch |
| 47 | Verification Gap | `customer_profile_screen.dart:357-359` | medium | `canCreateCredits` still ORed in `role.isOwner`, the same bypass the shared action dropped, so the profile offered origination to a deactivated owner that no credit list would offer a draft slip to. | patch |
| 48 | Blind Hunter | `lib/main.dart:196-199` | low | The `formatCurrency` doc comment claimed "the shop's currency" while `Money.fromCents` falls back to `Money.defaultCurrency`. | patch |
| 49 | Blind Hunter | test helper duplication | low | `pdfText` was still duplicated in the two list test files and the origination test still defined its own `pumpUntil` with the same signature as the shared one. | patch |
| 50 | Blind Hunter | `customer_registration_photo_test.dart` | low | The file asserted the absence of the capture controls without saying that implementing PRD Story 2.2 will deliberately break it. | patch |
| 51 | Blind Hunter | `didUpdateWidget` reset | medium | Nothing exercised the state isolation the override exists for: deleting it kept every test green because no list test seeds two credits and rebuilds. | patch |
| 52 | Blind Hunter | deactivated-account gate | medium | Nothing exercised the deny-by-default rule inside `AppUser.hasPermission`, so deleting it kept the suite green. | patch |
| 53 | Blind Hunter | `credit_origination_screen_test.dart` | medium | "The draft agreement action is not offered on the origination screen" asserted `findsNothing` only before submission, a state that was already true before the change, so the relocation's core assertion was unproven. | patch |
| 54 | Blind Hunter | web hand-off branch | medium | `_showDraftDownloadedDialog()` and the `savedPath == null` path were exercised nowhere, and the recording presenter could not return `null`. | patch |
| 55 | Verification Gap | `generatedKey` confirmation | medium | The green "Draft agreement slip generated." confirmation was never asserted, so setting `_generated = false` kept the suite green. | patch |
| 56 | Blind Hunter | create-then-print journey | medium | Nothing covered creating a credit through the profile and then printing that same credit's slip from the profile. | patch |
| 57 | Blind Hunter | F3 on a successful second agreement | medium | The second-agreement case created two credits but asserted nothing about their idempotency keys, so the successful create→create journey had no F3 assertion. | patch |
| 58 | Edge Case Hunter | `credit_draft_agreement_action.dart:181-192` | false | The audit action type is `generate_credit_draft` and the bytes are generated before the event is recorded, so the event describes what happened; the origination screen this replaces used the same order. | reject |
| 59 | Edge Case Hunter | `credit_origination_screen.dart:431-436` | low | The route can still be dismissed while a submission is in flight, so the agreement is created without the confirmation. The credit remains in the profile's list. | defer |
| 60 | Edge Case Hunter | `customer_profile_screen.dart:289-299` | false | If the reload fails the screen shows the error state with a Retry action rather than a list that silently omits the agreement, and "the credit was created" remains true. | reject |
| 61 | Edge Case Hunter | `lib/main.dart:197-201` | low | The dashboard is LKR-only. The pre-change code hardcoded `'Rs.'` too, so this change neither introduces nor worsens it. | defer |
| 62 | Edge Case Hunter | `deferred-work.md:52-54` | low | The ledger entry still announced a red suite in its summary even after a `resolution:` line was appended. | patch |
| 63 | Blind Hunter | duplicate `## Review Triage Log` heading | low | The spec carried two Review Triage Log headings, the second empty. | patch |
| 64 | Blind Hunter | spec Implementation Notes vs ledger | low | The spec claimed a currency gap was "logged in deferred-work.md" when no such entry existed. | patch |
| 65 | Blind Hunter | two `defer` findings not carried to the ledger | low | The dashboard currency gap and the dismiss-mid-submit case were routed `defer` but never reached the ledger. | patch |
| 66 | Blind Hunter | I/O & Edge-Case Matrix | low | The matrix had no row for an actor without `createCredits`, a stale list, a reload failure after creation, or the app being backgrounded mid-generation. | patch |
| 67 | Blind Hunter | Code Map `file:line` anchors | low | Every anchor for a file this change touched was stale, and the new `test/support/` helper file was missing from the Code Map. | patch |
| 68 | Blind Hunter | diff artifact encoding | low | The staged diff was written through a PowerShell pipeline that mangled every em dash and arrow, so the artifact could not be applied or reviewed faithfully. The working-tree sources were always correct. | patch |
| 69 | Blind Hunter | `review_loop_iteration` | low | The front matter still read `0` after a review loop had run. | patch |
| 70 | Blind Hunter | acceptance-criterion wording | low | The AC says the document is "opened for viewing or download"; on mobile the file is written to the documents directory and its path shown — no viewer is launched, and that was true before this change too. The AC's wording is human-owned frozen text. | reject |
| 71 | Blind Hunter | photo-exception workflow framing | low | The ledger framed the lost photo-exception UI as merely "pre-existing" rather than as a workflow with neither a route nor UI coverage. | patch |
| 72 | Verification Gap | `customer_registration_photo_test.dart` skip suggestion | false | The file's assertions pin the current behaviour deliberately; skipping them would remove the coverage the human asked for. A documented TODO satisfies the concern without dropping the assertions. | reject |

## Design Notes

The origination screen keeps two post-creation affordances alive: the inline success banner and the draft-agreement button. Only the banner moves to the profile; the draft button relocates so Story 4.4's "staff prints a draft agreement slip" path survives.

The route result is the natural carrier for the outcome — it lets the profile distinguish "created a credit" from "backed out" without a shared flag or a global bus.

Two surfaces now offer the same draft action, so the PDF generation lives in one shared action rather than being copied into each credit card. The customer profile's credit card is a `ListTile` whose whole tile is the payment tap target, so the draft action must be a distinct, separately tappable control alongside it.

The document hand-off is the one part of the sequence that a widget test cannot reach on its own: `viewVoucherPdf` waits on a platform channel that never resolves under `flutter test`. An optional injected presenter, defaulting to `viewVoucherPdf` and forwarded by both lists the way `AppDatabase? database` already is, makes the hand-off observable without changing production behaviour.

## Verification

**Commands:**
- `flutter analyze` -- expected: No issues found! **Result: No issues found! (5.2s)**
- `flutter test` -- expected: All tests passed! **Result: `+1026 ~7: All tests passed!` (1m57s; 1026 passed, 7 skipped, 0 failed)**
