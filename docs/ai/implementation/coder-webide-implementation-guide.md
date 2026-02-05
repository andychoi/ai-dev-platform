# Coder WebIDE Secure Development Platform - Implementation Guide

## Executive Summary

This document provides a comprehensive guide for implementing a secure web-based development platform using Coder for contractor access. The platform addresses the security requirement that prohibits remote shell, RDP, and database connections from untrusted devices while enabling productive development workflows.

---

## 1. Concept & Approach

### 1.1 Problem Statement

**Current Security Posture:**
- Remote shell access from untrusted devices: **BLOCKED**
- RDP connections from untrusted devices: **BLOCKED**
- Direct database connections from untrusted devices: **BLOCKED**

**Business Need:**
- Contractors require development environment access
- Code must remain within the security perimeter
- Audit trail required for all development activities

### 1.2 Solution Concept

```
┌────────────────────────────────────────────────────────────────────────────┐
│                           UNTRUSTED ZONE                                    │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │                    Contractor's Device                               │  │
│  │  ┌─────────────┐                                                    │  │
│  │  │   Browser   │  ◄── Only HTTPS (443) traffic                      │  │
│  │  │   Only      │      No local code storage                         │  │
│  │  └─────────────┘      No direct network access                      │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ HTTPS Only
                                    ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                           SECURE ZONE (DMZ)                                 │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │  WAF → Load Balancer → Coder Server                                 │  │
│  │                            │                                         │  │
│  │                    ┌───────┴───────┐                                │  │
│  │                    ▼               ▼                                │  │
│  │            ┌─────────────┐  ┌─────────────┐                        │  │
│  │            │ Workspace A │  │ Workspace B │  ◄── Isolated           │  │
│  │            │ (VS Code)   │  │ (VS Code)   │      Containers         │  │
│  │            └─────────────┘  └─────────────┘                        │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────┘
                                    │
                              Controlled Access
                                    ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                           INTERNAL ZONE                                     │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐          │
│  │ Git Server │  │ Databases  │  │ CI/CD      │  │ Artifacts  │          │
│  │ (Gitea)    │  │ (Proxied)  │  │ (Drone)    │  │ Registry   │          │
│  └────────────┘  └────────────┘  └────────────┘  └────────────┘          │
└────────────────────────────────────────────────────────────────────────────┘
```

### 1.3 Key Security Principles

| Principle | Implementation |
|-----------|----------------|
| **Zero Trust** | No implicit trust for contractor devices |
| **Least Privilege** | Access only to assigned projects |
| **Defense in Depth** | Multiple security layers |
| **Audit Everything** | Complete activity logging |
| **Data Never Leaves** | Code stays in secure zone |

### 1.4 Technology Stack

| Component | Technology | Purpose |
|-----------|------------|---------|
| WebIDE Platform | Coder (OSS) | Workspace orchestration |
| Code Editor | code-server (VS Code) | Browser-based IDE |
| Git Server | Gitea 1.25.4 | Source code management |
| CI/CD | Drone CI | Continuous integration |
| Container Runtime | Docker / Kubernetes | Workspace isolation |
| Database | PostgreSQL | Metadata storage |

---

## 2. Architecture

