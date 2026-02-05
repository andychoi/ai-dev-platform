#!/usr/bin/env bash
# =============================================================================
# Database Provisioning Script
# Called from workspace startup to provision individual or team databases
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
DEVDB_HOST="${DEVDB_HOST:-devdb}"
DEVDB_PORT="${DEVDB_PORT:-5432}"
DEVDB_ADMIN_USER="${DEVDB_ADMIN_USER:-workspace_provisioner}"
DEVDB_ADMIN_PASSWORD="${DEVDB_ADMIN_PASSWORD:-provisioner123}"

log_info() { echo -e "${BLUE}[DB]${NC} $1"; }
log_success() { echo -e "${GREEN}[DB]${NC} $1"; }
log_error() { echo -e "${RED}[DB]${NC} $1"; }

# =============================================================================
# SECURITY: Input validation to prevent SQL injection
# =============================================================================

# Validate identifier (username, db_name) - alphanumeric and underscore only
validate_identifier() {
    local value="$1"
    local field_name="$2"

    # Check not empty
    if [ -z "$value" ]; then
        log_error "$field_name cannot be empty"
        return 1
    fi

    # Check length (max 63 chars for PostgreSQL identifiers)
    if [ ${#value} -gt 63 ]; then
        log_error "$field_name too long (max 63 characters)"
        return 1
    fi

    # Check for valid characters only (alphanumeric, underscore, hyphen)
    if ! echo "$value" | grep -qE '^[a-zA-Z][a-zA-Z0-9_-]*$'; then
        log_error "$field_name contains invalid characters (must start with letter, contain only alphanumeric, underscore, hyphen)"
        return 1
    fi

    # Check for SQL injection patterns
    if echo "$value" | grep -qiE "(drop|delete|insert|update|select|union|;|'|\"|--)" ; then
        log_error "$field_name contains disallowed SQL keywords"
        return 1
    fi

    return 0
}

# Escape single quotes for SQL (defensive, after validation)
escape_sql() {
    echo "$1" | sed "s/'/''/g"
}

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  individual <username> [workspace_id]  - Create/connect to individual database"
    echo "  team <template_name> [owner]          - Create/connect to team database"
    echo "  list <username>                       - List databases for user"
    echo "  info <db_name>                        - Get connection info for database"
    echo ""
    echo "Environment Variables:"
    echo "  DEVDB_HOST      - DevDB host (default: devdb)"
    echo "  DEVDB_PORT      - DevDB port (default: 5432)"
    echo "  DB_OUTPUT_FILE  - Write connection info to file"
    echo ""
    echo "Examples:"
    echo "  $0 individual contractor1 ws-abc123"
    echo "  $0 team frontend-project"
    echo "  $0 list contractor1"
    exit 1
}

# Check if psql is available
check_psql() {
    if ! command -v psql &> /dev/null; then
        log_error "psql is not installed. Install postgresql-client."
        exit 1
    fi
}

# Execute SQL and return result
run_sql() {
    local sql="$1"
    PGPASSWORD="$DEVDB_ADMIN_PASSWORD" psql -h "$DEVDB_HOST" -p "$DEVDB_PORT" \
        -U "$DEVDB_ADMIN_USER" -d devdb -t -A -c "$sql" 2>/dev/null
}

# Create individual database
create_individual() {
    local username="$1"
    local workspace_id="${2:-}"

    # SECURITY: Validate inputs before SQL execution
    validate_identifier "$username" "username" || exit 1
    if [ -n "$workspace_id" ]; then
        validate_identifier "$workspace_id" "workspace_id" || exit 1
    fi

    # Escape for safety (belt and suspenders after validation)
    local safe_username=$(escape_sql "$username")
    local safe_workspace_id=$(escape_sql "$workspace_id")

    log_info "Provisioning individual database for: $username"

    local result
    if [ -n "$workspace_id" ]; then
        result=$(run_sql "SELECT * FROM provisioning.create_individual_db('$safe_username', '$safe_workspace_id');")
    else
        result=$(run_sql "SELECT * FROM provisioning.create_individual_db('$safe_username');")
    fi

    if [ -z "$result" ]; then
        log_error "Failed to provision database"
        exit 1
    fi

    # Parse result (db_name|db_user|db_password)
    local db_name=$(echo "$result" | cut -d'|' -f1)
    local db_user=$(echo "$result" | cut -d'|' -f2)
    local db_password=$(echo "$result" | cut -d'|' -f3)

    log_success "Database provisioned: $db_name"

    # Output connection info
    echo ""
    echo "=== Database Connection Info ==="
    echo "Host:     $DEVDB_HOST"
    echo "Port:     $DEVDB_PORT"
    echo "Database: $db_name"
    echo "User:     $db_user"
    if [ "$db_password" != "use_existing_password" ]; then
        echo "Password: $db_password"
        echo ""
        echo "Connection string:"
        echo "  postgresql://$db_user:$db_password@$DEVDB_HOST:$DEVDB_PORT/$db_name"
    else
        echo "Password: (existing - check your saved credentials)"
    fi
    echo ""

    # Write to file if requested
    if [ -n "$DB_OUTPUT_FILE" ]; then
        cat > "$DB_OUTPUT_FILE" <<EOF
DEVDB_HOST=$DEVDB_HOST
DEVDB_PORT=$DEVDB_PORT
DEVDB_NAME=$db_name
DEVDB_USER=$db_user
DEVDB_PASSWORD=$db_password
DEVDB_URL=postgresql://$db_user:$db_password@$DEVDB_HOST:$DEVDB_PORT/$db_name
EOF
        log_info "Connection info written to: $DB_OUTPUT_FILE"
    fi

    # Export as environment variables
    export DEVDB_NAME="$db_name"
    export DEVDB_USER="$db_user"
    export DEVDB_PASSWORD="$db_password"
    export DEVDB_URL="postgresql://$db_user:$db_password@$DEVDB_HOST:$DEVDB_PORT/$db_name"
}

# Create team database
create_team() {
    local template_name="$1"
    local owner="${2:-}"

    # SECURITY: Validate inputs before SQL execution
    validate_identifier "$template_name" "template_name" || exit 1
    if [ -n "$owner" ]; then
        validate_identifier "$owner" "owner" || exit 1
    fi

    # Escape for safety
    local safe_template=$(escape_sql "$template_name")
    local safe_owner=$(escape_sql "$owner")

    log_info "Provisioning team database for template: $template_name"

    local result
    if [ -n "$owner" ]; then
        result=$(run_sql "SELECT * FROM provisioning.create_team_db('$safe_template', '$safe_owner');")
    else
        result=$(run_sql "SELECT * FROM provisioning.create_team_db('$safe_template');")
    fi

    if [ -z "$result" ]; then
        log_error "Failed to provision team database"
        exit 1
    fi

    # Parse result
    local db_name=$(echo "$result" | cut -d'|' -f1)
    local db_user=$(echo "$result" | cut -d'|' -f2)
    local db_password=$(echo "$result" | cut -d'|' -f3)

    log_success "Team database provisioned: $db_name"

    echo ""
    echo "=== Team Database Connection Info ==="
    echo "Host:     $DEVDB_HOST"
    echo "Port:     $DEVDB_PORT"
    echo "Database: $db_name"
    echo "User:     $db_user"
    if [ "$db_password" != "use_existing_password" ]; then
        echo "Password: $db_password"
    fi
    echo ""
}

# List databases for user
list_databases() {
    local username="$1"

    # SECURITY: Validate input
    validate_identifier "$username" "username" || exit 1
    local safe_username=$(escape_sql "$username")

    log_info "Databases for user: $username"
    echo ""

    run_sql "SELECT db_name, db_type, access_level, created_at::date FROM provisioning.list_user_databases('$safe_username');" | \
        column -t -s'|' -N "Database,Type,Access,Created"
}

# Get connection info
get_info() {
    local db_name="$1"

    # SECURITY: Validate input
    validate_identifier "$db_name" "db_name" || exit 1
    local safe_db_name=$(escape_sql "$db_name")

    local result=$(run_sql "SELECT * FROM provisioning.get_connection_info('$safe_db_name');")

    if [ -z "$result" ]; then
        log_error "Database not found: $db_name"
        exit 1
    fi

    echo ""
    echo "=== Connection Info for $db_name ==="
    echo "$result" | awk -F'|' '{
        print "Host:     " $1
        print "Port:     " $2
        print "Database: " $3
        print "Type:     " $4
    }'
    echo ""
}

# Main
check_psql

case "${1:-}" in
    individual)
        [ -z "${2:-}" ] && usage
        create_individual "$2" "${3:-}"
        ;;
    team)
        [ -z "${2:-}" ] && usage
        create_team "$2" "${3:-}"
        ;;
    list)
        [ -z "${2:-}" ] && usage
        list_databases "$2"
        ;;
    info)
        [ -z "${2:-}" ] && usage
        get_info "$2"
        ;;
    *)
        usage
        ;;
esac
