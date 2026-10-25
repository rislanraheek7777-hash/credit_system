#!/usr/bin/env bash
set -euo pipefail

DB_PATH="${DB_PATH:-build/credit_system.db}"
BACKUP_DIR="${BACKUP_DIR:-build/backups}"
RESTORE_PATH="${RESTORE_PATH:-/tmp/credit_system_restore.db}"
RTO_LIMIT_SECONDS="${RTO_LIMIT_SECONDS:-300}"

if [[ ! -f "$DB_PATH" ]]; then
  echo "ERROR: DB not found at $DB_PATH"
  exit 1
fi

mkdir -p "$BACKUP_DIR"
START=$(date +%s)

# Backup
cp "$DB_PATH" "$BACKUP_DIR/credit_system_$(date +%Y%m%d_%H%M%S).db"

# Restore
cp "$DB_PATH" "$RESTORE_PATH"

# Integrity check
if command -v sqlite3 >/dev/null 2>&1; then
  RESULT=$(sqlite3 "$RESTORE_PATH" "PRAGMA integrity_check;")
  if [[ "$RESULT" != "ok" ]]; then
    echo "ERROR: integrity check failed: $RESULT"
    exit 1
  fi
fi

END=$(date +%s)
ELAPSED=$((END-START))
echo "SQLite DR drill OK in ${ELAPSED}s"

if [[ "$ELAPSED" -gt "$RTO_LIMIT_SECONDS" ]]; then
  echo "ERROR: RTO exceeded (${ELAPSED}s > ${RTO_LIMIT_SECONDS}s)"
  exit 1
fi
