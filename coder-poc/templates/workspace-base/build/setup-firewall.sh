#!/bin/bash
# Network Egress Firewall for Contractor Workspaces
# Restricts outbound connections to approved internal services only.
# Runs via sudo in the container entrypoint (requires NET_ADMIN capability).
#
# This script is idempotent — safe to run multiple times (flushes rules first).
#
# EXCEPTION HANDLING:
#   Admins can grant additional egress access via:
#   1. Environment variable: EGRESS_EXTRA_PORTS="8443,8888,3128"
#   2. Exception file: /etc/egress-exceptions.conf (one rule per line)
#
#   Exception file format (lines starting with # are comments):
#     port:<port>                    — allow TCP to any host on this port
#     host:<ip>                      — allow all TCP to this specific IP
#     host:<ip>:port:<port>          — allow TCP to specific IP + port
#     cidr:<cidr>                    — allow all TCP to this CIDR range
#     cidr:<cidr>:port:<port>        — allow TCP to CIDR + specific port
#
#   Example /etc/egress-exceptions.conf:
#     # Allow access to internal Nexus artifact repository
#     host:10.0.5.20:port:8081
#     # Allow access to corporate npm registry
#     host:10.0.5.30:port:443
#     # Allow HTTPS to partner API subnet
#     cidr:10.100.0.0/16:port:443
#     # Allow access to internal Kafka cluster
#     port:9092

set -e

# Only run as root
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: setup-firewall.sh must be run as root (via sudo)"
    exit 1
fi

# Check if iptables is available
if ! command -v iptables &>/dev/null; then
    echo "WARNING: iptables not found, skipping firewall setup"
    exit 0
fi

echo "Setting up network egress firewall..."

# Flush existing OUTPUT rules (idempotent)
iptables -F OUTPUT 2>/dev/null || true

# ─── ALLOW: Core infrastructure (always allowed) ─────────────────────────────

# Allow loopback (localhost communication within container)
iptables -A OUTPUT -o lo -j ACCEPT

# Allow established/related connections (responses to allowed requests)
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow DNS resolution (required for all network operations)
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# ─── ALLOW: Platform services (always allowed) ───────────────────────────────

# Coder server (agent callback, workspace API)
iptables -A OUTPUT -p tcp --dport 7443 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 7080 -j ACCEPT

# LiteLLM AI Gateway
iptables -A OUTPUT -p tcp --dport 4000 -j ACCEPT

# Gitea Git Server (HTTP + SSH for git operations)
iptables -A OUTPUT -p tcp --dport 3000 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 2222 -j ACCEPT

# Key Provisioner (AI key auto-provisioning)
iptables -A OUTPUT -p tcp --dport 8100 -j ACCEPT

# DevDB PostgreSQL (development database)
iptables -A OUTPUT -p tcp --dport 5432 -j ACCEPT

# DevDB MySQL (development database)
iptables -A OUTPUT -p tcp --dport 3306 -j ACCEPT

# Authentik (OIDC, only needed for auth flows)
iptables -A OUTPUT -p tcp --dport 9000 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 9443 -j ACCEPT

# MinIO S3 storage (artifact storage)
iptables -A OUTPUT -p tcp --dport 9001 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 9002 -j ACCEPT

# Langfuse (AI observability)
iptables -A OUTPUT -p tcp --dport 3100 -j ACCEPT

# code-server (internal, localhost access within container)
iptables -A OUTPUT -p tcp --dport 8080 -j ACCEPT

# ─── ALLOW: Extra ports from environment variable ────────────────────────────
# Set via workspace parameter or container env: EGRESS_EXTRA_PORTS="8443,8888"

EXTRA_PORTS="${EGRESS_EXTRA_PORTS:-}"
if [ -n "$EXTRA_PORTS" ]; then
    echo "Applying extra port exceptions from EGRESS_EXTRA_PORTS: $EXTRA_PORTS"
    IFS=',' read -ra PORTS <<< "$EXTRA_PORTS"
    for port in "${PORTS[@]}"; do
        port=$(echo "$port" | tr -d '[:space:]')
        if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
            iptables -A OUTPUT -p tcp --dport "$port" -j ACCEPT
            echo "  + Allowed TCP port $port (env exception)"
        else
            echo "  ! Skipping invalid port: $port"
        fi
    done
