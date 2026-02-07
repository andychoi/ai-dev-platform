# Roo Code + LiteLLM Setup Guide

This document covers the complete configuration of Roo Code AI coding agent with LiteLLM proxy in Coder workspaces.

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Prerequisites](#2-prerequisites)
3. [LiteLLM Proxy Setup](#3-litellm-proxy-setup)
4. [Roo Code Extension Configuration](#4-roo-code-extension-configuration)
5. [Workspace Template Integration](#5-workspace-template-integration)
6. [User Key Management](#6-user-key-management)
7. [Suppressing "Create Roo Account" Prompt](#7-suppressing-create-roo-account-prompt)
8. [Troubleshooting](#8-troubleshooting)
9. [Verification Checklist](#9-verification-checklist)

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  Coder Workspace (code-server)                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  Roo Code Extension (rooveterinaryinc.roo-cline)            │ │
│  │  ┌─────────────────────────────────────────────┐            │ │
│  │  │  providerProfiles → apiProvider: "openai"   │            │ │
│  │  │  openAiBaseUrl: http://litellm:4000/v1      │            │ │
│  │  │  openAiApiKey: <per-user virtual key>        │            │ │
│  │  │  openAiModelId: claude-sonnet-4-5            │            │ │
│  │  └──────────────────────┬──────────────────────┘            │ │
│  └──────────────────────────┼──────────────────────────────────┘ │
│                              │ OpenAI-compatible API calls        │
│                              ▼                                    │
│  ┌───────────────────────────────────────────────────────────┐   │
│  │  LiteLLM Proxy (port 4000)                                 │   │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐      │   │
│  │  │ Virtual Key  │ │   Budget     │ │  Rate Limit  │      │   │
│  │  │ Validation   │ │  Enforcement │ │  (per-user)  │      │   │
│  │  └──────────────┘ └──────────────┘ └──────────────┘      │   │
│  │  ┌──────────────┐ ┌──────────────┐                        │   │
│  │  │ Audit Log    │ │  Provider    │                        │   │
│  │  │ (PostgreSQL) │ │  Routing     │                        │   │
│  │  └──────────────┘ └──────┬───────┘                        │   │
│  └───────────────────────────┼───────────────────────────────┘   │
│                              │                                    │
│              ┌───────────────┼───────────────┐                   │
│              ▼               ▼               ▼                   │
│     ┌──────────────┐ ┌──────────────┐ ┌──────────────┐         │
│     │  Anthropic   │ │ AWS Bedrock  │ │   Future     │         │
│     │  Direct API  │ │  (Claude)    │ │  Providers   │         │
│     └──────────────┘ └──────────────┘ └──────────────┘         │
└─────────────────────────────────────────────────────────────────┘
```

### Key Design Decisions

- **Roo Code uses "openai" provider** — LiteLLM exposes an OpenAI-compatible `/v1/chat/completions` endpoint. Roo Code connects as if talking to OpenAI, but LiteLLM translates requests to each provider's native format.
- **Per-user virtual keys** — Each developer gets a LiteLLM virtual key with individual budget caps and rate limits. The master API key (for Anthropic/Bedrock) is never exposed to workspaces.
- **No Roo Cloud account needed** — The extension is configured to use a self-hosted LiteLLM proxy, bypassing Roo's cloud services entirely.

---

## 2. Prerequisites

### Browser Secure Context (CRITICAL)

code-server webviews (including Roo Code) require the `crypto.subtle` API, which browsers only expose in **secure contexts** (HTTPS or `localhost`). Since we access Coder via `http://host.docker.internal:7080`, the browser treats it as insecure and `crypto.subtle` is `undefined`, causing ALL extension webviews to render blank.

**Permanent fix — HTTPS is now enabled by default:**

Coder runs with TLS on port 7443 using a self-signed certificate. Access via `https://host.docker.internal:7443`. On first visit, accept the browser's certificate warning, or install the cert in your OS trust store:

```bash
# macOS — trust the self-signed cert (eliminates browser warning)
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  "$(pwd)/coder-poc/certs/coder.crt"
```

**Alternative PoC workaround — Chrome flag (if HTTPS is disabled):**

Launch Chrome with the secure origin flag before accessing Coder workspaces:

```bash
# macOS
open -a "Google Chrome" --args --unsafely-treat-insecure-origin-as-secure="http://host.docker.internal:7080"

# Linux
google-chrome --unsafely-treat-insecure-origin-as-secure="http://host.docker.internal:7080"
```

Or set via `chrome://flags/#unsafely-treat-insecure-origin-as-secure` — add `http://host.docker.internal:7080` and relaunch.

**How to verify:** Open browser console (F12) on any code-server page and run:
```javascript
console.log(crypto.subtle);  // Should NOT be undefined
```

If `crypto.subtle` is `undefined`, the flag/HTTPS is not active and all webviews will be blank.

### Required API Keys

At minimum, ONE of these must be configured in `coder-poc/.env`:

| Variable | Purpose | Required |
|----------|---------|----------|
| `ANTHROPIC_API_KEY` | Direct Anthropic API access | Yes (unless using Bedrock only) |
| `AWS_ACCESS_KEY_ID` | AWS Bedrock access | Optional |
| `AWS_SECRET_ACCESS_KEY` | AWS Bedrock secret | Optional (required with access key) |
| `AWS_REGION` | Bedrock region | Default: `us-east-1` |

**CRITICAL: Without `ANTHROPIC_API_KEY`, all direct Anthropic model calls will fail with `401 authentication_error`. LiteLLM is a proxy, NOT a model provider — it needs upstream API keys to forward requests.**

### Required Services

| Service | Port | Health Check |
|---------|------|-------------|
| LiteLLM | 4000 | `GET /health/readiness` |
| PostgreSQL | 5432 | `pg_isready` |
| Coder | 7080 | `GET /api/v2/buildinfo` |

### LiteLLM Master Key

Set in `.env`:
```bash
LITELLM_MASTER_KEY=sk-poc-litellm-master-key-change-in-production
```

This key is used to:
- Generate per-user virtual keys
- Access the LiteLLM admin API
- Manage budgets and rate limits

---

## 3. LiteLLM Proxy Setup

### Configuration File

Location: `coder-poc/litellm/config.yaml`

```yaml
model_list:
  # Direct Anthropic API models
  - model_name: claude-sonnet-4-5
    litellm_params:
      model: anthropic/claude-sonnet-4-5-20250929
      api_key: os.environ/ANTHROPIC_API_KEY

  - model_name: claude-haiku-4-5
    litellm_params:
      model: anthropic/claude-haiku-4-5-20251001
      api_key: os.environ/ANTHROPIC_API_KEY

  - model_name: claude-opus-4
    litellm_params:
      model: anthropic/claude-opus-4-20250514
      api_key: os.environ/ANTHROPIC_API_KEY

  # AWS Bedrock models (alternative provider)
  - model_name: bedrock-claude-sonnet
    litellm_params:
      model: bedrock/us.anthropic.claude-sonnet-4-5-20250929-v1:0
      aws_access_key_id: os.environ/AWS_ACCESS_KEY_ID
      aws_secret_access_key: os.environ/AWS_SECRET_ACCESS_KEY
      aws_region_name: os.environ/AWS_REGION

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  database_url: os.environ/DATABASE_URL

litellm_settings:
  max_end_user_budget: 10.00
  drop_params: true
  success_callback: ["log_to_db"]
  failure_callback: ["log_to_db"]
```

### Model Name Mapping

Roo Code sends model names; LiteLLM maps them to provider-specific model IDs:

| Roo Code sends | LiteLLM routes to | Provider | Failover |
|----------------|-------------------|----------|----------|
| `claude-sonnet-4-5` | `anthropic/claude-sonnet-4-5-20250929` | Anthropic API | Auto-failover to Bedrock |
| `claude-haiku-4-5` | `anthropic/claude-haiku-4-5-20251001` | Anthropic API | Auto-failover to Bedrock |
| `claude-opus-4` | `anthropic/claude-opus-4-20250514` | Anthropic API | None (Anthropic only) |
| `bedrock-claude-sonnet` | `bedrock/us.anthropic.claude-sonnet-4-5-*` | AWS Bedrock | None (Bedrock only) |
| `bedrock-claude-haiku` | `bedrock/us.anthropic.claude-haiku-4-5-*` | AWS Bedrock | None (Bedrock only) |

> **Model groups:** `claude-sonnet-4-5` and `claude-haiku-4-5` each have two entries in `config.yaml` — one for Anthropic direct and one for Bedrock. LiteLLM automatically fails over to the next provider if the primary returns an error (e.g., 401 from missing `ANTHROPIC_API_KEY`).

### Verify LiteLLM Health

```bash
# From host
curl http://localhost:4000/health/readiness

# From workspace container
docker exec <workspace-container> curl http://litellm:4000/health/readiness

# List available models
curl http://localhost:4000/v1/models \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"

# Test a completion (from host)
curl http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -d '{"model":"claude-sonnet-4-5","messages":[{"role":"user","content":"say hello"}],"max_tokens":10}'
```

---

## 4. Roo Code & OpenCode Configuration

### How Configuration Flows

```
1. Workspace creation → User optionally enters litellm_api_key (or leaves empty)
                              ↓
2. Startup script → If key empty, calls key-provisioner to auto-provision
                              ↓
3. With virtual key → Generates Roo Code config + OpenCode config
                              ↓
4. Roo Code: /home/coder/.config/roo-code/settings.json (auto-import)
   OpenCode: /home/coder/.config/opencode/config.json
                              ↓
5. Both tools ready → Use LiteLLM as API backend
```

### Auto-Provisioning (New)

If the `litellm_api_key` parameter is left empty (recommended), the startup script automatically provisions a key:

1. Calls `POST http://key-provisioner:8100/api/v1/keys/workspace` with workspace ID and username
2. Key-provisioner checks if key already exists (by alias `workspace-{workspace_id}`)
3. If exists → returns existing key (idempotent on restart)
4. If new → generates via LiteLLM with $10 budget, 60 RPM, scope `workspace:{workspace_id}`
5. Startup script uses the returned key for both Roo Code and OpenCode configuration

The key-provisioner isolates the LiteLLM master key — workspace containers never see it.

### OpenCode CLI

[OpenCode](https://opencode.ai) is a terminal-based AI coding agent installed alongside Roo Code. It provides:
- TUI (text user interface) for AI-assisted coding
- File reading, editing, and command execution
- Same LiteLLM backend as Roo Code

Configuration at `/home/coder/.config/opencode/config.json` uses `@ai-sdk/openai-compatible` provider pointing to LiteLLM.

To use: run `opencode` in the workspace terminal.

### Auto-Import Settings File

Generated at: `/home/coder/.config/roo-code/settings.json`

```json
{
  "providerProfiles": {
    "currentApiConfigName": "litellm",
    "apiConfigs": {
      "litellm": {
        "apiProvider": "openai",
        "openAiBaseUrl": "http://litellm:4000/v1",
        "openAiApiKey": "<per-user-virtual-key>",
        "openAiModelId": "claude-sonnet-4-5",
        "id": "litellm-default"
      }
    }
  }
}
```

### VS Code Settings

In `build/settings.json` (baked into workspace image):

```jsonc
{
  // Auto-import Roo Code config from startup-generated file
  "roo-cline.autoImportSettingsPath": "/home/coder/.config/roo-code/settings.json",

  // Disable all competing AI features
  "chat.agent.enabled": false,
  "chat.commandCenter.enabled": false,
  "chat.disableAIFeatures": true,
  "github.copilot.enable": { "*": false },
  "github.copilot.editor.enableAutoCompletions": false,
  "github.copilot.chat.enabled": false,
  "inlineChat.mode": "off",
  "editor.inlineSuggest.enabled": false,
  "cody.enabled": false,
  "cody.autocomplete.enabled": false,
  "workbench.secondarySideBar.defaultVisibility": "hidden"
}
```

### Workspace Dockerfile

Roo Code is pre-installed; competing extensions are removed:

```dockerfile
# Install Roo Code
RUN code-server --install-extension rooveterinaryinc.roo-cline

# Remove competing AI extensions
RUN code-server --uninstall-extension github.copilot 2>/dev/null || true \
    && code-server --uninstall-extension github.copilot-chat 2>/dev/null || true \
    && code-server --uninstall-extension sourcegraph.cody-ai 2>/dev/null || true
```

---

## 5. Workspace Template Integration

### Terraform Parameters (main.tf)

The template exposes these user-configurable parameters:

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `ai_assistant` | `roo-code` | Enable/disable AI agent |
| `litellm_api_key` | (empty) | Per-user LiteLLM virtual key |
| `ai_model` | `claude-sonnet` | Model selection |
| `ai_gateway_url` | `http://litellm:4000` | LiteLLM proxy URL |

### Startup Script Logic

The startup script in `main.tf` handles AI configuration:

1. Checks if `ai_assistant = "roo-code"` AND `litellm_api_key` is non-empty
2. Maps the selected model to LiteLLM model name:
   - `claude-sonnet` → `claude-sonnet-4-5`
   - `claude-haiku` → `claude-haiku-4-5`
   - `claude-opus` → `claude-opus-4`
3. Generates Roo Code auto-import config at `/home/coder/.config/roo-code/settings.json`
4. Sets environment variables in `~/.bashrc` for CLI tools

### Environment Variables Set in Workspace

```bash
AI_GATEWAY_URL="http://litellm:4000"
OPENAI_API_BASE="http://litellm:4000/v1"
OPENAI_API_KEY="<per-user-key>"
AI_MODEL="claude-sonnet-4-5"
```

---

## 6. User Key Management

### Auto-Provisioned Keys (Recommended)

Leave the "AI API Key" field empty when creating a workspace. The key-provisioner service will automatically generate a scoped key with:
- Budget: $10
- Rate limit: 60 RPM
- Scope: `workspace:{workspace_id}`

The key is reused on workspace restart (idempotent by alias).

### Self-Service Keys

For personal use outside workspaces (e.g., local development):

```bash
cd coder-poc
./scripts/generate-ai-key.sh
```

Requires a Coder session token. Creates a key with scope `user:{username}`, $20 budget, 100 RPM.

### Service Keys (Admin)

For CI/CD pipelines and background agents:

```bash
# CI key (haiku only, $5 budget)
./scripts/manage-service-keys.sh create ci frontend-repo

# Agent keys
./scripts/manage-service-keys.sh create agent review   # $15, sonnet+haiku
./scripts/manage-service-keys.sh create agent write     # $30, all models

# List and manage
./scripts/manage-service-keys.sh list
./scripts/manage-service-keys.sh revoke ci-frontend-repo
./scripts/manage-service-keys.sh rotate agent-review
```

### Bootstrap Keys (Legacy)

For initial setup or migration from manual key management:

```bash
cd coder-poc
./scripts/setup-litellm-keys.sh
```

### Key Scope Taxonomy

| Scope | Budget | RPM | Models | Use Case |
|-------|--------|-----|--------|----------|
| `workspace:{id}` | $10 | 60 | All | Roo Code + OpenCode in workspace |
| `user:{username}` | $20 | 100 | All | Personal experimentation |
| `ci:{repo}` | $5 | 30 | Haiku only | CI pipeline reviews |
| `agent:review` | $15 | 40 | Sonnet + Haiku | Read-only review agent |
| `agent:write` | $30 | 60 | All | Code generation agent |

### Check Key Info

```bash
# Via key-provisioner (with any LiteLLM key)
curl -s http://localhost:8100/api/v1/keys/info \
  -H "Authorization: Bearer <your-key>"

# Via LiteLLM admin API (master key)
curl -s http://localhost:4000/key/info \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"key": "sk-<user-key>"}'
```

See `docs/KEY-MANAGEMENT.md` for full key management documentation.

---

## 7. Suppressing "Create Roo Account" Prompt

### Problem

Roo Code v3.x includes a built-in Roo Cloud authentication system. When the extension loads, it may show a "Create Roo Account" or sign-in prompt, even when a 3rd party API provider (LiteLLM) is configured.

### Root Cause

The Roo Cloud auth system is separate from the API provider configuration. The extension uses Clerk (clerk.roocode.com) for its cloud auth. The `cloudIsAuthenticated` state defaults to `false`, which triggers the cloud UI.

### Solution

There is **no VS Code setting** to disable the Roo Cloud prompt. However:

1. **The providerProfiles auto-import DOES configure the 3rd party provider.** The user should be able to dismiss the cloud prompt and use the pre-configured LiteLLM provider.

2. **Internal state `roo-auth-skip-model`** — Roo Code stores a `cloudAuthSkipModel` flag in VS Code's `globalState`. When set to `true`, the cloud auth prompt is skipped. This gets set when a user explicitly skips the cloud auth flow.

3. **Practical workaround** — The user clicks "Skip" or dismisses the account creation prompt once. The extension remembers this choice in its global state.

### What the User Should Do

1. Open the Roo Code panel in the sidebar
2. If the "Create Roo Account" or cloud sign-in screen appears, look for "Skip" or "Use API Key" option
3. The pre-configured LiteLLM provider should already be available under the provider dropdown
4. Select the "litellm" profile if not already selected
5. The extension will remember this choice for future sessions

### If Roo Code Panel Is Blank

See [Troubleshooting - Blank Roo Code Panel](#blank-roo-code-panel) below.

---

## 8. Troubleshooting

### LiteLLM Returns 401 Authentication Error

**Symptom:**
```json
{"error":{"message":"AuthenticationError: x-api-key header is required","code":"401"}}
```

**Cause:** `ANTHROPIC_API_KEY` is empty in `.env`. LiteLLM can accept and route requests but cannot authenticate with Anthropic without the upstream API key.

**Fix:**
```bash
# 1. Set the API key in .env
echo 'ANTHROPIC_API_KEY=sk-ant-your-key-here' >> coder-poc/.env

# 2. Restart LiteLLM (MUST use up -d, not restart)
cd coder-poc && docker compose up -d litellm

# 3. Verify
curl http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -d '{"model":"claude-sonnet-4-5","messages":[{"role":"user","content":"say hello"}],"max_tokens":10}'
```

### LiteLLM Container Shows "unhealthy"

**Symptom:** `docker compose ps` shows LiteLLM as `unhealthy`.

**Common Causes:**
1. PostgreSQL not ready — LiteLLM needs PostgreSQL for key management and logging
2. Invalid config.yaml — Check for YAML syntax errors
3. Missing environment variables

**Diagnose:**
```bash
docker compose logs litellm --tail=50
```

### Roo Code Not Connecting to LiteLLM

**Symptom:** Roo Code shows errors when sending messages, or no response.

**Verify connectivity from workspace:**
```bash
# Check if workspace can reach LiteLLM
docker exec <workspace-container> curl -s http://litellm:4000/health/readiness

# List models visible to the user's key
docker exec <workspace-container> curl -s http://litellm:4000/v1/models \
  -H "Authorization: Bearer <user-key>"

# Test actual completion
docker exec <workspace-container> curl -s http://litellm:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <user-key>" \
  -d '{"model":"claude-sonnet-4-5","messages":[{"role":"user","content":"hello"}],"max_tokens":10}'
```

### Blank Roo Code Panel

**Symptom:** Clicking Roo Code in the sidebar shows a blank/white panel with no UI. This affects ALL extension webviews, not just Roo Code.

**Most Likely Cause: Insecure Context (crypto.subtle unavailable)**

When accessing code-server via `http://host.docker.internal:7080`, the browser treats the origin as insecure. The `crypto.subtle` API is `undefined`, which prevents code-server from generating webview iframe nonces. This is a platform-level issue — every extension webview will be blank.

**Diagnose:** Open browser console (F12) on the code-server page:
```javascript
console.log(crypto.subtle);  // undefined = insecure context = root cause
console.log(window.isSecureContext);  // false = confirms the issue
```

**Fix:** Enable HTTPS on Coder (permanent), or launch Chrome with the secure origin flag (temporary PoC workaround). See [Browser Secure Context](#browser-secure-context-critical) in Prerequisites.

**Other Possible Causes:**

1. **Extension activation failure** — Check the Roo Code output log:
   ```bash
   docker exec <workspace-container> cat \
     "$(docker exec <workspace-container> find /home/coder/.local/share/code-server/logs -name '*Roo-Code.log' | sort | tail -1)"
   ```

2. **Webview CSP (Content Security Policy)** — code-server may restrict webview resources. Check browser developer console (F12) for CSP errors.

**Additional Fixes (if not a secure context issue):**
- Restart code-server: In the workspace terminal, run `pkill -f code-server`; it will auto-restart
- Clear extension cache: Delete `/home/coder/.local/share/code-server/User/globalStorage/rooveterinaryinc.roo-cline/cache/`
- Try a different Roo Code version (pin in Dockerfile): `code-server --install-extension rooveterinaryinc.roo-cline@3.45.0`

### Auto-Import Not Working

**Symptom:** Roo Code opens with default settings, not the LiteLLM configuration.

**Verify:**
1. Check the auto-import config file exists:
   ```bash
   docker exec <workspace-container> cat /home/coder/.config/roo-code/settings.json
   ```

2. Check the VS Code setting is set:
   ```bash
   docker exec <workspace-container> grep autoImport \
     /home/coder/.local/share/code-server/User/settings.json
   ```

3. Check the Roo Code log for import status:
   ```bash
   # Should show: [AutoImport] Successfully imported settings
   docker exec <workspace-container> grep -r "AutoImport" \
     /home/coder/.local/share/code-server/logs/
   ```

### Model Not Available

**Symptom:** Roo Code shows "model not found" error.

**Cause:** The model name in Roo Code config doesn't match any `model_name` in LiteLLM's `config.yaml`.

**Fix:** Ensure model names match exactly:
- Roo Code config: `"openAiModelId": "claude-sonnet-4-5"`
- LiteLLM config: `model_name: claude-sonnet-4-5`

### Budget Exceeded

**Symptom:** `402 Budget Exceeded` error from LiteLLM.

**Fix:** Increase user budget:
```bash
curl http://localhost:4000/budget/update \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "contractor1", "max_budget": 20.00}'
```

---

## 9. Verification Checklist

### Infrastructure Checks

```bash
# 1. LiteLLM is running and healthy
curl -s http://localhost:4000/health/readiness | jq .status
# Expected: "connected"

# 2. ANTHROPIC_API_KEY is set (not empty)
docker exec litellm env | grep ANTHROPIC_API_KEY | grep -v "=$"
# Should show the key (not empty)

# 3. Models are registered
curl -s http://localhost:4000/v1/models -H "Authorization: Bearer $LITELLM_MASTER_KEY" | jq '.data[].id'
# Expected: claude-sonnet-4-5, claude-haiku-4-5, claude-opus-4, bedrock-*

# 4. Test completion works
curl -s http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -d '{"model":"claude-sonnet-4-5","messages":[{"role":"user","content":"say hello"}],"max_tokens":10}' | jq .choices[0].message.content
```

### Workspace Checks

```bash
CONTAINER="coder-<username>-<workspace>"

# 5. Workspace can reach LiteLLM
docker exec $CONTAINER curl -s http://litellm:4000/health/readiness

# 6. Roo Code config file exists
docker exec $CONTAINER cat /home/coder/.config/roo-code/settings.json

# 7. Auto-import setting is configured
docker exec $CONTAINER grep autoImport /home/coder/.local/share/code-server/User/settings.json

# 8. Roo Code extension is installed
docker exec $CONTAINER code-server --list-extensions | grep roo-cline

# 9. Roo Code auto-import succeeded (check logs)
docker exec $CONTAINER grep "AutoImport" $(docker exec $CONTAINER find /home/coder/.local/share/code-server/logs -name '*Roo-Code.log' | sort | tail -1)
# Expected: [AutoImport] Successfully imported settings
```

### End-to-End Test

1. Open Coder dashboard at `https://host.docker.internal:7443` (accept self-signed cert warning)
2. Open a workspace with Roo Code enabled
3. Click VS Code app → code-server opens
4. Click Roo Code icon in sidebar
5. If cloud prompt appears → skip/dismiss it
6. Type a message (e.g., "say hello") → should get a response from Claude via LiteLLM
