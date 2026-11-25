---
title: 'Secure Staff Credential Recovery (Forgot Username / Password)'
type: 'feature'
created: '2026-11-25'
status: 'in-review'
baseline_commit: '8fd3727d4e3faa6f8c3cab8fea2b8871fb42b41d'
route: 'dispatch'
review_loop_iteration: 3
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The shipped "Forgot username or password?" flow lets any person who knows a Shop ID overwrite the Shop Owner's password in local Drift SQLite and learn their username. It never reaches PostgreSQL (the source of truth), has no identity verification, no audit event, no rate limit, and violates tenant isolation and session-revocation contracts.

**Approach:** Replace it with a server-authoritative, two-step self-service recovery: request a single-use OTP delivered to the staff account's verified contact channel, then verify the OTP and set a new password. Unauthenticated responses are identical in **body and status** (timing equality is explicitly not required). Delivery credentials and the OTP pepper live only in a server-side component; the client never holds them. Success atomically rotates the password hash and increments `session_version` to revoke all sessions.

## Boundaries & Constraints

**Always:** PostgreSQL is the only authority for recovery — no local `app_users` password write. Tenant context comes from server records only, never a client-supplied shop ID. OTP is high-entropy, hashed at rest, single-use, short-TTL, constant-time compared. `client_operation_id` + idempotency key on every request; re-transmission returns the existing challenge's own operation id. Reset increments `session_version`; result is `ConfirmedByServer`. Audit appends under Category 12 (request/reset) and Category 14 (failure/abuse) via `cs_record_audit_event`; no 15th category, no 15th permission. No credential, OTP, or password in logs or audit. Recovery is blocked offline. Close the `app_users` login-identifier collision (unique `(shop_id, email)` / `(shop_id, phone)`) before release. Provider credentials and the OTP pepper are held exclusively by the server-side delivery endpoint.

**Never:** No local-only reset dialog, no username/channel disclosure to an unauthenticated caller, no client-held delivery secrets, no cross-tenant lookup, no client-supplied `shop_id`, no `getUserByLoginIdentifierGlobal`, no offline recovery, no modification of `001`/`002` migration SQL (checksum), no audit UPDATE/DELETE, no new RBAC permission.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| Unknown identifier | Unauthenticated request, no matching staff account | Same generic body/status as known case; no challenge persisted | N/A |
| Known identifier | Staff account with verified contact channel | Single-use hashed OTP challenge persisted; delivery via server endpoint; same generic body/status | N/A |
| Re-transmission | Same `client_operation_id` / idempotency key | Returns the existing challenge's operation id; no second OTP or delivery | N/A |
| Reused idempotency key, new operation id | Different operation id, same idempotency key | Returns the stored operation id, never the new one | N/A |
| Successful reset | Valid, unconsumed, unexpired OTP + password of min length 8 with confirmation | Hash updated, `session_version` + 1, challenge consumed, Category 12 audit, all sessions revoked | N/A |
| Invalid OTP | Wrong / expired / consumed / attempt threshold reached | Same generic failure; attempt counter increments without violating DB CHECK; challenge invalidated at threshold; Category 14 audit | No hint which condition failed |
| Delivery failure | Server endpoint reports failed delivery | No challenge persisted; generic response; user may resend with a fresh operation id | No account existence disclosed |
| Offline | Any recovery step with no server connectivity | Action blocked; no local write | Generic offline message |
| Cross-tenant probe | Identifier matching exactly one foreign tenant | A challenge may be created only for that verified channel; no caller tenant is disclosed; ambiguous matches are rejected with Category 14 | N/A |
| Username recovery | Verified caller wants forgotten username | Username shown only after successful OTP verification | Never shown pre-verification |
| Login identifier migration | Staff previously logged in with email/phone | Login is username-only with an in-app notice explaining how to find the username | N/A |
| Cached multi-tenant username | Same username cached for more than one shop locally | Caller must explicitly select a tenant before login; never silently pick the first | N/A |

## Decisions (approved 2026-11-25, review loopback 1)

- **Delivery channels:** both email and SMS, user-selectable at request time. Email uses the staff account's verified `email`; SMS uses its verified `phone`.
- **Providers and secrets:** SMTP for email and a generic HTTP SMS gateway for SMS. Credentials, endpoints, sender identities, and the OTP pepper are held **only by a server-side delivery endpoint**; the Flutter client holds no secrets. Secrets come from server environment variables, never source code.
- **OTP policy:** 5-minute TTL, 5 failed attempts maximum, rate limiting scoped per tenant + channel and enforced atomically in SQL.
- **Enrollment:** staff without a verified email/phone must have one registered by the Shop Owner in Staff Management (FR-5) before self-recovery is available; no self-enrollment and no platform-admin path.
- **Username disclosure:** shown only after successful OTP verification; never in the request response or the delivery payload.
- **Response equivalence:** identical body and status for matched/unmatched identifiers; literal timing equality is not required.
- **Cross-tenant single match:** acceptable because the OTP is delivered only to the verified channel; ambiguous matches are rejected with a Category 14 audit.
- **Password policy:** new password requires a confirmation field and a minimum length of 8 characters.
- **Resend:** delivery failure leaves no challenge; the user may resend with a fresh `client_operation_id` and idempotency key.
- **Login migration:** username-only login with an in-app notice; when a cached username exists in multiple tenants, the caller explicitly selects a tenant.

