#!/bin/bash
# Docker Workspace Auth Init Container Test Script (Production)
# Tests the auth-check init container image locally before deploying to ECS
#
# Prerequisites:
#   - auth-check image built:
#     cd aws-production/templates/docker-workspace/build
#     docker build -f Dockerfile.auth-check -t auth-check:latest .
#   - key-provisioner running (or mock endpoint)
#
# Usage:
#   ./aws-production/scripts/test-docker-auth.sh [--provisioner-url URL]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PROVISIONER_URL="${PROVISIONER_URL:-http://host.docker.internal:8100}"
PROVISIONER_SECRET="${PROVISIONER_SECRET:-poc-provisioner-secret-change-in-production}"
AUTH_IMAGE="auth-check:latest"

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --provisioner-url) PROVISIONER_URL="$2"; shift 2 ;;
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
echo -e "${BLUE}  Docker Auth Init Container Tests${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "  Auth image: ${AUTH_IMAGE}"
echo -e "  Provisioner: ${PROVISIONER_URL}"
echo ""

# ─── Prerequisites ───────────────────────────────────────────────────────────

echo -e "${BLUE}[Prerequisites]${NC}"

if docker image inspect "${AUTH_IMAGE}" >/dev/null 2>&1; then
    test_result "PRE-1" "auth-check image exists" "PASS"
else
    test_result "PRE-1" "auth-check image exists" "FAIL" \
        "Build: cd aws-production/templates/docker-workspace/build && docker build -f Dockerfile.auth-check -t auth-check:latest ."
    echo -e "\n${RED}Cannot continue without auth-check image. Exiting.${NC}"
    exit 1
fi

echo ""

# ─── Test 1: Fail-Closed (Unreachable Service) ──────────────────────────────

echo -e "${BLUE}[1. Fail-Closed Behavior]${NC}"

# Test with unreachable auth service — must exit 1
EXIT_CODE=0
OUTPUT=$(docker run --rm \
    -e WORKSPACE_OWNER=test-user \
    -e WORKSPACE_NAME=test-ws \
    -e AUTH_SERVICE_URL=http://unreachable-host:9999 \
    -e PROVISIONER_SECRET=test-secret \
    "${AUTH_IMAGE}" 2>&1) || EXIT_CODE=$?

if [ "$EXIT_CODE" -ne 0 ]; then
    test_result "FC-1" "Unreachable auth service → exit 1 (denied)" "PASS"
else
    test_result "FC-1" "Unreachable auth service → exit 1 (denied)" "FAIL" \
        "Expected exit 1, got exit ${EXIT_CODE}. Fail-open is a security risk."
fi

# Verify error message mentions unreachable
if echo "$OUTPUT" | grep -qi "unreachable\|error"; then
    test_result "FC-2" "Error message mentions service unreachable" "PASS"
else
    test_result "FC-2" "Error message mentions service unreachable" "FAIL" \
        "Output: ${OUTPUT}"
fi

echo ""

# ─── Test 2: Missing Environment Variables ───────────────────────────────────

echo -e "${BLUE}[2. Missing Environment Variables]${NC}"

# Missing WORKSPACE_OWNER
EXIT_CODE=0
docker run --rm \
    -e WORKSPACE_NAME=test-ws \
    -e AUTH_SERVICE_URL=http://localhost:8100 \
    -e PROVISIONER_SECRET=test-secret \
    "${AUTH_IMAGE}" >/dev/null 2>&1 || EXIT_CODE=$?

if [ "$EXIT_CODE" -ne 0 ]; then
    test_result "ENV-1" "Missing WORKSPACE_OWNER → exit 1" "PASS"
else
    test_result "ENV-1" "Missing WORKSPACE_OWNER → exit 1" "FAIL" "Expected exit 1"
fi

# Missing AUTH_SERVICE_URL
EXIT_CODE=0
docker run --rm \
    -e WORKSPACE_OWNER=test-user \
    -e WORKSPACE_NAME=test-ws \
    -e PROVISIONER_SECRET=test-secret \
    "${AUTH_IMAGE}" >/dev/null 2>&1 || EXIT_CODE=$?

