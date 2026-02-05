# Coder WebIDE Production Implementation Plan

**Created:** February 4, 2026
**Based on:** PoC Security Review (68 issues identified)
**Status:** Planning Phase

---

## Overview

This document outlines the implementation plan to transform the Coder WebIDE PoC into a production-ready platform. The plan addresses all critical and important security issues identified in the comprehensive review.

---

## Phase 1: Foundation & Critical Security (Week 1-2)

### 1.1 Secrets Management Infrastructure

**Goal:** Eliminate all hardcoded credentials

**Tasks:**
1. Deploy HashiCorp Vault in Docker
2. Create secret paths for each service:
   - `secret/coder/database`
   - `secret/coder/oidc`
   - `secret/gitea/oidc`
   - `secret/minio/oidc`
   - `secret/ai-gateway/providers`
   - `secret/authentik/keys`
3. Create Vault policies per service (least privilege)
4. Implement secret injection via:
   - Docker secrets for compose
   - Vault Agent sidecar for dynamic secrets
5. Rotate ALL existing credentials:
   - AWS credentials (CRITICAL - already exposed)
   - OIDC client secrets
   - Database passwords
   - Service account tokens

**Deliverables:**
- `docker-compose.vault.yml` - Vault service configuration
- `vault/policies/` - Service-specific policies
- `vault/scripts/init-secrets.sh` - Secret initialization
- Updated `.env.template` (no actual secrets)

---

### 1.2 TLS/HTTPS Configuration

**Goal:** Encrypt all traffic

**Tasks:**
1. Deploy Traefik as reverse proxy with:
   - Let's Encrypt integration (production)
   - Self-signed certs (staging)
2. Configure TLS termination for:
   - Coder (7080 → 443)
   - Gitea (3000 → 443)
   - Authentik (9000 → 443)
   - MinIO Console (9001 → 443)
   - AI Gateway (8090 → 443)
3. Enable internal TLS:
   - PostgreSQL: `sslmode=require`
   - Redis: TLS enabled
4. Update all service URLs to HTTPS
5. Enable secure cookies on all services

**Deliverables:**
- `docker-compose.traefik.yml` - Traefik configuration
- `traefik/` - Dynamic configuration, certs
- Updated environment with HTTPS URLs

---

### 1.3 Authentication Hardening

**Goal:** Secure all authentication flows

**Tasks:**
1. Enable PKCE for all OAuth2 clients in Authentik
2. Implement Single Logout (SLO):
   - Configure Coder OIDC logout
   - Verify Gitea SLO works
   - Document MinIO limitations
3. Configure session management:
   - Max session: 8 hours
   - Idle timeout: 30 minutes
   - Secure cookie flags
4. Enable rate limiting:
   - Coder: Remove `RATE_LIMIT_DISABLE_ALL`
   - Configure per-endpoint limits
5. Implement AI Gateway authentication:
   - JWT validation middleware
   - Workspace token verification
   - Integration with Coder API

**Deliverables:**
- Updated Authentik provider configurations
- `ai-gateway/auth.py` - Authentication middleware
- Updated docker-compose environment

---

### 1.4 Container Security

**Goal:** Apply principle of least privilege

**Tasks:**
1. Create non-root Coder service account:
   - Create `coder` user in container
   - Configure Docker socket permissions via group
   - Test workspace provisioning
2. Remove workspace sudo access:
   - Remove `NOPASSWD:ALL` from Dockerfile
   - Identify required privileged operations
   - Implement specific sudo rules if needed
3. Enable security options:
   - `no-new-privileges: true`
   - Drop unnecessary capabilities
   - Read-only root filesystem where possible
4. Add resource limits to all containers:
   ```yaml
   deploy:
     resources:
       limits:
         memory: 512M
         cpus: '1.0'
   ```

**Deliverables:**
- Updated `docker-compose.yml` with security settings
- Updated workspace Dockerfile
- Resource limit configurations

---

## Phase 2: Code Fixes & Hardening (Week 3-4)

### 2.1 SQL Injection Remediation

**Goal:** Eliminate all SQL injection vulnerabilities

**Tasks:**
1. Refactor `provision-database.sh`:
   - Use parameterized queries via psql variables
   - Implement input validation regex
   - Add escaping helper functions
2. Refactor `manage-devdb.sh`:
   - Same parameterized query approach
   - Validate database names against allowlist pattern
3. Add input validation to all scripts:
   - Alphanumeric + underscore only for identifiers
   - Length limits
   - Character escaping

**Deliverables:**
- Refactored database scripts
- `scripts/lib/validation.sh` - Shared validation functions
- Unit tests for validation

---

### 2.2 Git Credential Security

