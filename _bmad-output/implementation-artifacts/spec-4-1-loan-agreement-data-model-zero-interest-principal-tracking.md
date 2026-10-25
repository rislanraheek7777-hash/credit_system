# Story 4.1 - Loan Agreement Data Model & Zero-Interest Principal Tracking

**Epic:** Epic 4 - Zero-Interest Loan Origination & Cash Disbursement
**Story ID:** 4-1
**Status:** Implemented (local-first, Drift/SQLite only)
**Dependencies:** Story 1.1 (Money VO), Story 2.1 (Customer), Story 3.1 (Collateral)
**Backlog:** Story 4.2 (Loan Term Selection & Preliminary Due Date), Story 4.3 (Cash Disbursement Confirmation), Story 4.4 (Agreement Documentation)

---

## Acceptance Criteria

### AC-1: Zero-Interest Loan Agreement Creation
**Given** an authenticated user with `createLoans` permission
**When** they create a loan agreement with an attached customer, at least one collateral item, and a Principal Amount (using the immutable `Money` Value Object)
**Then** the loan is persisted with `Financial Status: Active / Pending Disbursement`, `Overall Workflow Status: Active (Pending Disbursement)`
**And** the Initial Outstanding Balance is set exactly equal to the Principal Amount in integer cents
**And** an audit event (Category 2: `Loan agreement origination`) is appended to `audit_events`.

**Implementation:** `LoanDao.createLoanAgreement()` (`lib/features/customers/data/daos/loan_dao.dart`).
- Authorization: `AuthorizationGuard.checkPermission(permission: AppPermission.createLoans)` plus an explicit
  deactivated-account rejection. Deactivated accounts and accounts without `createLoans` raise
  `PermissionDeniedException`.
- Principal is supplied as a `Money` value object; only `Money.minorUnits` (integer minor units) is
  persisted. `double` is never accepted or stored.
- The new row carries `status = 'active'` (financial status) and
  `workflow_status = 'pending_disbursement'` (disbursement workflow status).
- `balance_cents` is written as exactly `principal_cents`; no interest, fee, or compounding is applied.
- The local audit event is written to the `sync_queue` table (the offline-first counterpart of the
  server-side `audit_events` table) with `entity_type = 'loan'`, `action_type = 'create_loan'` and a
  payload preserving the actor ID, loan reference, principal amount, currency, due date and creation
  timestamp. The payload also records `auditCategory: 2` and `auditEvent: 'loan_agreement_origination'`
  per the PRD FR-31 mandatory 14-event catalog, in which category 2 is
  "Loan agreement origination".

### AC-2: Creation Idempotency
**Given** a loan agreement submission
**When** submitted by the client application
**Then** the request includes a client-generated `idempotency_key` (UUIDv4)
**And** rapid double-clicks or network retry transmissions commit exactly one loan record without duplicates.

**Implementation:**
- The `idempotency_key` is required and stored against the `(shop_id, idempotency_key)` unique index
  of the `sync_queue` table.
- The idempotency guard row is written **before** the loan row inside the same transaction, so the
  guard is authoritative rather than advisory. A concurrent submission of the same key loses the
  `INSERT OR IGNORE` race, writes no loan row, and returns the agreement created by the winner.
- The guard is detected with `insertReturningOrNull(...)`, which reports `null` when the unique index
  rejected the row. (Drift's `insert()` returns the *last insert rowid*, not the affected row count,
  and is therefore not a reliable duplicate signal.)
- A repeat submission with the same key returns the originally created agreement; it never creates a
  second loan and never duplicates the audit event.

### AC-3: Payment Block on Undisbursed Loans
**Given** a newly created agreement in `Active / Pending Disbursement`
**When** any user attempts to record a payment against the loan
**Then** the system strictly blocks payment submission: `"Payments cannot be accepted on undisbursed loans."`

**Implementation:** `Loan.assertPaymentsAllowed()` (`lib/features/customers/domain/models/loan.dart`)
raises `LoanPaymentBlockedException` with exactly that message whenever the workflow status is not
`disbursed`. `Loan.isActionable` applies the same gate, so the customer profile's payment action is
hidden for undisbursed loans.

> **Open dependency (Epic 5):** the payment-recording operation does not exist yet. The authoritative
> payment operation introduced in Story 5.1 **must** call `Loan.assertPaymentsAllowed()` before
> posting a payment, so the block is enforced in the operation itself and not only in the UI. The
> domain guard is the enforcement point available at this stage.

---

## Architecture Decisions

