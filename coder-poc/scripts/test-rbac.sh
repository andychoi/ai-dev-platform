#!/bin/bash
# test-rbac.sh — Validate RBAC & Access Control Configuration
#
# Tests role-based access control across the platform:
#   Layer 1: Static config (docker-compose.yml, main.tf) — always runs
#   Layer 2: Authentik API (groups, OIDC mapping) — requires Authentik running
#   Layer 3: Coder API (user roles, endpoint protection) — requires Coder running
#   Layer 4: LiteLLM admin protection — requires LiteLLM running
#
# Usage:
#   ./scripts/test-rbac.sh                       # Run all layers (skip unavailable services)
#   CODER_ADMIN_TOKEN=xxx ./scripts/test-rbac.sh  # Provide Coder session token
#
# Requirements:
#   - Run from the coder-poc directory
#   - Services should be running for full validation

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

# ─── Paths ────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
TEMPLATE_FILE="$PROJECT_DIR/templates/contractor-workspace/main.tf"

CODER_URL="${CODER_URL:-https://host.docker.internal:7443}"
AUTHENTIK_URL="${AUTHENTIK_URL:-http://localhost:9000}"
LITELLM_URL="${LITELLM_URL:-http://localhost:4000}"

echo -e "${BOLD}=== RBAC & Access Control Validation ===${NC}"
echo "  Compose: $COMPOSE_FILE"
echo "  Template: $TEMPLATE_FILE"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# LAYER 1: Static Configuration (always runs, no services needed)
# ═══════════════════════════════════════════════════════════════════════════════

echo -e "${BOLD}── Layer 1: Static Configuration ──${NC}"

# ─── 1.1 OIDC Group-to-Role Mapping Env Vars ─────────────────────────────────

echo -e "\n${BLUE}[1.1] OIDC group-to-role mapping (docker-compose.yml)${NC}"

if [ ! -f "$COMPOSE_FILE" ]; then
    fail "docker-compose.yml not found at $COMPOSE_FILE"
else
    # Check CODER_OIDC_GROUP_FIELD
    if grep -q 'CODER_OIDC_GROUP_FIELD.*groups' "$COMPOSE_FILE"; then
        pass "CODER_OIDC_GROUP_FIELD is set to 'groups'"
    else
        fail "CODER_OIDC_GROUP_FIELD not set or not 'groups'"
    fi

    # Check CODER_OIDC_USER_ROLE_FIELD
    if grep -q 'CODER_OIDC_USER_ROLE_FIELD.*groups' "$COMPOSE_FILE"; then
        pass "CODER_OIDC_USER_ROLE_FIELD is set to 'groups'"
    else
        fail "CODER_OIDC_USER_ROLE_FIELD not set — roles won't sync from OIDC"
    fi

    # Check CODER_OIDC_USER_ROLE_MAPPING contains the three key mappings
    if grep -q 'CODER_OIDC_USER_ROLE_MAPPING' "$COMPOSE_FILE"; then
        pass "CODER_OIDC_USER_ROLE_MAPPING is defined"

        # Check individual role mappings in the YAML block
        if grep -A5 'CODER_OIDC_USER_ROLE_MAPPING' "$COMPOSE_FILE" | grep -q 'coder-admins.*owner'; then
            pass "  coder-admins → owner mapping present"
        else
            fail "  coder-admins → owner mapping missing"
        fi

        if grep -A5 'CODER_OIDC_USER_ROLE_MAPPING' "$COMPOSE_FILE" | grep -q 'coder-template-admins.*template-admin'; then
            pass "  coder-template-admins → template-admin mapping present"
        else
            fail "  coder-template-admins → template-admin mapping missing"
        fi

        if grep -A5 'CODER_OIDC_USER_ROLE_MAPPING' "$COMPOSE_FILE" | grep -q 'coder-auditors.*auditor'; then
            pass "  coder-auditors → auditor mapping present"
        else
            fail "  coder-auditors → auditor mapping missing"
        fi
    else
        fail "CODER_OIDC_USER_ROLE_MAPPING not defined — all SSO users get Member role"
    fi

    # Check CODER_OIDC_GROUP_AUTO_CREATE
    if grep -q 'CODER_OIDC_GROUP_AUTO_CREATE.*true' "$COMPOSE_FILE"; then
        pass "CODER_OIDC_GROUP_AUTO_CREATE enabled (groups sync on login)"
    else
        warn "CODER_OIDC_GROUP_AUTO_CREATE not enabled — groups may not sync"
    fi