if [ "$EXIT_CODE" -ne 0 ]; then
    test_result "ENV-2" "Missing AUTH_SERVICE_URL → exit 1" "PASS"
else
    test_result "ENV-2" "Missing AUTH_SERVICE_URL → exit 1" "FAIL" "Expected exit 1"
fi

echo ""

# ─── Test 3: Live Authorization (requires key-provisioner) ──────────────────

echo -e "${BLUE}[3. Live Authorization (key-provisioner)]${NC}"

# Check if key-provisioner is reachable
if curl -sf "${PROVISIONER_URL}/health" >/dev/null 2>&1; then
    test_result "LIVE-0" "Key-provisioner reachable at ${PROVISIONER_URL}" "PASS"

    # Check if /api/v1/authorize/docker-workspace endpoint exists
    # (This endpoint may not exist yet — it needs to be added to key-provisioner)
    HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" \
        -X POST "${PROVISIONER_URL}/api/v1/authorize/docker-workspace" \
        -H "Authorization: Bearer ${PROVISIONER_SECRET}" \
        -H "Content-Type: application/json" \
        -d '{"username":"test","workspace_name":"test","resource_type":"docker-workspace"}' \
        2>/dev/null || echo "000")

    if [ "$HTTP_CODE" = "404" ]; then
        test_result "LIVE-1" "Authorization endpoint exists" "SKIP" \
            "Endpoint /api/v1/authorize/docker-workspace not implemented yet in key-provisioner"
        test_result "LIVE-2" "Authorized user allowed" "SKIP"
        test_result "LIVE-3" "Unauthorized user denied" "SKIP"
    elif [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "403" ]; then
        test_result "LIVE-1" "Authorization endpoint exists (HTTP ${HTTP_CODE})" "PASS"

        # Test with auth-check container against real service
        EXIT_CODE=0
        OUTPUT=$(docker run --rm --network host \
            -e WORKSPACE_OWNER=admin \
            -e WORKSPACE_NAME=test-ws \
            -e AUTH_SERVICE_URL="${PROVISIONER_URL}" \
            -e PROVISIONER_SECRET="${PROVISIONER_SECRET}" \
            "${AUTH_IMAGE}" 2>&1) || EXIT_CODE=$?

        if [ "$EXIT_CODE" -eq 0 ]; then
            test_result "LIVE-2" "Authorized user allowed (admin)" "PASS"
        else
            test_result "LIVE-2" "Authorized user allowed (admin)" "FAIL" \
                "Exit ${EXIT_CODE}: ${OUTPUT}"
        fi

        # Test unauthorized
        EXIT_CODE=0
        OUTPUT=$(docker run --rm --network host \
            -e WORKSPACE_OWNER=nonexistent-user \
            -e WORKSPACE_NAME=test-ws \
            -e AUTH_SERVICE_URL="${PROVISIONER_URL}" \
            -e PROVISIONER_SECRET="${PROVISIONER_SECRET}" \
            "${AUTH_IMAGE}" 2>&1) || EXIT_CODE=$?

        if [ "$EXIT_CODE" -ne 0 ]; then
            test_result "LIVE-3" "Unauthorized user denied (nonexistent-user)" "PASS"
        else
            test_result "LIVE-3" "Unauthorized user denied" "FAIL" \
                "Expected exit 1, got exit ${EXIT_CODE}"
        fi
    else
        test_result "LIVE-1" "Authorization endpoint exists" "FAIL" \
            "Unexpected HTTP ${HTTP_CODE} from ${PROVISIONER_URL}"
        test_result "LIVE-2" "Authorized user allowed" "SKIP"
        test_result "LIVE-3" "Unauthorized user denied" "SKIP"
    fi
else
    test_result "LIVE-0" "Key-provisioner reachable" "SKIP" \
        "Not running at ${PROVISIONER_URL}. Start with: docker compose up -d key-provisioner"
    test_result "LIVE-1" "Authorization endpoint exists" "SKIP"
    test_result "LIVE-2" "Authorized user allowed" "SKIP"
    test_result "LIVE-3" "Unauthorized user denied" "SKIP"
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
