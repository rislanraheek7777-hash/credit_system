# Story 1.6 — Shop Profile Configuration, Timezone & Currency Display Preferences

**Epic:** Epic 1 — Shop Administration, Staff RBAC & Secure Multi-Tenant Workspace  
**Story ID:** 1-6  
**Status:** Implementation in progress (local-first, Drift/SQLite only)  
**Dependencies:** Story 1.2 (Dual-Tier Relational Database Foundations & Migration Harness)  
**Backlog:** Story 1.7 (Counter Staff Administration & 14-Permission RBAC Configuration) — pending for editing enforcement  
**Backlog:** Story 1.3 — Server-Enforced PostgreSQL Tenant Isolation & Append-Only Audit Trigger — pending for server-side audit logging

---

## Acceptance Criteria

### AC-1: Shop Profile Configuration
**Given** an authenticated Shop Owner on the shop configuration screen  
**When** they view the shop profile  
**Then** the interface displays the shop profile including shop name, contact number, receipt header/footer, timezone, and currency display  
**And** the profile data is retrieved from local Drift SQLite storage  
**And** the shop profile is scoped strictly to the active shop tenant

### AC-2: Shop Timezone Configuration
**Given** a shop profile is created or updated  
**When** the shop profile is viewed  
**Then** the timezone defaults to `Asia/Colombo` (UTC+05:30)  
**And** the timezone input is validated against standard IANA timezone identifiers  
**And** all subsequent calendar due date and midnight boundary calculations evaluate in this configured local timezone

### AC-3: Currency Formatting
**Given** the shop currency configuration  
**When** configured by the Shop Owner  
**Then** currency display defaults to `LKR` (formatted as `"Rs. ###,###.00"`)  
**And** presentation formatting uses integer minor units (cents) via the immutable `Money` Value Object  
**And** Dart `double` is strictly prohibited for monetary representation  
**And** presentation formatting is decoupled from the internal integer minor units ledger

### AC-4: Currency Lock After First Financial Transaction
**Given** any financial transaction (loan agreement, disbursement, payment, or reversal) exists within the shop tenant  
**When** the Shop Owner attempts to change the base currency code  
**Then** the change is programmatically blocked  
**And** the currency remains locked to the existing code  
**And** an immutable audit entry is recorded (deferred to Story 1.3 server-side audit logging)

---

## Architecture Decisions

| Decision | Reference | Application to Story 1.6 |
|----------|-----------|------------------------|
| AD-1 | Dual Database with Asymmetric Authority | Local Drift SQLite for responsive counter operations; cloud PostgreSQL deferred |
| AD-2 | Integer Minor Units | `Money` value object for all monetary formatting; no Dart `double` |
| AD-4 | Clean Architecture Layering | Feature-first: `features/shop/domain/`, `features/shop/data/`, `features/shop/presentation/` |
| AD-6 | RBAC & Audit | Editing disabled pending Story 1.7 RBAC; server audit logging deferred |

---

## Implementation Notes

### Local-First Scope
- All shop profile data persists in local Drift SQLite (`Shops` table, schema v7)
- No PostgreSQL dependency for Story 1.6 UI
- Schema version 7 already includes all `Shops` table columns

### Currency Lock Behavior
- Currency change is blocked when `ShopDao.hasFinancialTransactions(shopId)` returns `true`
- **Limitation:** `hasFinancialTransactions()` checks `sync_queue` for financial entity types (`loan`, `payment`, `disbursement`, `reversal`). If `sync_queue` entries are cleaned up after server confirmation, the check may return `false` even though financial transactions occurred. This is a local heuristic; server-enforced currency locking is deferred to PostgreSQL RLS/triggers (Epic 4+).

### Server Audit Logging
- Server-side audit logging for shop profile changes is **deferred** to Story 1.3 (PostgreSQL tenant isolation & append-only audit trigger)
- Local-only audit logging is not implemented as a substitute
- The `canViewSensitive` flag and RBAC enforcement are deferred to Story 1.7

### Editing State
- All shop profile fields are **view-only** in Story 1.6
- Editing is disabled pending Story 1.7 RBAC authorization
- No save/save button is provided

---

## Testing Guidance

- Unit tests for `ShopProfile` domain model validation (already exist in `test/unit/features/shop/shop_profile_test.dart`)
- Unit tests for `ShopDao` CRUD and currency lock (already exist in `test/unit/features/shop/shop_dao_test.dart`)
- Widget tests for `ShopProfileScreen` view-only display (to be created in `test/widget/features/shop/shop_profile_screen_test.dart`)
- No integration tests requiring PostgreSQL (deferred to Story 1.3)

---

## Traceability

- **PRD:** FR-1 (Shop Profile Configuration), FR-2 (Shop Timezone), FR-3 (Currency Display)
- **AD-1:** Dual Database with Asymmetric Authority
- **AD-2:** Integer Minor Units with Immutable Money Value Object
- **AD-4:** Clean Architecture Layering
- **AD-6:** Granular 14-Permission RBAC, Immediate Session Revocation & Database-Enforced Append-Only Audit Trails