**Goal:** Secure source code access

**Tasks:**
1. Replace plaintext credentials with SSH keys:
   - Generate per-workspace SSH keypairs
   - Configure Gitea to accept SSH
   - Update workspace provisioning
2. Alternative: OAuth token authentication:
   - Implement Gitea OAuth app
   - Generate short-lived tokens
   - Inject via credential helper
3. Remove `~/.git-credentials` file creation
4. Configure `credential.helper` properly

**Deliverables:**
- Updated `main.tf` for SSH-based git
- SSH key generation in workspace startup
- Gitea SSH configuration

---

### 2.3 AI Gateway Security

**Goal:** Production-ready API gateway

**Tasks:**
1. Implement JWT authentication:
   - Validate tokens from Coder
   - Extract workspace_id from token
   - Reject unauthenticated requests
2. Fix CORS configuration:
   - Read allowed origins from config
   - Remove wildcard origins
   - Proper credential handling
3. Implement proper rate limiting:
   - Per-workspace limits
   - Redis-backed state
   - Token-per-minute enforcement
4. Add request validation:
   - Model allowlist validation
   - Max tokens bounds checking
   - Request size limits
5. Implement health checks:
   - Actual provider connectivity tests
   - Cached results with TTL
   - Proper status codes

**Deliverables:**
- `ai-gateway/middleware/auth.py`
- `ai-gateway/middleware/ratelimit.py`
- `ai-gateway/validators.py`
- Updated `gateway.py`

---

### 2.4 Network Isolation

**Goal:** Isolate workspaces from each other

**Tasks:**
1. Design network architecture:
   - Management network (services)
   - Per-workspace networks
   - Egress-only for workspaces
2. Implement in Terraform template:
   - Create workspace-specific network
   - Connect only required services
   - Block inter-workspace traffic
3. Configure network policies:
   - Workspace → Gitea: Allow
   - Workspace → AI Gateway: Allow
   - Workspace → DevDB: Allow (own schema only)
   - Workspace → Workspace: Deny
4. Document network architecture

**Deliverables:**
- Updated `main.tf` with network isolation
- Network policy configurations
- Architecture documentation

---

## Phase 3: Operational Readiness (Week 5-6)

### 3.1 Logging & Monitoring

**Goal:** Full observability

**Tasks:**
1. Deploy logging stack:
   - Loki for log aggregation
   - Promtail for log collection
   - Configure log rotation
2. Deploy monitoring stack:
   - Prometheus for metrics
   - Grafana for dashboards
   - Alertmanager for alerts
3. Configure application logging:
   - Structured JSON logs
   - Correlation IDs
   - PII redaction
4. Create dashboards:
   - Workspace usage
   - AI Gateway usage/costs
   - Authentication events
   - Error rates
5. Configure alerts:
   - Service health
   - Error rate thresholds
   - Security events

**Deliverables:**
- `docker-compose.monitoring.yml`
- `grafana/dashboards/` - Dashboard definitions
- `prometheus/` - Alert rules
- `loki/` - Log pipeline config

---

### 3.2 Backup & Recovery

**Goal:** Data protection and disaster recovery

**Tasks:**
1. Implement database backups:
   - PostgreSQL pg_dump scheduled
   - Point-in-time recovery setup
   - Off-site backup storage (MinIO/S3)
2. Implement configuration backups:
   - Vault backup/unseal keys
   - Authentik configuration export
   - Gitea repository backup
3. Document recovery procedures:
   - Database restore
   - Service rebuild
   - Secret recovery
4. Test recovery procedures:
   - Tabletop exercise
   - Actual restore test

**Deliverables:**
- `scripts/backup/` - Backup scripts
- `docs/disaster-recovery.md`
- Tested recovery runbooks

---

### 3.3 Documentation & Runbooks

**Goal:** Operational documentation

**Tasks:**
1. Architecture documentation:
   - Component diagram
   - Network diagram
   - Data flow diagram
2. Operational runbooks:
   - Service startup/shutdown
   - Secret rotation
   - User provisioning
   - Troubleshooting guide
3. Security documentation:
   - Access control matrix
   - Incident response
   - Audit procedures
4. User documentation:
   - Contractor onboarding
   - Workspace usage
   - Git workflow

**Deliverables:**
- `docs/architecture/`
- `docs/runbooks/`
- `docs/security/`
- `docs/user-guide/`

---

## File Structure

