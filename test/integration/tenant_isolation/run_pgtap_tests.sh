#!/usr/bin/env bash
# =============================================================================
# run_pgtap_tests.sh
# CI harness for Story 1.3 pgTAP integration tests.
#
# Behaviour
# ──────────
# LOCAL (DATABASE_URL not set):
#   Prints a clear SKIP message and exits 0.
#
# CI (DATABASE_URL set, dedicated PostgreSQL 16+ service):
#   Fails immediately (non-zero exit) if:
#     • DATABASE_URL is set but psql cannot connect.
#     • PostgreSQL version is < 16.
#     • pgTAP extension is not available.
#     • Any migration fails to apply.
#     • Any .tap test file returns a failing result.
#     • Role cleanup fails (preserves test failure code if tests failed).
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAP_DIR="${TAP_DIR:-$SCRIPT_DIR}"
PGPROVE="${PGPROVE:-pg_prove}"
PG_MIN_VERSION="${PG_MIN_VERSION:-16}"

# ─────────────────────────────────────────────────────────────────────────────
# Local Skip Guard
# ─────────────────────────────────────────────────────────────────────────────
if [[ -z "${DATABASE_URL:-}" ]]; then
    echo ""
    echo "=========================================================="
    echo " SKIP: PostgreSQL integration tests (Story 1.3 / pgTAP)"
    echo " Reason: DATABASE_URL environment variable is not set."
    echo " To run locally, set DATABASE_URL and re-execute:"
    echo "   export DATABASE_URL=postgres://user:pass@localhost/dbname"
    echo "   bash $(basename "${BASH_SOURCE[0]}")"
    echo "=========================================================="
    echo ""
    exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Cleanup & Exit Trapping Architecture
# ─────────────────────────────────────────────────────────────────────────────
ORIGINAL_TEST_EXIT=0
CLEANUP_FAILED=0
MEMBERSHIPS_ADDED=()

cleanup_test_roles() {
    echo "" >&2
    echo "Executing test harness role cleanup..." >&2

    for grant in "${MEMBERSHIPS_ADDED[@]:-}"; do
        [ -z "$grant" ] && continue
        local role="${grant%%:*}"
        local member="${grant##*:}"
        echo "Revoking temporary grant: $role FROM $member" >&2
        if ! psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "REVOKE $role FROM $member;" >&2; then
            echo "ERROR: Failed to revoke $role from $member during test cleanup!" >&2
            CLEANUP_FAILED=1
        fi
    done

    # Failure preservation rule:
    if [ "$ORIGINAL_TEST_EXIT" -ne 0 ]; then
        echo "Harness exiting with original test failure code: $ORIGINAL_TEST_EXIT" >&2
        exit "$ORIGINAL_TEST_EXIT"
    elif [ "$CLEANUP_FAILED" -ne 0 ]; then
        echo "Harness exiting with cleanup failure code: 1" >&2
        exit 1
    fi
}

trap 'ORIGINAL_TEST_EXIT=$?; cleanup_test_roles' EXIT

# ─────────────────────────────────────────────────────────────────────────────
# CI Prerequisites & Connectivity Guard
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=========================================================="
echo " PostgreSQL Integration Tests (Story 1.3 / pgTAP)"
echo " DATABASE_URL is set — running in CI mode."
echo "=========================================================="
echo ""

if ! command -v psql &>/dev/null; then
    echo "ERROR: psql not found in PATH." >&2
    exit 1
fi

echo "[1/5] Verifying database connectivity..."
if ! psql "$DATABASE_URL" -c "SELECT 1;" >/dev/null 2>&1; then
    echo "ERROR: Cannot connect to database at DATABASE_URL." >&2
    exit 1
fi
echo "      Connection: OK"

echo "[2/5] Verifying PostgreSQL version >= ${PG_MIN_VERSION}..."
PG_VERSION_NUM=$(psql "$DATABASE_URL" -t -A -c "SHOW server_version_num;" 2>/dev/null)
PG_MAJOR_VERSION=$(echo "$PG_VERSION_NUM" | cut -c1-2)

if [[ -z "$PG_VERSION_NUM" ]] || [[ "$PG_MAJOR_VERSION" -lt "$PG_MIN_VERSION" ]]; then
    echo "ERROR: PostgreSQL version ${PG_MAJOR_VERSION} is below required ${PG_MIN_VERSION}." >&2
    exit 1
