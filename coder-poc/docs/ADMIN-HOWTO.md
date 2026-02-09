# Admin How-To Guide - Dev Platform PoC

A practical guide for platform administrators. Covers day-to-day operations: template management, HTTPS/TLS, AI model configuration, user management, and troubleshooting.

For end-user questions, see [FAQ.md](FAQ.md). For infrastructure architecture, see [INFRA.md](INFRA.md).

## Table of Contents

1. [Quick Reference](#1-quick-reference)
2. [Accessing the Platform](#2-accessing-the-platform)
3. [Template Management](#3-template-management)
4. [HTTPS / TLS Configuration](#4-https--tls-configuration)
5. [AI Model Configuration (LiteLLM)](#5-ai-model-configuration-litellm)
6. [User Management](#6-user-management)
7. [Service Operations](#7-service-operations)
8. [Common Admin Tasks](#8-common-admin-tasks)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Quick Reference

### URLs

| Service | URL | Purpose |
|---------|-----|---------|
| Coder Dashboard | `https://host.docker.internal:7443` | Main platform (HTTPS) |
| Coder API | `http://localhost:7080` | Script/API access (HTTP) |
| Authentik | `http://host.docker.internal:9000` | SSO admin |
| Gitea | `http://localhost:3000` | Git server |
| LiteLLM Admin | `http://localhost:4000/ui` | AI proxy admin |
| MinIO Console | `http://localhost:9001` | Object storage |

### Default Credentials

| System | Username | Password |
|--------|----------|----------|
| Coder Admin | admin@example.com | CoderAdmin123! |
| Authentik | akadmin | (set during first boot) |
| Gitea | gitea_admin | password123 |
| LiteLLM | (use master key) | sk-poc-litellm-master-key-change-in-production |

### Key Directories

```
coder-poc/
  templates/contractor-workspace/    # Workspace template
    main.tf                          # Terraform config (parameters, resources, startup)
    build/Dockerfile                 # Workspace Docker image
    build/settings.json              # VS Code settings baked into image
  litellm/config.yaml                # LiteLLM model routing config
  certs/                             # TLS certificates (coder.crt, coder.key)
  scripts/                           # Setup and admin scripts
  .env                               # Environment variables
  docker-compose.yml                 # Service definitions
```

---

## 2. Accessing the Platform

### Browser Access (HTTPS)

Access the Coder dashboard at:

```
https://host.docker.internal:7443
```

This uses HTTPS with a self-signed certificate. On first visit, accept the browser's certificate warning.

**To eliminate the warning permanently (macOS):**

```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  "$(pwd)/coder-poc/certs/coder.crt"
```

### Why Not `localhost`?

Coder is accessed via `host.docker.internal` (not `localhost`) because:
- OIDC/SSO callback URLs are generated from `CODER_ACCESS_URL`
- OAuth state cookies are bound to the domain you visit
- If you visit `localhost` but the callback returns to `host.docker.internal`, cookie domain mismatch causes `oauth_state` errors

**Prerequisite:** Ensure `host.docker.internal` resolves on your host:
```bash
# Check if it resolves
ping -c1 host.docker.internal

# If not, add to /etc/hosts
echo "127.0.0.1 host.docker.internal" | sudo tee -a /etc/hosts
```

### Script/API Access (HTTP)

Setup scripts and API calls use HTTP on localhost (no TLS overhead, no cert trust needed):

```bash
# API calls from host machine
curl http://localhost:7080/api/v2/buildinfo

# API calls from inside coder-server container
docker exec coder-server curl http://localhost:7080/api/v2/buildinfo
```

---

## 3. Template Management

### What Is a Workspace Template?

A workspace template is a **Terraform configuration** that defines everything about a workspace:
- Docker image (tools, languages, extensions)
- Resource limits (CPU, memory, disk)
- User-configurable parameters (AI model, Git repo, etc.)
- Startup scripts (AI config, Git clone, dotfiles)
- IDE apps (code-server, terminal)

Templates are `.tf` files — **not YAML**. There is no web-based template editor in Coder. You edit files locally and push via CLI.

### Template File Structure

```
templates/contractor-workspace/
  main.tf               # Everything: providers, parameters, resources, agent, apps
  build/
    Dockerfile          # Base image with tools, extensions, system config
    settings.json       # VS Code settings (AI, extensions, UI preferences)
```

### Viewing the Current Template

```bash
# List templates in Coder
docker exec -e CODER_URL=http://localhost:7080 -e CODER_SESSION_TOKEN=$TOKEN \
  coder-server coder templates list

# View template versions
docker exec -e CODER_URL=http://localhost:7080 -e CODER_SESSION_TOKEN=$TOKEN \
  coder-server coder templates versions contractor-workspace
```

### Editing a Template

1. **Edit main.tf** — Change parameters, resources, or startup scripts:
   ```bash
   # Edit locally with your preferred editor
   code coder-poc/templates/contractor-workspace/main.tf
   ```

2. **Edit Dockerfile** — Add tools, languages, or extensions:
   ```bash
   code coder-poc/templates/contractor-workspace/build/Dockerfile
   ```

3. **Edit settings.json** — Change VS Code defaults:
   ```bash
   code coder-poc/templates/contractor-workspace/build/settings.json
   ```

### Building the Workspace Image

After Dockerfile changes, rebuild:

```bash
docker build -t contractor-workspace:latest \
  coder-poc/templates/contractor-workspace/build
```

### Pushing a Template to Coder

Coder doesn't need the `coder` CLI on the host — push from inside the coder-server container:

```bash
# Step 1: Get a session token
TOKEN=$(curl -sf http://localhost:7080/api/v2/users/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@example.com","password":"CoderAdmin123!"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['session_token'])")

# Step 2: Copy template into container
docker cp coder-poc/templates/contractor-workspace coder-server:/tmp/template-push

# Step 3: Push (create or update)
docker exec -e CODER_URL=http://localhost:7080 -e CODER_SESSION_TOKEN=$TOKEN \
  coder-server sh -c "
    cd /tmp/template-push
    coder templates push contractor-workspace --directory . --yes 2>&1 || \
    coder templates create contractor-workspace --directory . --yes 2>&1
    rm -rf /tmp/template-push
  "
```

Or run the automated setup script:
```bash
./coder-poc/scripts/setup-workspace.sh
```

### Template Parameters

The current `contractor-workspace` template exposes these user-configurable parameters:

| Parameter | Type | Default | Mutable | Description |
|-----------|------|---------|---------|-------------|
| cpu_cores | number | 2 | Yes | CPU cores (2 or 4) |
| memory_gb | number | 4 | Yes | RAM in GB (4 or 8) |
| disk_size | number | 10 | No | Persistent disk (10/20/50 GB) |
| git_repo | string | (empty) | Yes | Repository to auto-clone |
| dotfiles_repo | string | (empty) | Yes | Dotfiles repo |
| developer_background | string | vscode | Yes | IDE keybinding preset |
| ai_assistant | string | roo-code | Yes | AI agent (roo-code or none) |
| litellm_api_key | string | (empty) | Yes | Per-user LiteLLM virtual key |
| ai_model | string | claude-sonnet | Yes | AI model selection |

**Note:** `disk_size` is `mutable = false` — changing it requires deleting and recreating the workspace.

### Template Update vs. Workspace Recreate

| What Changed | Template Push Enough? | Workspace Recreate Needed? |
|--------------|----------------------|---------------------------|
| Dockerfile (new tools) | Yes (for new workspaces) | Yes (for existing workspaces) |
| Startup script | Yes (on next start) | No |
| Parameters (new options) | Yes | No (users see new options) |
| Agent env vars | Yes | Yes (baked at provision time) |
| Resource defaults | Yes (new workspaces only) | No |
| Volume mount paths | Yes | Yes |

---

## 4. HTTPS / TLS Configuration

> For architecture decisions, Traefik evaluation, and traffic flow diagrams, see [HTTPS.md](HTTPS.md).

### Current Setup

Coder runs with native TLS on port 7443 using a self-signed certificate.

Key environment variables in `.env` / `docker-compose.yml`:

```bash
CODER_ACCESS_URL=https://host.docker.internal:7443
CODER_TLS_ENABLE=true
CODER_TLS_ADDRESS=0.0.0.0:7443
CODER_TLS_CERT_FILE=/certs/coder.crt
CODER_TLS_KEY_FILE=/certs/coder.key
CODER_TLS_MIN_VERSION=tls12
CODER_SECURE_AUTH_COOKIE=true
```

### Why HTTPS?

HTTPS is required because `http://host.docker.internal:7080` is NOT a secure browser context:
- `crypto.subtle` API is `undefined` → code-server can't generate webview nonces
- ALL extension webviews (Roo Code, GitLens, etc.) render as blank panels
- Only `localhost` and HTTPS origins are treated as secure contexts by browsers

### Certificate Files

Location: `coder-poc/certs/`

```
certs/
  coder.crt    # Self-signed certificate (public)
  coder.key    # Private key (DO NOT commit - in .gitignore)
```

The certificate was generated with SAN (Subject Alternative Name) covering:
- `DNS:host.docker.internal`
- `DNS:localhost`
- `IP:127.0.0.1`

### Regenerating the Certificate

If the cert expires (365-day validity) or you need different SANs:

```bash
cd coder-poc/certs
openssl req -x509 -newkey rsa:2048 -keyout coder.key -out coder.crt \
  -days 365 -nodes \
  -subj "/CN=host.docker.internal" \
  -addext "subjectAltName=DNS:host.docker.internal,DNS:localhost,IP:127.0.0.1"
```

Then restart Coder:
```bash
cd coder-poc && docker compose up -d coder
```

### Workspace Agent TLS Trust

Workspace containers need to trust the self-signed cert so the Coder agent can connect back to the Coder server over HTTPS.

The template handles this automatically:
1. Cert is mounted into workspace at `/certs/coder.crt`
2. Entrypoint runs `sudo update-ca-certificates` before agent init
3. `SSL_CERT_FILE` and `NODE_EXTRA_CA_CERTS` env vars point to the cert

### HTTP API Still Available

Port 7080 (HTTP) is still exposed for:
- Setup scripts (`setup.sh`, `setup-workspace.sh`)
- API automation (`curl http://localhost:7080/api/v2/...`)
- CLI operations inside the coder-server container

`CODER_REDIRECT_TO_ACCESS_URL` is **disabled** to keep HTTP API working alongside HTTPS browser access.

---

## 5. AI Model Configuration (LiteLLM)

### Architecture

```
Workspace (Roo Code) → LiteLLM Proxy (port 4000) → Anthropic API / AWS Bedrock
```

LiteLLM is an OpenAI-compatible proxy. Roo Code connects as if talking to OpenAI, but LiteLLM translates and routes requests to the actual model provider.

### Config File

Location: `coder-poc/litellm/config.yaml`

### Model Groups (Automatic Failover)

LiteLLM supports **model groups**: multiple provider entries under the same `model_name`. If the primary provider fails, it automatically falls back to the next one.

Current setup:
- `claude-sonnet-4-5` → Anthropic direct (primary) + Bedrock (fallback)
- `claude-haiku-4-5` → Anthropic direct (primary) + Bedrock (fallback)
- `claude-opus-4` → Anthropic only (no Bedrock equivalent)
- `bedrock-claude-sonnet` → AWS Bedrock only (force Bedrock)
- `bedrock-claude-haiku` → AWS Bedrock only (force Bedrock)

### API Keys Required

Set in `coder-poc/.env`:

```bash
# At least ONE of these must be set
ANTHROPIC_API_KEY=sk-ant-...       # For direct Anthropic API
AWS_ACCESS_KEY_ID=AKIA...          # For AWS Bedrock
AWS_SECRET_ACCESS_KEY=...          # For AWS Bedrock
AWS_REGION=us-east-1               # Bedrock region
```

**If `ANTHROPIC_API_KEY` is empty**: Direct Anthropic calls fail with 401. If Bedrock fallback is configured, LiteLLM auto-fails over to Bedrock.

**If AWS credentials are empty**: Bedrock calls fail. If Anthropic is configured, direct API works.

### Adding a New Model

1. Edit `coder-poc/litellm/config.yaml`:
   ```yaml
   model_list:
     - model_name: my-new-model
       litellm_params:
         model: anthropic/claude-xxx
         api_key: os.environ/ANTHROPIC_API_KEY
   ```

2. Restart LiteLLM (**must** use `up -d`, not `restart`):
   ```bash
   cd coder-poc && docker compose up -d litellm
   ```

3. Add the model as an option in `main.tf`:
   ```hcl
   option {
     name  = "My New Model"
     value = "my-new-model"
   }
   ```

4. Add a case to the startup script in `main.tf`:
   ```hcl
   "my-new-model") AI_MODEL_ID="my-new-model" ;;
   ```

5. Rebuild and push the template.

### LiteLLM Admin UI

Access at: `http://localhost:4000/ui`

From the admin UI you can:
- View registered models
- Monitor request logs and spend
- Manage virtual keys
- Check user budgets

### Per-User Virtual Keys

Each developer gets a LiteLLM virtual key with individual budget and rate limits. Keys are provisioned when workspaces are created.

```bash
# Generate a key for a user
curl -s http://localhost:4000/key/generate \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"user_id":"contractor1","max_budget":10.00,"rpm_limit":60,"key_alias":"contractor1-workspace"}'

# Check a user's budget
curl -s http://localhost:4000/key/info \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"key":"sk-<user-key>"}'
```

See [ROO-CODE-LITELLM.md](ROO-CODE-LITELLM.md) for the full setup guide.

---

## 6. User Management

### Creating Users

**Via Coder UI:**
1. Log in as admin at `https://host.docker.internal:7443`
2. Go to **Deployment > Users**
3. Click **Create User**
4. Set email, username, password, role

**Via API:**
```bash
curl -sf http://localhost:7080/api/v2/users \
  -H "Coder-Session-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","username":"user1","password":"SecurePass123!","login_type":"password"}'
```

**Via setup script:**
```bash
./coder-poc/scripts/setup-coder-users.sh
```

### SSO Users

When using OIDC/SSO (Authentik), users are created automatically on first login. Ensure:

1. User exists in Authentik (or is in an auto-provisioned group)
2. Coder OIDC is configured (see AUTHENTIK-SSO.md)
3. User has `login_type=oidc` — **NOT** `password`

**Critical:** Users created with `login_type=password` cannot log in via OIDC. This is the most common SSO issue. Delete the user in Coder and have them log in fresh via SSO.

### Roles

| Role | Can Do |
|------|--------|
| Owner | Everything (admin) |
| Template Admin | Manage templates, view all workspaces |
| Member | Create/manage own workspaces only |
| Auditor | View audit logs only |

### Identity Consistency

Users must exist consistently across:
- **Authentik** (identity provider)
- **Gitea** (Git credentials)
- **Coder** (platform access)

Misalignment causes silent failures (e.g., Git push denied despite being logged in to Coder).

---

## 7. Service Operations

### Starting All Services

```bash
cd coder-poc && docker compose up -d
```

### Startup Order

Services have dependencies but Docker Compose handles most of them. Manual order if needed:
1. PostgreSQL + Redis (data layer)
2. Authentik (identity)
3. Coder, Gitea, LiteLLM (application layer)

### Restarting a Single Service

```bash
# For config/code changes that don't involve .env:
docker compose restart <service>

# For .env or docker-compose.yml changes (MUST use this):
docker compose up -d <service>
```

**Critical:** `docker compose restart` reuses the existing container and does NOT reload environment variables. After changing `.env`, always use `docker compose up -d`.

### Viewing Logs

```bash
# All services
docker compose logs -f

# Specific service (last 50 lines, follow)
docker compose logs -f --tail=50 coder
docker compose logs -f --tail=50 litellm

# Workspace container logs
docker logs coder-admin-myworkspace
```

### Health Checks

```bash
# Coder
curl -sf http://localhost:7080/api/v2/buildinfo

# LiteLLM
curl -sf http://localhost:4000/health/readiness

# Authentik
curl -sf http://host.docker.internal:9000/-/health/live/

# Gitea
curl -sf http://localhost:3000/api/v1/version

# All service health
docker compose ps
```

---

## 8. Common Admin Tasks

### Task: Set Up a New PoC Environment from Scratch

```bash
# 1. Start services
cd coder-poc && docker compose up -d

# 2. Run initial setup (first user, SSO config)
./scripts/setup.sh

# 3. Build workspace image and push template
./scripts/setup-workspace.sh

# 4. Generate LiteLLM keys for users
./scripts/setup-litellm-keys.sh

# 5. Access platform
open https://host.docker.internal:7443
```

### Task: Add a New AI Model Option for Users

1. Add model to `litellm/config.yaml` (see [Adding a New Model](#adding-a-new-model))
2. Add option to `templates/contractor-workspace/main.tf`
3. Add case to the model mapping in the startup script
4. Rebuild image (if Dockerfile changed): `docker build -t contractor-workspace:latest ...`
5. Push template: `./scripts/setup-workspace.sh`
6. Tell users to create new workspaces (or update existing ones)

### Task: Increase a User's AI Budget

```bash
LITELLM_MASTER_KEY="sk-poc-litellm-master-key-change-in-production"

curl http://localhost:4000/budget/update \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "contractor1", "max_budget": 25.00}'
```

### Task: Revoke a User's AI Access

Delete their LiteLLM virtual key. The workspace will lose AI access until rebuilt with a new key.

```bash
curl http://localhost:4000/key/delete \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"keys": ["sk-user-key-to-revoke"]}'
```

### Task: Change a User's AI Enforcement Level

The Design-First AI Enforcement Layer controls how AI agents approach development tasks (e.g., requiring a design proposal before writing code). The enforcement level (`unrestricted`, `standard`, `design-first`) is stored in the LiteLLM virtual key's metadata and injected server-side by a LiteLLM callback — users cannot bypass it.

**Option 1: Change for new workspaces** — Update the `ai_enforcement_level` template parameter default in `main.tf` and push the template.

**Option 2: Change for an existing workspace** — The enforcement level is baked into the key at creation time. To change it, either:
1. Delete the workspace and recreate it with the new level, or
2. Rotate the key via the LiteLLM admin API (delete the old key, create a new one with updated `metadata.enforcement_level`)

```bash
# Check a key's current enforcement level
curl -s -X GET http://localhost:4000/key/info \
  -H "Authorization: Bearer <user-key>" | python3 -c "
import sys, json; d = json.load(sys.stdin)
print('enforcement_level:', d.get('info',{}).get('metadata',{}).get('enforcement_level','NONE'))
"
```

See [AI.md Section 12](AI.md#12-design-first-ai-enforcement-layer) and [ROO-CODE-LITELLM.md Section 7](ROO-CODE-LITELLM.md#7-design-first-ai-enforcement) for full details.

### Task: Check What's Running

```bash
# Platform services
docker compose ps

# Active workspaces
docker ps --filter "name=coder-"

# Resource usage
docker stats --no-stream
```

---

## 9. Troubleshooting

### OIDC Login Fails: "oauth_state cookie must be provided"

**Cause:** Cookie domain mismatch. You visited `localhost` but the callback returns to `host.docker.internal` (or vice versa).

**Fix:** Always access Coder via `https://host.docker.internal:7443`. Clear cookies and try again.

### Blank Extension Panels (Roo Code, etc.)

**Cause:** Browser insecure context. `crypto.subtle` is `undefined` because the page is not served over HTTPS or localhost.

**Fix:** Access via `https://host.docker.internal:7443`. Verify in browser console:
```javascript
console.log(window.isSecureContext);  // Must be true
```

### Template Push Fails: "not authenticated"

**Cause:** Session token expired or not set.

**Fix:** Get a fresh token:
```bash
TOKEN=$(curl -sf http://localhost:7080/api/v2/users/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@example.com","password":"CoderAdmin123!"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['session_token'])")
```

### LiteLLM 401 Authentication Error

**Cause:** `ANTHROPIC_API_KEY` is empty in `.env` and Bedrock credentials aren't configured (or the selected model doesn't have a Bedrock fallback).

**Fix:** Set at least one provider's API key in `.env`, then:
```bash
docker compose up -d litellm
```

### Workspace Agent Not Connecting

**Cause:** Agent can't reach Coder server. Usually `CODER_ACCESS_URL` is wrong or the agent doesn't trust the TLS certificate.

**Fix:**
1. Check `CODER_ACCESS_URL` in the running container: `docker exec coder-server env | grep CODER_ACCESS_URL`
2. For TLS issues, ensure the cert is mounted and `update-ca-certificates` runs in the workspace entrypoint

### Environment Variables Not Taking Effect

**Cause:** Used `docker compose restart` instead of `docker compose up -d`.

**Fix:** Always use `up -d` after changing `.env`:
```bash
docker compose up -d <service-name>
```

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-06 | Platform Team | Initial version — template management, HTTPS, AI config, operations |
