---
title: 'Optional Item Receipts at Origination & Terminology Rename'
type: 'feature'
created: '2026-11-09'
status: 'done'
route: 'dispatch'
baseline_commit: '16acfdfff04630264f4f0632171dd66fd7afb71e'
review_loop_iteration: 0
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Credit origination currently forces staff to attach "Pledged Collateral" (`credit_origination_screen.dart:365-368`, `credit_dao.dart:259-261`), so an unsecured credit cannot be recorded, and the term no longer matches how the shop describes held items. The same term appears in the disbursement screen and generated PDFs.

**Approach:** Make item attachment optional (zero or more item receipts per credit) and rename user-facing wording to **Item Receipt** in the origination flow and generated documents only. Keep the `collateral_items` schema, `CollateralItem` model, feature folders, DAO names, permission identifiers, audit category labels, and standalone collateral registration/custody screens unchanged. A settled credit with zero item receipts derives `Closed / Completed`.

## Boundaries & Constraints

**Always:** Preserve existing item validation, binding, reference generation, and audit behavior when item IDs are supplied. Preserve the idempotency fingerprint contract. Preserve per-item photo behavior. Always write `Item Receipt` with the qualifier — bare `Receipt` remains reserved for payment receipts. Run the full analyze and unit/widget test suites before finishing.

**Never:** Do not add a Drift/PostgreSQL migration or change the schema. Do not rename code identifiers, tables, permissions, or FR-31 event-category labels. Do not rename the Collateral Registration, custody-return, or photo-exception screens. Do not introduce a new mandatory-item or mandatory-photo rule.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Zero-item origination | No item checkboxes selected; valid principal + term | Agreement is created; no item binding, no custody record, no collateral audit event | N/A |
| Zero-item DAO call | `collateralItemIds: const []` | Agreement persisted; initial balance equals principal | No `ArgumentError` |
| Items supplied | One or more unbound item IDs for the customer | Items bound to the credit; references/audit unchanged | Existing validation errors preserved |
| Settled zero-item credit | `CreditStatus.settled`, no attached items | `deriveOverallWorkflowStatus` → `Closed / Completed` | N/A |
| Settled item credit | Items all `returned` or one `exceptionHeld` | Existing `Settled / Closed (All Collateral Returned)` / `Closed (Collateral Exception)` unchanged | N/A |
| Empty-list fingerprint | Same customer/principal/due date, `[]` items | Deterministic canonical value and equality | N/A |

</frozen-after-approval>

## Code Map

- `lib/features/customers/presentation/credit_origination_screen.dart` — heading `:681`; empty state `:685-686`; summary string `:87`; submit guard `:365-368`; summary class `:26-120`; `_viewDraftAgreement` already tolerates empty selection `:444-459`.
- `lib/features/customers/data/daos/credit_dao.dart` — `createCreditAgreement` `:220-230`; empty-list `ArgumentError` `:259-261`; validation `:287-302`; binding already guarded `:368-378`; sync payload has no item IDs `:317-327`.
- `lib/features/customers/domain/services/credit_submission_idempotency.dart` — sorts IDs `:31-39`, joins with comma `:42-52`; empty list already deterministic.
- `lib/features/collateral/data/daos/collateral_dao.dart` — `deriveOverallWorkflowStatus` `:945-980`; zero-item credits currently fall through to `Settled (Pending Collateral Return)` `:979`.
- `lib/features/customers/presentation/credit_disbursement_screen.dart` — heading `:530`, hidden when zero items `:528`.
- `lib/features/customers/domain/models/credit_document_content.dart` — `Collateral Summary:` `:134`; `Itemized Collateral Details:` `:208`; `No collateral items recorded.` `:236`.
- `lib/features/customers/data/services/document_generation_service_impl.dart` — already defaults to `const []` and tolerates empty `:50, :110`.
- Tests: `test/widget/features/customers/credit_origination_screen_test.dart:469-484`; `test/unit/features/customers/credit_dao_test.dart:532-537`; `test/unit/features/customers/document_generation_service_test.dart:463-478`; `test/unit/features/customers/credit_submission_idempotency_test.dart`; `test/widget/features/customers/official_due_date_display_test.dart:303-329`.
- `test/unit/features/collateral/collateral_administrative_closure_test.dart:545-603` — status-derivation tests to extend.

