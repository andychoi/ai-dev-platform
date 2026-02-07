# Role-Based Access Control (RBAC) & Service Access Matrix

Platform-wide role and access control configuration for all services.

## Table of Contents

1. [Role Hierarchy](#1-role-hierarchy)
2. [Coder Dashboard Access](#2-coder-dashboard-access)
3. [Platform Service Access](#3-platform-service-access)
4. [OIDC Group-to-Role Mapping](#4-oidc-group-to-role-mapping)
5. [Template Parameter Visibility](#5-template-parameter-visibility)
6. [Workspace Connection Controls](#6-workspace-connection-controls)
7. [AI Key & Budget Scoping](#7-ai-key--budget-scoping)
8. [Admin Workflow](#8-admin-workflow)
9. [Validation](#9-validation)

---

## 1. Role Hierarchy

### Coder Roles (Native RBAC)

| Role | Target User | Authentik Group | Description |
|------|-------------|-----------------|-------------|
| **Owner** | Platform Admin | `coder-admins` | Full admin: users, templates, deployments, audit, system settings |
| **Template Admin** | App Manager | `coder-template-admins` | Manage templates, view all workspaces, create workspaces |
| **Member** | Contractor | *(default / `coder-members`)* | Create own workspaces from templates, use IDE and terminal |
| **Auditor** | Compliance | `coder-auditors` | Read-only access to audit logs |

### PoC Test Accounts

| Username | Role | Authentik Group | Password |
|----------|------|-----------------|----------|
| `admin` | Owner | `coder-admins` | `SecureP@ssw0rd!` |
| `app-manager` | Template Admin | `coder-template-admins` | `Manager123!` |
| `contractor1` | Member | *(none)* | `Contractor123!` |
| `contractor2` | Member | *(none)* | `Contractor123!` |
| `contractor3` | Member | *(none)* | `Contractor123!` |

---

## 2. Coder Dashboard Access

### Dashboard Elements by Role

| Element | Owner | Template Admin | Member | Auditor |
|---------|:-----:|:--------------:|:------:|:-------:|
| **Workspaces** (own) | Yes | Yes | Yes | No |
| **Workspaces** (view others') | Yes | Yes | No | No |
| **Workspaces** (access others' terminal/IDE) | **No*** | No | No | No |
| **Templates** (list/use) | Yes | Yes | Yes | No |
| **Templates** (create/edit/push) | Yes | Yes | No | No |
| **Users** management | Yes | No | No | No |
| **Deployment** settings | Yes | No | No | No |
| **Audit Log** | Yes | No | No | Yes |
| **Create workspace** | Yes | Yes | Yes | No |

\* `CODER_DISABLE_OWNER_WORKSPACE_ACCESS=true` — Owner can manage (start/stop/delete) but cannot open terminals or IDE in other users' workspaces.

### Security Settings (docker-compose.yml)

| Setting | Value | Purpose |
|---------|-------|---------|
| `CODER_DISABLE_OWNER_WORKSPACE_ACCESS` | `true` | Admin cannot access contractor terminals/IDE |
| `CODER_DISABLE_WORKSPACE_SHARING` | `true` | Users cannot share workspaces with each other |
| `CODER_DISABLE_PATH_APPS` | `false` (set `true` in prod) | Path-based app routing |
| `CODER_SECURE_AUTH_COOKIE` | `true` | Requires HTTPS for session cookies |
| `CODER_MAX_SESSION_EXPIRY` | `8h` | Session timeout |
| `CODER_RATE_LIMIT_API` | `512` | API rate limiting |
| `CODER_AIBRIDGE_ENABLED` | `false` | Built-in AI disabled (LiteLLM used) |
| `CODER_HIDE_AI_TASKS` | `true` | Hide AI task sidebar |

---

## 3. Platform Service Access

### Admin Web UIs

| Service | URL | Auth Method | Who Can Access | Contractor? |
|---------|-----|-------------|----------------|:-----------:|
| **Coder Dashboard** | `https://host.docker.internal:7443` | OIDC / password | All users (role-filtered) | Yes (limited) |
| **Coder Admin Panel** | `…/deployment/general` | Coder Owner session | Owner only | **No** |
| **Authentik Admin** | `http://localhost:9000/if/admin/` | `akadmin` / password | Platform Admin only | **No** |
| **LiteLLM Admin UI** | `http://localhost:4000/ui` | Master key / OIDC | Platform Admin only | **No** |
| **Gitea** | `http://localhost:3000` | OIDC / `gitea_admin` | All users (repo-scoped) | Yes (own repos) |
| **Gitea Admin** | `http://localhost:3000/admin` | `gitea_admin` / password | Instance admin only | **No** |
| **Langfuse** | `http://localhost:3100` | `admin@local.test` / password | Platform Admin only | **No** |
| **MinIO Console** | `http://localhost:9001` | `minioadmin` / password | Platform Admin only | **No** |
| **Platform Admin** | `http://localhost:5050` | `admin` / OIDC | Platform Admin only | **No** |

### Service Credentials

| Service | Username | Password / Key | Notes |
|---------|----------|----------------|-------|
| Coder | `admin` | `SecureP@ssw0rd!` | Owner account, OIDC preferred |
| Authentik | `akadmin` | `admin` (.env) | Change in production |
| LiteLLM | *(master key)* | `sk-poc-litellm-master-key-…` | Bearer token auth |
| Gitea | `gitea_admin` | `password123` | Change in production |
| Langfuse | `admin@local.test` | `adminadmin` | Change in production |
| MinIO | `minioadmin` | `minioadmin` | Change in production |
| Platform Admin | `admin` | `admin123` | Change in production |
| Key Provisioner | *(secret)* | `poc-provisioner-secret-…` | Service-to-service |

---

## 4. OIDC Group-to-Role Mapping

### Architecture

```
┌───────────────┐      OIDC token       ┌─────────────────┐
│   Authentik    │  (includes "groups"   │   Coder Server   │
│  Identity      │──────claim)──────────▶│                   │
│  Provider      │                       │  Reads groups     │
│                │                       │  Maps to roles    │
│  Groups:       │                       │                   │
│  coder-admins  │                       │  owner            │
│  coder-template│                       │  template-admin   │
│  coder-auditors│                       │  auditor          │
│  (none)        │                       │  member (default) │
└───────────────┘                       └─────────────────┘
```

### Coder Environment Variables

```yaml
# docker-compose.yml
CODER_OIDC_GROUP_FIELD: "groups"
CODER_OIDC_GROUP_MAPPING: |
  {
    "coder-admins": "owner",
    "coder-template-admins": "template-admin",
    "coder-auditors": "auditor"
  }
CODER_OIDC_USER_ROLE_FIELD: "groups"
CODER_OIDC_USER_ROLE_MAPPING: |
  {
    "coder-admins": ["owner"],
    "coder-template-admins": ["template-admin"],
    "coder-auditors": ["auditor"]
  }
CODER_OIDC_GROUP_AUTO_CREATE: "true"
```

### Authentik Setup Required

Run `./scripts/setup-authentik-rbac.sh` to:
1. Create groups: `coder-admins`, `coder-template-admins`, `coder-auditors`, `coder-members`
2. Create a custom OIDC property mapping that includes `groups` claim
3. Assign the mapping to the Coder OIDC provider

After running the script, assign users to groups in Authentik Admin → Directory → Groups.

### Role Assignment Flow

1. User clicks "Sign in with SSO" on Coder
2. Coder redirects to Authentik
3. User authenticates in Authentik
4. Authentik returns OIDC token with `groups` claim (e.g., `["coder-template-admins"]`)
5. Coder reads `groups` claim and maps to role (e.g., `template-admin`)
6. User sees role-appropriate dashboard
7. Role syncs on every login (group changes in Authentik take effect on next login)

---

## 5. Template Parameter Visibility

### Security-Sensitive Parameters

| Parameter | `mutable` | Who Sets It | Purpose |
|-----------|:---------:|-------------|---------|
| `ai_enforcement_level` | `false` | Admin at creation | AI behavior mode (standard/design-first/unrestricted) |
| `egress_extra_ports` | `false` | Admin at creation | Network firewall exceptions |
| `disk_size` | `false` | Admin at creation | Persistent storage allocation |
| `database_type` | `false` | Admin at creation | Database provisioning type |
| `cpu_cores` | `true` | User can change | Resource allocation (restart) |
| `memory_gb` | `true` | User can change | Resource allocation (restart) |
| `ai_model` | `true` | User can change | AI model selection |
| `git_repo` | `true` | User can change | Repository to clone |

**Immutable parameters** (`mutable = false`) are locked at workspace creation. Only a Template Admin or Owner can set them by creating a new workspace for the user.

---

## 6. Workspace Connection Controls

| Method | Setting | Value | Effect |
|--------|---------|-------|--------|
| **VS Code Desktop** | `vscode` | `false` | Cannot connect via local VS Code |
| **VS Code Insiders** | `vscode_insiders` | `false` | Cannot connect via Insiders |
| **Web Terminal** | `web_terminal` | `true` | Browser terminal (only allowed method) |
| **SSH** | `ssh_helper` | `false` | No SSH/SCP/SFTP access |
| **Port Forwarding** | `port_forwarding_helper` | `false` | Cannot tunnel ports |

Combined with terminal security hardening (P0/P1), contractors are restricted to:
- Browser-based code-server (VS Code)
- Browser-based web terminal
- No file transfer, no tunneling, no external connections

---

## 7. AI Key & Budget Scoping

| Key Scope | RPM | Daily Budget | Max Parallel | Who Gets It |
|-----------|-----|-------------|-------------|-------------|
| `workspace` | 60 | $10.00 | 5 | Auto-provisioned per workspace |
| `user` | 100 | $20.00 | 10 | Self-service via `generate-ai-key.sh` |
| `ci` | 30 | $5.00 | 3 | Managed via `manage-service-keys.sh` |

Each key also carries:
- `enforcement_level` — AI behavior mode (server-side enforced)
- `guardrail_level` — Content filtering (standard/strict/off)
- Structured `metadata.scope` for audit attribution

---

## 8. Admin Workflow

### Onboarding a New Contractor

1. **Create user in Authentik** — Admin → Directory → Users → Create
2. **Assign to group** — Add to `coder-members` (or no group = default Member)
3. **User logs in via SSO** — First OIDC login auto-creates Coder account with Member role
4. **Admin creates workspace** — Set `ai_enforcement_level`, `egress_extra_ports`, `database_type`
5. **Share workspace URL** — Contractor accesses via browser only

### Promoting to Template Admin

1. Add user to `coder-template-admins` group in Authentik
2. User logs in again via SSO → role auto-updates to Template Admin
3. User now sees template management in Coder dashboard

### Offboarding a Contractor

1. **Disable in Authentik** — Admin → Directory → Users → Deactivate
2. **Stop workspace in Coder** — Admin → Workspaces → Stop
3. **Revoke AI keys** — `./scripts/manage-service-keys.sh delete <key_alias>`
4. **Delete workspace** (optional) — Volume preserved if `prevent_destroy = true`

---

## 9. Validation

Run the automated test script:

```bash
cd coder-poc
./scripts/test-rbac.sh
```

The script validates:
- Coder RBAC env vars are set (OIDC group mapping)
- Authentik groups exist
- OIDC property mapping includes groups claim
- Coder API returns correct roles for test users
- Admin-only endpoints are inaccessible to contractors
- LiteLLM admin UI is protected
- Template parameters have correct mutability

---

## Related Documents

- [Enterprise Feature Review](ENTERPRISE-FEATURE-REVIEW.md)
- [Web Terminal Security](WEB-TERMINAL-SECURITY.md)
- [Key Management](KEY-MANAGEMENT.md)
- [Security Guide](SECURITY.md)
- [AI Integration](AI.md)

---

*Last updated: February 7, 2026*
