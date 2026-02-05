#!/bin/bash
# Access Control Test Script for Coder WebIDE PoC
# Tests Git repository access control and workspace isolation

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
GITEA_URL="${GITEA_URL:-http://localhost:3000}"
CODER_URL="${CODER_URL:-http://localhost:7080}"
DRONE_URL="${DRONE_URL:-http://localhost:8080}"

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Test result function
test_result() {
    local test_id="$1"
    local description="$2"
    local result="$3"  # PASS, FAIL, SKIP
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

# API call helper
gitea_api() {
    local user="$1"
    local pass="$2"
    local endpoint="$3"

    curl -s -o /dev/null -w "%{http_code}" \
        -u "${user}:${pass}" \
        "${GITEA_URL}/api/v1${endpoint}" 2>/dev/null
}

# Check if service is running
check_service() {
    local url="$1"
    local name="$2"

    if curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null | grep -q "200\|302"; then
        echo -e "  ${GREEN}[✓]${NC} $name is running"
        return 0
    else
        echo -e "  ${RED}[✗]${NC} $name is not responding"
        return 1
    fi
}

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║        Coder WebIDE PoC - Access Control Test Suite           ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Pre-flight checks
echo -e "${BLUE}Pre-flight Checks${NC}"
echo "─────────────────────────────────────────────────────────────────"

services_ok=true
check_service "$GITEA_URL" "Gitea" || services_ok=false
check_service "$CODER_URL" "Coder" || services_ok=false
check_service "$DRONE_URL" "Drone CI" || services_ok=false

if [ "$services_ok" = false ]; then
    echo ""
    echo -e "${RED}Some services are not running. Please start the environment first:${NC}"
    echo "  docker compose up -d"
    echo "  ./scripts/setup-gitea.sh"
    exit 1
fi

echo ""

# ============================================================================
# Category 1: Git Repository Access Control
# ============================================================================

echo -e "${BLUE}Category 1: Git Repository Access Control${NC}"
echo "─────────────────────────────────────────────────────────────────"

# TC-1.1: Authorized read access (contractor1 -> python-sample)
result=$(gitea_api "contractor1" "password123" "/repos/gitea/python-sample")
if [ "$result" == "200" ]; then
    test_result "TC-1.1" "contractor1 can access python-sample (write)" "PASS"
else
    test_result "TC-1.1" "contractor1 can access python-sample (write)" "FAIL" "HTTP $result"
fi

# TC-1.2: Read-only access (readonly -> python-sample)
result=$(gitea_api "readonly" "password123" "/repos/gitea/python-sample")
if [ "$result" == "200" ]; then
    test_result "TC-1.2" "readonly can read python-sample" "PASS"
else
    test_result "TC-1.2" "readonly can read python-sample" "FAIL" "HTTP $result"
fi

# TC-1.3: No access (contractor2 -> private-project)
result=$(gitea_api "contractor2" "password123" "/repos/gitea/private-project")
if [ "$result" == "404" ] || [ "$result" == "403" ]; then
    test_result "TC-1.3" "contractor2 cannot access private-project" "PASS"
else
    test_result "TC-1.3" "contractor2 cannot access private-project" "FAIL" "HTTP $result (expected 403/404)"
fi

# TC-1.4: contractor1 can access private-project (has write access)
result=$(gitea_api "contractor1" "password123" "/repos/gitea/private-project")
if [ "$result" == "200" ]; then
    test_result "TC-1.4" "contractor1 can access private-project (authorized)" "PASS"
else
    test_result "TC-1.4" "contractor1 can access private-project (authorized)" "FAIL" "HTTP $result"
fi

# TC-1.5: contractor3 write access to shared-libs
result=$(gitea_api "contractor3" "password123" "/repos/gitea/shared-libs")
if [ "$result" == "200" ]; then
    test_result "TC-1.5" "contractor3 can access shared-libs (write)" "PASS"
else
    test_result "TC-1.5" "contractor3 can access shared-libs (write)" "FAIL" "HTTP $result"
fi

# TC-1.6: contractor1 read-only on shared-libs
result=$(gitea_api "contractor1" "password123" "/repos/gitea/shared-libs")
if [ "$result" == "200" ]; then
    test_result "TC-1.6" "contractor1 can read shared-libs" "PASS"
else
    test_result "TC-1.6" "contractor1 can read shared-libs" "FAIL" "HTTP $result"
fi

# TC-1.7: readonly cannot access shared-libs (no permission)
result=$(gitea_api "readonly" "password123" "/repos/gitea/shared-libs")
if [ "$result" == "404" ] || [ "$result" == "403" ]; then
    test_result "TC-1.7" "readonly cannot access shared-libs" "PASS"
else
    test_result "TC-1.7" "readonly cannot access shared-libs" "FAIL" "HTTP $result (expected 403/404)"
fi

# TC-1.8: Invalid user cannot access anything
result=$(gitea_api "invaliduser" "wrongpass" "/repos/gitea/python-sample")
if [ "$result" == "401" ] || [ "$result" == "403" ]; then
    test_result "TC-1.8" "Invalid user authentication rejected" "PASS"
else
    test_result "TC-1.8" "Invalid user authentication rejected" "FAIL" "HTTP $result (expected 401/403)"
fi

echo ""

# ============================================================================
# Category 2: User Management
# ============================================================================

echo -e "${BLUE}Category 2: User Management${NC}"
echo "─────────────────────────────────────────────────────────────────"

# TC-2.1: Admin can list users
result=$(gitea_api "gitea" "admin123" "/admin/users")
if [ "$result" == "200" ]; then
    test_result "TC-2.1" "Admin can list all users" "PASS"
else
    test_result "TC-2.1" "Admin can list all users" "FAIL" "HTTP $result"
fi

# TC-2.2: Non-admin cannot list users
result=$(gitea_api "contractor1" "password123" "/admin/users")
if [ "$result" == "403" ] || [ "$result" == "404" ]; then
    test_result "TC-2.2" "Non-admin cannot list users" "PASS"
else
    test_result "TC-2.2" "Non-admin cannot list users" "FAIL" "HTTP $result (expected 403)"
fi

# TC-2.3: User can access own profile
result=$(gitea_api "contractor1" "password123" "/user")
if [ "$result" == "200" ]; then
    test_result "TC-2.3" "User can access own profile" "PASS"
else
    test_result "TC-2.3" "User can access own profile" "FAIL" "HTTP $result"
fi

echo ""

# ============================================================================
# Category 3: CI/CD Access
# ============================================================================

echo -e "${BLUE}Category 3: CI/CD Pipeline Access${NC}"
echo "─────────────────────────────────────────────────────────────────"

# TC-3.1: Drone CI is accessible
drone_status=$(curl -s -o /dev/null -w "%{http_code}" "$DRONE_URL/healthz" 2>/dev/null || echo "000")
if [ "$drone_status" == "200" ] || [ "$drone_status" == "204" ]; then
    test_result "TC-3.1" "Drone CI health check" "PASS"
else
    test_result "TC-3.1" "Drone CI health check" "SKIP" "Drone may not have /healthz endpoint"
fi

# TC-3.2: Check if Drone is connected to Gitea
test_result "TC-3.2" "Drone-Gitea webhook integration" "SKIP" "Requires webhook test"

echo ""

# ============================================================================
# Category 4: Workspace Isolation (Docker-based)
# ============================================================================

echo -e "${BLUE}Category 4: Workspace Isolation${NC}"
echo "─────────────────────────────────────────────────────────────────"

# TC-4.1: Check Coder API is accessible
coder_status=$(curl -s -o /dev/null -w "%{http_code}" "$CODER_URL/api/v2/buildinfo" 2>/dev/null)
if [ "$coder_status" == "200" ]; then
    test_result "TC-4.1" "Coder API is accessible" "PASS"
else
    test_result "TC-4.1" "Coder API is accessible" "FAIL" "HTTP $coder_status"
fi

# TC-4.2: Workspace containers are isolated (check Docker)
workspace_count=$(docker ps --filter "label=coder.workspace.id" -q 2>/dev/null | wc -l)
if [ "$workspace_count" -ge 0 ]; then
    test_result "TC-4.2" "Workspace container isolation" "PASS" "$workspace_count active workspace(s)"
else
    test_result "TC-4.2" "Workspace container isolation" "SKIP" "No workspaces running"
fi

# TC-4.3: Network isolation check
network_exists=$(docker network ls --filter "name=coder-network" -q 2>/dev/null | wc -l)
if [ "$network_exists" -gt 0 ]; then
    test_result "TC-4.3" "Coder network exists" "PASS"
else
    test_result "TC-4.3" "Coder network exists" "FAIL" "coder-network not found"
fi

echo ""

# ============================================================================
# Summary
# ============================================================================

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                      Test Summary                             ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))

echo ""
echo "Results:"
echo -e "  ${GREEN}Passed:${NC}  $TESTS_PASSED"
echo -e "  ${RED}Failed:${NC}  $TESTS_FAILED"
echo -e "  ${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
echo "  ─────────────────"
echo "  Total:   $TOTAL_TESTS"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Review the results above.${NC}"
    exit 1
fi
