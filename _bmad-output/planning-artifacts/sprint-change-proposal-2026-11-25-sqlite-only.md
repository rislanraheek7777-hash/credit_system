---
title: Sprint Change Proposal — SQLite-Only Single-Device Architecture Pivot
date: 2026-11-25
project: credit_system
trigger: User confirmed the deployment is SQLite-only with no PostgreSQL, invalidating the dual-tier architecture and every server-based recovery artifact
status: approved 2026-11-25 by Raheek
scope_classification: Major
mode: incremental
requested_by: Raheek
---

# Sprint Change Proposal — SQLite-Only Single-Device Pivot

## 1. Issue Summary

**Trigger:** After Story 1.11 was built as a standalone PostgreSQL-backed recovery service, the user confirmed: **"I use SQLite"** — no PostgreSQL, no server, single device, one SQLite database with a `shop_id` column.

**Issue type:** Strategic pivot / misunderstanding of the original deployment requirements. The planning artifacts describe PostgreSQL as source of truth (AD-1), RLS tenant isolation, server-side audit writer, cloud backup/PITR, and a standalone backend (AD-9) — none of which exist in the actual deployment.

**Evidence:**
- `ARCHITECTURE-SPINE.md` AD-1 — dual-tier Drift + PostgreSQL with RLS and sync states.
- `ARCHITECTURE-SPINE.md` AD-9 — standalone backend with `DATABASE_URL` and DB-backed challenges.
- `backend/` package and `003_credential_recovery.sql` — server code that cannot run in the deployment.
- User decisions 2026-11-25: in-app recovery, one DB with `shop_id`, single device, no cross-device sync.

**Problem statement:** The documented architecture and the recovery implementation target infrastructure the user does not have. Continuing would ship code that cannot start. The fix is a formal pivot to application-enforced isolation and in-app SQLite recovery.

## 2. Impact Analysis

### 2.1 Epic impact
- **Epic 1 is fundamentally re-scoped:** Stories 1.2, 1.3, 1.4, 1.5, 1.9 amended; **Story 1.11 removed**; Story 1.10 re-scoped in-app.
- **Epic 7** backup/DR story follows FR-32's local file backup model; pgTAP/PostgreSQL gates removed.
- **Epics 2–8** business logic unchanged; verification gates move from PostgreSQL integration to Drift SQLite tests.

### 2.2 Story impact
| Story | Impact |
|---|---|
| 1.2 | SQLite sole authority; dual-tier/sync ACs void. |
| 1.3 | RLS → repository guards; server audit writer → SQLite triggers. |
| 1.4 | Cloud backup/WAL → local file export + `PRAGMA integrity_check`. |
| 1.5 | CI: analyze + unit + Drift SQLite integration; no PostgreSQL service. |
| 1.9 | Platform-admin default-deny enforced in app code. |
| 1.10 | In-app SQLite recovery; app-held secrets accepted. |
| 1.11 | Removed (tombstone). |

### 2.3 Artifact conflicts
| Artifact | Conflict / change |
|---|---|
| `ARCHITECTURE-SPINE.md` | AD-1 rewritten (SQLite-only, app-enforced isolation), AD-6 dual-layer rule replaced, AD-9 rewritten (in-app recovery). |
| `prd.md` | FR-4, FR-32, FR-33, FR-34 rewritten for application-layer guarantees and local backup. |
| `epics.md` | Amendments to Stories 1.2–1.5, 1.9, 1.10; Story 1.11 tombstone; Epic 1 summaries. |
| `sprint-status.yaml` | Story 1.11 removed, pivot action item. |
| `deferred-work.md` | Backend/PostgreSQL work marked superseded. |
| UX | Unchanged — two-step dialog and username-only login with tenant picker remain. |

### 2.4 Technical impact
- Remove the standalone backend package, `DATABASE_URL`, `cs_*` SQL functions, RLS policies, pgTAP gate, and WAL/PITR narrative from active plans.
- Tenant isolation becomes a Dart repository guard: every query applies the authenticated `shop_id`; missing predicates are cross-tenant leaks, so repository tests are mandatory.
- Audit immutability via SQLite `BEFORE UPDATE/DELETE ... RAISE(ABORT)` triggers.
- Recovery: `credential_recovery_challenges` in Drift SQLite, idempotency via `UNIQUE`, single transaction for hash rotation + `session_version` + audit. App-held provider secrets are an accepted single-device risk.
- Backups: user-initiated SQLite file export with integrity verification.

## 3. Recommended Approach

**Option 1 — Direct Adjustment (selected).** Amend the planning artifacts to the SQLite-only reality and re-implement Story 1.10 in-app; remove Story 1.11.

Alternatives considered:
- **Option 2 — Rollback:** revert all recovery work. Rejected: the audit-trigger, idempotency, dialog, and tenant-guard work remains valuable and can be adapted.
- **Option 3 — MVP review:** not applicable; this aligns the plan with the actual deployment.

**Rationale:** Keeps the user-visible behavior and most domain rules while replacing only the infrastructure assumptions.

**Effort:** High. **Risk:** High — application-layer isolation has no engine-level backstop; every repository query must be tested. **Timeline impact:** one story re-scoped, one removed; no epic resequencing.

## 4. Detailed Change Proposals

All proposals presented individually in Incremental mode and approved by Raheek on 2026-11-25.

| # | Artifact | Change | Status |
|---|---|---|---|
| 1 | `ARCHITECTURE-SPINE.md` AD-1 | Rewritten to single-device SQLite with application-enforced tenant isolation | Applied |
| 2 | `ARCHITECTURE-SPINE.md` AD-6/AD-9 | Dual-layer rule → application guards; AD-9 → in-app SQLite recovery | Applied |
| 3 | `prd.md` | FR-4, FR-32, FR-33, FR-34 rewritten for app-layer isolation, local backup, in-app recovery | Applied |
| 4 | `epics.md` | Stories 1.2–1.5/1.9/1.10 amended, Story 1.11 tombstoned, Epic 1 summaries updated | Applied |
| 5 | `sprint-status.yaml` / `deferred-work.md` / this document | Story 1.11 removed, pivot action item, superseded work logged | Applied |

## 5. Implementation Handoff

**Scope classification: Major.** PM/Architect sign-off required for the loss of engine-level isolation and client-held secrets.

**Handoff:**
1. **Solution Architect** — approve the application-layer tenant guard pattern and SQLite audit triggers; define the repository-level guard API so no query can omit `shop_id`.
2. **Developer (`bmad-build`)** — re-implement Story 1.10 in-app against Drift SQLite; remove the backend package and PostgreSQL artifacts from the active build; add SQLite integration tests for tenant isolation, idempotency, audit immutability, and recovery.
3. **QA/Security** — ensure CI has no PostgreSQL dependency and that cross-tenant repository tests are a merge gate.

**Success criteria:**
- No PostgreSQL, `DATABASE_URL`, RLS, pgTAP, or backend service in active code/planning.
- Every tenant repository query is shop-scoped and verified by automated cross-tenant tests.
- Audit rows are immutable via SQLite trigger; no credential values logged.
- Recovery stores hashed OTP in SQLite, enforces idempotency with `UNIQUE`, rotates hash + `session_version` atomically, and emits Category 12/14.
- `flutter analyze` clean; unit + widget + Drift SQLite integration suites green in CI.
