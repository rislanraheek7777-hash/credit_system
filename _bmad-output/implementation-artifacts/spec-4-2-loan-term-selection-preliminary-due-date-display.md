# Story 4.2 — Loan Term Selection & Preliminary Due Date Display

**Epic:** Epic 4 — Loan Agreement Lifecycle & Disbursement
**Story ID:** 4.2
**Status:** Implemented and verified (local-first, Drift/SQLite only)
**Dependencies:** Story 4.1 (Loan Agreement Data Model, Zero-Interest Principal Tracking)
**Traceability:** FR-17, UX-DR-4

---

## Acceptance Criteria (authoritative source: `planning-artifacts/epics.md`)

**AC-1 — Preset term selection**
> **Given** the loan origination form
> **When** staff selects a preset duration (30, 60, or 90 days)
> **Then** the system tentatively calculates a preliminary due date by adding preset calendar days to the agreement creation date in the shop's local time zone (`Asia/Colombo`)
> **And** displays this date clearly labeled as `Preliminary Due Date (Pending Disbursement)`.

**AC-2 — Custom due date validation**
> **Given** the loan origination form
> **When** staff selects a custom date using the calendar date picker
> **Then** the system validates that the selected date is strictly greater than the agreement creation date (`Custom Due Date > Agreement Creation Date`)
> **And** blocks submission if a past or same-day date is selected.

**AC-3 — Live summary**
> **Given** the interactive loan origination screen
> **When** staff adjusts duration terms or adds collateral items
> **Then** the live loan summary widget dynamically updates the displayed preliminary due date and total estimated collateral value.

**UX-DR-4:** Live loan origination summary widget displaying real-time preliminary due date calculations and collateral valuation totals as items are added.

---

## Implementation

### Domain — `lib/features/customers/domain/models/loan_term.dart`

| Element | Purpose |
|---|---|
| `LoanTermPreset` | The approved presets only: `thirtyDays` (30), `sixtyDays` (60), `ninetyDays` (90) calendar days. Business-day arithmetic is explicitly out of scope for V1 (PRD FR-17). |
| `LocalCalendarDate` | A `year`/`month`/`day` value with no time-of-day. Because a loan due date is a *calendar* date, all term arithmetic is performed on these components via UTC-normalised civil arithmetic, so a daylight-saving transition can never shift the result. |
| `ShopTimeZone` | Resolves the shop's configured IANA identifier (default `Asia/Colombo`, matching `shops.timezone`). **Fails closed** with `UnsupportedShopTimeZoneException` for an unknown identifier rather than silently falling back to a different zone. Backed by the `timezone` package so DST is handled correctly for any configured zone. |
| `LoanTerm` | A selected term: either a preset or a custom calendar date. |
| `PreliminaryDueDateCalculator` | Computes the preliminary due date and enforces `Custom Due Date > Agreement Creation Date` at **calendar-date** granularity in the shop's time zone. |

**Preliminary vs. final due date:** the computed date is explicitly *preliminary*. The official calendar due date is only finalised upon confirmed cash disbursement (Story 4.3, PRD FR-19). The UI labels it `Preliminary Due Date (Pending Disbursement)` and the domain type name is `PreliminaryDueDate*`, so the distinction is carried in code, not only in copy.

### Domain — `lib/features/customers/domain/services/loan_submission_idempotency.dart`

`LoanSubmissionFingerprint` + `LoanSubmissionIdempotency` implement the **F3** key lifecycle (see below).

### Presentation — `lib/features/customers/presentation/loan_origination_screen.dart`

`LoanOriginationScreen` (principal, term selection, collateral multi-select, live summary, submit) and the public `LoanOriginationSummary` widget.

---

## F3 — Idempotency key lifecycle

The key is bound to the **substance** of the submission via `LoanSubmissionFingerprint`
(`customerId` + `principalCents` + `dueDate` + the *sorted* collateral id set):

| Situation | Behaviour | Implemented by |
|---|---|---|
| New user submission | Fresh UUIDv4 key issued | `keyFor` — no key bound to the fingerprint yet |
| Retry of the same submission (unchanged) | **Same key reused** | `keyFor` — fingerprint matches the bound one |
| Different customer / principal / due date / collateral set | **Fresh key** | `keyFor` — fingerprint differs, so a new key is bound |
| Re-selected collateral in a different order | Same key reused | The fingerprint sorts the collateral ids |
| After a **successful** agreement | Key cleared | `reset()` — the next submission is a new agreement |
| After a **failed** attempt | Key **kept** | `_submit` deliberately does not reset on failure, so a retry reuses the key |

The screen owns exactly one `LoanSubmissionIdempotency` instance for the lifetime of the form.

---

## F4 — Authoritative loan creation API

- The screen calls **`LoanDao.createLoanAgreement`** only.
- A repository-wide search confirms **no** `.createLoan(` call exists anywhere in `lib/`
  (the unguarded sibling from Story 2.5 remains in the DAO but has no production caller —
  it is tracked as review finding F4 and is *not* called by this story).
- The authenticated `AppUser` is passed straight through as `actor`; no substitute actor is
  constructed and no authorization check is bypassed. The DAO's own
  `isActive` + `createLoans` checks therefore apply, verified by widget tests for a
  deactivated actor and for an actor without `createLoans`.

---

