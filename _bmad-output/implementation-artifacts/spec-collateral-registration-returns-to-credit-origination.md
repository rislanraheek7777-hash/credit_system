---
title: 'Collateral registration returns to Credit Origination after registering an item'
type: 'feature'
created: '2026-11-18'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: '074918d5ca31581f205f3205ac23e5222d537773'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** After a counter staff member registers an item receipt via the origination flow ("Add Item Receipt" → Collateral Registration screen), the registration screen keeps them on it, showing an inline green banner. They must tap back themselves to reach Credit Origination, and the origination screen reloads only after the route closes — but nothing tells them which receipt they just added.

**Approach:** On successful registration the registration route closes and the staff member lands back on Credit Origination, whose receipt list reloads from the database — the established "return to the previous screen with the outcome carried by the route result" pattern (customer registration → Customers screen; credit creation → customer profile).

**Decisions (human-confirmed):**
- Q1 (a): the newly registered receipt appears **unchecked** in the origination list; pledging it is a manual tap on the item. The route carries the created `CollateralItem` as its result **only so the confirmation can name it** — it is not used to auto-select.
- Q2 (a): a SnackBar on Credit Origination confirms the registration, naming the item, with the wording `Item Receipt "<itemReferenceId>" registered.` — 4-second duration, matching the other confirmations. Back-out produces no SnackBar.
- Q3 (a): the now-unreachable multi-item UI is removed: the "Registered Items" list and its custody-transition `IconButton`s, `_transitionLastItem`, `_registeredItems`, and the inline success banner / form-clear tail of `_registerItem`. The registration screen becomes single-item: fill → Register Item → back to origination. `CollateralDao.transitionCustody` and every custody flow outside this screen are untouched.

## Boundaries & Constraints

**Always:**
- Registration still writes through the existing `CollateralDao.createCollateralItem`. This change is navigation and messaging only — no new write path, no schema, audit, or sync-queue change.
- The route closes only on successful registration. A failed creation (DAO rejection, or any validation error) leaves the registration screen mounted with its inline error, exactly as today; it never pops and never claims success.
- Backing out of the registration screen without registering produces no confirmation.
- Credit Origination reloads its receipt list from the database after the route closes, through the existing `_load()` path.
- The newly registered receipt is never auto-selected; pledging is a manual tap.
- The `CollateralRegistrationScreen` remains pushed by (and only by) the credit origination flow; no new entry points are introduced.

**Never:**
- Do not change `CollateralDao`, `CreditDao`, the `collateral_items`/`credits` schema, the audit-trail schema, or the idempotency implementation.
- Do not weaken any remaining permission check.
- Do not report a failure as a success: no pop, no SnackBar on failure or back-out.
- Do not auto-select the new receipt or otherwise touch `_selectedCollateralIds`.
- Do not touch the in-flight settle-credit work or any other screen.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Successful registration | Valid form (reference, category, value), actor holds permission to create | Route closes carrying the created `CollateralItem`; origination reloads; SnackBar `Item Receipt "<itemReferenceId>" registered.` shows for 4s; the new receipt appears unchecked | N/A |
| Validation failure | Blank estimated value, no category, invalid weight | Form shows the inline validation error; screen stays mounted; no pop | Error shown inline as today |
| DAO failure | `createCollateralItem` throws | Screen stays mounted with `Registration failed: ...`; no pop; no SnackBar | Inline message as today |
| Back-out | Staff dismisses the registration route without registering | Route closes with no result; origination reloads; no SnackBar | N/A |
| Registration screen is the root route (tests) | Widget test pumps the screen as `home:` | The root route pops like any route: the screen is dismissed and the item persists; screen tests push over a host route instead | N/A |
| Adding a second receipt | Staff taps "Add Item Receipt" again after the first registration | The registration screen opens empty; the second item can be registered and returns the same way | N/A |

</frozen-after-approval>

## Code Map

Paths are relative to the project root. `R/` = `lib/features/collateral/presentation/`, `P/` = `lib/features/customers/presentation/`, `T/` = `test/widget/features/`.

