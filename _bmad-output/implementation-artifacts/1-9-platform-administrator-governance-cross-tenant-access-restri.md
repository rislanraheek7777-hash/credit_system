# Story: 1.9 Platform Administrator Governance & Cross-Tenant Access Restrictions

Status: in-progress

## Story

As a Platform Security Officer and Shop Owner,
I want platform administrator accounts to be default-denied read access to shop customer personal data, loan agreements, and financial ledgers,
So that independent retail shops have guaranteed data privacy, strict tenant isolation, and regulatory compliance without unauthorized operator access.

## Acceptance Criteria

- Platform admin can view tenant status/health but not customer PII/financial data.
- Direct DB/API queries with platform admin token return 403 / zero rows.
- No break-glass bypasses.
- Unauthorized attempts logged as Category 14 audit event.
- CI boundary tests verify cross-tenant rejection.

## Tasks

- [x] Implement RBAC deny for platform admin on customer/loan/payment tables
- [x] Add audit logging on blocked attempts
- [x] Add CI boundary tests