</frozen-after-approval>

## Code Map

- `lib/features/auth/data/services/auth_service.dart` -- add server-only `requestCredentialRecovery` / `confirmCredentialRecovery`; reuse `transactionWithTenant`, `PasswordHashService`, and the `revokeSession` audit pattern (:611-668). Return the stored operation id on replay; validate password length; guard attempts below the DB CHECK.
- `server/otp_delivery_server.dart` (new) -- server-side HTTP endpoint holding SMTP/SMS credentials and the OTP pepper; delivers the code and returns only an acknowledgement. Client never holds these secrets.
- `lib/features/auth/data/services/otp_gateway.dart` -- thin client adapter that posts identifier/channel/OTP to the server endpoint; no provider secrets, no pepper; HTTP timeout.
- `lib/features/auth/data/daos/user_dao.dart` -- `getUserByLoginIdentifierGlobal` removed; tenant-scoped resolution; expose cached tenant ids for explicit selection.
- `lib/core/data/local/tables/app_users_table.dart` -- `(shopId, email)` / `(shopId, phone)` unique keys; regenerate `app_database.g.dart`; add Drift v29 migration so existing installs gain the constraints.
- `lib/core/data/remote/migrations/003_credential_recovery.sql` + `_down.sql` -- challenge table, FORCE RLS, unique constraints, narrow resolvers, atomic SQL rate limit, system-actor constant for unauthenticated audits.
- `lib/core/data/remote/migration_runner.dart` -- register migration version 3 with parity test.
- `lib/features/audit/domain/models/audit_event_record.dart:62-78` -- canonical Categories 12/14; action type `credential_password_reset`.
- `lib/features/auth/presentation/credential_recovery_dialog.dart` -- two-step flow, password confirmation + min length, resend action, generic errors, username only after verification.
- `lib/features/auth/presentation/login_screen.dart` -- remove flawed dialog; username-only notice; explicit tenant picker when cached username spans shops.
- `pubspec.yaml` -- direct `http` dependency; `shelf` for the server endpoint.
- `test/unit/features/auth/auth_service_test.dart` -- recovery behavior gates with mocks.
- `test/unit/features/auth/otp_gateway_test.dart` -- `http.MockClient` tests for the client adapter.
- `test/unit/core/data/remote/postgres_migration_contract_test.dart` -- 003 DDL/contract/parity tests.
- `test/unit/core/data/local/database_connection_test.dart` -- fresh **and** v28→v29 upgrade uniqueness tests.
- `test/widget/features/auth/credential_recovery_dialog_test.dart` -- two-step UI, confirmation, resend, generic errors.
- `test/integration/tenant_isolation/` -- new recovery `.tap` file executing resolvers/RLS/constraints against real PostgreSQL.

## Tasks & Acceptance

**Execution:**
- [x] `lib/core/data/remote/migrations/003_credential_recovery.sql` (+ down) -- challenge table with FORCE RLS, `(shop_id,email)`/`(shop_id,phone)` uniqueness, narrow resolvers, atomic SQL rate limit, system-actor constant -- server authority.
- [x] `lib/core/data/remote/migration_runner.dart` -- register version 3 with SQL parity -- checksum correctness.
- [x] `server/otp_delivery_server.dart` (new) -- server endpoint with env-only SMTP/SMS credentials and pepper -- no secrets in the client binary.
- [x] `lib/features/auth/data/services/otp_gateway.dart` -- client adapter with timeout, no secrets -- server-held credentials.
- [x] `lib/features/auth/data/services/auth_service.dart` -- request/confirm with replay-safe operation id, password length check, attempt guard, canonical audit action, no timing-equality claim -- core behavior.
- [x] `lib/features/auth/data/daos/user_dao.dart` -- tenant-scoped resolution and cached tenant ids -- close collision and support explicit selection.
- [x] `lib/core/data/local/tables/app_users_table.dart` + `lib/core/data/local/app_database.dart` -- unique keys and v29 upgrade migration -- existing installs protected.
- [x] `lib/features/auth/presentation/credential_recovery_dialog.dart` (new) + `lib/features/auth/presentation/login_screen.dart` -- two-step flow, confirmation, resend, username-only notice, tenant picker -- secure UI.
- [x] `pubspec.yaml` -- `http` + `shelf` dependencies -- gateway support.
- [x] `test/unit/core/data/remote/postgres_migration_contract_test.dart` -- 003 DDL/contract/parity tests -- migration safety.
- [x] `test/unit/core/data/local/database_connection_test.dart` -- fresh and upgrade uniqueness tests -- upgrade safety.
- [x] `test/unit/features/auth/auth_service_test.dart` -- replay, generic responses, attempt threshold, rate limit, revocation, audit, cross-tenant, delivery failure -- behavior gates.
- [x] `test/unit/features/auth/otp_gateway_test.dart` -- `MockClient` endpoint/body/header/failure tests -- real adapter coverage.
- [x] `test/widget/features/auth/credential_recovery_dialog_test.dart` -- confirmation, resend, generic errors, username-after-verification, tenant picker -- UI gates.
- [x] `test/integration/tenant_isolation/credential_recovery.tap` + harness -- real PostgreSQL resolver/RLS/uniqueness assertions -- DB boundary proof.

