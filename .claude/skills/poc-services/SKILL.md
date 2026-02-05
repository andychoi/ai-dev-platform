---
name: poc-services
description: Complete POC services reference - all 14 services, credentials, ports, networking, Docker troubleshooting
---

# POC Services Overview Skill

## Overview

This skill provides a complete reference for all services in the Coder WebIDE POC environment, including credential requirements, ports, and health checks.

## Service Registry

| Service | Port | Purpose | Health Check |
|---------|------|---------|--------------|
| **Coder** | 7080 | WebIDE platform | `http://localhost:7080/api/v2/buildinfo` |
| **Gitea** | 3000 | Git server | `http://localhost:3000/` |
| **Authentik** | 9000 | SSO/Identity Provider | `http://localhost:9000/-/health/ready/` |
| **MinIO Console** | 9001 | S3 storage UI | `http://localhost:9001/` |
| **MinIO API** | 9002 | S3 API endpoint | `http://localhost:9002/minio/health/live` |
| **AI Gateway** | 8090 | AI API proxy | `http://localhost:8090/health` |
| **Mailpit** | 8025 | Email testing | `http://localhost:8025/` |
| **DevDB** | 5432 | PostgreSQL (internal) | N/A (internal only) |

## Credential Requirements

### Admin Accounts

| Service | Username | Password | Notes |
|---------|----------|----------|-------|
| **Coder** | `admin@example.com` | `CoderAdmin123!` | First user, full admin |
| **Gitea** | `gitea` | `admin123` | Site administrator |
| **Authentik** | `akadmin` | `admin` | Identity provider admin |
| **MinIO** | `minioadmin` | `minioadmin` | Storage admin |

### Test User Accounts

| User | Role | Coder Email | Coder Password | Gitea User | Gitea Password |
|------|------|-------------|----------------|------------|----------------|
| `appmanager` | App Manager | `appmanager@example.com` | `Password123!` | `appmanager` | `password123` |
| `contractor1` | Contractor | `contractor1@example.com` | `Password123!` | `contractor1` | `password123` |
| `contractor2` | Contractor | `contractor2@example.com` | `Password123!` | `contractor2` | `password123` |
| `contractor3` | Contractor | `contractor3@example.com` | `Password123!` | `contractor3` | `password123` |
| `readonly` | Read-only | `readonly@example.com` | `Password123!` | `readonly` | `password123` |

### Authentik SSO Users

All users above are also created in Authentik with password `password123` for SSO login.

## User Permission Matrix

### Gitea Permissions

| User | Admin | Restricted | Can Create Org | Can Create Repo |
|------|-------|------------|----------------|-----------------|
| `gitea` | Yes | No | Yes | Yes |
| `appmanager` | No | No | Yes | Yes |
| `contractor1-3` | No | Yes | No | No |
| `readonly` | No | Yes | No | No |

**Restricted users** can only see repositories they are explicitly granted access to.

### Coder Permissions

| User | Role | Can Create Workspaces | Can Create Templates |
|------|------|----------------------|---------------------|
| `admin@example.com` | Owner | Yes | Yes |
| `appmanager@example.com` | Member | Yes | No |
| `contractor*@example.com` | Member | Yes | No |

## Login Types

### Password vs OIDC

| Service | Password Login | OIDC/SSO Login |
|---------|---------------|----------------|
| Coder | Yes (fallback) | Yes (primary) |
| Gitea | Yes (fallback) | Yes (via Authentik) |
| MinIO | Yes (fallback) | Yes (via Authentik) |
| Platform Admin | Yes (fallback) | Yes (via Authentik) |

**Important:** Users created via API with `password` login type cannot use OIDC until their login type is changed. Users signing up via OIDC automatically get `oidc` login type.

## Creating New Users Checklist

When adding a new user to the POC, ensure they exist in all required systems:

### For Contractors (Restricted)

```bash
# 1. Create in Authentik (for SSO)
docker exec authentik-server ak shell -c "
from authentik.core.models import User
user = User.objects.create(username='newuser', email='newuser@example.com', name='New User')
user.set_password('password123')
user.save()
print(f'Created: {user.username}')
"

# 2. Create in Gitea (restricted)
curl -X POST "http://localhost:3000/api/v1/admin/users" \
  -u "gitea:admin123" \
  -H "Content-Type: application/json" \
  -d '{"username":"newuser","email":"newuser@example.com","password":"password123","must_change_password":false}'

# Set restricted permissions
docker exec gitea sqlite3 /data/gitea/gitea.db \
  "UPDATE user SET is_restricted=1, allow_create_organization=0 WHERE name='newuser';"

# 3. Coder - User will be auto-created on first OIDC login
```

