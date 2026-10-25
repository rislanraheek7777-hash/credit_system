# Story 3.2 — Mandatory Collateral Photography & Forensic Inspection

**Epic:** Epic 3 — Multi-Item Collateral Intake, Appraisal & Custody Tracking  
**Story ID:** 3-2  
**Status:** Implementation in progress (local-first, Drift/SQLite only)  
**Dependencies:** Story 3.1 (Multi-Item Collateral Schema), Story 2.2 (Customer Photo Compression Pipeline), Story 2.3 (Customer Photo Exception Workflow)  
**Backlog:** Story 3.3 (Collateral Photo Missing Exception Request & Shop Owner Override) — pending for separate exception UI flow

---

## Acceptance Criteria

### AC-1: Mandatory Photo Capture
**Given** a counter staff member registering a collateral item  
**When** they attempt to submit the registration form  
**Then** a photograph of the item is required before registration can complete  
**And** the form validation rejects submission without a photo (unless an approved exception exists)

### AC-2: Photo Compression & Storage
**Given** a photograph selected for a collateral item  
**When** the photo is processed  
**Then** it is compressed using `CustomerPhotoCompressor` (max 1600px, JPEG, 150–300 KB target, 500 KB hard limit)  
**And** it is stored via `PhotoStorageService` in sandboxed tenant-isolated storage (`photos/{shopId}/collateral/`)  
**And** the relative path is stored in `CollateralItems.photoUri`  
**And** a SHA-256 hash is computed and stored in `CollateralItems.photoHash`

### AC-3: Photo Integrity Verification
**Given** a stored collateral photo with a SHA-256 hash  
**When** the photo integrity is verified  
**Then** the hash of the stored file matches `CollateralItems.photoHash`  
**And** mismatched hashes indicate tampering or corruption and are rejected

### AC-4: Owner-Approved Exception Workflow
**Given** a counter staff member cannot provide a photograph  
**When** they request a photo exception  
**Then** they must provide a mandatory reason  
**And** the exception is created in `pending_owner_approval` state  
**And** only a Shop Owner can approve or reject the exception  
**And** an approved exception allows registration without a photo  
**And** staff cannot bypass the photo requirement independently

### AC-5: Audit & Association
**Given** a photo exception request or approval  
**When** the exception is created, approved, or rejected  
**Then** an audit record is created with actor ID, timestamp, reason, and item association  
**And** each exception is bound to a specific collateral item within the shop

### AC-6: Schema Migration
**Given** existing databases at schema version 9  
**When** the application is upgraded  
**Then** schema version advances to 10  
**And** the `collateral_photo_exceptions` table is created with all columns, indexes, and CHECK constraints  
**And** all existing data is preserved without loss

---

## Architecture Decisions

| Decision | Reference | Application to Story 3.2 |
|----------|-----------|------------------------|
| AD-1 | Dual Database with Asymmetric Authority | Local Drift SQLite for photo exception storage; cloud sync deferred |
| AD-2 | Integer Minor Units | Photo file size tracked in bytes (integer), no Dart `double` |
| AD-3 | Finite State Machines | Collateral photo exception status machine (`pending_owner_approval` → `approved`/`rejected`/`consumed`) |
| AD-4 | Clean Architecture Layering | Feature-first: `features/collateral/domain/`, `features/collateral/data/`, `features/collateral/presentation/` |
| AD-5 | Image Storage Pipeline | `CustomerPhotoCompressor` + `PhotoStorageService` reused for collateral photos |
| AD-6 | RBAC & Audit | Shop Owner-only approval; exception requests audited with actor ID, reason, timestamps |

---

## Implementation Notes

### Local-First Scope
- All photo data persists in local Drift SQLite (`CollateralPhotoExceptions` table, schema v10)
- Photo files stored in sandboxed local storage via `PhotoStorageService`
- No PostgreSQL dependency for Story 3.2 UI or tests
- No camera hardware integration — UI supports photo URI text input + compression simulation

### Photo Storage Path
- Collateral photos stored at `photos/{shopId}/collateral/{itemReferenceId}_{timestampMs}.jpg`
- Reuses `PhotoStorageService.getRelativePhotoPath()` pattern (adapted for collateral)
- Relative paths stored in SQLite, decoupled from OS absolute paths

### Exception Table Design
- New `collateral_photo_exceptions` table (cannot reuse `customer_photo_exceptions` because that table is bound to `targetCustomerId` and `customerNic` which are customer-specific, not collateral-item-specific)
- Follows the same pattern as `customer_photo_exceptions`: status lifecycle, mandatory reason, requestedByUserId, reviewedByUserId, reviewNotes, reviewedAt
- FK: `collateral_item_id → collateral_items.id`, `shop_id → shops.id`, `requested_by_user_id → app_users.id`, `reviewed_by_user_id → app_users.id`

### RBAC Enforcement
- Exception request: requires `registerCustomers` permission (same as customer photo exceptions)
- Exception approval/rejection: restricted to Shop Owner role (`checkOwnerAdministrativeAction`)
- All operations enforce shop tenant isolation

### Photo Hash Integrity
- SHA-256 hash computed on compressed bytes via `crypto` package
- Stored in `CollateralItems.photoHash`
- Integrity verification: recompute hash from stored file bytes and compare

---

## Testing Guidance

- Unit tests for `CollateralPhotoException` domain model: validation, status transitions
- Unit tests for `CollateralPhotoExceptionDao`: CRUD operations, shop scoping, FK constraints
- Unit tests for photo compression: valid image, corrupt data, empty bytes, size limits
- Unit tests for photo hash: SHA-256 generation, integrity verification
- Widget tests for `CollateralRegistrationScreen`: mandatory photo validation, exception flow
- Migration tests: v9→v10 preserves existing data
- No PostgreSQL integration tests (deferred per offline-first rules)

---

## Traceability

- **PRD:** FR-13 (Multi-Item Collateral Registration), FR-14 (Collateral Attribute Capture), FR-15 (Mandatory Collateral Photographs & Shop Owner Exception Workflow)
- **AD-1:** Dual Database with Asymmetric Authority
- **AD-2:** Integer Minor Units with Immutable Money Value Object
- **AD-3:** Finite State Machines
- **AD-4:** Clean Architecture Layering
- **AD-5:** Image Storage Pipeline
- **AD-6:** Granular RBAC & Audit