| AD | Decision | Rationale |
|----|----------|-----------|
| AD-1 | Dual Database with Asymmetric Authority | Loan origination is recorded locally in SQLite; the append-only `audit_events` row is written server-side after synchronization. |
| AD-2 | Integer Minor Unit Monetary Precision | Principal and balance are integer minor units; `Money` is the only accepted input representation. |
| AD-3 | Finite State Machines | Financial status (`active`/`overdue`/`settled`) and disbursement workflow status (`pending_disbursement`/`disbursed`) are tracked as two independent fields, as required by PRD FR-19. |
| AD-4 | Clean Architecture Layering | `features/customers/domain/models/loan.dart` holds the invariants; `features/customers/data/daos/loan_dao.dart` performs the transactional write. |
| AD-6 | Granular RBAC & Audit | `createLoans` permission is required; the origination audit event is recorded atomically with the agreement. |

---

## Implementation Notes

### New Domain Type
- `LoanWorkflowStatus` enum - `pendingDisbursement` (`pending_disbursement`), `disbursed` (`disbursed`).
  Stored separately from the financial `LoanStatus` so the disbursement workflow (Epic 4) and the
  financial lifecycle (Epic 6) evolve independently.
- `LoanPaymentBlockedException` - carries the exact PRD FR-19 rejection message.

### Schema Change
- `loans.workflow_status` — `TEXT NOT NULL DEFAULT 'pending_disbursement'`, constrained to
  `CHECK (workflow_status IN ('pending_disbursement', 'disbursed'))`.

### Schema Migration
Schema version 11 → 12.

The `from < 7` migration step creates the `loans` table from the **current** table definition, so for
databases older than v7 the `workflow_status` column already exists. The v12 step therefore inspects
`PRAGMA table_info("loans")` and only adds the column when it is genuinely absent; adding it twice
raises `duplicate column name: workflow_status`.

Loans that predate the disbursement workflow were already payable under the Story 2.5 model, so they
are backfilled to `disbursed` to preserve their existing behaviour. Loans originated from schema
version 12 onwards start as `pending_disbursement` (the column default).

### Local Audit Event
The offline-first audit trail is the `sync_queue` table. The origination row carries:
- `shop_id` (tenant boundary), `entity_type = 'loan'`, `entity_id` (loan reference),
  `action_type = 'create_loan'`, `idempotency_key` (the client-generated UUIDv4),
  `status = 'pending_server_ack'`
- `payload_json`: `auditCategory` (2), `auditEvent` (`loan_agreement_origination`), `actorId`,
  `loanId`, `principalCents`, `currency`, `dueDate`, `createdAt`

### Permission Requirements
- Creating a loan agreement: `createLoans` permission (Cashier, Manager and Shop Owner all hold it).
- Deactivated accounts are rejected before the permission check.

---

## Testing Guidance

`test/unit/features/customers/loan_dao_test.dart` - group "LoanDao - Story 4.1 Loan Agreement Creation":
- Initial outstanding balance equals the principal exactly; a one-year term still leaves the balance
  equal to the principal (zero-interest)
- Correct status initialization (`active` + `pending_disbursement`)
- Pledged collateral items are bound to the new loan
- The local audit event records category 2, the actor, the loan reference, the principal amount and the
  timestamp
- Rejection of a deactivated actor and of an actor without `createLoans`
- Rejection of a non-positive principal, a blank idempotency key and an empty collateral list
- Rejection of a foreign-shop customer, a missing collateral item, a collateral item belonging to
  another customer and a collateral item already pledged to another loan
- Idempotent repeat submission, and exactly one agreement for concurrent duplicate submissions
- Atomic rollback when the audit event cannot be persisted (simulated with a `BEFORE INSERT` trigger)
- Shop scoping of the created agreement
- Payment block while the agreement is pending disbursement

`test/unit/features/customers/loan_test.dart` - domain tests for the workflow status, the
financial/workflow status independence, and the payment block.

---

## Traceability

- **PRD:** FR-6 (Granular RBAC), FR-18 (Zero-Interest Principal Tracking & Creation Idempotency),
  FR-19 (Separation of Loan Agreement Creation and Cash Disbursement Confirmation), FR-31 (Append-Only Audit Trail, event category 2)
- **AD-1:** Dual Database with Asymmetric Authority
- **AD-2:** Integer Minor Unit Monetary Precision
- **AD-3:** Finite State Machines
- **AD-4:** Clean Architecture Layering
- **AD-6:** Granular RBAC & Audit
