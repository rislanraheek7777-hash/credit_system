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
  summary: The full repository test run remains red with 28 pre-existing failures unrelated to Story 8.1.
  evidence: `flutter test test/unit/ test/widget/` reports 943 passed / 28 failed; failures are in drift migration v11/v13/v14/v15/v17/v18/v19/v20 tests, customer photo/registration/model tests, the payment schema test, and the untracked `_tmp_db_test.dart` timeout. No story-touched test fails. Flagged by edge-case-hunter review.

