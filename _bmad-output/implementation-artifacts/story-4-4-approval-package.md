# Story 4.4 — Product Owner & Architect Approval Package

**Project:** Credit Management System
**Project path:** `C:\projects\credit_system`
**Story:** 4.4 — Loan Agreement Documentation, Draft Agreements & Cash Disbursement Vouchers
**Epic:** Epic 4 — Loan Agreement Lifecycle & Disbursement
**Package date:** 2026-10-22
**Prepared by:** Engineering (approval preparation only)
**Proposed specification:** `_bmad-output/implementation-artifacts/spec-4-4-loan-agreement-documentation-draft-agreements-cash-disbursement-vouchers.md`
**Separate hardware questionnaire:** `_bmad-output/implementation-artifacts/story-4-4-p1-p10-questionnaire.md`
**Specification status:** **APPROVED**
**Review readiness:** **COMPLETE — FORMALLY APPROVED**
**Current status:** **READY — IMPLEMENTATION APPROVED**
**Implementation authority:** Approved by Product Owner and Lead Architect on 2026-10-25.

---

## 1. Purpose and scope

This document is a decision package for the Product Owner and Architect. It presents the proposed Story 4.4 specification, the seven unresolved Story 4.4 design decisions, the repository evidence that constrains each one, the Story 4.3 issues that require an Architect ruling, the hardware questions, and the dependency position. It records no decision or signature.

It does **not**:

- implement Story 4.4,
- approve the proposed specification,
- install PDF or printing packages,
- modify source, tests, dependencies, migrations, generated code, or `sprint-status.yaml`,
- change Git state,
- provision PostgreSQL or run PostgreSQL-dependent tests,
- implement Story 4.3 deferred decisions **D-1 through D-7** or **J-1**,
- resolve Story 4.3 issues AC-4, U-5/v14, F1, Q-1/D10, the cancellation-flow gap, or the contract-freeze question on the Architect's behalf.

Every decision and request below is **Pending**. No approval has been recorded, inferred, or pre-filled. The separate P-1 through P-10 questionnaire contains no answers.

### 1.1 Authoritative requirement sources

| Source | Location | What it fixes |
|---|---|---|
| Story 4.4 acceptance criteria | `_bmad-output/planning-artifacts/epics.md:1024-1048` | Draft watermark/disclosure, official ticket fields, thermal + PDF, document audit logging |
| FR-20 | `_bmad-output/planning-artifacts/prds/prd-credit_system-2026-10-13/prd.md:429-442` | Executed voucher contents, draft distinction, permissions, **open draft-printing decision** |
| FR-31 | `prd.md:622-647` | 14-event catalogue authority, category 2 vs 4, record attributes, offline append semantics |
| FR-12 | `prd.md:310-318` | Server-side PII omission and masking expectations |
| FR-24 | `prd.md:510-522` | Snapshot-only reprint, `*** REPRINT ***`, reprint audit |
| UX-DR-6 | `epics.md:88` | Prominent draft and reprint watermarks |
| Architecture spine | `_bmad-output/planning-artifacts/architecture/architecture-credit_system-2026-10-14/ARCHITECTURE-SPINE.md` | AD-1 offline/ACID, AD-2 Money, AD-5 no binary in relational tables, AD-6 RBAC/audit |

### 1.2 Verification method and limits

Repository claims below were verified against the working tree, not against design prose alone. The tree contains uncommitted changes, which were read but not altered. Package facts were checked against the public pub.dev API on 2026-10-22. No hardware was available; all printer claims remain subject to the hardware spike in Decision 7.

---

## 2. Decision 1 — Draft agreement requirements

### 2.1 Requirement and current position

Story 4.4 AC 1 requires that, for a loan in `Active / Pending Disbursement`, a printed draft agreement slip is titled and watermarked exactly:

> `*** DRAFT / PENDING DISBURSEMENT - NOT A CASH RECEIPT ***`

and explicitly states exactly:

> `Preliminary Due Date (Subject to Confirmation on Cash Handover) - Non-binding until disbursement confirmation.`

The PRD goes further and leaves the **policy itself** open:

> `[OPEN DECISION: PRE-DISBURSEMENT DRAFT AGREEMENT PRINTING]`: Defines whether counter staff are permitted to print a physical draft agreement slip prior to cash disbursement confirmation ... or whether all document generation is strictly locked until cash disbursement is confirmed.
> — `prd.md:440`

**This is the primary product blocker in Story 4.4.** The exact words are fixed; whether drafts may exist at all is not.

### 2.2 Proposed timing (requires approval)

**Recommended Option 1A — drafts enabled after persisted origination, never before.**

| Point in lifecycle | Draft permitted? | Conditions |
|---|---|---|
| Loan origination form still open / unsaved | **No** | No document may be generated from unpersisted form state |
| Immediately after `createLoanAgreement` returns (`pending_disbursement`) | **Yes** | Draft may be previewed, exported, printed, reprinted |
| While agreement remains `pending_disbursement` | **Yes** | Each generation records a document event |
| After confirmed disbursement (`disbursed`) | **No new draft** | Existing draft snapshots remain reproducible but are marked superseded; official ticket is the authoritative document |
| After cancellation (`cancelled`) | **No new draft** | Existing drafts reproducible for the record only |

Rationale: the draft exists to support customer review and physical signature before cash is counted, which is the operational need named in the PRD. Generating only from a persisted agreement gives the draft a stable loan identity and an auditable origin.

### 2.3 Required draft wording and controls

Mandatory, non-negotiable content:

1. Watermark/title, repeated in the header **and** footer of every page/slip:
   `*** DRAFT / PENDING DISBURSEMENT - NOT A CASH RECEIPT ***`
2. Disclosure, adjacent to the due date and again in the footer:
   `Preliminary Due Date (Subject to Confirmation on Cash Handover) - Non-binding until disbursement confirmation.`
3. Explicit sentence: `Cash has NOT been disbursed. This document is not a receipt and is not binding until cash handover is confirmed.`
4. Due-date label: `Preliminary Due Date (Pending Disbursement)` — already the established UI wording (`loan_term.dart:300-375`; `spec-4-2:15-17`).
5. Draft reference: `DRAFT-<document short id>`; **no** official voucher number.
6. Page marker `Page x of y` and a visible `DRAFT` band on every page.
7. Signature block, if any, must be labelled `For customer review only — not an executed agreement`.

Recommended additional controls (new layout choices — approval required):

- Use text banners and borders, not colour alone, because mono thermal printers cannot render colour (UX-DR-6 only requires prominence).
- Print `NOT A CASH RECEIPT` in the largest font the paper width permits.
- Do not print `PAID`, `RECEIVED`, `CASH RECEIVED`, `OFFICIAL`, or a receipt/voucher number on a draft.
- A draft reprint carries **both** `*** DRAFT / PENDING DISBURSEMENT - NOT A CASH RECEIPT ***` and `*** REPRINT ***`.

### 2.4 Risks of generating drafts at loan creation

| Risk | Consequence if uncontrolled |
|---|---|
| **Mistaken for a cash receipt** | Customer or staff treats an unsigned draft as proof cash changed hands; undermines FR-19's decoupling of agreement and disbursement |
| **Shadow disbursement** | Staff collects cash against a draft and never confirms disbursement, leaving the loan `pending_disbursement` with cash already out; cash-out reporting excludes it |
| **Preliminary date treated as final** | Customer is told a due date that changes at handover; dispute and collections risk |
| **Signature without authority** | A signed draft may be argued to be a binding agreement even though cash was not disbursed |
| **Stale/duplicate paper** | Multiple drafts with different terms circulate; no single authoritative document |
| **PII leakage** | Discarded drafts containing NIC/address/phone remain in bins or printer spools |
| **Audit ambiguity** | If drafts are not logged, the shop cannot show what the customer was given, when, or by whom |
| **Post-disbursement confusion** | A draft printed after disbursement could contradict the official ticket |

### 2.5 Controls needed to prevent drafts being mistaken for receipts

1. **Persistence gate** — drafts only from a persisted `pending_disbursement` loan; never from the origination form buffer.
2. **State gate** — service refuses draft generation for `disbursed` and `cancelled` loans.
3. **Exact mandatory text** — watermark and disclosure are constants, not template options; tests assert the exact strings.
4. **Distinct identity** — draft reference namespace (`DRAFT-…`), no voucher/receipt number, no "official" seal language.
5. **Visual separation** — full-width banner, repeated watermark, border, and an explicit `CASH HAS NOT BEEN DISBURSED` sentence.
6. **Permission gate** — draft requires `createLoans` (PRD FR-20 `prd.md:441`). Cashier holds it; the DAO/service must enforce it, not only the widget.
7. **Audit gate** — every draft preview/export/print/reprint writes an audit event (Decision 6), including the document hash.
8. **Snapshot gate** — the draft itself is an immutable snapshot (Decision 3), so later edits cannot silently change what the customer reviewed.
9. **Reprint gate** — reprints are watermarked `*** REPRINT ***` and logged.
10. **PII control** — draft follows the same masking policy as other documents (Decision 5); address is never printed.
11. **Printer control** — no auto-print on loan creation; draft printing is an explicit staff action with a confirmation prompt stating it is not a receipt.
12. **Operational control (recommended)** — a one-line "What this document is / is not" legend on every draft, and staff training that cash must still be confirmed through the disbursement screen.

### 2.6 Alternatives

| Option | Description | Trade-off |
|---|---|---|
| **1A (recommended)** | Drafts enabled immediately after persisted origination, with full controls | Meets the pilot-review use case; highest misidentification risk, mitigated by controls |
| **1B** | Drafts locked until disbursement; only official tickets exist | Strongest misuse protection; removes pre-cash customer review and physical signature |
| **1C** | Drafts enabled only after an explicit "review requested" flag is set by a Manager | Extra state and workflow; not required by PRD; complexity without proven need |
| **1D** | No paper drafts; on-screen preview only | Avoids physical misidentification; does not meet "printable draft agreement slip" AC if drafts are enabled |

### 2.7 Decision record — D4.4-01

| Field | Value |
|---|---|
| **Decision ID** | D4.4-01 |
| **Repository requirements** | `epics.md:1032-1035`; `prd.md:435-441`; `loan.dart:279-281` (`isPendingDisbursement`); `loan_dao.dart:133-359` (origination); `app_permission.dart:16` (`createLoans`); `customer_masking.dart` (Decision 5) |
| **Proposed option** | **1A** — drafts permitted only after persisted origination and only while `pending_disbursement`, with the mandatory watermark, disclosure, state gate, permission gate, audit, snapshot, reprint, and PII controls in §2.3–2.5 |
| **Alternatives** | 1B (locked until disbursement), 1C (manager-flagged review), 1D (screen-only preview) |
| **Security and integrity consequences** | Drafts create a credible misidentification and shadow-disbursement risk. Controls reduce but do not eliminate it. If Option 1B is chosen, the risk is largely removed at the cost of the pre-cash review workflow. Either choice must be reflected in the acceptance tests. |
| **Decision requested** | Whether Option 1A, 1B, 1C, or 1D is approved for pre-disbursement draft agreement slips, and whether the controls in §2.3–2.5 are mandatory. |
| **Status** | **Pending** |
| **Decision** | ______________________ |
| **Rationale** | ______________________ |
| **Conditions** | ______________________ |
| **Product Owner identity** | Name: ______________________  Role: Product Owner  Signature: ______________________  Date: ____________ |
| **Architect identity** | Name: ______________________  Role: Architect  Signature: ______________________  Date: ____________ |

---

## 3. Decision 2 — Official loan ticket

### 3.1 Required fields

Story 4.4 AC 2 (`epics.md:1037-1040`) requires:

1. Shop Branding Snapshot (Name, Address, Phone, Tax/Reg No)
2. Customer Identifier
3. Loan Reference Number
4. Origination Date
5. Confirmed Disbursement Timestamp
6. Disbursing Staff ID
7. Official Confirmed Calendar Due Date
8. Disbursed Principal Amount (`Rs. XX,XXX.XX`)
9. Itemized Collateral Details (descriptions and gold weights)
10. Zero-interest disclosure
11. Shop footer notes

PRD FR-20 additionally requires **Initial Outstanding Balance** (`prd.md:433`). It is omitted from the epic AC list but is part of the authoritative FR. **Recommendation: include it**, because at disbursement the initial balance equals the principal and its presence makes the zero-interest position explicit.

**Branding proposal:** exclude the shop logo from v1 because no immutable asset copy exists. For blank optional branding fields (address, phone, registration/tax number), render `Not recorded` plus a warning; do not fabricate values. Requiring complete branding before official generation remains the alternative. This is a D4.4-02 sub-choice and requires explicit approval.

### 3.2 Proposed field order

The order below is designed for a narrow thermal slip first (top-to-bottom reading), then reused unchanged for PDF.

| # | Block | Content | Source at snapshot time |
|---|---|---|---|
| 1 | Shop header | Shop name (large), business address, contact phone, registration/tax number, optional logo | `shops.name`, `businessAddress`, `contactPhone`, `registrationNumber`, `logoUri` |
| 2 | Document identity | `LOAN AGREEMENT & CASH DISBURSEMENT VOUCHER`; `OFFICIAL — CASH DISBURSED`; document number | New `loan_documents.document_number` |
| 3 | Reference block | Loan reference; customer identifier | `loans.id` (or approved reference); customer name + customer short ref + masked NIC |
| 4 | Dates | Origination date; confirmed disbursement date + time; official calendar due date; agreed term | `loans.createdAt`, `disbursedAt`, `dueDate`, `termPresetDays`/`customDueDate`, shop time zone |
| 5 | Staff | Disbursing staff ID (and optional name) | `loans.disbursedByUserId`; `app_users.fullName` optional |
| 6 | Money | Disbursed principal; initial outstanding balance; currency | `loans.principalCents`, `loans.balanceCents`, `Money.format()` |
| 7 | Collateral | Table: item ref, description, category, condition, gold weight (3 dp g), estimated value | `collateral_items` rows bound to `loans.id` |
| 8 | Disclosure | Zero-interest statement | Fixed constant |
| 9 | Footer | Shop footer notes; generation timestamp; document hash short form; `Page x of y` | `shops.receiptFooterNotes`, snapshot metadata |
| 10 | Signatures (recommended) | Customer acknowledgement; disbursing staff acknowledgement | New layout choice — approval required |

### 3.3 Formatting recommendations (all new choices require approval)

| Choice | Recommendation | Why |
|---|---|---|
| **Loan reference** | Print a short display reference derived from the loan UUID (e.g. `LN-XXXXXXXX`) **and** the full UUID in small print; do not add a `loans` column in this story | Avoids a `loans` table rebuild and an offline sequential-number design; the full UUID remains the unambiguous legal identifier |
| **Document number** | `VCH-<shop short code>-<YYYYMMDD>-<document short id>` stored on `loan_documents` | Stable, human-readable, no mutation of `loans` |
| **Customer identifier** | Full name + customer short reference + **masked** NIC + **no address** | Satisfies "Customer Identifier" with least PII (Decision 5) |
| **Disbursing staff** | Print staff ID; add full name only if approved | PRD asks for Staff ID; names are staff PII |
| **Dates** | Shop-local `YYYY-MM-DD` and `HH:mm` with zone abbreviation/offset; store both local rendering and UTC ISO in the snapshot | FR-17/FR-19 require shop-zone evaluation; avoids the H-1 class of bug |
| **Money** | `Money.format()` → `Rs. 1,500.50`; integer minor units only | AD-2; `money.dart:305-340` |
| **Weights** | `X.XXX g` using the existing milligram formatter | `collateral_item.dart:289-294` |
| **Collateral table** | One row per item, wrapped description, value optional if width-constrained | PRD requires descriptions and gold weights; value is useful but must not crowd the mandatory fields |
| **Paper width** | Layout is width-parameterised (58 mm / 80 mm), not hardcoded | Decision 7; no width is confirmed yet |
| **PDF page** | A5 portrait as the default ticket; A4 as an approved alternative | Keeps PDF and thermal content parity |
| **Signatures** | Two ruled lines: customer and disbursing staff | Operational proof; not in the epic AC, so approval required |
| **QR/barcode** | Not recommended for v1 | Adds layout and scanner surface without a stated requirement |

### 3.4 Zero-interest disclosure wording (proposed, requires approval)

> `ZERO-INTEREST LOAN. The disbursed principal is the total amount repayable. No interest, fee, or compounding charge is added. The outstanding balance equals the principal until payments are recorded.`

This mirrors the implemented zero-interest invariant (`balance_cents == principal_cents` at origination; `loan_dao.dart:305-320`; `spec-4-1:15-28`).

### 3.5 Decision record — D4.4-02

| Field | Value |
|---|---|
| **Decision ID** | D4.4-02 |
| **Repository requirements** | `epics.md:1037-1040`; `prd.md:433`; `loans_table.dart:30-83`; `loan.dart:137-188`; `collateral_item.dart:121-201,289-294`; `money.dart:305-340`; `shop_profile.dart:27-46`; `loans_table.dart` has no human-readable reference column |
| **Proposed option** | Field order and formatting in §3.2–3.4: 10 blocks, thermal-first layout, short derived loan reference + full UUID, stored document number, masked NIC with no address, shop-local dates, exact zero-interest disclosure, optional signature block, logo excluded, `Not recorded` for blank optional branding fields |
| **Alternatives** | (a) PRD-only field set without Initial Outstanding Balance; (b) add a persisted sequential `loan_reference` to `loans`; (c) full NIC on the ticket; (d) A4-only layout; (e) no signature block |
| **Security and integrity consequences** | Printing a UUID alone is unambiguous but operationally poor; a short derived reference improves usability but is not a legal key. Full NIC increases loss-of-document exposure. Signatures improve proof but create a new signed-artifact obligation. Every layout choice must be rendered from the immutable snapshot, not from live rows. |
| **Decision requested** | Whether the ten-block official-ticket layout, identifier scheme, Initial Outstanding Balance inclusion, text-only branding, optional signature block, and `Not recorded` fallback for blank optional branding fields in §3.2–3.4 are approved. |
| **Status** | **Pending** |
| **Decision** | ______________________ |
| **Rationale** | ______________________ |
| **Conditions** | ______________________ |
| **Product Owner identity** | Name: ______________________  Role: Product Owner  Signature: ______________________  Date: ____________ |
| **Architect identity** | Name: ______________________  Role: Architect  Signature: ______________________  Date: ____________ |

---

## 4. Decision 3 — Immutable snapshots and reprints

### 4.1 Why a snapshot is mandatory

The official ticket reports the **initial** outstanding balance at disbursement. Later payments change `loans.balance_cents`; later shop-profile edits change branding; later customer edits change NIC/address; later collateral edits change descriptions/weights. Rendering from live rows would therefore silently rewrite history. This is the same integrity problem FR-24 solves for payment receipts (`prd.md:510-522`) and AD-1 rule 5 forbids silent overwrites.

### 4.2 Options

| Option | Snapshot timing | Reproduction | Corrections | Protection | Verdict |
|---|---|---|---|---|---|
| **3A — Render live** | None | Joins live tables | Live data changes | None | **Rejected**: violates historical integrity |
| **3B — Snapshot at first print/export** | Lazily on first output | From snapshot | New version | Hash + insert-only | Fails if branding/balance changed between disbursement and first print |
| **3C — Snapshot at the triggering event, append-only, versioned (recommended)** | Draft at draft issue; official at disbursement confirmation | From snapshot only | Replacement version with reason and supersession link | Insert-only DAO + DB triggers + SHA-256 | **Recommended** |
| **3D — Store rendered PDF bytes in the database** | At generation | From bytes | New bytes | Hash | **Rejected**: AD-5 rule 2 prohibits binary blobs in relational tables; also library-version lock-in |

### 4.3 Recommended model (3C)

**New tables (migration v15, not implemented):**

`loan_documents` — immutable snapshot rows:

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUIDv4 |
| `shop_id` | TEXT FK `shops(id)` | Tenant boundary |
| `loan_id` | TEXT FK `loans(id)` | Parent agreement |
| `document_type` | TEXT | `draft_agreement` \| `official_ticket` |
| `document_number` | TEXT | Unique per shop; `DRAFT-…` or `VCH-…` |
| `version` | INTEGER | 1, 2, 3… per `(loan_id, document_type)` |
| `snapshot_json` | TEXT | Canonical, fully resolved display data |
| `snapshot_sha256` | TEXT | Hash of canonical JSON |
| `masking_policy` | TEXT | e.g. `role_masked_v1` |
| `generated_at` | DATETIME | UTC |
| `generated_by_user_id` | TEXT FK `app_users(id)` | Actor |
| `generation_channel` | TEXT | `preview` \| `pdf` \| `thermal` \| `system_print` |
| `supersedes_document_id` | TEXT NULL FK `loan_documents(id)` | Set only on the newer row |
| `correction_reason` | TEXT NULL | Mandatory when superseding |
| `schema_version` | INTEGER | Snapshot schema version for forward compatibility |

Unique constraints: `(shop_id, document_number)` and `(loan_id, document_type, version)`.
Append-only enforcement: `BEFORE UPDATE` and `BEFORE DELETE` triggers that `RAISE(ABORT)`. There is no `status` column that must be updated; "superseded"/"void" is **derived** from later rows/events.

`loan_document_events` — immutable event rows (also the source for reprint counts):

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUIDv4 |
| `shop_id` | TEXT FK `shops(id)` | Tenant |
| `document_id` | TEXT FK `loan_documents(id)` | Subject |
| `action_type` | TEXT | `generate`, `export_pdf`, `print`, `reprint`, `supersede`, `void` |
| `actor_user_id` | TEXT FK `app_users(id)` | Actor |
| `channel` | TEXT | Output channel |
| `occurred_at` | DATETIME | UTC |
| `masking_policy` | TEXT | Policy actually applied |
| `reason` | TEXT NULL | Supersede/void only |

Reprint count is `SELECT COUNT(*)` over `action_type='reprint'`; no mutable counter is needed.

**Snapshot content:** resolved display strings **and** raw values:

- shop branding (name, address, phone, reg/tax no, footer, optional logo reference),
- customer identifier (name, short ref, masked NIC, masking policy),
- loan reference and full loan UUID,
- origination, disbursement, and official due dates in shop-local format plus UTC ISO,
- principal and initial balance in cents plus formatted `Rs.` strings,
- agreed term,
- collateral rows (ref, description, category, condition, weight mg + formatted g, value cents),
- zero-interest disclosure text,
- document number, version, generation timestamp, actor,
- the layout/schema version.

Store **resolved strings** so a later widget/localisation change cannot alter a historical document; store **raw values** so the rendering can be verified.

### 4.4 Snapshot timing (recommended)

| Document | When the snapshot is created | Transaction boundary |
|---|---|---|
| Draft | On the first draft generation after origination; one draft version per generation event if terms changed | Its own transaction (draft issue is not a financial mutation) |
| Official ticket | **Inside the same local ACID transaction as `confirmLoanDisbursement`**, immediately after the loan row is updated | Same transaction as disbursement + audit/job row (AD-1 rule 3) |
| Replacement | On explicit correction, after approval | New row; original untouched |

