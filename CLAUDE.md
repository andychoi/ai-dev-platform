# Claude.md
# Coder WebIDE PoC – Claude Operating Context

## Purpose (For Claude)

This file defines what Claude must know first when assisting with this repository.
It intentionally stays high-level and references deeper operational detail in:

- coder-poc/docs/runbook.md – how to operate, configure, manage, and troubleshoot the system

Claude should reference that file instead of duplicating procedures.

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
- LiteLLM (AI proxy) + Key Provisioner (key management) + Enforcement Hook (design-first AI controls)
- Roo Code (AI agent, VS Code) + OpenCode (AI agent, CLI) + Claude Code (AI agent, CLI, Anthropic native)

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

See coder-poc/docs/runbook.md → Environment Setup.

---

### Startup Dependency Rule

- Coder requires PostgreSQL
- SSO requires Authentik

See coder-poc/docs/runbook.md → Service Lifecycle.

---

### Identity Consistency Rule

Any user must exist consistently in:
- Authentik
- Gitea
- Coder

Misalignment causes silent SSO failures.

See coder-poc/docs/runbook.md → User & Identity Management.

---

### Coder Login Type Rule

Users with login_type=password cannot log in via OIDC.

This is the most common SSO failure.

See coder-poc/docs/runbook.md → Troubleshooting → Login & SSO Issues.

---

### Workspace Immutability Rule

Some values are baked at workspace provision time:
- Agent URLs
- Environment variables
- Devcontainer behavior

Changes require:
1. Template push
2. Workspace deletion & recreation

See coder-poc/docs/runbook.md → Troubleshooting → Workspace & Agent Issues.

---

### LiteLLM API Key Rule (AI Critical)

LiteLLM is a **proxy**, not a model provider.
Without `ANTHROPIC_API_KEY` set in `.env`, all Anthropic model calls fail with 401.

Requirements:
- `ANTHROPIC_API_KEY` must be set in `coder-poc/.env` (not empty)
- Workspace keys are auto-provisioned by the key-provisioner service (or manually via `setup-litellm-keys.sh`)
- After changing `.env`, run `docker compose up -d litellm` (not restart)

See shared/docs/ROO-CODE-LITELLM.md for full setup.

---

### Key Provisioner Rule (AI Key Management)

The **key-provisioner** microservice (port 8100) isolates the LiteLLM master key from workspace containers. Workspaces never see the master key — they authenticate with `PROVISIONER_SECRET` and receive scoped virtual keys.

Key facts:
- Workspace keys are auto-provisioned on startup (no manual paste needed)
- Keys are idempotent — workspace restart reuses the same key (alias: `workspace-{workspace_id}`)
- Self-service keys available via `scripts/generate-ai-key.sh`
- Service keys (CI/agent) managed via `scripts/manage-service-keys.sh`
- Every key has structured `metadata.scope` (e.g., `workspace:abc-123`, `user:contractor1`, `ci:frontend-repo`)

See shared/docs/KEY-MANAGEMENT.md and skills/key-management/SKILL.md.

---

### Browser Secure Context Rule (Webview Critical)

Extension webviews (Roo Code, etc.) require `crypto.subtle`, which is only available in **secure contexts** (HTTPS or `localhost`).

Coder runs with TLS on port 7443 (`CODER_TLS_ENABLE=true`). This is required — without HTTPS, `crypto.subtle` is `undefined` and ALL code-server extension webviews render blank.

Self-signed cert is at `coder-poc/certs/coder.crt`. Users must accept the browser warning or install the cert in their OS trust store.

See shared/docs/ROO-CODE-LITELLM.md → Prerequisites → Browser Secure Context.

---

### Roo Code Configuration Rule

Roo Code connects to LiteLLM via OpenAI-compatible API (apiProvider: "openai").
Configuration flows: startup script → auto-import file → Roo Code providerProfiles.

Key facts:
- No VS Code setting to disable "Create Roo Account" prompt (it's internal globalState)
- Auto-import path: `/home/coder/.config/roo-code/settings.json`
- VS Code setting: `roo-cline.autoImportSettingsPath`
- Model names must match LiteLLM config exactly (e.g., `claude-sonnet-4-5`)

See shared/docs/ROO-CODE-LITELLM.md and skills/ai-gateway/SKILL.md.

---

### AI Enforcement Level Rule (Design-First)

The platform enforces AI behavior modes (`unrestricted`, `standard`, `design-first`) server-side via a LiteLLM callback hook. The enforcement level is stored in each virtual key's `metadata.enforcement_level` and cannot be changed from the workspace.

Key facts:
- Enforcement is tamper-proof — it happens at the LiteLLM proxy layer, not in the client
- The level is set at workspace creation via the `ai_enforcement_level` template parameter
- Existing keys are not updated when the template parameter changes — key rotation or workspace recreation is required
- Client-side config (Roo Code `customInstructions`, OpenCode `enforcement.md`) is advisory reinforcement only
- The `design-first` level blocks code output in the AI's first response and requires a design proposal

See shared/docs/AI.md Section 12 and shared/docs/ROO-CODE-LITELLM.md Section 7.

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
- Exposing master API keys to workspaces (use LiteLLM virtual keys via key-provisioner)
- Using Roo Cloud auth when LiteLLM is the provider
- Bypassing key-provisioner to call LiteLLM admin endpoints from workspaces
- Assuming changing the `ai_enforcement_level` template parameter updates existing keys (it does not — key rotation or workspace recreation is required)

---

End of Claude.md