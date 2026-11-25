---
title: 'Standalone Credential Recovery Backend Service'
type: 'feature'
created: '2026-11-25'
status: 'in-review'
baseline_commit: '8fd3727d4e3faa6f8c3cab8fea2b8871fb42b41d'
route: 'dispatch'
review_loop_iteration: 5
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Story 1.10 hosts the OTP "server" as a Dart component inside the Flutter client. The client therefore carries privileged migration/bootstrap paths, abuse-audit gaps, and an unauthenticated delivery endpoint; four review passes proved this is not a security boundary.

**Approach:** Build a separately deployable backend service that owns OTP generation, secrets, challenge lifecycle, delivery, verification, the atomic password reset, and audit appends. Reduce the Flutter client to a thin HTTP caller with no secrets, no privileged DB connection, and no DDL. Remove the client-hosted server and startup migration bootstrap — do not layer over them.

## Boundaries & Constraints

**Always:** Backend secrets come from OS environment variables only. Client holds no pepper, provider credential, privileged DB role, or DDL capability. Unauthenticated request responses are identical in body and status for matched/unmatched identifiers. The backend derives tenant context solely from PostgreSQL records. `credential_recovery_challenges` keeps immutable `tenant_id`, FORCE RLS, hashed OTP, destination, expiry, attempt counter, consumed marker, `client_operation_id` and `idempotency_key`; reuse Categories 12/14 only. Success rotates the password hash and `session_version` atomically in PostgreSQL and revokes all sessions. Recovery is blocked offline. No new permission or audit category.

**Never:** No client-hosted OTP generation/delivery/verification, no client DDL or migration bootstrap, no `BYPASSRLS` in the client role, no caller-supplied destination or code accepted by the backend, no plaintext OTP or password in logs/audit, no extra response field on one path only, no fifteenth category or sixteenth permission.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| Unknown identifier | `/request` with no matching staff account | Same body/status as matched case; no challenge delivered | N/A |
| Known identifier | `/request`, account with verified channel | Challenge reserved atomically, OTP generated and delivered by backend; same response body | Delivery failure → no challenge, no provider leak |
| Re-transmission | Same `client_operation_id` / idempotency key | Stored operation id and idempotency key returned; no second OTP or delivery | N/A |
| Ambiguous identifier | Identifier matches multiple tenants | Generic response; no challenge; exactly one Category 14 event | N/A |
| Successful verification | `/verify` with valid, unconsumed, unexpired OTP and new password | Backend atomically rotates hash, increments `session_version`, consumes challenge, appends Category 12; returns username | N/A |
| Invalid OTP | Wrong / expired / consumed / fifth attempt | One generic failure; backend increments attempts and appends exactly one Category 14 | No hint which condition failed |
| Direct endpoint probe | `/verify` with unknown operation id or no OTP | Generic failure or 400; no destination, hash, or tenant disclosed | Category 14 where attributable |
| Offline client | Any recovery step with no connectivity | Client blocks locally; no server call, no local write | Generic offline message |
| Backend restart | Challenge reserved before restart | Verification and lookup work from PostgreSQL alone; no in-process OTP state | N/A |
| Client inspection | Shipped Flutter app searched for secrets/DDL | No pepper, provider credential, privileged DB connection, migration runner, or `BYPASSRLS` capability | N/A |

## Decisions (approved 2026-11-25 / planning decisions)

- **Deployment:** a separate pure-Dart backend package under `backend/` with its own `pubspec.yaml`, `bin/server.dart`, `lib/src/` modules, and `test/`. It is deployable independently of the Flutter app; the client depends only on its HTTP contract.
- **Runtime config:** backend reads all secrets and DB settings from OS environment via `Platform.environment` (`CS_RECOVERY_OTP_PEPPER`, SMTP/SMS credentials and endpoints, `DATABASE_URL`, abuse-shop UUID, listen host/port). The client may use a build-time constant only for the public backend URL (`CS_RECOVERY_SERVER_URL`), never for a secret.
- **API:** two routes — `POST /request` (identifier, channel, operation id, idempotency key) and `POST /verify` (operation id, OTP, new password). `/deliver` is removed. The operation id (UUIDv4) is the challenge-bound, single-use reference; the backend authenticates it by DB lookup, not by a client-held secret. All `/request` outcomes return the same `{storedOperationId, storedIdempotencyKey}` body.
- **Ownership:** the backend performs all privileged DML — challenge SELECT `FOR UPDATE`, attempt counting, expiry check with SQL `NOW()`, password hash rotation, `session_version` increment, consumed marker, and Category 12/14 audit appends. The client performs none.
- **SQL:** migration 003 remains the single source of truth in `lib/core/data/remote/migrations/003_credential_recovery.sql`. The embedded Dart copy in `migration_runner.dart` is removed from the client; a backend CLI applies the `.sql` file from a configured path. CI/DBA applies 003 explicitly, never client startup.
- **Abuse audit:** a reserved platform/security shop UUID from `CS_RECOVERY_ABUSE_SHOP_ID` hosts un-attributable Category 14 events; the backend fails closed if it is unset. No real tenant's audit trail receives another tenant's security events.
- **Removal, not layering:** delete `server/`, `lib/core/data/remote/migration_bootstrap.dart`, its `main.dart` call, the client's raw recovery DML, and client tests that assert privileged behavior.
- **Fresh-device login (approved 2026-11-25):** after successful OTP verification the backend returns minimal trusted user context (user id, shop id, username, role, session version); the client caches it so online login works on a fresh device. This is cache seeding, not privileged recovery DML — no password hash or permission data is returned.
- **Delivery transport (approved 2026-11-25):** TLS is mandatory for SMTP; any configuration that disables TLS fails startup. No cleartext credential or OTP transmission.

