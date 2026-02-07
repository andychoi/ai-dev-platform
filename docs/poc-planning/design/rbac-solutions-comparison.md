# RBAC Solutions Comparison for Dev Platform

## Overview

This document compares options for Role-Based Access Control (RBAC) administration for the Dev Platform, including custom development vs open-source solutions.

---

## Requirements Summary

| Requirement | Priority | Notes |
|-------------|----------|-------|
| Azure AD integration (OIDC/SAML) | P0 | Existing IdP |
| Group-to-role mapping | P0 | Sync AD groups to platform roles |
| Admin UI for non-technical users | P0 | HR/Managers manage access |
| Audit logging | P0 | Compliance requirement |
| API for automation | P1 | CI/CD integration |
| Self-service requests | P2 | Contractors request access |
| Approval workflows | P2 | Manager approval |
| Time-bound access | P2 | Contractor engagement periods |

---

## Options Comparison

### Quick Comparison Matrix

| Solution | Complexity | Azure AD | Admin UI | Cost | Best For |
|----------|------------|----------|----------|------|----------|
| **Coder Built-in** | Low | ✅ OIDC | ⚠️ Basic | Free | Simple setups |
| **Custom App** | High | ✅ Full | ✅ Custom | Dev time | Specific needs |
| **Keycloak** | Medium | ✅ Full | ✅ Rich | Free | Enterprise |
| **Authentik** | Medium | ✅ Full | ✅ Modern | Free | Modern stack |
| **Zitadel** | Low | ✅ Full | ✅ Good | Free/Paid | Cloud-native |
| **Casdoor** | Low | ✅ Good | ✅ Simple | Free | Simple needs |

---

## Option 1: Coder Built-in RBAC

### Architecture
```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Azure AD   │────▶│   Coder     │────▶│ Workspaces  │
│  (Groups)   │OIDC │  (RBAC)     │     │             │
└─────────────┘     └─────────────┘     └─────────────┘
```

### Capabilities

| Feature | Support | Notes |
|---------|---------|-------|
| OIDC Integration | ✅ | Native Azure AD support |
| Group Sync | ✅ | Via OIDC claims |
| Template ACLs | ✅ | Group-based permissions |
| User Quotas | ✅ | CPU, memory, workspaces |
| Admin UI | ⚠️ | Basic, CLI-focused |
| Audit Logs | ✅ | Built-in |
| Approval Workflows | ❌ | Not supported |
| Self-Service | ⚠️ | Limited |

### Pros
- Zero additional infrastructure
- Native integration
- No sync issues

### Cons
- Limited admin UI
- No approval workflows
- Basic reporting

### When to Use
- Small teams (< 50 contractors)
- Simple permission models
- Technical admins comfortable with CLI

---

## Option 2: Custom RBAC Admin App

### Architecture
```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Azure AD   │────▶│ RBAC Admin  │────▶│   Coder     │
│             │     │    App      │     │   API       │
└─────────────┘     └─────────────┘     └─────────────┘
                          │
                    ┌─────┴─────┐
                    │ PostgreSQL│
                    │ (State)   │
                    └───────────┘
```

### Suggested Tech Stack

| Layer | Technology | Reason |
|-------|------------|--------|
| Frontend | React + Tailwind | Modern, maintainable |
| Backend | FastAPI (Python) | Quick development, async |
| Database | PostgreSQL | Consistent with Coder |
| Auth | MSAL (Azure AD SDK) | Native integration |

### Core Features to Build

```python
# Core Models
class Role(BaseModel):
    id: str
    name: str  # e.g., "contractor-alpha", "contractor-beta"
    permissions: List[Permission]
    coder_template: str  # Maps to Coder template
    quotas: ResourceQuota

class UserAssignment(BaseModel):
    user_email: str
    azure_ad_id: str
    roles: List[str]
    valid_from: datetime
    valid_until: datetime  # Time-bound access
    approved_by: str
    status: str  # pending, active, expired, revoked

class AccessRequest(BaseModel):
    requester: str
    requested_role: str
    justification: str
    project: str
    duration_days: int
    approver: str
    status: str  # pending, approved, rejected
```

### Estimated Development Effort

| Component | Effort | Notes |
|-----------|--------|-------|
| Backend API | 2-3 weeks | CRUD, Azure AD, Coder API |
| Admin UI | 2-3 weeks | User mgmt, roles, audit |
| Azure AD Sync | 1 week | Group sync, user provisioning |
| Coder Integration | 1 week | Template/user sync |
| Approval Workflow | 1-2 weeks | Request/approve flow |
| Audit & Reporting | 1 week | Logs, dashboards |
| **Total** | **8-12 weeks** | 1-2 developers |

