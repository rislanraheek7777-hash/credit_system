# Story 4.4 — Credit Agreement Documentation, Draft Agreements & Cash Disbursement Vouchers

> **Specification status: APPROVED.**
> **Project status: READY FOR IMPLEMENTATION.**
>
> Decisions D4.4-01 through D4.4-07 formally approved by Product Owner and Lead Architect.
> Story 4.4 implementation authorized.

**Epic:** Epic 4 — Credit Agreement Lifecycle & Disbursement  
**Story ID:** 4.4  
**Story status:** Approved specification — implementation authorized  
**Sprint status (observed):** `in-progress` (`sprint-status.yaml:73`)  
**Dependencies:** Story 4.3 (Disbursement engine), Story 1.6 (Shop branding)  
**Additional integration boundaries:** Story 1.7 (permission administration, not a hard dependency), Story 7.2 (export masking, not a dependency; no compliance claim)  
**Decision owners:** Product Owner and Architect (both approved)  
**Prepared:** 2026-10-22  
**Implementation authority:** Full (PO + Architect signoff 2026-10-25)

---

## 1. Purpose, status, and authority

### 1.1 What this document is

This is the proposed implementation specification for Story 4.4. It translates the
authoritative Story 4.4 acceptance criteria and the related PRD requirements into
proposed acceptance criteria, a document/snapshot domain, a proposed schema v15,
renderer requirements, masking and audit rules, a 20-test acceptance matrix, and
dependency gates.

It does **not**:

- implement Story 4.4;
- edit source, tests, migrations, dependencies, generated code, or database schemas;
- edit `sprint-status.yaml`;
- change Git state or discard uncommitted changes;
- provision PostgreSQL or run PostgreSQL-dependent tests;
- resolve or implement Story 4.3 deferred decisions **D-1 through D-7** or **J-1**;
- select a printer, install a PDF/printing package, or create an adapter;
- mark any pending decision approved.

### 1.2 Authority labels used in this document

| Label | Meaning |
|---|---|
| **[A] Authoritative baseline** | The requirement text already established by the epic, PRD, UX design requirements, or adopted architecture. "Authoritative" means these are the source requirements to implement against once implementation is authorised. It does **not** mean Story 4.4 is approved for implementation. |
| **[P] Proposed** | A design, acceptance criterion, schema, layout, policy, mapping, or test proposed by this specification and awaiting approval. |
| **Pending** | No required stakeholder signature or answer has been recorded. |

The authoritative baseline is limited to the sources in §2. Every other rule in
this document — including AC-01 through AC-10, AT-01 through AT-20, all schema
objects, the masking policy, the audit mapping, the permission matrix, the
offline rules, and the document layouts — is **[P]**.

### 1.3 Approval gates

Implementation may not start until **all** of the following are recorded:

1. **D4.4-01 through D4.4-07** each approved by both the Product Owner and the
   Architect, with signature and date (conditions, if any, written beside the
   signature).
2. This specification approved as the Story 4.4 implementation contract.
3. Story 4.3 either closed (`done`) or its disbursement contract formally frozen
   by the Architect — specifically required before official-snapshot integration
   (§15.3 and Appendix B).
4. For thermal output only: D4.4-04 and D4.4-07 approved **and** P-1 through P-10
   answered (Appendix A).
5. For PDF/printing dependencies: D4.4-04 approved and the dependency review
   completed. No package is installed by this document.
6. For schema v15 and snapshot-domain implementation: gates 1 and 2 recorded.

No reduced approval gate is authorised by this document. Any reduced gate requires
an explicit written Architect ruling recorded with the decisions; this
specification does not propose one.

Until then, the project remains **NOT READY — AWAITING APPROVAL**.

---

## 2. Sources and requirement baseline

### 2.1 Authoritative sources [A]

| Source | Location | What it fixes |
|---|---|---|
| Story 4.4 acceptance criteria | `_bmad-output/planning-artifacts/epics.md:1024-1048` | Draft watermark and disclosure, official ticket fields, thermal + PDF, document audit logging |
| Story 4.4 dependency list | `epics.md:1047` | Story 4.3 and Story 1.6 are the named epic dependencies |
| FR-20 | `_bmad-output/planning-artifacts/prds/prd-credit_system-2026-10-13/prd.md:429-442` | Official voucher contents, draft distinction, permissions, open draft-printing decision, document audit |
| FR-24 | `prd.md:510-522` | Immutable receipt snapshot and reprint integrity pattern. **FR-24 is a payment-receipt requirement; this story uses the same integrity pattern but does not claim FR-24 coverage for credit documents.** |
| FR-31 | `prd.md:622-647` | 14-category audit catalogue, category 2 action types, record attributes, offline local queue and authoritative server append |
| FR-12 | `prd.md:310-318` | Server-side sensitive-customer-data omission. **This story does not implement or claim FR-12 compliance.** |
| UX-DR-6 | `epics.md:88` | Prominent draft and reprint watermarks |
| Architecture spine | `_bmad-output/planning-artifacts/architecture/architecture-credit_system-2026-10-14/ARCHITECTURE-SPINE.md` | AD-1 offline/ACID and no silent overwrites; AD-2 Money; AD-5 no binary documents in relational tables; AD-6 RBAC and audit |
| Current sprint state | `_bmad-output/implementation-artifacts/sprint-status.yaml:73` | Story 4.4 is `backlog` |

### 2.2 Exact required draft strings [A]

Two strings are fixed by the epic and must be constants, not editable template
options. The PRD records the component wording for the second:

1. Draft title/watermark:
   `*** DRAFT / PENDING DISBURSEMENT - NOT A CASH RECEIPT ***`
   (`epics.md:1034`; `prd.md:437`)
2. Preliminary due-date disclosure:
   `Preliminary Due Date (Subject to Confirmation on Cash Handover) - Non-binding until disbursement confirmation.`
   (`epics.md:1035`; component wording at `prd.md:438-439`)

The draft must also state explicitly that cash has not been disbursed
(`prd.md:439`). The proposed exact sentence is in §8.1.2.

### 2.3 Open policy that this specification does not decide [A]

The PRD records an explicit open decision on whether pre-disbursement physical
draft printing is permitted at all:

> `[OPEN DECISION: PRE-DISBURSEMENT DRAFT AGREEMENT PRINTING]`
> — `prd.md:440`

This specification recommends Option 1A in D4.4-01, but **the policy remains
Pending**. If the Product Owner chooses a different option, the draft sections of
this specification must be revised before implementation.

---

## 3. Scope, exclusions, and deferred work

### 3.1 Proposed in-scope work [P]

- A pure-Dart document domain model and immutable snapshot contract.
- Append-only local `credit_documents` and `credit_document_events` tables and
  triggers, schema v15 (additive migration from v14).
- Draft issuance, official-ticket generation, PDF export, thermal rendering
  requirements, reprint, supersede, and void behaviour.
- A local document masking policy and snapshot-level masking enforcement.
- Document lifecycle audit action types under PRD FR-31 categories 2 and 14,
  queued through the existing local sync path.
- Permission and state gates at the service/DAO boundary, not only in widgets.
- UI surfaces for draft preview/print, official ticket preview/print/export,
  reprint, and failure messaging.
- Acceptance tests AT-01 through AT-20, including migration and no-PostgreSQL
  guards.

### 3.2 Explicit exclusions

| Item | Reason |
|---|---|
| Implementation in this task | Planning only; no approval exists. |
| Editing Story 1.6 shop-profile configuration | Story 1.6 is `backlog`; its screen is view-only. Story 4.4 reads the existing `shops` row and snapshots it. |
| Story 1.7 permission administration UI | The 14-permission catalogue and role templates already exist in code; runtime permission-editing UI is not required for 4.4. If runtime permission administration is required, 1.7 becomes a prerequisite. |
| Story 7.2 export masking and FR-12 server-side omission | Story 7.2 is `backlog`; there is no export service or server omission layer. 4.4 defines a local document policy only. |
| Receipt snapshots, payment reprints, or FR-24 receipt implementation | Different story and different artifact. 4.4 reuses the integrity pattern only. |
| Cloud document storage or a server-side document table | Not required by Story 4.4 or FR-20. Only audit events reconcile to the server in this proposal. |
| Cross-device reprint or server-side document archive | The snapshot is local. If the device is lost, the authoritative audit can prove an event occurred but cannot reproduce its content. Multi-device reprint/archival needs a separate approved story. |
| Immutable logo asset copies | v1 prints shop branding text, not a logo. A logo would require a content-addressed immutable copy outside the relational tables (AD-5) plus a fidelity and retention decision; P-5 remains open. |
| Printer model/transport selection | Blocked by P-1 through P-10 and D4.4-07. |
| Installing `pdf`, `printing`, or any thermal package | D4.4-04 is Pending; no dependency is installed. |
| Windows, iOS, macOS, or Linux product support | Only `android/` and `web/` targets exist. Adding a target is a separate platform decision. |
| Backfilling official documents for credits disbursed before Story 4.4 | Current rows do not contain the historical branding/customer/collateral values required for an authentic snapshot. A backfill policy is deferred; no automatic backfill is proposed. |
| Digital signatures, QR/barcode, automatic printing on origination, or PDF archival storage | Not required, or contrary to AD-5 for binary storage. |
| Sinhala/Tamil thermal fidelity | Depends on P-4 and the hardware spike; no glyph support is promised. |
| Story 4.3 decisions D-1 through D-7 and J-1 | Out of scope and must not be implemented or reinterpreted. |

### 3.3 Deferred Story 4.3 work

The approval package instructs that Story 4.3 deferred decisions **D-1 through
D-7** and **J-1** remain untouched (`story-4-4-approval-package.md:25,576,714`).
The inspected Story 4.3 specification does **not** enumerate those identifiers,
so this document does not invent their content. The following Story 4.3 matters
also remain unresolved and are not decided here:

- **Q-1 / D10** — the cancelled-agreement balance invariant remains open
  (`spec-4-3:5,45`).
- **F1** — the `AuditService` taxonomy conflict is ruled by R1 but not
  implemented (`spec-4-3:37,218`).
- **AC-4** — the specification says "approved design, not yet implemented," while
  the DAO contains a cancellation implementation; no dedicated test or
  presentation action was found (Appendix B).
- **U-5/v14** — the specification says the DB-level Tier 1 constraints/migration
  remain open, while the working tree already reports schema v14 and contains the
  v14 migration (Appendix B).
- **Disbursement contract freeze** — no formal freeze record was found; Story 4.3
  remains in `review` (`sprint-status.yaml:72`).

---

## 4. Decision register — D4.4-01 through D4.4-07

### 4.0 Approval rule

Every decision below is **Pending**. The recommendation is not an approval. Each
decision requires **both** a Product Owner signature and an Architect signature,
dated. Approval of one decision does not approve any other. Conditions attached
to an approval must be written next to that signature.

### 4.1 D4.4-01 — Draft agreement policy

| Field | Value |
|---|---|
| **Decision** | Whether pre-disbursement draft agreement slips may be generated and printed, and under what controls. |
| **Status** | **Pending** |
| **Proposed option** | **Option 1A** — drafts are permitted only after a persisted credit agreement exists and only while `workflow_status = pending_disbursement`; never from unsaved form state; no new draft after disbursement or cancellation. |
| **Required controls** | Persisted-entity gate; state gate; exact watermark and disclosure constants; distinct `DRAFT-` reference and no voucher number; explicit "cash has not been disbursed" sentence; `createCredits` permission enforced at service/DAO; audit every preview/export/print/reprint; immutable snapshot; reprint watermark; document masking; no automatic print; explicit confirmation prompt. |
| **Alternatives** | 1B — drafts locked until disbursement (official tickets only); 1C — drafts only after a Manager "review requested" flag; 1D — on-screen preview only, no paper draft. |
| **Consequences** | 1A supports pre-cash customer review but creates misidentification and shadow-disbursement risk; the controls reduce but do not eliminate it. 1B removes most of that risk but removes the physical review artefact. The chosen option must be reflected in AT-01 through AT-03. |
| **Evidence** | `epics.md:1032-1035`; `prd.md:435-441`; `credit.dart:277-281`; `credit_dao.dart:133-359`; `app_permission.dart:16`. |
| **Product Owner approval** | Pending — Name: ________________ Signature: ________________ Date: ____________ |
| **Architect approval** | Pending — Name: ________________ Signature: ________________ Date: ____________ |

