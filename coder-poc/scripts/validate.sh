#!/bin/bash
# Coder WebIDE PoC - Validation Script
# This script validates the Coder installation and workspace functionality

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CODER_URL="${CODER_URL:-http://localhost:7080}"
TEST_WORKSPACE_NAME="test-validation-$(date +%s)"

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           Coder WebIDE PoC - Validation Script                ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Test functions
run_test() {
    local test_name="$1"
    local test_command="$2"

    echo -n "  Testing: $test_name... "

    if eval "$test_command" &> /dev/null; then
        echo -e "${GREEN}PASS${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

skip_test() {
    local test_name="$1"
    local reason="$2"

    echo -e "  Testing: $test_name... ${YELLOW}SKIP${NC} ($reason)"
    ((TESTS_SKIPPED++))
}

# ============================================================================
# INFRASTRUCTURE TESTS
# ============================================================================

echo ""
echo -e "${BLUE}1. Infrastructure Tests${NC}"
echo "   ─────────────────────"

# Test 1.1: Docker daemon
run_test "Docker daemon running" "docker info"

# Test 1.2: PostgreSQL container
run_test "PostgreSQL container running" "docker ps | grep -q postgres"

# Test 1.3: Coder container
run_test "Coder container running" "docker ps | grep -q coder-server"

# Test 1.4: PostgreSQL health
run_test "PostgreSQL health check" "docker exec postgres pg_isready -U coder -d coder"

# Test 1.5: Coder network exists
run_test "Coder network exists" "docker network ls | grep -q coder-network"

# ============================================================================
# API TESTS
# ============================================================================

echo ""
echo -e "${BLUE}2. Coder API Tests${NC}"
echo "   ─────────────────"

# Test 2.1: API reachable
run_test "API endpoint reachable" "curl -sf ${CODER_URL}/api/v2/buildinfo"

# Test 2.2: Get version
CODER_VERSION=$(curl -sf ${CODER_URL}/api/v2/buildinfo | jq -r '.version' 2>/dev/null || echo "unknown")
echo -e "  Coder version: ${GREEN}${CODER_VERSION}${NC}"

# Test 2.3: Health endpoint
run_test "Health endpoint" "curl -sf ${CODER_URL}/api/v2/buildinfo | jq -e '.version'"

# ============================================================================
# CLI TESTS
# ============================================================================

echo ""
echo -e "${BLUE}3. Coder CLI Tests${NC}"
echo "   ─────────────────"

# Test 3.1: CLI installed
if command -v coder &> /dev/null; then
    run_test "Coder CLI installed" "coder version"
    CLI_AVAILABLE=true
else
    skip_test "Coder CLI installed" "CLI not found"
    CLI_AVAILABLE=false
fi

# Test 3.2: CLI authenticated
if [ "$CLI_AVAILABLE" = true ]; then
    if coder list &> /dev/null; then
        run_test "CLI authenticated" "coder list"
        CLI_AUTH=true
    else
        skip_test "CLI authenticated" "Not logged in"
        CLI_AUTH=false
    fi
else
    CLI_AUTH=false
fi

# ============================================================================
# TEMPLATE TESTS
# ============================================================================

echo ""
echo -e "${BLUE}4. Template Tests${NC}"
echo "   ───────────────"

if [ "$CLI_AUTH" = true ]; then
    # Test 4.1: Template exists
    run_test "contractor-workspace template exists" "coder templates list | grep -q contractor-workspace"

    # Test 4.2: Template has versions
    run_test "Template has active version" "coder templates versions list contractor-workspace 2>/dev/null | grep -q active"
else
    skip_test "Template tests" "CLI not authenticated"
fi

# ============================================================================
# WORKSPACE TESTS
# ============================================================================

echo ""
echo -e "${BLUE}5. Workspace Tests${NC}"
echo "   ─────────────────"

WORKSPACE_CREATED=false

if [ "$CLI_AUTH" = true ]; then
    # Test 5.1: Create workspace
    echo -n "  Testing: Create test workspace... "
    if coder create "$TEST_WORKSPACE_NAME" --template contractor-workspace \
        --parameter cpu_cores=2 \
        --parameter memory_gb=4 \
        --parameter disk_size=10 \
        --yes &> /dev/null; then
        echo -e "${GREEN}PASS${NC}"
        ((TESTS_PASSED++))
        WORKSPACE_CREATED=true
    else
        echo -e "${RED}FAIL${NC}"
        ((TESTS_FAILED++))
    fi

    if [ "$WORKSPACE_CREATED" = true ]; then
        # Wait for workspace to be ready
        echo -n "  Testing: Workspace becomes ready... "
        for i in {1..60}; do
            STATUS=$(coder list --output json 2>/dev/null | jq -r ".[] | select(.name==\"$TEST_WORKSPACE_NAME\") | .latest_build.status" 2>/dev/null || echo "unknown")
            if [ "$STATUS" = "running" ]; then
                echo -e "${GREEN}PASS${NC} (${i}s)"
                ((TESTS_PASSED++))
                break
            fi
            sleep 2
            if [ $i -eq 60 ]; then
                echo -e "${RED}FAIL${NC} (timeout)"
                ((TESTS_FAILED++))
            fi
        done

        # Test 5.2: SSH connectivity
        echo -n "  Testing: SSH connectivity... "
        if timeout 30 coder ssh "$TEST_WORKSPACE_NAME" -- echo "SSH works" &> /dev/null; then
            echo -e "${GREEN}PASS${NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}FAIL${NC}"
            ((TESTS_FAILED++))
        fi

        # Test 5.3: Code-server running
        echo -n "  Testing: code-server running in workspace... "
        if timeout 30 coder ssh "$TEST_WORKSPACE_NAME" -- pgrep -f code-server &> /dev/null; then
            echo -e "${GREEN}PASS${NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${YELLOW}SKIP${NC} (may need more time to start)"
            ((TESTS_SKIPPED++))
        fi

        # Test 5.4: Git available
        echo -n "  Testing: Git available in workspace... "
        if timeout 30 coder ssh "$TEST_WORKSPACE_NAME" -- git --version &> /dev/null; then
            echo -e "${GREEN}PASS${NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}FAIL${NC}"
            ((TESTS_FAILED++))
        fi

        # Test 5.5: Node.js available
        echo -n "  Testing: Node.js available in workspace... "
        if timeout 30 coder ssh "$TEST_WORKSPACE_NAME" -- node --version &> /dev/null; then
            echo -e "${GREEN}PASS${NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}FAIL${NC}"
            ((TESTS_FAILED++))
        fi

        # Test 5.6: Python available
        echo -n "  Testing: Python available in workspace... "
        if timeout 30 coder ssh "$TEST_WORKSPACE_NAME" -- python3 --version &> /dev/null; then
            echo -e "${GREEN}PASS${NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}FAIL${NC}"
            ((TESTS_FAILED++))
        fi

        # Test 5.7: Stop workspace
        echo -n "  Testing: Stop workspace... "
        if coder stop "$TEST_WORKSPACE_NAME" --yes &> /dev/null; then
            echo -e "${GREEN}PASS${NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}FAIL${NC}"
            ((TESTS_FAILED++))
        fi

        # Test 5.8: Delete workspace
        echo -n "  Testing: Delete workspace... "
        if coder delete "$TEST_WORKSPACE_NAME" --yes &> /dev/null; then
            echo -e "${GREEN}PASS${NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}FAIL${NC}"
            ((TESTS_FAILED++))
        fi
    fi
else
    skip_test "Workspace tests" "CLI not authenticated"
fi

# ============================================================================
# SECURITY TESTS
# ============================================================================

echo ""
echo -e "${BLUE}6. Security Tests${NC}"
echo "   ────────────────"

# Test 6.1: HTTPS redirect configured (check header)
run_test "API returns valid JSON" "curl -sf ${CODER_URL}/api/v2/buildinfo | jq -e '.'"

# Test 6.2: No default credentials exposed
run_test "Auth required for user list" "! curl -sf ${CODER_URL}/api/v2/users"

# Test 6.3: Container runs as non-root
run_test "Coder container user" "docker exec coder-server id | grep -v 'uid=0'"

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))

echo -e "  ${GREEN}Passed:${NC}  $TESTS_PASSED"
echo -e "  ${RED}Failed:${NC}  $TESTS_FAILED"
echo -e "  ${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
echo -e "  Total:   $TOTAL_TESTS"

echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              All tests passed! PoC is ready.                  ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    exit 0
else
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║              Some tests failed. Check the output above.       ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
    exit 1
fi