### Pros
- Fully customized to needs
- Complete control over UX
- Can implement any workflow
- No vendor dependency

### Cons
- Significant development effort
- Ongoing maintenance burden
- Security responsibility
- Slower time to value

### When to Use
- Very specific workflow requirements
- Strong internal development capacity
- Long-term strategic investment

---

## Option 3: Keycloak (Recommended for Enterprise)

### Architecture
```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Azure AD   │────▶│  Keycloak   │────▶│   Coder     │
│  (Identity) │SAML │  (RBAC)     │OIDC │             │
└─────────────┘     └─────────────┘     └─────────────┘
                          │
                    ┌─────┴─────┐
                    │ PostgreSQL│
                    └───────────┘
```

### Features

| Feature | Support | Notes |
|---------|---------|-------|
| Azure AD Integration | ✅ | SAML/OIDC federation |
| Admin Console | ✅ | Full-featured web UI |
| User Federation | ✅ | Sync from Azure AD |
| Fine-grained RBAC | ✅ | Roles, groups, permissions |
| Approval Workflows | ⚠️ | Via extensions |
| Audit Logging | ✅ | Comprehensive |
| API | ✅ | REST Admin API |
| Custom Themes | ✅ | Branding support |

### Docker Compose Addition

```yaml
keycloak:
  image: quay.io/keycloak/keycloak:24.0
  container_name: keycloak
  command: start-dev
  environment:
    - KEYCLOAK_ADMIN=admin
    - KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_PASSWORD:-admin}
    - KC_DB=postgres
    - KC_DB_URL=jdbc:postgresql://keycloak-db:5432/keycloak
    - KC_DB_USERNAME=keycloak
    - KC_DB_PASSWORD=${KEYCLOAK_DB_PASSWORD:-keycloak}
  ports:
    - "8180:8080"
  networks:
    - coder-network
  depends_on:
    - keycloak-db

keycloak-db:
  image: postgres:15-alpine
  container_name: keycloak-db
  environment:
    - POSTGRES_DB=keycloak
    - POSTGRES_USER=keycloak
    - POSTGRES_PASSWORD=${KEYCLOAK_DB_PASSWORD:-keycloak}
  volumes:
    - keycloak_data:/var/lib/postgresql/data
  networks:
    - coder-network
```

### Pros
- Industry standard, battle-tested
- Rich admin UI
- Extensive documentation
- Large community
- Red Hat backing

### Cons
- Can be complex to configure
- Resource intensive (Java)
- Learning curve
- Overkill for simple needs

### When to Use
- Enterprise environments
- Complex permission models
- Multiple applications to secure
- Need for compliance certifications

---

## Option 4: Authentik (Recommended for Modern Stack)

### Architecture
```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Azure AD   │────▶│  Authentik  │────▶│   Coder     │
│             │OIDC │             │OIDC │             │
└─────────────┘     └─────────────┘     └─────────────┘
```

### Features

| Feature | Support | Notes |
|---------|---------|-------|
| Azure AD Integration | ✅ | OIDC/SAML |
| Admin Console | ✅ | Modern, intuitive |
| User Federation | ✅ | LDAP, SCIM |
| RBAC | ✅ | Groups, roles |
| Approval Workflows | ✅ | Built-in flows |
| Audit Logging | ✅ | Comprehensive |
| API | ✅ | REST + GraphQL |
| Self-Service | ✅ | User portal |

### Docker Compose Addition

```yaml
authentik-server:
  image: ghcr.io/goauthentik/server:2024.2
  container_name: authentik-server
  command: server
  environment:
    - AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}
    - AUTHENTIK_REDIS__HOST=authentik-redis
    - AUTHENTIK_POSTGRESQL__HOST=authentik-db
    - AUTHENTIK_POSTGRESQL__USER=authentik
    - AUTHENTIK_POSTGRESQL__PASSWORD=${AUTHENTIK_DB_PASSWORD:-authentik}
    - AUTHENTIK_POSTGRESQL__NAME=authentik
  ports:
    - "9000:9000"
    - "9443:9443"
  networks:
    - coder-network
  depends_on:
    - authentik-db
    - authentik-redis

authentik-worker:
  image: ghcr.io/goauthentik/server:2024.2
  container_name: authentik-worker
  command: worker
  environment:
    - AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}
    - AUTHENTIK_REDIS__HOST=authentik-redis
    - AUTHENTIK_POSTGRESQL__HOST=authentik-db
    - AUTHENTIK_POSTGRESQL__USER=authentik
    - AUTHENTIK_POSTGRESQL__PASSWORD=${AUTHENTIK_DB_PASSWORD:-authentik}
    - AUTHENTIK_POSTGRESQL__NAME=authentik
  networks:
    - coder-network

authentik-db:
  image: postgres:15-alpine
  container_name: authentik-db
  environment:
    - POSTGRES_DB=authentik
    - POSTGRES_USER=authentik
    - POSTGRES_PASSWORD=${AUTHENTIK_DB_PASSWORD:-authentik}
  volumes:
    - authentik_db:/var/lib/postgresql/data
  networks:
    - coder-network

authentik-redis:
  image: redis:alpine
  container_name: authentik-redis
  networks:
    - coder-network
```