### 4.2 D4.4-02 — Official credit ticket layout and identifiers

| Field | Value |
|---|---|
| **Decision** | The official ticket's field set, field order, formatting, reference scheme, and signature block. |
| **Status** | **Pending** |
| **Proposed option** | Ten-block, thermal-first layout in §8.2. Include the 11 epic fields plus **Initial Outstanding Balance** from FR-20. Use a derived short credit reference **and** the full credit UUID; a stored document number; masked NIC and no customer address; shop-local dates; exact zero-interest disclosure; text-only shop branding (no logo in v1); optional two-line signature block. |
| **Identifier proposal** | `document_number` stored on `credit_documents`: draft `DRAFT-<document short id>`; official `VCH-<shop short code>-<YYYYMMDD>-<document short id>`. Proposed short ids are the first 8 uppercase hex characters of the UUID for the document and customer, and the first 10 for the credit; the shop short code is the first 6 uppercase hex characters of the shop UUID. A replacement version gets a new document number and records the superseded number in its snapshot. Credit reference is derived `LN-<credit short id>` plus the full UUID. No new column is added to `credits`. |
| **Alternatives** | PRD-only field set without Initial Outstanding Balance; persisted sequential `credit_reference` on `credits`; full NIC on paper; A4-only layout; no signature block. |
| **Consequences** | A short reference is usable but is not a legal key; the full UUID remains authoritative. A persisted sequential reference would require a `credits` schema change and an offline numbering design. Full NIC increases paper-loss exposure. Signatures improve proof but create a signed-artifact obligation. A logo is excluded from v1 because no immutable asset copy exists; adding it later requires a separate asset-fidelity decision. All layout choices must render from the snapshot, never live rows. |
| **Evidence** | `epics.md:1037-1040`; `prd.md:433`; `credits_table.dart:18-113`; `credit.dart:127-188`; `collateral_item.dart:121-201,289-294`; `money.dart:305-340`; `shop_profile.dart:27-46`. |
| **Product Owner approval** | Pending — Name: ________________ Signature: ________________ Date: ____________ |
| **Architect approval** | Pending — Name: ________________ Signature: ________________ Date: ____________ |

**Open sub-choice:** the package recommends including Initial Outstanding Balance
and optional signatures; the epic AC omits the balance and does not mention
signatures. Both are proposed additions and require explicit approval. There is no
existing customer "short reference" column; any short customer reference must be
derived for display and the full customer UUID retained. For a null/blank shop
address, phone, or registration number, the proposed fallback is `Not recorded`
plus a warning; the alternative is to require complete branding before official
generation. D4.4-02 must choose; neither option may invent values.

### 4.3 D4.4-03 — Immutable snapshots, schema v15, and reprints

| Field | Value |
|---|---|
| **Decision** | Whether documents are rendered live or from immutable snapshots, and how versions/reprints are represented. |
| **Status** | **Pending** |
| **Proposed option** | **Option 3C** — append-only `credit_documents` and `credit_document_events`; snapshot at the triggering event; official snapshot inside the disbursement transaction; SHA-256 over canonical JSON; replacement versions instead of edits; no mutable status/counter columns. |
| **Required properties** | Snapshot only, never live joins, for reproduction; resolved display strings plus non-sensitive raw numeric values; masked sensitive values only; insert-only DAO; SQLite `BEFORE UPDATE`/`BEFORE DELETE` triggers; unique `(credit_id, document_type, version)`; render-time hash verification; derived superseded/void state from later rows/events. |
| **Alternatives** | 3A live rendering (rejected: rewrites history); 3B snapshot at first print (fails if branding/balance changed before first output); 3D store PDF bytes in the database (rejected by AD-5); single table with mutable `status`/`reprint_count`. |
| **Consequences** | Strongest historical integrity; adds a migration, two tables, triggers, canonicalisation, and a document write inside disbursement. A snapshot failure rolls back the disbursement. Local triggers are not tamper evidence against a compromised device; server audit remains authoritative. |
| **Evidence** | `prd.md:433,510-522`; AD-1 rules 3 and 5 (`ARCHITECTURE-SPINE.md:54-64`); AD-5 rule 2 (`ARCHITECTURE-SPINE.md:226-243`); no document tables in `app_database.dart:38-50`. |
| **Product Owner approval** | Pending — Name: ________________ Signature: ________________ Date: ____________ |
| **Architect approval** | Pending — Name: ________________ Signature: ________________ Date: ____________ |

### 4.4 D4.4-04 — PDF generation and dependency strategy

| Field | Value |
|---|---|
| **Decision** | Which PDF/printing dependency strategy to adopt and in what phases. |
| **Status** | **Pending** |
| **Proposed option** | **Phase A:** add `pdf` (PDF creation) and `printing` (preview/share/OS print) only after approval. **Phase B:** add exactly one thermal transport after the hardware spike, behind an adapter interface. No package is installed now. |
| **Alternatives** | `pdf` only; `esc_pos_utils_plus` plus a custom transport for everything; vendor SDK; commercial PDF suite; multiple overlapping thermal packages. |
| **Consequences** | Fewer dependencies reduce supply-chain risk. `printing` adds platform code and an OS print path that can retain spooled documents. A thermal package later adds permissions and attack surface. Dart SDK is `^3.13.4`; the repository targets Android and Web only. |
| **Evidence** | `pubspec.yaml:21-22,30-49` (no PDF/printing dependency); `android/` and `web/` exist; no `windows/`, `ios/`, `macos/`, or `linux/` project directories; `epics.md:1040`; `prd.md:434`. |
| **Product Owner approval** | Pending — Name: ________________ Signature: ________________ Date: ____________ |
| **Architect approval** | Pending — Name: ________________ Signature: ________________ Date: ____________ |

### 4.5 D4.4-05 — Document PII masking policy

| Field | Value |
|---|---|
| **Decision** | Whether credit documents print full or masked customer identity data, and whether that depends on the generating user's role. |
| **Status** | **Pending** |
| **Proposed option** | **`always_masked_v1`** for all credit documents: customer address never printed; NIC and phone (if a layout includes phone) always masked; customer photo never printed; full name and opaque customer reference retained. Role-dependent unmasking remains an **on-screen** capability only. The policy identifier is stored in the snapshot and audit payload. |
| **Alternatives** | `role_dependent_v1` documents (full NIC/phone for `viewSensitiveCustomerData`); always-full NIC; mask only on screen; wait for Story 7.2. |
| **Consequences** | Always-masked reduces paper-loss exposure and gives consistent reprints; it may reduce physical identity verification for privileged staff. Role-dependent paper creates two variants for one credit and a reprint/unmask hazard. Waiting for 7.2 blocks 4.4 and still does not define document-level policy. The existing helpers return short NICs and short phone values unchanged, so documents need their own fail-closed masker; this is a required implementation detail under either option. |
| **Evidence** | `customer_masking.dart:13-50`; `customer_profile_screen.dart:263-269`; `customer_search_screen.dart:158`; `app_permission.dart:13`; `sprint-status.yaml:58,93`; `prd.md:310-318`. |
| **Product Owner approval** | Pending — Name: ________________ Signature: ________________ Date: ____________ |
| **Architect approval** | Pending — Name: ________________ Signature: ________________ Date: ____________ |

### 4.6 D4.4-06 — Audit category mapping

| Field | Value |
|---|---|
| **Decision** | How document lifecycle events fit the FR-31 14-category catalogue without creating a competing taxonomy. |
| **Status** | **Pending** |
| **Proposed option** | Treat document lifecycle actions as **Category 2** (`Credit agreement origination and cancellation`) with the eight document `action_type`s in §10.1. Use **Category 14** for access-denied and integrity failures. Do not reuse Category 13 (receipt reprints). Do not add a 15th category. |
| **Alternatives** | Add a PRD category 15 with a server migration; use Category 4 for all document events; use Category 13 for document reprints; audit every printer retry. |
| **Consequences** | Category 2 reuse avoids a server migration and a catalogue fork but stretches the category label; PRD `prd.md:644` currently names only `credit_agreement_origination`, `cancel_credit_agreement`, and `credit_term_reagreed`, so adding eight document action types requires an explicit Product Owner/Architect ruling **and** confirmation that the server action-type allow-list accepts them. Category 14 preserves the security signal. PII-free payloads limit breach blast radius. Local `sync_queue` is mutable and is not authoritative audit evidence. |
| **Evidence** | `prd.md:442,622-647`; `epics.md:1042-1044`; `audit_service.dart:35-49`; `sync_queue_table.dart:37-45`; `credit_dao.dart:28-64`; `spec-4-3:37,218`. |
| **Product Owner approval** | Pending — Name: ________________ Signature: ________________ Date: ____________ |
| **Architect approval** | Pending — Name: ________________ Signature: ________________ Date: ____________ |

### 4.7 D4.4-07 — Thermal printing strategy

| Field | Value |
|---|---|
| **Decision** | Which platforms and thermal transport strategy Story 4.4 promises. |
| **Status** | **Pending** |
| **Proposed option** | Android-first ESC/POS through one adapter interface; Web is PDF/browser-print only; no raw thermal promise on Web; Windows/iOS/macOS only if formally added as targets. Hardware spike against P-1 through P-10 before selecting a transport. |
| **Alternatives** | PDF-only v1; vendor SDK per printer; Web local bridge; defer all thermal to a later story. |
| **Consequences** | Native thermal avoids cloud dependency and keeps PII local, but adds Bluetooth/USB permissions and pairing risk. Raster rendering can support glyphs but sends an image of the document to the printer. OS print spoolers may retain documents. A Web bridge would widen the attack surface and is not recommended. |
| **Evidence** | `android/`, `web/` only; no `windows/`/`ios/`/`macos/`/`linux/`; `ARCHITECTURE-SPINE.md:43`; `epics.md:1040`; `prd.md:434`; P-1 through P-10 in Appendix A. |
| **Product Owner approval** | Pending — Name: ________________ Signature: ________________ Date: ____________ |
| **Architect approval** | Pending — Name: ________________ Signature: ________________ Date: ____________ |

### 4.8 Decision summary — all Pending

| ID | Decision | Proposed option | Status | Product Owner | Architect |
|---|---|---|---|---|---|
| D4.4-01 | Draft agreement policy | 1A — after persisted origination, while pending, full controls | **Pending** | ______________ | ______________ |
| D4.4-02 | Official ticket layout | Ten blocks; all epic fields + initial balance; masked NIC; optional signatures | **Pending** | ______________ | ______________ |
| D4.4-03 | Snapshots/schema/reprints | 3C — append-only snapshots + events, hash, versioned replacement | **Pending** | ______________ | ______________ |
| D4.4-04 | PDF dependency strategy | Phase A `pdf` + `printing`; Phase B one thermal transport after spike | **Pending** | ______________ | ______________ |
| D4.4-05 | Document masking | `always_masked_v1`; role-dependent on-screen only | **Pending** | ______________ | ______________ |
| D4.4-06 | Audit mapping | Category 2 document action types; Category 14 denials/integrity | **Pending** | ______________ | ______________ |
| D4.4-07 | Thermal strategy | Android-first ESC/POS adapter; Web PDF-only; P-1…P-10 gate | **Pending** | ______________ | ______________ |

---

## 5. Proposed document domain model and versioning

All items in this section are **[P]** and not implemented.

### 5.1 Proposed domain types

