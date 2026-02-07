#!/usr/bin/env bash
# =============================================================================
# Full Authentik SSO Setup - Automated Configuration
# Creates providers, configures services, and updates docker-compose
# =============================================================================

set -e

# macOS compatibility - don't use associative arrays

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
AUTHENTIK_URL="${AUTHENTIK_URL:-http://localhost:9000}"
AUTHENTIK_INTERNAL_URL="http://host.docker.internal:9000"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=== Full Authentik SSO Setup ===${NC}"
echo ""

# -----------------------------------------------------------------------------
# Step 1: Check Authentik is running
# -----------------------------------------------------------------------------
echo -e "${BLUE}[1/6] Checking Authentik...${NC}"
if ! curl -s "${AUTHENTIK_URL}/-/health/ready/" > /dev/null 2>&1; then
    echo -e "${RED}Error: Authentik is not running at ${AUTHENTIK_URL}${NC}"
    echo "Start it with: docker compose up -d authentik-server authentik-worker"
    exit 1
fi
echo -e "${GREEN}✓ Authentik is running${NC}"

# -----------------------------------------------------------------------------
# Step 2: Get or create API token
# -----------------------------------------------------------------------------
echo -e "${BLUE}[2/6] Getting API token...${NC}"

if [ -z "$AUTHENTIK_TOKEN" ]; then
    # Create token via Authentik shell
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
# Step 3: Get signing key
# -----------------------------------------------------------------------------
echo -e "${BLUE}[3/6] Getting signing key...${NC}"
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
echo -e "${GREEN}✓ Signing key: ${SIGNING_KEY:0:8}...${NC}"

# -----------------------------------------------------------------------------
# Step 4: Create OAuth2 Providers
# -----------------------------------------------------------------------------
echo -e "${BLUE}[4/6] Creating OAuth2 providers...${NC}"

# Store credentials in simple variables
CODER_CLIENT_ID=""
CODER_CLIENT_SECRET=""
GITEA_CLIENT_ID=""
GITEA_CLIENT_SECRET=""
MINIO_CLIENT_ID=""
MINIO_CLIENT_SECRET=""
PLATFORM_ADMIN_CLIENT_ID=""
PLATFORM_ADMIN_CLIENT_SECRET=""
LITELLM_CLIENT_ID=""
LITELLM_CLIENT_SECRET=""

# Get authorization flow
AUTH_FLOW=$(api_call GET '/flows/instances/?designation=authorization' | python3 -c 'import sys,json; r=json.load(sys.stdin)["results"]; print(r[0]["pk"] if r else "")' 2>/dev/null)

# Get property mappings
PROP_MAPPINGS=$(api_call GET '/propertymappings/scope/?managed__isnull=false' | python3 -c 'import sys,json; print(json.dumps([p["pk"] for p in json.load(sys.stdin).get("results",[])]))' 2>/dev/null)

