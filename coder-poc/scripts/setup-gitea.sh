#!/bin/bash
# Gitea Setup Script
# Creates users, organizations, and sample repositories for PoC testing
# Migrated from Gogs setup script

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
GITEA_URL="${GITEA_URL:-http://localhost:3000}"
GITEA_ADMIN_USER="gitea"
GITEA_ADMIN_PASSWORD="admin123"
GITEA_ADMIN_EMAIL="admin@local.test"

echo -e "${BLUE}"
echo "=========================================="
echo "     Gitea Git Server Setup Script       "
echo "=========================================="
echo -e "${NC}"

# Wait for Gitea to be ready
echo -e "${BLUE}Waiting for Gitea to be ready...${NC}"
max_attempts=30
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if curl -s "${GITEA_URL}/api/healthz" > /dev/null 2>&1; then
        echo -e "${GREEN}[OK]${NC} Gitea is ready"
        break
    fi
    attempt=$((attempt + 1))
    echo "  Waiting... (attempt $attempt/$max_attempts)"
    sleep 2
done

if [ $attempt -eq $max_attempts ]; then
    echo -e "${RED}[FAIL]${NC} Gitea is not responding at ${GITEA_URL}"
    exit 1
fi

# Check if Gitea needs initial setup
echo ""
echo -e "${BLUE}Checking Gitea installation status...${NC}"

# Function to make API calls
gitea_api() {
    local method="$1"
    local endpoint="$2"
    local data="$3"

    if [ -n "$data" ]; then
        curl -s -X "$method" \
            -H "Content-Type: application/json" \
            -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" \
            -d "$data" \
            "${GITEA_URL}/api/v1${endpoint}"
    else
        curl -s -X "$method" \
            -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" \
            "${GITEA_URL}/api/v1${endpoint}"
    fi
}

# Create admin user if not exists (via docker exec)
echo ""
echo -e "${BLUE}Setting up admin user...${NC}"

docker exec -u git gitea gitea admin user list --config /data/gitea/conf/app.ini 2>/dev/null | grep -q "${GITEA_ADMIN_USER}" && {
    echo "Admin user already exists"
} || {
    docker exec -u git gitea gitea admin user create \
        --username "${GITEA_ADMIN_USER}" \
        --password "${GITEA_ADMIN_PASSWORD}" \
        --email "${GITEA_ADMIN_EMAIL}" \
        --admin \
        --must-change-password=false \
        --config /data/gitea/conf/app.ini 2>/dev/null || true
    echo "Admin user created"
}

echo -e "${GREEN}[OK]${NC} Admin user: ${GITEA_ADMIN_USER} / ${GITEA_ADMIN_PASSWORD}"

# =============================================================================
# Configure OIDC Authentication Source (Authentik)
# =============================================================================
echo ""
echo -e "${BLUE}Configuring OIDC authentication (Authentik)...${NC}"

GITEA_OIDC_CLIENT_ID="${GITEA_OIDC_CLIENT_ID:-gitea}"
GITEA_OIDC_CLIENT_SECRET="${GITEA_OIDC_CLIENT_SECRET:-}"
OIDC_DISCOVERY_URL="http://host.docker.internal:9000/application/o/gitea/.well-known/openid-configuration"

# Source .env if client secret not set
if [ -z "$GITEA_OIDC_CLIENT_SECRET" ] && [ -f "$POC_DIR/.env" ]; then
    GITEA_OIDC_CLIENT_SECRET=$(grep '^GITEA_OIDC_CLIENT_SECRET=' "$POC_DIR/.env" 2>/dev/null | cut -d= -f2 | tr -d '"' | tr -d "'" || true)
fi

if [ -n "$GITEA_OIDC_CLIENT_SECRET" ]; then
    # Check if auth source already exists
    if docker exec -u git gitea gitea admin auth list --config /data/gitea/conf/app.ini 2>/dev/null | grep -q "Authentik"; then
        echo -e "  ${YELLOW}[!]${NC} OIDC auth source 'Authentik' already exists"
    else
        docker exec -u git gitea gitea admin auth add-oauth \
            --name "Authentik" \
            --provider "openidConnect" \
            --key "$GITEA_OIDC_CLIENT_ID" \
            --secret "$GITEA_OIDC_CLIENT_SECRET" \
            --auto-discover-url "$OIDC_DISCOVERY_URL" \
            --scopes "openid" --scopes "profile" --scopes "email" \
            --config /data/gitea/conf/app.ini 2>/dev/null
        echo -e "  ${GREEN}[OK]${NC} OIDC auth source created (Authentik)"
    fi
else
    echo -e "  ${YELLOW}[!]${NC} GITEA_OIDC_CLIENT_SECRET not set — skipping OIDC setup"
    echo "       Run setup-authentik-sso-full.sh first, then re-run this script"
