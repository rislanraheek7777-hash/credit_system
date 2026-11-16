---
title: 'Dashboard updates when a customer credit is added'
type: 'bugfix'
created: '2026-11-16'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: 'ddd28f67dc9905df6a9a033ff2d51eac493dbdd4'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** When a customer credit agreement is created (added via credit origination), the main dashboard does not reflect it as the user expects: the metric cards and Active Credits list should update to include the newly created (pending-disbursement) credit.

**Approach:** On successful agreement creation (`CreditDao.createCreditAgreement`, `status=active`, `workflow_status=pending_disbursement`), update the main dashboard (`_DashboardPage` in `lib/main.dart`) so **Total Credits**, **Active Credit**, **Outstanding**, and the **Active Credits list** include pending-disbursement agreements (same shop) without manual restart. Adjust aggregate metric definitions/filters and list filtering accordingly, keep updates reactive via existing Drift streams, and update affected specs/tests to match the new semantics.

**Decisions (user-confirmed):**
- Q1 = **B**: When a credit agreement is created (pending disbursement), Total Credits and Active Credit/Outstanding (and the Active Credits list) must reflect it immediately.
- Q2 = **A**: "Add customer credit" means creating a credit agreement (origination / `createCreditAgreement`, pending disbursement).
- Q3 = **A,B**: Issue is observed on the main Dashboard tab metric cards and the Active Credits list in `_DashboardPage` (`lib/main.dart`).

## Boundaries & Constraints

**Always:** Keep shop-scoped data isolation; keep dashboard updates reactive/consistent with existing Drift stream patterns (`DashboardMetricsService.watchMetrics`, `CreditDao.watchCreditsByShopId`); treat newly created pending-disbursement agreements as included in Total Credits, Active Credit, Outstanding, and Active Credits list per Q1; exclude cancelled credits from these counts/sums/lists; follow existing Money/currency presentation patterns used by the dashboard.

**Never:** Do not change unrelated credit lifecycle, payment, disbursement, RBAC, or navigation behavior beyond what is required for this dashboard update; do not introduce a second competing dashboard implementation path; do not modify `portfolio_dashboard_page.dart`/`DashboardScreen` as part of this fix unless required by direct dependency (they are not the reported view).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Agreement created (pending disbursement) | User creates credit in origination; `credits` row inserted `status=active`, `workflow_status=pending_disbursement`, `principal_cents == balance_cents` | `DashboardMetricsService.watchMetrics` emits updated metrics: Total Credits +1, Active Credit +principal, Outstanding +balance/principal for that shop; `_DashboardPage` cards and Active Credits list show the new credit | If creation fails, origination shows existing error; dashboard remains unchanged |
| Dashboard not currently visible at creation time | Credit created while user is on Customer/Profile/other tab | On navigating to Dashboard, stream-backed cards/list show the new pending-disbursement credit (current DB state) | N/A |
| Cancelled credit | Credit `status=cancelled` / workflow cancelled | Not counted in Total Credits, Active Credit, Outstanding, or Active Credits list | N/A |
| Disbursed/overdue credits | Existing disbursed or overdue credits | Continue to be included in relevant metrics/list as before | N/A |
| Other shop data | Credits/users/customers in a different `shopId` | No cross-shop leakage; all aggregates/lists scoped to active `shopId` | N/A |

</frozen-after-approval>

## Code Map

- `_bmad-output/implementation-artifacts/spec-dashboard-live-metrics.md` -- prior "done" spec defining current dashboard metric semantics (Total Credits includes pending non-cancelled; Active Credit/Outstanding/active list exclude pending disbursement), reactive stream approach, and known caveats.
- `lib/main.dart` (`_DashboardPage`, `_DashboardPageState`, ~137-430) -- main dashboard UI: creates `DashboardMetricsService`/`CreditDao`/`CustomerDao`, subscribes to `watchMetrics(shopId)` and `watchCreditsByShopId(shopId)`, renders metric cards (Total Customers/Staff/Credits, Active Credit, Outstanding, Collected, Ratio) and disbursed-only Active Credits list; `_loadCustomers()` is one-time cache (names can be stale) and refresh resubscribes metrics stream only.
- `lib/features/dashboard/data/services/dashboard_metrics_service.dart` (`DashboardMetricsService`) -- single shop-scoped aggregate query streamed via Drift `customSelect(...).watchSingle()` with `readsFrom {customers, appUsers, credits, payments}`; Total Credits = non-cancelled; Active Credit/Outstanding = active/overdue AND workflow `disbursed|overdue`; Collected = sum(principal-balance) for non-cancelled.
- `lib/features/dashboard/domain/models/dashboard_metrics.dart` -- immutable metrics snapshot and ratio (`collected/outstanding`, 0 when outstanding 0).
- `lib/features/customers/data/daos/credit_dao.dart` (`createCreditAgreement`, `confirmCreditDisbursement`, `watchCreditsByShopId`) -- agreement creation inserts `credits` as `active`/`pending_disbursement` (+ `sync_queue`, optional `collateral_items` bind) in one transaction; disbursement transitions to `disbursed` and sets official due date/disbursed fields; shop-scoped watches stream credit changes.
- `lib/features/customers/presentation/credit_origination_screen.dart` -- "Add/Create Credit Agreement" UI; on success pops created `Credit` and resets idempotency; on failure stays open.
- `lib/features/customers/presentation/customer_profile_screen.dart` (`_openAddCredit`, `_loadProfile`, `add_credit_button`) -- entry point to origination; reloads profile after return and shows confirmation only on created result.
- `lib/features/dashboard/portfolio_dashboard_page.dart`, `lib/features/dashboard/presentation/dashboard_screen.dart` -- alternate portfolio dashboard (streams credits, computes different client-side totals/formatting); not mounted by `MainApp` bottom navigation.
- Tests: `test/unit/features/dashboard/dashboard_metrics_service_test.dart`, `test/widget/features/dashboard/dashboard_live_metrics_test.dart`, `test/widget/features/customers/credit_origination_screen_test.dart`, `test/widget/features/customers/customer_profile_screen_test.dart`, `test/unit/features/customers/credit_dao_test.dart` -- existing coverage for reactive metrics, pending-disbursement exclusion from active/outstanding, and origination/create flow.

