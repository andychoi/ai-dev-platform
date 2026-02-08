# Coder WebIDE Production Plan — AWS Deployment

**Created:** February 4, 2026
**Updated:** February 8, 2026
**Based on:** PoC validation + Security Review (68 issues identified)
**Target:** AWS (ECS Fargate + managed services, VPN-only access)
**Edition:** Coder OSS (Community Edition) — see Decision Log for Enterprise evaluation
**Status:** Implementation Phase

---

## Executive Summary

Transform the Docker Compose PoC into a production AWS deployment. The core strategy: **replace self-hosted infrastructure with AWS managed services** and run all workloads on ECS Fargate. **Private-only access via VPN — no public-facing endpoints.** This eliminates operational burden for databases, caching, storage, secrets, TLS, and monitoring — letting the team focus on the application layer (templates, AI integration, workspace networking). ECS Fargate removes node management entirely: no AMI patching, no kubelet, no Kubernetes expertise required.

**Key architecture decisions (updated Feb 8):**
- **Dual-path access:** Coder tunnel (management plane) + direct ALB→code-server (data plane) coexist
- **Coder OSS (single-instance):** AWS-native HA (ECS auto-restart, dual-path) substitutes for Enterprise multi-replica
- **Three AI agents:** Roo Code (VS Code), OpenCode (CLI), Claude Code (Anthropic native CLI)
- **Corporate IdP ready:** Authentik deployed for PoC parity; production swaps to Okta/Azure AD via OIDC config change

### PoC → AWS Service Mapping

| PoC Component | AWS Production | Why |
|---------------|----------------|-----|
| PostgreSQL (container) | **Amazon RDS** (Single-AZ) | Automated backups, patching, snapshots |
| Redis (container) | **Amazon ElastiCache** | Managed clustering, encryption at rest |
| MinIO (container) | **Amazon S3** | Native, unlimited, no ops |
| Self-signed TLS certs | **ACM** (AWS Certificate Manager) | Auto-renewal, free, ALB integration |
| Traefik / self-signed | **Internal ALB** + ACM | Internal TLS termination, VPN-only access |
| HashiCorp Vault | **AWS Secrets Manager** | Native IAM integration, auto-rotation |
| Loki + Prometheus + Grafana | **CloudWatch** + Managed Grafana | Reduce ops; optional Prometheus via AMP |
| Docker Compose | **Amazon ECS (Fargate)** | Serverless compute, per-task ENI isolation, no node management |
| Authentik (container) | **Authentik on ECS** (or corporate IdP) | Keep for PoC parity; swap for Okta/Azure AD in enterprise |
| LiteLLM (container) | **LiteLLM on ECS** (AI gateway) | Routes to Bedrock (primary, IAM) + Anthropic API (fallback) |
| Docker-in-Docker workspaces | **ECS Fargate tasks** (per-user) | Each workspace = isolated task with own ENI + security group |
| EBS PVCs (workspace storage) | **Amazon EFS** | Shared filesystem, per-workspace access points, multi-AZ |

---

## Architecture

### Dual-Path Access Model

The platform provides **two coexisting access paths** to the same code-server process running inside each workspace container:

| | Path 1: Coder Tunnel (Management Plane) | Path 2: Direct ALB (Data Plane) |
|---|---|---|
| **Route** | Browser → ALB → Coder Server → coder_agent tunnel → code-server | Browser → ALB (OIDC auth) → code-server directly |
| **Auth** | Coder OIDC session | ALB OIDC authentication action |
| **Depends on** | Coder server must be running | Only ALB + IdP must be running |
| **Use case** | Workspace management, template provisioning, admin | Active development (VS Code, terminal, AI agents) |
| **Coder server failure** | Interrupted until ECS restarts Coder (~30-60s) | **Zero impact** — continues working |

**Why dual-path matters for OSS:**
- Coder OSS runs as a **single instance** (multi-replica requires Enterprise license)
- If the Coder server task restarts, **Path 2 provides zero-downtime for active developers**
- Running workspaces (code-server, terminal, git, AI agents) are fully independent from the Coder server
- ECS auto-restarts the Coder task within 30-60 seconds — Path 1 recovers automatically

**ALB OIDC Authentication for Direct Path:**
- AWS ALB natively supports OIDC authentication actions on listener rules
- `ide.internal.company.com` → ALB OIDC authenticate → forward to workspace target group (port 13337)
- The IdP (Authentik or corporate Okta/Azure AD) handles user authentication
- No Coder dependency for the auth flow — ALB talks directly to the IdP

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    VPN (Corporate Network)                                    │
└───────────────────────────────┬──────────────────────────────────────────────┘
                                │
                          ┌─────┴─────┐
                          │ Internal  │  ← ACM TLS termination
                          │    ALB    │    coder.internal.company.com
                          │  (HTTPS)  │    ide.internal.company.com (direct)
                          └─────┬─────┘
                           ┌────┴────┐
                    Path 1 │         │ Path 2
                   (tunnel)│         │ (direct)
                           ▼         ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│  VPC (10.0.0.0/16)            │                                               │
