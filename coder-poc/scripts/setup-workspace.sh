#!/bin/bash
# =============================================================================
# Coder Workspace Setup Script
# Automates: Image builds, template push (via container) for all templates
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

# Base image (must be built first — all language templates extend it)
BASE_IMAGE_DIR="${POC_DIR}/templates/workspace-base/build"

# Templates to set up: "name:directory:image" triplets
# All discovered templates are deployed automatically
TEMPLATES=()
[ -d "${POC_DIR}/templates/python-workspace" ] && TEMPLATES+=("python-workspace:python-workspace:python-workspace")
[ -d "${POC_DIR}/templates/nodejs-workspace" ] && TEMPLATES+=("nodejs-workspace:nodejs-workspace:nodejs-workspace")
[ -d "${POC_DIR}/templates/java-workspace" ] && TEMPLATES+=("java-workspace:java-workspace:java-workspace")
[ -d "${POC_DIR}/templates/dotnet-workspace" ] && TEMPLATES+=("dotnet-workspace:dotnet-workspace:dotnet-workspace")
[ -d "${POC_DIR}/templates/docker-workspace" ] && TEMPLATES+=("docker-workspace:docker-workspace:docker-workspace")

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

# Build a Docker image if it doesn't already exist
build_image() {
    local image_name="$1"
    local build_dir="$2"

    if [ ! -f "$build_dir/Dockerfile" ]; then
        log_warn "Dockerfile not found at $build_dir/Dockerfile — skipping"
        return 1
    fi

    if docker image inspect "${image_name}:latest" &>/dev/null && [ "${REBUILD_IMAGE:-}" != "true" ]; then
        log_success "${image_name} image already exists — skipping build"
        return 0
    fi

    log_info "Building ${image_name}:latest..."
    docker build -t "${image_name}:latest" "$build_dir" 2>&1 | tail -5
    log_success "${image_name} image built"
}

# Push a template to Coder (copies into coder-server container and runs coder CLI)
push_template() {
    local template_name="$1"
    local template_dir="$2"

    if [ ! -d "$template_dir" ]; then
        log_warn "Template directory not found: ${template_dir} — skipping"
        return 1
    fi

    log_info "Pushing template '${template_name}'..."

    docker cp "$template_dir" coder-server:/tmp/template-to-push

    docker exec \
        -e CODER_URL="${CODER_INTERNAL_URL}" \
        -e CODER_SESSION_TOKEN="${SESSION_TOKEN}" \
        coder-server sh -c "
        coder whoami 2>&1 || { echo 'Auth failed'; exit 1; }
        cd /tmp/template-to-push
        coder templates push ${template_name} --directory . --yes 2>&1 || \
        coder templates create ${template_name} --directory . --yes 2>&1
    " 2>&1 | while read -r line; do
        echo "  $line"
    done

    docker exec -u root coder-server rm -rf /tmp/template-to-push 2>/dev/null || true

    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        log_success "Template '${template_name}' pushed"
    else
        log_warn "Template '${template_name}' push may have had issues"
    fi
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
# Build Base Image (all language templates extend this)
# =============================================================================

print_header "Base Image: workspace-base"

if [ -d "$BASE_IMAGE_DIR" ]; then
    build_image "workspace-base" "$BASE_IMAGE_DIR"
else
    log_warn "Base image directory not found: $BASE_IMAGE_DIR"
fi

# =============================================================================
# Build Language Images & Push Templates
# =============================================================================

for entry in "${TEMPLATES[@]}"; do
    IFS=':' read -r tpl_name tpl_dir image_name <<< "$entry"
    tpl_path="${POC_DIR}/templates/${tpl_dir}"

    print_header "Template: ${tpl_name}"

    # Build image
    if [ -d "${tpl_path}/build" ]; then
        build_image "$image_name" "${tpl_path}/build"
    fi

    # Push template
    push_template "$tpl_name" "$tpl_path"
done

# =============================================================================
# Verify Templates
# =============================================================================

print_header "Verifying Templates"

TEMPLATES_JSON=$(curl -sf "${CODER_URL}/api/v2/templates" \
    -H "Coder-Session-Token: ${SESSION_TOKEN}" 2>/dev/null || echo "[]")

for entry in "${TEMPLATES[@]}"; do
    IFS=':' read -r tpl_name _ _ <<< "$entry"
    if echo "$TEMPLATES_JSON" | grep -q "$tpl_name"; then
        log_success "Template '${tpl_name}' is available in Coder"
    else
        log_warn "Template '${tpl_name}' may not be visible yet"
    fi
done

# =============================================================================
# Summary
# =============================================================================

print_header "Setup Complete"

echo -e "${GREEN}Workspace templates are ready!${NC}"
echo ""
echo "Next steps:"
echo "  1. Go to https://host.docker.internal:7443 (accept self-signed cert warning)"
echo "  2. Login via OIDC or local account"
echo "  3. Click 'Create Workspace'"
echo "  4. Select a template and configure workspace options:"
echo "     - AI Assistant: 'All Agents' (Roo Code + OpenCode + Claude Code) or pick one"
echo "     - Default LLM: pick a model (bedrock-claude-haiku is cheapest)"
echo "     - AI key is auto-provisioned on first start (no manual paste needed)"
echo "  5. Once workspace is running:"
echo "     - Web IDE (Roo Code): click 'code-server' in the workspace toolbar"
echo "     - Terminal AI (OpenCode): open the web terminal and run 'opencode'"
echo "     - Terminal AI (Claude Code): open the web terminal and run 'claude'"
echo ""

log_success "Setup completed successfully!"