### Pros
- Modern UI/UX
- Python-based (easier to extend)
- Built-in approval workflows
- Lighter than Keycloak
- Active development

### Cons
- Younger project than Keycloak
- Smaller community
- Fewer enterprise deployments

### When to Use
- Modern infrastructure
- Need approval workflows out-of-box
- Prefer Python ecosystem
- Want modern admin experience

---

## Option 5: Zitadel (Cloud-Native)

### Architecture
```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Azure AD   │────▶│   Zitadel   │────▶│   Coder     │
│             │OIDC │             │OIDC │             │
└─────────────┘     └─────────────┘     └─────────────┘
```

### Features

| Feature | Support | Notes |
|---------|---------|-------|
| Azure AD Integration | ✅ | OIDC federation |
| Admin Console | ✅ | Clean, modern |
| RBAC | ✅ | Projects, roles |
| Actions (Workflows) | ✅ | JavaScript-based |
| Audit Logging | ✅ | Event sourced |
| API | ✅ | gRPC + REST |
| Multi-tenancy | ✅ | Built-in |

### Docker Compose Addition

```yaml
zitadel:
  image: ghcr.io/zitadel/zitadel:latest
  container_name: zitadel
  command: start-from-init --masterkeyFromEnv
  environment:
    - ZITADEL_MASTERKEY=${ZITADEL_MASTERKEY}
    - ZITADEL_DATABASE_POSTGRES_HOST=zitadel-db
    - ZITADEL_DATABASE_POSTGRES_PORT=5432
    - ZITADEL_DATABASE_POSTGRES_DATABASE=zitadel
    - ZITADEL_DATABASE_POSTGRES_USER_USERNAME=zitadel
    - ZITADEL_DATABASE_POSTGRES_USER_PASSWORD=${ZITADEL_DB_PASSWORD:-zitadel}
    - ZITADEL_DATABASE_POSTGRES_USER_SSL_MODE=disable
    - ZITADEL_EXTERNALSECURE=false
  ports:
    - "8280:8080"
  networks:
    - coder-network
  depends_on:
    - zitadel-db

zitadel-db:
  image: postgres:15-alpine
  container_name: zitadel-db
  environment:
    - POSTGRES_DB=zitadel
    - POSTGRES_USER=zitadel
    - POSTGRES_PASSWORD=${ZITADEL_DB_PASSWORD:-zitadel}
  volumes:
    - zitadel_data:/var/lib/postgresql/data
  networks:
    - coder-network
```

### Pros
- Go-based (performant, single binary)
- Cloud-native design
- Built-in multi-tenancy
- Modern event-sourced architecture
- Good documentation

### Cons
- Newer project
- Smaller community than Keycloak
- Some features require paid tier

### When to Use
- Kubernetes-native deployments
- Need multi-tenancy
- Performance is critical
- Prefer Go ecosystem

---

## Option 6: Casdoor (Simple & Lightweight)

### Architecture
```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Azure AD   │────▶│   Casdoor   │────▶│   Coder     │
│             │OIDC │             │OIDC │             │
└─────────────┘     └─────────────┘     └─────────────┘
```

### Features

| Feature | Support | Notes |
|---------|---------|-------|
| Azure AD Integration | ✅ | OIDC/SAML |
| Admin Console | ✅ | Simple, clean |
| RBAC | ✅ | Basic roles |
| Workflows | ⚠️ | Limited |
| Audit Logging | ✅ | Basic |
| API | ✅ | REST |

### Docker Compose Addition

```yaml
casdoor:
  image: casbin/casdoor:latest
  container_name: casdoor
  environment:
    - RUNNING_IN_DOCKER=true
  ports:
    - "8000:8000"
  volumes:
    - ./casdoor/conf:/conf
  networks:
    - coder-network
```

### Pros
- Very lightweight
- Easy to set up
- Simple UI
- Go-based

### Cons
- Limited features
- Smaller community
- Basic workflows

