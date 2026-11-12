---
title: 'Customer registration returns to the customers screen with a confirmation message'
type: 'feature'
created: '2026-11-12'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
context: []
baseline_commit: '624bca935611d4dc6fbd9e1aba71c51c35f4042b'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** After a counter staff member taps "Register Customer", the registration screen keeps them on it, showing an inline green banner — `Customer "..." registered successfully (ID: ...)`. Staff must tap back themselves to reach the Customers screen, and the list they land on is silently stale: nothing tells them the customer they just created is the shop's newest profile, and if a search filter was active the new customer is not in the list at all.

**Approach:** On successful registration the route closes with the created customer as its result; the Customers screen reloads and confirms the registration with a SnackBar. The inline success banner is removed — the confirmation belongs to the screen the user lands on.

**Decisions (human-delegated — the user asked me to choose):**
- The SnackBar reuses the wording the inline banner already used: `Customer "<full name>" registered successfully (ID: <id>).` It names the customer and its id, which is what staff need to identify the profile they just created. Duration 4 seconds, matching the credit-origination confirmation on the customer profile.
- The Customers screen clears any active search filter before reloading, so the newly created customer is actually visible in the list. Leaving the filter would show a list that does not contain the customer the confirmation just announced.
- Backing out of the registration form without submitting produces no confirmation, matching the credit-origination confirmation on the customer profile.
- The registration screen does not auto-open the new customer's profile. Staff may be registering a customer in order to attach a credit, and navigating into a profile unasked would be surprising.

## Boundaries & Constraints

**Always:**
- Registration still writes through the existing `CustomerRegistrationService.registerCustomer`. This change is navigation and messaging only — no new write path, no schema change, no audit or sync-queue change.
- The registration route closes with the created `Customer` as its result on success, and with no result on every other outcome.
- A failed submission (duplicate NIC, shared phone awaiting confirmation, validation error, unexpected error) leaves the registration screen open with its inline message. It never pops and never produces a SnackBar.
- The Customers screen reloads from the database after the route closes, so the new customer is in the list.
- The confirmation is a SnackBar on the Customers screen, not an inline banner on a screen that is no longer mounted.
- The confirmation names the customer and its id. The id is the `int` primary key on `Customer` — not a UUID.

**Never:**
- Do not change `CustomerRegistrationService`, `CustomerDao`, the `customers` schema, or the audit/sync-queue insertion the service performs.
- Do not weaken the duplicate-NIC block or the shared-phone confirmation gate.
- Do not report a failure as a success: no SnackBar unless the service returned a customer.
- Do not touch the credit-origination navigation, the customer profile screen, the dashboard, or the service layer.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Valid form, no duplicate | name + phone filled, NIC free | Customer persisted; route closes with the `Customer`; Customers screen reloads and shows the SnackBar; the new customer is in the list | N/A |
| Shared phone confirmed | first submit raises `SharedPhoneDuplicateException`; staff taps "Confirm separate individual sharing phone number" | Second submit succeeds; route closes with the `Customer`; Customers screen shows the SnackBar | The warning banner stays until the confirm action is taken; no pop before then |
| Duplicate NIC | service raises `DuplicateNicException` | Registration screen stays open; the "Existing Customer Profile" dialog is shown; no SnackBar | Inline message + dialog, as today |
| Validation error | service raises `CustomerValidationException` | Registration screen stays open with the inline error; no SnackBar | N/A |
| Unexpected error | service raises anything else | Registration screen stays open with `Registration failed: ...`; no SnackBar | N/A |
| Backed out | staff dismisses the form without submitting | Route closes with no result; Customers screen reloads; no SnackBar | N/A |
| Active search filter | staff had typed ≥2 characters before opening the form | The filter is cleared and the full shop list is shown, so the new customer is visible | N/A |

</frozen-after-approval>

## Code Map

Paths are relative to the project root.