| Type | Responsibility |
|---|---|
| `CreditDocumentType` | `draftAgreement`, `officialTicket`. |
| `CreditDocument` | Immutable domain view of one snapshot row (identity, type, version, document number, hash, policy, generation metadata, supersession link). |
| `CreditDocumentSnapshot` | Canonical, fully resolved display document: branding, customer identifier, credit/reference, dates, money, collateral, disclosures, layout/schema version. |
| `DocumentMaskingPolicy` | Policy identifier and resolved masking flags; `always_masked_v1` recommended. |
| `CreditDocumentEvent` | Immutable lifecycle event (`generate`, `export_pdf`, `print`, `reprint`, `supersede`, `void`). |
| `CreditDocumentReference` | Pure functions for the derived credit reference and stored document number. |
| `CreditDocumentRenderer` | Pure-Dart port that returns rendered bytes for a snapshot and a reprint overlay. Implementations live in the data layer. |
| `ThermalTransport` | Proposed narrow port for one printer transport. **No adapter or transport is created by this document.** |

Suggested placements (proposed, not created):

- `lib/features/customers/domain/models/credit_document.dart`
- `lib/features/customers/domain/models/credit_document_snapshot.dart`
- `lib/features/customers/domain/models/document_masking_policy.dart`
- `lib/features/customers/domain/services/credit_document_service.dart`
- `lib/features/customers/domain/services/credit_document_numbering.dart`
- `lib/core/data/local/tables/credit_documents_table.dart`
- `lib/core/data/local/tables/credit_document_events_table.dart`
- `lib/features/customers/data/daos/credit_document_dao.dart`
- `lib/features/customers/data/documents/credit_document_pdf_renderer.dart` (after D4.4-04)
- `lib/features/customers/data/documents/credit_document_thermal_renderer.dart` (after D4.4-07)
- `lib/features/customers/presentation/credit_document_preview_screen.dart`

### 5.2 Snapshot contract

A snapshot is built **only** at document creation and then never re-reads live
rows. The proposed canonical payload contains:

- `snapshot_schema_version` and `layout_version`;
- document identity: type, version, document number, generated timestamp, actor;
- replacement trace, when applicable: superseded document UUID, superseded
  document number, and mandatory reason;
- shop branding: name, business address, contact phone, registration/tax number,
  footer notes; **no logo in v1** unless a separate immutable asset-copy strategy
  is approved (see §8.2.1 and P-5). A null/blank optional branding field is
  recorded as the literal `Not recorded` and is never fabricated; D4.4-02 may
  instead require complete branding before official generation;
- customer identifier: full name, opaque customer UUID, derived short customer
  reference, **masked NIC only**, masking policy;
- credit reference: derived short credit reference and full credit UUID;
- dates: origination, confirmed disbursement, official confirmed due date,
  agreed term, resolved shop time-zone identifier (and whether the fallback zone
  was used); shop-local display strings and UTC ISO values;
- money: principal cents and initial outstanding balance cents, each with a
  `Money.format()` display string; currency;
- collateral: each item's reference, description, category, condition, weight in
  milligrams and `X.XXX g` string, estimated value cents and display string;
- exact zero-interest disclosure text;
- draft-only exact watermark/disclosure constants and review signature label;
- optional approved signature labels.

### 5.3 Canonical JSON and hash rules

1. JSON object keys sorted lexicographically at every level.
2. UTF-8 encoding; no insignificant whitespace.
3. Arrays ordered deterministically: collateral by `itemReferenceId`, then item
   UUID.
4. Timestamps stored as UTC ISO-8601 with `Z`; shop-local display strings are
   separate fields.
5. Money is integer minor units; weight is integer milligrams; no `double`.
6. Optional values are explicit JSON `null`; do not rely on omitted keys.
7. `snapshot_schema_version` is part of the hashed payload.
8. `snapshot_sha256` is lowercase hex SHA-256 over the canonical UTF-8 bytes.
9. Reprint overlays (`*** REPRINT ***`, reprint time, sequence, staff ID) are
   added at render time and are **not** part of the base snapshot hash.
10. Before every render, recompute and compare the hash. On mismatch, refuse to
    render and record a Category 14 `document_integrity_failure` event.

### 5.4 Sensitive-data rule in the snapshot

The snapshot must **not** contain the raw NIC, residential address, customer
photo, or photo URI/hash. It contains only the already-masked display values
required by the layout selected under D4.4-02. The full values remain in the
operational `customers` table and stay subject to on-screen permissions. This
prevents the immutable document store from becoming a second, less-protected PII
store.

If D4.4-05 selects a role-dependent document policy that would print a full NIC,
this specification and schema must be revised and re-reviewed before
implementation. The proposed v1 snapshot/store does not provide a field or an
approval path for raw NIC on a document.

### 5.5 Document numbering and references

| Value | Proposed rule | Storage |
|---|---|---|
| Draft number | `DRAFT-<document short id>` | Stored in `credit_documents.document_number` |
| Official document number | `VCH-<shop short code>-<YYYYMMDD>-<document short id>` | Stored in `credit_documents.document_number` |
| Document short id | First 8 uppercase hex characters of the document UUID | Derived |
| Credit reference | `LN-<credit short id>` (first 10 uppercase hex of the credit UUID) plus full credit UUID in small print | Derived; no new `credits` column |
| Customer identifier | Full name + opaque customer UUID + `CUST-<first 8 uppercase hex>` + masked NIC | Snapshot fields; no new customer column |

Dates used in document numbers are shop-local dates in the shop's configured
time zone. For official v1, `YYYYMMDD` is the confirmed disbursement date. For a
replacement, it is the replacement generation date; the superseded number is
preserved in the snapshot. Document numbers are unique per shop. A collision must
fail the transaction or be retried with a fresh document UUID; an existing number
is never overwritten.

### 5.6 Versioning and derived state

- Version is scoped to `(credit_id, document_type)`.
- **Draft v1** is created on the first explicit draft issuance after persisted
  origination. A later draft version is created only by an explicit "regenerate
  draft" action after a snapshot-relevant change (for example, a re-agreed
  term); it becomes `version + 1`, receives its own document number, links
  `supersedes_document_id`, and records a reason (for example,
  `agreed_term_changed` or `regenerated_by_user`). A plain preview, print, or
  reprint reuses the current draft and does not create a version.
- **Official v1** is created once inside the disbursement confirmation
  transaction. A replacement is `version + 1` with its own document number, a
  mandatory reason, and a supersession link.
- A replacement **never reuses the superseded document number**. The replacement
  snapshot records the superseded document's number and UUID for traceability.
- There is **no mutable `status` column**. `isSuperseded`, `isVoided`,
  `isCurrent`, and `reprintCount` are derived:
  - `isVoided` — a `void` event exists for the document.
  - `isSuperseded` — a later version of the same `(credit_id, document_type)`
    exists, or, for a draft, an official ticket now exists for the credit.
  - A draft whose credit has been cancelled is not current and renders
    `*** CANCELLED — DO NOT USE ***` (a superseded draft renders
    `*** SUPERSEDED — DO NOT USE ***`).
  - `isCurrent` — highest version for the type and neither superseded nor
    voided.
  - `reprintCount` — count of `reprint` events for the document.
- Once an official ticket exists, every draft for that credit renders with
  `*** SUPERSEDED — DO NOT USE ***`; no draft row is mutated.
- Voiding or superseding a document never changes the credit's financial state,
  cash-disbursement record, balances, or collateral custody.

### 5.7 Proposed service operations and gates

The service/DAO must enforce these at the operation boundary (widget gating is
convenience only):

| Operation | State gate | Permission (proposed) | Transaction |
|---|---|---|---|
| Issue draft | Persisted `pending_disbursement` credit only | `createCredits` | Own transaction: snapshot + `generate` event + audit queue |
| Generate official | `disbursed` transition only, inside `confirmCreditDisbursement` | Caller already passed `confirmCreditDisbursement` | Same transaction as credit update |
| Preview/export PDF | Existing document; hash valid | `createCredits` or `viewAndReprintReceipts` for official; `createCredits` for draft | Event + audit queue before output |
| Print thermal | Existing document; hash valid; supported platform/transport | Same as export | Event + audit queue before handoff |
| Reprint | Existing document; hash valid | Draft: `createCredits`; official: `viewAndReprintReceipts` | Event + audit queue; no new version |
| Supersede | Existing current document; Shop Owner | Shop Owner role; offline locked (proposed) | Replacement insert + `generate` event for the new document + `supersede` event for the old document + audit queue |
| Void | Existing document; Shop Owner | Shop Owner role; offline locked (proposed) | `void` event + audit queue; no row mutation |

All operations are scoped by `shop_id = actor.shopId`. Cross-tenant access is
refused and audited as a Category 14 security event.

---

## 6. Proposed Drift/SQLite schema v15 and migration

All items in this section are **[P]**. No schema has been changed.

### 6.1 Schema version

- Current working tree: `schemaVersion => 14` (`app_database.dart:72`).
- Proposed: `schemaVersion => 15`.
- Migration is **additive**: no existing table is rebuilt.
- The current schema doc comment still says "Schema Version: 13"
  (`app_database.dart:29`); it must be corrected to 15 as part of implementation.

### 6.2 Proposed `credit_documents` table

| Column | SQLite type | Constraints / notes |
|---|---|---|
| `id` | TEXT | PK, UUIDv4 |
| `shop_id` | TEXT | NOT NULL, FK `shops(id)` ON DELETE RESTRICT |
| `credit_id` | TEXT | NOT NULL, FK `credits(id)` ON DELETE RESTRICT |
| `document_type` | TEXT | NOT NULL, CHECK in (`draft_agreement`, `official_ticket`) |
| `document_number` | TEXT | NOT NULL |
| `version` | INTEGER | NOT NULL, CHECK `version > 0` |
| `snapshot_json` | TEXT | NOT NULL, canonical JSON |
| `snapshot_sha256` | TEXT | NOT NULL, 64 lowercase hex characters |
| `masking_policy` | TEXT | NOT NULL; proposed `always_masked_v1` (revision required if D4.4-05 chooses otherwise) |
| `snapshot_schema_version` | INTEGER | NOT NULL, snapshot schema version |
| `layout_version` | INTEGER | NOT NULL, layout version |
| `generated_at` | DATETIME | NOT NULL, UTC |
| `generated_by_user_id` | TEXT | NOT NULL, FK `app_users(id)` ON DELETE RESTRICT |
| `generation_channel` | TEXT | NOT NULL, proposed `automatic` / `preview` / `pdf` / `thermal` / `system_print` |
| `supersedes_document_id` | TEXT | NULL, FK `credit_documents(id)` ON DELETE RESTRICT |
| `correction_reason` | TEXT | NULL; mandatory when version > 1 |

Constraints:

- Unique `(shop_id, document_number)`.
- Unique `(credit_id, document_type, version)`.
- `CHECK (length(snapshot_sha256) = 64 AND snapshot_sha256 NOT GLOB '*[^0-9a-f]*')`.
- `CHECK (version = 1 OR (supersedes_document_id IS NOT NULL AND correction_reason IS NOT NULL AND length(trim(correction_reason)) > 0))`.
- `CHECK (version > 1 OR (supersedes_document_id IS NULL AND correction_reason IS NULL))`.
- The service must verify that `supersedes_document_id` belongs to the same
  `shop_id`, `credit_id`, and `document_type`; SQLite cannot express that as a
  simple CHECK.
- The service must verify that the target `credit_id` belongs to the same `shop_id`
  before insert; the table carries `shop_id` for tenant-scoped queries, but SQLite
  cannot express a composite FK without rebuilding `credits`.
- No `status`, `reprint_count`, or other mutable state column.

Indexes (proposed): `(shop_id, credit_id)`, `(shop_id, document_type, generated_at)`,
and the two unique constraints above.

### 6.3 Proposed `credit_document_events` table

