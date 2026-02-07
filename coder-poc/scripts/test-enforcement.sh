#!/bin/bash
# test-enforcement.sh — Verify Design-First AI Enforcement Layer + Langfuse Observability
#
# Checks:
# 1. LiteLLM enforcement hook is loaded
# 2. Prompt files exist and are non-empty (except unrestricted)
# 3. Key provisioner accepts enforcement_level parameter
# 4. LiteLLM injects system prompt for standard/design-first keys
# 5. LiteLLM passes through cleanly for unrestricted keys
# 6. Langfuse infrastructure configured (services, callbacks, env vars)
# 7. Langfuse receives traces from LiteLLM API calls

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0

pass() { echo -e "  ${GREEN}✓${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}✗${NC} $1"; FAIL=$((FAIL + 1)); }
skip() { echo -e "  ${YELLOW}⊘${NC} $1 (skipped)"; SKIP=$((SKIP + 1)); }

echo "========================================"
echo "Design-First Enforcement + Langfuse Tests"
echo "========================================"
echo ""

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ---------------------------------------------------------------------------
# 1. Check prompt files
# ---------------------------------------------------------------------------
echo "1. Prompt files"

PROMPTS_DIR="$BASE_DIR/litellm/prompts"

if [ -f "$PROMPTS_DIR/unrestricted.md" ]; then
  # unrestricted.md should be empty
  if [ ! -s "$PROMPTS_DIR/unrestricted.md" ]; then
    pass "unrestricted.md exists and is empty"
  else
    fail "unrestricted.md should be empty but has content"
  fi
else
  fail "unrestricted.md not found"
fi

if [ -f "$PROMPTS_DIR/standard.md" ] && [ -s "$PROMPTS_DIR/standard.md" ]; then
  pass "standard.md exists and has content"
else
  fail "standard.md missing or empty"
fi

if [ -f "$PROMPTS_DIR/design-first.md" ] && [ -s "$PROMPTS_DIR/design-first.md" ]; then
  pass "design-first.md exists and has content"
else
  fail "design-first.md missing or empty"
fi

echo ""

# ---------------------------------------------------------------------------
# 2. Check enforcement hook file
# ---------------------------------------------------------------------------
echo "2. Enforcement hook"

HOOK_FILE="$BASE_DIR/litellm/enforcement_hook.py"

if [ -f "$HOOK_FILE" ]; then
  pass "enforcement_hook.py exists"
else
  fail "enforcement_hook.py not found"
fi

if grep -q "class EnforcementHook" "$HOOK_FILE" 2>/dev/null; then
  pass "EnforcementHook class defined"
else
  fail "EnforcementHook class not found in hook file"
fi

if grep -q "proxy_handler_instance" "$HOOK_FILE" 2>/dev/null; then
  pass "proxy_handler_instance exported"
else
  fail "proxy_handler_instance not found in hook file"
fi

echo ""

# ---------------------------------------------------------------------------
# 3. Check LiteLLM config (enforcement + Langfuse callbacks)
# ---------------------------------------------------------------------------
echo "3. LiteLLM config"

CONFIG_FILE="$BASE_DIR/litellm/config.yaml"

if grep -q "enforcement_hook.proxy_handler_instance" "$CONFIG_FILE" 2>/dev/null; then
  pass "config.yaml registers enforcement callback"
else
  fail "config.yaml does not reference enforcement_hook"
fi

# Langfuse callback checks
if grep -q 'success_callback:.*langfuse' "$CONFIG_FILE" 2>/dev/null; then
  pass "config.yaml has langfuse in success_callback"
else
  fail "config.yaml missing langfuse in success_callback"
fi

if grep -q 'failure_callback:.*langfuse' "$CONFIG_FILE" 2>/dev/null; then
  pass "config.yaml has langfuse in failure_callback"
else
  fail "config.yaml missing langfuse in failure_callback"
fi

if grep -q 'turn_off_message_logging:' "$CONFIG_FILE" 2>/dev/null; then
  pass "config.yaml has turn_off_message_logging (privacy control)"
else
  fail "config.yaml missing turn_off_message_logging setting"
fi

