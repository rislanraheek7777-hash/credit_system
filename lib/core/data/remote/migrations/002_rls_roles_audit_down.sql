-- =============================================================================
-- Rollback Migration: 002_rls_roles_audit_down.sql
-- Description: Reverts Story 1.3 policies and grants safely.
--
-- MANDATORY SAFETY CONSTRAINTS:
--   1. RLS is NEVER disabled. FORCE ROW LEVEL SECURITY remains set on all tables.
--   2. audit_events rows are NEVER deleted.
--   3. Audit trigger (trg_audit_immutable) and reject_audit_tampering() are NOT dropped.
--   4. Roles (cs_app, cs_audit_writer, cs_audit_admin) are NOT dropped to avoid
--      destroying pre-existing roles or failing due to cluster dependencies.
--   5. reject_audit_tampering() ownership is NOT speculatively reassigned.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- §ROLLBACK-GUARD  Fail-closed pre-check
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        JOIN   pg_class ON pg_class.oid = pg_trigger.tgrelid
        WHERE  pg_class.relname = 'audit_events'
          AND  tgname = 'trg_audit_immutable'
    ) THEN
        RAISE EXCEPTION
            'ROLLBACK ABORTED: trg_audit_immutable is missing from audit_events. '
            'Database state is unexpected. Manual DBA recovery is required.';
    END IF;

    RAISE NOTICE 'Rollback pre-checks passed. Proceeding with 002 rollback.';
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- §DROP-FUNCTIONS  Drop context-setting functions created in 002
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.cs_set_tenant_context(text);
DROP FUNCTION IF EXISTS public.cs_reset_tenant_context();

-- ─────────────────────────────────────────────────────────────────────────────
-- §REVOKE-GRANTS  Revoke grants added in 002
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'cs_app') THEN
        REVOKE SELECT, UPDATE                  ON TABLE public.shops        FROM cs_app;
        REVOKE SELECT, INSERT, UPDATE, DELETE  ON TABLE public.app_users    FROM cs_app;
        REVOKE SELECT, INSERT, UPDATE, DELETE  ON TABLE public.sync_queue   FROM cs_app;
        REVOKE SELECT                          ON TABLE public.audit_events FROM cs_app;
        REVOKE USAGE                           ON SCHEMA public             FROM cs_app;
    END IF;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'cs_audit_writer') THEN
        REVOKE INSERT ON TABLE public.audit_events FROM cs_audit_writer;
        REVOKE SELECT ON TABLE public.shops        FROM cs_audit_writer;
        REVOKE USAGE  ON SCHEMA public             FROM cs_audit_writer;
    END IF;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'cs_audit_admin') THEN
        REVOKE SELECT ON TABLE public.audit_events FROM cs_audit_admin;
        REVOKE USAGE  ON SCHEMA public             FROM cs_audit_admin;
    END IF;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- §RESTORE-POLICIES  Recreate RLS policies in their 001-era baseline
-- ─────────────────────────────────────────────────────────────────────────────

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
    );

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
    );

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
    );

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
    );

-- ─────────────────────────────────────────────────────────────────────────────
-- §ROLLBACK-VERIFY  Final invariant checks
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_tables text[] := ARRAY['shops', 'app_users', 'audit_events', 'sync_queue'];
    v_table text;
    v_rls boolean;
    v_forced boolean;
BEGIN
    FOREACH v_table IN ARRAY v_tables LOOP
        SELECT rowsecurity, forcepolicies
        INTO   v_rls, v_forced
        FROM   pg_class
        WHERE  relname = v_table
          AND  relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');

        IF NOT v_rls THEN
            RAISE EXCEPTION 'ROLLBACK VERIFY FAILED: RLS not enabled on public.%.', v_table;
        END IF;
        IF NOT v_forced THEN
            RAISE EXCEPTION 'ROLLBACK VERIFY FAILED: FORCE ROW LEVEL SECURITY missing on public.%.', v_table;
        END IF;
    END LOOP;

    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        JOIN   pg_class ON pg_class.oid = pg_trigger.tgrelid
        WHERE  pg_class.relname = 'audit_events'
          AND  tgname = 'trg_audit_immutable'
    ) THEN
        RAISE EXCEPTION 'ROLLBACK VERIFY FAILED: trg_audit_immutable missing after rollback.';
    END IF;

    RAISE NOTICE 'ROLLBACK VERIFY PASSED: Invariants confirmed. RLS and audit preserved.';
    RAISE NOTICE 'Residual State: Roles cs_app, cs_audit_writer, cs_audit_admin preserved in cluster with grants revoked.';
END;
$$;