| Column | SQLite type | Constraints / notes |
|---|---|---|
| `id` | TEXT | PK, UUIDv4 |
| `shop_id` | TEXT | NOT NULL, FK `shops(id)` ON DELETE RESTRICT |
| `document_id` | TEXT | NOT NULL, FK `credit_documents(id)` ON DELETE RESTRICT |
| `action_type` | TEXT | NOT NULL, CHECK in (`generate`, `export_pdf`, `print`, `reprint`, `supersede`, `void`) |
| `actor_user_id` | TEXT | NOT NULL, FK `app_users(id)` ON DELETE RESTRICT |
| `channel` | TEXT | NOT NULL; proposed `none`, `preview`, `pdf`, `thermal`, `system_print` |
| `occurred_at` | DATETIME | NOT NULL, UTC |
| `masking_policy` | TEXT | NOT NULL, policy actually applied |
| `reason` | TEXT | NULL; mandatory for `supersede` and `void` |
| `reprint_sequence` | INTEGER | NULL; mandatory for `reprint`, `CHECK > 0` |

Constraints:

- `CHECK ((action_type = 'reprint' AND reprint_sequence IS NOT NULL AND reprint_sequence > 0) OR (action_type <> 'reprint' AND reprint_sequence IS NULL))`.
- `CHECK ((action_type = 'supersede' AND reason IS NOT NULL AND length(trim(reason)) > 0) OR (action_type <> 'supersede'))`.
- `CHECK ((action_type = 'void' AND reason IS NOT NULL AND length(trim(reason)) > 0) OR (action_type <> 'void'))`.
- The service must verify that `shop_id` matches the referenced document's
  `shop_id`; SQLite cannot express that as a simple CHECK here.

Indexes (proposed): `document_id`, `(shop_id, occurred_at)`, plus a partial unique
index on `(document_id, reprint_sequence)` where `reprint_sequence IS NOT NULL` so
two reprint events cannot claim the same sequence.

`reprint_sequence` is an append-only observation, not a mutable counter. The
document's reprint count may be derived by counting `reprint` events; the
sequence preserves what the operator saw on that reprint.

### 6.4 Append-only enforcement

Proposed triggers, installed for both fresh installs and upgrades:

```sql
CREATE TRIGGER IF NOT EXISTS trg_credit_documents_no_update
BEFORE UPDATE ON credit_documents
BEGIN
  SELECT RAISE(ABORT, 'credit_documents is append-only');
END;

CREATE TRIGGER IF NOT EXISTS trg_credit_documents_no_delete
BEFORE DELETE ON credit_documents
BEGIN
  SELECT RAISE(ABORT, 'credit_documents is append-only');
END;

CREATE TRIGGER IF NOT EXISTS trg_credit_document_events_no_update
BEFORE UPDATE ON credit_document_events
BEGIN
  SELECT RAISE(ABORT, 'credit_document_events is append-only');
END;

CREATE TRIGGER IF NOT EXISTS trg_credit_document_events_no_delete
BEFORE DELETE ON credit_document_events
BEGIN
  SELECT RAISE(ABORT, 'credit_document_events is append-only');
END;
```

`onCreate` creates the tables/indexes with `m.createAll()`/`m.createIndex()`,
then explicitly installs these triggers. `onUpgrade` for `from < 15` creates the
tables/indexes and installs the same triggers. `IF NOT EXISTS` makes a second
launch idempotent.

**Limit:** local SQLite triggers stop application-level UPDATE/DELETE, not a
compromised device with direct file access. The authoritative tamper evidence is
the server-side immutable `audit_events` store (AD-6 rule 6), not the local
document tables.

### 6.5 Migration design

1. Bump `schemaVersion` from 14 to 15.
2. In `onUpgrade`, `if (from < 15)`: create `credit_documents`, create
   `credit_document_events`, create indexes, install triggers.
3. Do not rebuild `credits`, `shops`, `customers`, `collateral_items`, or
   `sync_queue`. The migration is additive.
4. Enable/keep `PRAGMA foreign_keys = ON`; verify `PRAGMA foreign_key_check`
   after migration.
5. Preserve all existing rows. There is no data seed and no automatic document
   backfill for existing disbursed credits.
6. Fresh install and v14→v15 upgrade must produce the same logical schema.
7. No PostgreSQL schema migration is proposed. Existing server `audit_events`
   categories 2 and 14 already exist; no category 15 is added.

### 6.6 Required migration tests

- Populated v14 database upgrades to v15 with all existing credits, shops,
  customers, collateral, sync-queue rows, and user rows intact.
- New tables, indexes, and triggers exist after upgrade and after fresh install.
- `UPDATE` and `DELETE` on both new tables abort with the trigger message.
- A second launch/migration run is idempotent.
- `PRAGMA foreign_key_check` is clean.
- The suite does not require PostgreSQL provisioning.

---

## 7. Snapshot timing, transaction boundaries, and rollback

### 7.1 Proposed timing

| Document/action | When the snapshot is created | Transaction boundary |
|---|---|---|
| Draft | On first explicit draft issuance after persisted origination; only while `pending_disbursement` | Own local transaction: state check, snapshot insert, `generate` event, audit-queue insert |
| Official ticket | Inside `confirmCreditDisbursement`, immediately after the conditional credit update succeeds | Same local transaction as the credit update, idempotency guard, document row, `generate` event, and audit-queue row |
| Draft regenerated after a term change | Explicit action; new draft version with its own number, supersession link, and reason | Own local transaction |
| Replacement | Explicit correction with Shop Owner approval | Own local transaction: new version + `generate` event for the replacement + `supersede` event for the original + audit queue |
| Void | Explicit Shop Owner action | Own local transaction: `void` event + audit queue; no row mutation |
| PDF/thermal/reprint output | No new snapshot | Short transaction for event + audit queue; rendering is local and outside the transaction |

### 7.2 Official snapshot integration rule

The official snapshot write is **inside** the disbursement transaction. Serialize
the snapshot from local rows and insert the document before the transaction
commits. No printer, PDF library, network, or OS print call may run inside that
transaction.

The intended transaction order is:

1. Verify actor/shop/state/permission (existing 4.3 boundary).
2. Insert the idempotency guard row.
3. Conditionally update the credit to `disbursed`, setting `disbursed_at`,
   `disbursed_by_user_id`, and the official due date.
4. Insert the official `credit_documents` row (version 1).
5. Insert the `generate` `credit_document_events` row.
6. Insert the Category 2 audit-queue row with `generate_credit_official_ticket`.
7. Commit atomically.
8. Only after commit, offer preview/print/export actions.

A snapshot/document failure at steps 4–6 rolls back steps 2–3. A disbursement must
never commit without its official document record, and an official document must
never exist without the disbursement it documents.

### 7.3 Draft transaction rule

A draft has no financial mutation, but it still has a stable identity and audit
trail. In one transaction:

1. Re-check the actor, shop, permission, and `pending_disbursement` state.
2. Insert the draft snapshot and `generate` event.
3. Insert the Category 2 audit-queue row.
4. Commit.

If any step fails, no draft is committed. A failed draft attempt may be recorded
in a separate best-effort Category 2 `credit_document_generation_failed` event.

### 7.4 Rollback and failure matrix

| Failure point | Result |
|---|---|
| Draft state/permission/serialization failure | No draft row, no event as a completed generation; record a failure/denial event separately where possible. |
| Official snapshot insert/event/queue failure | Entire disbursement transaction rolls back; no cash-disbursement confirmation; no official document. |
| Official generation failure after rollback | Record a best-effort Category 2 `credit_document_generation_failed` event; never claim success. |
| Output render failure before event | No output, no print/export event; show a recoverable error. |
| Output event/queue insert failure | Do not deliver the output; abort the action; keep the document unchanged. |
| Integrity hash mismatch | Refuse to render; record Category 14 `document_integrity_failure`; no print/export. |
| Printer offline/paper-out/transport failure | Document remains valid; show error; no financial mutation; allow an explicit reprint; do not auto-retry silently. |
| Duplicate official generation | Return the existing official document; unique constraints prevent a second version. |
| Cross-tenant or permission denial | Refuse; record Category 14 `document_access_denied` where a valid audit target exists. |

### 7.5 Idempotency and concurrency

- The existing `(shop_id, idempotency_key)` unique index on `sync_queue` remains
  the idempotency authority for the disbursement action.
- `(credit_id, document_type, version)` prevents duplicate document versions.
- `(shop_id, document_number)` prevents document-number collisions.
- Retrying the same disbursement key returns the recorded disbursement and its
  existing official document; it does not create a second official document.
- A concurrent second confirmation with a different key loses the conditional
  credit update and must not produce a second document.
- Reprints may be concurrent; each gets its own event and sequence, without
  changing financial state or the base snapshot. The sequence is allocated inside
  the event transaction; the partial unique index rejects a duplicate, and a
  collision is retried with the next value.

---

## 8. Draft, official, PDF, and thermal rendering requirements

### 8.1 Draft agreement slip — proposed requirements

#### 8.1.1 Eligibility and identity

- Only from a persisted credit with `workflow_status = pending_disbursement`.
- No draft for `disbursed` or `cancelled` credits.
- No draft from unsaved origination-form state.
- No draft without a persisted preliminary due date/agreed term. If the legacy
  term is unrecorded, refuse and route to Story 4.3 term recording; never invent
  a due date.
- Draft reference `DRAFT-<document short id>`; no official voucher number.
- Permission: `createCredits`, enforced at the service/DAO.
- No automatic print on origination; printing is an explicit staff action with a
  confirmation prompt stating that the document is not a receipt.

#### 8.1.2 Mandatory text and visual controls

1. Header **and** footer of every page/slip:
   `*** DRAFT / PENDING DISBURSEMENT - NOT A CASH RECEIPT ***`
2. Adjacent to the due date and repeated in the footer:
   `Preliminary Due Date (Subject to Confirmation on Cash Handover) - Non-binding until disbursement confirmation.`
3. Explicit sentence:
   `Cash has NOT been disbursed. This document is not a receipt and is not binding until cash handover is confirmed.`
4. Due-date label: `Preliminary Due Date (Pending Disbursement)`.
5. Visible `DRAFT` band and a `Page x of y` marker (or `Slip x of y` when a
   thermal layout is split).
6. Any signature block is labelled
   `For customer review only — not an executed agreement`.
7. No `PAID`, `RECEIVED`, `CASH RECEIVED`, `OFFICIAL`, or receipt/voucher number.
8. A draft reprint carries both the draft watermark **and** `*** REPRINT ***`.
9. Use text banners/borders, not colour alone; thermal printers may be monochrome.

#### 8.1.3 Proposed draft content

Shop header; draft identity/reference; customer name, opaque customer UUID, and
masked NIC (no address); credit reference and full UUID; origination date;
preliminary due date with the exact disclosure; principal formatted with
`Money.format()`; agreed term; collateral summary with descriptions and weights;
review-only signature line; generation timestamp and hash short form; exact
watermark/disclosure repeated.

### 8.2 Official credit ticket — proposed requirements

#### 8.2.1 Required content

The 11 fields fixed by the epic (`epics.md:1037-1040`):

1. Shop branding snapshot (name, address, phone, tax/registration number).
2. Customer identifier.
3. Credit reference number.
4. Origination date.
5. Confirmed disbursement timestamp.
6. Disbursing staff ID.
7. Official confirmed calendar due date.
8. Disbursed principal amount (`Rs. XX,XXX.XX`).
9. Itemized collateral details (descriptions and gold weights).
10. Zero-interest disclosure.
11. Shop footer notes.

Plus the FR-20 field omitted from the epic list: **Initial Outstanding Balance**
(`prd.md:433`). This is a proposed inclusion under D4.4-02.

#### 8.2.2 Proposed ten-block order

| # | Block | Content |
|---|---|---|
| 1 | Shop header | Name, business address, contact phone, registration/tax number; **no logo in v1** (P-5) |
| 2 | Document identity | `CREDIT AGREEMENT & CASH DISBURSEMENT VOUCHER`; `OFFICIAL — CASH DISBURSED`; stored document number |
| 3 | Reference block | Derived credit reference + full credit UUID; customer name + opaque customer UUID + derived short reference + masked NIC |
| 4 | Dates | Origination; confirmed disbursement date/time; official due date; agreed term; shop time zone |
| 5 | Staff | Disbursing staff ID; full name only if separately approved |
| 6 | Money | Disbursed principal and initial outstanding balance, both `Money.format()`; currency |
| 7 | Collateral | Item reference, description, category, condition, `X.XXX g` weight, estimated value |
| 8 | Disclosure | Exact zero-interest statement |
| 9 | Footer | Shop footer notes, generation timestamp, hash short form, page/slip marker |
| 10 | Signatures (optional) | Customer acknowledgement and disbursing staff acknowledgement, if approved |

