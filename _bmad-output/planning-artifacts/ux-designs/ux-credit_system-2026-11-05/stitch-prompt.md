# Google Stitch Prompt — Credit Management System (UX Design Handoff)

Paste this entire prompt into Google Stitch (https://stitch.withgoogle.com). It should emit a `DESIGN.md` (visual identity) plus per-screen HTML mockups. Save all outputs back into this folder (`_bmad-output/planning-artifacts/ux-designs/ux-credit_system-2026-11-05/`) — `DESIGN.md` at the root and HTML screens under `mockups/`.

---

## Product
**Credit Management System** — multi-tenant SaaS for independent retail shops (jewelry/gold, electronics, general retail) that issue short-term, zero-interest, collateral-backed credits (pawn-style credit). V1 focuses on Sri Lanka retail; default currency LKR, timezone Asia/Colombo.

## Users (no borrower self-service in V1)
- **Shop Owner** (admin): governance, approvals, dashboards, reports, overdue decisions.
- **Counter Staff** (operational): customer intake, credit origination, payments, receipts, collateral handover — permission-gated via 14 toggles.
- **Customer/Borrower** (indirect): receives receipts, pledged items held in custody; no login.
- **Platform Admin** (restricted): tenant provisioning/infra only.

## Brand & Tone
Simple, trustworthy, transparent, accountable. Digitized replacement of paper logbooks/receipts. Counter-optimized, fast, frictionless. Shop-level branding: name, logo, address, contact, tax/reg number, receipt header/footer. No imposed color palette yet — propose a calm, professional, high-contrast palette suitable for retail counters and mobile camera capture. Include dark-mode consideration optional.

## Form Factor
Flutter **Web + Mobile**. Counter terminal (web) for daily operations; mobile for camera capture and on-the-go. Touch + keyboard + mouse. Camera/webcam capture with pre-save preview; file upload (JPEG/PNG). Thermal slip and laser receipt printing; PDF export.

## Core Surfaces (screens) to design
1. Login (username/password, offline indicator, forgot credentials, new shop).
2. Shop profile configuration (name, address, phone, email, tax/reg, logo, receipt header/footer, timezone, currency display format).
3. Staff account admin + 14-permission toggle matrix.
4. Customer search (NIC/phone/name, shop-scoped) with results cards.
5. Customer registration (name, NIC, phone, address, photo capture/upload with preview; duplicate detection warning; shared-phone confirmation).
6. Customer profile (photo, contact masked by RBAC, credits grouped Active/Overdue/Settled).
7. Credit creation wizard: term preset (30/60/90) or custom date picker + principal; multi-item collateral registration (category, description, condition, estimated value, weight for gold, photos); summary review; idempotent submit.
8. Pending-disbursement worklist (non-destructive) + disbursement confirmation.
9. Cancel undisbursed agreement (owner, mandatory reason).
10. Payment recording (amount input, balance preview, overpayment block, idempotent submit).
11. Receipt view/print (thermal/laser/PDF, reprint watermark, immutable snapshot).
12. Collateral handover verification (original photos/weights, per-item confirm, partial pickup, exception/held).
13. Missing-photo exception request + owner approval.
14. Overdue review queue (badge, days-overdue counter, promised payment date, filters).
15. Due date extension (owner: date picker + mandatory reason).
16. Customer follow-up notes (channel, notes, promised payment date; reverse chronological).
17. Owner resolution states for overdue credits.
18. Correction request + owner approval queue; manual balance adjustment (owner).
19. Owner dashboards: daily cash reconciliation (cash in/out, net), portfolio overview (counts + aggregates, items in custody), pending correction queue.
20. Reports: Daily Cash Collection Ledger, Customer Credit Portfolio Summary, Overdue Delinquency Report, Collateral Vault Inventory (PDF/CSV).
21. Audit log viewer (permission-gated).
22. Platform admin tenant provisioning/infra monitoring (restricted).

## Visual Language Requirements
- Prominent status badges with exact labels: `Active (Pending Disbursement)`, `Active`, `Overdue`, `Settled (Items Pending Handover)`, `Closed / Completed`, `Closed (Collateral Exception)`, `Cancelled / Undisbursed`.
- Custody states: `In Custody`, `Returned`, `Exception / Held`.
- Watermarks: `*** DRAFT / PENDING DISBURSEMENT - NOT A CASH RECEIPT ***`, `*** REPRINT ***` with reprint timestamp.
- "Preliminary Due Date (Pending Disbursement)" labeling before disbursement.
- Overdue badge + days-overdue counter.
- Correction-pending lock indicator on affected credit only.
- PII masking in UI for unauthorized staff (NIC, phone, address, photo placeholder).
- Mandatory-field blocking with clear validation errors.
- Shop branding on receipts (logo, header/footer) with immutable snapshot at payment time.

## Constraints
- Zero interest: total repayment = principal; disclose on credit ticket.
- No automated seizure/liquidation; owner-governed only.
- No multi-currency (LKR base locked after first transaction); configurable display formatting only.
- Strict tenant isolation; server-side RBAC; PII omitted server-side unless permission.
- Idempotency on credit creation and payments; optimistic concurrency on simultaneous payments.
- Correction-pending lock blocks new payments only on affected credit.
- Monetary precision: 2 decimals, fixed-point/integer minor units.
- Photo mandatory by default; audited owner-approved exception.
- No borrower self-service, no SMS/WhatsApp, no third-party integrations, no OCR, no facial recognition, no RFID/barcode, no fuzzy name matching, no custom permissions beyond 14, in V1.
- Offline: local append-only queue; idempotent retry returns original receipt.

## Accessibility
- Not explicitly specified; apply sensible defaults: keyboard navigation, focus states, color contrast, screen-reader labels, touch targets ≥44px, clear error messaging. PII masking is a privacy control.

## Interaction Notes
- Counter flow target: returning-customer lookup + partial payment + receipt under ~1 minute (operational target).
- Fast, frictionless intake; prominent badges/queues for actionable items.
- Multi-credit customers must explicitly select target credit before payment.
- Reprint receipt preserves original transaction identity + distinct reprint audit entry.

## Deliverables Requested
1. `DESIGN.md` with YAML frontmatter tokens (colors, typography, rounded, spacing, components) + markdown body in canonical order: Brand & Style, Colors, Typography, Layout & Spacing, Elevation & Depth, Shapes, Components, Do's and Don'ts.
2. Per-screen HTML mockups for the surfaces above, saved under `mockups/`.
3. Any wireframes needed where layout drives behavior.

Spines win on conflict with mocks. Keep it simple and counter-optimized.
