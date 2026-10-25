#!/usr/bin/env bash
# Story 1.4: Disaster Recovery drill harness
set -euo pipefail

: "${PG_RESTORE_BIN:=pg_restore}"
: "${PSQL_BIN:=psql}"
: "${BACKUP_FILE:?BACKUP_FILE (base snapshot) is required}"
: "${TARGET_TS:?TARGET_TS (ISO timestamp) is required}"
: "${RECOVERY_DB_URL:?RECOVERY_DB_URL is required}"
: "${MODE:=self-hosted}"  # self-hosted | managed
: "${RTO_LIMIT_SECONDS:=14400}"  # 4 hours

START=$(date +%s)

echo "=== DR Drill: restoring base snapshot ==="
"$PG_RESTORE_BIN" --dbname="$RECOVERY_DB_URL" --clean --if-exists "$BACKUP_FILE"

echo "=== DR Drill: replaying WAL to $TARGET_TS (mode=$MODE) ==="
if [ "$MODE" = "self-hosted" ]; then
  echo "Self-hosted: create recovery.signal and set recovery_target_time='$TARGET_TS' in postgresql.auto.conf, then restart."
elif [ "$MODE" = "managed" ]; then
  echo "Managed: trigger provider PITR API to target timestamp $TARGET_TS."
else
  echo "Unknown MODE: $MODE"; exit 1
fi

echo "=== DR Drill: verifying ledger integrity ==="
"$PSQL_BIN" "$RECOVERY_DB_URL" -v ON_ERROR_STOP=1 <<'SQL'
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM loans l
    WHERE l.principal - COALESCE((SELECT SUM(amount) FROM payments p WHERE p.loan_id = l.id), 0)
          + COALESCE((SELECT SUM(amount) FROM reversals r WHERE r.loan_id = l.id), 0)
          <> l.balance
  ) THEN
    RAISE EXCEPTION 'ledger integrity check FAILED';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM audit_events) THEN
    RAISE EXCEPTION 'audit continuity check FAILED: no audit events found';
  END IF;
END $$;
SQL

END=$(date +%s)
ELAPSED=$((END - START))
echo "=== DR Drill complete in ${ELAPSED}s ==="
echo "RTO (seconds): ${ELAPSED}"
echo "RPO: verify against WAL archive granularity (target <= 15 min)."

if [ "$ELAPSED" -gt "$RTO_LIMIT_SECONDS" ]; then
  echo "RTO check FAILED: ${ELAPSED}s exceeds limit of ${RTO_LIMIT_SECONDS}s"
  exit 1
fi
echo "RTO check PASSED: ${ELAPSED}s <= ${RTO_LIMIT_SECONDS}s"