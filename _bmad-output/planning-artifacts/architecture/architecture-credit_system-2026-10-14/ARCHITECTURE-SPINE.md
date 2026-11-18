---
name: credit_system
type: architecture-spine
purpose: build-substrate
altitude: feature
paradigm: Clean Architecture with Feature-First Modular Boundaries
scope: Credit Management System Core Platform
status: draft
created: 2026-10-14
updated: 2026-10-14
binds:
  - FR-1 to FR-33
sources:
  - _bmad-output/planning-artifacts/prds/prd-credit_system-2026-10-13/prd.md
  - _bmad-output/planning-artifacts/briefs/brief-credit_system-2026-10-13/brief.md
  - _bmad-output/planning-artifacts/briefs/brief-credit_system-2026-10-13/addendum.md
companions: []
---

# Architecture Spine — Credit Management System

## Design Paradigm

Clean Architecture organized by **Feature-First** modules.
The codebase is structured into isolated, testable layers:
- `domain/`: Pure Dart entities, value objects, business rules, and repository interfaces. Completely free of Flutter UI or database dependencies.
- `data/`: Database DAOs, tables, API clients, and repository implementations.
- `presentation/`: Flutter widgets, state notifiers, view models, and UI formatting.

## Invariants & Rules

### AD-1 — Drift (SQLite) Local Relational Persistence with Cloud PostgreSQL & Row-Level Security (RLS) [ADOPTED]

- **Binds:** FR-4, FR-18, FR-21, FR-22, FR-23, FR-31, FR-32
- **Prevents:**
  - Cross-tenant data leaks across shops.
  - Floating-point arithmetic errors and orphaned child records (collateral/payments without parent credit).
  - Counter freezing or operational lockout during intermittent internet hiccups.
  - Silent record overwrites or unverified state reconciliation during sync.
  - Duplicate payment postings from concurrent submissions or network retries.
- **Rule:**
  1. **Dual-Tier Relational Storage:**
     - **Local (Counter):** Drift (SQLite) serves as the local relational cache and persistence engine for responsive counter operations on Flutter (Android and Web).
     - **Remote (Cloud Source of Truth):** PostgreSQL 16+ acts as the authoritative central multi-tenant database.
  2. **Server-Side Tenant Isolation (RLS):**
     - Every relational entity table must carry an immutable, non-nullable `tenant_id` (UUID).
     - PostgreSQL Row-Level Security (RLS) is strictly enforced on all tables:
       ```sql
       ALTER TABLE credits ENABLE ROW LEVEL SECURITY;
       CREATE POLICY tenant_isolation_policy ON credits
         USING (tenant_id = current_setting('app.current_tenant_id')::uuid);
       ```
     - Direct client access bypassing the authenticated tenant context is prohibited.
  3. **Atomic Financial Transactions (ACID):**
     - All balance updates, payment postings, reversals, and adjustments must execute within single atomic database transactions.
     - Partial commits are strictly prohibited; any failure rolls back the entire transaction.
     - Balance adjustments may only be posted from an approved request (staff-proposed → Shop Owner-approved, `approveCorrections`) or by direct Shop Owner execution. Both paths write an immutable `adjustment_debit` / `adjustment_credit` ledger entry in the same atomic transaction as the correction-lock lift; the stored balance is never mutated in place.
  4. **Offline Synchronization & Acknowledgement Semantics:**
     - Every local write operation assigns a client-generated `client_operation_id` (UUIDv4) and unique idempotency key.
     - Local mutations are flagged with a synchronization state: `PendingServerAck` vs. `ConfirmedByServer`.
     - Counter interfaces must visibly distinguish unconfirmed offline records from centrally confirmed records.
     - The client must never treat an offline write as permanent or centrally settled until the server responds with a signed acknowledgement.
  5. **No Silent Overwrites (Compensating Ledger Protocol):**
     - Financial transaction records are strictly append-only.
     - Sync conflict resolution must never overwrite, truncate, or merge existing financial entries. Corrections and reversals must be submitted as discrete compensating entries with mandatory audit justifications and Shop Owner approvals.
  6. **Idempotency & Duplicate Prevention:**
     - The cloud database enforces a unique constraint on `(tenant_id, idempotency_key)` and `(tenant_id, client_operation_id)`.
     - Re-transmitted requests return the existing confirmed transaction and receipt snapshot without re-executing balance deductions.
  7. **Sensitive PII Security:**
     - Customer NIC numbers, residential addresses, and photographic blobs are protected by server-side role-based access control and encrypted in transit (TLS 1.3). Direct unauthenticated media URLs are forbidden.
   8. **Offline Audit Durability (R2 — approved, not yet implemented):**
     - Offline durability is provided by a local, append-only, hash-chained journal in Drift SQLite (see AD-6 rule 7). The journal is a durability mechanism, not a second authority: the central cloud PostgreSQL `audit_events` table remains the authoritative, cryptographically verified record of truth, and every journal entry is reconciled to it on synchronization.
     - Cash disbursement and cancellation of an undisbursed agreement are **permitted while offline**: the business mutation and its journal entry are written in the same local ACID transaction; the agreement state transitions immediately in the local database and the event is marked `Pending Server Confirmation` until server acknowledgement. Other high-risk administrative actions (approving corrections, approving balance adjustments, due-date extensions, administrative closures) remain locked offline per AD-6 rule 8.
     - Reconciliation: on connectivity, each `PendingServerAck` journal entry is appended to `audit_events` by the server-side audit writer (Story 1.3 / 1.8); a rejected entry is surfaced as `failed` with `lastError` and is never silently dropped; an entry is removed from the local journal only after server acknowledgement. A device lost before synchronization leaves a permanent gap, which FR-32's RPO does not cover; this is an accepted risk of the offline-first model.

