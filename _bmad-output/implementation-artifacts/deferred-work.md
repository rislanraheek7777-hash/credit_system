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
