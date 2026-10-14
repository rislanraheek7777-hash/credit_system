---
title: "Product Brief: Credit Management System"
status: complete
created: 2026-10-13
updated: 2026-10-13
---

# Product Brief: Credit Management System

## Executive Summary

**Credit Management System** is a secure, multi-tenant Software-as-a-Service (SaaS) platform designed for independent retail businesses—including jewelry/gold shops, electronics stores, and businesses offering loans secured against valuable physical items. The platform provides independent shops with isolated digital environments to manage their own customer identity records, pledged collateral, loan agreements, payment transactions, and staff access.

Many small-to-medium retail credit and pawn businesses operate using informal, manual, or fragmented systems. These legacy practices introduce operational friction: balance calculation errors, lost receipts, untraceable record edits, unauthorized staff actions, and customer disputes over pledged item conditions. Credit Management System provides an auditable digital solution: shop owners govern staff permissions and review shop performance, while authorized counter staff register customer KYC (including name, NIC, phone, address, and photo), log pledged item attributes (item type, description, weight where applicable, condition, estimated value, and photos), and issue receipts for partial payments and full settlements.

In its initial version, the platform focuses on accurate zero-interest principal loan tracking, due date monitoring, and manual overdue loan review. Crucially, the platform enforces strict data isolation between shops, guarantees an auditable transaction history where settled records are permanently preserved rather than deleted, and equips shop owners with full control when loans become overdue.

*Proposed Technology Direction:* Flutter (Web and Mobile applications). Final tech stack decisions remain subject to architectural evaluation.

## The Problem

Independent retail businesses offering collateral-backed credit need to balance customer service at the counter with financial accuracy, security, and physical custody of valuable items. Today, these businesses frequently face vulnerabilities arising from non-standardized record keeping.

### Current Coping Mechanisms `[ASSUMPTION - TO VALIDATE]`
Target shops are assumed to rely on handwritten logbooks, physical paper receipts, paper customer index files, or standalone spreadsheets/basic desktop tools. The exact distribution of these methods across target shops will be confirmed through ongoing requirement discovery and interviews.

### Core Problems to Solve

1. **Financial Tracking and Calculation Accuracy:**
   * Tracking original loan principal, multiple partial installments, and remaining balances manually is prone to human mathematical error.
   * Reconciliation at the end of the day or month across active and settled loans is time-consuming and difficult to verify.

2. **Record Integrity, Traceability, and Accountability:**
   * When paper books or unstructured spreadsheets are used, it is difficult to determine who created a record, who updated an amount, or whether every collected payment was recorded properly.
   * Without an immutable audit trail, shop owners lack reliable visibility into staff actions, and staff lack protection against false accusations of mishandling funds.

3. **Pledged Collateral Documentation and Dispute Exposure:**
   * Valuable pledged items (e.g., gold jewelry, consumer electronics) are subject to customer disputes upon loan redemption regarding pre-existing scratches, cosmetic condition, missing accessories, or claimed weight discrepancies.
   * `[POTENTIAL PROBLEM TO VALIDATE]` Without standardized intake records—including photographs, condition notes, and calibrated weights where applicable—shops and customers lack an objective baseline to resolve return disputes.

4. **Overdue Loan Identification and Decision Management:**
   * Identifying which loans have passed their agreed due dates requires manual page-by-page review.
   * When a loan does become overdue, shop owners lack a structured system to review the delinquent case, record their business decision regarding the pledged item, and maintain a historical log of actions taken.

5. **Customer Privacy, Identity Protection, and Record Vulnerability:**
   * Storing sensitive identity records (NIC numbers, personal phone numbers, addresses, and photographs) on paper or unprotected spreadsheets creates data leakage and theft risks.
   * Physical documents face single-point-of-failure risks: damage from water or fire, misplacement, and physical theft can result in total, irrecoverable loss of loan and customer records.

### Affected Stakeholders

* **Shop Owners:** Need accurate financial visibility, staff accountability, dispute mitigation, and control over overdue loan decisions.
* **Staff Members:** Need clear, error-free daily workflows for customer registration, collateral logging, partial payment processing, and receipt issuance within their assigned permissions.
* **Customers:** Need transparent records of their loans and payments, confidence that their sensitive personal data (NIC/photos) is secure, and assurance that their pledged valuables are documented and returned in agreed condition.

