---
title: 'Soft-delete a customer from the customer profile screen'
type: 'feature'
created: '2026-11-19'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: 'bbfb913c37d33b33bebd576fe86f7e234c3fe1e8'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Counter staff can register and edit customers, but there is no way to remove an erroneous or test customer. A customer who has never had a credit carries no financial history, ledger, or collateral obligations, yet remains in search results forever.

**Approach:** Add a shop-owner-gated "Delete customer" action to the customer profile screen, eligible only when the customer has zero credit records. Deletion is a soft delete (`customers.deleted_at` timestamp), not a hard `DELETE`: the row is retained for audit/FX integrity, hidden from all lists and search, and the action is recorded in the append-only audit trail. Hard deletion is impossible anyway — `credits.customer_id`, `collateral_items.customer_id`, and `customer_follow_ups.customer_id` all use `ON DELETE RESTRICT`.

## Boundaries & Constraints

**Always:**
- Soft delete only via a new nullable `customers.deleted_at` column, added by a `from < 27` Drift migration step (`schemaVersion => 27`) plus a `drift_migration_v27_test.dart` following the v26 test pattern.
- Eligibility check must consider ALL credit rows for the customer regardless of status (active, overdue, settled, cancelled, pending-disbursement workflow). Any credit row blocks deletion.
- Delete action is re-checked server-of-truth style in the DAO/handler layer via `AuthorizationGuard` (owner-administrative pattern), not only by hiding the button in the UI.
- Audit record written on delete: category 1 (Customer creation and profile edits), `actionType` such as `customer_soft_deleted`, `targetEntityType: customer`, with shop/customer scope — mirror the CreditDao audit + `sync_queue` (`pending_server_ack`) pattern.
- Deleted customers are excluded from `CustomerDao.searchCustomers`, `getCustomersByShopId`, duplicate-phone/NIC reuse checks as applicable, and any list/picker that reads customers.
- Delete is blocked while offline (sensitive administrative action; mirror the `requireOnlineSession` / offline-blocked pattern used for corrections).
- After a successful delete, the UI pops back to the search screen (callers pass no result) and the deleted customer no longer appears there.

**Never:**
- No hard `DELETE` of customer rows, no new audit category (the 14-event catalog is fixed), no `double` money, no changes to the permission catalog (no "delete customer" permission exists or may be added without PRD amendment).
- No restore/undelete UI in this scope.
- No deletion side effects on credits, ledger, collateral, photos, or audit records (soft delete preserves them all).
- Do not touch `credits`, collateral custody, or payment flows.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Happy path | Owner views customer with zero credits | "Delete customer" button visible; confirm dialog → soft delete succeeds; audit event recorded; navigates back; customer absent from search | N/A |
| Customer has credits | Any credit row exists (any status) | Delete button disabled or shows blocking explanation; no deletion path reachable | Blocking snackbar/dialog naming the restriction |
| Non-owner staff | Manager/cashier/custom role | Delete button not rendered | N/A |
| Offline | Owner, offline session | Delete blocked with an offline message; no local-only destructive write | `requireOnlineSession`-style failure surfaced to UI |
| Already deleted | `deleted_at != null` | Customer never appears in search/lists/pickers | N/A |
| Confirmation declined | Owner taps delete, cancels | Nothing changes | N/A |

## Decisions (human-approved 2026-11-19)

1. **Eligibility — A:** Zero credits ever, of any status. Only customers with no financial footprint can be soft-deleted.
2. **Gate — A:** Shop Owner only, enforced via `AuthorizationGuard.checkOwnerAdministrativeAction` (owner-administrative pattern); no new permission.
3. **Visibility — A:** Soft-deleted customers are excluded from search, lists, and pickers everywhere; the profile is unreachable in-app.

</frozen-after-approval>

## Code Map