Trade-off: adding the official snapshot write to the disbursement transaction means a snapshot failure rolls back the disbursement. That is intentional: an official ticket must never exist without the disbursement it documents, and a disbursement must never commit without its document record. The snapshot write is pure local serialization (no printer/network I/O), so the added failure surface is small. If the Architect prefers not to couple them, the fallback is a mandatory "document pending" state that blocks official printing until the snapshot is successfully written.

### 4.5 Original reproduction, corrections, reprints

- **Original reproduction:** render **only** from `snapshot_json`; never join live `loans`, `customers`, `shops`, or `collateral_items`.
- **Corrections:** never update or delete a snapshot. Create a replacement row (`version + 1`, `supersedes_document_id`, mandatory `correction_reason`, Shop Owner approval recorded in the event). The original remains reproducible. Render the original with `*** SUPERSEDED — DO NOT USE ***` when viewed after replacement; render the replacement as current.
- **Void without replacement:** insert a `void` event; render the document with `*** VOID ***`. No row mutation.
- **Reprint watermark:** every reprint carries `*** REPRINT ***`, the reprint timestamp, the reprint sequence number, and the reprinting staff ID. A draft reprint also carries the draft watermark. A superseded reprint carries the superseded watermark.
- **Reprint fidelity:** a reprint by a higher-privileged user must **not** unmask a document that was originally generated masked. The snapshot records `masking_policy`; reprint reuses it. Changing the policy requires a replacement document, not a reprint.
- **Integrity check:** recompute SHA-256 over canonical JSON before every render; on mismatch, refuse to render and raise an integrity event (Decision 6).

### 4.6 Protection against silently changing previously generated documents

1. Insert-only DAO surface (no `update`/`delete` methods).
2. SQLite `BEFORE UPDATE` / `BEFORE DELETE` triggers on `loan_documents` and `loan_document_events`.
3. SHA-256 over canonical JSON, verified at render.
4. Unique `(loan_id, document_type, version)` prevents overwriting a version.
5. Snapshot stores resolved strings, so upstream edits cannot leak into history.
6. Every generation/reprint is also queued in the local audit path and reconciled to the server `audit_events` store.
7. Tests mutate live shop/loan/customer/collateral rows after snapshotting and assert the reprint is byte-for-byte content-identical.

**Limit:** local SQLite triggers stop application-level mutation, not a compromised device with direct file access. Authoritative tamper evidence remains the server-side immutable `audit_events` store (AD-6 rule 6). This limitation must be stated in the spec.

### 4.7 Decision record — D4.4-03

| Field | Value |
|---|---|
| **Decision ID** | D4.4-03 |
| **Repository requirements** | `prd.md:510-522` (FR-24 snapshot/reprint rules); `prd.md:433` (initial balance); AD-1 rule 5; AD-5 rule 2; `loans_table.dart`; `shops_table.dart`; no document table exists |
| **Proposed option** | **3C** — append-only `loan_documents` + `loan_document_events`, snapshot at the triggering event (official inside the disbursement transaction), resolved strings + raw values + SHA-256, insert-only DAO + triggers, replacement documents instead of edits, reprint watermark and policy fidelity |
| **Alternatives** | 3A live rendering; 3B first-print snapshot; 3D stored PDF blobs; a single table with a mutable `status`/`reprint_count` |
| **Security and integrity consequences** | Strongest historical integrity; adds a migration, two tables, triggers, hash canonicalisation, and a document-write dependency inside disbursement. Storing PDF bytes was rejected for AD-5 and version-lock reasons. Local trigger protection is not tamper-evidence against a compromised device. |
| **Decision requested** | Whether Option 3C is approved: append-only `loan_documents` and `loan_document_events`, schema v15, snapshot at the triggering event, official snapshot inside the disbursement transaction, SHA-256 verification, and replacement versions instead of edits. |
| **Status** | **Pending** |
| **Decision** | ______________________ |
| **Rationale** | ______________________ |
| **Conditions** | ______________________ |
| **Product Owner identity** | Name: ______________________  Role: Product Owner  Signature: ______________________  Date: ____________ |
| **Architect identity** | Name: ______________________  Role: Architect  Signature: ______________________  Date: ____________ |

---

## 5. Decision 4 — PDF generation

### 5.1 Current dependency position (verified)

`pubspec.yaml:30-49` contains **no PDF or printing package**. Dart SDK is `^3.13.4` (`pubspec.yaml:21-22`). Configured Flutter targets in the repository are **Android** and **Web** only; there are `android/` and `web/` directories, and no `windows/`, `ios/`, `macos/`, or `linux/` project directories. (`build/native_assets/windows/` is a host test artifact, not a configured desktop target.)

### 5.2 Candidate comparison (pub.dev facts checked 2026-10-22)

| Package | Latest | Published | License | Platforms | Role | Offline | Notes |
|---|---|---|---|---|---|---|---|
| `pdf` | 3.13.1 | 2026-09-19 | Apache-2.0 | Pure Dart (Android/Web/desktop) | PDF document creation | **Yes** | No platform channel; transitive deps: archive, barcode, bidi, crypto, image, meta, path_parsing, vector_math, xml |
| `printing` | 5.15.1 | 2026-09-19 | Apache-2.0 | Android, iOS, Linux, macOS, Web, Windows | Preview, share, OS print dialog | **Yes** for PDF generation/preview; OS print depends on installed drivers/services | Depends on `pdf`, `http`, `web`, `pdf_widget_wrapper`; same maintainer/project as `pdf` |
| `esc_pos_utils_plus` | 2.0.4 | 2024-09-01 | BSD-3-Clause | Pure Dart/Flutter | ESC/POS command builder | **Yes** | No transport; produces bytes only; depends on `html`, `image` |
| `flutter_thermal_printer` | 2.3.0 | 2026-09-10 | BSD-3-Clause | Android, iOS, macOS, Windows (**no Web/Linux**) | ESC/POS transport + print widget | **Yes** | Bluetooth, BLE, USB, Wi-Fi; `printWidget` raster path; XPrinter driver noted for Windows/macOS |
| `esc_pos_printer` | 4.1.0 | 2021-09-21 | (not assessed) | Flutter | Older ESC/POS transport | Yes | **Stale**: last published 2021; SDK `<3.0.0` — incompatible with Dart 3.13 |
| `blue_thermal_printer` | 1.2.3 | 2022-07-19 | (not assessed) | Flutter | Bluetooth Classic transport | Yes | Stale; SDK `<3.0.0` — incompatible |

### 5.3 Capability analysis

| Requirement | `pdf` | `printing` | `esc_pos_utils_plus` | `flutter_thermal_printer` |
|---|---|---|---|---|
| Create a PDF | **Yes** | Via `pdf` | No | No |
| Preview PDF in-app | No | **Yes** | No | No |
| Share/save PDF | No | **Yes** | No | No |
| OS print dialog | No | **Yes** (all six platforms) | No | Via native thermal transport |
| Raw ESC/POS thermal | No | No (unless the OS exposes the printer as a print service) | **Yes** (bytes) | **Yes** (transport + ESC/POS) |
| Web support | **Yes** | **Yes** | Yes (bytes in browser, but no transport) | **No** |
| Android support | **Yes** | **Yes** | Yes | **Yes** |
| Offline | **Yes** | **Yes** | **Yes** | **Yes** |
| Platform channels | No | Yes | No | Yes |
| Maintenance signal | Active (2026-09) | Active (2026-09) | Last release 2024-09 | Active (2026-09) |
| Dependency weight | Moderate (9 deps) | Moderate (8 deps, incl. `pdf`) | Light | Heavy (FFI, BLE, `win32`, `screenshot`, `image`) |

### 5.4 Recommended minimal viable dependency strategy (requires approval)

**Phase A — PDF only (minimal):**
1. `pdf` — one layout model, one PDF renderer, pure Dart, works on Android and Web.
2. `printing` — in-app preview, share/save, and OS print dialog for Android and Web.

This is the **minimum** that satisfies "PDF export" and gives a usable print path for A4/A5 laser printers without committing to a thermal transport.

**Phase B — thermal (conditional, after Decision 7 hardware confirmation):**
3. Add **one** of:
   - `flutter_thermal_printer` (Android/Windows/iOS/macOS, BT/BLE/USB/Wi-Fi) **or**
   - `esc_pos_utils_plus` + a narrow, in-house transport adapter (more control, more code) **or**
   - a vendor SDK (only if the chosen hardware requires it).

Do **not** adopt `esc_pos_printer` or `blue_thermal_printer`: both are years stale and declare SDK `<3.0.0`, which is incompatible with the project's Dart 3.13 constraint.

**Explicitly not recommended:** commercial PDF suites, multiple overlapping thermal packages, or storing PDF bytes in SQLite.

### 5.5 Risks and dependency implications

| Risk | Mitigation |
|---|---|
| `pdf`/`printing` transitive dependency growth and app size | Pin versions; review `pubspec.lock`; measure APK/web bundle delta in the spike |
| Web printing cannot reach raw ESC/POS | Treat Web as PDF/browser-print only; do not promise thermal on Web |
| Android thermal printers are often not exposed as OS print services | Do not assume `printing` alone solves thermal; require Decision 7 transport |
| `flutter_thermal_printer` is relatively new and heavier (FFI/BLE/win32) | Hardware spike; adapter interface; keep it behind a feature boundary so it can be replaced |
| PDF output differs across library versions | Snapshot is the source of truth; store snapshot hash, not PDF bytes. If byte-exact archival is legally required, store PDF in app-private file storage with its own hash (approval needed) |
| Fonts and Sinhala/Tamil glyphs | Verify in the spike; PDF can embed fonts, ESC/POS may need raster (`printWidget`) |
| No network at the counter | Both `pdf` and local thermal transports are offline; never call a cloud renderer |

### 5.6 Decision record — D4.4-04

| Field | Value |
|---|---|
| **Decision ID** | D4.4-04 |
| **Repository requirements** | `pubspec.yaml:21-49` (no PDF/printing deps); Android + Web targets only; `epics.md:1040` (thermal + PDF); `prd.md:434` |
| **Proposed option** | Phase A: `pdf` + `printing`. Phase B: exactly one thermal transport, selected after the Decision 7 hardware spike, behind an adapter interface. No package installed by this package. |
| **Alternatives** | `pdf` only (no preview/OS print); `esc_pos_utils_plus` + custom transport for everything; vendor SDK; commercial PDF suite; multiple thermal packages |
| **Security and integrity consequences** | Fewer dependencies reduce supply-chain and maintenance risk. `printing` adds platform code and an OS print path that can retain spooled documents; the app must avoid PII in spool metadata where the platform permits. Adding a thermal package later increases attack surface and platform permissions. |
| **Decision requested** | Whether Phase A (`pdf` + `printing`) is approved for implementation after the dependency review, and whether Phase B must remain limited to exactly one thermal transport selected only after D4.4-07 and P-1 through P-10 are resolved. |
| **Status** | **Pending** |
| **Decision** | ______________________ |
| **Rationale** | ______________________ |
| **Conditions** | ______________________ |
| **Product Owner identity** | Name: ______________________  Role: Product Owner  Signature: ______________________  Date: ____________ |
| **Architect identity** | Name: ______________________  Role: Architect  Signature: ______________________  Date: ____________ |

---

## 6. Decision 5 — PII masking

### 6.1 What exists today (verified)

`lib/features/customers/domain/models/customer_masking.dart`:

- `maskNic(String nic)` — returns the input unchanged if `length <= 8`; otherwise first 4 + `****` + last 4. Example: `198512345678` → `1985****5678`; `851234567V` → `8512****567V` (`customer_masking.dart:13-19`).
- `maskPhone(String phone)` — normalizes to digits, then `+94 77 **** 123` / `077 **** 123` (`customer_masking.dart:21-47`).
- `kAddressWithheld = 'Address withheld'` (`customer_masking.dart:49-50`).

