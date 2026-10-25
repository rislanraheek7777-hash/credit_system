# Story 4.4 — P-1 through P-10 Hardware and Printing Questionnaire

**Project:** Credit Management System
**Story:** 4.4 — Loan Agreement Documentation, Draft Agreements & Cash Disbursement Vouchers
**Audience:** Product Owner / Operations
**Related approval package:** `_bmad-output/implementation-artifacts/story-4-4-approval-package.md`
**Related specification:** `_bmad-output/implementation-artifacts/spec-4-4-loan-agreement-documentation-draft-agreements-cash-disbursement-vouchers.md`
**Questionnaire date:** 2026-10-22
**Status:** **UNANSWERED — 0 of 10 responses recorded**
**Decision authority:** This questionnaire records requirements and evidence. It does not approve D4.4-04 or D4.4-07 and does not authorise a dependency, adapter, or implementation change.

---

## 1. Purpose and instructions

This is the separate response instrument for **P-1 through P-10**. It extracts the hardware, paper, connection, language, logo, cash-drawer, platform, status-feedback, and fallback questions from the Story 4.4 approval package and specification.

No answer, respondent identity, signature, or date is recorded in this document. Every response field is blank. Do not infer an answer from the proposed option or from any other document.

Instructions:

1. Answer each question with the confirmed operational requirement, not a preference that has not been approved.
2. Attach or cite the evidence used (printer datasheet, purchase order, test print, site photograph, vendor confirmation, or operations decision).
3. If a question is not applicable, write `N/A` and state why. Do not leave an applicable question blank.
4. If the answer is not yet known, write `UNKNOWN — evidence required` and name the action needed. An unknown answer is not a decision.
5. Record the respondent's name, role, signature, and date at the end of this document. A response without an identified respondent is not valid evidence.
6. Return the completed questionnaire to the Product Owner and Architect. It gates D4.4-04/D4.4-07 and any thermal dependency or adapter selection.

**Minimum answer sets:**

- **Hard minimum:** P-1, P-2, P-3, P-4.
- **Adapter contract:** P-5, P-6, P-9, P-10.
- **Target scope:** P-7, P-8.

Until the applicable answers and supporting evidence are recorded, thermal dependency selection, thermal adapter creation, and thermal hardware acceptance remain **blocked**.

---

## 2. Respondent identity

| Field | Value |
|---|---|
| **Respondent name** | ______________________ |
| **Role** | ______________________ |
| **Product Owner / Operations authority** | ______________________ |
| **Department / shop** | ______________________ |
| **Contact details** | ______________________ |
| **Signature** | ______________________ |
| **Date** | ____________ |
| **Status** | **Pending — no respondent recorded** |

---

## 3. Response instrument — P-1 through P-10

| ID | Question | Why the answer gates Story 4.4 | Response | Evidence / attachment | Answered by (name / role) | Date |
|---|---|---|---|---|---|---|
| **P-1** | Exact printer make/model(s) and command set (ESC/POS vs TSPL/CPCL/ZPL)? | Determines whether ESC/POS is the correct protocol at all. A label printer would require a different path and possibly a vendor SDK. | ______________________________ | ______________________ | ______________________ | __________ |
| **P-2** | Paper width: 58 mm, 80 mm, or both? | Determines columns, font sizes, line wrapping, and whether `X.XXX g` weights and long collateral descriptions fit. | ______________________________ | ______________________ | ______________________ | __________ |
| **P-3** | Connection method: Bluetooth Classic, BLE, USB, Wi-Fi/TCP, or vendor dock? | Determines the transport package, Android permissions, pairing behaviour, and adapter contract. | ______________________________ | ______________________ | ______________________ | __________ |
| **P-4** | Must the ticket print Sinhala/Tamil, or English only? | ESC/POS code pages may lack required glyphs. The answer determines whether raster rendering or a different font strategy is required. | ______________________________ | ______________________ | ______________________ | __________ |
| **P-5** | Is a shop logo required on thermal output? | v1 proposes text-only branding. A “yes” requires an immutable asset copy, raster support, buffer/print-time assessment, and a separate asset-fidelity decision. | ______________________________ | ______________________ | ______________________ | __________ |
| **P-6** | Is a cash-drawer kick required? | Some printer SDKs expose a drawer kick; others do not. The answer affects the adapter contract and hardware acceptance. | ______________________________ | ______________________ | ______________________ | __________ |
| **P-7** | Must Web print thermal receipts? | The current Web target cannot reach raw ESC/POS. A “yes” requires a separately approved local bridge/agent and widens the attack surface. | ______________________________ | ______________________ | ______________________ | __________ |
| **P-8** | Is Windows desktop a supported counter target? | No `windows/` target exists today. Adding one is a platform-scope decision, not an implementation detail. | ______________________________ | ______________________ | ______________________ | __________ |
| **P-9** | Is print confirmation/status feedback required? | Distinguishes status-capable transports from fire-and-forget printing and affects failure handling and operator feedback. | ______________________________ | ______________________ | ______________________ | __________ |
| **P-10** | What is the fallback when the printer is unavailable? | Must not block cash handover on a printer fault. The proposed fallback is PDF preview/share; the final requirement must be recorded. | ______________________________ | ______________________ | ______________________ | __________ |

