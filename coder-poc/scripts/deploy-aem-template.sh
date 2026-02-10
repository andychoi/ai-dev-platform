#!/bin/bash
# =============================================================================
# Deploy AEM 6.5 Workspace Template
# Builds the AEM workspace image and pushes the template to Coder.
#
# Standalone script — does NOT modify setup-workspace.sh or default templates.
# Uses the same patterns: docker cp + docker exec (no host Coder CLI needed).
#
# Prerequisites:
#   - Docker running with coder-server container up
#   - workspace-base:latest image already built (run setup-workspace.sh first)
#
# Usage:
#   ./deploy-aem-template.sh              # Build image + push template
#   REBUILD_IMAGE=true ./deploy-aem-template.sh  # Force image rebuild
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE_NAME="aem-workspace"
TEMPLATE_DIR="${POC_DIR}/templates/${TEMPLATE_NAME}"
IMAGE_NAME="aem-workspace"
CODER_URL="${CODER_URL:-http://localhost:7080}"
CODER_INTERNAL_URL="http://localhost:7080"
ADMIN_EMAIL="${CODER_ADMIN_EMAIL:-admin@example.com}"
ADMIN_USERNAME="${CODER_ADMIN_USERNAME:-admin}"
ADMIN_PASSWORD="${CODER_ADMIN_PASSWORD:-CoderAdmin123!}"

# =============================================================================
# Helper Functions
# =============================================================================

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# =============================================================================
# Preflight Checks
# =============================================================================

print_header "Deploy AEM 6.5 Workspace Template"

log_info "Running preflight checks..."

# Required tools
command -v curl  &>/dev/null || { log_error "curl is required";  exit 1; }
command -v docker &>/dev/null || { log_error "docker is required"; exit 1; }

# Template directory must exist
if [ ! -d "$TEMPLATE_DIR" ]; then
    log_error "Template directory not found: $TEMPLATE_DIR"
    log_error "Run this script from the dev-platform repository root."
    exit 1
fi

# workspace-base image must exist (AEM image extends it)
if ! docker image inspect workspace-base:latest &>/dev/null; then
    log_error "workspace-base:latest image not found."
    log_error "Run setup-workspace.sh first to build the base image, or:"
    log_error "  docker build -t workspace-base:latest ${POC_DIR}/templates/workspace-base/build"
    exit 1
fi

# coder-server container must be running (for template push)
if ! docker inspect coder-server &>/dev/null; then
    log_error "coder-server container not found. Is Coder running?"
    log_error "  cd coder-poc && docker compose up -d"
    exit 1
fi

log_success "Preflight checks passed"

# =============================================================================
# Wait for Coder API
# =============================================================================

log_info "Waiting for Coder API..."
MAX_ATTEMPTS=30
for attempt in $(seq 1 $MAX_ATTEMPTS); do
    if curl -sf "${CODER_URL}/api/v2/buildinfo" >/dev/null 2>&1; then
        log_success "Coder API is ready"
        break
    fi
    if [ "$attempt" -eq "$MAX_ATTEMPTS" ]; then
        log_error "Coder API not ready after ${MAX_ATTEMPTS} attempts"
        exit 1
    fi
    echo -n "."
    sleep 2
done

# =============================================================================
# Authenticate
# =============================================================================

print_header "Authentication"

log_info "Authenticating as ${ADMIN_USERNAME}..."

# Try first-user creation, then login
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
        log_error "Check CODER_ADMIN_EMAIL / CODER_ADMIN_PASSWORD"
        exit 1
    fi
fi

if [ -z "$SESSION_TOKEN" ]; then
    log_error "Failed to get session token"
    exit 1
fi

# =============================================================================
# Build AEM Workspace Image
# =============================================================================

print_header "Build: ${IMAGE_NAME}:latest"

BUILD_DIR="${TEMPLATE_DIR}/build"

if [ ! -f "${BUILD_DIR}/Dockerfile" ]; then
    log_error "Dockerfile not found at ${BUILD_DIR}/Dockerfile"
    exit 1
fi

if docker image inspect "${IMAGE_NAME}:latest" &>/dev/null && [ "${REBUILD_IMAGE:-}" != "true" ]; then
    log_success "${IMAGE_NAME}:latest already exists (set REBUILD_IMAGE=true to force)"
