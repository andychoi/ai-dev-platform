# Coder WebIDE PoC – Runbook & Troubleshooting

## Architecture Overview

### Logical Architecture

```
Browser (HTTPS)
  → Coder (7443, TLS)
  → Gitea (3000)
  → MinIO (9001/9002)
  → Authentik (OIDC, 9000)
  → LiteLLM (4000)
  → Key Provisioner (8100)
  → PostgreSQL / Redis (internal)
```

### Workspace Container

Each workspace includes access to:
- code-server (8080, in-container)
- Gitea (git HTTP/SSH)
- LiteLLM (AI proxy)
- Key Provisioner (auto-provisioned keys)
- DevDB (PostgreSQL/MySQL)
- MinIO (S3 storage)

---

## Environment Setup

### Host Networking (OIDC Requirement)

Ensure `host.docker.internal` resolves:

```bash
grep -q "host.docker.internal" /etc/hosts || \
  echo "127.0.0.1 host.docker.internal" | sudo tee -a /etc/hosts
```

### Access URL

**Always access Coder via HTTPS:**

```
https://host.docker.internal:7443
```

Never use `localhost` (OAuth cookie domain mismatch). Never use HTTP port 7080 (extension webviews require HTTPS secure context).

Self-signed cert warning: accept in browser, or install permanently:

```bash
# macOS
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain coder-poc/certs/coder.crt
```

---

## Service Lifecycle

### Startup order

1. `postgres`, `authentik-redis`
2. `authentik-server` / `authentik-worker`
3. `coder`, `gitea`, `minio`, `litellm`
4. `key-provisioner`, `langfuse`, `mailpit`

### Key Commands

```bash
# Start all services
cd coder-poc
docker compose up -d

# Start with SSO
docker compose -f docker-compose.yml -f docker-compose.sso.yml up -d

# IMPORTANT: After changing .env or docker-compose.yml, use 'up -d' (NOT 'restart')
# 'docker compose restart' reuses existing container and does NOT reload env vars
docker compose up -d <service>
```

### Health Checks

```bash
curl -sf -k https://host.docker.internal:7443/api/v2/buildinfo  # Coder
curl -sf http://localhost:3000/                                    # Gitea
curl -sf http://localhost:9000/-/health/ready/                     # Authentik
curl -sf http://localhost:4000/health                              # LiteLLM
curl -sf http://localhost:8100/health                              # Key Provisioner
```

---

## User & Identity Management

### Role Model

| Role | Authentik Group | Coder Role | Description |
|------|----------------|------------|-------------|
| Platform Admin | `coder-admins` | Owner | Full admin access |
| App Manager | `coder-template-admins` | Template Admin | Template and workspace management |
| Contractor | *(default)* | Member | Own workspaces only |
| Compliance | `coder-auditors` | Auditor | Read-only audit logs |

All users must exist consistently in Authentik, Gitea, and Coder.
Coder users auto-create via OIDC on first SSO login.

See [RBAC-ACCESS-CONTROL.md](../../shared/docs/RBAC-ACCESS-CONTROL.md) for full details.

### Authentik – Create User

```bash
docker exec authentik-server ak shell -c "
from authentik.core.models import User
u = User.objects.create(username='USER', email='EMAIL', name='NAME')
u.set_password('password123'); u.save()
"
```

### Gitea – Create User

```bash
curl -X POST http://localhost:3000/api/v1/admin/users \
  -u gitea_admin:password123 \
  -H "Content-Type: application/json" \
  -d '{"username":"USER","email":"EMAIL","password":"password123","must_change_password":false}'
```

---

## SSO Setup

### Automated Setup (Recommended)

```bash
cd coder-poc
./scripts/setup-authentik-sso-full.sh
```

This creates OAuth2 providers in Authentik (Coder, Gitea, MinIO, Platform Admin), applications, and generates `.env.sso` + `docker-compose.sso.yml`.

### RBAC Group Setup

```bash
./scripts/setup-authentik-rbac.sh
```

Creates Authentik groups (`coder-admins`, `coder-template-admins`, `coder-auditors`, `coder-members`) and OIDC property mapping for the `groups` claim.

### Disable Default GitHub Login

Included in SSO overlay:
```yaml
CODER_OAUTH2_GITHUB_DEFAULT_PROVIDER_ENABLE: "false"
```

---

## Template Management

```bash
# Build workspace image
cd coder-poc/templates/contractor-workspace/build
docker build -t contractor-workspace:latest .

# Push template to Coder
cd coder-poc
docker cp templates/contractor-workspace coder-server:/tmp/contractor-workspace
docker exec \
  -e CODER_SESSION_TOKEN="$TOKEN" \
  -e CODER_URL="http://localhost:7080" \
  coder-server coder templates push contractor-workspace \
  --directory /tmp/contractor-workspace --yes
```

