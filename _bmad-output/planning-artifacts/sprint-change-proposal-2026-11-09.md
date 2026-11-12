---
title: "Sprint Change Proposal — Item Receipts Terminology & Optional Intake"
status: approved
created: 2026-11-09
approved: 2026-11-09
project: credit_system
requested_by: Raheek
mode: batch
scope: minor
---

# Sprint Change Proposal — Item Receipts Terminology & Optional Intake

## 1. Issue Summary

**Change trigger:** Stakeholder request (post-Epic-7 delivery) to change the credit-origination concept **"Pledged Collateral"** to **"Item Receipt"** and to make item attachment **optional** — a credit agreement must be creatable with zero item receipts.

**Problem statement:** The delivered product, the PRD, the epic breakdown, the UX spine, and the architecture currently treat item attachment as mandatory:

- PRD FR-13 (`prd.md:331`): *"A credit agreement must have at least one valid pledged item attached before it can be submitted."*
- PRD traceability (`prd.md:686`): verification gate is "Minimum 1 item validation test".
- Epic Story 3.1 (`epics.md:780`) and Story 4.1 (`epics.md:936`) repeat the "1 or more" rule.
- Code enforces it twice: `credit_origination_screen.dart:365-368` and `credit_dao.dart:259-260`.
- The term "Pledged Collateral" appears in the origination screen, the disbursement screen, and generated PDF content.

**Issue type:** New requirement emerged from stakeholders + terminology change. This is a scope/requirements amendment, not a defect.

**Evidence:**

| Location | Current behavior |
|---|---|
| `lib/features/customers/presentation/credit_origination_screen.dart:365-368` | Submission blocked with `Select at least one collateral item.` |
| `lib/features/customers/presentation/credit_origination_screen.dart:680` | Section heading `Pledged Collateral` |
| `lib/features/customers/presentation/credit_origination_screen.dart:686` | Empty state `No collateral items registered for this customer.` |
| `lib/features/customers/presentation/credit_origination_screen.dart:87` | Summary `Total Estimated Collateral Value` |
| `lib/features/customers/data/daos/credit_dao.dart:259-260` | Throws `ArgumentError(... 'must not be empty')` |
| `lib/features/customers/presentation/credit_disbursement_screen.dart:530` | Heading `Pledged Collateral` |
| `lib/features/customers/domain/models/credit_document_content.dart:134,208,236` | PDF strings `Collateral Summary:`, `Itemized Collateral Details:`, `No collateral items recorded.` |
| `lib/features/collateral/data/daos/collateral_dao.dart:973-979` | A settled credit with **zero** items returns `Settled (Pending Collateral Return)` — wrong for an unsecured credit |

**Approved decisions (this session):**

1. Run Correct Course in **Batch** mode.
2. Rename scope: **origination flow + generated PDFs** only. Leave the standalone Collateral Registration and custody screens, permission labels, code identifiers, and the `collateral_items` schema untouched.
3. A settled credit with **zero** item receipts derives **`Closed / Completed`** (no custody obligation).
4. No schema migration: `collateral_items.credit_id` is already nullable.

**Risk note:** The application already uses **"Receipt"** for immutable payment receipts (FR-24). "Item Receipt" must always be written with the "Item" qualifier; bare "Receipt" must never be repurposed. Receipt reprint/watermark behavior is unaffected.

---

## 2. Impact Analysis

### 2.1 Epic Impact

- **Epic 3 (Collateral Intake & Custody):** Story 3.1 and 3.2 acceptance criteria hard-code "1 or more". They must allow zero attachments while keeping the mandatory photograph rule **per attached item**.
- **Epic 4 (Credit Origination):** Story 4.1 requires "at least one collateral item" at creation; Story 4.2 assumes items are added to the live summary. Both need amendment.
- **Epic 7 (Reports/Dashboards):** FR-29's "Total Collateral Items currently In Custody" remains valid (it counts attached items); wording may optionally become "Item Receipts". No behavioral change.
- **Epic ordering / priority:** No resequencing. No epic becomes obsolete. A single change story is added for traceability (see Section 3).

### 2.2 Story Impact

| Story | Impact |
|---|---|
| 3.1 Multi-Item Collateral Schema | AC "1 or more" → "zero or more"; add zero-item AC. Schema unchanged. |
| 3.2 Mandatory Photographs | Rule applies to attached items only; explicitly state it does not force at least one item. |
| 3.3 Photo Exception | No change (still per attached item). |
| 3.4 / 3.5 Custody | No change; zero-item credits simply have no custody transitions. |
| 4.1 Credit Agreement Data Model | Remove "at least one collateral item" from creation AC. |
| 4.2 Term & Due Date Display | Live summary still shows item total; zero items is valid. |
| 4.3 / 4.4 Disbursement & Documents | Disbursement screen heading and voucher/draft PDF strings are renamed; zero-item documents must render the empty-state line. |