- `lib/features/customers/presentation/customer_profile_screen.dart` -- add Delete action to profile-actions `Wrap` (after `add_credit_button`, ~line 536); RBAC flags computed ~lines 460-469; `_credits` already loaded via `CreditDao.getCreditsByCustomerId(shopId, customerId)` (`credit_dao.dart:119-128`); destructive-confirm dialog pattern in `correction_review_screen.dart:141-202` (barrierDismissible false, bold effects list, "cannot be undone" wording). Not to change: payment/settle/disbursement sections.
- `lib/features/customers/data/daos/customer_dao.dart` -- add `softDeleteCustomer(shopId, customerId)` (sets `deletedAt`) and exclude `deletedAt != null` rows from `searchCustomers` (109), `getCustomersByShopId` (102), `getCustomerById` behavior unchanged (direct-id loads of deleted rows should fail or be unreachable). Follow `UserDao.deactivateUser` (`user_dao.dart:198`) shape.
- `lib/core/data/local/tables/customers_table.dart` -- add nullable `deletedAt` DateTime column.
- `lib/core/data/local/app_database.dart` -- `schemaVersion => 27`; add `if (from < 27)` step adding `deleted_at` column; mirror v26 pattern (~line 1020).
- `test/unit/core/data/local/drift_migration_v27_test.dart` -- new, modeled on `drift_migration_v26_test.dart`.
- `lib/core/permissions/authorization_guard.dart` (lines ~68-83) -- reuse `checkOwnerAdministrativeAction`; do NOT add a new `AppPermission`.
- `lib/features/customers/data/daos/credit_dao.dart` -- reference only: zero-credit eligibility = `getCreditsByCustomerId` returns empty; also the audit + `sync_queue` write pattern (~lines 315-355, 554+) to mirror for the audit event.
- `lib/features/audit/domain/models/audit_event_record.dart` -- category 1 title already exists ("Customer creation and profile edits"); use it, no new category.
- `lib/features/customer_search_screen.dart` (really `lib/features/customers/presentation/customer_search_screen.dart:387-399`) -- navigation entry point; no result plumbing needed, just pop.
- `lib/features/customers/data/services/customer_registration_service.dart` -- photo reference (`PhotoStorageService.deletePhotoIfExists`, ~line 259) — do NOT delete photos in this scope (soft delete must stay reversible); note in implementation.
- `test/widget/features/customers/customer_profile_screen_test.dart` -- extend: delete button visibility/gating matrix; confirm/cancel dialog; ineligible (has credits) state.

## Tasks & Acceptance

**Execution:**
- [x] `lib/core/data/local/tables/customers_table.dart` -- add nullable `deletedAt` `DateTimeColumn` -- schema for soft delete
- [x] `lib/core/data/local/app_database.dart` -- bump `schemaVersion` to 27, add `if (from < 27)` `addColumn` step -- migrate existing installs
- [x] `test/unit/core/data/local/drift_migration_v27_test.dart` -- new migration test modeled on v26 -- lock the schema delta
- [x] `lib/features/customers/data/daos/customer_dao.dart` -- add `softDeleteCustomer(shopId, customerId)` with `AuthorizationGuard` owner re-check and audit write (category 1, `customer_soft_deleted`); filter `deletedAt == null` in list/search queries -- domain integrity + auditability
- [x] `lib/features/customers/presentation/customer_profile_screen.dart` -- add owner-gated "Delete customer" button in the actions `Wrap`; disable/block with explanation when `_credits.isNotEmpty`; confirm dialog; pop on success; block when offline -- user-facing action
- [x] `test/widget/features/customers/customer_profile_screen_test.dart` -- cover gating matrix, dialog confirm/cancel, ineligible state -- regression protection
- [x] Verify no other customer-list queries leak soft-deleted rows (grep for `customers` table reads across `lib/`) -- consistency

**Acceptance Criteria:**
- Given a shop owner viewing a customer with zero credit rows of any status, when they tap "Delete customer" and confirm, then the customer row is soft-deleted (`deleted_at` set), an audit event (category 1) is recorded, and the customer no longer appears in search.
- Given a customer with at least one credit row of any status, when any user opens the profile, then deletion is not possible.
- Given a non-owner authenticated staff member, when they open any customer profile, then no delete action is rendered.
- Given an offline session, when the owner attempts deletion, then the operation is blocked with an offline error and nothing is written.
- Given an existing database at schema v26, when the app upgrades to v27, then the migration applies cleanly and prior data is intact.

## Implementation Notes

