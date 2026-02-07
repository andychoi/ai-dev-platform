---
name: key-management
description: Scoped LiteLLM key management - provisioner service, auto-provisioning, self-service keys, service keys
---

# Key Management Skill

## Overview

The **key-provisioner** service (port 8100) isolates the LiteLLM master key from workspace containers. Workspaces and users never see the master key. Instead, they receive scoped virtual keys with budget and rate-limit constraints. The provisioner handles auto-provisioning at workspace startup, self-service key generation, and key info lookups.

> Full documentation: `shared/docs/KEY-MANAGEMENT.md`

## Architecture

```
Workspace Container
  └─ startup script (PROVISIONER_SECRET)
     └─ POST /api/v1/keys/workspace
        └─ key-provisioner (:8100)
           └─ LiteLLM Master Key (internal only)
              └─ LiteLLM (:4000) /key/generate
                 └─ Returns scoped virtual key → workspace

Admin Host
  └─ manage-service-keys.sh (LITELLM_MASTER_KEY)
     └─ LiteLLM (:4000) /key/generate directly

User (in workspace)
  └─ generate-ai-key.sh (Coder session token)
     └─ POST /api/v1/keys/self-service
        └─ key-provisioner (:8100)
           └─ validates token via Coder API
              └─ LiteLLM /key/generate → returns key
```

## Key Types

| Scope | Alias Pattern | Budget | RPM | Models | Duration | Created By |
|-------|--------------|--------|-----|--------|----------|------------|
| `workspace` | `workspace-{id}` | $10 | 60 | all | 30 days | key-provisioner (auto) |
| `user` | `user-{username}` | $20 | 100 | all | 90 days | key-provisioner (self-service) |
| `ci` | `ci-{repo-slug}` | $5 | 30 | haiku only | 365 days | manage-service-keys.sh |
| `agent:review` | `agent-review` | $15 | 40 | sonnet+haiku | 365 days | manage-service-keys.sh |
| `agent:write` | `agent-write` | $30 | 60 | all | 365 days | manage-service-keys.sh |

## Key Provisioner Endpoints

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/api/v1/keys/workspace` | POST | `Bearer <PROVISIONER_SECRET>` | Auto-provision workspace key (idempotent) |
| `/api/v1/keys/self-service` | POST | `Bearer <coder-session-token>` | Generate personal key (validates via Coder API) |
| `/api/v1/keys/info` | GET | `Bearer <any-litellm-key>` | Get key usage/budget info |
| `/health` | GET | None | Health check (also verifies LiteLLM connectivity) |

## Auto-Provisioning Flow

1. Workspace starts, startup script runs
2. Script calls `POST /api/v1/keys/workspace` with `workspace_id`, `username`, `workspace_name`, and optionally `enforcement_level`
3. Auth: `Authorization: Bearer $PROVISIONER_SECRET`
4. Key-provisioner checks if alias `workspace-{id}` already exists (idempotent)
5. If not, generates key via LiteLLM `/key/generate` with scope defaults and `enforcement_level` in metadata
6. Returns virtual key to workspace
7. Key is written to Roo Code config for immediate use

### `enforcement_level` Metadata Field

Each virtual key can carry an `enforcement_level` in its metadata. The LiteLLM enforcement hook (`enforcement_hook.py`) reads this field at request time and prepends the corresponding system prompt.

| Value | Behavior |
|-------|----------|
| `unrestricted` | No system prompt injected |
| `standard` | General best-practices prompt (default) |
| `design-first` | Strict design-before-code workflow prompt |

- Set at provisioning time via the `enforcement_level` body parameter on `POST /api/v1/keys/workspace`
- Invalid values fall back to `standard`
- Stored in key metadata as `metadata.enforcement_level`
- See `skills/ai-gateway/SKILL.md` for enforcement hook details

## Scripts

| Script | Auth | Purpose |
|--------|------|---------|
| `scripts/generate-ai-key.sh` | Coder session token | Self-service personal key generation (calls provisioner) |
| `scripts/manage-service-keys.sh` | LiteLLM master key | Admin tool: create/list/revoke/rotate CI and agent keys |
| `scripts/setup-litellm-keys.sh` | LiteLLM master key | Bootstrap keys for predefined users (migration/initial setup) |

### manage-service-keys.sh Commands

```bash
./manage-service-keys.sh create ci <repo-slug>       # CI key (haiku, $5)
./manage-service-keys.sh create agent review          # Review agent ($15)
./manage-service-keys.sh create agent write           # Write agent ($30)
./manage-service-keys.sh list                         # List service keys
./manage-service-keys.sh revoke <key-alias>           # Delete key
./manage-service-keys.sh rotate <key-alias>           # Revoke + recreate
```

## Security Model

- **Master key**: Only in key-provisioner container and admin scripts. Never exposed to workspaces.
- **Provisioner secret**: Shared between key-provisioner and workspace containers (via env var). Used only for workspace auto-provisioning.
- **Coder session token**: Used by self-service endpoint. Validated against Coder API (`/api/v2/users/me`).
- **Virtual keys**: Stored in LiteLLM database (PostgreSQL). Per-user, scoped, budget-capped.
- **Principle**: Workspaces authenticate with `PROVISIONER_SECRET` and receive a scoped virtual key. They never touch the master key or LiteLLM admin API directly.

## Troubleshooting Quick Reference

| Symptom | Cause | Fix |
|---------|-------|-----|
| Workspace key 401 | `PROVISIONER_SECRET` mismatch | Check env var in both key-provisioner and workspace template |
| `key generation will fail` log | `LITELLM_MASTER_KEY` not set in key-provisioner | Set in `.env`, `docker compose up -d key-provisioner` |
| Self-service returns 401 | Invalid/expired Coder session token | Re-authenticate: `coder login` or set `CODER_SESSION_TOKEN` |
| Key exists but budget exceeded (402) | User hit max_budget | Increase via LiteLLM `/budget/update` API |
| `Could not reach key provisioner` | key-provisioner not running | `docker compose up -d key-provisioner` |
| Duplicate alias error | Key alias collision | Provisioner is idempotent (returns existing key). For manual keys, use unique aliases. |

## Key File Locations

| File | Purpose |
|------|---------|
| `shared/key-provisioner/app.py` | Key provisioner service source |
| `shared/key-provisioner/Dockerfile` | Provisioner container build |
| `coder-poc/scripts/generate-ai-key.sh` | Self-service key script |
| `coder-poc/scripts/manage-service-keys.sh` | Admin service key management |
| `coder-poc/scripts/setup-litellm-keys.sh` | Bootstrap/migration key setup |
| `coder-poc/.env` | Master key, provisioner secret, API keys |
| `shared/docs/KEY-MANAGEMENT.md` | Full documentation |
