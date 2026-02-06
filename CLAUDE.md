# Claude.md
# Coder WebIDE PoC – Claude Operating Context

## Purpose (For Claude)

This file defines what Claude must know first when assisting with this repository.
It intentionally stays high-level and references deeper operational detail in:

- runbook.md – how to operate, configure, and manage the system
- troubleshooting.md – failure modes, root causes, and fixes

Claude should reference those files instead of duplicating procedures.

---

## System Summary

Coder-based WebIDE PoC enabling contractors to work in browser-based development environments with:

- Strong isolation
- OIDC-based SSO
- No direct access to internal networks

Core components:
- Coder
- Authentik (OIDC)
- Gitea
- MinIO
- PostgreSQL / Redis
- LiteLLM (AI proxy) + Roo Code (AI agent)

---

## Absolute Rules (Non-Negotiable)

### Access URL Rule (OIDC Critical)

Coder must always be accessed via:

https://host.docker.internal:7443

Never use localhost. Never use plain HTTP (extension webviews require HTTPS secure context).

Reason:
- OAuth cookies
- Redirect URI generation
- Agent callback URLs

See runbook.md → Environment Setup.

---

### Startup Dependency Rule

- Coder requires PostgreSQL
- SSO requires Authentik

See runbook.md → Service Lifecycle.

---

### Identity Consistency Rule

Any user must exist consistently in:
- Authentik
- Gitea
- Coder

Misalignment causes silent SSO failures.

See runbook.md → User & Identity Management.

---

### Coder Login Type Rule

Users with login_type=password cannot log in via OIDC.

This is the most common SSO failure.

See troubleshooting.md → Login & SSO Issues.

---

### Workspace Immutability Rule

Some values are baked at workspace provision time:
- Agent URLs
- Environment variables
- Devcontainer behavior

Changes require:
1. Template push
2. Workspace deletion & recreation

See troubleshooting.md → Workspace & Agent Issues.

---

### LiteLLM API Key Rule (AI Critical)

LiteLLM is a **proxy**, not a model provider.
Without `ANTHROPIC_API_KEY` set in `.env`, all Anthropic model calls fail with 401.

Requirements:
- `ANTHROPIC_API_KEY` must be set in `coder-poc/.env` (not empty)
- Each workspace user needs a LiteLLM virtual key (generated via `setup-litellm-keys.sh`)
- After changing `.env`, run `docker compose up -d litellm` (not restart)

See docs/ROO-CODE-LITELLM.md for full setup.

---

### Browser Secure Context Rule (Webview Critical)

Extension webviews (Roo Code, etc.) require `crypto.subtle`, which is only available in **secure contexts** (HTTPS or `localhost`).

Coder runs with TLS on port 7443 (`CODER_TLS_ENABLE=true`). This is required — without HTTPS, `crypto.subtle` is `undefined` and ALL code-server extension webviews render blank.

Self-signed cert is at `coder-poc/certs/coder.crt`. Users must accept the browser warning or install the cert in their OS trust store.

See docs/ROO-CODE-LITELLM.md → Prerequisites → Browser Secure Context.

---

### Roo Code Configuration Rule

Roo Code connects to LiteLLM via OpenAI-compatible API (apiProvider: "openai").
Configuration flows: startup script → auto-import file → Roo Code providerProfiles.

Key facts:
- No VS Code setting to disable "Create Roo Account" prompt (it's internal globalState)
- Auto-import path: `/home/coder/.config/roo-code/settings.json`
- VS Code setting: `roo-cline.autoImportSettingsPath`
- Model names must match LiteLLM config exactly (e.g., `claude-sonnet-4-5`)

See docs/ROO-CODE-LITELLM.md and skills/ai-gateway/SKILL.md.

---

## Optimization Priorities for Claude

- Correctness over convenience
- OIDC correctness over shortcuts
- Reproducibility
- Least-privilege access
- Clear PoC vs production separation

---

## Anti-Patterns (Do Not Suggest)

- Using localhost for Coder
- Assuming container restart reloads env vars
- Mixing admin and contractor permission models
- Treating identity systems independently
- Assuming LiteLLM provides models (it's a proxy — needs upstream API keys)
- Exposing master API keys to workspaces (use LiteLLM virtual keys)
- Using Roo Cloud auth when LiteLLM is the provider

---

End of Claude.md