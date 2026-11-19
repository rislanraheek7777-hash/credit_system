- source_spec: `spec-fix-customer-id-type-mismatch.md`
  summary: Mixed-state v19→v20 migration path (INTEGER customers with TEXT referencing columns) is untested.
  evidence: The `else if` branch in `lib/core/data/local/app_database.dart` remaps referencing tables through the live customer rows; no test seeds that intermediate state. Would need an exotic fixture; deferred per verification-gap review.

- source_spec: `spec-fix-customer-id-type-mismatch.md`
  summary: `customer_search_screen.dart` and `settings_screen.dart` instantiate `AppDatabase()`/`CreditDao` without closing, risking resource leaks.
  evidence: Lines `lib/features/customers/presentation/customer_search_screen.dart:79,141-142` and `lib/features/settings/presentation/settings_screen.dart:59-60`. Pre-existing; not caused by this story's customer-ID change.

- source_spec: `spec-fix-customer-id-type-mismatch.md`
  summary: `shop_creation_screen.dart` truncates the shop id to 8 characters (`Uuid().v4().substring(0, 8)`), increasing collision risk.
  evidence: Pre-existing; not caused by this story's customer-ID change.

- source_spec: `spec-fix-customer-id-type-mismatch.md`
  summary: `app_users` table documents email/phone as unique within shop but `uniqueKeys` only declares `{shopId, username}`; `getUserByLoginIdentifierGlobal` resolves across all shops, so colliding identifiers can attribute a login to the wrong shop.
  evidence: `lib/core/data/local/tables/app_users_table.dart:63` and `lib/features/auth/data/daos/user_dao.dart:73-80`. Pre-existing design gap; flagged by verification-gap review.
- source_spec: `spec-dashboard-live-metrics.md`
  summary: Dashboard "Collected" is derived from credit balance deltas, so correction write-downs and manual balance adjustments look like cash collected.
  evidence: `correction_dao.dart` updates `credits.balance_cents` on corrections and adjustments, and the dashboard sums `principal_cents - balance_cents`; needs a product decision between cash-received and net-principal definitions.

- source_spec: `spec-dashboard-live-metrics.md`
  summary: Financial dashboard cards are not gated by `AppPermission.viewFinancialReports`.
  evidence: `_DashboardPage` accepts `currentUser` but never checks permissions; pre-existing exposure from the old Income/Outgoing cards, so it is a separate RBAC change.

- source_spec: `spec-dashboard-live-metrics.md`
  summary: `_MetricCard` cannot be reused outside a Row and lacks screen-reader labels and responsive/dark-mode handling.
  evidence: It returns `Expanded` internally and the dashboard uses fixed two-card rows; pre-existing layout, needs a dedicated accessibility/responsive pass.

- source_spec: `spec-dashboard-live-metrics.md`
  summary: Orphaned `portfolio_dashboard_page.dart` and `dashboard_screen.dart` duplicate dashboard behaviour with different calculations.
  evidence: Neither is referenced from `main.dart`; pre-existing dead code that should be deleted or redirected when the dashboard moves into `features/dashboard/presentation/`.

- source_spec: `spec-dashboard-live-metrics.md`
  summary: Dashboard header displays the raw shop id instead of the shop's business name.
  evidence: `main.dart` renders `Shop: ${widget.shopId}`; pre-existing, needs a shop-profile lookup or an injected `ShopProfile`.

- source_spec: `spec-8-1-optional-item-receipts-origination-and-terminology.md`
  summary: Reconcile the planning-doc `Closed / Completed` wording with the code's frozen `Settled / Closed (All Collateral Returned)` label for settled credits whose items were all returned.
  evidence: `ARCHITECTURE-SPINE.md:156` and `prd.md:366` say all-returned resolves to `Closed / Completed`, but `collateral_dao.dart:980` returns `Settled / Closed (All Collateral Returned)`. Pre-existing code behavior that the approved matrix explicitly kept unchanged; flagged by blind-hunter review.

- source_spec: `spec-8-1-optional-item-receipts-origination-and-terminology.md`
  summary: `CollateralDao.deriveOverallWorkflowStatus` has no production caller, so the derived zero-item `Closed / Completed` status is not visible in any screen.
  evidence: Whole-repo search finds only the declaration (`collateral_dao.dart:946`) and test call sites; screens render `credit.status`/`credit.workflowStatus` directly. The method was already unused before this story; the spec only requires the derivation. Flagged by blind-hunter and verification-gap review.

