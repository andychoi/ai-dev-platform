#!/bin/bash
# Coder WebIDE PoC - Cleanup Script
# This script removes all Coder PoC resources

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           Coder WebIDE PoC - Cleanup Script                   ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Confirm cleanup
if [ "${1:-}" != "--force" ] && [ "${1:-}" != "-f" ]; then
    echo -e "${YELLOW}WARNING: This will remove all Coder PoC data including:${NC}"
    echo "  - Docker containers (coder-server, coder-db)"
    echo "  - Docker volumes (postgres data, coder data)"
    echo "  - Workspace containers and volumes"
    echo "  - Docker images (optional)"
    echo ""
    read -p "Are you sure you want to continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cleanup cancelled."
        exit 0
    fi
fi

echo ""
echo -e "${BLUE}Stopping and removing Coder services...${NC}"

# Stop docker-compose services
cd "$POC_DIR"
if [ -f "docker-compose.yml" ]; then
    docker compose down -v 2>/dev/null || true
    echo -e "${GREEN}[✓]${NC} Docker Compose services stopped"
fi

# Remove workspace containers
echo ""
echo -e "${BLUE}Removing workspace containers...${NC}"
WORKSPACE_CONTAINERS=$(docker ps -a --filter "label=coder.workspace.id" -q 2>/dev/null || true)
if [ -n "$WORKSPACE_CONTAINERS" ]; then
    docker rm -f $WORKSPACE_CONTAINERS 2>/dev/null || true
    echo -e "${GREEN}[✓]${NC} Workspace containers removed"
else
    echo -e "${YELLOW}[!]${NC} No workspace containers found"
fi

# Remove workspace volumes
echo ""
echo -e "${BLUE}Removing workspace volumes...${NC}"
WORKSPACE_VOLUMES=$(docker volume ls --filter "name=coder-" -q 2>/dev/null || true)
if [ -n "$WORKSPACE_VOLUMES" ]; then
    docker volume rm $WORKSPACE_VOLUMES 2>/dev/null || true
    echo -e "${GREEN}[✓]${NC} Workspace volumes removed"
else
    echo -e "${YELLOW}[!]${NC} No workspace volumes found"
fi

# Remove named volumes
echo ""
echo -e "${BLUE}Removing PoC volumes...${NC}"
docker volume rm coder-poc-postgres coder-poc-data 2>/dev/null || true
echo -e "${GREEN}[✓]${NC} PoC volumes removed"

# Remove network
echo ""
echo -e "${BLUE}Removing Docker network...${NC}"
docker network rm coder-network 2>/dev/null || true
echo -e "${GREEN}[✓]${NC} Network removed"

# Optionally remove images
if [ "${1:-}" == "--images" ] || [ "${2:-}" == "--images" ]; then
    echo ""
    echo -e "${BLUE}Removing Docker images...${NC}"
    docker rmi ghcr.io/coder/coder:latest 2>/dev/null || true
    docker rmi postgres:15-alpine 2>/dev/null || true

    # Remove workspace images
    WORKSPACE_IMAGES=$(docker images --filter "reference=contractor-workspace*" -q 2>/dev/null || true)
    if [ -n "$WORKSPACE_IMAGES" ]; then
        docker rmi $WORKSPACE_IMAGES 2>/dev/null || true
    fi
    echo -e "${GREEN}[✓]${NC} Images removed"
fi

# Clean up Coder CLI config
if [ "${1:-}" == "--all" ] || [ "${2:-}" == "--all" ]; then
    echo ""
    echo -e "${BLUE}Removing Coder CLI configuration...${NC}"
    rm -rf ~/.config/coderv2 2>/dev/null || true
    rm -rf ~/.cache/coder 2>/dev/null || true
    echo -e "${GREEN}[✓]${NC} CLI configuration removed"
fi

echo ""
echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                    Cleanup Complete!                          ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo ""
echo "To reinstall, run:"
echo "  $SCRIPT_DIR/setup.sh"
echo ""
