-- ==============================================================================
-- Rollback Migration: 001_initial_schema_down.sql
-- Description: Cleanly reverts all tables, indexes, RLS policies, triggers,
--              and schema tracking created in 001_initial_schema.sql.
-- Binds: Sub-Task 1.2B; AD-1, AD-4.
-- Reversal Order: Dropped strictly in reverse order of foreign-key dependencies.
-- ==============================================================================

-- 1. Drop audit immutability trigger and function
DROP TRIGGER IF EXISTS trg_audit_immutable ON audit_events;
DROP FUNCTION IF EXISTS reject_audit_tampering();

-- 2. Drop tenant isolation policies
DROP POLICY IF EXISTS sync_queue_tenant_isolation_policy ON sync_queue;
DROP POLICY IF EXISTS audit_events_tenant_isolation_policy ON audit_events;
DROP POLICY IF EXISTS app_users_tenant_isolation_policy ON app_users;
DROP POLICY IF EXISTS shops_tenant_isolation_policy ON shops;

-- 3. Drop relational tables (reverse dependency order)
DROP TABLE IF EXISTS sync_queue CASCADE;
DROP TABLE IF EXISTS audit_events CASCADE;
DROP TABLE IF EXISTS app_users CASCADE;
DROP TABLE IF EXISTS shops CASCADE;

-- 4. Drop migration metadata tracking table
DROP TABLE IF EXISTS schema_migrations CASCADE;
