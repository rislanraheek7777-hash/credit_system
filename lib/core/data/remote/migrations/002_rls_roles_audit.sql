-- =============================================================================
-- Migration: 002_rls_roles_audit.sql
-- Description: Reinforces server-enforced tenant isolation (RLS), role
--              privileges, and audit-immutability for Story 1.3.
-- Binds: Story 1.3 AC-1.3.1, AC-1.3.2, AC-1.3.3; AD-6.
-- Author: Migration owner role (cs_migration_owner) — NOT superuser.
-- Requires: PostgreSQL 16+. Must be run AFTER 001_initial_schema.sql.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- §0  BASELINE GUARD
--     Abort immediately if the expected base tables from 001 are absent.
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'shops'
    ) THEN
        RAISE EXCEPTION
            'Migration 002 prerequisite check failed: table public.shops not found. '
            'Ensure 001_initial_schema.sql has been applied before running 002.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'audit_events'
    ) THEN
        RAISE EXCEPTION
            'Migration 002 prerequisite check failed: table public.audit_events not found.';
    END IF;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- §ROLES  DATABASE ROLE CREATION (LEAST-PRIVILEGED)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
    -- cs_app: runtime application role
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'cs_app') THEN
        CREATE ROLE cs_app
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOINHERIT
            NOBYPASSRLS;
        COMMENT ON ROLE cs_app IS
            'Story 1.3: Runtime application role. Least-privileged: no SUPERUSER, no BYPASSRLS, NOINHERIT.';
    ELSE
        ALTER ROLE cs_app
            NOSUPERUSER
            NOBYPASSRLS
            NOINHERIT;
    END IF;

    -- cs_audit_writer: SECURITY DEFINER function owner (strictly NO BYPASSRLS)
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'cs_audit_writer') THEN
        CREATE ROLE cs_audit_writer
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOINHERIT
            NOBYPASSRLS;
        COMMENT ON ROLE cs_audit_writer IS
            'Story 1.3: Owns SECURITY DEFINER functions. Holds INSERT-only on audit_events. NO BYPASSRLS.';
    ELSE
        ALTER ROLE cs_audit_writer
            NOSUPERUSER
            NOBYPASSRLS
            NOINHERIT;
    END IF;

    -- cs_audit_admin: read-only compliance/auditor role
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'cs_audit_admin') THEN
        CREATE ROLE cs_audit_admin
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOINHERIT
            NOBYPASSRLS;
        COMMENT ON ROLE cs_audit_admin IS
            'Story 1.3: Read-only auditor role. SELECT on audit_events only.';
    ELSE
        ALTER ROLE cs_audit_admin
            NOSUPERUSER
            NOBYPASSRLS
            NOINHERIT;
    END IF;

    -- cs_migration_owner: migration execution role check
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'cs_migration_owner') THEN
        RAISE WARNING
            'Role cs_migration_owner does not exist. '
            'A DBA must create it with CREATEROLE before applying this migration in production.';
    END IF;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- §GRANTS  SCHEMA-LEVEL USAGE AND PERMISSIONS
-- ─────────────────────────────────────────────────────────────────────────────

GRANT USAGE ON SCHEMA public TO cs_app;

-- cs_app permissions on tenant business tables:
GRANT SELECT, UPDATE ON TABLE public.shops TO cs_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.app_users TO cs_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.sync_queue TO cs_app;

-- audit_events: cs_app gets SELECT only (read own shop audit logs under RLS);
-- direct INSERT, UPDATE, and DELETE are DENIED to cs_app.
GRANT SELECT ON TABLE public.audit_events TO cs_app;

-- cs_audit_writer needs INSERT on audit_events and SELECT on shops (for existence checks)
GRANT USAGE  ON SCHEMA public              TO cs_audit_writer;
GRANT INSERT ON TABLE  public.audit_events TO cs_audit_writer;
GRANT SELECT ON TABLE  public.shops        TO cs_audit_writer;

-- cs_audit_admin: read-only on audit_events
GRANT USAGE  ON SCHEMA public              TO cs_audit_admin;
GRANT SELECT ON TABLE  public.audit_events TO cs_audit_admin;