**Acceptance Criteria:**
- Given an unauthenticated caller, when any recovery request is made, then the body and status are identical for matched and unmatched identifiers and never contain a username, shop id, or channel.
- Given a challenge, when the same operation or idempotency key is re-transmitted, then exactly one OTP was generated and delivered and the stored operation id is returned.
- Given a valid OTP and a password of at least 8 characters with matching confirmation, when committed, then hash and `session_version` change atomically, the challenge is consumed, `credential_password_reset` is appended under Category 12, and all sessions are revoked.
- Given an invalid, expired, consumed, or threshold-reached OTP, when verification is attempted, then the same generic failure is returned, the attempt counter never violates its CHECK, and Category 14 is appended.
- Given delivery failure, when the endpoint reports it, then no challenge persists and a fresh resend is possible.
- Given no server connectivity, when recovery is attempted, then it is blocked and no local `app_users` write occurs.
- Given a cached username in multiple tenants, when logging in, then the caller selects the tenant explicitly.
- Given a client-side inspection of the shipped app, when secrets are searched for, then no provider credential or pepper is found.

### Loopback 2 required corrections (non-frozen; bad_spec fixes)

- **Server generates the OTP.** `/deliver` receives only an opaque challenge reference and the server-side destination; it generates the code, stores/returns the peppered digest, and never accepts a client-supplied OTP. A client cannot self-verify a known code.
- **Delivery endpoint is bound and authenticated.** `/deliver` requires a signed, short-lived request tied to a server challenge; destination is derived from the challenge record, never from client input. Reject unknown references. Add a global delivery rate limit.
- **Atomic reserve-then-deliver.** `cs_create_recovery_challenge` is the authoritative step: branch on its `status` (`created` / `replay` / `rate_limited`); only `created` delivers. No provider traffic for rate-limited/replayed requests. Replays return the stored operation id and idempotency key.
- **Single-use is permanent.** Failed attempts use `CASE WHEN @p0 >= @p1 THEN NOW() ELSE consumed_at END`; an already-consumed challenge can never be reactivated.
- **Resolver abuse control.** Throttle unauthenticated resolver calls generically (per identifier hash and per process) and append Category 14 for rate-limit abuse; no un-audited early returns.
- **Per-tenant system actor.** Create a deterministic system actor per shop (e.g. UUIDv5 of tenant + fixed name) so audit actor FKs never cross tenants; keep a nullable/system actor alternative if simpler.
- **Runtime secrets on the server.** Use `Platform.environment` for server pepper, endpoints, credentials, and sender identities; compile-time defines are for the client endpoint URL only.
- **Contact validation.** Reject CRLF and control characters; validate email format and E.164 phone before SMTP/provider use.
- **v29 upgrade is non-destructive.** Detect each unique constraint via `PRAGMA index_list`/`index_info`; fail closed on duplicate contacts exactly as PostgreSQL does. Do not null verified channels silently.
- **Verification wiring.** Add a CI step invoking `bash test/integration/tenant_isolation/run_pgtap_tests.sh` with `DATABASE_URL`; include `/hash` and `/deliver` contract tests; extend the tenant-picker test to assert the selected tenant's user is used; add a signup username test.

### Loopback 3 required corrections (non-frozen; bad_spec fixes)