- Implemented 2026-11-19 by implementation subagent; verified by parent (diff read, tests re-run).
- `getCustomerByNic` was deliberately left NOT filtering `deleted_at`: `UNIQUE(shop_id, nic)` would make a NIC reuse fail late with a raw constraint error either way; leaving soft-deleted NICs visible preserves the friendly duplicate-NIC error path. `findCustomersByPhone` filters via the filtered `getCustomersByShopId`. `getCustomerById` unchanged per spec.
- Extra consistency edit beyond the spec's task list: `credit_dao.dart` create-credit customer fetch and dashboard `total_customers` raw SQL now exclude soft-deleted customers; deleted profiles are unreachable in-app (profile pops with no result; search refreshes on return).
- Offline block is UI-gated via threaded `isOfflineOnly` (MainApp -> _CustomersPage -> CustomerSearchScreen -> CustomerProfileScreen) with a snackbar; the DAO has no session object, mirroring `CorrectionDao` (UI-level offline block). DAO-level offline assertion would be a small follow-up.
- Implementation subagent accidentally ran `dart format` mid-task and re-styled in-flight 5.6 code, then fully recovered (format-only hunks reverted file-by-file; tree verified identical: full suite +1076 ~7 -6 as before the accident).
- Review patches (2026-11-19): 4 new DAO/credit/dashboard soft-delete unit tests, mounted search→profile→delete refresh test (search now reloads only when the profile pops `true`), delete button requires `role.isOwner && isActive`, `isOfflineOnly` defaults to `true` (fail-closed), deterministic UUIDv5 sync_queue `entityId`, schema doc comment attribution fixed, option-B NIC fix (domain `Customer.deletedAt` plumbed; duplicate-NIC error/dialog distinguish deleted holders; PII hidden for deleted records; unit test pins it).
- Final verification: `flutter analyze` → No issues found; full suite `+1084 ~7 -6` (the 6 failures are the same pre-existing HEAD-red tests listed above; +8 new passing tests from the patch round).
- Pre-existing failures (NOT this work; all expect UI that HEAD removed, verified: HEAD's customer_profile_screen.dart has 0 matches for 'Credit agreement created' while the test file expects it): 3 failures in test/widget/features/customers/customer_profile_screen_test.dart (credit origination SnackBar x2, Edit action), plus customer_photo_capture_test.dart, multi_credit_selection_test.dart, dashboard_live_metrics_test.dart. `flutter analyze`: No issues found.
- `drift_migration_v26_test.dart` (untracked, in-flight 5.6) assertions bumped 26->27 with a clarifying note; other prior migration tests bumped mechanically.

## Spec Change Log

## Review Triage Log

| # | Finding (layer) | Verdict | Evidence / Route |
|---|-----------------|---------|------------------|
| V1 | DAO credit-eligibility re-check untested (VG, pre-verified) | patch | No unit test exists; widget path cannot reach the DAO re-check. Patched: 4 unit tests added (credit-any-status block, double-delete, cross-shop actor, not-found). |
| V2 | Search list never re-queries after profile pop; unverified + unconditional reload on every return (VG pre-verified, BH low) | patch | `.then(_loadCustomers)` ran on every pop regardless; no test mounted search behind profile. Patched: pop now passes `true` only after a successful delete; search reloads only on that result; mounted delete-flow test added. |
| V3 | Credit-creation `deletedAt.isNull()` guard untested (VG pre-verified) | patch | `credit_dao_test.dart` had the sibling shop-mismatch test but no soft-deleted case. Patched: test added asserting `StateError`, no rows written. |
| V4 | Dashboard `total_customers` `AND deleted_at IS NULL` untested (VG pre-verified) | patch | All fixtures seeded live customers only. Patched: soft-deleted-seed test asserts `totalCustomers == 1`. |
| V5 | Duplicate-NIC after soft delete bricks the NIC with dead-end message (VG, BH, ECH) | patch | Human chose option B (2026-11-19): plumb `deletedAt` through the domain `Customer`; duplicate-NIC error/dialog now states it is a deleted record, with no PII and no "open the profile" instruction; unit test pins the interaction. |
| V6 | Offline block is UI-only; DAO has no session/offline assertion (VG, BH) | false (spec-settled) | Frozen spec mirrors the corrections pattern, which is UI-level offline blocking (`requireOnlineSession` at the UI/service edge; `CorrectionDao` likewise has no DAO offline check). Implementation matches; DAO-level guard would add public surface. Tracked as a follow-up in Implementation Notes. |
| V7 | Schema doc comment attributes v27 to "Story 5.6" (VG, BH) | patch | Direct misattribution; soft delete is the 2026-11-19 spec, Story 5.6 was v26 `direction`. Patched: comment corrected. |
| V8 | Soft-delete widget group shares a red file (VG) | false | Pre-existing test debt (3 unrelated failures at HEAD); the group is distinguishable via `--name` filtering; nothing this change can fix. |
| H1 | Spec Code Map "direct-id loads of deleted rows should fail" vs unfiltered `getCustomerById` (BH) | false | No caller reaches a deleted profile in-app (search filters, pop-on-delete, dashboard excludes, createCredit excludes); `getCustomerById` unchanged is what the Code Map mandates; fix would edit the spec — rejected per rule. |
| H2 | Offline UI-only (BH duplicate of V6) | false (spec-settled) | Same as V6. |
| H3 | Deactivated owner sees an enabled "Delete customer" button (BH) | patch | Other gated actions pair role/permission with `isActive`; the button tapped straight to a DAO `PermissionDeniedException`. Patched: `canDeleteCustomer` now requires `role.isOwner && isActive`. |
| H4 | Adjustment eligibility doc not enforced; pending-disbursement/cancelled credits forgivable (BH) | defer | Story 5.6 in-flight work, not this change; appended to deferred-work.md. |
| H5 | `requestCorrection` amount <= balance validated pre-transaction only (BH) | defer | Story 5.6 in-flight work; appended to deferred-work.md. |
| H6 | v25->v26 lacks `CHECK (direction IN ('debit','credit'))`; schema drift vs fresh installs (BH) | defer | Story 5.6 in-flight work; appended to deferred-work.md. |
| H7 | SettleSummaryScreen PDF failure strands user on settled credit; `_reloadAfterPayment` swallows re-query failure (BH, ECH) | defer | Story 5.6 in-flight work; appended to deferred-work.md. |
| H8 | Dashboard quick actions render for every role, no RBAC/`isActive` (BH) | defer | Story 5.6 in-flight work; appended to deferred-work.md. |
| H9 | Dashboard metric redesign (outstanding/ratio -> overdue) unspec'd; contradicts frozen PRD/specs (BH) | defer | Story 5.6 in-flight work; appended to deferred-work.md; needs correct-course. |
| H10 | `watchMetrics` stale `_overdueCutoff`; errors swallowed to default tz (BH, ECH) | defer | Story 5.6 in-flight work; appended to deferred-work.md. |
| H11 | Search reloads whole list on every profile return (BH) | patch | Grouped with V2 (same root cause); patched with the result-flag gate. |
| H12 | ~100 duplicated lines PaymentScreen/SettleSummaryScreen (BH) | defer | Story 5.6 in-flight work; appended to deferred-work.md. |
| H13 | Staff-proposed balance *increases* exceed frozen forgiveness intent (BH) | defer | Story 5.6 in-flight work; appended to deferred-work.md; needs human sign-off or removal of the debit path. |
| H14 | NIC dead-end (BH duplicate of V5) | patch | Human chose option B; patched as V5. |
| H15 | sync_queue `entityId` random UUID; not linkable/deterministic (BH) | patch | Fix is a one-expression change; no surface added. Patched: `entityId` = UUIDv5 of `credit-system/customer/<shopId>/<customerId>`. |
| H16 | Correction review dialog shows nonsense negative post-balance (BH, ECH) | defer | Story 5.6 in-flight work; appended to deferred-work.md. |
| H17a | Stale strings in v14/v15 migration tests and "Schema v7 Tests" group (BH) | false | Pre-existing cosmetic drift in files this diff only version-bumped; not caused by this change. |
| H17b | Agent-instruction residue in the spec's Design Notes (BH) | false | Fix is to edit this build's spec — rejected per rule; Design Notes tidied as spec hygiene instead. |
| H17c | No unit-level DAO test for `softDeleteCustomer` (BH) | patch | Grouped with V1; patched. |
| H17d | Settle spec completion-log ambiguity (BH) | false | Story 5.6 spec hygiene; fix would edit a spec; not this change. |
| H18 | Settle-flow minor warts: prefill clobber, full-balance sheet row clears entry, no push re-entrancy guard (BH) | defer | Story 5.6 in-flight work; appended to deferred-work.md. |
| E1 | NIC dead-end (ECH duplicate of V5) | patch | Patched as V5. |
| E2 | Settle extension DatePicker interpreted device-local, persisted off-by-one (ECH) | defer | Story 5.6 in-flight work; appended to deferred-work.md. |
| E3 | watchMetrics stale cutoff (ECH duplicate of H10) | defer | Story 5.6 in-flight work; appended to deferred-work.md. |
| E4 | Full-forgiveness adjustment equal to balance posts zero without settling (ECH) | defer | Story 5.6 in-flight work; appended to deferred-work.md. |
| E5 | `isOfflineOnly` defaults to `false` — fail-open for any future caller (ECH) | patch | Flip default to `true`; test helper passes `false` to keep online-path tests; threaded production call sites unchanged. |
| E6 | `_reloadAfterPayment` swallows re-query failure (ECH duplicate of H7) | defer | Story 5.6 in-flight work; appended to deferred-work.md. |
| E7 | `direction='credit'` + non-null `originalPaymentId` ledgers `compensating_debit` while reducing balance (ECH) | defer | Story 5.6 in-flight work; appended to deferred-work.md. |

## Design Notes

Soft delete over hard delete is forced by the schema (`ON DELETE RESTRICT` on three referencing tables) and by the audit contract (original records must remain attributable). Eligibility is intentionally stricter than the FK requires: even settled credits imply a financial relationship the shop may need to look up, so zero-credit is the only safe delete window. The destructive-confirm dialog mirrors the `correction_review_screen.dart` pattern.

## Verification

**Commands:**
- `flutter analyze` -- expected: no issues (zero-lint policy)
- `flutter test test/unit/core/data/local/drift_migration_v27_test.dart test/widget/features/customers/customer_profile_screen_test.dart` -- expected: all pass
- `flutter test` -- expected: suite stays green (baseline ~1021 passed / 7 skipped)