create_oauth_provider() {
    local name=$1
    local slug=$2
    local redirect_uri=$3

    echo "  Creating provider: $name"

    # Check if provider exists
    EXISTING=$(api_call GET "/providers/oauth2/?search=${slug}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for p in data.get('results', []):
    if p.get('name') == '${name}':
        print(f\"{p['pk']}|{p['client_id']}|{p.get('client_secret', '')}\")
        break
" 2>/dev/null)

    if [ -n "$EXISTING" ]; then
        PK=$(echo "$EXISTING" | cut -d'|' -f1)
        CLIENT_ID=$(echo "$EXISTING" | cut -d'|' -f2)
        CLIENT_SECRET=$(echo "$EXISTING" | cut -d'|' -f3)
        echo "    Provider exists (pk=$PK)"
    else
        # Create new provider
        RESULT=$(api_call POST "/providers/oauth2/" "{
            \"name\": \"${name}\",
            \"authorization_flow\": \"${AUTH_FLOW}\",
            \"client_type\": \"confidential\",
            \"client_id\": \"${slug}\",
            \"redirect_uris\": \"${redirect_uri}\",
            \"signing_key\": \"${SIGNING_KEY}\",
            \"sub_mode\": \"user_username\",
            \"include_claims_in_id_token\": true,
            \"property_mappings\": ${PROP_MAPPINGS}
        }")

        PK=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('pk',''))" 2>/dev/null)
        CLIENT_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('client_id',''))" 2>/dev/null)
        CLIENT_SECRET=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('client_secret',''))" 2>/dev/null)

        if [ -n "$PK" ]; then
            echo "    Created (pk=$PK)"
        else
            echo -e "${YELLOW}    Warning: Failed to create provider${NC}"
            echo "$RESULT" | head -c 200
            return
        fi
    fi

    # Export to global variables based on slug
    case "$slug" in
        coder)
            CODER_CLIENT_ID="$CLIENT_ID"
            CODER_CLIENT_SECRET="$CLIENT_SECRET"
            ;;
        gitea)
            GITEA_CLIENT_ID="$CLIENT_ID"
            GITEA_CLIENT_SECRET="$CLIENT_SECRET"
            ;;
        minio)
            MINIO_CLIENT_ID="$CLIENT_ID"
            MINIO_CLIENT_SECRET="$CLIENT_SECRET"
            ;;
        platform-admin)
            PLATFORM_ADMIN_CLIENT_ID="$CLIENT_ID"
            PLATFORM_ADMIN_CLIENT_SECRET="$CLIENT_SECRET"
            ;;
        litellm)
            LITELLM_CLIENT_ID="$CLIENT_ID"
            LITELLM_CLIENT_SECRET="$CLIENT_SECRET"
            ;;
    esac

    # Link to application (use slug in URL for reliability)
    if [ -n "$PK" ]; then
        LINK_RESULT=$(api_call PATCH "/core/applications/${slug}/" "{\"provider\": ${PK}}" 2>&1)
        if echo "$LINK_RESULT" | grep -q '"provider"'; then
            echo "    Linked to application"
        else
            echo "    Note: Could not link to application (app may not exist)"
        fi
    fi
}

# Create providers for each service
create_oauth_provider "Coder OIDC" "coder" "http://localhost:7080/api/v2/users/oidc/callback\nhttp://host.docker.internal:7080/api/v2/users/oidc/callback\nhttps://host.docker.internal:7443/api/v2/users/oidc/callback"
create_oauth_provider "Gitea OIDC" "gitea" "http://localhost:3000/user/oauth2/Authentik/callback"
create_oauth_provider "MinIO OIDC" "minio" "http://localhost:9001/oauth_callback"
create_oauth_provider "Platform Admin OIDC" "platform-admin" "http://localhost:5050/auth/callback"
create_oauth_provider "LiteLLM OIDC" "litellm" "http://localhost:4000/sso/callback"

echo -e "${GREEN}✓ OAuth2 providers created${NC}"

# -----------------------------------------------------------------------------
# Step 5: Generate environment file
# -----------------------------------------------------------------------------
echo -e "${BLUE}[5/6] Generating SSO configuration...${NC}"

SSO_ENV_FILE="${PROJECT_DIR}/.env.sso"

cat > "$SSO_ENV_FILE" << EOF
# =============================================================================
# Authentik SSO Configuration
# Generated by setup-authentik-sso-full.sh
# Source this file or add to docker-compose environment
# =============================================================================

# Coder OIDC
CODER_OIDC_ISSUER_URL=${AUTHENTIK_INTERNAL_URL}/application/o/coder/
CODER_OIDC_CLIENT_ID=${CODER_CLIENT_ID}
CODER_OIDC_CLIENT_SECRET=${CODER_CLIENT_SECRET}
CODER_OIDC_ALLOW_SIGNUPS=true
CODER_OIDC_EMAIL_DOMAIN=
CODER_OIDC_SCOPES=openid,profile,email
CODER_DISABLE_PASSWORD_AUTH=false

