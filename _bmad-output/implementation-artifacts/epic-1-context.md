# Epic 1 Context: Shop Administration, Staff RBAC & Secure Multi-Tenant Workspace

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Establish the Day-1 security and infrastructure foundation every later epic builds on: shop profile and branding with `Asia/Colombo` timezone and configurable currency display, owner-managed staff accounts with a fixed 14-permission RBAC catalog, immediate server-enforced session revocation, strict cross-tenant isolation via PostgreSQL RLS, an immutable append-only audit trail, continuous WAL/PITR backup provisioning, an automated CI verification pipeline, and self-service staff credential recovery delivered by a separately deployed backend service (Stories 1.10, 1.11).

## Stories

- Story 1.1: Immutable Money Value Object & Monetary Precision Foundations
- Story 1.2: Dual-Tier Relational Database Foundations & Migration Harness
- Story 1.3: Server-Enforced PostgreSQL Tenant Isolation & Append-Only Audit Trigger
- Story 1.4: Cloud Backup, Continuous WAL Archiving & Restore-Drill Harness
- Story 1.5: Automated Security, Multi-Tenant & Integrity CI Verification Pipeline
- Story 1.6: Shop Profile Configuration, Timezone & Currency Display Preferences
- Story 1.7: Counter Staff Administration & 14-Permission RBAC Configuration
- Story 1.8: Staff Authentication, Session Management & Server-Enforced Revocation
- Story 1.9: Platform Administrator Governance & Cross-Tenant Access Restrictions
- Story 1.10: Secure Staff Credential Recovery (Forgot Username / Password)
- Story 1.11: Standalone Credential Recovery Backend Service

## Requirements & Constraints

- **Money precision:** All amounts are integer minor units (100 cents = 1 LKR); Dart `double` is prohibited for money in domain/data/presentation. Parse at most two decimals; format `Rs. 1,500.50`; persist as SQLite `INTEGER` / PostgreSQL `BIGINT`; cross-currency math throws. Base ledger currency locks once any financial transaction exists; display formatting stays decoupled.
- **Shop config:** Timezone defaults to `Asia/Colombo`, validated against IANA identifiers, and governs all due-date/midnight calculations. Currency display defaults to `LKR`. Profile/branding updates affect future receipts only — historical snapshots never change. Administrative changes append an Category 14 audit event with pre/post diff.
- **RBAC & staff:** The 14-permission catalog is fixed and unmodifiable. Only the Shop Owner may create/deactivate staff, change permissions, or perform other administrative actions; non-owner calls are rejected `403`. Staff changes append a Category 12 event. Platform administrators are default-denied customer/ledger PII, no break-glass bypass, and blocked attempts append a Category 14 security event.
- **Auth & sessions:** JWT carries `user_id`, `shop_id`, `session_version`. Every protected request checks `session_version` against PostgreSQL; deactivation increments it and appends Category 12. Revoked/deactivated users get `401` on the next request and the client locks/clears the session. Offline, only safe queued counter operations are allowed; staff administration, permission changes, and reversals/corrections require online authorization. Remote revocation cannot reach a disconnected terminal until reconnection.
- **Tenant isolation:** `shop_id` derives strictly from verified JWT claims; client-supplied tenant IDs are ignored. RLS is enabled and `FORCE`d on all tables (`shop_id = current_setting('app.current_shop_id')`), app role has `NOBYPASSRLS`, context set via `SET LOCAL`. Zero cross-tenant leakage is a hard gate.
- **Audit:** Append-only; a `BEFORE UPDATE OR DELETE` trigger unconditionally rejects modifications; no credential values ever logged; no 15th audit category or 16th permission.
- **Backup/DR:** Continuous WAL archiving/PITR, encrypted versioned object storage; RPO ≤ 15 min, RTO ≤ 4 h. DR status is `UNVERIFIED` until a documented drill proves both metrics with zero corruption.
- **CI gates:** Mandatory merge pipeline (lint, unit, PostgreSQL integration, boundary attacks). Lint fails on `double` for money; 100% rejection of cross-tenant access and 100% denial across all 14 RBAC toggles required.
- **Credential recovery (FR-34):** Single-use, hashed, short-TTL OTP; identical generic body/status for matched vs unmatched identifiers (no account/channel/shop disclosure); `client_operation_id`/idempotency key returns the stored challenge on re-transmission; signed short-lived single-use challenge-bound reference; server-side five-attempt cap and throttling; success atomically updates password hash and `session_version` (revoking sessions) as `ConfirmedByServer`; blocked offline; Category 12 (`credential_recovery_requested`, `credential_password_reset`) / Category 14 (failure/abuse), one per path. Self-service is own-account only; no new permission or category.