## Tasks & Acceptance

**Execution:**
- [x] `lib/features/customers/presentation/credit_origination_screen.dart` — delete the `_selectedCollateralIds.isEmpty` guard; rename heading to `Item Receipts`, empty state to `No item receipts recorded for this customer. Item receipts are optional.`, summary to `Total Estimated Item Receipt Value: ...` — enables zero-item origination and matches terminology.
- [x] `lib/features/customers/data/daos/credit_dao.dart` — delete the `collateralItemIds.isEmpty` throw only — allow zero items while keeping all non-empty validation/binding intact.
- [x] `lib/features/collateral/data/daos/collateral_dao.dart` — add `if (items.isEmpty) return 'Closed / Completed';` after the settled/closure checks and before the non-empty all-returned branch — prevents a false pending-handover status for unsecured settled credits.
- [x] `lib/features/customers/presentation/credit_disbursement_screen.dart` — rename heading `:530` to `Item Receipts` — consistent counter wording.
- [x] `lib/features/customers/domain/models/credit_document_content.dart` — replace the three PDF strings with `Item Receipt Summary:`, `Item Receipt Details:`, `No item receipts recorded.` — consistent generated documents.
- [x] `test/widget/features/customers/credit_origination_screen_test.dart` — invert the no-item block test into a zero-item success test and assert the new heading/empty state — locks the new behavior.
- [x] `test/unit/features/customers/credit_dao_test.dart` — invert `rejects a credit with no pledged collateral item` into `creates a credit with zero item receipts`; keep the bind test — locks the DAO contract.
- [x] `test/unit/features/customers/credit_submission_idempotency_test.dart` — add deterministic empty-list fingerprint equality — pins the edge case.
- [x] `test/unit/features/collateral/collateral_administrative_closure_test.dart` — add settled zero-item derivation test; keep existing all-returned/pending assertions — locks the status branch.
- [x] `test/unit/features/customers/document_generation_service_test.dart` — update the empty-state assertion to `No item receipts recorded.` — keeps documents consistent.
- [x] `test/widget/features/customers/official_due_date_display_test.dart` — update the stale "required" fixture comment only if it is now misleading; no behavior change — avoid contradictory guidance.

**Acceptance Criteria:**
- Given a valid principal and term with zero item receipts selected, when the user submits, then the agreement is created and no item is bound.
- Given `createCreditAgreement` with an empty item list, when called, then it persists and returns the agreement without throwing.
- Given a settled credit with zero item receipts, when overall status is derived, then it returns `Closed / Completed`.
- Given the origination screen, disbursement screen, and generated PDFs, when rendered, then they use `Item Receipt(s)` and no origination-flow string reads `Pledged Collateral`.
- Given the same submission fingerprint with an empty item list, when compared, then equality and hash are deterministic.
- Given the repository, when `flutter analyze lib/ test/` and `flutter test test/unit/ test/widget/` run, then both pass.

## Implementation Notes

- Origination load failure: `_load` records `_loadFailed`; `_submit` refuses to create an agreement when item receipts could not be loaded, so a load error is never mistaken for a customer who has zero item receipts.
- Review patches added coverage for the PDF headers (`Item Receipt Summary:` / `Item Receipt Details:`), the disbursement `Item Receipts` heading, and the origination summary label.

## Verification

**Commands:**
- `flutter analyze lib/ test/` -- expected: no errors or warnings introduced by this change.
- `flutter test test/unit/ test/widget/` -- expected: all tests pass, including the new zero-item and status-derivation cases.

**Results (2026-11-09):**
- `flutter analyze lib/` — No issues found.
- Targeted suites (the seven test files touched by this story) — 139 tests passed, including every I/O Matrix row.
- `flutter analyze lib/ test/` exits 1 solely because of a pre-existing `avoid_print` info in the untracked file `test/widget/features/customers/_tmp_db_test.dart`; this story did not add or touch that file.
- `flutter test test/unit/ test/widget/` — 943 passed / 28 failed. All 28 failures are pre-existing and live in files untouched by this story: drift migration v11/v13/v14/v15/v17/v18/v19/v20 tests, customer photo/registration/model tests, the payment schema test, and the untracked `_tmp_db_test.dart` (10-minute timeout). No test file touched by this story fails.
- Because the working tree was already dirty at `baseline_commit`, the review diff was scoped to Story 8.1's edits so reviewers do not grade unrelated uncommitted work.