fi
echo "      PostgreSQL server_version_num = ${PG_VERSION_NUM}: OK"

echo "[3/5] Verifying pgTAP availability..."
PGTAP_AVAILABLE=$(psql "$DATABASE_URL" -t -A -c \
    "SELECT COUNT(*) FROM pg_available_extensions WHERE name = 'pgtap';" 2>/dev/null)

if [[ "$PGTAP_AVAILABLE" != "1" ]]; then
    echo "ERROR: pgTAP extension is not available in PostgreSQL instance." >&2
    exit 1
fi
echo "      pgTAP extension: available"

echo "[4/5] Verifying pg_prove availability..."
if ! command -v "$PGPROVE" &>/dev/null; then
    echo "ERROR: pg_prove not found at '${PGPROVE}'." >&2
    exit 1
fi
echo "      pg_prove: $(command -v "$PGPROVE")"

# ─────────────────────────────────────────────────────────────────────────────
# Apply Migrations (Fail-fast: errors are NOT suppressed)
# ─────────────────────────────────────────────────────────────────────────────
MIGRATION_DIR="$(cd "$SCRIPT_DIR/../../../lib/core/data/remote/migrations" 2>/dev/null && pwd || true)"
if [[ -n "$MIGRATION_DIR" && -f "$MIGRATION_DIR/001_initial_schema.sql" ]]; then
    echo "Applying migrations against test database..."
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$MIGRATION_DIR/001_initial_schema.sql"
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$MIGRATION_DIR/002_rls_roles_audit.sql"
    # Use the same idempotent CLI as operators so schema_migrations is recorded
    # and an operator/CI re-run cannot apply 003 twice.
    (
      cd "$SCRIPT_DIR/../../../backend" || exit 1
      dart pub get >/dev/null
      dart run bin/migrate.dart --path "$MIGRATION_DIR/003_credential_recovery.sql"
    )
    echo "Migrations applied successfully."
    echo ""
fi

# ─────────────────────────────────────────────────────────────────────────────
# Test Role Grant Check & Least-Privileged Runner Tracking
# ─────────────────────────────────────────────────────────────────────────────
CURRENT_RUNNER=$(psql "$DATABASE_URL" -t -A -c "SELECT current_user;" 2>/dev/null)

check_direct_membership() {
    local role="$1"
    local member="$2"
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -t -A -c "
        SELECT count(*) 
        FROM pg_catalog.pg_auth_members m
        JOIN pg_catalog.pg_roles r ON r.oid = m.roleid
        JOIN pg_catalog.pg_roles mb ON mb.oid = m.member
        WHERE r.rolname = '$role' AND mb.rolname = '$member';
    "
}

grant_if_missing() {
    local role="$1"
    local member="$2"
    local count
    count=$(check_direct_membership "$role" "$member")
    if [ "$count" -eq 0 ]; then
        echo "Granting temporary membership: $role TO $member"
        psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "GRANT $role TO $member;"
        MEMBERSHIPS_ADDED+=("$role:$member")
    else
        echo "Pre-existing membership confirmed: $role TO $member (will not revoke)"
    fi
}

grant_if_missing "cs_app" "$CURRENT_RUNNER"
grant_if_missing "cs_audit_writer" "$CURRENT_RUNNER"

# ─────────────────────────────────────────────────────────────────────────────
# Run Tests
# ─────────────────────────────────────────────────────────────────────────────
echo "[5/5] Running pgTAP tests in: ${TAP_DIR}"
echo ""

mapfile -t TAP_FILES < <(find "$TAP_DIR" -name "*.tap" | sort)

if [[ ${#TAP_FILES[@]} -eq 0 ]]; then
    echo "ERROR: No .tap files found in ${TAP_DIR}." >&2
    exit 1
fi

"$PGPROVE" \
    --dbname "$DATABASE_URL" \
    --failures \
    "${TAP_FILES[@]}"

PROVE_EXIT=$?

echo ""
if [[ $PROVE_EXIT -eq 0 ]]; then
    echo "=========================================================="
    echo " ALL pgTAP tests PASSED (Story 1.3)"
    echo "=========================================================="
else
    echo "=========================================================="
    echo " FAILURE: One or more pgTAP tests FAILED (Story 1.3)"
    echo "=========================================================="
fi
echo ""

exit $PROVE_EXIT
