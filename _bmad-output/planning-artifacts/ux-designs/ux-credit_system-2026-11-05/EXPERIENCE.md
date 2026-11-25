---
name: Credit System
status: final
sources:
  - {planning_artifacts}/prds/prd-credit_system-2026-10-13/prd.md
  - {planning_artifacts}/briefs/brief-credit_system-2026-10-13/brief.md
  - {planning_artifacts}/briefs/brief-credit_system-2026-10-13/addendum.md
updated: 2026-11-17
---

# Credit System — Experience Spine

## Foundation
Multi-surface: Flutter Web (counter terminal) + Flutter Mobile (camera capture, on-the-go). `DESIGN.md` is the visual identity reference; this spine owns behavior, states, interactions, accessibility, and journeys. UI system: Flutter Material 3 with brand layer overrides per DESIGN.md tokens. Single-tenant per shop; users belong to one shop at a time; shop context is implicit after login. Offline-capable via local append-only queue with idempotent server sync.

## Information Architecture
| Surface | Reached from | Purpose |
|---|---|---|
| Login | App open | Authenticate; offline indicator; new shop entry |
| Credential Recovery | Login ("Forgot username or password?") | Two-step self-service: request single-use OTP to verified contact channel; verify OTP and set new password; generic response at every step |
| Dashboard (Owner) | Login (owner) | Daily cash reconciliation, portfolio overview, pending correction queue, pending-disbursement worklist |
| Customer Search | Nav / dashboard | Search customers by NIC/phone/name; entry to registration/profile |
| Customer Registration | Search (no match) / FAB | Create profile with photo capture |
| Customer Profile | Search result | Contact summary (RBAC-masked) + credits grouped by status |
| Credit Creation Wizard | Customer profile / search | Term + principal + optional item receipts + review + submit |
| Pending Disbursement Worklist | Dashboard / nav | Non-destructive list of undisbursed agreements |
| Disbursement Confirmation | Worklist / credit | Confirm cash handover, finalize due date |
| Credit Details | Customer profile / overdue queue / credit lists | Agreement at a glance: outstanding-balance hero, collateral custody, payment history, follow-up notes; entry to Record Payment, Disbursement, Handover |
| Payment Recording | Customer profile → credit / Credit Details | Amount entry, balance preview, overpayment block |
| Receipt View | After payment / history | Immutable receipt, reprint, PDF |
| Collateral Handover | Customer profile → settled credit | Per-item verify & confirm return; partial pickup |
| Overdue Review Queue | Dashboard (owner) | Badged list, filters, follow-up logging, extension, resolution |
| Correction Request | Payment receipt | Submit correction with mandatory reason |
| Balance Adjustment Proposal | Credit Details / settle flow | Staff (`requestCorrections`) proposes debit/credit adjustment with mandatory reason; posts only on Shop Owner approval (`approveCorrections`); payments locked on that credit while pending; owner may also execute directly |
| Correction Approval Queue | Dashboard (owner) | Approve/reject with reason |
| Shop Profile | Settings | Business identity, branding, timezone, currency format |
| Staff Management | Settings (owner) | Accounts + 14 permission toggles |
| Audit Log Viewer | Settings (permission) | Append-only trail viewer |
| Reports | Dashboard/owner | PDF/CSV exports |
| Platform Admin | Separate entry | Tenant provisioning/infra (restricted) |

Mobile collapses sidebar to bottom nav; dialogs become full-screen sheets on small viewports. Modal stacks one level deep.

## Voice and Tone
Microcopy is concise, factual, and action-oriented. Use canonical glossary terms exactly (no synonyms). Error messages state the rule and the value (e.g., "Payment cannot exceed current outstanding balance of 50,000 LKR."). Confirmations repeat the consequence. Owner-only actions state required role. Avoid jargon beyond glossary. Receipts are formal and immutable. [ASSUMPTION] English only in V1; i18n not required by PRD.

