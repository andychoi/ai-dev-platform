---
name: ai-gateway
description: Roo Code AI agent + LiteLLM proxy - configuration, troubleshooting, model management, virtual keys
---

# AI Gateway Skill (Roo Code + LiteLLM)

## Overview

AI capabilities in Coder workspaces are provided by **Roo Code** (VS Code extension) connected to **LiteLLM** (OpenAI-compatible proxy). LiteLLM handles authentication, routing, budgeting, and audit logging for upstream AI providers (Anthropic, AWS Bedrock).

> Full documentation: `coder-poc/docs/ROO-CODE-LITELLM.md`

## Architecture

```
Workspace (code-server)
  └─ Roo Code Extension
     └─ OpenAI-compatible API (apiProvider: "openai")
        └─ LiteLLM Proxy (litellm:4000)
           ├─ Virtual Key Validation
           ├─ Budget Enforcement ($10/user default)
           ├─ Rate Limiting (60 RPM default)
           └─ Provider Routing
              ├─ Anthropic Direct API (ANTHROPIC_API_KEY)
              └─ AWS Bedrock (AWS credentials)
```

## Access

| Endpoint | URL (from host) | URL (from workspace) |
|----------|-----------------|---------------------|
| LiteLLM Health | http://localhost:4000/health/readiness | http://litellm:4000/health/readiness |
| LiteLLM Models | http://localhost:4000/v1/models | http://litellm:4000/v1/models |
| LiteLLM Admin | http://localhost:4000/ui | N/A |
| Chat Completions | http://localhost:4000/v1/chat/completions | http://litellm:4000/v1/chat/completions |

## Available Models

| Model Name (LiteLLM) | Provider | Use Case |
|----------------------|----------|----------|
| `claude-sonnet-4-5` | Anthropic | Balanced (default) |
| `claude-haiku-4-5` | Anthropic | Fast / cost-efficient |
| `claude-opus-4` | Anthropic | Advanced reasoning |
| `bedrock-claude-sonnet` | AWS Bedrock | Alternative provider |
| `bedrock-claude-haiku` | AWS Bedrock | Alternative provider |

## Critical Requirements

### ANTHROPIC_API_KEY Must Be Set

LiteLLM is a **proxy**, not a model provider. Without `ANTHROPIC_API_KEY` in `.env`, all Anthropic model calls fail with `401: x-api-key header is required`.

```bash
# Check if set (should NOT be empty)
grep "^ANTHROPIC_API_KEY=" coder-poc/.env

# Set it
# Edit coder-poc/.env and add your key, then:
cd coder-poc && docker compose up -d litellm
```

### Virtual Keys Required per User

Each workspace user needs a LiteLLM virtual key. Generate keys:

```bash
# Run the setup script
cd coder-poc && ./scripts/setup-litellm-keys.sh

# Or generate individually
curl http://localhost:4000/key/generate \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"user_id":"contractor1","max_budget":10.00,"rpm_limit":60}'
```

## Roo Code Configuration

### How It Works

1. User provides their LiteLLM virtual key as workspace parameter
2. Startup script generates `/home/coder/.config/roo-code/settings.json`
3. VS Code setting `roo-cline.autoImportSettingsPath` points to that file
4. Roo Code auto-imports the provider profile on activation

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
| 401 auth error | `ANTHROPIC_API_KEY` empty | Set key in `.env`, `docker compose up -d litellm` |
| LiteLLM unhealthy | PostgreSQL not ready or config error | Check `docker compose logs litellm` |
| Roo Code blank panel | Insecure context (`crypto.subtle` undefined) | Enable HTTPS on Coder, or launch Chrome with `--unsafely-treat-insecure-origin-as-secure="http://host.docker.internal:7080"` |
| Auto-import failed | Config file missing or wrong path | Check file exists and `autoImportSettingsPath` is set |
| Model not found | Model name mismatch | Match `openAiModelId` with LiteLLM `model_name` |
| Budget exceeded (402) | User spent their budget | Increase via `/budget/update` API |
| No response from Roo Code | LiteLLM unreachable from workspace | Check network: `curl http://litellm:4000/health/readiness` |

## Key File Locations

| File | Purpose |
|------|---------|
| `coder-poc/.env` | API keys and master key |
| `coder-poc/litellm/config.yaml` | Model definitions and settings |
| `coder-poc/templates/contractor-workspace/main.tf` | Workspace template with AI params |
| `coder-poc/templates/contractor-workspace/build/settings.json` | VS Code settings |
| `coder-poc/templates/contractor-workspace/build/Dockerfile` | Extension installation |
| `coder-poc/scripts/setup-litellm-keys.sh` | Virtual key generation |
| `coder-poc/docs/ROO-CODE-LITELLM.md` | Full setup documentation |
| (in workspace) `/home/coder/.config/roo-code/settings.json` | Generated Roo Code config |

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
```