- **Deploy migration 003.** Add a production call site that applies `registeredMigrations` through `MigrationRunner.applyAll()` at startup/config time, with idempotent tracking and a documented operator path. Tests alone must not be the only applier.
- **No process-local secrets or OTP state.** `/deliver` and `/verify` must read the peppered digest and pending reference from PostgreSQL (`credential_recovery_challenges`), never an in-memory map; restart and multi-instance deployments must work. Store the signed reference in the challenge row.
- **Uniform response body.** Created, replay, rate-limited and unknown paths return the identical acknowledgement object — no `deliveryReference` field on one path only. The reference, if needed, must be conveyed out-of-band or be deterministic from the operation id.
- **Audit every abuse path.** Resolver throttle, delivery throttle, invalid reference, and delivery failure all append Category 14 (without recipient or OTP). Use a per-identifier-hash throttle, not one global queue. Exactly one Category 14 per failed verification (remove the duplicate append).
- **Server unconditionally returns the stored idempotency key**, never the caller's, on replay. Generate the OTP only after a `created` status is confirmed.
- **Actor row is valid, per-tenant, and cleaned.** Verify the `role` value against the schema before inserting the synthetic actor; drop those rows in the 003 down migration; make pgTAP assert the same deterministic actor derivation the SQL uses.
- **Consistent DELETE contract.** Either grant DELETE to `cs_app` and allow cleanup (update the contract test accordingly), or move cleanup to a privileged server role; the test suite must assert one unambiguous invariant.
- **Server-authoritative expiry and active recheck.** Re-check `expires_at` with SQL `NOW()` and that the target user is still active/enrolled inside the reset transaction. Stop selecting `otp_hash` into the client.
- **Resolver normalization.** Compare `lower(btrim(u.username))` for the email channel so mixed-case usernames resolve; add pgTAP coverage.
- **v29 detector exactness.** Require an index's column set to equal `(shop_id, email)` / `(shop_id, phone)` exactly; fix pgTAP's bare `NOW` in the duplicate-email fixture; assert `23505`.
- **Tests for the previously uncovered paths:** `match_count=2` at `/request`, delivery failure (502) deletion + audit, `status='existing'` replay, cross-tenant confirm, and pgTAP actor derivation.

## Implementation Notes

- 2026-11-25: Initial implementation verified against the baseline diff (`flutter analyze` clean, 149 tests passed), then review loopback 1 re-derived the plan from human decisions. This file supersedes the earlier notes; the earlier notes remain in the Spec Change Log and Review Triage Log.
- KEEP: server-authoritative flow, hashed OTP, idempotency keys, generic body/status, Category 12/14 reuse, session revocation, offline block, no new permission/category, all passing unit/widget tests.
- Risk: server endpoint deployment (credentials and pepper) is a deployment responsibility; the Flutter repo contains the endpoint source only.
- 2026-11-25 (loopback 1 re-derivation): all 15 tasks complete. Verified independently: `flutter analyze` zero issues; unit suite + `database_connection_test` + `test/widget/features/auth/` → 166 tests passed. All 12 I/O matrix rows have covering tests that ran and passed, including delivery failure, replay with distinct idempotency key, password confirmation, resend, tenant picker, and v28→v29 upgrade.
- Remaining risk: 003 SQL and `credential_recovery.tap` have not been executed against a real PostgreSQL instance (`DATABASE_URL` unset); the server endpoint must be deployed with correct env configuration.
- 2026-11-25 (loopback 2): pass-2 security review found client-chosen OTPs, an open-relay delivery endpoint, ignored rate-limit status, pre-insert delivery, challenge reactivation, compile-time server secrets, SMTP injection, destructive v29 upgrade, and unwired pgTAP. KEEP: server-held secrets, generic body/status, Category 12/14, session revocation, offline block, idempotency, no new permission/category, all existing passing tests.

## Spec Change Log

- 2026-11-25 (review loopback 1): trigger — intent gaps on timing equality, cross-tenant single match, client-held secrets, password confirmation, resend, and login migration; plus bad-spec gaps on tenant selection, atomic rate limiting, audit actor, and the local schema upgrade. Amended the frozen intent (body/status equivalence only; server-held secrets; cross-tenant single match allowed; password confirmation/min length; resend; username-only login with tenant picker) and non-frozen tasks (server endpoint, v29 local migration, atomic SQL rate limit, canonical action name, attempt guard). Avoided the known-bad state: client-baked secrets, CHECK-violating sixth attempt, silently-first-tenant login, and fresh-install-only uniqueness. KEEP instructions: server-authoritative flow, hashed OTP, idempotency, generic body/status, Category 12/14 reuse, session revocation, offline block.

- 2026-11-25 (review loopback 2): trigger — pass-2 security defects (client-chosen OTP, open relay, ignored rate-limit status, pre-insert delivery, challenge reactivation, compile-time server secrets, SMTP injection, destructive v29 upgrade, unwired pgTAP). Amended only non-frozen sections: explicit server-OTP generation, signed/bound delivery endpoint, atomic reserve-then-deliver, permanent single-use, generic resolver throttle with Category 14, per-tenant system actor, `Platform.environment`, contact validation, non-destructive v29, and CI wiring. Avoided the known-bad state: self-verifiable OTP, open relay, reusable challenge, cross-tenant audit actor, data-destroying upgrade, tests that never run. KEEP instructions: server-authoritative flow, server-held secrets, hashed OTP, idempotency, generic body/status, Category 12/14 reuse, session revocation, offline block, no new permission/category.

