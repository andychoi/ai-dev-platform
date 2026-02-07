#!/bin/bash
# =============================================================================
# Manage Service Keys (Admin)
# Create, list, revoke, and rotate keys for CI/CD and service agents.
# Requires LiteLLM master key (admin-only script).
#
# Usage:
#   ./manage-service-keys.sh create ci <repo-slug>
#   ./manage-service-keys.sh create agent review|write
#   ./manage-service-keys.sh list
#   ./manage-service-keys.sh revoke <key-alias>
#   ./manage-service-keys.sh rotate <key-alias>
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LITELLM_URL="${LITELLM_URL:-http://litellm.coder-production.local:4000}"
MASTER_KEY="${LITELLM_MASTER_KEY:-sk-poc-litellm-master-key-change-in-production}"

usage() {
  echo "Usage: $0 <command> [args]"
  echo ""
  echo "Commands:"
  echo "  create ci <repo-slug>        Create CI pipeline key (haiku only, \$5 budget)"
  echo "  create agent review          Create review agent key (sonnet+haiku, \$15)"
  echo "  create agent write           Create write agent key (all models, \$30)"
  echo "  list                         List all service keys"
  echo "  revoke <key-alias>           Delete a service key"
  echo "  rotate <key-alias>           Revoke and recreate a service key"
  exit 1
}

litellm_post() {
  local endpoint="$1"
  local data="$2"
  curl -sf -X POST "$LITELLM_URL$endpoint" \
    -H "Authorization: Bearer $MASTER_KEY" \
    -H "Content-Type: application/json" \
    -d "$data" 2>/dev/null
}

litellm_get() {
  local endpoint="$1"
  curl -sf "$LITELLM_URL$endpoint" \
    -H "Authorization: Bearer $MASTER_KEY" 2>/dev/null
}

create_ci_key() {
  local repo="$1"
  local alias="ci-$repo"

  echo -e "${BLUE}Creating CI key for repo: $repo${NC}"

  RESPONSE=$(litellm_post "/key/generate" "{
    \"key_alias\": \"$alias\",
    \"user_id\": \"ci-$repo\",
    \"max_budget\": 5.00,
    \"rpm_limit\": 30,
    \"models\": [\"claude-haiku-4-5\"],
    \"metadata\": {
      \"scope\": \"ci:$repo\",
      \"key_type\": \"ci\",
      \"created_by\": \"manage-service-keys\",
      \"created_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
      \"repo\": \"$repo\",
      \"purpose\": \"CI pipeline code review\"
    }
  }")

  KEY=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('key',''))" 2>/dev/null || echo "")
  if [ -n "$KEY" ]; then
    echo -e "${GREEN}CI key created: $KEY${NC}"
    echo "  Alias: $alias | Budget: \$5 | RPM: 30 | Models: haiku only"
  else
    echo -e "${RED}Failed to create CI key${NC}"
    echo "$RESPONSE"
  fi
}

create_agent_key() {
  local agent_type="$1"

  case "$agent_type" in
    review)
      local alias="agent-review"
      local budget="15.00"
      local rpm="40"
      local models='["claude-sonnet-4-5","claude-haiku-4-5"]'
      local purpose="Read-only code review agent"
      ;;
    write)
      local alias="agent-write"
      local budget="30.00"
      local rpm="60"
      local models='[]'  # empty = all models
      local purpose="Code generation agent"
      ;;
    *)
      echo -e "${RED}Unknown agent type: $agent_type (use 'review' or 'write')${NC}"
      exit 1
      ;;
  esac

  echo -e "${BLUE}Creating $agent_type agent key${NC}"

  RESPONSE=$(litellm_post "/key/generate" "{
    \"key_alias\": \"$alias\",
    \"user_id\": \"$alias\",
    \"max_budget\": $budget,
    \"rpm_limit\": $rpm,
    $([ "$models" != "[]" ] && echo "\"models\": $models," || echo "")
    \"metadata\": {
      \"scope\": \"agent:$agent_type\",
      \"key_type\": \"agent\",
      \"created_by\": \"manage-service-keys\",
      \"created_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
      \"agent_type\": \"$agent_type\",
      \"purpose\": \"$purpose\"
    }
  }")

  KEY=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('key',''))" 2>/dev/null || echo "")
  if [ -n "$KEY" ]; then
    echo -e "${GREEN}Agent key created: $KEY${NC}"
    echo "  Alias: $alias | Budget: \$$budget | RPM: $rpm"
  else
    echo -e "${RED}Failed to create agent key${NC}"
    echo "$RESPONSE"
  fi
}