## The Solution

**Credit Management System** delivers a multi-tenant cloud application providing independent retail shops with dedicated, secure digital workspaces to manage collateral-backed micro-loans, customer identities, payment histories, and physical item custody.

### 1. Customer Profile & Collateral Intake Experience
* **Reusable Customer Profiles:** Authorized staff can search returning customers by National Identity Card (NIC) number or phone number within their shop. Existing profiles are reused to prevent duplicate entry, and the system flags potential duplicate records during onboarding.
* **Shop-Isolated Customer Privacy:** Customer searches and duplicate checks are strictly confined to the active shop. The system never reveals whether a customer exists in another tenant shop.
* **Customer KYC Records:** Staff record the customer's full name, NIC number, phone number, residential address, and customer photograph. Sensitive personal details and photographs are protected by role-based access control.
* **Multi-Item Collateral Pledges:** A single loan agreement supports one or multiple pledged items (e.g., pledging two rings and an electronic device under one loan principal).
* **Detailed Collateral Documentation:** Each item has an individual record capturing:
  * Item type / category (e.g., gold, jewelry, electronics, general valuables).
  * Description and condition grading.
  * Exact weight (with units, where applicable for precious metals).
  * Estimated valuation.
  * Photographs captured directly via mobile/webcam or uploaded from image files, with pre-save preview. Photographs are required by default; any permitted exception requires authorization, a reason, and an audit record.

### 2. Loan Servicing, Payment Processing & Settlement
* **Due Date Setting:** Staff can select standard duration presets (30, 60, or 90 days from the loan date) with automatic due date calculation, or select a custom date via a date picker.
* **Transparent Zero-Interest Servicing:** The platform tracks the original principal, cumulative repayments, and outstanding balance without automated interest or compounding calculations.
* **Payment Accuracy & Idempotency:** The system prevents overpayments (or handles them through a defined validation/approval workflow). Each payment is recorded exactly once via idempotency controls, and reprinting receipts never generates duplicate transactions. Outstanding balances use exact currency precision to prevent rounding errors.
* **Printable & Digital Receipts:** Every payment (partial installment or full settlement) generates an immutable receipt containing:
  * Unique receipt number and shop branding details.
  * Customer name and identifier.
  * Loan reference number.
  * Payment timestamp and payment type (partial payment vs. full settlement).
  * Amount paid, balance before payment, and remaining outstanding balance.
  * Export options suitable for printing/PDF generation and digital sharing.
* **Decoupled Settlement & Independent Item Return:**
  * Reaching a zero balance marks the loan as *Settled*, preserving complete transaction history.
  * Physical collateral handover is tracked independently: each pledged item maintains its own custody status. Staff must explicitly verify and confirm the return of each item before it is marked *Returned*, recording the return date and the staff member responsible.
  * A loan is not treated as fully handed over until all associated pledged items are accounted for. Authorized exceptions require a recorded reason and audit trail.
* **Controlled Financial Corrections:** Financial transactions cannot be permanently deleted or silently overwritten. Staff may request corrections with a mandatory reason; corrections and reversals require **Shop Owner approval** before recalculating balances. Both the original transaction and the adjusting entry are permanently retained in the audit history.

### 3. Overdue Loan Management & Shop Owner Decisions
* **Automated Overdue Flagging:** Loans with an outstanding balance greater than zero automatically transition to *Overdue* once the due date has passed according to the shop's local date and time. Fully settled loans are never marked overdue.
* **Overdue Visibility & Queues:** Dashboards and search filters highlight overdue accounts with visual badges, filterable by due date and balance. Counter staff have permission-gated visibility to assist customers at the counter.
* **Owner-Led Review & Structured Actions:** The system explicitly avoids automated seizure, sale, or disposal of pledged items. Shop Owners review delinquent accounts and record structured administrative decisions:
  * *Extend Due Date:* Record a revised agreed due date, preserving the original due date in history, alongside the reason, decision date, and owner approval.
  * *Record Follow-up:* Log customer communications, channels, notes, and promised payment dates.
  * *Record Promise to Pay:* Track scheduled customer payment commitments.
  * *Mark Under Review:* Note ongoing case evaluation.
  * *Record Owner Decision / Resolution:* Document the final disposition decision regarding the loan and collateral under applicable legal and shop policies.

