#!/bin/bash
# Setup LiteLLM virtual keys for all test users
# Each key has per-user budget and rate limits

set -euo pipefail

LITELLM_URL="http://localhost:4000"
MASTER_KEY="${LITELLM_MASTER_KEY:-sk-poc-litellm-master-key-change-in-production}"

# Default limits
DEFAULT_RPM="${LITELLM_DEFAULT_RPM:-60}"
DEFAULT_BUDGET="${LITELLM_DEFAULT_USER_BUDGET:-10.00}"

# Users to create keys for (username:budget:rpm)
USERS=(
  "admin:50.00:200"
  "appmanager:20.00:100"
  "contractor1:10.00:60"
  "contractor2:10.00:60"
  "contractor3:10.00:60"
)

echo "=== Setting up LiteLLM virtual keys ==="
echo "LiteLLM URL: $LITELLM_URL"
echo ""

# Wait for LiteLLM to be ready
echo "Waiting for LiteLLM to be ready..."
for i in $(seq 1 30); do
  if curl -sf "$LITELLM_URL/health" > /dev/null 2>&1; then
    echo "LiteLLM is ready!"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: LiteLLM not ready after 30 seconds"
    exit 1
  fi
  sleep 1
done

echo ""

for user_config in "${USERS[@]}"; do
  IFS=':' read -r username budget rpm <<< "$user_config"

  echo "Creating key for: $username (budget: \$$budget, rpm: $rpm)"

  RESPONSE=$(curl -s -X POST "$LITELLM_URL/key/generate" \
    -H "Authorization: Bearer $MASTER_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"key_alias\": \"$username\",
      \"user_id\": \"$username\",
      \"max_budget\": $budget,
      \"rpm_limit\": $rpm,
      \"metadata\": {
        \"workspace_user\": \"$username\",
        \"created_by\": \"setup-script\"
      }
    }")

  KEY=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('key', 'ERROR'))" 2>/dev/null || echo "ERROR")

  if [ "$KEY" = "ERROR" ]; then
    echo "  WARNING: Failed to create key for $username"
    echo "  Response: $RESPONSE"
  else
    echo "  Key created: ${KEY:0:20}..."
    # Store key mapping for workspace provisioning
    echo "$username=$KEY" >> /tmp/litellm-keys.txt
  fi
done

echo ""
echo "=== LiteLLM keys setup complete ==="
echo "Keys saved to /tmp/litellm-keys.txt"
echo ""
echo "To retrieve a key later:"
echo "  curl -s $LITELLM_URL/key/info -H 'Authorization: Bearer $MASTER_KEY' -d '{\"key\": \"sk-...\"}'"
