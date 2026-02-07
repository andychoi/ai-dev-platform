#!/usr/bin/env bash
# =============================================================================
# Full Authentik SSO Setup - Automated Configuration
# Reads OIDC client IDs and secrets from .env (source of truth) and syncs
# them into Authentik as OAuth2 providers + applications.
#
# .env is NEVER written to by this script. All secrets must be pre-defined.
# To generate a new secret: openssl rand -base64 96 | tr -d '\n'
# =============================================================================

set -e

# macOS compatibility - don't use associative arrays

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
AUTHENTIK_URL="${AUTHENTIK_URL:-http://host.docker.internal:9000}"
AUTHENTIK_INTERNAL_URL="http://host.docker.internal:9000"
ENV_FILE="${PROJECT_DIR}/.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=== Full Authentik SSO Setup ===${NC}"
echo ""

# -----------------------------------------------------------------------------
# Step 1: Load secrets from .env (read-only)
# -----------------------------------------------------------------------------
echo -e "${BLUE}[1/5] Loading OIDC secrets from .env...${NC}"

if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}Error: ${ENV_FILE} not found. Copy from .env.example first.${NC}"
    exit 1
fi

# Source .env to get all OIDC variables
# (safe: .env is key=value pairs only, no commands)
set -a
source "$ENV_FILE"
set +a

# Define the 5 OIDC apps: slug|client_id_var|client_secret_var
OIDC_APPS=(
    "coder|CODER_OIDC_CLIENT_ID|CODER_OIDC_CLIENT_SECRET"
    "gitea|GITEA_OIDC_CLIENT_ID|GITEA_OIDC_CLIENT_SECRET"
    "minio|MINIO_IDENTITY_OPENID_CLIENT_ID|MINIO_IDENTITY_OPENID_CLIENT_SECRET"
    "platform-admin|PLATFORM_ADMIN_OIDC_CLIENT_ID|PLATFORM_ADMIN_OIDC_CLIENT_SECRET"
    "litellm|LITELLM_OIDC_CLIENT_ID|LITELLM_OIDC_CLIENT_SECRET"
)

# Validate all secrets are present
MISSING=0
for app_def in "${OIDC_APPS[@]}"; do
    IFS='|' read -r slug id_var secret_var <<< "$app_def"
    id_val="${!id_var}"
    secret_val="${!secret_var}"
    if [ -z "$id_val" ] || [ -z "$secret_val" ]; then
        echo -e "${RED}  Missing: ${id_var} or ${secret_var}${NC}"
        MISSING=1
    else
        echo -e "  ${slug}: ID=${id_val}"
    fi
done

if [ "$MISSING" -eq 1 ]; then
    echo ""
    echo -e "${RED}Error: Some OIDC secrets are missing in .env${NC}"
    echo "Generate missing secrets with:  openssl rand -base64 96 | tr -d '\\n'"
    echo "Then add them to .env and re-run this script."
    exit 1
fi
echo -e "${GREEN}✓ All OIDC secrets loaded from .env${NC}"

# -----------------------------------------------------------------------------
# Step 2: Check Authentik is running + get API token
# -----------------------------------------------------------------------------
echo -e "${BLUE}[2/5] Connecting to Authentik...${NC}"

if ! curl -s "${AUTHENTIK_URL}/-/health/ready/" > /dev/null 2>&1; then
    echo -e "${RED}Error: Authentik is not running at ${AUTHENTIK_URL}${NC}"
    echo "Start it with: docker compose up -d authentik-server authentik-worker"
    exit 1
fi
echo -e "${GREEN}✓ Authentik is running${NC}"