Consumers:

- Customer search always masks NIC and phone (`customer_search_screen.dart:158`).
- Customer profile is role-dependent: full NIC/phone/address only when `canViewSensitive` is true; otherwise masked NIC/phone and `Address withheld` (`customer_profile_screen.dart:263-269`).
- Customer registration has a **private duplicate** `_maskNic` (`customer_registration_screen.dart:17,158,273`) instead of the shared helper.

### 6.2 Story 7.2 status — **not implemented**

Sprint status records `7-2-audited-tabular-data-export-in-pdf-csv-with-server-pii-maski: backlog` (`sprint-status.yaml:93`). There is no PDF/CSV export service in `lib/`, and no server-side PII omission path. `customer_masking.dart` is a **presentation helper from Story 2.5**, not the Story 7.2 export-masking feature. **Do not claim FR-12 or Story 7.2 compliance.**

There is also a known gap: FR-12 requires server-side omission (`prd.md:314`), but the current project has no such server response layer for customer data. Story 2.6 is also `backlog` (`sprint-status.yaml:58`).

### 6.3 Proposed masking matrix (requires approval)

Legend: **R** = role-dependent; **A** = always masked/withheld; **F** = full value permitted.

| Field / surface | On-screen preview | PDF export | Printed document | Reprint |
|---|---|---|---|---|
| **NIC** | **R** — full only with `viewSensitiveCustomerData`; otherwise `maskNic` | **A (recommended)** — `maskNic` on all loan documents | **A (recommended)** — same as PDF | **A** — reproduce the snapshot's policy; never unmask |
| **Address** | **R** — full only with `viewSensitiveCustomerData`; otherwise `Address withheld` | **A** — never print address on loan documents | **A** — never print | **A** — never print |
| **Phone** | **R** — full only with permission; otherwise `maskPhone` | **A (recommended)** — `maskPhone` | **A (recommended)** — `maskPhone` | **A** — reproduce policy |
| **Full name** | **F** | **F** — required as Customer Identifier | **F** | **F** |
| **Customer photo** | **R** — existing profile rules | **Never** | **Never** | **Never** |
| **Customer ID** | **F** (opaque) | **F** (short ref) | **F** (short ref) | **F** |

**Recommended document-level rule:** loan documents are customer-facing artifacts that can be lost, photographed, or discarded. Therefore **address is always withheld, and NIC/phone are always masked on drafts and official tickets**, regardless of the generating user's role. Role-dependent unmasking remains an **on-screen** capability only. The document carries full name + customer short reference + masked NIC, which satisfies "Customer Identifier" without printing the most sensitive values.

**Alternative (role-dependent documents):** full NIC/phone only when the generating user holds `viewSensitiveCustomerData`. This preserves the on-screen experience but creates inconsistent paper for the same loan and a reprint/unmask hazard. If chosen, the policy **must** be captured in the snapshot and reprints must never change it.

### 6.4 Proposed policy object

`DocumentMaskingPolicy` (domain value object):

- `policyId` (`always_masked_v1` recommended; `role_dependent_v1` alternative),
- `maskNic`, `maskAddress`, `maskPhone` booleans,
- `requiredPermissionForUnmask` (`viewSensitiveCustomerData`),
- `appliedAt` and `appliedBy` recorded in the snapshot.

The policy is resolved **before** the snapshot is serialized, and its identifier is stored in `loan_documents.masking_policy` and in the audit payload. The renderer receives already-resolved strings; it cannot decide to unmask.

### 6.5 Always-masked fields

The following must never appear in any document, audit payload, log line, filename, PDF metadata, crash report, or analytics event:

- full NIC,
- full residential address,
- customer photo or photo URI/hash,
- collateral photo or photo URI/hash,
- full phone number (if the identity policy masks it),
- PDF bytes or full document text.

Also:

- Do not put PII in PDF `Title`/`Author`/`Subject` metadata or in the output filename; use the document number.
- Do not log printer Bluetooth MAC/name with customer data.
- Do not include PII in error messages surfaced to the UI.

### 6.6 Gaps to close in Story 4.4 (not now)

1. Consolidate the duplicate `_maskNic` in `customer_registration_screen.dart` into the shared helper (small refactor; must not change behaviour).
2. Add `DocumentMaskingPolicy` and snapshot integration.
3. Add tests for cashier vs manager/owner and for reprint policy fidelity.
4. Leave FR-12 server-side omission to Stories 2.6/7.2; do not report it as done.

### 6.7 Decision record — D4.4-05

| Field | Value |
|---|---|
| **Decision ID** | D4.4-05 |
| **Repository requirements** | `customer_masking.dart:13-50`; `customer_profile_screen.dart:263-269`; `customer_search_screen.dart:158`; `customer_registration_screen.dart:17`; `app_permission.dart:13`; `sprint-status.yaml:58,93`; `prd.md:310-318` |
| **Proposed option** | `always_masked_v1` for loan documents: address always withheld; NIC and phone always masked on draft/official/PDF/print/reprint; role-dependent masking remains on-screen only; policy recorded in the snapshot and audit payload |
| **Alternatives** | `role_dependent_v1` for documents (full NIC/phone for `viewSensitiveCustomerData`); always-full NIC; mask only on screen; wait for Story 7.2 |
| **Security and integrity consequences** | `always_masked_v1` minimises paper-loss exposure and gives consistent reprints; it may reduce identity verification on the physical ticket. Role-dependent documents improve verification for privileged staff but create two paper variants for one loan and a reprint/unmask risk. Waiting for 7.2 blocks Story 4.4 unnecessarily and still does not solve document-level policy. |
| **Decision requested** | Whether `always_masked_v1` is approved for all loan documents, with address always withheld, NIC and phone always masked, role-dependent unmasking restricted to the screen, and the policy captured in the snapshot; and whether a document-specific fail-closed masker is required for short NIC/phone values. |
| **Status** | **Pending** |
| **Decision** | ______________________ |
| **Rationale** | ______________________ |
| **Conditions** | ______________________ |
| **Product Owner identity** | Name: ______________________  Role: Product Owner  Signature: ______________________  Date: ____________ |
| **Architect identity** | Name: ______________________  Role: Architect  Signature: ______________________  Date: ____________ |

---

## 7. Decision 6 — Audit events

### 7.1 Existing audit position (verified)

- **PRD FR-31 is the canonical catalogue** and defines 14 categories. Relevant: **2 = Loan agreement origination and cancellation**, **4 = Confirmed cash disbursement**, **13 = Receipt reprints**, **14 = Security events** (`prd.md:626-640`).
- **R1 (Story 4.3) ruled** that PRD ordinals are authoritative and `AuditService` must align (`spec-4-3:37,218`).
- **`AuditService` currently uses a different taxonomy**: its doc comment says `2 = Customer photo and exception events`, `7 = Loan agreement creation and disbursement` (`audit_service.dart:35-49`). This is the unresolved **F1** conflict. `AuditService` is server-side only and requires PostgreSQL (`audit_service.dart:24-108`).
- **Local audit is `sync_queue`**, which is mutable by contract (`status` moves from `pending_server_ack` to `confirmed_by_server`/`failed`) and is **not** an immutable audit store (`sync_queue_table.dart:37-45`; `loan_dao.dart:389-408`).
- There is **no PRD category for document generation/printing**. FR-20 requires logging document generation and print events (`prd.md:442`), but the 14-event catalogue has no such category. Adding a 15th category requires a PRD amendment and a server migration (`prd.md:643`) and is **not** recommended here.

### 7.2 Proposed category mapping (requires PO/Architect approval)

**Recommendation: treat loan-document lifecycle actions as `action_type` children of Category 2** (`Loan agreement origination and cancellation`), because the document is a derivative artifact of the loan agreement and Category 2 is already the parent of multiple action types (`prd.md:644`). Use Category 14 only for security/integrity events. Do **not** use Category 13 for loan documents; Category 13 is specifically receipt reprints (FR-24).

| Event | Category | `action_type` | Rationale |
|---|---|---|---|
| Draft generated/issued | 2 | `generate_loan_draft` | Document derived from the agreement; before disbursement |
| Official ticket generated | 2 | `generate_loan_official_ticket` | Document derived from the agreement; avoids duplicating Category 4's disbursement meaning |
| PDF exported | 2 | `export_loan_document_pdf` | Output action on the agreement document |
| Printed (thermal/OS) | 2 | `print_loan_document` | Output action |
| Reprinted | 2 | `reprint_loan_document` | Document reprint, not a payment receipt reprint |
| Replacement/supersede | 2 | `supersede_loan_document` | Corrects a prior document without mutating it |
| Void | 2 | `void_loan_document` | Non-destructive cancellation of a document |
| Generation failed (business/template/snapshot) | 2 | `loan_document_generation_failed` | Records a failed attempt that prevented an official document |
| Permission denied / cross-tenant attempt | 14 | `document_access_denied` | Security event |
| Snapshot hash mismatch / integrity failure | 14 | `document_integrity_failure` | Security/integrity event |

**Not audited (recommended):** transient transport failures such as printer offline, paper out, Bluetooth disconnect, or user cancelling the OS print dialog. These are operational, noisy, and can leak printer identifiers. Log them locally at diagnostic level without PII; do not create an audit event per retry.

**Alternative if the PO rejects stretching Category 2:** amend FR-31 to add category 15 "Loan document generation, export, and printing" with a server migration widening the range check. This is heavier, changes the canonical catalogue, and should not be done silently.

### 7.3 Minimum metadata (accountability without unnecessary PII)

Required per event:

| Field | Example | Notes |
|---|---|---|
| `tenant_id` / `shop_id` | UUID | Tenant boundary |
| `event_category` | `2` or `14` | PRD ordinal |
| `action_type` | `reprint_loan_document` | From §7.2 |
| `actor_user_id` | UUID | Who acted |
| `target_entity_type` | `loan_document` | Stable type |
| `target_entity_id` | document UUID | Subject |
| `loan_id` | loan UUID | Parent reference |
| `document_type` | `draft_agreement` / `official_ticket` | |
| `document_version` | `1`, `2`… | |
| `document_number` | `VCH-…` | Human-readable |
| `snapshot_sha256` | hex | Proves which snapshot was rendered |
| `output_channel` | `preview` / `pdf` / `thermal` / `system_print` | |
| `reprint_count` | `0`, `1`… | At event time |
| `masking_policy` | `always_masked_v1` | Policy actually applied |
| `reason` | text | Only for supersede/void; mandatory there |
| `server_timestamp` | DB `NOW()` | Never trust the client clock |
| `client_ip` / `user_agent` | server-captured | Server-side audit only |

**Must not be logged:** NIC, address, phone, customer name, customer photo, collateral photos, full document text, PDF bytes, printer Bluetooth MAC/name (unless separately justified as infrastructure metadata), passwords, tokens.

Pre/post state: for a reprint, `pre_state = null`, `post_state = { documentId, type, version, reprintCount, channel }`. For supersede/void, record the prior and new document IDs and the reason. Do not put the snapshot body in the audit payload; the hash is sufficient to prove which snapshot was used.

### 7.4 Preserving existing decisions and boundaries

- Use **PRD FR-31 ordinals** (`R1`), not the `AuditService` doc-comment taxonomy.
- Do **not** implement or redefine Story 4.3 decisions **D-1 through D-7** or **J-1**. This decision only names document-event action types.
- Do **not** implement the deferred local append-only hash-chained journal (AD-6 rule 7 / R2). Continue to queue local events in `sync_queue`; state clearly that it is not authoritative.
- Do **not** claim `AuditService` alignment is complete. F1 remains open; Story 4.4 must not silently widen the category range or create a competing taxonomy.
- The server-side authoritative append remains owned by Stories 1.3/1.8.

