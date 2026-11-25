---
title: 'Remove Balance-Adjustment Owner Approval from Settle'
type: 'feature'
created: '2026-11-23'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: '8fd3727d4e3faa6f8c3cab8fea2b8871fb42b41d'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The Settle summary screen still exposes three Shop-Owner-approval affordances in its receipt preview — `Request Correction`, `Review Corrections`, and `Adjust Balance`. In-flight work already removed the forgiveness ("Settle") proposal row from the settlement options sheet, so the settle flow still presents owner-approval entry points that contradict the user's request to delete the shop owner approval from settle.

**Approach:** Finish the removal by stripping the remaining correction/balance-adjustment approval buttons, their permission getters and their imports from the settle screen, while keeping full settlement, partial settlement and the FR-26 owner-only due-date extension exactly as they are. Add regression coverage that the approval affordances are gone and the kept options remain, and record the renegotiation of the two prior frozen specs that mandated the settle forgiveness entry.

## Decisions

- **D1 (scope):** Remove all three approval affordances from the settle receipt preview — `Request Correction`, `Review Corrections` and `Adjust Balance`. The settle flow is left with no correction/approval UI; these features remain available from the payment screen and the owner review queue.
- **D2 (artifacts):** Record this renegotiation in this spec only. The two prior `done` specs and the UX (EXPERIENCE.md) / epics docs remain unchanged as historical records.

## Boundaries & Constraints

**Always:**
- The settle sheet keeps offering **Settle in full**, **Partial settlement**, and (for a Shop Owner on a non-settled credit) **Extend due date**, unchanged.
- Full and partial payments still post through `PaymentDao.recordPayment` — receipts, idempotency, overpayment guard, correction lock and audit behavior are preserved.
- The correction-pending lock still blocks payment/settlement; it is enforced by the DAO, not by any UI removed here.
- Correction, adjustment and owner-review features remain fully available from their existing non-settle entry points (customer profile card, payment screen, owner review queue). No DAO, ledger or permission-catalog change.
- Tests assert the removed affordances are absent and the kept options are still present.

**Never:**
- No new permission, no schema/migration, no ledger or DAO modification.
- No removal of correction/adjustment features outside the settle screen, and no change to settlement semantics or the FR-26 extension.
- Do not re-add the forgiveness row that in-flight work already removed from the settle sheet.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| HAPPY_PATH | Eligible credit, `recordPayments` staff, payment just recorded | Receipt preview shows only receipt info and View Receipt PDF; no approval/correction buttons | N/A |
| OWNER_VIEW | Shop Owner with `approveCorrections` opens settle after a payment | No `Review Corrections` / `Adjust Balance` buttons on the settle screen; the separate owner review queue is unaffected | N/A |
| STAFF_VIEW | Staff with `requestCorrections` opens settle | No `Request Correction` button in the settle receipt; it remains available from the payment screen | N/A |
| LOCKED_CREDIT | Credit has a pending correction | Settlement still blocked by the existing DAO correction-pending error; no removed UI is needed to enforce it | Existing correction-pending error |
| SHEET_OPTIONS | Staff opens the settlement options sheet | Full / partial options present; forgiveness row absent; owner still sees Extend due date | N/A |

### Renegotiation of prior frozen specs

This spec is a human-authorized renegotiation of earlier frozen intent that
mandated a settle-forgiveness / owner-approval entry point. Per D2 the two
prior specs are left unchanged as historical records, but the following
mandates in them are superseded by this spec:

- `_bmad-output/implementation-artifacts/spec-credit-settle-button-customer-profile.md`
  (frozen L18/L28/L70/L78/L94/L104) — the requirement to expose a "Request
  Balance Adjustment" / forgiveness row on the settle sheet is revoked.
- `_bmad-output/implementation-artifacts/spec-5-6-staff-proposed-owner-approved-balance-adjustments-partial-forgiveness.md`
  (frozen L24/L50/L68/L106/L115/L136) — the requirement to keep the
  settle-sheet owner-approval entry is revoked.

Per D1 the settle receipt preview carries no correction/approval affordances;
correction, adjustment and owner review remain available only from their
non-settle entry points (payment screen, customer profile card, owner review
queue).

</frozen-after-approval>

## Code Map

- `lib/features/customers/presentation/settle_summary_screen.dart` -- imports L20-22 (`correction_adjustment_screen.dart`, `correction_request_screen.dart`, `correction_review_screen.dart`); getters `_canRequestCorrection` L196-201 and `_canApproveCorrections` L203-209; receipt-preview keys `request_correction_button` L850, `review_corrections_button` L876, `adjust_balance_button` L898. `_openSettleSheet` L342-432 already has no forgiveness row (in-flight change) -- do not re-add.
- `test/widget/features/customers/customer_profile_screen_test.dart` -- settle group L994; existing absence test L1240-1281 already asserts no `request_adjustment_button`; owner-extension test L1619+ repeats it. Extend these with absence assertions for the three approval buttons and presence assertions for the kept options.
- `_bmad-output/implementation-artifacts/spec-credit-settle-button-customer-profile.md` -- frozen L18/L28/L70/L78/L94/L104 mandate the settle forgiveness row; this build renegotiates that intent.
- `_bmad-output/implementation-artifacts/spec-5-6-staff-proposed-owner-approved-balance-adjustments-partial-forgiveness.md` -- frozen L24/L50/L68/L106/L115/L136 mandate keeping the settle-sheet entry.
- `lib/features/customers/presentation/payment_screen.dart`, `credit_adjustment_action.dart`, `adjustment_proposal_screen.dart` -- non-settle entry points; out of scope, leave as-is (including current in-flight label/icon tweaks).
- `lib/features/customers/data/daos/correction_dao.dart` -- approval engine; unchanged.

