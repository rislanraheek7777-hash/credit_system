# Credential Recovery Backend

Standalone, least-privilege authority for staff credential recovery. The
Flutter client only calls its two application routes over HTTPS.

## Quick start

```bash
cd backend
dart pub get
cp .env.example .env            # fill in real secrets
set -a && . ./.env && set +a
dart run bin/server.dart
```

Never commit secrets. Every secret and connection setting is read from OS
environment variables via `Platform.environment`; the service refuses to start
when a required value is missing or invalid.

## Environment variables

| Variable | Required | Purpose |
|---|---|---|
| `DATABASE_URL` | yes | Least-privilege PostgreSQL role (`cs_app`), no `BYPASSRLS`, no DDL at runtime |
| `CS_RECOVERY_OTP_PEPPER` | yes | Server-only pepper for OTP digests and reference HMAC |
| `CS_RECOVERY_ABUSE_SHOP_ID` | yes | UUID of the reserved platform shop that hosts un-attributable Category 14 events; must exist in `public.shops` |
| `CS_RECOVERY_SMTP_HOST` | yes | SMTP host; TLS is mandatory |
| `CS_RECOVERY_SMTP_PORT` | no | SMTP port, 1–65535 (default `465`) |
| `CS_RECOVERY_SMTP_USER` / `CS_RECOVERY_SMTP_PASSWORD` | no | SMTP credentials when the provider requires auth |
| `CS_RECOVERY_EMAIL_FROM` | yes | Verified sender address |
| `CS_RECOVERY_SMTP_TLS` | yes | Must be literal `true`; any other value fails startup |
| `CS_RECOVERY_SMTP_HELO` | no | EHLO identity (default `localhost`) |
| `CS_RECOVERY_SMS_ENDPOINT` | yes | SMS provider URL |
| `CS_RECOVERY_SMS_SENDER` / `CS_RECOVERY_SMS_API_KEY` | no | Provider sender id and API key |
| `CS_RECOVERY_SERVER_HOST` | no | Listen host (default `127.0.0.1`) |
| `CS_RECOVERY_SERVER_PORT` | no | Listen port, 1–65535 (default `8081`) |
| `CS_RECOVERY_TLS_CERT_PATH` / `CS_RECOVERY_TLS_KEY_PATH` | non-loopback only | TLS certificate/key; a non-loopback bind without both fails startup |
| `CS_RECOVERY_MIGRATION_SQL_PATH` | no | Path used by `bin/migrate.dart` when `--path` is omitted |

Ports are parsed strictly: a non-integer or out-of-range value fails startup.

## Client build

The Flutter client receives only the public URL, never a secret:

```bash
flutter build apk \
  --dart-define=CS_RECOVERY_SERVER_URL=https://recovery.example.internal/
```

CI asserts that this dart-define is supplied for release builds and exercises
the resulting gateway wiring.

## Routes

- `POST /request` — uniform acknowledgement `{storedOperationId, storedIdempotencyKey}` on every outcome.
- `POST /verify` — generic failure, or minimal trusted context on success:
  `userId`, `shopId`, `username`, `role`, `sessionVersion`.
- `GET /health` — liveness (`{"status":"ok"}`).
- `GET /ready` — readiness; `200` when the database answers, `503` otherwise.

`GET` on application routes and `POST` on health routes return `405` with an
`Allow` header. Requests are capped at 16 KiB before JSON decoding.

## Deployment constraints

- Throttles are **process-local** sliding windows. Run a **single backend
  instance**, or place a shared rate limiter in front of multiple instances.
  Limits reset on restart.
- Use HTTPS (reverse proxy or the built-in TLS listener). SMTP always uses TLS.
- SMTP and SMS can be enabled independently: leave the unused channel's
  variables unset. At least one must be configured at startup.
- `SIGTERM`/`SIGINT` closes the listener and the database pool gracefully.
- The service never issues DDL at startup.

## Migration and cleanup

Apply migration 003 explicitly before starting the service:

```bash
dart run bin/migrate.dart --path ../lib/core/data/remote/migrations/003_credential_recovery.sql
```

The apply is idempotent through `schema_migrations` and fails closed on a
checksum mismatch. `003_credential_recovery_down.sql` removes its own
`schema_migrations` row so a re-apply works after rollback.

Retention policy: challenge rows and their operation-ledger rows contain
contact metadata. Purge rows whose `expires_at` is older than 30 days (adjust
to your policy) on a schedule, respecting the append-only audit trail:

```sql
-- Run as a privileged role, or set the tenant context per shop with
-- SELECT pg_catalog.set_config('app.current_shop_id', '<shop-uuid>', true);
-- because both tables have FORCE ROW LEVEL SECURITY.
DELETE FROM public.credential_recovery_operations
 WHERE created_at < NOW() - INTERVAL '30 days';
DELETE FROM public.credential_recovery_challenges
 WHERE expires_at < NOW() - INTERVAL '30 days';
```

Audit events are immutable and are never deleted by this policy.

## Tests

```bash
dart analyze
dart test
```
