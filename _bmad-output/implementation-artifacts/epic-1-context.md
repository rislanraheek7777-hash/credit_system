# Epic 1 Context: Shop Administration, Staff RBAC & Secure Multi-Tenant Workspace

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Establish the secure, multi-tenant architectural foundation for the Credit Management System, enabling Shop Owners to configure shop identity and preferences (timezone `Asia/Colombo`, currency display), manage counter staff accounts with the 14-permission RBAC catalog, enforce server-validated session revocation (`session_version`), isolate tenant data unconditionally via PostgreSQL Row-Level Security, guarantee tamper-resistant audit logging through append-only database triggers, and establish automated CI test verification.

## Stories

- Story 1.1: Immutable Money Value Object & Monetary Precision Foundations
- Story 1.2: Dual-Tier Relational Database Foundations & Migration Harness
- Story 1.3: Server-Enforced PostgreSQL Tenant Isolation & Append-Only Audit Trigger
- Story 1.4: Cloud Backup, Continuous WAL Archiving & Restore Drill Harness
- Story 1.5: Automated Security, Multi-Tenant Integrity & CI Verification Pipeline
- Story 1.6: Shop Profile Configuration, Timezone & Currency Display Preferences
- Story 1.7: Counter Staff Administration & 14-Permission RBAC Configuration
- Story 1.8: Staff Authentication, Session Management & Server-Enforced Revocation
- Story 1.9: Platform Administrator Governance & Cross-Tenant Access Restrictions

## Requirements & Constraints

- Provide configurable shop profile including shop name, contact number, receipt header/footer, and time display.
- Enforce shop-specific timezone handling anchored to `Asia/Colombo` as the operational baseline.
- Configure currency formatting with `LKR` default (`"Rs. 1,500.50"`), prohibiting floating-point arithmetic.
- Maintain absolute tenant isolation: PostgreSQL Row-Level Security (RLS) policies must prevent cross-tenant read or write access under all circumstances.
- Counter staff administration with status flags (`active` vs `deactivated`) and immediate session revocation upon deactivation via incremented `session_version`.
- Enforce the authoritative 14-permission Role-Based Access Control (RBAC) catalog.
- Prohibit platform administrators from viewing tenant operational data or financial records without explicit, audited, time-bounded shop owner authorization.
- Enforce immutable, append-only audit logging: database triggers must block `UPDATE` and `DELETE` on the `audit_events` table.
- Guarantee disaster recovery durability: continuous WAL archiving targeting RPO <= 15 minutes, RTO <= 4 hours.
- Automated CI pipeline must run tenant isolation and RBAC test suites on every pull request, blocking deployment on any security failure.

## Technical Decisions

- **AD-1: Dual Database with Asymmetric Authority:** Cloud PostgreSQL 16+ is the authoritative source of truth. Local SQLite (via Drift) provides sandboxed counter persistence with an offline synchronization queue.
- **AD-2: Strict Integer Minor Units for Monetary Values:** Financial amounts are represented in integer minor units (cents) using 64-bit integers (`BIGINT` in PostgreSQL, `INTEGER` in SQLite, Dart `int`). Dart `double` is strictly prohibited.
- **AD-4: Clean Architecture Layering:** Structured into `core/`, `features/shop/`, and `features/auth/`. Local database logic lives in `core/data/local/` and remote migration logic in `core/data/remote/`.
- **AD-6: Security, RBAC & Audit Architecture:** PostgreSQL connection pooling sets `app.current_shop_id` server-side via trusted claims, never client-controlled. Tamper-resistant audit triggers block modification of event logs.
- **AD-7: Test Strategy & Quality Pipeline:** Automated test matrix covers Unit (Money, converters), Integration (RLS boundaries, migration rollbacks), and System/E2E workflows.
- **AD-8: Backup, PITR & Disaster Recovery Spine:** Continuous Write-Ahead Log (WAL) archiving to encrypted, versioned cloud object storage.

## UX & Interaction Patterns

- UX-DR-1: High-contrast, responsive counter interface optimized for physical retail environments (desktop browsers and tablets).
- UX-DR-8: Offline synchronization indicator on the app bar showing sync status (`Synced`, `Pending Server Confirmation [N items]`, or `Offline`).

## Cross-Story Dependencies

- Story 1.1 (Money Value Object & converters) is the foundational dependency for Story 1.2 (Database foundations).
- Story 1.2 (Dual-tier database foundations & migration harness) is the prerequisite for Story 1.3 (RLS policies & audit trigger) and Story 1.4 (WAL archiving).
- Stories 1.1 through 1.5 establish the foundational infrastructure required before UI/business stories (1.6 through 1.9) and downstream epics (Epics 2 through 7).

