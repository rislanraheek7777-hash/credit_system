# Story 1.3 – Server‑Enforced PostgreSQL Tenant Isolation & Append‑Only Audit

**Epic**: epic‑1 (Credit Management System Core)

---

## 1. User Stories & Acceptance Criteria

| ID | User Story | Acceptance Criteria |
|----|------------|----------------------|
| 1.3.1 | As a **Shop Owner**, I want all tenant data to be isolated at the database layer so that I cannot see or modify another shop’s data. | - Attempts to SELECT/INSERT/UPDATE/DELETE rows belonging to a different `shop_id` return **zero rows** or **permission denied**.<br>- Automated integration tests exercising cross‑tenant operations all pass. |
| 1.3.2 | As a **Compliance Auditor**, I need an immutable, append‑only audit trail for all data changes, preserving the original record and metadata. | - All DML on business tables also writes an audit record to a dedicated `audit` schema.
- Audit rows cannot be UPDATE‑d or DELETE‑d by any role except a dedicated `audit_admin` role.
- Audit tables contain `created_at`, `operation`, `user_id`, `tenant_id`, and a JSONB `payload`. |
| 1.3.3 | As a **Developer**, I need a least‑privileged runtime role (`cs_app`) that can only perform tenant‑scoped operations and cannot bypass RLS. | - `cs_app` role lacks `SUPERUSER` and `BYPASSRLS` privileges.
- All application SQL runs under `cs_app`.

*All criteria are measurable via automated PostgreSQL 16+ integration tests (see Section 8).*

---

## 2. PostgreSQL Row‑Level Security (RLS) & Tenant‑Isolation Policies

1. **Enable RLS** on every tenant‑scoped table (e.g., `public.accounts`, `public.loans`, `public.transactions`).
2. **Policy naming convention**: `tenant_isolation_<table_name>`.
3. **Policy definitions** will reference a session variable `app.current_tenant_id` set by the application after authenticating the request.

```sql
-- Example for the `accounts` table
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_accounts ON public.accounts
    USING (shop_id = current_setting('app.current_tenant_id')::uuid)
    WITH CHECK (shop_id = current_setting('app.current_tenant_id')::uuid);
```

*All tables must have a non‑null `shop_id UUID NOT NULL` column.*

---

## 3. Secure Tenant Identity & Server‑Side Authorization

- **Never trust** `shop_id` values supplied directly by the client.
- Authentication flow:
  1. Client presents a JWT containing `sub` (user ID) and `tenant` (shop UUID).
  2. Server validates the JWT, resolves the tenant via an internal `users` table, and sets the session variable:

    ```sql
    SELECT set_config('app.current_tenant_id', tenant_uuid::text, true)
    FROM users WHERE id = <user_id>;
    ```
- All subsequent SQL statements automatically respect the RLS policies.
- **Assumption**: The JWT verification library is trusted and kept up‑to‑date.

---

## 4. `USING` & `WITH CHECK` Policies (Template)

| Table | `USING` Clause | `WITH CHECK` Clause |
|-------|----------------|----------------------|
| `accounts` | `shop_id = current_setting('app.current_tenant_id')::uuid` | Same as USING |
| `loans` | `shop_id = current_setting('app.current_tenant_id')::uuid` | Same as USING |
| `transactions` | `shop_id = current_setting('app.current_tenant_id')::uuid` | Same as USING |

### 1. Shared Reference Data Decisions

- **Tenant‑isolated business tables**: customers, loans, collateral, repayments, receipts, and all shop‑specific records must remain isolated per tenant.
- **Globally shared reference tables**: Currently no lookup tables (`countries`, `currencies`, `product_catalog`) are defined in the schema. They are identified as **candidates** pending confirmation and creation.
- **Action required**: Verify existence and intended scope of any lookup tables before exempting them from RLS.
### 2. Future Tenant‑Owned Tables (Deferred)

- **Tables not yet present**: `customers`, `loans`, `collateral`, `repayments`, `receipts`.
- **Tenant ownership requirement**: each row must include a non‑null `shop_id UUID NOT NULL` referencing `shops(id)`.
- **Foreign‑key constraint**: `shop_id` → `shops(id)` with `ON DELETE RESTRICT`.
- **RLS policy template** (to be applied once tables exist):
  ```sql
  ALTER TABLE public.<table_name> ENABLE ROW LEVEL SECURITY;
  CREATE POLICY tenant_isolation_<table_name> ON public.<table_name>
    USING (shop_id = current_setting('app.current_tenant_id')::uuid)
    WITH CHECK (shop_id = current_setting('app.current_tenant_id')::uuid);
  ```
- **Cross‑tenant integration tests** (to be added to the test suite once tables are created):
  1. SELECT rows of another tenant → returns `0 rows`.
  2. INSERT with mismatching `shop_id` → `ERROR: permission denied`.
  3. UPDATE/DELETE across tenants → blocked by `WITH CHECK`.
- **Action required**: when these tables are introduced, ensure the above constraints and tests are implemented before enabling tenant isolation.

---

## 5. Append‑Only Audit Records

1. **Audit schema**: `audit`.
2. **Audit tables** mirroring each business table with a `_audit` suffix (e.g., `audit.accounts_audit`).
3. **Trigger function** (template):

