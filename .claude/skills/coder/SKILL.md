---
name: coder
description: Coder WebIDE platform - workspace management, templates, user authentication, OIDC configuration
---

# Coder WebIDE Skill

## Overview

Coder is the WebIDE platform that provides browser-based development environments (workspaces) for contractors.

## Access

| Endpoint | URL | Notes |
|----------|-----|-------|
| Web UI | https://host.docker.internal:7443 | **HTTPS required for webviews** |
| API | https://host.docker.internal:7443/api/v2 | Use this for API calls |
| Health Check | http://localhost:7080/api/v2/buildinfo | Health check (HTTP OK) |
| HTTP (redirects) | http://host.docker.internal:7080 | Redirects to HTTPS |

> **CRITICAL**: Always access Coder via `https://host.docker.internal:7443`. HTTPS is required for browser secure context (`crypto.subtle` / extension webviews). Self-signed cert — accept the browser warning or install the cert in your OS trust store.

### Trust the Self-Signed Certificate (Optional, Eliminates Browser Warning)

```bash
# macOS — add to system keychain
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  "$(pwd)/coder-poc/certs/coder.crt"

# Linux — add to CA store
sudo cp coder-poc/certs/coder.crt /usr/local/share/ca-certificates/coder.crt
sudo update-ca-certificates
```

## Credentials

### Admin Account

| Field | Value |
|-------|-------|
| Email | `admin@example.com` |
| Password | `CoderAdmin123!` |
| Role | Owner (first user) |

### Test Users

| Email | Password | Login Type |
|-------|----------|------------|
| `appmanager@example.com` | `Password123!` | OIDC |
| `contractor1@example.com` | `Password123!` | Password |
| `contractor2@example.com` | `Password123!` | Password |
| `contractor3@example.com` | `Password123!` | Password |

## Critical Dependencies

### Required Services

```
┌─────────────────────────────────────────────────────────────────┐
│                           Coder                                  │
│                        Port: 7080                                │
└───────────────────────────┬─────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│   PostgreSQL  │   │   Authentik   │   │    Docker     │
│   (Required)  │   │   (For OIDC)  │   │   (Required)  │
│   Port: 5432  │   │   Port: 9000  │   │   Socket      │
└───────────────┘   └───────────────┘   └───────────────┘
```

| Dependency | Required | Purpose |
|------------|----------|---------|
| **PostgreSQL** | Yes | Stores users, workspaces, templates |
| **Docker** | Yes | Runs workspace containers |
| **Authentik** | No (but recommended) | OIDC authentication |

### Database Configuration

```yaml
# PostgreSQL connection
CODER_PG_CONNECTION_URL: postgresql://coder:coder@postgres:5432/coder?sslmode=disable
```

**Critical:** Coder will not start without PostgreSQL connection.

## Login Types

### Password vs OIDC

Users have a specific `login_type` that determines how they can authenticate:

| Login Type | Can Use Password | Can Use OIDC |
|------------|-----------------|--------------|
| `password` | Yes | No |
| `oidc` | No | Yes |

**Common Issue:** User created via API with `password` type cannot login via OIDC.

### Check Login Type

```bash
docker exec postgres psql -U coder -d coder -c \
  "SELECT email, username, login_type FROM users;"
```

### Change Login Type

```bash
# Change to OIDC
docker exec postgres psql -U coder -d coder -c \
  "UPDATE users SET login_type='oidc' WHERE email='user@example.com';"

# Change to password
docker exec postgres psql -U coder -d coder -c \
  "UPDATE users SET login_type='password' WHERE email='user@example.com';"
```

## OIDC Configuration

### Environment Variables

```yaml
CODER_OIDC_ISSUER_URL: http://authentik-server:9000/application/o/coder/
CODER_OIDC_CLIENT_ID: coder
CODER_OIDC_CLIENT_SECRET: <secret>
CODER_OIDC_ALLOW_SIGNUPS: "true"
CODER_DISABLE_PASSWORD_AUTH: "false"  # Keep password as fallback
# Disable default GitHub OAuth2 login (shows by default in Coder 2.x)
CODER_OAUTH2_GITHUB_DEFAULT_PROVIDER_ENABLE: "false"
```

### Disabling GitHub Login

Coder 2.x shows a default GitHub OAuth2 login button that uses device flow without configuration. To disable it:

```yaml
CODER_OAUTH2_GITHUB_DEFAULT_PROVIDER_ENABLE: "false"
```

**Note:** `CODER_OAUTH2_GITHUB_DEFAULT_PROVIDER` (without `_ENABLE`) does NOT work.

### Callback URL / Redirect URI

Authentik must have the redirect URI configured to match what Coder sends.

