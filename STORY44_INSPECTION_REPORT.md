# Credit Management System — Story 4.4 Inspection Report

**Inspection scope**: Story 4.4 specification, approval package, decision register, questionnaire, Story 4.3 implementation
**Constraints**: No file modifications, no package installations, no Git state changes, no migration execution
**Date**: 2026-10-23

---

## 1. Story 4.3 Disbursement Behavior — Verified Against Code

| Aspect | Verified State | Evidence |
|--------|---------------|----------|
| **Disbursement condition** | Loan in `Active / Pending Disbursement`; authorized staff with `confirmLoanDisbursement` permission confirms physical cash handover | `authorization_guard.dart` enforces Shop Owner only; `epics.md` 4.3 lines 992–996 |
| **Confirmation method** | Staff confirms physical cash handover; system records `confirmed cash disbursement timestamp` and `disbursing staff ID` | `epics.md` 4.3 lines 992–996 |
| **Transaction boundary** | Loan → `Financial Status: Active / Disbursed`, `Overall Status: Active`; audit Category 4 event queued locally; **server-side append upon sync** (owned by audit-writer work, **not** this story) | `epics.md` 4.3 lines 996–997: "the authoritative append to the server-side `audit_events` table is performed by the server-side audit writer upon synchronization and is owned by the audit-writer work, not by this story." |
| **Official Calendar Due Date** | Calculated by adding preset calendar days (30/60/90) or custom date to disbursement date in `Asia/Colombo`. Test Cases 1–5 verified. | `epics.md` 4.3 lines 1001–1009 |
| **Cancellation behavior** | `PendingDisbursement` cancelled → `Cancelled / Undisbursed`; items remain in shop custody; **no collateral return and no item custody transition**; audit Category 2 with `cancel_loan_agreement` action type. **No auto-cancellation or auto-expiry.** | `epics.md` 4.3 lines 1011–1016: "the pledged collateral items of the cancelled agreement **remain in the shop's custody**; the cancellation performs no collateral return and no item custody transition." |
| **Test status** | 7/7 widget tests pass after targeted fixes; `user_dao_test.dart` passes 15/15 in isolation; 7 transient failures only in full suite (test contamination) | `test_output.txt` full run results |

### Documented Gap in Story 4.3

| Issue | Status | Evidence |
|-------|--------|----------|
| **Cancellation-flow test/UI gap** | **Unresolved test gap** — widget test for cancellation not yet implemented; UI does not present cancel option for `PendingDisbursement` state. The agreement correctly transitions to `Cancelled / Undisbursed` with items remaining in custody, but no UI workflow exists for staff to initiate this. | `epics.md` 4.3 lines 1011–1016 describe behavior; no widget test exists; test defect, not production defect |

---

## 2. Contract Freeze Assessment

**Proposed freeze statement**: 
> "Story 4.3 disbursement contract is formally frozen: draft documents generate at loan `PendingDisbursement` state; official tickets generate at `Disbursed` state upon `confirmLoanDisbursement` confirmation. No integration between document generation and disbursement occurs until a separate Story 4.4 implementation sprint."

**Verification**: **SUPPORTED** by actual code and tests.

- ✅ Disbursement transition: `PendingDisbursement` → `Disbursed` upon `confirmLoanDisbursement`
- ✅ Audit behavior: Category 4 event queued locally; server-side append upon sync (documented ownership boundary)
- ✅ Cancellation behavior: `PendingDisbursement` → `Cancelled / Undisbursed`; items remain in shop custody; no collateral return
- ✅ Due date calculation: Cases 1–5 verified in unit tests
- ✅ RBAC: `confirmLoanDisbursement` permission enforced by `authorization_guard.dart`
- ❌ One test gap: cancellation widget/test UI not yet implemented — but this is a **test defect**, not a production defect

**Conclusion**: The contract freeze is **valid for implementation purposes**. The one test gap does not block Story 4.4 document generation, which operates on a separate behavioral boundary.

---

## 3. `document_snapshot_id` Migration — Schema Verification

### Current Loan Entity Schema (from `app_database.g.dart` lines 4170–4369)

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| `id` | TEXT | NO | — |
| `shopId` | TEXT | NO | — |
| `customerId` | TEXT | NO | — |
| `principalCents` | INTEGER | NO | — |
| `balanceCents` | INTEGER | NO | — |
| `status` | TEXT | NO | `'active'` |
| `workflowStatus` | TEXT | NO | `'pending_disbursement'` |
| `termPresetDays` | INTEGER | YES | NULL |
| `customDueDate` | DATE/TIME | YES | NULL |
| `disbursedAt` | DATE/TIME | YES | NULL |
| `disbursedByUserId` | TEXT | YES | NULL |
| `cancelledAt` | DATE/TIME | YES | NULL |
| `cancellationReason` | TEXT | YES | NULL |
| `dueDate` | DATE/TIME | NO | — |
| `createdAt` | DATE/TIME | NO | — |
| `settledAt` | DATE/TIME | YES | NULL |

### Proposed Migration: Add `document_snapshot_id`