list_keys() {
  echo -e "${BLUE}=== Service Keys ===${NC}"
  echo ""

  RESPONSE=$(litellm_get "/key/list")
  if [ -z "$RESPONSE" ]; then
    echo -e "${RED}Failed to list keys${NC}"
    exit 1
  fi

  echo "$RESPONSE" | python3 -c "
import sys, json

data = json.load(sys.stdin)
keys = data if isinstance(data, list) else data.get('keys', [])

service_keys = []
for k in keys:
    alias = k.get('key_alias', '') or ''
    metadata = k.get('metadata', {}) or {}
    key_type = metadata.get('key_type', '')
    if key_type in ('ci', 'agent') or alias.startswith('ci-') or alias.startswith('agent-'):
        service_keys.append(k)

if not service_keys:
    print('  No service keys found.')
else:
    for k in service_keys:
        alias = k.get('key_alias', 'N/A')
        metadata = k.get('metadata', {}) or {}
        scope = metadata.get('scope', 'unknown')
        budget = k.get('max_budget', 'N/A')
        spend = k.get('spend', 0)
        print(f'  {alias:<25} scope={scope:<20} budget=\${budget} spent=\${spend:.2f}')
" 2>/dev/null || echo -e "${YELLOW}Could not parse key list${NC}"
}

revoke_key() {
  local alias="$1"
  echo -e "${YELLOW}Revoking key: $alias${NC}"

  RESPONSE=$(litellm_post "/key/delete" "{\"key_alias\": \"$alias\"}")
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}Key revoked: $alias${NC}"
  else
    echo -e "${RED}Failed to revoke key: $alias${NC}"
  fi
}

rotate_key() {
  local alias="$1"
  echo -e "${BLUE}Rotating key: $alias${NC}"

  # Get existing key info first
  INFO=$(litellm_post "/key/info" "{\"key_alias\": \"$alias\"}")
  if [ -z "$INFO" ]; then
    echo -e "${RED}Key not found: $alias${NC}"
    exit 1
  fi

  # Revoke old key
  revoke_key "$alias"

  # Determine type and recreate
  KEY_TYPE=$(echo "$INFO" | python3 -c "
import sys, json
data = json.load(sys.stdin)
info = data.get('info', data.get('key_info', {}))
metadata = info.get('metadata', {}) or {}
print(metadata.get('key_type', 'unknown'))
" 2>/dev/null || echo "unknown")

  case "$KEY_TYPE" in
    ci)
      REPO=$(echo "$INFO" | python3 -c "
import sys, json
data = json.load(sys.stdin)
info = data.get('info', data.get('key_info', {}))
metadata = info.get('metadata', {}) or {}
print(metadata.get('repo', ''))
" 2>/dev/null || echo "")
      if [ -n "$REPO" ]; then
        create_ci_key "$REPO"
      else
        echo -e "${RED}Could not determine repo for CI key${NC}"
      fi
      ;;
    agent)
      AGENT_TYPE=$(echo "$INFO" | python3 -c "
import sys, json
data = json.load(sys.stdin)
info = data.get('info', data.get('key_info', {}))
metadata = info.get('metadata', {}) or {}
print(metadata.get('agent_type', ''))
" 2>/dev/null || echo "")
      if [ -n "$AGENT_TYPE" ]; then
        create_agent_key "$AGENT_TYPE"
      else
        echo -e "${RED}Could not determine agent type${NC}"
      fi
      ;;
    *)
      echo -e "${RED}Cannot auto-rotate key type: $KEY_TYPE (recreate manually)${NC}"
      ;;
  esac
}

# Main dispatcher
[ $# -lt 1 ] && usage

case "$1" in
  create)
    [ $# -lt 2 ] && usage
    case "$2" in
      ci)
        [ $# -lt 3 ] && { echo -e "${RED}Usage: $0 create ci <repo-slug>${NC}"; exit 1; }
        create_ci_key "$3"
        ;;
      agent)
        [ $# -lt 3 ] && { echo -e "${RED}Usage: $0 create agent review|write${NC}"; exit 1; }
        create_agent_key "$3"
        ;;
      *)
        usage
        ;;
    esac
    ;;
  list)
    list_keys
    ;;
  revoke)
    [ $# -lt 2 ] && { echo -e "${RED}Usage: $0 revoke <key-alias>${NC}"; exit 1; }
    revoke_key "$2"
    ;;
  rotate)
    [ $# -lt 2 ] && { echo -e "${RED}Usage: $0 rotate <key-alias>${NC}"; exit 1; }
    rotate_key "$2"
    ;;
  *)
    usage
    ;;
esac
