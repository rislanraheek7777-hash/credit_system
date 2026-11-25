-- =============================================================================
-- Rollback Migration: 003_credential_recovery_down.sql
-- Description: Removes ONLY the objects introduced by 003_credential_recovery.sql.
--              001/002 objects are never touched.
-- =============================================================================

REVOKE EXECUTE ON FUNCTION public.cs_resolve_recovery_identity(text, text) FROM cs_app;
REVOKE EXECUTE ON FUNCTION public.cs_record_recovery_audit(uuid, integer, text, uuid, text, text, text) FROM cs_app;
REVOKE EXECUTE ON FUNCTION public.cs_create_recovery_challenge(uuid, uuid, text, text, uuid, uuid) FROM cs_app;
REVOKE EXECUTE ON FUNCTION public.cs_finalize_recovery_challenge(uuid, text, text) FROM cs_app;
REVOKE EXECUTE ON FUNCTION public.cs_load_recovery_for_reference(uuid) FROM cs_app;

DROP FUNCTION IF EXISTS public.cs_load_recovery_for_reference(uuid);
DROP FUNCTION IF EXISTS public.cs_finalize_recovery_challenge(uuid, text, text);
DROP FUNCTION IF EXISTS public.cs_create_recovery_challenge(uuid, uuid, text, text, uuid, uuid);
DROP FUNCTION IF EXISTS public.cs_record_recovery_audit(uuid, integer, text, uuid, text, text, text);
DROP FUNCTION IF EXISTS public.cs_resolve_recovery_identity(text, text);

REVOKE SELECT, INSERT, DELETE ON TABLE public.credential_recovery_operations FROM cs_app;
DROP POLICY IF EXISTS credential_recovery_operations_tenant_isolation_policy
    ON public.credential_recovery_operations;
DROP TABLE IF EXISTS public.credential_recovery_operations CASCADE;

DROP POLICY IF EXISTS credential_recovery_challenges_tenant_isolation_policy
    ON public.credential_recovery_challenges;
DROP TABLE IF EXISTS public.credential_recovery_challenges CASCADE;

ALTER TABLE public.app_users DROP CONSTRAINT IF EXISTS uq_app_users_shop_email;
ALTER TABLE public.app_users DROP CONSTRAINT IF EXISTS uq_app_users_shop_phone;

-- Remove deterministic synthetic actor rows that no audit event references.
-- Rows already referenced by append-only audit_events must remain so those
-- foreign keys stay valid.
DELETE FROM public.app_users AS u
 WHERE substr(u.username, 1, 25) = '__system_recovery_actor__'
   AND NOT EXISTS (
       SELECT 1 FROM public.audit_events AS a WHERE a.actor_id = u.id
   );

DROP ROLE IF EXISTS cs_recovery_resolver;

-- Keep migration bookkeeping consistent: without this, a re-apply would see a
-- recorded version 3 and skip DDL that was just rolled back.
DELETE FROM public.schema_migrations WHERE version = 3;
