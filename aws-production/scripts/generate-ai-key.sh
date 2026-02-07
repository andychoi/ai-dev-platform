#!/bin/bash
# =============================================================================
# Generate AI Key (Self-Service)
# Authenticates via Coder CLI token, calls key provisioner for a personal key.
# Usage: ./generate-ai-key.sh [username]
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROVISIONER_URL="${KEY_PROVISIONER_URL:-http://key-provisioner.coder-production.local:8100}"

# Get Coder session token
CODER_TOKEN="${CODER_SESSION_TOKEN:-}"
if [ -z "$CODER_TOKEN" ]; then
  # Try to get from coder CLI config
  if command -v coder >/dev/null 2>&1; then
    CODER_TOKEN=$(coder tokens list --output json 2>/dev/null | python3 -c "import sys,json; tokens=json.load(sys.stdin); print(tokens[0]['id'] if tokens else '')" 2>/dev/null || echo "")
  fi
fi

if [ -z "$CODER_TOKEN" ]; then
  echo -e "${RED}ERROR: No Coder session token found.${NC}"
  echo ""
  echo "Options:"
  echo "  1. Set CODER_SESSION_TOKEN environment variable"
  echo "  2. Run 'coder login' first to authenticate"
  echo ""
  echo "  export CODER_SESSION_TOKEN=\$(coder tokens create)"
  echo "  ./generate-ai-key.sh"
  exit 1
fi

PURPOSE="${1:-personal experimentation}"

echo -e "${BLUE}=== Generating self-service AI key ===${NC}"
echo "Provisioner: $PROVISIONER_URL"
echo ""

RESPONSE=$(curl -sf -X POST "$PROVISIONER_URL/api/v1/keys/self-service" \
  -H "Authorization: Bearer $CODER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"purpose\": \"$PURPOSE\"}" 2>/dev/null)

if [ -z "$RESPONSE" ]; then
  echo -e "${RED}ERROR: Could not reach key provisioner at $PROVISIONER_URL${NC}"
  echo "Make sure the key-provisioner service is running."
  exit 1
fi

KEY=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('key',''))" 2>/dev/null || echo "")
REUSED=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('reused',False))" 2>/dev/null || echo "")

if [ -z "$KEY" ]; then
  ERROR=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('error','unknown error'))" 2>/dev/null || echo "unknown error")
  echo -e "${RED}ERROR: $ERROR${NC}"
  exit 1
fi

echo -e "${GREEN}Key generated successfully!${NC}"
echo ""
if [ "$REUSED" = "True" ]; then
  echo -e "  ${YELLOW}(existing key reused)${NC}"
fi
echo ""
echo -e "  Key: ${GREEN}${KEY}${NC}"
echo ""
echo -e "${BLUE}Usage:${NC}"
echo "  # Set as environment variable"
echo "  export OPENAI_API_KEY=$KEY"
echo ""
echo "  # Or paste into workspace 'AI API Key' parameter"
echo ""
echo "  # Test the key"
echo "  curl -s http://localhost:4000/v1/models -H 'Authorization: Bearer $KEY' | python3 -m json.tool"
