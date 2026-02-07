#!/usr/bin/env bash
# =============================================================================
# Authentik RBAC Groups Setup for Coder Role Mapping
#
# Creates Authentik groups and a custom OIDC property mapping that includes
# the "groups" claim in the OIDC token. This enables automatic Coder role
# assignment based on Authentik group membership.
#
# Prerequisites:
#   - Authentik must be running
#   - setup-authentik-sso-full.sh must have been run first (creates the Coder provider)
#
# Usage:
#   ./scripts/setup-authentik-rbac.sh
#
# After running this script:
#   1. Assign users to groups in Authentik Admin → Directory → Groups
#   2. Run: docker compose up -d coder-server (to reload OIDC config)
#   3. Users get roles automatically on next SSO login
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
AUTHENTIK_URL="${AUTHENTIK_URL:-http://localhost:9000}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=== Authentik RBAC Groups Setup ===${NC}"
echo ""

# ─── Step 1: Check Authentik ─────────────────────────────────────────────────

echo -e "${BLUE}[1/5] Checking Authentik...${NC}"
if ! curl -s "${AUTHENTIK_URL}/-/health/ready/" > /dev/null 2>&1; then
    echo -e "${RED}Error: Authentik is not running at ${AUTHENTIK_URL}${NC}"
    echo "Start it with: docker compose up -d authentik-server authentik-worker authentik-redis"
    exit 1
fi
echo -e "${GREEN}✓ Authentik is running${NC}"

# ─── Step 2: Get API Token ───────────────────────────────────────────────────

echo -e "${BLUE}[2/5] Getting API token...${NC}"