## Technical Decisions

- Feature-first Clean Architecture: `core/` + nine vertical slices (`auth`, `shop`, `customers`, `collateral`, `credits`, `payments`, `overdue`, `reports`, `audit`); inward dependency rule — pure-Dart `domain/` ← `data/` and `presentation/`. Modules used here: `features/shop`, `features/auth`, `core/money`, `core/permissions`, `core/sync`, `core/database`.
- Dual-tier persistence: local Drift SQLite (sandboxed app storage / OPFS on web) for responsive counter ops + cloud PostgreSQL 16+ as source of truth. Sync queue rows carry `id`, `shop_id`, `entity_type`, `entity_id`, `idempotency_key`, `action_type`, `payload_json`, `created_at`, `status` (`pending_server_ack` → `confirmed_by_server`), `retry_count`; local and cloud writes are separate ACID transactions.
- Pure-Dart FSMs for credit lifecycle (`pendingDisbursement` → `active` → `overdue` → `settled`) and collateral custody (`inCustody` → `returned` → `exceptionHeld`); Riverpod `AsyncNotifier` controllers with typed permission selectors and payment locks.
- Images: client-side compression, metadata only in relational tables, private cloud storage with ≤15-minute signed URLs.
- **AD-9 (rewritten — backend-service decision):** A standalone backend service owns OTP generation, the pepper, SMTP/SMS credentials, delivery, verification, the challenge lifecycle, and audit appends. It uses OS environment variables only and a least-privilege PostgreSQL role. The Flutter client is a thin HTTP caller holding no OTP, hash, pepper, provider credential, privileged DB connection, or DDL capability, and runs no migration bootstrap at startup. `credential_recovery_challenges` (immutable `tenant_id`, FORCE RLS) stores OTP hash, destination, signed-reference digest, expiry, attempt counter, consumed marker, `client_operation_id`, `idempotency_key`; tenant context derives from server records, never client input. Every delivery/verification call is authenticated by a signed single-use reference; no caller-supplied destination or code is accepted. Migration 003 is applied by a DBA/CI step only (idempotent via `schema_migrations`); the client role has no DDL or `BYPASSRLS`. Existing client-hosted OTP server code and startup migration bootstrap must be **removed, not layered over**.

## UX & Interaction Patterns

- High-contrast, responsive counter interface for desktop browsers and tablets; Material 3 with brand token overrides.
- Login is username-only with an explicit tenant picker; app bar shows offline sync status (`Synced`, `Pending Server Confirmation [N items]`, `Offline`).
- Credential recovery uses a two-step dialog: request challenge → verify OTP + new password. One identical generic message for every unauthenticated outcome; inline validation only after a challenge exists; submit controls disabled while in flight; no username, shop, or channel value displayed; success returns to Login. The client dialog and username-only login with tenant selection are unchanged by the backend redesign.
- Settings surfaces: Shop Profile (business identity, branding, timezone, currency format), Staff Management (accounts + 14 toggles), permission-gated Audit Log Viewer. Platform Admin is a separate restricted entry.
- PII is masked at the data layer for unauthorized roles; no cross-tenant data is exposed.

## Cross-Story Dependencies

- Foundation chain: 1.1 (Money) → 1.2 (databases/sync queue) → 1.3 (RLS + audit trigger) and 1.4 (WAL/PITR) → 1.5 (CI) and 1.6/1.7/1.9; 1.7 (staff accounts) → 1.8 (auth/sessions) → 1.9 (platform-admin governance). 1.5 depends on 1.1/1.2/1.3.
- Credential recovery: implement **Story 1.11 (backend service) first**, then rework **Story 1.10** client code into a thin HTTP caller. Both depend on 1.2, 1.3, 1.7, 1.8, the CI gate (1.5 / 7.4), audit infrastructure (7.3), and closure of the `deferred-work.md` login-identifier collision (email/phone uniqueness per shop).
- Epic 1 is the Day-1 foundation: Epics 2 and 3 depend on it and can then run in parallel; Epics 2–7 rely on its tenant isolation, RBAC, audit, and CI gates. Backend API contract tests and 003 real-SQL tests join the mandatory CI merge gate (7.4).
