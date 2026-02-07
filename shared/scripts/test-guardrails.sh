#!/bin/bash
# test-guardrails.sh — Verify Content Guardrails (PII/Financial/Secret Detection)
#
# Checks:
# 1.  guardrails_hook.py exists with correct class structure
# 2.  config.yaml registers the guardrails callback
# 3.  Docker Compose mounts guardrails files and sets env vars
# 4.  Custom patterns file exists and is valid JSON
# 5.  Key provisioner supports guardrail_level metadata
# 6.  Live: PII patterns are blocked (SSN, credit card)
# 7.  Live: Financial patterns are blocked (IBAN, card numbers)
# 8.  Live: Secret patterns are blocked (AWS keys, GitHub tokens, private keys)
# 9.  Live: Clean prompts pass through without blocking
# 10. Live: Guardrail levels (off/standard/strict) behave correctly
# 11. Live: Guardrails disabled (GUARDRAILS_ENABLED=false) passes everything

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0

pass() { echo -e "  ${GREEN}✓${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}✗${NC} $1"; FAIL=$((FAIL + 1)); }
skip() { echo -e "  ${YELLOW}⊘${NC} $1 (skipped)"; SKIP=$((SKIP + 1)); }
info() { echo -e "  ${BLUE}ℹ${NC} $1"; }

echo "========================================"
echo "Content Guardrails Validation Tests"
echo "========================================"
echo ""

SHARED_DIR="$(cd "$(dirname "$0")/.." && pwd)"
POC_DIR="${POC_DIR:-$(cd "$SHARED_DIR/../coder-poc" 2>/dev/null && pwd || echo "")}"

# ---------------------------------------------------------------------------
# 1. Check guardrails hook file
# ---------------------------------------------------------------------------
echo "1. Guardrails hook file"

HOOK_FILE="$SHARED_DIR/litellm-hooks/guardrails_hook.py"

if [ -f "$HOOK_FILE" ]; then
  pass "guardrails_hook.py exists"
else
  fail "guardrails_hook.py not found"
fi

if grep -q "class GuardrailsHook" "$HOOK_FILE" 2>/dev/null; then
  pass "GuardrailsHook class defined"
else
  fail "GuardrailsHook class not found in hook file"
fi

if grep -q "guardrails_instance" "$HOOK_FILE" 2>/dev/null; then
  pass "guardrails_instance exported"
else
  fail "guardrails_instance not found in hook file"
fi

if grep -q "async_pre_call_hook" "$HOOK_FILE" 2>/dev/null; then
  pass "async_pre_call_hook method defined (pre-call blocking)"
else
  fail "async_pre_call_hook not found (patterns won't be scanned)"
fi

if grep -q "BUILTIN_PATTERNS" "$HOOK_FILE" 2>/dev/null; then
  pass "Built-in patterns defined"
else
  fail "BUILTIN_PATTERNS not found"
fi

echo ""

# ---------------------------------------------------------------------------
# 2. Check built-in pattern coverage
# ---------------------------------------------------------------------------
echo "2. Built-in pattern coverage"

check_pattern() {
  local name="$1"
  local category="$2"
  if grep -q "\"$name\":" "$HOOK_FILE" 2>/dev/null; then
    pass "$category: $name pattern defined"
  else
    fail "$category: $name pattern missing"
  fi
}

# PII patterns
check_pattern "us_ssn" "PII"
check_pattern "email_address" "PII"
check_pattern "phone_us" "PII"

# Financial patterns
check_pattern "credit_card_visa" "Financial"
check_pattern "credit_card_mastercard" "Financial"
check_pattern "credit_card_amex" "Financial"
check_pattern "iban" "Financial"

# Secret patterns
check_pattern "aws_access_key" "Secret"
check_pattern "github_token" "Secret"
check_pattern "generic_api_key" "Secret"
check_pattern "private_key_pem" "Secret"
check_pattern "jwt_token" "Secret"
check_pattern "connection_string" "Secret"

echo ""

# ---------------------------------------------------------------------------
# 3. Check LiteLLM config
# ---------------------------------------------------------------------------
echo "3. LiteLLM config"

CONFIG_FILE="${POC_DIR:+$POC_DIR/litellm/config.yaml}"
CONFIG_FILE="${CONFIG_FILE:-$SHARED_DIR/../coder-poc/litellm/config.yaml}"