**Recorded responses:** 0 of 10. **Status:** **UNANSWERED**.

---

## 4. Gate mapping

| Gate | Questions | What the answers determine | Status |
|---|---|---|---|
| **Protocol / command set** | P-1 | Whether ESC/POS is the correct protocol; whether a label-printer or vendor-SDK path is required | **Blocked — unanswered** |
| **Layout width** | P-2 | Columns, fonts, wrapping, weight/value legibility | **Blocked — unanswered** |
| **Transport** | P-3 | Package, permissions, adapter contract | **Blocked — unanswered** |
| **Glyphs / language** | P-4 | Font strategy; raster fallback | **Blocked — unanswered** |
| **Logo** | P-5 | Whether v1 remains text-only; later asset requirements | **Blocked — unanswered** |
| **Cash drawer** | P-6 | Adapter contract; hardware acceptance | **Blocked — unanswered** |
| **Web thermal** | P-7 | Whether a local bridge is in scope | **Blocked — unanswered** |
| **Windows target** | P-8 | Platform scope | **Blocked — unanswered** |
| **Status feedback** | P-9 | Transport capability; operator feedback | **Blocked — unanswered** |
| **Failure fallback** | P-10 | Cash-handover continuity; PDF fallback | **Blocked — unanswered** |

---

## 5. Approval linkage

This questionnaire is not an approval. The following remain Pending and are unaffected by any answer recorded here:

| Item | Required decision owner | Status |
|---|---|---|
| D4.4-04 — PDF generation and dependency strategy | Product Owner + Architect | **Pending** |
| D4.4-07 — Thermal printing strategy | Product Owner + Architect | **Pending** |
| Story 4.4 specification approval | Product Owner + Architect | **Pending** |
| Story 4.3 contract freeze / closure | Architect | **Pending** |
| PDF/printing dependency review | Architect | **Pending** |

A completed questionnaire supplies evidence for D4.4-07 and the thermal portion of D4.4-04. It does not approve either decision, authorise a package installation, or permit implementation. The Architect must still record the dependency review and both stakeholders must record their decisions.

---

## 6. Completion record

| Field | Value |
|---|---|
| **Responses recorded** | **0 of 10** |
| **Respondent identity recorded** | **No** |
| **Signature recorded** | **No** |
| **Date recorded** | **No** |
| **Questionnaire status** | **UNANSWERED — AWAITING PRODUCT OWNER / OPERATIONS** |
| **Evidence attachments** | **None** |
| **Handed to Product Owner** | **No** |
| **Handed to Architect** | **No** |
| **Resulting decision** | **None — this questionnaire does not decide D4.4-04 or D4.4-07** |

**Next action:** Product Owner / Operations completes P-1 through P-10, attaches evidence, signs and dates the response, and returns it for inclusion in the Story 4.4 approval package. No thermal dependency or adapter is selected before then.

---

*End of questionnaire. No answer, approval, signature, source, test, dependency, migration, database schema, `sprint-status.yaml`, or Git state was created or modified in preparing this instrument.*