### 2.3 Artifact Conflicts

| Artifact | Conflict |
|---|---|
| PRD glossary (`:144-145`) | "Pledged Item / Collateral" and "one or more pledged items". |
| PRD FR-13 (`:326-334`) | Mandatory minimum 1 item. |
| PRD FR-14 / FR-15 (`:336-357`) | Uses "pledged item" and "every pledged item". |
| PRD FR-20 (`:433`) | "Itemized Collateral Details". |
| PRD traceability (`:686`) | "Minimum 1 item validation test". |
| PRD UJ-1 (`:62-63`) | "Pledged Item 1 / Pledged Item 2". |
| Epics requirements inventory (`:39-41`) | "1 or more distinct pledged items". |
| Epics Story 3.1 / 3.2 / 4.1 / 4.2 | Mandatory-item wording. |
| UX `EXPERIENCE.md` (`:24`, `:82`) | "multi-item collateral", "adds pledged items". |
| Architecture AD-3 (`ARCHITECTURE-SPINE.md:151-159`) | Workflow formula has no zero-item branch. |
| — | No conflict with AD-1 (FK still supports nullable `credit_id`), AD-2, AD-5, AD-6, AD-7, AD-8. |

### 2.4 Technical Impact

- **Data:** none. `collateral_items.credit_id` nullable; `credits` has no item-count constraint; no Drift/PostgreSQL migration.
- **Authorization:** unchanged; `createCredits` still gates origination, `confirmCollateralReturn` still gates handovers.
- **Audit:** Category 3 events are emitted only when items are attached. The canonical FR-31 event catalogue labels are **not** renamed (avoid breaking the single authoritative taxonomy). Category 2 origination always fires.
- **Idempotency:** `CreditSubmissionFingerprint` already serialises a sorted list; an empty list is deterministic, so no change is needed — but a test must pin it.
- **Documents:** PDF generators already accept an empty list and emit an empty-state line; only the wording changes.
- **Status derivation:** `deriveOverallWorkflowStatus` needs an explicit empty-items branch; otherwise unsecured settled credits display a false pending-handover state.
- **Tests:** four existing assertions encode the old rule and must be inverted.

---

## 3. Recommended Approach

**Selected:** **Direct Adjustment** (Option 1). Amend requirements/stories, then implement the wording and the optional-intake rule in place.

**Why not rollback:** No completed work needs reverting. The schema and custody machinery remain correct and are simply not exercised when no items are attached.

**Why not MVP review:** The change *reduces* a constraint and does not alter the product's scope, users, or business model.

**Effort:** Low–Medium (≈0.5–1 developer day including tests and doc edits).
**Risk:** Low. One genuine business semantic decision (zero-item settled status) has been resolved. No migration, no data loss path.

**Backlog adjustment:** Add one traceability epic and story rather than reopening completed epics:

```yaml
epic-8: backlog                      # Item Receipt Terminology & Optional Intake (change request)
8-1-optional-item-receipts-origination-and-terminology: ready-for-dev
```

---

## 4. Detailed Change Proposals

### 4.1 PRD (`_bmad-output/planning-artifacts/prds/prd-credit_system-2026-10-13/prd.md`)

**Glossary — `:144`**

OLD:
> **Pledged Item / Collateral:** A physical valuable (e.g., gold jewelry, consumer electronics) held by the shop as security for a credit. Each item maintains its own descriptive, photographic, weight, and custody records.

NEW:
> **Item Receipt (Pledged Item / Collateral):** A physical valuable (e.g., gold jewelry, consumer electronics) recorded as held by the shop as security for a credit. Each item receipt maintains its own descriptive, photographic, weight, and custody records. Attachment to a credit agreement is optional.

**Glossary — Credit Agreement `:145`**

OLD:
> The system's recorded terms linking a customer, one or more pledged items, a principal credit amount, an agreed due date, and repayment history.

NEW:
> The system's recorded terms linking a customer, zero or more item receipts, a principal credit amount, an agreed due date, and repayment history.

**FR-13 — `:326-334`**

OLD:
> #### FR-13: Multi-Item Collateral Registration per Credit
> Counter Staff can register one or more distinct pledged items under a single credit agreement. Realizes UJ-1.
> ...
> - Each pledged item receives a unique, system-generated Item Reference Number linked to the parent credit agreement.
> - A credit agreement must have at least one valid pledged item attached before it can be submitted.

