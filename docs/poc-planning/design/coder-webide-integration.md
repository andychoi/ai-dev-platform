# Coder WebIDE Integration - Design Document

## Overview

This document describes the architecture and design decisions for implementing Coder as a secure web-based development platform for contractors. The design emphasizes zero-trust security, workspace isolation, and comprehensive audit capabilities.

## Implementation Status

This design document describes the **target production architecture**. The current PoC implementation uses Docker Compose instead of Kubernetes, with the following mapping:

| Design Component | PoC Implementation |
|------------------|-------------------|
| Kubernetes Pods | Docker containers |
| OIDC/SAML IdP | Authentik 2024.2 |
| Git Server | Gitea 1.25.4 |
| Secrets Manager | Environment variables (Vault planned) |
| Network Policies | Docker bridge network |

See `coder-poc/` directory for current implementation.

## Architecture Overview

### High-Level Architecture

> **Note:** The diagrams below show the production target architecture using Kubernetes. The current PoC uses Docker Compose with equivalent components.

```mermaid
graph TB
    subgraph "Contractor Zone (Untrusted)"
        CD[Contractor Device<br/>Browser Only]
    end

    subgraph "DMZ"
        WAF[Web Application Firewall]
        LB[Load Balancer<br/>TLS Termination]
    end

    subgraph "Control Plane"
        CP[Coder Control Plane]
        PG[(PostgreSQL<br/>Metadata)]
        OIDC[OIDC/SAML<br/>Identity Provider]
    end

    subgraph "Data Plane - Kubernetes Cluster"
        subgraph "Workspace Pool"
            WS1[Workspace Pod 1<br/>code-server]
            WS2[Workspace Pod 2<br/>code-server]
            WS3[Workspace Pod N<br/>code-server]
        end
        PV[(Persistent Volumes<br/>Workspace Data)]
    end

    subgraph "Internal Services"
        GIT[Git Server<br/>GitLab/GitHub]
        REG[Container Registry]
        DB[(Internal Databases)]
        VAULT[Secrets Manager<br/>HashiCorp Vault]
    end

    subgraph "Observability"
        LOG[Log Aggregator<br/>ELK/Splunk]
        MON[Monitoring<br/>Prometheus/Grafana]
    end

    CD -->|HTTPS| WAF
    WAF --> LB
    LB --> CP
    CP <-->|Auth| OIDC
    CP --> PG
    CP -->|Provision| WS1
    CP -->|Provision| WS2
    CP -->|Provision| WS3
    WS1 --> PV
    WS2 --> PV
    WS3 --> PV
    WS1 -->|Git SSH/HTTPS| GIT
    WS2 -->|Git SSH/HTTPS| GIT
    WS1 -->|Pull Images| REG
    WS1 -->|Secrets| VAULT
    WS1 -.->|Proxy Only| DB
    CP --> LOG
    WS1 --> LOG
    WS2 --> LOG
    CP --> MON
```

### Network Security Architecture

```mermaid
graph LR
    subgraph "Internet"
        C[Contractor Browser]
    end

    subgraph "Perimeter Security"
        FW1[Firewall]
        WAF[WAF<br/>OWASP Rules]
    end

    subgraph "Secure Enclave"
        subgraph "Control Plane Network"
            CP[Coder Server]
            PG[PostgreSQL]
        end

        subgraph "Workspace Network"
            WS[Workspace Pods]
            NP[Network Policies]
        end

        subgraph "Internal Network"
            GIT[Git Repos]
            DB[Databases]
            SVC[Internal Services]
        end
    end

    C -->|443/HTTPS| FW1
    FW1 --> WAF
    WAF -->|Validated| CP
    CP -->|WireGuard Tunnel| WS
    WS -->|Allowed Egress| GIT
    WS -->|Proxy| DB
    NP -->|Block| SVC

    style NP fill:#f96,stroke:#333
    style FW1 fill:#6f9,stroke:#333
    style WAF fill:#6f9,stroke:#333
```

### Workspace Isolation Model

> **Note:** Production target uses Kubernetes namespaces. PoC uses Docker container isolation.