fi

# ─── ALLOW: Exceptions from config files ─────────────────────────────────────
# Two layers of exception files:
#   1. /etc/egress-global.conf    — Environment-wide (applies to ALL workspaces in ALL templates)
#   2. /etc/egress-template.conf  — Template-specific (applies to workspaces using this template)
#
# Both files use the same format. Global rules are loaded first, then template rules.
# This gives admins a clear hierarchy:
#   - Global = corporate-wide services (Nexus, npm registry, monitoring)
#   - Template = project-specific services (partner API, team database, staging env)

apply_exception_file() {
    local file="$1"
    local label="$2"

    if [ ! -f "$file" ]; then
        echo "No $label exception file at $file"
        return
    fi

    echo "Applying $label exceptions from $file:"
    while IFS= read -r line; do
        # Skip comments and empty lines
        line=$(echo "$line" | sed 's/#.*//' | tr -d '[:space:]')
        [ -z "$line" ] && continue

        case "$line" in
            port:*)
                port="${line#port:}"
                if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
                    iptables -A OUTPUT -p tcp --dport "$port" -j ACCEPT
                    echo "  + Allowed TCP port $port ($label)"
                else
                    echo "  ! Invalid port rule: $line"
                fi
                ;;
            host:*:port:*)
                host=$(echo "$line" | sed 's/host:\([^:]*\):port:.*/\1/')
                port=$(echo "$line" | sed 's/.*:port:\(.*\)/\1/')
                if [[ "$port" =~ ^[0-9]+$ ]]; then
                    iptables -A OUTPUT -p tcp -d "$host" --dport "$port" -j ACCEPT
                    echo "  + Allowed TCP to $host:$port ($label)"
                else
                    echo "  ! Invalid host:port rule: $line"
                fi
                ;;
            host:*)
                host="${line#host:}"
                iptables -A OUTPUT -p tcp -d "$host" -j ACCEPT
                echo "  + Allowed all TCP to $host ($label)"
                ;;
            cidr:*:port:*)
                cidr=$(echo "$line" | sed 's/cidr:\([^:]*\):port:.*/\1/')
                port=$(echo "$line" | sed 's/.*:port:\(.*\)/\1/')
                if [[ "$port" =~ ^[0-9]+$ ]]; then
                    iptables -A OUTPUT -p tcp -d "$cidr" --dport "$port" -j ACCEPT
                    echo "  + Allowed TCP to $cidr:$port ($label)"
                else
                    echo "  ! Invalid cidr:port rule: $line"
                fi
                ;;
            cidr:*)
                cidr="${line#cidr:}"
                iptables -A OUTPUT -p tcp -d "$cidr" -j ACCEPT
                echo "  + Allowed all TCP to $cidr ($label)"
                ;;
            *)
                echo "  ! Unknown rule format: $line"
                ;;
        esac
    done < "$file"
}

# Load environment-wide exceptions first (corporate services)
apply_exception_file "/etc/egress-global.conf" "global"

# Load template-specific exceptions second (project services)
apply_exception_file "/etc/egress-template.conf" "template"

# ─── DENY: Everything else ───────────────────────────────────────────────────
# Log denied connections for monitoring (rate-limited to avoid log flood)
iptables -A OUTPUT -m limit --limit 5/min -j LOG --log-prefix "EGRESS_DENIED: " --log-level 4
iptables -A OUTPUT -j DROP

echo ""
echo "Network egress firewall configured."
echo "  Default: coder, litellm, gitea, key-provisioner, devdb, authentik, minio, langfuse, DNS"
[ -n "$EXTRA_PORTS" ] && echo "  Extra ports (workspace param): $EXTRA_PORTS"
[ -f "/etc/egress-global.conf" ] && echo "  Global exceptions: /etc/egress-global.conf"
[ -f "/etc/egress-template.conf" ] && echo "  Template exceptions: /etc/egress-template.conf"
echo "  Denied: all other outbound (logged as EGRESS_DENIED)"
echo ""

# Show rules for verification
iptables -L OUTPUT -n --line-numbers