### For App Managers (Elevated)

```bash
# Same as above, but set Gitea permissions differently:
docker exec gitea sqlite3 /data/gitea/gitea.db \
  "UPDATE user SET is_restricted=0, allow_create_organization=1 WHERE name='newuser';"
```

## Service Dependencies

```
┌─────────────────────────────────────────────────────────────────┐
│                        Authentik (SSO)                          │
│                         Port: 9000                              │
└───────────────────────────┬─────────────────────────────────────┘
                            │ OIDC
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│    Coder      │   │    Gitea      │   │    MinIO      │
│  Port: 7080   │   │  Port: 3000   │   │ Port: 9001    │
└───────┬───────┘   └───────────────┘   └───────────────┘
        │
        ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│  Workspaces   │──▶│  AI Gateway   │   │    DevDB      │
│  (Docker)     │   │  Port: 8090   │   │  Port: 5432   │
└───────────────┘   └───────────────┘   └───────────────┘
```

## Troubleshooting Credentials

### User can't login via SSO

1. Verify user exists in Authentik:
   ```bash
   docker exec authentik-server ak shell -c "
   from authentik.core.models import User
   print([u.username for u in User.objects.all()])
   "
   ```

2. Check login type in target service (e.g., Coder):
   ```bash
   docker exec postgres psql -U coder -d coder -c \
     "SELECT username, login_type FROM users WHERE email='user@example.com';"
   ```

3. If login_type is 'password', update to 'oidc':
   ```bash
   docker exec postgres psql -U coder -d coder -c \
     "UPDATE users SET login_type='oidc' WHERE email='user@example.com';"
   ```

### User can't access Gitea repos

1. Check if user is restricted:
   ```bash
   docker exec gitea sqlite3 /data/gitea/gitea.db \
     "SELECT name, is_restricted FROM user WHERE name='username';"
   ```

2. Add user to repository/organization explicitly via Gitea admin UI.

### SSO redirect errors

1. Verify redirect URIs in Authentik match the service configuration
2. Check Authentik provider settings:
   ```bash
   docker exec authentik-server ak shell -c "
   from authentik.providers.oauth2.models import OAuth2Provider
   for p in OAuth2Provider.objects.all():
       print(f'{p.name}: {p.redirect_uris}')
   "
   ```

## Host Machine Setup (REQUIRED for OIDC)

### /etc/hosts Entry

**CRITICAL:** Add `host.docker.internal` to your hosts file:

```bash
echo "127.0.0.1 host.docker.internal" | sudo tee -a /etc/hosts
```

**Why this is required:**
1. Workspace containers use `host.docker.internal` to reach Coder server
2. OIDC callback redirects browser to `host.docker.internal:7080`
3. Without this hosts entry, browser cannot resolve the hostname after OIDC login

### Browser Access URLs

**For OIDC login to work, you MUST access Coder at `host.docker.internal`:**

| Service | Browser URL | Notes |
|---------|-------------|-------|
| **Coder** | `http://host.docker.internal:7080` | **Required for OIDC!** |
| Authentik | `http://localhost:9000` | SSO admin |
| Gitea | `http://localhost:3000` | Git server |

**Why not localhost for Coder?**
- OAuth state cookie is set on the domain you visit
- OIDC callback returns to `host.docker.internal:7080` (from `CODER_ACCESS_URL`)
- Cookie domain must match, otherwise: `Cookie "oauth_state" must be provided` error

## Docker Networking for PoC

### Understanding URL Contexts

URLs work differently depending on where they're accessed from:

| Context | `localhost` Means | How to Reach Host | How to Reach Other Containers |
|---------|-------------------|-------------------|-------------------------------|
| **Host machine** | Host itself | `localhost` | `localhost:<mapped-port>` |
| **Inside container** | The container itself | `host.docker.internal` | `<container-name>:<internal-port>` |
| **Browser** | User's machine | `localhost` OR `host.docker.internal` (with hosts entry) | `localhost:<mapped-port>` |

### Browser and Container URL Configuration

