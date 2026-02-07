---
name: ai-gateway
description: Roo Code AI agent + LiteLLM proxy - configuration, troubleshooting, model management, virtual keys
---

# AI Gateway Skill (Roo Code + LiteLLM)

## Overview

AI capabilities in Coder workspaces are provided by **Roo Code** (VS Code extension) connected to **LiteLLM** (OpenAI-compatible proxy). LiteLLM handles authentication, routing, budgeting, and audit logging for upstream AI providers (Anthropic, AWS Bedrock).

> Full documentation: `shared/docs/ROO-CODE-LITELLM.md`

## Architecture

```
Workspace (code-server + terminal)
  ├─ Roo Code Extension (VS Code sidebar)
  └─ OpenCode CLI (terminal TUI)
     └─ OpenAI-compatible API (apiProvider: "openai")
        └─ LiteLLM Proxy (litellm:4000)
           ├─ Virtual Key Validation
           ├─ Budget Enforcement ($10/workspace default)
           ├─ Rate Limiting (60 RPM default)
           └─ Provider Routing
              ├─ Anthropic Direct API (ANTHROPIC_API_KEY)
              └─ AWS Bedrock (AWS credentials)

Key Provisioning:
  Workspace startup → Key Provisioner (key-provisioner:8100) → LiteLLM /key/generate
  (auto-provisions scoped virtual key; master key never exposed to workspaces)
```

## Access

| Endpoint | URL (from host) | URL (from workspace) |
|----------|-----------------|---------------------|
| LiteLLM Health | http://localhost:4000/health/readiness | http://litellm:4000/health/readiness |
| LiteLLM Models | http://localhost:4000/v1/models | http://litellm:4000/v1/models |
| LiteLLM Admin | http://localhost:4000/ui | N/A |
| Chat Completions | http://localhost:4000/v1/chat/completions | http://litellm:4000/v1/chat/completions |

## Enforcement Layer

LiteLLM uses a custom callback hook to inject system prompts based on per-key `enforcement_level` metadata. This controls how opinionated the AI agent's behavior is (e.g., requiring design docs before code).

- **Hook**: `litellm/enforcement_hook.py` -- registered in `config.yaml` via `callbacks: ["enforcement_hook.proxy_handler_instance"]`
- **Prompts directory**: `litellm/prompts/` -- editable `.md` files loaded with mtime-based cache (no restart required)
- **Levels**: `unrestricted` (no injection), `standard` (general best practices), `design-first` (strict design-before-code workflow)
- **Default level**: Controlled by `DEFAULT_ENFORCEMENT_LEVEL` env var (defaults to `standard`)
- The `enforcement_level` is set in key metadata at provisioning time (see `skills/key-management/SKILL.md`)

## Available Models

| Model Name (LiteLLM) | Provider | Use Case |
|----------------------|----------|----------|
| `claude-sonnet-4-5` | Anthropic | Balanced (default) |
| `claude-haiku-4-5` | Anthropic | Fast / cost-efficient |
| `claude-opus-4` | Anthropic | Advanced reasoning |
| `bedrock-claude-sonnet` | AWS Bedrock | Alternative provider |
| `bedrock-claude-haiku` | AWS Bedrock | Alternative provider |

## Critical Requirements

### Upstream API Keys

LiteLLM is a **proxy**, not a model provider. It needs at least ONE upstream credential:

| Provider | Env Var | Fallback |
|----------|---------|----------|
| Anthropic Direct | `ANTHROPIC_API_KEY` | Primary for `claude-sonnet-4-5`, `claude-haiku-4-5`, `claude-opus-4` |
| AWS Bedrock | `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` | Auto-fallback for `claude-sonnet-4-5` and `claude-haiku-4-5` |

LiteLLM config lists Bedrock as a fallback deployment for `claude-sonnet-4-5` and `claude-haiku-4-5`. If `ANTHROPIC_API_KEY` is empty but AWS creds are set, LiteLLM automatically routes to Bedrock.

```bash
# Check which upstream keys are configured
grep "^ANTHROPIC_API_KEY=\|^AWS_ACCESS_KEY_ID=" coder-poc/.env

# After changing keys:
cd coder-poc && docker compose up -d litellm
```

### Virtual Keys — Auto-Provisioned

Workspace keys are **auto-provisioned** by the key-provisioner service (port 8100). Leave the "AI API Key" parameter empty — a scoped key is generated on workspace start.

For manual or self-service key generation:

```bash
# Self-service (requires Coder session token)
./scripts/generate-ai-key.sh

# Admin: CI/agent service keys
./scripts/manage-service-keys.sh create ci frontend-repo
./scripts/manage-service-keys.sh create agent review

# Legacy bootstrap
./scripts/setup-litellm-keys.sh
```

See `skills/key-management/SKILL.md` for full key taxonomy and management.

## AI Agent Configuration

### How It Works

1. Workspace starts → key auto-provisioned (or user provides one)
2. Startup script generates Roo Code config + OpenCode config
3. Roo Code: `/home/coder/.config/roo-code/settings.json` (auto-import via `roo-cline.autoImportSettingsPath`)
4. OpenCode: `/home/coder/.config/opencode/config.json`
5. Both tools use same LiteLLM virtual key and endpoint

### Config Format (providerProfiles)

```json
{
  "providerProfiles": {
    "currentApiConfigName": "litellm",
    "apiConfigs": {
      "litellm": {
        "apiProvider": "openai",
        "openAiBaseUrl": "http://litellm:4000/v1",
        "openAiApiKey": "<virtual-key>",
        "openAiModelId": "claude-sonnet-4-5",
        "id": "litellm-default"
      }
    }
  }
}
```

