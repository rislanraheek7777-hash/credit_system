---
title: 'Story 1.2: Dual-Tier Relational Database Foundations & Migration Harness'
type: 'feature'
created: '2026-10-14'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
context:
  - _bmad-output/implementation-artifacts/epic-1-context.md
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The Credit Management System requires responsive, offline-capable local operation at retail counters while maintaining an authoritative, cloud-hosted PostgreSQL database as the authoritative single source of truth. Without clear relational foundations, sandboxed client storage, explicit schema migrations, and decoupled transaction boundaries, the system risks data loss, split-brain discrepancies, and schema drift.

**Approach:** Establish dual-tier relational database connections for local Drift (SQLite) and remote PostgreSQL 16+. Configure app-private sandboxed storage for Drift, reproducible DDL migrations with version tracking for PostgreSQL, and a base `sync_queue` table enforcing asynchronous, non-distributed ACID transactions where local operations remain explicitly pending until server confirmation.

## Boundaries & Constraints

**Always:**
- Persist financial amounts strictly as 64-bit integer minor units (`INTEGER` in SQLite, `BIGINT` in PostgreSQL). Floating-point columns (`REAL`, `FLOAT`, `DOUBLE PRECISION`, `NUMERIC`) are prohibited.
- Store local SQLite database files in application-managed sandboxed storage (e.g. `getApplicationDocumentsDirectory` via `path_provider` on desktop/mobile, in-memory for unit tests), never hard-coded paths.
- Treat local SQLite writes and remote PostgreSQL synchronization as distinct, decoupled transactions. Never claim or assume cross-database ACID transactions.
- Queue offline counter actions in `sync_queue` with UUIDv4 idempotency keys, tenant `shop_id`, action type, JSON payload, and explicit status lifecycle (`pending_server_ack`, `confirmed_by_server`, `failed`).
- Design PostgreSQL tenant context around trusted server-side authentication claims (`SET LOCAL app.current_shop_id`), never client-chosen parameters.
- Provide bidirectional migration scripts (forward and rollback/down) with explicit version tracking.

**Never:**
- Never use Dart `double` for monetary representation, calculations, or schema types.
- Never mark a sync queue transaction as cloud-confirmed without explicit server acknowledgment.
- Never store plaintext sensitive customer PII or auth secrets in unencrypted log files or queue metadata.
- Never implement full synchronization sync engines, auth logic, customer onboarding, or credit origination features inside Story 1.2 (these belong to Stories 1.3+, 1.8, Epic 2, and Epic 4).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Drift SQLite Init | Application launch on client device | Database file opened in sandboxed path; tables (`shops`, `app_users`, `sync_queue`) created at schema v1 | Throws `DatabaseInitializationException` on I/O or permissions failure |
| Drift In-Memory Test Init | Test suite execution | In-memory Drift database initialized instantly without disk artifacts | Returns clean test database instance |
| PostgreSQL Migration Up | Clean PostgreSQL 16+ database | Applies DDL: `shops`, `app_users`, `audit_events`, `sync_queue`, records version in `schema_migrations` | Rollback transaction on any DDL syntax or constraint error |
| PostgreSQL Migration Down | Applied v1 PostgreSQL schema | Reverts all created tables cleanly, leaves database in pristine state | Preserves previous version state if rollback fails |
| Sync Queue Insertion | Local counter action recorded | Inserts row with `status = 'pending_server_ack'`, generates UUIDv4 idempotency key | Rejects duplicate idempotency keys via unique constraint |
| Financial Column Type Check | DDL inspection on money columns | Verifies column type is `BIGINT` (PG) and `INTEGER` (SQLite), rejecting `FLOAT`/`REAL` | Fails schema validation test if non-integer type detected |

</frozen-after-approval>

## Open Questions

- 1. Live PostgreSQL Integration Test Execution — options:
  - OPTION A (Recommended): Implement pure-Dart migration runner using `package:postgres`, verify SQL DDL syntax and schema contracts with automated tests, and provide a configurable live test runner (`test/integration/remote/postgres_migration_test.dart`) that connects to any available PostgreSQL 16+ instance (via `DATABASE_URL` environment variable or local test container when available).
  - OPTION B: Block Story 1.2 until Docker or a local PostgreSQL 16+ service is installed and running on the local host machine.

- 2. Drift Table Definition Architecture — options:
  - OPTION A (Recommended): Pure Dart table definitions extending Drift's `Table` class with runtime query executors and schema migrations, keeping dependencies light and builds fast without heavy code generation.
  - OPTION B: Introduce `drift_dev` and `build_runner` code generation pipeline producing `.g.dart` files.

## Code Map

- `lib/core/data/local/app_database.dart` -- Main Drift local SQLite database class with schema versioning and migration strategy.
- `lib/core/data/local/tables/shops_table.dart` -- Drift schema for shop tenant profile.
- `lib/core/data/local/tables/app_users_table.dart` -- Drift schema for staff users and session versions.
- `lib/core/data/local/tables/sync_queue_table.dart` -- Drift schema for offline sync queue with idempotency keys and status.
- `lib/core/data/local/connection/database_connection.dart` -- Platform-aware connection resolver (sandboxed directory vs in-memory).
- `lib/core/data/remote/migrations/001_initial_schema.sql` -- PostgreSQL 16+ forward DDL migration (`BIGINT`, UUID, TIMESTAMPTZ, RLS prep).
- `lib/core/data/remote/migrations/001_initial_schema_down.sql` -- PostgreSQL 16+ rollback DDL migration.
- `lib/core/data/remote/migration_runner.dart` -- Version-tracked PostgreSQL migration execution harness.
- `lib/core/sync/models/sync_queue_entry.dart` -- Domain model for sync queue items and status transitions.
- `test/unit/core/data/local/drift_database_test.dart` -- Unit and integration tests for local SQLite schema, CRUD, and migrations.
- `test/unit/core/data/remote/postgres_migration_contract_test.dart` -- Tests validating PostgreSQL DDL contracts, column types, and rollback logic.