</frozen-after-approval>

## Code Map

- `backend/` (new package) -- standalone service: `pubspec.yaml` (`shelf`, `postgres`, `crypto`, `http`), `bin/server.dart` entrypoint, `lib/src/{config,otp,reference,delivery,routes,audit,database}.dart`.
- `C:\projects\credit_system\server\otp_delivery_server.dart` -- existing client-hosted server; source of behavior to port, then delete.
- `test/unit/features/auth/otp_delivery_server_test.dart` -- existing server tests; move/expand under `backend/test/`.
- `lib/features/auth/data/services/otp_gateway.dart` -- client adapter; reduce to `requestRecovery` / `verifyRecovery`; remove `deliver` and unused bearer path; public URL only.
- `lib/features/auth/data/services/auth_service.dart` -- `requestCredentialRecovery` / `confirmCredentialRecovery` become thin gateway calls; remove raw challenge DML, attempt counting, password rotation and audit appends (approx. current lines 1011–1171).
- `lib/features/auth/presentation/credential_recovery_dialog.dart` -- keep two-step UI; use authoritative ack values; pass operation id to `/verify`; no local reference state.
- `lib/core/data/remote/migration_bootstrap.dart` + `lib/main.dart:12,616` -- delete entirely; no client migration bootstrap.
- `lib/core/data/remote/migration_runner.dart` -- remove `credentialRecoveryMigration` embedded SQL and `registeredMigrations`; client no longer applies server DDL.
- `lib/core/data/remote/migrations/003_credential_recovery.sql` -- single source of truth; backend CLI applies it; extend pgTAP for functions actually used by backend.
- `test/integration/tenant_isolation/credential_recovery.tap` -- real-SQL assertions for resolvers, create/finalize/load functions, replay branch, FORCE RLS, audit actor.
- `.github/workflows/ci.yml` -- add `dart test backend/test/` and keep the pgTAP step.
- `test/unit/features/auth/auth_service_test.dart`, `test/widget/features/auth/credential_recovery_dialog_test.dart` -- update to thin-caller contract.

## Tasks & Acceptance

**Execution:**
- [x] `backend/pubspec.yaml` + `backend/bin/server.dart` + `backend/lib/src/*.dart` -- create deployable service with OS-env config, OTP generation/hash, HMAC reference digest, SMTP/SMS delivery, least-privilege DB access, uniform API -- backend owns security boundary.
- [x] `backend/test/` -- API contract tests: uniform bodies, replay, ambiguity, invalid/consumed/expired OTP, single Category 14, backend-side atomic reset -- behavior gates without client code.
- [ ] Remove `server/otp_delivery_server.dart` and its old test file -- no client-hosted server remains.
- [ ] Remove `lib/core/data/remote/migration_bootstrap.dart` and the `main.dart` import/call -- no client DDL at startup.
- [x] `lib/core/data/remote/migration_runner.dart` -- remove embedded 003 Dart string and `registeredMigrations` -- single SQL source of truth.
- [x] `lib/features/auth/data/services/otp_gateway.dart` -- reduce to `/request` and `/verify`; remove `deliver`/bearer dead path -- thin client.
- [x] `lib/features/auth/data/services/auth_service.dart` -- recovery methods delegate to gateway; remove all privileged DML -- client holds no secrets or DB power.
- [x] `lib/features/auth/presentation/credential_recovery_dialog.dart` -- use returned stored ids; remove dead reference state -- unchanged UX, correct contract.
- [ ] Tests update: `auth_service_test.dart`, `credential_recovery_dialog_test.dart`, `otp_gateway_test.dart` -- assert thin-caller behavior.
- [x] `test/integration/tenant_isolation/credential_recovery.tap` -- real-SQL coverage for backend-used functions and replay branch -- DB boundary proof.
- [x] `.github/workflows/ci.yml` -- add backend test step -- CI gate.
- [x] `deferred-work.md` / `sprint-status.yaml` -- mark Story 1.11 done through normal flow after review.

