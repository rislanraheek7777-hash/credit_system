# Epic 8 Context: Item Receipt Terminology & Optional Intake (Change Request)

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Epic 8 implements the approved 2026-11-09 change request that makes item attachment optional at credit origination and aligns user-facing origination-flow terminology with how shop staff describe held items. A credit agreement can now be originated and disbursed with zero item receipts (an unsecured credit), and every origination-flow surface and generated document must use "Item Receipt" instead of "Pledged Collateral". The change matters because it lets the shop record unsecured credits and removes mandatory-item enforcement that contradicted real counter practice, while preserving the existing collateral schema, custody machinery, and payment-receipt semantics. Internal schema and code identifiers are not renamed.

## Stories

- Story 8.1: Optional Item Receipts at Origination & Terminology Rename

## Requirements & Constraints

- Zero or more item receipts per credit: attachment is optional, and a credit can be submitted with none. Each attached item still receives a unique, system-generated Item Reference Number.
- With zero items attached, no custody record and no collateral audit event are generated. Category 2 credit-origination audit always fires.
- Per-item attributes are unchanged: category (`Gold/Jewelry`, `Electronics`, `General Valuables`), description, condition grading, and an independent Estimated Collateral Value stored in minor units (never conflated with principal). Gold/Jewelry requires a calibrated decimal gram weight stored with its unit.
- The mandatory-photo rule applies per attached item, not per credit: every attached item needs at least one photo unless a Shop Owner-approved exception exists. A zero-item credit is not blocked by this rule. The blocking message stays exactly `"Every item receipt must have at least one photograph."`
- Executed agreement/voucher documents must include Item Receipt Details (weights and descriptions); zero-item documents render the empty state `No item receipts recorded.`
- Success criteria: origination and disbursement succeed with zero items; affected UI and PDF strings say Item Receipt(s); attaching an item still binds it, generates references/audit events, and enforces the photo rule; a settled zero-item credit displays `Closed / Completed`; no schema migration; `flutter analyze` and `flutter test` pass.

## Technical Decisions

- No data migration. `collateral_items.credit_id` is already nullable and `credits` has no item-count constraint. Do not rename the `collateral_items` table, `CollateralItem`, `features/collateral`, DAO names, permission identifiers, or FR-31 audit category labels. Standalone Collateral Registration and custody screens are outside rename scope.
- Origination and document code lives in `features/customers` (origination screen, disbursement screen, `credit_document_content`), while item intake and custody live in `features/collateral`; respect the feature-first, inward-dependency rule.
- Remove the origination empty-selection submission guard and the credit DAO's empty-item-list `ArgumentError`; retain validation and binding when item IDs are supplied.
- Idempotency is already safe: the submission fingerprint serialises a sorted item list, so an empty list is deterministic. No code change expected, but pin it with a test.
- Status derivation: add an explicit zero-items branch — financially settled with no item receipts yields `Closed / Completed`. Preserve existing branches: settled with any item `In Custody` yields `Settled (Items Pending Handover)`; any item `Exception / Held` yields `Closed (Collateral Exception)`.
- PDF generators already tolerate empty lists; only wording changes.
- Existing tests that block or reject a zero-item credit encode the superseded rule and must be inverted: replace with zero-item success tests, add an empty-list idempotency fingerprint test and a zero-item settled-status test, and keep per-item mandatory-photo tests. The change record lists the affected files and fixtures.

## UX & Interaction Patterns

- Credit creation wizard: customer → term + principal → optionally add item receipts → review → submit. Adding items is optional; zero items is a valid review state.
- Labels across origination, disbursement, and draft/voucher PDFs: section heading `Item Receipts` (singular `Item Receipt`); summary `Total Estimated Item Receipt Value`; UI empty state `No item receipts recorded for this customer. Item receipts are optional.`; document empty state `No item receipts recorded.`
- Never use bare `Receipt` for items: that term is reserved for immutable payment receipts. Always write `Item Receipt`.
- A settled credit with zero item receipts has no handover step and resolves directly to `Closed / Completed`.
- Microcopy stays concise, factual, and uses canonical glossary terms exactly; validation errors state the rule.

## Cross-Story Dependencies

- Depends on completed Story 3.1 (item-receipt schema and intake) and Story 4.1 (credit agreement data model); this story reverses their prior "at least one item" assumption.
- Retains Story 3.2's per-attached-item photo requirement and Story 3.3's exception workflow.
- Renames the disbursement and document surfaces introduced in Stories 4.3/4.4; Story 4.2's live summary still shows the item total and accepts zero items.
- Epic 7 vault counts remain valid (they count attached items); no behavioral change.

