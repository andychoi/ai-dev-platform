#!/usr/bin/env bash
# =============================================================================
# DevDB Admin Management Tool
# Manage developer databases: list, inspect, cleanup orphans, delete
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
DEVDB_HOST="${DEVDB_HOST:-devdb}"
DEVDB_PORT="${DEVDB_PORT:-5432}"
DEVDB_ADMIN_USER="${DEVDB_ADMIN_USER:-devdb_admin}"
DEVDB_ADMIN_DB="${DEVDB_ADMIN_DB:-devdb}"
CODER_URL="${CODER_URL:-http://localhost:7080}"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_header() { echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"; }

# Run SQL on DevDB
run_sql() {
    docker exec devdb psql -U "$DEVDB_ADMIN_USER" -d "$DEVDB_ADMIN_DB" -t -A -c "$1" 2>/dev/null
}

run_sql_formatted() {
    docker exec devdb psql -U "$DEVDB_ADMIN_USER" -d "$DEVDB_ADMIN_DB" -c "$1" 2>/dev/null
}

usage() {
    echo "DevDB Admin Management Tool"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  list                    List all provisioned databases"
    echo "  summary                 Show database summary by type"
    echo "  inspect <db_name>       Show detailed info for a database"
    echo "  users                   List all database users"
    echo "  orphans                 Find orphaned databases (no active workspace)"
    echo "  cleanup [--dry-run]     Remove orphaned databases"
    echo "  delete <db_name>        Delete a specific database"
    echo "  size                    Show database sizes"
    echo "  connections             Show active connections"
    echo "  create-team <name>      Create a new team database"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 orphans"
    echo "  $0 cleanup --dry-run"
    echo "  $0 delete dev_olduser"
    echo "  $0 create-team frontend-project"
    exit 1
}

# Check if DevDB is accessible
check_devdb() {
    if ! docker exec devdb pg_isready -U "$DEVDB_ADMIN_USER" -d "$DEVDB_ADMIN_DB" > /dev/null 2>&1; then
        log_error "DevDB is not accessible. Is the container running?"
        exit 1
    fi
}

# List all databases
cmd_list() {
    log_header "All Provisioned Databases"
    run_sql_formatted "
        SELECT
            db_name AS \"Database\",
            db_type AS \"Type\",
            owner_username AS \"Owner\",
            template_name AS \"Template\",
            created_at::date AS \"Created\",
            last_accessed::date AS \"Last Access\"
        FROM provisioning.databases
        ORDER BY db_type, created_at DESC;
    "
}

# Show summary
cmd_summary() {
    log_header "Database Summary"
    run_sql_formatted "SELECT * FROM provisioning.database_summary;"

    echo ""
    log_info "PostgreSQL Statistics:"
    run_sql_formatted "
        SELECT
            datname AS \"Database\",
            pg_size_pretty(pg_database_size(datname)) AS \"Size\",
            numbackends AS \"Connections\"
        FROM pg_stat_database
        WHERE datname LIKE 'dev_%' OR datname LIKE 'team_%'
        ORDER BY pg_database_size(datname) DESC;
    "
}

# Inspect a database
cmd_inspect() {
    local db_name="$1"
    [ -z "$db_name" ] && { log_error "Database name required"; exit 1; }

    log_header "Database: $db_name"

    # Metadata
    log_info "Metadata:"
    run_sql_formatted "
        SELECT * FROM provisioning.databases WHERE db_name = '$db_name';
    "

    # Users with access
    echo ""
    log_info "Users with access:"
    run_sql_formatted "
        SELECT username, access_level, created_at::date
        FROM provisioning.db_users
        WHERE db_name = '$db_name';
    "

    # Size and stats
    echo ""
    log_info "Size and statistics:"
    run_sql_formatted "
        SELECT
            pg_size_pretty(pg_database_size('$db_name')) AS size,
            (SELECT count(*) FROM pg_stat_activity WHERE datname = '$db_name') AS active_connections;
    "
}

# List users
cmd_users() {
    log_header "Database Users"
    run_sql_formatted "
        SELECT
            u.username AS \"User\",
            u.db_name AS \"Database\",
            u.access_level AS \"Access\",
            d.db_type AS \"DB Type\",
            u.created_at::date AS \"Granted\"
        FROM provisioning.db_users u
        JOIN provisioning.databases d ON u.db_name = d.db_name
        ORDER BY u.username, u.db_name;
    "
}

# Find orphaned databases
cmd_orphans() {
    log_header "Checking for Orphaned Databases"

    # Get Coder token for API access
    log_info "Fetching active workspaces from Coder..."

    local token
    token=$(curl -s -X POST "${CODER_URL}/api/v2/users/login" \
        -H "Content-Type: application/json" \
        -d @- <<'EOF' | jq -r '.session_token // empty'
{
    "email": "admin@example.com",
    "password": "CoderAdmin123!"
}
EOF
    )

    if [ -z "$token" ]; then
        log_warn "Could not authenticate with Coder API. Showing all individual databases."
        log_info "Manual verification required."
        run_sql_formatted "
            SELECT db_name, owner_username, workspace_id, last_accessed::date
            FROM provisioning.databases
            WHERE db_type = 'individual'
            ORDER BY last_accessed;
        "
        return
    fi

    # Get active workspace IDs
    local active_workspaces
    active_workspaces=$(curl -s "${CODER_URL}/api/v2/workspaces" \
        -H "Coder-Session-Token: $token" | jq -r '.[].id' 2>/dev/null | tr '\n' ',' | sed 's/,$//')

    if [ -z "$active_workspaces" ]; then
        log_info "No active workspaces found."
        active_workspaces="'none'"
    else
        active_workspaces=$(echo "$active_workspaces" | sed "s/,/','/g" | sed "s/^/'/" | sed "s/$/'/")
    fi

    # Find orphaned databases
    echo ""
    log_info "Orphaned databases (no active workspace):"
    run_sql_formatted "
        SELECT
            db_name AS \"Database\",
            owner_username AS \"Owner\",
            workspace_id AS \"Workspace ID\",
            created_at::date AS \"Created\",
            last_accessed::date AS \"Last Access\",
            CASE
                WHEN workspace_id IS NULL THEN 'No workspace ID'
                ELSE 'Workspace deleted'
            END AS \"Status\"
        FROM provisioning.databases
        WHERE db_type = 'individual'
          AND (workspace_id IS NULL OR workspace_id NOT IN ($active_workspaces))
        ORDER BY last_accessed;
    "

    # Also show databases not accessed recently
    echo ""
    log_info "Stale databases (not accessed in 30+ days):"
    run_sql_formatted "
        SELECT
            db_name AS \"Database\",
            db_type AS \"Type\",
            owner_username AS \"Owner\",
            last_accessed::date AS \"Last Access\",
            NOW()::date - last_accessed::date AS \"Days Inactive\"
        FROM provisioning.databases
        WHERE last_accessed < NOW() - INTERVAL '30 days'
        ORDER BY last_accessed;
    "
}

# Cleanup orphaned databases
cmd_cleanup() {
    local dry_run=false
    [ "$1" = "--dry-run" ] && dry_run=true

    log_header "Database Cleanup"

    if $dry_run; then
        log_warn "DRY RUN - No changes will be made"
    fi

    # Get orphaned database names
    local orphans
    orphans=$(run_sql "
        SELECT db_name FROM provisioning.databases
        WHERE db_type = 'individual'
          AND last_accessed < NOW() - INTERVAL '90 days';
    ")

    if [ -z "$orphans" ]; then
        log_success "No orphaned databases found (>90 days inactive)"
        return
    fi

    echo ""
    log_warn "Databases to be removed:"
    echo "$orphans" | while read -r db; do
        echo "  - $db"
    done

    if $dry_run; then
        echo ""
        log_info "Run without --dry-run to actually delete these databases"
        return
    fi

    echo ""
    read -p "Are you sure you want to delete these databases? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "Cancelled"
        return
    fi

    # Delete each database
    echo "$orphans" | while read -r db; do
        if [ -n "$db" ]; then
            log_info "Deleting: $db"
            delete_database "$db"
        fi
    done

    log_success "Cleanup complete"
}

# Delete a specific database
delete_database() {
    local db_name="$1"

    # Terminate connections
    run_sql "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$db_name';" > /dev/null 2>&1 || true

    # Drop database
    docker exec devdb psql -U "$DEVDB_ADMIN_USER" -d postgres -c "DROP DATABASE IF EXISTS \"$db_name\";" 2>/dev/null

    # Drop user
    docker exec devdb psql -U "$DEVDB_ADMIN_USER" -d postgres -c "DROP USER IF EXISTS \"$db_name\";" 2>/dev/null || true

    # Remove from provisioning
    run_sql "DELETE FROM provisioning.db_users WHERE db_name = '$db_name';"
    run_sql "DELETE FROM provisioning.databases WHERE db_name = '$db_name';"

    log_success "Deleted: $db_name"
}

cmd_delete() {
    local db_name="$1"
    [ -z "$db_name" ] && { log_error "Database name required"; exit 1; }

    log_header "Delete Database: $db_name"

    # Check if exists
    local exists
    exists=$(run_sql "SELECT 1 FROM provisioning.databases WHERE db_name = '$db_name';")
    if [ -z "$exists" ]; then
        log_error "Database not found: $db_name"
        exit 1
    fi

    # Show info
    run_sql_formatted "SELECT * FROM provisioning.databases WHERE db_name = '$db_name';"

    echo ""
    read -p "Are you sure you want to delete this database? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "Cancelled"
        return
    fi

    delete_database "$db_name"
}

# Show database sizes
cmd_size() {
    log_header "Database Sizes"
    run_sql_formatted "
        SELECT
            datname AS \"Database\",
            pg_size_pretty(pg_database_size(datname)) AS \"Size\",
            pg_database_size(datname) AS \"Bytes\"
        FROM pg_database
        WHERE datname LIKE 'dev_%' OR datname LIKE 'team_%'
        ORDER BY pg_database_size(datname) DESC;
    "

    echo ""
    log_info "Total size:"
    run_sql_formatted "
        SELECT pg_size_pretty(SUM(pg_database_size(datname))) AS \"Total\"
        FROM pg_database
        WHERE datname LIKE 'dev_%' OR datname LIKE 'team_%';
    "
}

# Show active connections
cmd_connections() {
    log_header "Active Connections"
    run_sql_formatted "
        SELECT
            datname AS \"Database\",
            usename AS \"User\",
            client_addr AS \"Client\",
            state AS \"State\",
            query_start::timestamp(0) AS \"Started\"
        FROM pg_stat_activity
        WHERE datname LIKE 'dev_%' OR datname LIKE 'team_%'
        ORDER BY datname, query_start;
    "
}

# Create team database
cmd_create_team() {
    local team_name="$1"
    [ -z "$team_name" ] && { log_error "Team name required"; exit 1; }

    log_header "Create Team Database: $team_name"

    run_sql_formatted "SELECT * FROM provisioning.create_team_db('$team_name');"

    log_success "Team database created: team_$team_name"
}

# Main
check_devdb

case "${1:-}" in
    list)           cmd_list ;;
    summary)        cmd_summary ;;
    inspect)        cmd_inspect "$2" ;;
    users)          cmd_users ;;
    orphans)        cmd_orphans ;;
    cleanup)        cmd_cleanup "$2" ;;
    delete)         cmd_delete "$2" ;;
    size)           cmd_size ;;
    connections)    cmd_connections ;;
    create-team)    cmd_create_team "$2" ;;
    *)              usage ;;
esac
