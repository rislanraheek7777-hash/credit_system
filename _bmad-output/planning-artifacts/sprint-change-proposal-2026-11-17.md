---
title: Sprint Change Proposal — Staff-Proposed, Owner-Approved Balance Adjustments (Partial Forgiveness)
date: 2026-11-17
project: credit_system
trigger: Manual balance adjustment flow cannot serve legitimate partial forgiveness at settlement
status: approved 2026-11-17 by Raheek
scope_classification: Moderate
---

# Sprint Change Proposal — Partial Forgiveness via Staff-Proposed, Owner-Approved Balance Adjustments

## 1. Issue Summary

**Trigger:** While reviewing the settle flow in the customer profile (`spec-credit-settle-button-customer-profile.md`, status `in-review`, created 2026-11-16), it was established that a customer who cannot pay their full outstanding balance has no authorized, auditable way to have part of the balance forgiven at settlement time. The only manual balance adjustment path in the system is Shop-Owner-only (Story 5.5 AC-5, `CorrectionAdjustmentScreen`), it is not reachable from the settle flow, and staff cannot initiate it with owner approval.

**Issue type:** New requirement emerged from stakeholders (partial forgiveness at the counter), surfacing a gap in an existing requirement (FR-22).

**Evidence:**
- Product owner request (this session, 2026-11-17): staff should be able to "edit the balance directly" with owner approval for partial forgiveness.
- Codebase: `correction_adjustment_screen.dart` (owner-direct adjustment, immutable `adjustment_credit`/`adjustment_debit` ledger entries); unreferenced duplicate `correction_adjustment_screen_temp.dart`; `CreditCorrections` table already supports non-payment requests (`originalPaymentId` nullable) but has no adjustment-direction column and its approval path always applies `balance_cents += amount`.
- The exact business-rule semantics of `correctionAmountCents` are an open accounting decision recorded in Story 5.5 (both the table and DAO doc comments) — Story 5.6 must resolve direction explicitly.
- The 14-permission catalog is strictly fixed — the design must reuse `requestCorrections` (staff) and `approveCorrections` (owner). No new permission.

**Problem statement:** When a customer cannot pay in full, staff have no controlled way to forgive part of the balance during settlement. Workarounds would either violate ledger immutability (raw balance edits — impossible in this architecture, and undesirable) or concentrate all forgiveness authority in the Shop Owner as sole initiator, with no staff proposal/owner approval loop at the counter.

## 2. Impact Analysis

### Epic impact
- **Epic 5 — reopened (now `in-progress`)** in `sprint-status.yaml`. New Story 5.6 added governing staff-proposed, owner-approved adjustments. Story 5.5 remains `done` with an amendment cross-reference; its owner-direct adjustment AC stays in force. Epic 5 summary text updated in both locations (requirements summary + epic detail).
- **Epics 1–4, 6–8 — unaffected.** Overdue evaluation already excludes settled/zero-balance credits; adjustment entries are ordinary ledger entries; custody flow untouched.
- **Sequencing:** No resequencing. Story 5.6 depends on 5.2 (ledger math), 5.3 (correction lock), 5.5 (correction request/approval pattern) — all `done`.

### Story impact
- **New: Story 5.6 — Staff-Proposed, Owner-Approved Balance Adjustments (Partial Forgiveness)** (added to `epics.md`, status `backlog` in `sprint-status.yaml`).
- **Story 5.5** — amendment note added; behavior unchanged.
- **`spec-credit-settle-button-customer-profile.md`** — unchanged. The settle button remains a full-settlement shortcut over the payment path; forgiveness is a separate adjustment flow. (Related, unresolved: the spec is `in-review` and its frozen intent — Settle offered only for eligible credits — does not match the shipped gate in `credit_settle_action.dart::isAvailableFor`, which checks only `recordPayments`. Flagged for the settle-button review; not part of this change.)

### Artifact conflicts
- **PRD — FR-22 amended** (governance now two-step: staff propose → owner approve, or owner-direct; staff-proposal input by amount+direction or new effective balance; verification scenario 8 added). **FR-23 amended** (correction-pending lock explicitly covers pending adjustment proposals). FR-21 untouched.
- **Architecture spine** — three additive notes: adjustments post only from approved requests or direct owner execution, in the same atomic transaction as the lock lift; `isPaymentLocked` covers adjustment proposals; adjustment approval is a high-risk administrative action locked offline (AD-6 rule 8). No new AD; no schema or pattern change mandated by the spine itself.
- **UX (EXPERIENCE.md)** — new IA row `Balance Adjustment Proposal`; Credit Details actions gain `Balance Adjustment` (staff-propose → owner-approve, owner-direct allowed); new journey 5b (partial forgiveness at settlement). DESIGN.md unaffected (no visual identity change).
- **secondary artifacts** — `sprint-status.yaml` (epic reopened, 5-6 backlog, action item), `epics.md`, PRD, architecture spine, this proposal.

