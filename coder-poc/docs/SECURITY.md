# Security Architecture - Dev Platform PoC

This document describes the security architecture, controls, and best practices for the Coder WebIDE Development Platform.

**Related Documents:**
- [PRODUCTION.md](PRODUCTION.md) - Production deployment guide
- [POC-SECURITY-REVIEW.md](POC-SECURITY-REVIEW.md) - Comprehensive security audit findings
- [PRODUCTION-PLAN.md](../../coder-production/PRODUCTION-PLAN.md) - Implementation plan for production

## Table of Contents

1. [Security Overview](#1-security-overview)
2. [Authentication & Authorization](#2-authentication--authorization)
3. [Network Security](#3-network-security)
4. [Workspace Security](#4-workspace-security)
5. [Data Protection](#5-data-protection)
6. [AI Security](#6-ai-security)
7. [Audit & Logging](#7-audit--logging)
8. [Security Hardening](#8-security-hardening)
9. [Threat Model](#9-threat-model)
10. [Compliance Considerations](#10-compliance-considerations)

---

## 1. Security Overview

### 1.1 Security Principles

| Principle | Implementation |
|-----------|----------------|
| **Defense in Depth** | Multiple layers: network, container, application, user |
| **Least Privilege** | Role-based access, minimal permissions |
| **Zero Trust** | All connections authenticated, no implicit trust |
| **Isolation** | Workspaces isolated per user, network segmentation |
| **Audit Trail** | All actions logged for accountability |

### 1.2 Security Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              INTERNET                                        │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ HTTPS (TLS 1.3)
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         REVERSE PROXY / WAF                                  │
│                    (Optional: Traefik, Cloudflare)                          │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
            ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
            │   Coder     │ │  Authentik  │ │    Gitea     │
            │   (7080)    │ │   (9000)    │ │   (3000)    │
            └─────────────┘ └─────────────┘ └─────────────┘
                    │               │               │
                    └───────────────┼───────────────┘
                                    │
┌─────────────────────────────────────────────────────────────────────────────┐
│                         INTERNAL NETWORK (coder-network)                     │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐          │
│  │PostgreSQL│ │  Redis   │ │ LiteLLM  │ │  MinIO   │ │ Mailpit  │          │
│  │(internal)│ │(internal)│ │ LiteLLM  │ │(9001/02) │ │  (8025)  │          │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘          │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    WORKSPACE CONTAINERS                               │   │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                     │   │
│  │  │ Workspace 1 │ │ Workspace 2 │ │ Workspace N │  (Isolated)         │   │
│  │  │ (User A)    │ │ (User B)    │ │ (User N)    │                     │   │
│  │  └─────────────┘ └─────────────┘ └─────────────┘                     │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Authentication & Authorization

### 2.1 Authentication Methods

| Component | Method | Details |
|-----------|--------|---------|
| Coder | Local + OIDC | Built-in auth, optional Authentik SSO |
| Gitea | Local | Username/password |
| Authentik | Local + Federation | Can federate with Azure AD |
| MinIO | Access Keys | Root credentials + service accounts |
| LiteLLM | API Keys | Workspace-bound tokens |

### 2.2 Role-Based Access Control (RBAC)

#### Coder Roles

| Role | Permissions | Use Case |
|------|-------------|----------|
| **Owner** | Full admin access | Platform administrators |
| **Template Admin** | Manage templates, view workspaces | App/DevOps managers |
| **Member** | Create workspaces from templates | Contractors/developers |
| **Auditor** | Read-only audit logs | Compliance officers |

#### Permission Matrix

| Action | Owner | Template Admin | Member | Auditor |
|--------|-------|----------------|--------|---------|
| Create users | ✓ | ✗ | ✗ | ✗ |
| Manage templates | ✓ | ✓ | ✗ | ✗ |
| View all workspaces | ✓ | ✓ | ✗ | ✗ |
| Create workspace | ✓ | ✓ | ✓ | ✗ |
| Access own workspace | ✓ | ✓ | ✓ | ✗ |
| Access others' workspace | ✓* | ✗ | ✗ | ✗ |
| View audit logs | ✓ | ✗ | ✗ | ✓ |
| Deployment settings | ✓ | ✗ | ✗ | ✗ |

*Can be disabled with `CODER_DISABLE_OWNER_WORKSPACE_ACCESS=true`

### 2.3 Session Management

```yaml
# Coder session settings (current PoC configuration)
CODER_MAX_SESSION_EXPIRY: "8h"       # Maximum session duration (reduced from 24h)
CODER_SECURE_AUTH_COOKIE: "false"    # Disabled in PoC (HTTP-only), set "true" for production (requires HTTPS)
```

**Production:** Enable `CODER_SECURE_AUTH_COOKIE: "true"` when TLS is configured.

### 2.4 Authentik Integration (Optional)

For enterprise SSO:

```
User → Authentik → OIDC → Coder
                ↓
         Azure AD Federation (optional)
```

---

## 3. Network Security

### 3.1 Network Segmentation

| Network Zone | Services | Exposure |
|--------------|----------|----------|
| **Public** | Coder, Gitea, Authentik | External access |
| **Internal** | PostgreSQL, Redis, TestDB | Container-only |
| **Workspace** | User workspaces | Isolated per user |

### 3.2 Port Exposure

| Port | Service | Exposed To | Purpose |
|------|---------|------------|---------|
| 7080 | Coder | Host | WebIDE platform |
| 3000 | Gitea | Host | Git server |
| 8080 | Drone | Host | CI/CD |
| 4000 | LiteLLM | Host | AI API proxy |
| 9000/9443 | Authentik | Host | Identity provider |
| 9001/9002 | MinIO | Host | Object storage |
| 8025 | Mailpit | Host | Email testing |
| 5432 | PostgreSQL | Internal only | Database |
| 6379 | Redis | Internal only | Cache |

### 3.3 Firewall Rules (Production)

```bash
# Recommended iptables rules for production
# Allow only necessary inbound traffic
iptables -A INPUT -p tcp --dport 443 -j ACCEPT   # HTTPS
iptables -A INPUT -p tcp --dport 80 -j ACCEPT    # HTTP (redirect to HTTPS)
iptables -A INPUT -p tcp --dport 22 -j DROP      # Block SSH to host
iptables -A INPUT -j DROP                         # Default deny
```

### 3.4 TLS Configuration

**Development:** HTTP (acceptable for localhost)

**Production Requirements:**
- TLS 1.2+ on all public endpoints
- Valid certificates (Let's Encrypt or internal CA)
- HSTS headers enabled
- Certificate pinning for mobile clients (if applicable)

```yaml
# Example Traefik TLS configuration
tls:
  options:
    default:
      minVersion: VersionTLS12
      cipherSuites:
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
```

---

## 4. Workspace Security

### 4.1 Connection Method Controls

| Method | Status | Risk Level | Configuration |
|--------|--------|------------|---------------|
| Web IDE (code-server) | ✓ Enabled | Low | Browser-only access |
| Web Terminal | ✓ Enabled | Low | Browser-only access |
| VS Code Desktop | ✗ Disabled | High | `vscode = false` |
| SSH | ✗ Disabled | High | `ssh_helper = false` |
| Port Forwarding | ✗ Disabled | High | `port_forwarding_helper = false` |

### 4.2 Template Security Settings

```terraform
# Secure template configuration
resource "coder_agent" "main" {
  display_apps {
    vscode                 = false  # Prevent local VS Code connection
    vscode_insiders        = false  # Prevent VS Code Insiders
    web_terminal           = true   # Allow web terminal only
    ssh_helper             = false  # Prevent SSH/SCP
    port_forwarding_helper = false  # Prevent port tunneling
  }
}
```

### 4.3 Container Security

| Control | Implementation | Status |
|---------|----------------|--------|
| Non-root user | `user = "1000:1000"` in container | ENABLED |
| Docker socket access | Group-based (DOCKER_GID) | ENABLED |
| Read-only filesystem | Mount specific paths as writable | Not yet (production) |
| Resource limits | CPU/memory constraints per workspace | Configurable |
| No privileged mode | Containers run unprivileged | ENABLED |
| Seccomp profile | Default Docker seccomp | Default |

**Current Coder Server Configuration:**
```yaml
# docker-compose.yml - Coder runs as non-root with Docker socket access
user: "1000:1000"
group_add:
  - ${DOCKER_GID:-1}  # Docker group for socket access
```

```terraform
# Container security in template
resource "docker_container" "workspace" {
  user = "1000:1000"  # Non-root

  cpu_shares = data.coder_parameter.cpu_cores.value * 1024
  memory     = data.coder_parameter.memory_gb.value * 1024 * 1024 * 1024

  # Security options (recommended for production)
  # security_opts = ["no-new-privileges:true"]
}
```

### 4.4 Workspace Isolation

```yaml
# Server-level isolation settings (current PoC configuration)
CODER_DISABLE_WORKSPACE_SHARING: "true"   # No workspace sharing - ENABLED
CODER_DISABLE_PATH_APPS: "false"          # Path apps allowed in PoC (set "true" for production)
# CODER_DISABLE_OWNER_WORKSPACE_ACCESS: "true"  # Block admin access (optional)
```

**Note:** The current PoC allows path-based apps for easier local testing. In production with proper wildcard DNS, set `CODER_DISABLE_PATH_APPS: "true"` to require subdomain routing.

---

## 5. Data Protection

### 5.1 Data Classification

| Data Type | Classification | Storage | Encryption |
|-----------|----------------|---------|------------|
| Source code | Confidential | Workspace volumes | At-rest (volume encryption) |
| Credentials | Secret | Environment variables | In-transit (TLS) |
| User data | Internal | PostgreSQL | At-rest + in-transit |
| Audit logs | Internal | PostgreSQL | At-rest + in-transit |
| AI conversations | Confidential | LiteLLM logs | At-rest |

### 5.2 Secrets Management

**Current (Development):**
- Environment variables in docker-compose
- `.env` file (gitignored)

**Production Recommendations:**
- HashiCorp Vault for secrets
- AWS Secrets Manager / Azure Key Vault
- Kubernetes secrets with encryption

```yaml
# .env file permissions
chmod 600 .env
chown root:root .env
```

### 5.3 Data Retention

| Data | Retention | Deletion |
|------|-----------|----------|
| Workspace data | Until workspace deleted | User-initiated or admin |
| Audit logs | 90 days (configurable) | Automatic rotation |
| AI logs | 30 days | Automatic rotation |
| Git history | Permanent | Manual deletion |

### 5.4 Backup & Recovery

```bash
# Database backup
docker exec postgres pg_dumpall -U postgres > backup.sql

# Volume backup
docker run --rm -v coder-poc-postgres:/data -v $(pwd):/backup \
  alpine tar czf /backup/postgres-backup.tar.gz /data
```

---

## 6. AI Security

### 6.1 LiteLLM Proxy Security

| Control | Implementation | Status |
|---------|----------------|--------|
| Authentication | API key validation | Configurable (default: enabled) |
| Rate limiting | Per-key request limits | Enabled (60 RPM default) |
| CORS | Configurable allowed origins | Configured |
| Audit logging | All requests logged with workspace ID | Planned |
| API key rotation | Managed centrally, not exposed to users | Yes |
| Provider abstraction | Users don't see actual API keys | Yes |

**Current LiteLLM Configuration:**
```yaml
# docker-compose.yml - LiteLLM authentication
LITELLM_MASTER_KEY: "${LITELLM_MASTER_KEY}"
RATE_LIMIT_RPM: "${AI_RATE_LIMIT_RPM:-60}"
```

### 6.2 AI Data Flow

```
Workspace → LiteLLM Proxy → AWS Bedrock / Anthropic API
    │            │
    │            └─→ Audit Log (request/response metadata)
    │
    └─→ No API keys exposed to workspace
```

### 6.3 Disabled AI Features (Copilot, Cody, AI Bridge)

All built-in and third-party AI features are disabled to ensure AI traffic is routed exclusively through LiteLLM for auditing and cost control.

| Feature | Disabled Via | Security Rationale |
|---------|-------------|-------------------|
| Coder AI Bridge | `CODER_AIBRIDGE_ENABLED=false` | Bypasses LiteLLM proxy; no per-user audit trail |
| GitHub Copilot | Extension uninstalled + settings | Requires external GitHub auth; not auditable |
| Copilot Chat | Extension uninstalled + settings | Same as Copilot |
| VS Code inline chat | `inlineChat.mode=off` | Part of Copilot ecosystem |
| Inline suggestions | `editor.inlineSuggest.enabled=false` | Prevents non-LiteLLM AI sources |
| Sourcegraph Cody | Extension uninstalled + settings | Requires external auth; not auditable |

**Three-layer lockdown:**
1. **Server env vars** — `CODER_AIBRIDGE_ENABLED=false`
2. **VS Code settings** — All `github.copilot.*`, `cody.*`, `chat.*` disabled
3. **Dockerfile** — Explicit `--uninstall-extension` for Copilot, Copilot Chat, Cody

### 6.4 Design-First AI Enforcement (Server-Side Prompt Injection)

The platform includes a tamper-proof enforcement layer that controls AI agent behavior at the proxy level. A LiteLLM `CustomLogger` callback reads `enforcement_level` from each virtual key's metadata and prepends a mandatory system prompt to every chat completion request. Because enforcement happens server-side inside LiteLLM, users cannot disable, modify, or bypass it from the workspace.

| Enforcement Level | Effect |
|-------------------|--------|
| `unrestricted` | No system prompt injected |
| `standard` (default) | Lightweight reasoning checklist prepended |
| `design-first` | Mandatory design-before-code workflow; code output blocked in first response |

Security properties:
- **Tamper-proof** — Prompt injection occurs at the proxy, outside workspace control
- **Key-bound** — Enforcement level is stored in key metadata, not in client config
- **Downgrade-resistant** — Changing the template parameter does not affect existing keys; key rotation is required
- **Auditable** — LiteLLM logs include the enforcement level applied to each request

Client-side config (Roo Code `customInstructions`, OpenCode `enforcement.md`) reinforces the server-side rules but is advisory only. The server-side hook is the authoritative control.

See [AI.md Section 12](AI.md#12-design-first-ai-enforcement-layer) and [ROO-CODE-LITELLM.md Section 7](ROO-CODE-LITELLM.md#7-design-first-ai-enforcement) for implementation details.

### 6.5 Roo Code Extension Security

```json
// Workspace-level config (~/.config/roo-code/settings.json)
{
  "apiProvider": "openai-compatible",
  "openAiCompatibleApiConfiguration": {
    "baseUrl": "http://litellm:4000/v1",
    "apiKey": "<per-user-virtual-key>",
    "modelId": "<selected-model>"
  }
  // No upstream API keys stored - LiteLLM proxy handles credentials
}
```

---

## 7. Audit & Logging

### 7.1 Audit Events

| Event | Logged | Details |
|-------|--------|---------|
| User login/logout | ✓ | User, IP, timestamp |
| Workspace create/delete | ✓ | User, template, parameters |
| Workspace start/stop | ✓ | User, duration |
| Template changes | ✓ | User, diff |
| Admin actions | ✓ | All admin operations |
| AI requests | ✓ | Workspace ID, model, tokens |

### 7.2 Log Locations

| Component | Log Location | Format |
|-----------|--------------|--------|
| Coder | `docker logs coder-server` | JSON |
| Gitea | `/data/gitea/log/` | Text |
| LiteLLM | `docker logs litellm` | JSON |
| PostgreSQL | `docker logs postgres` | Text |
| Workspaces | Coder dashboard | Streaming |

### 7.3 Log Aggregation (Production)

```yaml
# Recommended: Forward logs to centralized system
# Options: ELK Stack, Loki+Grafana, Splunk, Datadog

logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
    labels: "service,environment"
```

### 7.4 Monitoring Alerts

| Alert | Condition | Severity |
|-------|-----------|----------|
| Failed logins | >5 in 5 minutes | High |
| Workspace creation spike | >10 in 1 minute | Medium |
| AI rate limit hit | Any | Low |
| Container OOM | Memory exceeded | High |
| Disk usage | >80% | Medium |

---

## 8. Security Hardening

### 8.1 Hardening Checklist

#### Infrastructure
- [ ] TLS enabled on all public endpoints
- [ ] Firewall configured (only necessary ports)
- [ ] Host SSH disabled or key-only
- [ ] Docker daemon secured
- [ ] Regular security updates scheduled

#### Application
- [ ] Default passwords changed
- [ ] Session timeouts configured
- [ ] CORS properly configured
- [ ] CSP headers enabled
- [ ] Rate limiting enabled

#### Workspaces
- [ ] VS Code Desktop disabled
- [ ] SSH disabled
- [ ] Port forwarding disabled
- [ ] Resource limits set
- [ ] Non-root containers

### 8.2 Docker Hardening

```yaml
# Production docker-compose additions
services:
  coder:
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
```

### 8.3 Security Headers

```nginx
# Nginx/Traefik security headers
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Content-Security-Policy "default-src 'self';" always;
```

---

## 9. Threat Model

### 9.1 Threat Actors

| Actor | Motivation | Capability |
|-------|------------|------------|
| Malicious contractor | Data theft, sabotage | Workspace access |
| External attacker | Data breach, ransomware | Network attacks |
| Insider threat | IP theft, unauthorized access | Admin/elevated access |
| Automated bots | Resource abuse, spam | Unauthenticated access |

### 9.2 Attack Vectors & Mitigations

| Vector | Risk | Mitigation |
|--------|------|------------|
| Credential stuffing | High | Rate limiting, MFA |
| Container escape | Medium | Updated Docker, no privileged |
| Data exfiltration | High | No SSH/SCP, network monitoring |
| Privilege escalation | Medium | Non-root containers, RBAC |
| Supply chain | Medium | Signed images, vulnerability scanning |
| AI prompt injection | Low | Input validation, output filtering |
| AI enforcement bypass | Low | Server-side prompt injection via LiteLLM hook; key-bound metadata |

### 9.3 Risk Assessment

| Risk | Likelihood | Impact | Score | Status |
|------|------------|--------|-------|--------|
| Unauthorized workspace access | Low | High | Medium | Mitigated |
| Data exfiltration via SSH | Low | High | Low | Disabled |
| Container breakout | Very Low | Critical | Low | Hardened |
| Credential compromise | Medium | High | Medium | MFA recommended |
| AI API abuse | Low | Medium | Low | Rate limited |

---

## 10. Compliance Considerations

### 10.1 Regulatory Frameworks

| Framework | Relevance | Key Requirements |
|-----------|-----------|------------------|
| SOC 2 | High | Access controls, audit logging |
| GDPR | Medium | Data protection, right to deletion |
| HIPAA | If applicable | PHI protection, audit trails |
| PCI-DSS | If applicable | Cardholder data isolation |

### 10.2 Compliance Controls

| Control | SOC 2 | GDPR | Implementation |
|---------|-------|------|----------------|
| Access control | CC6.1 | Art. 32 | RBAC, authentication |
| Audit logging | CC7.2 | Art. 30 | Comprehensive logging |
| Encryption | CC6.7 | Art. 32 | TLS, at-rest encryption |
| Data retention | CC6.6 | Art. 5 | Configurable retention |
| Incident response | CC7.4 | Art. 33 | Documented procedures |

### 10.3 Security Validation

```bash
# Run security validation
./scripts/validate-security.sh

# Expected output:
# Security Score: 72%+ (Dev)
# Security Score: 90%+ (Production with hardening)
```

---

## Appendix A: Quick Reference

### Security Commands

```bash
# Validate infrastructure security
./scripts/validate-security.sh

# Check container security
docker inspect --format='{{.Config.User}}' <container>

# View audit logs
docker logs coder-server | grep -i audit

# Check active sessions
curl -H "Coder-Session-Token: $TOKEN" \
  http://localhost:7080/api/v2/users/me/sessions
```

### Emergency Procedures

```bash
# Disable all workspaces
docker exec coder-server coder workspaces stop --all

# Revoke user access
docker exec coder-server coder users suspend <username>

# Rotate secrets
# 1. Update .env file
# 2. Restart services: docker compose up -d
```

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-04 | Platform Team | Initial version |
| 1.1 | 2026-02-05 | Platform Team | Updated to reflect current docker-compose.yml settings (non-root Coder, AI Gateway auth, rate limiting); added cross-references to related documents |