**Presentation**
- `R/collateral_registration_screen.dart` — `_registerItem()` (L129–204): persists via `dao.createCollateralItem(item)` (L181). On success, remove the `setState`/banner/clear-form tail (L183–197) and `Navigator.of(context).pop(item)` instead. Delete: `_registeredItems` (L75), the "Registered Items" UI block (L389–461), `_transitionLastItem` (L471–503), and `CollateralCustodyStatus`-dependent IconButtons with them. `register_collateral_button` (L359–362) stays. `dispose()` (L207–214) is unchanged.
- `P/credit_origination_screen.dart` — `_addItemReceipt()` (L344–359): change to `push<CollateralItem>(...)`, capture the result, `await _load()` (L203–236; refetches via `CollateralDao.getCollateralItemsByCustomerId`, L212–218), then show the SnackBar only when the result is non-null. `_selectedCollateralIds` (`Set<String>`, L180) is not modified. `_collateralItems` (L179) feeds the receipt list. The screen has no `ScaffoldMessenger` today; add it — errors stay inline (`origination_error_display`, L466–473).
- `lib/features/collateral/domain/models/collateral_item.dart` — the `CollateralItem` instance built in `_registerItem` (L163–179) is the route-result payload; `itemReferenceId` (L165) feeds the SnackBar text.

**Tests**
- `T/features/collateral/collateral_registration_screen_test.dart` — pumped as `home:` (L65–73, L159–167). The success test `'CollateralRegistrationScreen registers item without a photo'` taps `register_collateral_button` (L190) and asserts `find.textContaining('registered successfully')` with the screen mounted (L193) — rework to push over a host route (a `_HostScreen` mirroring `_OriginationHost`), pop semantics verified via a captured result, and assert the close.
- `T/features/customers/credit_origination_screen_test.dart` — `_OriginationHost` dummy home route (L57–120) pushes origination and captures pop results; `pumpScreen()` (L204–232). Extend the add-item-receipt coverage (button render L584–593; navigation L595–611) with: complete a registration inside the nested route → expect the SnackBar text and the reloaded list containing the new item, and the item left unchecked.

Only lib caller of `CollateralRegistrationScreen`: `P/credit_origination_screen.dart` L349. No router references.

## Tasks & Acceptance

**Execution:**
- [x] `R/collateral_registration_screen.dart` — on success, `pop(item)`; delete `_registeredItems`, the "Registered Items" block, `_transitionLastItem`, and the inline success banner/clear-form tail; keep failure paths byte-identical -- single-item screen, confirmation moves to the landing screen.
- [x] `P/credit_origination_screen.dart` — `_addItemReceipt()`: `push<CollateralItem>`, reload via `_load()`, then SnackBar `Item Receipt "<itemReferenceId>" registered.` (4s) only when a result came back; never touch `_selectedCollateralIds` -- existing pattern, one new messaging seam.
- [x] `T/features/collateral/collateral_registration_screen_test.dart` — rework the success test around a host route and the captured result; remove assertions that depend on the screen staying mounted.
- [x] `T/features/customers/credit_origination_screen_test.dart` — extend the add-item-receipt journey: register → auto-return → SnackBar naming the item → new item in the list, unchecked → `_selectedCollateralIds` unchanged.

**Acceptance Criteria:**
- Given a staff member on Credit Origination who taps "Add Item Receipt", when the registration form is valid and "Register Item" is tapped, then the registration route closes and Credit Origination is visible.
- Given a successful registration, when Credit Origination is shown again, then a SnackBar reading `Item Receipt "<itemReferenceId>" registered.` appears and the new receipt is present in the item-receipts list, unchecked.
- Given the registration DAO rejects or validation fails, when the error is shown, then the registration screen remains open and no SnackBar is shown.
- Given the staff member backs out of the registration screen without registering, when Credit Origination is shown again, then no SnackBar is shown.
- Given the staff member registers a first receipt and returns, when they tap "Add Item Receipt" again, then the registration screen opens empty and the flow can be repeated.

## Implementation Notes