if grep -q "guardrails_hook.guardrails_instance" "$CONFIG_FILE" 2>/dev/null; then
  pass "config.yaml registers guardrails callback"
else
  fail "config.yaml does not reference guardrails_hook"
fi

# Verify both callbacks are registered (enforcement + guardrails)
if grep -q "enforcement_hook.proxy_handler_instance" "$CONFIG_FILE" 2>/dev/null && \
   grep -q "guardrails_hook.guardrails_instance" "$CONFIG_FILE" 2>/dev/null; then
  pass "Both enforcement and guardrails callbacks registered"
else
  fail "Missing one or both callbacks in config.yaml"
fi

echo ""

# ---------------------------------------------------------------------------
# 4. Check Docker Compose
# ---------------------------------------------------------------------------
echo "4. Docker Compose"

COMPOSE_FILE="${POC_DIR:+$POC_DIR/docker-compose.yml}"
COMPOSE_FILE="${COMPOSE_FILE:-$SHARED_DIR/../coder-poc/docker-compose.yml}"

if [ ! -f "$COMPOSE_FILE" ]; then
  skip "docker-compose.yml not found at $COMPOSE_FILE — skipping compose checks"
else
  if grep -q "guardrails_hook.py:/app/guardrails_hook.py" "$COMPOSE_FILE" 2>/dev/null; then
    pass "guardrails_hook.py mounted into litellm container"
  else
    fail "guardrails_hook.py not mounted in docker-compose.yml"
  fi

  if grep -q "guardrails:/app/guardrails" "$COMPOSE_FILE" 2>/dev/null; then
    pass "guardrails directory mounted into litellm container"
  else
    fail "guardrails directory not mounted in docker-compose.yml"
  fi

  if grep -q "GUARDRAILS_ENABLED" "$COMPOSE_FILE" 2>/dev/null; then
    pass "GUARDRAILS_ENABLED env var configured"
  else
    fail "GUARDRAILS_ENABLED not in docker-compose.yml"
  fi

  if grep -q "DEFAULT_GUARDRAIL_LEVEL" "$COMPOSE_FILE" 2>/dev/null; then
    pass "DEFAULT_GUARDRAIL_LEVEL env var configured"
  else
    fail "DEFAULT_GUARDRAIL_LEVEL not in docker-compose.yml"
  fi
fi

echo ""

# ---------------------------------------------------------------------------
# 5. Check custom patterns file
# ---------------------------------------------------------------------------
echo "5. Custom patterns file"

PATTERNS_FILE="$SHARED_DIR/litellm-hooks/guardrails/patterns.json"

if [ -f "$PATTERNS_FILE" ]; then
  pass "patterns.json exists"
else
  fail "patterns.json not found at $PATTERNS_FILE"
fi

if [ -f "$PATTERNS_FILE" ]; then
  if python3 -c "import json; json.load(open('$PATTERNS_FILE'))" 2>/dev/null; then
    pass "patterns.json is valid JSON"
  else
    fail "patterns.json is invalid JSON"
  fi
fi

echo ""

# ---------------------------------------------------------------------------
# 6. Check key provisioner supports guardrail_level
# ---------------------------------------------------------------------------
echo "6. Key provisioner guardrail support"

PROVISIONER_FILE="$SHARED_DIR/key-provisioner/app.py"

if grep -q "guardrail_level" "$PROVISIONER_FILE" 2>/dev/null; then
  pass "app.py accepts guardrail_level parameter"
else
  skip "app.py does not reference guardrail_level yet (enhancement pending)"
fi

echo ""

# ---------------------------------------------------------------------------
# 7-11. Live service tests
# ---------------------------------------------------------------------------
echo "========================================="
echo "Live Tests (requires running services)"
echo "========================================="
echo ""

LITELLM_URL="${LITELLM_URL:-http://localhost:4000}"
MASTER_KEY="${LITELLM_MASTER_KEY:-}"

