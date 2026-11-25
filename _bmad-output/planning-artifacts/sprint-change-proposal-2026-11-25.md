---
title: Sprint Change Proposal — Secure Staff Credential Recovery (Forgot Username / Password)
date: 2026-11-25
project: credit_system
trigger: The shipped "Forgot username or password?" flow is a local-only, insecure password reset that bypasses PostgreSQL authority, tenant isolation, audit, and session revocation
status: approved 2026-11-25 by Raheek
scope_classification: Major
mode: incremental
requested_by: Raheek
---

# Sprint Change Proposal — Secure Staff Credential Recovery

## 1. Issue Summary

**Trigger:** The login screen already ships a "Forgot username or password?" control (`lib/features/auth/presentation/login_screen.dart:448-449`) wired to `_showForgotCredentialsDialog` (lines 77–152). The user asked to replace it with a proper, secure account-recovery feature.

**Issue type:** Failed approach requiring a different solution + new requirement emerged from stakeholders.

**Evidence:**

| Location | Current behavior |
|---|---|
| `login_screen.dart:78,123` | Depends only on local `UserDao`; resolves the shop owner via `_userDao!.getUsersByShopId(shopId)` — a **client-supplied Shop ID** |
| `login_screen.dart:128-129` | Hashes a new password locally and writes it to **Drift SQLite only** — no PostgreSQL call, no server acknowledgement |
| `login_screen.dart:135` | Displays `Password reset. Username: ${owner.username}` — discloses a username to an **unauthenticated** caller |
| `login_screen.dart:448-449` | Public entry point on the login screen; no verification, no rate limit, no audit event |
| `PRD FR-5:221` | Explicitly out of scope: "Self-service public registration for staff members (all staff creation is owner-initiated)" |
| `ARCHITECTURE-SPINE.md:516` | SMS/WhatsApp gateway explicitly deferred post-V1 |
| `stitch-prompt.md:66` | "no SMS/WhatsApp, no third-party integrations … in V1" |
| `deferred-work.md:13-15` | `app_users` unique keys only cover `{shopId, username}`; global login lookup can attribute a login to the wrong shop |
| `PRD:628-653` / `ARCHITECTURE-SPINE.md:307-357` | Audit trail is append-only and server-authoritative; no credential values may be logged |

**Problem statement:** Any person who knows a Shop ID can overwrite the Shop Owner's password in the local cache and learn their username. The change never reaches PostgreSQL (the source of truth), so it is not a real recovery, and it violates tenant-isolation, audit, and session-revocation contracts. A compliant replacement needs server-side identity verification, a single-use out-of-band challenge, and atomic credential reset with revocation.

**Decisions made in this session (Raheek, 2026-11-25):**
1. Verification channel: **email/SMS OTP gateway** — deliberately reverses the post-V1 deferral and V1 third-party exclusion.
2. Initiator: **any staff member, self-service**, for their own account only.
3. Workflow mode: **Incremental**; all seven edit proposals were reviewed individually and approved.

## 2. Impact Analysis

### 2.1 Epic impact
- **Epic 1 reopened** (`done` → `in-progress`) in `sprint-status.yaml`; new **Story 1.10** added with status `backlog`.
- **Epics 2–8 unaffected.** No resequencing, no epic becomes obsolete, no new epic needed. Epic 1 already owns staff accounts (FR-5), the permission catalog (FR-6), tenant isolation (FR-4), authentication (Story 1.8), and `features/auth` (AD-4).
- Precedent: Epic 5 was reopened for Story 5.6 by the 2026-11-17 change proposal.

### 2.2 Story impact
- **New: Story 1.10 — Secure Staff Credential Recovery (Forgot Username / Password)**, with 7 acceptance criteria, traceability, dependencies, and testing guidance.
- **Story 1.8** — its `session_version` revocation contract and offline prohibition on staff administration are reused, not changed.
- **Story 1.7** — owns initial credential issuance; becomes the place where verified contact channels must be registered.
- **Story 7.4** — CI gates extended with recovery-specific security tests.
- **Story 1.9** — "no unapproved break-glass bypasses" remains in force; no admin escape hatch is introduced.

### 2.3 Artifact conflicts
| Artifact | Conflict / change required |
|---|---|
| PRD | No recovery requirement existed; FR-5 L221 excluded self-service. Amended FR-5; added FR-34; added traceability row. |
| Architecture | No AD covered password/recovery; gateway deferred. Amended deferred item 2; added AD-9. |
| UX `EXPERIENCE.md` | Login surface had no recovery entry or flow. Added IA row, component pattern, state, and key flow 0. `DESIGN.md` unchanged (existing tokens suffice). |
| UX `stitch-prompt.md` | V1 exclusion contradicted the approved OTP decision. Amended line 66 with a narrow exception. |
| `epics.md` | Epic 1 summary/architecture/FR list, FR coverage map, Story 7.4 testing guidance. |
| `sprint-status.yaml` | Epic reopened, story added, action item, date bumped. |
| `deferred-work.md` | Login-identifier collision promoted to a blocking dependency for Story 1.10. |