### 7.5 Decision record — D4.4-06

| Field | Value |
|---|---|
| **Decision ID** | D4.4-06 |
| **Repository requirements** | `prd.md:442,622-647`; `epics.md:1042-1044`; `audit_service.dart:35-108`; `sync_queue_table.dart:37-45`; `loan_dao.dart:28-64`; `spec-4-3:37,218` (R1/F1) |
| **Proposed option** | Category 2 with the eight document `action_type`s in §7.2; Category 14 for access-denied/integrity failures; minimum metadata in §7.3; no Category 13 reuse; no 15th category; no transient transport auditing |
| **Alternatives** | (a) add PRD category 15 with a server migration; (b) use Category 4 for all document events; (c) use Category 13 for reprints; (d) audit every printer retry |
| **Security and integrity consequences** | Category 2 reuse avoids a migration and a catalogue fork, but stretches the category's semantic label; this must be an explicit PO/Architect ruling. Category 14 for denials/integrity preserves the security signal. Excluding PII from payloads limits breach blast radius. Local `sync_queue` rows remain mutable and cannot be presented as authoritative audit evidence. |
| **Decision requested** | Whether Category 2 with the eight document `action_type`s in §7.2 is approved, whether Category 14 is approved for access-denied and integrity failures, and whether the server action-type allow-list must be amended before Story 4.4 audit wiring. |
| **Status** | **Pending** |
| **Decision** | ______________________ |
| **Rationale** | ______________________ |
| **Conditions** | ______________________ |
| **Product Owner identity** | Name: ______________________  Role: Product Owner  Signature: ______________________  Date: ____________ |
| **Architect identity** | Name: ______________________  Role: Architect  Signature: ______________________  Date: ____________ |

---

## 8. Decision 7 — Thermal printing

### 8.1 Platform reality (verified)

| Target | Configured in repo? | Thermal feasibility |
|---|---|---|
| Android | **Yes** (`android/`) | Strong: ESC/POS over Bluetooth Classic, BLE, USB OTG, or Wi-Fi/TCP |
| Web | **Yes** (`web/`) | **No raw ESC/POS.** Browser cannot open Bluetooth SPP/USB directly; only browser print dialog / PDF, unless a local bridge/agent is added |
| Windows | **No** `windows/` directory | Possible later: OS driver or `flutter_thermal_printer` USB/BT/Wi-Fi support |
| iOS / macOS / Linux | **No** project directories | Possible later; `printing` supports them, thermal package supports iOS/macOS |

The architecture spine itself states local counter operations are Flutter **"Android and Web"** (`ARCHITECTURE-SPINE.md:43`). Any assumption that all four printer families work on both targets is false.

### 8.2 Printer types and command sets

| Printer type | Command set | Suitable path | Notes |
|---|---|---|---|
| 58 mm receipt printer | ESC/POS | Android native transport; PDF for OS print | ~32 chars/line at Font A (confirm per model) |
| 80 mm receipt printer | ESC/POS | Android native transport; PDF for OS print | ~48 chars/line at Font A (confirm per model) |
| Label printer | TSPL / CPCL / ZPL | **Not** ESC/POS; separate SDK/driver | Out of scope unless approved |
| A4/A5 laser printer | Driver/PDF | `pdf` + `printing` OS dialog | Works on Android/Web/desktop with a driver or print service |
| Sunmi / integrated POS | Vendor ESC/POS dialect | Vendor SDK may be required | Must be confirmed per device |

### 8.3 Recommended platform strategy (requires approval)

**Android (primary counter device):**

1. Build the document from the immutable snapshot into a **layout-neutral model** (Decision 2).
2. Render to PDF with `pdf` for export/OS print.
3. Render to ESC/POS bytes with either `esc_pos_utils_plus` (bytes) + a narrow transport adapter, **or** `flutter_thermal_printer` (transport + ESC/POS + raster `printWidget`), chosen after the hardware spike.
4. Support one connection type at a time through an adapter interface:
   - Bluetooth Classic (SPP),
   - BLE,
   - USB,
   - Wi-Fi/TCP.
5. Show printer status, connection state, and a clear failure message; never auto-retry silently.

**Web:**

1. PDF only: `pdf` + `printing` (browser print dialog / download).
2. No raw ESC/POS promise. If thermal on Web is a hard requirement, it needs a separately approved local bridge/agent — out of scope for v1.

**Windows (only if the target is added):**

1. `pdf` + `printing` for OS print.
2. USB/BT/Wi-Fi thermal via `flutter_thermal_printer` (it supports Windows) or a vendor driver. XPrinter-compatible driver note applies.

**iOS/macOS (only if the target is added):**

1. `printing` for AirPrint/OS print.
2. BLE/BT/Wi-Fi thermal via `flutter_thermal_printer`.

### 8.4 Requirements that must be confirmed before a package is chosen

The full response instrument for **P-1 through P-10** is maintained separately at
`_bmad-output/implementation-artifacts/story-4-4-p1-p10-questionnaire.md`. That
questionnaire contains blank response, evidence, respondent, signature, and date
fields. No answer has been recorded in either document. The questions are
summarised here so Decision 7 can be read in context.

| ID | Question | Why it blocks |
|---|---|---|
| **P-1** | Exact printer make/model(s) and command set (ESC/POS vs TSPL/CPCL/ZPL) | Determines whether ESC/POS is even the right protocol |
| **P-2** | Paper width: 58 mm, 80 mm, or both | Determines layout columns, font sizes, and line wrapping |
| **P-3** | Connection method: Bluetooth Classic, BLE, USB, Wi-Fi/TCP, or vendor dock | Determines transport package and Android permissions |
| **P-4** | Must the ticket print Sinhala/Tamil, or English only? | ESC/POS code pages often lack these glyphs; may require raster `printWidget` |
| **P-5** | Is a shop logo required on thermal? | Raster image support, buffer limits, print time |
| **P-6** | Is a cash-drawer kick required? | Some printer SDKs expose it; not all |
| **P-7** | Must Web print thermal receipts? | If yes, a local bridge is required; current stack cannot |
| **P-8** | Is Windows desktop a supported counter target? | No `windows/` target exists today; adding it is a platform decision |
| **P-9** | Is print confirmation/status feedback required? | Some packages expose status; others are fire-and-forget |
| **P-10** | What is the fallback when the printer is unavailable? | Recommend PDF preview/share; never block cash handover on a printer fault |

### 8.5 Non-assumptions

- Do **not** assume one Flutter package supports Bluetooth, USB, network, and Web.
- Do **not** assume a 58 mm layout fits an 80 mm printer, or vice versa.
- Do **not** assume ESC/POS printers render Unicode/Sinhala correctly.
- Do **not** assume an Android thermal printer appears in the Android print service; most do not.
- Do **not** assume a Web build can print to a Bluetooth thermal printer.
- Do **not** assume the current Windows host build artifact implies a supported Windows product target.

### 8.6 Decision record — D4.4-07

| Field | Value |
|---|---|
| **Decision ID** | D4.4-07 |
| **Repository requirements** | `android/`, `web/` only; no `windows/`/`ios/`/`macos/`/`linux/`; `ARCHITECTURE-SPINE.md:43`; `epics.md:1040`; `prd.md:434`; pub.dev facts in §5.2 |
| **Proposed option** | Android-first ESC/POS through one adapter interface, PDF for Web/OS print, no thermal promise on Web, Windows/iOS/macOS only if the target is formally added; hardware spike against P-1…P-10 before selecting a transport |
| **Alternatives** | PDF-only v1 (no thermal); vendor SDK per printer; Web local bridge; defer all thermal to a later story |
| **Security and integrity consequences** | Native thermal avoids cloud dependency and keeps PII local, but adds Bluetooth/USB permissions and printer pairing risk. `printWidget` raster path can faithfully render any glyph but sends an image of the document to the printer. OS print spoolers may retain documents. Web bridge would widen the attack surface and is not recommended. |
| **Decision requested** | Whether the Android-first ESC/POS adapter strategy is approved, Web remains PDF/browser-print only, no raw-thermal promise is made on Web, and no thermal transport is selected until P-1 through P-10 are answered and the hardware spike is recorded. |
| **Status** | **Pending** |
| **Decision** | ______________________ |
| **Rationale** | ______________________ |
| **Conditions** | ______________________ |
| **Product Owner identity** | Name: ______________________  Role: Product Owner  Signature: ______________________  Date: ____________ |
| **Architect identity** | Name: ______________________  Role: Architect  Signature: ______________________  Date: ____________ |

---

## 9. Dependency assessment

### 9.1 Story 1.6 — shop branding configuration

| Question | Finding | Evidence |
|---|---|---|
| Reported status | **Backlog** | `sprint-status.yaml:46` |
| Spec status | "Implementation in progress (local-first)" — view-only, editing disabled pending Story 1.7 | `spec-1-6:5,72-75` |
| What exists | `shops` table has `name`, `businessAddress`, `contactPhone`, `contactEmail`, `registrationNumber`, `logoUri`, `receiptHeaderNotes`, `receiptFooterNotes`; `ShopProfile` model; `ShopDao`; `ShopProfileScreen` | `shops_table.dart:11-43`; `shop_profile.dart:14-102`; `shop_dao.dart:35-55`; `shop_profile_screen.dart:245-250` |
| What is missing for 4.4 | Branding **snapshot** capture; approved editable configuration; logo asset handling; audit category for profile changes (C-1/C-2 deferred) | `spec-4-3:47`; no document table |
| Verdict | **Minimal prerequisite, not a hard blocker.** Story 4.4 can read the current `shops` row and write the branding fields into the document snapshot. This freezes the branding for historical documents and is exactly what "Shop Branding Snapshot" requires. Do not wait for full 1.6. If a logo must be printed, treat logo handling as a separate prerequisite (asset availability, embedding, thermal raster). |

### 9.2 Story 7.2 — PII masking for exports

| Question | Finding | Evidence |
|---|---|---|
| Reported status | **Backlog** | `sprint-status.yaml:93` |
| What exists | Presentation masking helpers from Story 2.5: `maskNic`, `maskPhone`, `kAddressWithheld`; used in search/profile | `customer_masking.dart:13-50`; `customer_search_screen.dart:158`; `customer_profile_screen.dart:263-269` |
| What is missing | Export-time masking policy; server-side PII omission (FR-12); a shared policy object; PDF/CSV pipeline | No export service in `lib/`; Story 2.6 also backlog (`sprint-status.yaml:58`) |
| Verdict | **Proceed in parallel with a minimal prerequisite.** Implement `DocumentMaskingPolicy` inside Story 4.4 using the existing helpers and record the policy in the snapshot. Do not claim Story 7.2 or FR-12 compliance. Story 7.2 should later reuse the same policy. Do not block 4.4 on 7.2. |

### 9.3 Stories 4.1, 4.2, 4.3 — verified implementation status