**Acceptance Criteria:**
- Given the deployed backend, when it starts, then all secrets come from OS environment and it connects with a least-privilege role; no client binary contains a pepper, provider credential, or DDL capability.
- Given an unauthenticated `/request`, when an identifier matches or not, then the response body and status are identical and contain only stored operation id and idempotency key.
- Given a re-transmitted challenge, when the backend handles it, then no second OTP or provider call occurs and the stored keys are returned.
- Given `/verify`, when the OTP is invalid, expired, consumed, or over the attempt cap, then one generic failure is returned, the attempt counter is updated server-side without violating its CHECK, and exactly one Category 14 event is appended.
- Given `/verify` succeeds, then the password hash and `session_version` change atomically in PostgreSQL, the challenge is consumed, Category 12 is appended, and all existing sessions fail with 401 on their next request.
- Given a backend restart, when verification is attempted, then it succeeds from PostgreSQL state alone.
- Given the client app, when its source and binary are inspected, then no `server/`, migration bootstrap, embedded 003 SQL, `BYPASSRLS`, or privileged recovery DML remains.

### Loopback 5 required corrections (non-frozen; workflow limit)

- **Uniform responses under audit/DB failure:** every pre-transaction audit/lookup path in `/request` and `/verify` returns the same generic body/status as its success counterpart, even when `appendAbuse` or the query throws. No 400/500 shape change based on backend failure.
- **Health/readiness routing:** explicit GET/POST routing for `/health` and `/ready` with accurate `Allow` headers; unknown paths keep `404`.
- **Production gateway test:** remove the skip condition; construct `AuthService` with neither `otpGateway` nor `gatewayFactory` under the `--dart-define` CI step and assert the default gateway posts to the configured URL.
- **Cross-tenant `/verify` test:** fake and pgTAP cases where the loaded challenge's `shop_id` differs from the rotation target, asserting zero rows affected and one Category 14.
- **Real connectivity gate:** inject a platform-aware `ConnectivityService` into `LoginScreen` from `main.dart` (native network check / web `onLine`) instead of defaulting `isOnline` to always true.
- **Dialog error paths:** any non-offline request failure clears the green success message and shows the generic failure; offline resend already does this.
- **Crash-retry recovery:** on `status='existing'` with an unset reference digest, re-finalize and re-deliver (or delete/recreate in one tenant transaction) so a reserved-but-unfinished challenge cannot lock out the idempotency key forever.
- **Cleanup fallback:** when the tenant-scoped cleanup/audit transaction fails, the abuse-shop fallback also deletes/consumes the challenge, not just appends an event.
- **Digest mismatch:** when the challenge row exists but the reference digest no longer matches, increment attempts, consume at threshold, then append Category 14.
- **Resolver throttle test:** 61 requests for one identifier produce exactly one `credential_recovery_resolver_throttled` event and no further resolver SQL.
- **Config/runbook:** enable SMTP or SMS independently per environment; retention DELETE runbook uses a privileged role or per-tenant `set_config`.

### Loopback 4 required corrections (non-frozen; final loopback)

- **No 500 escapes.** Wrap the entire `_handle` dispatch in a try/catch that returns a generic JSON 400/ack for any unexpected failure, including audit/DB failures on throttle and reference-lookup branches. Keep normal failure paths appending exactly one Category 14 where a tenant is known.
- **Verify throttle** uses both a per-operation bucket and a global per-window cap so rotating UUIDs cannot create unlimited audits/DB work.
- **HTTPS everywhere:** reject non-HTTPS `CS_RECOVERY_SMS_ENDPOINT` and non-HTTPS `CS_RECOVERY_SERVER_URL` at config/startup; OTP, bearer key, and new password must never traverse cleartext.
- **Post-rotation context read happens before commit.** If trusted context cannot be read, roll back the transaction so the password is not changed when the client sees failure.
- **Local cache seeding clears the stale password hash** on the update branch so the old password cannot authenticate offline after a server-side reset.
- **Grant `cs_app` DELETE on `credential_recovery_operations`** so failure cleanup can remove the ledger row; prove with a test that a retry after failure issues a fresh code.
- **Migration idempotency across tools:** make the pgTAP harness use `bin/migrate.dart` (or record `schema_migrations` in SQL) so an operator cannot re-apply 003 twice.
- **Rate-limit bookkeeping:** do not insert a ledger row on `rate_limited`, or include ledger rows in the rate count; prevent unbounded growth.
- **v29 upgrade:** fix the contradictory comment, add a column-parity assertion between generated table and rebuilt DDL, and correct the actor-cleanup prefix length to the full reserved username.
- **Operational hardening:** bound SMTP `expect()` with a deadline; remove dead `migrationSqlPath` config or make it the single path source.
- **Final test gaps:** login-screen recovery entry point, production default-gateway branch, and real duplicate inserts into an upgraded v29 database.

### Loopback 3 required corrections (non-frozen; bad_spec fixes)

