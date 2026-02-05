#!/usr/bin/env bash
# =============================================================================
# Unified Test Users Setup Script
# Creates consistent test users across Coder, Gitea, and Authentik
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
CODER_URL="${CODER_URL:-http://localhost:7080}"
CODER_ADMIN_EMAIL="${CODER_ADMIN_EMAIL:-admin@example.com}"
CODER_ADMIN_PASSWORD="${CODER_ADMIN_PASSWORD:-CoderAdmin123!}"

GITEA_URL="${GITEA_URL:-http://localhost:3000}"
GITEA_ADMIN_USER="${GITEA_ADMIN_USER:-gitea}"
GITEA_ADMIN_PASSWORD="${GITEA_ADMIN_PASSWORD:-admin123}"

AUTHENTIK_URL="${AUTHENTIK_URL:-http://localhost:9000}"
AUTHENTIK_TOKEN="${AUTHENTIK_TOKEN:-}"  # Set via environment or will be fetched

# Test users to create (username:password pairs)
TEST_USERNAMES="appmanager contractor1 contractor2 contractor3 readonly"
TEST_PASSWORD="Password123!"  # Coder requires strong passwords
GITEA_PASSWORD="password123"   # Gitea allows simpler passwords
AUTHENTIK_PASSWORD="password123"  # Authentik test user password

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           Unified Test Users Setup Script                     ║"
echo "╠═══════════════════════════════════════════════════════════════╣"
echo "║  Creates test users in: Coder, Gitea, Authentik              ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# =============================================================================
# CODER USERS
# =============================================================================
setup_coder_users() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Setting up Coder Users${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

    # Check if Coder is ready
    if ! curl -s "${CODER_URL}/api/v2/buildinfo" > /dev/null 2>&1; then
        log_error "Coder is not running at ${CODER_URL}"
        return 1
    fi
    log_success "Coder is running"

    # Login to get session token
    log_info "Logging in as admin..."
    CODER_TOKEN=$(curl -s -X POST "${CODER_URL}/api/v2/users/login" \
        -H "Content-Type: application/json" \
        -d @- <<EOF | jq -r '.session_token // empty'
{
    "email": "${CODER_ADMIN_EMAIL}",
    "password": "${CODER_ADMIN_PASSWORD}"
}
EOF
    )

    if [ -z "$CODER_TOKEN" ]; then
        log_error "Failed to login to Coder. Check admin credentials."
        return 1
    fi
    log_success "Logged in to Coder"

    # Get default organization ID
    log_info "Getting default organization..."
    ORG_ID=$(curl -s "${CODER_URL}/api/v2/organizations" \
        -H "Coder-Session-Token: ${CODER_TOKEN}" | jq -r '.[0].id // empty')

    if [ -z "$ORG_ID" ]; then
        log_error "Failed to get organization ID"
        return 1
    fi
    log_success "Organization ID: ${ORG_ID}"

    # Create test users
    for username in $TEST_USERNAMES; do
        password="$TEST_PASSWORD"
        email="${username}@example.com"

        log_info "Creating Coder user: ${username}"

        # Check if user exists
        exists=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Coder-Session-Token: ${CODER_TOKEN}" \
            "${CODER_URL}/api/v2/users/${username}")

        if [ "$exists" == "200" ]; then
            log_warn "User ${username} already exists in Coder"
            continue
        fi

        # Create user with OIDC login type so they can login via Authentik SSO
        # OIDC users authenticate through the identity provider, not via Coder password
        result=$(curl -s -X POST "${CODER_URL}/api/v2/users" \
            -H "Content-Type: application/json" \
            -H "Coder-Session-Token: ${CODER_TOKEN}" \
            -d @- <<EOF
{
    "email": "${email}",
    "username": "${username}",
    "password": "",
    "login_type": "oidc",
    "organization_ids": ["${ORG_ID}"]
}
EOF
        )

        if echo "$result" | jq -e '.id' > /dev/null 2>&1; then
            log_success "Created Coder user: ${username} (${email})"
        else
            error=$(echo "$result" | jq -r '.message // .detail // "Unknown error"')
            log_error "Failed to create ${username}: ${error}"
        fi
    done
}

# =============================================================================
# GITEA USERS
# =============================================================================
setup_gitea_users() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Setting up Gitea Users${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

    # Check if Gitea is ready
    if ! curl -s "${GITEA_URL}/api/healthz" > /dev/null 2>&1; then
        log_error "Gitea is not running at ${GITEA_URL}"
        return 1
    fi
    log_success "Gitea is running"

    # Create test users via Gitea CLI (more reliable than API)
    for username in $TEST_USERNAMES; do
        password="$GITEA_PASSWORD"
        email="${username}@example.com"

        log_info "Creating Gitea user: ${username}"

        # Try to create user via CLI
        result=$(docker exec gitea gitea admin user create \
            --username "$username" \
            --password "$password" \
            --email "$email" \
            --must-change-password=false 2>&1) || true

        if echo "$result" | grep -q "has been successfully created\|New user"; then
            log_success "Created Gitea user: ${username}"
        elif echo "$result" | grep -q "already exists"; then
            log_warn "User ${username} already exists in Gitea"
        else
            log_error "Failed to create ${username}: ${result}"
        fi
    done

    # Create sample repositories if they don't exist
    log_info "Setting up sample repositories..."

    # Check if setup-gitea.sh exists and run the repo creation part
    if [ -f "${SCRIPT_DIR}/setup-gitea.sh" ]; then
        log_info "Running repository setup from setup-gitea.sh..."
        bash "${SCRIPT_DIR}/setup-gitea.sh" 2>&1 | grep -E "(Created|already exists|Repository)" || true
    fi
}