### 2.1 Component Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Coder Control Plane                          │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                      coderd                                │  │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐     │  │
│  │  │   API   │  │  Auth   │  │Provision│  │  Audit  │     │  │
│  │  │ Server  │  │  (OIDC) │  │  Daemon │  │  Logger │     │  │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘     │  │
│  └───────────────────────────────────────────────────────────┘  │
│                            │                                     │
│                     ┌──────┴──────┐                             │
│                     ▼             ▼                             │
│              ┌──────────┐  ┌──────────┐                        │
│              │PostgreSQL│  │  Redis   │                        │
│              │(Metadata)│  │(Pub/Sub) │                        │
│              └──────────┘  └──────────┘                        │
└─────────────────────────────────────────────────────────────────┘
                            │
              Terraform Provisioning
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Workspace Data Plane                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │ Workspace 1 │  │ Workspace 2 │  │ Workspace N │            │
│  │ ┌─────────┐ │  │ ┌─────────┐ │  │ ┌─────────┐ │            │
│  │ │code-srv │ │  │ │code-srv │ │  │ │code-srv │ │            │
│  │ │(VS Code)│ │  │ │(VS Code)│ │  │ │(VS Code)│ │            │
│  │ └─────────┘ │  │ └─────────┘ │  │ └─────────┘ │            │
│  │ ┌─────────┐ │  │ ┌─────────┐ │  │ ┌─────────┐ │            │
│  │ │  Agent  │ │  │ │  Agent  │ │  │ │  Agent  │ │            │
│  │ └─────────┘ │  │ └─────────┘ │  │ └─────────┘ │            │
│  │     │       │  │     │       │  │     │       │            │
│  │     ▼       │  │     ▼       │  │     ▼       │            │
│  │ ┌─────────┐ │  │ ┌─────────┐ │  │ ┌─────────┐ │            │
│  │ │   PVC   │ │  │ │   PVC   │ │  │ │   PVC   │ │            │
│  │ │(Storage)│ │  │ │(Storage)│ │  │ │(Storage)│ │            │
│  │ └─────────┘ │  │ └─────────┘ │  │ └─────────┘ │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Network Architecture

```
Internet                    DMZ                         Internal
─────────              ─────────────                 ─────────────
    │                       │                             │
    │     ┌─────────┐      │                             │
    ├────►│   WAF   │      │                             │
    │     └────┬────┘      │                             │
    │          │           │                             │
    │     ┌────▼────┐      │                             │
    │     │   LB    │      │                             │
    │     │(TLS 1.3)│      │                             │
    │     └────┬────┘      │                             │
    │          │           │                             │
    │     ┌────▼────┐      │      ┌──────────┐          │
    │     │  Coder  │◄─────┼─────►│  Gitea   │          │
    │     │ Server  │      │      │(Git SSH) │          │
    │     └────┬────┘      │      └──────────┘          │
    │          │           │            │               │
    │     ┌────▼────┐      │      ┌─────▼─────┐        │
    │     │Workspace│◄─────┼─────►│ Drone CI  │        │
    │     │  Pods   │      │      └───────────┘        │
    │     └─────────┘      │                            │
    │                      │                            │

Network Rules:
─────────────
[Internet → WAF]     : HTTPS (443) only
[WAF → Coder]        : Validated requests
[Coder → Workspace]  : WireGuard tunnel
[Workspace → Gitea]  : Git (HTTP/SSH)
[Workspace → Drone]  : Webhook callbacks
[Workspace → DB]     : BLOCKED (use proxy)
[Workspace → Internet]: BLOCKED (egress filtered)
```

### 2.3 Authentication Flow

```
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│Contractor│     │  Coder   │     │   IdP    │     │Workspace │
│ Browser  │     │  Server  │     │(SSO/OIDC)│     │          │
└────┬─────┘     └────┬─────┘     └────┬─────┘     └────┬─────┘
     │                │                │                │
     │  1. Access     │                │                │
     │───────────────►│                │                │
     │                │                │                │
     │  2. Redirect   │                │                │
     │◄───────────────│                │                │
     │                │                │                │
     │  3. Auth + MFA │                │                │
     │────────────────────────────────►│                │
     │                │                │                │
     │  4. Auth Code  │                │                │
     │◄────────────────────────────────│                │
     │                │                │                │
     │  5. Exchange   │                │                │
     │───────────────►│  6. Validate   │                │
     │                │───────────────►│                │
     │                │  7. User Info  │                │
     │                │◄───────────────│                │
     │  8. Session    │                │                │
     │◄───────────────│                │                │
     │                │                │                │
     │  9. Create WS  │                │                │
     │───────────────►│  10. Provision │                │
     │                │───────────────────────────────►│
     │                │                │                │
     │  11. WS URL    │                │  12. Ready    │
     │◄───────────────│◄───────────────────────────────│
     │                │                │                │
     │  13. Access VS Code in Browser  │                │
     │────────────────────────────────────────────────►│
     │                │                │                │
```

