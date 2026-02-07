#!/bin/bash
# =============================================================================
# Coder Production — First-Time Bootstrap
# Runs after Terraform + ECS deploy to initialize first user and template
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROD_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# -----------------------------------------------------------------------------
# Prerequisites
# -----------------------------------------------------------------------------

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Coder Production Bootstrap (ECS Fargate)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

CODER_URL="${CODER_URL:-https://coder.company.com}"
ADMIN_EMAIL="${CODER_ADMIN_EMAIL:-admin@company.com}"
ADMIN_USERNAME="${CODER_ADMIN_USERNAME:-admin}"
ADMIN_PASSWORD="${CODER_ADMIN_PASSWORD:-}"
AWS_REGION="${AWS_REGION:-us-west-2}"
ECS_CLUSTER="${ECS_CLUSTER:-coder-production-cluster}"

if [ -z "$ADMIN_PASSWORD" ]; then
  log_error "CODER_ADMIN_PASSWORD must be set"
  exit 1
fi

command -v aws &>/dev/null  || { log_error "aws CLI required"; exit 1; }
command -v curl &>/dev/null || { log_error "curl required"; exit 1; }

# Verify ECS cluster exists
aws ecs describe-clusters --clusters "$ECS_CLUSTER" --region "$AWS_REGION" --query 'clusters[0].status' --output text 2>/dev/null | grep -q ACTIVE || {
  log_error "ECS cluster '$ECS_CLUSTER' not found or not ACTIVE in $AWS_REGION"
  exit 1
}
log_success "Connected to ECS cluster: $ECS_CLUSTER"

# -----------------------------------------------------------------------------
# Wait for services
# -----------------------------------------------------------------------------

log_info "Waiting for Coder to be ready..."
for i in $(seq 1 60); do
  if curl -sf "${CODER_URL}/api/v2/buildinfo" &>/dev/null; then
    log_success "Coder is ready"
    break
  fi
  [ "$i" -eq 60 ] && { log_error "Coder not ready after 120s"; exit 1; }
  sleep 2
done

log_info "Waiting for LiteLLM ECS service to be stable..."
aws ecs wait services-stable \
  --cluster "$ECS_CLUSTER" \
  --services litellm \
  --region "$AWS_REGION" 2>/dev/null || log_warn "LiteLLM service not stable yet"

# -----------------------------------------------------------------------------
# Create first admin user
# -----------------------------------------------------------------------------

log_info "Creating first admin user..."

FIRST_USER=$(curl -sf -X POST "${CODER_URL}/api/v2/users/first" \
  -H "Content-Type: application/json" \
  -d "{
    \"email\": \"${ADMIN_EMAIL}\",
    \"username\": \"${ADMIN_USERNAME}\",
    \"password\": \"${ADMIN_PASSWORD}\"
  }" 2>/dev/null || echo "")

if echo "$FIRST_USER" | grep -q "session_token"; then
  SESSION_TOKEN=$(echo "$FIRST_USER" | python3 -c "import sys,json; print(json.load(sys.stdin)['session_token'])" 2>/dev/null)
  log_success "Admin user created: ${ADMIN_USERNAME}"
else
  log_info "First user already exists, logging in..."
  LOGIN=$(curl -sf -X POST "${CODER_URL}/api/v2/users/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}" 2>/dev/null || echo "")

  if echo "$LOGIN" | grep -q "session_token"; then
    SESSION_TOKEN=$(echo "$LOGIN" | python3 -c "import sys,json; print(json.load(sys.stdin)['session_token'])" 2>/dev/null)
    log_success "Logged in as ${ADMIN_USERNAME}"
  else
    log_error "Failed to authenticate"
    exit 1
  fi
fi

# -----------------------------------------------------------------------------
# Push workspace template
# -----------------------------------------------------------------------------

log_info "Pushing contractor-workspace template..."

if command -v coder &>/dev/null; then
  export CODER_URL CODER_SESSION_TOKEN="$SESSION_TOKEN"
  coder templates push contractor-workspace \
    --directory "${PROD_DIR}/templates/contractor-workspace" \
    --yes 2>&1 || \
  coder templates create contractor-workspace \
    --directory "${PROD_DIR}/templates/contractor-workspace" \
    --yes 2>&1
  log_success "Template pushed"
else
  log_warn "coder CLI not found — download from ${CODER_URL}/bin/coder-linux-amd64"
  log_warn "Then run: coder templates push contractor-workspace --directory templates/contractor-workspace --yes"
fi

# -----------------------------------------------------------------------------
# Generate LiteLLM virtual key for admin
# -----------------------------------------------------------------------------

LITELLM_MASTER_KEY=$(aws secretsmanager get-secret-value \
  --secret-id "prod/litellm/master-key" \
  --region "$AWS_REGION" \
  --query 'SecretString' \
  --output text 2>/dev/null || echo "")

LITELLM_URL="${LITELLM_URL:-https://ai.company.com}"

if [ -n "$LITELLM_MASTER_KEY" ]; then
  log_info "Generating LiteLLM virtual key for admin..."
  KEY_RESPONSE=$(curl -sf "${LITELLM_URL}/key/generate" \
    -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
    -H "Content-Type: application/json" \
    -d "{
      \"user_id\": \"${ADMIN_USERNAME}\",
      \"max_budget\": 50.00,
      \"rpm_limit\": 200,
      \"key_alias\": \"${ADMIN_USERNAME}-workspace\"
    }" 2>/dev/null || echo "")

  if echo "$KEY_RESPONSE" | grep -q "key"; then
    VIRTUAL_KEY=$(echo "$KEY_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['key'])" 2>/dev/null)
    log_success "LiteLLM virtual key generated for admin"
    echo ""
    echo -e "  ${YELLOW}Save this key — use it when creating a workspace:${NC}"
    echo -e "  ${GREEN}${VIRTUAL_KEY}${NC}"
    echo ""
  else
    log_warn "Could not generate LiteLLM key — ensure LiteLLM is accessible at ${LITELLM_URL}"
  fi
else
  log_warn "LiteLLM master key not found in Secrets Manager — skip key generation"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Bootstrap Complete${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Coder:      ${CODER_URL}"
echo "  Admin:      ${ADMIN_EMAIL}"
echo "  Template:   contractor-workspace"
echo "  ECS:        ${ECS_CLUSTER} (${AWS_REGION})"
echo ""
echo "  Next steps:"
echo "    1. Log in to Coder (via VPN)"
echo "    2. Create a workspace using contractor-workspace template"
echo "    3. Enter the LiteLLM virtual key when prompted"
echo ""
