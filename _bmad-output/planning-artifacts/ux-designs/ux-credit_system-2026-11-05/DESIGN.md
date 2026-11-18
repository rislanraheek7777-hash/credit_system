---
name: Credit System
description: Collateral-backed micro-credit management for independent retail shops. Calm, counter-optimized, trustworthy. Light-first with optional dark mode.
status: final
sources:
  - {planning_artifacts}/prds/prd-credit_system-2026-10-13/prd.md
  - {planning_artifacts}/briefs/brief-credit_system-2026-10-13/brief.md
  - {planning_artifacts}/briefs/brief-credit_system-2026-10-13/addendum.md
updated: 2026-11-17
colors:
  surface-base: '#F5F7FA'
  surface-raised: '#FFFFFF'
  surface-sunken: '#EEF1F5'
  surface-overlay: '#FFFFFF'
  ink-primary: '#1A2332'
  ink-secondary: '#5B6573'
  ink-disabled: '#9AA3AF'
  ink-on-accent: '#FFFFFF'
  accent: '#1565C0'
  accent-hover: '#0D47A1'
  accent-soft: '#E3ECF7'
  border-hairline: '#D9DEE5'
  border-strong: '#B0B8C4'
  success: '#2E7D32'
  success-soft: '#E8F5E9'
  warning: '#EF6C00'
  warning-soft: '#FFF3E0'
  danger: '#C62828'
  danger-soft: '#FFEBEE'
  info: '#0277BD'
  info-soft: '#E1F5FE'
  surface-base-dark: '#12151C'
  surface-raised-dark: '#1C2029'
  surface-sunken-dark: '#0E1117'
  ink-primary-dark: '#E8ECF2'
  ink-secondary-dark: '#A3ACB9'
  ink-disabled-dark: '#5E6673'
  border-hairline-dark: '#2A303B'
  accent-dark: '#5B9BF5'
typography:
  display:
    fontFamily: Inter, Roboto, system-ui, sans-serif
    fontSize: 28px
    fontWeight: 700
    lineHeight: 1.2
  title:
    fontFamily: Inter, Roboto, system-ui, sans-serif
    fontSize: 20px
    fontWeight: 600
    lineHeight: 1.3
  heading:
    fontFamily: Inter, Roboto, system-ui, sans-serif
    fontSize: 16px
    fontWeight: 600
    lineHeight: 1.4
  body:
    fontFamily: Inter, Roboto, system-ui, sans-serif
    fontSize: 14px
    fontWeight: 400
    lineHeight: 1.5
  body-strong:
    fontFamily: Inter, Roboto, system-ui, sans-serif
    fontSize: 14px
    fontWeight: 600
    lineHeight: 1.5
  meta:
    fontFamily: Inter, Roboto, system-ui, sans-serif
    fontSize: 12px
    fontWeight: 400
    lineHeight: 1.4
  mono:
    fontFamily: 'JetBrains Mono, Roboto Mono, monospace'
    fontSize: 13px
    fontWeight: 400
    lineHeight: 1.4
rounded:
  xs: 4px
  sm: 6px
  md: 12px
  lg: 16px
  xl: 24px
  pill: 9999px
spacing:
  '1': 4px
  '2': 8px
  '3': 12px
  '4': 16px
  '5': 20px
  '6': 24px
  '8': 32px
  '10': 40px
  '12': 48px
components:
  button-primary:
    backgroundColor: '{colors.accent}'
    textColor: '{colors.ink-on-accent}'
    padding: '{spacing.3} {spacing.5}'
    borderRadius: '{rounded.md}'
    fontWeight: 600
  button-secondary:
    backgroundColor: '{colors.surface-raised}'
    textColor: '{colors.accent}'
    borderColor: '{colors.border-hairline}'
    padding: '{spacing.3} {spacing.5}'
    borderRadius: '{rounded.md}'
  card:
    backgroundColor: '{colors.surface-raised}'
    borderRadius: '{rounded.lg}'
    padding: '{spacing.5}'
    borderColor: '{colors.border-hairline}'
  badge-status:
    borderRadius: '{rounded.pill}'
    padding: '{spacing.1} {spacing.3}'
    fontSize: '{typography.meta.fontSize}'
    fontWeight: 600
  input:
    backgroundColor: '{colors.surface-raised}'
    borderColor: '{colors.border-hairline}'
    borderRadius: '{rounded.md}'
    padding: '{spacing.3} {spacing.4}'
  balance-hero:
    backgroundColor: '{colors.surface-raised}'
    borderRadius: '{rounded.lg}'
    padding: '{spacing.5}'
    borderColor: '{colors.border-hairline}'
  item-receipt-card:
    backgroundColor: '{colors.surface-raised}'
    borderRadius: '{rounded.md}'
    padding: '{spacing.3}'
    borderColor: '{colors.border-hairline}'
  app-bar:
    backgroundColor: '{colors.accent}'
    textColor: '{colors.ink-on-accent}'
