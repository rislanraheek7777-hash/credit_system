---
title: Sprint Change Proposal — Standalone Backend for Staff Credential Recovery
date: 2026-11-25
project: credit_system
trigger: Four review passes proved the client-hosted Dart OTP server cannot satisfy the security boundary FR-34 requires
status: approved 2026-11-25 by Raheek
scope_classification: Major
mode: incremental
requested_by: Raheek
---

# Sprint Change Proposal — Standalone Backend for Staff Credential Recovery

## 1. Issue Summary

**Trigger:** Story 1.10 was implemented with the OTP "server" hosted as a Dart component inside the Flutter client. Four independent review passes over three loopbacks each found new spec-level security defects: no bearer authentication on `/deliver` or `/verify`, server verification without attempt counting or Category 14 audit, a `deliveryReference` field validated then ignored, privileged DDL (`BYPASSRLS` role, constraints, functions) applied from `main()` on every client launch, duplicated SQL with only a parity test as guard, and pgTAP fixtures that would fail in CI. The code passed `flutter analyze` and 173 tests, but the security boundary was not proven.

**Issue type:** Failed approach requiring a different solution; architecture decision AD-9 is the root cause.

**Evidence:**
- `spec-1-10-secure-staff-credential-recovery.md` — Review Triage Logs, passes 1–4 (60+ findings, four consecutive loopbacks).
- `ARCHITECTURE-SPINE.md` AD-9 (pre-amendment) — placed the gateway adapter in `features/auth/data/` and described "the server" without defining a deployment boundary.
- `main.dart` — applied migration 003 via `applyServerMigrationsIfConfigured()` at startup, requiring privileged client credentials.
- `server/otp_delivery_server.dart` — in-client component holding pepper, generating codes, and exposing unauthenticated routes.
- Human decision 2026-11-25: redesign as a standalone backend service instead of a fourth loopback.

**Problem statement:** A client-hosted component cannot be a security boundary. Secrets, privileged DB roles, DDL execution, and abuse throttling must live in a separately deployed service with its own least-privilege role and test suite.

## 2. Impact Analysis

### 2.1 Epic impact
- **Epic 1 remains `in-progress`.** Story 1.10 is amended (no client-hosted server, no timing-equality requirement, backend-bound references); **new Story 1.11** added for the standalone backend service, status `backlog`.
- **Epics 2–8 unaffected.** No resequencing; no new epic needed (Epic 1 owns staff accounts and `features/auth`).
- Precedent: Story 5.6 and Story 1.10 were both added via change proposals into existing epics.

### 2.2 Story impact
| Story | Impact |
|---|---|
| 1.10 | Amended: backend resolves identity; body/status equivalence only; signed single-use reference auth; server-side attempt/abuse control; client holds no secrets/DDL. |
| 1.11 | New: standalone backend deployment, env-only secrets, least-privilege DB role, DBA/CI migration, own API and real-PostgreSQL tests. |
| 1.8 | Session revocation contract reused unchanged. |
| 1.7 / 1.9 | Owner-initiated credential enrollment and no-break-glass rule unchanged. |
| 7.4 | Backend API contract tests and 003 real-SQL tests join the CI merge gate. |

### 2.3 Artifact conflicts
| Artifact | Conflict / change |
|---|---|
| PRD FR-34 | "Server-authoritative" was ambiguous about deployment; now explicitly requires a separately deployed backend service and forbids client-held secrets/DDL. |
| Architecture AD-9 | Rewritten from a client adapter to the standalone-backend decision; client is a thin HTTP caller. |
| `epics.md` | Story 1.10 amendments, Story 1.11, Epic 1 summaries, testing guidance. |
| `sprint-status.yaml` | Story 1.11 backlog, action item, `last_updated`. |
| `deferred-work.md` | Prior entry marked RESOLVED by this proposal. |
| UX | No change — same two-step dialog and username-only login with tenant picker. |
| Paused spec | `spec-1-10-secure-staff-credential-recovery.md` stays `in-review`/PAUSED; its frozen intent and passing tests are inputs to the new build. |