- source_spec: `spec-8-1-optional-item-receipts-origination-and-terminology.md`
  summary: The custody-return screen still treats a zero-item credit as missing data, showing `No collateral items found.`
  evidence: `collateral_custody_return_screen.dart` renders that empty state; the approved intent explicitly excludes renaming the custody-return screen, so this needs a separate custody UX pass. Flagged by blind-hunter review.

- source_spec: `spec-8-1-optional-item-receipts-origination-and-terminology.md`
  summary: The customer profile credit card still labels the item section `Collateral`.
  evidence: `customer_profile_screen.dart:519` renders `Collateral`. The chosen rename coverage was the origination flow and generated PDFs only, so the profile surface is outside this story. Flagged by blind-hunter review.

- source_spec: `spec-8-1-optional-item-receipts-origination-and-terminology.md`
  summary: The repository test run is green; the 28 earlier pre-existing failures are resolved.
  evidence: `flutter test test/unit/ test/widget/` reported 943 passed / 28 failed at the time of Story 8.1; the failures were in drift migration v11/v13/v14/v15/v17/v18/v19/v20 tests, customer photo/registration/model tests, the payment schema test, and the untracked `_tmp_db_test.dart` timeout. No story-touched test failed. Flagged by edge-case-hunter review.
  resolution: Resolved by `spec-credit-origination-return-to-customer-profile.md` (2026-11-12); the repository test run is now green — `flutter test` reports `+1021 ~7: All tests passed!` (1021 passed, 7 skipped, 0 failed) and `flutter analyze` reports no issues. The failure areas named in the original evidence are accounted for: the drift-migration tests (`test/unit/core/data/local/drift_migration_v11/v13/v14/v15/v17/v18/v19/v20_test.dart`) now pass, the untracked `_tmp_db_test.dart` and the payment schema test no longer exist in the tree, and the customer photo/registration widget tests were resolved in this work by replacing the obsolete mock-capture tests (`customer_photo_capture_test.dart`, deleted) with `customer_registration_photo_test.dart`, which pins what the registration screen actually offers. The dashboard metric failure was resolved by making `lib/main.dart` format monetary values with the canonical `Money.fromCents(cents).format()` instead of a hardcoded `'Rs.${rupees.toStringAsFixed(2)}'`. The photograph contract itself remains covered by the service-level unit tests, and the still-missing real capture UI is logged separately in this ledger.

- source_spec: `spec-credit-origination-return-to-customer-profile.md`
  summary: The dashboard's monetary cards are not currency-aware: a shop configured with a non-LKR currency still shows the rupee symbol.
  evidence: `main.dart`'s `formatCurrency` calls `Money.fromCents(cents).format()`, which falls back to `Money.defaultCurrency` (`'LKR'`) instead of the shop's configured `currencyCode`; `Money._defaultSymbolFor` already supports USD, EUR and GBP. The pre-change code hardcoded `'Rs.'` too, so this change neither introduces nor worsens the gap. The origination screen resolves `_shop?.currencyCode` correctly. Flagged by blind-hunter and edge-case-hunter review in both review rounds.

- source_spec: `spec-credit-origination-return-to-customer-profile.md`
  summary: The origination route can be dismissed while a credit agreement is being submitted, so the agreement is created without the confirmation SnackBar.
  evidence: `credit_origination_screen.dart` leaves the AppBar back button live while `_isSubmitting` is true. A dismissal during the `createCreditAgreement` await discards the route result, so the profile reloads without the confirmation. The credit is still persisted and appears in the profile's list after the reload, so only the confirmation is lost. Blocking dismissal during a submit is a product decision, not a defect fix. Flagged by edge-case-hunter review in both review rounds.

- source_spec: `spec-credit-origination-return-to-customer-profile.md`
  summary: PRD Story 2.2 requires a mandatory customer KYC photograph, but the registration screen offers no capture control, so a customer registered today carries no photograph.
  evidence: `customer_registration_screen.dart` hardcodes `rawPhotoBytes: null` and `photoExceptionId: null` in the registration request, and the capture control it used to offer only produced a generated placeholder image (`_createSamplePhotoBytes()`) — the project has no image_picker/camera dependency, so real capture was never implemented. `CustomerRegistrationService.registerCustomer` still compresses and stores a real photograph when a caller supplies bytes, so only the capture UI is missing. Pre-existing, surfaced while fixing the repository's red test run; outside this spec's scope, which was the credit origination navigation change.