│                               │                                               │
│  ┌────────────────────────────┼───────────────────────────────────────────┐  │
│  │  Private Subnet — App (10.0.1.0/24, 10.0.2.0/24)                      │  │
│  │                                                                         │  │
│  │  ┌──────────── ECS Cluster (Fargate) ─────────────────────────────┐   │  │
│  │  │                                                                  │   │  │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌──────────────┐           │   │  │
│  │  │  │ Coder Server│  │ Authentik/  │  │ Key          │           │   │  │
│  │  │  │  (1 task)   │  │ Corp IdP    │  │ Provisioner  │           │   │  │
│  │  │  │  (OSS)      │  │  (2 tasks)  │  │  (1 task)    │           │   │  │
│  │  │  └──────┬──────┘  └─────────────┘  └──────────────┘           │   │  │
│  │  │         │ Path 1                                                │   │  │
│  │  │         │ (tunnel)                                              │   │  │
│  │  │         ▼                                                       │   │  │
│  │  │  ┌─────────────┐  ┌──────────────────────────────────────┐      │   │  │
│  │  │  │  LiteLLM    │  │  Workspace Tasks (per-user, Fargate) │      │   │  │
│  │  │  │  (2 tasks)  │  │  ┌────────┐ ┌────────┐ ┌────────┐  │      │   │  │
│  │  │  └─────────────┘  │  │ WS-1   │ │ WS-2   │ │ WS-N   │  │      │   │  │
│  │  │                    │  │code-srv│ │code-srv│ │code-srv│  │      │   │  │
│  │  │                    │  │+agents │ │+agents │ │+agents │  │      │   │  │
│  │  │                    │  │+claude │ │+claude │ │+claude │  │      │   │  │
│  │  │                    │  └───┬────┘ └───┬────┘ └───┬────┘  │      │   │  │
│  │  │                    │      ▲          ▲          ▲        │      │   │  │
│  │  │                    │      └── Path 2 (direct ALB) ──────│──────│   │  │
│  │  │                    └──────────────────────────────────────┘      │   │  │
│  │  └──────────────────────────────────────────────────────────────────┘   │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │  Private Subnet — Data (10.0.3.0/24, 10.0.4.0/24)                      │  │
│  │                                                                         │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │  │
│  │  │ RDS Postgres │  │ ElastiCache │  │     EFS     │  │     S3      │  │  │
│  │  │ (Single-AZ)  │  │   (Redis)   │  │ (home dirs) │  │  (Buckets)  │  │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘  │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │  AWS Managed Services (outside VPC or VPC endpoints)                    │  │
│  │  Secrets Manager │ CloudWatch │ ECR │ Bedrock │ KMS │ IAM │ Cloud Map │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────────┘
```

---

## PoC Learnings Carried Forward

Key findings from the PoC that inform production design:

| Finding | Impact on Production |
|---------|---------------------|
| `crypto.subtle` requires secure context | Internal ALB + ACM provides HTTPS natively — no self-signed cert headaches |
| `host.docker.internal` networking | Eliminated — ECS uses AWS Cloud Map for service discovery |
| OIDC cookie domain must match access URL | Single domain `coder.internal.company.com` via Internal ALB — no domain mismatch |
| `docker compose restart` doesn't reload env | ECS task definition updates force new task deployment with fresh config |
| LiteLLM Bedrock failover works | Production uses Bedrock as **primary** (IAM roles, no API keys to manage) |
| Roo Code auto-import config flow | Same pattern, but settings injected via EFS mount or task definition env |
| Template changes require workspace recreate | Same — document clearly for admins |
| Agent TLS trust (self-signed certs) | Eliminated — ACM certs are trusted by default |
| Workspace sudo for CA cert install | Eliminated — no self-signed certs to trust |
| LiteLLM `ANTHROPIC_API_KEY` required for primary | Bedrock via IAM (ECS task role) is primary — no static key needed. Anthropic direct API kept as optional fallback in Secrets Manager |
| `CODER_REDIRECT_TO_ACCESS_URL` broke HTTP API | Not applicable — ALB handles all routing |
| ECS Fargate eliminates node management | No AMI patching, no kubelet attack surface, no node scaling concerns |

### What the PoC HTTPS Implementation Proved

The PoC was upgraded to HTTPS (self-signed cert on port 7443) to validate that:
- Extension webviews (Roo Code) work correctly with `isSecureContext = true`
- OIDC flows work with `CODER_SECURE_AUTH_COOKIE=true`
- Workspace agents connect over TLS when `CODER_ACCESS_URL` uses HTTPS
- `update-ca-certificates` in workspace entrypoint trusts custom CAs

These findings confirm the production approach (ACM + Internal ALB) will work without the self-signed cert complexity. The PoC cert workarounds (`certs/` directory, Dockerfile sudoers for CA install, entrypoint cert copy) are all unnecessary in production.

---

## Phase 1: AWS Foundation (Week 1-2)

### 1.1 VPC & Networking

**Goal:** Isolated network foundation with private-only access

**AWS Resources:**
- VPC: `10.0.0.0/16`
- Public subnets: 2 AZs (NAT Gateway only — no public ALB)
- Private subnets (app): 2 AZs (ECS Fargate tasks, Internal ALB)
- Private subnets (data): 2 AZs (RDS, ElastiCache, EFS)
- NAT Gateway: For outbound internet (workspace package installs, Bedrock API)
- VPC Endpoints: S3, ECR, Secrets Manager, CloudWatch, Bedrock, STS, EFS

**Security Groups:**

| SG Name | Inbound | Source |
|---------|---------|--------|
| `sg-alb` | 443 (HTTPS) | VPC CIDR (10.0.0.0/16) |
| `sg-ecs-services` | Service ports | sg-alb, sg-ecs-services (self) |
| `sg-ecs-workspaces` | 13337 (code-server) | sg-alb |
| `sg-rds` | 5432 | sg-ecs-services only |
| `sg-elasticache` | 6379 | sg-ecs-services only |
| `sg-efs` | 2049 (NFS) | sg-ecs-services, sg-ecs-workspaces |

> **Note:** No `0.0.0.0/0` inbound anywhere — all traffic originates from VPN or within the VPC.

**Deliverables:**
- `terraform/modules/vpc/` — VPC, subnets, NAT, endpoints

---

### 1.2 ECS Cluster

**Goal:** Serverless compute for all workloads

**Configuration:**
- ECS cluster with Fargate capacity providers (FARGATE + FARGATE_SPOT)
- Container Insights enabled for metrics and logs
- AWS Cloud Map private DNS namespace for service discovery (e.g., `coder.internal`)
- No EC2 instances to manage

**Fargate Capacity Strategy:**

| Workload | Capacity Provider | Rationale |
|----------|------------------|-----------|
| Platform services (Coder, Authentik, LiteLLM) | FARGATE | Always-on, reliable, no interruption risk |
| Workspaces | FARGATE_SPOT | Cost savings (~70%), 2-min interruption notice acceptable for dev environments |

**Service Discovery (Cloud Map):**

| Service | Discovery Name | Port |
|---------|---------------|------|
| Coder Server | `coder.coder.internal` | 7080 |
| Authentik | `authentik.coder.internal` | 9000 |
| LiteLLM | `litellm.coder.internal` | 4000 |

**Advantages over EKS:**
- No node management, no AMI patching, no kubelet
- Each task gets its own ENI — true network-level isolation
- Simpler security model (security groups per task, not network policies)
- No Kubernetes expertise required for ops team
- Faster task startup than pod scheduling on cold nodes

**Deliverables:**
- `terraform/modules/ecs/` — ECS cluster, Fargate capacity providers, Cloud Map namespace

---

### 1.3 Data Layer (Managed Services)

**Goal:** Zero-ops data stores

#### Amazon RDS (PostgreSQL)

| Setting | Value |
|---------|-------|
| Engine | PostgreSQL 16 |
| Instance | db.r6g.large (Single-AZ) |
| Storage | 100 GB gp3, auto-scaling to 500 GB |
| Backup | 30-day retention, daily snapshots |
| Encryption | KMS (at rest), SSL required (in transit) |
| Databases | `coder`, `authentik`, `litellm` |

> **Note:** Single-AZ is sufficient for initial deployment. Upgrade to Multi-AZ later if SLA requires < 5 min RTO for database failures. Single-AZ RDS still provides automated backups and point-in-time recovery.

#### Amazon ElastiCache (Redis)

| Setting | Value |
|---------|-------|
| Engine | Redis 7.x |
| Node Type | cache.r6g.large |
| Cluster Mode | Disabled (single shard, 1 primary + 1 replica) |
| Encryption | At rest (KMS) + in transit (TLS) |
| Purpose | Authentik sessions, Coder pub/sub |

#### Amazon S3

| Bucket | Purpose |
|--------|---------|
| `company-coder-terraform-state` | Coder template state |
| `company-coder-backups` | Database backups, config exports |
| `company-coder-artifacts` | Build artifacts, workspace exports |

#### Amazon EFS (Workspace Storage)

| Setting | Value |
|---------|-------|
| Performance | General Purpose |
| Throughput | Bursting |
| Encryption | At rest (KMS) + in transit |
| Lifecycle | Transition to IA after 30 days |
| Access Points | Per-workspace (UID 1000, `/home/coder`) |

> **Note:** EFS access points provide per-workspace home directory isolation. Each workspace task mounts its own access point, enforcing UID/GID and root directory at the filesystem level. Multi-AZ by default — no single-AZ failure risk for workspace data.

**Deliverables:**
- `terraform/modules/rds/`
- `terraform/modules/elasticache/`
- `terraform/modules/s3/`
- `terraform/modules/efs/`

---

### 1.4 Secrets & IAM

**Goal:** No hardcoded credentials anywhere

#### AWS Secrets Manager

| Secret Path | Contents |
|-------------|----------|
| `prod/coder/database` | RDS connection string |
| `prod/coder/oidc` | OIDC client ID + secret |
| `prod/authentik/secret-key` | Authentik secret key |
| `prod/litellm/master-key` | LiteLLM admin key |
| `prod/litellm/anthropic-api-key` | Anthropic direct API key (optional fallback) |

#### IAM Roles (ECS Task Roles)

| Task Definition | IAM Role | Permissions |
|----------------|----------|-------------|
| `coder-server` | `coder-task-role` | Secrets Manager (read own), S3 (template state), ECS (RunTask for workspaces) |
| `litellm` | `litellm-task-role` | Bedrock (InvokeModel), Secrets Manager (read own) |
| `authentik` | `authentik-task-role` | Secrets Manager (read own), SES (email) |
| `workspace` | `workspace-task-role` | Minimal (LiteLLM accessed via network, no direct AWS API access) |
| All tasks (shared) | `ecs-task-execution-role` | ECR (pull images), Secrets Manager (inject secrets), CloudWatch Logs (write) |

**Key design:** LiteLLM uses an **ECS task role** to call Bedrock — no `ANTHROPIC_API_KEY` or `AWS_ACCESS_KEY_ID` in config. The task assumes the role automatically via the ECS task role mechanism.

> **Note:** The execution role is used by the ECS agent to pull images and inject secrets at startup. The task role is assumed by the application code at runtime for AWS API calls. These are separate roles with separate permissions.

**Deliverables:**
- `terraform/modules/secrets/`
- `terraform/modules/iam/` — ECS task roles + execution roles + policies

---

## Phase 2: Core Platform Deployment (Week 3-4)

### 2.1 TLS & Ingress

**Goal:** HTTPS everywhere with zero cert management

**Setup:**
- ACM certificate for `coder.internal.company.com` + `*.coder.internal.company.com` + `ide.internal.company.com`
- Internal ALB (scheme: **internal** — not internet-facing)
- ALB routes HTTPS to ECS services (HTTP internal)
- Wildcard subdomain for workspace apps (`*.coder.internal.company.com`)
- **`ide.internal.company.com`** — direct code-server access with ALB OIDC authentication (Path 2)
- Route 53 private hosted zone for DNS resolution within VPC

**ALB Routing Summary (Dual-Path):**

| Host | Priority | Target | Auth | Path |
|------|----------|--------|------|------|
| `coder.internal.company.com` | 100 | Coder (7080) | Coder OIDC | Path 1 (tunnel) |
| `auth.internal.company.com` | 200 | Authentik (9000) | None (IdP itself) | — |
| `ai.internal.company.com` | 400 | LiteLLM (4000) | API key | — |
| **`ide.internal.company.com`** | **450** | **Workspaces (13337)** | **ALB OIDC action** | **Path 2 (direct)** |
| `*.internal.company.com` | 500 | Coder (7080) | Coder OIDC | Path 1 (wildcard) |

**ALB Listener Rules (Terraform):**

```hcl
# terraform/services.tf — ALB listener rules