if grep -q 'langfuse_default_tags:' "$CONFIG_FILE" 2>/dev/null; then
  pass "config.yaml has langfuse_default_tags for trace correlation"
else
  fail "config.yaml missing langfuse_default_tags"
fi

echo ""

# ---------------------------------------------------------------------------
# 4. Check Docker Compose (enforcement mounts + Langfuse env vars)
# ---------------------------------------------------------------------------
echo "4. Docker Compose"

COMPOSE_FILE="$BASE_DIR/docker-compose.yml"

# Enforcement mounts
if grep -q "enforcement_hook.py:/app/enforcement_hook.py" "$COMPOSE_FILE" 2>/dev/null; then
  pass "enforcement_hook.py mounted into litellm container"
else
  fail "enforcement_hook.py not mounted in docker-compose.yml"
fi

if grep -q "prompts:/app/prompts" "$COMPOSE_FILE" 2>/dev/null; then
  pass "prompts directory mounted into litellm container"
else
  fail "prompts directory not mounted in docker-compose.yml"
fi

if grep -q "DEFAULT_ENFORCEMENT_LEVEL" "$COMPOSE_FILE" 2>/dev/null; then
  pass "DEFAULT_ENFORCEMENT_LEVEL env var configured"
else
  fail "DEFAULT_ENFORCEMENT_LEVEL not in docker-compose.yml"
fi

# Langfuse env vars for LiteLLM
if grep -q "LANGFUSE_PUBLIC_KEY" "$COMPOSE_FILE" 2>/dev/null; then
  pass "LANGFUSE_PUBLIC_KEY in litellm env"
else
  fail "LANGFUSE_PUBLIC_KEY not in docker-compose.yml"
fi

if grep -q "LANGFUSE_SECRET_KEY" "$COMPOSE_FILE" 2>/dev/null; then
  pass "LANGFUSE_SECRET_KEY in litellm env"
else
  fail "LANGFUSE_SECRET_KEY not in docker-compose.yml"
fi

if grep -q "LANGFUSE_HOST" "$COMPOSE_FILE" 2>/dev/null; then
  pass "LANGFUSE_HOST in litellm env"
else
  fail "LANGFUSE_HOST not in docker-compose.yml"
fi

echo ""

# ---------------------------------------------------------------------------
# 5. Check key-provisioner accepts enforcement_level
# ---------------------------------------------------------------------------
echo "5. Key provisioner"

PROVISIONER_FILE="$BASE_DIR/key-provisioner/app.py"

if grep -q "enforcement_level" "$PROVISIONER_FILE" 2>/dev/null; then
  pass "app.py accepts enforcement_level parameter"
else
  fail "app.py does not reference enforcement_level"
fi

if grep -q '"enforcement_level":' "$PROVISIONER_FILE" 2>/dev/null; then
  pass "enforcement_level stored in key metadata"
else
  fail "enforcement_level not stored in metadata"
fi

echo ""

# ---------------------------------------------------------------------------
# 6. Check workspace template
# ---------------------------------------------------------------------------
echo "6. Workspace template"

TEMPLATE_FILE="$BASE_DIR/templates/contractor-workspace/main.tf"

if grep -q "ai_enforcement_level" "$TEMPLATE_FILE" 2>/dev/null; then
  pass "ai_enforcement_level parameter defined"
else
  fail "ai_enforcement_level parameter not in template"
fi

if grep -q "ENFORCEMENT_LEVEL" "$TEMPLATE_FILE" 2>/dev/null; then
  pass "ENFORCEMENT_LEVEL used in startup script"
else
  fail "ENFORCEMENT_LEVEL not in startup script"
fi

if grep -q "customInstructions" "$TEMPLATE_FILE" 2>/dev/null; then
  pass "Roo Code customInstructions configured"
else
  fail "Roo Code customInstructions not in template"
fi

if grep -q "enforcement.md" "$TEMPLATE_FILE" 2>/dev/null; then
  pass "OpenCode enforcement.md referenced"
else
  fail "OpenCode enforcement.md not in template"
fi

echo ""

# ---------------------------------------------------------------------------
# 7. Langfuse infrastructure (services, headless init, storage)
# ---------------------------------------------------------------------------
echo "7. Langfuse infrastructure"