### AD-2 — Integer Minor Units with Immutable Money Value Object [ADOPTED]

- **Binds:** FR-3, FR-18, FR-21, FR-22, FR-24
- **Prevents:**
  - Floating-point precision drift (IEEE 754) causing micro-cent discrepancies.
  - Zero-balance settlement evaluation failures (`balance == 0.0000000001`).
  - Arithmetic mismatches between stored ledger balances and payment audit sums.
  - Premature or inconsistent currency formatting applied in business or data layers.
- **Rule:**
  1. **Integer Minor Unit Standard:**
     - All financial amounts for Sri Lankan Rupees (LKR) are strictly represented and calculated in **integer minor units (cents)**, with exactly 100 minor units per rupee (1.00 LKR = 100 minor units).
  2. **Dedicated Immutable `Money` Value Object:**
     - Domain and data layers must encapsulate monetary amounts inside an immutable `Money` value object:
       ```dart
       class Money {
         final int minorUnits; // 64-bit integer
         final String currency; // ISO 4217 code (default: 'LKR')

         const Money(this.minorUnits, {this.currency = 'LKR'});
         const Money.zero([String currency = 'LKR']) : this(0, currency: currency);

         Money operator +(Money other) {
           _assertSameCurrency(other);
           return Money(minorUnits + other.minorUnits, currency: currency);
         }

         Money operator -(Money other) {
           _assertSameCurrency(other);
           return Money(minorUnits - other.minorUnits, currency: currency);
         }

         bool get isZero => minorUnits == 0;
         bool get isPositive => minorUnits > 0;
         bool get isNegative => minorUnits < 0;
         int compareTo(Money other) {
           _assertSameCurrency(other);
           return minorUnits.compareTo(other.minorUnits);
         }
       }
       ```
  3. **Strict Prohibition of Floating-Point Types:**
     - The use of Dart `double` or `float` for monetary calculations, entities, balance adjustments, or persistence is strictly prohibited across the entire codebase and enforced via static linting.
  4. **Database Column Types:**
     - **SQLite (Drift):** Stored as `INTEGER` (64-bit signed integer).
     - **PostgreSQL:** Stored as `BIGINT` (in minor units).
  5. **Input Validation:**
     - Presentation input fields must validate that user-entered currency strings do not exceed two decimal places (e.g., `50000.50` is valid; `50000.555` is rejected).
  6. **Double-Entry Ledger Invariant (FR-22):**
     - Outstanding balance must mathematically satisfy:
       $$\text{Valid Balance} = \text{Principal} - \sum\text{Payments} + \sum\text{Reversals} \pm \sum\text{Adjustments}$$
     - All balance deductions must execute inside ACID transactions. Negative balances resulting from payments are programmatically blocked (`Payment <= Valid Outstanding Balance`).
  7. **Presentation-Layer Formatting Only:**
     - Formatting to human-readable strings (e.g., `Rs. 50,000.00` or `50,000.00 LKR`) is strictly confined to the presentation layer (widgets, PDF generators, receipt renderers) using locale-aware formatters.
  8. **Automated Verification Testing:**
     - Automated test suites must explicitly verify:
       - Partial payment balance deductions.
       - Full settlement zero-balance transition (`isZero == true`).
       - Approved payment reversals adding back exact minor units.
       - Large currency amounts without 64-bit integer overflow.
       - Roundtrip serialization between Dart `Money`, Drift SQLite `INTEGER`, and PostgreSQL `BIGINT`.

### AD-3 — Riverpod State Management with Pure Dart Finite State Machines (FSM) [ADOPTED]

- **Binds:** FR-5, FR-6, FR-16, FR-17, FR-19, FR-21, FR-23
- **Prevents:**
  - Tight coupling between business rules and Flutter UI widgets.
  - State divergence between credit financial status and physical collateral custody status.
  - Unauthorized counter operations due to client-side permission leakage.
  - Duplicate transaction submissions caused by rapid UI button clicks.
  - Inability to unit-test complex financial lifecycles without mounting widget trees.