- **Startup must respect RLS.** Check the abuse shop through a tenant-scoped transaction (`transactionWithTenant(config.abuseShopId, ...)`) or a narrow `SECURITY DEFINER` existence function; never query `public.shops` with no tenant context under FORCE RLS.
- **Failed delivery must not poison idempotency.** When a reservation is deleted after finalize/delivery failure, delete its `credential_recovery_operations` ledger row in the same tenant transaction so a retry with the same key can create a fresh challenge.
- **Cache seeding must not undo a successful reset.** Catch seeding errors separately in the dialog; surface backend success and report the local-cache issue without claiming the reset failed.
- **Rotation predicates must be real-SQL tested.** Add a pgTAP case executing the backend's exact `UPDATE ... WHERE id = @p1 AND shop_id = @p2` and a cross-tenant id, plus a test that removing `delivery_reference_hash` predicate fails.
- **Production gateway wiring check.** Add a build/CI assertion that `CS_RECOVERY_SERVER_URL` is supplied for release builds and a test that `AuthService` without an injected gateway constructs `HttpOtpGateway.fromEnvironment()` and posts to that URL.
- **Operational artifacts:** `backend/README.md` and `.env.example` documenting every env var, the `--dart-define` for the client, deployment constraints (single instance or shared throttle), the DBA migration step, health/readiness route, graceful shutdown, and a retention/cleanup policy for consumed/expired challenges.
- **Rollback consistency:** 003 down migration deletes its `schema_migrations` row so re-apply is not skipped.
- **Port validation:** parse `CS_RECOVERY_SMTP_PORT` / `CS_RECOVERY_SERVER_PORT` strictly and fail startup on invalid or out-of-range values.
- **Throttle pruning and HELO:** prune all expired buckets on each `_allow` call; make SMTP EHLO identity configurable with a safe default.

### Loopback 2 required corrections (non-frozen; bad_spec fixes)

- **Tenant context must use `SELECT set_config('app.current_shop_id', @p0, true)`** — PostgreSQL `SET` cannot take a bound parameter. Add a real-SQL assertion that exercises this exact call path (not a literal `SET LOCAL`).
- **Throttles:** prune counter keys after their window, scope resolver and delivery budgets per identifier/tenant (no global delivery queue), and add a `/verify` throttle before any Category 14 append or transaction.
- **Request validation inside `_handle`'s try/catch:** decode UTF-8 with `allowMalformed: false` and coerce all JSON fields with type checks, returning generic 400 on any malformed input — never 500.
- **SMTP:** remove the plain-socket path; require TLS (fail startup on any config that disables it). Hash the new password **before** opening the `FOR UPDATE` transaction.
- **Reference:** bind the HMAC to the challenge expiry (`HMAC(pepper, operationId|expiresAt)`), store the digest, and validate with SQL `NOW()`; this makes the reference short-lived and single-use without exposing a new response field.
- **SQL surface:** narrow `cs_load_recovery_for_reference` to identifiers only (no hash/destination) and drop the unused `cs_resolve_recovery_challenge` function and grant.
- **Audit:** no swallowed audit failures anywhere — every catch path that skips an append must be removed or append exactly one Category 14 and then return the generic ack.
- **Fresh-device cache seeding:** `/verify` returns minimal trusted context; client persists it locally via a narrow cache-seeding DAO method (never a password-hash write).
- **Tests:** fix fakes so `session_version` increments only when the SQL contains the increment; make v29 upgrade tests insert duplicate email/phone and assert constraint failure; add real-SQL coverage for the backend's tenant-context call and rotation.

### Loopback 1 required corrections (non-frozen; bad_spec fixes)

- **Audit appends must run inside tenant context.** Every Category 12/14 append calls `cs_record_recovery_audit` through `transactionWithTenant` with the resolved tenant (or the configured abuse shop for un-attributable events). Never swallow an audit failure silently; a failed append must fail the recovery step.
- **`cs_create_recovery_challenge` returns the stored idempotency key on every branch** (`created`, `existing`, `rate_limited`). Tests must vary the caller's key from the stored key to prove this.
- **Migration apply is idempotent.** `bin/migrate.dart` checks/records `schema_migrations` via `MigrationRunner` (or equivalent guard) so a second DBA/CI run is a no-op; never execute raw DDL twice.
- **Every state-changing UPDATE checks affected rows.** Zero rows on password rotation or challenge finalize must be treated as failure, audited once, and leave no usable challenge; clean up a finalized-with-zero-rows challenge.
- **Reserve→finalize failure path is closed.** If finalization, delivery, or a post-reservation SQL step fails, delete the reserved challenge, append one Category 14 event, and return the generic acknowledgement. No placeholder digest may consume the tenant rate budget.
- **Actor row is collision-safe.** Detect an existing real user with the synthetic actor username and fail closed or use a distinct reserved username; the audit actor FK must never be silently broken.
- **SMTP_TLS parsing is strict** — only literal `true`/`false` accepted; any other value fails startup so credentials and codes are never sent in cleartext.
- **HTTP hardening** — cap request body size before `jsonDecode`, send `Allow` on 405, and refuse to bind a non-loopback host unless TLS is configured.
- **Throttles are per identifier and pruned** — remove expired queue keys; rate-limit scope must not let one tenant exhaust another's delivery budget.
- **Real-SQL and cross-package tests** — pgTAP fixtures use `cashier`; add a backend test for the email SMTP path, one for `enrolled=false` at `/verify`, one for signup username persistence, and an explicit cross-package Argon2 compatibility test; fix the DELETE-grant assertion to parse the full statement.

