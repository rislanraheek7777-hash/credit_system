---
status: final
stepsCompleted:
  - step-01-validate-prerequisites
  - step-02-design-epics
  - step-03-create-stories
  - step-04-final-validation
inputDocuments:
  - _bmad-output/planning-artifacts/prds/prd-credit_system-2026-10-13/prd.md
  - _bmad-output/planning-artifacts/architecture/architecture-credit_system-2026-10-14/ARCHITECTURE-SPINE.md
  - _bmad-output/planning-artifacts/briefs/brief-credit_system-2026-10-13/brief.md
  - _bmad-output/planning-artifacts/briefs/brief-credit_system-2026-10-13/addendum.md
---

# credit_system - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for **Credit Management System**, decomposing all 33 requirements from the finalized Product Requirements Document (PRD) and 8 approved Architecture Decisions (AD-1 through AD-8) into user-value-focused, implementable epics and stories.

---

## Requirements Inventory

### Functional Requirements

* **FR-1:** Shop Profile Configuration (Shop name, business address, contact details, registration/tax numbers, shop logo, custom receipt header and footer notes; profile updates apply to future receipts without altering historical snapshots; tenant-isolated).
* **FR-2:** Shop Timezone & Calendar Semantics (Configurable shop local time zone defaulting to `Asia/Colombo`; automated overdue evaluation takes effect at 00:00:00 on the calendar day after due date).
* **FR-3:** Configurable Currency Display (Presentation formatting decoupled from base ledger currency; default Sri Lankan Rupees `LKR`; base ledger currency locked post-transaction to prevent misrepresenting financial records).
* **FR-4:** Strict Server-Side Tenant Isolation (RLS enforced across all queries, lookups, API routes, and database operations; zero cross-tenant leakage).
* **FR-5:** Staff Account Administration & Immediate Session Revocation (Owner creates, activates, deactivates staff accounts; deactivation immediately increments `session_version` and revokes active terminal sessions).
* **FR-6:** Granular 14-Permission RBAC Catalog (Explicit unmodifiable catalog: `registerCustomers`, `viewCustomers`, `viewSensitiveCustomerData`, `createCredits`, `confirmCreditDisbursement`, `recordPayments`, `viewAndReprintReceipts`, `viewOverdueCredits`, `recordCustomerNotes`, `requestCorrections`, `approveCorrections`, `confirmCollateralReturn`, `viewFinancialReports`, `viewAuditLogs`).
* **FR-7:** Restricted Platform Administrator Governance (Default-denied access to tenant customer PII and ledgers; emergency access requires explicit audited authorization).
* **FR-8:** Reusable Customer Profile Onboarding (Mandatory KYC fields: Full Name, NIC Number, Contact Phone, Address, Customer Photo; reusable across multiple credits in current shop).
* **FR-9:** Mandatory Customer Photo Capture & Exception Workflow (Camera capture or file upload with pre-save preview; strictly mandatory by default; exception requires documented reason and Shop Owner approval).
* **FR-10:** Shop-Scoped Duplicate Detection & Shared-Phone Resolution (Automated pre-creation match on NIC [blocked] and Phone [warning with verified confirmation log]).
* **FR-11:** Customer Search & Multi-Credit Navigation (Search by NIC, phone, or name strictly within active shop; explicit target credit selection prompt when customer holds multiple credits).
* **FR-12:** Server-Side Sensitive Customer Data Masking (NIC, address, and photo protected on server; masked for unauthorized roles unless possessing `viewSensitiveCustomerData`).
* **FR-13:** Item Receipt Registration per Credit (Support for zero or more item receipts per credit agreement — attachment is optional; unique item reference IDs generated for attached items).
* **FR-14:** Collateral Attribute Capture & Decimal Weight Calibration (Item Category [Gold/Jewelry, Electronics, Valuables], Description, Condition Grading, Estimated Collateral Value; calibrated decimal gram weights mandatory for gold).
* **FR-15:** Mandatory Item Receipt Photographs & Shop Owner Exception Workflow (Photo mandatory for every attached item receipt; exception requires documented reason and Shop Owner approval; does not require at least one item receipt).
* **FR-16:** Independent Per-Item Custody Tracking & Administrative Closure (Physical custody states: `In Custody`, `Returned`, `Exception / Held`; financial settlement does not mark items returned; administrative closure with exception supported).
* **FR-17:** Credit Term Selection & Preliminary Due Date Display (30/60/90-day duration presets or custom date picker; preliminary due date explicitly labeled prior to cash disbursement).
* **FR-18:** Zero-Interest Principal Tracking & Creation Idempotency (Total repayment obligation equals principal; no automated interest or hidden fees; idempotency guard prevents double creation).
* **FR-19:** Decoupled Cash Disbursement Confirmation & Official Due Date Calculation (Agreement creation decoupled from cash disbursement; official calendar due date calculated upon disbursement confirmation via Cases 1–5).
* **FR-20:** Credit Agreement Documentation & Cash Disbursement Voucher (Executed credit voucher distinguished from draft agreement; thermal print and PDF export).
* **FR-21:** Partial Payments & Full Settlement with Overpayment Protection (Cash payments against disbursed credits; `Payment <= Valid Outstanding Balance`; balance reaches zero transitions to `Settled`).
* **FR-22:** Exact Monetary Decimal Precision & Double-Entry Ledger Formula (All math in integer minor units [cents]; 100 minor units per LKR; formula: $\text{Balance} = \text{Principal} - \sum\text{Payments} + \sum\text{Reversals} \pm \sum\text{Adjustments}$; 7 verification scenarios).
* **FR-23:** Payment Concurrency, Idempotency & Correction-Pending Lock (Client idempotency keys; optimistic concurrency prevents double-spend; payment locked on credit while correction is pending owner approval).
* **FR-24:** Immutable Receipt Snapshot Model & Reprint Watermarking (Historical branding and financial snapshot captured at payment; reprints render original snapshot with `*** REPRINT ***` watermark and audit log).
* **FR-25:** Automated Overdue State Evaluation (Evaluated against local midnight boundary [Due Date + 1] in `Asia/Colombo` if balance > 0; settled credits never overdue).
* **FR-26:** Shop Owner Due Date Extension Workflow (Owner-only; mandatory reason; resets overdue status until new date passes; full extension history preserved).
* **FR-27:** Overdue Customer Follow-Up & Promise to Pay Logging (Communication channel, notes, and promised payment dates logged and surfaced on review queues).
* **FR-28:** Structured Owner Resolution & Collateral Disposition Recording (Owner case review states: `Under Review`, `Owner Settled / Written Off`, `Collateral Retained`; strictly no automated liquidation or auction).
* **FR-29:** Shop Owner Operational & Cash Reconciliation Dashboards (Real-time daily cash in vs. confirmed cash out; active/overdue/settled credit counts; vault collateral item count; pending corrections queue).
* **FR-30:** Audited Tabular Data Export in PDF & CSV (Daily cash collection ledger, customer portfolio, delinquency report, vault inventory; customer PII masked unless authorized; export events audited).

---

### Non-Functional Requirements

* **FR-31 (NFR-1):** Append-Only, Tamper-Resistant Audit Trail (Mandatory logging across 14 critical event categories; immutable database trigger rejects `UPDATE` and `DELETE`; pre/post state JSON diffs; mandatory reasons; zero credential logging).
* **FR-32 (NFR-2):** Data Backup, Disaster Recovery & Durability (Mandatory RPO $\le 15$ minutes, RTO $\le 4$ hours; continuous WAL archiving / Point-in-Time Recovery; S3/R2 object versioning; documented restore drill verification).
* **FR-33 (NFR-3):** Automated Security & Integrity Verification Gates (Automated test suites verifying 100% rejection of cross-tenant access attempts and denial across all 14 RBAC permission toggles; mandatory CI merge gate).

---

### Additional Requirements from Technical Architecture

* **AD-1 (Storage Architecture):** Dual-tier relational storage using Drift (SQLite) locally for responsive counter operations + PostgreSQL 16+ cloud source of truth with Row-Level Security (RLS). Offline sync queue with `PendingServerAck` vs. `ConfirmedByServer` states and UUID idempotency keys.
* **AD-2 (Monetary Math):** All financial calculations represented in integer minor units (100 cents per LKR). Dedicated immutable `Money` Value Object. Dart `double` strictly prohibited for money. Stored as SQLite `INTEGER` and PostgreSQL `BIGINT`.
* **AD-3 (State Management):** Pure Dart Finite State Machines for decoupled Credit Lifecycle (`pendingDisbursement` $\rightarrow$ `active` $\rightarrow$ `overdue` $\rightarrow$ `settled`) and Collateral Custody (`inCustody` $\rightarrow$ `returned` $\rightarrow$ `exceptionHeld`). Overall workflow status derived dynamically. Riverpod `AsyncNotifier` application controllers with typed permission selectors and payment locks.
* **AD-4 (Clean Architecture):** Feature-first modular organization across 9 business domains (`auth`, `shop`, `customers`, `collateral`, `credits`, `payments`, `overdue`, `reports`, `audit`) + `core/`. Inward dependency rule: `domain` (pure Dart, zero dependencies) $\leftarrow$ `data` & `presentation`.
* **AD-5 (Image Storage Pipeline):** Client-side image compression (max 1600px, 150–300 KB target WebP/JPEG preserving gold hallmarks and serial numbers). Relational database stores metadata only. Sandboxed local storage (app documents on mobile/desktop, OPFS/IndexedDB on web) + private cloud object storage with short-lived ($\le 15$m) signed URLs.
* **AD-6 (RBAC & Audit Immutability):** 14-permission catalog enforced on client and server. Immediate session revocation via server-validated `session_version`. PostgreSQL database trigger unconditionally blocks `UPDATE` and `DELETE` on `audit_events`.
* **AD-7 (Test Pyramid & CI):** Risk-prioritized test suite (~70% pure Dart unit, ~20% integration with real PostgreSQL RLS, ~10% counter widget flows) automated via GitHub Actions as a mandatory merge gate.
* **AD-8 (Disaster Recovery & PITR):** Mandatory RPO $\le 15$m, RTO $\le 4$h. Continuous WAL archiving for PITR, encrypted daily snapshots, S3/R2 object versioning, and documented restore drill verification.

---

### UX Design Requirements

* **UX-DR-1:** High-contrast, responsive counter interface optimized for physical retail environments (desktop browsers and tablets).
* **UX-DR-2:** Camera capture widget with live device camera/webcam viewfinder, pre-save review, image retake, and local crop/preview.
* **UX-DR-3:** Dynamic multi-credit customer view with distinct visual status badges (`Active`, `Overdue`, `Settled`) and mandatory target credit selection prompt prior to payment processing.
* **UX-DR-4:** Live credit origination summary widget displaying real-time preliminary due date calculations and collateral valuation totals as items are added.
* **UX-DR-5:** Payment recording interface with dynamic outstanding balance preview, instant overpayment blocking validation, and confirmation modal.
* **UX-DR-6:** Prominent visual watermark and visual banner for draft credit slips (`*** DRAFT / PENDING DISBURSEMENT ***`) and reprinted receipts (`*** REPRINT ***`).
* **UX-DR-7:** Prominent credit-scoped `Locked` banner on payment screens when a financial correction is pending Shop Owner review.
* **UX-DR-8:** Offline synchronization indicator on app bar displaying sync status (`Synced`, `Pending Server Confirmation [N items]`, or `Offline`).

---

### FR Coverage Map

* **FR-1:** Epic 1 — Shop Profile Configuration
* **FR-2:** Epic 1 (Timezone configuration) & Epic 6 (Midnight boundary evaluation)
* **FR-3:** Epic 1 — Configurable Currency Display
* **FR-4:** Epic 1 (Authoritative RLS schema) & Epics 2–7 (Cross-cutting boundary test verification)
* **FR-5:** Epic 1 — Staff Account Administration & Session Revocation
* **FR-6:** Epic 1 (Authoritative 14-permission RBAC catalog) & Epics 2–7 (Permission gate enforcement on actions)
* **FR-7:** Epic 1 (Restricted platform administrator default-deny) & Epics 2–7 (Tenant boundary protection)
* **FR-8:** Epic 2 — Reusable Customer Profile Onboarding
* **FR-9:** Epic 2 — Mandatory Customer Photo Capture & Exception Workflow
* **FR-10:** Epic 2 — Shop-Scoped Duplicate Detection & Shared-Phone Resolution
* **FR-11:** Epic 2 — Customer Search & Multi-Credit Navigation
* **FR-12:** Epic 1 (Masking permissions) & Epic 2 (Customer PII display) & Epic 7 (Tabular export masking)
* **FR-13:** Epic 3 — Multi-Item Collateral Registration per Credit
* **FR-14:** Epic 3 — Collateral Attribute Capture & Decimal Weight Calibration
* **FR-15:** Epic 3 — Mandatory Collateral Photographs & Exception Workflow
* **FR-16:** Epic 3 — Independent Per-Item Custody Tracking & Administrative Closure
* **FR-17:** Epic 4 — Credit Term Selection & Preliminary Due Date Display
* **FR-18:** Epic 4 — Zero-Interest Principal Tracking & Creation Idempotency
* **FR-19:** Epic 4 — Decoupled Cash Disbursement Confirmation & Official Due Date Calculation (Cases 1–5)
* **FR-20:** Epic 4 — Credit Agreement Documentation & Cash Disbursement Voucher
* **FR-21:** Epic 5 — Partial Payments & Full Settlement with Overpayment Protection
* **FR-22:** Epic 5 — Exact Monetary Decimal Precision & Double-Entry Ledger Formula (7 test scenarios)
* **FR-23:** Epic 5 — Payment Concurrency, Idempotency & Correction-Pending Lock
* **FR-24:** Epic 5 — Immutable Receipt Snapshot Model & Reprint Watermarking
* **FR-25:** Epic 6 — Automated Overdue State Evaluation (Asia/Colombo midnight boundary, Balance > 0, Exclude Settled)
* **FR-26:** Epic 6 — Shop Owner Due Date Extension Workflow (Owner-only, mandatory reason, status reset)
* **FR-27:** Epic 6 — Overdue Customer Follow-Up & Promise to Pay Logging
* **FR-28:** Epic 6 — Structured Owner Resolution & Collateral Disposition Recording (Zero automated liquidation)
* **FR-29:** Epic 7 — Shop Owner Operational & Cash Reconciliation Dashboards
* **FR-30:** Epic 7 — Audited Tabular Data Export in PDF & CSV (PII masked unless authorized)
* **FR-31 (NFR-1):** Epic 1 (Authoritative append-only schema & trigger) & Epics 1–7 (Cross-cutting logging of all 14 critical event categories)
* **FR-32 (NFR-2):** Epic 1 (Core continuous WAL archiving & storage versioning) & Epic 7 (Disaster recovery drill protocol & readiness reporting: mandatory RPO <= 15m, RTO <= 4h)
* **FR-33 (NFR-3):** Epic 1 (Automated CI test pipeline setup) & Epics 1–7 (Mandatory CI merge gates for zero cross-tenant leakage & 14-permission RBAC suites)
* **FR-34:** Epic 1 — Secure Staff Credential Recovery (single-use OTP, server-authoritative reset, session revocation)