#### 8.2.3 Proposed zero-interest disclosure

> `ZERO-INTEREST CREDIT. The disbursed principal is the total amount repayable. No interest, fee, or compounding charge is added. The outstanding balance equals the principal until payments are recorded.`

This reflects the implemented zero-interest invariant at origination: balance
equals principal (`credit_dao.dart:305-312`).

#### 8.2.4 Formatting

- Money: integer minor units formatted with `Money.format()` (`money.dart:305-340`).
- Weights: `formatWeightMilligrams` → `X.XXX g`
  (`collateral_item.dart:289-294`).
- Dates: shop-local display plus zone/offset; UTC ISO also stored in the snapshot.
- Paper/layout: width-parameterised for 58 mm/80 mm thermal; A5 portrait default
  PDF, A4 as an alternative if approved under D4.4-02.
- Full NIC, customer address, and customer photo are not printed.

### 8.3 PDF requirements (proposed)

- One layout model feeds both PDF and thermal renderers; no parallel hand-written
  layouts.
- PDF text must contain every mandatory field, exact watermark/disclosure, and
  the zero-interest statement.
- PDF title/author/subject metadata must not contain customer PII; use the
  document number as the title/filename.
- PDF bytes are generated locally; no cloud renderer.
- PDF bytes are **not** stored in SQLite (AD-5 rule 2). Export is share/save or
  app-private ephemeral output under a separate approved retention rule.
- Font embedding must support whatever language set P-4 confirms; Sinhala/Tamil
  is not promised before the hardware/layout spike.
- `pdf` and `printing` are not installed; D4.4-04 is Pending.

### 8.4 Thermal requirements (proposed, conditional)

- Android-first ESC/POS through one adapter interface; no printer is selected.
- Layout is width-parameterised; 58 mm and 80 mm are not assumed interchangeable.
- Monochrome output; no colour-only signal.
- Exact draft watermark/disclosure and reprint watermark must survive ESC/POS
  text or raster rendering.
- If the printer cannot render required glyphs, raster rendering may be used, but
  this sends an image of the document to the printer and must be explicit.
- Web is PDF/browser-print only; raw ESC/POS on Web is not promised.
- Printer status/connection/failure feedback is required only to the extent P-9
  confirms it; never auto-retry silently.
- Fallback on printer failure is PDF preview/share, and cash handover is never
  blocked on a printer fault (P-10 recommendation).
- Hardware tests require P-1 through P-10 answers.

### 8.5 Content parity

The same resolved snapshot strings and layout model must produce content parity
across PDF and thermal output. Tests must assert mandatory fields in both paths,
not merely that a file/byte stream was produced.

---

## 9. PII masking and reprint fidelity

### 9.1 Proposed policy

**`always_masked_v1`** for all credit documents:

- Customer address: never printed, never stored in the document snapshot.
- NIC: a **document-specific** mask derived from `maskNic`
  (`customer_masking.dart:13-19`) on every draft, official ticket, PDF, print, and
  reprint. `maskNic` must not be called blindly: it returns NICs of 8 characters
  or fewer unchanged (`customer_masking.dart:15-18`). The document policy must
  fully redact such a value (for example `****`) or reject it; it must never print
  a raw short NIC.
- Phone: if an approved layout includes a customer phone, a document-specific
  mask derived from `maskPhone` (`customer_masking.dart:21-47`); the recommended
  layout omits it. `maskPhone` returns normalized values of 6 digits or fewer
  unchanged (`customer_masking.dart:29-30,46`), so the document masker must
  redact or reject such a value rather than print it.
- Customer photo/URI/hash: never printed or stored in the document snapshot.
- Full name: permitted as the customer identifier.
- Opaque customer UUID: permitted; a short display reference may be derived.
- Role-dependent unmasking remains an on-screen capability only.

The policy identifier and resolved flags are recorded in the snapshot, document
row, and audit payload. Renderers receive already-resolved strings and cannot
choose to unmask.

### 9.2 Masking matrix

| Field / surface | On-screen preview | PDF | Printed document | Reprint |
|---|---|---|---|---|
| NIC | Role-dependent on screen | Always masked | Always masked | Reproduce snapshot policy; never unmask |
| Address | Role-dependent on screen | Never printed | Never printed | Never printed |
| Phone | Role-dependent on screen | Masked if present; recommended omitted | Masked if present; recommended omitted | Reproduce snapshot policy |
| Full name | Full | Full | Full | Full |
| Customer UUID | Full opaque | Full/short reference | Full/short reference | Full/short reference |
| Customer photo | Existing profile rules | Never | Never | Never |

### 9.3 Prohibited places for PII

Full NIC, full address, customer photo/URI/hash, collateral photo/URI/hash, full
phone number (where masked by policy), full document text, and PDF bytes must not
appear in:

- audit payloads or `sync_queue` payloads;
- log lines, crash reports, or analytics;
- PDF metadata or filenames;
- printer Bluetooth MAC/name paired with customer data;
- user-facing error messages.

### 9.4 Reprint fidelity

- A reprint renders strictly from `snapshot_json`; no live joins.
- The original document number, version, amounts, dates, branding, and masking
  policy are preserved.
- Fidelity means the same snapshot content under the pinned `layout_version`, not
  byte-identical PDF/ESC/POS output across renderer or library versions. Mandatory
  text and values must match.
- A higher-privileged user cannot unmask a document that was generated masked.
  Changing the policy requires a replacement document, not a reprint.
- The reprint overlay adds `*** REPRINT ***`, reprint timestamp, reprint sequence,
  and reprinting staff ID without changing the base snapshot hash.
- A superseded reprint also carries `*** SUPERSEDED — DO NOT USE ***`; a voided
  reprint carries `*** VOID ***`; a draft reprint carries the draft watermark too.
- Reprinting never creates a financial transaction or changes balances.

---

## 10. Audit, permissions, and offline behaviour

### 10.1 Proposed audit events and action types

PRD FR-31 is the canonical catalogue (`prd.md:626-640`). Category 2 is the parent
of credit-origination/cancellation action types; Category 14 is security events.
This proposal does not add a category.

| Event | FR-31 category | Proposed `action_type` | Local lifecycle event |
|---|---|---|---|
| Draft generated/issued | 2 | `generate_credit_draft` | `generate` |
| Official ticket generated | 2 | `generate_credit_official_ticket` | `generate` |
| PDF exported | 2 | `export_credit_document_pdf` | `export_pdf` |
| Printed (thermal/OS) | 2 | `print_credit_document` | `print` |
| Reprinted | 2 | `reprint_credit_document` | `reprint` |
| Replacement/supersede | 2 | `supersede_credit_document` | `supersede` |
| Void | 2 | `void_credit_document` | `void` |
| Generation failed (business/template/snapshot) | 2 | `credit_document_generation_failed` | No completed document event |
| Permission denied / cross-tenant attempt | 14 | `document_access_denied` | Audit queue only where no valid document subject |
| Snapshot hash mismatch / integrity failure | 14 | `document_integrity_failure` | Audit queue; document event only if a valid subject exists |

Before implementation, D4.4-06 must confirm that the server `audit_events`
category/action-type validation accepts these values (or define the mapping to
existing values). This specification proposes no server migration or fifteenth
category.

An `export`/`print` event records that the user initiated an output action with a
specific document hash and channel; it does not claim that an operating-system
print dialog completed or that paper physically emerged. Transport completion is
diagnostic, not a second audit event. If a handoff or file write fails after the
initiation event, the failure is recorded as a diagnostic or a
`credit_document_generation_failed` event; it is never reported as a completed
output.

Transient transport failures (printer offline, paper out, Bluetooth disconnect,
user cancels the OS print dialog) are operational diagnostics, not audit events
per retry. Diagnostic logs must remain PII-free.

### 10.2 Minimum audit metadata

Each event carries:

- local event UUID and, after synchronization, the server event ID;
- shop/tenant ID;
- event category (2 or 14);
- action type;
- actor user ID;
- target entity type `credit_document` and target document UUID (where valid);
- credit ID;
- document type and version;
- document number;
- snapshot SHA-256;
- output channel;
- reprint count/sequence at event time;
- masking policy actually applied;
- mandatory reason for supersede/void;
- pre-state and post-state **minimal state snapshots** limited to document
  UUID/version, lifecycle state, document number, and hash; these satisfy the
  FR-31 pre/post fields for the document entity and never contain the snapshot
  body or PII;
- server-captured client IP and user agent, when the server appends the event;
  these are never trusted from the client, and local pre-image rows leave them
  null;
- server timestamp (authoritative), with local timestamp only as a pre-image.

**Must not be logged:** NIC, address, phone, customer name, customer photo,
collateral photos, full document text, PDF bytes, printer Bluetooth MAC/name,
passwords, or tokens.

### 10.3 Local audit authority and F1 boundary

- `credit_document_events` is an immutable local document lifecycle ledger, not the
  authoritative audit trail.
- Every lifecycle/security event is also queued in `sync_queue` for server append.
  The queue row uses a UUIDv4 event/audit ID as its idempotency key - the local
  event UUID when one exists, otherwise a new UUIDv4 for the audit event - matching
  the column contract (`sync_queue_table.dart:25-26,64-66`), so a retry cannot
  append the same event twice. The row uses `entityType = credit_document` /
  `entityId = document UUID` when a document exists; otherwise `entityType = credit`
  / `entityId = credit UUID`. The action type is the §10.1 value, with a PII-free
  payload. `sync_queue` is mutable by contract
  (`status` moves through `pending_server_ack`/`confirmed_by_server`/`failed`
  (`sync_queue_table.dart:37-45`)) and is **not** an immutable audit store.
- The authoritative audit entry is the server `audit_events` row after
  synchronization (FR-31 `prd.md:645`).
- R1 already ruled that PRD ordinals are authoritative, but `AuditService`
  currently documents a different taxonomy (`audit_service.dart:35-49`). This is
  unresolved **F1**. Story 4.4 must use PRD ordinals and must not silently align,
  widen, or fork the `AuditService` catalogue. Appendix B asks the Architect how
  to proceed.
- The deferred hash-chained local audit journal (AD-6 rule 7 / R2) is not
  implemented here. No claim of authoritative offline audit is made.

### 10.4 Permissions

| Action | Proposed permission | Enforcement |
|---|---|---|
| Issue/preview/print/export draft | `createCredits` | Service/DAO, plus UI convenience |
| Generate official | Caller already holds `confirmCreditDisbursement` | Existing disbursement boundary |
| Preview/print/export official | `createCredits` **or** `viewAndReprintReceipts` | Service/DAO |
| Reprint draft | `createCredits` | Service/DAO |
| Reprint official | `viewAndReprintReceipts` | Service/DAO |
| Supersede/void | Shop Owner role | Service/DAO; proposed offline lock |
| View audit entries | `viewAuditLogs` (future audit viewer) | Not implemented in 4.4 |

All actions require an active actor and same-shop target. The 14-permission
catalogue and role templates already exist (`app_permission.dart:5-46,122-157`);
Story 1.7's permission-administration UI is not a hard dependency. If runtime
permission editing is required, Story 1.7 becomes a prerequisite.

### 10.5 Offline behaviour

| Action | Offline permitted? | Behaviour |
|---|---|---|
| Draft issue/preview/print/export/reprint | Yes | Local transaction; audit queued `pending_server_ack`; no cloud call |
| Official generation during disbursement | Yes | Same local transaction as the 4.3 disbursement; snapshot and audit queued |
| Official preview/print/export/reprint | Yes | Local snapshot + local output; audit queued |
| Supersede/void | **No (proposed)** | High-risk administrative action; locked until server connectivity under AD-6 rule 8, unless the Architect approves a journal-backed offline path |
| Backfill of pre-4.4 disbursed credits | No | Out of scope |
| Any document rendering | Yes | Local only; no cloud renderer |