NEW:
> #### FR-13: Item Receipt Registration per Credit (Optional)
> Counter Staff can register zero or more item receipts under a single credit agreement. Realizes UJ-1.
> ...
> - Each attached item receipt receives a unique, system-generated Item Reference Number linked to the parent credit agreement.
> - Attaching item receipts is optional; a credit agreement can be submitted with zero item receipts.
> - When no item receipt is attached, no custody obligation exists and no collateral audit event is generated.

**FR-14 — `:336-344`:** replace "For each pledged item" with "For each item receipt" (no rule change).
**FR-15 — `:346-357`:** replace "every pledged item" / "any pledged item" with "every item receipt" / "any item receipt"; add: *"This rule applies only to item receipts that are attached and does not require at least one item receipt."*
**FR-20 — `:433`:** "Itemized Collateral Details (with weights and descriptions)" → "Item Receipt Details (with weights and descriptions)".
**UJ-1 — `:62-63`:** "Pledged Item 1/2" → "Item Receipt 1/2" (prose only).
**Traceability — `:686`:** verification gate "Minimum 1 item validation test" → "Zero-item submission and item binding test".
**Leave unchanged:** FR-31 event-category labels (canonical audit contract), FR-16 custody semantics, FR-29 metrics.

### 4.2 Epics (`_bmad-output/planning-artifacts/epics.md`)

**Requirements Inventory FR-13 — `:39`**

OLD: `Support for 1 or more distinct pledged items per credit agreement; unique item reference IDs generated`
NEW: `Support for zero or more item receipts per credit agreement (optional attachment); unique item reference IDs generated for attached items`

**FR-14 `:40`, FR-15 `:41`:** "pledged item" → "item receipt".

**Story 3.1 — `:773`, `:780`**

OLD: *"register one or more distinct pledged collateral items"* / *"supports attaching 1 or more distinct pledged items"*
NEW: *"register zero or more item receipts"* / *"supports attaching zero or more item receipts"*

Add AC:
> **Given** a credit origination workflow
> **When** Counter Staff submits without attaching any item receipt
> **Then** the agreement is created successfully and no custody record is created.

**Story 3.2 — after `:821`:** add clarification: *"The mandatory-photo rule applies to each attached item receipt; it does not require at least one item receipt."*

**Story 4.1 — `:930`, `:936`**

OLD: *"linking a customer, pledged collateral items, and principal amount"* / *"with an attached customer, at least one collateral item, and a Principal Amount"*
NEW: *"linking a customer, zero or more item receipts, and principal amount"* / *"with an attached customer, zero or more item receipts, and a Principal Amount"*

**Story 4.2 — `:975`:** "adds collateral items" → "adds item receipts".

**New Epic 8 / Story 8.1** (traceability only):

> **Epic 8: Item Receipt Terminology & Optional Intake (Change Request)**
> Counter staff can originate a credit with zero item receipts and see consistent "Item Receipt" wording across origination, disbursement, and generated documents.
>
> **Story 8.1:** As a Counter Staff member, I want item attachment to be optional and labelled "Item Receipt", so that unsecured credits can be recorded and terminology matches shop practice.
> - AC1: origination submits with zero selected item receipts.
> - AC2: DAO persists a zero-item agreement without throwing.
> - AC3: origination, disbursement, and PDFs use "Item Receipt(s)".
> - AC4: settled zero-item credit derives `Closed / Completed`.
> - AC5: mandatory photo rule still blocks an attached item without a photo.

### 4.3 UX (`_bmad-output/planning-artifacts/ux-designs/ux-credit_system-2026-11-05/EXPERIENCE.md`)

**IA — `:24`**

OLD: `Term + principal + multi-item collateral + review + submit`
NEW: `Term + principal + optional item receipts + review + submit`

**Key Flow 1 — `:82`**

OLD: `→ adds pledged items (category, description, condition, estimated value, weight if gold, ≥1 photo) → reviews summary`
NEW: `→ optionally adds item receipts (category, description, condition, estimated value, weight if gold, ≥1 photo each) → reviews summary`

**Climax — `:83`**

OLD: `all required fields + photos validated`
NEW: `all required fields validated; each attached item receipt has a photo`

Add to State Patterns: *"Item receipts are optional at origination. A settled credit with zero item receipts has no handover step and resolves to Closed / Completed."*

`DESIGN.md` — no change required.

### 4.4 Architecture (`_bmad-output/planning-artifacts/architecture/architecture-credit_system-2026-10-14/ARCHITECTURE-SPINE.md`)

