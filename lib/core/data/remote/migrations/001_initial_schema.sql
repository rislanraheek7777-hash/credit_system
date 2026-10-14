-- ==============================================================================
-- Migration: 001_initial_schema.sql
-- Description: Initial PostgreSQL 16+ relational schema, strict tenant isolation
--              (RLS), append-only audit trigger, and offline sync queue.
-- Binds: Architecture Decisions AD-1, AD-2, AD-4, AD-6; PRD FR-1, FR-2, FR-3,
--        FR-4, FR-5, FR-6, FR-22, FR-23, FR-31.
-- Authoritative Monetary Type: BIGINT (minor units / integer cents).
-- Floating-Point Prohibition: REAL, FLOAT, DOUBLE PRECISION, and unconstrained
--                             NUMERIC are strictly forbidden for financial columns.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Migration Version Tracking Table
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS schema_migrations (
    version INTEGER PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    checksum VARCHAR(64) NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 2. Shops Table (Tenant Root Profile)
-- Binds: PRD FR-1, FR-2, FR-3, FR-4; AD-1, AD-4
-- ------------------------------------------------------------------------------
CREATE TABLE shops (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    currency_code VARCHAR(3) NOT NULL DEFAULT 'LKR' CHECK (length(currency_code) = 3),
    timezone VARCHAR(100) NOT NULL DEFAULT 'Asia/Colombo',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable and FORCE Row-Level Security on shops
ALTER TABLE shops ENABLE ROW LEVEL SECURITY;
ALTER TABLE shops FORCE ROW LEVEL SECURITY;

-- Tenant Isolation Policy for shops
-- Uses current_setting('app.current_shop_id', true) set exclusively by the authenticated server session
CREATE POLICY shops_tenant_isolation_policy ON shops
    FOR ALL
    USING (id = current_setting('app.current_shop_id', true)::uuid);

-- ------------------------------------------------------------------------------
-- 3. App Users Table (Counter Staff & Shop Owner Accounts)
-- Binds: PRD FR-5, FR-6; AD-1, AD-6
-- ------------------------------------------------------------------------------
CREATE TABLE app_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE RESTRICT,
    username VARCHAR(100) NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    session_version INTEGER NOT NULL DEFAULT 1 CHECK (session_version >= 1),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_app_users_shop_username UNIQUE (shop_id, username)
);

CREATE INDEX idx_app_users_shop_id ON app_users(shop_id);

ALTER TABLE app_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_users FORCE ROW LEVEL SECURITY;

CREATE POLICY app_users_tenant_isolation_policy ON app_users
    FOR ALL
    USING (shop_id = current_setting('app.current_shop_id', true)::uuid);

-- ------------------------------------------------------------------------------
-- 4. Audit Events Table (Tamper-Resistant Append-Only Activity Log)
-- Binds: PRD FR-31 (NFR-1); AD-6
-- ------------------------------------------------------------------------------
CREATE TABLE audit_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE RESTRICT,
    event_category INTEGER NOT NULL CHECK (event_category BETWEEN 1 AND 14),
    action_type VARCHAR(100) NOT NULL,
    actor_id UUID NOT NULL REFERENCES app_users(id) ON DELETE RESTRICT,
    target_entity_type VARCHAR(100) NOT NULL,
    target_entity_id UUID NOT NULL,
    pre_state_json JSONB,
    post_state_json JSONB,
    reason TEXT,
    client_ip VARCHAR(45),
    user_agent TEXT,
    server_timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_events_shop_created ON audit_events(shop_id, server_timestamp DESC);
CREATE INDEX idx_audit_events_target ON audit_events(shop_id, target_entity_type, target_entity_id);

ALTER TABLE audit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_events FORCE ROW LEVEL SECURITY;

CREATE POLICY audit_events_tenant_isolation_policy ON audit_events
    FOR ALL
    USING (shop_id = current_setting('app.current_shop_id', true)::uuid);

-- Database-Enforced Audit Immutability Trigger (Blocks UPDATE and DELETE unconditionally)
CREATE OR REPLACE FUNCTION reject_audit_tampering()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Audit trail records are append-only and cannot be modified or deleted.';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_immutable
BEFORE UPDATE OR DELETE ON audit_events
FOR EACH ROW EXECUTE FUNCTION reject_audit_tampering();

-- ------------------------------------------------------------------------------
-- 5. Sync Queue Table (Central Asynchronous Synchronization Buffer)
-- Binds: PRD FR-4, FR-23; AD-1
-- ------------------------------------------------------------------------------
CREATE TABLE sync_queue (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE RESTRICT,
    idempotency_key UUID NOT NULL,
    entity_type VARCHAR(100) NOT NULL,
    entity_id UUID NOT NULL,
    action_type VARCHAR(100) NOT NULL,
    payload_json JSONB NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'pending_server_ack' CHECK (status IN ('pending_server_ack', 'confirmed_by_server', 'failed')),
    retry_count INTEGER NOT NULL DEFAULT 0 CHECK (retry_count >= 0),
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    CONSTRAINT uq_sync_queue_shop_idempotency UNIQUE (shop_id, idempotency_key)
);

CREATE INDEX idx_sync_queue_shop_status ON sync_queue(shop_id, status);

ALTER TABLE sync_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_queue FORCE ROW LEVEL SECURITY;

CREATE POLICY sync_queue_tenant_isolation_policy ON sync_queue
    FOR ALL
    USING (shop_id = current_setting('app.current_shop_id', true)::uuid);