if [ -z "$AUTHENTIK_TOKEN" ]; then
    TOKEN_OUTPUT=$(docker exec authentik-server ak shell -c "
from authentik.core.models import Token, User
user = User.objects.get(username='akadmin')
token, created = Token.objects.get_or_create(
    identifier='sso-setup-token',
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

# Helper function for API calls
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

# -----------------------------------------------------------------------------
# Step 3: Get signing key + flows
# -----------------------------------------------------------------------------
echo -e "${BLUE}[3/5] Getting signing key and flows...${NC}"

SIGNING_KEY=$(api_call GET "/crypto/certificatekeypairs/" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for key in data.get('results', []):
    if 'authentik' in key.get('name', '').lower():
        print(key['pk'])
        break
" 2>/dev/null)

if [ -z "$SIGNING_KEY" ]; then
    echo -e "${YELLOW}No signing key found, creating one...${NC}"
    SIGNING_KEY=$(api_call POST "/crypto/certificatekeypairs/generate/" '{
        "common_name": "authentik SSO",
        "subject_alt_name": "authentik-sso",
        "validity_days": 365
    }' | python3 -c "import sys,json; print(json.load(sys.stdin).get('pk',''))")
fi
echo -e "  Signing key: ${SIGNING_KEY:0:8}..."

AUTH_FLOW=$(api_call GET '/flows/instances/?designation=authorization' | python3 -c 'import sys,json; r=json.load(sys.stdin)["results"]; print(r[0]["pk"] if r else "")' 2>/dev/null)

INVAL_FLOW=$(api_call GET '/flows/instances/?designation=invalidation' | python3 -c '
import sys,json
results = json.load(sys.stdin)["results"]
for r in results:
    if "provider" in r.get("slug",""):
        print(r["pk"]); break
else:
    if results: print(results[0]["pk"])
' 2>/dev/null)

PROP_MAPPINGS=$(api_call GET '/propertymappings/provider/scope/' | python3 -c '
import sys,json
mappings = json.load(sys.stdin).get("results",[])
print(json.dumps([m["pk"] for m in mappings if m.get("managed","")]))
' 2>/dev/null)

echo -e "${GREEN}✓ Signing key and flows ready${NC}"

# -----------------------------------------------------------------------------
# Step 4: Create/update OAuth2 Providers (secrets from .env)
# -----------------------------------------------------------------------------
echo -e "${BLUE}[4/5] Syncing OAuth2 providers to Authentik...${NC}"

sync_oauth_provider() {
    local name=$1
    local slug=$2
    local client_id=$3
    local client_secret=$4
    shift 4
    # Remaining args are redirect URIs
    local redirect_uris_json="["
    local first=true
    for uri in "$@"; do
        if [ "$first" = true ]; then first=false; else redirect_uris_json+=","; fi
        redirect_uris_json+="{\"matching_mode\":\"strict\",\"url\":\"${uri}\"}"
    done
    redirect_uris_json+="]"

    echo "  Syncing provider: $name (client_id=${client_id})"

    # Check if provider already exists (list all, filter by client_id)
    EXISTING_PK=$(api_call GET "/providers/oauth2/?page_size=50" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for p in data.get('results', []):
    if p.get('client_id') == '${client_id}':
        print(p['pk'])
        break
" 2>/dev/null)

    if [ -n "$EXISTING_PK" ]; then
        # Update existing provider with secrets from .env
        RESULT=$(api_call PATCH "/providers/oauth2/${EXISTING_PK}/" "{
            \"client_secret\": \"${client_secret}\",
            \"redirect_uris\": ${redirect_uris_json},
            \"signing_key\": \"${SIGNING_KEY}\",
            \"property_mappings\": ${PROP_MAPPINGS}
        }")
        echo "    Updated existing provider (pk=${EXISTING_PK})"
    else
        # Create new provider with secrets from .env
        RESULT=$(api_call POST "/providers/oauth2/" "{
            \"name\": \"${name}\",
            \"authorization_flow\": \"${AUTH_FLOW}\",
            \"invalidation_flow\": \"${INVAL_FLOW}\",
            \"client_type\": \"confidential\",
            \"client_id\": \"${client_id}\",
            \"client_secret\": \"${client_secret}\",
            \"redirect_uris\": ${redirect_uris_json},
            \"signing_key\": \"${SIGNING_KEY}\",
            \"sub_mode\": \"user_username\",
            \"include_claims_in_id_token\": true,
            \"property_mappings\": ${PROP_MAPPINGS}
        }")

        EXISTING_PK=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('pk',''))" 2>/dev/null)

        if [ -n "$EXISTING_PK" ]; then
            echo "    Created provider (pk=${EXISTING_PK})"
        else
            echo -e "${YELLOW}    Warning: Failed to create provider${NC}"
            echo "$RESULT" | head -c 200
            echo ""
            return
        fi
    fi

    # Create or link application
    APP_CHECK=$(api_call GET "/core/applications/${slug}/" 2>&1)
    if echo "$APP_CHECK" | python3 -c "import sys,json; json.load(sys.stdin)['slug']" &>/dev/null; then
        api_call PATCH "/core/applications/${slug}/" "{\"provider\": ${EXISTING_PK}}" > /dev/null 2>&1
        echo "    Linked to existing application"
    else
        LINK_RESULT=$(api_call POST "/core/applications/" "{
            \"name\": \"${name}\",
            \"slug\": \"${slug}\",
            \"provider\": ${EXISTING_PK},
            \"meta_launch_url\": \"\",
            \"open_in_new_tab\": true
        }" 2>&1)
        if echo "$LINK_RESULT" | python3 -c "import sys,json; json.load(sys.stdin)['slug']" &>/dev/null; then
            echo "    Created application and linked provider"
        else
            echo -e "${YELLOW}    Warning: Could not create application${NC}"
            echo "$LINK_RESULT" | head -c 200
            echo ""
        fi
    fi
}

# Sync all 5 providers (secrets read from .env, passed to Authentik)
sync_oauth_provider "Coder OIDC" "coder" \
    "$CODER_OIDC_CLIENT_ID" "$CODER_OIDC_CLIENT_SECRET" \
    "https://host.docker.internal:7443/api/v2/users/oidc/callback"

sync_oauth_provider "Gitea OIDC" "gitea" \
    "$GITEA_OIDC_CLIENT_ID" "$GITEA_OIDC_CLIENT_SECRET" \
    "http://localhost:3000/user/oauth2/Authentik/callback"

sync_oauth_provider "MinIO OIDC" "minio" \
    "$MINIO_IDENTITY_OPENID_CLIENT_ID" "$MINIO_IDENTITY_OPENID_CLIENT_SECRET" \
    "http://localhost:9001/oauth_callback"

sync_oauth_provider "Platform Admin OIDC" "platform-admin" \
    "$PLATFORM_ADMIN_OIDC_CLIENT_ID" "$PLATFORM_ADMIN_OIDC_CLIENT_SECRET" \
    "http://localhost:5050/auth/callback" \
    "http://host.docker.internal:5050/auth/callback"

sync_oauth_provider "LiteLLM OIDC" "litellm" \
    "$LITELLM_OIDC_CLIENT_ID" "$LITELLM_OIDC_CLIENT_SECRET" \
    "http://localhost:4000/sso/callback"

echo -e "${GREEN}✓ All OAuth2 providers synced${NC}"

# -----------------------------------------------------------------------------
# Step 5: Verify and summarize
# -----------------------------------------------------------------------------
echo -e "${BLUE}[5/5] Verifying configuration...${NC}"

# Remove stale generated files (secrets are now in .env only)
for stale_file in "${PROJECT_DIR}/docker-compose.sso.yml" "${PROJECT_DIR}/.env.sso"; do
    if [ -f "$stale_file" ]; then
        rm -f "$stale_file"
        echo "  Removed stale file: $(basename "$stale_file")"
    fi
done

if grep -q "CODER_OIDC_ISSUER_URL" "${PROJECT_DIR}/docker-compose.yml" 2>/dev/null; then
    echo -e "${GREEN}✓ OIDC config found in docker-compose.yml${NC}"
else
    echo -e "${YELLOW}  Warning: OIDC config not found in docker-compose.yml${NC}"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo -e "${GREEN}=== SSO Setup Complete ===${NC}"
echo ""
echo "Authentik providers synced with secrets from .env (read-only)."
echo ""
echo "OAuth2 Applications:"
echo "  Coder:          client_id=${CODER_OIDC_CLIENT_ID}"
echo "  Gitea:          client_id=${GITEA_OIDC_CLIENT_ID}"
echo "  MinIO:          client_id=${MINIO_IDENTITY_OPENID_CLIENT_ID}"
echo "  Platform Admin: client_id=${PLATFORM_ADMIN_OIDC_CLIENT_ID}"
echo "  LiteLLM:        client_id=${LITELLM_OIDC_CLIENT_ID}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo -e "${RED}0. REQUIRED - Add hosts entries (one-time):${NC}"
echo "   sudo sh -c 'echo \"127.0.0.1    host.docker.internal\" >> /etc/hosts'"
echo ""
echo "1. Restart services to pick up secrets:"
echo "   docker compose up -d coder minio platform-admin"
echo ""
echo "2. Configure Gitea OIDC (one-time, via Gitea Admin UI):"
echo "   a. Go to http://localhost:3000/admin/auths/new"
echo "   b. Authentication Type: OAuth2"
echo "   c. Provider: OpenID Connect"
echo "   d. Authentication Name: Authentik"
echo "   e. Client ID: ${GITEA_OIDC_CLIENT_ID}"
echo "   f. Client Secret: (from .env GITEA_OIDC_CLIENT_SECRET)"
echo "   g. Auto Discovery URL:"
echo "      ${AUTHENTIK_INTERNAL_URL}/application/o/gitea/.well-known/openid-configuration"
echo ""
echo "3. Test SSO login:"
echo "   - Coder:          https://host.docker.internal:7443"
echo "   - MinIO:          http://localhost:9001"
echo "   - Platform Admin: http://localhost:5050"
echo "   - LiteLLM:        http://localhost:4000/ui"
echo ""
echo "4. Local fallback accounts (if Authentik is down):"
echo "   - Coder: admin@example.com / CoderAdmin123!"
echo "   - MinIO: minioadmin / minioadmin"
echo "   - Gitea: gitea / admin123"
echo "   - Platform Admin: admin / admin123"
echo ""