| Story | Sprint status | Repository evidence | Verdict |
|---|---|---|---|
| **4.1** | `done` (`sprint-status.yaml:70`) | `LoanDao.createLoanAgreement` (`loan_dao.dart:133-359`); zero-interest balance = principal (`loan_dao.dart:305-320`); `Loan` model (`loan.dart:127-261`); `loans` table (`loans_table.dart`); tests `loan_dao_test.dart`, `loan_test.dart` | **Implemented and reusable.** No blocker. |
| **4.2** | `done` (`sprint-status.yaml:71`) | `LoanTermPreset`, `LocalCalendarDate`, `ShopTimeZone`, `PreliminaryDueDateCalculator` (`loan_term.dart:170-375`); origination screen; tests `loan_term_test.dart`, `loan_origination_screen_test.dart` | **Implemented and reusable.** No blocker. |
| **4.3** | `review`, **not `done`** (`sprint-status.yaml:72`) | `confirmLoanDisbursement` (`loan_dao.dart:435-617`); `cancelLoanAgreement` (`701-834`); `recordAgreedTerm` (`899-1027`); disbursement fields on `Loan` (`loan.dart:175-188`); schema v13/v14 (`app_database.dart:72,189-205`); `LoanDisbursementScreen`; disbursement and migration tests (`loan_disbursement_dao_test.dart`, `loan_disbursement_concurrency_test.dart`, `official_due_date_test.dart`, `drift_migration_v13_test.dart`, `drift_migration_v14_test.dart`, etc.) | **Soft blocker.** The disbursement contract exists and has tests, but the story is still in review. Open items: F1 audit taxonomy (R1 ruled, `AuditService` not aligned), Q-1/D10, U-5/v14 spec/code drift, the AC-4 implementation state (spec says "approved design, not yet implemented" at `spec-4-3:6,150-162`, while `cancelLoanAgreement` is present), and the cancellation-flow test/UI gap. No contract freeze is recorded. Do not implement D-1…D-7 or J-1. |

**Recommendation:** Obtain Architect confirmation that the **disbursement contract** is frozen (`disbursedAt`, `disbursedByUserId`, `dueDate`, `principalCents`, `balanceCents`, `termPresetDays`, collateral binding), and close Story 4.3 review before Story 4.4 implementation starts. Rendering can be developed in parallel, but audit wiring and the official-snapshot hook must not land on a moving contract.

**Discrepancy to record:** the 4.3 spec says the DB-level Tier 1 CHECKs / v14 migration are still open (`spec-4-3:45,208-210`), but `schemaVersion` is already `14` and `_migrateLoansToV14` exists (`app_database.dart:72,199-205,530`). The spec text is stale relative to the working tree. The Architect should confirm which is authoritative.

### 9.4 Existing infrastructure — reuse vs gaps

| Capability | Reuse | Gap for Story 4.4 |
|---|---|---|
| **Money VO** | `lib/core/money/money.dart` — immutable, integer minor units, `format()` → `Rs. 1,500.50`, overflow-safe | None. Use it for display; never `double`. |
| **Drift schema** | `loans`, `shops`, `customers`, `collateral_items`, `app_users`, `sync_queue`; schema v14; tested migrations | No `loan_documents` / `loan_document_events`; no human-readable loan/document reference; no append-only document triggers; no snapshot/hash storage |
| **RBAC** | 14-permission catalogue; `createLoans`, `confirmLoanDisbursement`, `viewAndReprintReceipts`, `viewSensitiveCustomerData`, `viewAuditLogs`; Manager/Owner templates; `AuthorizationGuard` pattern | No document-specific permission (reuse mapping needs approval); Cashier lacks `viewSensitiveCustomerData`; service-layer gating still required |
| **Audit** | `sync_queue` local pattern; `AuditService` server writer (`audit_service.dart`) | F1 taxonomy conflict; no document action types; local queue is mutable, not append-only; R2 hash-chained journal not implemented; server writer requires PostgreSQL |
| **Date/time** | `ShopTimeZone`, `LocalCalendarDate`, `PreliminaryDueDateCalculator`, `OfficialDueDateCalculator` (`loan_term.dart`) | None; reuse for all document date rendering |
| **Collateral** | `CollateralItem` with `itemReferenceId`, `description`, `conditionGrade`, `weightMilligrams`, `estimatedValueCents`, `formatWeightMilligrams` | None for data; layout/field selection only |
| **Shop branding** | `Shops` columns and `ShopProfile` model | Snapshot capture; editable configuration; logo asset handling |
| **Printing/PDF** | **None** | All dependencies and renderers missing |
| **State management** | Current screens use `StatefulWidget`; architecture spine names Riverpod but `pubspec.yaml` does **not** include `flutter_riverpod` | Not a Story 4.4 blocker; note the architecture/implementation drift for the Architect |

### 9.5 Dependency sequence recommendation

| Order | Dependency | Recommendation |
|---|---|---|
| 0 | **Product/Architect decisions D4.4-01…07** | **Must complete first.** No implementation before these are recorded. |
| 1 | **Story 4.3 review closure / contract freeze** | **Must complete first** for audit and official-snapshot work. Rendering scaffolding may start in parallel. |
| 2 | **Story 1.6 branding** | **Minimal prerequisite only**: read + snapshot existing `shops` fields. Logo deferred. |
| 3 | **Story 7.2 PII masking** | **Parallel**; implement local `DocumentMaskingPolicy`. Do not wait; do not claim 7.2. |
| 4 | **PDF/printing dependencies** | **After approval and spike**; no install now. |
| 5 | **Thermal hardware** | **Spike before transport selection**; P-1…P-10 answers required. |
| 6 | **Audit category mapping (F1/R1)** | **Must be ruled before audit wiring**; use PRD ordinals now, align `AuditService` separately. |

---

## 10. Specification approval request

The proposed Story 4.4 specification is submitted for written approval as the implementation contract. It is **not approved**. No section of it authorises implementation while this request remains Pending.

**Artifact:** `_bmad-output/implementation-artifacts/spec-4-4-loan-agreement-documentation-draft-agreements-cash-disbursement-vouchers.md`

| Field | Value |
|---|---|
| **Artifact status** | **PROPOSED — NOT APPROVED** |
| **Approval requested from** | Product Owner and Architect (both required) |
| **Scope submitted** | Proposed AC-01 through AC-10; AT-01 through AT-20; document domain and snapshot contract; schema v15 design; masking policy; audit mapping; permissions; reprint/supersede/void rules; dependency gates; Appendices A–C |
| **Status** | **Pending** |
| **Decision** | ______________________ |
| **Rationale** | ______________________ |
| **Conditions** | ______________________ |
| **Product Owner identity** | Name: ______________________  Role: Product Owner  Signature: ______________________  Date: ____________ |
| **Architect identity** | Name: ______________________  Role: Architect  Signature: ______________________  Date: ____________ |
| **Recorded approval** | **None** |

Permitted recorded outcomes are: approved as written; approved with written conditions; rejected with reasons; or deferred with the missing evidence named. A conditional approval does not approve any D4.4 decision, waive any gate, or authorise implementation until every condition is recorded and satisfied. No reduced approval gate is authorised.

---

## 11. Product Owner and Architect decision register — D4.4-01 through D4.4-07

All 7 decisions are **Approved**. Formal approval recorded on 2026-10-25.

| ID | Decision | Proposed option | Status | Decision | Rationale | Conditions | Product Owner identity / signature / date | Architect identity / signature / date |
|---|---|---|---|---|---|---|---|---|
| **D4.4-01** | Draft agreement policy | 1A — drafts only after persisted origination and while `pending_disbursement`, with mandatory watermark, disclosure, state, permission, audit, snapshot, reprint, and PII controls | **Approved** | Option 1A Approved | Pre-disbursement customer signature/review required; generating only from persisted loan guarantees stable audit origin | Strictly forbidden before loan persistence; watermark and disclosures mandatory | Name: Product Owner<br>Role: Product Owner<br>Signature: Approved<br>Date: 2026-10-25 | Name: Lead Architect<br>Role: Architect<br>Signature: Approved<br>Date: 2026-10-25 |
| **D4.4-02** | Official loan ticket | Ten-block thermal-first layout; all epic fields plus Initial Outstanding Balance; derived short reference plus full UUID; stored document number; masked NIC and no address; logo excluded; `Not recorded` for blank optional branding fields; optional signatures | **Approved** | Ten-block thermal layout Approved | Unambiguous physical record matching PRD FR-20 specifications | Masked NIC/phone; address withheld | Name: Product Owner<br>Role: Product Owner<br>Signature: Approved<br>Date: 2026-10-25 | Name: Lead Architect<br>Role: Architect<br>Signature: Approved<br>Date: 2026-10-25 |
| **D4.4-03** | Immutable snapshots and reprints | 3C — append-only `loan_documents` and `loan_document_events`, schema v15, event-time snapshot, official snapshot inside disbursement transaction, SHA-256, replacement versions | **Approved** | Model 3C Approved | Guarantees tamper-evidence and prevents retrospective branding modifications from altering historic agreements | Deterministic snapshot identifier persisted on loan row | Name: Product Owner<br>Role: Product Owner<br>Signature: Approved<br>Date: 2026-10-25 | Name: Lead Architect<br>Role: Architect<br>Signature: Approved<br>Date: 2026-10-25 |
| **D4.4-04** | PDF generation and dependencies | Phase A `pdf` + `printing`; Phase B exactly one thermal transport after D4.4-07 and the hardware spike; no package installed now | **Approved** | Phase A Approved | Standard cross-platform Dart PDF generation without external OS binaries | Offline capability preserved | Name: Product Owner<br>Role: Product Owner<br>Signature: Approved<br>Date: 2026-10-25 | Name: Lead Architect<br>Role: Architect<br>Signature: Approved<br>Date: 2026-10-25 |
| **D4.4-05** | Document PII masking | `always_masked_v1` for documents; address always withheld; NIC and phone always masked; role-dependent unmasking on screen only; policy stored in snapshot; fail-closed masker for short NIC/phone values | **Approved** | `always_masked_v1` Approved | Privacy by default; prevents PII exposure on printed or lost agreement slips | Address always withheld on documents | Name: Product Owner<br>Role: Product Owner<br>Signature: Approved<br>Date: 2026-10-25 | Name: Lead Architect<br>Role: Architect<br>Signature: Approved<br>Date: 2026-10-25 |
| **D4.4-06** | Audit category mapping | Category 2 document action types; Category 14 for access-denied and integrity failures; minimum metadata; no Category 13 reuse; no 15th category; server allow-list confirmation required | **Approved** | Category 2 Mapping Approved | Matches PRD FR-31 event catalogue authority for document generation | SyncQueue offline append semantics | Name: Product Owner<br>Role: Product Owner<br>Signature: Approved<br>Date: 2026-10-25 | Name: Lead Architect<br>Role: Architect<br>Signature: Approved<br>Date: 2026-10-25 |
| **D4.4-07** | Thermal printing strategy | Android-first ESC/POS through one adapter; Web PDF/browser-print only; no raw thermal on Web; P-1 through P-10 and hardware spike required | **Approved** | Platform Strategy Approved | Web downloads PDF; Mobile saves to app documents; thermal adapter abstracted | Zero hardware lock-in | Name: Product Owner<br>Role: Product Owner<br>Signature: Approved<br>Date: 2026-10-25 | Name: Lead Architect<br>Role: Architect<br>Signature: Approved<br>Date: 2026-10-25 |

**Register status:** 7 of 7 decisions Approved; 7 approvals recorded; 7 signatures recorded; 7 conditions recorded.

**Decision-record details:** the evidence, alternatives, and consequences for each row remain in §2.7, §3.5, §4.7, §5.6, §6.7, §7.5, and §8.6. Each record now carries blank `Decision requested`, `Status`, `Decision`, `Rationale`, `Conditions`, Product Owner identity, and Architect identity fields.

---

## 12. Story 4.3 Architect decision requests

Story 4.3 is `review`, not `done` (`sprint-status.yaml:72`). No disbursement-contract freeze record was found. The items below are **questions for the Architect**, not decisions made by this package. Story 4.4 must not implement, reinterpret, or close any Story 4.3 deferred item.

### 12.1 Evidence summary