```mermaid
graph TB
    subgraph "Kubernetes Cluster"
        subgraph "Namespace: contractor-a"
            WS_A[Workspace Pod A]
            PVC_A[PVC A<br/>10GB]
            SA_A[ServiceAccount A]
            NP_A[NetworkPolicy A]
        end

        subgraph "Namespace: contractor-b"
            WS_B[Workspace Pod B]
            PVC_B[PVC B<br/>10GB]
            SA_B[ServiceAccount B]
            NP_B[NetworkPolicy B]
        end

        subgraph "Shared Services Namespace"
            PROXY[Git Proxy]
            DB_PROXY[DB Proxy<br/>Boundary/pgBouncer]
        end
    end

    WS_A -->|Allowed| PROXY
    WS_B -->|Allowed| PROXY
    WS_A -->|Allowed| DB_PROXY
    WS_B -->|Allowed| DB_PROXY
    WS_A -.->|Blocked by NP| WS_B

    style NP_A fill:#f96
    style NP_B fill:#f96
```

## Component Design

> **Note:** This section describes production Kubernetes deployment. See PoC services in `coder-poc/docker-compose.yml`.

### 1. Coder Control Plane

**Deployment**: Kubernetes Deployment with 2+ replicas (PoC: single Docker container)

**Components**:
- `coderd` - Main server process
- PostgreSQL - Metadata storage
- Redis (optional) - Pub/sub for multi-replica

**Configuration**:
```yaml
# coder-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coder-config
  namespace: coder
data:
  CODER_ACCESS_URL: "https://coder.company.com"
  CODER_WILDCARD_ACCESS_URL: "*.coder.company.com"
  CODER_PG_CONNECTION_URL: "postgres://coder:***@postgres:5432/coder?sslmode=require"
  CODER_OIDC_ISSUER_URL: "https://idp.company.com"
  CODER_OIDC_CLIENT_ID: "coder-app"
  CODER_MAX_SESSION_EXPIRY: "8h"
  CODER_DISABLE_PASSWORD_AUTH: "true"
  CODER_AUDIT_LOGGING: "true"
```

### 2. Workspace Template Design

**Base Template Structure**:
```hcl
# templates/contractor-workspace/main.tf

terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

data "coder_workspace" "me" {}

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"
  dir  = "/home/coder/workspace"

  startup_script = <<-EOT
    # Install project dependencies
    cd /home/coder/workspace
    if [ -f "package.json" ]; then npm install; fi
    if [ -f "requirements.txt" ]; then pip install -r requirements.txt; fi
  EOT

  metadata {
    key          = "cpu"
    display_name = "CPU Usage"
    script       = "top -bn1 | grep 'Cpu(s)' | awk '{print $2}'"
    interval     = 10
  }
}

resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code"
  icon         = "/icon/code.svg"
  url          = "http://localhost:13337?folder=/home/coder/workspace"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 6
  }
}

resource "kubernetes_pod" "workspace" {
  metadata {
    name      = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"
    namespace = "contractor-workspaces"
    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = data.coder_workspace.me.id
      "coder.com/workspace-owner"  = data.coder_workspace.me.owner
    }
  }

  spec {
    security_context {
      run_as_user  = 1000
      run_as_group = 1000
      fs_group     = 1000
    }

    container {
      name  = "dev"
      image = "registry.company.com/coder/contractor-workspace:latest"

      resources {
        requests = {
          cpu    = "500m"
          memory = "2Gi"
        }
        limits = {
          cpu    = "2"
          memory = "4Gi"
        }
      }

      volume_mount {
        name       = "workspace"
        mount_path = "/home/coder/workspace"
      }

      env {
        name  = "CODER_AGENT_TOKEN"
        value = coder_agent.main.token
      }
    }

    volume {
      name = "workspace"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim.workspace.metadata[0].name
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "workspace" {
  metadata {
    name      = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"
    namespace = "contractor-workspaces"
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "10Gi"
      }
    }
    storage_class_name = "fast-ssd"
  }
}
```

### 3. Container Image Design