- **Rule:**
  1. **Pure Dart Domain State Machines:**
     - Financial state and custody state must be modeled as independent, decoupled state machines in pure Dart domain models:
       - **`CreditFinancialState`**: `pendingDisbursement` $\rightarrow$ `active` $\rightarrow$ `overdue` $\rightarrow$ `settled` (or `cancelled`).
       - **`CollateralCustodyState`**: `inCustody` $\rightarrow$ `returned` $\rightarrow$ `exceptionHeld`.
       - **`OverallWorkflowStatus`**: Derived dynamically from financial and custody status:
         $$\text{Status} = \begin{cases} 
         \text{Active (Pending Disbursement)}, & \text{if financial is pendingDisbursement} \\
         \text{Active}, & \text{if financial is active} \\
         \text{Overdue}, & \text{if financial is overdue} \\
         \text{Settled (Items Pending Handover)}, & \text{if financial is settled and any item inCustody} \\
         \text{Closed / Completed}, & \text{if financial is settled and (no item receipts attached or all items returned)} \\
         \text{Closed (Collateral Exception)}, & \text{if financial is settled and any item exceptionHeld} \\
         \text{Cancelled}, & \text{if financial is cancelled}
         \end{cases}$$
  2. **Application State with Riverpod:**
     - `flutter_riverpod` (^2.6.0) is the exclusive state management solution.
     - Controllers must extend `AsyncNotifier<T>` or `Notifier<T>` to expose immutable state wrapped in `AsyncValue<T>`.
     - UI widgets read and observe state using `ref.watch()`. Business logic methods are invoked via `ref.read().notifier`.
  3. **Role-Based Permission Selectors:**
     - A centralized `sessionProvider` holds the authenticated user's `tenantId`, `userId`, `role`, and `Set<AppPermission>`.
     - Granular UI toggles use typed selectors (e.g. `ref.watch(hasPermissionProvider(AppPermission.approveCorrections))`) to disable or hide restricted controls.
  4. **Idempotency & Concurrent Submission Protection:**
     - Action buttons triggering financial operations (credit creation, disbursement, payment) must observe `AsyncValue.isLoading`.
     - Submissions generate a client-side idempotency UUID on first tap and lock the UI controller until confirmed or rejected.
  5. **Credit Correction Lock:**
     - When a credit has an active correction pending owner review, the credit detail controller must expose a `isPaymentLocked` state that blocks payment inputs specifically for that credit. The same `isPaymentLocked` state applies while a staff-proposed balance adjustment (FR-22) is pending Shop Owner approval, and approving an adjustment is a high-risk administrative action locked while offline (AD-6 rule 8).

### AD-4 — Feature-First Clean Architecture & Inward Dependency Rules [ADOPTED]

- **Binds:** FR-1 through FR-33, Entire Codebase
- **Prevents:**
  - Code sprawl and tight coupling between Flutter UI widgets, Drift database code, and business rules.
  - Cross-feature spaghetti code where changes in one domain accidentally break unrelated modules.
  - Over-abstraction while maintaining strict architectural boundaries.
- **Rule:**
  1. **Feature-First Vertical Slices:**
     - The application is organized by business feature domains: `auth`, `shop`, `customers`, `collateral`, `credits`, `payments`, `overdue`, `reports`, and `audit`.
  2. **Core Infrastructure (`lib/core/`):**
     - Contains only shared, non-feature-specific primitives:
       - `database/`: Drift database connection, migrations, and shared table mixins (`tenant_id`, timestamps).
       - `errors/`: Typed domain failure definitions (`AppFailure`, `ValidationFailure`, `PermissionFailure`).
       - `money/`: Immutable `Money` value object, currency math, and presentation formatters (AD-2).
       - `permissions/`: 14 RBAC permission catalog, role definitions, and session state guards (AD-3).
       - `sync/`: Offline sync queue, operation models, and conflict handlers (AD-1).
       - `theme/`: Design tokens, colors, typography, and shop branding.
       - `utils/`: Timezone utilities (`Asia/Colombo`), calendar arithmetic, and date formatters.
  3. **Three-Layer Internal Architecture per Feature:**
     - **`domain/` (The Core):**
       - Contains pure Dart entities, value objects, business rules, failure definitions, and abstract repository interfaces.
       - **Strict Dependency Rule:** Must NEVER import Flutter widgets, Drift packages, or network HTTP libraries. 100% pure Dart, testable in isolation.
     - **`data/` (The Infrastructure):**
       - Contains Drift table definitions, DAOs, remote API clients, DTO mappers, and concrete implementations of domain repository interfaces.
       - Implements database transactions and enforces tenant isolation.
     - **`presentation/` (The User Interface):**
       - Contains Flutter widgets, screens, dialogs, form validators, and Riverpod controllers (`AsyncNotifier`).
       - Observes domain entities and triggers repository operations via Riverpod notifiers.
  4. **The Inward Dependency Invariant:**
     ```mermaid
     flowchart LR
         UI[Presentation Layer] -->|depends on| D[Domain Layer]
         DATA[Data Layer] -->|implements & depends on| D
         D -->|Zero Dependencies| PURE[Pure Dart SDK]
     ```
  5. **Pragmatic Simplicity:**
     - Avoid redundant layers (e.g., separate "use-case" or "interactor" classes for simple CRUD operations). Use-cases are introduced only when business logic involves orchestrating multiple repositories or complex multi-step financial workflows.