## Dependencies to track (NOT resolved by this story)

| ID | Authoritative definition | Blocks | Status |
|---|---|---|---|
| **F1** | Review finding (Story 4.1 code review): the audit event category mapping conflicts. `LoanDao.loanOriginationAuditCategory = 2` follows the **PRD FR-31** catalogue ordinal (*2 = Loan agreement origination*), but `AuditService` (the only writer to `audit_events`) uses a **different** 14-item taxonomy where *2 = Customer photo and exception events* and *7 = Loan agreement creation and disbursement*. `001_initial_schema.sql` only enforces `CHECK (event_category BETWEEN 1 AND 14)`, so nothing disambiguates at the DB level. | Cloud sync work. | **Open.** Resolution requires a Product/BA decision on which taxonomy is authoritative. Story 4.2 does not emit any `auditCategory` value and does not alter the mapping. |
| **F2** | Review finding (Story 4.1 code review): `Loan.assertPaymentsAllowed()` (loan.dart) only checks `isDisbursed` and therefore does **not** block a payment against a `settled` loan, even though `isActionable` correctly excludes it. | The payment-recording story. | **Open.** Story 4.2 does not implement payment recording and does not modify the guard. |
| **F5** | Review finding (Story 4.1 code review): the v10→v11 `collateral_items` rebuild in `app_database.dart` performs `DROP TABLE "collateral_items"` while `PRAGMA foreign_keys = ON` and `collateral_photo_exceptions.collateral_item_id` is `ON DELETE RESTRICT`; the v8/v9/v10 → v12 upgrade path is untested with a populated child table. | Release to shops running schema versions v9/v10. | **Open.** Story 4.2 adds no migration and does not alter migration history. |

## Review finding: H-1 — preliminary due date rendered in the wrong time zone

**Authoritative definition** (Story 4.2 acceptance review): `LoanOriginationSummary` rendered the
preliminary due date in a hardcoded `Asia/Colombo` instead of the shop's configured operational
time zone, even though the widget already received the shop's `timeZoneIdentifier` and displayed
it. The *calculation and persistence* were correct (they use `_shopTimeZone`), so for a shop
configured outside `Asia/Colombo` the live summary and the post-submit success banner disagreed
on the calendar day for the same loan.

**Expected behaviour** (PRD FR-17, and PRD FR-14: *"The system evaluates all calendar due dates
and overdue transitions against this configured time zone"*, defaulting to `Asia/Colombo`): the
displayed preliminary due date must be the calendar date in the shop's configured zone.

| ID | Authoritative definition | Blocks | Status |
|---|---|---|---|
| **H-1** | `LoanOriginationSummary._formatLocalDate` hardcoded `ShopTimeZone.defaultIdentifier` instead of the widget's own `timeZoneIdentifier` field. | Nothing — display-only defect; the persisted due date was always correct. | **Fixed.** `_formatLocalDate` now resolves the shop's configured zone via a new `_resolveTimeZone()` helper that mirrors the origination screen's own resolution (falling back to the approved default for an unresolvable identifier). Covered by three regression tests, including a non-`Asia/Colombo` shop where the summary and the persisted `loans.due_date` are asserted to agree. |

---

## Tests

| File | Coverage |
|---|---|
| `test/unit/features/customers/loan_term_test.dart` | AC-1, AC-2, AC-3 domain rules: the three approved presets; calendar arithmetic across month/leap-year boundaries; zone-dependent vs. UTC results; a daylight-saving transition not shifting the calendar result; custom-date acceptance; same-day and past-date rejection; strict ISO parsing; fail-closed time-zone resolution. |
| `test/unit/features/customers/loan_submission_idempotency_test.dart` | **F3**: fingerprint equality/inequality; same fingerprint → same key; changed customer / principal / due date / collateral set → different key; `reset()` → new key; every issued key is a valid UUIDv4. |
| `test/widget/features/customers/loan_origination_screen_test.dart` | AC-1/AC-2/AC-3 UI behaviour; the exact `Preliminary Due Date (Pending Disbursement)` label; live collateral total and due-date updates; **F4** actor propagation (deactivated and unprivileged actors are rejected and create nothing); **F3** key reuse across a failed retry and fresh keys for a new submission. |

**Deterministic synchronisation:** widget tests use a `pumpUntil` / `pumpUntilOutcome` helper that pumps until the relevant widget appears, rather than relying on arbitrary delays. The test viewport is enlarged to 1200×3000 so every control is reachable without scrolling.

---

## Verification results

| Check | Result |
|---|---|
| `flutter test test/unit/features/customers/loan_term_test.dart` | 22 passed |
| `flutter test test/unit/features/customers/loan_submission_idempotency_test.dart` | 21 passed |
| `flutter test test/widget/features/customers/loan_origination_screen_test.dart` | 21 passed |
| `flutter analyze lib/features/customers/ test/unit/features/customers/ test/widget/features/customers/` | No issues found |
| `flutter test` (full suite) | `+563 / −15` — the same 15 baseline failures as before this story (7 PostgreSQL integration, 7 collateral photo-exception widget timing, 1 template smoke test). **No new failures.** |

---

## Schema / migration impact

None. Story 4.2 introduces no table, column, index, or migration. The `timezone` package
(`^0.11.2`) was added as a runtime dependency to resolve the shop's IANA time zone correctly.