**Dockerfile for Contractor Workspace**:
```dockerfile
# contractor-workspace/Dockerfile
FROM codercom/code-server:latest

USER root

# Install development tools
RUN apt-get update && apt-get install -y \
    git \
    curl \
    wget \
    jq \
    vim \
    openssh-client \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Install language runtimes
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g npm@latest

RUN apt-get update && apt-get install -y python3 python3-pip python3-venv

# Install Coder agent
RUN curl -fsSL https://coder.com/install.sh | sh

# Security hardening
RUN chmod 700 /home/coder \
    && chown -R coder:coder /home/coder

# Pre-install approved VS Code extensions
COPY extensions.txt /tmp/extensions.txt
RUN while read ext; do \
      code-server --install-extension "$ext"; \
    done < /tmp/extensions.txt

USER coder
WORKDIR /home/coder

# Configure Git (will be overridden by user settings)
RUN git config --global init.defaultBranch main

ENTRYPOINT ["/usr/bin/coder", "agent"]
```

### 4. AI Gateway

- Custom FastAPI proxy service
- Multi-provider support: AWS Bedrock, Anthropic Direct
- Rate limiting and usage tracking
- OpenAI-compatible API endpoint
- Port: 8090

**PoC Implementation**: See `coder-poc/ai-gateway/` directory.

### 5. Developer Database Service (DevDB)

- Per-user and per-team PostgreSQL databases
- Automatic provisioning on workspace creation
- Naming convention: `dev_{username}` or `team_{template}`
- Managed via `scripts/manage-devdb.sh`

**PoC Implementation**: Uses shared PostgreSQL container with database-per-user isolation.

### 6. Platform Admin Dashboard

- Flask-based administration interface
- Service monitoring and user management
- Port: 5050

**PoC Implementation**: See `coder-poc/platform-admin/` directory.

### 7. Network Policy Design

> **Note:** Production uses Kubernetes NetworkPolicy. PoC uses Docker bridge network with port-based isolation.

```yaml
# network-policies/workspace-isolation.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: workspace-isolation
  namespace: contractor-workspaces
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: coder-workspace
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Allow traffic from Coder control plane only
    - from:
        - namespaceSelector:
            matchLabels:
              name: coder
          podSelector:
            matchLabels:
              app: coder
      ports:
        - protocol: TCP
          port: 13337  # code-server
  egress:
    # Allow DNS
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
    # Allow Git server
    - to:
        - ipBlock:
            cidr: 10.0.100.0/24  # Git server subnet
      ports:
        - protocol: TCP
          port: 443
        - protocol: TCP
          port: 22
    # Allow container registry
    - to:
        - ipBlock:
            cidr: 10.0.101.0/24  # Registry subnet
      ports:
        - protocol: TCP
          port: 443
    # Allow database proxy
    - to:
        - namespaceSelector:
            matchLabels:
              name: shared-services
          podSelector:
            matchLabels:
              app: db-proxy
      ports:
        - protocol: TCP
          port: 5432
    # Block everything else by default
```

### 5. Authentication Flow

```mermaid
sequenceDiagram
    participant C as Contractor Browser
    participant WAF as WAF/LB
    participant CP as Coder Server
    participant IdP as Identity Provider
    participant WS as Workspace

    C->>WAF: Access coder.company.com
    WAF->>CP: Forward request
    CP->>C: Redirect to IdP
    C->>IdP: Authenticate (MFA)
    IdP->>C: Auth code
    C->>CP: Exchange code
    CP->>IdP: Validate token
    IdP->>CP: User info + groups
    CP->>CP: Map groups to roles
    CP->>C: Session cookie (8hr max)

    C->>CP: Create/Start workspace
    CP->>WS: Provision pod
    WS->>CP: Agent connected
    CP->>C: Workspace URL
    C->>WAF: Access workspace
    WAF->>WS: WireGuard tunnel
    WS->>C: VS Code UI
```

### 6. Audit Logging Architecture