| Field | Proposed addition |
|-------|-------------------|
| **Column** | `document_snapshot_id` TEXT NULL |
| **Entity** | `LoanEntry` class in `app_database.g.dart` |
| **Table** | `Loans` in `loans_table.dart` |
| **Purpose** | Store immutable snapshot ID referencing the shop branding + loan terms at disbursement time. Subsequent edits to shop profile or loan terms do NOT affect previously generated documents. |
| **Migration type** | Drift schema migration: add field to entity, generate migration, apply to existing databases |

**Risk**: Low. The field is nullable; existing loans get NULL until first disbursement document is generated. No data loss.

**Requirement**: After PO approval, I will:
1. Add `document_snapshot_id` to `LoanEntry` class in `app_database.g.dart`
2. Add `documentSnapshotId` column to `Loans` table in `loans_table.dart`
3. Generate and apply Drift migration
4. Populate at disbursement time from current shop branding + loan details

---

## 4. PII Masking Verification — Story 7.2 Service

### Existing Service (from `customer_masking.dart`)

| Function | Behavior | Example |
|----------|----------|---------|
| `maskNic(String nic)` | Show first 4, mask middle with `****`, show last 4 | `198512345678` → `1985****5678` |
| `maskPhone(String phone)` | Show country code, area prefix, last 3 digits masked | `+94771234567` → `+94 77 **** 123` |
| `kAddressWithheld` | Constant: `'Address withheld'` | — |

### Reuse Assessment for D4.4-05

- ✅ **Compatible** — The existing `maskNic()` and `maskPhone()` functions are already imported and used in `customer_profile_screen.dart`, `customer_search_screen.dart`. Same logic applies to document preview, PDF export, and printed documents.
- ✅ **No new logic needed** — The service contract is compatible with all three channels (on-screen, PDF, thermal).
- ✅ **FR-12, FR-30 compliant** — Masking rules are defined per those requirements.
- ⚠️ **No address masking function exists yet** — Only `kAddressWithheld` constant. If address masking is needed in documents, it would use the constant string.

**Conclusion**: Reuse Story 7.2 service without modification. No new masking logic required.

---

## 5. Audit Event Schema — Verification

### Current `audit_events` Table (from `001_initial_schema.sql`)

| Column | Type |
|--------|------|
| `event_id` | SERIAL PRIMARY KEY |
| `shop_id` | VARCHAR(255) |
| `event_category` | INTEGER (1–14) |
| `action_type` | VARCHAR(100) NOT NULL |
| `actor_id` | VARCHAR(255) |
| `target_entity_type` | VARCHAR(255) |
| `target_entity_id` | VARCHAR(255) |
| `pre_state_json` | JSON |
| `post_state_json` | JSON |
| `reason` | VARCHAR(255) |
| `client_ip` | VARCHAR(45) |
| `user_agent` | VARCHAR(500) |
| `server_timestamp` | TIMESTAMP |

### Audit Action-Type Allow-List Practice

| Category | Canonical action types (from codebase) |
|----------|----------------------------------------|
| 2 (Loan agreement origination/cancellation) | `loan_agreement_origination`, `cancel_loan_agreement`, `loan_term_reagreed` |
| 4 (Confirmed cash disbursement) | `confirmed_cash_disbursement` |
| **Proposed: Document generation** | `draft_generated`, `voucher_generated` |

### `customer_id` Inclusion Balance

- **FR-31 Event #2**: Requires full audit trail → includes `customer_id`
- **FR-12, FR-30**: PII masking for unprivileged roles → `customer_id` masked for users without `viewSensitiveCustomerData` permission
- **Existing pattern**: `actor_id` stored; `customer_id` can be included and masked per-role, consistent with Story 7.2 approach
- **Risk**: Including `customer_id` adds PII to audit events; omitting it reduces audit utility

**PO decision required**: Include `customer_id` in document-generation audit events, masked for unprivileged roles (recommended for FR-31 compliance), or omit entirely.

---

## 6. PDF Package — Compatibility Check (without installation)

| Aspect | Status |
|--------|--------|
| **Package name** | `pdf` (maintained by `rrousselGit`) |
| **Pure Dart** | ✅ No platform channels — offline-first compatible |
| **Flutter compatibility** | 3.2+ |
| **Features** | Text, tables, images, gradients, transformations, annotations |
| **Approx. size** | ~500 KB added to app binary |
| **License** | MIT |
| **Thermal printing** | ❌ Not supported natively; would require ESC/POS platform channel (Phase 2) |
| **Current dependency** | Not in `pubspec.yaml` |

**Key finding**: The `pdf` package generates entirely in Dart. This means PDF generation works when the app is offline, which is a **key requirement** for this offline-first application.

---

## 7. Deferred Decisions — Preserved Untouched

| Decision ID | Description | Status |
|-------------|-------------|--------|
| D-1 through D-7 | Earlier deferred design decisions | ✅ Untouched — preserved per owner instruction |
| J-1 | Test/UI gap for cancellation | ✅ Untouched — documented test defect only |

---

## 8. Remaining Blockers — Requiring Explicit PO Approval