## Implementation Notes

- 2026-11-25: Implemented from baseline `8fd3727d4e3faa6f8c3cab8fea2b8871fb42b41d`. Verified independently: `dart analyze` (backend) zero issues; `dart test` (backend) 19/19 passed; `flutter analyze lib/ test/` zero issues; `flutter test test/unit/features/auth/ test/widget/features/auth/ test/unit/core/data/remote/` 147/147 passed. Cross-package check: backend-produced Argon2id hash verifies with the client's `PasswordHashService`.
- All 10 I/O matrix rows have covering tests that ran and passed, including uniform bodies, replay, ambiguity, single Category 14, restart-from-PostgreSQL, offline blocking, and no privileged client DML.
- Deviation from Code Map: `argon2` added to `backend/pubspec.yaml` so the backend emits client-compatible Argon2id PHC hashes; the four originally listed packages cannot do this.
- Risk: pgTAP T-CR-13…19 were not executed locally (no `DATABASE_URL` / `pg_prove`); CI now runs them.
- Risk: throttle queues remain per-process operational metadata; limits reset on restart. Deployment should run a single backend instance or share throttle state.

## Spec Change Log

## Review Triage Log

Review pass 1 — every finding rendered a verdict from the diff and actual files (duplicates kept as separate rows):

| # | Finding | Verdict | Evidence |
|---|---|---|---|
| BH1 | Stored idempotency key echoed as caller's on `existing`/`rate_limited` | high | SQL returns `p_idempotency_key`; fake DB returns `params[5]`; no test varies the key. |
| BH2 | Non-reset Category 12/14 appends dropped by FORCE RLS | high | `_auditor.append` on ambient DB with no `app.current_shop_id`; exceptions swallowed. |
| BH3 | pgTAP fixtures use unsupported `counter_staff` role | high | Four inserts in `credential_recovery.tap`; other fixtures use `cashier`. |
| BH4 | `bin/migrate.dart` not idempotent via `schema_migrations` | high | Re-runs fail on duplicate objects; spec requires idempotent DBA/CI apply. |
| BH5 | Throttles process-local and global delivery queue | medium | `_resolverCalls`/`_deliveryCalls` in memory; one tenant can exhaust delivery budget. |
| BH6 | `cs_resolve_recovery_identity` EXECUTE granted to `cs_app` without SQL throttle/audit | high | Client DB credentials can enumerate contact PII across tenants. |
| BH7 | Reserve→finalize gap leaves unusable challenge consuming rate budget | high | No sweeper or fresh-code path on placeholder digest. |
| BH8 | v29 comment contradicts fail-closed code | low | Comment says contacts are cleared; code throws. |
| BH9 | Client shows success on throttled/replayed request | high | Uniform ack means client cannot distinguish; `_requestCode` catch shows green message. |
| BH10 | Scratch artifacts in diff | low | Pre-existing staged junk, not caused by this story. |
| BH11 | No cross-package Argon2 compatibility test | medium | Claim contradicted by implementation report of a cross-package check; verify before routing. |
| BH12 | Actor insert conflict can break audit FK | high | `ON CONFLICT DO NOTHING` without target; real user with synthetic username blocks actor row. |
| BH13 | `migrationSqlPath` dead config | medium | Nothing consumes it; config test pins the wrong path. |
| BH14 | `/verify` has no idempotency key | low | Frozen scope targeted request-side idempotency; verify is single-use by OTP. |
| BH15 | HTTP hardening gaps (body limit, 405 header, plaintext bind) | medium | No request size limit; binds `0.0.0.0` without TLS enforcement. |
| VG1 | Email-channel delivery path never tested | high | All `/request` tests hardcode `channel: 'sms'`; SMTP handshake unexercised. |
| VG2 | Live-enrollment guard untested | high | Fake always `enrolled=true`; guard conjunct never observed false. |
| VG3 | Signup username persistence untested | medium | Only field-presence asserted; no submit/persist test. |
| EC1 | Zero-row password UPDATE reports success | high | No affected-row check before consuming challenge. |
| EC2 | Finalize zero-row leaves placeholder challenge | high | No cleanup on empty finalize result. |
| EC3 | Post-reservation SQL/provider exception unaudited | high | Generic ack returned without Category 14. |
| EC4 | Verify-time exception unaudited | high | Catch returns failure without Category 14. |
| EC5 | Throttle queues never pruned by key | medium | Empty identifier queues accumulate. |
| EC6 | Unbounded request body | high | No byte limit before `jsonDecode`. |
| EC7 | SMTP_TLS truthy strings silently disable TLS | high | Only literal `true` accepted; `TRUE`/`1` treated as false. |
| EC8 | Vacuous DELETE grant assertion | high | `contains('GRANT DELETE')` cannot observe combined grant. |
| EC9 | Replay echoes caller key (duplicate BH1) | high | See BH1. |