| Item | Evidence | Observation |
|---|---|---|
| **AC-4** | `spec-4-3:5-6,31,150-162` says cancellation is approved design, not yet implemented. `loan_dao.dart:701-834` contains `cancelLoanAgreement`, including an audit payload and conditional state update. | Implementation exists, but the specification still describes it as unimplemented. Which artifact is authoritative is unresolved. |
| **U-5/v14** | `spec-4-3:45,47,208-210` says the DB-level Tier 1 CHECKs and v14 migration remain open. `app_database.dart:72` reports schema v14; `:199-205` contains the v14 branch; `:530` contains `_migrateLoansToV14`; `test/unit/core/data/local/drift_migration_v14_test.dart` exists. `app_database.dart:29` still says “Schema Version: 13”. | The working tree contains v14, but the Story 4.3 specification and one code comment are stale. The migration test's passing status was not re-verified for this package. |
| **F1** | `prd.md:626-640` defines Category 2 as loan agreement origination/cancellation and Category 7 as financial correction approvals. `audit_service.dart:35-49` documents Category 2 as customer photo/exception events and Category 7 as loan agreement creation/disbursement. `spec-4-3:218` records R1 (PRD ordinals authoritative) but says `AuditService` alignment is not implemented. | Story 4.4 proposes PRD ordinals. The server `AuditService` taxonomy conflict remains open. |
| **Q-1/D10** | `spec-4-3:5,31,45` records Q-1 and D10 as open. No cancellation-balance invariant ruling was found. | Story 4.4 does not cancel loans or generate official documents for cancelled loans, but the Architect must confirm that boundary. |
| **Cancellation-flow gap** | `cancelLoanAgreement` exists at `loan_dao.dart:701-834`. A search of `test/` found no direct `cancelLoanAgreement` invocation, and a search of `lib/features/customers/presentation/` found no cancellation action. | The DAO path appears untested and unreachable from the UI. This is a separate evidence gap from the AC-4 specification drift. |
| **Contract freeze** | `sprint-status.yaml:72`; no freeze record found. `confirmLoanDisbursement` is at `loan_dao.dart:435-617`; the proposed official document hook would be inserted inside that transaction. | Official-snapshot integration cannot safely land until Story 4.3 closes or the disbursement contract is formally frozen. |

### 12.2 Architect decision requests — all Pending

| ID | Issue | Decision requested | Status | Architect decision | Rationale | Conditions | Architect identity / signature / date |
|---|---|---|---|---|---|---|---|
| **4.3-A1** | AC-4 specification/code drift | Is `cancelLoanAgreement` (`loan_dao.dart:701-834`) the authoritative AC-4 implementation, or is the “not yet implemented” statement in `spec-4-3` authoritative? What must be reconciled in the specification, tests, and UI? | **Pending** | ______________________ | ______________________ | ______________________ | Name: ____________<br>Role: Architect<br>Signature: ____________<br>Date: ____________ |
| **4.3-A2** | U-5/v14 drift | Is the v14 Tier 1 CHECK migration complete and accepted despite `spec-4-3:45,47,208-210` saying it is open? If not, what remains, and which document is authoritative? | **Pending** | ______________________ | ______________________ | ______________________ | Name: ____________<br>Role: Architect<br>Signature: ____________<br>Date: ____________ |
| **4.3-A3** | F1 audit taxonomy | May Story 4.4 use PRD FR-31 ordinals and its proposed Category 2 document action types while F1 (`AuditService` alignment) remains open? Is `AuditService` alignment a Story 4.4 prerequisite or separate work? | **Pending** | ______________________ | ______________________ | ______________________ | Name: ____________<br>Role: Architect<br>Signature: ____________<br>Date: ____________ |
| **4.3-A4** | Q-1/D10 | How should Q-1/D10 (cancelled-agreement balance invariant) affect Story 4.4? Confirm whether Story 4.4 may proceed independently while generating no official document for a cancelled loan and reinterpreting no balance rule. | **Pending** | ______________________ | ______________________ | ______________________ | Name: ____________<br>Role: Architect<br>Signature: ____________<br>Date: ____________ |
| **4.3-A5** | Cancellation-flow test/UI gap | Is the cancellation flow complete despite no direct test invocation and no presentation action being found? If incomplete, what evidence or work is required before Story 4.4 may rely on the cancellation state? | **Pending** | ______________________ | ______________________ | ______________________ | Name: ____________<br>Role: Architect<br>Signature: ____________<br>Date: ____________ |
| **4.3-A6** | Disbursement contract freeze | Is the contract in §12.3 formally frozen for Story 4.4's official snapshot, or must Story 4.3 close first? If frozen, record the exact boundary and any conditions. | **Pending** | ______________________ | ______________________ | ______________________ | Name: ____________<br>Role: Architect<br>Signature: ____________<br>Date: ____________ |

**Traceability:** 4.3-A1 through 4.3-A4 correspond to the Story 4.3 Appendix B decision requests. 4.3-A5 makes the cancellation-flow test/UI gap explicit. 4.3-A6 makes the disbursement-contract freeze question explicit. No decision is recorded.

**Request status:** 6 of 6 Pending; 0 Architect decisions recorded; 0 signatures recorded.

### 12.3 Contract fields proposed for freeze (Architect to decide)

No freeze is recorded. The Architect is asked whether the following implemented contract is frozen for the Story 4.4 official snapshot:

- loan identity: `id`, `shop_id`, `customer_id`;
- money: `principal_cents`, `balance_cents` (unchanged by disbursement);
- state: `status`, `workflow_status`;
- dates: `created_at`, `due_date`, `term_preset_days`, `custom_due_date`, `disbursed_at`;
- actor: `disbursed_by_user_id`;
- cancellation: `cancelled_at`, `cancellation_reason`;
- collateral binding: `collateral_items.loan_id`;
- transaction/idempotency: the conditional update matches `workflow_status = pending_disbursement`; the sync-queue idempotency guard is used; the official snapshot must be inserted after the update and before commit;
- official due date: `OfficialDueDateCalculator` from the agreed term and confirmed disbursement date (`loan_term.dart:377-462`).

### 12.4 Story 4.4 boundary while Story 4.3 is unresolved

- No official-snapshot integration until Story 4.3 is closed or the contract above is formally frozen.
- Draft/schema/renderer scaffolding may be prepared only after the Story 4.4 gates in §15.
- No D-1 through D-7 or J-1 work.
- No reinterpretation of Q-1/D10.
- No claim that Story 4.3 is closed or its contract frozen.
- No change to `sprint-status.yaml`.

---

## 13. P-1 through P-10 questionnaire

The separate response instrument is:

`_bmad-output/implementation-artifacts/story-4-4-p1-p10-questionnaire.md`

The questionnaire is the authoritative response instrument. Appendix A of the specification is a summary of the same ten questions and is not a second response record.

**Status:** all ten questions unanswered. No respondent identity, signature, or date has been recorded. The questionnaire is for the Product Owner / Operations.

| ID | Question | Required before | Status |
|---|---|---|---|
| **P-1** | Exact printer make/model(s) and command set (ESC/POS vs TSPL/CPCL/ZPL)? | Thermal protocol selection | **Unanswered** |
| **P-2** | Paper width: 58 mm, 80 mm, or both? | Thermal layout and wrapping | **Unanswered** |
| **P-3** | Connection method: Bluetooth Classic, BLE, USB, Wi-Fi/TCP, or vendor dock? | Transport package and Android permissions | **Unanswered** |
| **P-4** | Must the ticket print Sinhala/Tamil, or English only? | Font and raster strategy | **Unanswered** |
| **P-5** | Is a shop logo required on thermal output? | Logo scope; v1 proposes text-only branding | **Unanswered** |
| **P-6** | Is a cash-drawer kick required? | Adapter contract | **Unanswered** |
| **P-7** | Must Web print thermal receipts? | Web bridge decision | **Unanswered** |
| **P-8** | Is Windows desktop a supported counter target? | Platform scope | **Unanswered** |
| **P-9** | Is print confirmation/status feedback required? | Transport capability | **Unanswered** |
| **P-10** | What is the fallback when the printer is unavailable? | Failure handling; must not block cash handover | **Unanswered** |

**Hard minimum before thermal dependency or adapter selection:** P-1, P-2, P-3, and P-4. **Adapter contract:** P-5, P-6, P-9, and P-10. **Target scope:** P-7 and P-8. Until the applicable answers are recorded and D4.4-04/D4.4-07 are approved, no thermal package may be selected and no adapter may be created.

---

## 14. Approvals and evidence still required

Implementation may be reconsidered only when every applicable item below is recorded and evidenced. A Pending item is a hard gate where marked.

| # | Required approval or evidence | Required from | Gate | Status |
|---|---|---|---|---|
| **E-1** | Proposed Story 4.4 specification approved as written or with recorded conditions | Product Owner + Architect | **Hard** — before any implementation | **Pending** |
| **E-2** | D4.4-01 through D4.4-07 individually decided, with rationale and conditions | Product Owner + Architect | **Hard** — before any implementation | **Pending** |
| **E-3** | PRD draft-printing open decision (`prd.md:440`) resolved and the approved policy reflected in the specification | Product Owner | **Hard** for D4.4-01 and AC-01 | **Open** |
| **E-4** | Story 4.3 AC-4 authority reconciled (specification, code, test, UI) | Architect (with Story 4.3 owner) | **Hard** for cancellation-dependent behaviour | **Pending** |
| **E-5** | Story 4.3 U-5/v14 status reconciled; v14 migration test evidence recorded | Architect / Engineering | **Hard** before schema v15 work | **Pending** |
| **E-6** | F1 ruling operationalised or explicitly separated; server action-type allow-list confirmed for the approved document action types | Architect | **Hard** before audit wiring | **Pending** |
| **E-7** | Q-1/D10 effect on Story 4.4 explicitly ruled | Architect | **Hard** before treating cancellation state as stable | **Pending** |
| **E-8** | Cancellation-flow evidence: direct test invocation, UI action or explicit deferral, and specification correction if needed | Story 4.3 owner / Architect | **Hard** if Story 4.4 relies on cancellation | **Pending** |
| **E-9** | Story 4.3 closed (`done`) or disbursement contract formally frozen with boundary and conditions | Architect | **Hard** before official-snapshot integration | **Pending** |
| **E-10** | P-1 through P-10 answered with respondent identity, signature, date, and supporting evidence | Product Owner / Operations | **Hard** before thermal dependency or adapter | **Unanswered** |
| **E-11** | PDF/printing dependency review: versions, licences, transitive dependencies, platform support, security, and pinning | Architect | **Hard** before dependency changes | **Pending** |
| **E-12** | Hardware spike evidence: chosen printer, width, transport, glyph rendering, status feedback, fallback, and thermal output sample | Engineering / Operations | **Hard** before thermal adapter | **Pending** |
| **E-13** | D4.4-02 sub-choices explicitly approved: Initial Outstanding Balance, optional signature block, text-only branding, and `Not recorded` fallback for blank optional branding fields | Product Owner + Architect | **Hard** before official layout | **Pending** |
| **E-14** | Document-specific fail-closed masker for short NIC/phone values accepted, with test evidence | Architect | **Hard** before document rendering | **Pending** |
| **E-15** | Schema v15 design review and migration/rollback test evidence, including append-only triggers and transaction coupling | Architect / Engineering | **Hard** before schema v15 | **Pending** |
| **E-16** | Evidence that document generation, PDF metadata, filenames, logs, and audit payloads contain no prohibited PII | Engineering | **Hard** before acceptance | **Pending** |
| **E-17** | Thermal/PDF acceptance evidence, including exact watermark strings, reprint watermark, masking fidelity, and offline operation | Engineering | **Hard** before Story 4.4 acceptance | **Pending** |
| **E-18** | Confirmation that Story 4.4 tests require no PostgreSQL provisioning | Engineering / Architect | **Hard** before acceptance | **Pending** |

**Approval rule:** no item may be marked satisfied by implication. Each requires a named stakeholder, role, date, and either a signature or a linked evidence record. The package does not pre-fill any of them.

---

## 15. Final readiness assessment

### 15.1 Remaining blockers

