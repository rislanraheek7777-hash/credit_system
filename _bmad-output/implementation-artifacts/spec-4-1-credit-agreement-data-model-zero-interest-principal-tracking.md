# Story 4.1 - Credit Agreement Data Model & Zero-Interest Principal Tracking

**Epic:** Epic 4 - Zero-Interest Credit Origination & Cash Disbursement
**Story ID:** 4-1
**Status:** Implemented (local-first, Drift/SQLite only)
**Dependencies:** Story 1.1 (Money VO), Story 2.1 (Customer), Story 3.1 (Collateral)
**Backlog:** Story 4.2 (Credit Term Selection & Preliminary Due Date), Story 4.3 (Cash Disbursement Confirmation), Story 4.4 (Agreement Documentation)

---

## Acceptance Criteria

### AC-1: Zero-Interest Credit Agreement Creation
**Given** an authenticated user with `createCredits` permission
**When** they create a credit agreement with an attached customer, at least one collateral item, and a Principal Amount (using the immutable `Money` Value Object)
**Then** the credit is persisted with `Financial Status: Active / Pending Disbursement`, `Overall Workflow Status: Active (Pending Disbursement)`
**And** the Initial Outstanding Balance is set exactly equal to the Principal Amount in integer cents
**And** an audit event (Category 2: `Credit agreement origination`) is appended to `audit_events`.

**Implementation:** `CreditDao.createCreditAgreement()` (`lib/features/customers/data/daos/credit_dao.dart`).
- Authorization: `AuthorizationGuard.checkPermission(permission: AppPermission.createCredits)` plus an explicit
  deactivated-account rejection. Deactivated accounts and accounts without `createCredits` raise
  `PermissionDeniedException`.
- Principal is supplied as a `Money` value object; only `Money.minorUnits` (integer minor units) is
  persisted. `double` is never accepted or stored.
- The new row carries `status = 'active'` (financial status) and
  `workflow_status = 'pending_disbursement'` (disbursement workflow status).
- `balance_cents` is written as exactly `principal_cents`; no interest, fee, or compounding is applied.
- The local audit event is written to the `sync_queue` table (the offline-first counterpart of the
  server-side `audit_events` table) with `entity_type = 'credit'`, `action_type = 'create_credit'` and a
  payload preserving the actor ID, credit reference, principal amount, currency, due date and creation
  timestamp. The payload also records `auditCategory: 2` and `auditEvent: 'credit_agreement_origination'`
  per the PRD FR-31 mandatory 14-event catalog, in which category 2 is
  "Credit agreement origination".

### AC-2: Creation Idempotency
**Given** a credit agreement submission
**When** submitted by the client application
**Then** the request includes a client-generated `idempotency_key` (UUIDv4)
**And** rapid double-clicks or network retry transmissions commit exactly one credit record without duplicates.

**Implementation:**
- The `idempotency_key` is required and stored against the `(shop_id, idempotency_key)` unique index
  of the `sync_queue` table.
- The idempotency guard row is written **before** the credit row inside the same transaction, so the
  guard is authoritative rather than advisory. A concurrent submission of the same key loses the
  `INSERT OR IGNORE` race, writes no credit row, and returns the agreement created by the winner.
- The guard is detected with `insertReturningOrNull(...)`, which reports `null` when the unique index
  rejected the row. (Drift's `insert()` returns the *last insert rowid*, not the affected row count,
  and is therefore not a reliable duplicate signal.)
- A repeat submission with the same key returns the originally created agreement; it never creates a
  second credit and never duplicates the audit event.

### AC-3: Payment Block on Undisbursed Credits
**Given** a newly created agreement in `Active / Pending Disbursement`
**When** any user attempts to record a payment against the credit
**Then** the system strictly blocks payment submission: `"Payments cannot be accepted on undisbursed credits."`

**Implementation:** `Credit.assertPaymentsAllowed()` (`lib/features/customers/domain/models/credit.dart`)
raises `CreditPaymentBlockedException` with exactly that message whenever the workflow status is not
`disbursed`. `Credit.isActionable` applies the same gate, so the customer profile's payment action is
hidden for undisbursed credits.

> **Open dependency (Epic 5):** the payment-recording operation does not exist yet. The authoritative
> payment operation introduced in Story 5.1 **must** call `Credit.assertPaymentsAllowed()` before
> posting a payment, so the block is enforced in the operation itself and not only in the UI. The
> domain guard is the enforcement point available at this stage.

---

## Architecture Decisions