## Component Patterns (behavioral)
- **Search**: debounced 300ms, min 2 chars, shop-scoped; empty state with icon + text.
- **Forms**: mandatory fields block submit; inline validation; pre-save photo preview with retake.
- **Credential recovery**: two steps (request challenge → verify OTP + new password). One identical generic message for every unauthenticated outcome; inline validation only after a challenge exists; submit controls disabled while in flight; no username, shop, or channel value ever displayed.
- **Credit Details**: single-agreement "everything at a glance" surface. Balance hero (outstanding in mono, paid-progress bar vs principal, due-date pill with days remaining/overdue). Actions RBAC-gated: Record Payment (hidden/disabled when correction-pending lock active — lock banner shown instead), Confirm Disbursement (only in Pending Disbursement), Reprint Ticket, Correction Request, Balance Adjustment (staff-propose → owner-approve; blocked while an adjustment proposal is pending; owner may execute directly). Collateral section lists item receipts with per-item custody badge. Payment history is reverse-chronological with receipt #, actor, running balance; reversed entries shown struck-through with link to reversal. Follow-up notes (overdue) reverse-chronological with actor/timestamp. PII masked for unauthorized staff; no cross-tenant data. Entry points: customer profile, overdue queue, credit lists.
- **Multi-select credit**: explicit selection dialog when >1 actionable credit; single proceeds directly.
- **Payment**: amount parses to Money; validates 0 < amount ≤ balance; shows new balance preview; idempotent submit disables button while in flight.
- **Receipt**: generated after commit; PDF failure reported separately; reprint preserves original identity + reprint watermark.
- **Collateral handover**: per-item checkbox/confirm; partial pickup leaves others In Custody; all returned → Closed/Completed.
- **Exceptions**: request (staff) + approve (owner) with mandatory reason; blocks creation until approved/rejected.
- **Overdue queue**: badge + days-overdue counter; filters by due date/balance; follow-up notes reverse chronological.

## State Patterns
- Credit financial statuses: Active (Pending Disbursement), Active, Overdue, Settled (Items Pending Handover), Closed / Completed, Closed (Collateral Exception), Cancelled / Undisbursed.
- Custody states per item: In Custody, Returned, Exception / Held.
- Correction states: Correction Pending Approval → Approved (reversal posted) / Rejected (lock lifted).
- Photo exception states: Pending → Approved/Rejected.
- Pending-disbursement: non-destructive worklist; never auto-cancelled.
- Correction-pending lock: blocks new payments only on affected credit.
- Item receipts are optional at origination. A settled credit with zero item receipts has no handover step and resolves to `Closed / Completed`.
- Credit Details renders the derived overall status. `Settled (Items Pending Handover)` swaps the primary action to "Verify & Return Items"; `Closed / Completed` and `Cancelled / Undisbursed` render read-only with no Record Payment affordance. Correction-pending lock blocks Record Payment on that credit only and shows an explicit banner.
- Credential recovery states: Challenge Issued → Verified (password reset; all sessions revoked) / Expired / Consumed / Rejected; all request/verify errors are generic and non-enumerating.

## Interaction Primitives
- Tap/click to select; long-press not required.
- Swipe not used for destructive actions (accessibility).
- Keyboard: tab order, Enter to submit, Esc to close dialogs, arrow keys in lists.
- Date pickers for due dates and extensions.
- Numeric monetary input with decimal support; max hint = current balance.
- Camera capture + file upload with preview.
- Drag-and-drop not required.
- Confirmation dialogs for irreversible/owner actions.

## Accessibility Floor
- Keyboard navigable all surfaces; visible focus rings.
- Color never sole carrier of status (text + icon).
- Touch targets ≥44px; spacing ≥8px between interactive elements.
- Screen-reader labels for icons, badges, photo previews.
- Inline, specific error messages; no color-only error indication.
- Receipts printable/PDF for assistive tech; monospace amounts.
- [ASSUMPTION] No explicit WCAG level in PRD; target WCAG 2.1 AA for web.

## Key Flows
0. **Staff credential recovery (FR-34)** — Login → "Forgot username or password?" → enter login identifier → server resolves tenant from its own records and delivers a single-use OTP to the verified contact channel (identical generic response whether or not a match exists) → enter OTP + new password → server verifies, atomically resets the hash and increments `session_version`, appends Category 12/14 audit → all sessions revoked → return to Login.
1. **New customer + credit origination (UJ-1)** — Kasun searches NIC → no match → registers (name, phone, address, photo) → creates credit (30/60/90 or custom, principal) → optionally adds item receipts (category, description, condition, estimated value, weight if gold, ≥1 photo each) → reviews summary → submits (idempotent) → verifies cash handover → confirms disbursement → printable agreement/ticket with zero-interest disclosure.
   - Climax: all required fields validated; each attached item receipt has a photo; creator + disbursing user/timestamp recorded; printable ticket.