resource "aws_lb" "internal" {
  name               = "coder-internal-alb"
  internal           = true  # Private — VPN access only
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.private_subnet_ids
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = module.acm.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.coder.arn
  }
}

resource "aws_lb_listener_rule" "authentik" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.authentik.arn
  }

  condition {
    host_header { values = ["auth.internal.company.com"] }
  }
}

```

> **Note:** Accessible only via VPN. No public DNS needed — use Route 53 private hosted zone for `internal.company.com`.

**PoC lesson applied:** `crypto.subtle` / secure context issue is eliminated — ALB serves valid ACM certs over HTTPS.

**Deliverables:**
- `terraform/modules/alb/` — Internal ALB, HTTPS listener, target groups, listener rules
- `terraform/modules/acm/` — Certificate + DNS validation

---

### 2.2 Coder Server (ECS) — OSS Single-Instance

**Goal:** Production Coder OSS deployment on ECS Fargate

> **OSS vs Enterprise:** Coder OSS does not support multi-replica deployment. The server runs as a single ECS task. The dual-path architecture ensures zero-downtime for active developers during Coder server restarts (30-60s). Evaluate Enterprise ($66/user/month) at 200+ users if template RBAC or audit logging is needed. See Decision Log.

**ECS Task Definition:**

```json
{
  "family": "coder-server",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "2048",
  "memory": "4096",
  "taskRoleArn": "arn:aws:iam::role/coder-task-role",
  "executionRoleArn": "arn:aws:iam::role/ecs-task-execution-role",
  "containerDefinitions": [
    {
      "name": "coder",
      "image": "ghcr.io/coder/coder:latest",
      "portMappings": [
        { "containerPort": 7080, "protocol": "tcp" }
      ],
      "environment": [
        { "name": "CODER_ACCESS_URL", "value": "https://coder.internal.company.com" },
        { "name": "CODER_WILDCARD_ACCESS_URL", "value": "*.coder.internal.company.com" },
        { "name": "CODER_SECURE_AUTH_COOKIE", "value": "true" },
        { "name": "CODER_STRICT_TRANSPORT_SECURITY", "value": "true" },
        { "name": "CODER_DISABLE_PATH_APPS", "value": "true" },
        { "name": "CODER_MAX_SESSION_EXPIRY", "value": "28800" },
        { "name": "CODER_RATE_LIMIT_DISABLE_ALL", "value": "false" },
        { "name": "CODER_TELEMETRY", "value": "false" },
        { "name": "CODER_OIDC_ISSUER_URL", "value": "https://auth.internal.company.com/application/o/coder/" },
        { "name": "CODER_OIDC_ALLOW_SIGNUPS", "value": "true" },
        { "name": "CODER_OAUTH2_GITHUB_DEFAULT_PROVIDER_ENABLE", "value": "false" }
      ],
      "secrets": [
        { "name": "CODER_PG_CONNECTION_URL", "valueFrom": "arn:aws:secretsmanager:::secret:prod/coder/database" },
        { "name": "CODER_OIDC_CLIENT_ID", "valueFrom": "arn:aws:secretsmanager:::secret:prod/coder/oidc:client_id::" },
        { "name": "CODER_OIDC_CLIENT_SECRET", "valueFrom": "arn:aws:secretsmanager:::secret:prod/coder/oidc:client_secret::" }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/coder/services",
          "awslogs-region": "us-west-2",
          "awslogs-stream-prefix": "coder"
        }
      }
    }
  ]
}
```

**ECS Service:**

```hcl
# terraform/services.tf — Coder ECS service

