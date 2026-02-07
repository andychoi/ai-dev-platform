# Coder WebIDE PoC - Comprehensive Security Review

**Review Date:** February 4, 2026
**Status:** Pre-Production Assessment
**Overall Risk Level:** HIGH - Not production-ready

---

## Executive Summary

This comprehensive review of the Coder WebIDE Proof of Concept identified **68 security and configuration issues** across 5 areas. The PoC successfully demonstrates the intended functionality but requires significant hardening before production deployment.

**Update (February 7, 2026):** Significant security hardening has been implemented since the initial review. See strikethrough items and status annotations below.

### Issue Breakdown by Severity

| Severity | Count | Fixed/Addressed | Remaining | Description |
|----------|-------|-----------------|-----------|-------------|
| **CRITICAL** | 16 | 8 | 8 | Must fix before ANY production use |
| **IMPORTANT** | 28 | 5 | 23 | Must fix before public/multi-tenant deployment |
| **MINOR** | 24 | 0 | 24 | Should fix for production hardening |

### Issue Breakdown by Component

| Component | Critical | Important | Minor | Total |
|-----------|----------|-----------|-------|-------|
| Infrastructure (Docker/Compose) | 3 | 7 | 6 | 16 |
| Coder Templates (Workspace) | 3 | 6 | 7 | 16 |
| Scripts/Automation | 4 | 7 | 6 | 17 |
| SSO/Authentication | 6 | 6 | 8 | 20 |
| AI Gateway | 3 | 5 | 4 | 12 |

---

## CRITICAL Issues (Must Fix Immediately)

### 1. Exposed AWS Credentials in .env File
**Location:** `coder-poc/.env` (lines 69-70)
```
AWS_ACCESS_KEY_ID=AKIA********************
AWS_SECRET_ACCESS_KEY=************************************
```
**Action:** ROTATE IMMEDIATELY - These are real AWS credentials exposed in version control.

### 2. Hardcoded OIDC Client Secrets
**Location:** `.env.sso`, `docker-compose.sso.yml`
- Coder, Gitea, MinIO, Platform Admin client secrets all hardcoded
**Action:** Regenerate all secrets in Authentik, remove from git history

### 3. ~~Coder Server Running as Root (UID 0)~~ FIXED
**Location:** `docker-compose.yml` (line 99)
```yaml
user: "1000:1000"  # Now runs as non-root
```
**Status:** RESOLVED - Coder now runs as non-root user (UID 1000) with Docker socket access via group_add

### 4. ~~Unrestricted Sudo in Workspaces~~ FIXED
**Location:** `templates/contractor-workspace/build/Dockerfile`
**Status:** RESOLVED — `apt-get install` removed from sudoers. Only read-only/safe commands remain: `apt-get update`, `systemctl status`, `update-ca-certificates`, cert copy, `setup-firewall.sh`. See [WEB-TERMINAL-SECURITY.md](WEB-TERMINAL-SECURITY.md) Section 2.1.

### 5. Git Credentials Stored in Plaintext
**Location:** `templates/contractor-workspace/main.tf` (lines 386-403)
- Writes credentials to `~/.git-credentials` in plaintext
**Action:** Use SSH keys or OAuth token-based authentication

### 6. SQL Injection Vulnerabilities
**Location:** `scripts/provision-database.sh`, `scripts/manage-devdb.sh`
```bash
run_sql "SELECT * FROM provisioning.create_individual_db('$username', '$workspace_id');"
```
**Action:** Implement parameterized queries or proper escaping

### 7. ~~HTTP-Only Communication (No TLS)~~ FIXED
**Location:** Coder server now runs with TLS on port 7443
**Status:** RESOLVED — Self-signed TLS cert with SAN (`DNS:host.docker.internal,DNS:localhost,IP:127.0.0.1`). `CODER_TLS_ENABLE=true`, `CODER_TLS_ADDRESS=0.0.0.0:7443`. Secure cookies enabled (`CODER_SECURE_AUTH_COOKIE=true`). Workspace agents trust cert via `update-ca-certificates`. Database `sslmode=disable` remains (internal network only, acceptable for PoC).