```mermaid
graph LR
    subgraph "Coder Platform"
        CP[Control Plane]
        WS[Workspaces]
    end

    subgraph "Log Pipeline"
        FB[Fluent Bit<br/>DaemonSet]
        KF[Kafka<br/>Buffer]
    end

    subgraph "Storage & Analysis"
        ES[(Elasticsearch)]
        KB[Kibana<br/>Dashboards]
        SIEM[SIEM<br/>Alerts]
    end

    CP -->|Audit Events| FB
    WS -->|Terminal Logs| FB
    WS -->|File Access| FB
    FB --> KF
    KF --> ES
    ES --> KB
    ES --> SIEM
```

**Audit Event Schema**:
```json
{
  "timestamp": "2026-02-04T10:30:00Z",
  "event_type": "workspace.session.command",
  "user_id": "contractor-123",
  "user_email": "john@contractor.com",
  "workspace_id": "ws-abc123",
  "session_id": "sess-xyz789",
  "source_ip": "203.0.113.50",
  "details": {
    "command": "git push origin feature-branch",
    "working_directory": "/home/coder/workspace/project",
    "exit_code": 0
  },
  "risk_score": 0.2
}
```

## Security Design

### Data Flow Security

| Flow | Source | Destination | Protection |
|------|--------|-------------|------------|
| Browser → Coder | Contractor | Load Balancer | TLS 1.3 + WAF |
| Coder → Workspace | Control Plane | Pod | WireGuard tunnel |
| Workspace → Git | Pod | Git Server | SSH keys / HTTPS |
| Workspace → DB | Pod | DB Proxy | mTLS + short-lived creds |
| Audit Logs | All | Log Platform | TLS + encryption at rest |

### Secret Management

```mermaid
graph LR
    subgraph "Workspace"
        APP[Application]
        AGENT[Coder Agent]
    end

    subgraph "Secrets Infrastructure"
        VAULT[HashiCorp Vault]
        K8S[Kubernetes Secrets]
    end

    AGENT -->|Vault Agent| VAULT
    VAULT -->|Dynamic Secrets| AGENT
    AGENT -->|Inject| APP
    K8S -->|Static Config| AGENT
```

**Secret Types**:
1. **Git Credentials**: SSH keys or OAuth tokens (rotated daily)
2. **Database Credentials**: Dynamic, short-lived (1hr TTL)
3. **API Keys**: Per-workspace, scoped tokens
4. **Registry Auth**: Pull-only tokens

### Clipboard & File Transfer Prevention

```yaml
# code-server settings to prevent data exfiltration
# Injected into workspace container
{
  "security.workspace.trust.enabled": true,
  "security.workspace.trust.untrustedFiles": "prompt",
  "terminal.integrated.enablePersistentSessions": false,
  "files.simpleDialog.enable": true,
  "workbench.settings.enableNaturalLanguageSearch": false
}
```

**Browser-Level Controls**:
- Content-Security-Policy headers to prevent clipboard access
- Disable file upload/download dialogs
- WebSocket traffic inspection

## Data Model

### Entity Relationship

```mermaid
erDiagram
    Organization ||--o{ User : has
    Organization ||--o{ Template : owns
    User ||--o{ Workspace : creates
    Template ||--o{ Workspace : provisions
    Workspace ||--o{ Session : tracks
    Session ||--o{ AuditLog : generates
    User }|--|| Role : assigned

    Organization {
        uuid id PK
        string name
        string sso_config
        timestamp created_at
    }

    User {
        uuid id PK
        string email
        string external_id
        uuid org_id FK
        uuid role_id FK
        timestamp last_login
    }

    Template {
        uuid id PK
        string name
        text terraform_config
        uuid org_id FK
        json resource_limits
    }

    Workspace {
        uuid id PK
        string name
        uuid user_id FK
        uuid template_id FK
        string status
        timestamp last_active
    }

    Session {
        uuid id PK
        uuid workspace_id FK
        string source_ip
        timestamp started_at
        timestamp ended_at
    }

    AuditLog {
        uuid id PK
        uuid session_id FK
        string event_type
        json details
        timestamp created_at
    }

    Role {
        uuid id PK
        string name
        json permissions
    }
```

## Deployment Architecture

