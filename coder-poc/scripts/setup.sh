#!/bin/bash
# Coder WebIDE PoC - Full Setup Script
# This script sets up the complete Coder environment with SSO locally

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
CODER_PORT="${CODER_PORT:-7080}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-coderpassword}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-CoderAdmin123!}"

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║        Coder WebIDE PoC - Full Setup with SSO                 ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Function to print status
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    echo ""
    echo -e "${BLUE}[1/11] Checking prerequisites...${NC}"

    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        echo "  MacOS: brew install --cask docker"
        echo "  Linux: curl -fsSL https://get.docker.com | sh"
        exit 1
    fi
    print_status "Docker installed: $(docker --version | cut -d' ' -f3 | tr -d ',')"

    # Check Docker is running
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running. Please start Docker."
        exit 1
    fi
    print_status "Docker daemon is running"

    # Check Docker Compose
    if docker compose version &> /dev/null; then
        print_status "Docker Compose installed: $(docker compose version --short)"
    else
        print_error "Docker Compose is not installed."
        exit 1
    fi

    # Check jq
    if ! command -v jq &> /dev/null; then
        print_warning "jq not installed - some features may not work"
    fi

    # Check curl
    if ! command -v curl &> /dev/null; then
        print_error "curl is not installed."
        exit 1
    fi

    # Get Docker group ID for socket access
    if [[ "$(uname)" == "Linux" ]]; then
        export DOCKER_GID=$(getent group docker | cut -d: -f3 2>/dev/null || echo "999")
    else
        # Docker Desktop (Mac/Windows): socket is owned by root:root (GID 0)
        export DOCKER_GID=0
    fi
    print_status "Docker group ID: $DOCKER_GID"
}

# Check and add hosts entry
setup_hosts() {
    echo ""
    echo -e "${BLUE}[2/11] Checking hosts configuration...${NC}"

    # Check for host.docker.internal
    if grep -q "host.docker.internal" /etc/hosts 2>/dev/null; then
        print_status "host.docker.internal already in /etc/hosts"
    else
        print_warning "Adding host.docker.internal to /etc/hosts (requires sudo)"
        echo "127.0.0.1 host.docker.internal" | sudo tee -a /etc/hosts > /dev/null
        print_status "Added host.docker.internal to /etc/hosts"
    fi

    # Note: authentik-server hosts entry is not needed
    # OIDC uses host.docker.internal for both container and browser access
}

# Start infrastructure (without SSO first to let Authentik initialize)
start_infrastructure() {
    echo ""
    echo -e "${BLUE}[3/11] Starting infrastructure...${NC}"

    cd "$POC_DIR"

    # Export environment variables
    export POSTGRES_PASSWORD
    export CODER_ACCESS_URL="https://host.docker.internal:7443"

    # Pull images first
    print_info "Pulling Docker images (this may take a few minutes)..."
    docker compose pull --quiet

    # Start all services (base compose - Coder will start without OIDC initially)
    print_info "Starting services..."
    docker compose up -d

    # Wait for PostgreSQL
    print_info "Waiting for PostgreSQL..."
    for i in {1..30}; do
        if docker exec postgres pg_isready -U coder -d coder &> /dev/null; then
            print_status "PostgreSQL is ready"
            break
        fi
        sleep 1
        if [ $i -eq 30 ]; then
            print_error "PostgreSQL failed to start"
            exit 1
        fi
    done
}

# Wait for Authentik to be ready
wait_for_authentik() {
    echo ""
    echo -e "${BLUE}[4/11] Waiting for Authentik...${NC}"

    print_info "Authentik takes 30-60 seconds to initialize..."
    for i in {1..90}; do
        if curl -sf "http://localhost:9000/-/health/ready/" > /dev/null 2>&1; then
            print_status "Authentik is ready"
            return 0
        fi
        sleep 2
        if [ $((i % 10)) -eq 0 ]; then
            print_info "Still waiting for Authentik... ($i seconds)"
        fi
    done
    print_error "Authentik failed to start in time"
    docker compose logs authentik-server | tail -20
    exit 1
}