---

# Credit System — Design Spine

## Brand & Style
Credit System is a calm, counter-optimized, trustworthy workspace for independent retail shops. It replaces paper logbooks and spreadsheets with a clear, auditable, permission-aware interface. Visual language is clean and high-contrast, optimized for fast scanning under retail lighting and for mobile camera capture. Shop branding (logo, name, receipt header/footer) is first-class but subordinate to system clarity. [ASSUMPTION] Palette derived from the existing in-app gradient (blue) for continuity; no brand palette was specified in the brief.

## Colors
Primary accent blue (#1565C0) anchors actions and navigation. Surfaces are near-white with subtle sunken panels for grouping. Status colors are reserved for badges and validation: green success, orange warning, red danger, blue info. Status colors must never be the only carrier of meaning (always paired with text/icon). Dark mode variants provided for low-light counters; [ASSUMPTION] dark mode is optional and not required by PRD.

## Typography
Inter/Roboto system stack for cross-platform consistency (Flutter web + mobile). Display 28px for page titles, title 20px for section headers, body 14px for dense data, meta 12px for secondary labels. Monospace for IDs, amounts, and receipt numbers. Line heights tuned for dense tables and forms.

## Layout & Spacing
4px base grid. Cards use 24px padding; sections separated by 16–24px. Mobile: single column, 16px horizontal margins. Web counter: two-column where helpful (form + preview), max content width 1200px. Touch targets ≥44px. Forms use labeled inputs with helper text; validation errors inline.

## Elevation & Depth
Cards use subtle shadow (0 2px 8px rgba(0,0,0,0.06)) plus 1px hairline border. Modals/dialogs use stronger shadow and scrim. App bar is flat accent color. No gratuitous gradients beyond the established header gradient.

## Shapes
Rounded corners: 4px (xs) for chips/badges, 12px (md) for inputs/buttons, 16px (lg) for cards, 24px (xl) for dialogs. Pills for status badges. Circular avatars for photos.

## Components
- **App bar**: accent gradient header, white title/icons.
- **Buttons**: primary (accent), secondary (outlined), danger (red) for destructive/owner actions, ghost for tertiary.
- **Cards**: white surface, 16px radius, hairline border, used for customer/credit/receipt summaries.
- **Status badges**: pill with soft status background + strong text (Active, Overdue, Settled, Closed, etc.).
- **Inputs**: labeled, 12px radius, hairline border, focus ring accent.
- **Tables/lists**: zebra-free, 8px row spacing, card-based on mobile, table on web.
- **Dialogs**: 24px radius, scrim, title + content + actions.
- **Receipts**: monospace, immutable snapshot, watermarks for draft/reprint.
- **Photo capture**: preview thumbnail, retake/re-upload, mandatory indicator.
- **Balance hero** (credit details): outstanding amount in mono 32/40px, paid-progress bar (accent on sunken track) vs principal, due-date pill (warning when ≤14 days or overdue). Paid/principal/disbursed meta in mono below.
- **Item receipt card**: 56–64px photo thumbnail, category · description · weight/condition, mono estimated value, custody pill (In Custody / Returned / Exception-Held).

## Do's and Don'ts
- Do keep counter flows under ~1 minute; minimize clicks for returning customers.
- Do always pair color with text/icon for status.
- Do mask PII for unauthorized staff at the data layer, not just visually.
- Do use immutable snapshots for receipts; never re-render historical receipts from live profile.
- Don't introduce interest/fees UI (V1 is zero-interest).
- Don't allow automated collateral seizure/liquidation affordances.
- Don't show cross-tenant data or global search.
- Don't use floating-point for money; format from minor units.
- Don't auto-cancel pending-disbursement agreements; surface non-destructive worklist.
- Don't mark a credit Closed while items remain In Custody (except owner administrative closure with exception).