**Critical:** Coder generates callback URL from `CODER_ACCESS_URL`. If using `host.docker.internal`, Authentik needs BOTH:

```
http://localhost:7080/api/v2/users/oidc/callback
http://host.docker.internal:7080/api/v2/users/oidc/callback
```

**Fix redirect_uri mismatch in Authentik:**
```bash
docker exec authentik-server ak shell -c "
from authentik.providers.oauth2.models import OAuth2Provider
p = OAuth2Provider.objects.get(client_id='coder')
p.redirect_uris = '''http://localhost:7080/api/v2/users/oidc/callback
http://host.docker.internal:7080/api/v2/users/oidc/callback'''
p.save()
"
```

## User Management

### Create User (API)

```bash
# Get session token
CODER_SESSION=$(curl -s -X POST "http://localhost:7080/api/v2/users/login" \
  -H "Content-Type: application/json" \
  -d @- << 'EOF' | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_token',''))"
{"email":"admin@example.com","password":"CoderAdmin123!"}
EOF
)

# Get organization ID
ORG_ID=$(curl -s "http://localhost:7080/api/v2/organizations" \
  -H "Coder-Session-Token: $CODER_SESSION" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")

# Create user
curl -X POST "http://localhost:7080/api/v2/users" \
  -H "Coder-Session-Token: $CODER_SESSION" \
  -H "Content-Type: application/json" \
  -d @- << EOF
{
  "email": "newuser@example.com",
  "username": "newuser",
  "name": "New User",
  "password": "Password123!",
  "login_type": "password",
  "organization_ids": ["$ORG_ID"]
}
EOF
```

### List Users

```bash
curl -s "http://localhost:7080/api/v2/users" \
  -H "Coder-Session-Token: $CODER_SESSION" \
  | python3 -m json.tool
```

## Workspace Management

### List Workspaces

```bash
curl -s "http://localhost:7080/api/v2/workspaces" \
  -H "Coder-Session-Token: $CODER_SESSION" \
  | python3 -c "
import sys,json
for ws in json.load(sys.stdin).get('workspaces',[]):
    print(f\"{ws['name']}: {ws['latest_build']['status']} (owner: {ws['owner_name']})\")
"
```

### Delete Workspace

```bash
# Get workspace ID first
WS_ID="workspace-uuid-here"
curl -X DELETE "http://localhost:7080/api/v2/workspaces/$WS_ID" \
  -H "Coder-Session-Token: $CODER_SESSION"
```

## Template Management

### Push Template

```bash
# From inside coder-server container
docker exec -e CODER_SESSION_TOKEN="$CODER_SESSION" \
  -e CODER_URL="http://localhost:7080" \
  coder-server coder templates push template-name \
  --directory /path/to/template --yes
```

### List Templates

```bash
curl -s "http://localhost:7080/api/v2/templates" \
  -H "Coder-Session-Token: $CODER_SESSION"
```

## Workspace Security Settings

### Disabled Features (Security)

In the workspace template (`main.tf`):

```hcl
display_apps {
  vscode          = false  # No local VS Code connection
  vscode_insiders = false
  ssh_helper      = false  # No SSH/SCP file transfer
  port_forwarding_helper = false  # No port forwarding
  web_terminal    = true   # Browser terminal only
}
```

### Network Isolation

Workspaces connect to `coder-network` and can only access:
- Gitea (git operations)
- AI Gateway (AI assistance)
- DevDB (database)

## App Routing: Subdomain vs Path-Based

Coder apps (VS Code, terminals) can be accessed via two routing methods:

### Path-Based Routing (Default for PoC)

```hcl
resource "coder_app" "code-server" {
  subdomain = false  # Path-based routing
  # ...
}
```

- **URL Format:** `https://coder.example.com/@user/workspace/apps/code-server`
- **Requirements:** None - works with any setup
- **Use Case:** Local development, PoC, simple deployments

### Subdomain Routing (Production)

```hcl
resource "coder_app" "code-server" {
  subdomain = true  # Subdomain routing
  # ...
}
```

- **URL Format:** `https://code-server--workspace--user.coder.example.com`
- **Requirements:**
  - Wildcard DNS record: `*.coder.example.com → <coder-ip>`
  - Wildcard TLS certificate for `*.coder.example.com`
  - `CODER_WILDCARD_ACCESS_URL` environment variable
- **Use Case:** Production deployments with proper DNS

### Production Setup for Subdomain Routing

1. **DNS Configuration:**
   ```
   coder.example.com      A     <coder-server-ip>
   *.coder.example.com    A     <coder-server-ip>
   ```

2. **TLS Certificate:**
   - Use Let's Encrypt with DNS-01 challenge for wildcard cert
   - Or obtain wildcard cert from your CA