> **Production Migration:** For transitioning from PoC to production, see [Production Implementation Plan](../../../aws-production/PRODUCTION-PLAN.md) which details the Kubernetes deployment strategy and security hardening requirements.

### Kubernetes Resources

> **Note:** This section describes production Kubernetes deployment. PoC uses `docker-compose.yml` for service orchestration.

```mermaid
graph TB
    subgraph "coder namespace"
        DEP[Deployment: coder<br/>2 replicas]
        SVC[Service: coder]
        ING[Ingress: coder.company.com]
        CM[ConfigMap: coder-config]
        SEC[Secret: coder-secrets]
        PG_DEP[StatefulSet: postgres]
        PG_PVC[PVC: postgres-data]
    end

    subgraph "contractor-workspaces namespace"
        WS_PODS[Dynamic Workspace Pods]
        WS_PVC[Workspace PVCs]
        NP[NetworkPolicy]
        SA[ServiceAccounts]
    end

    ING --> SVC
    SVC --> DEP
    DEP --> CM
    DEP --> SEC
    PG_DEP --> PG_PVC
    DEP --> PG_DEP
```

### High Availability Design

| Component | Strategy | RPO | RTO |
|-----------|----------|-----|-----|
| Coder Server | Multi-replica + HPA | 0 | < 1min |
| PostgreSQL | Streaming replication | < 1min | < 5min |
| Workspace PVCs | Snapshot backups | 1hr | 1hr |
| Audit Logs | Real-time replication | 0 | < 5min |

## Design Decisions

### DD-1: Coder Community vs Enterprise

**Decision**: Start with Coder Community (AGPL-3.0)

**Rationale**:
- Community version provides core functionality needed
- AGPL license acceptable for internal use
- Can upgrade to Enterprise if needed for:
  - High availability control plane
  - Advanced audit features
  - Premium support

### DD-2: Workspace Isolation Strategy

**Decision**: Namespace-per-contractor with NetworkPolicy isolation

**Rationale**:
- Kubernetes namespaces provide logical isolation
- NetworkPolicy enforces network segmentation
- Per-workspace ServiceAccounts limit K8s API access
- More flexible than dedicated node pools

### DD-3: Database Access Pattern

**Decision**: Use database proxy (pgBouncer/Boundary) instead of direct access

**Rationale**:
- Centralized access control and auditing
- Dynamic credential injection
- Connection pooling improves resource usage
- No direct database network access from workspaces

### DD-4: Clipboard/File Transfer Prevention

**Decision**: Multi-layer prevention (network + browser + audit)

**Rationale**:
- CSP headers prevent most clipboard operations
- Network egress blocks file transfer destinations
- Audit logging detects attempts for investigation
- Defense in depth approach

## Integration Points

| System | Integration Method | Purpose |
|--------|-------------------|---------|
| Identity Provider | OIDC/SAML | Authentication & group sync |
| Git Server | SSH/HTTPS | Source code access |
| Container Registry | Docker registry API | Image pulls |
| Vault | Vault Agent | Secret injection |
| Logging Platform | Fluent Bit | Audit log shipping |
| Monitoring | Prometheus | Metrics collection |
| Alerting | PagerDuty/Slack | Security incidents |
| AI Gateway | REST API | AI-assisted coding |
| DevDB | PostgreSQL | Developer databases |
| MinIO | S3 API | Object storage |

## Risk Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Data exfiltration | Medium | High | Egress filtering, clipboard prevention, audit |
| Workspace escape | Low | Critical | Pod security policies, minimal privileges |
| Credential theft | Medium | High | Dynamic credentials, short TTL, rotation |
| DoS on platform | Medium | Medium | Rate limiting, resource quotas, HPA |
| Insider threat | Low | High | Comprehensive audit logging, anomaly detection |

## References

- [Coder Architecture Documentation](https://coder.com/docs/architecture)
- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [HashiCorp Vault Kubernetes Integration](https://developer.hashicorp.com/vault/docs/platform/k8s)
- [NIST SP 800-207 Zero Trust Architecture](https://csrc.nist.gov/publications/detail/sp/800-207/final)