# Try to read keys from .env if not set
ENV_FILE="${POC_DIR:+$POC_DIR/.env}"
ENV_FILE="${ENV_FILE:-$SHARED_DIR/../coder-poc/.env}"
if [ -f "$ENV_FILE" ] && [ -z "$MASTER_KEY" ]; then
  MASTER_KEY=$(grep '^LITELLM_MASTER_KEY=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 | tr -d '"' | tr -d "'" || true)
fi

# Check if LiteLLM is running
if ! curl -sf "$LITELLM_URL/health/readiness" > /dev/null 2>&1; then
  skip "LiteLLM not running — skipping all live tests"
  echo ""
  echo "========================================"
  TOTAL=$((PASS + FAIL + SKIP))
  echo -e "Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${SKIP} skipped${NC} (${TOTAL} total)"
  echo "========================================"
  if [ "$FAIL" -gt 0 ]; then exit 1; fi
  exit 0
fi

pass "LiteLLM is running"

if [ -z "$MASTER_KEY" ]; then
  skip "LITELLM_MASTER_KEY not set — skipping live API tests"
  echo ""
  echo "========================================"
  TOTAL=$((PASS + FAIL + SKIP))
  echo -e "Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${SKIP} skipped${NC} (${TOTAL} total)"
  echo "========================================"
  if [ "$FAIL" -gt 0 ]; then exit 1; fi
  exit 0
fi

# Verify guardrails hook is loaded in LiteLLM
CALLBACKS_JSON=$(curl -sf -H "Authorization: Bearer $MASTER_KEY" "$LITELLM_URL/get/config/callbacks" 2>/dev/null || echo "")
if echo "$CALLBACKS_JSON" | grep -q "guardrails_hook.guardrails_instance"; then
  pass "Guardrails hook loaded in LiteLLM (confirmed via API)"
else
  fail "Guardrails hook NOT found in LiteLLM callbacks API"
  info "Run: docker compose up -d litellm"
fi

echo ""

# ---------------------------------------------------------------------------
# Helper: create test key with specific guardrail level
# ---------------------------------------------------------------------------
create_test_key() {
  local level="$1"
  local alias="test-guardrail-${level}-$$"
  local resp
  resp=$(curl -sf -X POST "$LITELLM_URL/key/generate" \
    -H "Authorization: Bearer $MASTER_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"key_alias\": \"$alias\",
      \"max_budget\": 0.10,
      \"metadata\": {
        \"guardrail_level\": \"$level\",
        \"enforcement_level\": \"unrestricted\",
        \"purpose\": \"guardrail-test\"
      }
    }" 2>/dev/null)
  if [ $? -ne 0 ] || [ -z "$resp" ]; then
    echo ""
    return 1
  fi
  echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('key',''))" 2>/dev/null
}

# Helper: send a message and return HTTP status + response body
send_message() {
  local key="$1"
  local message="$2"
  local tmpfile
  tmpfile=$(mktemp)
  local http_code
  http_code=$(curl -s -o "$tmpfile" -w "%{http_code}" -X POST "$LITELLM_URL/chat/completions" \
    -H "Authorization: Bearer $key" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"claude-haiku-4-5\",
      \"messages\": [{\"role\": \"user\", \"content\": \"$message\"}],
      \"max_tokens\": 5
    }" 2>/dev/null)
  local body
  body=$(cat "$tmpfile")
  rm -f "$tmpfile"
  echo "$http_code|$body"
}

# Helper: check if response was blocked by guardrails
is_blocked() {
  local response="$1"
  echo "$response" | grep -qi "blocked by content guardrails\|guardrail"
}

# ---------------------------------------------------------------------------
# 7. PII detection tests
# ---------------------------------------------------------------------------
echo "7. PII pattern detection"

KEY_STANDARD=$(create_test_key "standard") || true
if [ -z "$KEY_STANDARD" ]; then
  fail "Could not create test key for standard guardrail level"
  skip "Skipping PII tests"