**Impact on existing workspaces:**
- Startup script changes: **restart** workspace
- Dockerfile changes: user clicks **"Update"** in Coder UI
- Agent env vars / volume mounts: requires workspace **deletion and recreation**

---

## Troubleshooting

### Login & SSO Issues

#### OIDC Login Fails for Existing User

**Cause:** `login_type=password` in Coder database.

```bash
# Diagnose
docker exec postgres psql -U coder -d coder -c \
  "SELECT email, login_type FROM users;"

# Fix
docker exec postgres psql -U coder -d coder -c \
  "UPDATE users SET login_type='oidc' WHERE email='user@example.com';"
```

#### Redirect URI Error

**Cause:** Mismatch between `CODER_ACCESS_URL` and Authentik redirect URIs.

Authentik must have BOTH redirect URIs configured:
```
https://host.docker.internal:7443/api/v2/users/oidc/callback
http://host.docker.internal:7080/api/v2/users/oidc/callback
```

#### "Cookie oauth_state must be provided"

**Cause:** Accessing Coder via `localhost` but OIDC callback returns to `host.docker.internal`. Cookie domain mismatch.

**Fix:** Always access via `https://host.docker.internal:7443`.

---

### Workspace & Agent Issues

#### Agent Never Connects

**Cause:** `CODER_ACCESS_URL` uses `localhost` instead of `host.docker.internal`.

```bash
# Fix in .env
CODER_ACCESS_URL=https://host.docker.internal:7443

# Recreate container (restart won't reload env vars)
docker compose up -d coder
```

#### Terminal Stuck "Trying to connect..."

**Cause:** User shell is `/bin/false`.

**Fix in Dockerfile:**
```dockerfile
RUN useradd -m -s /bin/bash -u 1001 coder && usermod -s /bin/bash coder
```

#### Agent START_ERROR (docker ps)

**Cause:** Devcontainer detection enabled.

**Fix in template:**
```terraform
resource "coder_agent" "main" {
  env = {
    CODER_AGENT_DEVCONTAINERS_ENABLE = "false"
  }
}
```

#### Extension Panels Blank (Roo Code, etc.)

**Cause:** Browser not in secure context (`crypto.subtle` unavailable over HTTP).

**Diagnose:** Browser console: `window.isSecureContext` returns `false`.

**Fix:** Access via `https://host.docker.internal:7443` (not HTTP port 7080).

---

### AI & Enforcement Issues

#### AI Not Working (No Response)

1. Check Roo Code panel opens (sidebar icon)
2. Check config: `cat ~/.config/roo-code/settings.json` — verify `apiKey` present
3. Check budget: run `ai-usage` — may have hit spend limit
4. Check LiteLLM health: `curl http://litellm:4000/health`
5. Restart workspace to re-provision key

#### AI Not Following Design-First Workflow

**Cause:** `enforcement_level` in key metadata may be wrong or missing.

```bash
# Check key's enforcement level
curl -s -X GET http://localhost:4000/key/info \
  -H "Authorization: Bearer <user-key>" | python3 -c "
import sys, json; d = json.load(sys.stdin)
print('enforcement_level:', d.get('info',{}).get('metadata',{}).get('enforcement_level','NONE'))
"

# Verify enforcement hook is loaded
docker logs litellm 2>&1 | grep enforcement

# Run enforcement test suite
bash scripts/test-enforcement.sh
```

**Fix:** Rotate the key (delete + recreate) or recreate workspace with correct `ai_enforcement_level` parameter. Changing the template parameter alone does NOT update existing keys.

See [AI.md Section 12](../../shared/docs/AI.md#12-design-first-ai-enforcement-layer) for details.

---

### Config Issues

#### .env Changes Ignored

**Cause:** `docker compose restart` reuses existing container.

**Fix:** Always use `docker compose up -d <service>` after changing `.env`.

#### Template Changes Not Applied

1. Push template: `coder templates push ...`
2. Users click "Update" on their workspace
3. Some changes (agent env vars, volume mounts) require workspace deletion and recreation

---

## Related Documents

- [ADMIN-HOWTO.md](ADMIN-HOWTO.md) — Detailed admin procedures
- [AUTHENTIK-SSO.md](AUTHENTIK-SSO.md) — SSO configuration
- [INFRA.md](INFRA.md) — Infrastructure architecture
- [RBAC-ACCESS-CONTROL.md](../../shared/docs/RBAC-ACCESS-CONTROL.md) — Roles and permissions
- [WEB-TERMINAL-SECURITY.md](../../shared/docs/WEB-TERMINAL-SECURITY.md) — Terminal hardening

---

*Last updated: February 7, 2026*