### 8. ~~Missing Authentication on AI Gateway~~ OBSOLETE
**Location:** The old Python `ai-gateway/gateway.py` has been **removed entirely**.
**Status:** RESOLVED — AI traffic is now routed through **LiteLLM proxy** (port 4000) with per-user virtual key authentication. Keys are auto-provisioned by the key-provisioner service. No unauthenticated AI access is possible.

### 9. ~~Open CORS Configuration~~ OBSOLETE
**Location:** The old Python `ai-gateway/gateway.py` has been **removed entirely**.
**Status:** RESOLVED — The LiteLLM proxy handles CORS configuration.

### 10. Hardcoded Database Admin Credentials
**Locations:**
- `templates/contractor-workspace/main.tf`: `provisioner123`
- `devdb/init.sql`: `aigateway123`, `provisioner123`
- `scripts/*.sh`: Multiple hardcoded passwords
**Action:** Use secrets management system

### 11. Missing PKCE for OAuth2/OIDC
**Location:** All OIDC configurations
**Action:** Enable PKCE (RFC 7636) for all OAuth2 clients

### 12. Weak Default Credentials Everywhere
**Examples:**
- PostgreSQL: `coderpassword`
- Authentik: `admin`
- MinIO: `minioadmin`
- Platform Admin: `admin123`
**Action:** Generate cryptographically strong passwords, enforce rotation

### 13. No Single Logout (SLO) Implementation
**Location:** Coder, MinIO configurations
**Action:** Implement OIDC RP-Initiated Logout for all services

### 14. ~~Rate Limiting Disabled~~ FIXED
**Location:** `docker-compose.yml`
```yaml
CODER_RATE_LIMIT_DISABLE_ALL: "${CODER_RATE_LIMIT_DISABLE_ALL:-false}"
CODER_RATE_LIMIT_API: "${CODER_RATE_LIMIT_API:-512}"
```
**Status:** RESOLVED - Rate limiting is now enabled by default (512 requests per minute)

### 15. ~~Secure Cookies Disabled~~ FIXED
**Location:** `docker-compose.yml`
```yaml
CODER_SECURE_AUTH_COOKIE: "true"
```
**Status:** RESOLVED — Secure cookies are now enabled. HTTPS is active on port 7443 (required for secure cookies).

### 16. Missing Network Isolation Between Workspaces — PARTIALLY ADDRESSED
**Location:** `templates/contractor-workspace/main.tf`
- All workspaces on same Docker network
**Status:** PARTIALLY ADDRESSED — Network **egress filtering** implemented via iptables (see [WEB-TERMINAL-SECURITY.md](WEB-TERMINAL-SECURITY.md) Section 3.1). Workspaces can only reach approved internal services. Outbound to unapproved destinations is dropped and logged (`EGRESS_DENIED:`). Per-workspace network isolation remains a production improvement.

---

## IMPORTANT Issues (Must Fix Before Production)

### Infrastructure
1. No container memory/CPU limits configured
2. Missing health checks for drone-runner
3. Weak PostgreSQL pg_hba.conf (trust-based auth)
4. Insecure SMTP configuration (plaintext auth allowed)
5. Gitea secrets hardcoded in app.ini
6. Missing logging configuration (no rotation)
7. Docker socket exposed to multiple containers

### Coder Templates
1. Temporary credentials files left in /tmp
2. Security options commented out (`no-new-privileges`)
3. Insecure script execution (curl | bash without verification)
4. Coder agent token exposed in environment
5. Code-server running without authentication
6. No image vulnerability scanning
7. ~~Docker CLI in workspace~~ FIXED — Docker CLI removed from workspace image
8. ~~Dangerous network binaries~~ FIXED — ssh, scp, sftp, nc, nmap, socat removed
9. ~~No shell audit logging~~ FIXED — All commands logged via `logger` to syslog
10. ~~No idle session timeout~~ FIXED — `TMOUT=1800` (30min), readonly

### Scripts/Automation
1. Missing input validation on all user parameters
2. Unvalidated external API calls and response parsing
3. Insecure password handling (visible in process listing)
4. Missing error handling with silent failures
5. Insecure temporary file creation (predictable paths)
6. Missing authentication validation in API responses
7. Race conditions in database cleanup

### SSO/Authentication
1. OAuth2 redirect URI case sensitivity issues
2. No rate limiting on authentication endpoints
3. Missing mTLS for service-to-service communication
4. Insufficient OAuth2 scope restrictions
5. Missing CSRF protection in Platform Admin
6. Weak session configuration (24h expiry too long)