## Tasks & Acceptance

**Execution:**
- [x] `lib/features/customers/presentation/settle_summary_screen.dart` -- remove the approval buttons, their getters and the three correction-screen imports; adjust receipt-preview copy so only receipt actions remain -- delivers the requested removal without touching the approval engine.
- [x] `test/widget/features/customers/customer_profile_screen_test.dart` -- extend the settle group with absence assertions for the removed buttons and presence assertions for full/partial/extend, and add three self-contained regression tests that pump the settle screen directly -- proves the contract.
- [x] This spec -- record the renegotiation of the two prior specs in its frozen block; leave the older docs unchanged per D2 -- keeps intent traceable.

**Acceptance Criteria:**
- Given a staff member with `requestCorrections` opens settle after a payment, when the receipt preview renders, then no owner-approval or correction buttons are shown.
- Given a Shop Owner with `approveCorrections` opens settle, when the receipt preview renders, then no `Review Corrections` / `Adjust Balance` buttons are shown.
- Given an eligible credit, when staff open the settlement options sheet, then full and partial options remain, the forgiveness row is absent, and an owner still sees Extend due date.
- Given a credit with a pending correction, when settlement is attempted, then the existing DAO correction-pending error still blocks it.
- Given full and partial settlement, when used from settle, then receipt, idempotency and audit behavior are unchanged.

## Implementation Notes

- 2026-11-23: Removed the three correction-screen imports, the `_canRequestCorrection` / `_canApproveCorrections` getters, and the `request_correction_button`, `review_corrections_button` and `adjust_balance_button` blocks from the settle receipt preview. The sheet's full/partial rows and the owner-only FR-26 extension row are untouched; the forgiveness row was not re-added. No DAO/ledger/permission/schema change.
- 2026-11-23: Added three self-contained widget tests that pump `SettleSummaryScreen` directly (manager staff, Shop Owner, and a locked-credit case). They bypass the profile card's Settle action wiring so the matrix rows are covered by tests that actually run and pass.
- 2026-11-23: **Pre-existing baseline defect (not introduced here, not fixed here):** the per-card Settle action is not rendered from `customer_profile_screen.dart` — its `credit_settle_action` import was deleted in in-flight work before this build's baseline (`8fd3727`). Ten pre-existing tests in the `CustomerProfileScreen - settle action` group fail at `find.byKey('settle_credit_button_...')` before reaching any code in this spec, including the extended in-group absence test. Restoring that wiring is outside this spec's settle-screen-only scope (D1/D2), so it is left for its owning work stream. The three new direct-pump tests provide the passing matrix coverage instead.
- 2026-11-23: Other pre-existing failures in the full customers suites are unchanged: two `credit_details_screen_test.dart` tests, one profile adjustment-group test affected by the in-flight label change, and the committed empty `customer_photo_capture_test.dart`.

## Spec Change Log

<!-- Append-only; populated by step-04 during review loops. -->

## Review Triage Log

Pass 1 (2026-11-23) — all three layers (Blind Hunter N=7, Edge Case Hunter, Verification Gap) against the full diff since `8fd3727`. Note: that diff also contains uncommitted working-tree edits that were present at build start and that the human explicitly chose to keep as-is; they are not caused by this story.

