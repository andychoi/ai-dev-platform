# Claude.md
# Coder WebIDE PoC – Claude Operating Context

## Purpose (For Claude)

This file defines what Claude must know first when assisting with this repository.
It intentionally stays high-level and references deeper operational detail in the documentation map below.

Claude should reference those files instead of duplicating procedures.

---

## Documentation Map

Claude should look up details in these files rather than relying on this summary alone.

### PoC Operations (`coder-poc/docs/`)

| Document | When to Reference |
|----------|-------------------|
| [runbook.md](coder-poc/docs/runbook.md) | Service lifecycle, troubleshooting, environment setup |
| [ADMIN-HOWTO.md](coder-poc/docs/ADMIN-HOWTO.md) | Template management, TLS, AI models, user management |
| [DOCKER-DEV.md](coder-poc/docs/DOCKER-DEV.md) | Docker-in-workspace options, DinD, security analysis |
| [HTTPS.md](coder-poc/docs/HTTPS.md) | TLS architecture decisions, Traefik evaluation, traffic flows |
| [INFRA.md](coder-poc/docs/INFRA.md) | Infrastructure details, service configuration |
| [AUTHENTIK-SSO.md](coder-poc/docs/AUTHENTIK-SSO.md) | OIDC provider setup, redirect URIs, user provisioning |

### Platform-Wide (`shared/docs/`)

| Document | When to Reference |
|----------|-------------------|
| [AI.md](shared/docs/AI.md) | AI integration architecture, enforcement levels, disabled features |
| [KEY-MANAGEMENT.md](shared/docs/KEY-MANAGEMENT.md) | Key provisioner, virtual key taxonomy, scoped budgets |
| [ROO-CODE-LITELLM.md](shared/docs/ROO-CODE-LITELLM.md) | Roo Code + LiteLLM setup, config format, troubleshooting |
| [CLAUDE-CODE-LITELLM.md](shared/docs/CLAUDE-CODE-LITELLM.md) | Claude Code CLI integration with LiteLLM pass-through |
| [OPENCODE.md](shared/docs/OPENCODE.md) | OpenCode CLI agent setup |
| [SECURITY.md](shared/docs/SECURITY.md) | Security architecture, network isolation, threat model |
| [GUARDRAILS.md](shared/docs/GUARDRAILS.md) | Content guardrails (PII/financial/secret detection) |
| [RBAC-ACCESS-CONTROL.md](shared/docs/RBAC-ACCESS-CONTROL.md) | Roles, permissions, service access matrix |
| [DATABASE.md](shared/docs/DATABASE.md) | Developer database provisioning (DevDB) |
| [FAQ.md](shared/docs/FAQ.md) | End-user frequently asked questions |

### AWS Production (`aws-production/`)

| Document | When to Reference |
|----------|-------------------|
| [PRODUCTION-PLAN.md](aws-production/PRODUCTION-PLAN.md) | AWS migration: ECS Fargate, RDS, ALB, Azure AD OIDC |
| `terraform/` | IaC modules (VPC, ECS, RDS, ALB, IAM, S3, Secrets, ElastiCache, EFS) |

### Claude Skills (`.claude/skills/`)

| Skill | Domain |
|-------|--------|
| `coder/SKILL.md` | Coder platform, templates, users, OIDC |
| `poc-services/SKILL.md` | All services, ports, credentials, Docker networking |
| `ai-gateway/SKILL.md` | Roo Code + LiteLLM + OpenCode AI integration |
| `key-management/SKILL.md` | Key provisioner, auto-provisioning, service keys |
| `authentik-sso/SKILL.md` | Authentik identity provider, SSO |
| `gitea/SKILL.md` | Git server, permissions, OIDC |
| `minio/SKILL.md` | S3-compatible storage |

---

## System Summary

Coder-based WebIDE PoC enabling contractors to work in browser-based development environments with:

- Strong isolation
- OIDC-based SSO
- No direct access to internal networks

Core components:
- Coder (HTTPS on port 7443, native TLS)
- Authentik (OIDC identity provider)
- Gitea (Git server) + MinIO (S3 storage)
- PostgreSQL / Redis
- LiteLLM (AI proxy, port 4000) + Key Provisioner (key management, port 8100) + Enforcement Hook
- Platform Admin Dashboard (Flask, port 5050)
- Roo Code (AI agent, VS Code) + OpenCode (AI agent, CLI) + Claude Code (AI agent, CLI, Anthropic native)
- Langfuse (AI observability, port 3100)

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

### Docker Workspace Access Rule

Docker-enabled workspaces require the user to be in the `docker-users` group (Authentik/Azure AD). This is enforced at two layers:

1. **Terraform precondition** — `data.coder_workspace_owner.me.groups` must contain `docker-users`
2. **ECS init container** (production only) — calls authorization service before task starts

Coder OSS has no template ACLs, so this group check is the only access control for templates.

Key facts:
- Group changes take effect after the user logs out and back in (OIDC sync)
- Existing Docker workspaces are NOT affected when a user is removed from the group
- The init container is fail-closed: if the auth service is unreachable, the workspace is blocked

See coder-poc/docs/DOCKER-DEV.md Sections 17-18.

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
- Mounting host Docker socket into workspaces (allows container escape — use rootless DinD sidecar)
- Using `--privileged` DinD when rootless DinD works (unnecessary privilege escalation)
- Running Docker workspaces on Fargate (impossible — Fargate has no nested container support)
- Skipping the `docker-users` group check (Coder OSS has no template ACLs — the group precondition is the only access control)

---

End of Claude.md