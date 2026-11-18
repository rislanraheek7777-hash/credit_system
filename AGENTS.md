# Agent Instructions — Credit Management System

**Project:** credit_system  
**Version:** 1.0.0  
**Primary Language:** English  
**Communication Language:** English  

---

## 🏗️ Project Overview

The **Credit Management System** is a multi-tenant SaaS platform for independent retail businesses (jewelry/gold shops, consumer electronics stores, and collateral lending shops) to manage customer identities, collateral-backed micro-credits, payment transactions, and physical item custody.

The platform enforces **strict multi-tenant data isolation**, **zero-interest principal tracking**, **auditable transaction histories**, and **role-based access control** via a 14-permission catalog.

The codebase follows **Clean Architecture with Feature-First modular boundaries** and **Drift SQLite** (local) + **PostgreSQL** (cloud source of truth) dual-tier persistence.

---

## 📦 Available BMad Phases & Current Status

| Phase | Skill | Status | Key Artifacts |
|-------|-------|--------|--------------|
| **Planning** | `bmad-product-brief` | ✅ Complete | `briefs/brief-credit_system-2026-10-13/brief.md` |
| | `bmad-prd` | ✅ Complete | `prds/prd-credit_system-2026-10-13/prd.md` |
| | `bmad-architecture` | ✅ Complete | `architecture/ARCHITECTURE-SPINE.md` |
| | `bmad-create-epics-and-stories` | ✅ Complete | `epics.md` (33 FR + 8 AD breakdown) |
| | `bmad-sprint-planning` | ✅ Complete | `implementation-artifacts/sprint-status.yaml` |
| | `bmad-ux` | ✅ Complete | `planning-artifacts/ux-designs/ux-.../DESIGN.md` + `EXPERIENCE.md` |
| **Ship (Next)** | `bmad-build` | 🔄 **Ready to start** | — |

All **required** planning-phase artifacts are complete. The project is ready for the **ship phase** (`bmad-build`).

---

## 🛠️ Development Commands & Workflows

### Flutter/Dart

| Command | Description |
|---------|-------------|
| `flutter pub get` | Resolve dependencies (run after changing `pubspec.yaml`) |
| `flutter analyze` | Run static analysis (zero-lint/zero-warning policy) |
| `flutter test` | Run all tests (unit + integration + widget) |
| `flutter test test/unit/` | Run unit tests only |
| `flutter test test/integration/` | Run integration tests (real PostgreSQL) |
| `flutter test test/widget/` | Run widget smoke tests |

### BMad Skill Invocation

| Skill | Menu Code | Args | Description |
|-------|-----------|------|-------------|
| `bmad-build` | `BD` | — | Standard implementation flow: clarify intent, plan, implement, review, present. **Next required step.** |
| `bmad-code-review` | `CR` | — | Ad hoc review of any code change. Optional extra check after `bmad-build`'s built-in review. |
| `bmad-qa-generate-e2e-tests` | `QA` | — | Generate automated API and end-to-end tests for implemented code. |
| `bmad-project-context` | `PC` | — | Set up or refresh repo's agent instructions (creates/updates `AGENTS.md`). Run if project context changes. |
| `bmad-brainstorming` | `BP` | — | Guided idea-generation session. Use when stuck generating ideas or at ideation start. |
| `bmad-prfaque` | `WB` | `-H` | Amazon's Working Backwards method: write the press release first, then answer hard stakeholder questions. |

### Code Workflows

| Workflow | How to Run |
|----------|------------|
| **Run all tests** | `flutter test` |
| **Run unit tests only** | `flutter test test/unit/` |
| **Run widget tests only** | `flutter test test/widget/` |
| **Run static analysis** | `flutter analyze` |
| **Run disaster recovery drill** | Refer to `AD-8` in `ARCHITECTURE-SPINE.md` — requires PITR backup restoration and automated consistency verification |

---

## 📁 Project Structure (Key Directories)

