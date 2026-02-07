#!/bin/bash
# =============================================================================
# Setup LiteLLM Virtual Keys for All Test Users
# Creates per-user API keys with budget and rate limits
# Keys are saved to a file for use during workspace provisioning
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LITELLM_URL="${LITELLM_URL:-http://localhost:4000}"
MASTER_KEY="${LITELLM_MASTER_KEY:-sk-poc-litellm-master-key-change-in-production}"
KEYS_FILE="${LITELLM_KEYS_FILE:-/tmp/litellm-keys.txt}"

# Users to create keys for (username:budget:rpm)
USERS=(
  "admin:50.00:200"
  "appmanager:20.00:100"
  "contractor1:10.00:60"
  "contractor2:10.00:60"
  "contractor3:10.00:60"
  "readonly:5.00:30"
)

echo -e "${BLUE}=== Setting up LiteLLM virtual keys ===${NC}"
echo "LiteLLM URL: $LITELLM_URL"
echo ""

# Wait for LiteLLM to be ready (use /health/readiness — no auth required)
echo "Waiting for LiteLLM to be ready..."
for i in $(seq 1 60); do
  if curl -sf "$LITELLM_URL/health/readiness" > /dev/null 2>&1; then
    echo -e "${GREEN}LiteLLM is ready!${NC}"
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo -e "${RED}ERROR: LiteLLM not ready after 60 seconds${NC}"
    exit 1
  fi
  sleep 1
done

echo ""

# Clear previous keys file
> "$KEYS_FILE"

KEYS_CREATED=0
KEYS_FAILED=0

for user_config in "${USERS[@]}"; do
  IFS=':' read -r username budget rpm <<< "$user_config"

  echo -n "Creating key for $username (budget: \$$budget, rpm: $rpm)... "

  RESPONSE=$(curl -s -X POST "$LITELLM_URL/key/generate" \
    -H "Authorization: Bearer $MASTER_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"key_alias\": \"$username\",
      \"user_id\": \"$username\",
      \"max_budget\": $budget,
      \"rpm_limit\": $rpm,
      \"metadata\": {
        \"scope\": \"user:$username\",
        \"key_type\": \"user\",
        \"workspace_user\": \"$username\",
        \"created_by\": \"setup-litellm-keys\",
        \"purpose\": \"bootstrap key (setup script)\"
      }
    }" 2>/dev/null || echo "{}")

  KEY=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('key', ''))" 2>/dev/null || echo "")

  if [ -n "$KEY" ] && [ "$KEY" != "" ]; then
    echo -e "${GREEN}${KEY:0:20}...${NC}"
    echo "$username=$KEY" >> "$KEYS_FILE"
    KEYS_CREATED=$((KEYS_CREATED + 1))
  elif echo "$RESPONSE" | grep -q "already exists"; then
    echo -e "${YELLOW}exists (skipped)${NC}"
    KEYS_CREATED=$((KEYS_CREATED + 1))
  else
    echo -e "${RED}FAILED${NC}"
    echo "  Response: $RESPONSE"
    KEYS_FAILED=$((KEYS_FAILED + 1))
  fi
done

echo ""
echo -e "${BLUE}=== LiteLLM keys setup complete ===${NC}"
echo -e "  Keys created: ${GREEN}${KEYS_CREATED}${NC}"
if [ "$KEYS_FAILED" -gt 0 ]; then
  echo -e "  Keys failed:  ${RED}${KEYS_FAILED}${NC}"
fi
echo "  Keys file: $KEYS_FILE"
echo ""
echo -e "${BLUE}Usage:${NC}"
echo "  When creating a workspace, paste the user's key from $KEYS_FILE"
echo "  into the 'LiteLLM API Key' parameter field."
echo ""
echo "  To look up a user's key:"
echo "    grep 'username' $KEYS_FILE"
echo ""
echo "  To verify a key works:"
echo "    curl -s http://localhost:4000/v1/models -H 'Authorization: Bearer <key>'"
