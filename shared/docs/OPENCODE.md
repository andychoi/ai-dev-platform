# OpenCode CLI Setup Guide

This document covers the complete configuration and usage of OpenCode, the terminal-based AI coding agent, within Coder workspaces.

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [Installation](#3-installation)
4. [Configuration](#4-configuration)
5. [Auto-Provisioning](#5-auto-provisioning)
6. [Design-First Enforcement](#6-design-first-enforcement)
7. [Usage](#7-usage)
8. [Debug Commands](#8-debug-commands)
9. [Troubleshooting](#9-troubleshooting)
10. [Verification Checklist](#10-verification-checklist)
11. [Related Docs](#11-related-docs)

---

## 1. Overview

[OpenCode](https://opencode.ai) is a TUI-based (text user interface) AI coding agent that runs in the terminal. It provides an interactive chat interface for AI-assisted development -- reading files, editing code, and executing commands -- without leaving the terminal.

### How It Fits in the Platform

OpenCode is installed in every Coder workspace **alongside Roo Code** (the VS Code extension). Both tools share the same LiteLLM backend and use the same per-user virtual API key. Developers choose their preferred interface:

| Tool | Interface | Best For |
|------|-----------|----------|
| **Roo Code** | VS Code sidebar (GUI) | Visual workflows, webview-dependent tasks |
| **OpenCode** | Terminal (TUI) | SSH sessions, headless work, terminal-native developers |

Both tools receive identical enforcement rules (standard, design-first, unrestricted) and route through the same LiteLLM proxy with the same budget and rate limits.

### Workspace Parameter Options

When creating a workspace, the "AI Coding Agent" parameter controls which tools are configured:

| Option | Value | What Gets Configured |
|--------|-------|---------------------|
| Roo Code + OpenCode (Recommended) | `both` | Both Roo Code and OpenCode |
| Roo Code Only | `roo-code` | Roo Code extension only |
| OpenCode CLI Only | `opencode` | OpenCode CLI only |
| None | `none` | No AI tools configured |

---

## 2. Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  Coder Workspace (Terminal)                                      │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  OpenCode CLI (TUI)                                        │  │
│  │  ┌──────────────────────────────────────────────────────┐  │  │
│  │  │  provider: "litellm"                                  │  │  │
│  │  │  npm: @ai-sdk/openai-compatible                       │  │  │
│  │  │  baseURL: http://litellm:4000/v1                      │  │  │
│  │  │  apiKey: <per-user virtual key>                        │  │  │
│  │  │  model: litellm/claude-sonnet-4-5                     │  │  │
│  │  └───────────────────────┬──────────────────────────────┘  │  │
│  └───────────────────────────┼────────────────────────────────┘  │
│                               │ OpenAI-compatible API calls       │
│                               ▼                                   │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  LiteLLM Proxy (port 4000)                                 │  │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────────────────┐ │  │
│  │  │ Virtual Key │ │  Budget    │ │ Enforcement Hook       │ │  │
│  │  │ Validation  │ │ Enforcement│ │ (system prompt inject) │ │  │
│  │  └────────────┘ └────────────┘ └────────────────────────┘ │  │
│  │  ┌────────────┐ ┌────────────┐                             │  │
│  │  │ Rate Limit │ │  Provider  │                             │  │
│  │  │ (per-user) │ │  Routing   │                             │  │
│  │  └────────────┘ └─────┬──────┘                             │  │
│  └────────────────────────┼───────────────────────────────────┘  │
│                            │                                      │
│              ┌─────────────┼──────────────┐                      │
│              ▼             ▼              ▼                       │
│     ┌──────────────┐ ┌──────────┐ ┌──────────────┐              │
│     │  Anthropic   │ │   AWS    │ │   Future     │              │
│     │  Direct API  │ │ Bedrock  │ │  Providers   │              │
│     └──────────────┘ └──────────┘ └──────────────┘              │
└──────────────────────────────────────────────────────────────────┘
```

### Key Design Points

- **OpenAI-compatible provider** -- OpenCode connects to LiteLLM using the `@ai-sdk/openai-compatible` npm package. LiteLLM exposes an OpenAI-compatible `/v1/chat/completions` endpoint and translates requests to each provider's native format (Anthropic, Bedrock, etc.).
- **Per-user virtual keys** -- Each workspace gets a scoped LiteLLM virtual key with individual budget caps and rate limits. The upstream API keys (Anthropic, AWS) are never exposed to workspace containers.
- **Same backend as Roo Code** -- Both tools hit the same LiteLLM proxy, share the same virtual key, and are subject to the same enforcement rules.

---

## 3. Installation

OpenCode is **pre-installed** in the workspace Docker image. No manual installation is required.

### What the Dockerfile Does

Three things are set up at image build time:

1. **Binary installation** -- The OpenCode installer places the binary at `~/.opencode/bin/opencode`
2. **PATH configuration** -- The binary directory is added to `PATH` via `ENV`
3. **npm package** -- The `@ai-sdk/openai-compatible` SDK is pre-installed in `~/.config/opencode/`

### Dockerfile Snippet

```dockerfile
# OpenCode CLI - terminal-based AI coding agent
# Installed alongside Roo Code so developers can use either GUI or CLI
# The installer places the binary at ~/.opencode/bin/opencode (runs as coder user)
RUN curl -fsSL https://opencode.ai/install | bash
ENV PATH="/home/coder/.opencode/bin:${PATH}"

# Pre-install OpenAI-compatible provider SDK for OpenCode custom providers (LiteLLM)
# Without this, opencode can't load the "litellm" provider defined in opencode.json
RUN cd /home/coder/.config/opencode && npm install @ai-sdk/openai-compatible
```

### Three Things Required (Summary)

| Requirement | Purpose | Installed By |
|-------------|---------|--------------|
| `@ai-sdk/openai-compatible` npm package | Enables custom OpenAI-compatible providers | Dockerfile (build time) |
| `models` section in config | Registers Claude models under the litellm provider | Startup script (runtime) |
| `opencode.json` config file | Defines provider, API key, base URL, model selection | Startup script (runtime) |

Without the `models` section, OpenCode ignores the custom provider and falls back to built-in defaults (GPT models). Without the npm package, OpenCode cannot load the litellm provider at all.

---

## 4. Configuration

### Config File Location

```
/home/coder/.config/opencode/opencode.json
```

This is the global config path. OpenCode also supports project-level config at `./opencode.json` in the project root, but workspace-wide configuration uses the global path.

### Full Configuration Example

```json
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": ["/home/coder/.config/opencode/enforcement.md"],
  "provider": {
    "litellm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "LiteLLM",
      "options": {
        "baseURL": "http://litellm:4000/v1",
        "apiKey": "<per-user-virtual-key>"
      },
      "models": {
        "claude-sonnet-4-5": {
          "name": "Claude Sonnet 4.5"
        },
        "claude-haiku-4-5": {
          "name": "Claude Haiku 4.5"
        },
        "claude-opus-4": {
          "name": "Claude Opus 4"
        }
      }
    }
  },
  "model": "litellm/claude-sonnet-4-5",
  "small_model": "litellm/claude-haiku-4-5"
}
```

### Field Reference

| Field | Description |
|-------|-------------|
| `$schema` | JSON schema for editor autocompletion and validation |
| `instructions` | Array of file paths containing system instructions (enforcement rules). Omitted when enforcement level is `unrestricted`. |
| `provider.litellm` | Custom provider definition. The key `litellm` becomes the provider ID used in `model` and `small_model`. |
| `provider.litellm.npm` | npm package that implements the provider SDK. Must be `@ai-sdk/openai-compatible` for LiteLLM. |
| `provider.litellm.name` | Human-readable display name shown in the TUI. |
| `provider.litellm.options.baseURL` | LiteLLM proxy endpoint. Uses Docker service name `litellm` (resolved within the Docker network). |
| `provider.litellm.options.apiKey` | Per-user virtual key issued by the key-provisioner. |
| `provider.litellm.models` | Map of model IDs to display metadata. **Required** -- without this section, OpenCode ignores the provider. |
| `model` | Default model for chat. Format: `<provider-id>/<model-id>` (e.g., `litellm/claude-sonnet-4-5`). |
| `small_model` | Model used for lighter tasks (summaries, quick lookups). Typically the faster/cheaper model. |

### Model Name Mapping

The model IDs in `opencode.json` must match the `model_name` entries in LiteLLM's `config.yaml`:

| OpenCode model field | LiteLLM model_name | Upstream provider |
|---------------------|-------------------|-------------------|
| `litellm/claude-sonnet-4-5` | `claude-sonnet-4-5` | Anthropic (with Bedrock failover) |
| `litellm/claude-haiku-4-5` | `claude-haiku-4-5` | Anthropic (with Bedrock failover) |
| `litellm/claude-opus-4` | `claude-opus-4` | Anthropic only |

---

## 5. Auto-Provisioning

OpenCode configuration is fully automated. Developers do not need to manually create config files or obtain API keys.

### How It Works

```
1. Workspace creation
   └─ User selects AI agent (both/opencode) + model + enforcement level
                              ↓
2. Startup script runs
   └─ If no API key provided, calls key-provisioner to auto-provision
                              ↓
3. Key-provisioner (port 8100)
   └─ Checks alias "workspace-{workspace_id}"
   └─ If exists → returns existing key (idempotent on restart)
   └─ If new → creates key via LiteLLM ($10 budget, 60 RPM)
                              ↓
4. Startup script generates config
   └─ /home/coder/.config/opencode/opencode.json  (provider + models + key)
   └─ /home/coder/.config/opencode/enforcement.md  (if standard or design-first)
                              ↓
5. OpenCode ready
   └─ Run "opencode" in terminal → uses LiteLLM backend
```

### What the Startup Script Does

1. Checks if `AI_ASSISTANT` is `opencode` or `both`
2. Verifies the binary exists at `/home/coder/.opencode/bin/opencode` (uses `[ -x path ]`, not `command -v`, to avoid PATH issues)
3. Creates the `~/.config/opencode/` directory
4. If enforcement level is `standard` or `design-first`, writes `enforcement.md` with the corresponding instructions
5. Writes `opencode.json` with the LiteLLM provider, virtual key, selected model, and (if applicable) the `instructions` array pointing to `enforcement.md`
6. Adds `~/.opencode/bin` to PATH in `~/.bashrc`

### Environment Variables

The startup script also exports these variables in `~/.bashrc`, available to all terminal sessions:

```bash
export PATH="/home/coder/.opencode/bin:$PATH"
export AI_GATEWAY_URL="http://litellm:4000"
export OPENAI_API_BASE="http://litellm:4000/v1"
export OPENAI_API_KEY="<per-user-key>"
export AI_MODEL="claude-sonnet-4-5"
```

---

## 6. Design-First Enforcement

The enforcement layer controls how OpenCode approaches development tasks. It operates at **two levels** simultaneously, ensuring rules cannot be bypassed by the client.

### Enforcement Levels

| Level | Behavior | Use Case |
|-------|----------|----------|
| `unrestricted` | No system prompt injection, no instructions file. Original tool behavior. | Quick tasks, experienced developers |
| `standard` (default) | Lightweight 6-point reasoning checklist. Think before coding. | Daily development |
| `design-first` | Mandatory design proposal before any code. Must await confirmation. | Complex features, new contractors |

### Server-Side Enforcement (LiteLLM Hook)

The `EnforcementHook` in `litellm/enforcement_hook.py` is a LiteLLM callback that runs on **every** API call:

1. Reads `enforcement_level` from the virtual key's metadata
2. Loads the corresponding prompt from `/app/prompts/{level}.md`
3. Prepends it as a system message to the request

This is tamper-proof -- workspaces cannot modify or bypass the server-side injection. The hook applies identically to both Roo Code and OpenCode since both use the same LiteLLM endpoint.

Prompt files use mtime-based caching. Edits to prompt files take effect on the next API call without restarting LiteLLM.

### Client-Side Enforcement (OpenCode Instructions)

For `standard` and `design-first` levels, the startup script writes an `enforcement.md` file and references it in the config:

**File:** `/home/coder/.config/opencode/enforcement.md`

**Config reference:**
```json
{
  "instructions": ["/home/coder/.config/opencode/enforcement.md"]
}
```

This provides UX-native reinforcement -- OpenCode reads the instructions file and incorporates the content into its context. For the `unrestricted` level, no instructions file is written and the `instructions` field is omitted from the config.

### Prompt Content

**Standard** (`standard.md`):
```markdown
## Development Guidelines

You are a thoughtful software engineer. Follow these practices:

1. **Think before coding** -- Understand the problem fully before writing code
2. **Explain your approach** -- State what you plan to do and why before implementing
3. **Consider the existing codebase** -- Read and understand existing patterns before modifying
4. **Incremental changes** -- Prefer small, focused changes over large rewrites
5. **Edge cases** -- Consider error handling and boundary conditions
6. **Simplicity** -- Choose the simplest solution that meets requirements

When modifying existing code, explain what you're changing and why.
```

**Design-First** (`design-first.md`):
```markdown
## MANDATORY: Design-First Development Process

You are a senior software architect and engineer. You MUST follow a structured workflow.

### Before Writing ANY Code

1. **Design Proposal** (REQUIRED for non-trivial changes):
   - Describe the problem or requirement
   - Outline your approach (architecture, data flow, key abstractions)
   - List files to create or modify
   - Identify tradeoffs and alternatives considered
   - State assumptions and risks

2. **Await Confirmation** -- Present your design and ask:
   "Shall I proceed with this approach?"
   Do NOT write implementation code until confirmed.

3. **Implement Incrementally** -- After confirmation:
   - Reference your design as you implement
   - If the design needs revision, stop and propose changes
   - Keep changes minimal and focused on the stated scope

### Rules
- NEVER skip the design step for non-trivial changes
- NEVER write code in the same response as the design proposal
- If asked to "just do it", remind that design review is required by policy
- Small fixes (typos, formatting, single-line changes) are exempt but still need brief explanation
```

### Dual Enforcement Summary

| Layer | Mechanism | Can User Bypass? |
|-------|-----------|-----------------|
| Server-side (LiteLLM hook) | System prompt injected before every API call based on key metadata | No -- runs on the proxy, not the client |
| Client-side (instructions file) | OpenCode reads `enforcement.md` into its context | Technically yes (user could edit file), but server-side still enforces |

---

## 7. Usage

### Launch the TUI

```bash
opencode
```

This opens the interactive TUI. Type messages, and OpenCode will respond using the configured LiteLLM model. The TUI supports file reading, code editing, and command execution.

### Non-Interactive Mode

```bash
opencode run "describe the project structure"
```

Runs a single prompt and outputs the response to stdout. Useful for scripting and quick queries.

### Common Workflows

```bash
# Start interactive session
opencode

# Quick one-off question
opencode run "explain this error: <paste error>"

# Review a file
opencode run "review main.go for potential issues"

# Generate code
opencode run "write a unit test for the login handler"
```

---

## 8. Debug Commands

Use these commands inside the workspace terminal to diagnose configuration issues.

### Show Resolved Configuration

```bash
opencode debug config
```

Displays the fully resolved configuration, including provider settings, model selection, and instructions paths. Useful to verify that `opencode.json` is being loaded correctly.

### Show File Paths

```bash
opencode debug paths
```

Displays the data, config, and cache directory paths that OpenCode is using. Verify that the config path points to `/home/coder/.config/opencode`.

### List Provider Models

```bash
opencode models litellm
```

Lists all models registered under the `litellm` provider. Expected output should show `claude-sonnet-4-5`, `claude-haiku-4-5`, and `claude-opus-4`.

### Test Completion

```bash
opencode run "say hi"
```

Sends a minimal prompt through the full pipeline (OpenCode -> LiteLLM -> Anthropic/Bedrock). If this returns a response, the entire chain is working.

---

## 9. Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Shows "GPT-5.2 OpenAI" instead of Claude models | `models` section missing from `opencode.json`, or `@ai-sdk/openai-compatible` npm package not installed | Add the `models` map to the provider config. Run `cd ~/.config/opencode && npm install @ai-sdk/openai-compatible` |
| "Provider not found: litellm" | `@ai-sdk/openai-compatible` npm package not installed in `~/.config/opencode/` | Run `cd ~/.config/opencode && npm install @ai-sdk/openai-compatible` |
| "incorrect api key" or authentication errors | Config file `opencode.json` was never generated (startup script did not run or failed) | Check startup log: `cat /tmp/coder-startup-script.log`. Look for "OpenCode CLI not found" messages. |
| Config not generated at startup | Binary existence check failed. Earlier versions used `command -v opencode` which fails if PATH does not include `~/.opencode/bin/` at startup time. | Verify the template uses `[ -x /home/coder/.opencode/bin/opencode ]` instead of `command -v opencode`. Update template and recreate workspace. |
| "command not found: opencode" | PATH does not include `~/.opencode/bin/`. The binary is installed but not on the shell's search path. | Run `export PATH="/home/coder/.opencode/bin:$PATH"` or start a new shell session (the startup script adds this to `~/.bashrc`). |
| OpenCode connects but model calls fail with 401 | LiteLLM has no upstream API key (`ANTHROPIC_API_KEY` empty in `.env`) | Set `ANTHROPIC_API_KEY` in `coder-poc/.env` and run `docker compose up -d litellm` (not restart). |
| "Budget exceeded" (402 error) | Per-user virtual key budget exhausted | Admin can increase budget via LiteLLM admin API. See [ROO-CODE-LITELLM.md](ROO-CODE-LITELLM.md) Section 9. |
| Enforcement instructions not applied | `enforcement.md` not written (enforcement level is `unrestricted`), or `instructions` field missing from config | Check enforcement level: `cat ~/.config/opencode/opencode.json | jq .instructions`. Server-side enforcement still applies regardless. |

### Checking Startup Logs

The Coder workspace startup script logs all AI configuration steps:

```bash
cat /tmp/coder-startup-script.log | grep -i opencode
```

Expected output for a successful configuration:

```
Configuring OpenCode CLI with LiteLLM proxy...
OpenCode configured: model=litellm/claude-sonnet-4-5 enforcement=standard
```

---

## 10. Verification Checklist

Run these commands inside the workspace terminal to verify OpenCode is correctly configured.

### 1. Binary Exists and Is on PATH

```bash
which opencode
# Expected: /home/coder/.opencode/bin/opencode

opencode --version
```

### 2. Config File Exists

```bash
cat ~/.config/opencode/opencode.json | python3 -m json.tool
# Expected: valid JSON with litellm provider, models, and apiKey
```

### 3. npm Package Installed

```bash
ls ~/.config/opencode/node_modules/@ai-sdk/openai-compatible/
# Expected: package contents (index.js, package.json, etc.)
```

### 4. Provider Models Listed

```bash
opencode models litellm
# Expected: claude-sonnet-4-5, claude-haiku-4-5, claude-opus-4
```

### 5. Enforcement Instructions (if applicable)

```bash
# Only present for standard or design-first levels
cat ~/.config/opencode/enforcement.md
# Expected: development guidelines or design-first rules

# Verify config references it
cat ~/.config/opencode/opencode.json | python3 -c "
import sys, json
cfg = json.load(sys.stdin)
print('instructions:', cfg.get('instructions', 'NOT SET'))
"
```

### 6. Test Completion End-to-End

```bash
opencode run "say hi"
# Expected: a response from Claude via LiteLLM
```

### 7. Full Debug Dump

```bash
opencode debug config
opencode debug paths
```

---

## 11. Related Docs

| Document | Description |
|----------|-------------|
| [ROO-CODE-LITELLM.md](ROO-CODE-LITELLM.md) | Roo Code + LiteLLM setup (includes shared architecture, key management, enforcement) |
| [KEY-MANAGEMENT.md](KEY-MANAGEMENT.md) | Full key management documentation (key-provisioner, self-service keys, service keys) |
| [AI.md](AI.md) | AI platform architecture overview (enforcement hook details in Section 12) |

### Source Files

| File | Purpose |
|------|---------|
| `templates/contractor-workspace/build/Dockerfile` | OpenCode binary and npm package installation |
| `templates/contractor-workspace/main.tf` | Startup script (config generation, key provisioning, enforcement) |
| `litellm/enforcement_hook.py` | Server-side enforcement hook (system prompt injection) |
| `litellm/prompts/standard.md` | Standard enforcement prompt |
| `litellm/prompts/design-first.md` | Design-first enforcement prompt |
| `litellm/config.yaml` | LiteLLM model routing and proxy settings |

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-06 | Platform Team | Initial standalone OpenCode documentation |