### Technical impact
- **No new permission** (fixed catalog). **No raw balance mutation** — balance stays derived from immutable ledger entries.
- **Data model:** `credit_corrections` is reusable for the request lifecycle but lacks an adjustment-direction column (and its approval applies `balance_cents += amount` only). Story 5.6 will either add a `direction` column (Drift migration) or introduce a sibling `adjustment_requests` table. Decision deferred to implementation with the open accounting semantics resolved.
- **Ledger:** `credit_ledger_entries` already supports `adjustment_debit` / `adjustment_credit`; posting path exists (`recordAdjustment`) and must gain a pending-proposal → approval variant (or the correction approval path generalized by direction).
- **Lock:** reuse `correction_pending` / `isPaymentLocked`; payments blocked on the affected credit only, per user decision 2026-11-17.
- **Offline:** approval is high-risk administrative — locked offline.
- **Audit:** proposal / approval / rejection all log Category 7 events with actor IDs, target credit, pre/post balance, justification.
- **Cleanup owed by implementation:** delete unreferenced `correction_adjustment_screen_temp.dart`.

## 3. Recommended Approach

**Option 1 — Direct Adjustment (selected).** Modify the existing plan by adding Story 5.6 to reopened Epic 5 and amending FR-22/FR-23 and dependent artifacts.

Alternatives considered:
- Option 2 (rollback): nothing to roll back — settle-button work is additive and unaffected. Not viable.
- Option 3 (MVP review): MVP already shipped; this is post-MVP governance extension. Not applicable.
- Hybrid: not needed; no milestone replanning required.

**Rationale:** Reuses the proven Story 5.5 correction-request/approval architecture and Story 5.3 lock machinery; honors ledger immutability; keeps staff authority bounded by owner approval; lowest risk of the three options.

**Effort:** Medium. **Risk:** Low–Medium (main risk is the open `correctionAmountCents` semantics — must be resolved explicitly in Story 5.6; direction column vs sibling table is an implementation decision). **Timeline impact:** one story; no milestone resequencing.

## 4. Detailed Change Proposals (all applied 2026-11-17)

| # | Artifact | Change | Status |
|---|----------|--------|--------|
| 1 | `prd.md` FR-22 | Governance replaced: two-step control — staff-proposed/owner-approved adjustment (`requestCorrections` proposes with mandatory reason; `approveCorrections` owner approves; immutable `adjustment_debit`/`adjustment_credit` posts; lock while pending) + owner-direct path retained; input by amount+direction or new effective balance; verification scenario 8 added; permissions bullet updated | Applied |
| 2 | `prd.md` FR-23 | Correction-pending lock explicitly extends to pending adjustment proposals | Applied |
| 3 | `epics.md` | Epic 5 summary (requirements summary + epic detail) notes Story 5.6; Story 5.5 cross-reference; **new Story 5.6** with full ACs, traceability (FR-6, FR-22, FR-23, FR-31 Category 7, AD-1/2/6), dependencies, testing guidance, and implementation notes (incl. `correction_adjustment_screen_temp.dart` deletion) | Applied |
| 4 | `sprint-status.yaml` | `epic-5: in-progress`; added `5-6-staff-proposed-owner-approved-balance-adjustments-partial-forgiveness: backlog`; action item recorded; `last_updated` bumped | Applied |
| 5 | `ARCHITECTURE-SPINE.md` | AD-3 atomicity note: adjustments post only from approved requests or direct owner execution, same atomic transaction as lock lift; `isPaymentLocked` covers adjustment proposals; offline high-risk action list extended with adjustment approval | Applied |
| 6 | `EXPERIENCE.md` | New IA row `Balance Adjustment Proposal`; Credit Details actions extended; new journey 5b (partial forgiveness at settlement) | Applied |

## 5. Implementation Handoff

**Scope classification: Moderate** — backlog reorganization (done via this proposal) plus implementation requiring Developer execution; no PM/Architect replan required since no milestone rescope.

**Handoff:**
1. **Developer (bmad-build)** — implement Story 5.6: resolve `credit_corrections` direction semantics vs sibling table; Drift migration if needed; staff proposal UI on customer profile credit cards and/or payment/settlement screen (matching the settle-button pattern); owner approval queue integration (reuse correction queue surface); ledger posting on approval; correction-pending lock enforcement; audit events; delete `correction_adjustment_screen_temp.dart`; unit/widget/integration tests per the story's Testing Guidance.
2. **Product Owner** — confirm the accounting-semantics decision for `correctionAmountCents` (amount vs delta; forgiveness direction handling) and SLA expectations for the approval queue.

**Success criteria:**
- All Story 5.6 ACs pass; `flutter analyze` clean; full test suite green.
- Verification scenario 8 (PRD FR-22) passes end-to-end.
- No permission catalog changes; no raw balance mutation anywhere; audit events emitted for proposal/approve/reject.
- sprint-status.yaml story 5-6 → `done` only via the normal build/review flow.

**Related open items (not in scope, flagged):**
- Settle-button spec (`in-review`) eligibility-gate drift vs frozen intent.
- Story 5.5 open accounting decision (`correctionAmountCents` semantics) — must be closed by Story 5.6.