resource "aws_ecs_service" "coder" {
  name            = "coder-server"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.coder.arn
  desired_count   = 1  # OSS: single instance (multi-replica requires Enterprise)
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_subnet_ids
    security_groups  = [aws_security_group.ecs_services.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.coder.arn
    container_name   = "coder"
    container_port   = 7080
  }

  service_registries {
    registry_arn = aws_service_discovery_service.coder.arn
  }
}
```

```bash
# Deploy / Update
aws ecs update-service \
  --cluster coder-production \
  --service coder-server \
  --task-definition coder-server:LATEST \
  --force-new-deployment

aws ecs wait services-stable \
  --cluster coder-production \
  --services coder-server
```

**Deliverables:**
- `terraform/services.tf` — Coder ECS task definition + service

---

### 2.3 Supporting Services on ECS

#### Authentik (Identity Provider)

Deploy as ECS Fargate service. Connects to RDS (shared instance, separate database) and ElastiCache.

```hcl
resource "aws_ecs_service" "authentik" {
  name            = "authentik"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.authentik.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_subnet_ids
    security_groups  = [aws_security_group.ecs_services.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.authentik.arn
  }
}
```

**Corporate IdP Integration (Recommended for Production):**

Authentik is deployed for PoC parity but should be replaced with the organization's existing IdP in production:

| IdP | OIDC Issuer URL Example | Notes |
|-----|------------------------|-------|
| **Okta** | `https://company.okta.com/oauth2/default` | Most common enterprise IdP |
| **Azure AD** | `https://login.microsoftonline.com/{tenant}/v2.0` | If org uses M365 |
| **AWS IAM Identity Center** | `https://identitystore.{region}.amazonaws.com` | If AWS-native |
| **Authentik (keep)** | `https://auth.internal.company.com/application/o/coder/` | Only if no corporate IdP |

To swap: update `CODER_OIDC_ISSUER_URL`, `CODER_OIDC_CLIENT_ID`, `CODER_OIDC_CLIENT_SECRET` in Secrets Manager + ALB OIDC auth action config. No workspace changes needed.

> **Note:** AWS IAM (infrastructure auth) and OIDC IdP (application SSO) serve **different layers** — they are not duplicates. IAM controls who can manage AWS resources; OIDC controls who can log into Coder/workspaces.

#### LiteLLM (AI Gateway)

LiteLLM is the **centralized AI gateway** for all workspace AI traffic. It provides:
- OpenAI-compatible API (`/v1/chat/completions`) for Roo Code and OpenCode
- **Anthropic-native pass-through** (`/anthropic/v1/messages`) for Claude Code CLI
- Per-user virtual keys with budget caps and rate limits
- Provider routing (Bedrock primary, Anthropic fallback)
- Request/response logging to PostgreSQL for audit
- Model aliasing (workspaces request `claude-sonnet-4-5`, LiteLLM routes to the right provider)
- **Guardrail actions:** `block` (reject) or `mask` (redact PII with `[REDACTED]` tags) per key

Deploy as ECS Fargate service with task role for Bedrock access:

```hcl
resource "aws_ecs_task_definition" "litellm" {
  family                   = "litellm"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"
  task_role_arn            = aws_iam_role.litellm_task_role.arn
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name  = "litellm"
    image = "ghcr.io/berriai/litellm:main-latest"
    portMappings = [{ containerPort = 4000, protocol = "tcp" }]
    environment = [
      { name = "AWS_REGION_NAME", value = "us-west-2" }
    ]
    secrets = [
      { name = "DATABASE_URL", valueFrom = "arn:aws:secretsmanager:::secret:prod/litellm/database" },
      { name = "LITELLM_MASTER_KEY", valueFrom = "arn:aws:secretsmanager:::secret:prod/litellm/master-key" },
      { name = "ANTHROPIC_API_KEY", valueFrom = "arn:aws:secretsmanager:::secret:prod/litellm/anthropic-api-key" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/coder/services"
        "awslogs-region"        = "us-west-2"
        "awslogs-stream-prefix" = "litellm"
      }
    }
  }])
}
```

**LiteLLM config — Bedrock primary + Anthropic fallback:**

```yaml
# litellm/config.yaml (stored in S3 or embedded in task definition)
model_list:
  # Claude Sonnet — Bedrock primary (IAM role, no key), Anthropic fallback
  - model_name: claude-sonnet-4-5
    litellm_params:
      model: bedrock/us.anthropic.claude-sonnet-4-5-20250929-v1:0
      aws_region_name: us-west-2

  - model_name: claude-sonnet-4-5
    litellm_params:
      model: anthropic/claude-sonnet-4-5-20250929
      api_key: os.environ/ANTHROPIC_API_KEY

  # Claude Haiku — Bedrock primary, Anthropic fallback
  - model_name: claude-haiku-4-5
    litellm_params:
      model: bedrock/us.anthropic.claude-haiku-4-5-20251001-v1:0
      aws_region_name: us-west-2

  - model_name: claude-haiku-4-5
    litellm_params:
      model: anthropic/claude-haiku-4-5-20251001
      api_key: os.environ/ANTHROPIC_API_KEY

  # Claude Opus — Bedrock primary, Anthropic fallback
  - model_name: claude-opus-4
    litellm_params:
      model: bedrock/us.anthropic.claude-opus-4-20250514-v1:0
      aws_region_name: us-west-2

  - model_name: claude-opus-4
    litellm_params:
      model: anthropic/claude-opus-4-20250514
      api_key: os.environ/ANTHROPIC_API_KEY

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  database_url: os.environ/DATABASE_URL

litellm_settings:
  max_end_user_budget: 10.00
  drop_params: true
  success_callback: ["log_to_db"]
  failure_callback: ["log_to_db"]
  # Privacy-first: only log metadata (model, tokens, cost, latency) — no prompt/completion content
  turn_off_message_logging: true
  # Callbacks:
  # 1. enforcement_hook — injects system prompts based on key metadata (design-first)
  # 2. guardrails_hook — blocks or masks PII/financial/secrets based on key metadata
  callbacks: ["enforcement_hook.proxy_handler_instance", "guardrails_hook.guardrails_instance"]

  # Anthropic pass-through for Claude Code CLI (native Anthropic SDK format)
  # Enables /anthropic/v1/messages endpoint — same virtual keys, same guardrails
  enable_anthropic_pass_through: true
```

> **Model groups:** Each model name has two provider entries. LiteLLM tries Bedrock first (IAM role, no static key). If Bedrock fails (quota, region issue), it auto-falls back to Anthropic direct API. This is the same pattern validated in the PoC.

**Three AI Agent Support:**