With `/etc/hosts` configured, `host.docker.internal` works from BOTH browser and containers:

| URL | Works From | Use For |
|-----|------------|---------|
| `http://host.docker.internal:7080` | Browser AND containers | **Primary Coder access** |
| `http://localhost:7080` | Browser only | Backup (breaks OIDC) |
| `http://coder-server:7080` | Inside containers on same network | Container-to-container |

**Correct Configuration:**
- **`CODER_ACCESS_URL`:** `http://host.docker.internal:7080`
- **Browser access:** `http://host.docker.internal:7080` (same URL!)
- **Ensure hosts file is configured** (see above)

### The `localhost` Problem

**Problem:** Services configured with `localhost` URLs don't work from inside containers.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Host Machine                                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ Browser: localhost:7080 → Works! (reaches host port 7080)              ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ Docker Network (coder-network)                                          ││
│  │  ┌─────────────────┐     ┌─────────────────┐                           ││
│  │  │  coder-server   │     │   workspace     │                           ││
│  │  │  (port 7080)    │     │   container     │                           ││
│  │  │                 │     │                 │                           ││
│  │  │ localhost:7080  │     │ localhost:7080  │ ← FAILS! (no service)     ││
│  │  │ = this container│     │ = this container│                           ││
│  │  └─────────────────┘     └─────────────────┘                           ││
│  └─────────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
```

### Solution: `host.docker.internal`

Docker Desktop (Mac/Windows) provides `host.docker.internal` DNS that resolves to the host machine:

```yaml
# docker-compose.yml
environment:
  # BAD: Containers can't reach this
  CODER_ACCESS_URL: "http://localhost:7080"

  # GOOD: Containers can reach the host
  CODER_ACCESS_URL: "http://host.docker.internal:7080"
```

### Container-to-Container Communication

Containers on the same Docker network can reach each other by container name:

```yaml
# From workspace container:
# ✓ http://coder-server:7080    (container name)
# ✓ http://gitea:3000           (container name)
# ✓ http://ai-gateway:8090      (container name)
# ✗ http://localhost:7080       (won't work)
```

### Coder-Specific Networking

#### Access URL Configuration

| Setting | Used By | Recommended Value |
|---------|---------|-------------------|
| `CODER_ACCESS_URL` | Agent downloads, API calls | `http://host.docker.internal:7080` |
| `CODER_WILDCARD_ACCESS_URL` | Subdomain app routing | `http://*.host.docker.internal:7080` (if using subdomains) |

#### Agent Connection Flow

```
1. Workspace container starts
2. Agent init script runs
3. Agent downloads binary from CODER_ACCESS_URL/bin/coder-linux-<arch>
4. Agent connects to Coder server via CODER_ACCESS_URL
5. If CODER_ACCESS_URL=localhost → Connection refused (localhost = workspace container)
```

#### Fixing Agent Connection Issues

**Symptom:** "Agent has not connected" / "Failed to download coder agent"

**Check logs:**
```bash
docker logs <workspace-container> 2>&1 | tail -20
# Look for: "curl: (7) Failed to connect to localhost port 7080"
```

**Fix:**
```bash
# Update docker-compose.yml
CODER_ACCESS_URL: "http://host.docker.internal:7080"

# Restart Coder
docker compose up -d coder

# Delete and recreate workspace
```

### Path-Based vs Subdomain Apps

| Setting | Requires |
|---------|----------|
| `subdomain = false` | `CODER_DISABLE_PATH_APPS: "false"` |
| `subdomain = true` | Wildcard DNS + `CODER_WILDCARD_ACCESS_URL` |

**For PoC (no wildcard DNS):**
```yaml
# docker-compose.yml
CODER_DISABLE_PATH_APPS: "false"

# template main.tf
subdomain = false
```

### Linux Docker Host (No Docker Desktop)

On Linux without Docker Desktop, `host.docker.internal` doesn't exist by default. Options:

**Option 1: Add host entry**
```yaml
# docker-compose.yml
services:
  coder:
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

**Option 2: Use host IP**
```bash
# Get host IP
HOST_IP=$(hostname -I | awk '{print $1}')
# Use in CODER_ACCESS_URL
CODER_ACCESS_URL: "http://${HOST_IP}:7080"
```

**Option 3: Use container network (if on same network)**
```yaml
CODER_ACCESS_URL: "http://coder-server:7080"
```

### Network Troubleshooting Commands

```bash
# Check container can reach Coder server
docker exec <workspace-container> curl -s http://host.docker.internal:7080/api/v2/buildinfo

