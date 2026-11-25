-- =============================================================================
-- Migration: 003_credential_recovery.sql
-- Description: Server-authoritative, two-step staff credential recovery.
--              Adds single-use OTP challenges (hashed at rest, tenant-scoped,
--              idempotent), closes the app_users contact-identifier collision,
--              and exposes two narrowly-scoped SECURITY DEFINER resolvers so an
--              unauthenticated caller can be resolved without ever trusting a
--              client-supplied shop id.
-- Binds: Story 1.10 (Secure Staff Credential Recovery); AD-1, AD-4, AD-6.
-- Requires: PostgreSQL 16+. Must be run AFTER 002_rls_roles_audit.sql.
-- NOTE: 001 and 002 are checksum-guarded and MUST NOT be modified.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- §0  PREREQUISITE GUARD
-- ─────────────────────────────────────────────────────────────────────────────
DO $guard$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'app_users'
    ) THEN
        RAISE EXCEPTION
            'Migration 003 prerequisite check failed: public.app_users not found. '
            'Ensure 001_initial_schema.sql has been applied before 003.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'cs_app'
    ) THEN
        RAISE EXCEPTION
            'Migration 003 prerequisite check failed: role cs_app not found. '
            'Ensure 002_rls_roles_audit.sql has been applied before 003.';
    END IF;
END;
$guard$;

-- ─────────────────────────────────────────────────────────────────────────────
-- §1  CHALLENGE TABLE
--     The OTP is stored ONLY as a SHA-256 digest of a high-entropy random
--     token. No plaintext OTP, password, or credential is ever persisted here.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE public.credential_recovery_challenges (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id             UUID NOT NULL REFERENCES public.shops(id) ON DELETE RESTRICT,
    user_id             UUID NOT NULL REFERENCES public.app_users(id) ON DELETE RESTRICT,
    channel             VARCHAR(10) NOT NULL CHECK (channel IN ('email', 'sms')),
    destination         VARCHAR(255),
    delivery_reference_hash VARCHAR(64),
    otp_hash            VARCHAR(64) NOT NULL CHECK (otp_hash ~ '^[0-9a-f]{64}$'),
    expires_at          TIMESTAMPTZ NOT NULL,
    attempts            INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    consumed_at         TIMESTAMPTZ,
    client_operation_id UUID NOT NULL,
    idempotency_key     UUID NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_recovery_expiry CHECK (expires_at > created_at),
    CONSTRAINT ck_recovery_attempts CHECK (attempts <= 5),
    CONSTRAINT uq_recovery_client_operation UNIQUE (client_operation_id),
    CONSTRAINT uq_recovery_idempotency UNIQUE (idempotency_key)
);

CREATE INDEX idx_recovery_shop_channel_created
    ON public.credential_recovery_challenges (shop_id, channel, created_at DESC);
CREATE INDEX idx_recovery_shop_user
    ON public.credential_recovery_challenges (shop_id, user_id);

COMMENT ON TABLE public.credential_recovery_challenges IS
    'Story 1.10: Single-use, short-lived, hashed OTP challenges for unauthenticated staff credential recovery. Never contains a plaintext OTP or password.';

