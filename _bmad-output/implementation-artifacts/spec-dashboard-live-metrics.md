---
title: 'Live Dashboard Metrics for Customers, Staff, and Credits'
type: 'feature'
created: '2026-11-05'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The dashboard's summary cards are hardcoded placeholders that always return `0`, so adding a customer, staff account, or credit and reopening the dashboard shows no change.

**Approach:** Replace the placeholder getters with one shop-scoped Drift aggregate query exposed as an auto-updating stream, and render the dashboard metric cards from that stream. The stream re-emits whenever the `customers`, `app_users`, `credits`, or `payments` tables change, so the dashboard reflects new customers, staff, credits, and payments without a manual reload.

**Decisions:**
- Total Staff counts every `app_users` row for the shop with `is_active = 1`, including the shop owner.
- Total Credits counts every non-cancelled credit agreement (active, overdue, and settled).
- Active Credit sums `principal_cents` for credits currently `active` or `overdue`.
- Cancelled credits are excluded from counts, outstanding, and collected totals.
- The ratio keeps the existing dashboard formula: `collected / outstanding`, reported as `0` when outstanding is `0`.
- The existing `$` currency formatting is retained; shop currency selection is out of scope.

</frozen-after-approval>

## Implementation Notes

**Files changed**
- `lib/features/dashboard/domain/models/dashboard_metrics.dart` (new): immutable snapshot with the seven metrics and the legacy `collected / outstanding` ratio.
- `lib/features/dashboard/data/services/dashboard_metrics_service.dart` (new): one shop-scoped aggregate `customSelect` with `readsFrom` the four watched tables, exposed as `watchMetrics` (`watchSingle`) and `loadMetrics`.
- `lib/main.dart`: injected an optional `AppDatabase` through `MainApp` and the dashboard/customers/credit-details pages; `_DashboardPage` now owns a `DashboardMetricsService` stream; replaced the Income/Outgoing placeholders with Total Credits, Active Credit, Outstanding, Collected, and Ratio cards; added `ValueKey`s to every card for widget tests.
- `lib/core/data/local/connection/database_connection.dart`: `openInMemoryConnection` now accepts `closeStreamsSynchronously` so widget tests can stop drift query streams without leaving a pending timer in the fake-async zone.
- Tests: `test/unit/features/dashboard/dashboard_metrics_service_test.dart`, `test/widget/features/dashboard/dashboard_live_metrics_test.dart`, and updated `test/widget_test.dart`.

**Decisions**
- A single aggregate query keeps all cards mutually consistent; it is cheaper and less error-prone than one query per card.
- Active Credit and Outstanding are restricted to credits whose cash was actually disbursed (`workflow_status IN ('disbursed', 'overdue')`). A new agreement is created as `status = active` while still `pending_disbursement`; counting it would overstate the live portfolio because repayment has not started.
- Total Credits still counts every non-cancelled agreement (including pending disbursement), matching the frozen decision.
- The dashboard is a `StreamBuilder` over a Drift stream, so inserts/updates re-emit without a manual reload; pull-to-refresh simply resubscribes.

**Surprises**
- `HEAD:lib/main.dart`'s dashboard was syntactically broken (mangled method bodies, an unterminated string, and count queries that were never awaited), so it could not render real metrics. The spec's "placeholders that always return 0" description reflects that non-functional state.
- Drift schedules a `Timer.run` when a watched query loses its last listener. In `flutter_test` that timer outlives the fake-async zone and fails the test, so widget tests use the synchronous stream-close option.

**Verification**
- `flutter test test/unit/features/dashboard/dashboard_metrics_service_test.dart test/widget/features/dashboard/dashboard_live_metrics_test.dart test/widget_test.dart` — 5 tests passed.
- `dart analyze lib/main.dart lib/core/data/local/connection/database_connection.dart lib/features/dashboard test/unit/features/dashboard test/widget/features/dashboard test/widget_test.dart` — no issues.

## Review Triage Log