Pass-1 routing: **bad_spec** entries (BH1, BH2, BH4, BH7, BH12, EC1–EC4, EC7 + duplicates) trigger loopback 1; patch/defer entries are moot until the spec is amended.

### Review pass 2 (after loopback 1)

| # | Finding | Verdict | Evidence |
|---|---|---|---|
| BH2.1 | `SET LOCAL app.current_shop_id = @p0` with bound parameter is invalid PostgreSQL | high | `package:postgres` rewrites `@p0` to `$1`; `SET` cannot take a placeholder; pgTAP uses a literal. Every tenant-scoped backend operation fails at runtime. |
| BH2.2 | Per-process throttles; buckets never pruned by key | high | `_resolverCalls`/`_deliveryCalls` in memory; unique identifiers grow the map. |
| BH2.3 | `/verify` has no throttle | high | Unknown operation ids create unlimited Category 14 audits and DB transactions. |
| BH2.4 | SMTP TLS `false` sends credentials and codes in cleartext | high | Plain `Socket` + base64 `AUTH LOGIN`. |
| BH2.5 | Argon2 hashing inside `FOR UPDATE` transaction | medium | 64 MiB hash while holding row lock and DB connection. |
| BH2.6 | `cs_load_recovery_for_reference` returns hash and destination | medium | Resolver should return minimal identifiers only. |
| BH2.7 | Unused `cs_resolve_recovery_challenge` remains granted | high | Unused BYPASSRLS cross-tenant lookup surface. |
| BH2.8 | Reference has no expiry/nonce despite "signed, short-lived" claim | high | HMAC of operation id only; remains valid after consumption. |
| BH2.9 | Fresh device cannot log in after recovery (local cache gate) | high | `_login` throws when no cached shop id; recovery does not seed cache. |
| BH2.10 | Malformed UTF-8 before routing escapes as 500 | high | `_readBody` decode outside `_handle` try/catch. |
| BH2.11 | Rate limit is per shop+channel, not per identifier | medium | One username can exhaust recovery for the whole tenant. |
| BH2.12 | Runtime SQL coverage shallow | high | Contract tests use `contains`; pgTAP never drives backend tenant context or rotation. |
| EC2.1 | Invalid UTF-8 gives 500 | high | See BH2.10. |
| EC2.2 | Non-string JSON field gives 500 | high | Cast outside try. |
| EC2.3 | Unthrottled `/verify` abuse appends | high | See BH2.3. |
| EC2.4 | Mixed-case username fails on SMS channel | medium | Only email channel lowercases input. |
| EC2.5 | Offline resend shows success | high | Generic catch shows green message after failed resend. |
| EC2.6 | Audit failures still swallowed in outer catch paths | high | `catch (_) { /* ack anyway */ }` in `_failReservation` and outer catch. |
| VG2.1 | Session-revocation increment asserted via fake that increments itself | high | Fake increments on `UPDATE app_users` regardless of SQL text. |
| VG2.2 | v29 upgrade test never inserts duplicate contacts | medium | Metadata/pre-check tests cannot observe missing UNIQUE clauses. |

Pass-2 routing: **bad_spec** entries (BH2.1, BH2.3, BH2.4, BH2.8, EC2.5, EC2.6, VG2.1 + duplicates) trigger loopback 2; BH2.9 was resolved by the human (cache seeding added).

### Review pass 3 (after loopback 2)