The local UI must show unconfirmed audit state as pending server confirmation. A
local record is not a completed authoritative audit entry.

---

## 11. Reprint, supersede, void, and failure rules

### 11.1 Reprint

- Reprint is allowed only for an existing document whose hash verifies.
- It creates no new snapshot version and no financial mutation.
- It records a `reprint` event with sequence, channel, actor, timestamp, and
  masking policy, and queues the corresponding audit event.
- It renders from the snapshot, applies the correct watermarks, and preserves the
  original document number/version.
- Reprint of a superseded/void document is for the record only and must carry the
  superseded/void banner.

### 11.2 Supersede / replacement

- Only a Shop Owner may supersede, with a mandatory reason.
- The replacement is a new version (`version + 1`) with its own document number
  and `supersedes_document_id`; the original number is recorded in the
  replacement snapshot and is never reused. The original row remains untouched
  and reproducible.
- The replacement gets a `generate` lifecycle event; the original gets a
  `supersede` event with the mandatory reason. Both are queued for audit.
- The replacement snapshot is derived from the **original snapshot plus the
  approved corrected fields**; it must not silently refresh unrelated fields from
  live rows.
- The original renders `*** SUPERSEDED — DO NOT USE ***`; the replacement is
  current.
- Superseding an official ticket does not reverse or alter the disbursement,
  balances, or collateral custody.

### 11.3 Void

- Only a Shop Owner may void, with a mandatory reason.
- Void inserts a `void` event; no row is updated or deleted.
- A voided document renders `*** VOID ***`.
- Voiding does not reverse cash disbursement, balances, or collateral custody.
- A voided document is not replaced unless a separate replacement is approved.

### 11.4 Failure handling summary

| Scenario | Required behaviour |
|---|---|
| Draft requested for unsaved/disbursed/cancelled credit | Refuse; no document; auditable denial/failure |
| Draft requested without a persisted term/preliminary due date | Refuse; route to Story 4.3 term recording; never invent a date |
| Shop branding field missing | Render `Not recorded` and warn, or block official generation if D4.4-02 requires complete branding; never invent a value |
| Draft requested without `createCredits` | Refuse at service; Category 14 access-denied event |
| Official requested before disbursement | Refuse; no official document |
| Official snapshot write fails | Roll back the whole disbursement; no official document |
| Snapshot hash mismatch | Refuse render; Category 14 integrity event |
| Document number collision | Retry with fresh document UUID or fail; never overwrite |
| Duplicate official generation | Return existing official; no second version |
| PDF/thermal package unavailable | Disable output path; no fake output; retain snapshot |
| Printer offline/paper out | Error + explicit retry; no financial impact; no silent retry loop |
| Web raw thermal requested | Not supported; offer PDF/browser print |
| Cross-tenant document access | Refuse; Category 14 event |
| Audit queue write fails | Abort the action; do not deliver untracked output |
| Local database trigger rejects mutation | Abort; no partial change |
| Existing pre-4.4 disbursed credit | No automatic official backfill; document the gap |

### 11.5 Legacy disbursed credits

Credits disbursed before Story 4.4 have no historical branding, customer, or
collateral snapshot. They must **not** receive an automatically generated official
ticket that falsely implies it was captured at disbursement. A separate backfill
policy, with an explicit marker and approval, is deferred and out of scope.

---

## 12. Proposed acceptance criteria (AC-01 through AC-10)

All ACs below are **[P]** elaborations of the authoritative Story 4.4 AC and
related requirements. They are not approved and are not implementation authority.

### AC-01 (Proposed) — Draft eligibility

**Given** a persisted credit agreement in `pending_disbursement`  
**When** an active staff member with `createCredits` requests a draft  
**Then** a draft document is created from a snapshot with a stable draft
reference  
**And** no draft is created from unsaved form state, or for a `disbursed` or
`cancelled` credit  
**And** no draft is created without a persisted term/preliminary due date; no due
date is invented  
**And** no draft is printed automatically on origination.

### AC-02 (Proposed) — Draft content and watermark

**Given** a generated draft  
**Then** every page/slip shows exactly
`*** DRAFT / PENDING DISBURSEMENT - NOT A CASH RECEIPT ***` in the header and
footer  
**And** displays exactly
`Preliminary Due Date (Subject to Confirmation on Cash Handover) - Non-binding until disbursement confirmation.`  
**And** states exactly
`Cash has NOT been disbursed. This document is not a receipt and is not binding until cash handover is confirmed.`  
**And** labels the due date `Preliminary Due Date (Pending Disbursement)`  
**And** uses a `DRAFT-` reference with no official voucher number or `PAID`/
`RECEIVED`/`OFFICIAL` claim.

### AC-03 (Proposed) — Official ticket eligibility and content

**Given** a confirmed cash disbursement  
**When** the official executed credit ticket is generated  
**Then** the ticket contains all 11 epic fields plus Initial Outstanding Balance  
**And** formats the principal and balance with `Money.format()`  
**And** lists each collateral item with description and `X.XXX g` weight  
**And** contains the zero-interest disclosure in §8.2.3 and the shop footer notes  
**And** is generated only for a `disbursed` credit, never for `pending_disbursement`
or `cancelled`.

### AC-04 (Proposed) — Official snapshot atomicity

**Given** `confirmCreditDisbursement` is executing  
**When** the official snapshot, document row, lifecycle event, or audit-queue row
fails  
**Then** the entire local transaction rolls back, including the credit state change  
**And** no disbursement commits without an official document record  
**And** no official document commits without the disbursement it documents  
**And** a retry does not create a second official document or a second
disbursement.

### AC-05 (Proposed) — Immutable snapshots and versions

**Given** a generated document  
**When** live shop, customer, credit, balance, or collateral data changes  
**Then** a reprint renders the original snapshot values  
**And** direct `UPDATE`/`DELETE` on `credit_documents` or `credit_document_events`
aborts  
**And** a correction creates a new version with a supersession link and mandatory
reason; the original remains reproducible  
**And** void is recorded as an event without deleting or mutating the row.

### AC-06 (Proposed) — Masking and reprint fidelity

**Given** the proposed `always_masked_v1` policy, subject to D4.4-05  
**Then** customer address is never printed or stored in the snapshot  
**And** NIC is always masked; customer photo is never printed  
**And** phone, if included, is always masked  
**And** the policy identifier is stored in the snapshot and audit payload  
**And** a higher-privileged reprint cannot unmask a document generated under the
masked policy  
**And** no PII appears in PDF metadata, filenames, logs, or audit payloads.

### AC-07 (Proposed) — Audit trail

**Given** any document generation, PDF export, print, reprint, supersede, void,
failed generation, permission denial, or integrity failure  
**Then** the FR-31 category/action type selected under D4.4-06 and the minimum metadata are recorded  
**And** where a document lifecycle event exists, it and its audit-queue row are
written in the same local transaction as the state change or output initiation
they record  
**And** a failed generation or security denial without a completed document uses
the audit queue only, with no fabricated lifecycle event  
**And** no prohibited PII enters the payload  
**And** the event is marked pending server acknowledgement until the authoritative
server append occurs.

### AC-08 (Proposed) — Permissions, tenant scope, and offline

**Given** an actor requests a document action  
**Then** the service checks active status, same-shop scope, and the required
permission  
**And** unauthorized or cross-tenant access is refused and audited under Category
14  
**And** draft/official generation, PDF/print, and reprint work offline from local
data  
**And** supersede/void are locked offline unless the Architect approves an
offline path  
**And** no cloud renderer, network print service, or server call is required for
document content.

### AC-09 (Proposed) — PDF and thermal output

**When** D4.4-04 and D4.4-07 are approved and, for thermal, hardware is confirmed  
**Then** PDF export produces a valid PDF containing all mandatory fields  
**And** Android thermal output produces the same mandatory content for the paper
width and transport confirmed through P-1 through P-3  
**And** Web remains PDF/browser-print only  
**And** printer/paper failures are reported without changing financial state or
silently retrying  
**And** the PDF/thermal paths render from the same snapshot and layout model.

### AC-10 (Proposed) — Schema v15, migration, and rollback integrity

**Given** a v14 local database  
**When** the application upgrades to schema v15  
**Then** existing shops, users, customers, credits, collateral, and sync-queue rows
survive  
**And** `credit_documents`/`credit_document_events`, their indexes, and append-only
triggers exist  
**And** a fresh install produces the same logical schema  
**And** the upgrade is idempotent and passes `PRAGMA foreign_key_check`  
**And** a failed upgrade leaves the v14 database usable with no partial v15
objects  
**And** no PostgreSQL provisioning is required for Story 4.4 tests  
**And** no automatic backfill is performed for pre-4.4 disbursed credits.

---

## 13. Proposed acceptance-test matrix (AT-01 through AT-20)

| ID | AC | Test and level | Asserts | Gate |
|---|---|---|---|---|
| **AT-01** | AC-01, AC-02 | Widget + PDF text | Exact draft watermark and disclosure; explicit non-disbursement sentence; `Preliminary Due Date (Pending Disbursement)` label | After spec/schema approval |
| **AT-02** | AC-01 | Unit/service | No draft from unsaved state, `disbursed`, `cancelled`, or missing term/due date; no invented date; no auto-print | After spec approval |
| **AT-03** | AC-01, AC-08 | Unit + widget | Actor without `createCredits` refused at service; UI denial is secondary | After spec approval |
| **AT-04** | AC-03 | PDF text + widget | All 11 epic fields plus Initial Outstanding Balance; formatted principal; collateral descriptions/weights; zero-interest text; footer; missing branding renders `Not recorded` or the approved block, never a fabricated value | After spec approval; PDF after D4.4-04 |
| **AT-05** | AC-03, AC-04 | Unit/integration | Official only for `disbursed`; snapshot failure rolls back credit, document, event, and audit queue | After D4.4-03 and 4.3 freeze |
| **AT-06** | AC-05 | Unit/integration | After live shop/customer/credit/collateral changes, reprint renders original snapshot values | After spec/schema approval |
| **AT-07** | AC-05, AC-07 | Unit | Recomputed SHA-256 matches; tampered JSON refuses render and records Category 14 integrity failure | After spec approval |
| **AT-08** | AC-05, AC-10 | Migration/integration | `UPDATE`/`DELETE` on both new tables raise `ABORT` | After schema approval |
| **AT-09** | AC-05, AC-09 | Unit | Replacement has new document number/version + supersession link + mandatory reason; superseded number recorded; new `generate` and original `supersede` events queued; original untouched and renders `*** SUPERSEDED — DO NOT USE ***` | After schema approval |
| **AT-10** | AC-05, AC-09 | Widget + PDF text | `*** REPRINT ***`, timestamp, sequence, staff ID; no financial mutation; count derived | After spec approval; PDF after D4.4-04 |
| **AT-11** | AC-06 | Unit + widget | Higher-privileged reprint cannot unmask a masked snapshot | After spec approval |
| **AT-12** | AC-06 | Unit + widget | Cashier vs Manager/Owner surfaces; address never printed; NIC masked at normal and short-length boundaries (<= 8 chars never raw); phone masked at short-length boundary if the layout includes it; photo never; no PII in metadata/filename/log/audit | After spec approval |
| **AT-13** | AC-07 | Unit | Generation/export/print/reprint/supersede/void/failure produce the category/action type selected under D4.4-06 plus minimum metadata; retry reuses the UUID/idempotency key and does not duplicate the audit event | After D4.4-06 |
| **AT-14** | AC-07, AC-08 | Unit | Unauthorized/cross-tenant access produces Category 14 `document_access_denied`; target refused | After D4.4-06 |
| **AT-15** | AC-07, AC-08 | Unit/widget | Generation and local audit queue work with no network; event is `pending_server_ack`; no cloud call | After spec approval |
| **AT-16** | AC-09 | Unit golden | ESC/POS bytes contain exact watermarks/disclosure; correct width wrapping; no colour-only signal | Blocked: D4.4-04, D4.4-07 |
| **AT-17** | AC-09 | Manual checklist | Real printer, P-2 width, P-3 connection, confirmed glyphs and status, PDF fallback; logo only if a separate asset decision adds it | Blocked: P-1…P-10, hardware spike |
| **AT-18** | AC-09 | Widget/service | Valid PDF; text contains all mandatory fields; share/save works on Android and Web | Blocked: D4.4-04 |
| **AT-19** | AC-10 | Drift integration (SQLite only) | Populated v14→v15 preserves data; tables/indexes/triggers present; fresh install parity; second launch idempotent; FK check clean; failed DDL rolls back without partial v15 objects | After schema approval |
| **AT-20** | AC-10 | CI guard | Story 4.4 suite runs without provisioning PostgreSQL or running PostgreSQL-dependent tests | After spec approval |