| Agent | Protocol | LiteLLM Endpoint | Configuration |
|-------|----------|-------------------|---------------|
| **Roo Code** (VS Code) | OpenAI-compatible | `/v1/chat/completions` | `openAiBaseUrl` in settings.json |
| **OpenCode** (CLI) | OpenAI-compatible | `/v1/chat/completions` | `baseURL` in opencode.json |
| **Claude Code** (CLI) | Anthropic native | `/anthropic/v1/messages` | `ANTHROPIC_BASE_URL` env var |

Claude Code uses Anthropic's native SDK format. LiteLLM's `enable_anthropic_pass_through: true` routes these requests through the same proxy pipeline (virtual keys, guardrails, logging) without format translation. The enforcement hook **skips** Claude Code because it is inherently a plan-first agent (proposes changes before executing).

**PoC lesson applied:** The PoC proved LiteLLM model group failover works reliably. Production makes Bedrock the primary (IAM auth = no keys to manage) while keeping Anthropic API as a safety net.

**Deliverables:**
- `terraform/services.tf` — ECS task definitions + services for all platform components

---

### 2.4 Workspace Template (ECS Fargate)

**Goal:** Fargate-based workspaces with per-task network isolation

In production, Coder provisions workspaces as **ECS Fargate tasks** (not Docker containers or Kubernetes pods). This gives us:
- Per-task ENI — true network-level isolation (no shared node networking)
- Security group enforcement at the VPC level
- EFS access points for per-workspace home directory isolation
- No Docker socket access needed
- No node management or scheduling concerns

```hcl
# templates/contractor-workspace/main.tf (ECS Fargate version)
terraform {
  required_providers {
    coder = { source = "coder/coder" }
    aws   = { source = "hashicorp/aws" }
  }
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "coder_parameter" "cpu_cores" {
  name    = "cpu_cores"
  type    = "number"
  default = "2"
  option {
    name  = "2 vCPU"
    value = "2"
  }
  option {
    name  = "4 vCPU"
    value = "4"
  }
}

data "coder_parameter" "memory_gb" {
  name    = "memory_gb"
  type    = "number"
  default = "4"
  option {
    name  = "4 GB"
    value = "4"
  }
  option {
    name  = "8 GB"
    value = "8"
  }
}

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"
  display_apps {
    vscode                 = false
    vscode_insiders        = false
    web_terminal           = true
    ssh_helper             = false
    port_forwarding_helper = false
  }
}

# Per-workspace EFS access point (isolates home directory)
resource "aws_efs_access_point" "workspace" {
  file_system_id = var.efs_file_system_id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = "/workspaces/${data.coder_workspace_owner.me.name}/${lower(data.coder_workspace.me.name)}"
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "0755"
    }
  }

  tags = {
    Name  = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
    Owner = data.coder_workspace_owner.me.name
  }
}

resource "aws_ecs_task_definition" "workspace" {
  family                   = "coder-ws-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = data.coder_parameter.cpu_cores.value * 1024
  memory                   = data.coder_parameter.memory_gb.value * 1024
  task_role_arn            = var.workspace_task_role_arn
  execution_role_arn       = var.ecs_execution_role_arn

  volume {
    name = "home"
    efs_volume_configuration {
      file_system_id     = var.efs_file_system_id
      transit_encryption = "ENABLED"
      authorization_configuration {
        access_point_id = aws_efs_access_point.workspace.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([{
    name      = "dev"
    image     = var.workspace_image
    command   = ["sh", "-c", coder_agent.main.init_script]
    user      = "1000:1000"
    essential = true

    portMappings = [
      { containerPort = 13337, protocol = "tcp" }
    ]

    environment = [
      { name = "CODER_AGENT_TOKEN", value = coder_agent.main.token }
    ]

    mountPoints = [
      {
        sourceVolume  = "home"
        containerPath = "/home/coder"
        readOnly      = false
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/coder/workspaces"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = data.coder_workspace_owner.me.name
      }
    }
  }])
}

resource "aws_ecs_service" "workspace" {
  name            = "coder-ws-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.workspace.arn
  desired_count   = data.coder_workspace.me.start_count  # 0 when stopped, 1 when started
  launch_type     = "FARGATE"

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.workspace_security_group_id]
    assign_public_ip = false
  }
}
```

**Deliverables:**
- `templates/contractor-workspace/main.tf` — ECS Fargate workspace template
- `templates/contractor-workspace/build/Dockerfile` — Hardened workspace image
- ECR repository for workspace images

---

## Phase 3: Security Hardening (Week 5-6)

### 3.1 Workspace Isolation (Security Groups)

**Goal:** Workspaces cannot reach each other

Security groups provide network-level isolation enforced at the VPC layer. Each ECS Fargate task gets its own ENI, so security group rules apply per-task — not per-node.

**`sg-ecs-workspaces` rules:**

| Direction | Port | Protocol | Target | Purpose |
|-----------|------|----------|--------|---------|
| Inbound | 13337 | TCP | sg-alb | code-server access via ALB |
| Outbound | 4000 | TCP | sg-ecs-services | LiteLLM (AI proxy) |
| Outbound | 53 | UDP | VPC DNS (10.0.0.2) | DNS resolution |
| Outbound | 443 | TCP | 0.0.0.0/0 (via NAT) | Internet (package installs, external APIs) |
| **Denied** | Any | Any | sg-ecs-workspaces (self) | **No workspace-to-workspace traffic** |

> **Note:** Unlike Kubernetes network policies, security groups are enforced at the VPC level and are auditable via VPC Flow Logs. Each Fargate task has its own ENI, so there is no shared node networking that could be bypassed.

