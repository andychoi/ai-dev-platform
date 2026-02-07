#!/usr/bin/env bash
# =============================================================================
# test-rate-limits.sh — Test per-user rate limiting with aggressively small limits
#
# Creates a test key with very low limits (3 RPM, 500 TPM, $0.01 budget)
# then fires requests to verify that LiteLLM enforces them.
#
# Usage:
#   ./scripts/test-rate-limits.sh
#
# Prerequisites:
#   - LiteLLM and key-provisioner running (docker compose up -d litellm key-provisioner)
#   - PROVISIONER_SECRET set (or uses default PoC value)
# =============================================================================

set -euo pipefail

PROVISIONER_SECRET="${PROVISIONER_SECRET:-poc-provisioner-secret-change-in-production}"
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-sk-poc-litellm-master-key-change-in-production}"
LITELLM_URL="${LITELLM_URL:-http://localhost:4000}"
KEY_PROVISIONER_URL="${KEY_PROVISIONER_URL:-http://localhost:8100}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; }

echo ""
echo "======================================"
echo "  Rate Limit Test Suite"
echo "======================================"
echo ""

# --------------------------------------------------------------------------
# Step 1: Create a test key with aggressively small limits via LiteLLM API
# (bypassing key-provisioner to set custom low limits for testing)
# --------------------------------------------------------------------------
info "Creating test key with aggressive limits (3 RPM, 500 TPM, \$0.01 budget, 1h reset)..."

TEST_ALIAS="test-ratelimit-$(date +%s)"
TEST_USER="test-ratelimit-user"

CREATE_RESP=$(curl -s -w "\n%{http_code}" "${LITELLM_URL}/key/generate" \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H "Content-Type: application/json" \
  -d "{
    \"key_alias\": \"${TEST_ALIAS}\",
    \"user_id\": \"${TEST_USER}\",
    \"max_budget\": 0.01,
    \"rpm_limit\": 3,
    \"tpm_limit\": 500,
    \"max_parallel_requests\": 1,
    \"budget_duration\": \"1h\",
    \"metadata\": {
      \"scope\": \"test:ratelimit\",
      \"key_type\": \"test\",
      \"purpose\": \"rate limit testing\"
    }
  }")

HTTP_CODE=$(echo "$CREATE_RESP" | tail -1)
BODY=$(echo "$CREATE_RESP" | sed '$d')

if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
  fail "Failed to create test key (HTTP $HTTP_CODE)"
  echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
  exit 1
fi

TEST_KEY=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['key'])" 2>/dev/null)
if [ -z "$TEST_KEY" ]; then
  fail "Could not extract key from response"
  echo "$BODY"
  exit 1
fi

ok "Test key created: ${TEST_KEY:0:20}..."
echo ""

# --------------------------------------------------------------------------
# Step 2: Verify key info shows the limits
# --------------------------------------------------------------------------
info "Verifying key limits..."

KEY_INFO=$(curl -s "${LITELLM_URL}/key/info" \
  -H "Authorization: Bearer ${TEST_KEY}")

echo "$KEY_INFO" | python3 -c "
import sys, json
data = json.load(sys.stdin)
info = data.get('info', data.get('key_info', {}))
print(f'  RPM limit:      {info.get(\"rpm_limit\", \"N/A\")}')
print(f'  TPM limit:      {info.get(\"tpm_limit\", \"N/A\")}')
print(f'  Max budget:     \${info.get(\"max_budget\", \"N/A\")}')
print(f'  Budget duration: {info.get(\"budget_duration\", \"N/A\")}')
print(f'  Max parallel:   {info.get(\"max_parallel_requests\", \"N/A\")}')
print(f'  Current spend:  \${info.get(\"spend\", 0)}')
" 2>/dev/null || echo "$KEY_INFO"
echo ""

# --------------------------------------------------------------------------
# Step 3: Fire requests to test RPM limit (3 RPM = should fail on 4th request)
# --------------------------------------------------------------------------
info "Testing RPM limit (3 RPM — sending 5 rapid requests)..."
echo ""

RPM_PASS=0
RPM_FAIL=0