```
lib/
├── core/                          # Shared foundational infrastructure
│   ├── database/                  # Drift SQLite, migrations, shared table mixins
│   ├── errors/                    # Typed domain failure definitions
│   ├── money/                     # Immutable Money value object (AD-2) — DO NOT use double!
│   ├── permissions/               # 14 RBAC permissions catalog
│   ├── sync/                      # Offline sync queue & reconciliation (AD-1)
│   ├── theme/                     # Design tokens, colors, typography
│   └── utils/                     # Timezone utils (Asia/Colombo), calendar arithmetic
│
└── features/                      # Business feature modules (vertical slices)
    ├── auth/                      # Staff login, token storage & session provider
    ├── shop/                      # Shop profile, branding & time zone configuration
    ├── customers/                 # KYC profile onboarding, camera capture & search
    ├── collateral/                # Multi-item collateral intake, weights & custody states
    ├── credits/                   # Principal tracking, terms, due dates & disbursements
    ├── payments/                  # Partial repayments, settlements, reversals & receipts
    ├── overdue/                   # Delinquency review queues, extensions & notes
    ├── reports/                   # Cash reconciliation dashboards & PDF/CSV export
    └── audit/                     # 14-event append-only audit trail viewer
```

**Critical Rules:**
- `core/domain/` — **Pure Dart, zero Flutter/database dependencies**. 100% testable in isolation.
- `core/money/` — **All monetary amounts in integer minor units (cents). Dart `double` is strictly prohibited** and enforced via static linting.
- `core/permissions/` — **14-permission catalog** must be enforced on both client (Riverpod selectors) and server (PostgreSQL RLS).
- All feature modules follow: `domain/` (pure Dart) → `data/` (Drift/PostgreSQL) → `presentation/` (Riverpod widgets).

---

## ⚠️ Known Pitfalls & Conventions

| Issue | Guidance |
|-------|----------|
| **Floating-point money** | Never use `double` or `float` for monetary calculations. Use `core/money/Money` value object exclusively. Static analysis will flag violations. |
| **Cross-tenant data access** | All database queries must filter by `tenant_id`. Never trust client-supplied tenant IDs. PostgreSQL RLS enforces this; client-side Riverpod selectors are presentation-only. |
| **Audit trail immutability** | `audit_events` table has a PostgreSQL trigger that unconditionally rejects `UPDATE` and `DELETE`. Never attempt to modify or delete audit records. |
| **Idempotency keys** | All client-initiated financial operations must include a `client_operation_id` (UUIDv4). Re-transmitted requests must return the existing record without re-executing. |
| **Offline sync queue** | Local writes are flagged `PendingServerAck` vs `ConfirmedByServer`. Sensitive admin actions (corrections, extensions, closures) are blocked offline. |
| **Image storage** | Photos are stored client-side (sandboxed) and uploaded to private cloud storage with signed URLs (≤15 min validity). Relational tables store only metadata (path, hash, size, mime type). |
| **Due date boundary** | Overdue evaluation happens at 00:00:00 on the calendar day **after** the due date (`Due Date + 1`) in shop's local time (`Asia/Colombo`). Settled credits are never marked overdue. |
| **Cash disbursement decoupling** | Credit creation and cash disbursement are separate steps. Payments are blocked on credits in `Pending Disbursement` state. Official due date is calculated from confirmed disbursement date. |

---

## 📬 Communication & Escalation

- **Change proposals** → Run `bmad-correct-course` (menu code `CC`)
- **Code review** → Run `bmad-code-review` (menu code `CR`)
- **Quality/eval issues** → Contact the project lead or run `bmad-review`
- **Workflow/process questions** → Refer to this `AGENTS.md` or run `bmad-project-context` to refresh

---

## 🚀 Next Recommended Step

**Run `bmad-build`** to start the implementation/shipping phase. This will follow the standard BMad build flow: clarify intent, plan, implement, review, and present.

To invoke: `bmad-build`

Or, if you want to review the current state first: `bmad-review`

---

*This file is managed by `bmad-project-context`. If the project context changes (new requirements, architecture shifts, or module additions), run `bmad-project-context` to refresh.*