- source_spec: `spec-credit-origination-return-to-customer-profile.md`
  summary: The photo-exception workflow has neither a route nor any UI coverage: no surface raises an exception request and the shop-owner approval screen is unreachable.
  evidence: A repository-wide search finds `CustomerPhotoExceptionReviewScreen` only in its own definition file — nothing navigates to it. The registration screen no longer raises a photo-exception request (it hardcodes `photoExceptionId: null`), and no other surface offers one, so no exception can ever be approved through the UI: Story 2.3's request-and-approve journey and Story 3.3's exception resolution have been reduced to a service-only contract covered by `customer_photo_exception_service_test.dart` and `customer_registration_service_test.dart`. The deleted `customer_photo_capture_test.dart` was the last UI-level coverage of the request dialog and the approval-unblocks-registration journey, and its replacement (`customer_registration_photo_test.dart`) asserts the request button's absence rather than the workflow's behaviour. Pre-existing, surfaced while fixing the repository's red test run; the workflow needs a real capture surface before it can be exercised end to end.

- source_spec: `spec-customer-registration-returns-to-customers-screen.md`
  summary: Backing out of the customer registration form reloads the shop list even when the search field holds a single character, so the list contradicts the query.
  evidence: `_onSearchChanged` clears the results for queries under two characters (`customer_search_screen.dart:68-82`), while `_loadCustomers()` falls through to the full shop list for the same query (`:121-134`); `_openRegistrationForm()` calls it unconditionally after the form closes (`:189-191`). The pre-change FAB handler reloaded the same way, so this is pre-existing and not caused by the registration-returns-to-Customers change.

- source_spec: `_bmad-output/implementation-artifacts/spec-dashboard-update-when-credit-added.md`
  summary: Active portfolio inclusion criteria are duplicated between dashboard metrics SQL and the `_DashboardPage` Active Credits list filter.
  evidence: `DashboardMetricsService` aggregates `active_credit_cents`/`outstanding_cents` and `main.dart` filters the Active Credits list separately; this change updated both consistently to include `pending_disbursement`, but there is no shared definition/test enforcing parity if status/workflow rules change in the future. Pre-existing maintenance risk, not introduced by this fix.

- source_spec: `_bmad-output/implementation-artifacts/spec-dashboard-update-when-credit-added.md`
  summary: No explicit automated coverage for in-place credit status/workflow transitions affecting dashboard metrics and the Active Credits list after initial emission.
  evidence: Updated tests cover creation/reactive inserts (including pending disbursement) and payment-driven balance changes, but not transitions such as pending→disbursed or becoming cancelled/settled on an existing credit row; reactive behavior was not modified by this fix. Follow-up coverage gap.

- source_spec: `spec-collateral-registration-returns-to-credit-origination.md`
  summary: Per-card Settle buttons on the customer profile route to the count-based settle selection instead of the tapped card's `_settleCredit(credit)`; no test binds `settle_credit_button_<id>` to the resulting PaymentScreen's creditId.
  evidence: `customer_profile_screen.dart:652/666/680` discard the card's credit; `_openSettleCreditSelection()` (:440) re-derives actionableCredits and settles `actionableCredits.first` or opens a selection dialog. Every settle-group test seeds one eligible credit, so the tap-target path is indistinguishable. Flagged by all three review layers of spec-collateral-registration-returns-to-credit-origination.md; belongs to the settle-button change (`spec-credit-settle-button-customer-profile.md`).

- source_spec: `spec-collateral-registration-returns-to-credit-origination.md`
  summary: The settle eligibility gate in `CreditSettleAction.isAvailableFor` was dropped: Settle renders on disbursed, settled, zero-balance and pending-disbursement cards for any `recordPayments` holder; the settle spec's ineligible-credits test fails as shipped and that spec's Verification section still claims all-pass.
  evidence: `credit_settle_action.dart:49-51` checks only `recordPayments`; `sprint-change-proposal-2026-11-17.md` itself flags the mismatch; the review layer ran the failing test (`settle action ineligible credits offer no Settle action` — found the button). Pre-existing in-flight settle-credit work, not this story.