- 2026-11-25 (review loopback 3): trigger — pass-3 defects (migration 003 never applied, process-local OTP state, response-body enumeration, un-audited abuse paths, actor row lifecycle, contradictory DELETE grant, stale pgTAP fixture). Amended only non-frozen sections: production migration application, DB-backed server state, uniform acknowledgement body, per-identifier throttling with full Category 14 coverage, stored idempotency key, post-status OTP generation, valid/cleaned per-tenant actor, consistent DELETE contract, SQL expiry/active rechecks, resolver normalization, exact v29 detection, and missing path tests. Avoided the known-bad state: paper-only migration, restart-broken recovery, enumerable responses, unaudited abuse, cross-tenant actor FKs, tests that cannot pass. KEEP: server authority, server-held secrets, hashed OTP, idempotency, generic body/status, Category 12/14 reuse, session revocation, offline block, no new permission/category.

## PAUSED — redesign decision (2026-11-25)

Four review passes each surfaced new spec-level defects. Root cause is architectural: the OTP "server" is a Dart component inside the Flutter client. The human chose to **redesign as a standalone backend service** instead of a fourth loopback. Do not resume implementation from this spec. Next: run `bmad-correct-course` to amend AD-9 for a real backend, then a fresh `bmad-build` with a new spec for the backend service. Unresolved items are logged in `deferred-work.md`. KEEP: frozen intent (body/status equivalence, server-held secrets, single-use OTP, audit reuse, no new permission/category) and all passing auth/recovery tests. This spec remains `in-review` and is superseded by the redesign.

## Review Triage Log

Verdicts rendered from verification against the diff and the actual files; duplicative reports of one defect are kept as separate rows (same claim, same evidence).

| # | Finding | Verdict | Evidence |
|---|---|---|---|
| E1 | `login_screen.dart:144` multi-tenant username silently uses first shop | medium | `shopIds.first` at :144; no tenant selection exists; doc at user_dao.dart:81 says caller must choose. |
| E2 | `auth_service.dart:1182` sixth attempt sets `attempts=6`, violating `ck_recovery_attempts <= 5` | high | SQL CHECK in 003:36; `nextAttempts=attempts+1` at :1181; exception aborts tx before audit at :1191. |
| E3 | `auth_service.dart:1214` password UPDATE may match zero rows | false | `challenge.user_id` has FK `ON DELETE RESTRICT` to `app_users`; row cannot be deleted while challenge exists. |
| E4 | Rate-limit SELECT/INSERT race | medium | Count at :1036-1047 and INSERT at :1063 are separate statements in one tx; concurrent txs can both pass. |
| E5 | `auth_service.dart:1091` null gateway persists challenge with undeliverable code | medium | `created` computed before gateway check; `gateway != null` only gates delivery. |
| E6 | `auth_service.dart:1104` re-transmission with reused idempotency key returns the new operation id | medium | `existing` query at :1025 matches either key; result at :1104 returns caller's `operationId`. |
| E7 | `otp_gateway.dart` HTTP post has no timeout | medium | `_client.post(...)` has no `.timeout`; hung provider blocks recovery indefinitely. |
| E8 | Dialog keeps green success message beside red failure on step-two error | low | `_confirmRecovery` catch clears `_error` only; `_message` from step one stays set. |
| E9 | Timing side channel between matched/unmatched identifier | high | Unknown path hashes in memory only; known path does resolver + tx + INSERT + audits + HTTP. |
| E10 | Extra OTP generated in memory on replay | false | `_generateOtp()` at :1020 is discarded when `existing` is found; no delivery, persistence, or observable effect. |
| E11 | Threshold failure appends no Category 14 (duplicate of E2) | high | Same tx abort at :1182 before audit execute at :1191. |
| E12 | Identifier matching exactly one foreign tenant still creates a challenge | high | Only `matchCount > 1` is rejected at :614; a single foreign match persists a challenge. |
| B1 | Migration 003 never executed against real PostgreSQL | high | pgTAP harness applies 003 but no `.tap` asserts RLS/resolvers/constraints; spec notes record it unrun. |
| B2 | No CI gate wires new recovery tests | false | `.github/workflows/ci.yml:44` runs `flutter test test/unit/ test/widget/`; all new tests are included. |
| B3 | No verified flag / enrollment path | false | Frozen Decision says owner-registered email/phone is the verified channel; no flag was required. |
| B4 | Timing equality not achieved (duplicate of E9) | high | Same code paths; response bodies match but timing does not. |
| B5 | Unknown identifiers bypass rate limiting | high | Resolver query at :990 runs before any challenge/rate check; unbounded DB load and timing oracle. |
| B6 | Secrets baked into client via `String.fromEnvironment` | high | `otp_gateway.dart:82-88` and `auth_service.dart:_otpPepper`; extractable from shipped binary. |
| B7 | No password confirmation/strength check | medium | Dialog has one password field; `confirmCredentialRecovery` rejects only empty password. |
| B8 | Delivery failure swallowed with no resend path | medium | Catch at :1098 ignores error; dialog advances to step two; user has no code. |
| B9 | Audit actor/IP/UA misattributed | medium | All recovery audits pass victim id as actor and `NULL` for IP/UA. |
| B10 | Local `schemaVersion` not bumped for new unique keys | medium | `app_database.dart:133` still 28; no `onUpgrade` step for the two keys. |
| B11 | Audit action `credential_recovery_completed` vs canonical `credential_password_reset` | medium | `auth_service.dart:1237`; PRD/change proposal name `credential_password_reset`. |
| B12 | Attempt CHECK violation (duplicate of E2) | high | See E2. |
| B13 | Scratch/debug files added | low | `output.txt`, `summary.txt`, `test_output.txt`, `_tmp/claims...` were already staged before this build's baseline work. |
| B14 | Email/phone login removed with no migration path | medium | `authenticate` now `WHERE username = @p0`; login label changed; no notice/fallback. |
| B15 | Missing tests for delivery failure, distinct idempotency key, cross-tenant confirm, timing | medium | No such tests exist in `auth_service_test.dart` or dialog widget test. |
| V1 | SQL resolvers/RLS/uniqueness never executed by a test | high | Pre-verified: contract tests use `contains`, mocks bypass SQL, no recovery `.tap` exists. |
| V2 | Real `HttpOtpGateway` mocked away in every test | medium | Pre-verified: no `otp_gateway_test.dart`; fakes injected everywhere. |
| V3 | Local uniqueness verified only on fresh schema | medium | Pre-verified: `database_connection_test.dart:269` uses in-memory fresh DB, never `onUpgrade`. |
| V4 | `schemaVersion` 28 (duplicate of B10) | medium | See B10. |
| V5 | Login `.first` (duplicate of E1) | medium | See E1. |
| V6 | Rate-limit doc says "SQL-enforced" but is Dart-only | low | Comment at `auth_service.dart:934`; count computed in Dart at :1036. |

