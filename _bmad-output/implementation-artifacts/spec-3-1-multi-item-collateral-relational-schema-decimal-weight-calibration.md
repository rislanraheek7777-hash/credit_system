# Story 3.1 — Multi-Item Collateral Relational Schema & Decimal Weight Calibration

**Epic:** Epic 3 — Multi-Item Collateral Intake, Appraisal & Custody Tracking  
**Story ID:** 3-1  
**Status:** Implementation in progress (local-first, Drift/SQLite only)  
**Dependencies:** Story 1.2 (Dual-Tier Relational Database Foundations), Story 2.1 (Customer Profile Schema & Persistence), Story 2.5 (Loans table exists)  
**Backlog:** Story 3.2 (Collateral Photo Capture & Exception Workflow) — pending for camera/photo integration  
**Backlog:** Epic 4 (Zero-Interest Loan Origination) — pending for loan-collateral binding enforcement

---

## Acceptance Criteria

### AC-1: Collateral Item Schema & Persistence
**Given** an authenticated counter staff member registering collateral  
**When** they submit collateral item details (category, description, condition, weight, estimated value)  
**Then** the item is persisted in local Drift SQLite with:
- A canonical UUIDv4 primary key
- Shop tenant boundary (`shop_id`) for multi-tenant isolation
- Customer reference (`customer_id`) linking to an existing customer profile
- Optional loan reference (`loan_id`) linking to an existing loan (nullable until Epic 4 enforces binding)
- Item reference ID unique within the shop
- Category (gold, electronics, valuables) with CHECK constraint
- Description and condition grade
- Weight stored as integer milligrams (no Dart `double`)
- Estimated value as `Money` (integer cents) via fixed-point conventions
- Optional photo URI and SHA-256 hash references
- Custody state (`in_custody`, `returned`, `exception_held`) with CHECK constraint
- UTC creation and update timestamps

### AC-2: Weight Precision (No Floating Point)
**Given** a collateral item with a decimal weight (e.g., 5.5 grams of gold)  
**When** the weight is stored and retrieved  
**Then** it is represented internally as integer milligrams (5,500 mg) with no floating-point arithmetic
**And** weight validation rejects negative values
**And** weight parsing from decimal strings (e.g., "5.5g" → 5500 mg) is exact with no rounding

### AC-3: Estimated Value with Money Value Object
**Given** an estimated collateral value (e.g., Rs. 15,000.00)  
**When** the value is stored and retrieved  
**Then** it uses the existing `Money` Value Object (integer minor units)
**And** Dart `double` is strictly prohibited for monetary representation
**And** cross-currency operations are rejected via `Money` invariants

### AC-4: Custody State Machine
**Given** a newly registered collateral item  
**When** custody state changes  
**Then** valid transitions are: `in_custody` → `returned`, `in_custody` → `exception_held`
**And** invalid transitions (e.g., `returned` → `in_custody`, `exception_held` → `returned`) throw a validation exception
**And** each custody state is auditable via the sync queue

### AC-5: Multi-Item Support
**Given** a customer with multiple pledged items  
**When** staff register items sequentially  
**Then** each item receives a unique item reference ID within the shop
**And** previously entered items are not lost when adding additional items
**And** all items can be queried by customer ID within the shop boundary

### AC-6: Schema Migration
**Given** existing databases at schema version 8  
**When** the application is upgraded  
**Then** schema version advances to 9
**And** the `collateral_items` table is created with all columns, indexes, and CHECK constraints
**And** all existing data (shops, customers, loans, etc.) is preserved without loss
**And** foreign key constraints reference existing `shops`, `customers`, and `loans` tables

---

## Architecture Decisions

| Decision | Reference | Application to Story 3.1 |
|----------|-----------|------------------------|
| AD-1 | Dual Database with Asymmetric Authority | Local Drift SQLite for collateral storage; cloud sync deferred |
| AD-2 | Integer Minor Units | `Money` value object for estimated value; no Dart `double` |
| AD-2 | Integer Precision | Weight stored as integer milligrams; no Dart `double` |
| AD-3 | Finite State Machines | Collateral custody state machine (`in_custody` → `returned`/`exception_held`) |
| AD-4 | Clean Architecture Layering | Feature-first: `features/collateral/domain/`, `features/collateral/data/`, `features/collateral/presentation/` |
| AD-5 | Image Storage Pipeline | Photo URI/hash references reuse `PhotoStorageService` and `CustomerPhotoCompressor` conventions |

---

## Implementation Notes

### Local-First Scope
- All collateral data persists in local Drift SQLite (`CollateralItems` table, schema v9)
- No PostgreSQL dependency for Story 3.1 UI or tests
- Loan reference (`loan_id`) is nullable — Epic 4 will enforce loan-collateral binding when loans are activated
- Customer reference (`customer_id`) is required — collateral must belong to an existing customer

### Weight Storage
- Weight is stored as integer milligrams in the `weight_milligrams` column
- Parsing from decimal gram strings (e.g., "5.5") multiplies by 1000 to get milligrams
- No `double` is used anywhere in weight handling

### Custody State Machine
- Initial state: `in_custody`
- Valid transitions: `in_custody` → `returned`, `in_custody` → `exception_held`
- Invalid transitions throw `CollateralCustodyTransitionException`
- State changes update `updated_at` timestamp

### Foreign Key Relationships
- `shop_id` → `shops.id` (KeyAction.restrict on delete)
- `customer_id` → `customers.id` (KeyAction.restrict on delete)
- `loan_id` → `loans.id` (KeyAction.restrict on delete, nullable)
- All queries are strictly scoped to `shopId` for tenant isolation

### Photo Integration
- Photo capture/selection reuses `PhotoStorageService` and `CustomerPhotoCompressor` from Story 2.2
- Photo URI and hash are stored as nullable columns (Story 3.2 will make photos mandatory)
- No camera integration in Story 3.1 — UI supports photo URI text input

---

## Testing Guidance

- Unit tests for `CollateralItem` domain model: validation, weight precision, category/custody enums, state transitions
- Unit tests for `CollateralDao`: CRUD operations, customer/shop scoping, loan relationships, invalid references
- Migration tests: v8→v9 preserves existing data, creates collateral table with indexes
- Widget tests for `CollateralRegistrationScreen`: form validation, multi-item entry, category selection
- No PostgreSQL integration tests (deferred per offline-first rules)

---

## Traceability

- **PRD:** FR-13 (Multi-Item Collateral Registration), FR-14 (Collateral Attribute Capture & Decimal Weight), FR-16 (Independent Per-Item Custody Tracking)
- **AD-1:** Dual Database with Asymmetric Authority
- **AD-2:** Integer Minor Units with Immutable Money Value Object
- **AD-3:** Finite State Machines
- **AD-4:** Clean Architecture Layering
- **AD-5:** Image Storage Pipeline