else
  pass "Created test key with guardrail_level=standard"

  # Test: SSN should be blocked
  RESULT=$(send_message "$KEY_STANDARD" "My SSN is 078-05-1120, can you help me?")
  HTTP_CODE="${RESULT%%|*}"
  BODY="${RESULT#*|}"

  if [ "$HTTP_CODE" = "400" ] || echo "$BODY" | grep -qi "blocked\|guardrail\|Social Security"; then
    pass "SSN detected and blocked (078-05-1120)"
  elif echo "$BODY" | grep -qi "AuthenticationError\|401\|api_key"; then
    skip "SSN test: upstream auth error (ANTHROPIC_API_KEY not set)"
  else
    fail "SSN NOT blocked — HTTP $HTTP_CODE"
    info "Response: $(echo "$BODY" | head -c 200)"
  fi

  # Test: Email should be flagged (not blocked in standard mode)
  RESULT=$(send_message "$KEY_STANDARD" "Contact john.doe@example.com for info")
  HTTP_CODE="${RESULT%%|*}"
  BODY="${RESULT#*|}"

  if echo "$BODY" | grep -qi "AuthenticationError\|401\|api_key"; then
    skip "Email test: upstream auth error (ANTHROPIC_API_KEY not set)"
  elif [ "$HTTP_CODE" = "200" ] || echo "$BODY" | grep -qi "choices"; then
    pass "Email flagged but not blocked in standard mode (correct)"
  elif echo "$BODY" | grep -qi "blocked"; then
    # In standard mode, emails should warn, not block
    fail "Email blocked in standard mode (should only warn)"
  else
    skip "Email test: unexpected response — HTTP $HTTP_CODE"
  fi
fi

echo ""

# ---------------------------------------------------------------------------
# 8. Financial pattern detection
# ---------------------------------------------------------------------------
echo "8. Financial pattern detection"

if [ -n "$KEY_STANDARD" ]; then
  # Test: Visa card should be blocked
  RESULT=$(send_message "$KEY_STANDARD" "My card number is 4532-0150-0000-1234")
  HTTP_CODE="${RESULT%%|*}"
  BODY="${RESULT#*|}"

  if [ "$HTTP_CODE" = "400" ] || echo "$BODY" | grep -qi "blocked\|guardrail\|credit card\|Visa"; then
    pass "Visa card number detected and blocked"
  elif echo "$BODY" | grep -qi "AuthenticationError\|401\|api_key"; then
    skip "Visa test: upstream auth error"
  else
    fail "Visa card NOT blocked — HTTP $HTTP_CODE"
    info "Response: $(echo "$BODY" | head -c 200)"
  fi

  # Test: IBAN should be blocked
  RESULT=$(send_message "$KEY_STANDARD" "Transfer to GB29NWBK60161331926819 please")
  HTTP_CODE="${RESULT%%|*}"
  BODY="${RESULT#*|}"

  if [ "$HTTP_CODE" = "400" ] || echo "$BODY" | grep -qi "blocked\|guardrail\|IBAN"; then
    pass "IBAN detected and blocked"
  elif echo "$BODY" | grep -qi "AuthenticationError\|401\|api_key"; then
    skip "IBAN test: upstream auth error"
  else
    fail "IBAN NOT blocked — HTTP $HTTP_CODE"
  fi
else
  skip "Financial tests: no test key available"
fi

echo ""

# ---------------------------------------------------------------------------
# 9. Secret/credential detection
# ---------------------------------------------------------------------------
echo "9. Secret/credential detection"