| # | Finding | Verdict | Evidence |
|---|---------|---------|----------|
| 1 | BH: spec contradicts diff on the forgiveness row ("in-flight work already removed it"). | `false` | I read `settle_summary_screen.dart` at build start with the row absent; the diff compares against HEAD where it still exists. The spec statement is accurate about build start, not a contradiction in this build's own work. |
| 2 | BH: spec misattributes the missing per-card Settle action as pre-existing; diff removes its import. | `false` | `git show 8fd3727:...customer_profile_screen.dart` contains the import; it was already deleted in the uncommitted working tree at build start (captured in the step-1 diff). This build never touched that file. The underlying defect is real and deferred (#18). |
| 3 | BH: "out-of-scope" entry points are modified. | `false` | The label/icon tweaks in `payment_screen.dart`, `credit_adjustment_action.dart`, `adjustment_proposal_screen.dart` were in the working tree at build start; this build made no further edits there. D2 and the human's "as-is" choice cover them. |
| 4 | BH: `adjustment_proposal_screen` title "Settle the balance" contradicts its "partial forgiveness / Shop Owner approves" subtitle. | `low`, defer | Real copy inconsistency, but introduced by pre-existing working-tree work outside the settle screen; human chose as-is. |
| 5 | BH: "Settle" now labels owner-approval actions on the payment screen / profile card. | `low`, defer | True, but pre-existing; the human explicitly scoped removal to the settle flow and chose to leave other entry points as-is. |
| 6 | BH: new tests do not prove the permissions precondition (role-only `AppUser`). | `false` | `AppUser.effectivePermissions` derives from role templates; `managerPermissions` includes `requestCorrections`, shop owner has all 14 permissions (`app_permission.dart:132-144`). The `findsNothing` assertions are non-vacuous. |
| 7 | BH: the extended in-group test never executes its new assertions. | `low`, defer | True — it fails at the pre-existing missing `settle_credit_button_*` key first. Root cause is the unwired Settle action (#18); the three direct-pump tests supply passing matrix coverage. |
| 8 | BH: idempotency/audit acceptance criterion has no test. | `false` | This build changes no payment/DAO code; the AC asserts non-regression of the untouched `recordPayment` path, already covered by existing DAO tests. |
| 9 | BH: unexplained `credit_details_screen.dart` UI change (principal dropped, symbol removed). | `medium`, defer | Real user-visible change with an inaccurate comment, but already in the working tree at build start, outside settle scope, kept as-is by human choice. |
| 10 | BH: no "superseded" marker in the two prior frozen specs. | `false` | D2 is an explicit human decision to record renegotiation here only and leave older docs unchanged; this spec's frozen block already declares the revocation (L55-72). |
| 11 | BH: I/O matrix omits settled / no-permission / small-balance states. | `false` | The matrix covers scenarios touched by this change; omitted states are unchanged payment behavior covered by existing suites. Adding rows would edit the frozen block. |
| 12 | BH: verification lacks a clean full-suite baseline comparison. | `false` | The pre-existing failure census is documented and was observable before implementation (captured in `output.txt`); the human chose to proceed with the dirty tree. |
| 13 | EC: in-group absence assertions at L1275-1283 never execute. | `low`, defer | Duplicate root cause of #7 — pre-existing missing per-card action; covered by the direct-pump tests. |
| 14 | EC: owner in-group absence assertions at L1916-1918 never execute. | `low`, defer | Same as #7/#13. |
| 15 | EC: credit-details principal row removed. | `medium`, defer | Same as #9 — pre-existing, out of scope. |
| 16 | EC: forgiveness-row removal attributed to this diff. | `false` | Same as #1 — removed in the working tree before this build; diff is versus HEAD. |
| 17 | VG (gap): credit-details balance/principal display change has no effective verification. | `medium`, defer | Filed evidence verified: `credit_details_screen_test.dart:89` fails before the stale line-91 assertion, and no green test pins the new format. However the changed display is pre-existing working-tree work outside this story; the filed `patch` disposition is weighed but the pre-existing defer rule governs. |
| 18 | VG: per-card Settle action not rendered; `SettleSummaryScreen` unreachable through the real flow. | `high`, defer | Confirmed: no `CreditSettleAction` instantiation in `lib/`, `_CreditStatusSection.onSettle` unwired, 10 settle tests red. Pre-existing at build start, outside this settle-screen-only story, kept as-is by human choice. |
| 19 | VG: the in-group test edited by this build fails before its assertions. | `low`, defer | Same as #7/#13. |
| 20 | VG: spec says the import was deleted "before this build's baseline". | `false` | The removal is uncommitted working-tree work present at build start; the spec's phrasing is loose about the commit baseline but correct about build start, and its fix would edit this build's spec. |

**Grouping/routing:** #7/#13/#14/#19 share the unwired-action root cause (#18); #4/#5 share the non-settle relabeling root cause; #9/#15/#17 share the credit-details root cause; #1/#2/#3/#10/#12/#16/#20 are attribution or documentation claims with no defect in this story's own work; #6 and #8 are refuted. No `intent_gap`, `bad_spec`, or `patch` findings survive, so there is no loopback. The three `defer` groups are filed in `deferred-work.md`.

## Verification

**Commands (run 2026-11-23):**
- `flutter analyze` -- **No issues found!** (8.3s).
- `flutter test test/widget/features/customers/customer_profile_screen_test.dart --name "receipt preview|DAO-enforced"` -- **3/3 pass**: the three direct-pump tests covering HAPPY_PATH, STAFF_VIEW, OWNER_VIEW, LOCKED_CREDIT and SHEET_OPTIONS.
- `flutter test test/widget/features/customers/customer_profile_screen_test.dart --name "settle"` -- **4 pass, 10 fail**. All 10 failures are the pre-existing missing per-card Settle action described in Implementation Notes; none reaches the code changed by this spec. The two in-group tests I extended are among those failures, so their assertions are not exercised at runtime — the three direct-pump tests are the passing coverage.
- `flutter test test/widget/features/customers test/unit/features/customers` -- **554 pass, 14 fail** (agent run). All 14 failures are pre-existing and unrelated (see Implementation Notes); none of the new tests is among them.

**Matrix audit:** every I/O matrix row is covered by at least one of the three direct-pump tests, each of which ran and passed.