```sql
CREATE OR REPLACE FUNCTION audit.log_change() RETURNS trigger AS $$
BEGIN
  INSERT INTO audit.%s_audit (
    operation,
    changed_at,
    user_id,
    tenant_id,
    payload
  ) VALUES (
    TG_OP,
    now(),
    current_setting('app.current_user_id')::uuid,
    current_setting('app.current_tenant_id')::uuid,
    to_jsonb(NEW)
  );
  RETURN NEW; -- For INSERT/UPDATE, DELETE returns OLD (but we never DELETE audit rows)
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

4. **Attach trigger** to each table:

```sql
CREATE TRIGGER audit_accounts AFTER INSERT OR UPDATE ON public.accounts
FOR EACH ROW EXECUTE FUNCTION audit.log_change();
```

5. **Permissions**:
   - `cs_app` role: `INSERT`/`SELECT`/`UPDATE`/`DELETE` on business tables **only**; **NO** privileges on `audit` schema.
   - `audit_writer` role: `INSERT` on audit tables, used by the trigger (`SECURITY DEFINER`).
   - `audit_admin` role: `SELECT` on audit tables, `UPDATE`/`DELETE` ONLY for lawful data‑retention compliance.

---

## 6. Database Role Separation

| Role | Description | Privileges |
|------|-------------|------------|
| `cs_app` | Runtime application role | `CONNECT`, `SELECT/INSERT/UPDATE/DELETE` on business tables, **NO** `SUPERUSER`, **NO** `BYPASSRLS` |
| `audit_writer` | Owner of audit trigger functions (SECURITY DEFINER) | `INSERT` on `audit.*` tables |
| `audit_admin` | Auditors / compliance team | `SELECT` on `audit.*` (read‑only; any update/delete requires a documented emergency procedure) |
| `db_admin` | DBA / migration role | Full privileges, used only for migrations |

All roles are granted via `GRANT` statements; no role inherits another except `audit_writer` is set as the owner of trigger functions.

---

## 7. Migration & Rollback Considerations

1. **Migration steps** (run by `db_admin`):
   - Add `shop_id UUID NOT NULL` column to each existing table (default generated from existing `owner_id` mapping where applicable).
   - Populate `shop_id` for existing rows.
   - Enable RLS and create policies as per Section 2.
   - Create `audit` schema and tables.
   - Install trigger functions.
   - Grant role permissions.
2. **Rollback plan**:
   - Disable RLS (`ALTER TABLE … DISABLE ROW LEVEL SECURITY`).
   - Drop audit triggers and tables (retain data in a backup schema).
   - Remove `shop_id` column if no longer needed.
   - Re‑grant previous privileges.
3. **Assumption**: No existing foreign‑key constraints reference `shop_id` before migration. If they do, they must be updated in the migration script.

---

## 8. PostgreSQL 16+ Integration Tests

- **Test harness**: `pgTAP` or a language‑specific driver (Rust, Go, Python) using `DATABASE_URL`.
- **Scenarios**:
  1. **Cross‑tenant SELECT** – User from Tenant A attempts to read rows belonging to Tenant B → returns `0 rows`.
  2. **Cross‑tenant INSERT** – Attempt to insert a row with `shop_id` of another tenant → `ERROR: permission denied` due to `WITH CHECK`.
  3. **Cross‑tenant UPDATE/DELETE** – Same as above, expect `0 rows` or permission error.
  4. **Audit creation** – Verify an audit row is inserted for each successful INSERT/UPDATE.
  5. **Audit immutability** – Attempts by `cs_app` to UPDATE/DELETE audit rows must fail.
  6. **Role enforcement** – Confirm `cs_app` cannot set `BYPASSRLS` or alter policies.

**Test strategy**:
- Tests are guarded by `if (os.getenv('DATABASE_URL'))` – when missing, they are reported as **SKIPPED** with a clear message.
- CI pipeline includes a dedicated PostgreSQL service; the job must **fail** if the database is unavailable.

---

## 9. `DATABASE_URL`‑Based Test Strategy

```text
# Local developer run
export DATABASE_URL=postgres://cs_app:password@localhost/credit_system_dev
pytest -m integration

# CI job (GitHub Actions, GitLab CI, etc.)
services:
  postgres:
    image: postgres:16-alpine
    env:
      POSTGRES_USER: cs_app
      POSTGRES_PASSWORD: secret
      POSTGRES_DB: credit_system_ci
```
- When `DATABASE_URL` is unset, the test runner prints:
  > "Skipping PostgreSQL integration tests – DATABASE_URL not set."
- The CI job declares the PostgreSQL service as **required**; if the service fails to start, the job fails.

---

## 10. Security Risks, Assumptions & Open Questions

| Risk / Assumption | Description | Mitigation / Decision Needed |
|-------------------|-------------|------------------------------|
| **Trust in JWT** | We assume the JWT signature verification is uncompromised. | Review key rotation policy. |
| **Cross‑tenant reference data** | Some lookup tables may need to be shared (e.g., product catalog). | Identify such tables and exclude them from RLS. |
| **Tenant ID leakage via error messages** | PostgreSQL may expose `permission denied` vs `no rows`. | Ensure error handling masks tenant existence. |
| **Performance impact of RLS** | Large tenant datasets could suffer query planner overhead. | Benchmark typical queries; consider partial indexes on `shop_id`. |
| **Audit data growth** | Append‑only tables will grow indefinitely. | Define retention policy and archiving strategy (open for discussion). |
| **Migration data back‑fill** | Populating `shop_id` for existing rows may require business logic. | Gather mapping rules; may need a temporary ETL job. |
| **Audit admin privileges** | Too broad access could undermine immutability. | Scope `audit_admin` to read‑only unless compliance requires delete. |

---

*Prepared based on existing Story 1.2 spec, sprint‑status.yaml, and architecture briefs. No code changes have been made.*