# Setup SSO (providers + applications)
setup_sso() {
    echo ""
    echo -e "${BLUE}[5/11] Setting up Authentik SSO...${NC}"

    cd "$POC_DIR"

    # Run the SSO setup script to create providers
    print_info "Creating OAuth2 providers..."
    if [ -f "$SCRIPT_DIR/setup-authentik-sso-full.sh" ]; then
        # Run SSO setup (suppress verbose output)
        "$SCRIPT_DIR/setup-authentik-sso-full.sh" 2>&1 | grep -E "(✓|Created|Error|error)" || true
        print_status "OAuth2 providers created"
    else
        print_error "SSO setup script not found"
        exit 1
    fi

    # Create Authentik applications
    print_info "Creating Authentik applications..."
    docker exec authentik-server ak shell -c "
from authentik.providers.oauth2.models import OAuth2Provider
from authentik.core.models import Application

apps = [
    {'name': 'Coder', 'slug': 'coder', 'provider_name': 'Coder OIDC'},
    {'name': 'Gitea', 'slug': 'gitea', 'provider_name': 'Gitea OIDC'},
    {'name': 'MinIO', 'slug': 'minio', 'provider_name': 'MinIO OIDC'},
    {'name': 'Platform Admin', 'slug': 'platform-admin', 'provider_name': 'Platform Admin OIDC'},
    {'name': 'LiteLLM', 'slug': 'litellm', 'provider_name': 'LiteLLM OIDC'},
]

for a in apps:
    try:
        provider = OAuth2Provider.objects.get(name=a['provider_name'])
        app, created = Application.objects.get_or_create(
            slug=a['slug'],
            defaults={'name': a['name'], 'provider': provider}
        )
        if not created:
            app.provider = provider
            app.save()
    except Exception as e:
        pass
" 2>&1 | grep -v "^{" || true

    # Verify OIDC endpoint
    sleep 2
    if curl -sf "http://localhost:9000/application/o/coder/.well-known/openid-configuration" | grep -q "issuer"; then
        print_status "OIDC endpoint verified"
    else
        print_warning "OIDC endpoint may not be ready yet"
    fi
}

# Restart Coder with SSO
restart_with_sso() {
    echo ""
    echo -e "${BLUE}[6/11] Restarting Coder with SSO...${NC}"

    cd "$POC_DIR"

    # Recreate containers to pick up new OIDC secrets from .env
    # No overlay needed — docker-compose.yml reads secrets via ${VAR} from .env
    print_info "Applying SSO configuration..."
    docker compose up -d coder minio platform-admin 2>&1 | grep -v "^time=" || true

    # Wait for Coder to be ready
    print_info "Waiting for Coder to restart..."
    sleep 5
    for i in {1..30}; do
        if curl -sf "http://localhost:${CODER_PORT}/api/v2/buildinfo" > /dev/null 2>&1; then
            print_status "Coder is ready with SSO"
            break
        fi
        sleep 2
        if [ $i -eq 30 ]; then
            print_error "Coder failed to restart"
            docker logs coder-server 2>&1 | tail -10
            exit 1
        fi
    done

    # Verify GitHub login is disabled
    if docker inspect coder-server --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -q "GITHUB_DEFAULT_PROVIDER_ENABLE=false"; then
        print_status "GitHub login disabled"
    fi

    if docker inspect coder-server --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -q "CODER_OIDC_ISSUER_URL"; then
        print_status "OIDC configured"
    fi
}

# Create first user
create_admin_user() {
    echo ""
    echo -e "${BLUE}[7/11] Creating admin user...${NC}"

    # Check if first user already exists
    FIRST_USER_CHECK=$(curl -sf "http://localhost:${CODER_PORT}/api/v2/users/first" 2>/dev/null || echo "error")
    if echo "$FIRST_USER_CHECK" | grep -q '"first_user":false'; then
        print_warning "Admin user already exists, skipping creation"
        return
    fi

    # Create first user using the API
    print_info "Creating admin user..."
    RESPONSE=$(curl -sf -X POST "http://localhost:${CODER_PORT}/api/v2/users/first" \
        -H "Content-Type: application/json" \
        -d "{
            \"username\": \"${ADMIN_USER}\",
            \"email\": \"${ADMIN_EMAIL}\",
            \"password\": \"${ADMIN_PASSWORD}\"
        }" 2>/dev/null || echo "error")

    if echo "$RESPONSE" | grep -q "session_token"; then
        print_status "Admin user created: ${ADMIN_EMAIL}"
    else
        print_warning "Admin user may already exist or creation failed"
    fi
}

# Push workspace template
push_template() {
    echo ""
    echo -e "${BLUE}[8/11] Pushing workspace template...${NC}"

    cd "$POC_DIR"

    # Call setup-workspace.sh which handles:
    # - Building Docker image
    # - Authenticating with Coder
    # - Pushing template via Docker (no host CLI required)
    if [ -f "$SCRIPT_DIR/setup-workspace.sh" ]; then
        print_info "Running workspace setup script..."
        CODER_URL="http://localhost:${CODER_PORT}" \
        CODER_ADMIN_EMAIL="${ADMIN_EMAIL}" \
        CODER_ADMIN_USERNAME="${ADMIN_USER}" \
        CODER_ADMIN_PASSWORD="${ADMIN_PASSWORD}" \
        "$SCRIPT_DIR/setup-workspace.sh" 2>&1 | grep -E "(SUCCESS|✓|success|pushed|Created|template|built|skipping|INFO|ERROR|WARN|Pushing|Building|Verifying|Copying)" || true
        print_status "Template setup complete"
    else
        print_warning "setup-workspace.sh not found - template not pushed"
        print_info "Manually run: ./scripts/setup-workspace.sh"
    fi
}

# Setup additional services
setup_additional_services() {
    echo ""
    echo -e "${BLUE}[9/11] Setting up additional services...${NC}"

    cd "$POC_DIR"

    # Setup Gitea users if script exists
    if [ -f "$SCRIPT_DIR/setup-gitea.sh" ]; then
        print_info "Setting up Gitea users and repositories..."
        "$SCRIPT_DIR/setup-gitea.sh" 2>&1 | grep -E "(✓|Created|already exists)" || true
        print_status "Gitea configured"
    fi
}

# Setup LiteLLM virtual keys
setup_litellm_keys() {
    echo ""
    echo -e "${BLUE}[10/11] Setting up LiteLLM virtual keys...${NC}"

    cd "$POC_DIR"

    if [ -f "$SCRIPT_DIR/setup-litellm-keys.sh" ]; then
        print_info "Generating per-user API keys for AI assistant (Roo Code)..."
        "$SCRIPT_DIR/setup-litellm-keys.sh" 2>&1 | grep -E "(✓|created|exists|FAILED|ready|complete)" || true
        if [ -f /tmp/litellm-keys.txt ] && [ -s /tmp/litellm-keys.txt ]; then
            print_status "LiteLLM virtual keys created ($(wc -l < /tmp/litellm-keys.txt | tr -d ' ') keys)"
            print_info "Keys saved to /tmp/litellm-keys.txt"
            print_info "Use these keys when creating workspaces (paste into 'LiteLLM API Key' field)"
        else
            print_warning "No keys file found — LiteLLM may not be running"
        fi
    else
        print_warning "setup-litellm-keys.sh not found — AI keys not provisioned"
        print_info "Roo Code will not work in workspaces without virtual keys"
    fi
}

# Setup test users (Coder, Gitea, Authentik)
setup_test_users() {
    echo ""
    echo -e "${BLUE}[11/11] Creating test users...${NC}"

    cd "$POC_DIR"

    # Setup test users if script exists
    if [ -f "$SCRIPT_DIR/setup-test-users.sh" ]; then
        print_info "Creating test users in Coder, Gitea, and Authentik..."
        "$SCRIPT_DIR/setup-test-users.sh" 2>&1 | grep -E "(✓|Created|already exists|OK|SUCCESS)" || true
        print_status "Test users created"
    else
        print_warning "setup-test-users.sh not found"
    fi
}

# Print summary
print_summary() {
    echo ""
    echo -e "${GREEN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                    Setup Complete!                            ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo ""
    echo -e "${BLUE}Access URLs:${NC}"
    echo "  ┌─────────────────┬───────────────────────────────────────────┐"
    echo "  │ Demo Portal     │ http://localhost:3333                     │"
    echo "  │ Coder WebIDE    │ https://host.docker.internal:7443        │"
    echo "  │ Authentik SSO   │ http://localhost:9000                     │"
    echo "  │ Gitea (Git)     │ http://localhost:3000                     │"
    echo "  │ MinIO Storage   │ http://localhost:9001                     │"
    echo "  │ Platform Admin  │ http://localhost:5050                     │"
    echo "  │ Drone CI        │ http://localhost:8080                     │"
    echo "  │ LiteLLM (AI)    │ http://localhost:4000                     │"
    echo "  └─────────────────┴───────────────────────────────────────────┘"

    echo ""
    echo -e "${BLUE}Credentials:${NC}"
    echo "  ┌─────────────────┬─────────────────────┬─────────────────────┐"
    echo "  │ Service         │ Username            │ Password            │"
    echo "  ├─────────────────┼─────────────────────┼─────────────────────┤"
    echo "  │ Coder           │ ${ADMIN_EMAIL}     │ ${ADMIN_PASSWORD}          │"
    echo "  │ Authentik       │ akadmin             │ admin               │"
    echo "  │ Gitea           │ gitea               │ admin123            │"
    echo "  │ MinIO           │ minioadmin          │ minioadmin          │"
    echo "  └─────────────────┴─────────────────────┴─────────────────────┘"

    echo ""
    echo -e "${BLUE}Test Users (for SSO login):${NC}"
    echo "  ┌─────────────┬─────────────────────────┬─────────────────────┐"
    echo "  │ Username    │ Email                   │ Password            │"
    echo "  ├─────────────┼─────────────────────────┼─────────────────────┤"
    echo "  │ appmanager  │ appmanager@example.com  │ password123         │"
    echo "  │ contractor1 │ contractor1@example.com │ password123         │"
    echo "  │ contractor2 │ contractor2@example.com │ password123         │"
    echo "  │ contractor3 │ contractor3@example.com │ password123         │"
    echo "  │ readonly    │ readonly@example.com    │ password123         │"
    echo "  └─────────────┴─────────────────────────┴─────────────────────┘"

    echo ""
    echo -e "${BLUE}SSO Login:${NC}"
    echo "  1. Go to https://host.docker.internal:7443 (accept self-signed cert warning)"
    echo "  2. Click 'Login with OIDC'"
    echo "  3. Use any test user above OR Authentik admin (akadmin / admin)"
    echo ""
    echo -e "${YELLOW}IMPORTANT:${NC} Always use https://host.docker.internal:7443 (HTTPS required for webviews)"

    echo ""
    echo -e "${BLUE}Quick Commands:${NC}"
    echo "  View logs:        docker compose logs -f"
    echo "  Stop all:         docker compose down"
    echo "  Restart with SSO: docker compose up -d"
    echo "  Run validation:   ./scripts/validate.sh"

    echo ""
    echo -e "${BLUE}LiteLLM Virtual Keys (for AI Assistant):${NC}"
    if [ -f /tmp/litellm-keys.txt ] && [ -s /tmp/litellm-keys.txt ]; then
        echo "  ┌─────────────┬──────────────────────────────────────────────┐"
        while IFS='=' read -r user key; do
            printf "  │ %-11s │ %-44s │\n" "$user" "${key:0:44}"
        done < /tmp/litellm-keys.txt
        echo "  └─────────────┴──────────────────────────────────────────────┘"
        echo ""
        echo "  Paste the user's key into the 'LiteLLM API Key' field when creating a workspace."
    else
        echo "  No keys generated. Run: ./scripts/setup-litellm-keys.sh"
    fi

    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "  1. Open https://host.docker.internal:7443 in your browser (accept cert warning)"
    echo "  2. Login via OIDC (Authentik)"
    echo "  3. Create a workspace from 'contractor-workspace' template"
    echo "     - Paste the user's LiteLLM key into the 'LiteLLM API Key' field"
    echo "  4. Click 'code-server' to open VS Code in browser"
    echo "  5. Open Roo Code (sidebar icon) — AI chat should work immediately"

    # Open portal in browser
    if command -v open &>/dev/null; then
        open "http://localhost:3333"
    elif command -v xdg-open &>/dev/null; then
        xdg-open "http://localhost:3333"
    else
        echo "  Open http://localhost:3333 in your browser to get started"
    fi

    echo ""
}

# Main execution
main() {
    check_prerequisites
    setup_hosts
    start_infrastructure
    wait_for_authentik
    setup_sso
    restart_with_sso
    create_admin_user
    push_template
    setup_additional_services
    setup_litellm_keys
    setup_test_users
    print_summary
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --clean        Remove all data and start fresh"
        echo "  --no-sso       Setup without SSO (basic mode)"
        echo ""
        echo "Environment Variables:"
        echo "  CODER_PORT         Port for Coder UI (default: 7080)"
        echo "  ADMIN_USER         Admin username (default: admin)"
        echo "  ADMIN_EMAIL        Admin email (default: admin@example.com)"
        echo "  ADMIN_PASSWORD     Admin password (default: CoderAdmin123!)"
        exit 0
        ;;
    --clean)
        echo -e "${YELLOW}Cleaning up existing installation...${NC}"
        cd "$POC_DIR"
        docker compose down -v 2>/dev/null || true
        print_status "Cleanup complete"
        echo ""
        main
        ;;
    --no-sso)
        echo -e "${YELLOW}Setting up without SSO...${NC}"
        check_prerequisites
        setup_hosts
        start_infrastructure
        create_admin_user
        echo ""
        echo -e "${GREEN}Basic setup complete (no SSO)${NC}"
        echo "Access Coder at: http://localhost:${CODER_PORT}"
        ;;
    *)
        main
        ;;
esac