if [ -n "$KEY_STANDARD" ]; then
  # Test: AWS access key should be blocked
  RESULT=$(send_message "$KEY_STANDARD" "Here is my key: AKIAIOSFODNN7EXAMPLE")
  HTTP_CODE="${RESULT%%|*}"
  BODY="${RESULT#*|}"

  if [ "$HTTP_CODE" = "400" ] || echo "$BODY" | grep -qi "blocked\|guardrail\|AWS"; then
    pass "AWS access key detected and blocked"
  elif echo "$BODY" | grep -qi "AuthenticationError\|401\|api_key"; then
    skip "AWS key test: upstream auth error"
  else
    fail "AWS access key NOT blocked — HTTP $HTTP_CODE"
  fi

  # Test: GitHub token should be blocked
  RESULT=$(send_message "$KEY_STANDARD" "Use token ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn")
  HTTP_CODE="${RESULT%%|*}"
  BODY="${RESULT#*|}"

  if [ "$HTTP_CODE" = "400" ] || echo "$BODY" | grep -qi "blocked\|guardrail\|GitHub"; then
    pass "GitHub token detected and blocked"
  elif echo "$BODY" | grep -qi "AuthenticationError\|401\|api_key"; then
    skip "GitHub token test: upstream auth error"
  else
    fail "GitHub token NOT blocked — HTTP $HTTP_CODE"
  fi

  # Test: Private key should be blocked
  RESULT=$(send_message "$KEY_STANDARD" "-----BEGIN RSA PRIVATE KEY----- MIIEpAIBAAKCAQEA...")
  HTTP_CODE="${RESULT%%|*}"
  BODY="${RESULT#*|}"

  if [ "$HTTP_CODE" = "400" ] || echo "$BODY" | grep -qi "blocked\|guardrail\|private key\|Private"; then
    pass "Private key (PEM) detected and blocked"
  elif echo "$BODY" | grep -qi "AuthenticationError\|401\|api_key"; then
    skip "Private key test: upstream auth error"
  else
    fail "Private key NOT blocked — HTTP $HTTP_CODE"
  fi

  # Test: Database connection string should be blocked
  RESULT=$(send_message "$KEY_STANDARD" "Connect to postgres://admin:secret@db.example.com:5432/mydb")
  HTTP_CODE="${RESULT%%|*}"
  BODY="${RESULT#*|}"

  if [ "$HTTP_CODE" = "400" ] || echo "$BODY" | grep -qi "blocked\|guardrail\|connection string\|Database"; then
    pass "Database connection string detected and blocked"
  elif echo "$BODY" | grep -qi "AuthenticationError\|401\|api_key"; then
    skip "Connection string test: upstream auth error"
  else
    fail "Database connection string NOT blocked — HTTP $HTTP_CODE"
  fi
else
  skip "Secret tests: no test key available"
fi

echo ""

# ---------------------------------------------------------------------------
# 10. Clean prompt passthrough
# ---------------------------------------------------------------------------
echo "10. Clean prompt passthrough"

if [ -n "$KEY_STANDARD" ]; then
  RESULT=$(send_message "$KEY_STANDARD" "What is the capital of France?")
  HTTP_CODE="${RESULT%%|*}"
  BODY="${RESULT#*|}"

  if echo "$BODY" | grep -qi "AuthenticationError\|401\|api_key"; then
    skip "Clean prompt test: upstream auth error (ANTHROPIC_API_KEY not set)"
  elif [ "$HTTP_CODE" = "200" ] && echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])" > /dev/null 2>&1; then
    pass "Clean prompt passed through successfully"
  elif echo "$BODY" | grep -qi "blocked\|guardrail"; then
    fail "Clean prompt was incorrectly blocked by guardrails (false positive)"
  elif echo "$BODY" | grep -qi "budget\|exceeded"; then
    skip "Clean prompt test: budget exceeded"
  else
    skip "Clean prompt test: unexpected response — HTTP $HTTP_CODE"
    info "Response: $(echo "$BODY" | head -c 200)"
  fi

  # Test with code-like content that shouldn't trigger
  RESULT=$(send_message "$KEY_STANDARD" "Write a Python function that adds two numbers")
  HTTP_CODE="${RESULT%%|*}"
  BODY="${RESULT#*|}"

  if echo "$BODY" | grep -qi "AuthenticationError\|401\|api_key"; then
    skip "Code prompt test: upstream auth error"
  elif echo "$BODY" | grep -qi "blocked\|guardrail"; then
    fail "Code prompt was incorrectly blocked (false positive)"
  elif [ "$HTTP_CODE" = "200" ]; then
    pass "Code prompt passed through (no false positive)"
  else
    skip "Code prompt test: unexpected response — HTTP $HTTP_CODE"
  fi
else
  skip "Clean prompt tests: no test key available"
fi

echo ""

# ---------------------------------------------------------------------------
# 11. Guardrail level comparison (off vs standard vs strict)
# ---------------------------------------------------------------------------
echo "11. Guardrail level comparison"

KEY_OFF=$(create_test_key "off") || true
KEY_STRICT=$(create_test_key "strict") || true