fi

# ─── 1.2 Security Settings ───────────────────────────────────────────────────

echo -e "\n${BLUE}[1.2] Security settings (docker-compose.yml)${NC}"

if [ -f "$COMPOSE_FILE" ]; then
    # CODER_DISABLE_OWNER_WORKSPACE_ACCESS
    if grep -q 'CODER_DISABLE_OWNER_WORKSPACE_ACCESS.*true' "$COMPOSE_FILE"; then
        pass "CODER_DISABLE_OWNER_WORKSPACE_ACCESS enabled (admin can't access contractor terminals)"
    else
        fail "CODER_DISABLE_OWNER_WORKSPACE_ACCESS not enabled — admin can open contractor terminals"
    fi

    # CODER_DISABLE_WORKSPACE_SHARING
    if grep -q 'CODER_DISABLE_WORKSPACE_SHARING.*true' "$COMPOSE_FILE"; then
        pass "CODER_DISABLE_WORKSPACE_SHARING enabled (no workspace sharing)"
    else
        fail "CODER_DISABLE_WORKSPACE_SHARING not enabled — users can share workspaces"
    fi

    # CODER_SECURE_AUTH_COOKIE
    if grep -q 'CODER_SECURE_AUTH_COOKIE.*true' "$COMPOSE_FILE"; then
        pass "CODER_SECURE_AUTH_COOKIE enabled (HTTPS-only cookies)"
    else
        warn "CODER_SECURE_AUTH_COOKIE not enabled — cookies sent over HTTP"
    fi

    # CODER_MAX_SESSION_EXPIRY
    if grep -q 'CODER_MAX_SESSION_EXPIRY' "$COMPOSE_FILE"; then
        EXPIRY=$(grep 'CODER_MAX_SESSION_EXPIRY' "$COMPOSE_FILE" | head -1 | sed 's/.*:-//' | sed 's/[}"]*$//')
        pass "CODER_MAX_SESSION_EXPIRY set (${EXPIRY})"
    else
        warn "CODER_MAX_SESSION_EXPIRY not set — using default (may be too long)"
    fi

    # CODER_AIBRIDGE_ENABLED
    if grep -q 'CODER_AIBRIDGE_ENABLED.*false' "$COMPOSE_FILE"; then
        pass "CODER_AIBRIDGE_ENABLED disabled (using LiteLLM instead)"
    else
        warn "CODER_AIBRIDGE_ENABLED not disabled — built-in AI chat is active"
    fi

    # CODER_HIDE_AI_TASKS
    if grep -q 'CODER_HIDE_AI_TASKS.*true' "$COMPOSE_FILE"; then
        pass "CODER_HIDE_AI_TASKS enabled (AI task sidebar hidden)"
    else
        info "CODER_HIDE_AI_TASKS not set — AI task sidebar may be visible"
    fi

    # Disable default GitHub OAuth2
    if grep -q 'CODER_OAUTH2_GITHUB_DEFAULT_PROVIDER_ENABLE.*false' "$COMPOSE_FILE"; then
        pass "Default GitHub OAuth2 provider disabled"
    else
        warn "Default GitHub OAuth2 provider not disabled — GitHub login button may show"
    fi

    # TLS enabled
    if grep -q 'CODER_TLS_ENABLE.*true' "$COMPOSE_FILE"; then
        pass "TLS enabled (HTTPS required for secure context)"
    else
        fail "TLS not enabled — extension webviews will be blank (crypto.subtle unavailable)"
    fi
fi

# ─── 1.3 Template Parameter Mutability ────────────────────────────────────────