## Review Triage Log

Layers run: Blind Hunter, Edge Case Hunter, Verification Gap. No layers skipped.

| ID | Layer | Finding | Verdict | Route | Evidence / disposition |
|----|-------|---------|---------|-------|-----------------------|
| BH-1 | blind | All-returned credits keep `Settled / Closed (All Collateral Returned)` while planning docs say `Closed / Completed`. | low | defer | The all-returned label is pre-existing and the frozen matrix requires it unchanged; no `lib/` consumer keys on either string. Reconcile the architecture formula later. |
| BH-2 | blind | Derived status has no production caller. | medium | defer | `deriveOverallWorkflowStatus` was already unused before this story; the spec's AC is derivation-only. Deferred with VG-4. |
| BH-3 | blind | Custody-return screen shows `No collateral items found.` for a valid zero-item credit. | low | defer | Intent explicitly excludes renaming the custody-return screen; pre-existing empty state. |
| BH-4 | blind | Disbursement section is hidden for zero-item credits; renamed heading untested. | low | patch | Heading assertion added under VG-2. An explicit zero-item empty state would add UI the spec did not request. |
| BH-5 | blind | PDF headers untested; no zero-item draft test. | medium | patch | Added `Item Receipt Summary:` and `Item Receipt Details:` assertions under VG-1. A draft zero-item case is beyond the I/O matrix. |
| BH-6 | blind | Stale `collateral` wording in test names and idempotency docs. | low | reject | Internal identifiers and test descriptions are explicitly out of rename scope; user-facing wording is correct. |
| BH-7 | blind | New comment says `collateral handover`. | low | patch | Comment reworded to `item-receipt handover`. |
| BH-8 | blind | Fingerprint tests do not assert an empty selection differs from a non-empty one. | low | reject | Matrix row only requires deterministic equality for `[]`; no demonstrated bug, and the case is beyond the frozen matrix. |
| BH-9 | blind | `nothing was bound` assertion is vacuous. | false | reject | The fixture inserts two collateral items before the test (`credit_dao_test.dart:367-388`), so `items.every(...)` is not vacuous. |
| BH-10 | blind | DAO contract change undocumented. | low | patch | Added a dartdoc note that `collateralItemIds` may be empty. |
| BH-11 | blind | Optionality shown only in the zero-items empty state; a `0.00` summary can look incomplete. | low | reject | The spec mandates that exact empty-state string; markers/`None selected` add UI surface, and `0.00` is the expected total. |
| BH-12 | blind | Document wording ambiguous; `Summary` vs `Details` inconsistent. | false | reject | All three strings are explicitly mandated by the approved spec; changing them would require editing the spec. |
| BH-13 | blind | No zero-item E2E downstream test; profile screen still says `Collateral`. | low | defer | Profile is outside the chosen origination-flow + PDF rename scope; downstream tests are beyond the matrix and the touched suites are green. |
| EC-1 | edge | Item-load failure leaves zero items and now allows an unsecured credit. | high | patch | Confirmed: `_load` catches the error and leaves `_collateralItems` empty while the form still submits. Added `_loadFailed` and a `_submit` guard. |
| EC-2 | edge | Second tap after success creates a duplicate agreement. | false | reject | `_idempotency.reset()` and the existing `a new submission after a success receives a fresh key` test make this intentional multi-credit behavior. |
| EC-3 | edge | Acceptance claims the suites pass while they are red. | medium | defer | The 28 failures are pre-existing and in untouched files; documented in Verification and recorded for follow-up. |
| VG-1 | verification | PDF header strings are unasserted. | medium | patch | Added draft and voucher header assertions; a wording regression now fails. |
| VG-2 | verification | Disbursement heading is unasserted. | medium | patch | Added `find.text('Item Receipts')` to the pending-disbursement test. |
| VG-3 | verification | Origination summary label is unasserted. | medium | patch | Added `startsWith('Total Estimated Item Receipt Value:')` to the live-summary test. |
| VG-4 | verification | `deriveOverallWorkflowStatus` has no production caller (observation). | medium | defer | Same root cause as BH-2; the method was already unused and the spec AC is derivation-only. |

No intent_gap or bad_spec findings; no loopback. Patch entries applied and verified. `review_loop_iteration` remains `0`.