### 2.4 Technical impact
- The client-hosted server code (`server/`, migration bootstrap in `main()`) must be **removed**, not layered over.
- Backend becomes a separately deployable unit: OS-env secrets, least-privilege PostgreSQL role, signed challenge-bound reference, server-side rate limiting and attempt counting, one Category 14 per abuse/failure.
- Migration 003 applied by DBA/CI only; client role has no DDL or `BYPASSRLS`.
- No new permission, no 15th audit category, no change to money, tenant isolation, or receipt rules.

## 3. Recommended Approach

**Option 1 — Direct Adjustment (selected).** Amend AD-9, FR-34, Story 1.10, add Story 1.11, and route implementation through a fresh `bmad-build`.

Alternatives considered:
- **Option 2 — Rollback:** revert all Story 1.10 code and re-plan from scratch. Rejected: the frozen intent, UI, tests, and much of the SQL remain valid; a fourth loopback already proved incremental patching of the wrong architecture does not converge.
- **Option 3 — MVP review:** not applicable; this is post-MVP security hardening.
- **Hybrid:** not needed.

**Rationale:** Keeps proven work (client dialog, session revocation, Categories 12/14, idempotency model) while moving only the security boundary to a deployable service.

**Effort:** High. **Risk:** Medium–High (new deployable, provider cost, DBA-run migration). **Timeline impact:** one new story + rework of 1.10; no epic resequencing.

## 4. Detailed Change Proposals

All proposals were presented individually in Incremental mode and approved by Raheek on 2026-11-25.

| # | Artifact | Change | Status |
|---|---|---|---|
| 1 | `ARCHITECTURE-SPINE.md` AD-9 | Rewritten: standalone backend owns OTP generation, secrets, challenge lifecycle, verification and audit; client is thin HTTP caller; DBA/CI applies 003; no client DDL/`BYPASSRLS` | Applied |
| 2 | `prd.md` FR-34 | Consequences now require backend-stored operation/idempotency keys, backend-only secrets and verification, signed single-use reference, server-side throttling; Out of Scope forbids client-hosted delivery and client DDL | Applied |
| 3 | `epics.md` | Story 1.10 ACs amended (backend identity resolution, body/status equivalence, signed reference, no client secrets/DDL), Story 1.11 added, Epic 1 summaries and testing guidance updated | Applied |
| 4 | `sprint-status.yaml` / `deferred-work.md` | Story 1.11 backlog, redesign action item, prior deferred entry marked RESOLVED | Applied |
| 5 | This document | Sprint Change Proposal written to `sprint-change-proposal-2026-11-25-backend-redesign.md` | Applied |

`DESIGN.md` and `EXPERIENCE.md` intentionally unchanged — the user-facing flow is unchanged.

## 5. Implementation Handoff

**Scope classification: Major.** APM/Architect involvement is required for the new deployment unit, provider/cost decisions, and the DBA migration path.

**Handoff:**
1. **Product Manager + Solution Architect** — approve backend deployment model, provider/cost, OS-env configuration contract, least-privilege role, and DBA/CI migration procedure.
2. **Developer (`bmad-build`, fresh session)** — implement **Story 1.11** first (backend service, 003 deployment, API contract, real-SQL tests), then rework **Story 1.10** client code to a thin HTTP caller and remove the client-hosted server and migration bootstrap.
3. **QA / Security** — wire backend API contract tests and 003 real-PostgreSQL assertions into the CI gate; verify no secrets or DDL capability remain in the client.

**Success criteria:**
- Backend is separately deployable; all secrets from OS env; least-privilege DB role; no client DDL or `BYPASSRLS`.
- Uniform unauthenticated body/status; signed single-use reference auth; server-side attempt/throttle control with exactly one Category 14 per failure.
- `flutter analyze` clean; unit, widget, backend API contract, and real-PostgreSQL suites green in CI.
- No 15th permission or audit category; all sessions revoked on successful reset; no client-hosted OTP code remains.
- Stories 1.11 and 1.10 reach `done` only through the normal build/review flow.

**Note:** The paused spec and its passing tests remain as design evidence; do not resume implementation from it directly.
