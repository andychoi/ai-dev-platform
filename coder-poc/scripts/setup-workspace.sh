#!/bin/bash
# =============================================================================
# Coder Workspace Setup Script
# Automates: User creation, CLI login, template push, sample workspace creation
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CODER_URL="${CODER_URL:-http://localhost:7080}"
ADMIN_EMAIL="${CODER_ADMIN_EMAIL:-admin@localhost}"
ADMIN_USERNAME="${CODER_ADMIN_USERNAME:-admin}"
ADMIN_PASSWORD="${CODER_ADMIN_PASSWORD:-Password123!}"
TEMPLATE_DIR="$(dirname "$0")/../templates/contractor-workspace"
TEMPLATE_NAME="contractor-workspace"

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 is required but not installed."
        return 1
    fi
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
# Check Prerequisites
# =============================================================================

print_header "Checking Prerequisites"

check_command curl
check_command docker
check_command jq

# Check if coder CLI is installed
if ! command -v coder &> /dev/null; then
    log_warn "Coder CLI not found. Installing..."
    curl -fsSL https://coder.com/install.sh | sh
fi

log_success "All prerequisites met"

# =============================================================================
# Wait for Services
# =============================================================================

print_header "Waiting for Services"

wait_for_coder

# Check if first user needs to be created
FIRST_USER_NEEDED=$(curl -sf "${CODER_URL}/api/v2/users/first" 2>/dev/null || echo "error")

# =============================================================================
# Create First User (if needed)
# =============================================================================

print_header "User Setup"

if echo "$FIRST_USER_NEEDED" | grep -q "error"; then
    log_info "Checking if first user setup is required..."
fi

# Try to create first user
FIRST_USER_RESPONSE=$(curl -sf -X POST "${CODER_URL}/api/v2/users/first" \
    -H "Content-Type: application/json" \
    -d "{
        \"email\": \"${ADMIN_EMAIL}\",
        \"username\": \"${ADMIN_USERNAME}\",
        \"password\": \"${ADMIN_PASSWORD}\"
    }" 2>/dev/null || echo "")

if [ -n "$FIRST_USER_RESPONSE" ] && echo "$FIRST_USER_RESPONSE" | jq -e '.session_token' > /dev/null 2>&1; then
    SESSION_TOKEN=$(echo "$FIRST_USER_RESPONSE" | jq -r '.session_token')
    log_success "First user created: ${ADMIN_USERNAME}"
else
    log_info "First user already exists, attempting login..."

    # Login to get session token
    LOGIN_RESPONSE=$(curl -sf -X POST "${CODER_URL}/api/v2/users/login" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"${ADMIN_EMAIL}\",
            \"password\": \"${ADMIN_PASSWORD}\"
        }" 2>/dev/null || echo "")

    if [ -n "$LOGIN_RESPONSE" ] && echo "$LOGIN_RESPONSE" | jq -e '.session_token' > /dev/null 2>&1; then
        SESSION_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.session_token')
        log_success "Logged in as: ${ADMIN_USERNAME}"
    else
        log_error "Failed to login. Please check credentials or create user manually at ${CODER_URL}"
        echo ""
        echo "Manual setup:"
        echo "  1. Open ${CODER_URL} in browser"
        echo "  2. Create admin account"
        echo "  3. Run: coder login ${CODER_URL}"
        echo "  4. Run: coder templates push ${TEMPLATE_NAME} --directory ${TEMPLATE_DIR}"
        exit 1
    fi
fi

# =============================================================================
# Configure Coder CLI
# =============================================================================

print_header "Configuring Coder CLI"

# Create coder config directory
mkdir -p ~/.config/coderv2

# Write session file
cat > ~/.config/coderv2/session << EOF
${SESSION_TOKEN}
EOF

# Write URL file
cat > ~/.config/coderv2/url << EOF
${CODER_URL}
EOF

log_success "Coder CLI configured"