### Review pass 2 (after loopback 1 re-derivation)

| # | Finding | Verdict | Evidence |
|---|---|---|---|
| BH1 | OTP chosen by client; out-of-band check self-verifiable | high | `_generateOtp()` in Dart; `/hash` and `/deliver` accept client OTP; spec requires server-held secrets and server authority. |
| BH2 | `/deliver` is an unauthenticated open relay | high | Endpoint accepts arbitrary `destination` + `otp` with no challenge binding or rate limit. |
| BH3 | `rate_limited` status ignored, success shown | high | `cs_create_recovery_challenge` returns status; only `stored_operation_id` read; test asserts delivery on rate-limit path. |
| BH4 | Delivery precedes authoritative challenge insert | high | Pre-checks in separate transactions; concurrent replays deliver twice; saturated tenant still generates traffic. |
| BH5 | Failed attempt can clear `consumed_at` and reactivate OTP | high | `CASE WHEN @p0 >= @p1 THEN NOW() ELSE NULL END` overwrites a consumed challenge. |
| BH6 | Resolver calls have no abuse throttle | high | Unknown identifier returns before any limit; resolver performs cross-tenant scan/sort. |
| BH7 | Global system-actor row breaks audit tenant isolation | high | Fixed UUID primary key with `ON CONFLICT DO NOTHING` means only first tenant has an actor row. |
| BH8 | Server config read with `String.fromEnvironment` | high | Compile-time defines only; runtime env deployment fails; pepper cannot rotate. |
| BH9 | SMTP CRLF/header injection via destination | high | Raw `RCPT TO:<$to>` / `To: $to` interpolation; no format validation. |
| BH10 | v29 upgrade nulls duplicate contacts; detector never matches | high | Destructive rebuild on every v28 open; PG migration instead fails closed on duplicates. |
| BH11 | Server endpoint and pgTAP assertions never executed | high | No server tests; CI runs only `flutter test`; `.tap` harness never invoked. |
| BH12 | Dialog discards `result.clientOperationId` | medium | `_requestCode`/`_resendCode` store the locally generated id, not the stored one. |
| BH13 | Delivery failure produces no Category 14 audit | medium | `OtpDeliveryException` swallowed silently. |
| EC1 | Consumed challenge reusable (duplicate of BH5) | high | Same `ELSE NULL` overwrite. |
| EC2 | Rate-limit short-circuit unaudited | medium | Dart early return at :1039 before audited SQL path. |
| EC3 | Concurrent replay double delivery (duplicate of BH4) | high | Deliver-before-insert ordering. |
| EC4 | Mixed-case username fails on email channel | medium | Resolver lowercases identifier but compares raw `u.username`. |
| EC5 | Open relay (duplicate of BH2) | high | See BH2. |
| EC6 | CRLF injection (duplicate of BH9) | high | See BH9. |
| EC7 | Compile-time secrets (duplicate of BH8) | high | See BH8. |
| EC8 | Claim: single-use guarantee broken (duplicate of BH5) | high | See BH5. |
| EC9 | Claim: exactly-one OTP broken (duplicate of BH4) | high | See BH4. |
| EC10 | Claim: server env secrets false (duplicate of BH8) | high | See BH8. |
| EC11 | Claim: Category 14 on abuse false (duplicate of EC2) | medium | See EC2. |
| VG1 | pgTAP recovery tests never executed | high | Pre-verified: no runner invocation; CI only runs Dart tests. |
| VG2 | Tenant picker test never asserts chosen tenant used | medium | Pre-verified: test asserts dialog renders only. |
| VG3 | Signup username field has no test | medium | Pre-verified: no signup test exists. |
| VG4 | Server endpoint has no tests | medium | Pre-verified; filed disposition `defer` — separately deployed component. |
| VG5 | UI never reuses operation/idempotency key on retry | medium | Fresh UUID on every request/resend; no stored idempotency key. |
| VG6 | Open relay (duplicate of BH2) | high | See BH2. |