**Test status:** none of AT-01 through AT-20 has been executed. This matrix is a
proposed contract, not evidence of passing tests.

---

## 14. Traceability

| Requirement | Proposed AC | Proposed AT | Decision dependency |
|---|---|---|---|
| Story 4.4 AC 1 — draft watermark/disclosure | AC-01, AC-02 | AT-01, AT-02, AT-03 | D4.4-01 |
| Story 4.4 AC 2 — official ticket fields, thermal + PDF | AC-03, AC-09 | AT-04, AT-16, AT-17, AT-18 | D4.4-02, D4.4-04, D4.4-07 |
| Story 4.4 AC 3 — document audit events | AC-07 | AT-13, AT-14, AT-15 | D4.4-06 |
| FR-20 — executed voucher contents and permissions | AC-03, AC-06, AC-08 | AT-04, AT-12, AT-14 | D4.4-02, D4.4-05 |
| FR-20 — open draft-printing decision | AC-01, AC-02 | AT-01, AT-02 | D4.4-01 |
| FR-24 — snapshot/reprint integrity pattern (not receipt coverage) | AC-05, AC-06, AC-09 | AT-06, AT-07, AT-09, AT-10, AT-11 | D4.4-03, D4.4-05 |
| FR-31 — categories, action types, record attributes, offline queue | AC-07, AC-08 | AT-13, AT-14, AT-15 | D4.4-06 |
| FR-12 — boundary only; no compliance claimed | AC-06 | AT-12 | D4.4-05 |
| UX-DR-6 — prominent draft/reprint watermarks | AC-02, AC-05 | AT-01, AT-10 | D4.4-01, D4.4-03 |
| AD-1 — local ACID, offline, no silent overwrite | AC-04, AC-08 | AT-05, AT-15 | D4.4-03, D4.4-06 |
| AD-2 — integer minor units | AC-03 | AT-04 | D4.4-02 |
| AD-5 — no binary blobs in relational tables | AC-05 | AT-06 | D4.4-03 |
| AD-6 — RBAC/audit | AC-07, AC-08 | AT-13, AT-14 | D4.4-06 |
| Proposed schema/rollback integrity (AC-10) | AC-10 | AT-19, AT-20 | D4.4-03 |

---

## 15. Dependency assessment and order

### 15.1 Story 1.6 — shop branding

| Question | Finding |
|---|---|
| Sprint status | `backlog` (`sprint-status.yaml:46`). |
| What exists | `shops` columns for name, business address, contact phone, email, registration number, logo URI, header/footer notes (`shops_table.dart:11-43`); `ShopProfile` (`shop_profile.dart:14-102`); `ShopDao.getShopById` (`shop_dao.dart:62-66`); view-only profile screen (`shop_profile_screen.dart:245-266`). |
| What is missing | Editable branding configuration (Story 1.7 RBAC), logo asset handling, branding snapshot. |
| Validation | **Branding can use the existing shop row without implementing Story 1.6 editing.** Story 4.4 reads and snapshots the current `shops` row. Do not wait for editable 1.6. If a logo must be printed, treat logo availability/embedding/raster support as a separate prerequisite (P-5). |

### 15.2 Story 1.7 — permission administration

| Question | Finding |
|---|---|
| Sprint status | `backlog` (`sprint-status.yaml:47`). |
| What exists | 14-permission catalogue and role templates (`app_permission.dart:5-46,122-157`); `AuthorizationGuard` used by existing DAOs. |
| Validation | **Not a hard dependency for 4.4.** Story 4.4 can gate on the existing catalogue and role templates. Story 1.7 is required only if the Product Owner requires runtime permission assignment/editing as part of 4.4, which this specification does not propose. |

### 15.3 Story 4.3 — disbursement engine

| Question | Finding |
|---|---|
| Sprint status | `review`, not `done` (`sprint-status.yaml:72`). |
| What exists | `createCreditAgreement` (`credit_dao.dart:133-359`); `confirmCreditDisbursement` (`435-617`); `cancelCreditAgreement` (`701-834`); `recordAgreedTerm` (`899-1027`); disbursement/cancellation fields (`credit.dart:175-188`); schema v14 (`app_database.dart:72,199-205`); disbursement tests and migration tests exist. |
| What is unresolved | F1 audit taxonomy; Q-1/D10; AC-4 spec/code drift; U-5/v14 spec/code drift; no formal contract freeze; no dedicated `cancelCreditAgreement` test/UI found. |
| Validation | **Official-snapshot integration remains blocked until Story 4.3 is closed or its disbursement contract is formally frozen.** Draft/schema/renderer scaffolding may be prepared after the Story 4.4 gates, but the official hook must not land on a moving contract. |

**Contract fields the Architect is asked to freeze (not decided here):** the
persisted credit identity and tenant scope; `principalCents`, `balanceCents`,
`status`, `workflowStatus`, `dueDate`, `createdAt`, `termPresetDays`,
`customDueDate`, `disbursedAt`, `disbursedByUserId`, `cancelledAt`,
`cancellationReason`; the collateral binding via `collateral_items.credit_id`; the
conditional update predicate; the idempotency guard; and the transaction boundary
into which the official snapshot is inserted. See Appendix B.

### 15.4 Story 7.2 — export masking

| Question | Finding |
|---|---|
| Sprint status | `backlog` (`sprint-status.yaml:93`). |
| What exists | Presentation masking helpers from Story 2.5 (`customer_masking.dart:13-50`); no PDF/CSV export service; no server-side PII omission layer. Story 2.6 is also backlog (`sprint-status.yaml:58`). |
| Validation | **Story 4.4 defines its own local document-masking policy and does not claim Story 7.2 or FR-12 server-side compliance.** The local policy can proceed in parallel with 7.2; 7.2 should later reuse the same policy. Do not block 4.4 on 7.2 and do not report 7.2/FR-12 as done. |

### 15.5 Gate matrix

| Gate | Blocks | Evidence required |
|---|---|---|
| D4.4-01…07 both signatures | All implementation | Signed decision register, no blanks |
| Specification approval | All implementation | Recorded approval of this document |
| Story 4.3 closure or contract freeze | Official-snapshot integration, audit wiring for official generation | Architect record; sprint status/closure evidence |
| P-1…P-10 answers + D4.4-04/D4.4-07 | Thermal dependency/adapter | Completed Appendix A and approved decisions |
| D4.4-04 | PDF/printing dependency installation | Approved decision and dependency review |
| D4.4-06 | Audit wiring | Approved category mapping; F1 handling recorded |
| 1.6 minimal branding read | Branding snapshot | Existing `shops` row; no editing required |
| 7.2 | Nothing in 4.4 | Independent; no compliance claim |
| 1.7 | Nothing unless runtime permission admin is requested | Existing catalogue sufficient for 4.4 |

### 15.6 Proposed implementation order after all applicable gates

1. Record approvals and spec approval.
2. Add schema v15 tables/indexes/triggers and migration; prove insert-only.
3. Add pure-Dart snapshot/domain/policy/numbering and hash tests.
4. Add draft issuance/rendering/audit path.
5. Freeze/close Story 4.3, then add official-snapshot integration inside the
   disbursement transaction.
6. Add PDF dependency/renderer after D4.4-04.
7. Run the hardware spike, answer P-1…P-10, select exactly one thermal transport
   after D4.4-07, then add the adapter.
8. Wire audit, permissions, UI, failure handling, and AT-01…AT-20.
9. Verify acceptance and record evidence; do not mark Story 4.4 done without all
   gates.

This order authorises nothing by itself.

---

## 16. Outstanding approvals and readiness

### 16.1 Outstanding signatures

| Item | Required signatories | Status |
|---|---|---|
| D4.4-01 through D4.4-07 | Product Owner + Architect (each decision) | **All Pending** |
| This specification | Product Owner + Architect | **Pending** |
| Story 4.3 contract freeze / closure | Architect (with Story 4.3 owner) | **Pending** |
| P-1 through P-10 | Product Owner / Operations | **All unanswered** |
| Thermal dependency approval | Architect after P answers | **Blocked** |
| PDF/printing dependency approval | Architect | **Blocked** |

### 16.2 Readiness verdict

**NOT READY — AWAITING APPROVAL**

Reasons:

1. All seven D4.4 decisions are Pending; no signature or approval exists.
2. The PRD's draft-printing policy remains an explicit open decision
   (`prd.md:440`).
3. Story 4.3 is in `review`; its disbursement contract is not formally frozen;
   F1 and Q-1/D10 remain open; AC-4 and U-5/v14 evidence conflicts with the spec.
4. No official Story 4.4 implementation approval exists; Story 4.4 is `backlog`.
5. P-1 through P-10 are unanswered, so no thermal dependency or adapter can be
   selected.
6. Story 1.6 branding and Story 7.2 masking are backlog; only the minimal local
   prerequisites are assessed.
7. No `credit_documents`/`credit_document_events` schema, PDF/printing dependency,
   renderer, or document test exists yet.

**Next action:** route D4.4-01 through D4.4-07, this specification, and the
Appendix B Architect record for written decisions. Do not implement.

---

## Appendix A — P-1 through P-10 questionnaire

### A.1 Inventory

All ten questions below were extracted from
`story-4-4-approval-package.md:650-661`. **No question is missing.** No answer has
been recorded; every response area is blank.

### A.2 Response instrument

**Respondent role:** Product Owner / Operations  
**Respondent name:** ______________________  
**Signature:** ______________________  
**Date:** ____________

| ID | Question | Product Owner / Operations response | Evidence / attachment | Date |
|---|---|---|---|---|
| **P-1** | Exact printer make/model(s) and command set (ESC/POS vs TSPL/CPCL/ZPL)? | ______________________________ | ______________________ | __________ |
| **P-2** | Paper width: 58 mm, 80 mm, or both? | ______________________________ | ______________________ | __________ |
| **P-3** | Connection method: Bluetooth Classic, BLE, USB, Wi-Fi/TCP, or vendor dock? | ______________________________ | ______________________ | __________ |
| **P-4** | Must the ticket print Sinhala/Tamil, or English only? | ______________________________ | ______________________ | __________ |
| **P-5** | Is a shop logo required on thermal output? | ______________________________ | ______________________ | __________ |
| **P-6** | Is a cash-drawer kick required? | ______________________________ | ______________________ | __________ |
| **P-7** | Must Web print thermal receipts? | ______________________________ | ______________________ | __________ |
| **P-8** | Is Windows desktop a supported counter target? | ______________________________ | ______________________ | __________ |
| **P-9** | Is print confirmation/status feedback required? | ______________________________ | ______________________ | __________ |
| **P-10** | What is the fallback when the printer is unavailable? | ______________________________ | ______________________ | __________ |

### A.3 What each answer gates

