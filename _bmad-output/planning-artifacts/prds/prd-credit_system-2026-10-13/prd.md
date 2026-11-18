---
title: "PRD: Credit Management System"
status: final
created: 2026-10-13
updated: 2026-10-14
---

# PRD: Credit Management System

## 0. Document Purpose

This Product Requirements Document (PRD) defines the functional, operational, and security requirements for **Credit Management System** Version 1. It serves as the primary technical specification for system architects, software developers, UI/UX designers, and quality assurance engineers.

All requirements build directly upon the approved [Product Brief](file:///C:/projects/credit_system/_bmad-output/planning-artifacts/briefs/brief-credit_system-2026-10-13/brief.md) and [Addendum](file:///C:/projects/credit_system/_bmad-output/planning-artifacts/briefs/brief-credit_system-2026-10-13/addendum.md). Requirements are organized by functional areas using stable, numbered identifiers (FR-1 through FR-N), unambiguous business rules, and testable acceptance criteria suitable for verification in automated and manual test suites. Assumptions, unresolved decisions, and operational boundaries are explicitly tagged.

## 1. Vision

**Credit Management System** is a multi-tenant Software-as-a-Service (SaaS) platform designed for independent retail businesses—including jewelry/gold shops, consumer electronics stores, and retail businesses that provide credits secured against valuable physical items. The platform provides independent shops with dedicated, logically isolated digital environments to manage customer identity records, pledged collateral, credit agreements, payment transactions, staff permissions, and item returns.

In its initial version, the platform is intended to reduce the operational, financial, and security risks associated with handwritten paper logbooks and disconnected spreadsheets. It addresses these risks by providing transparent zero-interest principal tracking, exact monetary calculation precision, duplicate-payment prevention, an auditable transaction history where original entries cannot be silently altered or deleted, independent tracking of physical collateral custody, and owner-governed overdue credit reviews.

*Proposed Technology Direction:* Flutter (Web and Mobile applications). Final technology stack, database architecture, and hosting decisions remain subject to architectural confirmation.

## 2. Target User

### 2.1 Jobs To Be Done (JTBD)

#### The Shop Owner
* **Financial Governance & Visibility:** *“I need to view accurate daily cash collections, outstanding credit principal, and overdue accounts in one place so that I can monitor my shop’s financial standing without relying on error-prone manual ledger calculations.”*
* **Theft & Discrepancy Risk Mitigation:** *“I need operational controls and an unalterable audit trail so that every rupee collected at the counter is legitimately accounted for, and unauthorized edits or silent deletions are prevented.”*
* **Collateral Protection & Dispute Mitigation:** *“I need clear photographic and weight records captured at intake so that when a customer redeems a pledge, our staff have objective verification records to resolve any disputes regarding item condition or missing components.”*
* **Overdue Decision Control:** *“I need structured oversight over credits that pass their due dates so I can record extensions, customer follow-up notes, or resolution decisions, while ensuring the software never takes automated actions to seize or sell pledged items.”*
* **Data Privacy & Tenant Security:** *“I need confidence that our shop’s customer identities and financial records are strictly isolated and cannot be viewed or searched by any other shop on the platform.”*

#### Counter Staff
* **Fast, Frictionless Customer Intake:** *“I need to look up returning customers quickly by NIC or phone number within our shop so I do not waste time repeatedly typing the same personal details.”*
* **Accurate, Mistake-Proof Payment Processing:** *“I need the system to calculate outstanding balances and validate payments against the actual balance so that manual arithmetic mistakes on partial payments are eliminated.”*
* **Instant Proof of Transaction:** *“I need to issue an immediate printable or digital receipt for every confirmed payment so customers leave with proof, and I have documentation that funds were received.”*
* **Independent Collateral Return Verification:** *“I need to verify pledged items against original photos and recorded weights before handing them back, tracking the return status of each item independently so our vault inventory remains accurate even if a customer retrieves only part of their pledged items.”*

#### Customer / Borrower
* **Transparent Transaction Records:** *“I need an unambiguous receipt for every payment showing how much was paid and my exact remaining outstanding balance.”*
* **Safe Custody of Valuables:** *“I need confidence that my pledged valuables are securely stored, properly identified, and returned to me in their original condition upon credit settlement.”*
* **Privacy of Personal Data:** *“I need assurance that my national identity number, phone number, and personal photo are securely stored and not accessible to unauthorized parties or other shops.”*

### 2.2 Non-Users (Version 1)
* **Borrower Self-Service Users:** In Version 1, customers do not have direct system login credentials or a self-service mobile app. All interaction is mediated by shop staff.
* **Multi-Branch Corporate Chains:** Version 1 strictly scopes to independent shop tenants. Multi-store chains needing cross-branch inventory pooling or centralized multi-location balance sharing are out of scope.
* **Commercial Amortization / Installment Lenders:** The platform is not built for conventional banking, compound interest, or installment credit with dynamic interest amortization matrices.

### 2.3 Key User Journeys

*(Note: Persona names, shop names, National Identity Card numbers, credit references, and financial amounts below are illustrative examples used to clarify concrete behavior; they do not represent hardcoded values).*

#### UJ-1: New Customer Registration & Collateral Credit Origination
* **Persona & Context:** Kasun (Counter Staff at Perera Jewellers) and Sunil (a new customer pledging items for short-term credit).
* **Entry State:** Kasun is authenticated on the counter interface with permission to create customer and credit records.
* **Path:**
  1. Kasun searches for Sunil by NIC number (`198512345678`) strictly within Perera Jewellers. The system confirms no profile exists within the shop and opens the registration screen.
  2. Kasun enters Sunil’s full name, phone number, and residential address, and captures Sunil’s live photograph using the device camera (or uploads an image file with pre-save preview).
  3. Kasun initiates credit creation: selects a **30-day preset duration** (system auto-computes the calendar due date based on shop local time) and enters a requested **Principal Amount** of `50,000 LKR`.
  4. Kasun adds **Item Receipt 1**: selects category `Gold/Jewelry`, enters description (`22K Gold Sovereign Necklace, rope design`), inputs weight (`12.40 grams`), grades condition (`Good, minor clasp wear`), enters an **Estimated Collateral Value** (`75,000 LKR`—stored independently from the credit principal), and captures two item photos.
  5. Kasun adds **Item Receipt 2**: selects category `Electronics`, enters description (`Samsung Galaxy A54`), inputs condition (`Light scratches on rear, screen intact`), enters estimated value (`40,000 LKR`), and captures an item photo.
  6. Kasun reviews the complete summary and taps *Create Credit Agreement*. The system verifies idempotency (preventing duplicate credit creation if the button is pressed repeatedly during a slow network response).
  7. The credit is created in the initial state: `Financial Status: Active / Pending Disbursement`, `Custody Status (per item): In Custody`, `Overall Workflow Status: Active (Pending Disbursement)`.
  8. Kasun or the Shop Owner verifies cash handover and confirms disbursement. The credit state updates to `Financial Status: Active / Disbursed`, `Overall Workflow Status: Active`.
* **Climax:** The system validates that all required customer fields, credit terms, and collateral photos exist, records Kasun as the creator, records the disbursing user and timestamp, and generates a printable initial agreement/ticket.
* **Resolution:** Sunil receives `50,000 LKR` cash and his customer slip. Pledged items are tagged with unique item references and placed in the shop vault. Reports distinguish undisbursed credits from disbursed credits, ensuring cash reports do not reflect undisbursed funds.
* **Edge Case (Photo Exception):** If an item cannot be photographed due to an exceptional hardware failure, Counter Staff may request a missing-photo exception with a mandatory reason, but cannot self-approve. Only the Shop Owner can approve the exception override, which is permanently logged in the audit trail. If denied, credit creation remains blocked.

#### UJ-2: Fast Returning-Customer Partial Payment & Receipt Generation
* **Persona & Context:** Kasun (Counter Staff) and Sunil (returning two weeks later to make a partial payment).
* **Entry State:** Kasun is authenticated on the counter terminal.
* **Path:**
  1. Kasun searches by Sunil’s NIC or phone number strictly within the active shop.
  2. Sunil’s profile displays his credit history. Because a customer may hold multiple credits (active, overdue, or settled), the system prompts Kasun to **explicitly select the target credit** (Credit `#LN-1042`: Principal `50,000 LKR`, Valid Outstanding Balance `50,000 LKR`, Due in 16 days).
  3. Sunil tenders `20,000 LKR` cash.
  4. Kasun inputs `20,000 LKR`. The system validates that `0 < Payment <= Valid Outstanding Balance` and previews the new balance: `30,000 LKR`.
  5. Kasun submits the payment with an automated idempotency token.
* **Climax:** The server processes the transaction, prevents duplicate postings from double-clicks or retries, updates the valid balance to `30,000 LKR`, and generates Receipt `#RCP-8801`.
* **Resolution:** Kasun prints the receipt for Sunil. Pre-payment balance (`50,000 LKR`), amount paid (`20,000 LKR`), and resulting balance (`30,000 LKR`) are clearly documented. *(Note: Completing this counter flow in under one minute is an operational target to calibrate during pilot testing, not a hard functional constraint).*
* **Edge Cases:**
  * **Overpayment Attempt:** If Kasun enters `55,000 LKR`, the system blocks the submission: *"Payment cannot exceed current outstanding balance of 50,000 LKR."*
  * **Receipt Reprint:** If Sunil asks for a replacement slip later, Kasun selects *Reprint Receipt*. The system reprints Receipt `#RCP-8801` with its original transaction identity, receipt number, and financial contents, generating a distinct reprint audit log entry.

#### UJ-3: Full Financial Settlement & Independent Collateral Handover
* **Persona & Context:** Kasun (Counter Staff) and Sunil (paying the remaining `30,000 LKR` to settle the credit and retrieve his valuables).
* **Entry State:** Credit `#LN-1042` has a valid outstanding balance of `30,000 LKR` with two items in custody.
* **Path:**
  1. Kasun records the final payment of `30,000 LKR`.
  2. The valid balance reaches exactly `0.00 LKR`. The financial state transitions to **Settled**.
  3. The system prints a settlement receipt and updates the derived status to: `Financial Status: Settled`, `Custody Status (Item 1): In Custody`, `Custody Status (Item 2): In Custody`, `Overall Workflow Status: Settled (Items Pending Handover)`.
  4. Kasun retrieves the items from the vault.
  5. On screen, Kasun uses the original intake photos and weight notes as verification aids (checking the gold necklace on a scale to verify `12.40g` and inspecting the smartphone screen).
  6. In front of Sunil, Kasun checks both items on screen and taps *Confirm Return to Customer*.
* **Climax:** The system prompts for handover confirmation. Each item independently updates from `In Custody` to `Returned`, recording Kasun’s staff ID and the exact timestamp.
* **Resolution:** When all items are confirmed returned, the derived overall status updates to `Closed / Completed`. The credit record remains permanently searchable in historical reporting.
* **Edge Case (Partial Collateral Pickup):** If Sunil settles the credit in full but only collects his smartphone today (asking the shop to keep the gold necklace until tomorrow), Kasun marks only the phone as `Returned`. The gold necklace remains `In Custody`. The system maintains the overall status as `Settled (Items Pending Handover)` and prevents the credit from being marked as fully handed over until all items are returned or an authorized exception is recorded.

#### UJ-4: Payment Correction & Shop Owner Approval Workflow
* **Persona & Context:** Kasun (Counter Staff) and Mr. Perera (Shop Owner).
* **Entry State:** Kasun accidentally typed `35,000 LKR` instead of `3,500 LKR` for a partial payment and recognized the mistake after printing.
* **Path:**
  1. Kasun navigates to the payment record and selects *Request Correction*.
  2. Kasun enters a mandatory reason: *"Typographical error: entered 35,000 instead of 3,500 cash received"*.
  3. The transaction is flagged as `Correction Pending Approval`.
  4. **Correction-Pending Lock:** The system temporarily blocks new payment submissions specifically on this affected credit while the correction is pending approval, preventing subsequent transactions from being recorded against an unverified balance. Other credits in the shop remain unaffected.
  5. Mr. Perera reviews his owner dashboard queue, inspects the physical till, and evaluates Kasun's request.
* **Climax:** 
  * *If Approved:* Mr. Perera approves the reversal. The system posts a compensating reversal entry referencing the original payment, recalculates the valid balance, unlocks the credit, and logs the approval in the audit trail. The original erroneous record is permanently retained in history.
  * *If Rejected:* Mr. Perera enters a mandatory rejection reason (e.g., *"Till audit does not reflect cash discrepancy"*). The request transitions to `Rejected`, the balance remains unchanged, the payment lock on the credit is lifted, and the rejection is logged in the audit trail.
* **Resolution:** Upon approval, Kasun posts the correct payment of `3,500 LKR` as a fresh transaction, generating a new valid receipt.

#### UJ-5: Overdue Credit Review & Due Date Extension
* **Persona & Context:** Mr. Perera (Shop Owner) reviewing delinquent accounts.
* **Entry State:** A credit of `25,000 LKR` has reached 00:00:00 on the calendar day following its due date in the shop's local time zone with a valid outstanding balance greater than zero.
* **Path:**
  1. The system automatically transitions the credit to: `Financial Status: Overdue`, `Overall Workflow Status: Overdue`. A prominent Overdue badge is displayed on dashboards and search lists.
  2. Mr. Perera opens the Overdue Review queue, reviews the customer contact details, and calls the borrower.
  3. The borrower explains a temporary emergency and requests a two-week extension, promising to pay by November 5.
  4. Mr. Perera selects *Extend Due Date*, inputs `2026-11-05`, enters the reason (*"Customer phone request; promised full settlement by Nov 5"*), and confirms.
* **Climax:** The system updates the active due date to `2026-11-05`, temporarily clears the overdue status until the new date passes, preserves the original due date and the full chain of prior extensions in history, and writes an audit log entry.
* **Resolution:** Mr. Perera maintains complete business control. No automated seizure, forfeiture, or liquidation occurs.
* **Open Decision `[OPEN DECISION: CUSTOMER ACKNOWLEDGEMENT]`:** Whether a due-date extension requires signed customer paperwork, an SMS confirmation, or remains an internal owner note will be validated during pilot shop interviews.

### 2.4 Additional Edge Cases & Concurrency Guards

1. **Concurrent Payments on the Same Credit:** If two staff members attempt to record a payment on the same credit simultaneously, optimistic concurrency locking ensures the second request re-evaluates the updated balance and blocks overpayments.
2. **Network Timeout on Submission:** If a payment request times out after the server has already committed the transaction, the client retries with the same idempotency key; the server detects the existing transaction and returns the original receipt without creating a duplicate.
3. **Multiple Credits per Customer:** A customer profile clearly distinguishes active, overdue, and settled credits, preventing staff from misapplying funds to the wrong agreement.
4. **Unauthorized Staff Actions:** If a staff member attempts an operation without required permissions (e.g., viewing shop-level revenue or approving a reversal), the system immediately blocks the action with a clear permission error and logs the attempt.
5. **Due Date Arrival with Positive Balance:** Automatic transition to `Overdue` occurs at 00:00:00 on the calendar day after the due date in the shop's local time zone if the valid balance is greater than zero. Settled credits are excluded from this transition.

## 3. Glossary

*Downstream workflows, specifications, and implementations must use these terms exactly. No synonyms may be introduced.*

* **Shop / Tenant:** An independent retail business registered on the platform. All data (customers, credits, items, payments, staff accounts, reports, activity logs) belonging to a shop is strictly isolated from every other shop.
* **Shop Owner:** The primary administrative user of a shop tenant, possessing full governance over staff accounts, permission assignments, business profile configuration, financial reports, overdue decisions, and correction approvals.
* **Counter Staff:** An operational employee authorized by the Shop Owner to perform day-to-day counter tasks (customer intake, collateral logging, payment recording, receipt printing, item handover) based on assigned permissions.
* **Platform Administrator:** A platform-level technical role responsible for multi-tenant infrastructure, tenant onboarding, system availability, and service administration. Explicitly restricted from viewing tenant customer PII (NIC/photos) or financial ledgers without audited authorization.
* **Customer / Borrower:** An individual who pledges physical valuables to a shop in exchange for a short-term credit advance.
* **Customer Profile:** A reusable record containing customer identity data (Name, NIC, Phone, Address, Photo). A customer profile can be reused for multiple credits within the same shop, but is never exposed across different shops.
* **Item Receipt (Pledged Item / Collateral):** A physical valuable (e.g., gold jewelry, consumer electronics) recorded as held by the shop as security for a credit. Each item receipt maintains its own descriptive, photographic, weight, and custody records. Attachment to a credit agreement is optional.
* **Credit Agreement:** The system's recorded terms linking a customer, zero or more item receipts, a principal credit amount, an agreed due date, and repayment history. *(Note: Legal enforceability and statutory disclosures are subject to external legal validation).*
* **Zero-Interest Model:** The financial model for Version 1 where the total amount to repay equals the original principal disbursed, with no automated interest or compounding fees.
* **Principal:** The initial disbursed credit amount recorded upon credit creation.
* **Payment (Confirmed):** A successfully recorded and posted financial transaction that reduces the outstanding principal balance of a credit. Distinguished from pending, failed, cancelled, or reversed transaction states.
* **Outstanding Balance:** The remaining unpaid principal on an active credit, calculated as the original principal adjusted by all valid, posted financial transactions (including approved reversals and adjustments).
* **Partial Payment:** A confirmed payment that reduces the outstanding balance but leaves a remaining balance greater than zero.
* **Settlement:** The financial state of a credit when its valid outstanding balance reaches exactly zero. Settlement does not signify that physical pledged items have been returned.
* **Custody Status:** The independently tracked physical state of each pledged item (`In Custody`, `Returned`, `Exception / Held`). A credit may be financially settled while one or more pledged items remain in custody.
* **Overall Workflow Status:** The derived macro status of a credit reflecting both financial and custody reality: `Active (Pending Disbursement)`, `Active`, `Overdue`, `Settled (Items Pending Handover)`, `Closed / Completed`, or `Closed (Collateral Exception)`.
* **Overdue Credit:** A credit whose agreed due date has passed according to the shop's configured local date and time, and whose valid outstanding balance is greater than zero. A settled credit must not be marked overdue.
* **Compensating Reversal / Adjustment:** A controlled financial entry that corrects an erroneous transaction by recording a correcting entry, reason, responsible user, timestamp, and required Shop Owner approval, while permanently preserving the original transaction in history.
* **Audit Trail:** An append-only, tamper-resistant log capturing the actor, action type, timestamp, affected record, relevant change details, and business reason where applicable.

## 4. Features *(Review Draft — Under User Review)*

### 4.1 Multi-Tenant Shop Management & Governance

**Description:** Provides independent retail businesses with self-contained, isolated digital workspaces. Every shop operates under its own profile, local time zone, currency formatting, and branding. The Platform Administrator manages platform availability and tenant provisioning but has strictly restricted access to individual shop customer PII and ledgers.

#### FR-1: Shop Profile Configuration
A Shop Owner can configure and update their shop's business profile, including shop name, business address, contact telephone, email, business registration/tax number, shop logo, and custom receipt header and footer notes. Realizes UJ-1, UJ-2.
* **Realizes:** UJ-1, UJ-2.
* **Consequences (testable):**
  - Updated receipt header, footer notes, logo, and shop details immediately apply to newly generated receipts.
  - Historical receipts are protected via immutable snapshots (FR-24); changes to shop profile, logo, or receipt notes apply strictly to future receipts and never alter or overwrite previously generated historical receipts.
  - Updates made by Shop A never alter or reflect in the profile of Shop B.
* **Business Rules & Permissions:** Restricted to Shop Owner role.
* **Audit Requirements:** Logs profile updates with timestamp, owner ID, and changed field attributes in the append-only, tamper-resistant audit trail.
* **Out of Scope:** Multi-branch parent-child shop hierarchy in Version 1.

#### FR-2: Shop Timezone & Calendar Semantics
A Shop Owner can configure their shop's local time zone (defaulting to `Asia/Colombo` for Sri Lankan deployments `[ASSUMPTION]`). The system evaluates all calendar due dates and overdue transitions against this configured time zone. Realizes UJ-1, UJ-5.
* **Realizes:** UJ-1, UJ-5.
* **Consequences (testable):**
  - Overdue status transitions automatically take effect at 00:00:00 on the calendar day after the due date (Due Date + 1) in the shop's configured local time zone if the valid outstanding balance is greater than zero.
  - Two shops configured in different time zones evaluate due dates and overdue transitions according to their respective local calendar dates.
* **Business Rules & Permissions:** Restricted to Shop Owner role.
* **Audit Requirements:** Logs timezone modifications with old and new values in the append-only, tamper-resistant audit trail.
* **Out of Scope:** Automatic daylight saving time shifts for regions without DST.

#### FR-3: Configurable Currency Display & Ledger Currency Immutability
A Shop Owner can configure the shop's currency display format and presentation symbol (defaulting to Sri Lankan Rupees, `LKR` `[ASSUMPTION]`). Realizes UJ-1, UJ-2.
* **Realizes:** UJ-1, UJ-2.
* **Consequences (testable):**
  - **Presentation vs. Ledger Currency:** The system strictly separates presentation formatting (currency symbol, symbol placement prefix/suffix, decimal separator, thousands grouping) from the underlying base ledger currency code (e.g., ISO 4217 code `LKR`).
  - Presentation formatting changes apply purely to the user interface, receipt rendering, and report displays; they do not alter stored numerical monetary amounts or execute currency conversions.
  - **Preventing Misrepresentation of Financial Records:** Once any financial transaction (credit agreement origination, cash disbursement, payment, reversal, or adjustment) exists within the shop tenant, the underlying base ledger currency code is strictly locked and cannot be altered. This prevents misrepresenting historical debt or payment figures under a different currency unit without authorized conversion.
  - `[OPEN DECISION: POST-TRANSACTION CURRENCY CODE ALTERATION POLICY]`: Defines whether the base ledger currency code is permanently immutable once transactions exist or whether an owner-authorized multi-tenant redenomination or currency migration procedure could be supported in a future version. In Version 1, base ledger currency changes post-transaction are programmatically blocked.
* **Business Rules & Permissions:** Restricted to Shop Owner role.
* **Audit Requirements:** Logs all presentation formatting changes and any attempted ledger currency modifications in the append-only, tamper-resistant audit trail.
* **Out of Scope:** Multi-currency transactions, dynamic FX conversion, or multi-currency wallets within a single shop in Version 1.

#### FR-4: Strict Server-Side Tenant Isolation Enforcement
The system must enforce strict tenant data isolation on the server side across all database queries, API routes, search indexes, and file storage requests. No user in Shop A can search, retrieve, view, or modify customer records, credits, pledged items, payments, staff profiles, or audit logs belonging to Shop B under any operational condition. Realizes UJ-1, UJ-2, UJ-3.
* **Realizes:** UJ-1, UJ-2, UJ-3.
* **Consequences (testable):**
  - API requests, URL manipulations, or direct database queries attempting to access a foreign tenant ID return an immediate authorization rejection (`403 Forbidden` / `404 Not Found`) without revealing whether the resource exists in another shop.
  - Customer NIC or phone searches execute strictly within the active shop tenant and return zero results if the individual exists only in another shop.
* **Business Rules & Permissions:** Enforced on all incoming requests regardless of role.
* **Audit Requirements:** Unauthorized cross-tenant access attempts trigger high-priority security audit logs in the append-only, tamper-resistant audit trail.
* **Out of Scope:** Physical database-per-tenant hardware isolation (architecture evaluates logical isolation strategies).

---

### 4.2 Staff Management & Role-Based Access Control (RBAC)

**Description:** Allows the Shop Owner to govern employee access, create unique login accounts for counter staff, and assign granular operational permissions while safeguarding sensitive administrative actions.

#### FR-5: Staff Account Administration & Session Revocation
A Shop Owner can create, view, activate, and deactivate staff member accounts for their shop, assigning each staff member a unique username/email and login credentials. Realizes UJ-1, UJ-4.
* **Realizes:** UJ-1, UJ-4.
* **Consequences (testable):**
  - Deactivating a staff account immediately revokes all active authentication tokens and active sessions on the server side, preventing subsequent logins and operations.
  - Deactivated staff members cannot be assigned as the actor for new credits, payments, disbursements, or item returns.
* **Business Rules & Permissions:** Restricted to Shop Owner role.
* **Audit Requirements:** Logs account creation, activation, and deactivation with timestamps and actor ID in the append-only, tamper-resistant audit trail.
* **Out of Scope:** Self-service public registration for staff members (all staff creation is owner-initiated).

#### FR-6: Granular Permission Assignment
A Shop Owner can enable or disable specific operational permission toggles for each staff account, covering an explicit catalog of 14 permissions:
1. `Register Customers`: Register new customers and edit permitted profile details.
2. `View Customers`: Search and view customer contact details and photographs.
3. `View Sensitive Customer Data`: View unmasked customer sensitive identity data (full NIC and residential address).
4. `Create Credits`: Create new credit agreements and register attached pledged items.
5. `Confirm Credit Disbursement`: Confirm physical cash disbursement and record disbursement handover.
6. `Record Payments`: Record partial payments and full settlements against disbursed credits.
7. `View and Reprint Receipts`: View payment histories and reprint existing payment receipts.
8. `View Overdue Credits`: Access and review overdue credit queues and delinquency reports.
9. `Record Customer Notes`: Record customer interaction notes, follow-up calls, and promises to pay.
10. `Request Corrections`: Submit requests for financial transaction corrections or reversals.
11. `Approve Corrections`: Authorize or reject pending financial corrections and reversals *(Restricted to Shop Owner by default)*.
12. `Confirm Collateral Return`: Confirm physical handover and release of pledged collateral items back to the customer.
13. `View Financial Reports`: View daily cash collection reports, till summaries, and shop-level financial metrics.
14. `View Audit Logs`: Access and review the shop's append-only, tamper-resistant activity audit trail.
* **Realizes:** UJ-1 through UJ-5.
* **Consequences (testable):**
  - Attempting any action without the corresponding permission toggle enabled is blocked on the server side with a generic permission denied response that does not reveal sensitive record data.
  - The catalog contains exactly 14 operational permissions; no unauthorized staff actions are permitted outside assigned toggles.
* **Business Rules & Permissions:** Controlled exclusively by Shop Owner.
* **Audit Requirements:** Logs permission modifications with before and after permission states in the append-only, tamper-resistant audit trail.
* **Out of Scope:** Creating arbitrary custom permission types outside the defined catalog in Version 1.

#### FR-7: Restricted Platform Administrator Governance
A Platform Administrator can provision new shop tenants, monitor infrastructure health, and perform service-level administration, but access to tenant customer personal identification data, photographs, and financial ledgers is denied by default. Realizes non-functional platform governance.
* **Realizes:** Non-functional platform governance.
* **Consequences (testable):**
  - Platform admin interfaces and API endpoints deny access to individual shop customer PII and transaction ledgers by default.
  - Any emergency operational access requires explicit, time-bounded authorization and generates an immutable security audit entry recording the operator ID, target shop, timestamp, and mandatory technical justification in the append-only, tamper-resistant audit trail.
* **Business Rules & Permissions:** Enforced on platform-level accounts.
* **Audit Requirements:** Security log generated for all administrative tenant interventions in the append-only, tamper-resistant audit trail.
* **Out of Scope:** End-user customer support ticketing portal in Version 1.

---

### 4.3 Customer Profile & Identity Management

**Description:** Enables staff to onboard customers, capture identity verification details, and reuse customer profiles across multiple credit agreements while preventing duplicate profile creation within the shop. Realizes UJ-1 and UJ-2.

#### FR-8: Reusable Customer Profile Onboarding
Counter Staff with customer registration permission can create a customer profile containing: Full Name, National Identity Card (NIC) number, Contact Telephone Number, Residential Address, and Customer Photograph. Realizes UJ-1.
* **Realizes:** UJ-1.
* **Consequences (testable):**
  - System enforces mandatory entry for Full Name, NIC Number, Phone Number, Address, and Photograph; submission is blocked if any of these fields are missing (unless an explicit owner-approved photograph exception exists as defined in FR-9).
  - Customer profile is persisted and immediately available for attaching one or more credit agreements within the shop.
* **Business Rules & Permissions:** Requires `Register Customers` permission.
* **Audit Requirements:** Logs customer profile creation with timestamp and staff ID in the append-only, tamper-resistant audit trail.
* **Out of Scope:** Automated optical character recognition (OCR) scanning of physical NIC cards in Version 1.

#### FR-9: Customer Photograph Capture & Exception Workflow
Staff can capture the customer’s photograph directly using a connected device camera/webcam, or upload an existing image file (JPEG/PNG), with an interactive pre-save preview. Customer photographs are mandatory by default. Realizes UJ-1.
* **Realizes:** UJ-1.
* **Consequences (testable):**
  - Interactive preview allows retakes or re-upload before record creation.
  - Customer photograph is strictly mandatory by default; profile creation is programmatically blocked if the photograph is missing.
  - **Exception Workflow:** If a photograph cannot be captured due to equipment failure or documented physical constraint, Counter Staff may submit a missing-photo exception request with a mandatory documented reason.
  - Staff cannot self-approve photo exception requests. Only a user with the Shop Owner role can approve or reject the exception.
  - The system must programmatically block final customer profile creation while an exception request is pending approval or if it is rejected.
  - Upon Shop Owner approval, customer profile creation is unblocked and completed, recording an immutable record of the requester ID, approver ID, target customer, mandatory reason, and timestamps in the append-only, tamper-resistant audit trail.
* **Business Rules & Permissions:** Staff requests; Shop Owner approves.
* **Audit Requirements:** Full audit record of exception request, documented reason, and owner approval/rejection logged in the append-only, tamper-resistant audit trail.
* **Out of Scope:** Automated facial recognition or biometric matching.

#### FR-10: Shop-Scoped Duplicate Detection & Shared-Phone Resolution
Before creating a new customer profile, the system performs an automated duplicate check against existing profiles in the current shop using the entered NIC number and phone number. Realizes UJ-1.
* **Realizes:** UJ-1.
* **Consequences (testable):**
  - **Matching NIC:** System programmatically blocks creation and prompts staff to open the existing profile.
  - **Matching Phone with Different NIC:** System displays a duplicate warning banner displaying the existing profile's basic details (masked if unauthorized). Staff must verify whether the applicant is a distinct individual (e.g., family member sharing a phone).
  - To proceed with a shared phone number, staff must click an explicit confirmation (*"Confirm separate individual sharing phone number"*), which logs an audit entry recording the verification in the append-only, tamper-resistant audit trail.
  - Duplicate detection never queries or discloses data from any other shop tenant.
* **Business Rules & Permissions:** Requires `Register Customers` permission.
* **Audit Requirements:** Logs shared-phone confirmations with staff ID and timestamp in the append-only, tamper-resistant audit trail.
* **Out of Scope:** Fuzzy phonetic name matching in Version 1.

#### FR-11: Customer Search & Multi-Credit Navigation
Counter Staff can search customer profiles by NIC number, phone number, or full name strictly within their shop. Realizes UJ-2.
* **Realizes:** UJ-2.
* **Consequences (testable):**
  - Search results display customer name, NIC, phone number, and credit summary.
  - Selecting a customer opens their profile displaying all associated credits categorized by status (Active, Overdue, Settled).
  - When recording a payment or performing credit actions for a customer with multiple credits, the system requires staff to explicitly select the specific target credit before opening the transaction interface.
* **Business Rules & Permissions:** Requires `View Customers` permission. Sensitive fields respect permissions.
* **Audit Requirements:** Search queries logged if required by security audit configuration in the append-only, tamper-resistant audit trail.
* **Out of Scope:** Global cross-shop customer directory search.

#### FR-12: Server-Side Sensitive Customer Data Access Control
Customer National Identity Card numbers, residential addresses, and personal photographs are protected on the server side and accessible only to authenticated users with the *View Customer Sensitive Data* permission enabled. Realizes UJ-1, UJ-2.
* **Realizes:** UJ-1, UJ-2.
* **Consequences (testable):**
  - For unauthorized staff, the server omits full customer photographs and delivers masked values (e.g., `+94 77 **** 123` and `1985****5678`) in API responses, ensuring sensitive data cannot be extracted via network inspection or direct file URLs.
  - Masking is treated as a presentation feature supported by server-side data omission.
* **Business Rules & Permissions:** Enforced on server response layer.
* **Audit Requirements:** Unauthorized attempts to access direct photo URLs return `403 Forbidden` and log a security alert in the append-only, tamper-resistant audit trail.
* **Out of Scope:** Customer-facing privacy consent management portal in Version 1.

---

### 4.4 Collateral Intake & Custody Documentation

**Description:** Governs the registration, appraisal attributes, mandatory photographic capture, and independent physical custody tracking of pledged items held as credit security. Realizes UJ-1 and UJ-3.

#### FR-13: Item Receipt Registration per Credit (Optional)
Counter Staff can register zero or more item receipts under a single credit agreement. Realizes UJ-1.
* **Realizes:** UJ-1.
* **Consequences (testable):**
  - Each attached item receipt receives a unique, system-generated Item Reference Number linked to the parent credit agreement.
  - Attaching item receipts is optional; a credit agreement can be submitted with zero item receipts.
  - When no item receipt is attached, no custody obligation exists and no collateral audit event is generated.
* **Business Rules & Permissions:** Requires `Create Credits` permission.
* **Audit Requirements:** Logs attached item references upon credit creation in the append-only, tamper-resistant audit trail.
* **Out of Scope:** Bundling collateral items across multiple independent credits.

#### FR-14: Collateral Attribute Capture & Calibration
For each item receipt, Counter Staff must record: Item Category (Gold/Jewelry, Electronics, General Valuables), Detailed Description, Condition Grading, Estimated Collateral Value, and Calibrated Weight (where applicable). Realizes UJ-1.
* **Realizes:** UJ-1.
* **Consequences (testable):**
  - For items in the `Gold/Jewelry` category, the Weight field is strictly mandatory, accepts calibrated decimal values (e.g., grams to two decimal places), and is stored with its unit of measure.
  - Estimated Collateral Value is stored as an independent appraisal field and is never conflated with or auto-calculated as the credit principal amount.
* **Business Rules & Permissions:** Requires `Create Credits` permission.
* **Audit Requirements:** Logs item attributes upon creation in the append-only, tamper-resistant audit trail.
* **Out of Scope:** Real-time spot gold price market API integrations in Version 1.

#### FR-15: Mandatory Item Receipt Photographs & Shop Owner Exception Workflow
Counter Staff must capture or upload at least one clear photograph for every item receipt, with pre-save preview. Realizes UJ-1.
* **Realizes:** UJ-1.
* **Consequences (testable):**
  - Item receipt photograph is strictly mandatory by default for every item receipt; credit agreement creation and item receipt intake are programmatically blocked if any attached item receipt lacks an attached photo. This rule applies only to item receipts that are attached and does not require at least one item receipt.
  - **Exception Workflow:** If an item cannot be photographed due to equipment failure or physical constraint, Counter Staff may submit a missing-photo exception request with a mandatory documented reason.
  - Staff cannot self-approve photo exception requests. Only a user with the Shop Owner role can approve or reject the exception.
  - The system must programmatically block final credit agreement creation and item receipt intake while an exception request is pending approval or if it is rejected.
  - Upon Shop Owner approval, item receipt registration is unblocked, recording an immutable record of the requester ID, approver ID, target item reference, mandatory reason, and timestamps in the append-only, tamper-resistant audit trail.
* **Business Rules & Permissions:** Staff requests; Shop Owner approves.
* **Audit Requirements:** Full audit record of exception request, documented reason, and owner approval/rejection logged in the append-only, tamper-resistant audit trail.
* **Out of Scope:** AI-based automated item condition analysis or scratch detection.

#### FR-16: Independent Per-Item Custody Tracking, Settlement & Administrative Closure
The system must track the physical custody status of each pledged item independently from the credit's financial status. Each pledged item maintains its own physical custody state: `In Custody`, `Returned`, or `Exception / Held`. Realizes UJ-3.
* **Realizes:** UJ-3.
* **Consequences (testable):**
  - **Financial Settlement vs. Custody:** A credit reaching a valid outstanding balance of zero transitions its financial status to `Settled`. Settlement alone does not alter item custody states; pledged items remain `In Custody` until physical return is explicitly confirmed.
  - **Physical Item Handover:** Handing back an item requires an explicit confirmation action by authorized staff, recording the return timestamp, handing staff ID, and item reference. Marking an item as `Returned` updates only that specific item's custody status and does not automatically alter other items under the same credit.
  - **Fully Handed Over:** When every pledged item attached to a settled credit has been confirmed as `Returned`, the overall workflow status transitions to `Closed / Completed`.
  - **Exception / Held State:** An item may transition to `Exception / Held` if it cannot be returned due to physical dispute, loss/theft in vault, police seizure, or legal freeze. Transitioning to `Exception / Held` requires Shop Owner authorization with a mandatory documented justification. An item in `Exception / Held` is explicitly not considered physically returned.
  - **Administrative Closure with Collateral Exception:** If a credit is financially settled (or otherwise resolved) but one or more pledged items remain in `Exception / Held`, the credit cannot transition to standard `Closed / Completed`. Instead, the Shop Owner can execute an Administrative Closure with Collateral Exception. This transitions the credit's overall workflow status to `Closed (Collateral Exception)`, requires explicit Shop Owner authorization and documented sign-off in the append-only, tamper-resistant audit trail, and permanently retains the affected items in `Exception / Held` without falsely recording them as `Returned`.
* **Business Rules & Permissions:** Physical handover requires `Confirm Collateral Return` permission; transitioning items to `Exception / Held` and executing Administrative Closure with Collateral Exception require Shop Owner role.
* **Audit Requirements:** All custody status transitions, handover events, and administrative closures are logged with timestamps, actor IDs, item references, and mandatory reasons in the append-only, tamper-resistant audit trail.
* **Out of Scope:** Automated RFID/barcode vault locker integration in Version 1.

---

### 4.5 Zero-Interest Credit Origination & Cash Disbursement

**Description:** Manages the lifecycle of a zero-interest credit from term selection and principal recording to explicit cash disbursement confirmation. Realizes UJ-1 and UJ-5.

#### FR-17: Credit Term Selection & Preliminary Due Date Display
When creating a credit agreement, Counter Staff can select a standard duration preset (30, 60, or 90 calendar days) or specify a custom calendar due date via a date picker. Realizes UJ-1.
* **Realizes:** UJ-1.
* **Consequences (testable):**
  - **Preliminary Due Date Presentation:** While a credit agreement is in `Active / Pending Disbursement`, any displayed or generated due date is explicitly identified as `Preliminary Due Date (Pending Disbursement)`.
  - For preset duration selections (30, 60, or 90 days), the preliminary due date is tentatively calculated as Agreement Creation Date + Preset Days in the shop's local time zone (`Asia/Colombo`).
  - **Custom Due Date Validation:** When selecting a custom date, the system enforces that the selected date must be strictly greater than the credit agreement creation date (`Custom Due Date > Agreement Creation Date`).
  - The calculated preliminary due date and selected term are displayed prominently on the agreement summary prior to submission.
  - The official calendar due date is confirmed and finalized only upon cash disbursement confirmation as defined in FR-19.
* **Business Rules & Permissions:** Requires `Create Credits` permission.
* **Audit Requirements:** Logs agreed term preset or custom date upon agreement creation in the append-only, tamper-resistant audit trail.
* **Out of Scope:** Dynamic business-day calculation excluding regional public holidays in Version 1.

#### FR-18: Zero-Interest Principal Tracking & Creation Idempotency
Staff record the agreed credit Principal Amount. In Version 1, the total repayment obligation equals the principal amount with no automated interest, processing fees, or compounding charges. Realizes UJ-1.
* **Realizes:** UJ-1.
* **Consequences (testable):**
  - Initial Outstanding Principal Balance is set exactly equal to the Principal Amount.
  - **Duplicate Submission Guard:** Credit creation requests require a client-generated idempotency key; rapid double-clicks or network retry submissions produce exactly one credit agreement record.
* **Business Rules & Permissions:** Requires `Create Credits` permission.
* **Audit Requirements:** Logs principal amount and creation timestamp in the append-only, tamper-resistant audit trail.
* **Out of Scope:** Tiered interest rate calculations or administrative documentation fees in Version 1.

#### FR-19: Separation of Credit Agreement Creation and Cash Disbursement Confirmation
The system must decouple credit agreement creation from confirmed cash disbursement, calculating the official repayment period and calendar due date from the confirmed disbursement date. Realizes UJ-1.
* **Realizes:** UJ-1.
* **Consequences (testable):**
  - **Initial State:** Upon creation, the credit is in state: `Financial Status: Active / Pending Disbursement`, `Overall Workflow Status: Active (Pending Disbursement)`.
  - **Payment Block:** Payment processing is strictly blocked on any credit in the `Active / Pending Disbursement` state.
  - **Disbursement Confirmation & Official Due Date Calculation:**
    - Authorized staff must explicitly confirm cash disbursement, recording the disbursing user ID and timestamp, which transitions the credit to `Financial Status: Active / Disbursed`, `Overall Workflow Status: Active`.
    - **Preset Duration Calculation (30, 60, 90 Days):** On disbursement confirmation, the system calculates and permanently saves the Official Calendar Due Date by adding the agreed preset calendar days to the confirmed cash disbursement date in the shop's local time zone:
      $$\text{Official Calendar Due Date} = \text{Disbursement Date (in Shop Local Time)} + N\text{ calendar days}$$
    - **Custom Date Validation at Disbursement:** If a custom fixed due date was chosen during creation, the system validates that:
      $$\text{Custom Due Date} > \text{Disbursement Date (in Shop Local Time)}$$
      If the disbursement was delayed such that the custom due date is on or before the disbursement date, the system programmatically **blocks disbursement confirmation** and requires staff to select a valid future due date before proceeding.
  - **Calendar-Day Calculation Semantics & Test Cases:**
    - Adding $N$ calendar days increments the calendar date (YYYY-MM-DD) by exactly $N$ days regardless of time of day in shop local time (`Asia/Colombo`).
    - *Test Case 1 (30-Day Preset):* Agreement created 2026-10-14 (preliminary due date 2026-11-13). Disbursed 2026-10-15 -> Official Due Date saved as `2026-11-14` (October 15 + 30 days).
    - *Test Case 2 (60-Day Preset across Month End):* Disbursed 2026-10-15 -> Official Due Date saved as `2026-12-14` (16 days in Oct + 30 in Nov + 14 in Dec = 60 days).
    - *Test Case 3 (90-Day Preset):* Disbursed 2026-10-15 -> Official Due Date saved as `2027-01-13` (16 in Oct + 30 in Nov + 31 in Dec + 13 in Jan = 90 days).
    - *Test Case 4 (Custom Date Valid):* Agreement created 2026-10-10 with custom date 2026-11-20. Disbursed 2026-10-12 -> Valid (`2026-11-20 > 2026-10-12`), saved as `2026-11-20`.
    - *Test Case 5 (Custom Date Blocked on Delay):* Agreement created 2026-10-10 with custom date 2026-10-15. Disbursement attempted on 2026-10-15 (same day) or 2026-10-16 (past due) -> Disbursement confirmation is programmatically blocked with a validation error requiring a valid future date.
  - **Cash-Out Reporting:** Daily cash-out reports strictly include only confirmed disbursements, preventing undisbursed principal from inflating cash flow reports.
  - **Cancellation of Undisbursed Agreements:** An agreement in `Pending Disbursement` can be cancelled by authorized staff with a mandatory reason, transitioning to `Financial Status: Cancelled / Undisbursed`, `Overall Workflow Status: Cancelled`. Both creation and cancellation are preserved in the append-only, tamper-resistant audit trail.
  - **No Automatic Cancellation or Expiry:** An agreement awaiting disbursement is **never cancelled automatically**. There is no timeout and no auto-expiry. An abandoned agreement is cancelled **manually by the Shop Owner** with a mandatory reason. To keep abandoned agreements visible without mutating them, the system surfaces a **non-destructive worklist** of agreements still awaiting disbursement; the worklist reports an agreement and never changes its state.
  - **Collateral Custody of a Cancelled Agreement:** The pledged items of a cancelled agreement **remain in the shop's custody** and are **not** automatically released to the customer. Cancelling an agreement changes the agreement's own state; it is not a collateral return, and no item custody transition is performed as part of the cancellation.
* **Business Rules & Permissions:** Disbursement requires `Confirm Credit Disbursement` permission; cancellation requires Shop Owner role.
* **Audit Requirements:** Logs disbursement confirmation and cancellation with timestamps, user IDs, calculated due date, and reasons in the append-only, tamper-resistant audit trail. The disbursement confirmation is recorded under FR-31 category 4; the cancellation of an undisbursed agreement is recorded under FR-31 category 2 with action type `cancel_credit_agreement`.
* **Resolved Decisions:** The former `[OPEN DECISION: TIMEOUT/AUTO-EXPIRY POLICY FOR ABANDONED PENDING-DISBURSEMENT CREDITS]` is **resolved** by the rules above: manual Shop Owner cancellation only, no auto-expiry, non-destructive worklist for abandoned agreements. The age threshold at which an agreement is surfaced on that worklist remains an open operational setting and is not fixed by this requirement.

#### FR-20: Credit Agreement Documentation & Initial Slip Generation
The system generates printable and exportable (PDF) credit documentation, distinguishing between pre-disbursement review drafts and executed disbursement vouchers. Realizes UJ-1.
* **Realizes:** UJ-1.
* **Consequences (testable):**
  - **Executed Credit Agreement & Cash Disbursement Voucher (Post-Disbursement):** Upon confirmed cash disbursement, the system generates the official executed credit ticket containing: Shop Branding Snapshot, Customer Identifier, Credit Reference Number, Origination Date, Confirmed Cash Disbursement Date & Timestamp, Disbursing Staff ID, Official Confirmed Calendar Due Date, Disbursed Principal Amount, Initial Outstanding Balance, Item Receipt Details (with weights and descriptions), zero-interest disclosure, and shop footer notes.
  - **Document Export & Printing:** Official tickets can be printed via connected thermal slip or laser printers, or exported as PDF documents.
  - **Distinction from Pre-Disbursement Draft:**
    - If a pre-disbursement draft agreement slip is printed prior to cash disbursement, it must be visually and textually distinct:
      - Titled and watermarked as `*** DRAFT / PENDING DISBURSEMENT - NOT A CASH RECEIPT ***`.
      - Clearly displays `Preliminary Due Date (Subject to Confirmation on Cash Handover)`.
      - Explicitly states that cash has not yet been disbursed and the agreement is non-binding until disbursement confirmation.
  - `[OPEN DECISION: PRE-DISBURSEMENT DRAFT AGREEMENT PRINTING]`: Defines whether counter staff are permitted to print a physical draft agreement slip prior to cash disbursement confirmation (e.g., for customer physical signature/review before money is counted), or whether all document generation is strictly locked until cash disbursement is confirmed. This will be evaluated during pilot operational testing without pre-judging user preference.
* **Business Rules & Permissions:** Generating executed vouchers requires `Create Credits` or `View and Reprint Receipts` permission; draft printing (if enabled) requires `Create Credits` permission.
* **Audit Requirements:** Logs document generation and print events in the append-only, tamper-resistant audit trail.

---

### 4.6 Payment Processing, Balance Validation & Receipts

**Description:** Governs recording partial payments and full settlements, exact balance recalculation, anti-overpayment validation, duplicate transaction prevention, and receipt generation. Realizes UJ-2 and UJ-3.

#### FR-21: Partial Payment & Full Settlement Recording with Overpayment Protection
Counter Staff with payment recording permissions can record cash payments against an active or overdue credit that has been confirmed as disbursed. Realizes UJ-2.
* **Realizes:** UJ-2.
* **Consequences (testable):**
  - Payment amount must be strictly greater than zero (`Payment > 0.00`).
  - **Overpayment Block:** The system programmatically blocks any payment where `Payment > Current Valid Outstanding Balance`, returning an explicit validation error.
  - When `Payment < Valid Outstanding Balance`, the payment is recorded as a `Partial Payment`, and the balance is reduced by the exact payment amount.
  - When `Payment == Valid Outstanding Balance`, the payment is recorded as a `Full Settlement`, and the credit's financial status immediately updates to `Settled`.
* **Business Rules & Permissions:** Requires `Record Payments` permission.
* **Audit Requirements:** Logs payment transaction with receipt reference, amount, pre/post balance, staff ID, and timestamp in the append-only, tamper-resistant audit trail.
* **Out of Scope:** Payment installment scheduling with mandatory minimum installment thresholds.

#### FR-22: Exact Monetary Decimal Precision, Double-Entry Arithmetic & Controlled Adjustments
All monetary calculations for credit principal, payments, adjustments, and outstanding balances must use fixed-point decimal arithmetic or integer minor units to eliminate floating-point rounding errors. Balance calculations and transaction postings must be executed atomically on the server within ACID database transactions, with strict controls over payment reversals and manual adjustments. Realizes UJ-2, UJ-3, UJ-4.
* **Realizes:** UJ-2, UJ-3, UJ-4.
* **Double-Entry & Algebraic Accounting Rules:**
  - The system enforces the explicit ledger balance formula:
    $$\text{Valid Outstanding Balance} = \text{Principal Amount (Debit)} - \sum\text{Valid Confirmed Payments (Credit)} + \sum\text{Approved Payment Reversals (Debit)} \pm \sum\text{Approved Adjustments}$$
  - **Principal Disbursement (Debit):** Cash disbursed increases the borrower's debt obligation.
  - **Confirmed Customer Payment (Credit):** Valid payment reduces the borrower's debt obligation.
  - **Payment Reversal (Compensating Debit):**
    - Corrects an erroneous confirmed payment (e.g. typographical error or misapplied credit).
    - Adds back the reversed payment amount to the outstanding balance:
      $$\text{Balance}_{\text{new}} = \text{Balance}_{\text{current}} + \text{Reversed Payment Amount}$$
    - Requires Counter Staff request with mandatory documented reason and **explicit Shop Owner approval**.
    - The original payment transaction is permanently preserved without modification or deletion; a linked compensating debit transaction is recorded.
  - **Manual Balance Adjustment (Controlled Debit or Credit):**
    - Handles audited manual balance corrections (e.g., dispute settlement, cent rounding reconciliation, or negotiated concession).
    - An adjustment marked as **Debit** increases the borrower's debt obligation:
      $$\text{Balance}_{\text{new}} = \text{Balance}_{\text{current}} + \text{Adjustment Amount}$$
    - An adjustment marked as **Credit** decreases the borrower's debt obligation:
      $$\text{Balance}_{\text{new}} = \text{Balance}_{\text{current}} - \text{Adjustment Amount}$$
    - **Authorization & Governance:** Manual balance adjustments follow the same two-step control as payment reversals:
      - **Staff-proposed, owner-approved adjustment:** Counter Staff holding `requestCorrections` may *propose* a debit or credit adjustment (e.g., forgiving part of the balance during settlement — negotiated concession, dispute settlement, rounding reconciliation). The proposal is recorded as `pending_approval` with a mandatory business reason, activates the correction-pending lock on the credit (payments blocked on that credit only), and posts only upon **explicit Shop Owner approval** (`approveCorrections`). On approval the system posts an immutable `adjustment_debit` / `adjustment_credit` ledger entry; on rejection the balance is unchanged and the lock lifts. Staff can never approve their own proposal.
      - **Owner-direct adjustment (existing):** A Shop Owner may still execute an adjustment directly without a prior staff request.
      - The balance is never edited in place; every adjustment is posted as a ledger delta entry derived from an explicit input, preserving full transaction history.
    - **Input affordance:** the actor enters the adjustment amount and direction (debit/credit), or the desired new effective balance from which the system derives the delta; the delta is what posts.
    - Historical Integrity: Adjustments are recorded as immutable standalone ledger entries linked to the credit, preserving all prior transaction history.
* **Consequences (testable):**
  - Calculations use integer minor units (e.g., cents) or arbitrary-precision decimals with a consistent scale (2 decimal places for `LKR`) to eliminate floating-point rounding discrepancies.
  - Balance validation and deduction execute within an atomic transaction; database failures roll back completely without partial state commits.
  - **Mandatory Verification Test Scenarios:**
    1. *Partial Payment:* Starting balance 50,000.00 LKR, payment of 20,000.00 LKR posted -> Valid outstanding balance equals exactly 30,000.00 LKR.
    2. *Full Settlement:* Valid balance 30,000.00 LKR, payment of 30,000.00 LKR posted -> Valid outstanding balance equals exactly 0.00 LKR; financial status transitions immediately to `Settled`.
    3. *Approved Payment Reversal:* Valid balance 15,000.00 LKR following an erroneous 35,000.00 LKR payment; upon approved reversal, balance recalculates to exactly 50,000.00 LKR, creating an immutable compensating debit entry while preserving the original record.
    4. *Approved Debit Adjustment:* Valid balance 25,000.00 LKR; owner approves debit adjustment of +250.00 LKR with reason -> Valid balance recalculates to exactly 25,250.00 LKR.
    5. *Approved Credit Adjustment:* Valid balance 25,000.00 LKR; owner approves credit adjustment of -500.00 LKR with reason -> Valid balance recalculates to exactly 24,500.00 LKR.
    6. *Duplicate Submission (Idempotency):* Identical payment payload submitted multiple times with the same idempotency key -> Exactly one transaction is committed; duplicate requests return the original transaction receipt without deducting funds twice.
    7. *Concurrent Payments:* Two simultaneous payment requests of 30,000.00 LKR against a 50,000.00 LKR balance -> Concurrency controls (optimistic locking / row locking) process one request successfully (leaving 20,000.00 LKR) and immediately evaluate the second request against the updated balance, blocking it with an overpayment error.
     8. *Staff-Proposed Credit Adjustment with Owner Approval:* Valid balance 25,000.00 LKR; staff proposes a credit adjustment of -5,000.00 LKR (partial forgiveness) with mandatory reason -> proposal recorded `pending_approval`, correction-pending lock activates, payments blocked on that credit; Shop Owner approves -> balance recalculates to exactly 20,000.00 LKR, immutable `adjustment_credit` entry posted, lock lifts, audit event logged. Rejection path: balance unchanged at 25,000.00 LKR, lock lifts, rejection reason mandatory.
* **Business Rules & Permissions:** Enforced system-wide across all financial services. Reversals require `Request Corrections` (staff) and `Approve Corrections` (owner); staff-proposed adjustments require `Request Corrections` (staff proposal) and `Approve Corrections` (owner approval, or Shop Owner direct execution); manual adjustments executed directly by a Shop Owner require the Shop Owner role.
* **Audit Requirements:** Any arithmetic discrepancy between transaction sums and stored balance triggers a high-severity financial integrity alert in the append-only, tamper-resistant audit trail. All reversals and adjustments log actor IDs, approver ID, target credit, pre/post balance, timestamps, and mandatory business justifications.
* **Out of Scope:** Multi-currency floating FX ledgers in Version 1.

#### FR-23: Payment Concurrency, Idempotency & Correction-Pending Lock
The system must prevent duplicate financial postings arising from concurrent counter requests, rapid double-clicks, or client network retries, and must protect balances during pending corrections. Realizes UJ-2, UJ-4.
* **Realizes:** UJ-2, UJ-4.
* **Consequences (testable):**
  - Each payment submission requires a client-generated idempotency token. If a request is received with an already-processed token, the server returns the existing confirmed transaction and receipt without re-posting.
  - Optimistic concurrency locking blocks simultaneous payments on the same credit from overpaying the balance.
  - **Correction-Pending Lock:** While a financial correction request on a specific credit is pending approval, new payment submissions are temporarily blocked strictly on that affected credit. The same lock applies while a staff-proposed balance adjustment (FR-22) is pending Shop Owner approval. Other credits in the shop remain fully operational in both cases.
* **Business Rules & Permissions:** System concurrency guard.
* **Audit Requirements:** Duplicate submission attempts and blocked concurrent requests are logged in the append-only, tamper-resistant audit trail.
* **Out of Scope:** Distributed multi-region two-phase commit consensus protocols.

#### FR-24: Immutable Receipt Snapshot Model, Reprint Auditing & Historical Integrity
Every confirmed payment immediately generates an immutable receipt record capturing an immutable branding and transaction snapshot. Realizes UJ-2.
* **Realizes:** UJ-2.
* **Consequences (testable):**
  - **Snapshot Architecture:** At the exact moment of payment confirmation, the system captures an immutable snapshot of:
    - Shop branding attributes: Shop Name, Business Address, Contact Telephone, Email, Tax/Registration Number, Shop Logo, and custom Receipt Header and Footer notes.
    - Transaction attributes: Unique Receipt Number, Payment Timestamp, Payment Type (Partial Payment vs. Full Settlement), Amount Paid, Pre-Payment Balance, Resulting Balance, Customer Identifier, Credit Reference Number, and Cashier/Staff ID.
  - **Reprint Integrity:** Reprinting an existing receipt renders the document strictly from the historical snapshot. It preserves the original receipt number, payment amount, and original transaction timestamp. Reprinting never creates a new financial transaction or alters ledger balances.
  - **Reprint Watermark & Visual Identity:** Any reprinted receipt displays a prominent visual indicator (e.g., `*** REPRINT ***` in the receipt header) alongside the reprint generation timestamp.
  - **Reprint Audit Logging:** Each reprint action generates a distinct audit log entry recording the original receipt number, reprint timestamp, and the identity of the staff member who initiated the reprint.
  - Later updates to the shop's profile, logo, or receipt footer notes apply strictly to future receipts and never alter historical receipt snapshots.
* **Business Rules & Permissions:** Requires `View and Reprint Receipts` permission (or Shop Owner role).
* **Audit Requirements:** Distinct audit log entry for every receipt reprint event in the append-only, tamper-resistant audit trail.
* **Out of Scope:** Customer-facing online receipt download portal in Version 1.


---

### 4.7 Overdue Credit Governance & Shop Owner Decisions

**Description:** Manages the identification of delinquent accounts past their calendar due date, structured owner reviews, due date extensions, and resolution documentation without automated collateral disposal. Realizes UJ-5.

#### FR-25: Automated Overdue State Evaluation & Calendar Boundary
The system must automatically evaluate credit due dates against the shop's local time zone and flag delinquent credits as Overdue. Realizes UJ-5.
* **Realizes:** UJ-5.
* **Consequences (testable):**
  - **Overdue Transition Rule:** A credit automatically transitions its financial status to `Overdue` and its overall workflow status to `Overdue` at 00:00:00 on the calendar day after the official due date (`Disbursed / Agreed Due Date + 1 calendar day`) in the shop's configured local time zone (`Asia/Colombo`), strictly provided that `Valid Outstanding Balance > 0.00`.
  - **Settled Credits Excluded:** Fully settled credits (`Valid Outstanding Balance == 0.00`) are strictly excluded from overdue evaluation and must never transition to `Overdue`.
  - **Visual Badges & Filterable Queues:** Overdue credits are visually distinguished on counter screens, customer profiles, and owner dashboards with a prominent `Overdue` badge and days overdue counter.
* **Business Rules & Permissions:** Automated system evaluation; viewing overdue accounts requires `View Overdue Credits` permission.
* **Audit Requirements:** State transition logged with credit reference and timestamp in the append-only, tamper-resistant audit trail.
* **Out of Scope:** Automated punitive late fee calculation or compounding interest penalties in Version 1.

#### FR-26: Shop Owner Due Date Extension Workflow
A Shop Owner can grant and record an extension to the official calendar due date for an active or overdue credit. Realizes UJ-5.
* **Realizes:** UJ-5.
* **Consequences (testable):**
  - **Owner Exclusivity:** Due date extension is restricted exclusively to the Shop Owner role; Counter Staff cannot execute extensions.
  - **Mandatory Justification:** The system programmatically blocks due date extension submission unless a non-empty business justification/reason is provided.
  - **Future Date Validation:** The newly requested due date must be strictly greater than the current calendar date in the shop's local time zone (`New Due Date > Current Date`).
  - **Status Reset:** If the credit was previously in `Overdue` status, confirming the extension immediately resets the financial and overall status to `Active`, recalculating overdue evaluation against the new due date.
  - **Historical Chain Preservation:** The original calendar due date and all intermediate due dates, extension reasons, requesting/approving user IDs, and timestamps are permanently preserved in an immutable chronological extension history chain.
* **Business Rules & Permissions:** Restricted to Shop Owner role.
* **Audit Requirements:** Logs original due date, revised due date, reason, owner ID, and timestamp in the append-only, tamper-resistant audit trail.
* **Out of Scope:** Configurable extension processing fees or mandatory interest refinancing in Version 1.

#### FR-27: Overdue Customer Follow-Up & Promise to Pay Logging
Authorized staff can document communication attempts, borrower responses, and formal promises to pay on delinquent or active accounts. Realizes UJ-5.
* **Realizes:** UJ-5.
* **Consequences (testable):**
  - Staff can record customer interaction entries containing: Contact Timestamp, Communication Channel (e.g., Phone Call, In-Person Counter Visit, Physical Notice), Staff Identifier, Detailed Interaction Notes, and optional Promised Payment Date.
  - Logged follow-ups appear in reverse chronological order on the credit detail view.
  - If a Promised Payment Date is entered, the system displays this commitment date on the Overdue Credit Review queue as a priority reminder for staff.
* **Business Rules & Permissions:** Requires `Record Customer Notes` permission.
* **Audit Requirements:** Logs follow-up entry creation with staff ID, credit reference, and timestamp in the append-only, tamper-resistant audit trail.
* **Out of Scope:** Automated outgoing SMS or WhatsApp follow-up messaging in Version 1.

#### FR-28: Structured Owner Resolution & Collateral Disposition Recording
When an overdue credit cannot be resolved through repayment or extensions, the Shop Owner can formally document a case review decision and resolution status in the system. Realizes UJ-5.
* **Realizes:** UJ-5.
* **Consequences (testable):**
  - **Structured Action States:** The Shop Owner can transition an overdue credit into structured governance states:
    - `Under Review`: Flags the account for ongoing evaluation, investigation, or legal notice.
    - `Owner Settled / Written Off`: Documents an authorized commercial resolution (e.g. debt write-off or negotiated closure) requiring a mandatory justification and ledger adjustment.
    - `Collateral Retained / Legal Dispute`: Documents cases where pledged items are retained or referred to legal/police processes under shop policy and regional law.
  - **No Automated Liquidation:** The platform strictly avoids automated forfeiture, automated collateral transfer to inventory, or public auction mechanisms. All disposition decisions remain manual, owner-authorized, and recorded for historical documentation.
  - **Mandatory Audit Signature:** Any resolution decision requires explicit Shop Owner confirmation and a mandatory documented business rationale.
* **Business Rules & Permissions:** Restricted to Shop Owner role.
* **Audit Requirements:** Logs resolution status transition, decision notes, owner ID, affected collateral item references, and timestamp in the append-only, tamper-resistant audit trail.
* **Out of Scope:** Public auction bidding portal or automated liquidator inventory integration in Version 1.

---

### 4.8 Reporting, Analytics & Data Export

**Description:** Equips shop owners and authorized staff with operational visibility over daily cash flows, active credit liabilities, vault inventory, and historical auditing, with secure data export.

#### FR-29: Shop Owner Financial & Operational Dashboards
The system provides real-time aggregated reporting on shop operations, cash flows, and collateral custody. Realizes non-functional governance.
* **Realizes:** Non-functional governance and shop administration.
* **Consequences (testable):**
  - **Daily Cash Reconciliation Summary:** Displays total confirmed principal disbursed (cash out), total confirmed repayments collected (cash in), and net counter cash movement for any selected calendar date. Undisbursed credits are strictly excluded from cash disbursement figures.
  - **Portfolio Overview:** Real-time metrics for:
    - Total Active Credits Count and Aggregate Outstanding Principal.
    - Total Overdue Credits Count and Aggregate Overdue Principal.
    - Total Settled Credits Count.
    - Total Collateral Items currently `In Custody` in the shop vault.
  - **Pending Correction Queue:** Prominently surfaces any pending payment correction requests requiring Shop Owner evaluation.
  - **Tenant Boundary:** Dashboard aggregates strictly calculate within the active shop tenant boundary and never include cross-tenant figures.
* **Business Rules & Permissions:** Requires `View Financial Reports` permission or Shop Owner role.
* **Audit Requirements:** Dashboard view access logged if required by security audit configuration.
* **Out of Scope:** Multi-shop consolidated enterprise reporting or AI cash-flow forecasting in Version 1.

#### FR-30: Audited Tabular Data Export (PDF & CSV)
Authorized users can export standardized operational reports in PDF (for printing/sharing) and CSV (for spreadsheet analysis). Realizes non-functional reporting.
* **Realizes:** Non-functional reporting.
* **Consequences (testable):**
  - **Supported Reports:** Daily Cash Collection Ledger, Customer Credit Portfolio Summary, Overdue Delinquency Report, and Collateral Vault Inventory.
  - **Export Formats:**
    - **PDF:** Pre-formatted with shop branding snapshot, generation timestamp, requesting staff ID, filter parameters, and page numbering.
    - **CSV:** Machine-readable raw columnar data with exact decimal numbers, standard ISO 8601 timestamps, and UTF-8 encoding.
  - **Privacy Enforcement:** Sensitive customer identity attributes (full NIC and residential addresses) are masked in export outputs unless the requesting user possesses `View Sensitive Customer Data` permission.
* **Business Rules & Permissions:** Requires `View Financial Reports` permission.
* **Audit Requirements:** Every data export event generates an audit entry recording report type, date filter parameters, format (PDF/CSV), and requesting user ID in the append-only, tamper-resistant audit trail.
* **Out of Scope:** Automated scheduled email report deliveries in Version 1.

---

### 4.9 Non-Functional Requirements & Security Foundations

**Description:** Enforces architectural invariants for auditability, disaster recovery, data integrity, and multi-tenant security verification.

#### FR-31: Append-Only Audit Trail Specification
The system must maintain an append-only, tamper-resistant audit trail recording all defined critical events. Realizes non-functional audit integrity.
* **Realizes:** Non-functional audit integrity.
* **Consequences (testable):**
  - **Mandatory Event Catalog:** The system programmatically generates an immutable audit entry for every instance of:
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
  - **Record Attributes:** Every audit entry records: Event ID, Tenant ID, Event Category, Action Type, Actor User ID, Target Entity Reference, Pre-State Snapshot, Post-State Snapshot, Business Reason (where mandatory), Client IP / User-Agent, and Server Timestamp.
  - **Immutability:** Audit records are write-once; no user (including Shop Owner and Platform Administrator) possesses permissions to edit, overwrite, or delete audit records.
  - **Canonical Event Catalogue Authority:** The numbered catalogue above is the **single authoritative event-category contract** for the whole system. Any implementation-side category list — including the `AuditService` taxonomy — **must align to these ordinals and labels** and must never define an independent numbering. The mapping from an event category to its meaning is maintained in exactly **one canonical source**, so that an ordinal can never carry two meanings. Adding a fifteenth category requires an explicit PRD amendment together with a server migration that widens the `event_category` range check; the range check is never widened silently.
  - **Action Types Within a Category:** `action_type` distinguishes individual events that share one category. Category 2 (`Credit agreement origination and cancellation`) is the parent of the action types `credit_agreement_origination`, `cancel_credit_agreement` and `credit_term_reagreed`. The cancellation of an undisbursed agreement is recorded as **category 2 with action type `cancel_credit_agreement`**; it is **not** recorded under category 4 (`Confirmed cash disbursement`), because no cash was disbursed.
  - **Offline Capture and Authoritative Append:** An event that occurs while the shop is offline is first recorded **locally** in an append-only local queue and is appended to the server-side `audit_events` table upon synchronization. A local record is **not** by itself an authoritative audit entry — the authoritative entry is the row in `audit_events`. The local store's durability and synchronization behaviour is specified by the architecture, not by this requirement.
* **Business Rules & Permissions:** System-wide automated capture; viewing audit logs requires `View Audit Logs` permission (or Shop Owner role).
* **Audit Requirements:** Self-auditing append-only log.

#### FR-32: Data Backup, Recovery Objectives & Durability
The system architecture must implement automated backups and formal recovery procedures. Realizes non-functional operational continuity.
* **Realizes:** Non-functional operational continuity.
* **Consequences (testable):**
  - **Recovery Point Objective (RPO):** Maximum acceptable data loss window of $\le 15$ minutes in the event of catastrophic server failure.
  - **Recovery Time Objective (RTO):** System restoration to fully operational status within $\le 4$ hours.
  - **Restoration Drill Verification:** Disaster recovery restore procedures must be successfully executed and verified against automated consistency test suites prior to production go-live.
* **Business Rules & Permissions:** Platform infrastructure governance.
* **Audit Requirements:** Backup execution and restoration drills logged in platform administration logs.

#### FR-33: Tenant Isolation & Role-Based Access Automated Verification Gates
Multi-tenant isolation and role-based permissions must be verified through automated regression test suites prior to release. Realizes non-functional security.
* **Realizes:** Non-functional security.
* **Consequences (testable):**
  - **Automated Tenant Boundary Test Suite:** Automated test suite attempts cross-tenant entity lookups, payment postings, and customer searches across isolated tenants, verifying 100% rejection with `403 Forbidden` / `404 Not Found`.
  - **RBAC Matrix Verification:** Automated test suite verifies all 14 permission toggles, ensuring that unprivileged accounts are blocked from unauthorized operations (e.g. approving corrections, viewing financial summaries, confirming item handovers).
* **Business Rules & Permissions:** Release gate criteria.
* **Audit Requirements:** Automated test run reports preserved with build artifacts.

---

## 5. Requirements Traceability & Completeness Matrix

| Feature ID | Feature Name | User Journey | Target Role | Verification Test Gate |
| :--- | :--- | :--- | :--- | :--- |
| **FR-1** | Shop Profile Configuration | UJ-1, UJ-2 | Shop Owner | Snapshot isolation test |
| **FR-2** | Shop Timezone & Calendar Semantics | UJ-1, UJ-5 | Shop Owner | Next-day 00:00:00 overdue boundary |
| **FR-3** | Configurable Currency Display | UJ-1, UJ-2 | Shop Owner | Ledger currency immutability check |
| **FR-4** | Server-Side Tenant Isolation | UJ-1..UJ-5 | All Users | Automated cross-tenant boundary attack suite |
| **FR-5** | Staff Account Administration | UJ-1, UJ-4 | Shop Owner | Session revocation verification |
| **FR-6** | Granular Permission Assignment | UJ-1..UJ-5 | Shop Owner | 14-toggle RBAC denial suite |
| **FR-7** | Restricted Platform Admin Access | Non-functional | Platform Admin | Default-denied customer PII test |
| **FR-8** | Reusable Customer Onboarding | UJ-1 | Counter Staff | Required KYC validation test |
| **FR-9** | Customer Photo Capture & Exception | UJ-1 | Counter Staff / Owner | Owner-only exception override test |
| **FR-10** | Duplicate Detection & Phone Sharing | UJ-1 | Counter Staff | Shared-phone verification log test |
| **FR-11** | Customer Search & Credit Navigation | UJ-2 | Counter Staff | Multi-credit selection prompt test |
| **FR-12** | Sensitive Customer PII Protection | UJ-1, UJ-2 | Counter Staff | Server-side masking test |
| **FR-13** | Item Receipt Registration (Optional) | UJ-1 | Counter Staff | Zero-item submission and item binding test |
| **FR-14** | Collateral Attributes & Weight | UJ-1 | Counter Staff | Gold weight decimal validation test |
| **FR-15** | Mandatory Collateral Photographs | UJ-1 | Counter Staff / Owner | Owner-only photo exception test |
| **FR-16** | Independent Collateral Custody | UJ-3 | Counter Staff / Owner | Decoupled return & admin closure test |
| **FR-17** | Credit Term & Preliminary Due Date | UJ-1 | Counter Staff | Preset & custom date validation test |
| **FR-18** | Zero-Interest Principal Tracking | UJ-1 | Counter Staff | Idempotency & zero-interest test |
| **FR-19** | Cash Disbursement Separation | UJ-1 | Counter Staff | Disbursement date calculation test (Cases 1-5) |
| **FR-20** | Credit Agreement Documentation | UJ-1 | Counter Staff | Voucher vs. Draft watermark test |
| **FR-21** | Payments & Overpayment Protection | UJ-2 | Counter Staff | Anti-overpayment validation test |
| **FR-22** | Decimal Precision & Ledgers | UJ-2, UJ-3, UJ-4 | System / Owner | 7-scenario ledger arithmetic test suite |
| **FR-23** | Concurrency, Idempotency & Lock | UJ-2, UJ-4 | System | Optimistic concurrency & correction lock test |
| **FR-24** | Immutable Receipt Snapshots | UJ-2 | Counter Staff | Historical snapshot & reprint watermark test |
| **FR-25** | Automated Overdue State Evaluation | UJ-5 | System | Local calendar day boundary test |
| **FR-26** | Shop Owner Due Date Extensions | UJ-5 | Shop Owner | Chain preservation & status reset test |
| **FR-27** | Customer Follow-Up & Promise to Pay | UJ-5 | Counter Staff | Notes & promise date sorting test |
| **FR-28** | Structured Owner Resolution | UJ-5 | Shop Owner | Non-automated manual disposition test |
| **FR-29** | Owner Operational Dashboards | Non-functional | Shop Owner | Cash-in/out aggregation test |
| **FR-30** | Tabular Data Export (PDF/CSV) | Non-functional | Counter Staff / Owner | Export format & PII masking test |
| **FR-31** | Append-Only Audit Trail | Non-functional | All Roles | Immutability & 14-event completeness test |
| **FR-32** | Data Backup & Disaster Recovery | Non-functional | Platform Admin | RPO <= 15m, RTO <= 4h drill |
| **FR-33** | Tenant Isolation Verification Gates | Non-functional | QA / Security | Zero cross-tenant leakage verification |