### 4. Multi-Tenant Governance & Role-Based Permissions
* **Strict Tenant Data Walls:** Each shop operates within a logically isolated boundary. Staff and owners cannot access, search, or view another shop's customers, loans, items, or financial records under any circumstance.
* **Shop Profile Customization:** Each shop manages its business name, address, contact details, registration/tax numbers, logo, receipt headers/footers, local time zone, and default currency display format.
* **Granular Staff Permissions:** Owners create staff accounts with unique credentials and govern specific operational permissions:
  * Customer registration and profile editing.
  * Loan and collateral intake.
  * Payment processing and receipt generation.
  * Viewing sensitive customer contact info and photos.
  * Viewing shop-wide financial summaries.
  * Requesting vs. approving financial corrections (approvals reserved for owners).
  * Confirming item handovers.
  * Viewing activity logs.
* **Comprehensive Audit Trail:** The system maintains an append-only activity log tracking customer changes, loan/item updates, payments, correction workflows, extensions, owner decisions, collateral handovers, staff account changes, and security events. Audit records are protected against unauthorized modification.

### 5. Reporting, Analytics & Data Export
* **Owner Financial Dashboards:** Real-time visibility into daily payment collections, active loan balances, settled loans, overdue loan summaries, and correction history.
* **Data Export:** Reports support date and status filtering, with export options to PDF (formatted for print and executive sharing) and CSV (structured for spreadsheet analysis), subject to strict user permissions and tenant isolation.

### Non-Functional Requirements for Architecture & Verification
* **Data Backup & Disaster Recovery:** The system architecture must incorporate automated backup and a defined recovery process to guard against service failure or data loss.
* **Security & Tenant Isolation Verification:** Authentication security, tenant isolation, and audit trail tamper-resistance are explicit requirements that must be verified through automated testing rather than treated as unverified assumptions.

### Assumptions & Version 1 Boundaries
* **`[ASSUMPTIONS]`** Initial default market configuration is Sri Lanka and Sri Lankan Rupees (LKR), with currency remaining configurable per shop.
* **`[EXPLICIT NON-GOALS FOR V1]`** Automated SMS/WhatsApp customer reminders; automated collateral seizure, auctioning, or liquidation; automated interest/penalty calculations.

## What Makes This Different

### Core Positioning
> **"A simple, secure, and transparent way for independent shops to manage collateral-backed loans, pledged items, payments, and returns in one place."**

### The Alternative Landscape `[ASSUMPTIONS TO VALIDATE]`
Target shops currently manage collateral-based lending using a mix of manual and basic tools:
* **Paper Logbooks & Handwritten Receipts:** Low cost and familiar, but prone to balance miscalculations, untraceable manual edits, lost receipts, zero searchability, and high vulnerability to physical loss or damage.
* **Spreadsheets (Excel / Google Sheets):** Highly flexible, but lack granular staff permission controls, cannot enforce business rules (e.g., preventing accidental cell deletion or duplicate entries), lack immutable audit histories, and are awkward to use on mobile devices at a counter.
* **General Retail POS & Inventory Systems:** Designed around inventory sales; they lack fundamental mechanisms for loan agreements, pledged item custody, gold weight tracking, partial principal repayments, and return verification.
* **Desktop / On-Premise Software:** Some shops may use legacy desktop software, which often requires local machine maintenance, lacks modern mobile access, and may enforce complex interest models ill-suited for simple micro-lending.
*(Note: The exact prevalence of each alternative among target shops is an assumption to be validated during customer interviews.)*

### Key Differentiators & Intended Outcomes

1. **Unified Collateral-First Workflow:**
   * Unlike general bookkeeping or POS systems, the platform is designed specifically around the lifecycle of a collateralized loan—binding customer KYC, pledged items, repayment history, receipts, and physical item handover into a single, cohesive workflow.
2. **Accurate, Zero-Interest Financial Tracking:**
   * Keeps accounting straightforward and transparent: tracks original principal, records partial installments, prevents overpayments or duplicate entries, and maintains balance accuracy without forcing shops into complex, unnecessary interest or penalty calculations.