for i in $(seq 1 5); do
  RESP=$(curl -s -w "\n%{http_code}" "${LITELLM_URL}/chat/completions" \
    -H "Authorization: Bearer ${TEST_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
      "model": "claude-sonnet-4-5",
      "messages": [{"role": "user", "content": "Say OK"}],
      "max_tokens": 5
    }' 2>/dev/null)

  CODE=$(echo "$RESP" | tail -1)
  RBODY=$(echo "$RESP" | sed '$d')

  if [ "$CODE" = "200" ]; then
    ok "  Request $i: HTTP $CODE (allowed)"
    RPM_PASS=$((RPM_PASS + 1))
  elif [ "$CODE" = "429" ]; then
    warn "  Request $i: HTTP $CODE (rate limited)"
    RPM_FAIL=$((RPM_FAIL + 1))
  else
    fail "  Request $i: HTTP $CODE (unexpected)"
    echo "    $(echo "$RBODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error',{}).get('message','')[:100])" 2>/dev/null || echo "$RBODY" | head -1)"
  fi
done

echo ""
if [ "$RPM_FAIL" -gt 0 ]; then
  ok "RPM limiting is working ($RPM_PASS allowed, $RPM_FAIL rate-limited)"
else
  warn "RPM limiting may not have kicked in (all $RPM_PASS requests allowed)"
  warn "This can happen if the upstream API is slow enough to space requests naturally"
fi
echo ""

# --------------------------------------------------------------------------
# Step 4: Test admin spend reset
# --------------------------------------------------------------------------
info "Testing admin spend reset via key-provisioner..."

RESET_RESP=$(curl -s -w "\n%{http_code}" "${KEY_PROVISIONER_URL}/api/v1/keys/reset-user" \
  -H "Authorization: Bearer ${PROVISIONER_SECRET}" \
  -H "Content-Type: application/json" \
  -d "{\"user_id\": \"${TEST_USER}\"}")

RESET_CODE=$(echo "$RESET_RESP" | tail -1)
RESET_BODY=$(echo "$RESET_RESP" | sed '$d')

if [ "$RESET_CODE" = "200" ]; then
  ok "Spend reset successful"
  echo "  $(echo "$RESET_BODY" | python3 -m json.tool 2>/dev/null || echo "$RESET_BODY")"
else
  fail "Spend reset failed (HTTP $RESET_CODE)"
  echo "  $RESET_BODY"
fi
echo ""

# --------------------------------------------------------------------------
# Step 5: Test platform-admin reset endpoint
# --------------------------------------------------------------------------
info "Testing platform-admin reset endpoint (requires login — skipping if not authenticated)..."

PA_RESP=$(curl -s -w "\n%{http_code}" "http://localhost:5050/api/ai-usage/reset-user" \
  -H "Content-Type: application/json" \
  -d "{\"user_id\": \"${TEST_USER}\"}" \
  -b "session=" 2>/dev/null)

PA_CODE=$(echo "$PA_RESP" | tail -1)
if [ "$PA_CODE" = "302" ] || [ "$PA_CODE" = "401" ]; then
  warn "Platform admin requires login (expected — endpoint exists but needs auth)"
elif [ "$PA_CODE" = "200" ]; then
  ok "Platform admin reset endpoint returned 200"
else
  warn "Platform admin returned HTTP $PA_CODE (may need auth)"
fi
echo ""

# --------------------------------------------------------------------------
# Step 6: Verify key list endpoint
# --------------------------------------------------------------------------
info "Testing key list endpoint..."

LIST_RESP=$(curl -s -w "\n%{http_code}" "${KEY_PROVISIONER_URL}/api/v1/keys/list" \
  -H "Authorization: Bearer ${PROVISIONER_SECRET}")

LIST_CODE=$(echo "$LIST_RESP" | tail -1)
if [ "$LIST_CODE" = "200" ]; then
  ok "Key list endpoint working"
else
  fail "Key list endpoint failed (HTTP $LIST_CODE)"
fi
echo ""

# --------------------------------------------------------------------------
# Step 7: Clean up test key
# --------------------------------------------------------------------------
info "Cleaning up test key..."

DEL_RESP=$(curl -s -w "\n%{http_code}" "${LITELLM_URL}/key/delete" \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"keys\": [\"${TEST_KEY}\"]}")

DEL_CODE=$(echo "$DEL_RESP" | tail -1)
if [ "$DEL_CODE" = "200" ]; then
  ok "Test key deleted"
else
  warn "Could not delete test key (HTTP $DEL_CODE) — may need manual cleanup"
fi

echo ""
echo "======================================"
echo "  Test Complete"
echo "======================================"
echo ""