# Verify CLI connection
if coder whoami > /dev/null 2>&1; then
    CURRENT_USER=$(coder whoami --output json | jq -r '.username')
    log_success "CLI authenticated as: ${CURRENT_USER}"
else
    log_warn "CLI authentication verification failed, attempting direct login..."
    echo "${ADMIN_PASSWORD}" | coder login "${CODER_URL}" --username "${ADMIN_USERNAME}" --password-stdin
fi

# =============================================================================
# Push Template
# =============================================================================

print_header "Pushing Workspace Template"

if [ ! -d "$TEMPLATE_DIR" ]; then
    log_error "Template directory not found: ${TEMPLATE_DIR}"
    exit 1
fi

log_info "Template directory: ${TEMPLATE_DIR}"
log_info "Template name: ${TEMPLATE_NAME}"

# Check if template exists
EXISTING_TEMPLATE=$(coder templates list --output json 2>/dev/null | jq -r ".[] | select(.name==\"${TEMPLATE_NAME}\") | .name" || echo "")

if [ "$EXISTING_TEMPLATE" = "$TEMPLATE_NAME" ]; then
    log_info "Template exists, updating..."
    coder templates push "$TEMPLATE_NAME" \
        --directory "$TEMPLATE_DIR" \
        --yes \
        --variable "cpu_cores=2" \
        --variable "memory_gb=4" 2>&1 || {
            log_warn "Template push with variables failed, trying without..."
            coder templates push "$TEMPLATE_NAME" --directory "$TEMPLATE_DIR" --yes
        }
else
    log_info "Creating new template..."
    coder templates push "$TEMPLATE_NAME" \
        --directory "$TEMPLATE_DIR" \
        --yes 2>&1 || {
            log_error "Failed to push template"
            exit 1
        }
fi

log_success "Template '${TEMPLATE_NAME}' pushed successfully"

# =============================================================================
# Create Sample Workspaces
# =============================================================================

print_header "Creating Sample Workspaces"

create_workspace() {
    local ws_name=$1
    local git_repo=$2

    log_info "Creating workspace: ${ws_name}"

    # Check if workspace exists
    if coder list --output json 2>/dev/null | jq -e ".[] | select(.name==\"${ws_name}\")" > /dev/null 2>&1; then
        log_warn "Workspace '${ws_name}' already exists, skipping..."
        return 0
    fi

    # Create workspace
    coder create "$ws_name" \
        --template "$TEMPLATE_NAME" \
        --parameter "git_repo=${git_repo}" \
        --parameter "git_server_url=http://gitea:3000" \
        --parameter "ai_gateway_url=http://ai-gateway:8090" \
        --yes 2>&1 || {
            log_warn "Failed to create workspace with parameters, trying basic creation..."
            coder create "$ws_name" --template "$TEMPLATE_NAME" --yes 2>&1 || return 1
        }

    log_success "Workspace '${ws_name}' created"
}

# Create a demo workspace
create_workspace "demo-workspace" ""

# =============================================================================
# Summary
# =============================================================================

print_header "Setup Complete"

echo -e "${GREEN}Coder WebIDE Platform is ready!${NC}"
echo ""
echo "Access Points:"
echo "  - Coder Dashboard:  ${CODER_URL}"
echo "  - Git Server:       http://localhost:3000"
echo "  - AI Gateway:       http://localhost:8090"
echo "  - MinIO Console:    http://localhost:9001"
echo "  - Mailpit:          http://localhost:8025"
echo "  - Authentik:        http://localhost:9000"
echo ""
echo "Credentials:"
echo "  - Coder Admin:      ${ADMIN_USERNAME} / ${ADMIN_PASSWORD}"
echo "  - MinIO:            minioadmin / minioadmin"
echo "  - Authentik:        admin / admin"
echo ""
echo "CLI Commands:"
echo "  - List workspaces:  coder list"
echo "  - Create workspace: coder create <name> --template ${TEMPLATE_NAME}"
echo "  - Open workspace:   coder open <name>"
echo "  - SSH to workspace: coder ssh <name>"
echo ""
log_success "Setup completed successfully!"