| # | Finding | Verdict | Evidence |
|---|---|---|---|
| BH3.1–3 | Client server/bootstrap/embedded SQL "not removed" | false | Verified on disk: all three files are absent; `migration_runner.dart` has no `credentialRecoveryMigration`; `main.dart` has no bootstrap call. |
| BH3.4 | No negative test for embedded migration absence | low | Verified absent by direct inspection; test would be documentation only. |
| BH3.5 | Mojibake in SQL/Dart | false | Actual source files contain no mojibake; artifact of diff encoding. |
| BH3.6 | No deployment/ops artifacts or health endpoint | medium | No README/.env.example/health route/graceful shutdown in diff. |
| BH3.7 | `migrationSqlPath` dead config | medium | Parsed/pinned by tests, consumed nowhere. |
| BH3.8 | Failed delivery poisons idempotency key | high | Ledger row survives challenge deletion; retry returns `existing` with no code. |
| BH3.9 | Down migration leaves schema_migrations row | medium | Rollback then re-apply no-ops on a rolled-back schema. |
| BH3.10 | No challenge retention/cleanup policy | medium | Consumed/expired rows and contact PII persist indefinitely. |
| BH3.11 | Process-local throttles undocumented as deployment constraint | medium | Spec notes advise single instance; no runbook/ops artifact enforces it. |
| BH3.12 | Real-SQL verification incomplete/not run locally | high | Known risk; pgTAP not executed without `DATABASE_URL`. |
| BH3.13 | "Forgot username" requires password reset | low | Frozen intent permits username disclosure only after verification; accepted. |
| BH3.14 | SMTP HELO hardcoded | low | Strict providers may reject `EHLO localhost`. |
| EC3.1 | Compile error from `serverUrl` parameter | false | `flutter analyze` clean; tests construct it successfully. |
| EC3.2 | Abuse-shop SELECT lacks tenant context under FORCE RLS | high | `backend/bin/server.dart:28` queries `public.shops` with no `app.current_shop_id`. |
| EC3.3 | Throttle buckets not pruned on each call | medium | `_allow` prunes only when the bucket is consulted again. |
| EC3.4 | Malformed port silently defaults | medium | `int.tryParse(...) ?? 465` with no range validation. |
| EC3.5 | Cache-seeding failure reports reset failure | high | Seeding exception falls into dialog catch after server-side reset succeeded. |
| EC3.6 | Expired OTP does not increment attempt counter | medium | Expiry branch returns early at `state.isEmpty`. |
| VG3.1 | Real-SQL tenant rotation untested | high | Fake bypasses `shop_id`/reference predicates; pgTAP uses its own SQL. |
| VG3.2 | Production gateway wiring never exercised | high | All tests inject a gateway; no `--dart-define` check for `CS_RECOVERY_SERVER_URL`. |
| VG3.3 | Unrelated settle-flow test failures | N/A | Pre-existing, already deferred; not caused by this story. |
| VG3.4 | Dead `migrationSqlPath` (duplicate BH3.7) | medium | See BH3.7. |

Pass-3 routing: **bad_spec** entries (BH3.8, EC3.2, EC3.5, VG3.1, VG3.2 + duplicates) trigger loopback 3; documentation/cleanup items are bundled into the same amendment.

### Review pass 4 (after loopback 3)

| # | Finding | Verdict | Evidence |
|---|---|---|---|
| BH4.1 | `/request` resolver-throttle audit failure escapes as 500 | high | `abuseOnce` before method `try`; `_handle` has no catch. |
| BH4.2 | `/verify` reference lookup / unknown-id audit failure escapes as 500 | high | Both before `try`. |
| BH4.3 | `/verify` throttle keyed by caller UUID; rotateable | high | Fresh UUID gets a fresh budget; unlimited Category 14 rows. |
| BH4.4 | SMS endpoint `http://` accepted | high | Only non-empty check; OTP + bearer key in cleartext. |
| BH4.5 | Empty post-rotation context commits reset but returns 400 | high | `if (refreshed.isEmpty) return null` after rotation inside tx. |
| BH4.6 | Migration 003 not idempotent across psql CLI and Dart CLI | medium | psql harness does not record `schema_migrations`. |
| BH4.7 | Rate-limited ledger rows grow unbounded | medium | Ledger insert on every throttled request; count only examines challenges. |
| BH4.8 | v29 comment contradicts fail-closed code | low | Previously logged, still present. |
| BH4.9 | v29 rebuild hand-copies columns | medium | Later columns could be dropped; no parity test. |
| BH4.10 | `migrationSqlPath` dead config | medium | Parsed/pinned, consumed nowhere. |
| BH4.11 | Actor-cleanup `substr(...,1,21)` shorter than 25-char prefix | medium | Real user with that username prefix could be deleted on rollback. |
| BH4.12 | Scratch artifacts in diff | low | Pre-existing staged junk; not this story's defect. |
| BH4.13 | Status artifacts disagree with spec task | low | Spec marks story done task checked while status is in-progress; resolved at finalization. |
| BH4.14 | Client URL accepts `http://` | high | OTP and new password can be sent in cleartext. |
| EC4.1 | Recovery seed leaves stale password hash locally | high | Update branch of `seedRecoveryIdentity` does not clear hash. |
| EC4.2 | `cs_app` lacks DELETE on operations ledger | high | Cleanup fails; idempotency key poisoned. |
| EC4.3 | Cleartext SMS endpoint (duplicate BH4.4) | high | See BH4.4. |
| EC4.4 | SMTP reply hang | medium | No deadline in `expect()`. |
| EC4.5 | Audit failures swallowed (duplicate of pass-2 patch) | high | Catch paths still ack without append. |
| VG4.1 | Recovery entry point on login untested | medium | No test taps `forgotCredentialsButton`. |
| VG4.2 | Production default-gateway branch untested | high | Every test injects a gateway/factory. |
| VG4.3 | v29 upgrade test pins generated metadata | medium | No duplicate insert into upgraded DB. |

Pass-4 routing: **bad_spec** entries (BH4.1–5, BH4.14, EC4.1–2 + duplicates) trigger loopback 4.

