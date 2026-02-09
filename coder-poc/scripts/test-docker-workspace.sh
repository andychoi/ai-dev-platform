#!/bin/bash
# Docker Workspace Test Script for Coder WebIDE PoC
# Tests Docker workspace authorization, DinD sidecar, and isolation
#
# Prerequisites:
#   - docker-workspace image built: docker build -t docker-workspace:latest ./build
#   - docker-workspace template pushed: coder templates push docker-workspace
#   - "docker-users" group exists in Authentik
#   - At least one user IN the group and one NOT in the group
#
# Usage:
#   ./coder-poc/scripts/test-docker-workspace.sh [--skip-auth] [--workspace NAME]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CODER_URL="${CODER_URL:-http://localhost:7080}"
CODER_TOKEN="${CODER_SESSION_TOKEN:-}"
WORKSPACE_NAME="${WORKSPACE_NAME:-docker-test}"
SKIP_AUTH="${SKIP_AUTH:-false}"

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-auth) SKIP_AUTH=true; shift ;;
    --workspace) WORKSPACE_NAME="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

test_result() {
    local test_id="$1"
    local description="$2"
    local result="$3"
    local details="$4"

    case $result in
        PASS)
            echo -e "  ${GREEN}[PASS]${NC} $test_id: $description"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            ;;
        FAIL)
            echo -e "  ${RED}[FAIL]${NC} $test_id: $description"
            [ -n "$details" ] && echo -e "         ${details}"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            ;;
        SKIP)
            echo -e "  ${YELLOW}[SKIP]${NC} $test_id: $description"
            [ -n "$details" ] && echo -e "         ${details}"
            TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
            ;;
    esac
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Docker Workspace Test Suite${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# ─── Prerequisites ───────────────────────────────────────────────────────────

echo -e "${BLUE}[Prerequisites]${NC}"

# Check docker-workspace image exists
if docker image inspect docker-workspace:latest >/dev/null 2>&1; then
    test_result "PRE-1" "docker-workspace image exists" "PASS"
else
    test_result "PRE-1" "docker-workspace image exists" "FAIL" \
        "Build it: cd coder-poc/templates/docker-workspace && docker build -t docker-workspace:latest ./build"
fi

# Check DinD rootless image available
if docker image inspect docker:dind-rootless >/dev/null 2>&1; then
    test_result "PRE-2" "docker:dind-rootless image available" "PASS"
else
    echo -e "  ${YELLOW}Pulling docker:dind-rootless...${NC}"
    docker pull docker:dind-rootless >/dev/null 2>&1
    test_result "PRE-2" "docker:dind-rootless image available" "PASS"
fi

# Check Coder is reachable
if curl -sf "${CODER_URL}/api/v2/buildinfo" >/dev/null 2>&1; then
    test_result "PRE-3" "Coder API reachable at ${CODER_URL}" "PASS"
else
    test_result "PRE-3" "Coder API reachable at ${CODER_URL}" "FAIL" \
        "Start Coder: cd coder-poc && docker compose up -d"
fi

# Check template exists
if [ -n "$CODER_TOKEN" ]; then
    TEMPLATE_CHECK=$(curl -sf "${CODER_URL}/api/v2/organizations/default/templates" \
        -H "Coder-Session-Token: ${CODER_TOKEN}" 2>/dev/null | \
        python3 -c "import sys,json; ts=json.load(sys.stdin); print('found' if any(t['name']=='docker-workspace' for t in ts) else 'not_found')" 2>/dev/null || echo "error")
    if [ "$TEMPLATE_CHECK" = "found" ]; then
        test_result "PRE-4" "docker-workspace template registered in Coder" "PASS"
    else
        test_result "PRE-4" "docker-workspace template registered in Coder" "SKIP" \
            "Push template: coder templates push docker-workspace -d coder-poc/templates/docker-workspace"
    fi
else
    test_result "PRE-4" "docker-workspace template registered in Coder" "SKIP" \
        "Set CODER_SESSION_TOKEN to check"
fi

echo ""

# ─── Test 1: Authorization (Layer 2 - Terraform Precondition) ────────────────

echo -e "${BLUE}[1. Authorization Tests]${NC}"

if [ "$SKIP_AUTH" = "true" ]; then
    test_result "AUTH-1" "Unauthorized user blocked by precondition" "SKIP" "--skip-auth flag set"
    test_result "AUTH-2" "Authorized user passes precondition" "SKIP" "--skip-auth flag set"
else
    echo -e "  ${YELLOW}NOTE: Authorization tests require manual verification.${NC}"
    echo -e "  ${YELLOW}  1. Log in as user NOT in docker-users group → create workspace → expect ACCESS DENIED${NC}"
    echo -e "  ${YELLOW}  2. Log in as user IN docker-users group → create workspace → expect success${NC}"
    test_result "AUTH-1" "Unauthorized user blocked (manual check)" "SKIP" \
        "Log in as non-docker-users member, try: coder create test --template docker-workspace"
    test_result "AUTH-2" "Authorized user can create workspace (manual check)" "SKIP" \
        "Log in as docker-users member, try: coder create test --template docker-workspace"
fi

echo ""

# ─── Test 2: DinD Sidecar Standalone ─────────────────────────────────────────

echo -e "${BLUE}[2. DinD Sidecar Tests (standalone)]${NC}"

# Spin up a temporary DinD rootless container for testing
DIND_TEST_NAME="dind-test-$$"
echo -e "  Starting temporary rootless DinD: ${DIND_TEST_NAME}..."

docker run -d --name "${DIND_TEST_NAME}" \
    --security-opt seccomp=unconfined \
    --security-opt apparmor=unconfined \
    -e DOCKER_TLS_CERTDIR= \
    docker:dind-rootless >/dev/null 2>&1

# Wait for DinD to be ready
DIND_READY=false
for i in $(seq 1 20); do
    if docker exec "${DIND_TEST_NAME}" docker info >/dev/null 2>&1; then
        DIND_READY=true
        break
    fi
    sleep 2
done

if [ "$DIND_READY" = "true" ]; then
    test_result "DIND-1" "Rootless DinD sidecar starts successfully" "PASS"

    # Check Docker version in DinD
    DIND_VERSION=$(docker exec "${DIND_TEST_NAME}" docker version --format '{{.Server.Version}}' 2>/dev/null || echo "")
    if [ -n "$DIND_VERSION" ]; then
        test_result "DIND-2" "DinD Docker server version: ${DIND_VERSION}" "PASS"
    else
        test_result "DIND-2" "DinD Docker server responds" "FAIL"
    fi

    # Run hello-world inside DinD
    if docker exec "${DIND_TEST_NAME}" docker run --rm hello-world >/dev/null 2>&1; then
        test_result "DIND-3" "Container runs inside DinD (hello-world)" "PASS"
    else
        test_result "DIND-3" "Container runs inside DinD (hello-world)" "FAIL"
    fi

    # Check isolation — DinD cannot see host containers
    HOST_CONTAINERS=$(docker ps -q | wc -l | tr -d ' ')
    DIND_CONTAINERS=$(docker exec "${DIND_TEST_NAME}" docker ps -q 2>/dev/null | wc -l | tr -d ' ')
    if [ "$DIND_CONTAINERS" -eq 0 ] || [ "$DIND_CONTAINERS" -lt "$HOST_CONTAINERS" ]; then
        test_result "DIND-4" "DinD isolated from host (host: ${HOST_CONTAINERS}, dind: ${DIND_CONTAINERS})" "PASS"
    else
        test_result "DIND-4" "DinD isolated from host" "FAIL" \
            "DinD sees ${DIND_CONTAINERS} containers, host has ${HOST_CONTAINERS}"
    fi

    # Test docker compose inside DinD
    COMPOSE_VERSION=$(docker exec "${DIND_TEST_NAME}" docker compose version --short 2>/dev/null || echo "")
    if [ -n "$COMPOSE_VERSION" ]; then
        test_result "DIND-5" "Docker Compose available in DinD: v${COMPOSE_VERSION}" "PASS"
    else
        test_result "DIND-5" "Docker Compose available in DinD" "SKIP" \
            "docker compose plugin not in dind-rootless image (expected — CLI has it)"
    fi

    # Test multi-container app inside DinD
    docker exec "${DIND_TEST_NAME}" sh -c '
        docker run -d --name test-nginx nginx:alpine >/dev/null 2>&1
        docker run -d --name test-redis redis:alpine >/dev/null 2>&1
    ' >/dev/null 2>&1
    RUNNING=$(docker exec "${DIND_TEST_NAME}" docker ps --format '{{.Names}}' 2>/dev/null | wc -l | tr -d ' ')
    if [ "$RUNNING" -ge 2 ]; then
        test_result "DIND-6" "Multi-container workload inside DinD (${RUNNING} running)" "PASS"
    else
        test_result "DIND-6" "Multi-container workload inside DinD" "FAIL" \
            "Expected 2+ containers, got ${RUNNING}"
    fi

    # Cleanup containers inside DinD
    docker exec "${DIND_TEST_NAME}" sh -c 'docker rm -f test-nginx test-redis 2>/dev/null' >/dev/null 2>&1
else
    test_result "DIND-1" "Rootless DinD sidecar starts successfully" "FAIL" \
        "DinD not ready after 40 seconds"
    test_result "DIND-2" "DinD Docker server responds" "SKIP"
    test_result "DIND-3" "Container runs inside DinD" "SKIP"
    test_result "DIND-4" "DinD isolated from host" "SKIP"
    test_result "DIND-5" "Docker Compose available in DinD" "SKIP"
    test_result "DIND-6" "Multi-container workload inside DinD" "SKIP"
fi

# Cleanup test DinD
docker rm -f "${DIND_TEST_NAME}" >/dev/null 2>&1
echo ""

# ─── Test 3: Workspace Integration (if running workspace) ───────────────────

echo -e "${BLUE}[3. Workspace Integration Tests]${NC}"

# Check if a docker workspace container is running
WS_CONTAINER=$(docker ps --filter "label=coder.workspace.role=dind-sidecar" --format '{{.Names}}' 2>/dev/null | head -1)
MAIN_CONTAINER=$(docker ps --filter "name=coder-" --filter "ancestor=docker-workspace:latest" --format '{{.Names}}' 2>/dev/null | head -1)

if [ -n "$MAIN_CONTAINER" ]; then
    echo -e "  Found running Docker workspace: ${MAIN_CONTAINER}"

    # Check DOCKER_HOST is set
    DOCKER_HOST_VAL=$(docker exec "$MAIN_CONTAINER" printenv DOCKER_HOST 2>/dev/null || echo "")
    if echo "$DOCKER_HOST_VAL" | grep -q "tcp://"; then
        test_result "WS-1" "DOCKER_HOST set in workspace: ${DOCKER_HOST_VAL}" "PASS"
    else
        test_result "WS-1" "DOCKER_HOST set in workspace" "FAIL" "Got: ${DOCKER_HOST_VAL}"
    fi

    # Check docker CLI available
    if docker exec "$MAIN_CONTAINER" which docker >/dev/null 2>&1; then
        test_result "WS-2" "Docker CLI available in workspace" "PASS"
    else
        test_result "WS-2" "Docker CLI available in workspace" "FAIL"
    fi

    # Check docker version talks to sidecar
    if docker exec "$MAIN_CONTAINER" docker version >/dev/null 2>&1; then
        test_result "WS-3" "Workspace docker CLI connects to DinD sidecar" "PASS"
    else
        test_result "WS-3" "Workspace docker CLI connects to DinD sidecar" "FAIL" \
            "docker version failed — sidecar may not be running"
    fi

    # Check docker compose available
    if docker exec "$MAIN_CONTAINER" docker compose version >/dev/null 2>&1; then
        test_result "WS-4" "Docker Compose plugin available in workspace" "PASS"
    else
        test_result "WS-4" "Docker Compose plugin available in workspace" "FAIL"
    fi
else
    echo -e "  ${YELLOW}No running Docker workspace found. Skipping integration tests.${NC}"
    echo -e "  ${YELLOW}Create one first: coder create ${WORKSPACE_NAME} --template docker-workspace${NC}"
    test_result "WS-1" "DOCKER_HOST set in workspace" "SKIP" "No running workspace"
    test_result "WS-2" "Docker CLI available in workspace" "SKIP"
    test_result "WS-3" "Workspace connects to DinD sidecar" "SKIP"
    test_result "WS-4" "Docker Compose plugin available" "SKIP"
fi

echo ""

# ─── Summary ─────────────────────────────────────────────────────────────────

TOTAL=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Results: ${TOTAL} tests${NC}"
echo -e "  ${GREEN}Passed: ${TESTS_PASSED}${NC}"
echo -e "  ${RED}Failed: ${TESTS_FAILED}${NC}"
echo -e "  ${YELLOW}Skipped: ${TESTS_SKIPPED}${NC}"
echo -e "${BLUE}========================================${NC}"

[ "$TESTS_FAILED" -gt 0 ] && exit 1
exit 0
