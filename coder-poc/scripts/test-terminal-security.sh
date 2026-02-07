#!/bin/bash
# test-terminal-security.sh — Validate Web Terminal Security Hardening
#
# Tests all P0 and P1 security measures applied to contractor workspaces:
#   P0: Sudoers restrictions, dangerous binary removal, Docker CLI removal,
#       shell audit logging, idle timeout
#   P1: Network egress firewall (iptables), PATH lockdown
#
# Usage:
#   ./scripts/test-terminal-security.sh                     # Auto-detect workspace container
#   ./scripts/test-terminal-security.sh <container_name>    # Specify container
#
# Requirements:
#   - Docker must be running
#   - Workspace container must be running (or specify container name)
#   - Run from the coder-poc directory

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0
WARN=0

pass()  { echo -e "  ${GREEN}✓${NC} $1"; PASS=$((PASS + 1)); }
fail()  { echo -e "  ${RED}✗${NC} $1"; FAIL=$((FAIL + 1)); }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; WARN=$((WARN + 1)); }
skip()  { echo -e "  ${YELLOW}⊘${NC} $1 (skipped)"; SKIP=$((SKIP + 1)); }
info()  { echo -e "  ${BLUE}ℹ${NC} $1"; }

# ─── Container Discovery ───────────────────────────────────────────────────────

CONTAINER="${1:-}"

if [ -z "$CONTAINER" ]; then
    # Auto-detect: find a running coder workspace container
    CONTAINER=$(docker ps --format '{{.Names}}' | grep -E '^coder-' | head -1 || true)
    if [ -z "$CONTAINER" ]; then
        echo -e "${RED}ERROR:${NC} No running coder workspace container found."
        echo "  Start a workspace first, or specify container name:"
        echo "  $0 <container_name>"
        echo ""
        echo "  Running containers:"
        docker ps --format '  {{.Names}}  ({{.Image}})'
        exit 1
    fi
fi

# Verify container exists and is running
if ! docker inspect "$CONTAINER" &>/dev/null; then
    echo -e "${RED}ERROR:${NC} Container '$CONTAINER' not found."
    exit 1
fi

CONTAINER_STATUS=$(docker inspect -f '{{.State.Status}}' "$CONTAINER")
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo -e "${RED}ERROR:${NC} Container '$CONTAINER' is not running (status: $CONTAINER_STATUS)."
    exit 1
fi

# Helper: run command in container as coder user
run_as_coder() {
    docker exec -u coder "$CONTAINER" bash -l -c "$1" 2>&1
}

# Helper: run command in container as root
run_as_root() {
    docker exec -u root "$CONTAINER" bash -c "$1" 2>&1
}

# ─── Test Header ────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Web Terminal Security Hardening — Validation Test Suite  ${NC}"
echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Container:  ${BLUE}$CONTAINER${NC}"
echo -e "  Image:      ${BLUE}$(docker inspect -f '{{.Config.Image}}' "$CONTAINER")${NC}"
echo -e "  Status:     ${GREEN}$CONTAINER_STATUS${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# P0 — CRITICAL TESTS
# ═══════════════════════════════════════════════════════════════════════════════

echo -e "${BOLD}P0 — Critical Security Measures${NC}"
echo ""

# ─── P0.1: Sudoers Restrictions ─────────────────────────────────────────────

echo "  P0.1  Sudoers Restrictions"

# Test: apt-get install is NOT allowed
OUTPUT=$(run_as_coder "sudo apt-get install netcat-openbsd 2>&1" || true)
if echo "$OUTPUT" | grep -qi "not allowed\|permission denied\|sorry"; then
    pass "sudo apt-get install is blocked"
else
    fail "sudo apt-get install is NOT blocked — contractor can install arbitrary packages"
    info "Output: $OUTPUT"
fi

# Test: apt-get update IS allowed (safe, read-only)
OUTPUT=$(run_as_coder "sudo -n apt-get update --print-uris 2>&1 | head -1" || true)
if echo "$OUTPUT" | grep -qvi "not allowed\|permission denied\|sorry"; then
    pass "sudo apt-get update is allowed (read-only)"
else
    fail "sudo apt-get update is blocked — may break cert updates"
fi

# Test: systemctl status IS allowed
OUTPUT=$(run_as_coder "sudo -n systemctl status cron 2>&1 | head -1" || true)
if echo "$OUTPUT" | grep -qvi "not allowed\|permission denied\|sorry"; then
    pass "sudo systemctl status is allowed (read-only)"
else
    warn "sudo systemctl status is blocked — minor, not critical"
fi

