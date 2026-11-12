# Story 3.3 — Collateral Photo Exception Review & Shop Owner Override UI

**Epic:** Epic 3 — Multi-Item Collateral Intake, Appraisal & Custody Tracking  
**Story ID:** 3-3  
**Status:** Implementation in progress (local-first, Drift/SQLite only)  
**Dependencies:** Story 3.2 (Mandatory Collateral Photography & Forensic Inspection) — done  
**Backlog:** Story 3.4 (Decoupled Per-Item Custody State Machine & Physical Handover Verification)

---

## Acceptance Criteria

### AC-1: Shop Owner Exception Review Screen
**Given** an authenticated Shop Owner  
**When** they navigate to the collateral photo exception review screen  
**Then** the interface displays all pending photo exception requests strictly scoped to their shop  
**And** each request shows: collateral item reference, item description, customer reference, requesting staff member, request timestamp, and reason for the missing photo  
**And** each request shows its current status (`pending_owner_approval`)

### AC-2: Request Details View
**Given** a pending photo exception request  
**When** the Shop Owner opens the request details  
**Then** the interface displays complete request information including collateral item details and request reason  
**And** the interface shows Approve and Reject actions for pending requests  
**And** no actions are shown for already-decided requests (approved/rejected/consumed)

### AC-3: Approve Action
**Given** a pending photo exception request  
**When** the Shop Owner taps Approve and confirms  
**Then** the request status transitions to `approved`  
**And** the Shop Owner's user ID, decision timestamp, and decision notes are recorded  
**And** the approval does NOT indicate that a photograph was captured — it only waives the photo requirement  
**And** the approved exception can be consumed during collateral registration (single-use)

### AC-4: Reject Action
**Given** a pending photo exception request  
**When** the Shop Owner taps Reject, enters a mandatory rejection reason, and confirms  
**Then** the request status transitions to `rejected`  
**And** the Shop Owner's user ID, decision timestamp, and rejection reason are recorded  
**And** the collateral item remains subject to the mandatory-photo rule  
**And** a rejection reason is mandatory — rejection cannot proceed without it

### AC-5: Authorization & Lifecycle Integrity
**Given** a counter staff member (non-owner)  
**When** they attempt to access the review screen or approve/reject a request  
**Then** the action is unconditionally denied with `PermissionDeniedException`  
**Given** an already-decided request (approved/rejected/consumed)  
**When** any action is attempted  
**Then** the action is rejected — only pending requests may receive decisions  
**Given** a duplicate decision attempt (e.g., approving an already-approved request)  
**Then** the action is rejected — prevents conflicting concurrent updates

### AC-6: Audit & Persistence
**Given** any decision (approve or reject)  
**When** the decision is saved  
**Then** an audit record is created with actor ID, target exception ID, action type, pre/post state, reason, and timestamp  
**And** the original request record is never deleted or overwritten — decisions append to the record  
**And** all changes persist in local Drift SQLite

---

## Architecture Decisions

| Decision | Reference | Application to Story 3.3 |
|----------|-----------|------------------------|
| AD-1 | Dual Database with Asymmetric Authority | Local Drift SQLite only; cloud deferred |
| AD-4 | Clean Architecture Layering | Feature-first: `features/collateral/presentation/`, `features/collateral/data/`, `features/collateral/domain/` |
| AD-6 | RBAC & Audit | Shop Owner-only approval via `AuthorizationGuard.checkOwnerAdministrativeAction`; audit records for all decisions |

---

## Implementation Notes

### UI Conventions
- Follows `StaffManagementScreen` pattern: constructor takes `shopId`, `currentUser`, `database`
- Uses `AppBar` with title, `Scaffold` with `Padding` and `SingleChildScrollView`
- Loading, empty, error, and success states consistent with existing screens
- `MaterialPageRoute` for navigation to details/confirmation dialogs

### Authorization
- Screen access enforced via `AuthorizationGuard.checkOwnerAdministrativeAction` in `initState` and action handlers
- Counter staff (Cashier/Manager) cannot access the screen or perform decisions
- Only pending requests can be approved/rejected — terminal states block further transitions

### No Schema Changes Required
- The `collateral_photo_exceptions` table already exists (created in Story 3.2, schema v10)
- All required columns are present: `reviewedByUserId`, `reviewNotes`, `reviewedAt`, `status`
- No new migration needed

### Integration with Story 3.2
- Approved exceptions can be consumed during collateral registration via `CollateralPhotoExceptionDao.consumeException`
- Rejected exceptions leave the collateral item subject to the mandatory-photo rule
- Consumed exceptions are single-use and cannot be reused

---

## Testing Guidance

- Unit tests for `CollateralPhotoExceptionDao`: approve/reject with valid and invalid states
- Widget tests for `CollateralPhotoExceptionReviewScreen`: owner access, staff denial, pending listing, approve/reject flows, rejection reason required
- No PostgreSQL integration tests (deferred per offline-first rules)

---

## Traceability

- **PRD:** FR-15 (Mandatory Collateral Photographs & Shop Owner Exception Workflow)
- **AD-4:** Clean Architecture Layering
- **AD-6:** Granular RBAC & Audit