fi

# =============================================================================
# Create Drone CI OAuth2 Application
# =============================================================================
echo ""
echo -e "${BLUE}Configuring Drone CI OAuth2 application...${NC}"

# Check if Drone OAuth2 app already exists
EXISTING_APPS=$(gitea_api "GET" "/user/applications/oauth2" 2>/dev/null)
if echo "$EXISTING_APPS" | grep -q '"Drone CI"'; then
    echo -e "  ${YELLOW}[!]${NC} Drone CI OAuth2 app already exists"
else
    DRONE_APP_RESULT=$(gitea_api "POST" "/user/applications/oauth2" '{
        "name": "Drone CI",
        "redirect_uris": ["http://localhost:8080/login"]
    }' 2>/dev/null)

    if echo "$DRONE_APP_RESULT" | grep -q '"client_id"'; then
        DRONE_CID=$(echo "$DRONE_APP_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('client_id',''))" 2>/dev/null)
        DRONE_CSEC=$(echo "$DRONE_APP_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('client_secret',''))" 2>/dev/null)
        echo -e "  ${GREEN}[OK]${NC} Drone CI OAuth2 app created"

        # Update .env with Drone credentials
        if [ -f "$POC_DIR/.env" ]; then
            if grep -q "^DRONE_GITEA_CLIENT_ID=" "$POC_DIR/.env" 2>/dev/null; then
                sed -i.bak "s|^DRONE_GITEA_CLIENT_ID=.*|DRONE_GITEA_CLIENT_ID=${DRONE_CID}|" "$POC_DIR/.env"
                sed -i.bak "s|^DRONE_GITEA_CLIENT_SECRET=.*|DRONE_GITEA_CLIENT_SECRET=${DRONE_CSEC}|" "$POC_DIR/.env"
            else
                echo "DRONE_GITEA_CLIENT_ID=${DRONE_CID}" >> "$POC_DIR/.env"
                echo "DRONE_GITEA_CLIENT_SECRET=${DRONE_CSEC}" >> "$POC_DIR/.env"
            fi
            rm -f "$POC_DIR/.env.bak"
            echo -e "  ${GREEN}[OK]${NC} .env updated with Drone OAuth2 credentials"
        fi
    else
        echo -e "  ${YELLOW}[!]${NC} Failed to create Drone CI OAuth2 app"
    fi
fi

# Create contractor users via API
echo ""
echo -e "${BLUE}Creating contractor users...${NC}"

for userinfo in "contractor1:contractor1@example.com" "contractor2:contractor2@example.com" "contractor3:contractor3@example.com" "readonly:readonly@example.com"; do
    username="${userinfo%%:*}"
    email="${userinfo#*:}"

    result=$(gitea_api "POST" "/admin/users" "{
        \"username\": \"${username}\",
        \"email\": \"${email}\",
        \"password\": \"password123\",
        \"must_change_password\": false
    }" 2>/dev/null)

    if echo "$result" | grep -q '"id"'; then
        echo -e "  ${GREEN}[OK]${NC} Created: ${username}"
    else
        echo -e "  ${YELLOW}[!]${NC} ${username} (may already exist)"
    fi
done

echo -e "${GREEN}[OK]${NC} Contractor users created"

# Create sample repositories
echo ""
echo -e "${BLUE}Creating sample repositories...${NC}"

# Function to create a repo via API
create_repo() {
    local name="$1"
    local description="$2"
    local private="$3"

    result=$(gitea_api "POST" "/user/repos" "{
        \"name\": \"${name}\",
        \"description\": \"${description}\",
        \"private\": ${private},
        \"auto_init\": true,
        \"default_branch\": \"main\"
    }" 2>/dev/null)

    if echo "$result" | grep -q '"id"'; then
        echo -e "  ${GREEN}[OK]${NC} Created: ${name}"
    else
        echo -e "  ${YELLOW}[!]${NC} ${name} (may already exist)"
    fi
}

# Create repositories
create_repo "python-sample" "Sample Python application with CI pipeline" "false"
create_repo "frontend-app" "Sample frontend application" "false"
create_repo "private-project" "Private project - restricted access" "true"
create_repo "shared-libs" "Shared libraries for all projects" "false"

# Initialize python-sample with actual code
echo ""
echo -e "${BLUE}Initializing python-sample repository...${NC}"

# Create temporary directory for repo initialization
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Clone the repo
git clone "http://${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}@localhost:3000/${GITEA_ADMIN_USER}/python-sample.git" 2>/dev/null || true