Pass-2 routing: **bad_spec** entries (BH1, BH2, BH4, BH6, BH7, BH10 + duplicates) trigger loopback 2; patch/defer entries are moot until the spec is amended. No new frozen-intent change is required, so no human renegotiation is needed.

### Review pass 3 (after loopback 2 re-derivation)

| # | Finding | Verdict | Evidence |
|---|---|---|---|
| E3.1 | Reference/operation mismatch could reset another tenant's user | false | Guard `if (referenceOperationId != operationId) throw ...` is present at :1049-1061. |
| E3.2 | Expiry evaluated with client clock | medium | `DateTime.now()` in client confirm; no SQL `NOW()` recheck in transaction. |
| E3.3 | Uppercase username fails on email channel | medium | Resolver lowercases input but compares raw `u.username`. |
| E3.4 | Server restart loses pending references | high | `_pending` is in-process only; DB digest never read on deliver/verify. |
| E3.5 | v29 unique-index detector matches supersets | medium | Detector accepts an index with extra columns, skipping the required constraint. |
| E3.6 | Created vs unknown response bodies differ (`deliveryReference`) | high | `_ack` omits the field; created path includes it — account enumeration. |
| E3.7 | OTP generated before status check | medium | `_generateOtp()` runs on replay/rate-limited requests. |
| E3.8 | Replay echoes request idempotency key, not stored one | medium | SQL returns only `stored_operation_id`; `_ack` echoes request key. |
| E3.9 | Resolver 429 has no Category 14 audit | high | Early return before `_audit`. |
| E3.10 | Resolver throttle is global, not per identifier | medium | Single `_resolverCalls` queue; identifier not hashed. |
| E3.11 | Invalid reference yields no audit | medium | 403 before `_audit` or attempt increment. |
| E3.12 | Delivery-failure DELETE errors swallowed | medium | `_removeChallenge` catch leaves orphan challenge consuming rate budget. |
| BH3.1 | Migration 003 never applied by production code | high | `registeredMigrations` referenced only by tests; no production apply call. |
| BH3.2 | pgTAP actor assertion uses obsolete fixed UUID | high | T-CR-12 expects `000...001`; SQL derives md5-per-tenant UUID. |
| BH3.3 | Synthetic actor row unverified and never cleaned | high | No role-enum check; 003 down does not remove inserted rows. |
| BH3.4 | Failed verification double Category 14 | medium | Server `_verify` and client `confirm` both append the same action. |
| BH3.5 | Process-local server state (duplicate of E3.4) | high | See E3.4. |
| BH3.6 | Rate-limit paths un-audited (duplicate of E3.9) | high | See E3.9. |
| BH3.7 | Mixed-case username (duplicate of E3.3) | medium | See E3.3. |
| BH3.8 | Client reads unused `otp_hash` | medium | SELECT at :1799; verification delegated to server; widens exposure. |
| BH3.9 | Contradictory DELETE-grant contract | high | One test forbids DELETE, another requires it; SQL grants it to `cs_app`. |
| BH3.10 | Server tests omit replay/delivery-failure/collision cases | medium | `status='existing'` never mocked; provider always 200; no match_count=2 case. |
| BH3.11 | No cross-tenant confirm test; no active recheck at reset | medium | Confirm relies only on `cs_resolve_recovery_challenge`; no active-status guard. |
| VG3.1 | Ambiguous cross-tenant identifier untested at server consumer | high | Pre-verified: mock always returns `match_count=1`; no assert on audit/no-reference. |
| VG3.2 | Delivery-failure cleanup untested | medium | Pre-verified: provider mock always 200; `execute` is a no-op. |
| VG3.3 | pgTAP duplicate-email insert uses bare `NOW` | high | SQLSTATE 23505 assertion cannot pass as written. |
| VG3.4 | Mixed-case username (duplicate of E3.3) | medium | See E3.3. |

