# Story 3.4 — Decoupled Per-Item Custody State Machine & Physical Handover Verification

**Epic:** Epic 3 — Multi-Item Collateral Intake, Appraisal & Custody Tracking  
**Story ID:** 3-4  
**Status:** Implementation in progress (local-first, Drift/SQLite only)  
**Dependencies:** Story 3.1 (Multi-Item Collateral Relational Schema & Decimal Weight Calibration), Story 3.2 (Mandatory Collateral Photography & Forensic Inspection), Story 3.3 (Collateral Photo Missing Exception Request & Shop Owner Override UI)  
**Backlog:** Story 3.5 (Collateral Exception State & Shop Owner Administrative Closure)

---

## Acceptance Criteria

### AC-1: Collateral Custody State Machine
**Given** a collateral item in `inCustody` state  
**When** counter staff requests a return  
**Then** the item custody state transitions to `handoverRequested`  
**And** a custody event is recorded with actor ID, timestamp, previous state, new state, and reason

**Given** a collateral item in `handoverRequested` state  
**When** counter staff reports physical handover  
**Then** the item custody state transitions to `handoverReported`  
**And** a custody event is recorded with actor ID, timestamp, previous state, new state, and reason

**Given** a collateral item in `handoverReported` state  
**When** Shop Owner confirms the return  
**Then** the item custody state transitions to `returned`  
**And** a custody event is recorded with actor ID, timestamp, previous state, new state, and reason

**Given** a collateral item in `returned` state  
**When** any state transition is attempted  
**Then** the transition is rejected (terminal state)

### AC-2: Per-Item Custody Independence
**Given** multiple collateral items belonging to the same credit  
**When** one item's custody state changes  
**Then** other items' custody states remain unchanged  
**And** each item's custody state can be queried independently

### AC-3: Shop Owner Confirmation Requirement
**Given** a collateral item in `handoverReported` state  
**When** counter staff attempts to confirm the return  
**Then** the action is rejected (requires Shop Owner role)

**Given** a collateral item in `handoverReported` state  
**When** Shop Owner confirms the return  
**Then** the custody state transitions to `returned`  
**And** the Shop Owner's user ID and decision timestamp are recorded

### AC-4: Discrepancy Reporting
**Given** a counter staff member identifies a discrepancy between system state and physical reality  
**When** staff reports a discrepancy for a collateral item  
**Then** the item custody state transitions to `discrepancy`  
**And** a discrepancy record is created with reporter ID, timestamp, reason, and item reference

**Given** a collateral item in `discrepancy` state  
**When** Shop Owner reviews and resolves the discrepancy  
**Then** the item custody state transitions to `returned`, `inCustody`, or `exceptionHeld` based on the decision  
**And** the Shop Owner's user ID, decision timestamp, and resolution notes are recorded

### AC-5: Unresolved Discrepancies Visible
**Given** a collateral item in `discrepancy` state  
**When** staff views the custody queue  
**Then** the item is visible as having an unresolved discrepancy  
**And** the discrepancy remains visible until resolved

### AC-6: Duplicate Return Prevention
**Given** a collateral item in `returned` state  
**When** any custody transition is attempted  
**Then** the transition is rejected  
**And** no state change occurs

### AC-7: Audit Trail
**Given** any custody transition or discrepancy decision  
**When** the change is saved  
**Then** an audit record is created with actor ID, target entity ID, action type, pre/post state, reason, and timestamp  
**And** the original custody record is preserved (not overwritten)

---

## Architecture Decisions

| Decision | Reference | Application to Story 3.4 |
|----------|-----------|------------------------|
| AD-1 | Dual Database with Asymmetric Authority | Local Drift SQLite only; cloud deferred |
| AD-3 | Finite State Machines | Collateral custody state machine extended with new states and transitions |
| AD-4 | Clean Architecture Layering | Feature-first: `features/collateral/domain/`, `features/collateral/data/`, `features/collateral/presentation/` |
| AD-6 | RBAC & Audit | Shop Owner-only confirmation via `AuthorizationGuard.checkOwnerAdministrativeAction()`; audit records for all decisions |

---

## Implementation Notes

### New Custody States
- `inCustody` - item is in shop custody (existing)
- `handoverRequested` - staff requested return (NEW)
- `handoverReported` - staff reported physical handover (NEW)
- `returned` - owner confirmed physical return (existing, terminal)
- `exceptionHeld` - item held due to exception (existing, terminal)
- `discrepancy` - discrepancy reported (NEW)

### New State Transitions
- `inCustody` → `handoverRequested` (staff requests return)
- `inCustody` → `discrepancy` (staff reports discrepancy)
- `handoverRequested` → `handoverReported` (staff confirms physical handover)
- `handoverRequested` → `inCustody` (staff cancels request)
- `handoverReported` → `returned` (owner confirms return)
- `handoverReported` → `inCustody` (owner rejects handover)
- `discrepancy` → `returned` (owner resolves and confirms return)
- `discrepancy` → `inCustody` (owner resolves, item stays)
- `discrepancy` → `exceptionHeld` (owner decides to hold)

### New Database Tables
- `collateral_custody_events` - audit trail for custody transitions
- `collateral_discrepancies` - discrepancy reports and resolutions

### Schema Migration
Schema version 10 → 11

### Permission Requirements
- Staff requesting handover: `createCredits` permission
- Staff reporting handover: `createCredits` permission
- Shop Owner confirming return: `confirmCollateralReturn` permission
- Shop Owner resolving discrepancy: `approveCorrections` permission

---

## Testing Guidance

- Unit tests for `CollateralCustodyStatus.isValidTransition()` - all valid/invalid transitions
- Unit tests for `CollateralDao.transitionCustody()` and new DAO methods
- Widget tests for `CollateralCustodyReturnScreen` - staff reporting handover
- Widget tests for `CollateralDiscrepancyReviewScreen` - Shop Owner reviewing discrepancies

---

## Traceability

- **PRD:** FR-13 (Multi-Item Collateral Registration), FR-14 (Collateral Attribute Capture), FR-15 (Mandatory Collateral Photographs & Shop Owner Exception Workflow), FR-16 (Independent Per-Item Custody Tracking)
- **AD-1:** Dual Database with Asymmetric Authority
- **AD-3:** Finite State Machines
- **AD-4:** Clean Architecture Layering
- **AD-6:** Granular RBAC & Audit