3. **Coder Environment Variables:**
   ```yaml
   CODER_ACCESS_URL: https://coder.example.com
   CODER_WILDCARD_ACCESS_URL: https://*.coder.example.com
   ```

4. **Update Template:**
   ```hcl
   resource "coder_app" "code-server" {
     subdomain = true  # Enable subdomain routing
     # ...
   }
   ```

### Benefits of Subdomain Routing

| Feature | Path-Based | Subdomain |
|---------|------------|-----------|
| URL Cleanliness | Long paths | Clean URLs |
| Cookie Isolation | Shared cookies | Isolated per app |
| Security | Lower isolation | Better isolation |
| Setup Complexity | Simple | Requires wildcard DNS/TLS |

### Warning Message

If you see: *"Some workspace applications will not work - subdomain = true requires Wildcard Access URL"*

**Fix:** Either configure wildcard DNS/TLS, or set `subdomain = false` in the template.

## Workspace Image Optimization

### Pre-built Images (Recommended for Production)

Instead of building images on every workspace creation:

1. **Build once:**
   ```bash
   docker build -t contractor-workspace:latest ./templates/contractor-workspace/build
   ```

2. **Reference directly in template:**
   ```hcl
   locals {
     workspace_image = "contractor-workspace:latest"
   }

   resource "docker_container" "workspace" {
     image = local.workspace_image
     # ...
   }
   ```

3. **For production with registry:**
   ```hcl
   locals {
     workspace_image = "registry.example.com/contractor-workspace:v1.0.0"
   }
   ```

### Avoid These (Slow):

```hcl
# DON'T: Build on every workspace (slow)
resource "docker_image" "workspace" {
  build {
    context = "${path.module}/build"
  }
}

# DON'T: Use timestamp triggers (forces rebuild)
triggers = {
  version = timestamp()
}
```

## Troubleshooting

### Agent Won't Connect

**Symptom:** "Workspace is running but the agent has not connected"

#### Cause 1: Wrong CODER_ACCESS_URL

`CODER_ACCESS_URL` is set to `localhost` which containers can't reach.

**Quick Fix:**
```bash
# Check current setting
docker exec coder-server env | grep CODER_ACCESS_URL

# Should be: http://host.docker.internal:7080
# NOT: http://localhost:7080
```

**Full Fix:**

1. Update `.env` file:
```bash
CODER_ACCESS_URL=http://host.docker.internal:7080
```

2. **IMPORTANT:** Use `docker compose up -d` NOT `docker compose restart`:
```bash
# WRONG: restart doesn't reload .env changes
docker compose restart coder

# CORRECT: up -d recreates container with new env vars
docker compose up -d coder
```

3. Delete and recreate the workspace (agent URL is baked in at provision time)

See `skills/poc-services/SKILL.md` → "Docker Networking for PoC" for detailed explanation.

#### Cause 2: Devcontainer Detection Failing (Coder 2.x+)

**Symptom:** Agent logs show `lifecycle:{state:START_ERROR}` with `docker ps: exit status 1`

**Cause:** Coder 2.x enables devcontainer detection by default, which runs `docker ps` inside workspace. If Docker-in-Docker isn't configured, this fails and marks the agent as errored.

**Fix:** Disable devcontainer detection in the template (`main.tf`):

```hcl
resource "coder_agent" "main" {
  # ... other config ...

  # Disable devcontainer detection (requires Docker-in-Docker which we don't support)
  env = {
    CODER_AGENT_DEVCONTAINERS_ENABLE = "false"
  }

  # ... rest of config ...
}
```

**After updating template:**
```bash
# 1. Push updated template
docker cp templates/contractor-workspace/. coder-server:/tmp/contractor-workspace/
docker exec -e CODER_SESSION_TOKEN="$TOKEN" -e CODER_URL="http://localhost:7080" \
  coder-server coder templates push contractor-workspace --directory /tmp/contractor-workspace --yes

# 2. Delete and recreate workspaces to use new template version
```

#### Cause 3: Stale Agent Token

**Symptom:** Agent logs show `401 Unauthorized: Workspace agent not authorized`

**Cause:** Workspace was created before Coder server was restarted/recreated. The agent token is orphaned.

**Fix:** Delete the workspace from Coder UI and recreate it.

### Environment Variable Changes Not Taking Effect

**Problem:** Changed `.env` or `docker-compose.yml` but container still uses old values.

**Cause:** `docker compose restart` reuses existing container with old env vars.

**Fix:**
```bash
# Use 'up -d' to recreate the container
docker compose up -d <service-name>

# Verify new value
docker exec <container-name> env | grep <VAR_NAME>
```

### Terminal Immediately Exits / "Trying to Connect"