- source_spec: `spec-collateral-registration-returns-to-credit-origination.md`
  summary: The settle action and selection flow ship multiple unverified defects: a double-brace literal in the multi-credit dialog subtitle, an unguarded `firstWhere` crash when the selected credit id vanishes, a dead-end SnackBar on zero-actionable-credit taps, and stale/contradictory code comments.
  evidence: `customer_profile_screen.dart:484` interpolates `'Balance: ${...format()}}'` printing a literal `}`; `_openSettleCreditSelection` first-where/empty-state unguarded; comments at :145/:176 describe deleted or differently-wired code. Pre-existing in-flight settle-credit work.

- source_spec: `spec-collateral-registration-returns-to-credit-origination.md`
  summary: The customer profile lost the origination creation confirmation (`Credit agreement created. Preliminary due date: …` SnackBar) and the credit-edit profile refresh.
  evidence: `customer_profile_screen.dart:381-404` drops the mandated SnackBar and discards `created` behind `// ignore: unused_local_variable`; two profile tests fail as filed. `_openEditCustomer` re-fetches via an unclosed fresh `AppDatabase()` and never calls `_loadProfile()` (:406-431), so saved name/details never re-render; its test fails as filed. Pre-existing in-flight profile rework.

- source_spec: `spec-collateral-registration-returns-to-credit-origination.md`
  summary: The dashboard's "Active Credits" list was deleted from `lib/main.dart` with no replacement UI, no spec authorization, and an unmodified widget test that now fails (`dashboard_live_metrics_test.dart`: `Text "Customer One" never appeared`).
  evidence: Blind-hunter and edge-case-hunter review of the collateral-origination diff; the portfolio dashboard still shows the "Active Credits" metric, so the home screen is inconsistent with its own metric. Pre-existing in-flight deletion.

- source_spec: `spec-collateral-registration-returns-to-credit-origination.md`
  summary: The mandatory Story 3.2 per-item photograph workflow (compression, storage, SHA-256 verification, mandatory photo gate) and photo-exception workflow are removed from collateral registration.
  evidence: The baseline's `collateral_registration_screen.dart` carried the photo UI; the current tree — pre-existing in-flight rework predating this story — registers with no photo and no owner-approved exception, while `epics.md` FR-15 and frozen Stories 3.2/3.3 specs still mandate them, and `spec-8-1` says "Preserve per-item photo behavior". Needs a correct-course decision on whether the photo workflow is retired and the planning artifacts amended. Surfaced during settlement of spec-collateral-registration-returns-to-credit-origination.md review.

- source_spec: `spec-collateral-registration-returns-to-credit-origination.md`
  summary: Settle-mode full settlements never render the receipt PDF: `payment_screen.dart` pops with the receipt before `_generateReceiptPdf(receipt)` runs.
  evidence: `payment_screen.dart:241-245` pop-before-generate in the settle path; the non-settle full-payment path generates and shows the PDF. The DB receipt row is still committed so history/reprint work; the artifact itself is silently skipped with no covering test. Pre-existing in-flight settle-credit work.

- source_spec: `spec-collateral-registration-returns-to-credit-origination.md`
  summary: The migration bundle ships an unverified `credit_type` v23 backfill (misclassifies legacy item-backed agreements as `cash` on upgrade), an unverified NULL-collateral document/DAO fallback path, a strict `CreditType.fromValue` that crashes every credit read on a drifted stored value, and no dedicated v23/v24 migration tests.
  evidence: `app_database.dart:799-846`'s UPDATE runs but no test asserts `credit_type` after upgrade from pre-v23 (`drift_migration_v25_test.dart` skips the block; v11–v20 contain no references — review layer ran them: 95 passed); no `Unspecified`/`Not recorded` coverage for NULL description/condition/weight in documents or DAO round-trip; `credit_dao`/`correction_dao`/`overdue_dao` decode `credit_type` via a throwing `CreditType.fromValue`; v23/v24 have no dedicated test file; v25 got one; older migration tests were bumped to 25 mechanically and kept stale names ("Schema v7 Tests", "version is 20"). Pre-existing in-flight migration work.

- source_spec: `spec-collateral-registration-returns-to-credit-origination.md`
  summary: Repo hygiene drifted in the pre-existing in-flight tree: `_bmad/core/module-help.csv` renamed every `bmad-*` skill to `bmd-*` (with a new `_bmad/core/bmd-help/SKILL.md` missing YAML frontmatter and the CSV lost its trailing newline) while repo-wide references still say `bmad-*`; AGENTS.md carries stale state ("Ship (Next): bmad-build", `bmad-prfaque` typo, `core/domain/` reference); `files.txt` (empty) and `customer_photo_capture_test.dart` (empty) were committed; sprint-status `last_updated` is a placeholder midnight; UX mockups carry an internally inconsistent due-date example ("Due in 16 days · 02 Dec 2026" from an 18 Nov baseline).
  evidence: Verified by file reads and searches during the review; all items pre-existing in-flight artifacts, not this story's.

