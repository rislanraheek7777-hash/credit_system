---
title: "Product Brief Addendum: Credit Management System"
status: complete
created: 2026-10-13
updated: 2026-10-13
---

# Product Brief Addendum: Credit Management System

This addendum preserves downstream context, architectural deferrals, detailed schemas, and parked roadmap candidates established during the product brief discovery sessions for **Credit Management System**. These details feed directly into the subsequent Product Requirements Document (PRD) and Technical Architecture phases.

---

## 1. Downstream Architecture Considerations & Invariants

* **Multi-Tenant Data Isolation Strategy:**
  * Architecture must evaluate and enforce tenant boundary security (e.g., Row-Level Security, tenancy middleware, or isolated schemas).
  * Automated security test suites must explicitly test cross-tenant boundary attacks to guarantee that no API query or lookup can expose another shop’s records.
* **Financial Precision & Idempotency:**
  * All currency operations must use fixed-point decimal arithmetic or integer minor units (e.g., cents) to eliminate IEEE 754 floating-point rounding errors.
  * Payment submission endpoints must employ idempotency tokens or unique constraint locks to guarantee that network retries or repeated counter clicks never record duplicate transactions.
* **Decoupled Collateral Handover State Machine:**
  * Loans and physical pledged items must maintain decoupled lifecycles:
    * Loan Financial State: `Active` $\rightarrow$ `Settled` (when balance reaches 0).
    * Collateral Physical State: `In Custody` $\rightarrow$ `Returned` (only upon verified physical handover).
    * A loan record cannot transition to `Closed / Completed` until all pledged items are in `Returned` status or have an authorized, audited exception recorded.
* **Controlled Financial Correction Workflow:**
  * Reversals and adjustments must never overwrite or delete original records. The architecture must implement a compensating entry ledger pattern where the original transaction, adjustment entry, reason, requesting user, and approving owner are linked immutably.
* **Data Backup, Recovery & Durability:**
  * Concrete Recovery Point Objective (RPO) and Recovery Time Objective (RTO) targets must be formalized during architecture.
  * Disaster recovery procedures must be verified through executed restoration drills prior to production deployment.
* **Media / Photo Storage:**
  * Secure, access-controlled image storage with pre-upload compression for customer identification photos and collateral verification photos.

---

## 2. Downstream Requirements & Entity Specification

### A. Customer Entity
* Full Name
* National Identity Card (NIC) number (indexed with unique constraint within the shop tenant)
* Phone Number
* Residential Address
* Customer Photograph
* Duplicate check logic: Pre-creation matching on NIC and Phone within the active shop.

### B. Collateral Entity (Multi-Item per Loan)
* Item Category / Type (Gold/Jewelry, Electronics, General Valuables)
* Description & Detailed Notes
* Condition Grading
* Calibrated Weight & Units (mandatory for precious metals)
* Estimated Valuation
* Item Photographs (mandatory by default; exception requires owner authorization and audit log)
* Custody Status (`In Custody`, `Returned`, `Exception / Held`)
* Return Confirmation Record (Return Timestamp, Handing Staff Member, Customer Handover Confirmation)

### C. Loan Entity
* Loan Reference Number (unique per shop)
* Customer Reference
* Pledged Item References (one or many)
* Principal Amount
* Loan Date & Shop Local Timestamp
* Due Date (calculated from 30/60/90-day preset or custom calendar picker)
* Financial Status (`Active`, `Overdue`, `Settled`)
* Cumulative Paid Amount & Current Outstanding Balance

### D. Payment Entity
* Unique Receipt Number
* Loan Reference
* Payment Timestamp & Responsible Staff Member
* Payment Type (`Partial Payment`, `Full Settlement`)
* Amount Paid
* Pre-Payment Balance & Resulting Outstanding Balance
* Idempotency Token / Submission Identifier

### E. Defined Critical Audit Events Catalog
The system must log the following 11 events in an append-only audit trail:
1. Customer creation and profile edits.
2. Loan agreement creation.
3. Collateral registration and item detail edits.
4. Payment recording (partial and full settlement).
5. Financial correction requests (with reason).
6. Financial correction approvals or rejections by Shop Owner.
7. Due date extensions (with original date preserved, revised date, reason, and owner approval).
8. Overdue customer follow-ups and promises to pay.
9. Owner decisions regarding overdue loans and collateral disposition.
10. Collateral physical return confirmations.
11. Staff account creation, deactivation, and permission modifications.

---

## 3. Parked Future Capabilities (Post-V1 Evaluation)

The following features were evaluated and deliberately parked for future roadmap consideration following pilot validation:
* **Automated Customer Notifications:** SMS and WhatsApp integrations for automated payment receipts, upcoming due-date alerts, and overdue reminders (subject to messaging costs, carrier integrations, and privacy consent).
* **Customer Self-Service Portal:** Web/mobile portal allowing borrowers to view balances, due dates, and receipts directly.
* **Multi-Branch Hierarchy:** Consolidated management for business owners operating multiple storefronts or branches.
* **Business Analytics & Cash Flow Forecasting:** Liquidity insights, overdue loan aging heatmaps, and collateral valuation trend reports.
* **Accounting Integrations:** Bi-directional sync with platforms like QuickBooks or Xero.
* **Configurable Financial Engines:** Interest rate and penalty calculation schemes, to be designed only if validated by market demand and regional compliance.

---

## 4. Key Assumptions to Validate in Pilot Phase

* **Regional Context:** Sri Lanka and Sri Lankan Rupees (LKR) are the initial operational baseline; the system supports configurable currencies for broader international viability.
* **Legacy Method Baseline:** The prevalence of handwritten paper ledgers vs. spreadsheets in target shops must be surveyed during pilot recruitment to accurately quantify operational improvements.
* **Operational Velocity:** The 1-minute returning customer partial payment target and 99.5% availability target will be calibrated against real-world counter performance and hosting benchmarks.