---

## Architecture Dependencies & Implementation Order

Rather than an arbitrary waterfall chain, implementation proceeds according to a true Directed Acyclic Graph (DAG) of functional prerequisites, allowing parallelization while guaranteeing that security, tenant isolation, and audit foundations are established on Day 1:

```mermaid
flowchart TD
    subgraph Foundation ["Foundational Core (Day 1 Infrastructure)"]
        CORE["core/ (Money VO, Drift SQLite, Postgres RLS, Audit Trigger, CI Gates, WAL PITR)"]
        E1["Epic 1: Shop Administration, Staff RBAC & Secure Multi-Tenant Workspace"]
        CORE --> E1
    end

    subgraph ParallelIntake ["Parallel Counter Intake Modules"]
        E2["Epic 2: Customer Identity, KYC Onboarding & Profiles"]
        E3["Epic 3: Multi-Item Collateral Intake, Appraisal & Custody"]
    end

    subgraph CoreTransactionLoop ["Core Retail Transaction Loop (Release Phase 1 MVP)"]
        E4["Epic 4: Zero-Interest Credit Origination & Cash Disbursement"]
        E5["Epic 5: Payment Processing, Fixed-Point Ledgers & Receipts"]
    end

    subgraph GovernanceAnalytics ["Governance, Analytics & Durability (Release Phases 2 & 3)"]
        E6["Epic 6: Overdue Credit Governance, Extensions & Owner Decisions"]
        E7["Epic 7: Operational Cash Dashboards, Data Export & Disaster Recovery"]
    end

    E1 --> E2
    E1 --> E3
    E2 --> E4
    E3 --> E4
    E4 --> E5
    E4 --> E6
    E5 -.->|Ledger Balance| E6
    E1 --> E7
    E4 --> E7
    E5 --> E7
    E6 --> E7
```

* **Parallel Execution Opportunities**: Epics 2 and 3 are completely decoupled clean architecture modules (`features/customers` and `features/collateral`) and can be developed concurrently once Epic 1 establishes the workspace.
* **MVP Release Phase 1**: Epics 1 + 2 + 3 + 4 + 5 complete 100% of the counter transaction lifecycle (shop setup, KYC, collateral intake, credit issuance, cash disbursement, partial payments, full settlement, and printed receipts).
* **Release Phase 2**: Epic 6 activates delinquency governance, customer promise-to-pay tracking, owner extensions, and manual collateral dispositions.
* **Release Phase 3**: Epic 7 delivers executive cash reconciliation, audited tabular reporting, and verified disaster recovery drill reports.

---

## Epic List

#### Epic Overview Summary

**Epic 1: Shop Administration, Staff RBAC & Secure Multi-Tenant Workspace**  
Shop Owners can configure their shop profile, local timezone (`Asia/Colombo`), branding, and currency display; manage counter staff accounts with the 14-permission RBAC catalog; immediately revoke sessions upon account deactivation via server-validated `session_version`; operate in a strictly isolated multi-tenant environment (PostgreSQL RLS); initialize the append-only audit log trigger rejecting `UPDATE`/`DELETE`; configure continuous WAL archiving for PITR (mandatory RPO <= 15m, RTO <= 4h); and establish the automated CI test pipeline; and provide self-service staff credential recovery in-app against SQLite (Story 1.10).  
* **FRs covered:** FR-1, FR-2, FR-3, FR-4, FR-5, FR-6, FR-7, FR-12, FR-31, FR-32, FR-33, FR-34  
* **Architecture:** AD-1 (PostgreSQL RLS, Drift SQLite), AD-2 (Integer minor units / Money Value Object), AD-4 (`features/shop`, `features/auth`, `core/`), AD-6 (RBAC & session revocation, audit trigger), AD-7 (CI pipeline setup), AD-8 (Base WAL archiving setup), AD-9 (Transactional OTP & credential recovery)

**Epic 2: Customer Identity, KYC Onboarding & Profile Management**  
Counter staff can quickly register new and returning customers with complete KYC details (Name, NIC, Phone, Address, Customer Photo); capture device/webcam photos or submit owner-approved photo exceptions; resolve shared-phone duplicate warnings while blocking duplicate NICs; securely access masked identity data based on `viewSensitiveCustomerData` permission; navigate multi-credit customer profiles; log audit events for onboarding and overrides; and verify zero cross-tenant customer data leakage in automated CI tests.  
* **FRs covered:** FR-8, FR-9, FR-10, FR-11, FR-12, FR-31, FR-33  
* **Architecture:** AD-4 (`features/customers`), AD-5 (Customer photo optimization & sandboxing), AD-6 (Data masking & audit logging), UX-DR-2, UX-DR-3

**Epic 3: Multi-Item Collateral Intake, Appraisal & Custody Tracking**  
Counter staff can document and photograph multiple pledged valuables (gold jewelry with calibrated decimal gram weights, consumer electronics, general valuables) under a credit; preview captured photos or submit owner exception requests; independently track the physical custody lifecycle of each item (`In Custody`, `Returned`, `Exception / Held`) decoupled from financial settlement; record administrative closures with mandatory reasons; log audit events for custody transitions; and verify cross-tenant collateral isolation in CI.  
* **FRs covered:** FR-13, FR-14, FR-15, FR-16, FR-31, FR-33  
* **Architecture:** AD-3 (Collateral custody state machine), AD-4 (`features/collateral`), AD-5 (Collateral photo pipeline), AD-6 (Custody audit logging)

**Epic 4: Zero-Interest Credit Origination & Cash Disbursement**  
Counter staff and Shop Owners can configure zero-interest credit agreements with preset or custom terms; preview preliminary due dates; generate draft agreement slips; guard against duplicate creation via idempotency keys; explicitly confirm cash disbursement; calculate official due dates from confirmed disbursement dates (Cases 1–5); issue executed disbursement vouchers; log agreement and disbursement audit events; and enforce `createCredits` and `confirmCreditDisbursement` RBAC permissions.  
* **FRs covered:** FR-17, FR-18, FR-19, FR-20, FR-31, FR-33  
* **Architecture:** AD-2 (Integer minor units principal), AD-3 (Credit lifecycle state machine), AD-4 (`features/credits`), UX-DR-4, UX-DR-6, AD-6 (Disbursement permissions & audit)

**Epic 5: Payment Processing, Fixed-Point Ledgers & Receipt Snapshots**  
Counter staff can record partial payments and full settlements with anti-overpayment validation ($Payment \le OutstandingBalance$); calculate exact balances using integer minor units and double-entry ledger formulas ($\text{Balance} = \text{Principal} - \sum\text{Payments} + \sum\text{Reversals} \pm \sum\text{Adjustments}$); execute atomic transactions with UUID idempotency keys and optimistic concurrency locks; generate immutable receipt snapshots with reprint watermarking (`*** REPRINT ***`); request payment corrections with automatic credit-scoped payment locks (`LockedForCorrection`); process Shop Owner approval/rejection with compensating reversal entries; propose and (Shop Owner) approve staff-initiated balance adjustments for partial forgiveness (Story 5.6); log all financial and reprint audit events; and satisfy all 7 financial verification scenarios.  
* **FRs covered:** FR-21, FR-22, FR-23, FR-24, FR-31, FR-33  
* **Architecture:** AD-1 (ACID transactions, offline sync queue), AD-2 (Money Value Object & cents ledger math), AD-3 (Payment lock), AD-4 (`features/payments`), UX-DR-5, UX-DR-6, UX-DR-7, AD-6 (Correction permissions & audit logging)

**Epic 6: Overdue Credit Governance, Extensions & Owner Decisions**  
Shop Owners and authorized staff can identify delinquent credits automatically at the local midnight boundary (`Asia/Colombo`) strictly when outstanding balance > 0 (excluding fully settled credits); review overdue queues; record customer communication notes and promises to pay; grant Shop-Owner-only due date extensions with mandatory reasons, updating due dates and resetting dynamic status to `Active` while preserving complete immutable extension history; record structured administrative resolutions (`Under Review`, `Owner Settled / Written Off`, `Collateral Retained`) with zero automated collateral liquidation; log all overdue actions in the audit trail; and enforce `viewOverdueCredits` permission.  
* **FRs covered:** FR-25, FR-26, FR-27, FR-28, FR-31, FR-33  
* **Architecture:** AD-2 (Balance validation), AD-3 (Overdue state evaluation & status reset), AD-4 (`features/overdue`), AD-6 (Owner-only extension governance & audit logging)

**Epic 7: Operational Cash Dashboards, Data Export & Disaster Recovery**  
Shop Owners can view real-time daily cash movements (cash in vs. confirmed cash out), portfolio balances, vault inventory counts, and pending corrections queue; export audited tabular reports in PDF and CSV with PII masked unless possessing `viewSensitiveCustomerData`; view the tamper-resistant activity audit trail; monitor disaster recovery health and backup timestamps; and execute and document disaster recovery verification drills verifying mandatory RPO <= 15m and RTO <= 4h.  
* **FRs covered:** FR-29, FR-30, FR-31, FR-32, FR-33  
* **Architecture:** AD-1 (Offline sync queue & recovery), AD-4 (`features/reports`, `features/audit`), AD-6 (Audit trigger immutability), AD-7 (Automated test suites & CI verification gates), AD-8 (PITR WAL archiving, S3 versioning, and restore drills), UX-DR-8

---

## Epic 1: Shop Administration, Staff RBAC & Secure Multi-Tenant Workspace

Shop Owners can configure their shop profile, local timezone (`Asia/Colombo`), branding, and currency display; manage counter staff accounts with the 14-permission RBAC catalog; immediately revoke sessions upon account deactivation via server-validated `session_version`; operate in a strictly isolated multi-tenant environment (PostgreSQL RLS); initialize the append-only audit log trigger rejecting `UPDATE`/`DELETE`; configure continuous WAL archiving for PITR (mandatory RPO <= 15m, RTO <= 4h); establish the automated CI test pipeline; and provide self-service staff credential recovery in-app against SQLite (Story 1.10).

### Story 1.1: Immutable Money Value Object & Monetary Precision Foundations

As a Software Developer and Shop Owner,  
I want an immutable `Money` Value Object representing financial amounts in integer minor units (cents) with currency validation, rounding prevention, and strict prohibition of Dart `double`,  
So that all financial calculations across the platform are mathematically exact, safe from floating-point distortion, and permanently auditable.

**Acceptance Criteria:**

**Given** the financial domain in `core/domain/value_objects/money.dart`  
**When** any monetary amount is instantiated  
**Then** it is represented internally strictly as an integer count of minor units (cents for LKR: 100 cents = 1 Rupee)  
**And** Dart `double` is strictly prohibited for monetary representation, calculations, and storage across all domain, data, and presentation models.

**Given** two `Money` instances of the same currency (`LKR`)  
**When** addition, subtraction, or comparisons (`<`, `<=`, `>`, `>=`, `==`) are performed  
**Then** exact integer arithmetic is returned  
**And** subtracting an amount larger than the balance throws an `InvalidNegativeBalanceException` unless explicitly modeling a signed adjustment  
**And** addition or subtraction across mismatched currencies throws an `IncompatibleCurrencyException`.

**Given** user input from counter text fields or API parameters  
**When** a monetary string is parsed (e.g. `"1500.50"`, `"250"` or `"0.75"`)  
**Then** it correctly parses into integer cents (`150050`, `25000`, `75`)  
**And** any input containing more than two decimal places (e.g. `"1500.555"`) is rejected with a validation error.

**Given** a `Money` instance  
**When** formatted for screen display, receipts, or reports  
**Then** it formats as `"Rs. 1,500.50"` with thousand separators and exactly two decimal places  
**And** the internal state remains strictly integer cents.

**Given** Drift SQLite and PostgreSQL mapping layers  
**When** serialized to the database  
**Then** the value persists as SQLite `INTEGER` and PostgreSQL `BIGINT` (cents)  
**And** deserialization reconstructs the immutable `Money` Value Object without loss of precision.

* **Traceability:** FR-3, FR-22, AD-2
* **Dependencies:** None (Pure Dart core package)
* **Testing Guidance:** Unit tests in `test/core/domain/value_objects/money_test.dart` testing 100% of arithmetic operations, zero-balance checks, overflow/underflow, negative balance prevention, currency matching, decimal string parsing, formatting, and Drift/PostgreSQL serialization adapters.

---

### Story 1.2: SQLite Relational Database Foundations & Migration Harness

> **SQLite-only amendment (2026-11-25):** PostgreSQL, dual-tier sync, and `PendingServerAck`/`ConfirmedByServer` are void. Drift SQLite is the sole authority; all ACs referring to cloud migration or server acknowledgment are superseded by local schema/migration tests.

As a Software Developer,  
I want dual-tier relational database connections configured for local Drift (SQLite) and cloud PostgreSQL 16+ with safe schema migration harnesses and an offline synchronization queue schema,  
So that the application has responsive local persistence at the counter alongside a durable cloud source of truth.

**Acceptance Criteria:**

**Given** the local client runtime on mobile, desktop, or web  
**When** the database helper initializes in `core/data/local/`  
**Then** Drift opens the SQLite database in app-private sandboxed storage (`getApplicationDocumentsDirectory` on mobile/desktop, OPFS/Wasm on web)  
**And** core tables (`shops`, `app_users`, `sync_queue`) are created with primary keys, foreign keys, and indices.

**Given** cloud database connection configuration  
**When** schema migrations execute in `core/data/remote/`  
**Then** base relational tables (`shops`, `app_users`, `audit_events`, `sync_queue`) are created in PostgreSQL 16+ using appropriate data types (`UUID` for IDs, `BIGINT` for currency minor units, `TIMESTAMPTZ` for dates)  
**And** migration rollback and version tracking are verified.

**Given** the `sync_queue` table on local Drift and cloud PostgreSQL  
**When** records are queued for cloud synchronization  
**Then** each row stores `id` (UUID), `shop_id` (UUID), `entity_type`, `entity_id`, `idempotency_key` (UUID), `action_type`, `payload_json`, `created_at`, `status` (`pending_server_ack` vs. `confirmed_by_server`), and `retry_count`  
**And** transactions are never marked as cloud-confirmed until explicit server acknowledgment is received.