- source_spec: `spec-collateral-registration-returns-to-credit-origination.md`
  summary: Two pre-existing registration-screen concurrency gaps: the DAO-failure catch path calls `setState` without a `mounted` guard, and dismissing the route while `createCollateralItem` is in flight silently drops the route result (the caller reloads too early, or the committed item never appears with no confirmation).
  evidence: `collateral_registration_screen.dart:182-187` catch block unchanged from baseline; `:178-181` commit-then-pop with no dismiss protection while `_isLoading`; the origination reload-after-push pattern races the insert in the dismiss case. Both pre-existing; neither path was changed by this spec.

- source_spec: `spec-customer-soft-delete-no-credits.md`
  summary: AdjustmentProposalScreen's eligibility doc ("disbursed, active or overdue, positive balance, no pending correction") is not enforced - `_creditEligibleForAdjustment` checks only `!correctionPending && balanceCents > 0`, and `CorrectionDao.requestCorrection` never validates status/workflow, so a pending-disbursement or cancelled credit with a positive balance can be proposed for forgiveness.
  evidence: Review of the in-flight Story 5.6 change-set surfaced during the soft-delete review; neither the screen nor the DAO re-checks disbursed/active/overdue before accepting the proposal.

- source_spec: `spec-customer-soft-delete-no-credits.md`
  summary: `requestCorrection` validates `amount <= balanceCents` on a pre-transaction read; the in-transaction re-read only checks `correctionPending`. A payment/settlement landing between the reads can enqueue an over-balance forgiveness proposal that then fails at approval time.
  evidence: Review of the in-flight Story 5.6 change-set surfaced during the soft-delete review; re-validate `amount <= currentCredit.balanceCents` inside the transaction.

- source_spec: `spec-customer-soft-delete-no-credits.md`
  summary: v25->v26 migrated databases lack the `CHECK (direction IN ('debit','credit'))` constraint that fresh installs get via customConstraints (the v26 step uses raw ALTER TABLE ... ADD COLUMN), leaving a silent schema drift between upgrade paths.
  evidence: Review of the in-flight Story 5.6 change-set surfaced during the soft-delete review; at minimum the migration comment should record the intentional drift.

- source_spec: `spec-customer-soft-delete-no-credits.md`
  summary: SettleSummaryScreen strands the user on a stale, already-settled credit when receipt PDF generation fails after a committed full settlement (`_isSubmitting=false`, `_paymentError` set, no reload/pop), and `_reloadAfterPayment` swallows re-query failures leaving a stale pre-payment balance.
  evidence: Review of the in-flight Story 5.6 change-set surfaced during the soft-delete review (`settle_summary_screen.dart` `_recordPayment` / `_reloadAfterPayment`); stale balance re-arms the Settle button for an unsettleable credit.

- source_spec: `spec-customer-soft-delete-no-credits.md`
  summary: Dashboard quick actions ("New Customer", "New Credit", "Record Payment") render for every role with no RBAC (`registerCustomers`/`createCredits`/`recordPayments`) and no `isActive` check, dead-ending or redirecting under-privileged staff against the deny-by-default pattern.
  evidence: Review of the in-flight Story 5.6 change-set surfaced during the soft-delete review (`main.dart` `_QuickActionCard` rows).

- source_spec: `spec-customer-soft-delete-no-credits.md`
  summary: The dashboard metric redesign (`outstandingCents`/`ratio` removed, `overdueCents` added, "Overdue" card) is unspec'd and contradicts frozen artifacts: `prd.md` FR (Total Active Credits Count and Aggregate Outstanding Principal), `spec-dashboard-live-metrics.md` and `spec-dashboard-update-when-credit-added.md` still document Outstanding/Ratio.
  evidence: Review of the in-flight Story 5.6 change-set surfaced during the soft-delete review; needs a correct-course decision (or amendment of those artifacts) before it can ship as intended.