### AD-5 — Client-Side Optimization, App-Private Local Storage & Private Object Storage with Signed URLs [ADOPTED]

- **Binds:** FR-9, FR-12, FR-14, FR-15, FR-31
- **Prevents:**
  - Database bloat and performance degradation from storing binary image data in relational tables.
  - Counter stalls and upload timeouts on mobile/intermittent network connections.
  - Public exposure or scraping of sensitive customer identity (NIC) photos and valuable pledged items.
  - Image corruption, unhandled upload failures, and duplicate file uploads.
  - Cross-tenant image access via forged or client-supplied tenant identifiers.
- **Rule:**
  1. **Client-Side Image Optimization:**
     - Photos captured via camera or file upload are resized and compressed directly on the client device before persistence or transmission.
     - Target maximum dimension: 1600 pixels on the longest edge, with adaptive WebP/JPEG quality (75–85%).
     - Target file size range: 150 KB – 300 KB. This is treated as a calibrated target, ensuring compression preserves visible gold hallmarks, condition grading, serial numbers, and cosmetic scratches without loss of forensic utility.
  2. **Metadata-Only Relational Storage:**
     - Relational tables in SQLite and PostgreSQL store only image metadata:
       ```sql
       CREATE TABLE collateral_photos (
         id UUID PRIMARY KEY,
         tenant_id UUID NOT NULL,
         collateral_item_id UUID NOT NULL,
         local_path TEXT,
         remote_storage_key TEXT,
         sha256_hash TEXT NOT NULL,
         file_size_bytes INTEGER NOT NULL,
         mime_type TEXT NOT NULL,
         upload_status TEXT NOT NULL, -- 'pendingUpload', 'uploading', 'uploaded', 'uploadFailed'
         captured_by_user_id UUID NOT NULL,
         captured_at TIMESTAMP NOT NULL
       );
       ```
     - Raw image binary bytes are strictly prohibited from relational database tables.
  3. **Platform-Specific Local Storage Strategy:**
     - **Mobile & Desktop (Android, Windows, etc.):** Images are stored in the app's private sandboxed directory (`getApplicationDocumentsDirectory() / photos / {tenant_id} /`), inaccessible to other apps.
     - **Flutter Web:** Images are stored in browser-supported sandboxed storage (Origin Private File System / OPFS or IndexedDB blob store) with graceful eviction policies after confirmed cloud synchronization.
  4. **Private Cloud Storage & Short-Lived Signed URLs:**
     - Cloud object storage (S3 / Cloudflare R2 / Supabase Storage) must have public read access completely disabled.
     - Viewing an image requires an authenticated request where the server verifies tenant context and user permissions (`View Customers` / `View Sensitive Customer Data`) before returning a cryptographically signed URL valid for $\le 15$ minutes.
     - Storage keys must be partitioned by tenant (`tenants/{tenant_id}/{entity_type}/{id}.webp`). The server strictly computes this path from the authenticated session context, never trusting client-supplied paths.
  5. **Upload Lifecycle & Retry State Machine:**
     - Uploads maintain an explicit state machine: `pendingUpload` $\rightarrow$ `uploading` $\rightarrow$ `uploaded` (or `uploadFailed`).
     - Network interruptions trigger retry with exponential backoff.
     - The unique `sha256_hash` and `remote_storage_key` guarantee upload idempotency, preventing duplicate object uploads.
  6. **Retention & Audit Compliance:**
     - Photos associated with active or settled credits are preserved for the full statutory record retention period. Deletion of photos is restricted exclusively to authorized administrative procedures and logged in the append-only audit trail.
  7. **Automated Verification Gates:**
     - Automated test suites must verify:
       - Client-side compression preserving hallmark clarity within 150–300 KB.
       - Offline capture and local sandboxed retrieval.
       - Upload retry and recovery following simulated network disconnects.
       - Immediate `403 Forbidden` rejection on unauthorized or cross-tenant image URL requests.
       - Hash verification detecting file tampering or corruption.

### AD-6 — Granular 14-Permission RBAC, Immediate Session Revocation & Database-Enforced Append-Only Audit Trails [ADOPTED]

- **Binds:** FR-5, FR-6, FR-7, FR-12, FR-16, FR-19, FR-20, FR-21, FR-22, FR-24, FR-26, FR-28, FR-29, FR-30, FR-31
- **Prevents:**
  - Privilege escalation, unauthorized disbursements, unapproved reversals, and illicit collateral releases.
  - Cross-tenant data leaks and forged tenant authorization headers.
  - Deactivated or terminated staff continuing counter operations on active terminal sessions.
  - Historical audit tampering, silent log truncation, or record destruction by any user or administrator.
  - Leaking sensitive credentials, passwords, or customer PII into diagnostic logs.