3. **Independent Collateral Identification & Return Verification:**
   * Pledged items maintain independent photographic, descriptive, and weight records alongside individual custody statuses. This is intended to directly reduce return disputes and prevent the operational risk of marking a loan settled while physical items remain unreturned.
4. **Owner Governance Balanced with Staff Ergonomics:**
   * Provides counter staff with an efficient, error-free operational flow for customer intake, payment processing, and receipt issuance, while keeping sensitive operations—such as approving payment corrections, adjusting permissions, and making overdue loan decisions—firmly under the Shop Owner’s control.
5. **Accessible Web & Mobile Cloud Experience:**
   * Enables shop owners and staff to securely access the system from supported web browsers and mobile devices without requiring individual shops to host or maintain their own application servers. *(Tech stack and deployment architecture to be confirmed in subsequent planning phases.)*
6. **Built-in Trust, Privacy & Audit Accountability:**
   * Protects sensitive customer identity data (NIC and photos), enforces strict logical isolation between independent shops, and maintains an immutable audit trail of financial and operational events to foster long-term confidence for both owners and customers.

## Who This Serves

### 1. Version 1 Core Personas

#### The Shop Owner — Primary Business Persona
* **Who they are:** Owner or managing partner of an independent retail business (such as a gold/jewelry shop, consumer electronics store, or collateral lending shop).
* **What they need:** Direct oversight over daily cash collections and outstanding credit; strict control over staff accounts and granular permissions; exclusive authority to approve financial corrections and voids; a structured tool to review and record decisions on overdue collateral; and an unalterable audit trail.
* **Intended Success Outcomes:** Greater confidence in shop records, elimination of unexplained ledger discrepancies, clear accountability across counter staff, and documented protection against collateral condition disputes.

#### Counter Staff — Primary Operational Persona
* **Who they are:** Frontline shop employees responsible for customer intake, collateral appraisal/logging, and daily transactions at the counter.
* **What they need:** A simple, efficient interface on web or mobile to quickly look up customers by NIC or phone, capture item photographs and calibrated weights, calculate balances without manual arithmetic errors, print/share receipts, and confirm physical item handovers within their assigned permissions.
* **Intended Success Outcomes:** Fast, low-friction counter transactions, reduced arithmetic mistakes on partial payments, clear operational guardrails, and protection from false blame via automatic activity logs.

#### Customer / Borrower — Primary External Beneficiary
* **Who they are:** Individuals pledging personal valuables as security for short-term credit.
* **What they need:** Verifiable receipts for every partial or full payment; transparent tracking of their remaining balance; robust privacy protection for their sensitive NIC and personal photos; and safe, documented return of their pledged valuables.
* **Intended Success Outcomes:** Trust in the shop's financial transparency and safe, undisputed return of their exact pledged items in original condition upon settlement.
* *Version 1 Boundary:* Customers interact with the system indirectly through counter staff. Customer self-service portals and accounts are treated as open questions and possible future additions.

### 2. Potential & Platform Governance Roles

#### Auditor / Accountant `[OPTIONAL / FUTURE ROLE]`
* **Role & Responsibility:** A designated internal or external financial reviewer who requires read-only access to daily collection summaries, loan ledgers, settlement reports, and activity logs without permission to create loans, record payments, or modify data.
* *Version 1 Boundary:* Optional role pending validated demand from shop owners during discovery.

#### Platform Administrator `[PLATFORM-LEVEL GOVERNANCE ROLE]`
* **Role & Responsibility:** Technical personnel managing multi-tenant infrastructure, shop onboarding, system availability, and maintenance.
* *Strict Privacy Constraint:* Platform Administrators must **not** have default or unrestricted visibility into individual shop records (customer NICs, photographs, or financial ledgers). Any exceptional support access must be strictly authorized, restricted, and audited. *(The dedicated admin UI for Version 1 remains an architectural decision to confirm).*

## Success Criteria

### 1. Mandatory Release Criteria (Verification & Testing Gates)
These non-negotiable functional, financial, and security gates must be verified through automated testing before the system can be approved for production launch:

* **Calculation Accuracy & Decimal Precision:** 100% of tested partial payment sequences, settlements, and balance deductions produce exact results using consistent currency precision, strictly avoiding floating-point rounding errors.
* **Payment Idempotency Verification:** Verified through automated tests and idempotency controls that repeated, concurrent, or re-transmitted submissions of the same payment action can never generate duplicate financial transactions.
* **Required-Field Data Validation:** The system programmatically blocks loan creation if required customer identity fields, loan terms, or pledged item attributes are missing. Pledged-item photographs are required by default; if an authorized exception is permitted, it must strictly require explicit authorization, a recorded reason, and an immutable audit entry.
* **Settlement vs. Handover Decoupling:** The system programmatically prevents marking a loan as fully handed over until 100% of associated pledged items have recorded return confirmations or authorized, audited exceptions.
* **Multi-Tenant Isolation:** Zero unauthorized cross-shop data leaks verified across automated security test suites, database queries, and search APIs.
* **Role-Based Access Enforcement:** Users are strictly blocked from performing actions beyond their assigned permissions; sensitive operations (correction approvals, store financial summaries) remain inaccessible to unauthorized roles.
* **Defined Audit Trail Integrity:** 100% of defined critical events (customer creation/profile edits, loan creation, collateral intake/updates, payments, reversals/corrections, due date extensions, overdue follow-ups, owner decisions, item handovers, staff account and permission changes, and security events) generate append-only audit records. Financial corrections must permanently preserve the original transaction while creating a traceable correction/reversal entry—original transactions can never be silently overwritten or deleted.
* **Backup & Recovery Verification:** Automated backup and disaster recovery restoration procedures must be successfully executed, timed, and documented before production launch.
* **Financial Data Durability:** Zero loss or corruption of confirmed financial records across tested normal operations, simulated service interruptions, and recovery scenarios.

### 2. Pilot Testing Metrics & Operational Goals `[INITIAL TARGETS TO CALIBRATE]`
These metrics represent initial operational targets to be measured and calibrated during pilot deployment in real shops:

* **Counter Efficiency Target:** A trained staff member can look up a returning customer and record a partial payment with receipt generation in under one minute under normal counter conditions (target to validate in pilot).
* **Loan Intake Baseline:** Measure the baseline time required to register a customer, document pledged items, and issue a loan; establish a realistic improvement target after comparing with existing workflows at pilot shops.
* **Daily Ledger Reconciliation Goal:** Support end-of-day reconciliation with a target of zero unexplained balance discrepancies across pilot testing days (any discrepancies must be formally investigated and documented).
* **Collateral Handover Completeness:** 100% of physically completed item returns have a recorded return status, timestamp, and responsible staff identifier.
* **Dispute Baseline Tracking:** Systematically record collateral and balance-related disputes during pilot testing to establish an objective baseline before setting a reduction target.
* **System Availability Target:** Initial availability target of 99.5% monthly uptime (excluding explicitly scheduled and communicated maintenance windows), subject to technical feasibility and hosting choices.

### 3. Longer-Term Business & Adoption Goals
* **Pilot Shop Retention:** Measure how many pilot shops continue using the system for daily operations after the trial period.
* **Qualitative User Feedback:** Collect user satisfaction and ease-of-use ratings from shop owners regarding business oversight and from counter staff regarding transaction speed.
* **Demonstrated Administrative Value:** Measure administrative time saved and evaluate improvements in loan record completeness compared with the pilot baseline, working toward minimizing missing or incomplete records.

## Scope

### In Scope for Version 1
* **Multi-Tenant Shop Onboarding & Profiles:** Shop profile setup (name, address, contact details, registration/tax numbers, logo, receipt headers/footers, local time zone, configurable currency display).
* **Customer Management:** Reusable customer profiles (name, NIC, phone, address, photo) with duplicate detection strictly within the current shop.
* **Collateral Intake:** Multi-item support per loan, item descriptions, calibrated weights (where applicable), condition grading, photographs (camera capture and file upload with preview; photos mandatory by default with audited exception workflow).
* **Zero-Interest Loan Tracking:** Duration presets (30, 60, 90 days) and custom date picker, automatic due date calculation, principal and balance tracking.
* **Payment Processing & Receipts:** Partial payments, full settlements, balance validation to prevent overpayments, duplicate-payment prevention, printable/PDF and shareable digital receipts.
* **Collateral Custody Tracking:** Independent per-item return status tracking, explicit staff return confirmations, decoupling financial settlement from physical handover.
* **Controlled Financial Corrections:** Staff correction requests with mandatory reason; Shop Owner approval required before balance adjustment; permanent preservation of original transaction and adjustment history (no silent edits or deletions).
* **Overdue Loan Governance:** Automatic overdue status when due date passes (shop local time) and balance > 0; structured owner-managed decisions (extensions, follow-up logs, owner decisions, promises to pay, under-review status, resolution logs); no automated disposal.
* **Access Control & Governance:** Role-based permissions, Owner administrative controls, protected append-only audit trail, daily collection and loan balance reports with PDF/CSV export.
* **Non-Functional Foundations:** Multi-tenant data isolation, backup/recovery processes, and role-based protection for sensitive customer PII.