**Given** local counter actions and cloud sync operations  
**When** an operation is recorded  
**Then** the local Drift SQLite write executes as a distinct, self-contained ACID transaction  
**And** the cloud PostgreSQL synchronization executes as a separate, distinct server transaction  
**And** failures in cloud synchronization do not roll back confirmed local offline storage, but update sync queue status to `retry_pending`.

* **Traceability:** AD-1, AD-4
* **Dependencies:** Story 1.1 (Money value object)
* **Testing Guidance:** Drift schema creation and migration tests; local CRUD integration tests; PostgreSQL connection and migration tests; sync queue state transition tests (`pending_server_ack` -> `confirmed_by_server`).

---

### Story 1.3: Application-Enforced Tenant Isolation & SQLite Append-Only Audit Trigger

> **SQLite-only amendment (2026-11-25):** RLS policies, `app.current_shop_id`, `NOBYPASSRLS` and server-side audit writer are replaced by: (a) repository guards that scope every query to the authenticated `shop_id`, verified by cross-tenant repository tests; (b) SQLite `BEFORE UPDATE/DELETE ... RAISE(ABORT)` triggers on `audit_events`.

As a Platform Security Officer and Shop Owner,  
I want server-enforced PostgreSQL Row-Level Security (RLS) driven strictly by trusted authentication context, alongside a database trigger that rejects all `UPDATE` and `DELETE` operations on audit logs,  
So that cross-tenant data leakage is physically prevented at the database engine level and the audit trail is immutable even against elevated application roles.

**Acceptance Criteria:**

**Given** multi-tenant tables in PostgreSQL (`shops`, `app_users`, `audit_events`, and all future business tables)  
**When** database migrations apply  
**Then** `ALTER TABLE ... ENABLE ROW LEVEL SECURITY;` is executed on every table  
**And** `FORCE ROW LEVEL SECURITY` is enabled so table owners and application roles are bound by policies  
**And** RLS policies enforce `shop_id = current_setting('app.current_shop_id', true)::uuid`.

**Given** incoming client requests to the server API  
**When** request authentication executes  
**Then** `shop_id` is derived strictly from the cryptographically verified JWT session claims signed by the server  
**And** client-supplied query parameters, headers, or body attributes claiming a `shop_id` are ignored and forbidden from overriding the context  
**And** the server sets `app.current_shop_id` within a transaction boundary using `SET LOCAL app.current_shop_id = :trusted_shop_id`.

**Given** the PostgreSQL connection pool used by the application backend  
**When** transactions execute and release connections  
**Then** the application database role has `NOBYPASSRLS` privileges  
**And** `SET LOCAL` guarantees that tenant context is strictly scoped to the transaction and automatically cleared upon transaction commit/rollback, preventing tenant leakage across pooled connections.

**Given** the `audit_events` table in PostgreSQL  
**When** the table is created  
**Then** it includes columns: `event_id` (UUID), `shop_id` (UUID), `event_category` (INTEGER 1–14 matching the PRD), `action_type` (TEXT), `actor_id` (UUID), `target_entity_type` (TEXT), `target_entity_id` (UUID), `pre_state_json` (JSONB), `post_state_json` (JSONB), `reason` (TEXT), `client_ip` (TEXT), `user_agent` (TEXT), `server_timestamp` (TIMESTAMPTZ)  
**And** a PostgreSQL database trigger (`BEFORE UPDATE OR DELETE ON audit_events`) unconditionally raises an exception (`RAISE EXCEPTION 'Audit trail records are append-only and cannot be modified or deleted.';`)  
**And** permissions to `ALTER`, `DROP TRIGGER`, or `TRUNCATE` on `audit_events` are revoked from the application database role.

* **Traceability:** FR-4, FR-31 (Invariants), AD-1, AD-6, FR-33
* **Dependencies:** Story 1.2 (Database foundations)
* **Testing Guidance:** Integration tests on a real PostgreSQL test database asserting that:
  - Queries with mismatched `app.current_shop_id` return zero rows.
  - Queries without setting `app.current_shop_id` fail or return zero rows.
  - Attempting to execute `UPDATE audit_events SET reason = 'tampered'` throws fatal trigger exception.
  - Attempting to execute `DELETE FROM audit_events` throws fatal trigger exception.
  - Testing connection pool re-use confirms tenant context does not leak into subsequent queries.

---

### Story 1.4: Local SQLite File Backup & Restore-Drill Harness

> **SQLite-only amendment (2026-11-25):** No WAL archiving, PITR, S3/R2 versioning or cloud provider. Backup = user-initiated SQLite file export with `PRAGMA integrity_check`; restore drill = file restore + integrity + known-record check.

As a Shop Owner and Systems Administrator,  
I want continuous Write-Ahead Log (WAL) archiving configured for Point-in-Time Recovery (PITR), versioned cloud object storage, and an automated restore drill script,  
So that database recovery capabilities meeting RPO <= 15 minutes and RTO <= 4 hours are provisioned from the beginning and verified through empirical testing.

**Acceptance Criteria:**

**Given** the production/staging cloud PostgreSQL instance  
**When** database backup infrastructure is provisioned  
**Then** WAL archiving (`archive_mode = on`, `archive_command` or managed provider PITR) is enabled with continuous upload to isolated backup storage  
**And** recovery point granularity supports restoring to any timestamp within the retention window, targeting RPO <= 15 minutes.

**Given** cloud object storage (S3/Cloudflare R2)  
**When** storage buckets are created  
**Then** bucket-level object versioning is enabled to guard against accidental overwrites or malicious deletion  
**And** server-side encryption (SSE) is enforced for all stored assets and database backups.

**Given** a backup archive and WAL logs  
**When** the disaster recovery drill harness (`scripts/dr_drill.sh` / Python harness) is executed  
**Then** it provisions an isolated recovery database instance, restores the base snapshot, replays WAL logs to a designated target timestamp, and measures actual elapsed recovery time  
**And** it executes automated financial consistency queries asserting ledger balance integrity ($\text{Balance} = \text{Principal} - \sum\text{Payments} + \sum\text{Reversals}$) and unbroken audit trail continuity.

**Given** disaster recovery documentation and operational health indicators  
**When** initial backup configuration is deployed  
**Then** the system explicitly marks DR compliance as `UNVERIFIED`  
**And** status transitions to `VERIFIED` only after a documented restore drill measures RTO <= 4 hours, RPO <= 15 minutes, and zero data corruption.

* **Traceability:** FR-32, AD-8
* **Dependencies:** Story 1.2 (Database foundations)
* **Testing Guidance:** Automated test harness executing the restore drill script against test container/local PostgreSQL; automated verification that WAL replay restores database to exact point-in-time; measurement and assertion of RTO and RPO metrics; ledger consistency check script.

---

### Story 1.5: Automated Security, Multi-Tenant & Integrity CI Verification Pipeline

> **SQLite-only amendment (2026-11-25):** CI runs `flutter analyze`, pure-Dart unit tests and Drift SQLite integration tests. No PostgreSQL service, pgTAP, or server boundary suite; cross-tenant and audit-immutability gates run against SQLite.

As a Software Developer and Shop Owner,  
I want an automated Continuous Integration (CI) pipeline running risk-prioritized unit, integration, and security verification suites on every code change,  
So that tenant isolation, RBAC enforcement, financial math precision, and audit immutability are continuously verified as non-negotiable merge gates.

**Acceptance Criteria:**

**Given** the project GitHub repository  
**When** code is pushed or a pull request is opened against `main`  
**Then** the CI workflow (`.github/workflows/ci.yml`) triggers automatically  
**And** the build executes across defined quality stages: static analysis/linting, pure Dart unit tests, database integration tests with real PostgreSQL, and boundary attack tests.

**Given** the CI linting stage  
**When** codebase files are analyzed  
**Then** custom lint rules flag and fail the build if Dart `double` is imported or used for monetary variables or arithmetic in `domain/` or `data/` packages.

**Given** the CI database integration test stage running with a real PostgreSQL service container  
**When** the test suite executes automated cross-tenant boundary attack tests  
**Then** 100% of unauthorized attempts to read or write cross-tenant rows fail with zero leakage, or the build fails.

**Given** the automated test suite  
**When** tests attempt to execute `UPDATE` or `DELETE` on `audit_events` or invoke protected operations without valid permission claims  
**Then** tests confirm that the database trigger and authorization middleware reject the operations with 100% reliability.

**Given** branch protection rules on `main`  
**When** any test in the CI pipeline fails  
**Then** merging is completely blocked until all tests pass cleanly.

* **Traceability:** FR-33, AD-7
* **Dependencies:** Stories 1.1, 1.2, 1.3
* **Testing Guidance:** GitHub Actions workflow syntax validation; execution of test suite in local container via `act` or Docker; negative verification that intentionally breaking an RLS rule or using a `double` fails the CI workflow.

---

### Story 1.6: Shop Profile Configuration, Timezone & Currency Display Preferences

As a Shop Owner,  
I want to configure my shop's legal profile, contact details, logo, timezone (default `Asia/Colombo`), custom receipt header and footer notes, and currency display preferences,  
So that my shop operates in its local time zone and all customer documentation accurately reflects my business identity.

**Acceptance Criteria:**

**Given** an authenticated Shop Owner on the shop configuration screen  
**When** they enter the Shop Name, Business Address, Contact Telephone, Email, Registration/Tax Number, upload a shop logo, and enter custom receipt header and footer notes  
**Then** the profile data is validated, stored in local Drift SQLite, and synchronized to cloud PostgreSQL under the trusted `shop_id`  
**And** the shop profile is immediately available for counter header displays and future receipt formatting.

**Given** the shop timezone configuration  
**When** a shop profile is created or updated  
**Then** the timezone defaults to `Asia/Colombo` (UTC+05:30)  
**And** the input is validated against standard IANA timezone identifiers  
**And** all subsequent calendar due date and midnight boundary calculations evaluate in this configured local timezone.

**Given** the currency presentation setting  
**When** configured by the Shop Owner  
**Then** currency display defaults to `LKR` (formatted as "Rs. ###,###.00")  
**And** presentation formatting is strictly decoupled from the internal integer minor units ledger  
**And** once any financial transaction (credit agreement, disbursement, payment, or reversal) exists within the shop tenant, the underlying base ledger currency code is strictly locked and cannot be altered.

**Given** an existing shop with historical payment receipts  
**When** the Shop Owner updates the shop logo, address, or receipt footer notes  
**Then** all newly issued receipts display the updated branding and notes  
**But** previously generated receipt snapshots remain completely unchanged.

**Given** any modification to the shop profile or branding  
**When** the save operation commits successfully  
**Then** an audit entry (Event Category 14: `Security & administrative tenant configuration events`) is appended to `audit_events` containing the Shop Owner actor ID, timestamp, and pre/post state JSON diff.