### AI Gateway — LARGELY ADDRESSED
*The old Python AI Gateway (`ai-gateway/gateway.py`) has been replaced by LiteLLM proxy + enforcement hooks.*
1. ~~No request validation~~ ADDRESSED — LiteLLM validates requests; content guardrails scan for PII/secrets
2. ~~Weak rate limiting~~ ADDRESSED — Per-key RPM limits (30-120 RPM depending on scope)
3. Sensitive data potentially in logs — `turn_off_message_logging: true` is default
4. Missing health checks for upstream providers
5. ~~Incomplete error handling~~ ADDRESSED — LiteLLM returns structured error responses

---

## Production Readiness Checklist

### Phase 1: Critical Security (Week 1-2)

- [ ] **Secrets Management**
  - [ ] Rotate ALL exposed credentials (AWS, OIDC secrets, DB passwords)
  - [ ] Remove credentials from git history
  - [ ] Implement HashiCorp Vault or AWS Secrets Manager
  - [ ] Generate cryptographically random passwords (32+ chars)

- [x] **Authentication & Authorization** (mostly done)
  - [x] Implement TLS/HTTPS on all endpoints — Coder TLS on port 7443
  - [ ] Enable PKCE for all OAuth2 clients
  - [x] Implement AI Gateway authentication — LiteLLM per-user virtual keys
  - [x] Enable secure cookies (`CODER_SECURE_AUTH_COOKIE: "true"`)
  - [ ] Implement Single Logout for all services
  - [x] Enable rate limiting — per-key RPM limits + Coder API rate limiting (512 RPM)

- [x] **Container Security** (mostly done)
  - [x] Remove root privileges from Coder server — runs as UID 1000
  - [x] Remove unrestricted sudo from workspaces — restricted to read-only commands
  - [ ] Enable `no-new-privileges` security option
  - [ ] Add memory/CPU limits to all containers

- [ ] **Code Fixes**
  - [ ] Fix SQL injection in database scripts
  - [ ] Replace plaintext git credentials with SSH keys
  - [x] Restrict CORS to explicit origins — old gateway removed, LiteLLM handles CORS
  - [ ] Add input validation to all scripts and APIs

### Phase 2: Hardening (Week 3-4)

- [ ] **Network Security**
  - [x] Implement workspace egress filtering — iptables-based firewall, approved destinations only
  - [ ] Implement per-workspace network isolation (full isolation)
  - [ ] Enable PostgreSQL TLS (`sslmode=require`)
  - [ ] Configure mTLS for service-to-service communication
  - [ ] Restrict IP allowlists

- [ ] **Logging & Monitoring**
  - [ ] Configure log rotation for all containers
  - [ ] Implement centralized logging (ELK/Loki)
  - [ ] Add Prometheus metrics endpoints
  - [ ] Enable audit logging for auth events
  - [ ] Sanitize PII from logs

- [ ] **Error Handling**
  - [ ] Add proper error handling to all scripts
  - [ ] Implement cleanup traps for temporary files
  - [ ] Return generic error messages to clients
  - [ ] Add retry logic for transient failures

- [ ] **Validation**
  - [ ] Add input validation to all API endpoints
  - [ ] Validate API responses before processing
  - [ ] Implement request size limits
  - [ ] Add health checks for all services

### Phase 3: Operational Readiness (Week 5-6)

- [ ] **High Availability**
  - [ ] Configure database replication
  - [ ] Implement service redundancy
  - [ ] Add load balancing

- [ ] **Backup & Recovery**
  - [ ] Automate database backups
  - [ ] Test disaster recovery procedures
  - [ ] Document recovery time objectives

- [ ] **Compliance**
  - [ ] Enable MFA for admin accounts
  - [ ] Implement session timeout (4-8 hours max)
  - [ ] Add CSRF protection to all forms
  - [ ] Document security controls

---

## Quick Fix Commands

### Rotate AWS Credentials
```bash
# 1. Generate new credentials in AWS Console
# 2. Update .env file
# 3. Revoke old credentials
aws iam delete-access-key --access-key-id AKIA******************** --user-name <username>
```