Pass-3 routing: **bad_spec** entries (E3.4, BH3.1, BH3.3, BH3.6, BH3.9 + duplicates) trigger loopback 3; patch/defer entries are moot until the spec is amended.

### Review pass 4 (after loopback 3 re-derivation)

| # | Finding | Verdict | Evidence |
|---|---|---|---|
| BH4.1 | `/verify` has no attempt increment or Category 14; controls exist only in Dart client | high | Direct `/verify` callers get unlimited guesses; loopback 3 required one Category 14 per failure. |
| BH4.2 | `/deliver` and `/verify` have no bearer check despite comments/tests | high | `_handle` performs no auth; gateway never sends bearer. |
| BH4.3 | Vacuous DELETE-grant assertion persists | high | `contains('GRANT DELETE')` cannot observe combined grant; opposing invariants remain. |
| BH4.4 | Cross-tenant confirm still untested | medium | No test drives a foreign `shop_id` from `cs_resolve_recovery_challenge`. |
| BH4.5 | `deliveryReference` validated then ignored; not a signed reference | high | Confirm posts `reference: operationId`; dialog stores operation id as reference. |
| BH4.6 | Redundant `deliver` acknowledgement call adds a failure path | low | `/deliver` only acknowledges; failure swallowed. |
| BH4.7 | Abuse auditing skipped when `CS_RECOVERY_ABUSE_SHOP_ID` unset; cross-tenant when set | high | `_auditAbuse` returns early; otherwise writes to a real tenant. |
| BH4.8 | Client startup applies privileged DDL on every launch | high | `main()` calls `applyServerMigrationsIfConfigured()`; BYPASSRLS role + constraints; races/startup failure. |
| BH4.9 | v29 comment contradicts fail-closed code | low | Comment describes nulling contacts; code throws. |
| BH4.10 | SQL duplicated in Dart and `.sql`; parity test is sole guard | medium | Two sources of truth for security-critical DDL. |
| BH4.11 | pgTAP fixtures use `counter_staff` role while others use `cashier` | high | CI-gated `.tap` may fail at fixture insert. |
| BH4.12 | Blank contact strings collide under unique constraints | high | `signup_screen` passes `''`; SQL NULL assumption wrong. |
| BH4.13 | No pre-reset-token session-revocation test | medium | Only `session_version` increment asserted. |
| EC4.1 | Mixed-case username fails on SMS channel | medium | Only email channel lowercases input. |
| EC4.2 | Real user with synthetic actor username breaks audit FK | medium | `ON CONFLICT (id)` does not guard `(shop_id, username)`. |
| EC4.3 | Replay echoes caller key, not stored key (claim) | high | Guard snippet returns stored key — claim not established at cited lines; verify before routing. |
| EC4.4 | Abuse un-audited in default deployment (claim, duplicate BH4.7) | high | See BH4.7. |
| EC4.5 | DELETE grant vacuous assertion (claim, duplicate BH4.3) | high | See BH4.3. |
| EC4.6 | Cross-tenant confirm untested (claim, duplicate BH4.4) | medium | See BH4.4. |
| EC4.7 | `/deliver` contract differs from spec (claim) | medium | OTP generated in `/request`, `/deliver` acknowledges — design deviation, not necessarily defect. |
| VG4.1 | Four SQL functions/branches never executed by real-SQL test | high | Pre-verified: `.tap` plans 13, none call finalize/load/resolve/replay; mocks bypass SQL. |
| VG4.2 | Vacuous DELETE assertion (duplicate BH4.3) | high | See BH4.3. |

Pass-4 routing: **bad_spec** entries (BH4.1, BH4.2, BH4.5, BH4.7, BH4.8, BH4.11, BH4.12 + duplicates) remain unresolved. Escalation to human is required rather than a fourth mechanical loopback.

## Verification

**Commands:**
- `flutter analyze` -- expected: zero issues
- `flutter test test/unit/features/auth/ test/unit/core/data/remote/ test/unit/core/data/local/database_connection_test.dart` -- expected: all pass
- `flutter test test/widget/features/auth/` -- expected: all pass
- `flutter test test/integration/` -- expected: pass or skip cleanly when `DATABASE_URL` is unset