### When to Use
- Simple requirements
- Quick setup needed
- Basic RBAC sufficient

---

## Recommendation

### Decision Matrix

| Criteria | Weight | Keycloak | Authentik | Zitadel | Casdoor | Custom |
|----------|--------|----------|-----------|---------|---------|--------|
| Azure AD Integration | 20% | 5 | 5 | 5 | 4 | 5 |
| Admin UI Quality | 15% | 4 | 5 | 4 | 3 | 5 |
| Approval Workflows | 15% | 3 | 5 | 4 | 2 | 5 |
| Ease of Setup | 10% | 3 | 4 | 4 | 5 | 2 |
| Community/Support | 15% | 5 | 4 | 3 | 3 | 1 |
| Resource Usage | 10% | 2 | 3 | 4 | 5 | 4 |
| Long-term Maintenance | 15% | 4 | 4 | 4 | 3 | 2 |
| **Weighted Score** | | **3.85** | **4.35** | **4.00** | **3.45** | **3.50** |

### Primary Recommendation: **Authentik**

For this Dev Platform use case, **Authentik** is recommended because:

1. **Built-in Approval Workflows** - Critical for contractor access requests
2. **Modern Admin UI** - Non-technical admins can manage access
3. **Azure AD Integration** - Seamless federation with existing IdP
4. **Self-Service Portal** - Contractors can request access
5. **Reasonable Resource Usage** - Lighter than Keycloak
6. **Active Development** - Regular updates, modern architecture

### Alternative: **Keycloak**

Choose Keycloak if:
- Already have Keycloak expertise in-house
- Need maximum enterprise features
- Require specific compliance certifications
- Plan to secure many applications

### Alternative: **Custom App**

Choose Custom only if:
- Very specific workflow requirements that no OSS meets
- Strong internal development team
- Willing to invest 8-12 weeks development
- Can commit to ongoing maintenance

---

## Implementation: Authentik for Dev Platform

### Integration Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           AUTHENTICATION FLOW                             │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  1. User accesses Coder                                                  │
│     ┌──────────┐                                                         │
│     │ Coder UI │                                                         │
│     └────┬─────┘                                                         │
│          │ Redirect to Authentik                                         │
│          ▼                                                               │
│  2. Authentik checks federation                                          │
│     ┌──────────┐     ┌──────────┐                                       │
│     │Authentik │────▶│ Azure AD │  (If user from @company.com)          │
│     └────┬─────┘     └──────────┘                                       │
│          │                                                               │
│  3. User authenticates with Azure AD (MFA)                              │
│          │                                                               │
│  4. Authentik enriches token with roles                                 │
│     ┌──────────┐                                                         │
│     │Authentik │  Adds: groups, roles, quotas                           │
│     │  RBAC    │                                                         │
│     └────┬─────┘                                                         │
│          │                                                               │
│  5. Token returned to Coder                                             │
│     ┌──────────┐                                                         │
│     │  Coder   │  Receives: user + groups + permissions                 │
│     └──────────┘                                                         │
│                                                                           │
└──────────────────────────────────────────────────────────────────────────┘
```

### Authentik Configuration for Dev Platform

```yaml
# authentik/blueprints/dev-platform.yaml
version: 1
metadata:
  name: Dev Platform RBAC
entries:
  # Azure AD Federation
  - model: authentik_sources_oauth.OAuthSource
    id: azure-ad
    attrs:
      name: Azure AD
      slug: azure-ad
      provider_type: azuread
      consumer_key: ${AZURE_CLIENT_ID}
      consumer_secret: ${AZURE_CLIENT_SECRET}

  # Contractor Roles
  - model: authentik_rbac.Role
    id: contractor-alpha
    attrs:
      name: Contractor - Project Alpha

  - model: authentik_rbac.Role
    id: contractor-beta
    attrs:
      name: Contractor - Project Beta

  # Access Request Flow
  - model: authentik_flows.Flow
    id: access-request
    attrs:
      name: Access Request
      slug: access-request
      designation: enrollment

  # Approval Stage
  - model: authentik_stages_prompt.PromptStage
    id: access-request-form
    attrs:
      fields:
        - name: project
          type: dropdown
          choices: ["Project Alpha", "Project Beta"]
        - name: justification
          type: text
        - name: duration
          type: dropdown
          choices: ["30 days", "60 days", "90 days"]
```

### Next Steps

1. Add Authentik to docker-compose.yml
2. Configure Azure AD federation
3. Set up contractor roles and flows
4. Integrate with Coder OIDC
5. Test approval workflow

---

## Document Control

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-04 | Dev Platform Team | Initial draft |