- Undisbursed agreements counted in Active Credit/Outstanding — `medium` — patch. Confirmed `credit_dao.dart:357-358` creates `status: active` with `pending_disbursement`; the aggregate now filters on `workflow_status IN ('disbursed', 'overdue')`, and a pending credit fixture plus assertion cover it.
- Collected derived from `principal - balance` so corrections/write-downs move it — `low` — deferred. Confirmed `correction_dao.dart` mutates `credits.balance_cents` on approvals/adjustments, but "Collected" is defined as principal repaid net of balance; choosing a cash-vs-net definition is a product decision.
- Financial cards not permission-gated (`viewFinancialReports`) — `medium` — deferred. Pre-existing exposure: `HEAD:lib/main.dart` already rendered Income/Outgoing to every role, so this change did not introduce it; an RBAC pass is a separate change.
- Loading/error/empty states all render as zeros; raw error text shown — `low` — rejected. The pre-first-event zero frame is brief, and adding spinner/retry/empty states is more than a direct correction for a rarely reached DB failure.
- Ratio card lacks a `%`/explanation and returns 0 when collected > 0 with no outstanding — `false` for the zero-denominator claim: the frozen decision explicitly requires ratio `0` when outstanding is `0`; the missing `%` label is `low` and not worth an extra surface.
- Money formatting bypasses `Money` and shows hardcoded `$` — `false`. The frozen decision explicitly retains the existing `$` formatting and declares shop-currency selection out of scope.
- `DashboardMetrics` lacks `==`/`hashCode`/`copyWith` — `low` — rejected. The only consequence is a rebuild on a watched-table write, which is the expected cost of a live dashboard.
- `_metricsStream` is not rebuilt when `shopId`/`database` inputs change — `low` — rejected. The shop is fixed for a session and the page is recreated on navigation; only hot-reload of `MainApp` could hit it.
- Pull-to-refresh resubscribes and returns immediately — `low` — rejected. Drift streams are already live and the new subscription re-reads the database, so the indicator is redundant rather than wrong.
- `_MetricCard` is `Expanded`-only, fixed two-column, and has no semantics — `low` — deferred. Pre-existing widget/layout; an accessibility and responsive-layout pass is a separate change.
- Orphaned `portfolio_dashboard_page.dart` / `dashboard_screen.dart` compete with the live dashboard — `low` — deferred. Pre-existing dead code; the new page stayed in `main.dart` to keep the change small.
- Database-ownership fallback could open a second connection — `false`. Production always injects `_appDatabase` through `MainApp`; the fallback only serves standalone/test construction and is closed in `dispose`, which is stricter than `HEAD`'s per-build `AppDatabase()`.
- `openConnection` does not forward `closeStreamsSynchronously` — `low` — rejected. The flag is a test-only need; callers can use `openInMemoryConnection` directly, and adding a resolver parameter expands the public surface for no production caller.
- Spec artifact incomplete / misstates prior behaviour — `false` for the behaviour claim: `HEAD`'s dashboard was broken and could not produce metrics; the artifact is finalized by this log.
- Metric definitions not documented for readers — `low` — rejected. `DashboardMetrics` documents each field and the cards carry the same labels; a glossary is outside this change.
- Tests omit live payment re-emission and half the cards — `medium` — patch. Added a live payment assertion (Total Transactions 1 → 2) to the reactive unit test and assertions for Total Transactions, Outstanding, Collected, and Ratio to the widget test; shop scoping and cancelled-credit exclusion were already covered.
- Duplicated polling/cleanup scaffolding in tests — `low` — rejected. The shared synchronous-close option already removes the real failure mode; a shared helper would not change behaviour.
- SQL repeats `shop_id = ?` seven times with a matching loop count — `low` — rejected. The contract is local to one method and covered by three tests; rewriting to a Drift expression query is unnecessary churn.
- Dashboard header shows the raw shop id instead of the shop name — `low` — deferred. Pre-existing `Shop: $shopId` text; resolving the profile needs a new lookup path and belongs with shop-profile work.
- Smoke test now uses `findsWidgets` for "Dashboard" — `low` — rejected. It is a test-only assertion weakened by the new header text; the widget test and card keys provide the real coverage.