-- Idempotency ledger. Rate-limited requests never create a challenge, but the
-- stored operation id and idempotency key must still be authoritative on every
-- branch. This ledger is the durable record for those keys.
CREATE TABLE public.credential_recovery_operations (
    client_operation_id UUID PRIMARY KEY,
    idempotency_key     UUID NOT NULL UNIQUE,
    shop_id             UUID NOT NULL REFERENCES public.shops(id) ON DELETE RESTRICT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_recovery_operations_shop_created
    ON public.credential_recovery_operations (shop_id, created_at DESC);

COMMENT ON TABLE public.credential_recovery_operations IS
    'Story 1.11: Durable operation/idempotency key ledger for every recovery request branch.';

-- ─────────────────────────────────────────────────────────────────────────────
-- §2  TENANT ISOLATION (FORCE RLS) ON THE NEW TABLE
--     Same safe UUID regex guard as migration 002 — no client-supplied
--     shop_id is ever used as tenant context.
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.credential_recovery_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.credential_recovery_challenges FORCE  ROW LEVEL SECURITY;

CREATE POLICY credential_recovery_challenges_tenant_isolation_policy
    ON public.credential_recovery_challenges
    FOR ALL
    USING (
        shop_id = (
            CASE
                WHEN nullif(pg_catalog.current_setting('app.current_shop_id', true), '')
                     ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                THEN pg_catalog.current_setting('app.current_shop_id', true)::uuid
                ELSE NULL
            END
        )
    )
    WITH CHECK (
        shop_id = (
            CASE
                WHEN nullif(pg_catalog.current_setting('app.current_shop_id', true), '')
                     ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                THEN pg_catalog.current_setting('app.current_shop_id', true)::uuid
                ELSE NULL
            END
        )
    );

-- cs_app gets only the privileges required by the two recovery operations.
-- Audit writes continue to go exclusively through cs_record_audit_event.
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.credential_recovery_challenges TO cs_app;

ALTER TABLE public.credential_recovery_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.credential_recovery_operations FORCE  ROW LEVEL SECURITY;

CREATE POLICY credential_recovery_operations_tenant_isolation_policy
    ON public.credential_recovery_operations
    FOR ALL
    USING (
        shop_id = (
            CASE
                WHEN nullif(pg_catalog.current_setting('app.current_shop_id', true), '')
                     ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                THEN pg_catalog.current_setting('app.current_shop_id', true)::uuid
                ELSE NULL
            END
        )
    )
    WITH CHECK (
        shop_id = (
            CASE
                WHEN nullif(pg_catalog.current_setting('app.current_shop_id', true), '')
                     ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                THEN pg_catalog.current_setting('app.current_shop_id', true)::uuid
                ELSE NULL
            END
        )
    );

GRANT SELECT, INSERT, DELETE ON TABLE public.credential_recovery_operations TO cs_app;

-- ─────────────────────────────────────────────────────────────────────────────
-- §3  CLOSE THE LOGIN-IDENTIFIER COLLISION
--     Unique per tenant. Pre-existing duplicates cause ADD CONSTRAINT to fail
--     loudly (fail-closed) so a DBA must resolve them before release.
--     SQL NULLs are distinct, so staff without a contact remain enrollable.
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.app_users
    ADD CONSTRAINT uq_app_users_shop_email UNIQUE (shop_id, email);
ALTER TABLE public.app_users
    ADD CONSTRAINT uq_app_users_shop_phone UNIQUE (shop_id, phone);

-- ─────────────────────────────────────────────────────────────────────────────
-- §4  NARROW UNAUTHENTICATED RESOLVERS
--     A dedicated NOLOGIN role with BYPASSRLS owns the two SECURITY DEFINER
--     resolvers. cs_app cannot assume this role (NOINHERIT) and has no direct
--     cross-tenant table privileges; it can only call these two functions,
--     which return the minimum data required and never a username or hash.
--     match_count > 1 signals an ambiguous/cross-tenant collision: the caller
--     must return the generic response and append a Category 14 audit event.
-- ─────────────────────────────────────────────────────────────────────────────
DO $resolver_role$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'cs_recovery_resolver') THEN
        CREATE ROLE cs_recovery_resolver
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOINHERIT
            BYPASSRLS;
        COMMENT ON ROLE cs_recovery_resolver IS
            'Story 1.10: Owns only the two narrow SECURITY DEFINER recovery resolvers. NOLOGIN, NOINHERIT; no direct grants to cs_app.';
    END IF;
END;
$resolver_role$;