**Symptom:** Terminal shows "Trying to connect..." forever, or connects then immediately disconnects.

**Root Cause:** User shell is set to `/bin/false` instead of `/bin/bash`.

**Diagnose:**
```bash
docker exec <workspace-container> getent passwd coder
# If you see: coder:x:1001:1001::/home/coder:/bin/false  ← WRONG!
```

**Fix in Dockerfile:** Always explicitly set the shell after user creation:
```dockerfile
RUN useradd -m -s /bin/bash -u 1001 coder \
    && usermod -s /bin/bash coder   # <-- Add this line to ensure shell is set
```

**Why it happens:** The base image may have a `coder` user with `/bin/false` shell. User creation logic that skips creating existing users won't change the shell.

### Duplicate Terminal Icons

**Symptom:** Two terminal icons appear in the workspace dashboard.

**Cause:** Both built-in web terminal AND a custom terminal app are configured:
```hcl
# This creates the built-in terminal
display_apps {
  web_terminal = true
}

# This creates a SECOND terminal (duplicate!)
resource "coder_app" "terminal" {
  command = "/bin/bash"
}
```

**Fix:** Remove the custom `coder_app "terminal"` resource. The built-in `web_terminal = true` is sufficient and handles everything properly.

### Extension Webviews Blank (Secure Context)

**Symptom:** ALL extension webviews (Roo Code, etc.) show blank/white panels. Browser console shows `crypto.subtle` is `undefined`.

**Root Cause:** Coder is accessed via `http://host.docker.internal:7080`. Since `host.docker.internal` is not `localhost`, the browser treats it as an insecure context. The `crypto.subtle` API (required by code-server for webview iframe nonce generation) is unavailable, breaking all webviews.

**Diagnose:**
```javascript
// In browser console (F12) on the code-server page:
console.log(crypto.subtle);        // undefined = insecure context
console.log(window.isSecureContext); // false = confirms the issue
```

**Fix (Default — HTTPS enabled):** Coder now runs with TLS on port 7443. Access via `https://host.docker.internal:7443`. Accept the self-signed certificate warning or install the cert in your OS trust store.

**Fix (If HTTPS is disabled for some reason):** Launch Chrome with the secure origin flag:
```bash
# macOS
open -a "Google Chrome" --args --unsafely-treat-insecure-origin-as-secure="http://host.docker.internal:7080"

# Linux
google-chrome --unsafely-treat-insecure-origin-as-secure="http://host.docker.internal:7080"
```

**Important:** This affects ALL extensions with webviews, not just Roo Code. It is a platform-level issue with code-server + non-localhost HTTP origins.

### Startup Script "Output Pipes Not Closed" Warning

**Symptom:**
```
WARNING: script exited successfully, but output pipes were not closed after 10s.
```

**Cause:** Background processes (like `code-server &`) keep stdout/stderr attached to the startup script.

**Fix:** Redirect output when starting background processes:
```bash
# WRONG: keeps pipes open
code-server --auth none --bind-addr 0.0.0.0:8080 /home/coder/workspace &

# CORRECT: redirects output, closes pipes
code-server --auth none --bind-addr 0.0.0.0:8080 /home/coder/workspace > /tmp/code-server.log 2>&1 &
```

**Reference:** https://coder.com/docs/admin/templates/troubleshooting#startup-script-issues

### Workspace Build Fails

1. Check build logs:
   ```bash
   # Via API
   curl -s "http://localhost:7080/api/v2/workspaces/$WS_ID/builds" \
     -H "Coder-Session-Token: $CODER_SESSION"
   ```

2. Check Docker:
   ```bash
   docker ps -a | grep coder
   docker logs <container-id>
   ```

3. Clear Docker cache:
   ```bash
   docker builder prune -af
   ```

### OIDC Login Fails

1. Verify Authentik is running:
   ```bash
   curl -s http://localhost:9000/-/health/ready/
   ```

2. Check OIDC configuration:
   ```bash
   docker exec coder-server env | grep OIDC
   ```

3. Verify redirect URI in Authentik matches Coder's callback

### User Can't Login

1. Check login type:
   ```bash
   docker exec postgres psql -U coder -d coder -c \
     "SELECT login_type FROM users WHERE email='user@example.com';"
   ```

2. Update if needed (see above)

### Database Connection Issues

```bash
# Check PostgreSQL
docker exec postgres pg_isready -U coder -d coder

# Check Coder logs
docker logs coder-server 2>&1 | grep -i "database\|postgres"
```

## Backup

### Database Backup

```bash
docker exec postgres pg_dump -U coder coder > coder-backup.sql
```

### Restore

```bash
cat coder-backup.sql | docker exec -i postgres psql -U coder coder
```