- **Rule:**
  1. **Strict 14-Permission Catalog (FR-6):**
     - The system implements and enforces the exact catalog of 14 permissions:
       1. `registerCustomers`
       2. `viewCustomers`
       3. `viewSensitiveCustomerData`
       4. `createCredits`
       5. `confirmCreditDisbursement`
       6. `recordPayments`
       7. `viewAndReprintReceipts`
       8. `viewOverdueCredits`
       9. `recordCustomerNotes`
       10. `requestCorrections`
       11. `approveCorrections` (Shop Owner only by default)
       12. `confirmCollateralReturn`
       13. `viewFinancialReports`
       14. `viewAuditLogs`
     - Adding, deleting, or altering permission semantics without a formal PRD amendment is prohibited.
  2. **Dual-Layer Authorization Enforcement:**
     - **Client (Presentation):** Riverpod typed selectors (e.g., `ref.watch(hasPermissionProvider(AppPermission.approveCorrections))`) declaratively disable or hide unauthorized buttons, tabs, and routes.
     - **Server (Data / API):** The server and PostgreSQL Row-Level Security unconditionally enforce tenant isolation and permission requirements on every API request, export generation, image access, and database mutation. Client-side checks are treated strictly as presentation conveniences, never as security boundaries.
  3. **Immediate Session Revocation (FR-5):**
     - User authentication tokens carry a server-validated `session_version` (or token identifier).
     - Deactivating an account or altering its permissions immediately increments the user's `session_version` on the server, causing all active sessions across counter terminals and browser tabs to fail subsequent requests with `401 Unauthorized` / `403 Forbidden`.
  4. **Sensitive Action Authorization Requirements:**
     - Explicit authorization is mandatory for:
       - Payment correction approvals (requires `approveCorrections`).
       - Due date extensions (requires Shop Owner role).
       - Cash disbursement confirmation (requires `confirmCreditDisbursement`).
       - Collateral release confirmation (requires `confirmCollateralReturn`).
       - Store financial reports and CSV/PDF data exports (requires `viewFinancialReports`).
       - Customer photo and collateral photo exception approvals (requires Shop Owner role).
  5. **Append-Only Audit Schema & Event Catalog (FR-31):**
     - Every critical event across the 14 defined categories generates an immutable audit entry:
       ```sql
       CREATE TABLE audit_events (
         id UUID PRIMARY KEY,
         tenant_id UUID NOT NULL,
         event_category TEXT NOT NULL,
         action_type TEXT NOT NULL,
         actor_user_id UUID NOT NULL,
         target_entity_type TEXT NOT NULL,
         target_entity_id UUID NOT NULL,
         pre_state JSONB,
         post_state JSONB,
         business_reason TEXT, -- Mandatory for corrections, reversals, exceptions & extensions
         client_ip TEXT,
         created_at TIMESTAMP NOT NULL DEFAULT NOW()
       );
       ```
     - Logging passwords, authentication tokens, or unnecessary sensitive identity data is strictly prohibited.
  6. **Database-Enforced Audit Immutability:**
     - In PostgreSQL, standard database users are granted `INSERT` and `SELECT` only on `audit_events`.
     - A database trigger unconditionally aborts and rolls back any attempt to execute `UPDATE` or `DELETE` on the `audit_events` table:
       ```sql
       CREATE OR REPLACE FUNCTION reject_audit_tampering() RETURNS TRIGGER AS $$
       BEGIN
         RAISE EXCEPTION 'Audit trail records are strictly immutable and cannot be updated or deleted.';
       END;
       $$ LANGUAGE plpgsql;

       CREATE TRIGGER trg_audit_immutable
       BEFORE UPDATE OR DELETE ON audit_events
       FOR EACH ROW EXECUTE FUNCTION reject_audit_tampering();
       ```
     - *Limitations & Stronger Protection:* Trigger protection safeguards against application-level exploits and standard DB users. For enterprise compliance and disaster recovery, database backups and audit archives must be replicated to write-once-read-many (WORM / Object Lock) storage.
  7. **Local SQLite Audit Records & Trust Hierarchy (R2 — approved, not yet implemented):**
     - In local Drift SQLite, audit records are protected at the application layer by exposing insert-only and query-only repository methods, and (for offline durability) by an append-only, hash-chained journal whose entries are written inside the same local ACID transaction as the business mutation. The journal's entries are not themselves authoritative audit events; they are durable pre-images.
     - The central cloud PostgreSQL `audit_events` table serves as the authoritative, cryptographically verified record of truth, and every journal entry is reconciled to it on synchronization. The journal survives device restarts but is not tamper-evident against a compromised device; enterprise-grade tamper evidence is provided by the server-side trigger and (per rule 6) by WORM/Object Lock replication of `audit_events`.
  8. **Offline Policy & Authorization Guarantees:**
     - Counter operations recorded while offline are explicitly marked `PendingServerAck` and cannot bypass permissions. High-risk administrative actions (e.g., approving corrections, due-date extensions, or administrative closures) are programmatically locked until central server connectivity is confirmed.
     - **Offline-permitted, journal-backed actions (R2/U-1, approved):** cash disbursement and cancellation of an undisbursed agreement are permitted while offline. The business mutation and its journal entry are written in the same local ACID transaction; the agreement state transitions immediately in the local database and the event is marked `Pending Server Confirmation` until server acknowledgement. Other high-risk administrative actions remain locked offline.
     - **Reconciliation of the local journal:** on connectivity, each `PendingServerAck` journal entry is appended to `audit_events` by the server-side audit writer (Story 1.3 / 1.8); a rejected entry is surfaced as `failed` with `lastError` and is never silently dropped; an entry is removed from the local journal only after server acknowledgement. A device lost before synchronization leaves a permanent gap, which FR-32's RPO does not cover; this is an accepted risk of the offline-first model.
  9. **Automated Verification Testing:**
     - Automated test suites verify:
       - Denial of unauthorized actions across all 14 permission toggles.
       - Complete rejection of cross-tenant access attempts (`403 Forbidden`).
       - Instant session termination upon account deactivation.
       - Rejection of database `UPDATE` and `DELETE` on `audit_events`.
       - Rejection of financial corrections and extensions when mandatory business reasons are missing.
   10. **Ownership & Epic Allocation (R2 — approved, not yet implemented):**
      - Story 1.3 (server-side append, trigger, RLS) and Story 1.8 (AuditService wiring) own the authoritative writer to `audit_events`.
      - The local append-only journal and the sync engine are owned by a new Story 1.x (offline audit durability) under Epic 1, with Story 7.3 (audit viewer) reading only from the authoritative store and Story 7.5 (disaster-recovery drill) extending its consistency checks to the journal's reconciliation.