---

## 3. PoC Implementation

### 3.1 PoC Scope

| In Scope | Out of Scope |
|----------|--------------|
| Coder deployment (Docker) | Kubernetes deployment |
| Gitea Git server | Enterprise Git (GitLab/GitHub) |
| SSO/OIDC via Authentik | Production IdP integration |
| Basic access control | Full RBAC |
| Docker isolation | NetworkPolicy isolation |

> **Note:** The PoC includes full SSO/OIDC authentication via Authentik, providing a realistic authentication flow for contractor access.

### 3.2 PoC Components

```
coder-poc/
├── docker-compose.yml          # 14 services orchestration
├── docker-compose.sso.yml      # SSO configuration variant
├── .env.example                # Configuration template
├── postgres/
│   └── init.sql               # Multi-database init
├── gitea/
│   └── app.ini                # Git server config
├── ai-gateway/                 # AI proxy service
│   ├── gateway.py
│   ├── config.yaml
│   └── Dockerfile
├── platform-admin/             # Admin dashboard
│   └── Dockerfile
├── devdb/                      # Developer databases
│   └── init.sql
├── testdb/                     # Test database
│   └── init.sql
├── templates/
│   └── contractor-workspace/
│       ├── main.tf
│       └── build/
│           ├── Dockerfile
│           ├── settings.json
│           └── continue-config.json
├── sample-projects/
│   └── python-app/
└── scripts/                    # 14 operational scripts
    ├── setup.sh
    ├── setup-gitea.sh
    ├── setup-authentik-sso.sh
    ├── setup-coder-users.sh
    ├── validate.sh
    ├── validate-security.sh
    ├── test-access-control.sh
    ├── provision-database.sh
    ├── manage-devdb.sh
    └── cleanup.sh
```

**PoC Services (14 containers):**

| Service | Purpose |
|---------|---------|
| **Coder** | WebIDE platform and workspace orchestration |
| **PostgreSQL** | Metadata storage for Coder and other services |
| **Redis** | Pub/Sub for Coder |
| **Gitea** | Git server for source code management |
| **Authentik** (3 containers) | OIDC provider: server, worker, PostgreSQL |
| **AI Gateway** | Custom proxy for AI API access |
| **DevDB** | Developer PostgreSQL databases |
| **TestDB** | Isolated test database |
| **MinIO** | Object storage (S3-compatible) |
| **Mailpit** | Email testing service |
| **Platform Admin** | Admin dashboard |

### 3.3 Test Users & Access Matrix

```
┌─────────────────┬────────────┬────────────┬────────────┬──────────┐
│ Repository      │ contractor1│ contractor2│ contractor3│ readonly │
├─────────────────┼────────────┼────────────┼────────────┼──────────┤
│ python-sample   │ ✓ Write    │ ✓ Write    │ ✗ None     │ ○ Read   │
│ private-project │ ✓ Write    │ ✗ None     │ ✗ None     │ ✗ None   │
│ shared-libs     │ ○ Read     │ ○ Read     │ ✓ Write    │ ✗ None   │
│ frontend-app    │ ✗ None     │ ✗ None     │ ✗ None     │ ✗ None   │
└─────────────────┴────────────┴────────────┴────────────┴──────────┘

Legend: ✓ Write  ○ Read  ✗ No Access
```

