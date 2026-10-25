# Disaster Recovery Runbook

## Prerequisites
- PostgreSQL 16+ with WAL archiving enabled (`archive_mode=on`).
- Backup storage (S3/R2) with object versioning + SSE.
- `pg_restore`, `psql`, `aws` CLI available.

## Environment variables
- `BACKUP_FILE`: path to base dump
- `TARGET_TS`: RFC3339 timestamp for PITR
- `RECOVERY_DB_URL`: connection string for recovery instance
- `MODE`: `managed` or `local`
- `RTO_LIMIT_SECONDS`: default 14400 (4h)

## Run drill
```bash
BACKUP_FILE=/path/to/base.dump \
TARGET_TS="2026-10-25T12:00:00Z" \
RECOVERY_DB_URL="postgresql://user:pass@host:5432/recovery" \
MODE=managed \
RTO_LIMIT_SECONDS=14400 \
bash scripts/dr_drill.sh
```

## Verification
- Script exits 0 on success.
- Ledger/audit integrity checks pass.
- RTO within limit.

## After drill
- Update sprint status 1.4 and 7.5 to done.
- Update DR compliance to VERIFIED.