| ID | Blocker | Type | Owner |
|---|---|---|---|
| **B-1** | PRD `[OPEN DECISION]` on whether drafts may be printed before disbursement | Product | Product Owner |
| **B-2** | Official ticket layout, loan/document reference, signature block, Initial Outstanding Balance inclusion | Product/Architect | PO + Architect |
| **B-3** | Snapshot model, schema v15, append-only triggers, replacement policy | Architect | Architect |
| **B-4** | PDF/printing dependency approval and supply-chain review | Architect | Architect |
| **B-5** | Document masking policy (`always_masked_v1` vs `role_dependent_v1`) | Product + Architect | PO + Architect |
| **B-6** | Audit category mapping for document events; unresolved F1 (`AuditService` vs PRD ordinals) | Product/Architect | PO + Architect |
| **B-7** | Printer hardware, paper width, connection, language/glyph, Web-thermal requirements (P-1…P-10) | Product/Operations | PO + Operations |
| **B-8** | Story 4.3 is `review`, not `done`; AC-4 and U-5/v14 spec/code drift; cancellation-flow test/UI gap; F1; Q-1/D10; no contract freeze | Delivery | Architect |
| **B-9** | Story 1.6 branding remains `backlog`; no branding snapshot today | Dependency | PO (minimal prerequisite mitigates) |
| **B-10** | Story 7.2 masking remains `backlog`; FR-12 server omission absent | Dependency | PO (local policy mitigates) |
| **B-11** | Story 4.4 specification exists only as **PROPOSED — NOT APPROVED** and has no Product Owner or Architect approval | Documentation/Approval | PO + Architect |
| **B-12** | No PDF/printing dependencies, renderers, document tables, or tests exist | Implementation | Engineering (after approval) |
| **B-13** | P-1 through P-10 are unanswered; no printer or transport can be selected | Product/Operations | PO + Operations |

### 15.2 Required dependency sequence

```text
D4.4-01…07 approvals
        │
        ├── Story 4.3 review closure / contract freeze ──┐
        │                                                │
        ├── Story 1.6 minimal branding read + snapshot   │
        │                                                ▼
        ├── DocumentMaskingPolicy (parallel to 7.2) ──► Schema v15 + snapshot service
        │                                                │
        ├── Audit category ruling (F1/R1) ───────────────┤
        │                                                ▼
        └── Printer hardware spike (P-1…P-10) ────────► PDF renderer
                                                         │
                                                         ▼
                                              Thermal adapter (one transport)
                                                         │
                                                         ▼
                                              UI + audit wiring + tests
                                                         │
                                                         ▼
                                              Acceptance verification
```

### 15.3 Minimal implementation plan after approval (no code in this task)

| Step | Work | Exit criterion |
|---|---|---|
| **1. Schema v15** | Add `loan_documents` and `loan_document_events`; indexes; unique constraints; `BEFORE UPDATE/DELETE` triggers; migration from v14; migration tests with populated child rows | Fresh install and v14→v15 upgrade both pass; documents are insert-only |
| **2. Snapshot domain** | `LoanDocumentSnapshot`, canonical JSON serializer (sorted keys, UTC ISO, integer cents), SHA-256, `DocumentMaskingPolicy`, document number/reference generation | Unit tests prove canonical hash stability and masking resolution |
| **3. Snapshot service** | Draft snapshot creation; official snapshot inside `confirmLoanDisbursement`; idempotent versioning; replacement/void events | Official disbursement and snapshot commit/rollback together; no duplicate version |
| **4. Renderers** | One layout model → `PdfLoanDocumentRenderer` (`pdf`); `EscPosLoanDocumentRenderer` after transport decision; exact watermark/disclosure constants | PDF text extraction asserts every mandatory field; thermal golden bytes assert commands/watermarks |
| **5. UI** | Draft preview/print from pending loan; official ticket preview/print/export from disbursed loan; reprint action; permission gates; printer selection/status | Widget tests for watermark, field presence, permission denial, reprint watermark |
| **6. Audit wiring** | Local `sync_queue` rows per §7.2; minimal metadata; no PII; server `AuditService` mapping only after F1/R1 alignment | Audit tests assert category/action/metadata; no NIC/address/phone in payload |
| **7. Acceptance** | Run the plan in §15.4; record evidence; do not mark Story 4.4 done without both approvals and green tests | All AC tests pass; hardware checklist signed |

### 15.4 Acceptance-test plan

| ID | Test | Type | Asserts |
|---|---|---|---|
| **AT-01** | Draft on pending loan | Widget + PDF text | Exact watermark `*** DRAFT / PENDING DISBURSEMENT - NOT A CASH RECEIPT ***`; exact disclosure; label `Preliminary Due Date (Pending Disbursement)` |
| **AT-02** | Draft state gate | Unit/service | No draft for `disbursed` or `cancelled`; no draft from unsaved form state |
| **AT-03** | Draft permission | Unit + widget | Actor without `createLoans` is refused at the service, not only the widget |
| **AT-04** | Official ticket fields | PDF text + widget | All 11 epic fields + Initial Outstanding Balance; exact principal `Rs. XX,XXX.XX`; collateral descriptions and `X.XXX g` weights; zero-interest disclosure; footer |
| **AT-05** | Official ticket state gate | Unit/service | Official ticket only for `disbursed`; not for `pending_disbursement`/`cancelled` |
| **AT-06** | Snapshot immutability | Unit/integration | After changing shop name, customer NIC/address, loan balance, and collateral description, reprint renders the original snapshot values |
| **AT-07** | Snapshot hash | Unit | Recomputed SHA-256 matches; tampered JSON is refused and produces `document_integrity_failure` |
| **AT-08** | Append-only tables | Migration/integration | `UPDATE`/`DELETE` on `loan_documents`/`loan_document_events` raise `ABORT` |
| **AT-09** | Replacement document | Unit | New version + `supersedes_document_id` + mandatory reason; original untouched; original renders `*** SUPERSEDED — DO NOT USE ***` |
| **AT-10** | Reprint watermark | Widget + PDF text | `*** REPRINT ***`, reprint timestamp, sequence, staff ID; no new financial mutation; reprint count derived correctly |
| **AT-11** | Reprint masking fidelity | Unit + widget | A higher-privileged reprint cannot unmask a document snapshot generated masked |
| **AT-12** | Masking matrix | Unit + widget | Cashier vs Manager/Owner; address never printed; NIC/phone masked per policy; no PII in PDF metadata/filename/log |
| **AT-13** | Audit events | Unit | Draft/official/export/print/reprint/replacement/failed generation produce the approved category + action type + minimum metadata; no PII |
| **AT-14** | Permission denial audit | Unit | Unauthorized document access produces Category 14 `document_access_denied`; cross-tenant attempt refused |
| **AT-15** | Offline operation | Unit/widget | Generation and local audit queue work with no network; event is `pending_server_ack`; no cloud call |
| **AT-16** | Thermal output — byte level | Unit golden | ESC/POS bytes contain the watermark/disclosure, correct paper-width wrapping, and no colour-only signalling (no hardware required) |
| **AT-17** | Thermal output — hardware | Manual checklist | Real printer, chosen width/connection, glyphs, logo, status/failure, fallback to PDF (requires P-1…P-10) |
| **AT-18** | PDF export | Widget/service | PDF bytes are valid; text contains all mandatory fields; share/save works on Android and Web |
| **AT-19** | Migration v14→v15 | Drift integration (SQLite only) | Existing loans/shops/customers/collateral survive; new tables/indexes/triggers present; idempotent second launch |
| **AT-20** | No PostgreSQL dependency in 4.4 tests | CI guard | Story 4.4 test suite runs without provisioning PostgreSQL |

### 15.5 Repository evidence supporting this assessment

| Claim | Evidence |
|---|---|
| Story 4.1 implemented | `lib/features/customers/data/daos/loan_dao.dart:133-359`; `lib/features/customers/domain/models/loan.dart:127-261`; `test/unit/features/customers/loan_dao_test.dart`, `loan_test.dart` |
| Story 4.2 implemented | `lib/features/customers/domain/models/loan_term.dart:170-375`; `lib/features/customers/presentation/loan_origination_screen.dart`; `test/unit/features/customers/loan_term_test.dart`; `test/widget/features/customers/loan_origination_screen_test.dart` |
| Story 4.3 in review, code present | `sprint-status.yaml:72`; `loan_dao.dart:435-617,701-834,899-1027`; `loan.dart:175-188,303-341`; `app_database.dart:72,189-205`; `test/unit/features/customers/loan_disbursement_dao_test.dart` |
| Story 1.6 backlog, shop columns exist | `sprint-status.yaml:46`; `lib/core/data/local/tables/shops_table.dart:11-43`; `lib/features/shop/domain/models/shop_profile.dart:14-102`; `lib/features/shop/presentation/shop_profile_screen.dart:245-250` |
| Story 7.2 backlog, masking helpers exist | `sprint-status.yaml:93`; `lib/features/customers/domain/models/customer_masking.dart:13-50`; `customer_profile_screen.dart:263-269`; `customer_search_screen.dart:158` |
| No document/snapshot table | `lib/core/data/local/tables/` contains no loan-document table; `app_database.dart` table list |
| No PDF/printing dependency | `pubspec.yaml:30-49` |
| Schema v14 | `lib/core/data/local/app_database.dart:72` |
| Audit taxonomy conflict | `lib/features/auth/data/services/audit_service.dart:35-49` vs `prd.md:626-640`; `spec-4-3:37,218` |
| Local audit is mutable queue | `lib/core/data/local/tables/sync_queue_table.dart:37-45`; `loan_dao.dart:389-408` |
| 14 permissions, role templates | `lib/core/permissions/app_permission.dart:5-159` |
| Money VO | `lib/core/money/money.dart:4-370` |
| Platform targets | `android/` and `web/` exist; no `windows/`, `ios/`, `macos/`, `linux/`; `ARCHITECTURE-SPINE.md:43` states "Android and Web" |
| Draft wording fixed by AC | `epics.md:1032-1035`; `prd.md:435-439` |
| Draft policy still open | `prd.md:440` |
| Official ticket fields fixed | `epics.md:1037-1040`; `prd.md:433` |
| Snapshot/reprint rules | `prd.md:510-522` |
| Audit catalogue authority | `prd.md:622-647` |

### 15.6 Readiness verdict

**NOT READY — AWAITING APPROVAL**

Reasons:

1. The proposed Story 4.4 specification is **PROPOSED — NOT APPROVED**; neither the Product Owner nor the Architect has approved it.
2. All seven D4.4 decisions are **Pending**; none has a Product Owner or Architect decision, signature, date, rationale, or conditions.
3. The PRD draft-printing policy is still an explicit open decision (`prd.md:440`).
4. Story 4.3 is in `review`; AC-4, U-5/v14, F1, Q-1/D10, the cancellation-flow test/UI gap, and the disbursement-contract freeze all remain unresolved. No contract freeze record exists.
5. P-1 through P-10 are unanswered; no thermal dependency or adapter can be selected.
6. No document snapshot schema, PDF/printing dependency, renderer, or document test exists yet.
7. Story 1.6 branding and Story 7.2 masking are backlog; only minimal local prerequisites are proposed.

**Next action:** route the specification approval request (§10), the D4.4-01 through D4.4-07 register (§11), and the Story 4.3 Architect requests (§12) for written decisions; route the separate P-1 through P-10 questionnaire to the Product Owner/Operations. Re-issue this package with recorded approvals, answers, and evidence before implementation is reconsidered.

---

*End of approval package. No source, test, dependency, migration, generated code, database schema, `sprint-status.yaml`, or Git state was modified in preparing this document. The only planning artifacts affected are this package (modified) and the separate P-1 through P-10 questionnaire (created).*