echo -e "\n${BLUE}[1.3] Template parameter mutability (main.tf)${NC}"

if [ ! -f "$TEMPLATE_FILE" ]; then
    fail "Template file not found at $TEMPLATE_FILE"
else
    # Helper: check a parameter's mutable setting
    check_mutability() {
        local param_name=$1
        local expected=$2
        local description=$3

        # Extract the parameter block and find mutable setting
        local block
        block=$(awk "/data \"coder_parameter\" \"${param_name}\"/,/^}/" "$TEMPLATE_FILE")
        local mutable_value
        mutable_value=$(echo "$block" | grep 'mutable' | head -1 | awk -F'=' '{print $2}' | awk '{print $1}')

        if [ "$mutable_value" = "$expected" ]; then
            pass "${param_name}: mutable=${mutable_value} (${description})"
        else
            fail "${param_name}: mutable=${mutable_value}, expected ${expected} (${description})"
        fi
    }

    # Security-sensitive: must be immutable (mutable = false)
    check_mutability "ai_enforcement_level" "false" "admin-only, locks AI behavior mode"
    check_mutability "egress_extra_ports" "false" "admin-only, locks network exceptions"
    check_mutability "disk_size" "false" "admin-only, locks storage allocation"
    check_mutability "database_type" "false" "admin-only, locks database provisioning"

    # User-modifiable: should be mutable (mutable = true)
    check_mutability "cpu_cores" "true" "user can adjust CPU"
    check_mutability "memory_gb" "true" "user can adjust memory"
    check_mutability "ai_model" "true" "user can select AI model"
    check_mutability "git_repo" "true" "user can set repository"
fi

# ─── 1.4 Workspace Connection Controls ────────────────────────────────────────

echo -e "\n${BLUE}[1.4] Workspace connection controls (main.tf)${NC}"

if [ -f "$TEMPLATE_FILE" ]; then
    # Extract the display_apps block
    DISPLAY_BLOCK=$(awk '/display_apps/,/}/' "$TEMPLATE_FILE" | head -20)

    check_display_app() {
        local app_name=$1
        local expected=$2
        local description=$3

        local value
        value=$(echo "$DISPLAY_BLOCK" | grep "$app_name" | head -1 | awk -F'=' '{print $2}' | awk '{print $1}')

        if [ "$value" = "$expected" ]; then
            pass "${app_name} = ${value} (${description})"
        else
            fail "${app_name} = ${value}, expected ${expected} (${description})"
        fi
    }

    check_display_app "vscode " "false" "VS Code Desktop disabled"
    check_display_app "vscode_insiders" "false" "VS Code Insiders disabled"
    check_display_app "web_terminal" "true" "web terminal enabled (browser only)"
    check_display_app "ssh_helper" "false" "SSH disabled (no file transfer)"
    check_display_app "port_forwarding_helper" "false" "port forwarding disabled"

    # Check security opts
    if grep -q 'no-new-privileges:true' "$TEMPLATE_FILE"; then
        pass "no-new-privileges security opt set"
    else
        fail "no-new-privileges not set — privilege escalation possible"
    fi

    # Check NET_ADMIN for firewall
    if grep -q 'NET_ADMIN' "$TEMPLATE_FILE"; then
        pass "NET_ADMIN capability present (required for iptables firewall)"
    else
        warn "NET_ADMIN capability missing — egress firewall won't work"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# LAYER 2: Authentik API (requires Authentik running)
# ═══════════════════════════════════════════════════════════════════════════════

echo -e "\n${BOLD}── Layer 2: Authentik API ──${NC}"

AUTHENTIK_AVAILABLE=false
if curl -sf "${AUTHENTIK_URL}/-/health/ready/" > /dev/null 2>&1; then
    AUTHENTIK_AVAILABLE=true
    echo -e "  ${GREEN}✓${NC} Authentik is reachable at ${AUTHENTIK_URL}"
else
    echo -e "  ${YELLOW}⊘${NC} Authentik not reachable at ${AUTHENTIK_URL} — skipping Layer 2"
fi

