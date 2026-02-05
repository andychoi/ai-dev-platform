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
- Optional AI Gateway

---

## Absolute Rules (Non-Negotiable)

### Access URL Rule (OIDC Critical)

Coder must always be accessed via:

http://host.docker.internal:7080

Never use localhost.

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

---

End of Claude.md