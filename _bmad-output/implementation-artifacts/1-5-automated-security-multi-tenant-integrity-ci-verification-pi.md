# Story: 1.5 Automated Security, Multi-Tenant & Integrity CI Verification Pipeline

Status: in-progress

## Story

As a Software Developer and Shop Owner,
I want an automated CI pipeline running risk-prioritized unit, integration, and security verification suites on every code change,
So that tenant isolation, RBAC enforcement, financial math precision, and audit immutability are continuously verified as non-negotiable merge gates.

## Acceptance Criteria

- CI workflow triggers on push/PR to main.
- Quality stages: lint, unit tests, DB integration tests with real PostgreSQL, boundary attack tests.
- Lint fails if Dart double used for money in domain/data.
- Cross-tenant boundary tests 100% pass or build fails.
- Audit immutability + RBAC verified.
- Branch protection blocks merge on failure.

## Tasks

- [ ] Create .github/workflows/ci.yml
- [ ] Add custom lint rule for monetary double usage
- [ ] Add cross-tenant boundary attack tests

