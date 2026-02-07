#!/bin/bash
# =============================================================================
# Coder Workspace Setup Script
# Automates: User creation, template push (via container), sample workspace
# NO HOST CLI REQUIRED - uses Docker to push templates
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(dirname "$SCRIPT_DIR")"
CODER_URL="${CODER_URL:-http://localhost:7080}"  # HTTP for API calls (scripts)
CODER_INTERNAL_URL="http://localhost:7080"  # HTTP for Coder CLI inside container (no cert needed)
ADMIN_EMAIL="${CODER_ADMIN_EMAIL:-admin@example.com}"
ADMIN_USERNAME="${CODER_ADMIN_USERNAME:-admin}"
ADMIN_PASSWORD="${CODER_ADMIN_PASSWORD:-CoderAdmin123!}"
TEMPLATE_DIR="${POC_DIR}/templates/contractor-workspace"
TEMPLATE_NAME="contractor-workspace"

# =============================================================================
# Helper Functions
# =============================================================================

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

wait_for_coder() {
    log_info "Waiting for Coder server to be ready..."
    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if curl -sf "${CODER_URL}/api/v2/buildinfo" > /dev/null 2>&1; then
            log_success "Coder server is ready"
            return 0
        fi
        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done

    log_error "Coder server not ready after ${max_attempts} attempts"
    return 1
}

# =============================================================================
# Main Script
# =============================================================================

print_header "Coder Workspace Setup (No Host CLI Required)"

# Check prerequisites
log_info "Checking prerequisites..."
command -v curl &> /dev/null || { log_error "curl is required"; exit 1; }
command -v docker &> /dev/null || { log_error "docker is required"; exit 1; }
log_success "Prerequisites met"

# Wait for Coder
wait_for_coder

# =============================================================================
# Get Session Token
# =============================================================================

print_header "Authentication"

# Try to create first user or login
log_info "Authenticating with Coder..."

FIRST_USER_RESPONSE=$(curl -sf -X POST "${CODER_URL}/api/v2/users/first" \
    -H "Content-Type: application/json" \
    -d "{
        \"email\": \"${ADMIN_EMAIL}\",
        \"username\": \"${ADMIN_USERNAME}\",
        \"password\": \"${ADMIN_PASSWORD}\"
    }" 2>/dev/null || echo "")

if [ -n "$FIRST_USER_RESPONSE" ] && echo "$FIRST_USER_RESPONSE" | grep -q "session_token"; then
    SESSION_TOKEN=$(echo "$FIRST_USER_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_token',''))" 2>/dev/null)
    log_success "First user created: ${ADMIN_USERNAME}"
else
    # Login to get session token
    LOGIN_RESPONSE=$(curl -sf -X POST "${CODER_URL}/api/v2/users/login" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"${ADMIN_EMAIL}\",
            \"password\": \"${ADMIN_PASSWORD}\"
        }" 2>/dev/null || echo "")

    if [ -n "$LOGIN_RESPONSE" ] && echo "$LOGIN_RESPONSE" | grep -q "session_token"; then
        SESSION_TOKEN=$(echo "$LOGIN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_token',''))" 2>/dev/null)
        log_success "Logged in as: ${ADMIN_USERNAME}"
    else
        log_error "Failed to authenticate with Coder"
        exit 1
    fi
fi

if [ -z "$SESSION_TOKEN" ]; then
    log_error "Failed to get session token"
    exit 1
fi

# =============================================================================
# Build Workspace Image
# =============================================================================

print_header "Building Workspace Image"

if [ -f "$TEMPLATE_DIR/build/Dockerfile" ]; then
    log_info "Building contractor-workspace:latest..."
    docker build -t contractor-workspace:latest "$TEMPLATE_DIR/build" 2>&1 | tail -5
    log_success "Workspace image built"
else
    log_warn "Dockerfile not found at $TEMPLATE_DIR/build/Dockerfile"
fi

# =============================================================================
# Push Template via Docker
# =============================================================================

print_header "Pushing Template to Coder"

if [ ! -d "$TEMPLATE_DIR" ]; then
    log_error "Template directory not found: ${TEMPLATE_DIR}"
    exit 1
fi

log_info "Template directory: ${TEMPLATE_DIR}"
log_info "Template name: ${TEMPLATE_NAME}"

# Copy template into the coder-server container and push from there
log_info "Copying template to coder-server container..."

# Copy template directory to container
docker cp "$TEMPLATE_DIR" coder-server:/tmp/template-to-push

# Configure CLI and push template from inside the container
log_info "Pushing template from inside coder-server..."

# Use environment variables for CLI authentication (no file writes needed)
docker exec \
    -e CODER_URL="${CODER_INTERNAL_URL}" \
    -e CODER_SESSION_TOKEN="${SESSION_TOKEN}" \
    coder-server sh -c "
    # Verify authentication
    echo 'Verifying authentication...'
    coder whoami 2>&1 || { echo 'Auth failed'; exit 1; }

    # Push template
    echo 'Pushing template...'
    cd /tmp/template-to-push
    coder templates push ${TEMPLATE_NAME} --directory . --yes 2>&1 || \
    coder templates create ${TEMPLATE_NAME} --directory . --yes 2>&1
" 2>&1 | while read -r line; do
    echo "  $line"
done

# Cleanup copied files (docker cp preserves host UID, so rm needs root)
docker exec -u root coder-server rm -rf /tmp/template-to-push 2>/dev/null || true

PUSH_RESULT=${PIPESTATUS[0]}

if [ $PUSH_RESULT -eq 0 ]; then
    log_success "Template '${TEMPLATE_NAME}' pushed successfully"
else
    log_warn "Template push may have had issues - check output above"
fi

# =============================================================================
# Verify Template
# =============================================================================

print_header "Verifying Template"

# Check if template exists via API
TEMPLATES=$(curl -sf "${CODER_URL}/api/v2/templates" \
    -H "Coder-Session-Token: ${SESSION_TOKEN}" 2>/dev/null || echo "[]")

if echo "$TEMPLATES" | grep -q "$TEMPLATE_NAME"; then
    log_success "Template '${TEMPLATE_NAME}' is available in Coder"
else
    log_warn "Template may not be visible yet - try refreshing Coder UI"
fi

# =============================================================================
# Summary
# =============================================================================

print_header "Setup Complete"

echo -e "${GREEN}Workspace template is ready!${NC}"
echo ""
echo "Next steps:"
echo "  1. Go to https://host.docker.internal:7443 (accept self-signed cert warning)"
echo "  2. Login via OIDC or local account"
echo "  3. Click 'Create Workspace'"
echo "  4. Select '${TEMPLATE_NAME}' template"
echo "  5. Configure workspace options and create"
echo ""
log_success "Setup completed successfully!"