-- ─────────────────────────────────────────────────────────────────────────────
-- §CONTEXT  TENANT CONTEXT FUNCTIONS
--
-- SECURITY ARCHITECTURE & TRUST BOUNDARY:
-- Option A assumes a trusted application tier. In PostgreSQL, custom GUCs
-- (app.current_shop_id) cannot be privilege-restricted; an actor with arbitrary
-- SQL execution under cs_app can set this GUC directly. True authorization
-- requires the trusted application backend to verify JWT claims and bind the
-- validated shop ID to transactions. Validating existence in public.shops
-- does NOT constitute authorization.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.cs_set_tenant_context(p_shop_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
    v_shop_uuid uuid;
    v_exists boolean;
BEGIN
    -- 1. Input validation: reject NULL, empty, and non-UUID strings before casting
    IF p_shop_id IS NULL OR p_shop_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RAISE EXCEPTION 'cs_set_tenant_context: Invalid tenant UUID format: %', p_shop_id
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    v_shop_uuid := p_shop_id::uuid;

    -- 2. Set transaction-local session variable (is_local = true)
    -- Must set locally before query so RLS on public.shops evaluates it
    PERFORM pg_catalog.set_config('app.current_shop_id', p_shop_id, true);

    -- 3. Shop existence check under FORCE ROW LEVEL SECURITY
    -- cs_audit_writer executes this query under FORCE RLS. The active policy
    -- permits reading the shop row matching current_setting('app.current_shop_id', true)::uuid.
    SELECT EXISTS (
        SELECT 1 FROM public.shops WHERE id = v_shop_uuid
    ) INTO v_exists;

    -- 4. Fail-closed if shop row is absent
    IF NOT v_exists THEN
        RAISE EXCEPTION 'cs_set_tenant_context: Tenant shop % does not exist or access denied', p_shop_id
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
END;
$$;

ALTER FUNCTION public.cs_set_tenant_context(text) OWNER TO cs_audit_writer;

COMMENT ON FUNCTION public.cs_set_tenant_context(text) IS
    'Story 1.3: Validates UUID format, sets transaction-local app.current_shop_id, '
    'and verifies shop existence under FORCE RLS. Owned by cs_audit_writer.';

-- ─────────────────────────────────────────────────────────────────────────────
-- §RESET  TENANT CONTEXT RESET FUNCTION
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.cs_reset_tenant_context()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
BEGIN
    PERFORM pg_catalog.set_config('app.current_shop_id', '', false);
END;
$$;

ALTER FUNCTION public.cs_reset_tenant_context() OWNER TO cs_audit_writer;

REVOKE EXECUTE ON FUNCTION public.cs_set_tenant_context(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cs_reset_tenant_context()    FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.cs_set_tenant_context(text) TO cs_app;
GRANT EXECUTE ON FUNCTION public.cs_reset_tenant_context()    TO cs_app;
GRANT EXECUTE ON FUNCTION public.cs_set_tenant_context(text) TO cs_audit_writer;
GRANT EXECUTE ON FUNCTION public.cs_reset_tenant_context()    TO cs_audit_writer;

-- ─────────────────────────────────────────────────────────────────────────────
-- §RLS  ENABLE AND FORCE ROW-LEVEL SECURITY ON ALL TENANT TABLES
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.shops        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shops        FORCE  ROW LEVEL SECURITY;

ALTER TABLE public.app_users    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_users    FORCE  ROW LEVEL SECURITY;

ALTER TABLE public.audit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_events FORCE  ROW LEVEL SECURITY;

ALTER TABLE public.sync_queue   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_queue   FORCE  ROW LEVEL SECURITY;

-- ─────────────────────────────────────────────────────────────────────────────
-- §POLICIES  TENANT ISOLATION POLICIES (SAFE REGEX GUARDS & WITH CHECK)
-- ─────────────────────────────────────────────────────────────────────────────

-- shops: Explicit WITH CHECK ensures updates or writes conform to current_shop_id
DROP POLICY IF EXISTS shops_tenant_isolation_policy ON public.shops;
CREATE POLICY shops_tenant_isolation_policy ON public.shops
    FOR ALL
    USING (
        id = (
            CASE
                WHEN nullif(pg_catalog.current_setting('app.current_shop_id', true), '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                THEN pg_catalog.current_setting('app.current_shop_id', true)::uuid
                ELSE NULL
            END
        )
    )
    WITH CHECK (
        id = (
            CASE
                WHEN nullif(pg_catalog.current_setting('app.current_shop_id', true), '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                THEN pg_catalog.current_setting('app.current_shop_id', true)::uuid
                ELSE NULL
            END
        )
    );

-- app_users
DROP POLICY IF EXISTS app_users_tenant_isolation_policy ON public.app_users;
CREATE POLICY app_users_tenant_isolation_policy ON public.app_users
    FOR ALL
    USING (
        shop_id = (
            CASE
                WHEN nullif(pg_catalog.current_setting('app.current_shop_id', true), '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                THEN pg_catalog.current_setting('app.current_shop_id', true)::uuid
                ELSE NULL
            END
        )
    )
    WITH CHECK (
        shop_id = (
            CASE
                WHEN nullif(pg_catalog.current_setting('app.current_shop_id', true), '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                THEN pg_catalog.current_setting('app.current_shop_id', true)::uuid
                ELSE NULL
            END
        )
    );

-- audit_events
DROP POLICY IF EXISTS audit_events_tenant_isolation_policy ON public.audit_events;
CREATE POLICY audit_events_tenant_isolation_policy ON public.audit_events
    FOR ALL
    USING (
        shop_id = (
            CASE
                WHEN nullif(pg_catalog.current_setting('app.current_shop_id', true), '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                THEN pg_catalog.current_setting('app.current_shop_id', true)::uuid
                ELSE NULL
            END
        )
    )
    WITH CHECK (
        shop_id = (
            CASE
                WHEN nullif(pg_catalog.current_setting('app.current_shop_id', true), '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                THEN pg_catalog.current_setting('app.current_shop_id', true)::uuid
                ELSE NULL
            END
        )
    );

-- sync_queue
DROP POLICY IF EXISTS sync_queue_tenant_isolation_policy ON public.sync_queue;
CREATE POLICY sync_queue_tenant_isolation_policy ON public.sync_queue
    FOR ALL
    USING (
        shop_id = (
            CASE
                WHEN nullif(pg_catalog.current_setting('app.current_shop_id', true), '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                THEN pg_catalog.current_setting('app.current_shop_id', true)::uuid
                ELSE NULL
            END
        )
    )
    WITH CHECK (
        shop_id = (
            CASE
                WHEN nullif(pg_catalog.current_setting('app.current_shop_id', true), '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                THEN pg_catalog.current_setting('app.current_shop_id', true)::uuid
                ELSE NULL
            END
        )
    );

-- ─────────────────────────────────────────────────────────────────────────────
-- §AUDIT-IMMUTABILITY  REINFORCE reject_audit_tampering TRIGGER
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.reject_audit_tampering()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
BEGIN
    RAISE EXCEPTION
        'Audit trail records are append-only and cannot be modified or deleted. Operation=%, Table=audit_events', TG_OP
        USING ERRCODE = 'insufficient_privilege';
END;
$$;

ALTER FUNCTION public.reject_audit_tampering() OWNER TO cs_audit_writer;

COMMENT ON FUNCTION public.reject_audit_tampering() IS
    'Story 1.3: Unconditionally rejects UPDATE or DELETE on audit_events. '
    'Owned by cs_audit_writer. audit_admin and cs_app are both blocked.';

DROP TRIGGER IF EXISTS trg_audit_immutable ON public.audit_events;
CREATE TRIGGER trg_audit_immutable
    BEFORE UPDATE OR DELETE ON public.audit_events
    FOR EACH ROW
    EXECUTE FUNCTION public.reject_audit_tampering();

-- ─────────────────────────────────────────────────────────────────────────────
-- §VERIFY  POST-MIGRATION ASSERTIONS
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_tables text[] := ARRAY['shops', 'app_users', 'audit_events', 'sync_queue'];
    v_table text;
    v_rls boolean;
    v_forced boolean;
BEGIN
    -- 1. Verify forced RLS on all tenant tables
    FOREACH v_table IN ARRAY v_tables LOOP
        SELECT rowsecurity, forcepolicies
        INTO   v_rls, v_forced
        FROM   pg_class
        WHERE  relname = v_table
          AND  relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');

        IF NOT v_rls THEN
            RAISE EXCEPTION '§VERIFY FAILED: RLS not enabled on public.%.', v_table;
        END IF;
        IF NOT v_forced THEN
            RAISE EXCEPTION '§VERIFY FAILED: FORCE ROW LEVEL SECURITY not set on public.%.', v_table;
        END IF;
    END LOOP;

    -- 2. Verify cs_app is not a superuser and does not bypass RLS
    IF EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'cs_app' AND (rolsuper OR rolbypassrls)
    ) THEN
        RAISE EXCEPTION '§VERIFY FAILED: cs_app must not have SUPERUSER or BYPASSRLS.';
    END IF;

    -- 3. Verify cs_audit_writer does NOT have BYPASSRLS
    IF EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'cs_audit_writer' AND rolbypassrls
    ) THEN
        RAISE EXCEPTION '§VERIFY FAILED: cs_audit_writer must not have BYPASSRLS.';
    END IF;

    -- 4. Verify cs_app does not have INSERT or DELETE on shops
    IF EXISTS (
        SELECT 1 FROM information_schema.table_privileges
        WHERE table_schema = 'public'
          AND table_name   = 'shops'
          AND grantee      = 'cs_app'
          AND privilege_type IN ('INSERT', 'DELETE')
    ) THEN
        RAISE EXCEPTION '§VERIFY FAILED: cs_app must not have INSERT or DELETE on shops.';
    END IF;

    -- 5. Verify function ownerships
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_roles r ON r.oid = p.proowner
        WHERE p.proname = 'reject_audit_tampering' AND r.rolname = 'cs_audit_writer'
    ) THEN
        RAISE EXCEPTION '§VERIFY FAILED: reject_audit_tampering must be owned by cs_audit_writer.';
    END IF;

    RAISE NOTICE '§VERIFY PASSED: All 002_rls_roles_audit.sql post-migration assertions succeeded.';
END;
$$;