# MinIO OIDC
MINIO_IDENTITY_OPENID_CONFIG_URL=${AUTHENTIK_INTERNAL_URL}/application/o/minio/.well-known/openid-configuration
MINIO_IDENTITY_OPENID_CLIENT_ID=${MINIO_CLIENT_ID}
MINIO_IDENTITY_OPENID_CLIENT_SECRET=${MINIO_CLIENT_SECRET}
MINIO_IDENTITY_OPENID_CLAIM_NAME=policy
MINIO_IDENTITY_OPENID_SCOPES=openid,profile,email
MINIO_IDENTITY_OPENID_REDIRECT_URI=http://localhost:9001/oauth_callback

# Gitea OIDC (configure via Gitea Admin UI > Authentication Sources > Add OAuth2)
# Provider: OpenID Connect
# Auto Discovery URL: ${AUTHENTIK_INTERNAL_URL}/application/o/gitea/.well-known/openid-configuration
GITEA_OIDC_CLIENT_ID=${GITEA_CLIENT_ID}
GITEA_OIDC_CLIENT_SECRET=${GITEA_CLIENT_SECRET}
GITEA_OIDC_DISCOVERY_URL=${AUTHENTIK_INTERNAL_URL}/application/o/gitea/.well-known/openid-configuration

# Platform Admin OIDC
PLATFORM_ADMIN_OIDC_ISSUER_URL=${AUTHENTIK_INTERNAL_URL}/application/o/platform-admin/
PLATFORM_ADMIN_OIDC_CLIENT_ID=${PLATFORM_ADMIN_CLIENT_ID}
PLATFORM_ADMIN_OIDC_CLIENT_SECRET=${PLATFORM_ADMIN_CLIENT_SECRET}

# LiteLLM Admin UI OIDC
LITELLM_OIDC_CLIENT_ID=${LITELLM_CLIENT_ID}
LITELLM_OIDC_CLIENT_SECRET=${LITELLM_CLIENT_SECRET}

EOF

echo -e "${GREEN}✓ Configuration saved to ${SSO_ENV_FILE}${NC}"

# -----------------------------------------------------------------------------
# Step 5b: Update .env with generated secrets
# Docker Compose auto-loads .env (not .env.sso), so secrets must be here
# -----------------------------------------------------------------------------
ENV_FILE="${PROJECT_DIR}/.env"

if [ -f "$ENV_FILE" ]; then
    echo "  Updating .env with generated secrets..."

    # Helper: update or append a key=value in .env
    update_env_var() {
        local key=$1
        local value=$2
        if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
            # Use | as sed delimiter since values may contain /
            sed -i.bak "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
        else
            echo "${key}=${value}" >> "$ENV_FILE"
        fi
    }

    update_env_var "CODER_OIDC_CLIENT_SECRET" "$CODER_CLIENT_SECRET"
    update_env_var "CODER_OIDC_CLIENT_ID" "$CODER_CLIENT_ID"
    update_env_var "GITEA_OIDC_CLIENT_ID" "$GITEA_CLIENT_ID"
    update_env_var "GITEA_OIDC_CLIENT_SECRET" "$GITEA_CLIENT_SECRET"
    update_env_var "MINIO_IDENTITY_OPENID_CLIENT_ID" "$MINIO_CLIENT_ID"
    update_env_var "MINIO_IDENTITY_OPENID_CLIENT_SECRET" "$MINIO_CLIENT_SECRET"
    update_env_var "PLATFORM_ADMIN_OIDC_CLIENT_ID" "$PLATFORM_ADMIN_CLIENT_ID"
    update_env_var "PLATFORM_ADMIN_OIDC_CLIENT_SECRET" "$PLATFORM_ADMIN_CLIENT_SECRET"
    update_env_var "LITELLM_OIDC_CLIENT_ID" "$LITELLM_CLIENT_ID"
    update_env_var "LITELLM_OIDC_CLIENT_SECRET" "$LITELLM_CLIENT_SECRET"

    # Clean up sed backup file
    rm -f "${ENV_FILE}.bak"

    echo -e "${GREEN}✓ .env updated with OIDC secrets${NC}"