### OpenCode Config Format (opencode.json)

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "litellm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "LiteLLM",
      "options": {
        "baseURL": "http://litellm:4000/v1",
        "apiKey": "<virtual-key>"
      },
      "models": {
        "claude-sonnet-4-5": { "name": "Claude Sonnet 4.5" },
        "claude-haiku-4-5": { "name": "Claude Haiku 4.5" },
        "claude-opus-4": { "name": "Claude Opus 4" }
      }
    }
  },
  "model": "litellm/claude-sonnet-4-5",
  "small_model": "litellm/claude-haiku-4-5"
}
```

**Three things required for OpenCode + LiteLLM:**
1. npm package `@ai-sdk/openai-compatible` installed in `~/.config/opencode/`
2. `models` map declaring available models (without it, opencode ignores the provider)
3. Config at `~/.config/opencode/opencode.json` (global) or `./opencode.json` (project)

### "Create Roo Account" Prompt

Roo Code v3.x shows a cloud auth prompt by default. There is no VS Code setting to disable it. Users should:
1. Skip/dismiss the cloud auth prompt
2. The pre-configured LiteLLM provider is already available

The skip state is stored in VS Code globalState as `roo-auth-skip-model`.

## Disabled AI Features

To prevent interference, the following are disabled in workspace settings:

| Feature | Setting | Value |
|---------|---------|-------|
| VS Code Chat | `chat.disableAIFeatures` | `true` |
| GitHub Copilot | `github.copilot.enable` | `{"*": false}` |
| Inline Suggestions | `editor.inlineSuggest.enabled` | `false` |
| Cody | `cody.enabled` | `false` |
| Coder AI Bridge | `CODER_AIBRIDGE_ENABLED` | `false` |
| Coder AI Tasks | `CODER_HIDE_AI_TASKS` | `true` |

Extensions removed in Dockerfile: `github.copilot`, `github.copilot-chat`, `sourcegraph.cody-ai`

## Troubleshooting Quick Reference

| Symptom | Cause | Fix |
|---------|-------|-----|
| 401 auth error | No upstream API key (Anthropic or Bedrock) | Set `ANTHROPIC_API_KEY` or AWS creds in `.env`, `docker compose up -d litellm` |
| LiteLLM unhealthy | PostgreSQL not ready or config error | Check `docker compose logs litellm` |
| Roo Code blank panel | Insecure context (`crypto.subtle` undefined) | Enable HTTPS on Coder |
| Auto-import failed | Config file missing or wrong path | Check file exists and `autoImportSettingsPath` is set |
| Model not found | Model name mismatch | Match `openAiModelId` with LiteLLM `model_name` |
| Budget exceeded (402) | User spent their budget | Increase via `/budget/update` API |
| No response from AI | LiteLLM unreachable from workspace | Check network: `curl http://litellm:4000/health/readiness` |
| OpenCode shows wrong model (GPT-5.2) | `models` section missing in config | Add `models` map to opencode.json provider |
| OpenCode "Provider not found" | `@ai-sdk/openai-compatible` not installed | Run `cd ~/.config/opencode && npm install @ai-sdk/openai-compatible` |
| OpenCode config not generated | Startup script `command -v` failed | Check `[ -x ~/.opencode/bin/opencode ]`; verify PATH includes `~/.opencode/bin` |
| OpenCode "incorrect api key" | Config missing (no opencode.json) | Check `/home/coder/.config/opencode/opencode.json` exists with correct key |

## Key File Locations

| File | Purpose |
|------|---------|
| `coder-poc/.env` | API keys and master key |
| `coder-poc/litellm/config.yaml` | Model definitions and settings |
| `shared/litellm-hooks/enforcement_hook.py` | Enforcement callback hook (system prompt injection) |
| `shared/litellm-hooks/prompts/*.md` | Enforcement prompt templates (unrestricted, standard, design-first) |
| `coder-poc/templates/contractor-workspace/main.tf` | Workspace template with AI params |
| `coder-poc/templates/contractor-workspace/build/settings.json` | VS Code settings |
| `coder-poc/templates/contractor-workspace/build/Dockerfile` | Extension installation |
| `shared/key-provisioner/app.py` | Key provisioner microservice |
| `coder-poc/scripts/setup-litellm-keys.sh` | Bootstrap key generation |
| `coder-poc/scripts/generate-ai-key.sh` | Self-service key generation |
| `coder-poc/scripts/manage-service-keys.sh` | CI/agent key management |
| `shared/docs/ROO-CODE-LITELLM.md` | Full setup documentation |
| `shared/docs/KEY-MANAGEMENT.md` | Key management documentation |
| (in workspace) `/home/coder/.config/roo-code/settings.json` | Generated Roo Code config |
| (in workspace) `/home/coder/.config/opencode/opencode.json` | Generated OpenCode config |

## Verification Commands

```bash
# Health check
curl -s http://localhost:4000/health/readiness | jq .status

# List models
curl -s http://localhost:4000/v1/models -H "Authorization: Bearer $LITELLM_MASTER_KEY" | jq '.data[].id'

# Test completion
curl -s http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -d '{"model":"claude-sonnet-4-5","messages":[{"role":"user","content":"say hello"}],"max_tokens":10}'

# Check workspace connectivity
docker exec <workspace> curl -s http://litellm:4000/health/readiness

# Check Roo Code logs
docker exec <workspace> find /home/coder/.local/share/code-server/logs -name '*Roo-Code.log' -exec cat {} \;

# OpenCode diagnostics
docker exec <workspace> /home/coder/.opencode/bin/opencode debug config   # resolved config
docker exec <workspace> /home/coder/.opencode/bin/opencode debug paths    # data/config/cache dirs
docker exec <workspace> /home/coder/.opencode/bin/opencode models litellm # list provider models
docker exec <workspace> /home/coder/.opencode/bin/opencode run "say hi"   # non-interactive test
```