| Gate | Questions | Effect |
|---|---|---|
| Protocol/command set | **P-1** | Determines whether ESC/POS is the correct protocol at all; a label printer would need a different path. |
| Layout width | **P-2** | Determines columns, font sizes, wrapping, and whether `X.XXX g` and long descriptions fit. |
| Transport | **P-3** | Determines transport package, Android permissions, and adapter contract. |
| Glyphs/language | **P-4** | May force raster rendering or a different font strategy. |
| Logo | **P-5** | v1 prints branding text only. A "yes" determines whether a later revision needs an immutable asset copy, raster support, and print-time changes. |
| Drawer | **P-6** | Some SDKs expose a kick; not all. |
| Web thermal | **P-7** | If yes, a separately approved local bridge is required; current stack cannot. |
| Windows target | **P-8** | No `windows/` target exists; adding one is a platform decision. |
| Status feedback | **P-9** | Distinguishes status-capable transports from fire-and-forget. |
| Failure fallback | **P-10** | Must not block cash handover on a printer fault. |

### A.4 Minimum answers before thermal dependency/adapter selection

- **Hard minimum:** P-1, P-2, P-3, P-4.
- **Adapter contract:** P-5, P-6, P-9, P-10.
- **Target scope:** P-7, P-8.

Until all applicable answers are recorded and D4.4-04/D4.4-07 are approved, no
thermal printer dependency may be selected and no adapter may be created. This
document neither selects a printer nor installs a package.

---

## Appendix B — Story 4.3 reconciliation and Architect decision record

### B.1 Status

Story 4.3 is `review`, not `done` (`sprint-status.yaml:72`). No formal
"disbursement contract freeze" record was found. A search of the Story 4.3
specification, `sprint-status.yaml`, and planning/status artifacts (excluding this
new draft) found no Story 4.3 freeze record; the only `frozen` match was the
unrelated `<frozen-after-approval>` block in `spec-1-2`. No Story 4.3 freeze
decision exists.

**This record does not decide any item below.** It prepares the questions and
evidence for the Architect.

### B.2 Discrepancy evidence

| Item | Evidence | Observation |
|---|---|---|
| **AC-4** | `spec-4-3:5-6,31,150-162` says cancellation design is "approved design, not yet implemented." `credit_dao.dart:701-834` implements `cancelCreditAgreement`, including Category 2 audit payload and conditional update. A search of `test/` for `cancelCreditAgreement` returned no matches; a search of `lib/features/customers/presentation/` returned no cancellation action. | Code exists, but tests and UI are absent. The specification text is stale or the implementation is incomplete/partial. Which is authoritative is unresolved. |
| **U-5/v14** | `spec-4-3:45,47,208-210` says the DB-level Tier 1 CHECKs/v14 migration remain open. `app_database.dart:72` reports schema v14; `:199-205` contains the v14 branch; `:530+` contains `_migrateCreditsToV14`; `test/unit/core/data/local/drift_migration_v14_test.dart` exists. `app_database.dart:29` still says "Schema Version: 13." | The working tree has v14, but the spec and a code doc comment are stale. The test file's passing status was not verified here. |
| **F1** | `prd.md:626-640` lists category 2 as credit agreement origination/cancellation and category 7 as financial correction approvals; `audit_service.dart:35-49` documents category 2 as customer photo/exception and category 7 as credit agreement creation/disbursement. `spec-4-3:37,218` records R1 (PRD ordinals authoritative) but says `AuditService` alignment is not implemented. | Story 4.4 will use PRD ordinals. The server `AuditService` taxonomy conflict remains open. |
| **Contract freeze** | `sprint-status.yaml:72`; no freeze record. `confirmCreditDisbursement` at `credit_dao.dart:435-617`; document hook would be inside its transaction. | Official-snapshot integration cannot safely land until the contract is frozen or the story closes. |

### B.3 Contract fields proposed for freeze (Architect to decide)

The following persisted/behavioural contract is already implemented, with
disbursement and migration tests present (their passing status was not re-verified
here). The Architect is asked whether it is frozen for Story 4.4's official
snapshot:

- credit identity: `id`, `shop_id`, `customer_id`;
- money: `principal_cents`, `balance_cents` (unchanged by disbursement);
- state: `status`, `workflow_status`;
- dates: `created_at`, `due_date`, `term_preset_days`, `custom_due_date`,
  `disbursed_at`;
- actor: `disbursed_by_user_id`;
- cancellation: `cancelled_at`, `cancellation_reason`;
- collateral binding: `collateral_items.credit_id`;
- transaction and idempotency: the conditional update matches
  `workflow_status = pending_disbursement`; the sync-queue idempotency guard is
  used; the official snapshot must be inserted after the update and before commit;
- official due date: `OfficialDueDateCalculator` from the agreed term and
  confirmed disbursement date (`credit_term.dart:377-462`).

### B.4 Architect decision requests — all Pending

| ID | Decision requested | Architect decision | Name / signature / date |
|---|---|---|---|
| **4.3-A1** | Is `cancelCreditAgreement` (`credit_dao.dart:701-834`) the authoritative AC-4 implementation, or is the "not yet implemented" spec statement authoritative? What must be done to reconcile the spec, tests, and UI? | ______________________________ | ______________________ |
| **4.3-A2** | Is the v14 Tier 1 CHECK migration complete and accepted despite `spec-4-3:45,47,208-210` saying it is open? If not, what remains, and which document is authoritative? | ______________________________ | ______________________ |
| **4.3-A3** | May Story 4.4 use PRD FR-31 ordinals and document action types under Category 2 while F1 (`AuditService` alignment) remains open? Is `AuditService` alignment a 4.4 prerequisite or separate work? | ______________________________ | ______________________ |
| **4.3-A4** | Is the disbursement contract in B.3 formally frozen for Story 4.4, or must Story 4.3 close first? If frozen, record the exact boundary and any conditions. | ______________________________ | ______________________ |
| **4.3-A5** | How should Q-1/D10 (cancelled-agreement balance invariant) affect Story 4.4? This specification does not cancel credits or generate official documents for cancelled credits; confirm whether 4.4 may proceed independently of that open item. | ______________________________ | ______________________ |

**Status of every request: Pending. No Architect decision is implied.**

### B.5 Story 4.4 boundary while Story 4.3 is unresolved

- Draft/schema/renderer scaffolding may be prepared only after the Story 4.4
  gates; no official-snapshot integration.
- No D-1 through D-7 or J-1 work.
- No reinterpretation of Q-1/D10.
- No claim that Story 4.3 is closed or its contract frozen.
- No change to `sprint-status.yaml`.

---

## Appendix C — Evidence index

Line references were verified against the working tree on 2026-10-22. The tree
contains pre-existing uncommitted changes; they were read but not altered. This
new draft is the only file created by this task. No test was run as part of this
documentation task.

| Claim | Evidence |
|---|---|
| Story 4.4 requirements are in the epic | `epics.md:1024-1048` (draft 1032-1035; official 1037-1040; audit 1042-1044; dependencies 1047) |
| Draft policy is open in the PRD | `prd.md:440` |
| Official voucher fields include Initial Outstanding Balance | `prd.md:433`; epic list `epics.md:1039` omits it |
| Document permissions | `prd.md:441` |
| Document audit requirement | `prd.md:442` |
| FR-24 snapshot/reprint pattern | `prd.md:510-522` |
| FR-31 catalogue and action types | `prd.md:622-647` (categories 626-640; authority 643; category 2 action types 644; offline 645) |
| FR-12 server-side omission boundary | `prd.md:310-318` |
| UX-DR-6 watermark requirement | `epics.md:88` |
| AD-1 offline/ACID/no silent overwrite | `ARCHITECTURE-SPINE.md:32-73` (atomic 54-56; append-only/no overwrite 62-64; offline 70-73) |
| AD-2 Money | `ARCHITECTURE-SPINE.md:75-134`; `money.dart:305-340` |
| AD-5 no binary blobs | `ARCHITECTURE-SPINE.md:212-263` (metadata-only rule 226-243) |
| AD-6 RBAC/audit | `ARCHITECTURE-SPINE.md:265-356`; `app_permission.dart:5-46,122-157`; `sync_queue_table.dart:37-45` |
| Platform targets | `android/` and `web/` exist; no `windows/`, `ios/`, `macos/`, or `linux/`; `ARCHITECTURE-SPINE.md:43` |
| Current schema version | `app_database.dart:72` (`14`); table list `:38-50`; v14 branch `:199-205`; `_migrateCreditsToV14` `:530+`; stale doc comment `:29` |
| Credit table fields and checks | `credits_table.dart:18-113` (fields 20-83; CHECKs 89-113) |
| Credit model fields/transitions | `credit.dart:127-188`; getters 269-301; disbursement 311-341; cancellation 357-370 |
| Origination, disbursement, cancellation, term DAO operations | `credit_dao.dart:133-359,435-617,701-834,899-1027`; zero-interest balance 305-312; time-zone resolution 1031-1046 |
| Shop branding columns | `shops_table.dart:11-43`; `shop_profile.dart:14-102`; `shop_dao.dart:62-66`; view-only screen `shop_profile_screen.dart:245-266` |
| Story 1.6 is backlog and view-only | `sprint-status.yaml:46`; `spec-1-6:5,72-75` |
| Story 1.7 is backlog; 14 permissions/role templates exist | `sprint-status.yaml:47`; `app_permission.dart:5-46,122-157` |
| Customer fields/PII | `customers_table.dart:12-50` (name 20-21; NIC 23-24; phone 26-27; address 29-30; photo 32-36) |
| Collateral fields/formatting | `collateral_items_table.dart:22-90`; `collateral_item.dart:121-201,289-294` |
| Masking helpers | `customer_masking.dart:13-50` (short-NIC bypass at 15-18; short-phone bypass at 29-30,46); consumers `customer_search_screen.dart:158`, `customer_profile_screen.dart:263-269` |
| Story 7.2 is backlog; no export service | `sprint-status.yaml:93`; source/test search found no PDF/CSV export service or server PII omission; Story 2.6 backlog `:58` |
| Audit taxonomy conflict (F1) | `audit_service.dart:35-49` vs `prd.md:626-640`; `spec-4-3:37,218` |
| Local queue is mutable | `sync_queue_table.dart:37-45` |
| Story 4.3 is review, not done | `sprint-status.yaml:72` |
| AC-4 spec/code drift | `spec-4-3:5-6,31,150-162` vs `credit_dao.dart:701-834`; no `cancelCreditAgreement` matches in `test/`; no cancellation action in `lib/features/customers/presentation/` |
| U-5/v14 spec/code drift | `spec-4-3:45,47,208-210` vs `app_database.dart:72,199-205,530+`; `drift_migration_v14_test.dart` exists; no test run verified |
| No formal 4.3 contract freeze | Search of 4.3/status/planning artifacts (excluding this draft) found no Story 4.3 freeze record; `sprint-status.yaml:72` |
| Story 4.4 is backlog | `sprint-status.yaml:73` |
| No PDF/printing dependency | `pubspec.yaml:21-22,30-49` |
| No document tables/types | Searches of `lib/`, `test/`, `android/`, `web/`, and migration paths for `credit_documents`, `credit_document_events`, `CreditDocument`, and `DocumentMaskingPolicy` returned no implementation matches; `app_database.dart:38-50` |
| Draft and official strings | Exact draft strings at `epics.md:1034-1035`; component wording at `prd.md:437-439` |
| P-1 through P-10 source | `story-4-4-approval-package.md:650-661` |
| Approval package decisions remain Pending | `story-4-4-approval-package.md:138-149,213-224,332-343,410-421,499-510,581-592,672-683,748-762` |

---

## Document control

- **Created:** 2026-10-22.
- **Nature:** New planning/specification artifact only.
- **Changes made by this task:** This file only. No existing file was edited by
  this task.
- **No source, test, migration, dependency, generated code, schema, database, or
  `sprint-status.yaml` was changed by this task.**
- **No Git commit, branch, reset, checkout, or staging operation was performed.**
  The new specification file is untracked; pre-existing working-tree changes were
  left untouched.
- **No test, PostgreSQL instance, or printer hardware was used.**
- **Status remains:** **NOT READY — AWAITING APPROVAL.**