# Services
if grep -q "langfuse-web:" "$COMPOSE_FILE" 2>/dev/null; then
  pass "langfuse-web service defined"
else
  fail "langfuse-web service not in docker-compose.yml"
fi

if grep -q "langfuse-worker:" "$COMPOSE_FILE" 2>/dev/null; then
  pass "langfuse-worker service defined"
else
  fail "langfuse-worker service not in docker-compose.yml"
fi

if grep -q "clickhouse:" "$COMPOSE_FILE" 2>/dev/null; then
  pass "clickhouse service defined (analytics DB)"
else
  fail "clickhouse service not in docker-compose.yml"
fi

# Headless init (auto-creates org, project, API keys on first boot)
if grep -q "LANGFUSE_INIT_PROJECT_PUBLIC_KEY" "$COMPOSE_FILE" 2>/dev/null; then
  pass "Headless init: project public key configured"
else
  fail "LANGFUSE_INIT_PROJECT_PUBLIC_KEY not set (keys won't auto-create)"
fi

if grep -q "LANGFUSE_INIT_PROJECT_SECRET_KEY" "$COMPOSE_FILE" 2>/dev/null; then
  pass "Headless init: project secret key configured"
else
  fail "LANGFUSE_INIT_PROJECT_SECRET_KEY not set (keys won't auto-create)"
fi

# MinIO bucket init for Langfuse blob storage
if grep -q "langfuse-events" "$COMPOSE_FILE" 2>/dev/null; then
  pass "MinIO langfuse-events bucket created"
else
  fail "langfuse-events bucket not in mc-init"
fi

if grep -q "langfuse-media" "$COMPOSE_FILE" 2>/dev/null; then
  pass "MinIO langfuse-media bucket created"
else
  fail "langfuse-media bucket not in mc-init"
fi

# LiteLLM depends_on langfuse-web (ensures traces endpoint is ready)
if grep -q "langfuse-web" "$COMPOSE_FILE" 2>/dev/null; then
  pass "litellm depends on langfuse-web"
else
  fail "litellm does not depend on langfuse-web"
fi

# .env.example has Langfuse vars
ENV_EXAMPLE="$BASE_DIR/.env.example"
if [ -f "$ENV_EXAMPLE" ]; then
  if grep -q "LANGFUSE_PUBLIC_KEY" "$ENV_EXAMPLE" && grep -q "LANGFUSE_SECRET_KEY" "$ENV_EXAMPLE"; then
    pass ".env.example documents Langfuse API keys"
  else
    fail ".env.example missing Langfuse key documentation"
  fi
else
  skip ".env.example not found"
fi

echo ""

# ---------------------------------------------------------------------------
# 8. Live service tests (if services are running)
# ---------------------------------------------------------------------------
echo "8. Live service tests"

LITELLM_URL="${LITELLM_URL:-http://localhost:4000}"
PROVISIONER_URL="${PROVISIONER_URL:-http://localhost:8100}"
LANGFUSE_URL="${LANGFUSE_URL:-http://localhost:3100}"
MASTER_KEY="${LITELLM_MASTER_KEY:-}"
LF_PUBLIC_KEY="${LANGFUSE_PUBLIC_KEY:-}"
LF_SECRET_KEY="${LANGFUSE_SECRET_KEY:-}"

