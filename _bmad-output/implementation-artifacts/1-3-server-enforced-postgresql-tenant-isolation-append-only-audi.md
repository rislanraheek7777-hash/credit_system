# Story: 1.3 Server-Enforced PostgreSQL Tenant Isolation & Append-Only Audit Trigger

Status: in-progress

## Story

As a Platform Security Officer and Shop Owner,
I want server-enforced PostgreSQL Row-Level Security (RLS) driven strictly by trusted authentication context, alongside a database trigger that rejects all UPDATE and DELETE operations on audit logs,
So that cross-tenant data leakage is physically prevented at the database engine level and the audit trail is immutable even against elevated application roles.

## Acceptance Criteria

- RLS enabled + forced on all multi-tenant tables.
- RLS policies enforce shop_id = current_setting('app.current_shop_id', true)::uuid.
- shop_id derived strictly from verified JWT; client-supplied ignored.
- SET LOCAL app.current_shop_id within transaction.
- Application role NOBYPASSRLS; SET LOCAL scoped to transaction.
- audit_events append-only trigger rejects UPDATE/DELETE.

## Tasks

- [ ] Wire Dart backend to set tenant context per transaction.
- [ ] Add integration tests for cross-tenant isolation and audit immutability.

## Dev Notes

Migration 002_rls_roles_audit.sql already defines roles, functions, and trigger.