if [ "$AUTHENTIK_AVAILABLE" = true ]; then
    # Get API token
    AUTHENTIK_TOKEN="${AUTHENTIK_TOKEN:-}"
    if [ -z "$AUTHENTIK_TOKEN" ]; then
        AUTHENTIK_TOKEN=$(docker exec authentik-server ak shell -c "
from authentik.core.models import Token, User
user = User.objects.get(username='akadmin')
token, created = Token.objects.get_or_create(
    identifier='rbac-test-token',
    defaults={'user': user, 'intent': 'api', 'expiring': False}
)
print(f'TOKEN:{token.key}')
" 2>&1 | grep "^TOKEN:" | cut -d: -f2 || true)
    fi

    if [ -z "$AUTHENTIK_TOKEN" ]; then
        warn "Could not obtain Authentik API token — skipping Authentik checks"
    else
        ak_api() {
            curl -sf -X GET "${AUTHENTIK_URL}/api/v3${1}" \
                -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
                -H "Content-Type: application/json" 2>/dev/null
        }

        # ─── 2.1 Required Groups ─────────────────────────────────────────────

        echo -e "\n${BLUE}[2.1] Required Authentik groups${NC}"

        for group_name in coder-admins coder-template-admins coder-auditors coder-members; do
            GROUP_EXISTS=$(ak_api "/core/groups/?name=${group_name}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(len(data.get('results', [])) > 0)
" 2>/dev/null || echo "False")

            if [ "$GROUP_EXISTS" = "True" ]; then
                pass "Group '${group_name}' exists"
            else
                fail "Group '${group_name}' missing — run setup-authentik-rbac.sh"
            fi
        done

        # ─── 2.2 OIDC Property Mapping ───────────────────────────────────────

        echo -e "\n${BLUE}[2.2] OIDC 'groups' property mapping${NC}"

        MAPPING_EXISTS=$(ak_api "/propertymappings/scope/?name=Coder%20Groups%20Claim" | python3 -c "
import sys, json
data = json.load(sys.stdin)
results = data.get('results', [])
if results:
    expr = results[0].get('expression', '')
    print('FULL' if 'ak_groups' in expr else 'PARTIAL')
else:
    print('MISSING')
" 2>/dev/null || echo "ERROR")

        case "$MAPPING_EXISTS" in
            FULL)
                pass "OIDC 'Coder Groups Claim' mapping exists with correct expression"
                ;;
            PARTIAL)
                warn "OIDC 'Coder Groups Claim' exists but expression may be incorrect"
                ;;
            MISSING)
                fail "OIDC 'Coder Groups Claim' mapping missing — run setup-authentik-rbac.sh"
                ;;
            *)
                warn "Could not verify OIDC property mapping"
                ;;
        esac

        # ─── 2.3 Mapping assigned to Coder provider ──────────────────────────

        echo -e "\n${BLUE}[2.3] Groups mapping assigned to Coder OIDC provider${NC}"

        PROVIDER_CHECK=$(ak_api "/providers/oauth2/?name=coder" | python3 -c "
import sys, json
data = json.load(sys.stdin)
results = data.get('results', [])
if not results:
    print('NO_PROVIDER')
else:
    provider = results[0]
    mappings = provider.get('property_mappings', [])
    print(f'FOUND:{len(mappings)}')
" 2>/dev/null || echo "ERROR")

        if [[ "$PROVIDER_CHECK" == NO_PROVIDER ]]; then
            fail "Coder OIDC provider not found in Authentik"
        elif [[ "$PROVIDER_CHECK" == FOUND:* ]]; then
            COUNT=${PROVIDER_CHECK#FOUND:}
            if [ "$COUNT" -gt 0 ]; then
                pass "Coder OIDC provider has ${COUNT} property mappings"
            else
                warn "Coder OIDC provider has no property mappings — groups claim may be missing"
            fi
        else
            warn "Could not verify Coder OIDC provider mappings"
        fi

        # ─── 2.4 Test user group membership ──────────────────────────────────

        echo -e "\n${BLUE}[2.4] Test user group membership${NC}"

        check_user_groups() {
            local username=$1
            local expected_group=$2

            local user_groups
            user_groups=$(ak_api "/core/users/?username=${username}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
results = data.get('results', [])
if results:
    groups = results[0].get('groups_obj', [])
    names = [g.get('name','') for g in groups]
    print(','.join(names) if names else 'NONE')
else:
    print('NOT_FOUND')
" 2>/dev/null || echo "ERROR")

            if [ "$user_groups" = "NOT_FOUND" ]; then
                skip "User '${username}' not found in Authentik"
            elif [ "$user_groups" = "ERROR" ]; then
                skip "Could not query user '${username}'"
            elif [ -z "$expected_group" ]; then
                # No specific group expected (default member)
                info "User '${username}' groups: ${user_groups}"
            elif echo "$user_groups" | grep -q "$expected_group"; then
                pass "User '${username}' is in group '${expected_group}'"
            else
                warn "User '${username}' not in '${expected_group}' (groups: ${user_groups})"
                info "  Assign via: Authentik Admin → Directory → Groups → ${expected_group} → Add user"
            fi
        }

        check_user_groups "admin" "coder-admins"
        check_user_groups "app-manager" "coder-template-admins"
        check_user_groups "contractor1" ""
        check_user_groups "contractor2" ""
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# LAYER 3: Coder API (requires Coder running)
# ═══════════════════════════════════════════════════════════════════════════════

echo -e "\n${BOLD}── Layer 3: Coder API ──${NC}"

CODER_AVAILABLE=false
if curl -sfk "${CODER_URL}/api/v2/buildinfo" > /dev/null 2>&1; then
    CODER_AVAILABLE=true
    VERSION=$(curl -sfk "${CODER_URL}/api/v2/buildinfo" | python3 -c "import sys,json; print(json.load(sys.stdin).get('version','unknown'))" 2>/dev/null || echo "unknown")
    echo -e "  ${GREEN}✓${NC} Coder is reachable at ${CODER_URL} (version: ${VERSION})"
else
    echo -e "  ${YELLOW}⊘${NC} Coder not reachable at ${CODER_URL} — skipping Layer 3"
fi

if [ "$CODER_AVAILABLE" = true ]; then
    # Get admin session token (try env var first, then login)
    ADMIN_TOKEN="${CODER_ADMIN_TOKEN:-}"

    if [ -z "$ADMIN_TOKEN" ]; then
        ADMIN_USER="${CODER_ADMIN_USER:-admin}"
        ADMIN_PASS="${CODER_ADMIN_PASSWORD:-SecureP@ssw0rd!}"

        LOGIN_RESULT=$(curl -sfk -X POST "${CODER_URL}/api/v2/users/login" \
            -H "Content-Type: application/json" \
            -d "{\"email\":\"${ADMIN_USER}\",\"password\":\"${ADMIN_PASS}\"}" 2>/dev/null || true)

        ADMIN_TOKEN=$(echo "$LOGIN_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_token',''))" 2>/dev/null || true)
    fi

    if [ -z "$ADMIN_TOKEN" ]; then
        warn "Could not obtain Coder admin token — skipping role checks"
        info "Set CODER_ADMIN_TOKEN or CODER_ADMIN_PASSWORD to enable"
    else
        coder_api() {
            curl -sfk -X GET "${CODER_URL}/api/v2${1}" \
                -H "Coder-Session-Token: ${ADMIN_TOKEN}" \
                -H "Content-Type: application/json" 2>/dev/null
        }

        # ─── 3.1 User Roles ──────────────────────────────────────────────────

        echo -e "\n${BLUE}[3.1] Coder user roles${NC}"

        check_coder_role() {
            local username=$1
            local expected_role=$2

            local user_data
            user_data=$(coder_api "/users/${username}")
            if [ -z "$user_data" ]; then
                skip "User '${username}' not found in Coder"
                return
            fi

            local actual_roles
            actual_roles=$(echo "$user_data" | python3 -c "
import sys, json
data = json.load(sys.stdin)
roles = data.get('roles', [])
names = [r.get('name','') if isinstance(r, dict) else str(r) for r in roles]
print(','.join(names) if names else 'member')
" 2>/dev/null || echo "unknown")

            if echo "$actual_roles" | grep -qi "$expected_role"; then
                pass "User '${username}' has role '${expected_role}' (roles: ${actual_roles})"
            else
                warn "User '${username}' has roles '${actual_roles}', expected '${expected_role}'"
                info "  Role syncs on next SSO login. Check Authentik group membership."
            fi
        }

        check_coder_role "admin" "owner"
        check_coder_role "app-manager" "template-admin"
        check_coder_role "contractor1" "member"

        # ─── 3.2 Admin Endpoint Protection ────────────────────────────────────

        echo -e "\n${BLUE}[3.2] Admin endpoint protection (contractor cannot access)${NC}"

        # Try to get a contractor token
        CONTRACTOR_TOKEN=""
        CONTRACTOR_PASS="${CONTRACTOR_PASSWORD:-Contractor123!}"
        CONTRACTOR_LOGIN=$(curl -sfk -X POST "${CODER_URL}/api/v2/users/login" \
            -H "Content-Type: application/json" \
            -d "{\"email\":\"contractor1\",\"password\":\"${CONTRACTOR_PASS}\"}" 2>/dev/null || true)

        CONTRACTOR_TOKEN=$(echo "$CONTRACTOR_LOGIN" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_token',''))" 2>/dev/null || true)

        if [ -z "$CONTRACTOR_TOKEN" ]; then
            skip "Could not login as contractor1 — skipping endpoint protection tests"
            info "Contractor may use OIDC only (no password login). This is expected."
        else
            # Test admin-only API endpoints with contractor token
            test_admin_endpoint() {
                local endpoint=$1
                local description=$2

                local status
                status=$(curl -sk -o /dev/null -w "%{http_code}" \
                    "${CODER_URL}/api/v2${endpoint}" \
                    -H "Coder-Session-Token: ${CONTRACTOR_TOKEN}" 2>/dev/null || echo "000")

                if [ "$status" = "403" ] || [ "$status" = "404" ]; then
                    pass "${description}: ${status} (blocked)"
                elif [ "$status" = "401" ]; then
                    pass "${description}: ${status} (unauthorized)"
                elif [ "$status" = "200" ]; then
                    fail "${description}: ${status} (accessible — should be blocked!)"
                else
                    warn "${description}: HTTP ${status}"
                fi
            }

            test_admin_endpoint "/users" "List all users"
            test_admin_endpoint "/deployment/config" "Deployment settings"
            test_admin_endpoint "/audit" "Audit log"
            test_admin_endpoint "/templates" "List templates (should be visible but read-only)"
        fi

        # ─── 3.3 Deployment Settings ─────────────────────────────────────────

        echo -e "\n${BLUE}[3.3] Coder deployment settings (runtime verification)${NC}"

        DEPLOY_CONFIG=$(coder_api "/deployment/config" || echo "{}")

        if [ -n "$DEPLOY_CONFIG" ] && [ "$DEPLOY_CONFIG" != "{}" ]; then
            # Parse specific settings
            check_deploy_setting() {
                local json_path=$1
                local expected=$2
                local description=$3

                local actual
                actual=$(echo "$DEPLOY_CONFIG" | python3 -c "
import sys, json
data = json.load(sys.stdin)
# Navigate dot-separated path into the config
keys = '${json_path}'.split('.')
obj = data
for k in keys:
    if isinstance(obj, dict):
        obj = obj.get(k, {})
    else:
        obj = ''
        break
# Handle nested 'value' field common in Coder's API response
if isinstance(obj, dict) and 'value' in obj:
    obj = obj['value']
print(str(obj).lower() if obj else '')
" 2>/dev/null || echo "")

                if [ "$actual" = "$expected" ]; then
                    pass "${description}: ${actual}"
                elif [ -z "$actual" ]; then
                    skip "${description}: could not read value"
                else
                    warn "${description}: ${actual} (expected: ${expected})"
                fi
            }

            check_deploy_setting "disable_owner_workspace_access" "true" "Owner workspace access disabled"
            check_deploy_setting "disable_workspace_sharing" "true" "Workspace sharing disabled"
        else
            skip "Could not read deployment config — may lack admin permissions"
        fi
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# LAYER 4: LiteLLM Admin Protection
# ═══════════════════════════════════════════════════════════════════════════════

echo -e "\n${BOLD}── Layer 4: LiteLLM Admin Protection ──${NC}"

LITELLM_AVAILABLE=false
if curl -sf "${LITELLM_URL}/health/readiness" > /dev/null 2>&1; then
    LITELLM_AVAILABLE=true
    echo -e "  ${GREEN}✓${NC} LiteLLM is reachable at ${LITELLM_URL}"
else
    echo -e "  ${YELLOW}⊘${NC} LiteLLM not reachable at ${LITELLM_URL} — skipping Layer 4"
fi

if [ "$LITELLM_AVAILABLE" = true ]; then
    echo -e "\n${BLUE}[4.1] LiteLLM admin endpoints require master key${NC}"

    # Test without auth
    NO_AUTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
        "${LITELLM_URL}/key/list" 2>/dev/null || echo "000")

    if [ "$NO_AUTH_STATUS" = "401" ] || [ "$NO_AUTH_STATUS" = "403" ]; then
        pass "Key list endpoint blocked without auth (${NO_AUTH_STATUS})"
    elif [ "$NO_AUTH_STATUS" = "200" ]; then
        fail "Key list endpoint accessible without auth — master key not enforced!"
    else
        warn "Key list endpoint returned ${NO_AUTH_STATUS}"
    fi

    # Test with a fake key
    FAKE_KEY_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
        "${LITELLM_URL}/key/list" \
        -H "Authorization: Bearer sk-fake-invalid-key" 2>/dev/null || echo "000")

    if [ "$FAKE_KEY_STATUS" = "401" ] || [ "$FAKE_KEY_STATUS" = "403" ]; then
        pass "Key list endpoint rejects invalid key (${FAKE_KEY_STATUS})"
    elif [ "$FAKE_KEY_STATUS" = "200" ]; then
        fail "Key list endpoint accepts invalid key — auth is broken!"
    else
        warn "Key list endpoint returned ${FAKE_KEY_STATUS} for invalid key"
    fi

    # Test model list (should be accessible with valid workspace key)
    MODEL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
        "${LITELLM_URL}/v1/models" 2>/dev/null || echo "000")

    if [ "$MODEL_STATUS" = "200" ]; then
        pass "Model list endpoint is accessible (expected for workspace keys)"
    elif [ "$MODEL_STATUS" = "401" ]; then
        info "Model list requires auth (stricter config)"
    else
        warn "Model list returned ${MODEL_STATUS}"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
echo -e "${BOLD}  RBAC Validation Summary${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}Passed:${NC}  ${PASS}"
echo -e "  ${RED}Failed:${NC}  ${FAIL}"
echo -e "  ${YELLOW}Warnings:${NC} ${WARN}"
echo -e "  ${YELLOW}Skipped:${NC} ${SKIP}"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo -e "  ${RED}${BOLD}RESULT: FAIL${NC} — ${FAIL} check(s) need attention"
    echo ""
    echo -e "  ${BLUE}Remediation:${NC}"
    echo "    1. Run: ./scripts/setup-authentik-rbac.sh  (creates groups + OIDC mapping)"
    echo "    2. Run: docker compose up -d coder-server  (reload OIDC config)"
    echo "    3. Assign users to groups in Authentik Admin → Directory → Groups"
    echo "    4. Users get roles on next SSO login"
    echo ""
    exit 1
elif [ "$WARN" -gt 0 ]; then
    echo -e "  ${YELLOW}${BOLD}RESULT: PASS with warnings${NC}"
    exit 0
else
    echo -e "  ${GREEN}${BOLD}RESULT: ALL CHECKS PASSED${NC}"
    exit 0
fi