### AD-7 — Test Pyramid Strategy with Automated CI Pipeline & Risk-Prioritized Coverage [ADOPTED]

- **Binds:** FR-1 through FR-33, Non-functional Verification Gates
- **Prevents:**
  - Financial calculation regressions, balance mismatches, and overpayment errors.
  - Cross-tenant data leakage or permission bypass vulnerabilities escaping into production.
  - Flaky, fragile end-to-end testing slowing down development velocity.
  - False confidence from SQLite mocks obscuring PostgreSQL-specific Row-Level Security syntax bugs.
  - Merging broken or unverified code into the `main` branch.
- **Rule:**
  1. **Risk-Prioritized Test Pyramid Architecture:**
     - **Base (~70% — Pure Dart Domain Unit Tests):**
       - Exercises core domain business logic: `Money` minor-unit math (AD-2), credit lifecycle state transitions (AD-3), preset and custom due-date calculator (FR-19 Cases 1–5), double-entry ledger balance formulas (FR-22 7 scenarios), independent collateral custody transitions (FR-16), and evaluation of all 14 RBAC permissions (AD-6).
       - Executes in pure Dart without Flutter widget tree or database setup in seconds.
     - **Middle (~20% — Integration & Real Database Invariant Tests):**
       - *Drift SQLite Integration:* Verifies schema migrations, foreign-key constraints, atomic transaction rollback behavior on mid-operation failure, and local offline sync queue operations.
       - *PostgreSQL Real-Instance Integration:* Uses a real PostgreSQL test instance (via test containers or local test DB) to verify Row-Level Security (RLS) policies, cross-tenant isolation attack attempts, and database triggers blocking `UPDATE`/`DELETE` on `audit_events`. Tests in SQLite are never treated as proof of PostgreSQL RLS security.
       - *Offline Sync & Network Invariants:* Verifies client retry backoff, idempotency deduplication on repeated submissions, interrupted image uploads, and post-network recovery.
     - **Top (~10% — Counter Flow Widget Tests):**
       - Uses Flutter `WidgetTester` to verify critical counter screens: customer lookup by NIC, credit agreement origination, payment submission, receipt snapshot preview, and reprint watermark rendering.
  2. **Boundary & Edge-Case Test Scenarios:**
     - Automated test suites must explicitly cover:
       - Full settlement zero-balance transition (`isZero == true`).
       - Partial payment balance deductions and overpayment validation blocks.
       - Approved payment reversals adding back exact minor units.
       - Overdue state transitions at 00:00:00 in the shop's local time zone (`Asia/Colombo`).
       - Due-date extensions preserving full history chains and mandatory reasons.
       - Session revocation immediately blocking subsequent in-flight requests.
  3. **Automated GitHub Actions CI Pipeline:**
     - Every push and pull request to `main` must pass an automated CI quality pipeline:
       1. Static analysis (`flutter analyze`): Strict zero-lint/zero-warning policy.
       2. Unit test suite (`flutter test test/unit/`).
       3. Integration and database security test suite (`flutter test test/integration/`).
       4. Counter widget smoke suite (`flutter test test/widget/`).
     - Passing all financial integrity and security tests is a mandatory gate for merging.
  4. **Test Independence & Data Hygiene:**
     - Tests must be completely deterministic and free of production customer data, live credentials, or external internet dependencies.
     - In-memory database fixtures and ephemeral test tenants are generated and torn down per test run.
  5. **Realistic Scope & Documented Verification Boundaries:**
     - Automated test suites verify implemented specifications, state machines, and relational constraints. They do not claim to mathematically prove the entire application bug-free under unmodelled hardware or cloud hosting failures. Testing boundaries and unverified operational factors must remain explicitly documented.