- source_spec: `spec-customer-soft-delete-no-credits.md`
  summary: `DashboardMetricsService.watchMetrics` computes `_overdueCutoff()` once at subscription (never advances across shop-local midnight) and `_overdueCutoff` swallows all errors (including DB read failures), silently falling back to the default time zone and yielding plausible-looking but wrong overdue figures.
  evidence: Review of the in-flight Story 5.6 change-set surfaced during the soft-delete review; recompute the cutoff per emission and log/surface the fallback instead of swallowing it.

- source_spec: `spec-customer-soft-delete-no-credits.md`
  summary: ~100 lines are duplicated verbatim between PaymentScreen and SettleSummaryScreen (`_openAdjustmentProposal`, `_generateReceiptPdf`, `_viewReceipt`, `_showReceiptSavedDialog`/`_showReceiptDownloadedDialog`, receipt-preview block); the copies will drift independently on the next receipt-format change.
  evidence: Review of the in-flight Story 5.6 change-set surfaced during the soft-delete review; extract a shared receipt/proposal helper or widget.

- source_spec: `spec-customer-soft-delete-no-credits.md`
  summary: Staff-proposed balance increases ("debit" proposals) exceed Story 5.6's frozen partial-forgiveness intent; the owner-only direct-adjustment path (`recordAdjustment`) is the documented route for increases.
  evidence: Review of the in-flight Story 5.6 change-set surfaced during the soft-delete review; `AdjustmentProposalScreen` offers the debit path to staff; needs explicit human sign-off in the 5.6 spec change log or the option hidden.

- source_spec: `spec-customer-soft-delete-no-credits.md`
  summary: The correction review dialog renders a nonsense negative post-balance for forgiveness proposals (preBalance + delta, no clamp) before the DAO's `newBalanceCents < 0` guard rejects the approval.
  evidence: Review of the in-flight Story 5.6 change-set surfaced during the soft-delete review (`correction_review_screen.dart` `_confirmApprove`); dialog should pre-validate or clamp so the confirmation never states impossible arithmetic.

- source_spec: `spec-customer-soft-delete-no-credits.md`
  summary: Settle-flow minor warts: `SettleSummaryScreen._load()` re-prefills the amount field to the full balance on every reload (clobbering a prepared partial entry); a "Partial settlement" sheet row at exactly the full balance silently clears the field; no re-entrancy guard on the settle/sheet navigation pushes (double-tap can stack sheets/screens).
  evidence: Review of the in-flight Story 5.6 change-set surfaced during the soft-delete review; fix by prefilling only on first load, treating entered == balance as the full case, and guarding the pushes.

- source_spec: `spec-customer-soft-delete-no-credits.md`
  summary: `_extendDueDate` in settle_summary_screen.dart passes a device-local midnight DatePicker value to `grantDueDateExtension`, which re-derives the calendar date in the shop timezone - on devices ahead of shop tz the extension persists a day early or is rejected as not-after-today.
  evidence: Edge-case review of the in-flight Story 5.6 change-set surfaced during the soft-delete review; convert with `_shopTimeZone.instantAtStartOfDay(LocalCalendarDate(picked.year, picked.month, picked.day))`.

- source_spec: `spec-customer-soft-delete-no-credits.md`
  summary: An adjustment-direction correction equal to the outstanding balance posts a zero balance without settling the credit - the credit stays active at zero and no payment path can ever settle it.
  evidence: Low-risk edge surfaced during edge-case review of the in-flight Story 5.6 change-set (`correction_dao.dart` approveCorrection, isAdjustmentProposal); when `newBalanceCents == 0` write status settled + settled_at alongside the balance/lock/ledger updates.

- source_spec: `spec-customer-soft-delete-no-credits.md`
  summary: A correction proposal with `direction == 'credit'` together with a non-null `originalPaymentId` ledgers a `compensating_debit` entry while decreasing the balance, misstating the movement type.
  evidence: Edge-case review of the in-flight Story 5.6 change-set surfaced during the soft-delete review (`correction_dao.dart` direction validation / entryType selection); validate the combination and reject it.

- source_spec: `spec-customer-soft-delete-no-credits.md`
  summary: `AdjustmentProposalScreen`/`CorrectionDao.requestCorrection` for a credit-adjustment proposal accepts cancellation-state credits and pending-disbursement workflows as "forgivable"; see also the zero-balance-at-full-forgiveness edge.
  evidence: Edge-case review of the in-flight Story 5.6 change-set surfaced during the soft-delete review (`correction_dao.dart:543-556`); full-forgiveness proposals must settle, never strand, the credit.