```hcl
# terraform/modules/vpc/ — workspace security group

resource "aws_security_group" "ecs_workspaces" {
  name_prefix = "sg-ecs-workspaces-"
  vpc_id      = aws_vpc.main.id

  # Inbound: only ALB for code-server
  ingress {
    from_port       = 13337
    to_port         = 13337
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Outbound: LiteLLM
  egress {
    from_port       = 4000
    to_port         = 4000
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_services.id]
  }

  # Outbound: DNS
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  # Outbound: Internet via NAT (package installs)
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

### 3.2 WAF & DDoS Protection

Not required — all endpoints are internal (VPN-only access). There are no public-facing endpoints, eliminating the need for WAF rules, geo-blocking, or DDoS protection. AWS Shield Standard is included with the ALB at no additional cost.

### 3.3 Authentication Hardening

- PKCE for all OAuth2 flows (configure in Authentik)
- MFA enforcement (Authentik TOTP/WebAuthn)
- Session timeouts: 8h max, 30m idle
- `CODER_SECURE_AUTH_COOKIE=true` (enforced by HTTPS via ACM)
- GuardDuty for anomalous API access detection

### 3.4 Container Image Security

- ECR image scanning (on push)
- Workspace images built in CI, scanned with Trivy
- Read-only root filesystem where possible
- No sudo in workspace containers
- Fargate: tasks run as non-root by default, no host access — no privileged containers, no host networking, no host PID namespace

**Deliverables:**
- Security group rules in `terraform/modules/vpc/`
- `terraform/modules/cloudwatch/` — VPC Flow Logs for security audit

---

## Phase 4: Observability (Week 7)

### 4.1 Logging

**CloudWatch Logs:**
- ECS task logs via `awslogs` log driver (built into Fargate — no sidecar needed)
- Log groups:
  - `/ecs/coder/services` — Platform services (Coder, Authentik, LiteLLM)
  - `/ecs/coder/workspaces` — Workspace task logs
- Retention: 90 days (services), 30 days (workspaces)

> **Note:** Fargate's built-in `awslogs` driver eliminates the need for a Fluent Bit DaemonSet or sidecar. All container stdout/stderr is sent directly to CloudWatch.

### 4.2 Metrics & Dashboards

**Option A: CloudWatch + Managed Grafana (recommended)**
- CloudWatch Container Insights for ECS metrics
- Amazon Managed Grafana for dashboards
- CloudWatch Alarms for alerts → SNS → PagerDuty/Slack

**Option B: Amazon Managed Prometheus (AMP) + Managed Grafana**
- Prometheus metrics from Coder, LiteLLM
- AMP for storage (no self-hosted Prometheus to manage)
- Managed Grafana for visualization

### 4.3 Key Dashboards

| Dashboard | Metrics |
|-----------|---------|
| Platform Overview | Active workspaces, user sessions, API latency, error rate |
| Workspace Scaling | Task count, Fargate utilization, pending tasks, desired vs running |
| AI Usage | Bedrock invocations, token consumption, model distribution, LiteLLM spend |
| Security | Failed logins, GuardDuty findings, OIDC errors, VPC Flow Log anomalies |

### 4.4 Alerts

| Alert | Condition | Severity | Action |
|-------|-----------|----------|--------|
| Coder API down | 0 healthy targets on ALB | P1 | Page on-call |
| Workspace build failures | >3 failures in 5 min | P2 | Notify Slack |
| RDS CPU >80% | 5 min sustained | P2 | Scale up RDS |
| ECS service unstable | Repeated task failures | P2 | Check task logs |
| Bedrock throttling | >10 throttle errors in 1 min | P3 | Check quotas |
| EFS throughput limit | >80% burst credits consumed | P3 | Consider provisioned throughput |

**Deliverables:**
- `terraform/modules/cloudwatch/` — Log groups, alarms, dashboards
- `grafana/dashboards/` — Dashboard JSON (if using Managed Grafana)

---

## Phase 5: Operational Readiness (Week 8)

### 5.1 CI/CD Pipeline (Self-Hosted GitLab)

CI/CD runs on the organization's **self-hosted GitLab** instance. Build jobs use a **GitLab Runner on AWS** (EC2-based) for ECR access and ECS deployment.

```yaml
# .gitlab-ci.yml
stages:
  - build
  - scan
  - deploy
  - post-deploy

variables:
  ECR_REPO: "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/coder-workspace"

build-workspace-image:
  stage: build
  tags: [aws-runner]  # GitLab Runner with AWS IAM access
  script:
    - aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO
    - docker build -t $ECR_REPO:$CI_COMMIT_TAG templates/contractor-workspace/build/
    - docker push $ECR_REPO:$CI_COMMIT_TAG
    - docker tag $ECR_REPO:$CI_COMMIT_TAG $ECR_REPO:latest
    - docker push $ECR_REPO:latest
  rules:
    - if: $CI_COMMIT_TAG =~ /^v.*/

scan-image:
  stage: scan
  tags: [aws-runner]
  script:
    - trivy image --severity CRITICAL,HIGH --exit-code 1 $ECR_REPO:$CI_COMMIT_TAG
  rules:
    - if: $CI_COMMIT_TAG =~ /^v.*/

deploy-coder:
  stage: deploy
  tags: [aws-runner]
  environment:
    name: production
  script:
    - aws ecs update-service --cluster coder-production --service coder-server --force-new-deployment
    - aws ecs wait services-stable --cluster coder-production --services coder-server
  rules:
    - if: $CI_COMMIT_TAG =~ /^v.*/
      when: manual  # Manual approval for production deploy

push-template:
  stage: post-deploy
  tags: [aws-runner]
  script:
    - coder templates push contractor-workspace
        --directory templates/contractor-workspace --yes
  rules:
    - if: $CI_COMMIT_TAG =~ /^v.*/
  needs: [deploy-coder]

terraform-plan:
  stage: build
  tags: [aws-runner]
  script:
    - cd terraform && terraform init && terraform plan -out=tfplan
  artifacts:
    paths: [terraform/tfplan]
  rules:
    - if: $CI_MERGE_REQUEST_IID
      changes: [terraform/**/*]

terraform-apply:
  stage: deploy
  tags: [aws-runner]
  environment:
    name: production
  script:
    - cd terraform && terraform init && terraform apply tfplan
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
      changes: [terraform/**/*]
      when: manual
```

#### GitLab Runner on AWS

The runner needs:
- **IAM Role** with permissions for: ECR (push/pull), ECS (UpdateService, DescribeServices), Secrets Manager (read), S3 (Terraform state)
- **Docker** for image builds (Docker-in-Docker or shell executor with Docker installed)
- **AWS CLI + Docker + Terraform + Coder CLI** for deployments

Options:
- **EC2-based runner** — Persistent instance, simpler setup, always available (recommended)
- **Fargate runner** — Ephemeral, pay-per-use, best isolation

### 5.2 Backup & Recovery

| Data | Method | Frequency | Retention | RPO |
|------|--------|-----------|-----------|-----|
| RDS (PostgreSQL) | Automated snapshots | Daily | 30 days | <24h |
| RDS (PostgreSQL) | Point-in-time recovery | Continuous | 30 days | <5 min |
| Authentik config | S3 export | Daily | 90 days | <24h |
| ECS task definitions | Versioned in Terraform | On change | Git history | 0 |
| Workspace EFS | AWS Backup for EFS | Daily | 14 days | <24h |

### 5.3 Disaster Recovery

| Scenario | RTO | RPO | Procedure |
|----------|-----|-----|-----------|
| Single AZ failure | <15 min | <5 min | ECS Fargate replaces tasks in healthy AZ; EFS is multi-AZ by default |
| RDS failure | <30 min | <5 min | Restore from latest automated snapshot (Single-AZ) |
| ECS task failure | <2 min | 0 | Fargate replaces failed tasks automatically (no nodes to manage) |
| Full region failure | <4 hours | <24h | Restore from S3 cross-region backups |
| Workspace data loss | <30 min | <24h | Restore from EFS AWS Backup snapshot |

### 5.4 Documentation

| Document | Audience |
|----------|----------|
| Architecture diagram (with AWS resource ARNs) | Engineering |
| Runbook: Coder upgrade | Ops |
| Runbook: Secret rotation | Ops |
| Runbook: Workspace template update | Platform admin |
| Runbook: User onboarding (SSO) | Platform admin |
| Runbook: Incident response | On-call |
| User guide: Workspace usage | Contractors |
| FAQ | All |

**Deliverables:**
- `.gitlab-ci.yml`
- `scripts/backup/` — Authentik export
- `docs/runbooks/`

---

## File Structure

```
aws-production/
├── PRODUCTION-PLAN.md
├── terraform/
│   ├── main.tf                     # Root module — infrastructure
│   ├── services.tf                 # ECS task definitions + services
│   ├── variables.tf
│   ├── outputs.tf
│   ├── backend.tf                  # S3 + DynamoDB state backend
│   └── modules/
│       ├── vpc/                    # VPC, subnets, NAT, endpoints
│       ├── ecs/                    # ECS cluster, Fargate, Cloud Map
│       ├── alb/                    # Internal ALB, HTTPS listener
│       ├── efs/                    # EFS for workspace storage
│       ├── rds/                    # PostgreSQL Single-AZ
│       ├── elasticache/            # Redis
│       ├── s3/                     # Buckets
│       ├── acm/                    # TLS certificates
│       ├── secrets/                # Secrets Manager entries
│       ├── iam/                    # ECS task roles + execution roles
│       └── cloudwatch/             # Alarms, log groups
├── templates/
│   └── contractor-workspace/
│       ├── main.tf                 # ECS Fargate workspace template
│       └── build/
│           └── Dockerfile          # Hardened workspace image
├── .gitlab-ci.yml                  # GitLab CI/CD pipeline
├── scripts/
│   ├── bootstrap.sh               # First-time setup
│   └── backup/
│       └── backup-authentik.sh
└── docs/
    ├── architecture.md
    └── runbooks/