| AD | Decision | Rationale |
|----|----------|-----------|
| AD-1 | Dual Database with Asymmetric Authority | Credit origination is recorded locally in SQLite; the append-only `audit_events` row is written server-side after synchronization. |
| AD-2 | Integer Minor Unit Monetary Precision | Principal and balance are integer minor units; `Money` is the only accepted input representation. |
| AD-3 | Finite State Machines | Financial status (`active`/`overdue`/`settled`) and disbursement workflow status (`pending_disbursement`/`disbursed`) are tracked as two independent fields, as required by PRD FR-19. |
| AD-4 | Clean Architecture Layering | `features/customers/domain/models/credit.dart` holds the invariants; `features/customers/data/daos/credit_dao.dart` performs the transactional write. |
| AD-6 | Granular RBAC & Audit | `createCredits` permission is required; the origination audit event is recorded atomically with the agreement. |

---

## Implementation Notes

### New Domain Type
- `CreditWorkflowStatus` enum - `pendingDisbursement` (`pending_disbursement`), `disbursed` (`disbursed`).
  Stored separately from the financial `CreditStatus` so the disbursement workflow (Epic 4) and the
  financial lifecycle (Epic 6) evolve independently.
- `CreditPaymentBlockedException` - carries the exact PRD FR-19 rejection message.

### Schema Change
- `credits.workflow_status` — `TEXT NOT NULL DEFAULT 'pending_disbursement'`, constrained to
  `CHECK (workflow_status IN ('pending_disbursement', 'disbursed'))`.

### Schema Migration
Schema version 11 → 12.

The `from < 7` migration step creates the `credits` table from the **current** table definition, so for
databases older than v7 the `workflow_status` column already exists. The v12 step therefore inspects
`PRAGMA table_info("credits")` and only adds the column when it is genuinely absent; adding it twice
raises `duplicate column name: workflow_status`.

Credits that predate the disbursement workflow were already payable under the Story 2.5 model, so they
are backfilled to `disbursed` to preserve their existing behaviour. Credits originated from schema
version 12 onwards start as `pending_disbursement` (the column default).

### Local Audit Event
The offline-first audit trail is the `sync_queue` table. The origination row carries:
- `shop_id` (tenant boundary), `entity_type = 'credit'`, `entity_id` (credit reference),
  `action_type = 'create_credit'`, `idempotency_key` (the client-generated UUIDv4),
  `status = 'pending_server_ack'`
- `payload_json`: `auditCategory` (2), `auditEvent` (`credit_agreement_origination`), `actorId`,
  `creditId`, `principalCents`, `currency`, `dueDate`, `createdAt`

### Permission Requirements
- Creating a credit agreement: `createCredits` permission (Cashier, Manager and Shop Owner all hold it).
- Deactivated accounts are rejected before the permission check.

---

## Testing Guidance

`test/unit/features/customers/credit_dao_test.dart` - group "CreditDao - Story 4.1 Credit Agreement Creation":
- Initial outstanding balance equals the principal exactly; a one-year term still leaves the balance
  equal to the principal (zero-interest)
- Correct status initialization (`active` + `pending_disbursement`)
- Pledged collateral items are bound to the new credit
- The local audit event records category 2, the actor, the credit reference, the principal amount and the
  timestamp
- Rejection of a deactivated actor and of an actor without `createCredits`
- Rejection of a non-positive principal, a blank idempotency key and an empty collateral list
- Rejection of a foreign-shop customer, a missing collateral item, a collateral item belonging to
  another customer and a collateral item already pledged to another credit
- Idempotent repeat submission, and exactly one agreement for concurrent duplicate submissions
- Atomic rollback when the audit event cannot be persisted (simulated with a `BEFORE INSERT` trigger)
- Shop scoping of the created agreement
- Payment block while the agreement is pending disbursement

`test/unit/features/customers/credit_test.dart` - domain tests for the workflow status, the
financial/workflow status independence, and the payment block.

---

## Traceability

- **PRD:** FR-6 (Granular RBAC), FR-18 (Zero-Interest Principal Tracking & Creation Idempotency),
  FR-19 (Separation of Credit Agreement Creation and Cash Disbursement Confirmation), FR-31 (Append-Only Audit Trail, event category 2)
- **AD-1:** Dual Database with Asymmetric Authority
- **AD-2:** Integer Minor Unit Monetary Precision
- **AD-3:** Finite State Machines
- **AD-4:** Clean Architecture Layering
- **AD-6:** Granular RBAC & Audit

