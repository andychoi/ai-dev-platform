#!/bin/bash
# Coder WebIDE PoC - Complete Cleanup Script
# This script removes ALL PoC resources for a fresh start

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(dirname "$SCRIPT_DIR")"

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_info() { echo -e "${BLUE}[i]${NC} $1"; }

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║        Coder WebIDE PoC - Complete Cleanup Script             ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Show help
if [ "${1:-}" == "--help" ] || [ "${1:-}" == "-h" ]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force, -f    Skip confirmation prompt"
    echo "  --images       Also remove Docker images"
    echo "  --all          Remove everything including CLI config"
    echo "  --keep-images  Keep Docker images (faster reinstall)"
    echo "  --help, -h     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Interactive cleanup with confirmation"
    echo "  $0 --force      # Non-interactive cleanup"
    echo "  $0 --all        # Complete cleanup including CLI config"
    exit 0
fi

# Confirm cleanup
if [ "${1:-}" != "--force" ] && [ "${1:-}" != "-f" ]; then
    echo -e "${YELLOW}WARNING: This will remove ALL PoC data including:${NC}"
    echo ""
    echo "  Services (14 total):"
    echo "    - Coder server and workspaces"
    echo "    - Authentik (SSO) - users, groups, applications"
    echo "    - Gitea - repositories, users, settings"
    echo "    - MinIO - buckets and objects"
    echo "    - PostgreSQL - all databases"
    echo "    - Redis, Drone CI, AI Gateway, DevDB, TestDB"
    echo ""
    echo "  Data:"
    echo "    - All Docker volumes"
    echo "    - Generated SSO configuration (.env.sso)"
    echo "    - Workspace containers and data"
    echo ""
    read -p "Are you sure you want to continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cleanup cancelled."
        exit 0
    fi
fi

echo ""

# =============================================================================
# Step 1: Stop all Docker Compose services
# =============================================================================
echo -e "${BLUE}[1/7] Stopping all services...${NC}"

cd "$POC_DIR"

# Stop base compose with volumes
if [ -f "docker-compose.yml" ]; then
    docker compose down -v 2>/dev/null || true
    print_status "All services stopped"
else
    print_warning "docker-compose.yml not found"
fi

# =============================================================================
# Step 2: Remove workspace containers
# =============================================================================
echo ""
echo -e "${BLUE}[2/7] Removing workspace containers...${NC}"

# Coder workspace containers
WORKSPACE_CONTAINERS=$(docker ps -a --filter "label=coder.workspace.id" -q 2>/dev/null || true)
if [ -n "$WORKSPACE_CONTAINERS" ]; then
    docker rm -f $WORKSPACE_CONTAINERS 2>/dev/null || true
    print_status "Coder workspace containers removed"
else
    print_info "No workspace containers found"
fi

# Any containers with coder in the name
CODER_CONTAINERS=$(docker ps -a --filter "name=coder" -q 2>/dev/null || true)
if [ -n "$CODER_CONTAINERS" ]; then
    docker rm -f $CODER_CONTAINERS 2>/dev/null || true
    print_status "Additional Coder containers removed"
fi

# =============================================================================
# Step 3: Remove all volumes
# =============================================================================
echo ""
echo -e "${BLUE}[3/7] Removing Docker volumes...${NC}"

# Named volumes from docker-compose.yml (explicit name: values)
VOLUMES_TO_REMOVE=(
    "coder-poc-postgres"
    "coder-poc-data"
    "coder-poc-minio"
    "coder-poc-testdb"
    "coder-poc-devdb"
    "coder-poc-gitea"
    "coder-poc-drone"
    # "coder-poc-ai-gateway-logs"  # Deprecated: replaced by LiteLLM
    "coder-poc-authentik-redis"
    "coder-poc-authentik-media"
    "coder-poc-authentik-templates"
)

for vol in "${VOLUMES_TO_REMOVE[@]}"; do
    if docker volume inspect "$vol" &>/dev/null; then
        docker volume rm "$vol" 2>/dev/null || true
        print_status "Removed volume: $vol"
    fi
done

# Workspace volumes (coder-* pattern)
WORKSPACE_VOLUMES=$(docker volume ls --filter "name=coder-" -q 2>/dev/null || true)
if [ -n "$WORKSPACE_VOLUMES" ]; then
    echo "$WORKSPACE_VOLUMES" | xargs docker volume rm 2>/dev/null || true
    print_status "Workspace volumes removed"
fi

# Any remaining volumes with poc in the name
POC_VOLUMES=$(docker volume ls --filter "name=poc" -q 2>/dev/null || true)
if [ -n "$POC_VOLUMES" ]; then
    echo "$POC_VOLUMES" | xargs docker volume rm 2>/dev/null || true
    print_status "Additional PoC volumes removed"
fi

print_status "All volumes cleaned"

# =============================================================================
# Step 4: Remove networks
# =============================================================================
echo ""
echo -e "${BLUE}[4/7] Removing Docker networks...${NC}"

NETWORKS_TO_REMOVE=(
    "coder-poc_default"
    "coder-poc_coder-network"
    "coder-network"
)

