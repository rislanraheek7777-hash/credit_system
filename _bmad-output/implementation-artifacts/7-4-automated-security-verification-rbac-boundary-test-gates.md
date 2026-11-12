# Story: 7.4 Automated Security Verification & RBAC Boundary Test Gates

Status: in-progress

## Story

As a Software Developer,
I want automated security verification and RBAC boundary test gates,
So that regressions in permissions are caught in CI.

## Acceptance Criteria

- CI runs RBAC boundary tests.
- All 14 permissions tested (allow + deny).
- Cross-tenant tests pass.

## Tasks

- [ ] Add RBAC boundary test suite
- [ ] Wire into CI
- [ ] Add tests