### Review pass 5 (final automated pass)

| # | Finding | Verdict | Evidence |
|---|---|---|---|
| BH5.1 | Uniform `/request` ack breaks when resolver-throttle audit fails | high | `abuseOnce` still before method `try`; `_handle` generic catch returns 400. |
| BH5.2 | Uniform `/verify` failure body breaks on unknown-id audit failure | high | Lookup/audit before transaction `try`. |
| BH5.3 | Health-route method contract wrong | medium | POST `/health` → 404, README promises 405 + Allow. |
| BH5.4 | Production default-gateway branch still untested | high | CI-configured test skips the no-injection branch. |
| BH5.5 | No cross-tenant `/verify` test | high | No fake/real-SQL case with foreign shop id. |
| BH5.6 | Offline gate no-op in production | high | `login_screen.dart` defaults `isOnline` to always true. |
| BH5.7 | Request transport failure shows green success | high | Dialog catch sets generic request message on any non-offline error. |
| BH5.8 | Runbook retention SQL cannot work under FORCE RLS | medium | DELETE without tenant context matches nothing. |
| BH5.9 | Config requires both SMTP and SMS channels | medium | User-selectable channels but startup needs both. |
| BH5.10 | Scratch/log artifacts in diff | low | Pre-existing staged junk. |
| BH5.11 | Status artifacts inconsistent | low | Spec in-review vs checked tasks; reconcile at finalization. |
| EC5.1 | Step-one failure shows success | high | See BH5.7. |
| EC5.2 | Crash between create/finalize leaves undeliverable challenge | high | `existing` status has no re-finalize path. |
| EC5.3 | Digest mismatch does not invalidate challenge | medium | State-empty branch audits but does not increment/consume. |
| EC5.4 | Cleanup fallback leaves finalized challenge live | high | Abuse-shop fallback does not delete challenge. |
| VG5.1 | Resolver throttle branch untested | medium | No 61-request test. |
| VG5.2 | Production SQL never executed against PostgreSQL | high | Fakes use substring matching; pgTAP uses its own SQL. |
| VG5.3 | Credit-details display test stale | N/A | Pre-existing, already deferred. |

Pass-5 routing: **bad_spec** entries (BH5.1, BH5.2, BH5.6, BH5.7, EC5.2, EC5.4 + duplicates) remain. Further loopback would reach iteration 5 (the workflow limit); escalation to the human is appropriate.

### Review pass 6 (at workflow limit — HALT, no further loopback)

| # | Finding | Verdict | Evidence |
|---|---|---|---|
| BH6.1 | Finalized-but-undelivered challenge after crash still locked out | high | `_recoverUnfinished` aborts when digest is set; loopback-5 requirement not fully met. |
| BH6.2 | Default-gateway test never posts | high | No-factory case asserts type/URL only, no HTTP request. |
| BH6.3 | README env table requires all three channel vars | low | Config allows either channel independently. |
| BH6.4 | `CS_RECOVERY_EMAIL_FROM` not validated for CRLF | high | Interpolated into SMTP `MAIL FROM` and `From:`. |
| BH6.5 | Throttle queues grow under high-cardinality attack | medium | `_allow` prunes only consulted buckets. |
| BH6.6 | v29 rebuild has no column-parity assertion | medium | Hand-copied column list can drift. |
| BH6.7 | Production SQL never executed against real PostgreSQL | high | Fakes use substring matching; pgTAP uses its own SQL. |
| BH6.8 | Dialog `show()` always returns null on Close | low | Return contract dead; callers ignore it. |
| BH6.9 | Spec/status artifacts inconsistent | low | Spec in-review with open findings; stories in-progress. |
| BH6.10 | Scratch/log artifacts in diff | low | Pre-existing staged junk. |
| EC6.1 | Finalize zero rows then delivery | false | Guard `if (finalized.isEmpty) return _failReservation(...)` is present. |
| EC6.2 | Unvalidated `from` header | high | See BH6.4. |
| EC6.3 | IPv6-only device wrongly offline | medium | IO connectivity checks only non-loopback interfaces. |
| EC6.4 | Gateway POST untested (duplicate BH6.2) | high | See BH6.2. |
| VG6 | No verification gaps found | — | All backend/client/SQL/migration paths covered by running tests. |

HALT at `review_loop_iteration: 5` (further loopback would exceed the workflow limit). Remaining high items are documented here and in `deferred-work.md`; no further automated re-derivation will be attempted.

## Verification

**Commands:**
- `dart analyze backend/` -- expected: zero issues
- `dart test backend/test/` -- expected: all pass
- `flutter analyze` -- expected: zero issues
- `flutter test test/unit/features/auth/ test/widget/features/auth/` -- expected: all pass
- `bash test/integration/tenant_isolation/run_pgtap_tests.sh` -- expected: pass when `DATABASE_URL` and pgTAP are configured; skip cleanly otherwise