for net in "${NETWORKS_TO_REMOVE[@]}"; do
    if docker network inspect "$net" &>/dev/null; then
        docker network rm "$net" 2>/dev/null || true
        print_status "Removed network: $net"
    fi
done

print_status "Networks cleaned"

# =============================================================================
# Step 5: Remove generated config files
# =============================================================================
echo ""
echo -e "${BLUE}[5/7] Removing generated configuration files...${NC}"

# Generated config files (regenerated by setup.sh)
FILES_TO_REMOVE=(
    "$POC_DIR/.env.sso"
    "$POC_DIR/docker-compose.sso.yml"
)

for file in "${FILES_TO_REMOVE[@]}"; do
    if [ -f "$file" ]; then
        rm -f "$file"
        print_status "Removed: $(basename $file)"
    fi
done

print_status "Config files cleaned"

# =============================================================================
# Step 6: Optionally remove Docker images
# =============================================================================
if [ "${1:-}" == "--images" ] || [ "${2:-}" == "--images" ] || [ "${1:-}" == "--all" ] || [ "${2:-}" == "--all" ]; then
    echo ""
    echo -e "${BLUE}[6/7] Removing Docker images...${NC}"

    IMAGES_TO_REMOVE=(
        "ghcr.io/coder/coder"
        "postgres"
        "redis"
        "ghcr.io/goauthentik/server"
        "gitea/gitea"
        "minio/minio"
        "drone/drone"
        "drone/drone-runner-docker"
        "axllent/mailpit"
    )

    for img in "${IMAGES_TO_REMOVE[@]}"; do
        if docker images "$img" -q | grep -q .; then
            docker rmi $(docker images "$img" -q) 2>/dev/null || true
            print_status "Removed image: $img"
        fi
    done

    # Remove workspace images
    WORKSPACE_IMAGES=$(docker images --filter "reference=*contractor-workspace*" -q 2>/dev/null || true)
    if [ -n "$WORKSPACE_IMAGES" ]; then
        docker rmi $WORKSPACE_IMAGES 2>/dev/null || true
        print_status "Workspace images removed"
    fi

    # Remove old AI gateway image (deprecated, replaced by LiteLLM)
    AI_GATEWAY_IMAGES=$(docker images --filter "reference=*ai-gateway*" -q 2>/dev/null || true)
    if [ -n "$AI_GATEWAY_IMAGES" ]; then
        docker rmi $AI_GATEWAY_IMAGES 2>/dev/null || true
        print_status "AI Gateway image removed"
    fi

    # Remove LiteLLM image
    LITELLM_IMAGES=$(docker images --filter "reference=*litellm*" -q 2>/dev/null || true)
    if [ -n "$LITELLM_IMAGES" ]; then
        docker rmi $LITELLM_IMAGES 2>/dev/null || true
        print_status "LiteLLM image removed"
    fi

    # Remove platform-admin image
    PLATFORM_IMAGES=$(docker images --filter "reference=*platform-admin*" -q 2>/dev/null || true)
    if [ -n "$PLATFORM_IMAGES" ]; then
        docker rmi $PLATFORM_IMAGES 2>/dev/null || true
        print_status "Platform Admin image removed"
    fi

    print_status "Images cleaned"
else
    echo ""
    echo -e "${BLUE}[6/7] Keeping Docker images...${NC}"
    print_info "Use --images to also remove Docker images"
fi

# =============================================================================
# Step 7: Optionally clean CLI config
# =============================================================================
if [ "${1:-}" == "--all" ] || [ "${2:-}" == "--all" ]; then
    echo ""
    echo -e "${BLUE}[7/7] Removing Coder CLI configuration...${NC}"

    # Coder CLI config
    rm -rf ~/.config/coderv2 2>/dev/null || true
    rm -rf ~/.cache/coder 2>/dev/null || true
    print_status "Coder CLI configuration removed"

    # Remove session tokens
    rm -f ~/.coder-session 2>/dev/null || true
    print_status "Session tokens removed"
else
    echo ""
    echo -e "${BLUE}[7/7] Keeping CLI configuration...${NC}"
    print_info "Use --all to also remove Coder CLI config"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                    Cleanup Complete!                          ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo ""
echo -e "${BLUE}What was removed:${NC}"
echo "  [✓] All 14 Docker services"
echo "  [✓] All database data (PostgreSQL, Redis)"
echo "  [✓] Authentik SSO configuration"
echo "  [✓] Gitea repositories and users"
echo "  [✓] MinIO buckets and objects"
echo "  [✓] All workspace containers and volumes"
echo "  [✓] Generated SSO config files"

if [ "${1:-}" == "--images" ] || [ "${2:-}" == "--images" ] || [ "${1:-}" == "--all" ]; then
    echo "  [✓] Docker images"
fi

if [ "${1:-}" == "--all" ] || [ "${2:-}" == "--all" ]; then
    echo "  [✓] Coder CLI configuration"
fi

echo ""
echo -e "${BLUE}To reinstall from scratch:${NC}"
echo "  cd $POC_DIR"
echo "  ./scripts/setup.sh"
echo ""
echo -e "${BLUE}To reinstall with fresh data but keep images (faster):${NC}"
echo "  ./scripts/setup.sh"
echo ""