**Presentation**
- `lib/features/customers/presentation/customer_registration_screen.dart` -- `_register()` (`:83-191`). The success branch (`:113-124`) sets `_statusMessage`/`_isSuccess` and stays mounted; it must instead close the route with the created `Customer`. The catch clauses (`:125` duplicate NIC, `:164` shared phone, `:172` validation, `:181` generic) stay exactly as they are — they keep the staff member on the form with the reason. The status container (`:297-317`) keeps rendering errors; the green success branch becomes unreachable, so `_isSuccess` (`:66`) goes with it.
- `lib/features/customers/presentation/customer_search_screen.dart` -- the "Add Customer" FAB (`:161-176`). The push (`:163-168`) becomes a typed `push<Customer>`; the result is kept; the reload (`:172`) must clear `_searchController` first, because `_loadCustomers()` (`:120-156`) re-runs the active query whenever it is ≥2 characters (`:121-124`) and would otherwise reload a filtered list that does not contain the new customer. The SnackBar is shown only when a customer came back.
- `lib/features/customers/presentation/customer_profile_screen.dart` -- `_openAddCredit()` (`:277-308`) is the pattern being copied: typed push (`:278`), reload (`:292`), null guard for back-out (`:297`), SnackBar with a 4-second duration (`:300-307`). Do not modify.
- `lib/main.dart` -- `_CustomersPage` (`:512-534`) is a `StatelessWidget` with no Scaffold of its own; the Customers screen's Scaffold (`:160`) is nested inside `MainApp`'s (`:98`), so a SnackBar on the root `ScaffoldMessenger` renders above the bottom navigation bar, as the customer profile's does. Do not modify.

**Domain**
- `lib/features/customers/domain/models/customer.dart` -- `Customer` (`:32`) with `final int id` (`:34`) and `final String fullName` (`:40`).
- `lib/features/customers/domain/services/customer_registration_service.dart` -- `registerCustomer` (`:89`) returns `Future<Customer>` and throws `CustomerValidationException`, `DuplicateNicException`, `SharedPhoneDuplicateException`. Do not modify.

**Tests**
- `test/widget/features/customers/customer_registration_screen_test.dart` -- pumps the screen as the ROOT widget (`:8-10`, `:27-29`). A successful registration now closes the route, and a root route has nothing to pop back to, so the harness must push the screen over a dummy host route.
- `test/widget/features/customers/customer_registration_photo_test.dart` -- the "registering without a photograph succeeds" case (`:163-184`) asserts `find.textContaining('Customer "Kumara Silva" registered successfully')` (`:173`), which is the inline banner this change removes. Re-point it at the route result.
- `test/widget/features/customers/customer_search_screen_test.dart` -- the Customers screen's widget tests; they pump the screen as the root and use text finders only. The new registration-journey case belongs here.
- `test/support/customers_test_support.dart` -- the shared helpers: `pumpUntil` (`:34`), `useLargeSurface` (`:48`), `openTestDatabase` (`:58`), `seedShopAndCustomer` (`:67`).

## Tasks & Acceptance

**Execution:**
- [x] `lib/features/customers/presentation/customer_registration_screen.dart` -- close the route with the created `Customer` on success and drop the inline success banner and the now-unreachable `_isSuccess` flag; leave every failure path and the shared-phone gate untouched -- the confirmation belongs to the Customers screen, and the failure paths must keep the staff member on the form with the reason.
- [x] `lib/features/customers/presentation/customer_search_screen.dart` -- type the push as `push<Customer>`, keep the result, clear the search filter before reloading, and show the SnackBar only when a customer came back -- the list must show the customer the confirmation announces.
- [x] `test/widget/features/customers/customer_registration_screen_test.dart` -- push the screen over a dummy host route so a successful registration has somewhere to return to, and assert the route closes with the created customer and that the inline success banner is gone.
- [x] `test/widget/features/customers/customer_registration_photo_test.dart` -- re-point the success assertion at the route result, since the inline banner it asserted is removed.
- [x] `test/widget/features/customers/customer_search_screen_test.dart` -- cover the journey: open the form from the FAB, register, assert the form closed, the list reloaded with the new customer, and the SnackBar text; plus the back-out case, which must show no SnackBar.

**Acceptance Criteria:**
- Given a counter staff member on the Customers screen, when they open the registration form and submit a valid customer, then the form closes and the Customers screen is shown again.
- Given the Customers screen is shown again after a successful registration, when the confirmation appears, then it is a SnackBar reading `Customer "<full name>" registered successfully (ID: <id>).` and the customer list contains the new customer.
- Given a search filter of at least two characters was active when the form was opened, when the registration succeeds, then the filter is cleared and the full shop list is shown, so the new customer is visible.
- Given a submission that fails for any reason, when the error is displayed, then the registration screen remains open and no confirmation SnackBar is shown.
- Given the staff member backs out of the form without submitting, when the Customers screen is shown again, then no confirmation SnackBar is shown.
- Given a shared phone number the staff member explicitly confirmed, when the second submission succeeds, then the route closes and the same confirmation is shown.

