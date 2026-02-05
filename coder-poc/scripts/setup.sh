#!/bin/bash
# Coder WebIDE PoC - Setup Script
# This script sets up the complete Coder environment locally

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
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@local.test}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-SecureP@ssw0rd!}"

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           Coder WebIDE PoC - Setup Script                     ║"
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
    echo -e "${BLUE}Checking prerequisites...${NC}"

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
    elif command -v docker-compose &> /dev/null; then
        print_warning "Using legacy docker-compose command"
        COMPOSE_CMD="docker-compose"
    else
        print_error "Docker Compose is not installed."
        exit 1
    fi

    # Check available resources
    echo ""
    print_info "Checking system resources..."

    # Get Docker group ID for Linux
    if [[ "$(uname)" == "Linux" ]]; then
        export DOCKER_GID=$(getent group docker | cut -d: -f3 2>/dev/null || echo "999")
        print_status "Docker group ID: $DOCKER_GID"
    else
        export DOCKER_GID=999
    fi
}

# Start Coder infrastructure
start_infrastructure() {
    echo ""
    echo -e "${BLUE}Starting Coder infrastructure...${NC}"

    cd "$POC_DIR"

    # Export environment variables
    export POSTGRES_PASSWORD
    # Use host.docker.internal so workspace containers can reach Coder server
    export CODER_ACCESS_URL="http://host.docker.internal:${CODER_PORT}"

    # Pull images first
    print_info "Pulling Docker images..."
    docker compose pull

    # Start services
    print_info "Starting services..."
    docker compose up -d

    # Wait for PostgreSQL
    print_info "Waiting for PostgreSQL to be ready..."
    for i in {1..30}; do
        if docker exec coder-db pg_isready -U coder -d coder &> /dev/null; then
            print_status "PostgreSQL is ready"
            break
        fi
        sleep 1
        if [ $i -eq 30 ]; then
            print_error "PostgreSQL failed to start in time"
            docker compose logs postgres
            exit 1
        fi
    done

    # Wait for Coder
    print_info "Waiting for Coder to be ready..."
    for i in {1..60}; do
        if curl -s "http://localhost:${CODER_PORT}/api/v2/buildinfo" &> /dev/null; then
            print_status "Coder is ready"
            break
        fi
        sleep 2
        if [ $i -eq 60 ]; then
            print_error "Coder failed to start in time"
            docker compose logs coder
            exit 1
        fi
    done
}

# Create first user
create_admin_user() {
    echo ""
    echo -e "${BLUE}Creating admin user...${NC}"

    # Check if first user already exists
    if curl -s "http://localhost:${CODER_PORT}/api/v2/users/first" | grep -q "true"; then
        print_warning "Admin user already exists, skipping creation"
        return
    fi

    # Create first user using the API
    RESPONSE=$(curl -s -X POST "http://localhost:${CODER_PORT}/api/v2/users/first" \
        -H "Content-Type: application/json" \
        -d "{
            \"username\": \"${ADMIN_USER}\",
            \"email\": \"${ADMIN_EMAIL}\",
            \"password\": \"${ADMIN_PASSWORD}\"
        }")

    if echo "$RESPONSE" | grep -q "session_token"; then
        print_status "Admin user created successfully"
    else
        print_warning "Could not create admin user via API, trying CLI..."
        docker exec coder-server coder login "http://localhost:7080" \
            --first-user-username "$ADMIN_USER" \
            --first-user-email "$ADMIN_EMAIL" \
            --first-user-password "$ADMIN_PASSWORD" 2>/dev/null || true
    fi
}

# Install Coder CLI locally
install_coder_cli() {
    echo ""
    echo -e "${BLUE}Setting up Coder CLI...${NC}"

    if command -v coder &> /dev/null; then
        print_status "Coder CLI already installed: $(coder version 2>/dev/null | head -1)"
    else
        print_info "Installing Coder CLI..."
        curl -fsSL https://coder.com/install.sh | sh
        print_status "Coder CLI installed"
    fi
}

# Configure Coder CLI
configure_cli() {
    echo ""
    echo -e "${BLUE}Configuring Coder CLI...${NC}"

    # Login to local Coder instance
    print_info "Logging into Coder..."

    # Use expect-like approach with timeout
    echo "$ADMIN_PASSWORD" | timeout 10 coder login "http://localhost:${CODER_PORT}" \
        --username "$ADMIN_USER" 2>/dev/null || {
        print_warning "Auto-login failed. Please login manually:"
        echo "  coder login http://localhost:${CODER_PORT}"
    }
}

# Push workspace template
push_template() {
    echo ""
    echo -e "${BLUE}Creating workspace template...${NC}"

    cd "$POC_DIR/templates/contractor-workspace"

    # Check if template exists
    if coder templates list 2>/dev/null | grep -q "contractor-workspace"; then
        print_warning "Template 'contractor-workspace' already exists"
        print_info "Updating template..."
        coder templates push contractor-workspace --directory . --yes 2>/dev/null || {
            print_warning "Template update requires manual intervention"
            echo "  cd $POC_DIR/templates/contractor-workspace"
            echo "  coder templates push contractor-workspace --directory . --yes"
        }
    else
        print_info "Creating new template..."
        coder templates create contractor-workspace --directory . --yes 2>/dev/null || {
            print_warning "Template creation requires manual intervention"
            echo "  cd $POC_DIR/templates/contractor-workspace"
            echo "  coder templates create contractor-workspace --directory ."
        }
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
    echo -e "${BLUE}Access Information:${NC}"
    echo "  URL:      http://localhost:${CODER_PORT}"
    echo "  Username: ${ADMIN_USER}"
    echo "  Password: ${ADMIN_PASSWORD}"

    echo ""
    echo -e "${BLUE}Quick Commands:${NC}"
    echo "  View logs:        docker compose -f $POC_DIR/docker-compose.yml logs -f"
    echo "  Stop Coder:       docker compose -f $POC_DIR/docker-compose.yml down"
    echo "  Create workspace: coder create my-workspace --template contractor-workspace"
    echo "  List workspaces:  coder list"
    echo "  SSH to workspace: coder ssh my-workspace"
    echo "  Run validation:   $SCRIPT_DIR/validate.sh"

    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "  1. Open http://localhost:${CODER_PORT} in your browser"
    echo "  2. Login with the credentials above"
    echo "  3. Create a new workspace from the 'contractor-workspace' template"
    echo "  4. Click 'VS Code' to open the web IDE"

    echo ""
}

# Main execution
main() {
    check_prerequisites
    start_infrastructure
    create_admin_user
    install_coder_cli
    configure_cli
    push_template
    print_summary
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --clean        Remove all Coder data and start fresh"
        echo ""
        echo "Environment Variables:"
        echo "  CODER_PORT         Port for Coder UI (default: 7080)"
        echo "  ADMIN_USER         Admin username (default: admin)"
        echo "  ADMIN_EMAIL        Admin email (default: admin@local.test)"
        echo "  ADMIN_PASSWORD     Admin password (default: SecureP@ssw0rd!)"
        echo "  POSTGRES_PASSWORD  PostgreSQL password (default: coderpassword)"
        exit 0
        ;;
    --clean)
        echo -e "${YELLOW}Cleaning up existing Coder installation...${NC}"
        cd "$POC_DIR"
        docker compose down -v 2>/dev/null || true
        docker volume rm coder-poc-postgres coder-poc-data 2>/dev/null || true
        print_status "Cleanup complete"
        main
        ;;
    *)
        main
        ;;
esac
