# Coder WebIDE PoC - Comprehensive Security Review

**Review Date:** February 4, 2026
**Status:** Pre-Production Assessment
**Overall Risk Level:** HIGH - Not production-ready

---

## Executive Summary

This comprehensive review of the Coder WebIDE Proof of Concept identified **68 security and configuration issues** across 5 areas. The PoC successfully demonstrates the intended functionality but requires significant hardening before production deployment.

**Update (February 2026):** Several critical issues have been addressed. See strikethrough items below.

### Issue Breakdown by Severity

| Severity | Count | Fixed | Remaining | Description |
|----------|-------|-------|-----------|-------------|
| **CRITICAL** | 16 | 2 | 14 | Must fix before ANY production use |
| **IMPORTANT** | 28 | 0 | 28 | Must fix before public/multi-tenant deployment |
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

### 4. Unrestricted Sudo in Workspaces
**Location:** `templates/contractor-workspace/build/Dockerfile` (line 108)
```dockerfile
echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/nopasswd
```
**Action:** Remove sudo entirely or restrict to specific commands only

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

### 7. HTTP-Only Communication (No TLS)
**Location:** All services
- All OAuth2/OIDC callbacks use HTTP
- Database connections use `sslmode=disable`
**Action:** Implement TLS for all endpoints, enable secure cookies

### 8. Missing Authentication on AI Gateway
**Location:** `ai-gateway/gateway.py`
- All endpoints accessible without any authentication
**Action:** Implement JWT token validation for all endpoints

### 9. Open CORS Configuration
**Location:** `ai-gateway/gateway.py` (lines 143-150)
```python
allow_origins=["*"],
allow_credentials=True,
```
**Action:** Restrict to explicit allowed origins only

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

### 15. Secure Cookies Configurable (Default: Disabled for PoC)
**Location:** `docker-compose.yml`
```yaml
CODER_SECURE_AUTH_COOKIE: "${CODER_SECURE_AUTH_COOKIE:-false}"
```
**Status:** PARTIALLY ADDRESSED - Now configurable via environment variable. Enable in production by setting `CODER_SECURE_AUTH_COOKIE=true` (requires HTTPS)

### 16. Missing Network Isolation Between Workspaces
**Location:** `templates/contractor-workspace/main.tf`
- All workspaces on same Docker network
**Action:** Create per-workspace networks or implement network policies

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

### AI Gateway
1. No request validation (no bounds checking)
2. Weak rate limiting (IP-based only, no per-workspace)
3. Sensitive data potentially in logs
4. Missing health checks for upstream providers
5. Incomplete error handling (leaks implementation details)

---

## Production Readiness Checklist

### Phase 1: Critical Security (Week 1-2)

- [ ] **Secrets Management**
  - [ ] Rotate ALL exposed credentials (AWS, OIDC secrets, DB passwords)
  - [ ] Remove credentials from git history
  - [ ] Implement HashiCorp Vault or AWS Secrets Manager
  - [ ] Generate cryptographically random passwords (32+ chars)

- [ ] **Authentication & Authorization**
  - [ ] Implement TLS/HTTPS on all endpoints
  - [ ] Enable PKCE for all OAuth2 clients
  - [ ] Implement AI Gateway authentication (JWT)
  - [ ] Enable secure cookies (`CODER_SECURE_AUTH_COOKIE: "true"`)
  - [ ] Implement Single Logout for all services
  - [ ] Enable rate limiting

- [ ] **Container Security**
  - [ ] Remove root privileges from Coder server
  - [ ] Remove unrestricted sudo from workspaces
  - [ ] Enable `no-new-privileges` security option
  - [ ] Add memory/CPU limits to all containers

- [ ] **Code Fixes**
  - [ ] Fix SQL injection in database scripts
  - [ ] Replace plaintext git credentials with SSH keys
  - [ ] Restrict CORS to explicit origins
  - [ ] Add input validation to all scripts and APIs

### Phase 2: Hardening (Week 3-4)

- [ ] **Network Security**
  - [ ] Implement workspace network isolation
  - [ ] Enable PostgreSQL TLS (`sslmode=require`)
  - [ ] Configure mTLS for service-to-service communication
  - [ ] Restrict CORS and IP allowlists

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

This PoC successfully demonstrates the Coder WebIDE platform's capabilities for contractor development environments. However, it requires significant security hardening before production deployment, particularly around:

1. **Credential Management** - Currently exposes real secrets
2. **Authentication** - Missing TLS, PKCE, proper session handling
3. **Authorization** - Missing AI Gateway auth, excessive sudo privileges
4. **Network Security** - No workspace isolation, no mTLS
5. **Operational Security** - Missing logging, monitoring, backups

**Estimated effort to production-ready:** 4-6 weeks with dedicated security focus.

---

*Generated by comprehensive PoC review - February 4, 2026*
*Updated: February 5, 2026 - Marked fixed issues (#3, #14, #15)*
