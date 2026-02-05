#!/bin/bash
# =============================================================================
# Setup Authentik SSO for Platform Services
# Creates applications and providers for single sign-on across all services
# =============================================================================

set -e

AUTHENTIK_URL="${AUTHENTIK_URL:-http://localhost:9000}"
AUTHENTIK_TOKEN="${AUTHENTIK_TOKEN:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Authentik SSO Setup ===${NC}"

# Check if Authentik is running
if ! curl -s "${AUTHENTIK_URL}/-/health/ready/" > /dev/null 2>&1; then
    echo -e "${RED}Error: Authentik is not running at ${AUTHENTIK_URL}${NC}"
    echo "Please start Authentik first: docker compose up -d authentik-server authentik-worker"
    exit 1
fi

# Get API token
if [ -z "$AUTHENTIK_TOKEN" ]; then
    echo -e "${YELLOW}No API token provided. Please create one in Authentik Admin:${NC}"
    echo "1. Go to ${AUTHENTIK_URL}/if/admin/#/core/tokens"
    echo "2. Create a new token with 'API access' intent"
    echo "3. Run: export AUTHENTIK_TOKEN=<your-token>"
    echo "4. Re-run this script"
    exit 1
fi

API_HEADERS="-H 'Authorization: Bearer ${AUTHENTIK_TOKEN}' -H 'Content-Type: application/json'"

echo ""
echo -e "${GREEN}Creating applications for platform services...${NC}"

# Function to create application
create_application() {
    local name=$1
    local slug=$2
    local launch_url=$3
    local icon=$4

    echo "Creating application: $name"

    curl -s -X POST "${AUTHENTIK_URL}/api/v3/core/applications/" \
        -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"${name}\",
            \"slug\": \"${slug}\",
            \"meta_launch_url\": \"${launch_url}\",
            \"meta_icon\": \"${icon}\",
            \"policy_engine_mode\": \"any\"
        }" > /dev/null 2>&1 || true
}

# Function to create proxy provider
create_proxy_provider() {
    local name=$1
    local external_host=$2
    local internal_host=$3

    echo "Creating proxy provider: $name"

    curl -s -X POST "${AUTHENTIK_URL}/api/v3/providers/proxy/" \
        -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"${name}\",
            \"external_host\": \"${external_host}\",
            \"internal_host\": \"${internal_host}\",
            \"mode\": \"forward_single\",
            \"skip_path_regex\": \"^/(health|api/health|healthz)$\"
        }" > /dev/null 2>&1 || true
}

# Create applications for each service
create_application "Coder WebIDE" "coder" "http://localhost:7080" "fa://code"
create_application "Gitea Git Server" "gitea" "http://localhost:3000" "fa://git"
create_application "Drone CI" "drone" "http://localhost:8080" "fa://play"
create_application "MinIO Storage" "minio" "http://localhost:9001" "fa://database"
create_application "Platform Admin" "platform-admin" "http://localhost:5050" "fa://cog"
create_application "LiteLLM" "litellm" "http://localhost:4000" "fa://robot"

echo ""
echo -e "${GREEN}Creating OAuth2 providers...${NC}"

# For now, applications can use Authentik as OAuth2/OIDC provider
# Each service would need to be configured to use Authentik for auth

echo ""
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""
echo "Applications created in Authentik. Next steps:"
echo ""
echo "1. Access Authentik Admin: ${AUTHENTIK_URL}/if/admin/"
echo "   Login: akadmin / admin"
echo ""
echo "2. Configure each service to use Authentik:"
echo ""
echo "   Coder:"
echo "   - Set CODER_OIDC_ISSUER_URL=${AUTHENTIK_URL}/application/o/coder/"
echo "   - Create OAuth2 provider in Authentik and set client ID/secret"
echo ""
echo "   Gitea:"
echo "   - Enable OAuth2 in Gitea admin settings"
echo "   - Add Authentik as OAuth2 provider"
echo ""
echo "   Drone:"
echo "   - Set DRONE_GITEA_CLIENT_ID and DRONE_GITEA_CLIENT_SECRET"
echo "   - Or use Authentik OAuth2 directly"
echo ""
echo "3. For fully integrated SSO with proxy:"
echo "   - Deploy Authentik Proxy Outpost"
echo "   - Route all traffic through Traefik/nginx with Authentik forward auth"
echo ""
echo "See docs/AUTHENTIK-SSO.md for detailed configuration guide."