### Regenerate OIDC Secrets in Authentik
```bash
docker exec authentik-server ak shell -c "
from authentik.providers.oauth2.models import OAuth2Provider
import secrets
for p in OAuth2Provider.objects.all():
    p.client_secret = secrets.token_urlsafe(64)
    p.save()
    print(f'{p.name}: {p.client_secret}')
"
```

### Enable Secure Configuration
```bash
# Update docker-compose.yml environment
CODER_SECURE_AUTH_COOKIE: "true"
CODER_RATE_LIMIT_DISABLE_ALL: "false"  # Remove this line entirely
```

### Add Resource Limits to Containers
```yaml
# Add to each service in docker-compose.yml
deploy:
  resources:
    limits:
      memory: 512M
      cpus: '1.0'
    reservations:
      memory: 256M
```

### Remove Git History Secrets
```bash
# Use git-filter-repo (safer than filter-branch)
pip install git-filter-repo
git filter-repo --invert-paths --path .env.sso --path .env
# Force push to remote (coordinate with team!)
```

---

## Architecture Improvements for Production

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         PRODUCTION ARCHITECTURE                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐                │
│  │   Traefik    │────▶│    Coder     │────▶│  Workspace   │                │
│  │   (TLS/LB)   │     │  (non-root)  │     │  (isolated)  │                │
│  └──────────────┘     └──────────────┘     └──────────────┘                │
│         │                    │                                              │
│         │              ┌─────▼─────┐                                        │
│         │              │  Vault    │  ◀── Secrets Management                │
│         │              └───────────┘                                        │
│         │                    │                                              │
│  ┌──────▼──────┐      ┌─────▼─────┐      ┌──────────────┐                  │
│  │  Authentik  │◀────▶│ PostgreSQL │◀────▶│    Redis     │                  │
│  │   (OIDC)    │      │  (TLS+HA)  │      │   (Cluster)  │                  │
│  └─────────────┘      └───────────┘      └──────────────┘                  │
│         │                                                                   │
│  ┌──────▼──────┐      ┌───────────┐      ┌──────────────┐                  │
│  │    Gitea    │      │   MinIO   │      │  AI Gateway  │                  │
│  │   (OIDC)    │      │  (OIDC)   │      │  (JWT Auth)  │                  │
│  └─────────────┘      └───────────┘      └──────────────┘                  │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                     MONITORING & LOGGING                              │  │
│  │  Prometheus  │  Grafana  │  Loki  │  Alertmanager                    │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Production Changes:
1. **TLS Termination** - Traefik handles all HTTPS
2. **Secrets Management** - Vault for all credentials
3. **Workspace Isolation** - Per-workspace networks
4. **Non-Root Containers** - All services run as non-root
5. **Database HA** - PostgreSQL with replication
6. **Centralized Logging** - Loki for log aggregation
7. **Monitoring** - Prometheus + Grafana for metrics

---

## Conclusion

This PoC successfully demonstrates the Coder WebIDE platform's capabilities for contractor development environments. Significant hardening has been completed since the initial review.

**Addressed since initial review:**
- TLS/HTTPS on Coder (port 7443, self-signed cert)
- Secure cookies enabled
- AI gateway replaced by LiteLLM with per-user key auth and content guardrails
- Sudo restricted to read-only commands
- Dangerous binaries removed (ssh, scp, nc, nmap, docker CLI)
- Network egress filtering (iptables-based firewall)
- Shell audit logging and idle timeout
- PATH lockdown (readonly)
- RBAC with OIDC group-to-role mapping

**Remaining for production:**
1. **Credential Management** - Secrets still in `.env` files (needs Vault/Secrets Manager)
2. **Authentication** - Missing PKCE, Single Logout
3. **Network Security** - No per-workspace isolation, no mTLS
4. **Operational Security** - Missing centralized logging, monitoring, backups
5. **Infrastructure** - No container memory limits, no HA/DR

**Estimated remaining effort to production-ready:** 3-4 weeks with dedicated focus (reduced from original 4-6 weeks due to hardening already completed).

---

*Generated by comprehensive PoC review - February 4, 2026*
*Updated: February 5, 2026 - Marked fixed issues (#3, #14, #15)*
*Updated: February 7, 2026 - Major refresh: marked 8 critical and 5 important items as fixed/addressed (TLS, sudo, AI gateway, egress controls, terminal security). Updated production readiness checklist and timeline.*
