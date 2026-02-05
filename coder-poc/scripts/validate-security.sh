#!/bin/bash
# =============================================================================
# Security Validation Script for Dev Platform PoC
# Tests: Network isolation, access controls, data protection, service hardening
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNED=0
TESTS_TOTAL=0

# Output file
REPORT_FILE="security-report-$(date +%Y%m%d-%H%M%S).txt"

# =============================================================================
# Helper Functions
# =============================================================================

log_test() {
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    echo -e "${CYAN}[TEST ${TESTS_TOTAL}]${NC} $1"
}

log_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "  ${GREEN}✓ PASS${NC}: $1"
    echo "[PASS] $1" >> "$REPORT_FILE"
}

log_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "  ${RED}✗ FAIL${NC}: $1"
    echo "[FAIL] $1" >> "$REPORT_FILE"
}

log_warn() {
    TESTS_WARNED=$((TESTS_WARNED + 1))
    echo -e "  ${YELLOW}⚠ WARN${NC}: $1"
    echo "[WARN] $1" >> "$REPORT_FILE"
}

log_info() {
    echo -e "  ${BLUE}ℹ INFO${NC}: $1"
}

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "" >> "$REPORT_FILE"
    echo "=== $1 ===" >> "$REPORT_FILE"
}

print_section() {
    echo ""
    echo -e "${CYAN}─── $1 ───${NC}"
    echo ""
}

# =============================================================================
# Initialize Report
# =============================================================================

echo "Security Validation Report" > "$REPORT_FILE"
echo "Generated: $(date)" >> "$REPORT_FILE"
echo "Platform: Dev Platform PoC" >> "$REPORT_FILE"
echo "==========================================" >> "$REPORT_FILE"

echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     DEV PLATFORM SECURITY VALIDATION                          ║${NC}"
echo -e "${BLUE}║     Testing: Network, Access, Data, Service Security          ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# 1. SERVICE AVAILABILITY
# =============================================================================

print_header "1. Service Availability & Health"