### Explicitly Out of Scope for Version 1
* **Automated Customer Reminders:** Automated SMS or WhatsApp messaging (deferred to a future phase pending notification cost and privacy evaluation).
* **Automated Collateral Liquidation:** Automated seizure, forfeiture, auctioning, or sale of pledged items (all decisions remain manual and owner-governed).
* **Interest & Fee Calculations:** Interest rate schemes, compounding, finance fees, and automated late penalties.
* **Customer Self-Service:** Borrower login portals or mobile apps.
* **Third-Party External Integrations:** Automated police/registry feeds (e.g., LeadsOnline) and direct accounting software integrations (e.g., QuickBooks/Xero).

### Key Assumptions & Deferrals
* `[ASSUMPTIONS]` Initial default operating region is Sri Lanka with Sri Lankan Rupees (LKR) as the default currency format, with currency remaining configurable per shop.
* `[ARCHITECTURE DEFERRALS]` Final technology stack (Flutter Web/Mobile as proposed direction), cloud hosting infrastructure, and deployment architecture remain subject to architectural confirmation.

## Vision

### 1. Long-Term Aspiration (2–3 Year Horizon)
**Credit Management System** aspires to become the trusted, standard business management platform for independent retail shops that offer collateral-backed micro-credit. Over the next two to three years, the platform aims to evolve from its initial Version 1 foundation into a comprehensive operational solution that helps shop owners govern customer records, pledged valuables, loan balances, repayments, delinquent accounts, and physical item returns with absolute transparency and ease.

The initial rollout will focus on proving tangible business value, reliability, and security in real-world retail shops within Sri Lanka. Once validated, the platform will explore measured expansion into broader regional markets where independent collateral-backed lending models are prevalent, subject to local regulatory compliance, market demand, and commercial feasibility.

### 2. Core Long-Term Pillars
* **Uncompromising Operational Accuracy:** Continuous refinement of daily counter workflows to ensure zero financial record loss, mathematically exact balances, and rapid reconciliation.
* **Customer Privacy & Data Protection:** Setting a high standard of data security for customer personal identity records (NIC and photos) and strict multi-tenant boundary protection.
* **Custody Accountability:** Strengthening trust between lenders and borrowers through transparent, photographic, and verifiable physical asset tracking.
* **Ease of Daily Operation:** Empowering shop owners and counter staff with intuitive, accessible tools on web and mobile that replace tedious paperwork with effortless digital governance.

### 3. Potential Future Capabilities `[POSSIBILITIES SUBJECT TO PILOT VALIDATION]`
The following capabilities represent growth opportunities to evaluate based on verified user demand, operational feedback, and regulatory feasibility:
* **Automated Customer Notifications:** Automated SMS or WhatsApp messages for payment receipts, upcoming due-date reminders, and loan status updates.
* **Customer Self-Service Portal:** Optional web/mobile borrower accounts allowing customers to view their active loan balances, scheduled due dates, historical payment receipts, and pledged item status.
* **Multi-Branch Enterprise Management:** Centralized dashboard for shop owners operating chains across multiple physical store locations, enabling consolidated reporting and cross-branch inventory visibility while maintaining strict role boundaries.
* **Business Intelligence & Analytics:** Advanced cash-flow forecasting, risk modeling on overdue loan aging, and seasonal liquidity insights.
* **Third-Party Ecosystem Integrations:** Optional integrations with external accounting suites (e.g., Xero, QuickBooks) and localized business tools.
* **Configurable Financial Models:** Optional interest rate and fee-calculation engines, introduced strictly if justified by customer demand and full compliance with regional financial regulations.