### AD-8 — Provider-Neutral Disaster Recovery, Point-in-Time Recovery (PITR) & High Availability Architecture [ADOPTED]

- **Binds:** FR-4, FR-22, FR-31, FR-32
- **Prevents:**
  - Catastrophic financial transaction data loss exceeding the PRD recovery point window.
  - Protracted counter operational downtime exceeding the recovery time threshold.
  - Ledger discrepancies, broken foreign-key relationships, or corrupted audit trails following database restoration.
  - Accidental permanent deletion or tampering of collateral/KYC photographs in cloud storage.
  - Premature or unverified SLA claims regarding disaster recovery capabilities.
  - Blind reliance on local counter devices without acknowledging offline hardware destruction risks.
- **Rule:**
  1. **Mandatory Recovery Objectives (FR-32):**
     - **Mandatory RPO:** $\le 15$ minutes maximum data loss window in any catastrophic infrastructure failure.
     - **Mandatory RTO:** $\le 4$ hours maximum duration to restore full operational service.
     - *Internal Target Calibration:* Internal engineering targets of $\text{RPO} \le 5$ minutes and $\text{RTO} \le 2$ hours are established as optimization goals; they are explicitly treated as targets subject to empirical verification during disaster recovery drills and must never be represented as guaranteed SLAs prior to verified demonstration.
  2. **Provider-Neutral Database Recovery Capabilities:**
     - The production PostgreSQL deployment must provide:
       - Continuous Write-Ahead Log (WAL) archiving or equivalent provider-supported Point-in-Time Recovery (PITR) capable of restoring to arbitrary second-level timestamps within the retention window (minimum 14–30 days).
       - Automated daily baseline snapshots encrypted at rest (AES-256) and in transit (TLS 1.3).
       - Geographically separate secondary backup replication (e.g., secondary cloud region or offsite cold vault) where supported by the infrastructure provider.
       - Formal, documented disaster recovery runbook detailing step-by-step restore execution, credential rotation, and tenant verification.
  3. **Financial Durability & Restored Ledger Integrity:**
     - Confirmed financial transactions (credits, cash disbursements, payments, approved reversals) are durable and irrevocable.
     - Following any restoration drill or disaster recovery event, automated consistency verification must prove:
       - Complete ledger balance equality: $\text{Balance} = \text{Principal} - \sum\text{Payments} + \sum\text{Reversals} \pm \sum\text{Adjustments}$.
       - Intact parent-child relationships across Tenants $\rightarrow$ Customers $\rightarrow$ Credits $\rightarrow$ Collateral Items $\rightarrow$ Payments.
       - Complete preservation of append-only `audit_events` with zero gaps or truncation.
     - Silent overwrites, arbitrary balance edits, or discarding confirmed financial records during restoration or reconciliation is strictly prohibited.
  4. **Offline Operations & Counter Device Fault Semantics (AD-1 Alignment):**
     - Local Drift SQLite provides resilient local data access during internet cuts.
     - Transactions recorded while offline remain explicitly flagged as `PendingServerAck` on the counter interface.
     - Client idempotency keys (`client_operation_id` UUIDv4) prevent duplicate postings upon reconnection.
     - *Operational Risk Acknowledged:* If a counter tablet or PC suffers catastrophic local hardware destruction (e.g. physical fire or water damage) *before* queued offline transactions have synchronized with the server, unacknowledged local transactions cannot be recovered from the cloud. Counter staff protocols must prioritize connecting devices to sync pending transactions promptly.
  5. **Collateral & Customer Photograph Recovery & Tenant Isolation:**
     - Cloud object storage must enforce Object Versioning and multi-zone redundancy.
     - Restored storage snapshots must maintain identical object key structures (`tenants/{tenant_id}/{entity_type}/{id}.webp`), ensuring every photo remains strictly mapped to its originating tenant, customer KYC profile, and collateral item record.
  6. **Pre-Production Disaster Recovery Drill Verification:**
     - Prior to commercial production go-live, the engineering team must execute and document a complete end-to-end disaster recovery drill:
       1. Simulate primary database failure.
       2. Restore from PITR backup to an isolated staging environment.
       3. Run automated integration and security test suites against the restored database to verify tenant isolation, RBAC, and ledger math.
       4. Clock and document actual achieved RPO and RTO.
     - Restore drills must be repeated semi-annually and following material infrastructure changes.
  7. **Provider Capability Evaluation Gate:**
     - Architecture requires evaluating the chosen cloud hosting provider (e.g. AWS RDS, Supabase, Neon, or DigitalOcean) against these exact specifications before provisioning production workloads.

