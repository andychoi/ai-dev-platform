# Claude Code CLI + LiteLLM Integration

This document describes how Claude Code CLI is integrated into the Coder WebIDE platform using LiteLLM as the API proxy.

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [How It Works](#3-how-it-works)
4. [Prerequisites](#4-prerequisites)
5. [Workspace Configuration](#5-workspace-configuration)
6. [Environment Variables](#6-environment-variables)
7. [Enforcement & Guardrails](#7-enforcement--guardrails)
8. [Usage](#8-usage)
9. [Troubleshooting](#9-troubleshooting)
10. [Comparison: Claude Code vs Roo Code vs OpenCode](#10-comparison)

---

## 1. Overview

[Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) is Anthropic's official terminal-based AI coding agent. Unlike Roo Code (VS Code extension) and OpenCode (third-party CLI), Claude Code uses the **native Anthropic Messages API** rather than an OpenAI-compatible endpoint.

The platform integrates Claude Code CLI through LiteLLM's **Anthropic pass-through endpoint** (`/anthropic/v1/messages`), which:
- Accepts native Anthropic SDK format (no protocol translation needed)
- Applies virtual key authentication, budget tracking, and rate limiting
- Fires enforcement hooks and content guardrails
- Routes to the configured Anthropic provider

This gives Claude Code CLI the same governance controls as Roo Code and OpenCode — per-user budgets, design-first enforcement, PII/secret guardrails, and audit logging via Langfuse.

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     WORKSPACE CONTAINER                          │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  Roo Code    │  │  OpenCode    │  │  Claude Code │          │
│  │  (VS Code)   │  │  (CLI)       │  │  (CLI)       │          │
│  │              │  │              │  │              │          │
│  │  OpenAI API  │  │  OpenAI API  │  │ Anthropic API│          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                 │                  │                   │
│         ▼                 ▼                  ▼                   │
│  litellm:4000/v1   litellm:4000/v1   litellm:4000/anthropic    │
│  (OpenAI-compat)   (OpenAI-compat)   (Anthropic pass-through)  │
└─────────┬─────────────────┬──────────────────┬──────────────────┘
          │                 │                  │
          └─────────────────┼──────────────────┘
                            │
                            ▼
                  ┌─────────────────┐
                  │    LiteLLM      │
                  │   (Port 4000)   │
                  │                 │
                  │  • Virtual key  │
                  │    auth         │
                  │  • Enforcement  │
                  │    hook         │
                  │  • Guardrails   │
                  │    hook         │
                  │  • Budget &     │
                  │    rate limits  │
                  │  • Langfuse     │
                  │    logging      │
                  └────────┬────────┘
                           │
                  ┌────────┴────────┐
                  │  Anthropic API  │
                  │  (upstream)     │
                  └─────────────────┘
```

### Key Difference from Roo Code / OpenCode

| Agent | API Protocol | LiteLLM Endpoint | Header |
|-------|-------------|------------------|--------|
| Roo Code | OpenAI-compatible | `/v1/chat/completions` | `Authorization: Bearer <key>` |
| OpenCode | OpenAI-compatible | `/v1/chat/completions` | `Authorization: Bearer <key>` |
| **Claude Code** | **Anthropic native** | **`/anthropic/v1/messages`** | **`x-api-key: <key>`** |

All three use the same LiteLLM virtual key. The difference is the API format — Claude Code speaks Anthropic natively, while Roo Code and OpenCode use the OpenAI-compatible translation layer.

---

## 3. How It Works

### Request Flow

1. **Claude Code CLI** sends a request to `${ANTHROPIC_BASE_URL}/v1/messages` using the Anthropic SDK format
2. This resolves to `http://litellm:4000/anthropic/v1/messages`
3. **LiteLLM** receives the request on its Anthropic pass-through endpoint:
   - Extracts the virtual key from the `x-api-key` header
   - Validates against the virtual key database (budget, rate limits, expiry)
   - Fires the **enforcement hook** (reads `enforcement_level` from key metadata, injects system prompt)
   - Fires the **guardrails hook** (scans for PII, financial data, secrets)
   - Routes to the Anthropic upstream provider
4. **Anthropic API** processes the request and returns a response
5. **LiteLLM** logs the request metadata to PostgreSQL and Langfuse, then returns the response to Claude Code CLI

### Model Name Resolution

Claude Code CLI sends Anthropic model IDs (e.g., `claude-sonnet-4-5-20250929`). LiteLLM maps these to its `model_list` entries by matching against `litellm_params.model` (which is prefixed with `anthropic/`):

```yaml
# LiteLLM config.yaml
- model_name: claude-sonnet-4-5
  litellm_params:
    model: anthropic/claude-sonnet-4-5-20250929  # ← matches Claude Code's model ID
```

---

## 4. Prerequisites

### Platform Requirements

- LiteLLM running with `ANTHROPIC_API_KEY` set in `.env` (Anthropic direct API required — Bedrock pass-through is not supported for the Anthropic endpoint)
- Key-provisioner service running (port 8100)
- Docker image built with Claude Code CLI installed (`npm install -g @anthropic-ai/claude-code`)

### Workspace Requirements

- `ai_assistant` parameter set to `claude-code` or `all`
- Virtual key auto-provisioned (or manually set via `litellm_api_key` parameter)

### Network Requirements

Claude Code CLI in the workspace must be able to reach `litellm:4000` on the Docker network. This is the same requirement as Roo Code and OpenCode — no additional network configuration needed.

---

## 5. Workspace Configuration

### Template Parameter Selection

When creating a workspace, select one of these `AI Coding Agent` options:

| Option | Agents Configured |
|--------|------------------|
| All Agents | Roo Code + OpenCode + Claude Code |
| Claude Code CLI | Claude Code only |
| Roo Code + OpenCode | Roo Code + OpenCode (no Claude Code) |
| Roo Code Only | Roo Code only |
| OpenCode CLI Only | OpenCode only |

### What Gets Configured

When `claude-code` or `all` is selected, the startup script:

1. **Writes `~/.claude/settings.json`** — Pre-configured tool permissions (file operations allowed, network tools denied)
2. **Exports `ANTHROPIC_BASE_URL`** — Points to LiteLLM's Anthropic pass-through (`http://litellm:4000/anthropic`)
3. **Exports `ANTHROPIC_API_KEY`** — Set to the workspace's auto-provisioned virtual key

---

## 6. Environment Variables

These are set in `~/.bashrc` when Claude Code is enabled:

| Variable | Value | Purpose |
|----------|-------|---------|
| `ANTHROPIC_BASE_URL` | `http://litellm:4000/anthropic` | Routes Claude Code CLI to LiteLLM's Anthropic pass-through |
| `ANTHROPIC_API_KEY` | `<workspace-virtual-key>` | Virtual key for auth, budget, and rate limiting |

### How It Differs from Roo Code / OpenCode

| Variable | Claude Code | Roo Code / OpenCode |
|----------|------------|---------------------|
| Base URL | `ANTHROPIC_BASE_URL` (Anthropic SDK) | `openAiBaseUrl` / `baseURL` (OpenAI SDK) |
| API Key | `ANTHROPIC_API_KEY` (`x-api-key` header) | `openAiApiKey` / `apiKey` (`Authorization: Bearer` header) |
| Endpoint | `/anthropic/v1/messages` | `/v1/chat/completions` |

All three use the **same virtual key** — LiteLLM accepts both `x-api-key` and `Authorization: Bearer` headers.

---

## 7. Enforcement & Guardrails

### Design-First Enforcement — Skipped for Claude Code

Claude Code CLI is a **plan-first agent by design**. It already reasons before coding, asks for user confirmation before file operations, and follows structured workflows natively. The platform's enforcement hook (`design-first`, `standard`) was built to replicate this behavior in other agents (Roo Code, OpenCode). Applying it back to Claude Code is redundant.

When `ai_assistant=claude-code`, the startup script automatically sets `enforcement_level=unrestricted` for the virtual key, bypassing the enforcement hook. This means:

| LiteLLM Layer | Active for Claude Code? | Reason |
|---|---|---|
| Design-first enforcement | **No** | Claude Code already plans first natively |
| Standard enforcement | **No** | Claude Code already reasons step-by-step |
| Content guardrails (PII/secrets) | **Yes** | Agent-agnostic — catches sensitive data in prompts |
| Budget & rate limits | **Yes** | Per-user cost control |
| Audit logging (Langfuse) | **Yes** | Usage tracking and compliance |

> **Note:** When `ai_assistant=all` (Claude Code + Roo Code + OpenCode sharing the same key), the user-selected enforcement level is preserved because Roo Code and OpenCode still benefit from it.

### Content Guardrails — Still Active

The guardrails hook scans all messages for PII, financial data, and secrets. This applies to Claude Code CLI requests through the Anthropic pass-through endpoint. Claude Code has no built-in PII scanner, so this server-side layer remains valuable.

### Client-Side Permissions

The `~/.claude/settings.json` file pre-configures Claude Code's tool permissions:

**Allowed:**
- File operations (Read, Write, Edit)
- Git commands (log, diff, status)
- Development tools (npm, npx, node)
- Search tools (ls, cat, find, grep)

**Denied:**
- Network tools (curl, wget, ssh, scp) — prevents data exfiltration

This is advisory reinforcement — the content guardrails hook and network egress firewall provide the actual security boundary.

---

## 8. Usage

### Starting Claude Code CLI

```bash
# Open terminal in workspace (Web Terminal or code-server terminal)
claude

# Claude Code CLI starts with interactive REPL
# ANTHROPIC_BASE_URL and ANTHROPIC_API_KEY are already set
```

### Common Commands

```bash
# Start Claude Code
claude

# Start with a specific task
claude "Review the code in src/ for security issues"

# Start in a specific directory
cd /home/coder/workspace/my-project && claude

# Check that environment is configured
echo $ANTHROPIC_BASE_URL    # Should show http://litellm:4000/anthropic
echo $ANTHROPIC_API_KEY     # Should show sk-... (virtual key)
```

### Verifying the Connection

```bash
# Quick test: send a minimal request through the Anthropic pass-through
curl -s http://litellm:4000/anthropic/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "content-type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "claude-sonnet-4-5-20250929",
    "max_tokens": 50,
    "messages": [{"role": "user", "content": "Say hello"}]
  }'
```

### Checking Usage

```bash
# Same as other agents — virtual key is shared
ai-usage
```

---

## 9. Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| `claude: command not found` | CLI not installed | Rebuild workspace image: `docker build -t nodejs-workspace:latest ./build` |
| `401 Unauthorized` | Invalid or missing API key | Check `echo $ANTHROPIC_API_KEY` — re-provision via `generate-ai-key.sh` |
| `Connection refused` | LiteLLM not running | Check `curl http://litellm:4000/health` from workspace |
| `Model not found` | Model name mismatch | Verify the model exists in `litellm/config.yaml` model_list |
| `Budget exceeded` | User hit spending limit | Check with `ai-usage`, ask admin to reset |
| Claude Code ignores enforcement | Key metadata missing enforcement_level | Recreate workspace or rotate key via key-provisioner |

### Diagnostic Commands

```bash
# Check Claude Code CLI is installed
which claude
claude --version

# Check environment variables
env | grep ANTHROPIC

# Check LiteLLM health
curl -s http://litellm:4000/health

# Check LiteLLM Anthropic endpoint
curl -s http://litellm:4000/anthropic/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "content-type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model":"claude-sonnet-4-5-20250929","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}'

# Check virtual key info
curl -s http://litellm:4000/key/info \
  -H "Authorization: Bearer $ANTHROPIC_API_KEY" | python3 -m json.tool

# Check LiteLLM logs for Anthropic pass-through
docker logs litellm 2>&1 | grep -i anthropic | tail -20
```

### ANTHROPIC_API_KEY vs LiteLLM Virtual Key

The workspace `ANTHROPIC_API_KEY` is a **LiteLLM virtual key** (starts with `sk-`), NOT a real Anthropic API key. This is by design:
- The real Anthropic API key is configured in LiteLLM's `.env` file on the host
- Workspaces never see the real key
- Virtual keys provide per-user budget, rate limiting, and audit logging

---

## 10. Comparison

### Claude Code vs Roo Code vs OpenCode

| Feature | Roo Code | OpenCode | Claude Code |
|---------|----------|----------|-------------|
| **Interface** | VS Code sidebar | Terminal REPL | Terminal REPL |
| **API Protocol** | OpenAI-compatible | OpenAI-compatible | Anthropic native |
| **Provider** | Any (via LiteLLM) | Any (via LiteLLM) | Anthropic only |
| **Agentic Coding** | Yes | Yes | Yes |
| **File Operations** | Yes (VS Code) | Yes (terminal) | Yes (terminal) |
| **Terminal Commands** | Yes | Yes | Yes |
| **Extended Thinking** | Depends on model | Depends on model | Native support |
| **Tool Use** | Custom tools | Custom tools | Built-in tools |
| **Multi-file Editing** | Yes | Yes | Yes |
| **Enforcement** | Server-side + client | Server-side + client | Server-side + client permissions |
| **Budget Tracking** | Via virtual key | Via virtual key | Via virtual key |

### When to Use Which

| Use Case | Recommended Agent |
|----------|------------------|
| Visual IDE workflow with sidebar chat | Roo Code |
| Terminal-native development | Claude Code or OpenCode |
| Anthropic-specific features (extended thinking) | Claude Code |
| Quick prototyping in terminal | OpenCode or Claude Code |
| Multiple provider support (future) | Roo Code or OpenCode |

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-08 | Platform Team | Initial version — Claude Code CLI + LiteLLM integration |