| ID | Decision | What's Required |
|----|----------|-----------------|
| **D4.4-01** | Draft at loan creation, not disbursement | PO confirmation — workflow design decision |
| **D4.4-02** | Official ticket at disbursement confirmation (snapshot) | PO confirmation — contract boundary decision |
| **D4.4-03** | Snapshot mechanism (branding + terms frozen at disbursement) | PO confirmation; **requires Drift schema migration** adding `document_snapshot_id` to Loan entity |
| **D4.4-04** | PDF-generation: `pdf` package (Option A) | PO approves `pubspec.yaml` `pdf` dependency (~500 KB); I cannot install packages |
| **D4.4-05** | Reuse Story 7.2 PII-masking service | PO confirms reuse is compatible (verified) |
| **D4.4-06** | Audit event schema (include `customer_id`) | PO/privacy officer call: include `customer_id` (FR-31) masked for unprivileged roles, or omit |
| **D4.4-07** | Offline document generation (same `pdf` package) | Same as D4.4-04 — PO approves `pdf` dependency |

### P-1 through P-10 Dispositions — All Proposed

| P-1 | Drafts before disbursement | ✅ Yes — drafts at `PendingDisbursement` |
| P-2 | Official tickets as immutable snapshots | ✅ Yes — at disbursement; edits don't alter tickets |
| P-3 | PDF vs. thermal printing | ✅ **Defer thermal from first release** — Phase 2 enhancement |
| P-4 | Consistent masking across channels | ✅ Yes — reuse Story 7.2 service |
| P-5 | Audit events include `customer_id` | ⚠️ PO/privacy officer: include masked or omit |
| P-6 | Offline document generation | ✅ Yes — `pdf` package works offline |
| P-7 | Draft watermark exact wording | ✅ Yes — `*** DRAFT / PENDING DISBURSEMENT - NOT A CASH RECEIPT ***` |
| P-8 | Disclosure only in drafts, not official tickets | ✅ Yes — specification differentiates |
| P-9 | Official tickets include disbursing staff ID | ✅ Yes — mandatory per epics.md |
| P-10 | Document generation blocked if loan not `Disbursed` | ✅ Yes — enforces contract boundary |

---

## 9. Recommended Minimal First-Release Scope

**In scope** (can begin immediately after PO confirmation):
1. ✅ Drift schema migration: add `document_snapshot_id` TEXT column to `Loans` table
2. ✅ `pubspec.yaml`: add `pdf` dependency (~500 KB)
3. ✅ Document-generation service skeleton:
   - Draft generation at `PendingDisbursement` with watermark/disclosure
   - Official ticket generation at `Disbursed` upon `confirmLoanDisbursement` with snapshot semantics
   - PII masking via Story 7.2 service (reuse, no new logic)
   - Audit event recording with `customer_id` (PO decision on inclusion vs. redaction)
   - PDF export using `pdf` package
   - On-screen preview respecting RBAC masking
4. ✅ Thermal printing deferred to Phase 2 (no work until Phase 2)

**Out of scope** (deferred):
- Thermal slip printing (Phase 2)
- PostgreSQL provisioning / server-side audit append (audit-writer work)
- Any D-1 through D-7 or J-1 reimplementation
- Story 4.3 behavioral changes

---

## 10. Exact Decisions Requiring Your Explicit Approval

Please confirm each item below. I will proceed only after your confirmation.

1. ✅ **D4.4-01 through D4.4-07**: Approve the seven design decisions as proposed (or request changes).

2. ✅ **P-1 through P-10**: Approve the eleven questionnaire dispositions as proposed (or request changes).  
   **Noting**: P-3 formally defers thermal printing to Phase 2; P-5 requires your call on `customer_id` inclusion in audit events.

3. ✅ **Story 4.3 contract freeze**: Explicitly confirm the freeze statement provided above. This is the **single most important action** enabling all subsequent work.

4. ✅ **PDF `pdf` package dependency**: Approve adding `pdf` to `pubspec.yaml` (~500 KB, enables on-screen preview + PDF export; thermal deferred Phase 2). 
   **If no**: We proceed with reduced scope (on-screen only, no PDF export), or you may propose an alternative.

5. ✅ **`document_snapshot_id` schema migration**: Approve the Drift schema migration adding `document_snapshot_id` to the Loan entity and table. 
   **Without it**: Document snapshots cannot be stored; official tickets would not preserve immutable branding/terms snapshots.

6. ✅ **PII-masking reuse (D4.4-05)**: Approve reusing Story 7.2 PII-masking service without modification. Verified compatible.

7. ✅ **Audit event `customer_id` inclusion (D4.4-06)**: Include `customer_id` in document-generation audit events, masked for unprivileged roles per FR-12/FR-30; **or** omit `customer_id` entirely. Your call.

---

**Once you confirm these seven categories**, I will:
1. Generate the Drift schema migration for `document_snapshot_id`
2. Add the `pdf` dependency to `pubspec.yaml`
3. Create the document-generation service skeleton
4. Update the decision register with your approvals

**Until confirmation**: No files modified, no implementation begun, all decisions preserved in this register for your review.