## Stack

| Name | Version | Role |
| :--- | :--- | :--- |
| Flutter SDK | 3.47.5 stable | Cross-platform UI Framework |
| Dart SDK | 3.13.4 | Programming Language |
| Drift (SQLite) | ^2.24.0 | Local Relational Persistence & Offline Cache |
| PostgreSQL | 16+ | Authoritative Multi-Tenant Cloud Database with RLS |
| flutter_riverpod | ^2.6.0 | Reactive State Management & Dependency Injection |
| image | ^4.3.0 | Cross-Platform Image Compression & Processing |

## Structural Seed (Approved Source Tree)

```text
lib/
├── main.dart                          # Application bootstrap
├── app.dart                           # MaterialApp root, router & theme configuration
│
├── core/                              # Shared foundational infrastructure
│   ├── database/                      # Drift database instance, tables & schema migrations
│   ├── errors/                        # Failures, exceptions & error handling
│   ├── money/                         # Immutable Money value object & currency formatters (AD-2)
│   ├── permissions/                   # 14 RBAC permissions catalog & authorization guards
│   ├── sync/                          # Offline operation queue & sync reconciliation (AD-1)
│   ├── theme/                         # Design system, colors & branding styles
│   └── utils/                         # Timezone arithmetic (Asia/Colombo) & date helpers
│
└── features/                          # Business feature modules (vertical slices)
    ├── auth/                          # Staff login, token storage & session provider
    │   ├── domain/                    # User entity, AuthRepository interface, Role enum
    │   ├── data/                      # AuthRepositoryImpl, secure token storage
    │   └── presentation/              # LoginScreen, session controllers
    ├── shop/                          # Shop profile, branding & time zone configuration
    │   ├── domain/                    # ShopProfile entity, ShopRepository interface
    │   ├── data/                      # DriftShopDao, ShopRepositoryImpl
    │   └── presentation/              # ShopSettingsScreen, shop controllers
    ├── customers/                     # KYC profile onboarding, camera capture & search
    │   ├── domain/                    # Customer entity, CustomerRepository interface
    │   ├── data/                      # DriftCustomerDao, CustomerRepositoryImpl
    │   └── presentation/              # CustomerRegisterScreen, CustomerSearchScreen
    ├── collateral/                    # Multi-item collateral intake, weights & custody states
    │   ├── domain/                    # CollateralItem entity, CustodyStatus state machine
    │   ├── data/                      # DriftCollateralDao, CollateralRepositoryImpl
    │   └── presentation/              # CollateralIntakeWidget, ItemVerificationScreen
    ├── credits/                         # Principal tracking, terms, due dates & disbursements
    │   ├── domain/                    # Credit entity, CreditFinancialStatus state machine
    │   ├── data/                      # DriftCreditDao, CreditRepositoryImpl
    │   └── presentation/              # CreditOriginationScreen, CreditDetailScreen
    ├── payments/                      # Partial repayments, settlements, reversals & receipts
    │   ├── domain/                    # Payment entity, ReceiptSnapshot, Ledger calculator
    │   ├── data/                      # DriftPaymentDao, PaymentRepositoryImpl (ACID)
    │   └── presentation/              # PaymentScreen, ReceiptPrintDialog
    ├── overdue/                       # Delinquency review queues, extensions & notes
    │   ├── domain/                    # OverdueReview entity, ExtensionHistory
    │   ├── data/                      # OverdueRepositoryImpl
    │   └── presentation/              # OverdueQueueScreen, ExtensionDialog
    ├── reports/                       # Cash reconciliation dashboards & PDF/CSV export
    │   ├── domain/                    # DailyReconciliation entity, ExportService interface
    │   ├── data/                      # PdfReceiptGenerator, CsvExportService
    │   └── presentation/              # OwnerDashboardScreen, ReportExportScreen
    └── audit/                         # 14-event append-only audit trail viewer
        ├── domain/                    # AuditEvent entity, AuditLogRepository interface
        ├── data/                      # DriftAuditDao, AuditLogRepositoryImpl
        └── presentation/              # AuditLogViewerScreen
```

## Deferred (Post-V1 Architecture Candidates)

The following architectural dimensions are intentionally deferred beyond Version 1 in alignment with the PRD:
1. **Multi-Currency FX & Dynamic Wallets:** Single base ledger currency (LKR baseline) locked post-transaction; multi-currency floating ledger deferred.
2. **Automated Reminders & SMS/WhatsApp Integration:** Outgoing notification gateway architectures deferred pending provider and cost evaluation.
3. **Multi-Branch Corporate Hierarchy:** Centralized inventory pooling across separate physical storefronts deferred; strictly independent shop tenants in Version 1.
4. **Bi-directional Third-Party Accounting Sync:** QuickBooks / Xero API synchronization bridges deferred to post-pilot roadmap.

