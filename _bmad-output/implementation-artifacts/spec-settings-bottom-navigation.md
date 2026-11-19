---
title: 'Settings in bottom navigation (move from Customers AppBar)'
type: 'feature'
created: '2026-11-19'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Settings, Shop Profile, and Staff Management are reachable only as icon actions in the Customers screen's AppBar (top nav). That clutters the customer search surface, hides shop configuration behind a secondary screen's toolbar, and is inconsistent with the app's bottom `NavigationBar` shell. The UX spine (`EXPERIENCE.md`) routes Shop Profile and Staff Management through Settings.

**Approach:** Add a single "Settings" destination to `MainApp`'s bottom `NavigationBar` (appended at index 3, after Credit Details). Remove the three AppBar action IconButtons (Settings, Shop Profile, owner-only Staff Management) and their now-unused imports/role check from `customer_search_screen.dart`. Convert `SettingsScreen` from a pushed full page (own `Scaffold` + `AppBar`) into the bottom-nav tab body, keeping its option list: dark-mode switch, Shop Profile, owner-only Staff Management, About, and Logout (rendered only when `onLogout` is provided, as today). Shop Profile and Staff Management remain pushed routes from the Settings tab. Settings tab is visible to all roles — the Settings hub already hides owner-only tiles, matching current AppBar visibility.

**Decisions (made at planning):**
- Single Settings destination, not three separate ones (user-approved; Material 3–5 destinations; matches UX spine).
- Appended at index 3 — `_DashboardPage` quick actions hardcode tab indices 1 (Customers) and 2 (Credit Details); inserting mid-list would break them.
- `SettingsScreen` converted in place (no `embedded`/`asTab` flag) — after this change its only call site is the tab.
- `_confirmLogout` must not blindly `Navigator.pop()` when Settings is a tab (nothing to pop; could pop the shell route) — only pop when `canPop()`.
- `MainApp` builds the tab the same way other tabs are built (`_CustomersPage` pattern: own widget constructed in `build`, `onLogout` wired to `_handleLogout`).
- Keep Settings' gradient-header look consistent with the dashboard/customers surfaces rather than a bare AppBar-less list.
- Extend `test/widget_test.dart` to assert the Settings destination exists and tapping it renders the Settings surface.

</frozen-after-approval>

## Implementation Notes

- `SettingsScreen` converted in place from pushed page (own `Scaffold`+`AppBar`) to a bottom-nav tab body: gradient header row (icon + 'Settings' title) matching the customers/dashboard gradient surfaces; dark-mode card, option list, and `_open` push behavior unchanged.
- `_confirmLogout` now pops only when `canPop()` — Settings no longer guarantees a pushed route.
- `MainApp` (`lib/main.dart`): added `Icons.settings_outlined`/`Icons.settings` destination (index 3), constructs `SettingsScreen` directly as the 4th page (same eager-construction pattern as other tabs), wired `onLogout: _handleLogout` and `database`.
- `customer_search_screen.dart`: removed the three AppBar IconActions (Settings/Shop Profile/Staff Management), their imports, the `AppRole` check, and the now-dead `onLogout` ctor param. `_CustomersPage` in `main.dart` lost its forwarding `onLogout` too.
- `test/widget_test.dart`: extended smoke test (tap Settings destination by key, expect Shop Profile/Staff Management/Logout tiles; Customers AppBar has no IconButtons) and added tests: non-owner hides Staff Management; Logout confirm flow fires `onLogout`; Settings without `onLogout` shows no Logout tile.
- No test referenced the removed tooltips or `SettingsScreen`; no other `lib/` call site pushed `SettingsScreen` (verified by map + grep).
- Correction (post-review): an earlier revision of this note claimed a test asserted "no Logout without onLogout" — that was wrong; `MainApp` always wires `onLogout: _handleLogout`, so the MainApp-hosted tab always shows Logout. The `onLogout == null` gate remains for hosts/tests that omit it, and is now covered by a direct `SettingsScreen` widget test.
- Review-driven fixes folded in: tab-index constants in `main.dart` (`_dashboardTabIndex`/`_customersTabIndex`/`_creditDetailsTabIndex`) with `ValueKey`ed destinations; Settings header rounded to match the dashboard surface and wrapped in `ExcludeSemantics` (decorative duplication of the nav label); `_logoutInFlight` guard against double-tap dialog stacking (converted to StatefulWidget); `StaffManagementScreen` now receives the shared `database` like `ShopProfileScreen`; app version centralized in `_appVersion` (subtitle and `showAboutDialog`); class doc and `_confirmLogout` comment updated to describe the tab-body contract.
- Pre-existing failures unrelated to this change (verified via `git stash` on clean tree): `dashboard_live_metrics_test.dart`, `multi_credit_selection_test.dart`, `customer_photo_capture_test.dart` (loading), `customer_profile_screen_test.dart` (credit origination return ×2, edit form). Full suite after change: 1084 passed, only those 6 fail.