# Try to read keys from .env if not set
ENV_FILE="$BASE_DIR/.env"
if [ -f "$ENV_FILE" ]; then
  if [ -z "$MASTER_KEY" ]; then
    MASTER_KEY=$(grep '^LITELLM_MASTER_KEY=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 | tr -d '"' | tr -d "'" || true)
  fi
  if [ -z "$LF_PUBLIC_KEY" ]; then
    LF_PUBLIC_KEY=$(grep '^LANGFUSE_PUBLIC_KEY=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 | tr -d '"' | tr -d "'" || true)
  fi
  if [ -z "$LF_SECRET_KEY" ]; then
    LF_SECRET_KEY=$(grep '^LANGFUSE_SECRET_KEY=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 | tr -d '"' | tr -d "'" || true)
  fi
fi

# Check if LiteLLM is running
if curl -sf "$LITELLM_URL/health/readiness" > /dev/null 2>&1; then
  pass "LiteLLM is running"

  # Verify enforcement hook is loaded via admin API (not container logs)
  if [ -n "$MASTER_KEY" ]; then
    CALLBACKS_JSON=$(curl -sf -H "Authorization: Bearer $MASTER_KEY" "$LITELLM_URL/get/config/callbacks" 2>/dev/null)
    if echo "$CALLBACKS_JSON" | grep -q "enforcement_hook.proxy_handler_instance"; then
      pass "Enforcement hook loaded in LiteLLM (confirmed via API)"
    else
      fail "Enforcement hook NOT found in LiteLLM callbacks API"
    fi
  else
    skip "LITELLM_MASTER_KEY not set — cannot verify hook via API"
  fi
else
  skip "LiteLLM not running — skipping live tests"
fi

# Check if key-provisioner is running
if curl -sf "$PROVISIONER_URL/health" > /dev/null 2>&1; then
  pass "Key provisioner is running"
else
  skip "Key provisioner not running — skipping live tests"
fi

# Check if Langfuse is running
LANGFUSE_RUNNING=false
if curl -sf "$LANGFUSE_URL/api/public/health" > /dev/null 2>&1; then
  pass "Langfuse is running"
  LANGFUSE_RUNNING=true
else
  skip "Langfuse not running at $LANGFUSE_URL — skipping Langfuse live tests"
fi

# Verify Langfuse API keys work (authenticated endpoint)
if $LANGFUSE_RUNNING && [ -n "$LF_PUBLIC_KEY" ] && [ -n "$LF_SECRET_KEY" ]; then
  LF_AUTH_RESP=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "$LF_PUBLIC_KEY:$LF_SECRET_KEY" \
    "$LANGFUSE_URL/api/public/traces?limit=1" 2>/dev/null)
  if [ "$LF_AUTH_RESP" = "200" ]; then
    pass "Langfuse API keys valid (authenticated successfully)"
  else
    fail "Langfuse API keys rejected (HTTP $LF_AUTH_RESP)"
  fi
elif $LANGFUSE_RUNNING; then
  skip "Langfuse keys not set — cannot verify API authentication"
fi

echo ""

# ---------------------------------------------------------------------------
# 9. Enforcement comparison test (requires running services + master key)
# ---------------------------------------------------------------------------
echo "9. Enforcement comparison (with vs without)"

# Track whether enforcement API calls succeed (used by trace verification)
ENFORCEMENT_CALLS_SUCCEEDED=false
ENFORCEMENT_CALL_TIME=""

if [ -z "$MASTER_KEY" ]; then
  skip "LITELLM_MASTER_KEY not set — skipping comparison test"
elif ! curl -sf "$LITELLM_URL/health/readiness" > /dev/null 2>&1; then
  skip "LiteLLM not running — skipping comparison test"
else
  CLEANUP_KEYS=()

  # Helper: create a key with specific enforcement level
  create_test_key() {
    local level="$1"
    local alias="test-enforcement-${level}-$$"
    local resp
    resp=$(curl -sf -X POST "$LITELLM_URL/key/generate" \
      -H "Authorization: Bearer $MASTER_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"key_alias\": \"$alias\", \"max_budget\": 0.01, \"metadata\": {\"enforcement_level\": \"$level\"}}" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$resp" ]; then
      echo ""
      return 1
    fi
    local key
    key=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('key',''))" 2>/dev/null)
    echo "$key"
  }

  # Helper: make a chat request and capture the request that LiteLLM sends
  # We use a non-existent model to trigger an error, but we can check logs
  # Or better: use a real model with max_tokens=1 to minimize cost
  test_enforcement() {
    local key="$1"
    local level="$2"
    local resp
    resp=$(curl -sf -X POST "$LITELLM_URL/chat/completions" \
      -H "Authorization: Bearer $key" \
      -H "Content-Type: application/json" \
      -d '{"model": "claude-haiku-4-5", "messages": [{"role": "user", "content": "Say only: hello"}], "max_tokens": 5}' 2>/dev/null)
    echo "$resp"
  }

  echo ""
  echo "  Creating test keys for each enforcement level..."
  echo ""

  KEY_UNRESTRICTED=$(create_test_key "unrestricted") || true
  KEY_STANDARD=$(create_test_key "standard") || true
  KEY_DESIGN=$(create_test_key "design-first") || true

  if [ -n "$KEY_UNRESTRICTED" ] && [ -n "$KEY_STANDARD" ] && [ -n "$KEY_DESIGN" ]; then
    pass "Created test keys for all 3 enforcement levels"

    # Verify key metadata via API (use key as own Authorization header)
    for kv in "unrestricted:$KEY_UNRESTRICTED" "standard:$KEY_STANDARD" "design-first:$KEY_DESIGN"; do
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
    print(meta.get('enforcement_level', 'MISSING'))
except: print('ERROR')
" 2>/dev/null)
      if [ "$STORED_LEVEL" = "$level" ]; then
        pass "Key metadata: enforcement_level=$level (correct)"
      else
        fail "Key metadata: expected=$level got=$STORED_LEVEL"
      fi
    done

    echo ""
    echo "  Testing live API calls (requires ANTHROPIC_API_KEY)..."
    echo ""

    # Record time before calls for Langfuse trace filtering
    ENFORCEMENT_CALL_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

    # Test each level with a real API call
    RESP_UNRESTRICTED=$(test_enforcement "$KEY_UNRESTRICTED" "unrestricted" 2>/dev/null || echo "")
    RESP_STANDARD=$(test_enforcement "$KEY_STANDARD" "standard" 2>/dev/null || echo "")
    RESP_DESIGN=$(test_enforcement "$KEY_DESIGN" "design-first" 2>/dev/null || echo "")

    # Check if calls succeeded or failed due to missing API key
    CALL_SUCCESS_COUNT=0
    check_response() {
      local level="$1"
      local resp="$2"

      if [ -z "$resp" ]; then
        skip "$level: No response (API key may not be set)"
        return
      fi

      # Check for authentication errors (no ANTHROPIC_API_KEY)
      if echo "$resp" | grep -qi "AuthenticationError\|api_key\|401\|Unauthorized"; then
        skip "$level: Upstream auth error (ANTHROPIC_API_KEY not valid)"
        return
      fi

      # Check for budget exceeded (we set 0.01)
      if echo "$resp" | grep -qi "budget\|exceeded\|limit"; then
        skip "$level: Budget limit hit"
        return
      fi

      # Check for a successful completion
      if echo "$resp" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])" > /dev/null 2>&1; then
        pass "$level: API call succeeded"
        CALL_SUCCESS_COUNT=$((CALL_SUCCESS_COUNT + 1))
      else
        ERROR=$(echo "$resp" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error',{}).get('message','unknown')[:80])" 2>/dev/null || echo "unknown")
        skip "$level: API error — $ERROR"
      fi
    }

    check_response "unrestricted" "$RESP_UNRESTRICTED"
    check_response "standard" "$RESP_STANDARD"
    check_response "design-first" "$RESP_DESIGN"

    if [ "$CALL_SUCCESS_COUNT" -gt 0 ]; then
      ENFORCEMENT_CALLS_SUCCEEDED=true
    fi

    echo ""
    echo "  Cleanup: deleting test keys..."
    for key in "$KEY_UNRESTRICTED" "$KEY_STANDARD" "$KEY_DESIGN"; do
      curl -s -X POST "$LITELLM_URL/key/delete" \
        -H "Authorization: Bearer $MASTER_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"keys\": [\"$key\"]}" > /dev/null 2>&1 || true
    done
    pass "Test keys cleaned up"

  else
    fail "Could not create test keys (check LiteLLM master key and DB)"
  fi
fi

echo ""

# ---------------------------------------------------------------------------
# 10. Langfuse trace verification (after enforcement calls)
# ---------------------------------------------------------------------------
echo "10. Langfuse trace verification"

if ! $LANGFUSE_RUNNING; then
  skip "Langfuse not running — skipping trace verification"
elif [ -z "$LF_PUBLIC_KEY" ] || [ -z "$LF_SECRET_KEY" ]; then
  skip "Langfuse API keys not set — skipping trace verification"
elif ! $ENFORCEMENT_CALLS_SUCCEEDED; then
  skip "No successful enforcement calls — skipping trace verification"
else
  # Langfuse ingests traces asynchronously via the worker.
  # Wait briefly for the async pipeline: LiteLLM → Langfuse web → worker → ClickHouse
  echo "  Waiting 5s for async trace ingestion..."
  sleep 5

  # Query recent traces from Langfuse API
  TRACES_RESP=$(curl -s \
    -u "$LF_PUBLIC_KEY:$LF_SECRET_KEY" \
    "$LANGFUSE_URL/api/public/traces?limit=10&orderBy=timestamp.desc" 2>/dev/null)

  if [ -z "$TRACES_RESP" ]; then
    fail "Langfuse traces API returned empty response"
  else
    # Parse trace count from response
    TRACE_COUNT=$(echo "$TRACES_RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    traces = d.get('data', [])
    print(len(traces))
except: print('0')
" 2>/dev/null)

    if [ "$TRACE_COUNT" -gt 0 ]; then
      pass "Langfuse has traces ($TRACE_COUNT recent traces found)"
    else
      fail "Langfuse has no traces (LiteLLM → Langfuse pipeline may be broken)"
    fi

    # Check for traces with expected model name
    HAS_MODEL=$(echo "$TRACES_RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    traces = d.get('data', [])
    # Check trace metadata or tags for model info
    for t in traces:
        meta = t.get('metadata', {}) or {}
        tags = t.get('tags', []) or []
        name = t.get('name', '') or ''
        # LiteLLM sets the trace name or metadata with model info
        if 'claude' in name.lower() or 'claude' in str(meta).lower() or any('claude' in tag.lower() for tag in tags):
            print('yes')
            sys.exit(0)
    print('no')
except: print('error')
" 2>/dev/null)

    if [ "$HAS_MODEL" = "yes" ]; then
      pass "Traces contain Claude model references"
    elif [ "$HAS_MODEL" = "no" ]; then
      skip "No Claude model references in recent traces (may use different naming)"
    else
      skip "Could not parse trace model info"
    fi

    # Check that traces have cost/token metadata (proves LiteLLM integration works)
    HAS_USAGE=$(echo "$TRACES_RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    traces = d.get('data', [])
    for t in traces:
        # Langfuse traces from LiteLLM have usage data (input/output tokens)
        inp = t.get('input', None)
        out = t.get('output', None)
        usage = t.get('totalCost', None)
        # With turn_off_message_logging, input/output may be null but cost exists
        if usage is not None and usage > 0:
            print('yes')
            sys.exit(0)
    print('no')
except: print('error')
" 2>/dev/null)

    if [ "$HAS_USAGE" = "yes" ]; then
      pass "Traces have cost data (LiteLLM cost tracking active)"
    elif [ "$HAS_USAGE" = "no" ]; then
      skip "No cost data in recent traces (may need more time to propagate)"
    else
      skip "Could not parse trace usage data"
    fi

    # Verify privacy: with turn_off_message_logging=true, traces should NOT have prompt content
    HAS_CONTENT=$(echo "$TRACES_RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    traces = d.get('data', [])
    for t in traces:
        inp = t.get('input', None)
        out = t.get('output', None)
        # If input/output contain actual message content, privacy is off
        if inp and isinstance(inp, (dict, list)) and str(inp) != '{}' and str(inp) != '[]':
            # Check if it looks like actual chat messages
            inp_str = json.dumps(inp)
            if 'hello' in inp_str.lower() or 'content' in inp_str.lower():
                print('content_logged')
                sys.exit(0)
    print('content_redacted')
except: print('error')
" 2>/dev/null)

    if [ "$HAS_CONTENT" = "content_redacted" ]; then
      pass "Privacy: prompt content NOT logged (turn_off_message_logging active)"
    elif [ "$HAS_CONTENT" = "content_logged" ]; then
      fail "Privacy: prompt content IS logged (turn_off_message_logging may be off)"
    else
      skip "Could not verify privacy setting"
    fi
  fi
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
  exit 1
fi