```
coder-production/
├── PRODUCTION-PLAN.md          # This document
├── docker-compose.yml          # Main production compose
├── docker-compose.vault.yml    # Vault service
├── docker-compose.traefik.yml  # Traefik reverse proxy
├── docker-compose.monitoring.yml # Logging/monitoring
├── .env.template               # Environment template (no secrets)
├── vault/
│   ├── policies/               # Vault policies per service
│   ├── scripts/
│   │   └── init-secrets.sh     # Secret initialization
│   └── config.hcl              # Vault configuration
├── traefik/
│   ├── traefik.yml             # Static configuration
│   ├── dynamic/                # Dynamic configuration
│   └── certs/                  # Certificate storage
├── templates/
│   └── contractor-workspace/
│       ├── main.tf             # Hardened Terraform
│       └── build/
│           └── Dockerfile      # Secured workspace image
├── ai-gateway/
│   ├── gateway.py              # Secured gateway
│   ├── middleware/
│   │   ├── auth.py             # JWT authentication
│   │   └── ratelimit.py        # Redis rate limiting
│   ├── validators.py           # Input validation
│   └── config.yaml             # Production config
├── scripts/
│   ├── lib/
│   │   └── validation.sh       # Shared validation
│   ├── backup/
│   │   ├── backup-postgres.sh
│   │   └── backup-gitea.sh
│   ├── provision-database.sh   # Secured version
│   └── manage-devdb.sh         # Secured version
├── monitoring/
│   ├── prometheus/
│   │   ├── prometheus.yml
│   │   └── alerts/
│   ├── grafana/
│   │   └── dashboards/
│   └── loki/
│       └── config.yaml
└── docs/
    ├── architecture/
    │   ├── overview.md
    │   ├── network.md
    │   └── diagrams/
    ├── runbooks/
    │   ├── startup.md
    │   ├── secret-rotation.md
    │   └── troubleshooting.md
    ├── security/
    │   ├── access-control.md
    │   └── incident-response.md
    └── user-guide/
        ├── onboarding.md
        └── workspace-usage.md
```

---

## Implementation Order

### Week 1
| Day | Tasks |
|-----|-------|
| 1-2 | Deploy Vault, migrate secrets |
| 3-4 | Configure Traefik TLS |
| 5 | Update all service URLs to HTTPS |

### Week 2
| Day | Tasks |
|-----|-------|
| 1-2 | Authentication hardening (PKCE, SLO, sessions) |
| 3-4 | Container security (non-root, limits) |
| 5 | Testing and validation |

### Week 3
| Day | Tasks |
|-----|-------|
| 1-2 | SQL injection fixes |
| 3-4 | Git credential security (SSH keys) |
| 5 | AI Gateway authentication |

### Week 4
| Day | Tasks |
|-----|-------|
| 1-2 | AI Gateway hardening (rate limits, validation) |
| 3-4 | Network isolation |
| 5 | Integration testing |

### Week 5
| Day | Tasks |
|-----|-------|
| 1-2 | Deploy monitoring stack |
| 3-4 | Configure dashboards and alerts |
| 5 | Implement backup scripts |

### Week 6
| Day | Tasks |
|-----|-------|
| 1-2 | Test backup/recovery |
| 3-4 | Documentation |
| 5 | Final security review |

---

## Success Criteria

### Security
- [ ] Zero hardcoded credentials in codebase
- [ ] All traffic encrypted (TLS)
- [ ] PKCE enabled for all OAuth2 flows
- [ ] Single Logout working for all services
- [ ] No SQL injection vulnerabilities
- [ ] Workspaces isolated from each other
- [ ] AI Gateway requires authentication
- [ ] Rate limiting active on all endpoints

### Operational
- [ ] All services have health checks
- [ ] Logging aggregated and searchable
- [ ] Metrics available in Grafana
- [ ] Alerts configured for critical issues
- [ ] Backup/recovery tested
- [ ] Documentation complete

### Compliance
- [ ] Session timeouts configured
- [ ] Audit logging enabled
- [ ] Access control documented
- [ ] Incident response documented

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Service disruption during migration | Parallel deployment, gradual cutover |
| Secret exposure during rotation | Use Vault transit encryption |
| Network isolation breaks functionality | Thorough testing matrix |
| Performance degradation from TLS | Monitor latency, optimize ciphers |
| Monitoring overhead | Right-size retention, sampling |

---

## Dependencies

### External
- Domain name and DNS configuration
- TLS certificates (Let's Encrypt or purchased)
- Sufficient compute resources for monitoring stack

### Internal
- Team availability for testing
- Security review sign-off
- Stakeholder approval for downtime windows

---

## Next Steps

1. **Immediate:** Rotate exposed AWS credentials
2. **This week:** Begin Vault deployment
3. **Review:** Schedule security review for Week 6
4. **Approval:** Get stakeholder sign-off on this plan

---

*Plan created from PoC Security Review findings - February 4, 2026*