**AD-3 workflow formula — `:156`**

OLD:
> `Closed / Completed`, if financial is settled and all items returned

NEW:
> `Closed / Completed`, if financial is settled and (no item receipts attached **or** all items returned)

No other AD changes. Data model, RLS, permissions, image pipeline, and audit immutability are unaffected.

### 4.5 Implementation (code) — for the Developer agent

| # | File | Change |
|---|---|---|
| 1 | `lib/features/customers/presentation/credit_origination_screen.dart:365-368` | Delete the `_selectedCollateralIds.isEmpty` submission block. |
| 2 | same `:680` | Heading `Pledged Collateral` → `Item Receipts`. |
| 3 | same `:686` | Empty state → `No item receipts recorded for this customer. Item receipts are optional.` |
| 4 | same `:87` | Summary → `Total Estimated Item Receipt Value: ...` |
| 5 | `lib/features/customers/data/daos/credit_dao.dart:259-261` | Delete the `collateralItemIds.isEmpty` throw; keep existing `isNotEmpty` guard when binding items. |
| 6 | `lib/features/collateral/data/daos/collateral_dao.dart:973-979` | If `items.isEmpty` return `Closed / Completed`; otherwise keep current all-returned/pending logic. |
| 7 | `lib/features/customers/presentation/credit_disbursement_screen.dart:530` | Heading → `Item Receipts`. |
| 8 | `lib/features/customers/domain/models/credit_document_content.dart:134` | `Collateral Summary:` → `Item Receipt Summary:` |
| 9 | same `:208` | `Itemized Collateral Details:` → `Item Receipt Details:` |
| 10 | same `:236` | `No collateral items recorded.` → `No item receipts recorded.` |
| 11 | `test/widget/features/customers/credit_origination_screen_test.dart:345,469` | Invert the “blocked with no item” test into “submits with zero item receipts”; update label assertions. |
| 12 | `test/unit/features/customers/credit_dao_test.dart:532` | Invert “rejects a credit with no pledged collateral item” into “creates a credit with zero item receipts”. |
| 13 | `test/unit/features/customers/credit_submission_idempotency_test.dart` | Add a deterministic empty-list fingerprint test. |
| 14 | collateral status tests | Add: settled credit with zero items → `Closed / Completed`. |
| 15 | `test/widget/features/customers/official_due_date_display_test.dart:306` | Remove the “a pledged collateral item is required” fixture comment/setup where no longer needed. |

**Explicitly out of scope:** renaming `collateral_items`, `CollateralItem`, `features/collateral`, DAO names, permission identifiers, FR-31 audit category labels, or the Collateral Registration/custody screens.

---

## 5. Implementation Handoff

**Scope classification: Minor** — direct implementation by the Developer agent; no replan or stakeholder escalation.

**Sequence:**

1. Apply the artifact edits in Sections 4.1–4.4 (PRD, epics, UX, architecture).
2. Add `epic-8` / `8-1-…` to `_bmad-output/implementation-artifacts/sprint-status.yaml` (`ready-for-dev`) and update `last_updated`.
3. Run `bmad-build` for Story 8.1 using this proposal as the spec input.
4. Run `bmad-code-review` afterward (optional but recommended).
5. Regression gate: full `flutter analyze` + `flutter test` must pass before review.

**Handoff recipient:** Developer agent (Amelia) via `bmad-build`.

**Success criteria:**

- A credit agreement can be created and disbursed with zero item receipts.
- Every user-facing origination-flow surface and generated PDF says **Item Receipt(s)**; no bare “Receipt” ambiguity with payment receipts.
- Attaching an item without a photo is still blocked; attaching items still binds them and generates references/audit events.
- A settled zero-item credit shows `Closed / Completed`.
- All updated tests pass, and no schema migration is introduced.

---

## 6. Checklist Record

| Section | Status | Notes |
|---|---|---|
| 1. Trigger & context | [x] Done | Stakeholder change request; evidence captured above. |
| 2. Epic impact | [x] Done | Epics 3 and 4 amended; Epic 8 added for traceability; no resequencing. |
| 3. Artifact conflicts | [x] Done | PRD, epics, UX, architecture identified; no schema conflict. |
| 4. Path forward | [x] Done | Option 1 Direct Adjustment selected. |
| 5. Proposal components | [x] Done | This document. |
| 6. Final review & handoff | [x] Done | Approved by Raheek on 2026-11-09. Epic 8 / Story 8.1 added to `sprint-status.yaml`; handoff to `bmad-build`. |