else
    log_info "Building ${IMAGE_NAME}:latest (this may take a few minutes)..."
    docker build -t "${IMAGE_NAME}:latest" "$BUILD_DIR" 2>&1 | tail -10
    log_success "${IMAGE_NAME}:latest built"
fi

# =============================================================================
# Verify Image
# =============================================================================

print_header "Verify: ${IMAGE_NAME}:latest"

# Check Java version
JAVA_VERSION=$(docker run --rm "${IMAGE_NAME}:latest" java -version 2>&1 | head -1)
if echo "$JAVA_VERSION" | grep -q '"11\.'; then
    log_success "Java: $JAVA_VERSION"
else
    log_warn "Expected Java 11, got: $JAVA_VERSION"
fi

# Check Maven version
MVN_VERSION=$(docker run --rm "${IMAGE_NAME}:latest" mvn --version 2>&1 | head -1)
if echo "$MVN_VERSION" | grep -q "3.9.9"; then
    log_success "Maven: $MVN_VERSION"
else
    log_warn "Expected Maven 3.9.9, got: $MVN_VERSION"
fi

# Check xmlstarlet
if docker run --rm "${IMAGE_NAME}:latest" xmlstarlet --version &>/dev/null; then
    log_success "xmlstarlet: installed"
else
    log_warn "xmlstarlet: not found"
fi

# Check Maven settings
if docker run --rm "${IMAGE_NAME}:latest" test -f /home/coder/.m2/settings.xml; then
    log_success "Maven settings.xml: present"
else
    log_warn "Maven settings.xml: missing from image (will be created at startup)"
fi

# =============================================================================
# Push Template to Coder
# =============================================================================

print_header "Push Template: ${TEMPLATE_NAME}"

log_info "Copying template to coder-server container..."
docker cp "$TEMPLATE_DIR" coder-server:/tmp/template-to-push

log_info "Pushing template '${TEMPLATE_NAME}'..."
docker exec \
    -e CODER_URL="${CODER_INTERNAL_URL}" \
    -e CODER_SESSION_TOKEN="${SESSION_TOKEN}" \
    coder-server sh -c "
    coder whoami 2>&1 || { echo 'Auth failed'; exit 1; }
    cd /tmp/template-to-push
    coder templates push ${TEMPLATE_NAME} --directory . --yes 2>&1 || \
    coder templates create ${TEMPLATE_NAME} --directory . --yes 2>&1
" 2>&1 | while read -r line; do
    echo "  $line"
done

# Clean up
docker exec -u root coder-server rm -rf /tmp/template-to-push 2>/dev/null || true

# =============================================================================
# Verify Template in Coder
# =============================================================================

print_header "Verify Template"

TEMPLATES_JSON=$(curl -sf "${CODER_URL}/api/v2/templates" \
    -H "Coder-Session-Token: ${SESSION_TOKEN}" 2>/dev/null || echo "[]")

if echo "$TEMPLATES_JSON" | grep -q "$TEMPLATE_NAME"; then
    log_success "Template '${TEMPLATE_NAME}' is available in Coder"
else
    log_warn "Template '${TEMPLATE_NAME}' may not be visible yet (check Coder UI)"
fi

# =============================================================================
# Summary
# =============================================================================

print_header "AEM Template Deployed"

echo -e "${GREEN}AEM 6.5 workspace template is ready!${NC}"
echo ""
echo "Create a workspace:"
echo "  1. Go to https://host.docker.internal:7443"
echo "  2. Click 'Create Workspace' → select '${TEMPLATE_NAME}'"
echo "  3. Configure:"
echo "     - CPU: 4+ cores (6-8 if enabling Publisher)"
echo "     - Memory: 8+ GB (12-16 if enabling Publisher)"
echo "     - Author JVM Heap: 2-3 GB"
echo ""
echo "AEM quickstart JAR (proprietary — not in image):"
echo "  After workspace starts, upload the JAR:"
echo "    coder scp local:aem-quickstart-6.5.x.jar <workspace>:/home/coder/aem/aem-quickstart.jar"
echo "  Then restart the workspace for AEM to start."
echo ""
echo "Useful aliases (available inside the workspace):"
echo "  aem-build       — mvn clean install + deploy to Author"
echo "  aem-deploy      — same but skip tests"
echo "  aem-status      — check Author/Publisher status"
echo "  aem-logs        — tail Author error.log"
echo "  aem-bundles     — OSGi bundle summary"
echo ""

log_success "Deployment complete!"
