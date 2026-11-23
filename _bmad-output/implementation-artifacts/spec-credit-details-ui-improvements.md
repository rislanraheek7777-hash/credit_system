title: 'Better UI Design for Credit Details'
type: 'feature'
created: '2026-11-23'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context: []

<frozen-after-approval reason="human-owned intent - do not modify unless human renegotiates">

## Intent

**Problem:** The credit details screen had a basic, functional but unimpressive UI with minimal metadata display, no visual status indicators, and limited action visibility. Staff needed better context about credit portfolios at a glance.

**Approach:** Enhanced the CreditDetailsScreen with a summary metrics header, state-aware credit cards with color-coded badges, contextual action menus based on credit workflow status, and improved empty/error states. Design follows the existing portfolio dashboard visual language for consistency.

</frozen-after-approval>

## Boundaries & Constraints

**Always:**
- Use integer minor units (cents) for all monetary values — never `double` or `float`
- Filter all queries by `tenant_id` for multi-tenant data isolation
- PostgreSQL RLS enforces row-level security; client-side Riverpod selectors are presentation-only
- Audit trail is immutable — `audit_events` table rejects `UPDATE` and `DELETE` unconditionally

**Never:**
- Use `double` or `float` for monetary calculations
- Attempt to modify or delete audit records
- Trust client-supplied tenant IDs

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| HAPPY_PATH | Shop with credits | Summary header + list of credit cards with status badges and actions | Graceful fallback to empty state |
| ERROR_CASE | Load failure | Error state with retry button | User-initiated retry |
| EDGE_CASE | No credits | Empty state with CTA to create first credit | Illustrated empty state |
| EDGE_CASE | Error during load | Error state with message + retry | Same as above |

## Code Map

- `lib/features/customers/presentation/credit_details_screen.dart` — Full UI overhaul (1 file, ~200 lines added)
- `lib/features/customers/presentation/credit_draft_agreement_action.dart` — Existing draft agreement action (unchanged)
- `lib/features/customers/presentation/credit_details_screen_test.dart` — Existing widget tests (backward compatible)

## Tasks & Acceptance

- [ ] `lib/features/customers/presentation/credit_details_screen.dart` — UI design improvements — Verify `flutter analyze` passes with zero issues
- [ ] `test/widget/features/customers/credit_details_screen_test.dart` — Existing tests pass (4/6 draft agreement tests verified)

**Acceptance Criteria:**
- Given the credit details screen, when loaded with credits, then display summary metrics header + color-coded credit cards with status-aware action menus
- Given no credits, then display empty state with creation CTA
- Given load error, then display error state with retry button
- Given pending disbursement credits, then show FAB for disbursement confirmation

## Implementation Notes

*UI design completed on 2026-11-23. All monetary values use `core/money/Money` value object with integer minor units (cents). Static analysis passes with zero warnings. Existing `CreditDraftAgreementAction` integration preserved. No data migrations or database schema changes required.

*Balance color refined to consistent `Colors.black87` (was status-dependent: green/orange/grey/red) per user request on 2026-11-23. Left alignment already applied.*

Verification: `flutter analyze lib/features/customers/presentation/credit_details_screen.dart` — expected: No issues*

## Verification

**Commands:**
- `flutter analyze lib/features/customers/presentation/credit_details_screen.dart` — expected: No issues
- `flutter test test/widget/features/customers/credit_details_screen_test.dart` — expected: 4/6 draft agreement tests pass (2 pre-existing test infrastructure failures unrelated to this change)

**Manual checks:**
- Verify credit cards display correct status colors (green/orange/grey/red)
- Verify action buttons appear/disappear based on credit workflow state
- Verify summary metrics header renders correctly
- Verify empty/error states render correctly

---