## Tasks & Acceptance

**Sub-Task 1.2A: Local Drift/SQLite Foundations & Sandboxed Storage**
- [x] `pubspec.yaml` -- Add `path_provider: ^2.1.6`, `uuid: ^4.5.1`, `path: ^1.9.1`, `crypto: ^3.0.6` -- Required for sandboxed storage paths, UUIDv4 generation, and checksum hashing.
- [x] `lib/core/data/local/tables/shops_table.dart` -- Define `Shops` table with UUID `id`, `name`, `currency_code` ('LKR'), `timezone` ('Asia/Colombo').
- [x] `lib/core/data/local/tables/app_users_table.dart` -- Define `AppUsers` table with UUID `id`, `shop_id` FK, `role`, `session_version`, `is_active`.
- [x] `lib/core/data/local/tables/sync_queue_table.dart` -- Define `SyncQueue` table with `id`, `shop_id`, `idempotency_key`, `status`, `payload_json`.
- [x] `lib/core/data/local/app_database.dart` -- Implement `AppDatabase` with schema version 1, migration hooks, and table registration.
- [x] `lib/core/data/local/connection/database_connection.dart` -- Implement platform connection factory (sandboxed directory for app, in-memory for tests).
- [x] `test/unit/core/data/local/database_connection_test.dart` -- Write tests verifying platform connection factory, directory resolution, and SQLite constraints.
- [x] `test/unit/core/data/local/drift_database_test.dart` -- Write tests verifying Drift database creation, table constraints, indices, and CRUD.

**Sub-Task 1.2B: Remote PostgreSQL 16+ Migration Harness & Schema Definitions**
- [x] `lib/core/data/remote/migrations/001_initial_schema.sql` -- Author idempotent forward DDL migration for `shops`, `app_users`, `audit_events`, `sync_queue` with `BIGINT` minor units and RLS.
- [x] `lib/core/data/remote/migrations/001_initial_schema_down.sql` -- Author rollback DDL migration cleanly removing tables, triggers, and schema tracking.
- [x] `lib/core/data/remote/migration_runner.dart` -- Implement migration runner tracking applied versions in `schema_migrations` table with SHA-256 checksum verification.
- [x] `test/unit/core/data/remote/postgres_migration_contract_test.dart` -- Validate migration SQL syntax, DDL constraints, `BIGINT` column types, and rollback scripts.

**Sub-Task 1.2C: Sync Queue Contract & Asymmetric Transaction Boundary Model**
- [x] `lib/core/sync/models/sync_queue_entry.dart` -- Implement `SyncQueueEntry` domain entity with `SyncStatus` enum (`pending_server_ack`, `confirmed_by_server`, `failed`), idempotency key preservation, and diagnostic privacy.
- [x] `test/unit/core/sync/sync_queue_entry_test.dart` -- Test status lifecycle, idempotency key generation, and payload serialization without PII leakage.

**Sub-Task 1.2D: Verification & Checkpoint Review**
- [x] Run `flutter test` across all unit and database suites (97 tests passing).
- [x] Run `flutter analyze` ensuring zero issues.
- [x] Review Git diff and status.

**Acceptance Criteria:**
- Given client application initialization, when Drift database opens, then it connects via sandboxed app storage and creates `shops`, `app_users`, and `sync_queue` tables with correct keys and indices.
- Given cloud database configuration, when migration runner executes `001_initial_schema.sql`, then all tables are created with `UUID`, `BIGINT` for currency, and `TIMESTAMPTZ`, and rolling back restores pristine state.
- Given a counter transaction, when logged to `sync_queue`, then it persists with a UUIDv4 idempotency key and `status = pending_server_ack`, without cross-database distributed locking.

## Implementation Notes

- **Dual-Tier SQLite/PostgreSQL Alignment:** The local Drift SQLite schema and remote PostgreSQL DDL share identical field names, types, and constraints (`UUID`, `LKR` default currency, `Asia/Colombo` default timezone, `session_version >= 1` check constraint).
- **Asymmetric Transaction Boundaries:** Counter mutations commit locally to SQLite in an ACID transaction with `status = pending_server_ack`. Cloud synchronization is completely decoupled, ensuring counter responsiveness during network interruptions.
- **Permanent Idempotency:** `idempotencyKey` is generated once at operation creation via `Uuid().v4()` and strictly preserved across retries.
- **Diagnostic Privacy:** `SyncQueueEntry.toDiagnosticString()` and `toString()` omit payload contents, reporting only payload size in bytes to prevent PII leakage into diagnostic logs.
- **Audit Immutability:** `001_initial_schema.sql` establishes database trigger `trg_audit_immutable` on `audit_events` unconditionally aborting `UPDATE` and `DELETE`.
- **Migration Safety:** `MigrationRunner` computes deterministic SHA-256 hashes normalized across CRLF/LF line endings and rejects tampered migrations via `MigrationChecksumMismatchException`.

## Design Notes

- **Asymmetric Authority:** Drift is an edge operational store. PostgreSQL is the single source of truth.
- **Decoupled Transactions:** A local counter action commits locally in SQLite first. A background or online sync worker synchronizes rows downstream to PostgreSQL.
- **No Floating-Point Money:** Verified in both SQLite table definitions and PostgreSQL DDL migrations.