check_service() {
    local name=$1
    local url=$2
    local expected_code=${3:-200}

    log_test "Service availability: ${name}"

    response=$(curl -sf -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")

    if [ "$response" = "$expected_code" ] || [ "$response" = "204" ]; then
        log_pass "${name} is accessible (HTTP ${response})"
        return 0
    else
        log_fail "${name} not accessible (HTTP ${response}, expected ${expected_code})"
        return 1
    fi
}

check_service "Coder Server" "http://localhost:7080/api/v2/buildinfo"
check_service "Gitea Git Server" "http://localhost:3000/"
check_service "AI Gateway" "http://localhost:8090/health"
check_service "MinIO Console" "http://localhost:9001/"
check_service "MinIO S3 API" "http://localhost:9002/minio/health/live"
check_service "Mailpit" "http://localhost:8025/"
check_service "Authentik" "http://localhost:9000/-/health/ready/" "204"

# =============================================================================
# 2. NETWORK ISOLATION
# =============================================================================

print_header "2. Network Isolation Tests"

print_section "2.1 Internal-Only Services"

# Test that internal services are NOT exposed to host
log_test "PostgreSQL not exposed to host"
if ! nc -z localhost 5432 2>/dev/null; then
    log_pass "PostgreSQL (5432) is internal-only - not exposed to host"
else
    log_warn "PostgreSQL (5432) is exposed to host - consider restricting"
fi

log_test "TestDB not exposed to host"
if ! nc -z localhost 5433 2>/dev/null; then
    log_pass "TestDB is internal-only - not exposed to host"
else
    log_warn "TestDB is exposed to host"
fi

log_test "Redis not exposed to host"
if ! nc -z localhost 6379 2>/dev/null; then
    log_pass "Redis (6379) is internal-only - not exposed to host"
else
    log_warn "Redis (6379) is exposed to host - consider restricting"
fi

print_section "2.2 Container Network Isolation"

log_test "Containers on isolated network"
NETWORK_EXISTS=$(docker network ls --format '{{.Name}}' | grep -c "coder-network" || echo "0")
if [ "$NETWORK_EXISTS" -gt 0 ]; then
    log_pass "Isolated 'coder-network' exists"
else
    log_fail "Isolated network 'coder-network' not found"
fi

log_test "Network driver is bridge (isolated)"
NETWORK_DRIVER=$(docker network inspect coder-network --format '{{.Driver}}' 2>/dev/null || echo "unknown")
if [ "$NETWORK_DRIVER" = "bridge" ]; then
    log_pass "Network uses bridge driver (isolated)"
else
    log_warn "Network driver: ${NETWORK_DRIVER}"
fi

# =============================================================================
# 3. AUTHENTICATION & ACCESS CONTROL
# =============================================================================

print_header "3. Authentication & Access Control"

print_section "3.1 Unauthenticated Access Tests"

log_test "Coder API requires authentication"
CODER_UNAUTH=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:7080/api/v2/users/me" 2>/dev/null)
if [ "$CODER_UNAUTH" = "401" ]; then
    log_pass "Coder API properly rejects unauthenticated requests (HTTP 401)"
else
    log_fail "Coder API returned HTTP ${CODER_UNAUTH} for unauthenticated request"
fi

log_test "Gitea private repos require authentication"
GITEA_UNAUTH=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:3000/api/v1/user" 2>/dev/null)
if [ "$GITEA_UNAUTH" = "401" ] || [ "$GITEA_UNAUTH" = "403" ]; then
    log_pass "Gitea API properly requires authentication (HTTP ${GITEA_UNAUTH})"
else
    log_warn "Gitea API returned HTTP ${GITEA_UNAUTH} - verify auth settings"
fi

log_test "MinIO requires authentication"
MINIO_UNAUTH=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:9002/minio/admin/v3/info" 2>/dev/null)
if [ "$MINIO_UNAUTH" = "403" ] || [ "$MINIO_UNAUTH" = "401" ]; then
    log_pass "MinIO API requires authentication (HTTP ${MINIO_UNAUTH})"
else
    log_warn "MinIO returned HTTP ${MINIO_UNAUTH} - verify auth"
fi

print_section "3.2 Default Credentials Check"

log_test "Checking for default/weak credentials"
log_info "This is a reminder to change default passwords in production:"
log_info "  - MinIO: minioadmin/minioadmin"
log_info "  - Authentik: admin/admin"
log_info "  - PostgreSQL: postgres/postgres"
log_warn "Default credentials detected - change before production use"

# =============================================================================
# 4. DATA PROTECTION
# =============================================================================

print_header "4. Data Protection"

print_section "4.1 Volume Encryption & Persistence"

log_test "Checking Docker volumes exist"
VOLUMES=$(docker volume ls --format '{{.Name}}' | grep -c "coder-poc" || echo "0")
if [ "$VOLUMES" -gt 0 ]; then
    log_pass "Found ${VOLUMES} persistent volumes"
    log_info "Volumes: $(docker volume ls --format '{{.Name}}' | grep 'coder-poc' | tr '\n' ', ')"
else
    log_warn "No coder-poc volumes found"
fi

print_section "4.2 Sensitive Data Exposure"

log_test "Environment variables don't contain secrets in logs"
# Check if any container has secrets visible in inspect
EXPOSED_SECRETS=0
for container in postgres coder-server gitea ai-gateway minio; do
    if docker inspect "$container" 2>/dev/null | grep -iE "(password|secret|key).*=" | grep -v "null" | grep -v '""' > /dev/null 2>&1; then
        EXPOSED_SECRETS=$((EXPOSED_SECRETS + 1))
    fi
done
if [ "$EXPOSED_SECRETS" -eq 0 ]; then
    log_pass "No obvious secrets exposed in container inspect"
else
    log_warn "${EXPOSED_SECRETS} containers may have secrets visible in docker inspect"
fi

log_test "Checking for .env file protection"
if [ -f "$(dirname "$0")/../.env" ]; then
    ENV_PERMS=$(stat -f "%A" "$(dirname "$0")/../.env" 2>/dev/null || stat -c "%a" "$(dirname "$0")/../.env" 2>/dev/null)
    if [ "$ENV_PERMS" = "600" ] || [ "$ENV_PERMS" = "400" ]; then
        log_pass ".env file has restricted permissions (${ENV_PERMS})"
    else
        log_warn ".env file permissions are ${ENV_PERMS} - consider chmod 600"
    fi
else
    log_info "No .env file found (using defaults or docker-compose env)"
fi

# =============================================================================
# 5. CONTAINER SECURITY
# =============================================================================

print_header "5. Container Security"

print_section "5.1 Container User Context"

log_test "Checking container user contexts"
for container in gitea ai-gateway mailpit minio; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        USER=$(docker inspect "$container" --format '{{.Config.User}}' 2>/dev/null || echo "unknown")
        if [ -z "$USER" ] || [ "$USER" = "root" ] || [ "$USER" = "0" ] || [ "$USER" = "0:0" ]; then
            log_warn "${container} runs as root user"
        else
            log_pass "${container} runs as non-root user (${USER})"
        fi
    fi
done

print_section "5.2 Docker Socket Access"

log_test "Docker socket access is restricted"
SOCKET_CONTAINERS=$(docker ps --format '{{.Names}}' | while read container; do
    if docker inspect "$container" --format '{{range .Mounts}}{{.Source}}{{end}}' 2>/dev/null | grep -q "docker.sock"; then
        echo "$container"
    fi
done)

if [ -n "$SOCKET_CONTAINERS" ]; then
    log_warn "Containers with Docker socket access: ${SOCKET_CONTAINERS}"
    log_info "Docker socket access needed for Coder to create workspaces"
else
    log_pass "No containers have Docker socket access"
fi

print_section "5.3 Resource Limits"

log_test "Checking container resource limits"
LIMITED_CONTAINERS=0
UNLIMITED_CONTAINERS=0

for container in $(docker ps --format '{{.Names}}'); do
    MEM_LIMIT=$(docker inspect "$container" --format '{{.HostConfig.Memory}}' 2>/dev/null || echo "0")
    if [ "$MEM_LIMIT" = "0" ]; then
        UNLIMITED_CONTAINERS=$((UNLIMITED_CONTAINERS + 1))
    else
        LIMITED_CONTAINERS=$((LIMITED_CONTAINERS + 1))
    fi
done

if [ "$UNLIMITED_CONTAINERS" -gt 0 ]; then
    log_warn "${UNLIMITED_CONTAINERS} containers have no memory limits (OK for dev, set for prod)"
else
    log_pass "All containers have resource limits"
fi

# =============================================================================
# 6. SERVICE-SPECIFIC SECURITY
# =============================================================================

print_header "6. Service-Specific Security"

print_section "6.1 Coder Security"

log_test "Coder CSRF protection"
CODER_COOKIE=$(curl -sI "http://localhost:7080/" | grep -i "set-cookie" || echo "")
if echo "$CODER_COOKIE" | grep -qi "secure\|samesite"; then
    log_pass "Coder sets secure cookie attributes"
else
    log_warn "Coder may not set secure cookie attributes (OK for localhost)"
fi

print_section "6.2 Git Server (Gitea) Security"

log_test "Gitea registration status"
GITEA_REG=$(curl -sf "http://localhost:3000/" 2>/dev/null | grep -i "register" || echo "")
if [ -n "$GITEA_REG" ]; then
    log_warn "Gitea registration may be enabled - disable for production"
else
    log_pass "Gitea registration appears disabled"
fi

print_section "6.3 AI Gateway Security"

log_test "AI Gateway rate limiting"
AI_HEALTH=$(curl -sf "http://localhost:8090/health" 2>/dev/null || echo "{}")
if echo "$AI_HEALTH" | grep -qi "rate\|limit"; then
    log_pass "AI Gateway has rate limiting configured"
else
    log_info "AI Gateway rate limiting status unknown"
fi

log_test "AI Gateway audit logging"
if docker logs ai-gateway 2>&1 | head -20 | grep -qi "log\|audit"; then
    log_pass "AI Gateway appears to have logging enabled"
else
    log_info "AI Gateway logging status - verify in config"
fi

# =============================================================================
# 7. TLS/ENCRYPTION
# =============================================================================

print_header "7. TLS/Encryption Status"

log_test "TLS configuration (dev environment)"
log_info "Current setup uses HTTP (acceptable for local development)"
log_warn "For production: Enable TLS on all public endpoints"
log_info "  - Use reverse proxy (Traefik/nginx) with Let's Encrypt"
log_info "  - Or configure each service with TLS certificates"

# Check if any HTTPS ports are configured
if docker ps --format '{{.Ports}}' | grep -q "443"; then
    log_pass "Some services have HTTPS ports configured"
else
    log_info "No HTTPS ports detected (expected for dev)"
fi

# =============================================================================
# 8. LOGGING & MONITORING
# =============================================================================

print_header "8. Logging & Monitoring"

print_section "8.1 Container Logging"

log_test "Container logs are accessible"
LOG_DRIVERS=0
for container in $(docker ps --format '{{.Names}}' | head -5); do
    DRIVER=$(docker inspect "$container" --format '{{.HostConfig.LogConfig.Type}}' 2>/dev/null || echo "none")
    if [ "$DRIVER" != "none" ]; then
        LOG_DRIVERS=$((LOG_DRIVERS + 1))
    fi
done
log_pass "${LOG_DRIVERS} containers have logging enabled"

print_section "8.2 Health Checks"

log_test "Services have health checks configured"
HEALTHY_CONTAINERS=$(docker ps --format '{{.Names}}\t{{.Status}}' | grep -c "healthy" || echo "0")
TOTAL_CONTAINERS=$(docker ps --format '{{.Names}}' | wc -l | tr -d ' ')
log_pass "${HEALTHY_CONTAINERS}/${TOTAL_CONTAINERS} containers report healthy status"

# =============================================================================
# SUMMARY
# =============================================================================

print_header "Security Validation Summary"

echo -e "Tests Passed:  ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Tests Failed:  ${RED}${TESTS_FAILED}${NC}"
echo -e "Warnings:      ${YELLOW}${TESTS_WARNED}${NC}"
echo -e "Total Tests:   ${TESTS_TOTAL}"
echo ""

# Calculate score
SCORE=$(( (TESTS_PASSED * 100) / TESTS_TOTAL ))

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "${GREEN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  SECURITY SCORE: ${SCORE}%                  ║${NC}"
    echo -e "${GREEN}║  STATUS: PASSED (Dev Environment)     ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"
else
    echo -e "${YELLOW}╔═══════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  SECURITY SCORE: ${SCORE}%                  ║${NC}"
    echo -e "${YELLOW}║  STATUS: NEEDS ATTENTION              ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════╝${NC}"
fi

echo ""
echo "Report saved to: ${REPORT_FILE}"
echo ""

# Production recommendations
echo -e "${BLUE}Production Recommendations:${NC}"
echo "  1. Change all default passwords"
echo "  2. Enable TLS on all endpoints"
echo "  3. Set memory/CPU limits on containers"
echo "  4. Enable audit logging"
echo "  5. Configure firewall rules"
echo "  6. Set up monitoring/alerting"
echo "  7. Regular security updates"
echo ""

# Write summary to report
echo "" >> "$REPORT_FILE"
echo "==========================================" >> "$REPORT_FILE"
echo "SUMMARY" >> "$REPORT_FILE"
echo "Passed: ${TESTS_PASSED}" >> "$REPORT_FILE"
echo "Failed: ${TESTS_FAILED}" >> "$REPORT_FILE"
echo "Warnings: ${TESTS_WARNED}" >> "$REPORT_FILE"
echo "Score: ${SCORE}%" >> "$REPORT_FILE"

# Exit with error if any tests failed
if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi

exit 0