- The Dart/Flutter toolchain cannot run through its `.bat` wrappers on this machine (`Access is denied` / `Unable to determine engine version` — the engine check spawns nested `cmd → pwsh`). Verification runs by driving the flutter_tools snapshot directly with the SDK binary: `& "C:\Flutter\bin\cache\dart-sdk\bin\dart.exe" --packages="C:\Flutter\packages\flutter_tools\.dart_tool\package_config.json" "C:\Flutter\bin\cache\flutter_tools.snapshot" analyze|test ...`. Result: `No issues found!`; both widget test files together pass 35/35 (7 pre-existing each preserved, 7 new coverage tests added by this run: validation-failure, DAO-failure, root-route, second-receipt journey, and the back-out no-SnackBar extension).
- The orchestrator (not the implementation subagent) removed the `app_permission.dart` import from both test files mid-run while calling it "unused". `app_permission.dart` defines `AppRole`, which the tests use; the tree broke (`Undefined name 'AppRole'`) and the implementation subagent restored the imports and re-verified green. Both files still require the import.
- Diff artifacts for the mandated step-03 review: full diff since baseline in `%TEMP%\opencode-diff-074918d5-to-worktree.patch`; the spec-owned slice in `%TEMP%\opencode-diff-spec-owned-only.patch` (the baseline was a dirty tree — the user's settle-credit body of work is interleaved with this change in the two lib files).
- ScaffoldMessenger queues SnackBars: the second registration's confirmation is not in the tree until the first SnackBar elapses. The second-receipt test pumps 5 fake seconds before asserting on it.
- The frozen matrix's root-route row was factually wrong (`Navigator.pop` removes the root route; the screen is dismissed, the item persists). The row was amended — see the amended frozen block — and the root-route test asserts the amended behavior. Triggering evidence: the test found 0 `CollateralRegistrationScreen` widgets after a successful save when pumped as `home:`.
- `_HostScreen` in the registration test is only reachable/assert-able after the route pops; assertions inside it during an open route were removed (not the coverage — the matrix rows are covered by the mounted-screen + persisted-items assertions and by the journey tests).

## Spec Change Log

(empty — the frozen root-route row amendment was human-directed at the step-03 audit halt; recorded in Implementation Notes, not a Spec Change Log loopback)

## Review Triage Log

Layer sources: BH = Blind Hunter, ECH = Edge Case Hunter, VG = Verification Gap (VG gap findings pre-verified; VG-Other verified at the cited site).

| # | Layer | Location | Verdict | Evidence | Route |
|---|-------|----------|---------|----------|-------|
| 1 | BH | collateral_registration_screen.dart — Story 3.2 photo workflow removed | low | The photo-capture/gate code was already absent when this run read the tree (step-01 read showed the reworked screen with optional description/condition/weight and no photo code); the baseline carried it. Pre-existing in-flight rework, not caused by this spec — its frozen Boundaries forbid touching it | defer |
| 2 | VG | registration screen — removed photo-capture hunks | low | Same defect as #1, filed independently; frozen spec authorizes deleting only the multi-item UI | defer |
| 3 | ECH | registration screen (removed photo-capture hunks) | low | Same defect as #1, filed independently | defer |
| 4 | BH | collateral_registration_screen.dart — root-route row "amended without human renegotiation" | false | The step-03 audit HALTed on the mismatch; the human explicitly answered "Amend row to reality (Recommended)" and the amendment is recorded in Implementation Notes and this log. The clause his complaint invokes was honored | — |
| 5 | VG | customer_profile_screen.dart:652/666/680 | medium | Per-card Settle discards the tapped credit and re-derives the actionable set; `_settleCredit(credit)` is the spec's prescribed path. Pre-verified by the layer with failing-test-grade evidence. Pre-existing in-flight settle work, out of this story | defer |
| 6 | BH | customer_profile_screen.dart onSettle ×3 | medium | Same defect as #5, filed independently | defer |
| 7 | ECH | customer_profile_screen.dart:652 | medium | Same defect as #5, filed independently | defer |
| 8 | ECH | customer_profile_screen.dart:666 | medium | Same defect as #5, filed independently | defer |
| 9 | ECH | customer_profile_screen.dart:680 | medium | Same defect as #5, filed independently | defer |
| 10 | BH | credit_settle_action.dart — `isAvailableFor` drops eligibility gate | medium | Settle button ships on ineligible cards; VG ran the ineligible-credits test and it fails as filed. Settle-story artifact, not this story | defer |
| 11 | BH | settle spec tests-pass claims inaccurate | low | Companion of #10; the settle spec's Verification section claims all-pass for tests the layers observed failing | defer |
| 12 | VG | credit_settle_action.dart:49-51 eligibility dropped (failing test run) | medium | Same defect as #10; layer executed the failing test in this tree | defer |
| 13 | VG | customer_profile_screen_test.dart — no ≥2-eligible settle binding test | medium | Every test seeds one eligible credit, so tap-target == count path; the missing multi-card coverage belongs to the settle story | defer |
| 14 | BH | main.dart Active Credits list deleted | low | Pre-existing in-flight deletion; portfolio dashboard still shows the metric; dashboard test fails on the missing list | defer |
| 15 | ECH | lib/main.dart (removed Active Credits list) | low | Same defect as #14, filed independently | defer |
| 16 | VG | customer_profile_screen.dart:381-404 `_openAddCredit` SnackBar dropped | medium | Two profile tests fail as filed; confirms pre-existing deletion of the origination confirmation in the same in-flight profile rework | defer |
| 17 | BH | customer_profile_screen.dart `_openAddCredit` SnackBar gone | medium | Same defect as #16, filed independently | defer |
| 18 | ECH | customer_profile_screen.dart (_openAddCredit SnackBar removal) | medium | Same defect as #16, filed independently | defer |
| 19 | BH | customer_profile_screen.dart — `_openEditCustomer` AppDatabase leak + dropped refresh | low | Uncommitted-new code opens an unclosed `AppDatabase()` and skips `_loadProfile()`; in-flight rework, verified at the cited site — not this story | defer |
| 20 | BH | settle-button spec self-contradictory and shipped in-review | low | The contradiction lives in that spec's frozen block, not this one; merge hygiene belongs to that change | defer |
| 21 | VG | payment_screen.dart:241-245 settle-mode pops before receipt PDF | low | Verified trace in this tree; settle-story behavior; receipt row still committed; reprint still possible | defer |
| 22 | BH | payment_screen settle-mode no receipt PDF | low | Same defect as #21, filed independently | defer |
| 23 | ECH | payment_screen.dart:241-244 | low | Same defect as #21, filed independently | defer |
| 24 | BH | module-help.csv renamed bmad→bmd | low | Repo-wide references still use bmad-*; stray find/replace in pre-existing in-flight config; not this story | defer |
| 25 | BH | AGENTS.md stale (bmad-build next, typo, core/domain/) | low | Pre-existing in-flight addition; AGENTS.md is bmad-project-context managed | defer |
| 26 | BH | sprint-status midnight timestamp + snapshot-only verification | low | Conventions gaps; this spec's snapshot-driven run is recorded as such in Implementation Notes; sprint file is bmm-config | defer |
| 27 | BH | CreditType.fromValue throws on unknown + silent `'cash'` defaults | low | Verified: no fallback on unrecognized stored strings across the three DAOs; user's in-flight migration bundle | defer |
| 28 | VG | v23 `credit_type` backfill untested — v25 fixture skips `from < 23` | low | Layer ran migration tests: 95 pass, none pin the backfill; in-flight migration bundle | defer |
| 29 | BH | Migration coverage gap v23/v24 + stale identifiers | low | Same family as #28; BH adds stale test names; `drift_migration_v23_test.dart` genuinely does not exist | defer |
| 30 | ECH | app_database.dart:811 upgrade-v23 skip on missing credits table | low | Pre-existing upgrade path silently skips; in-flight migration bundle | defer |
| 31 | ECH | app_database.dart:870 upgrade-v24 skip on missing collateral_items | low | Same family as #30 | defer |
| 32 | ECH | app_database.dart:956 upgrade-v24 CHECK widening skip | low | Same family as #30 | defer |
| 33 | BH | files.txt + customer_photo_capture_test.dart empty | low | Both files are byte-empty junk artifacts; pre-existing in-flight additions | defer |
| 34 | VG | files.txt + customer_photo_capture_test.dart empty | low | Same defect as #33, filed independently | defer |
| 35 | BH | v23/v24 migration fixtures missing (drift_database_test) | low | Same family as #28–#32 | defer |
| 36 | BH | UX mockups fixture math internally inconsistent | low | Pre-existing untracked mockups; "Due in 16 days · 02 Dec" from 18 Nov arithmetic mismatch | defer |
| 37 | VG | NULL-collateral document/DAO fallbacks untested | low | Verified: no `Unspecified`/`Not recorded` references in tests; fixtures fully populated. Pre-existing in-flight NULL-collateral feature | defer |
| 38 | VG | `_showMultiCreditSelectionForSettle` double-brace interpolation | low | Verified at `'Balance: ${...format()}}'`; prints literal `}`; dead-end SnackBar also verified; settle-story | defer |
| 39 | VG | settle spec Verification claims false (4 failing tests) | low | Verified by execution — same evidence as #11; settle-story | defer |
| 40 | VG | mandatory photo gate removal vs spec-8-1 / FR-15 / Stories 3.2/3.3 | low | De-facto removal by pre-existing in-flight rework (see #1); belongs to a correct-course review of that rework, not this spec | defer |
| 41 | VG | stale/contradictory profile comments (lines 145, 176) | low | Verified; comments describe deleted/differently-wired settle code; in-flight | defer |
| 42 | ECH | customer_profile_screen.dart:507-511 firstWhere absent element | low | Verified unguarded `firstWhere` on re-derived id in settle continuation; settle story | defer |
| 43 | ECH | registration_screen.dart:182-187 catch setState without mounted guard | low | Verified bit-identical in baseline; pre-existing; guard trivial but not caused by this story | defer |
| 44 | ECH | registration_screen.dart:178-181 dismiss during insert — committed item, lost result | low | Pre-existing interleaving; baseline had the same await without dismiss guard; the origination reload-then-return semantics are unchanged | defer |
| 45 | BH | credit_origination_screen.dart — success SnackBar after `_load()` failure | low | Spec-mandated conditionality (SnackBar iff route result non-null); inline error co-displays; frozen decision — renegotiating wording is the human's call | defer |
| 46 | ECH | credit_origination_screen.dart:361-371 SnackBar vs `_loadFailed` | low | Same defect as #45, filed independently | defer |

**No intent_gap / bad_spec / patch entries.** 44 findings defer (pre-existing or sibling in-flight work, not caused by this story); 2 false (#4, human-directed amendment during the audit halt). All findings against the four spec-owned files are accounted for: none requires changes for this story to ship.

## I/O Matrix Coverage

| Row | Covering test | Ran |
|-----|---------------|-----|
| Successful registration | `credit_origination_screen_test.dart` — "registering an item from the receipt flow returns to the origination screen…" | passed |
| Validation failure | `collateral_registration_screen_test.dart` — "validation failures keep the screen open and do not pop" | passed |
| DAO failure | `collateral_registration_screen_test.dart` — "a DAO failure shows an inline error and does not pop" | passed |
| Back-out | `credit_origination_screen_test.dart` — "tapping Add Item Receipt navigates to the collateral registration screen" (no-SnackBar assertion) | passed |
| Root route | `collateral_registration_screen_test.dart` — "on a root route, the pop dismisses the screen and the item persists" | passed |
| Adding a second receipt | `credit_origination_screen_test.dart` — "staff can register a second receipt after the first…" | passed |

## Design Notes

The route result is the outcome carrier — same as credit creation closing the origination route with the created `Credit`. The confirmation belongs on the landing screen, not on one that has just unmounted. The registration screen does not special-case a root route: `Navigator.pop` removes it like any other route, which is how the amended root-route matrix row behaves and why tests push the screen over a host route.

## Verification

**Commands:**
- `flutter analyze` -- expected: No issues found!
- `flutter test test/widget/features/collateral/collateral_registration_screen_test.dart test/widget/features/customers/credit_origination_screen_test.dart` -- expected: All tests passed!