* **Traceability:** FR-1, FR-2, FR-3, FR-4, FR-31 (Event #14), AD-1, AD-4 (`features/shop`)
* **Dependencies:** Story 1.2 (Database foundations), Story 1.3 (Tenant isolation & audit trigger)
* **Testing Guidance:** Unit tests for IANA timezone validation and formatting; integration tests for shop profile persistence; regression test verifying past receipt snapshots are untouched by profile updates; test verifying base currency cannot be changed after transactions exist; audit log verification for administrative configuration events.

---

### Story 1.7: Counter Staff Administration & 14-Permission RBAC Configuration

As a Shop Owner,  
I want to create, view, and manage staff user accounts and configure their role-based permissions using the approved 14-permission catalog,  
So that counter employees only access authorized workflows and customer data while administrative operations remain strictly owner-controlled.

**Acceptance Criteria:**

**Given** an authenticated Shop Owner on the staff management screen  
**When** they view the active staff list  
**Then** only staff accounts belonging strictly to their `shop_id` are displayed via server-enforced RLS  
**And** zero staff records from any other tenant are visible or queryable.

**Given** the staff account creation form  
**When** the Shop Owner enters a staff member's full name, unique username/email, initial password, and selects a role (`Cashier`, `Manager`, or `Custom`)  
**Then** the system presents granular permission toggles strictly matching the approved 14-permission catalog:
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
  11. `approveCorrections`
  12. `confirmCollateralReturn`
  13. `viewFinancialReports`
  14. `viewAuditLogs`  
**And** no permission can be added, removed, or redefined outside of this fixed catalog.

**Given** any administrative action (staff creation, permission modifications, deactivation, shop profile changes, due date extensions, correction approvals)  
**When** invoked by a non-owner staff member  
**Then** the server unconditionally rejects the request with `403 Forbidden`  
**And** custom staff roles cannot assign permissions they do not possess or elevate their own privileges.

**Given** every protected server endpoint mapped to an RBAC permission  
**When** evaluated in automated tests  
**Then** requests with the required permission toggle return `200 OK`  
**And** requests lacking the permission toggle return `403 Forbidden` without leaking resource existence.

**Given** any staff account creation, activation, deactivation, or permission modification  
**When** the change commits  
**Then** an audit event (Category 12: `Staff account creation, deactivation, and permission modifications`) is atomically appended to `audit_events` with actor ID, target staff ID, and detailed permission diff.

* **Traceability:** FR-4, FR-5, FR-6, FR-12, FR-31 (Event #12), FR-33, AD-4 (`features/auth`), AD-6
* **Dependencies:** Story 1.2 (Database foundations), Story 1.3 (Tenant isolation), Story 1.6 (Shop entity)
* **Testing Guidance:** Unit tests verifying the 14-permission enum catalog and permission evaluation matrix; server-side authorization tests verifying each permission is enforced independently (both 403 denied and 200 permitted cases); privilege escalation prevention tests; multi-tenant isolation tests; audit log verification for Event Category 12.

---

### Story 1.8: Staff Authentication, Session Management & Server-Enforced Revocation

As a Shop Owner,  
I want staff accounts to authenticate securely and have the ability to immediately revoke access upon deactivating an account, with realistic offline boundaries and server-enforced re-authentication,  
So that terminated or compromised counter staff cannot perform unauthorized counter operations once the server receives their requests.

**Acceptance Criteria:**

**Given** a counter staff member on the login screen  
**When** they submit valid shop credentials, username, and password  
**Then** the server verifies credentials and returns a secure JWT/session token containing `user_id`, `shop_id`, and `session_version`  
**And** the client caches the authenticated session locally in Drift SQLite in sandboxed app-private storage.

**Given** an authenticated staff member sending a protected API request  
**When** the server receives the request token  
**Then** it verifies that the token's `session_version` matches the authoritative `session_version` stored in PostgreSQL for that user  
**And** proceeds only if the account is `Active` and versions match.

**Given** a Shop Owner on the staff management screen  
**When** they deactivate a staff account or trigger session revocation  
**Then** the server atomically updates the user status to `Inactive`, increments `session_version` by 1 in PostgreSQL, and logs an audit event (Category 12: `Staff account creation, deactivation, and permission modifications`).

**Given** a staff terminal whose user account has been deactivated on the server  
**When** the terminal sends its next API request or background sync  
**Then** the server immediately returns `401 Unauthorized`  
**And** the client app terminates the local session, clears sensitive in-memory state, locks the terminal, and displays a session revoked notification.

**Given** a counter terminal operating while disconnected from the network  
**When** the terminal operates offline  
**Then** the terminal permits only predefined safe counter operations (e.g. read-only cached customer search, queuing credit creation or payments as `PendingServerAck`)  
**And** sensitive operations (staff administration, permission changes, financial reversals/corrections) strictly require online server authorization and are blocked while offline  
**And** the system explicitly acknowledges that remote session revocation cannot be pushed to a disconnected terminal until it re-establishes network connectivity.

* **Traceability:** FR-4, FR-5, FR-31 (Event #12), FR-33, AD-1, AD-4 (`features/auth`), AD-6
* **Dependencies:** Story 1.7 (Staff user accounts)
* **Testing Guidance:** Integration test verifying that incrementing `session_version` invalidates existing JWT tokens on the very next HTTP request; API test verifying deactivated user receives `401 Unauthorized` across all endpoints; client test verifying offline queueing behavior and immediate session eviction upon reconnection; negative authentication tests.

---

### Story 1.9: Platform Administrator Governance & Cross-Tenant Access Restrictions

> **SQLite-only amendment (2026-11-25):** Platform-admin default-deny is enforced by application guards and repository queries only; there are no server endpoints or RLS policies. Blocked attempts append Category 14 locally.

As a Platform Security Officer and Shop Owner,  
I want platform administrator accounts to be default-denied read access to shop customer personal data, credit agreements, and financial ledgers,  
So that independent retail shops have guaranteed data privacy, strict tenant isolation, and regulatory compliance without unauthorized operator access.

**Acceptance Criteria:**

**Given** an authenticated Platform Administrator in the platform management console  
**When** they view system telemetry and shop accounts  
**Then** they can view tenant account status, subscription tier, storage quota, and system health metrics  
**But** customer names, NIC numbers, photos, collateral descriptions, credit balances, and payment records are completely hidden and unreadable.

**Given** any direct database query or API request authenticated with a Platform Administrator token  
**When** the query attempts to read or export records from `customers`, `collateral_items`, `credits`, `payments`, or `receipt_snapshots`  
**Then** the server returns `403 Forbidden` and PostgreSQL Row-Level Security blocks data retrieval (zero rows returned).

**Given** platform administration APIs and database access policies  
**When** evaluated  
**Then** no unapproved "break-glass" bypasses or backdoor credentials exist that circumvent PostgreSQL Row-Level Security or tenant isolation.

**Given** any attempt by a platform administrator to access tenant-scoped customer or ledger data  
**When** the attempt is blocked  
**Then** a high-priority security audit event (Category 14: `Security events: unauthorized access attempts, cross-tenant violations`) is immediately recorded in `audit_events`.

**Given** the automated CI security test suite  
**When** boundary attack simulations execute  
**Then** tests verify that attempting to set `app.current_shop_id` to another tenant's ID or querying cross-tenant tables fails with 100% rejection.

* **Traceability:** FR-4, FR-7, FR-12, FR-31 (Event #14), FR-33, AD-1, AD-6, AD-7
* **Dependencies:** Story 1.2 (Database foundations), Story 1.3 (Tenant isolation), Story 1.8 (Authentication tokens)
* **Testing Guidance:** Automated CI test suite asserting that platform administrator tokens fail to query customer PII or financial tables (HTTP 403 / zero rows); integration tests simulating cross-tenant SQL injection and parameter manipulation; audit logging tests for Event Category 14 on unauthorized administrative access attempts.

---

### Story 1.10: Secure Staff Credential Recovery (Forgot Username / Password)

> **SQLite-only amendment (2026-11-25):** recovery runs in-app against SQLite. The PostgreSQL/backend-specific ACs below are superseded by: (a) an unauthenticated request returns the same generic body/status for matched and unmatched identifiers while storing a single-use OTP challenge in `credential_recovery_challenges`; (b) one SQLite transaction atomically rotates the password hash, increments `session_version`, consumes the challenge and appends Category 12; failures append Category 14. Re-transmission uses SQLite `UNIQUE(client_operation_id)`/`UNIQUE(idempotency_key)`. App-held delivery secrets are an accepted single-device risk.

As a Counter Staff member who cannot log in,  
I want to recover my username and reset my password using a single-use OTP sent to my verified contact channel,  
So that I can regain access without any unauthenticated caller enumerating accounts or taking over another shop's staff credentials.

**Acceptance Criteria:**

**Given** an unauthenticated user on the login screen  
**When** they open "Forgot username or password?" and submit a login identifier  
**Then** the standalone backend service resolves the staff account from its own records using tenant-safe lookup (never a client-supplied shop ID) and, if an account with a verified contact channel exists, issues a single-use OTP hashed at rest with a short TTL  
**And** unauthenticated responses are identical in body and status whether or not an account matched (timing equality is not required)  
**And** no username, shop ID, or contact-channel value is disclosed.

**Given** a credential recovery challenge has been issued  
**When** the same request is re-transmitted with the same `client_operation_id` / idempotency key  
**Then** the server returns the existing challenge without issuing a second OTP or second delivery  
**And** the client disables the request control while in flight.

**Given** the OTP entry step  
**When** the user submits a valid, unconsumed, unexpired OTP with a new password  
**Then** the server verifies in constant time against the stored hash, atomically updates the password hash and increments `session_version` in PostgreSQL  
**And** all existing sessions are immediately revoked on their next request (401)  
**And** the challenge is marked consumed and cannot be reused.

**Given** a delivery or verification request  
**When** it reaches the backend  
**Then** it is authenticated with a signed, short-lived, single-use reference bound to the challenge; no caller-supplied destination or code is accepted  
**And** the backend enforces the five-attempt cap and abuse throttling with exactly one Category 14 event per failure/abuse path.

**Given** an invalid, expired, consumed OTP, or more than the bounded number of failed attempts  
**When** verification fails  
**Then** the server returns the same generic failure message, increments the attempt counter, invalidates the challenge at the threshold, and appends a Category 14 security audit event  
**And** the response never reveals whether the identifier, OTP, or challenge existed.

**Given** the client is offline  
**When** the user attempts any recovery step  
**Then** the action is blocked and no local `app_users` password write occurs  
**And** the legacy client-side reset dialog in `login_screen.dart` is removed.

**Given** the Flutter client  
**When** recovery is exercised  
**Then** it holds no OTP, hash, pepper, provider credential, or privileged DB connection and runs no DDL or migration bootstrap at startup  
**And** migration 003 is applied only by a DBA/CI deployment step.

**Given** the `app_users` login-identifier collision recorded in `deferred-work.md`  
**When** recovery identity resolution goes live  
**Then** email/phone uniqueness within a shop is enforced by schema (`uniqueKeys`) and server lookup  
**And** no recovery challenge can be attributed to a user in a different tenant.

**Given** any successful or failed recovery operation  
**When** it commits  
**Then** an append-only event is written server-side under Category 12 (`credential_recovery_requested`, `credential_password_reset`) or Category 14 (failure/abuse) with tenant ID, actor/target user ID, and server timestamp  
**And** no password, OTP, or reset token value appears in the audit record or application logs  
**And** no fifteenth audit category or sixteenth permission is introduced.

* **Traceability:** FR-4, FR-5, FR-31 (Events #12/#14), FR-33, FR-34, AD-1, AD-4 (`features/auth`), AD-6, AD-9, UX (Credential Recovery flow)
* **Dependencies:** Story 1.2 (SQLite schema), Story 1.3 (tenant guard + audit trigger), Story 1.7, Story 1.8, Story 1.5 (CI gates), and resolution of the `deferred-work.md` login-identifier collision
* **Testing Guidance:** Backend API contract tests plus real-PostgreSQL integration tests: OTP single-use/expiry/attempt-threshold, idempotent re-transmission, cross-tenant rejection, generic-response equality (body + status) for matched vs unmatched identifiers, session revocation on next request, Category 12/14 append and immutability, no credential values in logs. Widget tests for the two-step flow. These join the mandatory CI merge gate.

---

### Story 1.11: REMOVED — Standalone Credential Recovery Backend Service

> **Removed 2026-11-25:** the SQLite-only single-device decision eliminates the standalone backend, `DATABASE_URL`, PostgreSQL RLS and pgTAP. Recovery is implemented in-app under Story 1.10 (AD-9). Do not implement this story.

---

## Epic 2: Customer Identity, KYC Onboarding & Profile Management

Counter staff can quickly register new and returning customers with complete KYC details (Name, NIC, Phone, Address, Customer Photo); capture device/webcam photos or submit owner-approved photo exceptions; resolve shared-phone duplicate warnings while blocking duplicate NICs; securely access masked identity data based on `viewSensitiveCustomerData` permission; navigate multi-credit customer profiles; log audit events for onboarding and overrides; and verify zero cross-tenant customer data leakage in automated CI tests.

### Story 2.1: Reusable Customer Profile Data Schema & Persistence

As a Counter Staff member,  
I want to register and persist reusable customer profiles with full name, NIC number, phone number, residential address, and customer photograph metadata within my shop tenant,  
So that customer details are captured accurately once and can be securely reused across multiple credit agreements without duplicate manual entry.

**Acceptance Criteria:**

**Given** an authenticated user with `registerCustomers` permission  
**When** they submit a new customer profile with Full Name, NIC Number, Contact Phone Number, Residential Address, and Photo reference  
**Then** the customer record is persisted in Drift SQLite locally and synchronized with PostgreSQL  
**And** the record is tagged with an immutable `tenant_id`  
**And** a unique constraint on `(tenant_id, nic)` prevents duplicate NIC registrations within the same shop  
**And** an audit event (Category 1: `Customer creation and profile edits`) is appended to `audit_events`.

**Given** an existing customer profile in the shop  
**When** the customer returns for a second or subsequent credit  
**Then** counter staff can attach the new credit to the existing profile without re-entering personal data  
**And** the profile maintains a relational list of all attached credits (active, overdue, and settled).

**Given** any database query or API search for customers  
**When** executed by staff in Shop A  
**Then** the server enforces Row-Level Security such that zero customer records from Shop B can be retrieved or detected.

* **Traceability:** FR-4, FR-8, FR-31 (Event #1), FR-33, AD-1, AD-4 (`features/customers`)
* **Dependencies:** Story 1.2 (Database foundations), Story 1.3 (Tenant isolation)
* **Testing Guidance:** Unit tests for Customer entity serialization; Drift SQLite DAO tests asserting unique constraint on `(tenant_id, nic)`; integration tests verifying that customer records are strictly isolated between two test tenants.

---

### Story 2.2: Mandatory Customer Photo Capture & Client Compression Pipeline

As a Counter Staff member and Shop Owner,  
I want to capture customer identity photographs directly using a connected device camera or file upload, with client-side compression and interactive preview,  
So that clear photographic proof of identity is captured for every borrower while preserving device responsiveness and bandwidth.

**Acceptance Criteria:**

**Given** the customer onboarding screen  
**When** the staff member initiates photo capture  
**Then** the interface opens an interactive camera viewfinder (or system file picker) with live preview  
**And** allows capturing, reviewing, and retaking the photograph prior to saving.

**Given** a newly captured customer photograph  
**When** processed by the client application  
**Then** the image is compressed and resized directly on the client device (maximum 1600px on the longest edge, target file size 150 KB – 300 KB WebP/JPEG)  
**And** the compression preserves facial clarity and identifying features without visible degradation.

**Given** compressed image bytes  
**When** saved on the device  
**Then** the file is stored in sandboxed app-private storage (`getApplicationDocumentsDirectory() / photos / {tenant_id} / customers /`)  
**And** the database record stores only the relative path, SHA-256 hash, file size, and upload status (`pendingUpload`)  
**And** raw binary image bytes are strictly excluded from relational SQL tables.

**Given** standard customer registration without an approved photo exception  
**When** staff attempts to save the profile without a captured photograph  
**Then** the client and server programmatically block submission with a validation error: `"Customer photograph is mandatory."`

* **Traceability:** FR-8, FR-9, AD-5, UX-DR-2
* **Dependencies:** Story 2.1 (Customer entity)
* **Testing Guidance:** Unit tests asserting client-side image compression meets resolution and size bounds; widget test verifying live camera viewfinder, retake, and preview widgets; validation test asserting profile submission is blocked if photo is null.

---

### Story 2.3: Customer Photo Exception Request & Shop Owner Approval Workflow

As a Counter Staff member and Shop Owner,  
I want a formal exception workflow when a customer cannot be photographed due to hardware failure or documented physical constraints, requiring Shop Owner approval,  
So that counter operations are not halted by equipment failures while preventing unauthorized staff from bypassing mandatory KYC photographic rules.

**Acceptance Criteria:**

**Given** a customer registration where photo capture cannot be completed  
**When** Counter Staff selects *Request Photo Exception*  
**Then** the system requires a mandatory, non-empty documented business justification (e.g. `"Camera hardware failure; manual physical NIC copy verified"`)  
**And** creates a photo exception request in state `Pending Owner Approval`  
**And** programmatically blocks completion of the customer profile while the request is pending.

**Given** a pending customer photo exception request  
**When** evaluated by a user with only the Counter Staff role  
**Then** the staff member is strictly blocked from approving or overriding the exception.

**Given** a Shop Owner viewing the pending exception queue  
**When** the Shop Owner approves the exception  
**Then** customer profile creation is unblocked and completed without a photo  
**And** an immutable audit entry is appended (Category 1: `Customer creation and profile edits`) recording requester ID, approver ID, mandatory reason, and timestamps.

**Given** a Shop Owner viewing the pending exception queue  
**When** the Shop Owner rejects the exception with a mandatory rejection note  
**Then** the request transitions to `Rejected`, profile creation remains blocked, and an audit entry is logged.

* **Traceability:** FR-6, FR-9, FR-31 (Event #1), AD-6
* **Dependencies:** Story 2.1 (Customer profile), Story 2.2 (Photo capture), Story 1.7 (RBAC)
* **Testing Guidance:** Integration test asserting staff cannot self-approve photo exceptions; test asserting profile creation is blocked until owner approval; audit logging test asserting requester, approver, and reason are permanently recorded.

---

### Story 2.4: Shop-Scoped Duplicate Customer Detection & Shared-Phone Resolution Workflow

As a Counter Staff member,  
I want automated duplicate detection based on NIC and phone number strictly within our shop, with a structured verification workflow for family members sharing a phone,  
So that we avoid creating duplicate customer accounts while accommodating legitimate shared contact numbers.

**Acceptance Criteria:**

**Given** Counter Staff entering customer onboarding details  
**When** an NIC number is entered that already exists in the active shop  
**Then** the system immediately displays a blocking notification: `"Customer profile already exists for this NIC within Perera Jewellers"`  
**And** provides a button to open the existing customer profile, preventing duplicate creation.

**Given** Counter Staff entering customer onboarding details  
**When** a phone number is entered that matches an existing customer in the shop, but the NIC number is different  
**Then** the system displays a non-blocking warning banner: `"Phone number shared with existing customer [Name] (masked NIC: 1985****5678)"`  
**And** prompts staff to verify whether this is a distinct individual (e.g. spouse or parent).

**Given** a shared-phone duplicate warning  
**When** Counter Staff clicks *"Confirm separate individual sharing phone number"*  
**Then** profile creation is permitted to proceed  
**And** an audit event is logged (Category 1) recording the confirmation, staff ID, shared phone number, and both customer IDs.

**Given** duplicate checks executing in Shop A  
**When** an applicant's NIC exists in Shop B but not Shop A  
**Then** the duplicate check returns zero matches and never discloses the individual's presence in Shop B.

* **Traceability:** FR-4, FR-10, FR-31 (Event #1), AD-1, AD-6
* **Dependencies:** Story 2.1 (Customer persistence)
* **Testing Guidance:** Unit tests for duplicate detection repository methods; integration tests verifying cross-tenant duplicate queries return zero results; widget test for shared-phone confirmation dialog and audit event dispatch.

---

### Story 2.5: Customer Search, Credit Navigation & Multi-Credit Target Selection

As a Counter Staff member,  
I want to search customer profiles by NIC, phone, or name and view all associated credits categorized by status, requiring explicit credit selection when performing actions,  
So that I can quickly serve returning counter customers without misapplying repayments to the wrong credit agreement.

**Acceptance Criteria:**

**Given** Counter Staff on the customer search screen  
**When** they type an NIC number, phone number, or name fragment (minimum 2 characters)  
**Then** search results display matching customers within the active shop with masked sensitive fields (unless authorized).

**Given** a selected customer profile  
**When** the customer record is opened  
**Then** the interface displays the customer's photo thumbnail, verified name, contact summary, and an organized list of all associated credits  
**And** credits are visually categorized by badges: `Active`, `Overdue`, and `Settled`.

**Given** a customer who holds multiple credits (e.g. one active credit and one overdue credit)  
**When** Counter Staff initiates a payment, credit detail view, or collateral return  
**Then** the system displays a modal prompt requiring staff to explicitly select the specific target credit before opening the transaction screen  
**And** prevents defaulting or auto-selecting a credit to avoid misapplied payments.

* **Traceability:** FR-4, FR-11, UX-DR-3
* **Dependencies:** Story 2.1 (Customer profile)
* **Testing Guidance:** Widget test for customer search and debounced query execution; UI test verifying multi-credit selection prompt forces explicit user choice; negative test ensuring searches do not return foreign-tenant customers.

---

### Story 2.6: Server-Side Sensitive Customer Data Masking & RBAC Enforcement

As a Shop Owner,  
I want sensitive customer identity data (full NIC numbers, residential addresses, and raw photos) to be masked on the server side unless the user possesses the `viewSensitiveCustomerData` permission,  
So that frontline employees have operational visibility without exposing sensitive personal identification data to unauthorized viewing or scraping.

**Acceptance Criteria:**

**Given** an authenticated user who has `viewCustomers` permission but DOES NOT have `viewSensitiveCustomerData`  
**When** they request customer profile data via API or query  
**Then** the server delivers masked NIC (`1985****5678`), masked telephone (`+94 77 **** 123`), and omitted residential address  
**And** customer photo binary/storage URLs are omitted or replaced with a generic placeholder.

**Given** an authenticated user who possesses `viewSensitiveCustomerData` permission (or the Shop Owner role)  
**When** they view the customer profile  
**Then** the server delivers full unmasked NIC, full telephone, residential address, and a cryptographically signed image URL valid for $\le 15$ minutes.

**Given** an unauthorized user attempting to access direct cloud storage photo URLs or API endpoints for customer photos  
**When** the request is received  
**Then** the server returns `403 Forbidden` and logs a security audit event (Category 14: `Security events: unauthorized access attempts, cross-tenant violations`).

* **Traceability:** FR-6, FR-12, FR-31 (Event #14), FR-33, AD-1, AD-5, AD-6
* **Dependencies:** Story 2.1 (Customer profile), Story 1.7 (RBAC catalog)
* **Testing Guidance:** Automated API test verifying server-side response serialization omits sensitive fields for unauthorized roles; integration test asserting short-lived signed URLs expire after 15 minutes; security test asserting unauthorized direct photo access returns HTTP 403.

---

## Epic 3: Multi-Item Collateral Intake, Appraisal & Custody Tracking

Counter staff can document and photograph multiple pledged valuables (gold jewelry with calibrated decimal gram weights, consumer electronics, general valuables) under a credit; preview captured photos or submit owner exception requests; independently track the physical custody lifecycle of each item (`In Custody`, `Returned`, `Exception / Held`) decoupled from financial settlement; record administrative closures with mandatory reasons; log audit events for custody transitions; and verify cross-tenant collateral isolation in CI.

### Story 3.1: Multi-Item Collateral Relational Schema & Decimal Weight Calibration

As a Counter Staff member,  
I want to register zero or more item receipts under a credit agreement, capturing category, description, condition grading, estimated value, and mandatory calibrated decimal gram weights for gold,  
So that every physical asset held by the shop is comprehensively recorded and accurately appraised at intake, while unsecured credits can still be originated.

**Acceptance Criteria:**

**Given** a credit origination workflow  
**When** Counter Staff adds item receipts  
**Then** the system supports attaching zero or more item receipts under a single parent credit agreement  
**And** generates a unique Item Reference Number (e.g. `ITM-1042-01`, `ITM-1042-02`) for each attached item.

**Given** a credit origination workflow  
**When** Counter Staff submits without attaching any item receipt  
**Then** the agreement is created successfully and no custody record is created.

**Given** any item receipt being registered  
**When** attributes are entered  
**Then** staff must record: Category (`Gold/Jewelry`, `Electronics`, `General Valuables`), Description, Condition Grading, and Estimated Collateral Value  
**And** Estimated Collateral Value is stored as an independent appraisal field in minor units and is never conflated with the credit principal.

**Given** an item with Category `Gold/Jewelry`  
**When** details are submitted  
**Then** the Weight field is strictly mandatory, accepts calibrated decimal values (e.g. `12.40` grams), and is stored with its unit of measure (`grams`)  
**And** entering a negative weight or omitting the weight blocks item creation with a validation error.

* **Traceability:** FR-13, FR-14, AD-1, AD-4 (`features/collateral`)
* **Dependencies:** Story 1.2 (Database foundations)
* **Testing Guidance:** Drift SQLite schema tests verifying parent-child relationship between credit and collateral items; unit tests for decimal weight validation; validation tests ensuring gold category enforces mandatory weight.

---

### Story 3.2: Mandatory Item Receipt Photographic Capture & Forensic Inspection Optimization

As a Counter Staff member and Shop Owner,  
I want to capture at least one clear photograph for every attached item receipt with pre-save preview and client-side compression that preserves gold hallmarks and serial numbers,  
So that we have objective forensic evidence of item condition at intake to resolve any customer return disputes.

**Acceptance Criteria:**

**Given** a collateral intake form for an item  
**When** staff captures or uploads photographs  
**Then** the interface provides live viewfinder capture or file upload with an interactive pre-save preview, supporting multiple photos per item (e.g. overall view, hallmark closeup, cosmetic flaws).

**Given** captured collateral photos  
**When** compressed on the client device  
**Then** compression targets 150 KB – 300 KB WebP/JPEG (maximum 1600px dimension) while preserving visible gold hallmarks, stamps, serial numbers, and cosmetic scratches without loss of forensic utility.

**Given** collateral photos saved locally  
**When** stored on the device  
**Then** files are placed in sandboxed app storage (`photos / {tenant_id} / collateral /`), metadata (path, hash, size) is recorded in SQLite, and raw binary bytes are strictly excluded from SQL tables.

**Given** an attempt to submit a credit agreement where any attached item receipt lacks a photograph  
**When** no approved photo exception exists  
**Then** submission is programmatically blocked with a validation error: `"Every item receipt must have at least one photograph."`

**Given** a credit agreement with zero item receipts  
**When** submitted  
**Then** the mandatory-photo rule does not apply because there is no attached item to photograph.

* **Traceability:** FR-14, FR-15, AD-5
* **Dependencies:** Story 3.1 (Collateral schema)
* **Testing Guidance:** Unit tests checking that image compression preserves hallmark sharpness within target file size bounds; widget test for collateral photo gallery and preview; validation test ensuring credit creation fails if an item lacks photos.

---

### Story 3.3: Collateral Photo Missing-Exception Request & Shop Owner Override Workflow

As a Counter Staff member and Shop Owner,  
I want a formal photo exception request workflow for collateral items when equipment fails, requiring Shop Owner approval and logging an immutable audit record,  
So that legitimate intake can proceed during emergencies while preventing staff from skipping collateral photos without authorization.

**Acceptance Criteria:**

**Given** a collateral item that cannot be photographed due to camera failure or physical constraint  
**When** Counter Staff selects *Request Collateral Photo Exception*  
**Then** the system requires a mandatory, non-empty documented business reason  
**And** places the item and parent agreement creation in `Pending Owner Approval`  
**And** programmatically blocks agreement finalization while pending.

**Given** a pending collateral photo exception  
**When** evaluated by a user with Counter Staff role  
**Then** the staff member is strictly blocked from approving or overriding the exception.

**Given** a Shop Owner reviewing the pending exception queue  
**When** the Shop Owner approves the exception override  
**Then** collateral registration is unblocked  
**And** an immutable audit entry is appended (Category 3: `Collateral registration and item detail edits`) recording requester ID, approver ID, item reference, mandatory reason, and timestamps.

**Given** a Shop Owner rejecting the exception  
**When** rejected with a mandatory reason note  
**Then** the item remains blocked from credit creation, and an audit entry is logged.

* **Traceability:** FR-6, FR-15, FR-31 (Event #3), AD-6
* **Dependencies:** Story 3.1, Story 3.2, Story 1.7 (RBAC)
* **Testing Guidance:** Integration test asserting staff cannot self-approve collateral photo exceptions; verification that credit creation is locked until owner approval; audit logging verification of requester, approver, and reason.

---

### Story 3.4: Decoupled Per-Item Custody State Machine & Physical Handover Verification

As a Counter Staff member,  
I want each pledged item to maintain an independent physical custody status (`In Custody`, `Returned`, `Exception / Held`) decoupled from the credit's financial balance, requiring explicit return confirmation for each item,  
So that vault inventory is accurate and credits cannot be marked as fully completed while physical items remain in the shop.

**Acceptance Criteria:**

**Given** an active credit with multiple pledged items  
**When** the customer makes a payment that reduces the financial balance to zero (`Settled`)  
**Then** the financial status transitions to `Settled`  
**But** each pledged item strictly remains in its physical custody state (`In Custody`)  
**And** the overall credit workflow status transitions to `Settled (Items Pending Handover)`.

**Given** a customer picking up their valuables at the counter  
**When** Counter Staff with `confirmCollateralReturn` permission hands back an item  
**Then** staff inspects the original intake photos and recorded weights as verification aids, checks the item on screen, and confirms return  
**And** the item transitions from `In Custody` to `Returned`, recording the return timestamp, handing staff ID, and customer handover confirmation  
**And** an audit event (Category 11: `Collateral physical return confirmations and exception closures`) is appended to `audit_events`.

**Given** a credit with two items where the customer retrieves only one item today  
**When** staff confirms return of Item 1  
**Then** Item 1 updates to `Returned` while Item 2 strictly remains `In Custody`  
**And** the overall credit workflow status remains `Settled (Items Pending Handover)`.

**Given** a settled credit where all associated pledged items have been confirmed as `Returned`  
**When** the last item is returned  
**Then** the overall workflow status transitions to `Closed / Completed`.

* **Traceability:** FR-6, FR-16, FR-31 (Event #10), AD-3, AD-6
* **Dependencies:** Story 3.1 (Collateral schema)
* **Testing Guidance:** Unit tests for independent CustodyStatus state machine; state transition test verifying financial settlement does not mutate custody states; partial pickup test asserting credit remains pending handover until all items are returned.

---

### Story 3.5: Collateral Exception State & Shop Owner Administrative Closure Workflow

As a Shop Owner,  
I want to transition an unreturned collateral item into an `Exception / Held` state and execute an Administrative Closure with Collateral Exception when items cannot be physically returned,  
So that credits with lost, stolen, or legally seized collateral can be closed administratively without falsifying records as returned.

**Acceptance Criteria:**

**Given** a pledged item that cannot be physically returned to the customer (e.g. police seizure, vault theft, or physical condition dispute)  
**When** a user with the Shop Owner role updates the item status  
**Then** the system requires selecting `Exception / Held` and providing a mandatory documented business rationale  
**And** logs an audit event (Category 3) recording the transition, owner ID, item reference, and reason  
**And** unauthorized counter staff are strictly blocked from setting an item to `Exception / Held`.

**Given** a credit that is financially settled (or resolved by owner decision) where one or more pledged items remain in `Exception / Held`  
**When** the Shop Owner executes *Administrative Closure with Collateral Exception*  
**Then** the credit's overall workflow status transitions to `Closed (Collateral Exception)`  
**And** the system permanently retains the affected items in `Exception / Held` without falsely marking them as `Returned`  
**And** appends an immutable audit entry (Category 11: `Collateral physical return confirmations and exception closures`) with owner sign-off.

* **Traceability:** FR-6, FR-16, FR-31 (Events #3, #11), AD-3, AD-6
* **Dependencies:** Story 3.4 (Custody state machine), Story 1.7 (Shop Owner role)
* **Testing Guidance:** Integration test asserting counter staff cannot execute administrative closures or set items to Exception/Held; test verifying credit transitions to `Closed (Collateral Exception)` while preserving `exceptionHeld` item states; audit verification.

---

## Epic 4: Zero-Interest Credit Origination & Cash Disbursement

Counter staff and Shop Owners can configure zero-interest credit agreements with preset or custom terms; preview preliminary due dates; generate draft agreement slips; guard against duplicate creation via idempotency keys; explicitly confirm cash disbursement; calculate official due dates from confirmed disbursement dates (Cases 1–5); issue executed disbursement vouchers; log agreement and disbursement audit events; and enforce `createCredits` and `confirmCreditDisbursement` RBAC permissions.

### Story 4.1: Credit Agreement Data Model & Zero-Interest Principal Tracking

As a Counter Staff member,  
I want to create a credit agreement linking a customer, zero or more item receipts, and principal amount in integer minor units under a zero-interest model with creation idempotency,  
So that credit debt obligations are accurately recorded without automated interest or hidden fees.

**Acceptance Criteria:**

**Given** an authenticated user with `createCredits` permission  
**When** they create a credit agreement with an attached customer, zero or more item receipts, and a Principal Amount (using the immutable `Money` Value Object)  
**Then** the credit is persisted with `Financial Status: Active / Pending Disbursement`, `Overall Workflow Status: Active (Pending Disbursement)`  
**And** the Initial Outstanding Balance is set exactly equal to the Principal Amount in integer cents  
**And** an audit event (Category 2: `Credit agreement origination and cancellation`) is appended to `audit_events`.

**Given** a credit agreement submission  
**When** submitted by the client application  
**Then** the request includes a client-generated `idempotency_key` (UUIDv4)  
**And** rapid double-clicks or network retry transmissions commit exactly one credit record without duplicates.

**Given** a newly created agreement in `Active / Pending Disbursement`  
**When** any user attempts to record a payment against the credit  
**Then** the system strictly blocks payment submission: `"Payments cannot be accepted on undisbursed credits."`

* **Traceability:** FR-6, FR-18, FR-19, FR-31 (Event #2), AD-1, AD-2, AD-3
* **Dependencies:** Story 1.1 (Money VO), Story 2.1 (Customer), Story 3.1 (Collateral)
* **Testing Guidance:** Unit tests asserting initial balance equals principal in cents; idempotency tests simulating duplicate credit creation requests with identical tokens; validation test asserting payment processing is blocked while pending disbursement.

---

### Story 4.2: Credit Term Selection & Preliminary Due Date Display

As a Counter Staff member,  
I want to select standard credit duration presets (30, 60, 90 calendar days) or specify a custom calendar due date with live preliminary due date calculation,  
So that the customer and cashier can review the tentative repayment deadline prior to agreement submission.

**Acceptance Criteria:**

**Given** the credit origination form  
**When** staff selects a preset duration (30, 60, or 90 days)  
**Then** the system tentatively calculates a preliminary due date by adding preset calendar days to the agreement creation date in the shop's local time zone (`Asia/Colombo`)  
**And** displays this date clearly labeled as `Preliminary Due Date (Pending Disbursement)`.

**Given** the credit origination form  
**When** staff selects a custom date using the calendar date picker  
**Then** the system validates that the selected date is strictly greater than the agreement creation date (`Custom Due Date > Agreement Creation Date`)  
**And** blocks submission if a past or same-day date is selected.

**Given** the interactive credit origination screen  
**When** staff adjusts duration terms or adds item receipts  
**Then** the live credit summary widget dynamically updates the displayed preliminary due date and total estimated item receipt value.

* **Traceability:** FR-17, UX-DR-4
* **Dependencies:** Story 4.1 (Credit model)
* **Testing Guidance:** Unit tests for preset date additions (30, 60, 90 days across month ends and leap years); validation tests for custom date picker rejecting past dates; widget test verifying live summary updates.

---

### Story 4.3: Decoupled Cash Disbursement Confirmation & Official Due Date Calculation Engine

As a Counter Staff member and Shop Owner,  
I want an explicit cash disbursement confirmation step that records the physical cash handover, confirms the official calendar due date, and updates financial status,  
So that cash reports reflect only genuinely disbursed funds and the official repayment period starts when cash is placed in the borrower's hands.

**Acceptance Criteria:**

**Given** a credit agreement in `Active / Pending Disbursement`  
**When** authorized staff with `confirmCreditDisbursement` permission confirms physical cash handover  
**Then** the credit transitions to `Financial Status: Active / Disbursed`, `Overall Workflow Status: Active`  
**And** records the confirmed cash disbursement timestamp and disbursing staff ID  
**And** an audit event (Category 4: `Confirmed cash disbursement`) is **queued for append** to `audit_events` as an append-only local record carrying the category, the action type, the disbursing staff ID, the confirmed timestamp and the calculated official due date  
**And** the authoritative append to the server-side `audit_events` table is performed by the server-side audit writer upon synchronization and is owned by the audit-writer work, not by this story.

**Given** cash disbursement confirmation for a credit with a preset duration (30, 60, or 90 days)  
**When** disbursement is confirmed  
**Then** the system calculates the Official Calendar Due Date by adding the agreed preset calendar days to the confirmed disbursement date in `Asia/Colombo`:
  $$\text{Official Calendar Due Date} = \text{Disbursement Date (in Shop Local Time)} + N\text{ calendar days}$$
  *(Test Case 1: 30-day preset disbursed Oct 15 -> Due Date Nov 14; Test Case 2: 60-day preset disbursed Oct 15 -> Due Date Dec 14; Test Case 3: 90-day preset disbursed Oct 15 -> Due Date Jan 13).*

**Given** cash disbursement confirmation for a credit with a custom calendar due date  
**When** disbursement is confirmed  
**Then** the system validates that `Custom Due Date > Disbursement Date (in Shop Local Time)`:
  - If valid (Test Case 4): the custom date is confirmed and saved.
  - If delayed such that the custom due date is on or before the disbursement date (Test Case 5): disbursement confirmation is programmatically blocked with an error requiring staff to select a valid future date before proceeding.

**Given** an agreement in `Pending Disbursement` that is abandoned or cancelled  
**When** the Shop Owner cancels the agreement with a mandatory reason  
**Then** the agreement transitions to `Cancelled / Undisbursed`, leaving an audit trail without impacting daily cash-out reports  
**And** the cancellation is recorded as an audit event in FR-31 **Category 2** (`Credit agreement origination and cancellation`) with action type `cancel_credit_agreement` — it is **not** recorded under Category 4 (`Confirmed cash disbursement`), because no cash was disbursed  
**And** the pledged collateral items of the cancelled agreement **remain in the shop's custody**; the cancellation performs no collateral return and no item custody transition  
**And** the system never cancels an undisbursed agreement automatically: there is no timeout and no auto-expiry, and an abandoned agreement is surfaced on a non-destructive worklist that reports it without changing its state.

* **Traceability:** FR-6, FR-19, FR-31 (Event #4 for the disbursement; Event #2 for the cancellation), AD-3, AD-6
* **Dependencies:** Story 4.1, Story 4.2
* **Testing Guidance:** Unit tests verifying Cases 1–5 calendar calculation semantics; integration test verifying cash disbursement updates credit state to Active; test verifying cash reports exclude undisbursed credits; cancellation audit test asserting the event carries Category 2 with action type `cancel_credit_agreement`; test asserting a cancelled agreement cannot be disbursed and cannot be cancelled twice; test asserting the pledged items remain in custody after cancellation.

---

### Story 4.4: Credit Agreement Documentation, Draft Agreements & Cash Disbursement Vouchers

As a Counter Staff member,  
I want to generate printable and PDF credit documents, clearly distinguishing pre-disbursement review drafts from executed cash disbursement vouchers,  
So that customers receive unambiguous, official physical agreements only after cash is confirmed disbursed.

**Acceptance Criteria:**

**Given** a credit agreement prior to cash disbursement (`Active / Pending Disbursement`)  
**When** staff prints a draft agreement slip  
**Then** the document is visually watermarked and titled: `*** DRAFT / PENDING DISBURSEMENT - NOT A CASH RECEIPT ***`  
**And** explicitly states: `"Preliminary Due Date (Subject to Confirmation on Cash Handover) - Non-binding until disbursement confirmation."`

**Given** a confirmed cash disbursement  
**When** the official executed credit ticket is generated  
**Then** the document contains: Shop Branding Snapshot (Name, Address, Phone, Tax/Reg No), Customer Identifier, Credit Reference Number, Origination Date, Confirmed Disbursement Timestamp, Disbursing Staff ID, Official Confirmed Calendar Due Date, Disbursed Principal Amount (`Rs. XX,XXX.XX`), Itemized Collateral Details (descriptions and gold weights), zero-interest disclosure, and shop footer notes  
**And** supports thermal slip printing and PDF export.

**Given** document generation actions  
**When** executed  
**Then** the system logs document print/export events in the append-only audit trail.

* **Traceability:** FR-6, FR-20, FR-31 (Events #2, #4), UX-DR-6
* **Dependencies:** Story 4.3 (Disbursement engine), Story 1.6 (Shop branding)
* **Testing Guidance:** Golden widget / PDF rendering tests asserting draft watermark on undisbursed slips; layout verification of official disbursement vouchers ensuring all mandatory attributes are printed.

---

## Epic 5: Payment Processing, Fixed-Point Ledgers & Receipt Snapshots

Counter staff can record partial payments and full settlements with anti-overpayment validation ($Payment \le OutstandingBalance$); calculate exact balances using integer minor units and double-entry ledger formulas ($\text{Balance} = \text{Principal} - \sum\text{Payments} + \sum\text{Reversals} \pm \sum\text{Adjustments}$); execute atomic transactions with UUID idempotency keys and optimistic concurrency locks; generate immutable receipt snapshots with reprint watermarking (`*** REPRINT ***`); request payment corrections with automatic credit-scoped payment locks (`LockedForCorrection`); process Shop Owner approval/rejection with compensating reversal entries; propose and (Shop Owner) approve staff-initiated balance adjustments for partial forgiveness (Story 5.6); log all financial and reprint audit events; and satisfy all 7 financial verification scenarios.

### Story 5.1: Payment Submission, Anti-Overpayment Validation & Settlement Transition

As a Counter Staff member,  
I want to record cash repayments against a disbursed credit with instant balance validation and automatic transition to Settled when the balance reaches zero,  
So that payments are posted accurately and overpayments are programmatically prevented.

**Acceptance Criteria:**

**Given** an authenticated user with `recordPayments` permission on the payment screen for a disbursed credit  
**When** staff enters a payment amount  
**Then** the system validates that `Payment > 0.00` in integer minor units (Money VO).

**Given** an entered payment amount  
**When** the payment exceeds the current valid outstanding balance (`Payment > Valid Outstanding Balance`)  
**Then** the system programmatically blocks submission with an immediate error: `"Payment cannot exceed current outstanding balance of Rs. XX,XXX.XX"` (Anti-Overpayment Protection).

**Given** a valid payment where `Payment < Valid Outstanding Balance`  
**When** submitted  
**Then** the transaction is recorded as a `Partial Payment`, reducing the outstanding balance by the exact payment amount in cents  
**And** an audit event (Category 5: `Payment recording`) is appended to `audit_events`.

**Given** a valid payment where `Payment == Valid Outstanding Balance`  
**When** submitted  
**Then** the transaction is recorded as a `Full Settlement`, the valid outstanding balance reaches exactly `0.00 LKR` (`isZero == true`), and the financial status immediately transitions to `Settled`.

* **Traceability:** FR-6, FR-21, FR-31 (Event #5), AD-2, AD-3, UX-DR-5
* **Dependencies:** Story 4.3 (Disbursed credit), Story 1.1 (Money VO)
* **Testing Guidance:** Unit tests for anti-overpayment validation; test asserting partial payment deduction in minor units; test asserting zero-balance transition to Settled; audit log verification.

---

### Story 5.2: Double-Entry Ledger Formula & Atomic Transaction Persistence

As a Software Engineer and Shop Owner,  
I want all financial balance calculations to follow an explicit double-entry ledger formula executed inside ACID database transactions in integer minor units,  
So that financial balances are mathematically exact, immune to floating-point rounding errors, and verifiable against all 7 PRD scenarios.

**Acceptance Criteria:**

**Given** the financial ledger domain and database repository  
**When** any balance calculation or transaction posting occurs  
**Then** the system calculates valid balance using the algebraic formula:
  $$\text{Valid Outstanding Balance} = \text{Principal Amount (Debit)} - \sum\text{Payments (Credit)} + \sum\text{Approved Reversals (Debit)} \pm \sum\text{Approved Adjustments}$$
**And** all monetary math is executed using 64-bit integer minor units (cents) with zero Dart `double` usage.

**Given** a payment submission or balance adjustment  
**When** persisted to the database  
**Then** the ledger transaction and balance deduction execute within a single atomic database transaction  
**And** any failure rolls back the entire operation, leaving zero partial commits or orphaned balance states.

**Given** the automated test suite  
**When** executed against the financial ledger engine  
**Then** all 7 mandatory PRD verification test scenarios pass:
  1. *Partial Payment:* 50,000.00 LKR - 20,000.00 LKR = 30,000.00 LKR.
  2. *Full Settlement:* 30,000.00 LKR - 30,000.00 LKR = 0.00 LKR (`Settled`).
  3. *Approved Payment Reversal:* 15,000.00 LKR + 35,000.00 LKR reversed = 50,000.00 LKR.
  4. *Approved Debit Adjustment:* 25,000.00 LKR + 250.00 LKR = 25,250.00 LKR.
  5. *Approved Credit Adjustment:* 25,000.00 LKR - 500.00 LKR = 24,500.00 LKR.
  6. *Duplicate Submission (Idempotency):* Duplicate submission commits exactly once.
  7. *Concurrent Payments:* Two simultaneous payments of 30,000.00 LKR against a 50,000.00 LKR balance process one and block the second with an overpayment error.

* **Traceability:** FR-22, AD-1, AD-2
* **Dependencies:** Story 5.1 (Payment submission), Story 1.1 (Money VO)
* **Testing Guidance:** Comprehensive automated unit and integration test suite executing all 7 scenarios; Drift SQLite transaction rollback test simulating mid-operation database failure.

---

### Story 5.3: Payment Idempotency, Concurrency Control & Correction-Pending Lock

As a Counter Staff member and System Administrator,  
I want client-side idempotency keys, optimistic concurrency locks, and a correction-pending payment lock on the affected credit,  
So that network retries never post duplicate payments, simultaneous transactions cannot double-spend, and payments are blocked while a balance correction is pending review.

**Acceptance Criteria:**

**Given** a payment submission request from a counter terminal  
**When** sent to the server  
**Then** the request carries a unique `idempotency_key` (UUIDv4)  
**And** if re-transmitted due to network timeout, the server returns the existing confirmed transaction and receipt without deducting funds twice.

**Given** two counter terminals attempting simultaneous payments on the same credit  
**When** both requests arrive concurrently  
**Then** database concurrency controls (row-level locking / optimistic lock) process the first request, update the balance, and evaluate the second request against the updated balance, blocking it if an overpayment would occur.

**Given** a credit where a financial correction request is pending Shop Owner review  
**When** any staff member opens the credit on the payment screen  
**Then** the credit displays a prominent banner: `Locked for Correction Review`  
**And** payment inputs are programmatically blocked specifically for that affected credit  
**While** all other credits in the shop remain fully operational.

* **Traceability:** FR-23, AD-1, AD-3, UX-DR-7
* **Dependencies:** Story 5.2 (Ledger transactions)
* **Testing Guidance:** Concurrency stress test simulating parallel payments; network timeout simulation asserting idempotency deduplication; UI test verifying payment lock banner and input blocking on pending corrections.

---

### Story 5.4: Immutable Receipt Snapshot Model, Watermarked Reprints & Audit Logging

As a Counter Staff member and Customer,  
I want an immutable receipt generated for every confirmed payment that preserves historical shop branding and transaction details, with a prominent watermark and audit log for reprints,  
So that customers receive immediate transaction proof and historical receipts can never be altered by subsequent shop profile edits.

**Acceptance Criteria:**

**Given** a confirmed payment transaction  
**When** the receipt is generated  
**Then** the system captures an immutable snapshot of:
  - Shop branding: Shop Name, Address, Phone, Email, Tax/Reg No, Logo, and Header/Footer notes at payment time.
  - Transaction details: Unique Receipt Number (e.g. `RCP-8801`), Payment Timestamp, Payment Type (`Partial Payment` or `Full Settlement`), Amount Paid, Pre-Payment Balance, Resulting Balance, Customer Identifier, Credit Reference, and Cashier ID.

**Given** subsequent updates to the shop profile, logo, or receipt notes  
**When** previously issued historical receipts are viewed or reprinted  
**Then** the historical receipt renders strictly from its original snapshot, completely unaffected by shop profile updates.

**Given** a request to reprint an existing receipt by staff with `viewAndReprintReceipts` permission  
**When** the reprint is generated  
**Then** it preserves the original receipt number and original payment timestamp  
**And** displays a prominent visual watermark: `*** REPRINT ***` in the header alongside the reprint generation timestamp  
**And** generates a distinct audit log entry (Category 13: `Receipt reprints`) recording receipt number, reprint timestamp, and staff ID  
**And** creates zero new financial ledger transactions.

* **Traceability:** FR-6, FR-24, FR-31 (Event #13), UX-DR-6
* **Dependencies:** Story 5.2 (Payments), Story 1.6 (Shop profile)
* **Testing Guidance:** Snapshot isolation test verifying shop profile edits do not alter historical receipts; reprint test asserting watermark rendering and creation of distinct audit entry; verification that reprinting does not mutate ledger balances.

---

### Story 5.5: Controlled Financial Correction & Shop Owner Reversal Approval Workflow

As a Counter Staff member and Shop Owner,  
I want a formal workflow to request payment corrections with mandatory reasons, requiring Shop Owner approval to post compensating reversal entries while permanently preserving original records,  
So that typographical counter errors are corrected transparently without silent record overwrites or unauthorized balance alterations.

**Acceptance Criteria:**

**Given** a confirmed payment record containing an error (e.g. entered 35,000 instead of 3,500 LKR)  
**When** Counter Staff with `requestCorrections` permission selects *Request Correction*  
**Then** the system requires a mandatory, non-empty business explanation  
**And** flags the transaction as `Correction Pending Approval`  
**And** activates the correction lock on the credit (Story 5.3).

**Given** a pending correction request  
**When** evaluated by a user with only Counter Staff role  
**Then** the staff member is strictly blocked from approving the reversal.

**Given** a Shop Owner reviewing the pending correction queue  
**When** the Shop Owner approves the correction request  
**Then** the system creates an immutable compensating debit transaction referencing the original payment  
**And** recalculates the valid outstanding balance ($\text{Balance}_{\text{new}} = \text{Balance}_{\text{current}} + \text{Reversed Payment Amount}$)  
**And** lifts the correction lock on the credit  
**And** permanently preserves the original erroneous transaction in history  
**And** logs an audit event (Category 7: `Financial correction approvals or rejections by Shop Owner`).

**Given** a Shop Owner reviewing a correction request  
**When** the Shop Owner rejects the request with a mandatory rejection reason  
**Then** the request transitions to `Rejected`, the balance remains unchanged, the correction lock is lifted, and an audit event is logged.

**Given** a Shop Owner executing a manual balance adjustment (debit or credit)  
**When** submitted  
**Then** it requires a mandatory business rationale, adjusts the balance according to debit/credit rules, preserves full transaction history, and logs an audit event.

* **Traceability:** FR-6, FR-22, FR-23, FR-31 (Events #6, #7), AD-1, AD-6
* **Dependencies:** Story 5.2 (Ledger math), Story 5.3 (Correction lock), Story 1.7 (Shop Owner role)
* **Testing Guidance:** Integration test for correction request lifecycle; test verifying compensating entry ledger arithmetic; security test asserting counter staff cannot approve reversals; test verifying rejection lifts payment lock.
* **Amendment:** Staff-proposed, owner-approved balance adjustments are governed by Story 5.6 (partial forgiveness). This story's owner-direct adjustment AC remains in force.

---

### Story 5.6: Staff-Proposed, Owner-Approved Balance Adjustments (Partial Forgiveness)

As a Counter Staff member and Shop Owner,  
I want staff to propose a debit or credit balance adjustment with a mandatory reason, with the Shop Owner holding exclusive approval authority before anything posts,  
So that a customer who cannot pay in full can have part of their balance forgiven at settlement in a controlled, auditable way, without staff being able to alter balances silently or without owner authorization.

**Acceptance Criteria:**

**Given** an active disbursed credit with a positive outstanding balance and Counter Staff holding `requestCorrections` (or a Shop Owner)  
**When** the staff member selects *Request Balance Adjustment* on a credit card (customer profile) or from the payment/settlement screen  
**Then** the system requires a mandatory, non-empty business explanation, an adjustment direction (`debit`/`credit`) and a positive amount in integer minor units, and records the proposal as `pending_approval`, activating the correction-pending lock on that credit.

**Given** a pending adjustment proposal  
**When** evaluated by a user with only Counter Staff (or Manager) permissions  
**Then** the user is strictly blocked from approving it.

**Given** a Shop Owner reviewing the pending correction/adjustment queue  
**When** the Shop Owner approves the proposal  
**Then** the system posts an immutable `adjustment_credit` (forgiveness) or `adjustment_debit` ledger entry linked to the credit, recalculates the valid outstanding balance atomically, lifts the correction-pending lock, and logs an audit event (Category 7) with actor IDs, target credit, pre/post balance, and the mandatory justification.

**Given** a Shop Owner reviewing a pending adjustment proposal  
**When** the Shop Owner rejects it with a mandatory rejection reason  
**Then** the proposal transitions to `Rejected`, the balance remains unchanged, the correction-pending lock lifts, and an audit event is logged.

**Given** a pending adjustment proposal on a credit  
**When** any user attempts to record a payment on that credit  
**Then** the payment is blocked with the existing correction-pending error; other credits remain unaffected.

**Given** either a debit or a credit adjustment proposal is approved  
**When** the ledger entry posts  
**Then** the resulting balance equals `Balance_current + Adjustment` (debit) or `Balance_current − Adjustment` (credit), computed in integer minor units, and an adjustment exceeding the balance in the credit direction is rejected per existing money rules (no negative balances unless explicitly modeled).

* **Traceability:** FR-6, FR-22, FR-23, FR-31 (Category 7), AD-1, AD-2, AD-6
* **Dependencies:** Story 5.2 (Ledger math), Story 5.3 (Correction lock), Story 5.5 (Correction request/approval pattern), Story 1.7 (Shop Owner role)
* **Testing Guidance:** Integration test for proposal → approval → ledger post → lock lift lifecycle; rejection path test; security test asserting staff cannot approve; idempotency test on double-tap approve; balance arithmetic tests for credit and debit directions; settlement-forgiveness end-to-end test (propose partial forgiveness → approve → settle remainder).
* **Implementation notes:** The `credit_corrections` table already supports non-payment adjustments (`originalPaymentId` nullable) but has no adjustment-direction column and its approval path always applies `balance_cents += amount`. Story 5.6 will either add a `direction` column (Drift migration) or introduce a sibling `adjustment_requests` table. The Shop Owner direct-adjustment path (`recordAdjustment`) stays unchanged. The unreferenced duplicate `correction_adjustment_screen_temp.dart` is deleted as part of this story.

---

## Epic 6: Overdue Credit Governance, Extensions & Owner Decisions

Shop Owners and authorized staff can identify delinquent credits automatically at the local midnight boundary (`Asia/Colombo`) strictly when outstanding balance > 0 (excluding fully settled credits); review overdue queues; record customer communication notes and promises to pay; grant Shop-Owner-only due date extensions with mandatory reasons, updating due dates and resetting dynamic status to `Active` while preserving complete immutable extension history; record structured administrative resolutions (`Under Review`, `Owner Settled / Written Off`, `Collateral Retained`) with zero automated collateral liquidation; log all overdue actions in the audit trail; and enforce `viewOverdueCredits` permission.

### Story 6.1: Automated Local-Midnight Overdue Evaluation & Badging Engine

As a Counter Staff member and Shop Owner,  
I want the system to automatically transition credits with positive balances to Overdue at the local midnight boundary following their due date, displaying visual badges and queues,  
So that delinquent accounts are identified systematically without manual date-by-date record checks.

**Acceptance Criteria:**

**Given** a disbursed credit with a valid outstanding balance greater than zero (`Valid Outstanding Balance > 0.00`)  
**When** the system evaluates credit status at 00:00:00 on the calendar day after the official due date (`Official Due Date + 1 calendar day`) in the shop's configured local time zone (`Asia/Colombo`)  
**Then** the credit automatically transitions its financial status to `Overdue` and its overall workflow status to `Overdue`  
**And** an audit event is appended to `audit_events`.

**Given** a credit that has reached a valid outstanding balance of zero (`Settled`) prior to or after the due date  
**When** the local calendar date passes the due date  
**Then** the credit is strictly excluded from overdue evaluation and must never transition to `Overdue`.

**Given** an overdue credit displayed on counter search lists, customer profiles, or owner dashboards  
**When** rendered in the interface  
**Then** it displays a prominent visual `Overdue` badge and a days-overdue counter.

**Given** two shop tenants configured in different time zones  
**When** evaluating overdue boundaries  
**Then** each tenant transitions credits according to its own configured local time zone calendar boundary.

* **Traceability:** FR-2, FR-6, FR-25, AD-3
* **Dependencies:** Story 4.3 (Disbursed credit), Story 1.6 (Shop timezone)
* **Testing Guidance:** Unit tests verifying midnight boundary calculation in `Asia/Colombo`; test asserting settled credits with zero balance are never marked overdue; multi-timezone boundary integration test.

---

### Story 6.2: Shop Owner Due Date Extension Workflow & History Chain

As a Shop Owner,  
I want to grant official due date extensions with mandatory business justifications, resetting overdue status to Active while permanently preserving the full extension history chain,  
So that I can accommodate customer repayment emergencies under owner governance without losing historical due date records.

**Acceptance Criteria:**

**Given** an active or overdue credit  
**When** a user with the Shop Owner role grants a due date extension  
**Then** the system requires a mandatory, non-empty business justification (e.g. `"Customer requested 2-week extension due to family emergency; full settlement promised Nov 5"`)  
**And** validates that the new due date is strictly greater than the current calendar date in the shop's local time zone (`New Due Date > Current Date`).

**Given** an extension granted on an `Overdue` credit  
**When** confirmed by the Shop Owner  
**Then** the credit's financial and overall workflow status immediately resets to `Active`  
**And** overdue evaluation is scheduled against the newly granted due date.

**Given** any due date extension  
**When** confirmed  
**Then** the system permanently preserves the original calendar due date and all intermediate extensions in an immutable chronological history chain (original date, revised date, reason, owner ID, timestamp)  
**And** logs an audit event (Category 8: `Due date extensions`).

**Given** a user with only Counter Staff permissions  
**When** they attempt to grant a due date extension  
**Then** the system strictly blocks the action with a permission error.

* **Traceability:** FR-6, FR-26, FR-31 (Event #8), AD-3, AD-6
* **Dependencies:** Story 6.1 (Overdue evaluation), Story 1.7 (Shop Owner role)
* **Testing Guidance:** Unit tests verifying status reset from Overdue to Active upon extension; verification of extension history chain serialization; security test asserting counter staff cannot execute extensions.

---

### Story 6.3: Delinquency Customer Follow-Up & Promise-to-Pay Logging

As a Counter Staff member,  
I want to log borrower communication attempts, contact notes, and promises to pay on delinquent accounts, surfacing commitment dates on review queues,  
So that customer interaction history is documented and upcoming promised payment commitments are tracked systematically.

**Acceptance Criteria:**

**Given** an authenticated user with `recordCustomerNotes` permission on an overdue or active credit  
**When** they record a customer follow-up  
**Then** the interface captures: Contact Timestamp, Communication Channel (`Phone Call`, `In-Person Counter Visit`, `Physical Notice`), Staff Identifier, Detailed Interaction Notes, and optional Promised Payment Date  
**And** logs an audit event (Category 9: `Customer follow-up notes and promises to pay`).

**Given** recorded follow-up entries on a credit  
**When** viewed on the credit detail screen  
**Then** notes are displayed in reverse chronological order with timestamps and staff IDs.

**Given** a follow-up entry with a Promised Payment Date  
**When** the Overdue Credit Review queue is rendered  
**Then** the system displays the promised payment date as a priority follow-up reminder for staff.

* **Traceability:** FR-6, FR-27, FR-31 (Event #9)
* **Dependencies:** Story 6.1 (Overdue credits)
* **Testing Guidance:** Widget test for customer follow-up logging form; sorting verification of interaction history; test ensuring promise-to-pay dates surface on delinquency review queues.

---

### Story 6.4: Structured Owner Case Resolution & Collateral Disposition Governance

As a Shop Owner,  
I want to record structured administrative case resolutions (`Under Review`, `Owner Settled / Written Off`, `Collateral Retained / Legal Dispute`) with zero automated collateral disposal,  
So that delinquent collateral cases are formally resolved according to shop policy and regional law while keeping all disposition decisions under human control.

**Acceptance Criteria:**

**Given** an overdue credit that cannot be resolved through standard repayment  
**When** the Shop Owner reviews the delinquent case  
**Then** the Shop Owner can transition the credit into a structured resolution state:
  - `Under Review`: Flags the account for ongoing investigation or formal notice.
  - `Owner Settled / Written Off`: Documents an authorized commercial write-off or negotiated closure, requiring a mandatory justification and ledger adjustment.
  - `Collateral Retained / Legal Dispute`: Documents cases where pledged collateral is retained or referred to legal/police processes.

**Given** any overdue credit resolution in the platform  
**When** evaluated  
**Then** the system strictly avoids automated collateral seizure, automated forfeiture, automated inventory transfers, or public auctions  
**And** all disposition actions require manual Shop Owner review and explicit confirmation.

**Given** a confirmed owner resolution decision  
**When** recorded  
**Then** the system requires a mandatory business rationale  
**And** logs an audit event (Category 10: `Owner decisions on overdue credits and collateral disposition`) recording owner ID, decision type, affected item references, and timestamp.

* **Traceability:** FR-6, FR-28, FR-31 (Event #10), AD-6
* **Dependencies:** Story 6.1 (Overdue credits), Story 1.7 (Shop Owner role)
* **Testing Guidance:** Integration test verifying owner resolution transitions; test asserting automated forfeiture is strictly prohibited; audit verification of resolution decisions and mandatory notes.

---

## Epic 7: Operational Cash Dashboards, Data Export & Disaster Recovery

Shop Owners can view real-time daily cash movements (cash in vs. confirmed cash out), portfolio balances, vault inventory counts, and pending corrections queue; export audited tabular reports in PDF and CSV with PII masked unless possessing `viewSensitiveCustomerData`; view the tamper-resistant activity audit trail; monitor disaster recovery health and backup timestamps; and execute and document disaster recovery verification drills verifying mandatory RPO <= 15m and RTO <= 4h.

### Story 7.1: Shop Owner Real-Time Cash Reconciliation & Portfolio Dashboards

As a Shop Owner,  
I want a real-time operational dashboard summarizing daily counter cash flows (cash in vs. confirmed cash out), portfolio credit counts, vault collateral counts, and pending correction queues,  
So that I have instant financial oversight over shop operations and can reconcile the physical till at the end of each day.

**Acceptance Criteria:**

**Given** an authenticated user with `viewFinancialReports` permission (or Shop Owner role) on the dashboard screen  
**When** viewing the Daily Cash Reconciliation summary for a selected date  
**Then** the system displays:
  - Total Confirmed Repayments Collected (`Cash In`).
  - Total Confirmed Principal Disbursed (`Cash Out`).
  - Net Counter Cash Movement (`Cash In - Cash Out`).
**And** credits in `Active / Pending Disbursement` are strictly excluded from cash disbursement totals.

**Given** the Portfolio Overview widget on the dashboard  
**When** rendered  
**Then** the system displays real-time metrics strictly within the active tenant boundary:
  - Total Active Credits Count and Aggregate Outstanding Principal.
  - Total Overdue Credits Count and Aggregate Overdue Principal.
  - Total Settled Credits Count.
  - Total Collateral Items currently `In Custody` in the vault.

**Given** one or more pending payment correction requests in the shop  
**When** the Shop Owner opens the dashboard  
**Then** the system prominently displays an alert banner in the Pending Corrections Queue showing the count of requests awaiting review.

* **Traceability:** FR-4, FR-6, FR-29, AD-4 (`features/reports`)
* **Dependencies:** Story 4.3 (Disbursed principal), Story 5.2 (Payments)
* **Testing Guidance:** Unit tests for daily cash reconciliation aggregation formulas; verification that undisbursed agreements do not inflate cash-out metrics; tenant isolation test asserting dashboards never aggregate cross-tenant figures.

---

### Story 7.2: Audited Tabular Data Export in PDF & CSV with Server PII Masking

As a Shop Owner and Counter Staff member,  
I want to export standardized operational reports in PDF and CSV formats with customer PII masked according to user permissions and all export actions audited,  
So that I can print executive reports, analyze raw transaction data in spreadsheets, and comply with customer privacy standards.

**Acceptance Criteria:**

**Given** a user with `viewFinancialReports` permission on the reports export screen  
**When** generating an export  
**Then** the system supports four standardized operational reports:
  1. Daily Cash Collection Ledger
  2. Customer Credit Portfolio Summary
  3. Overdue Delinquency Report
  4. Collateral Vault Inventory Report.

**Given** a report export request in PDF format  
**When** rendered  
**Then** the document is pre-formatted with Shop Branding Snapshot, generation timestamp, requesting staff ID, filter date parameters, and page numbering.

**Given** a report export request in CSV format  
**When** generated  
**Then** the file contains machine-readable raw columnar data with exact integer minor unit formatting, standard ISO 8601 timestamps, and UTF-8 encoding.

**Given** an export generated by a user who DOES NOT possess `viewSensitiveCustomerData` permission  
**When** customer records are exported in PDF or CSV  
**Then** full NIC numbers and residential addresses are masked (e.g. `1985****5678`), delivering masked data from the server.

**Given** any report export event  
**When** completed  
**Then** the system appends an audit entry to `audit_events` recording report type, date filters, format (PDF/CSV), and requesting user ID.

* **Traceability:** FR-6, FR-12, FR-30, FR-31, AD-4
* **Dependencies:** Story 7.1 (Reporting queries), Story 2.6 (PII masking)
* **Testing Guidance:** Integration test asserting PII masking is enforced in both PDF and CSV exports for unprivileged roles; validation of CSV decimal formatting and ISO timestamps; audit log verification for export events.

---

### Story 7.3: Database-Enforced Append-Only Audit Trail Viewer & Immutability Trigger

As a Shop Owner and System Auditor,  
I want a dedicated audit trail viewer displaying immutable log records across all 14 critical event categories, backed by a database trigger that rejects any update or deletion,  
So that shop operations are completely transparent, tamper-resistant, and verifiable during disputes or internal investigations.

**Acceptance Criteria:**

**Given** an authenticated user with `viewAuditLogs` permission on the audit viewer screen  
**When** they browse the shop's audit trail  
**Then** the interface displays chronological records across all 14 mandatory critical event categories:
  1. Customer creation and profile edits.
  2. Credit agreement origination and cancellation.
  3. Collateral registration and item detail edits.
  4. Confirmed cash disbursement.
  5. Payment recording (partial and full settlement).
  6. Financial correction requests (with reason).
  7. Financial correction approvals or rejections by Shop Owner.
  8. Due date extensions (with original/revised dates and reason).
  9. Customer follow-up notes and promises to pay.
  10. Owner decisions on overdue credits and collateral disposition.
  11. Collateral physical return confirmations and exception closures.
  12. Staff account creation, deactivation, and permission modifications.
  13. Receipt reprints.
  14. Security events (unauthorized access attempts, cross-tenant violations).
**And** Category 2 carries multiple action types — `credit_agreement_origination`, `cancel_credit_agreement`, and `credit_term_reagreed` — under the canonical catalogue authority (R1/R4); the `action_type` is the distinguishing field within a category.

**Given** any audit record  
**When** inspected  
**Then** it displays: Event ID, Tenant ID, Event Category, Action Type, Actor User ID, Target Entity Reference, Pre/Post State JSON snapshots, Business Reason (where mandatory), Client IP, and Server Timestamp  
**And** passwords, tokens, or unnecessary sensitive identity data are strictly excluded.

**Given** any attempt by any user or administrator to execute SQL `UPDATE` or `DELETE` on the PostgreSQL `audit_events` table  
**When** the command is executed  
**Then** the database trigger `trg_audit_immutable` immediately aborts the operation with an exception: `"Audit trail records are strictly immutable and cannot be updated or deleted."`

* **Traceability:** FR-6, FR-31 (NFR-1), FR-33, AD-6
* **Dependencies:** Story 1.3 (Database audit schema and trigger)
* **Testing Guidance:** Integration test asserting database trigger blocks SQL UPDATE and DELETE on `audit_events`; UI test verifying audit viewer filtering by event category and actor; security verification that passwords/tokens are never logged.

---

### Story 7.4: Automated Security Verification & RBAC Boundary Test Gates

As a Quality Assurance and Platform Security Engineer,  
I want automated security test suites that attempt cross-tenant attacks and verify all 14 RBAC permission toggles, running as mandatory CI gates on every build,  
So that no privilege escalation or cross-tenant data leakage vulnerability can escape into production.

**Acceptance Criteria:**

**Given** the automated security test suite running in GitHub Actions CI  
**When** the Cross-Tenant Boundary Attack suite executes  
**Then** tests simulate URL parameter manipulation, JWT tenant header forgery, and direct database queries attempting to access Shop B data from Shop A  
**And** 100% of unauthorized cross-tenant requests are rejected with `403 Forbidden` / `404 Not Found` (zero cross-tenant data leaks).

**Given** the RBAC Denial Test Suite executing in CI  
**When** tests iterate across all 14 granular permission toggles  
**Then** accounts lacking specific permissions are verified to be strictly blocked from unauthorized actions (e.g. approving corrections, viewing financial summaries, confirming collateral returns, viewing audit logs)  
**And** attempting unauthorized operations logs an Event Category 14 security alert.

**Given** any pull request to the `main` branch  
**When** CI quality checks run  
**Then** `flutter analyze` (zero lints) and `flutter test` (100% security and financial tests passing) must succeed before merge is permitted.

* **Traceability:** FR-4, FR-6, FR-33 (NFR-3), AD-6, AD-7
* **Dependencies:** Story 1.5 (CI pipeline setup)
* **Testing Guidance:** Automated security regression test suite; cross-tenant SQL injection and header forgery tests; automated matrix test exercising all 14 RBAC toggles; recovery-specific gates for generic-response equality (matched vs unmatched identifiers), OTP single-use/expiry/attempt-threshold, idempotent re-transmission, no credential values in logs/audit, and immediate session revocation (Story 1.10 / FR-34).

---

### Story 7.5: Continuous WAL Archiving, S3 Object Versioning & Disaster Recovery Drill Harness

As a Platform Administrator and Shop Owner,  
I want continuous PostgreSQL Write-Ahead Log (WAL) archiving for Point-in-Time Recovery, encrypted S3 object versioning for photos, and a documented disaster recovery drill verifying mandatory RPO $\le 15$m and RTO $\le 4$h,  
So that financial ledgers and collateral photographs are durable, protected against catastrophic hosting failures, and verifiable during restoration drills.

**Acceptance Criteria:**

**Given** the production PostgreSQL deployment  
**When** configured  
**Then** continuous WAL archiving (or provider Point-in-Time Recovery) is enabled with a minimum retention window of 14–30 days, capable of restoring the database to arbitrary second-level timestamps.

**Given** cloud object storage for customer and collateral photographs  
**When** configured  
**Then** object storage enforces Object Versioning and tenant-partitioned paths (`tenants/{tenant_id}/{entity_type}/{id}.webp`), ensuring photos are protected against accidental deletion or corruption.

**Given** a simulated primary database failure during a pre-production disaster recovery drill  
**When** the restoration runbook is executed in an isolated staging environment  
**Then** the database is restored from PITR backups  
**And** automated consistency test suites verify:
  - Exact ledger balance equality ($\text{Balance} = \text{Principal} - \sum\text{Payments} + \sum\text{Reversals} \pm \sum\text{Adjustments}$).
  - Intact parent-child relational integrity (Tenants $\rightarrow$ Customers $\rightarrow$ Credits $\rightarrow$ Collateral $\rightarrow$ Payments).
  - Complete preservation of append-only `audit_events` with zero gaps.
**And** the measured Recovery Point Objective (RPO) is proven to be $\le 15$ minutes and the Recovery Time Objective (RTO) is proven to be $\le 4$ hours.

**Given** the counter client application  
**When** operating offline or synchronizing  
**Then** the interface displays an offline sync status indicator (`Synced`, `Pending Server Confirmation [N items]`, or `Offline`)  
**And** operational documentation explicitly records counter device fault boundaries (unacknowledged offline transactions cannot be recovered if counter hardware is destroyed before syncing).

* **Traceability:** FR-32 (NFR-2), AD-1, AD-8, UX-DR-8
* **Dependencies:** Story 1.4 (Backup harness)
* **Testing Guidance:** Documented execution of disaster recovery restoration drill runbook; post-restore automated ledger integrity test; S3 object versioning delete-marker test; UI test for offline sync indicator.

---

## Epic 8: Item Receipt Terminology & Optional Intake (Change Request)

Counter staff can originate a credit with zero item receipts, and every user-facing origination-flow surface and generated document uses the term **Item Receipt** consistently.

* **FRs covered:** FR-13, FR-14, FR-15, FR-20
* **Architecture:** AD-3 (workflow status derivation for zero-item credits), AD-4 (`features/customers`, `features/collateral`)
* **Change record:** `_bmad-output/planning-artifacts/sprint-change-proposal-2026-11-09.md`

### Story 8.1: Optional Item Receipts at Origination & Terminology Rename

As a Counter Staff member,  
I want item attachment to be optional and labelled "Item Receipt",  
So that the shop can record unsecured credits and the counter language matches how staff describe items held.

**Acceptance Criteria:**

**Given** the credit origination screen  
**When** Counter Staff submits without selecting any item receipt  
**Then** the agreement is created successfully  
**And** no custody record or collateral audit event is generated for that agreement.

**Given** a credit agreement request with an empty item receipt list  
**When** persisted through the credit DAO  
**Then** the agreement is stored with `Financial Status: Active / Pending Disbursement`  
**And** no `ArgumentError` is thrown for the empty list.

**Given** the credit origination screen, disbursement screen, and generated draft/voucher PDFs  
**When** rendered  
**Then** the label reads `Item Receipts` (or `Item Receipt` in the singular)  
**And** the summary reads `Total Estimated Item Receipt Value`  
**And** an empty document renders `No item receipts recorded.`  
**And** no user-facing string in this flow reads `Pledged Collateral`.

**Given** a credit with item receipts attached  
**When** any attached item lacks a photograph and no approved exception exists  
**Then** submission remains blocked with `"Every item receipt must have at least one photograph."`

**Given** a financially settled credit with zero attached item receipts  
**When** the overall workflow status is derived  
**Then** it returns `Closed / Completed` rather than `Settled (Pending Collateral Return)`.

* **Traceability:** FR-13, FR-14, FR-15, FR-20, AD-3
* **Dependencies:** Story 3.1, Story 4.1 (completed)
* **Testing Guidance:** Widget test for zero-item origination submit; DAO unit test for empty item list; deterministic empty-list idempotency fingerprint test; derive-status unit test for zero-item settlement; string assertions for origination, disbursement, and PDF content; retain per-item mandatory-photo tests.