2. **Returning partial payment (UJ-2)** — search → select target credit among multiple → enter amount → validation + balance preview → submit (idempotent) → receipt print; reprint preserves original identity + reprint audit.
   - Climax: balance updated, receipt #RCP generated.
3. **Full settlement + collateral handover (UJ-3)** — final payment → balance 0 → Settled; items remain In Custody; verify against original photos/weights → per-item confirm return; partial pickup supported; all returned → Closed/Completed.
4. **Credit review at the counter** — Kasun opens Credit #LN-1042 from Sunil's profile → scans outstanding-balance hero, due-date pill, collateral custody badges, and last receipts → taps Record Payment (or logs a follow-up note when overdue). Owner sees Extend Due Date inline.
   - Climax: correct credit selected, balance verified against receipts, action taken in one screen — no navigation to a separate ledger.
5. **Payment correction (UJ-4)** — request correction with mandatory reason → correction-pending lock on that credit → owner approves (reversal posted, lock lifted) or rejects with reason → repost correct payment.
5b. **Partial forgiveness at settlement** — staff proposes a credit adjustment (forgiven amount, or new effective balance from which the delta is derived) with mandatory reason → correction-pending lock on that credit → owner approves (immutable `adjustment_credit` posted, lock lifted) or rejects with reason → staff settles the remainder via the normal payment/settle path.
6. **Overdue review + extension (UJ-5)** — auto-overdue badge at local midnight after due date → owner queue review → call borrower → extend due date with reason → status resets to Active; promise-to-pay logging; structured resolutions.

## Inspiration & Anti-patterns
- Inspiration: digitized paper logbooks/receipts; collateral-first lifecycle; shop branding on receipts.
- Anti-patterns to avoid: manual arithmetic errors, untraceable edits, lost receipts, marking settled while items unreturned, overpayments/duplicates, cross-tenant leaks, unauthorized PII access, silent transaction overwrite, automated collateral seizure, interest/fee automation, floating-point money.

## Responsive & Platform
- Mobile: single column, bottom nav, camera-first photo capture, large touch targets.
- Web counter: denser tables, keyboard shortcuts, two-column form+preview, max 1200px.
- Breakpoints: sm <600px (mobile), md 600–1024px (tablet), lg >1024px (desktop).
- Printing: thermal slip (58/80mm) and laser (A4) templates; PDF export; reprint watermark.

## Invented Sections
### Offline & Sync
Local append-only queue records events first; server audit trail appended on sync; local not authoritative. Idempotency keys prevent duplicates on retry; server returns original receipt. Pending-disbursement agreements never auto-expire; non-destructive worklist surfaces them.

### Permission-Aware UI
14 toggles drive visibility/actions. Unauthorized users see masked PII and no action buttons. Server-side enforcement; UI hides but never gates alone.

### Receipts & Audit
Immutable snapshots at payment confirmation capture shop profile, amounts, balances, timestamps, actor. Reprint adds `*** REPRINT ***` + reprint timestamp + audit entry. Audit trail append-only; no edit/delete even by owner/admin.

### Credit Details Screen
Single-agreement overview surface (balance hero + collateral custody + payment history + follow-ups). Composition confirmed 2026-11-17: mobile single-column, web counter two-column (form/summary left, payments/notes right, max 1200px). Visual references: [mockups/credit-details-mobile.html](mockups/credit-details-mobile.html) · [mockups/credit-details-web.html](mockups/credit-details-web.html). Spines win on conflict with mocks.

### Overdue Governance
Auto-transition at 00:00 local day after due date if balance >0. Owner-only extension with mandatory reason; original due date + extension chain preserved. Promise-to-pay dates surface reminders. Resolutions: under review, written off (owner), collateral retained/legal dispute (owner). No automated seizure.