## Implementation Notes

**`customer_registration_screen.dart`** -- the success branch of `_register()` now ends with `Navigator.of(context).pop(customer)` instead of setting `_statusMessage`/`_isSuccess`. `_isSuccess` is deleted, and the status container renders in red only: the green branch is unreachable, because the screen is popped before anything it rendered could be read. Every catch clause is untouched, so a duplicate NIC, a shared phone awaiting confirmation, a validation error and an unexpected error all keep the staff member on the form with the reason inline and close the route with no result.

**`customer_search_screen.dart`** -- the FAB's push moved out of the `build` closure into a `_openRegistrationForm()` method on the state, so the `context` used after the `await` is the state's own context and the `mounted` guard is the one the analyzer recognises (the same shape as `customer_profile_screen.dart`'s `_openAddCredit()`). The push is typed `push<Customer>`; the result is kept, the list is reloaded, and the SnackBar is shown only when a customer came back. The SnackBar reads `Customer "<full name>" registered successfully (ID: <id>).` with a four-second duration, matching the credit-origination confirmation.

**The filter clear is conditional on a customer having been registered.** `_searchController.clear()` (and the pending debounce's cancellation, which protects that clear) runs only when `created != null`. Backing out of the form reloads the list but leaves the operator's search filter exactly as it was: wiping a search that nothing was added to would destroy work for no reason, and no confirmation is shown either. When a customer *was* registered, the filter is cleared because `_loadCustomers()` re-runs the active query whenever it is at least two characters long, and a filtered list would not contain the customer the confirmation announces. The pending debounce is cancelled with the clear, so a filter that was typed but not yet applied cannot re-apply the stale query over the reloaded list.

Two details beyond the literal task text, both stated deliberately:

- **The injected database is now forwarded to the registration screen** (`database: widget.database`), which the task list did not mention. The registration screen previously opened its own `AppDatabase()` connection instead of the one the Customers screen reads from, so the Customers screen and the form could be pointed at different databases. This is the established convention in this codebase (18 other `database: widget.database` forwards, including the credit-origination push this change copies), and without it the reloaded list cannot contain the customer the form just created.

**Tests** -- the registration screen's harness now pushes the screen over a dummy host route (a `_RegistrationHost` that captures the route result), because a successful registration closes the route and a root route has nothing to pop back to. The photo test's success assertion is re-pointed at that route result.

**How each I/O & Edge-Case Matrix row is covered** (all in `test/widget/features/customers/`, the search screen's harness being the only one where "the form stays open" and "no SnackBar" are both observable in one journey):

| Matrix row | Covering test | What it pins |
|-------------|---------------|--------------|
| Valid form, no duplicate | `customer_search_screen_test.dart` -- "registering a customer returns to the Customers screen and is confirmed with a SnackBar" | The form closes, the list reloaded with the new customer, the SnackBar reads `Customer "<full name>" registered successfully (ID: <id>).`, and its duration is four seconds |
| Shared phone confirmed | `customer_search_screen_test.dart` -- "a confirmed shared phone registration closes the form and shows the same confirmation" | The warning banner asks for confirmation and registers nothing until confirmed; the confirmed submission closes the form and shows the same SnackBar. `customer_registration_screen_test.dart` covers the same flow at the route level |
| Duplicate NIC | `customer_registration_screen_test.dart` -- "a failed registration keeps the screen open and returns no result" | The "Existing Customer Profile" dialog is shown, the screen stays open, and the route closes with no result |
| Validation error | `customer_search_screen_test.dart` -- "a validation error keeps the form open and shows no confirmation SnackBar" | An invalid phone format passes the form's own non-empty validator and reaches the service, which raises `CustomerValidationException` before any DAO call; the form stays open with the inline `Invalid phone number: ...` message, no SnackBar appears, and no customer row was written |
| Unexpected error | `customer_search_screen_test.dart` -- "an unexpected failure keeps the form open and shows no confirmation SnackBar" | A dedicated database instance is closed underneath the form, so its DAO call raises an error that is none of the three documented exceptions and the generic `catch (e)` branch runs: the form stays open with `Registration failed: ...`, no SnackBar appears, and the customer table is empty |
| Backed out | `customer_search_screen_test.dart` -- "backing out of the registration form shows no confirmation SnackBar and keeps the active search filter" | The route closes with no result, no SnackBar appears, nothing was written, and the active search filter survives the round trip |
| Active search filter | `customer_search_screen_test.dart` -- "an active search filter is cleared so the new customer is visible" | After a successful registration the filter is cleared and the full shop list is shown, so the new customer is visible |

Two fixture details the tests had to accommodate:

- **`SyncQueueEntry` validates `shopId` as a canonical UUID**, and the shared-phone path writes a sync-queue event. The shared-phone cases therefore use a UUID shop id; the fixtures that only exercise the plain path are unaffected.
- **Drift's `close()` is idempotent** -- verified empirically -- so the unexpected-error case can close its dedicated instance to provoke the failure and close it again in the tear-down without harm. The shared `db` fixture is closed by the shared tear-down and is never the instance under test. The dedicated instance is file-backed so the assertion "no customer row was created" can read the database the failed registration would have written to; it is built directly on `NativeDatabase` rather than through `AppDatabaseConnection.openSandboxedConnection`, because that factory resolves lazily through real file I/O, which never completes inside a widget test's fake-async zone.

## Spec Change Log

No amendment to the frozen intent was needed. The non-frozen sections gained implementation notes covering the debounce cancellation and the database forward, both of which were additions to the task text rather than changes to it.

## Review Triage Log

The three review lenses ran inline in the implementing session: launching them as subagents failed with the provider's free-usage limit. Each lens still executed its own instruction (the blind-hunter floor was `min(floor(sqrt(35.9) + 1), 10) = 6`), and every finding below was verified against the code before a verdict was rendered.

| # | Layer | Location | Verdict | Evidence | Route |
|---|-------|----------|---------|----------|-------|
| 1 | Blind Hunter | `customer_registration_screen_test.dart` / `customer_registration_photo_test.dart` `_RegistrationHost` | low | Both files define a near-identical private host harness, and they already diverge — only the photo host forwards `storageService` — so a constructor change must be made twice. | reject |
| 2 | Blind Hunter | `customer_search_screen.dart:199-207` | low | A second confirmation within four seconds queues behind the first because `showSnackBar` is called without dismissing the current one. The form must be opened and filled between registrations, so the window is not reachable in everyday use. | reject |
| 3 | Blind Hunter | `customer_search_screen.dart:121-134`, `:191` | low | With a one-character query the results are intentionally cleared, but the unconditional reload after the form closes falls through to the full shop list, so the list contradicts the field. Pre-existing: the pre-change FAB handler reloaded identically. | defer |
| 4 | Blind Hunter | `customer_search_screen_test.dart` SnackBar assertion | low | The four-second duration stated in the frozen Decisions is asserted nowhere; changing it to one second kept the suite green. | patch |
| 5 | Blind Hunter | `customer_search_screen.dart:191-207` | low | The confirmation is awaited behind the list reload, so leaving the tab during the query loses it. The reload is a local query of milliseconds, and leaving the Customers screen removes the surface the confirmation belongs to. | reject |
| 6 | Blind Hunter | `customer_registration_screen.dart:118-124` | false | The success branch does not reset `_isLoading`, but the screen is only ever pushed (`customer_search_screen.dart:167`), so `pop` always succeeds and the state is disposed; the test host reproduces the pushed shape. | reject |
| 7 | Blind Hunter | `customer_search_screen_test.dart:24-58` | false | The hand-rolled shop seed cannot be replaced by `seedShopAndCustomer`, which always inserts a borrower; the journey, validation and filter-clear cases must start with no customer rows, and only the two duplicate-phone cases need one. | reject |
| 8 | Blind Hunter | `customer_search_screen_test.dart` (unexpected-error case) | low | Opening a second `AppDatabase` triggers drift's `dontWarnAboutMultipleDatabases` debug warning. The two instances use different executors and files, so the corruption the warning guards against cannot occur; suppressing it would hide real double-instance bugs. | reject |
| 9 | Edge Case Hunter | `customer_registration_screen.dart:124` | false | `Navigator.pop(customer)` on a route that cannot pop. The screen has exactly one production call site, which pushes it (`customer_search_screen.dart:167`), and every test now pushes it over a host; it is never the root route. | reject |
| 10 | Edge Case Hunter | `customer_search_screen.dart:178-207` | false | A pending or concurrent search could overwrite the list after the filter clear. Reaching the success path requires completing the form, which outlasts the 300 ms debounce plus query; on back-out the reload repeats the already-active query, so a stale write produces the same results. | reject |
| 11 | Edge Case Hunter | `customer_search_screen.dart:185-187` | false | The debounce is cancelled only on success; a pending timer on back-out re-runs the same query and produces the same list. | reject |
| 12 | Edge Case Hunter | deletion check: `_isSuccess` and the green status styling | false | The removed success state's behaviour is re-established as the route result plus the SnackBar, and no reference to `_isSuccess` remains in this screen (`collateral_registration_screen.dart` has its own, unrelated flag). | reject |
| 13 | Verification Gap | `customer_search_screen_test.dart:170-182` | low | Same gap as #4: the test asserted only the message text, so the duration could regress unobserved. | patch |
| 14 | Verification Gap | `customer_search_screen.dart:191` (back-out reload) | false | Removing the back-out reload keeps the back-out test green, but the reload has no user-visible effect there, so there is no regression for a test to catch. | reject |
| 15 | Verification Gap | `main.dart` nesting | false | The harness pumps `MaterialApp(home: CustomerSearchScreen)` without the real bottom-nav Scaffold, but `ScaffoldMessenger.of(context)` resolves the same ancestor messenger in both shapes, and the assertion is `findsOneWidget`, which would fail if the SnackBar were duplicated across nested Scaffolds. | reject |

Rows 4 and 13 share one root cause and were fixed together: the journey test now asserts `tester.widget<SnackBar>(find.byType(SnackBar)).duration == const Duration(seconds: 4)`. No `intent_gap` or `bad_spec` entry survived, so no loopback was needed; row 3 is the only entry routed out of this story.

## Design Notes

The route result is the natural carrier for the outcome — it lets the Customers screen distinguish "registered a customer" from "backed out" without a shared flag or a global bus. This is the mechanism the credit-origination change already established on the customer profile, and the two should read alike.

The search-filter reset is not cosmetic. `_loadCustomers()` re-runs the active query when it is at least two characters long, so without the reset the reload would repopulate a filtered list — and the SnackBar would announce a customer that is not on screen.

The success banner is removed rather than kept alongside the SnackBar: the registration screen is popped on success, so its banner would never be read. The error rendering stays, because every failure keeps the screen mounted.

## Verification

**Commands:**
- `flutter analyze` -- expected: No issues found! **Result: No issues found! (6.0s)**
- `flutter test test/widget/features/customers/customer_search_screen_test.dart test/widget/features/customers/customer_registration_screen_test.dart test/widget/features/customers/customer_registration_photo_test.dart` -- expected: All tests passed! **Result: `+17: All tests passed!`** (the three files this change touches)
- `flutter test` (full suite, after the review patch) -- expected: All tests passed! **Result: `+1035 ~7: All tests passed!`**

**Mutation checks:**
- Removing the `_searchController.clear()` call fails "an active search filter is cleared so the new customer is visible" (`pumpUntil: condition never became true`), so that test pins the filter reset rather than passing incidentally.
- Making the filter clear unconditional again (ignoring `created != null`) fails "backing out of the registration form shows no confirmation SnackBar and keeps the active search filter" (`Expected: 'Su' / Actual: ''`), so the back-out case pins the conditional clear.

**Empirical checks behind the test fixtures:**
- Drift's `close()` is idempotent: closing an already-closed database raises nothing, so the unexpected-error case can close its dedicated instance to provoke the failure and close it again in the tear-down safely.
- Closing an *opened* database makes later DAO calls raise `Bad state: Can't re-open a database after closing it.` -- none of the service's three documented exceptions -- which is what drives the screen's generic `catch (e)` branch. Closing a database that was never opened is a no-op and would not provoke the failure, so the dedicated instance is opened (and seeded) before it is closed.