### 2.4 Technical impact
- **No new permission** — the catalog is frozen at 14. **No fifteenth audit category** — reuse Category 12 (`credential_recovery_requested`, `credential_password_reset`) and Category 14 (failure/abuse).
- **New server table** `credential_recovery_challenges` (immutable `tenant_id`, target `user_id`, OTP hash, channel, TTL, attempt counter, one-time-use marker, `client_operation_id`, `idempotency_key`) with unique constraints.
- **New OTP gateway adapter** behind a domain interface in `features/auth/data/`; provider and cost are open PM/Architect decisions.
- **Password reset moves server-side**; the local Drift `app_users` write path in the legacy dialog is removed. Reset atomically increments `session_version`, revoking all sessions.
- **Offline:** recovery is a high-risk administrative action and is blocked while offline (AD-6 rule 8 / Story 1.8 AC5).
- **Identity resolution:** `deferred-work.md` collision must be closed — enforce unique `(shop_id, email)` / `(shop_id, phone)` in Drift and PostgreSQL and replace global lookup with tenant-scoped resolution.
- **No credential values** in audit records or logs; generic, non-enumerating responses at every unauthenticated step.

## 3. Recommended Approach

**Option 1 — Direct Adjustment (selected).** Add Story 1.10 to reopened Epic 1 and amend PRD, architecture, UX, epics, sprint status, and deferred work within the existing plan. No milestone resequencing.

Alternatives considered:
- **Option 2 — Rollback:** not viable. Nothing is reverted; the legacy dialog is additive and simply removed/replaced.
- **Option 3 — MVP review:** not applicable. MVP shipped; this is post-MVP security hardening plus a deliberate V1 scope expansion for OTP.
- **Hybrid:** not needed.

**Rationale:** Reuses proven contracts — Story 1.8 `session_version` revocation, FR-31 Categories 12/14, AD-1 idempotency/acknowledgement — and keeps the blast radius in `features/auth`. The only genuinely new capability is the narrow OTP gateway.

**Effort:** Medium–High. **Risk:** Medium (external provider dependency, PII handling, identity-collision prerequisite). **Timeline impact:** one story, no epic resequencing; release gated on provider/cost decision.

## 4. Detailed Change Proposals

All proposals were presented individually in Incremental mode and approved by Raheek on 2026-11-25.

| # | Artifact | Change | Status |
|---|---|---|---|
| 1 | `prd.md` FR-5 | Self-service *recovery* carved out of the registration exclusion; audit note added | Applied |
| 1 | `prd.md` FR-34 | New requirement: server-authoritative single-use OTP recovery, generic responses, tenant-safe lookup, session revocation, offline block, Categories 12/14, no new permission | Applied |
| 1 | `prd.md` §5 | Traceability row for FR-34 | Applied |
| 2 | `ARCHITECTURE-SPINE.md` deferred item 2 | Narrow transactional OTP path adopted for V1; bulk/marketing gateways remain deferred | Applied |
| 2 | `ARCHITECTURE-SPINE.md` AD-9 | New decision: gateway adapter, server-only flow, `credential_recovery_challenges` table, generic errors, atomic revocation, audit reuse, UI replacement | Applied |
| 3 | `EXPERIENCE.md` | Credential Recovery IA row, component pattern, state pattern, key flow 0 | Applied |
| 4 | `epics.md` | Epic 1 summary (both occurrences) + FR-34 + AD-9; FR coverage map row; new Story 1.10; Story 7.4 recovery CI gates | Applied |
| 5 | `sprint-status.yaml` | `epic-1: in-progress`; `1-10-…: backlog`; action item; `last_updated` bumped | Applied |
| 6 | `deferred-work.md` | Login-identifier collision marked as blocking dependency with concrete resolution | Applied |
| 6 | `stitch-prompt.md` | V1 exclusion amended with narrow FR-34/AD-9 exception | Applied |
| 7 | This document | Sprint Change Proposal written to `{planning_artifacts}/sprint-change-proposal-2026-11-25.md` | Applied |

`DESIGN.md` intentionally unchanged — existing input/button/dialog tokens and danger semantics cover the flow.

## 5. Implementation Handoff

**Scope classification: Major.** The approved OTP decision introduces a new external dependency, reverses two explicit V1 exclusions, and requires a provider/cost decision. PM/Architect involvement is required before Developer implementation.

**Handoff:**
1. **Product Manager + Solution Architect** — decide OTP channel (email vs SMS), provider, cost envelope, OTP TTL, failed-attempt threshold, and rate-limit values; define how a verified contact channel is enrolled for existing staff accounts that lack one; confirm the FR-5/FR-34 scope amendment and AD-9.
2. **Developer (`bmad-build`)** — implement Story 1.10: close the login-identifier collision first; add the PostgreSQL `credential_recovery_challenges` migration with RLS and unique constraints; implement OTP gateway adapter and server-authoritative request/confirm endpoints with idempotency, generic responses, rate limiting, and audit appends; replace `_showForgotCredentialsDialog` with the two-step flow; add unit/widget/real-PostgreSQL integration tests.
3. **QA / Security** — add the recovery gates to Story 7.4 CI suite; verify zero credential values in logs/audit and 100% cross-tenant rejection.

**Success criteria:**
- All 7 Story 1.10 acceptance criteria pass.
- `flutter analyze` clean (zero lints); full unit, widget, and real-PostgreSQL integration suites green.
- Generic-response equality for matched vs unmatched identifiers; OTP single-use/expiry/threshold; idempotent re-transmission; immediate session revocation; Category 12/14 audit appends; no credential values in logs.
- No 15th permission, no 15th audit category, no local password write, no offline recovery.
- `sprint-status.yaml` story `1-10-…` reaches `done` only through the normal build/review flow.

**Sequencing note:** Story 1.10 is a governance/security addition to Epic 1, not on the transaction-loop critical path. It must not block Epic 2–8 work already `done`.