```

---

## Implementation Timeline

### Week 1-2: AWS Foundation
| Day | Tasks |
|-----|-------|
| 1-2 | Terraform VPC + subnets + security groups |
| 3-4 | ECS cluster + Fargate capacity providers + Cloud Map |
| 5-6 | RDS + ElastiCache + EFS + S3 buckets |
| 7-8 | Secrets Manager + IAM task roles + execution roles |
| 9-10 | ACM certificates + Internal ALB + listener rules |

### Week 3-4: Core Platform
| Day | Tasks |
|-----|-------|
| 1-2 | Coder ECS service deployment + ALB routing |
| 3-4 | Authentik ECS deployment + OIDC config |
| 5-6 | LiteLLM ECS deployment + Bedrock integration |
| 9-10 | Workspace template (ECS Fargate) + ECR image |

### Week 5-6: Security Hardening
| Day | Tasks |
|-----|-------|
| 1-2 | Security group rules (workspace isolation) |
| 3-4 | VPC Flow Logs + GuardDuty |
| 5-6 | Container image scanning + non-root enforcement |
| 7-8 | Authentication hardening (PKCE, MFA, sessions) |
| 9-10 | Penetration testing + security review |

### Week 7: Observability
| Day | Tasks |
|-----|-------|
| 1-2 | CloudWatch log groups + awslogs driver config |
| 3-4 | Managed Grafana dashboards + Container Insights |
| 5 | CloudWatch Alarms + SNS notifications |

### Week 8: Operational Readiness
| Day | Tasks |
|-----|-------|
| 1-2 | CI/CD pipeline (GitLab CI + AWS Runner) |
| 3-4 | Backup scripts + DR test |
| 5 | Documentation + runbooks |

---

## Cost Estimation (Monthly)

### Small (50 users, 20 concurrent workspaces) — Coder OSS

| Resource | Specification | Monthly Cost |
|----------|---------------|--------------|
| ECS Fargate — Platform | Coder (1x 1vCPU/4GB, OSS), Authentik (2x 0.5vCPU/2GB), LiteLLM (2x 0.5vCPU/2GB) | $145 |
| ECS Fargate — Workspaces | 20 concurrent x 2vCPU x 4GB (Spot) | $450 |
| RDS PostgreSQL | db.r6g.large Single-AZ | $175 |
| ElastiCache Redis | cache.r6g.large | $200 |
| Internal ALB | 1 ALB + traffic | $25 |
| EFS | ~200 GB (20 workspaces x 10GB avg) | $60 |
| S3 | ~100 GB | $3 |
| Secrets Manager | ~10 secrets | $5 |
| CloudWatch | Logs + metrics | $50 |
| NAT Gateway | 1 (single AZ) | $35 |
| Bedrock (Claude) | ~$5/user/month avg | $250 |
| GitLab Runner | t3.large (shared) | $60 |
| **Total (OSS)** | | **~$1,470/month** |
| + Coder Enterprise | $66/user/month x 50 users | +$3,300/month |

> **Note:** Coder OSS is $0 license cost. Enterprise adds template RBAC, audit log streaming, and multi-replica HA but costs $66/user/month. For 50 users, Enterprise more than doubles the total. OSS + dual-path is recommended at this scale.

### Medium (200 users, 50 concurrent workspaces) — Coder OSS

| Resource | Specification | Monthly Cost |
|----------|---------------|--------------|
| ECS Fargate — Platform | Coder (1x 2vCPU/8GB, OSS), Authentik (2x 1vCPU/4GB), LiteLLM (2x 1vCPU/4GB) | $330 |
| ECS Fargate — Workspaces | 50 concurrent x 2vCPU x 4GB (Spot) | $1,120 |
| RDS PostgreSQL | db.r6g.xlarge Single-AZ | $350 |
| ElastiCache Redis | cache.r6g.xlarge | $400 |
| Internal ALB | 1 ALB + traffic | $40 |
| EFS | ~500 GB (50 workspaces x 10GB avg) | $150 |
| S3 | ~500 GB | $12 |
| Secrets Manager | ~10 secrets | $5 |
| Managed Grafana | 1 workspace | $9 |
| CloudWatch | Logs + metrics | $100 |
| NAT Gateway | 1 (single AZ) | $35 |
| GitLab Runner | t3.xlarge (shared) | $120 |
| Bedrock (Claude) | ~$5/user/month avg | $1,000 |
| **Total (OSS)** | | **~$3,700/month** |
| + Coder Enterprise | $66/user/month x 200 users | +$13,200/month |

> **Evaluate Enterprise at 200+ users** if template RBAC (restrict template visibility by group) or audit log streaming (compliance) is required. At 200 users, Enterprise adds $13.2K/month — a 3.5x increase.

### Cost Optimization

| Strategy | Savings | Trade-off |
|----------|---------|-----------|
| Fargate Spot for workspaces | ~70% on workspace compute | 2-min interruption notice |
| Compute Savings Plans (1-yr) | ~20-30% on Fargate | Commitment |
| EFS Intelligent-Tiering / Infrequent Access | ~60% on cold data | 30-day minimum before IA transition |
| Scale workspace tasks to 0 when stopped | ~50% on workspace Fargate | Cold start on resume (~30-60s) |
| S3 Intelligent-Tiering | ~30% on storage | Minimal |

---

## Success Criteria

### Infrastructure
- [ ] All services running on ECS Fargate (no Docker Compose)
- [ ] Single-AZ RDS with automated daily snapshots + PITR
- [ ] Workspace tasks auto-scale via ECS service desired_count (0 when stopped, 1 when started)
- [ ] EFS multi-AZ storage verified for all workspaces
- [ ] DR restore tested from S3 backups and EFS snapshots

### Security
- [ ] Zero hardcoded credentials (all in Secrets Manager)
- [ ] ACM TLS on all internal endpoints
- [ ] Bedrock via IAM task roles (no static API keys)
- [ ] Security groups isolate workspace tasks (no workspace-to-workspace traffic)
- [ ] Fargate tasks run non-root, no host access
- [ ] ECR image scanning enabled
- [ ] PKCE + MFA on OIDC flows
- [ ] VPC Flow Logs enabled for audit

### Operational
- [ ] GitLab CI/CD deploys Coder + templates automatically
- [ ] CloudWatch alarms → PagerDuty/Slack
- [ ] Grafana dashboards for all key metrics
- [ ] Runbooks for top 5 incident types
- [ ] Backup/restore tested end-to-end
- [ ] < 5 min RTO for single-service failure

### Application
- [ ] Workspace creation < 2 minutes (including Fargate cold start)
- [ ] Roo Code + OpenCode + Claude Code + LiteLLM + Bedrock working end-to-end
- [ ] Claude Code CLI using Anthropic pass-through (`/anthropic/v1/messages`)
- [ ] OIDC login working (Authentik or corporate IdP)
- [ ] Dual-path access verified (Coder tunnel + direct ALB)
- [ ] Direct path continues working during Coder server restart
- [ ] Git clone/push working (existing GitLab with Azure AD SSO)
- [ ] All PoC features preserved

---

## Risk Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Fargate cold start time (~30-60s) | High | Low | Acceptable for dev workspaces; keep platform services always-on |
| Bedrock model availability / quotas | Medium | High | Request quota increases early; keep Anthropic API as fallback |
| Fargate Spot interruption | Medium | Low | 2-min notice; workspace state on EFS survives interruption; auto-restart |
| Authentik → corporate IdP migration | Medium | Medium | Abstract OIDC config; test with target IdP early; ALB OIDC auth action also needs IdP update |
| Cost overrun on Bedrock | Medium | Medium | LiteLLM budget caps + CloudWatch billing alarms |
| Coder OSS single-instance restart | Medium | Low | Dual-path: direct ALB path is unaffected; ECS restarts in 30-60s; only management operations (workspace create/stop) are briefly interrupted |
| Template migration (Docker → ECS Fargate) | High | Medium | Parallel testing; keep Docker template for PoC fallback |
| Coder ECS provisioning maturity | Medium | Medium | Coder's Kubernetes provisioner is more mature than direct ECS; mitigate with thorough template testing and Coder community engagement |

---

## Decision Log

| Decision | Choice | Rationale | Alternatives Considered |
|----------|--------|-----------|------------------------|
| **Coder Edition** | **OSS (Community)** | $0 license; dual-path architecture provides zero-downtime for active developers during Coder restarts; template RBAC is UX convenience (layer 5 of 5 security layers), not a security requirement — Git permissions control code access; evaluate Enterprise at 200+ users | Enterprise ($66/user/mo — template RBAC, audit streaming, multi-replica HA) |
| **Workspace Access** | **Dual-path (tunnel + direct ALB)** | Path 1 (Coder tunnel) for management; Path 2 (direct ALB→code-server) for data plane. Both hit the same code-server. Direct path is independent from Coder server, providing zero-downtime for developers | Tunnel only (single point of failure), direct only (loses Coder management features) |
| Compute | ECS Fargate | Each task = isolated ENI + security group; no node management; simpler security model; no Kubernetes expertise needed | EKS (more ecosystem but more complexity), EC2+Docker (PoC pattern) |
| Access | Private/VPN only | Reduces attack surface, eliminates WAF/Shield needs, simpler security model | Public (more exposure), VPN + public fallback |
| Database | RDS Single-AZ | Zero-ops, automated backups, cost-effective | Multi-AZ (upgrade later for HA), Aurora (overkill), self-managed Patroni |
| Storage | EFS | Multi-AZ persistent storage, per-workspace access points, no EBS attachment limits | EBS (single-AZ, must attach to node), S3 + FUSE (latency) |
| CI/CD | Self-hosted GitLab + AWS Runner | Existing org tooling; runner on AWS for ECR/ECS access | GitHub Actions, CodePipeline, Jenkins |
| **AI Agents** | **Roo Code + OpenCode + Claude Code** | Three agent options: Roo Code (VS Code UI), OpenCode (CLI), Claude Code (Anthropic native CLI, plan-first). All route through LiteLLM proxy with same guardrails and virtual keys | Single agent (limits developer choice), direct API access (no centralized controls) |
| AI Gateway | LiteLLM (Bedrock primary + Anthropic fallback) | Centralized proxy with per-user keys, budget caps, audit logging; Anthropic pass-through for Claude Code CLI | Direct Bedrock only (no abstraction), Anthropic only (needs key management) |
| Secrets | Secrets Manager | Native IAM, direct ECS integration for secret injection | Vault (more ops), SSM Parameter Store (less features) |
| TLS | ACM + Internal ALB | Free, auto-renewal, no cert management | Let's Encrypt (more ops), self-signed (PoC pattern) |
| Monitoring | CloudWatch + Managed Grafana | Less ops than self-hosted Prometheus stack | AMP+AMG (more cost), self-hosted (more ops) |
| **Identity** | **Authentik on ECS → Corporate IdP** | Authentik for PoC parity; production should swap to org's existing IdP (Okta/Azure AD) — just change OIDC issuer URL + client credentials. ALB OIDC auth for direct path uses same IdP | Cognito (less flexible), keep Authentik long-term (unnecessary ops) |
| Git | Existing GitLab (Azure AD SSO) | Use org's existing Git platform; no additional infrastructure needed | Gitea on ECS (PoC pattern), CodeCommit (limited) |
| Service Discovery | AWS Cloud Map | Native ECS integration, private DNS namespace | Route 53 resolver (more manual), consul (more ops) |

---

## Next Steps

1. **Immediate:** Rotate exposed AWS credentials from PoC `.env`
2. **Week 1:** Begin Terraform modules (VPC, ECS, RDS)
3. **Week 1:** Request Bedrock model access + quota increases
4. **Week 2:** Set up CI/CD pipeline for Terraform plan/apply
5. **Week 3:** Deploy Coder via ECS, validate workspace creation
6. **Ongoing:** Security review at each phase gate

---

*Plan updated February 8, 2026 — dual-path architecture, Coder OSS single-instance, Claude Code CLI, corporate IdP guidance*
*Plan updated February 6, 2026 — retargeted for AWS (ECS Fargate + managed services, VPN-only access)*
*Original plan (Docker Compose) created February 4, 2026 from PoC Security Review findings*
*Architecture changed from EKS to ECS Fargate — eliminates Kubernetes complexity, simplifies operations*