# Test: update-ca-certificates IS allowed
OUTPUT=$(run_as_coder "sudo -l 2>&1" || true)
if echo "$OUTPUT" | grep -q "update-ca-certificates"; then
    pass "sudo update-ca-certificates is allowed (needed for TLS)"
else
    fail "sudo update-ca-certificates is not in sudoers — TLS cert trust will fail"
fi

# Test: firewall script IS allowed (P1 dependency)
if echo "$OUTPUT" | grep -q "setup-firewall.sh"; then
    pass "sudo setup-firewall.sh is allowed (needed for P1 egress rules)"
else
    skip "sudo setup-firewall.sh not in sudoers (P1 not installed in image)"
fi

echo ""

# ─── P0.2: Docker CLI Removed ───────────────────────────────────────────────

echo "  P0.2  Docker CLI Removed"

OUTPUT=$(run_as_coder "which docker 2>&1" || true)
if echo "$OUTPUT" | grep -qi "not found\|no docker"; then
    pass "docker CLI is not installed"
else
    fail "docker CLI found at: $OUTPUT — container escape risk"
fi

# Also check common alternative paths
OUTPUT=$(run_as_coder "ls -la /usr/bin/docker /usr/local/bin/docker 2>&1" || true)
if echo "$OUTPUT" | grep -qi "no such file\|cannot access"; then
    pass "docker binary not found in common paths"
else
    fail "docker binary exists: $OUTPUT"
fi

echo ""

# ─── P0.3: Dangerous Binaries Removed ───────────────────────────────────────

echo "  P0.3  Dangerous Network Binaries Removed"

DANGEROUS_BINARIES="ssh scp sftp ssh-keygen ssh-keyscan nc ncat netcat telnet ftp socat nmap"
ALL_REMOVED=true

for bin in $DANGEROUS_BINARIES; do
    OUTPUT=$(run_as_coder "which $bin 2>&1" || true)
    if echo "$OUTPUT" | grep -qi "not found\|no $bin"; then
        pass "$bin is not available"
    else
        fail "$bin found at: $OUTPUT — exfiltration/recon risk"
        ALL_REMOVED=false
    fi
done

# Test: openssh-client package not installed
OUTPUT=$(run_as_coder "dpkg -l openssh-client 2>&1" || true)
if echo "$OUTPUT" | grep -qi "no packages\|not installed\|dpkg-query: no"; then
    pass "openssh-client package is not installed"
else
    if echo "$OUTPUT" | grep -q "^ii"; then
        fail "openssh-client package IS installed"
    else
        pass "openssh-client package is not installed"
    fi
fi

echo ""

# ─── P0.4: Development Tools Still Work ──────────────────────────────────────

echo "  P0.4  Development Tools Still Available"

DEV_TOOLS="git curl wget python3 node npm vim jq"
for tool in $DEV_TOOLS; do
    OUTPUT=$(run_as_coder "which $tool 2>&1" || true)
    if echo "$OUTPUT" | grep -qi "not found"; then
        fail "$tool is missing — needed for development"
    else
        pass "$tool is available"
    fi
done

echo ""

# ─── P0.5: Shell Audit Logging ──────────────────────────────────────────────

echo "  P0.5  Shell Audit Logging"

# Test: PROMPT_COMMAND is set with logger
OUTPUT=$(run_as_coder 'echo "$PROMPT_COMMAND"' || true)
if echo "$OUTPUT" | grep -q "logger"; then
    pass "PROMPT_COMMAND includes logger (command audit active)"
else
    fail "PROMPT_COMMAND does not include logger — commands are not being audited"
fi

# Test: HISTTIMEFORMAT is set
OUTPUT=$(run_as_coder 'echo "$HISTTIMEFORMAT"' || true)
if [ -n "$OUTPUT" ] && echo "$OUTPUT" | grep -q "%"; then
    pass "HISTTIMEFORMAT is set (timestamps in history)"
else
    fail "HISTTIMEFORMAT is not set — no timestamps in command history"
fi

# Test: shell-audit.sh profile script exists
OUTPUT=$(run_as_root "test -f /etc/profile.d/shell-audit.sh && echo exists" || true)
if echo "$OUTPUT" | grep -q "exists"; then
    pass "/etc/profile.d/shell-audit.sh exists"
else
    fail "/etc/profile.d/shell-audit.sh missing — audit logging not configured"
fi

echo ""

# ─── P0.6: Idle Session Timeout ─────────────────────────────────────────────

echo "  P0.6  Idle Session Timeout"

# Test: TMOUT is set to 1800
OUTPUT=$(run_as_coder 'echo "$TMOUT"' || true)
if [ "$OUTPUT" = "1800" ]; then
    pass "TMOUT is set to 1800 (30-minute idle timeout)"