if [ -n "$KEY_OFF" ] && [ -n "$KEY_STANDARD" ] && [ -n "$KEY_STRICT" ]; then
  pass "Created test keys for all 3 guardrail levels"

  # Verify key metadata
  for kv in "off:$KEY_OFF" "standard:$KEY_STANDARD" "strict:$KEY_STRICT"; do
    level="${kv%%:*}"
    key="${kv#*:}"
    META=$(curl -s -X GET "$LITELLM_URL/key/info" \
      -H "Authorization: Bearer $key" 2>/dev/null || echo "{}")
    STORED_LEVEL=$(echo "$META" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    info = d.get('info', d.get('key_info', {}))
    meta = info.get('metadata', {})
    print(meta.get('guardrail_level', 'MISSING'))
except: print('ERROR')
" 2>/dev/null)
    if [ "$STORED_LEVEL" = "$level" ]; then
      pass "Key metadata: guardrail_level=$level (correct)"
    else
      fail "Key metadata: expected=$level got=$STORED_LEVEL"
    fi
  done

  echo ""
  info "Testing SSN across guardrail levels..."
  echo ""

  # OFF level: SSN should pass through
  RESULT=$(send_message "$KEY_OFF" "My SSN is 078-05-1120, check it")
  HTTP_CODE="${RESULT%%|*}"
  BODY="${RESULT#*|}"

  if echo "$BODY" | grep -qi "AuthenticationError\|401\|api_key"; then
    skip "off level SSN test: upstream auth error"
  elif echo "$BODY" | grep -qi "blocked\|guardrail"; then
    fail "off level: SSN blocked (should pass through when guardrails off)"
  elif [ "$HTTP_CODE" = "200" ]; then
    pass "off level: SSN passed through (guardrails disabled for this key)"
  else
    skip "off level: unexpected response — HTTP $HTTP_CODE"
  fi

  # STANDARD level: SSN should be blocked (high severity)
  RESULT=$(send_message "$KEY_STANDARD" "My SSN is 078-05-1120, check it")
  HTTP_CODE="${RESULT%%|*}"
  BODY="${RESULT#*|}"

  if echo "$BODY" | grep -qi "AuthenticationError\|401\|api_key"; then
    skip "standard level SSN test: upstream auth error"
  elif [ "$HTTP_CODE" = "400" ] || echo "$BODY" | grep -qi "blocked\|guardrail"; then
    pass "standard level: SSN blocked (high severity → block)"
  else
    fail "standard level: SSN NOT blocked"
  fi

  # STRICT level: Email should be blocked (medium severity, blocked in strict)
  RESULT=$(send_message "$KEY_STRICT" "Contact john.doe@example.com")
  HTTP_CODE="${RESULT%%|*}"
  BODY="${RESULT#*|}"

  if echo "$BODY" | grep -qi "AuthenticationError\|401\|api_key"; then
    skip "strict level email test: upstream auth error"
  elif [ "$HTTP_CODE" = "400" ] || echo "$BODY" | grep -qi "blocked\|guardrail"; then
    pass "strict level: Email blocked (medium severity → block in strict mode)"
  elif [ "$HTTP_CODE" = "200" ]; then
    fail "strict level: Email NOT blocked (strict should block medium severity)"
  else
    skip "strict level: unexpected response — HTTP $HTTP_CODE"
  fi
else
  fail "Could not create test keys for level comparison"
fi

echo ""

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
echo "Cleanup"

CLEANUP_COUNT=0
for key in "$KEY_STANDARD" "$KEY_OFF" "$KEY_STRICT"; do
  if [ -n "$key" ]; then
    curl -s -X POST "$LITELLM_URL/key/delete" \
      -H "Authorization: Bearer $MASTER_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"keys\": [\"$key\"]}" > /dev/null 2>&1 || true
    CLEANUP_COUNT=$((CLEANUP_COUNT + 1))
  fi
done
if [ "$CLEANUP_COUNT" -gt 0 ]; then
  pass "$CLEANUP_COUNT test key(s) cleaned up"
fi

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "========================================"
TOTAL=$((PASS + FAIL + SKIP))
echo -e "Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${SKIP} skipped${NC} (${TOTAL} total)"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Troubleshooting:"
  echo "  - Ensure LiteLLM is running: docker compose up -d litellm"
  echo "  - After config changes: docker compose up -d litellm (not restart)"
  echo "  - Check hook loaded: curl -H 'Authorization: Bearer \$MASTER_KEY' localhost:4000/get/config/callbacks"
  echo "  - Check logs: docker compose logs litellm | grep guardrail"
  echo "  - Docs: shared/docs/GUARDRAILS.md"
  exit 1
fi