if [ -z "$AUTHENTIK_TOKEN" ]; then
    TOKEN_OUTPUT=$(docker exec authentik-server ak shell -c "
from authentik.core.models import Token, User
user = User.objects.get(username='akadmin')
token, created = Token.objects.get_or_create(
    identifier='rbac-setup-token',
    defaults={'user': user, 'intent': 'api', 'expiring': False}
)
print(f'TOKEN:{token.key}')
" 2>&1 | grep "^TOKEN:" | cut -d: -f2)

    if [ -z "$TOKEN_OUTPUT" ]; then
        echo -e "${RED}Failed to create API token${NC}"
        exit 1
    fi
    AUTHENTIK_TOKEN="$TOKEN_OUTPUT"
fi
echo -e "${GREEN}✓ API token obtained${NC}"

# Helper function
api_call() {
    local method=$1
    local endpoint=$2
    local data=$3

    if [ -n "$data" ]; then
        curl -s -X "$method" "${AUTHENTIK_URL}/api/v3${endpoint}" \
            -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$data"
    else
        curl -s -X "$method" "${AUTHENTIK_URL}/api/v3${endpoint}" \
            -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
            -H "Content-Type: application/json"
    fi
}

# ─── Step 3: Create Groups ───────────────────────────────────────────────────

echo -e "${BLUE}[3/5] Creating RBAC groups...${NC}"

# Group definitions: name → description
declare -A GROUPS=(
    ["coder-admins"]="Coder Owner role — full platform admin access"
    ["coder-template-admins"]="Coder Template Admin role — manage templates and view workspaces"
    ["coder-auditors"]="Coder Auditor role — read-only audit log access"
    ["coder-members"]="Coder Member role — standard contractor access (default)"
)

for group_name in "${!GROUPS[@]}"; do
    description="${GROUPS[$group_name]}"

    # Check if group exists
    EXISTING=$(api_call GET "/core/groups/?name=${group_name}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
results = data.get('results', [])
print(results[0]['pk'] if results else '')
" 2>/dev/null)

    if [ -n "$EXISTING" ]; then
        echo -e "  ${YELLOW}⊘${NC} Group '${group_name}' already exists (pk: ${EXISTING})"
    else
        RESULT=$(api_call POST "/core/groups/" "{
            \"name\": \"${group_name}\",
            \"is_superuser\": false
        }")
        PK=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('pk',''))" 2>/dev/null)
        if [ -n "$PK" ]; then
            echo -e "  ${GREEN}✓${NC} Created group '${group_name}' (pk: ${PK})"
        else
            echo -e "  ${RED}✗${NC} Failed to create group '${group_name}': $RESULT"
        fi
    fi
done

# ─── Step 4: Create Custom Property Mapping (groups claim) ──────────────────

echo -e "${BLUE}[4/5] Creating OIDC 'groups' property mapping...${NC}"

MAPPING_NAME="Coder Groups Claim"

# Check if mapping exists
EXISTING_MAPPING=$(api_call GET "/propertymappings/scope/?name=$(python3 -c 'import urllib.parse; print(urllib.parse.quote("'"${MAPPING_NAME}"'"))')" | python3 -c "
import sys, json
data = json.load(sys.stdin)
results = data.get('results', [])
print(results[0]['pk'] if results else '')
" 2>/dev/null)

if [ -n "$EXISTING_MAPPING" ]; then
    echo -e "  ${YELLOW}⊘${NC} Property mapping '${MAPPING_NAME}' already exists (pk: ${EXISTING_MAPPING})"
    MAPPING_PK="$EXISTING_MAPPING"
else
    # Create a custom scope mapping that includes user's group names in the "groups" claim
    MAPPING_RESULT=$(api_call POST "/propertymappings/scope/" "{
        \"name\": \"${MAPPING_NAME}\",
        \"scope_name\": \"groups\",
        \"description\": \"Include user group memberships in OIDC token for Coder role mapping\",
        \"expression\": \"return [group.name for group in request.user.ak_groups.all()]\"
    }")
    MAPPING_PK=$(echo "$MAPPING_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('pk',''))" 2>/dev/null)
    if [ -n "$MAPPING_PK" ]; then
        echo -e "  ${GREEN}✓${NC} Created property mapping '${MAPPING_NAME}' (pk: ${MAPPING_PK})"
    else
        echo -e "  ${RED}✗${NC} Failed to create property mapping: $MAPPING_RESULT"
    fi
fi

# ─── Step 5: Add mapping to the Coder OIDC provider ─────────────────────────

echo -e "${BLUE}[5/5] Adding groups mapping to Coder OIDC provider...${NC}"

# Find the Coder provider
CODER_PROVIDER=$(api_call GET "/providers/oauth2/?name=coder" | python3 -c "
import sys, json
data = json.load(sys.stdin)
results = data.get('results', [])
print(results[0]['pk'] if results else '')
" 2>/dev/null)

if [ -z "$CODER_PROVIDER" ]; then
    echo -e "  ${RED}✗${NC} Coder OIDC provider not found. Run setup-authentik-sso-full.sh first."
    exit 1
fi

# Get current property mappings
CURRENT_MAPPINGS=$(api_call GET "/providers/oauth2/${CODER_PROVIDER}/" | python3 -c "
import sys, json
data = json.load(sys.stdin)
mappings = data.get('property_mappings', [])
# Handle both dict and string formats
pks = []
for m in mappings:
    if isinstance(m, dict):
        pks.append(m.get('pk', ''))
    else:
        pks.append(str(m))
print(json.dumps(pks))
" 2>/dev/null)

# Check if our mapping is already included
if echo "$CURRENT_MAPPINGS" | grep -q "$MAPPING_PK"; then
    echo -e "  ${YELLOW}⊘${NC} Groups mapping already assigned to Coder provider"
else
    # Add our mapping to the list
    NEW_MAPPINGS=$(echo "$CURRENT_MAPPINGS" | python3 -c "
import sys, json
current = json.load(sys.stdin)
current.append('${MAPPING_PK}')
print(json.dumps(current))
" 2>/dev/null)

    # Update the provider
    UPDATE_RESULT=$(api_call PATCH "/providers/oauth2/${CODER_PROVIDER}/" "{
        \"property_mappings\": ${NEW_MAPPINGS}
    }")

    if echo "$UPDATE_RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if 'pk' in d else 1)" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Added groups mapping to Coder OIDC provider"
    else
        echo -e "  ${RED}✗${NC} Failed to update Coder provider: $UPDATE_RESULT"
    fi
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}=== RBAC Setup Complete ===${NC}"
echo ""
echo "Authentik groups created:"
echo "  coder-admins          → Coder Owner role"
echo "  coder-template-admins → Coder Template Admin role"
echo "  coder-auditors        → Coder Auditor role"
echo "  coder-members         → Coder Member role (default)"
echo ""
echo "OIDC 'groups' claim added to Coder provider."
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Assign users to groups in Authentik Admin:"
echo "     ${AUTHENTIK_URL}/if/admin/#/identity/groups"
echo ""
echo "     Example:"
echo "       admin       → coder-admins"
echo "       app-manager → coder-template-admins"
echo "       contractor1 → coder-members (or no group = default Member)"
echo ""
echo "  2. Reload Coder to pick up OIDC config changes:"
echo "     docker compose up -d coder-server"
echo ""
echo "  3. Users get roles automatically on next SSO login."
echo "     Existing manually-assigned roles are preserved."
echo ""
echo -e "${BLUE}Coder OIDC role mapping env vars (already in docker-compose.yml):${NC}"
echo "  CODER_OIDC_GROUP_FIELD=groups"
echo "  CODER_OIDC_USER_ROLE_FIELD=groups"
echo "  CODER_OIDC_USER_ROLE_MAPPING={\"coder-admins\":[\"owner\"],...}"