elif [ -n "$OUTPUT" ]; then
    warn "TMOUT is set to $OUTPUT (expected 1800)"
else
    fail "TMOUT is not set — no idle timeout, abandoned sessions stay open"
fi

# Test: TMOUT is readonly
OUTPUT=$(run_as_coder 'unset TMOUT 2>&1' || true)
if echo "$OUTPUT" | grep -qi "readonly\|cannot unset"; then
    pass "TMOUT is readonly (user cannot disable it)"
else
    fail "TMOUT is NOT readonly — user can disable idle timeout with 'unset TMOUT'"
fi

# Test: idle-timeout.sh profile script exists
OUTPUT=$(run_as_root "test -f /etc/profile.d/idle-timeout.sh && echo exists" || true)
if echo "$OUTPUT" | grep -q "exists"; then
    pass "/etc/profile.d/idle-timeout.sh exists"
else
    fail "/etc/profile.d/idle-timeout.sh missing — idle timeout not configured"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# P1 — IMPORTANT TESTS
# ═══════════════════════════════════════════════════════════════════════════════

echo -e "${BOLD}P1 — Important Security Measures${NC}"
echo ""

# ─── P1.1: Network Egress Firewall ──────────────────────────────────────────

echo "  P1.1  Network Egress Firewall (iptables)"

# Test: iptables rules exist in OUTPUT chain
OUTPUT=$(run_as_root "iptables -L OUTPUT -n 2>&1" || true)
if echo "$OUTPUT" | grep -qi "DROP\|REJECT"; then
    pass "iptables OUTPUT chain has deny rules (firewall active)"

    # Count rules
    RULE_COUNT=$(echo "$OUTPUT" | grep -c "ACCEPT\|DROP\|LOG" || true)
    info "iptables OUTPUT chain has $RULE_COUNT rules"
else
    if echo "$OUTPUT" | grep -qi "iptables.*not found\|command not found"; then
        skip "iptables not installed (P1 firewall not in this image)"
    elif echo "$OUTPUT" | grep -qi "permission denied\|Operation not permitted"; then
        skip "Cannot read iptables rules (NET_ADMIN capability may not be set)"
    else
        fail "iptables OUTPUT chain has no deny rules — egress is unrestricted"
        info "Output: $(echo "$OUTPUT" | head -5)"
    fi
fi

# Test: approved ports are allowed
APPROVED_PORTS="4000 3000 5432 7443 8100 53"
for port in $APPROVED_PORTS; do
    if echo "$OUTPUT" | grep -q "dpt:$port"; then
        pass "Port $port is allowed (approved service)"
    else
        if echo "$OUTPUT" | grep -qi "DROP"; then
            warn "Port $port not explicitly listed in iptables rules"
        else
            skip "Cannot verify port $port (firewall not active)"
        fi
    fi
done

# Test: egress to unapproved host is blocked
# Try to reach an external host (should timeout or be blocked)
OUTPUT=$(run_as_coder "curl -s --max-time 3 --connect-timeout 3 http://example.com 2>&1" || true)
if echo "$OUTPUT" | grep -qi "timed out\|connection refused\|network unreachable\|couldn't connect\|failed to connect"; then
    pass "Egress to external host (example.com) is blocked"
elif [ -z "$OUTPUT" ]; then
    pass "Egress to external host (example.com) returned empty (likely blocked)"
else
    if echo "$OUTPUT" | grep -qi "DOCTYPE\|Example Domain"; then
        fail "Egress to external host (example.com) succeeded — firewall not blocking"
    else
        warn "Egress test to example.com returned unexpected output: $(echo "$OUTPUT" | head -1)"
    fi
fi

# Test: egress to approved service works (litellm health check)
OUTPUT=$(run_as_coder "curl -s --max-time 5 http://litellm:4000/health 2>&1" || true)
if echo "$OUTPUT" | grep -qi "healthy\|ok\|running"; then
    pass "Egress to approved service (litellm:4000) works"
elif echo "$OUTPUT" | grep -qi "connection refused\|couldn't connect"; then
    skip "LiteLLM not reachable (service may not be running)"
else
    warn "LiteLLM health check returned: $(echo "$OUTPUT" | head -1)"
fi

# Test: denied connections are logged
OUTPUT=$(run_as_root "iptables -L OUTPUT -n 2>&1" || true)
if echo "$OUTPUT" | grep -q "LOG.*EGRESS_DENIED"; then
    pass "Denied connections are logged (EGRESS_DENIED prefix)"