# =============================================================================
# AUTHENTIK USERS
# =============================================================================
setup_authentik_users() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Setting up Authentik Users${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

    # Check if Authentik is ready
    if ! curl -s "${AUTHENTIK_URL}/-/health/ready/" > /dev/null 2>&1; then
        log_warn "Authentik is not ready at ${AUTHENTIK_URL}"
        log_warn "Skipping Authentik user setup (may need more startup time)"
        return 0
    fi
    log_success "Authentik is running"

    # Check if authentik-server container exists
    if ! docker ps --format '{{.Names}}' | grep -q '^authentik-server$'; then
        log_warn "authentik-server container not found"
        log_warn "Skipping Authentik user setup"
        return 0
    fi

    # Create users via ak shell (more reliable than API, no token required)
    log_info "Creating Authentik users via ak shell..."

    # Build Python script for user creation
    USERS_PYTHON=""
    for username in $TEST_USERNAMES; do
        email="${username}@example.com"
        # Format display name: contractor1 -> Contractor 1, appmanager -> App Manager
        display_name=$(echo "$username" | sed 's/\([a-z]\)\([0-9]\)/\1 \2/g' | sed 's/\(.\)/\U\1/')
        USERS_PYTHON="${USERS_PYTHON}    ('${username}', '${email}', '${AUTHENTIK_PASSWORD}', '${display_name}'),
"
    done

    # Execute via ak shell
    docker exec authentik-server ak shell -c "
from authentik.core.models import User

test_users = [
${USERS_PYTHON}]

for username, email, password, name in test_users:
    try:
        user, created = User.objects.get_or_create(
            username=username,
            defaults={
                'email': email,
                'name': name,
                'is_active': True,
            }
        )
        if created:
            user.set_password(password)
            user.save()
            print(f'Created: {username}')
        else:
            print(f'Exists: {username}')
    except Exception as e:
        print(f'Error {username}: {e}')
" 2>&1 | while read -r line; do
        if echo "$line" | grep -q "^Created:"; then
            log_success "$(echo "$line" | sed 's/Created:/Created Authentik user:/')"
        elif echo "$line" | grep -q "^Exists:"; then
            log_warn "$(echo "$line" | sed 's/Exists:/User already exists in Authentik:/')"
        elif echo "$line" | grep -q "^Error"; then
            log_error "$line"
        fi
    done
}

# =============================================================================
# MAIN
# =============================================================================

# Parse arguments
SETUP_CODER=true
SETUP_GITEA=true
SETUP_AUTHENTIK=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --coder-only)
            SETUP_GITEA=false
            SETUP_AUTHENTIK=false
            shift
            ;;
        --gitea-only)
            SETUP_CODER=false
            SETUP_AUTHENTIK=false
            shift
            ;;
        --authentik-only)
            SETUP_CODER=false
            SETUP_GITEA=false
            shift
            ;;
        --no-authentik)
            SETUP_AUTHENTIK=false
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --coder-only      Only setup Coder users"
            echo "  --gitea-only      Only setup Gitea users"
            echo "  --authentik-only  Only setup Authentik users"
            echo "  --no-authentik    Skip Authentik setup"
            echo "  -h, --help        Show this help"
            echo ""
            echo "Environment Variables:"
            echo "  CODER_URL           Coder URL (default: http://localhost:7080)"
            echo "  CODER_ADMIN_EMAIL   Coder admin email (default: admin@example.com)"
            echo "  CODER_ADMIN_PASSWORD Coder admin password (default: CoderAdmin123!)"
            echo "  GITEA_URL            Gitea URL (default: http://localhost:3000)"
            echo "  GITEA_ADMIN_USER     Gitea admin username (default: gitea)"
            echo "  GITEA_ADMIN_PASSWORD Gitea admin password (default: admin123)"
            echo "  AUTHENTIK_URL       Authentik URL (default: http://localhost:9000)"
            echo "  AUTHENTIK_TOKEN     Authentik API token (required for Authentik)"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run setup for each system
if [ "$SETUP_CODER" = true ]; then
    setup_coder_users || log_warn "Coder setup had issues"
fi

if [ "$SETUP_GITEA" = true ]; then
    setup_gitea_users || log_warn "Gitea setup had issues"
fi

if [ "$SETUP_AUTHENTIK" = true ]; then
    setup_authentik_users || log_warn "Authentik setup had issues"
fi

# Summary
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Setup Complete${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Test Users Created:"
echo "┌─────────────┬─────────────────────────┬────────────────┬─────────────┬───────────────┐"
echo "│ Username    │ Email                   │ Coder Pass     │ Gitea Pass  │ Authentik Pass│"
echo "├─────────────┼─────────────────────────┼────────────────┼─────────────┼───────────────┤"
for username in $TEST_USERNAMES; do
    printf "│ %-11s │ %-23s │ %-14s │ %-11s │ %-13s │\n" "$username" "${username}@example.com" "$TEST_PASSWORD" "$GITEA_PASSWORD" "$AUTHENTIK_PASSWORD"
done
echo "└─────────────┴─────────────────────────┴────────────────┴─────────────┴───────────────┘"
echo ""
echo "Access URLs:"
echo "  - Coder:     ${CODER_URL}"
echo "  - Gitea:     ${GITEA_URL}"
echo "  - Authentik: ${AUTHENTIK_URL}"
echo ""
echo "Admin Credentials:"
echo "  - Coder:     ${CODER_ADMIN_EMAIL} / ${CODER_ADMIN_PASSWORD}"
echo "  - Gitea:     ${GITEA_ADMIN_USER} / ${GITEA_ADMIN_PASSWORD}"
echo "  - Authentik: akadmin / admin"
echo ""