else
    echo -e "${YELLOW}  Warning: ${ENV_FILE} not found. Create it from .env.example first.${NC}"
fi

# -----------------------------------------------------------------------------
# Step 6: Verify configuration
# docker-compose.yml reads OIDC secrets from .env via ${VAR} references
# No overlay file needed — .env is the single source of truth
# -----------------------------------------------------------------------------
echo -e "${BLUE}[6/6] Verifying configuration...${NC}"

# Remove stale overlay if it exists (secrets were hardcoded and go stale)
if [ -f "${PROJECT_DIR}/docker-compose.sso.yml" ]; then
    rm -f "${PROJECT_DIR}/docker-compose.sso.yml"
    echo "  Removed stale docker-compose.sso.yml (secrets now managed via .env)"
fi

if grep -q "CODER_OIDC_ISSUER_URL" "${PROJECT_DIR}/docker-compose.yml" 2>/dev/null; then
    echo -e "${GREEN}✓ OIDC config found in docker-compose.yml${NC}"
else
    echo -e "${YELLOW}  Warning: OIDC config not found in docker-compose.yml${NC}"
    echo "  Add CODER_OIDC_* environment variables to the coder service"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo -e "${GREEN}=== SSO Setup Complete ===${NC}"
echo ""
echo "OAuth2 Credentials:"
echo "-------------------"
echo "Coder:          ID=${CODER_CLIENT_ID}"
echo "Gitea:          ID=${GITEA_CLIENT_ID}"
echo "MinIO:          ID=${MINIO_CLIENT_ID}"
echo "Platform Admin: ID=${PLATFORM_ADMIN_CLIENT_ID}"
echo "LiteLLM:        ID=${LITELLM_CLIENT_ID}"
echo ""
echo "Files updated:"
echo "  - ${ENV_FILE} (OIDC secrets for Docker Compose)"
echo "  - ${SSO_ENV_FILE} (reference copy)"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo -e "${RED}0. REQUIRED - Add hosts entries (one-time):${NC}"
echo "   sudo sh -c 'echo \"127.0.0.1    host.docker.internal authentik-server\" >> /etc/hosts'"
echo "   This allows your browser to reach Coder (OIDC) and the SSO server."
echo ""
echo "1. Restart services to pick up new secrets:"
echo "   docker compose up -d coder minio"
echo ""
echo "2. Configure Gitea OIDC (one-time):"
echo "   a. Go to http://localhost:3000/admin/auths/new"
echo "   b. Authentication Type: OAuth2"
echo "   c. Provider: OpenID Connect"
echo "   d. Authentication Name: Authentik"
echo "   e. Client ID: ${GITEA_CLIENT_ID}"
echo "   f. Client Secret: ${GITEA_CLIENT_SECRET}"
echo "   g. OpenID Connect Auto Discovery URL:"
echo "      ${AUTHENTIK_INTERNAL_URL}/application/o/gitea/.well-known/openid-configuration"
echo ""
echo "3. Test SSO login:"
echo "   - Coder: https://host.docker.internal:7443 (accept cert warning, click 'Login with OIDC')"
echo "     NOTE: HTTPS required for extension webviews. Accept the self-signed cert warning."
echo "   - MinIO: http://localhost:9001 (click 'Login with SSO')"
echo "   - Platform Admin: http://localhost:5050 (click 'Sign in with Authentik SSO')
   - LiteLLM:        http://localhost:4000/ui (click 'SSO Login')"
echo ""
echo "4. Local fallback accounts (if Authentik is down):"
echo "   - Coder: admin@example.com / CoderAdmin123!"
echo "   - MinIO: minioadmin / minioadmin"
echo "   - Gitea: gitea / admin123"
echo ""