else
    if echo "$OUTPUT" | grep -qi "DROP"; then
        warn "Denied connections are dropped but not logged (add LOG rule for monitoring)"
    else
        skip "Cannot verify logging rules (firewall not active)"
    fi
fi

# Test: contractor cannot modify firewall rules
OUTPUT=$(run_as_coder "sudo iptables -F OUTPUT 2>&1" || true)
if echo "$OUTPUT" | grep -qi "not allowed\|permission denied\|sorry"; then
    pass "Contractor cannot flush iptables rules (sudo restricted)"
else
    fail "Contractor CAN modify iptables rules — firewall can be bypassed"
fi

echo ""

# ─── P1.2: PATH Lockdown ────────────────────────────────────────────────────

echo "  P1.2  PATH Lockdown"

# Test: PATH is readonly
OUTPUT=$(run_as_coder 'export PATH="/tmp:$PATH" 2>&1' || true)
if echo "$OUTPUT" | grep -qi "readonly"; then
    pass "PATH is readonly (user cannot modify it)"
else
    fail "PATH is NOT readonly — user can add directories to PATH"
fi

# Test: PATH contains expected directories
EXPECTED_DIRS="/usr/local/bin /usr/bin /bin /home/coder/.local/bin /home/coder/.opencode/bin /usr/local/go/bin"
CURRENT_PATH=$(run_as_coder 'echo "$PATH"' || true)
for dir in $EXPECTED_DIRS; do
    if echo "$CURRENT_PATH" | grep -q "$dir"; then
        pass "PATH includes $dir"
    else
        warn "PATH missing $dir (may affect development tools)"
    fi
done

# Test: PATH does not contain suspicious directories
SUSPICIOUS_DIRS="/tmp /var/tmp /dev/shm"
for dir in $SUSPICIOUS_DIRS; do
    if echo "$CURRENT_PATH" | grep -q "$dir"; then
        fail "PATH contains $dir — potential binary injection point"
    else
        pass "PATH does not contain $dir"
    fi
done

# Test: path-lockdown.sh profile script exists
OUTPUT=$(run_as_root "test -f /etc/profile.d/path-lockdown.sh && echo exists" || true)
if echo "$OUTPUT" | grep -q "exists"; then
    pass "/etc/profile.d/path-lockdown.sh exists"
else
    fail "/etc/profile.d/path-lockdown.sh missing — PATH lockdown not configured"
fi

echo ""

# ─── P1.3: Egress Exception Files ───────────────────────────────────────────

echo "  P1.3  Egress Exception Configuration"

# Test: global exception file is mounted
OUTPUT=$(run_as_root "test -f /etc/egress-global.conf && echo exists" || true)
if echo "$OUTPUT" | grep -q "exists"; then
    pass "/etc/egress-global.conf is mounted (environment-wide exceptions)"
else
    skip "/etc/egress-global.conf not mounted (global exceptions not configured)"
fi

# Test: template exception file is mounted
OUTPUT=$(run_as_root "test -f /etc/egress-template.conf && echo exists" || true)
if echo "$OUTPUT" | grep -q "exists"; then
    pass "/etc/egress-template.conf is mounted (template-specific exceptions)"
else
    skip "/etc/egress-template.conf not mounted (template exceptions not configured)"
fi

# Test: exception files are read-only (contractor cannot modify them)
OUTPUT=$(run_as_coder "echo test >> /etc/egress-global.conf 2>&1" || true)
if echo "$OUTPUT" | grep -qi "read-only\|permission denied\|operation not permitted"; then
    pass "/etc/egress-global.conf is read-only (contractor cannot modify)"
else
    if run_as_root "test -f /etc/egress-global.conf" 2>/dev/null; then
        fail "/etc/egress-global.conf is writable by contractor — exception bypass risk"
    else
        skip "Cannot test (file not mounted)"
    fi
fi

OUTPUT=$(run_as_coder "echo test >> /etc/egress-template.conf 2>&1" || true)
if echo "$OUTPUT" | grep -qi "read-only\|permission denied\|operation not permitted"; then
    pass "/etc/egress-template.conf is read-only (contractor cannot modify)"
else
    if run_as_root "test -f /etc/egress-template.conf" 2>/dev/null; then
        fail "/etc/egress-template.conf is writable by contractor — exception bypass risk"
    else
        skip "Cannot test (file not mounted)"
    fi
fi