### 3.4 CI Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│                    Drone CI Pipeline                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   │
│  │ Install  │──►│  Format  │──►│   Lint   │──►│  Type    │   │
│  │   deps   │   │  (Black) │   │ (Flake8) │   │  (MyPy)  │   │
│  └──────────┘   └──────────┘   └──────────┘   └────┬─────┘   │
│                                                      │         │
│                                                      ▼         │
│                                               ┌──────────┐     │
│                                               │   Test   │     │
│                                               │ (Pytest) │     │
│                                               │  80% cov │     │
│                                               └────┬─────┘     │
│                                                    │           │
│                                                    ▼           │
│                                               ┌──────────┐     │
│                                               │  Build   │     │
│                                               │  Verify  │     │
│                                               └──────────┘     │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│ Triggers: Push to main/develop, feature/* branches, PRs        │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. Limitations & Remediation

### 4.1 Developer Tool Limitations

| Native Tool | Limitation | Remediation | Effort |
|-------------|------------|-------------|--------|
| **Visual Studio** | No WinForms/WPF designer | JetBrains Rider via Gateway | High |
| **IntelliJ** | Different keybindings, less refactoring | IntelliJ keymap extension, Gateway | Medium |
| **Toad SQL** | No visual query builder | CloudBeaver integration | Medium |
| **Claude CLI** | Network restrictions | Pre-install + API gateway | Low |

### 4.2 Platform Limitations

| Limitation | Impact | Remediation |
|------------|--------|-------------|
| Browser-only access | Latency for typing | JetBrains Gateway for native feel |
| No file download | Can't export locally | Git push to approved repos |
| No clipboard to local | Can't copy secrets out | By design (security) |
| Session timeout | Work interruption | Auto-save, longer sessions |
| Resource limits | Large builds slow | Tiered resource options |

### 4.3 PoC vs Production Gap

> **Production Roadmap:** A comprehensive 6-week production implementation plan is available at [coder-production/PRODUCTION-PLAN.md](../../../coder-production/PRODUCTION-PLAN.md). This plan addresses 68 security issues identified during PoC review, covering:
> - Week 1-2: Foundation & Critical Security (Vault, TLS, authentication hardening)
> - Week 3-4: Code Fixes & Hardening (SQL injection, SSH keys, network isolation)
> - Week 5-6: Operational Readiness (logging, monitoring, backup)

| Aspect | PoC | Production Required |
|--------|-----|---------------------|
| **Authentication** | SSO/OIDC via Authentik | Production IdP + MFA |
| **Network** | Docker bridge | K8s NetworkPolicy |
| **TLS** | Disabled | TLS 1.3 required |
| **Secrets** | Environment vars | HashiCorp Vault |
| **Audit** | Basic logs | SIEM integration |
| **HA** | Single instance | Multi-replica + HPA |
| **Backup** | None | Automated snapshots |

### 4.4 Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Data exfiltration | Medium | High | Egress filtering, audit logs |
| Container escape | Low | Critical | Pod security policies |
| Credential theft | Medium | High | Short-lived tokens, rotation |
| DoS attack | Medium | Medium | Rate limiting, resource quotas |
| Developer rejection | High | Medium | Training, tool alternatives |

---

## 5. Validation Approach

### 5.1 Test Categories

```
┌─────────────────────────────────────────────────────────────────┐
│                    Validation Test Suite                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │  Infrastructure │  │  Access Control │  │   CI Pipeline   │ │
│  │     Tests       │  │      Tests      │  │     Tests       │ │
│  ├─────────────────┤  ├─────────────────┤  ├─────────────────┤ │
│  │ • Service health│  │ • Auth success  │  │ • Trigger on    │ │
│  │ • API endpoints │  │ • Auth failure  │  │   push          │ │
│  │ • Network conn  │  │ • Read access   │  │ • All stages    │ │
│  │ • Template avail│  │ • Write access  │  │   pass          │ │
│  │ • WS lifecycle  │  │ • No access     │  │ • Coverage met  │ │
│  └─────────────────┘  │ • Admin vs user │  │ • Artifacts     │ │
│                       └─────────────────┘  └─────────────────┘ │
│                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │   Isolation     │  │   Developer     │  │    Security     │ │
│  │     Tests       │  │   Workflow      │  │     Tests       │ │
│  ├─────────────────┤  ├─────────────────┤  ├─────────────────┤ │
│  │ • Cross-WS file │  │ • Clone repo    │  │ • Egress block  │ │
│  │ • Cross-WS net  │  │ • Edit code     │  │ • Credential    │ │
│  │ • Resource caps │  │ • Run tests     │  │   security      │ │
│  │ • Container iso │  │ • Commit/push   │  │ • Session mgmt  │ │
│  └─────────────────┘  │ • Trigger CI    │  │ • Audit logging │ │
│                       └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 Success Criteria

| Criterion | Threshold | Measurement |
|-----------|-----------|-------------|
| Access control accuracy | 100% | All tests pass |
| Workspace isolation | 100% | No cross-access |
| CI/CD integration | Working | Pipeline executes |
| Startup time | < 2 min | Workspace ready |
| Developer satisfaction | > 3.5/5 | Survey results |

### 5.3 Test Execution

```bash
# 1. Start environment
docker compose up -d

# 2. Setup Git server with users/repos
./scripts/setup-gitea.sh

# 3. Run infrastructure validation
./scripts/validate.sh

# 4. Run access control tests
./scripts/test-access-control.sh

# 5. Manual CI test
# - Clone repo in workspace
# - Make change and push
# - Verify Drone pipeline runs
```

---

## 6. Implementation Roadmap

### Phase 1: PoC Validation (Current)

```
Week 1-2: Local Docker PoC
├── ✓ Coder server deployment
├── ✓ Gitea Git server setup
├── ✓ Drone CI integration
├── ✓ Workspace template creation
├── ✓ Access control configuration
└── ✓ Validation test suite
```

### Phase 2: Security Hardening

```
Week 3-4: Production Preparation
├── SSO/OIDC integration
├── TLS certificate setup
├── Vault secrets integration
├── Audit log shipping
├── Network policy design
└── Security review
```

### Phase 3: Pilot Deployment

```
Week 5-6: Limited Rollout
├── Select 5-10 pilot contractors
├── Training sessions
├── Monitor usage/feedback
├── Iterate on templates
└── Document learnings
```

### Phase 4: Production Deployment

```
Week 7-10: Full Rollout
├── Kubernetes deployment
├── HA configuration
├── Monitoring/alerting
├── User onboarding
├── Legacy access sunset
└── Operational handoff
```

---

## 7. Documentation Index

| Document | Location | Purpose |
|----------|----------|---------|
| Requirements | `docs/ai/requirements/coder-webide-integration.md` | Functional/non-functional requirements |
| Design | `docs/ai/design/coder-webide-integration.md` | Architecture and design decisions |
| Planning | `docs/ai/planning/coder-webide-integration.md` | Implementation plan and tasks |
| Limitations | `docs/ai/requirements/coder-webide-limitations-remediation.md` | Tool limitations and remediation |
| Test Scenarios | `docs/ai/testing/coder-webide-access-control-tests.md` | Access control test cases |
| PoC README | `coder-poc/README.md` | Quick start and usage guide |

---

## 8. Conclusion

### Is This Approach Feasible?

**Yes.** The PoC demonstrates that:

1. **Secure access is achievable** - Browser-only access eliminates direct network exposure
2. **Developer productivity is maintainable** - VS Code web provides familiar experience
3. **Access control works** - Git-level permissions enforce project boundaries
4. **CI/CD integrates cleanly** - Standard pipelines work without modification
5. **Audit capability exists** - All actions can be logged and reviewed

### Is This Enough for Validation?

**Yes.** The PoC validates:

| Requirement | Validation Method |
|-------------|-------------------|
| No shell access from untrusted devices | All access via browser |
| No RDP from untrusted devices | Web-only IDE |
| No direct DB access | Workspace isolation |
| Code stays in secure zone | No file download |
| Audit trail | Activity logging |
| Access control | Permission matrix tested |

### Recommended Next Steps

1. **Run the PoC** - Follow setup instructions
2. **Execute test suite** - Validate all scenarios
3. **Gather feedback** - From potential pilot users
4. **Security review** - Before production planning
5. **Budget approval** - For production infrastructure