## Tasks & Acceptance

**Execution:**
- [x] `lib/features/dashboard/data/services/dashboard_metrics_service.dart` -- update aggregate SQL for `active_credit_cents` and `outstanding_cents` to include newly created pending-disbursement agreements (shop-scoped `status IN ('active','overdue')` and `workflow_status IN ('pending_disbursement','disbursed','overdue')`, or equivalent) and update class/field-relevant comments to reflect new semantics -- so creating an agreement immediately increases Active Credit/Outstanding.
- [x] `lib/main.dart` (`_DashboardPage` Active Credits list filter, ~371-376) -- include `CreditWorkflowStatus.pendingDisbursement` alongside disbursed/overdue-active credits in the displayed list (while preserving shop scoping, status checks, sort, and existing UI behavior) -- so the new agreement appears in the Active Credits list on the main dashboard.
- [x] `test/unit/features/dashboard/dashboard_metrics_service_test.dart` -- revise fixtures/expectations and add coverage so a newly created pending-disbursement credit is counted in Total Credits, Active Credit, and Outstanding (and collected behavior remains correct), including reactive re-emission on credit creation; keep shop isolation and cancelled-credit exclusion assertions valid -- prevent regression and lock new semantics.
- [x] `test/widget/features/dashboard/dashboard_live_metrics_test.dart` -- update/add assertions so main dashboard cards (Total Credits, Active Credit, Outstanding) and Active Credits list reflect a newly added pending-disbursement agreement without manual reload -- validate Q3A,B end-to-end at widget level.

**Acceptance Criteria:**
- Given a shop-scoped credit agreement is created via origination as `status=active`, `workflow_status=pending_disbursement`, when `DashboardMetricsService.watchMetrics` emits, then Total Credits increments by 1, Active Credit increments by the agreement principal, and Outstanding increments by the agreement balance/principal for that shop only.
- Given the main Dashboard tab (`_DashboardPage`) is visible or navigated to after agreement creation, when metrics/list streams update, then the Total Credits, Active Credit, Outstanding cards and the Active Credits list show the new pending-disbursement credit without manual app restart.
- Given a cancelled credit or credits in another shop, when dashboard metrics/list are computed, then cancelled credits remain excluded and cross-shop data never appears.
- Given existing disbursed/overdue credit behavior and unrelated flows, when this change is applied, then `dart analyze` on touched files reports no issues and targeted dashboard tests pass.

## Implementation Notes

- `DashboardMetricsService` now treats `workflow_status = 'pending_disbursement'` (with `status IN ('active','overdue')`) as part of Active Credit and Outstanding so newly created agreements are reflected immediately on stream emission.
- `_DashboardPage` Active Credits list now includes pending-disbursement credits (in addition to disbursed/overdue-active) while preserving existing sort/status behavior.
- `DashboardMetrics` field docs updated to match the new aggregate semantics.
- This intentionally supersedes the earlier "live dashboard" behavior that excluded pending-disbursement from active/outstanding/list (see `spec-dashboard-live-metrics.md`).

## Spec Change Log

- 2026-11-16: Implemented dashboard metric/list inclusion for newly created pending-disbursement agreements per frozen intent.

## Review Triage Log

- blind-hunter: Duplicated active-portfolio inclusion rules in `DashboardMetricsService` SQL and `_DashboardPage` Active Credits list filter can diverge on future status/workflow changes. Verdict: `low` (defer). Evidence: both locations were updated consistently in this change (`pending_disbursement` added in both); duplication/maintenance risk is pre-existing and not introduced by this fix. Deferred.
- blind-hunter: No explicit test for in-place credit status/workflow transitions (e.g. pending→disbursed, cancelled/settled) updating metrics/list after creation. Verdict: `low` (defer). Evidence: reactive streams/watch behavior existed before this change and was not modified; spec/matrix did not require transition coverage for this fix. Deferred as follow-up coverage.
- blind-hunter: Pending-disbursement credits in Active Credits list may have unclear/provisional due dates affecting sort/urgency. Verdict: `false`. Evidence: `CreditDao.createCreditAgreement` stores the provided preliminary `dueDate` on the created credit (`status=active`, `workflow_status=pending_disbursement`), and list sorting by `dueDate` is consistent with existing behavior; no bad outcome demonstrated.
- blind-hunter: Including pending-disbursement in outstanding changes collected/outstanding ratio on creation. Verdict: `false`. Evidence: this is the intended consequence of user-confirmed semantics (Q1=B) to include pending agreements in Active Credit/Outstanding; unit/widget expectations were updated accordingly and `collectedCents` remains `principal-balance` for non-cancelled credits.

## Verification

**Commands (as specified):**
- `flutter test test/unit/features/dashboard/dashboard_metrics_service_test.dart test/widget/features/dashboard/dashboard_live_metrics_test.dart`
- `flutter test` (targeted customer/credit tests impacted by changes)
- `dart analyze <touched files>`

**Status:** Not run in this environment — shell command execution failed with `Access is denied` when spawning `pwsh`/`dart`/`flutter`. Manual/CI verification required.

**Manual checks (if no CLI):**
- Run app, add a customer credit via the confirmed flow, navigate to/observe Dashboard and confirm the specified metric/list updates immediately or on stream emission as agreed.