CREATE OR REPLACE FUNCTION public.cs_resolve_recovery_identity(
    p_identifier text,
    p_channel text
)
RETURNS TABLE (shop_id uuid, user_id uuid, destination text, match_count integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $fn$
DECLARE
    v_normalized text;
    v_count integer;
    v_shop uuid;
    v_user uuid;
    v_dest text;
BEGIN
    IF p_identifier IS NULL OR btrim(p_identifier) = '' OR p_channel NOT IN ('email', 'sms') THEN
        RETURN;
    END IF;

    -- Case-insensitive for usernames on both channels; harmless for phone
    -- numbers, which are digits only.
    v_normalized := lower(btrim(p_identifier));

    SELECT count(*)::integer
      INTO v_count
      FROM public.app_users AS u
     WHERE u.is_active
       AND u.password_hash IS NOT NULL
       AND (
            CASE p_channel
                WHEN 'email' THEN
                    nullif(btrim(u.email), '') IS NOT NULL
                    AND (lower(btrim(u.username)) = v_normalized OR lower(btrim(u.email)) = v_normalized)
                WHEN 'sms' THEN
                    nullif(btrim(u.phone), '') IS NOT NULL
                    AND (lower(btrim(u.username)) = v_normalized OR btrim(u.phone) = v_normalized)
                ELSE false
            END
       );

    IF v_count = 0 THEN
        RETURN;
    END IF;

    SELECT u.shop_id,
           u.id,
           CASE p_channel WHEN 'email' THEN btrim(u.email) ELSE btrim(u.phone) END
      INTO v_shop, v_user, v_dest
      FROM public.app_users AS u
     WHERE u.is_active
       AND u.password_hash IS NOT NULL
       AND (
            CASE p_channel
                WHEN 'email' THEN
                    nullif(btrim(u.email), '') IS NOT NULL
                    AND (lower(btrim(u.username)) = v_normalized OR lower(btrim(u.email)) = v_normalized)
                WHEN 'sms' THEN
                    nullif(btrim(u.phone), '') IS NOT NULL
                    AND (lower(btrim(u.username)) = v_normalized OR btrim(u.phone) = v_normalized)
                ELSE false
            END
       )
     ORDER BY u.created_at, u.id
     LIMIT 1;

    shop_id := v_shop;
    user_id := v_user;
    destination := v_dest;
    match_count := v_count;
    RETURN NEXT;
END;
$fn$;

ALTER FUNCTION public.cs_resolve_recovery_identity(text, text) OWNER TO cs_recovery_resolver;

COMMENT ON FUNCTION public.cs_resolve_recovery_identity(text, text) IS
    'Story 1.10: Resolves a recovery identifier to one enrolled staff account. Returns no username, hash, or OTP. match_count > 1 means ambiguous/cross-tenant collision.';

REVOKE EXECUTE ON FUNCTION public.cs_resolve_recovery_identity(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cs_resolve_recovery_identity(text, text) TO cs_app;

-- ─────────────────────────────────────────────────────────────────────────────
-- §4b UNAUTHENTICATED AUDIT ACTOR + ATOMIC CHALLENGE CREATION
--     Unauthenticated recovery events must not attribute the victim as actor.
--     A reserved system actor row (inactive, no password) is created on demand
--     so audit_events.actor_id keeps its FK integrity under RLS.
--
--     Rate limiting and idempotency are enforced INSIDE SQL under a tenant+
--     channel advisory transaction lock, closing the SELECT/INSERT race that
--     a Dart-only count would leave open.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cs_record_recovery_audit(
    p_shop_id uuid,
    p_event_category integer,
    p_action_type text,
    p_target_user_id uuid,
    p_reason text,
    p_client_ip text,
    p_user_agent text
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $fn$
DECLARE
    v_digest text;
    v_actor uuid;
    v_actor_username text;
BEGIN
    -- Deterministic tenant-scoped system actor (UUIDv5-shaped): the same
    -- tenant always maps to the same actor, and different tenants never share
    -- one. md5() is available in pg_catalog and needs no extension.
    v_digest := md5(p_shop_id::text || '|cs_recovery_system_actor');
    v_actor := (
        substr(v_digest, 1, 8) || '-' ||
        substr(v_digest, 9, 4) || '-5' ||
        substr(v_digest, 13, 3) || '-8' ||
        substr(v_digest, 17, 3) || '-' ||
        substr(v_digest, 20, 12)
    )::uuid;
    -- Include the tenant in the reserved username so no two shops collide.
    v_actor_username := '__system_recovery_actor__' || p_shop_id::text;

    -- Fail closed if the synthetic id or reserved username is already held by
    -- a real account; otherwise the audit actor FK would silently break.
    IF EXISTS (
        SELECT 1 FROM public.app_users AS u
         WHERE u.id = v_actor
           AND (u.is_active OR u.password_hash IS NOT NULL)
    ) THEN
        RAISE EXCEPTION '§FAIL: recovery system actor id collides with a real account';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.app_users AS u
         WHERE u.shop_id = p_shop_id
           AND btrim(u.username) = v_actor_username
           AND u.id <> v_actor
    ) THEN
        RAISE EXCEPTION '§FAIL: recovery system actor username is already in use';
    END IF;

    INSERT INTO public.app_users (
        id, shop_id, username, full_name, role,
        is_active, session_version, created_at, updated_at
    ) VALUES (
        v_actor,
        p_shop_id, v_actor_username, 'System Recovery Actor', 'cashier',
        FALSE, 1, NOW(), NOW()
    ) ON CONFLICT (id) DO NOTHING;

    IF NOT EXISTS (
        SELECT 1 FROM public.app_users AS u
         WHERE u.id = v_actor
           AND btrim(u.username) = v_actor_username
           AND NOT u.is_active
           AND u.password_hash IS NULL
    ) THEN
        RAISE EXCEPTION '§FAIL: recovery system actor row is not usable';
    END IF;

    PERFORM public.cs_record_audit_event(
        p_shop_id, p_event_category, p_action_type,
        v_actor,
        'app_user', p_target_user_id,
        NULL, NULL, p_reason, p_client_ip, p_user_agent
    );
END;
$fn$;

COMMENT ON FUNCTION public.cs_record_recovery_audit(uuid, integer, text, uuid, text, text, text) IS
    'Story 1.10: Appends an unauthenticated recovery audit using a deterministic per-tenant system actor rather than the victim user id.';

CREATE OR REPLACE FUNCTION public.cs_create_recovery_challenge(
    p_shop_id uuid,
    p_user_id uuid,
    p_channel text,
    p_destination text,
    p_client_operation_id uuid,
    p_idempotency_key uuid
)
RETURNS TABLE (stored_operation_id uuid, stored_idempotency_key uuid, status text)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $fn$
DECLARE
    v_existing uuid;
    v_stored_idem uuid;
    v_count integer;
BEGIN
    -- Serialize rate-limit accounting for this tenant + channel.
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(p_shop_id::text || ':' || p_channel, 0)
    );

    SELECT c.client_operation_id, c.idempotency_key
      INTO v_existing, v_stored_idem
      FROM public.credential_recovery_challenges AS c
     WHERE c.client_operation_id = p_client_operation_id
        OR c.idempotency_key = p_idempotency_key
     ORDER BY c.created_at DESC
     LIMIT 1;

    IF v_existing IS NULL THEN
        SELECT o.client_operation_id, o.idempotency_key
          INTO v_existing, v_stored_idem
          FROM public.credential_recovery_operations AS o
         WHERE o.client_operation_id = p_client_operation_id
            OR o.idempotency_key = p_idempotency_key
         ORDER BY o.created_at DESC
         LIMIT 1;
    END IF;

    IF v_existing IS NOT NULL THEN
        RETURN QUERY
            SELECT v_existing, v_stored_idem, 'existing'::text;
        RETURN;
    END IF;

    SELECT count(*)::integer
      INTO v_count
      FROM public.credential_recovery_challenges AS c
     WHERE c.shop_id = p_shop_id
       AND c.channel = p_channel
       AND c.created_at > NOW() - INTERVAL '15 minutes';

    IF v_count >= 5 THEN
        -- No ledger row is written here: throttled requests must not grow the
        -- ledger without bound. The caller's opaque ids are echoed back.
        PERFORM public.cs_record_recovery_audit(
            p_shop_id, 14, 'credential_recovery_rate_limited', p_user_id,
            'Credential recovery request rate limit exceeded', NULL, NULL
        );
        RETURN QUERY
            SELECT p_client_operation_id, p_idempotency_key, 'rate_limited'::text;
        RETURN;
    END IF;

    -- Placeholder digest: the real OTP is generated by the server endpoint
    -- AFTER this function confirms status = 'created', then installed by
    -- cs_finalize_recovery_challenge with its peppered digest.
    INSERT INTO public.credential_recovery_challenges (
        shop_id, user_id, channel, destination, otp_hash, expires_at,
        client_operation_id, idempotency_key
    ) VALUES (
        p_shop_id, p_user_id, p_channel, p_destination,
        repeat(md5(gen_random_uuid()::text), 2),
        NOW() + INTERVAL '5 minutes', p_client_operation_id, p_idempotency_key
    );

    INSERT INTO public.credential_recovery_operations (
        client_operation_id, idempotency_key, shop_id
    ) VALUES (
        p_client_operation_id, p_idempotency_key, p_shop_id
    ) ON CONFLICT DO NOTHING;

    PERFORM public.cs_record_recovery_audit(
        p_shop_id, 12, 'credential_recovery_requested', p_user_id,
        'Credential recovery requested', NULL, NULL
    );

    RETURN QUERY
        SELECT p_client_operation_id, p_idempotency_key, 'created'::text;
END;
$fn$;

COMMENT ON FUNCTION public.cs_create_recovery_challenge(uuid, uuid, text, text, uuid, uuid) IS
    'Story 1.10: Atomically enforces replay safety and a per-tenant+channel rate limit while reserving a recovery challenge.';

-- Finalization is performed by the server AFTER it generates the OTP. The
-- signed reference is stored as a digest in the challenge row so /deliver and
-- /verify survive process restarts and work across instances.
CREATE OR REPLACE FUNCTION public.cs_finalize_recovery_challenge(
    p_client_operation_id uuid,
    p_otp_hash text,
    p_delivery_reference_hash text
)
RETURNS TABLE (destination text, channel text, shop_id uuid, user_id uuid, expires_at timestamptz)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $fn$
BEGIN
    UPDATE public.credential_recovery_challenges AS c
       SET otp_hash = p_otp_hash,
           delivery_reference_hash = p_delivery_reference_hash
     WHERE c.client_operation_id = p_client_operation_id
       AND c.consumed_at IS NULL
       AND c.expires_at > NOW();

    IF NOT FOUND THEN
        RETURN;
    END IF;

    RETURN QUERY
        SELECT c.destination, c.channel, c.shop_id, c.user_id, c.expires_at
          FROM public.credential_recovery_challenges AS c
         WHERE c.client_operation_id = p_client_operation_id;
END;
$fn$;

COMMENT ON FUNCTION public.cs_finalize_recovery_challenge(uuid, text, text) IS
    'Story 1.10: Installs the server-generated peppered digest and signed-reference digest after reservation.';

-- Minimal identifier lookup for /verify. No hash, destination, channel or
-- state is exposed here: the backend validates the expiry-bound reference and
-- all mutable state inside its own tenant-scoped transaction.
CREATE OR REPLACE FUNCTION public.cs_load_recovery_for_reference(
    p_client_operation_id uuid
)
RETURNS TABLE (client_operation_id uuid, shop_id uuid, user_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $fn$
BEGIN
    RETURN QUERY
        SELECT c.client_operation_id, c.shop_id, c.user_id
          FROM public.credential_recovery_challenges AS c
         WHERE c.client_operation_id = p_client_operation_id
         LIMIT 1;
END;
$fn$;

ALTER FUNCTION public.cs_load_recovery_for_reference(uuid) OWNER TO cs_recovery_resolver;

REVOKE EXECUTE ON FUNCTION public.cs_finalize_recovery_challenge(uuid, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cs_load_recovery_for_reference(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cs_finalize_recovery_challenge(uuid, text, text) TO cs_app;
GRANT EXECUTE ON FUNCTION public.cs_load_recovery_for_reference(uuid) TO cs_app;

REVOKE EXECUTE ON FUNCTION public.cs_record_recovery_audit(uuid, integer, text, uuid, text, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cs_create_recovery_challenge(uuid, uuid, text, text, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cs_record_recovery_audit(uuid, integer, text, uuid, text, text, text) TO cs_app;
GRANT EXECUTE ON FUNCTION public.cs_create_recovery_challenge(uuid, uuid, text, text, uuid, uuid) TO cs_app;

-- ─────────────────────────────────────────────────────────────────────────────
-- §5  POST-MIGRATION ASSERTIONS
-- ─────────────────────────────────────────────────────────────────────────────
DO $verify$
DECLARE
    v_rls boolean;
    v_forced boolean;
BEGIN
    SELECT rowsecurity, forcepolicies
      INTO v_rls, v_forced
      FROM pg_class
     WHERE relname = 'credential_recovery_challenges'
       AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');

    IF NOT v_rls OR NOT v_forced THEN
        RAISE EXCEPTION '§VERIFY FAILED: credential_recovery_challenges must have FORCE ROW LEVEL SECURITY enabled.';
    END IF;

    SELECT rowsecurity, forcepolicies
      INTO v_rls, v_forced
      FROM pg_class
     WHERE relname = 'credential_recovery_operations'
       AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');

    IF NOT v_rls OR NOT v_forced THEN
        RAISE EXCEPTION '§VERIFY FAILED: credential_recovery_operations must have FORCE ROW LEVEL SECURITY enabled.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'cs_app' AND (rolsuper OR rolbypassrls)
    ) THEN
        RAISE EXCEPTION '§VERIFY FAILED: cs_app must not have SUPERUSER or BYPASSRLS.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_roles r ON r.oid = p.proowner
        WHERE p.proname = 'cs_resolve_recovery_identity' AND r.rolname = 'cs_recovery_resolver'
    ) THEN
        RAISE EXCEPTION '§VERIFY FAILED: cs_resolve_recovery_identity must be owned by cs_recovery_resolver.';
    END IF;

    RAISE NOTICE '§VERIFY PASSED: All 003_credential_recovery.sql post-migration assertions succeeded.';
END;
$verify$;