if [ -d "python-sample" ]; then
    cd python-sample

    # Check if sample project files exist
    if [ -d "$POC_DIR/sample-projects/python-app" ]; then
        # Copy sample project files
        cp "$POC_DIR/sample-projects/python-app/app.py" . 2>/dev/null || true
        cp "$POC_DIR/sample-projects/python-app/test_app.py" . 2>/dev/null || true
        cp "$POC_DIR/sample-projects/python-app/requirements.txt" . 2>/dev/null || true
        cp "$POC_DIR/sample-projects/python-app/.drone.yml" . 2>/dev/null || true
    fi

    # Create README
    cat > README.md << 'EOF'
# Python Sample Application

A sample Python application demonstrating the Coder WebIDE PoC with CI/CD.

## Features

- Basic math functions
- Calculator class
- Prime number checker
- Fibonacci generator

## Development

```bash
# Install dependencies
pip install -r requirements.txt

# Run tests
pytest test_app.py -v

# Run application
python app.py
```

## CI Pipeline

This project uses Drone CI for continuous integration:

- **format-check**: Black code formatting
- **lint**: Flake8 linting
- **type-check**: MyPy type checking
- **test**: Pytest with coverage (80% minimum)
- **build**: Verification run

## Access Control

- `admin`: Full access (owner)
- `contractor1`, `contractor2`: Read/Write access
- `readonly`: Read-only access
EOF

    # Commit and push
    git config user.email "admin@local.test"
    git config user.name "Admin"
    git add -A
    git commit -m "Initial commit: Python sample application with CI" 2>/dev/null || true
    git push origin main 2>/dev/null || git push origin master 2>/dev/null || true

    echo -e "${GREEN}[OK]${NC} python-sample initialized with sample code"
else
    echo -e "${YELLOW}[!]${NC} Could not clone python-sample (may need manual setup)"
fi

# Cleanup
cd /
rm -rf "$TEMP_DIR"

# Set up access control (add collaborators)
echo ""
echo -e "${BLUE}Setting up access control...${NC}"

# Add collaborators via API
add_collaborator() {
    local repo="$1"
    local username="$2"
    local permission="$3"  # read, write, admin

    result=$(gitea_api "PUT" "/repos/${GITEA_ADMIN_USER}/${repo}/collaborators/${username}" "{
        \"permission\": \"${permission}\"
    }" 2>/dev/null)

    echo -e "  Added ${username} to ${repo} (${permission})"
}

# python-sample: contractor1 and contractor2 can write, readonly can read
add_collaborator "python-sample" "contractor1" "write"
add_collaborator "python-sample" "contractor2" "write"
add_collaborator "python-sample" "readonly" "read"

# private-project: only contractor1 has access
add_collaborator "private-project" "contractor1" "write"

# shared-libs: all contractors can read, only contractor3 can write
add_collaborator "shared-libs" "contractor1" "read"
add_collaborator "shared-libs" "contractor2" "read"
add_collaborator "shared-libs" "contractor3" "write"

echo -e "${GREEN}[OK]${NC} Access control configured"

# Summary
echo ""
echo -e "${GREEN}"
echo "=========================================="
echo "       Gitea Setup Complete!             "
echo "=========================================="
echo -e "${NC}"

echo ""
echo "Access Gitea at: ${GITEA_URL}"
echo ""
echo "Users created:"
echo "  - gitea / admin123 (Administrator)"
echo "  - contractor1 / password123"
echo "  - contractor2 / password123"
echo "  - contractor3 / password123"
echo "  - readonly / password123"
echo ""
echo "Repositories:"
echo "  - python-sample (public) - With CI pipeline"
echo "  - frontend-app (public)"
echo "  - private-project (private)"
echo "  - shared-libs (public)"
echo ""
echo "Access Control Matrix:"
echo "  +------------------+-------------+-------------+-------------+----------+"
echo "  | Repository       | contractor1 | contractor2 | contractor3 | readonly |"
echo "  +------------------+-------------+-------------+-------------+----------+"
echo "  | python-sample    | write       | write       | none        | read     |"
echo "  | private-project  | write       | none        | none        | none     |"
echo "  | shared-libs      | read        | read        | write       | none     |"
echo "  +------------------+-------------+-------------+-------------+----------+"
echo ""
echo "OIDC:"
if [ -n "$GITEA_OIDC_CLIENT_SECRET" ]; then
    echo "  SSO via Authentik is configured automatically."
    echo "  Login at ${GITEA_URL} and click 'Sign in with Authentik'"
else
    echo "  OIDC not configured (client secret missing)."
    echo "  Run setup-authentik-sso-full.sh, then re-run this script."
fi
echo ""
echo "Drone CI:"
echo "  OAuth2 app created in Gitea (credentials written to .env)"
echo "  Restart Drone after setup: docker compose up -d drone-server"
echo ""