## Review Triage Log

Blind Hunter pass (~10.3 kB changed, finding floor 4; 16 reported). Verdicts:

- Audit Log Viewer unreachable from Settings — defer → deferred-work.md (pre-existing; EXPERIENCE routes it via Settings; new permission-gated feature, outside approved scope).
- Tab state destroyed on switch; IndexedStack/keep-alive wanted — defer → deferred-work.md (pre-existing mount policy for all tabs; changes eager-load behavior, needs explicit decision).
- Tab indices unanchored magic numbers — **high, patched** (`_dashboardTabIndex`/`_customersTabIndex`/`_creditDetailsTabIndex` in `main.dart`; dashboard quick actions + initial index use them; pages/destinations order documented).
- Test coverage gaps — **patched** for the change's own regression surface: AppBar-has-no-IconButtons guard, non-owner hides Staff Management, Logout confirm flow fires `onLogout`, gate case (no `onLogout` ⇒ no tile). Small-viewport/text-scale verification — defer → deferred-work.md.
- Spec note claimed "no Logout without onLogout"; MainApp always wires it — **patched** (Implementation Notes corrected; gate kept deliberately as embeddable affordance and now test-covered).
- Spec left `in-progress` — false / expected mid-workflow state; `status: done` set in this finalization.
- Settings header flat vs dashboard's rounded gradient — **patched** (bottomLeft/right 32 radius). "Duplicates nav label" sub-point — rejected: header is the page title surface, consistent with Dashboard/Customers pattern.
- Header icon/heading re-announce nav label to screen readers — **patched** (`ExcludeSemantics` on the decorative header Row).
- Doc comments implied a supported pushed-route mode (no Scaffold/AppBar/back) — **patched** (class doc now states the tab-body contract; `_confirmLogout` comment fixed).
- Logout double-tap stacks confirmation dialogs — **medium, patched** (`_logoutInFlight` guard; converted to StatefulWidget).
- Dark-mode toggle session-only (no persistence) — defer → deferred-work.md (pre-existing; persistence is a feature needing a storage decision).
- `find.text('Settings')` ambiguous post-tap; destinations lacked keys — **patched** (`nav-*` ValueKeys on all four destinations; test taps by key).
- `ShopProfileScreen` passed `database`, `StaffManagementScreen` not — **patched** (both receive the shared `database`).
- Version `1.0.0` duplicated in subtitle and About dialog — **patched** (shared `_appVersion` const). Staleness-vs-pubspec sub-point — rejected for scope; wiring `package_info_plus` is out of this change.
- AGENTS.md project map omits `settings/` module — defer → deferred-work.md (AGENTS.md is maintained by `bmad-project-context`).
- Sequential per-build page construction / hoist out of `build()` — defer → deferred-work.md (same root cause as the mount-policy entry).