# Test: EGRESS_EXTRA_PORTS env var is set (workspace parameter)
OUTPUT=$(run_as_coder 'echo "$EGRESS_EXTRA_PORTS"' || true)
if [ -n "$OUTPUT" ] && [ "$OUTPUT" != "" ]; then
    info "EGRESS_EXTRA_PORTS is set: $OUTPUT"
    # Verify the extra ports are in iptables rules
    IFS=',' read -ra EPORTS <<< "$OUTPUT"
    IPTABLES_OUTPUT=$(run_as_root "iptables -L OUTPUT -n 2>&1" || true)
    for eport in "${EPORTS[@]}"; do
        eport=$(echo "$eport" | tr -d '[:space:]')
        if echo "$IPTABLES_OUTPUT" | grep -q "dpt:$eport"; then
            pass "Extra port $eport is in iptables rules (workspace exception active)"
        else
            fail "Extra port $eport is in EGRESS_EXTRA_PORTS but NOT in iptables rules"
        fi
    done
else
    info "EGRESS_EXTRA_PORTS is empty (no workspace-level port exceptions)"
fi

# Test: exception rules from files are in iptables (if files have uncommented rules)
GLOBAL_RULES=0
if run_as_root "test -f /etc/egress-global.conf" 2>/dev/null; then
    GLOBAL_RULES=$(run_as_root "grep -v '^#' /etc/egress-global.conf | grep -v '^\s*$' | wc -l" || echo "0")
    GLOBAL_RULES=$(echo "$GLOBAL_RULES" | tr -d '[:space:]')
fi
TEMPLATE_RULES=0
if run_as_root "test -f /etc/egress-template.conf" 2>/dev/null; then
    TEMPLATE_RULES=$(run_as_root "grep -v '^#' /etc/egress-template.conf | grep -v '^\s*$' | wc -l" || echo "0")
    TEMPLATE_RULES=$(echo "$TEMPLATE_RULES" | tr -d '[:space:]')
fi
info "Active exception rules: global=$GLOBAL_RULES, template=$TEMPLATE_RULES"

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# BONUS — EXISTING CODER LOCKDOWN
# ═══════════════════════════════════════════════════════════════════════════════

echo -e "${BOLD}Coder Platform Lockdown (Template-Level)${NC}"
echo ""

echo "  B.1  Connection Restrictions"

# Test: no-new-privileges security opt
OUTPUT=$(docker inspect -f '{{.HostConfig.SecurityOpt}}' "$CONTAINER" 2>/dev/null || true)
if echo "$OUTPUT" | grep -q "no-new-privileges"; then
    pass "no-new-privileges security option is set"
else
    warn "no-new-privileges not set on container"
fi

# Test: container runs as non-root
OUTPUT=$(docker inspect -f '{{.Config.User}}' "$CONTAINER" 2>/dev/null || true)
if [ -n "$OUTPUT" ] && [ "$OUTPUT" != "root" ] && [ "$OUTPUT" != "0" ]; then
    pass "Container runs as non-root user ($OUTPUT)"
else
    if [ -z "$OUTPUT" ]; then
        warn "Container user not explicitly set (may run as root)"
    else
        fail "Container runs as root — should use non-root user"
    fi
fi

# Test: NET_ADMIN capability (needed for iptables, but documented trade-off)
OUTPUT=$(docker inspect -f '{{.HostConfig.CapAdd}}' "$CONTAINER" 2>/dev/null || true)
if echo "$OUTPUT" | grep -q "NET_ADMIN"; then
    info "NET_ADMIN capability is set (required for P1 iptables firewall)"
else
    info "NET_ADMIN capability not set (P1 firewall requires it)"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

TOTAL=$((PASS + FAIL + SKIP + WARN))

echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Test Summary${NC}"
echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${GREEN}✓ Passed:${NC}   $PASS"
echo -e "  ${RED}✗ Failed:${NC}   $FAIL"
echo -e "  ${YELLOW}⚠ Warned:${NC}   $WARN"
echo -e "  ${YELLOW}⊘ Skipped:${NC}  $SKIP"
echo -e "  ─────────────────"
echo -e "  Total:      $TOTAL"
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo -e "  ${GREEN}${BOLD}All critical tests passed!${NC}"
    if [ "$WARN" -gt 0 ]; then
        echo -e "  ${YELLOW}Review warnings above for potential improvements.${NC}"
    fi
    echo ""
    exit 0
else
    echo -e "  ${RED}${BOLD}$FAIL test(s) FAILED — security hardening incomplete.${NC}"
    echo -e "  Review failures above and rebuild the workspace image."
    echo ""
    echo -e "  ${BLUE}Rebuild steps:${NC}"
    echo "    cd coder-poc/templates/contractor-workspace/build"
    echo "    docker build -t contractor-workspace:latest ."
    echo "    cd ../../.."
    echo "    coder templates push contractor-workspace --yes"
    echo ""
    exit 1
fi