# Check DNS resolution inside container
docker exec <workspace-container> nslookup host.docker.internal

# Check container network
docker inspect <container> | jq '.[0].NetworkSettings.Networks'

# List containers on coder-network
docker network inspect coder-network | jq '.[0].Containers'

# Test connectivity between containers
docker exec workspace-container ping -c 2 coder-server
```

### Common Networking Issues

| Issue | Symptom | Fix |
|-------|---------|-----|
| Agent can't connect | "localhost connection refused" | Use `host.docker.internal` |
| Apps don't load | "Path apps disabled" | Set `CODER_DISABLE_PATH_APPS=false` |
| Subdomain warning | "Wildcard URL required" | Use `subdomain=false` or configure wildcard DNS |
| Container can't reach Gitea | "Connection refused" | Use `gitea:3000` not `localhost:3000` |
| Linux host networking | `host.docker.internal` not found | Add `extra_hosts` or use host IP |
| Agent START_ERROR | "docker ps: exit status 1" | Disable devcontainers in template (see below) |
| Env changes not applied | Container uses old values | Use `docker compose up -d` not `restart` |

### Devcontainer Detection Issue (Coder 2.x+)

Coder 2.x enables devcontainer detection by default. This runs `docker ps` inside workspaces, which fails if Docker-in-Docker isn't configured.

**Symptom in workspace logs:**
```
lifecycle:{state:START_ERROR}
run docker ps: exit status 1
```

**Fix:** Add to `coder_agent` in template `main.tf`:
```hcl
resource "coder_agent" "main" {
  # Disable devcontainer detection
  env = {
    CODER_AGENT_DEVCONTAINERS_ENABLE = "false"
  }
  # ...
}
```

Then push template and recreate workspaces.

### Docker Compose: restart vs up -d

**Critical:** Environment variable changes require `up -d`, not `restart`:

| Command | Behavior | Use When |
|---------|----------|----------|
| `docker compose restart <svc>` | Reuses existing container, same env | Quick restart, no config changes |
| `docker compose up -d <svc>` | Recreates container if config changed | After `.env` or compose.yml changes |

```bash
# WRONG: won't pick up .env changes
docker compose restart coder

# CORRECT: recreates with new env vars
docker compose up -d coder
```

### Template and Workspace Lifecycle

Template changes require TWO steps:

1. **Push the template** - Updates template version in Coder
2. **Recreate workspaces** - Existing workspaces use old template version

```bash
# Push updated template
docker exec -e CODER_SESSION_TOKEN="$TOKEN" -e CODER_URL="http://localhost:7080" \
  coder-server coder templates push contractor-workspace \
  --directory /tmp/contractor-workspace --yes

# Then: Delete workspace from UI and create new one
```

**Why?** Agent configuration (including URLs and env vars) is baked into the workspace at creation time. Changing the template only affects NEW workspaces.

### Startup Script Best Practices

**Always redirect background process output:**
```bash
# WRONG: Causes "output pipes not closed" warning
code-server --auth none 0.0.0.0:8080 &

# CORRECT: Redirects output, closes pipes cleanly
code-server --auth none 0.0.0.0:8080 > /tmp/code-server.log 2>&1 &
```

**Check startup logs:**
- Dashboard: Click "Show startup log" on workspace page
- Container: `docker logs <workspace-container>`
- Inside workspace: `/tmp/coder-startup-script.log`
- Agent logs: `/tmp/coder-agent.log`

**Reference:** https://coder.com/docs/admin/templates/troubleshooting

## Quick Health Check Script

```bash
#!/bin/bash
echo "=== POC Services Health Check ==="

check() {
  if curl -sf "$2" > /dev/null 2>&1; then
    echo "✓ $1"
  else
    echo "✗ $1 - FAILED"
  fi
}

check "Coder" "http://localhost:7080/api/v2/buildinfo"
check "Gitea" "http://localhost:3000/"
check "Authentik" "http://localhost:9000/-/health/ready/"
check "MinIO Console" "http://localhost:9001/"
check "AI Gateway" "http://localhost:8090/health"
check "Mailpit" "http://localhost:8025/"

echo "=== Done ==="
```
