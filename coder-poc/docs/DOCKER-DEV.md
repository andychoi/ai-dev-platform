# Docker-Based Development in Workspaces

Options for running Docker and Docker Compose inside Coder workspaces, covering both the PoC (Docker Compose on local host) and AWS production (ECS Fargate). Includes security analysis for each approach.

## Table of Contents

1. [Problem Statement](#1-problem-statement)
2. [PoC Options](#2-poc-options)
3. [PoC Option A: Host Socket Mount (DooD)](#3-poc-option-a-host-socket-mount-dood)
4. [PoC Option B: DinD Sidecar (Privileged)](#4-poc-option-b-dind-sidecar-privileged)
5. [PoC Option C: Rootless DinD (Recommended)](#5-poc-option-c-rootless-dind-recommended)
6. [Production Constraint: Fargate Has No Docker](#6-production-constraint-fargate-has-no-docker)
7. [Production Options](#7-production-options)
8. [Production Option A: ECS on EC2](#8-production-option-a-ecs-on-ec2)
9. [Production Option B: Remote Docker Host](#9-production-option-b-remote-docker-host)
10. [Production Option C: AWS CodeBuild](#10-production-option-c-aws-codebuild)
11. [Production Option D: EKS + Sysbox](#11-production-option-d-eks--sysbox)
12. [Production Option E: Compose-to-ECS Translation](#12-production-option-e-compose-to-ecs-translation)
13. [Comparison Matrices](#13-comparison-matrices)
14. [Recommendation](#14-recommendation)
15. [Template Strategy](#15-template-strategy)
16. [Mixed Fargate + EC2 Architecture (Recommended Production)](#16-mixed-fargate--ec2-architecture-recommended-production)
17. [Access Control: Docker Workspace Authorization](#17-access-control-docker-workspace-authorization)
18. [Testing & Validation](#18-testing--validation)

---

## 1. Problem Statement

Some development workflows require running multi-container applications locally:

- Backend + database + cache (`docker compose up`)
- Building container images (`docker build`)
- Integration testing against real services
- Microservice development with local dependencies

The current workspace template disables Docker (`CODER_AGENT_DEVCONTAINERS_ENABLE=false`) because:

- Most developers don't need it
- Docker inside containers is a privilege escalation risk
- The base template follows least-privilege principles

This document evaluates options for enabling Docker selectively, via a separate template.

---

## 2. PoC Options

Three approaches for Docker inside workspaces running on Docker Compose (local host).

| Option | Method | Security Risk | Complexity |
|--------|--------|---------------|------------|
| A: Host Socket Mount | Mount `/var/run/docker.sock` | High | Low |
| B: DinD Sidecar | Privileged `docker:dind` container | Medium | Medium |
| **C: Rootless DinD** | `docker:dind-rootless` container | **Low** | Medium |

---

## 3. PoC Option A: Host Socket Mount (DooD)

The workspace mounts the host's Docker socket and shares the host's Docker daemon.

```
Host Docker Daemon
  ├── coder-server
  ├── gitea
  ├── litellm
  ├── workspace-1  ←── mounts /var/run/docker.sock
  │   └── docker CLI → talks to host daemon
  │       └── user's app containers (visible to host!)
  └── workspace-2
```

**Template addition:**

```hcl
volumes {
  host_path      = "/var/run/docker.sock"
  container_path = "/var/run/docker.sock"
}
```

**Dockerfile addition:**

```dockerfile
RUN apt-get update && apt-get install -y docker.io docker-compose-v2 \
    && usermod -aG docker coder
```

### Security Assessment: HIGH RISK

| Threat | Impact | Likelihood |
|--------|--------|------------|
| **See all host containers** | `docker ps` shows coder-server, postgres, etc. | Certain |
| **Stop infrastructure** | `docker stop coder-server` kills the platform | Easy |
| **Inspect other workspaces** | `docker exec` into another user's workspace | Easy |
| **Host filesystem access** | `docker run -v /:/host` mounts entire host | Easy |
| **Privilege escalation** | `docker run --privileged` → root on host | Easy |

**Verdict:** Only acceptable for single-user PoC testing with full trust. Not suitable for multi-user environments.

---

## 4. PoC Option B: DinD Sidecar (Privileged)

A dedicated `docker:dind` container runs alongside each workspace. The workspace connects to it via TCP.

```
Host Docker Daemon
  ├── coder-server, gitea, litellm, ...
  ├── workspace-1
  │   └── DOCKER_HOST=tcp://dind-ws1:2375
  └── dind-ws1 (privileged)
      └── isolated Docker daemon
          ├── user's app container A
          └── user's app container B
```

**Template addition:**

```hcl
resource "docker_container" "dind" {
  name       = "dind-${data.coder_workspace.me.name}"
  image      = "docker:dind"
  privileged = true
  env        = ["DOCKER_TLS_CERTDIR="]

  networks_advanced {
    name = data.docker_network.coder.name
  }
}

# In workspace container env
env {
  name  = "DOCKER_HOST"
  value = "tcp://dind-${data.coder_workspace.me.name}:2375"
}
```

### Security Assessment: MEDIUM RISK

| Threat | Impact | Mitigated? |
|--------|--------|------------|
| See other workspaces' containers | Isolated — each workspace has its own DinD | Yes |
| Stop infrastructure containers | DinD is separate from host daemon | Yes |
| Container escape from DinD | `--privileged` on DinD allows kernel-level escape | Partially — escapes to DinD, not directly to host |
| Resource exhaustion | DinD can consume host resources | Needs cgroup limits |
| Network sniffing | DinD on shared Docker network | Use dedicated network per DinD |

**Verdict:** Good balance for multi-user PoC. Each workspace gets its own isolated Docker daemon. The `--privileged` flag on DinD is the main risk.

---

## 5. PoC Option C: Rootless DinD (Recommended)

Same as Option B but using rootless Docker. No `--privileged` required.

```
Host Docker Daemon
  ├── coder-server, gitea, litellm, ...
  ├── workspace-1
  │   └── DOCKER_HOST=tcp://dind-ws1:2375
  └── dind-ws1 (rootless, unprivileged)
      └── rootless Docker daemon (user namespace)
          ├── user's app container A
          └── user's app container B
```

**Template addition:**

```hcl
resource "docker_container" "dind" {
  name  = "dind-${data.coder_workspace.me.name}"
  image = "docker:dind-rootless"
  env   = ["DOCKER_TLS_CERTDIR="]

  # Required for rootless — no privileged flag
  security_opts = ["seccomp=unconfined", "apparmor=unconfined"]

  networks_advanced {
    name = data.docker_network.coder.name
  }
}
```

### Security Assessment: LOW RISK

| Threat | Impact | Mitigated? |
|--------|--------|------------|
| Container escape | Rootless — runs in user namespace, no root on host | Yes |
| See other workspaces | Isolated DinD per workspace | Yes |
| Privilege escalation | No `--privileged`, no root daemon | Yes |
| Resource exhaustion | Same as Option B — needs cgroup limits | Needs limits |

### Compatibility Limitations

| Limitation | Impact on Typical Dev Workflows | Workaround |
|-----------|--------------------------------|------------|
| No `overlay2` storage driver | Uses `fuse-overlayfs` — slightly slower builds | Acceptable — transparent to user |
| No privileged nested containers | Can't run `--privileged` inside DinD | Rarely needed for app dev |
| Ports < 1024 require config | Can't bind port 80 or 443 inside | Use 3000, 8080, etc. (standard for dev) |
| Some overlay network drivers limited | `docker network create --driver overlay` may fail | Use default `bridge` — works for Compose |
| AppArmor/seccomp constraints | Some syscalls blocked | `seccomp=unconfined` resolves most issues |

**For typical `docker compose` with app + postgres + redis:** All of these work fine. The limitations affect advanced Docker features, not standard development workflows.

**Verdict:** Best option for PoC. Secure, isolated, and compatible with standard Docker Compose development.

---

## 6. Production Constraint: Fargate Has No Docker

**ECS Fargate fundamentally cannot run nested containers.**

A Fargate task IS the container runtime — there is no Docker daemon, no socket, no DinD capability. This is by design (serverless isolation).

```
PoC (works):
  Host Docker → Workspace → DinD Sidecar → User's app containers ✓

Production Fargate (impossible):
  Fargate Task = Workspace → ??? No Docker daemon ✗
```

The rootless DinD compatibility issues from the PoC are **irrelevant** in production — the entire DinD approach doesn't translate to Fargate. Production requires a fundamentally different strategy.

---

## 7. Production Options

| Option | Method | Docker Compose Dev? | Build Images? | Interactive? |
|--------|--------|:---:|:---:|:---:|
| A: ECS on EC2 | EC2 instances with DinD | Yes | Yes | Yes |
| B: Remote Docker Host | Shared EC2 Docker server | Yes | Yes | Yes |
| C: AWS CodeBuild | Trigger builds from workspace | No | Yes | No |
| D: EKS + Sysbox | Kubernetes with secure nesting | Yes | Yes | Yes |
| E: Compose-to-ECS | Translate compose to ECS tasks | Partial | No | Partial |

---

## 8. Production Option A: ECS on EC2

Run workspaces that need Docker on EC2-backed ECS (not Fargate). The EC2 instance has Docker, enabling DinD sidecar.

```
ECS Cluster
  ├── Fargate capacity (standard workspaces — no Docker)
  └── EC2 capacity (docker-enabled workspaces)
      └── EC2 Instance
          ├── Workspace Task
          └── DinD Sidecar Task (rootless)
```

| Pros | Cons |
|------|------|
| Full Docker support, same DinD pattern as PoC | Must manage EC2 instances (AMI, patching, scaling) |
| Mixed cluster: Fargate for most, EC2 for Docker users | EC2 capacity reserved even when idle |
| Familiar `docker compose` workflow for developers | More complex infrastructure |
| Can use rootless DinD (same security as PoC) | Shared EC2 host = blast radius concern |

**Security:** Same as PoC Option C (rootless DinD). EC2 instance should be hardened and in a dedicated subnet.

---

## 9. Production Option B: Remote Docker Host

Workspaces stay on Fargate but connect to a dedicated EC2 instance running Docker daemon via TCP/TLS.

```
┌─────────────────────────────────┐     ┌─────────────────────────────┐
│  ECS Fargate (workspace)        │     │  EC2 (Docker Host)          │
│                                 │     │                             │
│  DOCKER_HOST=tcp://docker:2376  │────▶│  Docker Daemon (TLS)        │
│  Docker CLI + Compose           │     │  ├── user1's containers     │
│                                 │     │  ├── user2's containers     │
└─────────────────────────────────┘     │  └── user3's containers     │
                                        └─────────────────────────────┘
```

| Pros | Cons |
|------|------|
| Workspaces stay on Fargate (serverless) | Shared daemon — security concerns (see below) |
| No EC2 management for workspaces | Single point of failure |
| Simpler than mixed ECS cluster | Network hop adds latency to builds |
| Easy to scale Docker host independently | Docker host needs active management |

### Security Assessment: MEDIUM-HIGH RISK

This option requires careful analysis because multiple workspaces share a single Docker daemon.

#### Threat Model

| Threat | Description | Severity | Likelihood |
|--------|-------------|----------|------------|
| **Cross-user container visibility** | User A runs `docker ps` and sees User B's containers, images, volumes | High | Certain (without mitigation) |
| **Cross-user container manipulation** | User A can `docker stop`, `docker exec`, or `docker logs` User B's containers | Critical | Certain (without mitigation) |
| **Host filesystem escape** | `docker run -v /:/host alpine` mounts entire Docker host filesystem | Critical | Easy (without mitigation) |
| **Privileged container escape** | `docker run --privileged` → root access on Docker host | Critical | Easy (without mitigation) |
| **Resource exhaustion (noisy neighbor)** | One user's containers consume all CPU/memory/disk on the Docker host | High | Likely |
| **Image supply chain** | Pulling malicious images that mine crypto or exfiltrate data | Medium | Possible |
| **Network sniffing** | Containers on shared bridge network can sniff each other's traffic | Medium | Possible |
| **Data persistence leaks** | Volumes and images from one user persist and may be accessible to others | Medium | Likely |
| **TLS credential theft** | If Docker TLS client certs are compromised, full daemon access | High | Depends on key management |
| **Daemon compromise** | Docker daemon vulnerability → host-level access for all users | Critical | Low (if patched) |

#### Required Mitigations

To make Option B viable, ALL of the following are required:

**1. Docker Authorization Plugin** — Restricts what each user can do.

```json
// Example: OPA-based authz plugin
{
  "authorization-plugins": ["openpolicyagent"]
}
```

Rules: Users can only manage containers with their own labels. No `--privileged`, no host volume mounts, no `--pid=host`, no `--network=host`.

**2. User Namespace Remapping** — Prevents root-in-container = root-on-host.

```json
// /etc/docker/daemon.json
{
  "userns-remap": "default"
}
```

**3. Per-User Network Isolation** — Each user gets a dedicated Docker network.

```bash
# Provisioned per workspace
docker network create --internal user-${WORKSPACE_ID}
# All user containers join only this network
```

**4. Resource Limits** — Prevent noisy-neighbor via cgroup constraints.

```bash
# Per-user limits enforced by authz plugin
docker run --memory=2g --cpus=2 --pids-limit=100 ...
```

**5. Container Labeling** — All containers tagged with workspace identity.

```bash
docker run --label workspace=${WORKSPACE_ID} --label user=${USERNAME} ...
```

**6. Periodic Cleanup** — Cron job to remove dangling images/volumes/containers.

```bash
# Every hour
docker system prune -f --filter "until=2h"
docker volume prune -f --filter "label!=persistent"
```

**7. TLS Mutual Auth** — Docker daemon requires client certificates.

```json
{
  "tls": true,
  "tlscacert": "/certs/ca.pem",
  "tlscert": "/certs/server-cert.pem",
  "tlskey": "/certs/server-key.pem",
  "tlsverify": true
}
```

Each workspace gets unique client certs, provisioned at startup, revoked on teardown.

**8. Monitoring & Alerting** — CloudWatch agent on Docker host tracking container events, resource usage, and anomalous behavior.

#### Residual Risk

Even with all mitigations, the shared daemon model has inherent risks:

- Authorization plugins add complexity and can have bypass vulnerabilities
- Docker daemon is a single process — a crash affects all users
- Zero-day Docker vulnerabilities affect all workspaces simultaneously
- Cleanup timing windows may allow brief cross-user visibility

**Verdict:** Viable but operationally heavy. The mitigation stack (authz plugin, userns remap, per-user networks, TLS certs, cleanup cron) is significant. Consider Option A (EC2-backed ECS) if more than 10-20 Docker-enabled users are expected.

---

## 10. Production Option C: AWS CodeBuild

Workspaces trigger AWS CodeBuild projects for container builds. No Docker in the workspace.

```
Workspace (Fargate)              AWS CodeBuild
  │                                │
  │ aws codebuild start-build     │
  │ ──────────────────────────────▶│
  │                                │ docker build
  │                                │ docker compose up (test)
  │ poll / webhook                 │ docker push → ECR
  │ ◀──────────────────────────────│
  │                                │
```

| Pros | Cons |
|------|------|
| No Docker in workspace at all | Not interactive — build-only workflow |
| AWS-managed, auto-scaling | Can't run `docker compose up` for dev |
| IAM-scoped (per-project build role) | Cold start delay (30-60s) |
| Isolated build environments | Different mental model for developers |

**Security:** Best — no Docker exposure in workspaces. Builds run in isolated, short-lived CodeBuild environments.

**Use case:** CI/CD image builds, not interactive Docker Compose development.

---

## 11. Production Option D: EKS + Sysbox

Switch from ECS to Amazon EKS (Kubernetes) and use the [Sysbox](https://github.com/nestybox/sysbox) container runtime for secure nested containers.

```
EKS Cluster
  └── Node (Sysbox runtime)
      └── Pod: workspace
          └── Sysbox container (looks like a VM)
              └── Docker daemon (unprivileged, user-namespace isolated)
                  ├── user's app container A
                  └── user's app container B
```

| Pros | Cons |
|------|------|
| Secure nested containers (no `--privileged`) | Requires EKS instead of ECS (different orchestrator) |
| Each workspace is fully isolated | Sysbox needs to be installed on EKS nodes |
| Transparent Docker experience for developers | More complex infrastructure |
| Production-grade solution used by Coder Enterprise | Higher operational overhead |

**Security:** Best for interactive Docker. Sysbox provides VM-level isolation without actual VMs.

---

## 12. Production Option E: Compose-to-ECS Translation

Translate `docker-compose.yml` into ECS task definitions. Each Compose service becomes a sidecar container in the same task.

```
docker-compose.yml:                   ECS Task Definition:
  services:                             containers:
    app:          ──translate──▶          - name: app
      image: myapp                          image: myapp
    db:                                   - name: db
      image: postgres                       image: postgres
    redis:                                - name: redis
      image: redis                          image: redis
```

Tools: [ecs-cli compose](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/cmd-ecs-cli-compose.html), [docker compose ECS integration](https://docs.docker.com/cloud/ecs-integration/)

| Pros | Cons |
|------|------|
| Native ECS — no Docker daemon needed | Not transparent — compose features differ |
| Per-task isolation | No `docker build` (images must be pre-built in ECR) |
| Works on Fargate | Developer must adapt workflow |
| AWS-managed networking and service discovery | Volume mounts and networking work differently |

**Security:** Good — each task runs in Fargate isolation. No shared daemon.

**Use case:** Teams with fixed Compose stacks that can be pre-built. Not suitable for active container development.

---

## 13. Comparison Matrices

### PoC Options

| Criteria | A: Socket Mount | B: DinD Privileged | C: Rootless DinD |
|----------|:---:|:---:|:---:|
| Security | Poor | Good | Best |
| Setup complexity | Low | Medium | Medium |
| `docker compose` works | Yes | Yes | Yes |
| Per-workspace isolation | No | Yes | Yes |
| Privileged mode required | No | Yes (sidecar) | No |
| Resource overhead | None | ~256MB/workspace | ~256MB/workspace |

### Production Options

| Criteria | A: EC2 | B: Remote Host | C: CodeBuild | D: EKS+Sysbox | E: Compose-ECS |
|----------|:---:|:---:|:---:|:---:|:---:|
| Interactive Docker | Yes | Yes | No | Yes | Partial |
| `docker compose up` | Yes | Yes | No | Yes | Partial |
| `docker build` | Yes | Yes | Yes | Yes | No |
| Security | Good | Medium (heavy mitigations) | Best | Best | Good |
| Operational complexity | Medium | High | Low | High | Medium |
| Fargate workspaces | No (EC2) | Yes | Yes | No (EKS) | Yes |
| Per-user isolation | Yes (rootless DinD) | Requires authz plugin | Yes (build env) | Yes (Sysbox) | Yes (task) |
| Cost efficiency | Medium | Good (shared host) | Good (pay-per-build) | Medium | Good |
| Scales to 100+ users | Yes | Needs multiple hosts | Yes | Yes | Yes |

---

## 14. Recommendation

### PoC

**Use Option C (Rootless DinD)** in a separate template.

- Works for standard `docker compose` workflows
- No `--privileged` flag
- Isolated per workspace
- Compatible with app + database + cache patterns

### Production — Mixed Fargate + EC2 (Recommended)

| Tier | Users | Approach |
|------|-------|----------|
| **Standard** (80-90% of users) | Developers who write code and push to Git | **Fargate** workspaces, no Docker. CI/CD builds containers. |
| **Docker-enabled** (10-20%) | Developers who need interactive Docker | **EC2** capacity provider with rootless DinD sidecar |

Both tiers run in the **same ECS cluster** using capacity providers. Standard workspaces use Fargate (serverless). Docker workspaces are placed on EC2 instances via a separate capacity provider. The EC2 ASG scales to zero when no Docker workspaces are running — **no cost when idle**.

See [Section 16](#16-mixed-fargate--ec2-architecture-recommended-production) for full architecture and Terraform module.

If only a few users need Docker and you want to keep everything on Fargate, **Option B (Remote Docker Host)** is viable but requires the full mitigation stack (authz plugin, userns remap, TLS certs, per-user networks, cleanup).

For organizations already using Kubernetes: **Option D (EKS + Sysbox)** is the production-grade answer.

---

## 15. Template Strategy

Both PoC and production should use separate templates to enforce least-privilege:

```
templates/
├── python-workspace/          # Standard — no Docker
│   └── main.tf               # Current template, egress-controlled
├── docker-workspace/          # Docker-enabled — rootless DinD
│   ├── main.tf               # Adds DinD sidecar + DOCKER_HOST env
│   └── build/
│       └── Dockerfile         # Base + docker CLI + docker-compose
└── (production only)
    └── docker-workspace-ec2/  # EC2-backed with rootless DinD
        └── main.tf            # ECS EC2 launch type + DinD task
```

**Access control:** Use Coder template RBAC to restrict docker-enabled templates to approved users/groups. In Coder OSS (PoC), all members can use all templates — restrict via Authentik group membership and admin review. In Coder Enterprise or production, use template ACLs.

---

## 16. Mixed Fargate + EC2 Architecture (Recommended Production)

The recommended production approach uses **ECS capacity providers** to run both Fargate and EC2 workloads in the same cluster. This avoids managing a separate EC2 fleet for the minority of users who need Docker.

### Architecture

```
ECS Cluster
  │
  ├── Capacity Provider: FARGATE (default)
  │     └── Standard workspace tasks (80-90%)
  │         └── No Docker, serverless, zero infra management
  │
  └── Capacity Provider: EC2_DOCKER (on-demand)
        └── Auto Scaling Group (min=0, max=N)
            └── EC2 Instance (ECS-optimized AMI)
                ├── Docker-enabled workspace task
                └── Rootless DinD sidecar task
                    └── User's app containers
```

### How It Works

1. **Standard workspaces** use the default Fargate capacity provider — no change from current architecture.
2. **Docker workspaces** use a Coder template that specifies `capacityProviderStrategy = [{ capacityProvider: "EC2_DOCKER" }]`.
3. When ECS places a Docker workspace task, it signals the EC2 capacity provider.
4. The capacity provider's **managed scaling** policy tells the ASG to launch an EC2 instance.
5. The EC2 instance joins the cluster (ECS agent in userdata), and the task is placed on it.
6. When all Docker workspaces stop, **managed termination protection** drains the instance, and the ASG scales back to zero.

### Scale-to-Zero Behavior

The key cost advantage: **EC2 instances only exist while Docker workspaces are running.**

```
Timeline:
  t0  ─── No Docker workspaces ─── ASG: 0 instances ─── Cost: $0
  t1  ─── User creates Docker workspace ─── ASG scales to 1 ─── ~60s
  t2  ─── User working ─── Instance running ─── ~$0.05/hr (t3.medium)
  t3  ─── User stops workspace ─── Task drains ─── Instance terminates
  t4  ─── ASG: 0 instances ─── Cost: $0
```

Cold-start penalty: ~60-90 seconds for the first Docker workspace (EC2 launch + ECS agent registration). Subsequent workspaces on the same instance start immediately.

### Operational Overhead

| Aspect | Fargate Only | Mixed Fargate + EC2 |
|--------|-------------|---------------------|
| AMI management | None | ECS-optimized AMI (auto-updated by AWS) |
| Patching | None | SSM Patch Manager or AMI rebuild |
| Scaling | Automatic | ASG managed scaling (automatic) |
| Monitoring | CloudWatch Container Insights | + EC2 instance metrics |
| Cost when idle | $0 | $0 (scale-to-zero ASG) |
| Terraform complexity | ~50 lines (ECS module) | ~150 lines (ecs-ec2-docker module) |

**Verdict:** Low operational overhead. The ECS-optimized AMI handles Docker and the ECS agent out of the box. Managed scaling and termination protection are built into ECS. The main operational task is occasional AMI updates (quarterly, or when security patches release).

### Terraform Module

A dedicated module at `aws-production/terraform/modules/ecs-ec2-docker/` provides:

- EC2 launch template (ECS-optimized AMI, userdata to join cluster)
- Auto Scaling Group (min=0, desired=0, max=configurable)
- ECS capacity provider with managed scaling
- Security group for EC2 Docker instances
- IAM instance profile for ECS agent

The module registers the capacity provider on the existing ECS cluster. Coder workspace templates reference it via `capacityProviderStrategy`.

```hcl
# In root main.tf
module "ecs_ec2_docker" {
  source = "./modules/ecs-ec2-docker"

  name_prefix        = local.name_prefix
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_app_subnet_ids
  ecs_cluster_name   = module.ecs.cluster_name
  instance_type      = "t3.medium"     # 2 vCPU, 4GB — fits 2-3 Docker workspaces
  max_instances      = 3               # Scale limit
  tags               = var.tags
}
```

### Coder Template Integration

The Docker-enabled Coder template specifies the EC2 capacity provider:

```hcl
# In Coder template (docker-workspace)
resource "aws_ecs_task_definition" "workspace" {
  # ... standard workspace config ...
  requires_compatibilities = ["EC2"]
}

resource "aws_ecs_service" "workspace" {
  capacity_provider_strategy {
    capacity_provider = "EC2_DOCKER"
    weight            = 1
    base              = 1
  }
  # ... rest of service config ...
}
```

### Cost Estimate

| Scenario | Monthly Cost (EC2 portion only) |
|----------|---------------------------------|
| No Docker users | $0 (ASG at zero) |
| 1 user, 8hr/day, 22 days | ~$8 (t3.medium on-demand) |
| 5 users, 8hr/day, 22 days | ~$24 (2 t3.medium shared) |
| 10 users, full-time | ~$73 (3 t3.medium) |

Fargate workspace costs are separate and unchanged. EC2 is only for the Docker capacity provider.

### Migration Path: PoC → Production

```
PoC (Docker Compose on local host):
  Option C: Rootless DinD sidecar per workspace
  └── DOCKER_HOST=tcp://dind-ws1:2375

Production (ECS Mixed Cluster):
  EC2 capacity provider + rootless DinD sidecar task
  └── Same pattern, different orchestrator
  └── Scale-to-zero when no Docker workspaces
```

The developer experience is identical — `docker compose up` works the same way. The only difference is the orchestration layer underneath.

---

## 17. Access Control: Docker Workspace Authorization

Coder OSS (Community Edition) does not have template ACLs. All members can see and create all templates. To restrict Docker-enabled templates to approved users, the platform implements **layered authorization**.

### Authorization Layers

```
Layer 1: Authentik Group ── "docker-users" group in identity provider
   │
Layer 2: Terraform Precondition ── Template checks coder_workspace_owner.me.groups
   │                                 Blocks workspace creation if not in group
   │
Layer 3: ECS Init Container ── Calls auth service before task starts (production only)
                                 Defense-in-depth: catches any bypass of Layer 2
```

| Layer | Where | Enforcement | Environment |
|-------|-------|-------------|-------------|
| **1. Identity Group** | Authentik (PoC) / Azure AD (Prod) | Group membership | Both |
| **2. Terraform Precondition** | Coder template (`main.tf`) | Fail workspace creation | Both |
| **3. ECS Init Container** | ECS task definition | Fail task before workspace starts | Production only |

### Layer 1: Identity Provider Group

Create a `docker-users` group in the identity provider. Only users in this group can create Docker-enabled workspaces.

**Authentik (PoC):**

1. Authentik Admin → Directory → Groups → Create Group
2. Name: `docker-users`
3. Add approved users as members
4. The group is included in the OIDC `groups` claim (already configured via `CODER_OIDC_GROUP_FIELD=groups`)

**Azure AD (Production):**

1. Azure AD → Groups → New Group
2. Name: `docker-users`, Type: Security
3. Add approved users as members
4. Ensure the group claim is included in the OIDC token

### Layer 2: Terraform Precondition

The docker-workspace template checks `data.coder_workspace_owner.me.groups`:

```hcl
locals {
  docker_authorized = contains(data.coder_workspace_owner.me.groups, "docker-users")
}

resource "null_resource" "docker_access_check" {
  count = local.docker_authorized ? 0 : 1

  lifecycle {
    precondition {
      condition     = local.docker_authorized
      error_message = <<-EOT
        ACCESS DENIED: Docker workspace requires "docker-users" group membership.
        Your groups: ${jsonencode(data.coder_workspace_owner.me.groups)}
      EOT
    }
  }
}
```

When an unauthorized user tries to create a Docker workspace, Terraform fails immediately with a clear error showing their current groups and instructions to request access.

### Layer 3: ECS Init Container (Production)

The production ECS task definition includes an `auth-check` init container that runs before the workspace and DinD sidecar start:

```
ECS Task:
  1. auth-check (essential=false)  ← Must exit 0 before others start
     └── Calls key-provisioner /api/v1/authorize/docker-workspace
     └── Checks if user is in "docker-users" group
     └── Exit 0 = proceed, Exit 1 = task fails

  2. dind (essential=true, dependsOn: auth-check=SUCCESS)
     └── Rootless Docker daemon

  3. dev (essential=true, dependsOn: auth-check=SUCCESS, dind=START)
     └── Workspace with Docker CLI
```

**Fail-closed design:** If the authorization service is unreachable, the init container exits 1 (denied). This prevents workspaces from starting if the auth service is down.

### Files

| File | Purpose |
|------|---------|
| `coder-poc/templates/docker-workspace/main.tf` | PoC template with Layer 2 precondition |
| `aws-production/templates/docker-workspace/main.tf` | Production template with Layer 2 + Layer 3 |
| `aws-production/templates/docker-workspace/build/auth-check.sh` | Init container authorization script |
| `aws-production/templates/docker-workspace/build/Dockerfile.auth-check` | Init container image |

---

## 18. Testing & Validation

### Test Scripts

| Script | Location | What It Tests |
|--------|----------|---------------|
| `test-docker-workspace.sh` | `coder-poc/scripts/` | PoC: DinD sidecar, isolation, workspace integration |
| `test-docker-auth.sh` | `aws-production/scripts/` | Production: auth init container (fail-closed, env vars, live auth) |

```bash
# Run PoC tests
./coder-poc/scripts/test-docker-workspace.sh

# Run production auth tests (requires auth-check image)
./aws-production/scripts/test-docker-auth.sh
```

### PoC: Test Authorization (Layer 2)

```bash
# 1. Build the docker-workspace image
cd coder-poc/templates/docker-workspace
docker build -t docker-workspace:latest ./build

# 2. Push the template to Coder
coder templates push docker-workspace --directory .

# 3. Test AUTHORIZED user (must be in "docker-users" group)
#    - Log in as a user who IS in the "docker-users" Authentik group
#    - Create workspace → should succeed
coder create my-docker-ws --template docker-workspace

# 4. Test UNAUTHORIZED user
#    - Log in as a user NOT in the "docker-users" group
#    - Create workspace → should fail with ACCESS DENIED
coder create my-docker-ws --template docker-workspace
# Expected: Error: ACCESS DENIED: Docker workspace requires "docker-users" group membership.

# 5. Test Docker functionality in authorized workspace
coder ssh my-docker-ws
docker version          # Should show client + server versions
docker compose version  # Should show Compose plugin version
docker run hello-world  # Should pull and run successfully
docker ps               # Should only show user's containers
```

### PoC: Test DinD Sidecar Isolation

```bash
# Inside the Docker workspace:

# 1. Verify DOCKER_HOST points to sidecar
echo $DOCKER_HOST
# Expected: tcp://dind-{owner}-{workspace}:2375

# 2. Verify isolation — workspace cannot see host containers
docker ps -a
# Expected: Only user's containers (not coder-server, gitea, etc.)

# 3. Test docker compose workflow
mkdir -p ~/workspace/test-app && cd ~/workspace/test-app
cat > docker-compose.yml << 'EOF'
services:
  web:
    image: nginx:alpine
    ports:
      - "8080:80"
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: testpass
EOF

docker compose up -d
docker compose ps     # Should show web + db running
docker compose down   # Should clean up
```

### Production: Test Init Container (Layer 3)

```bash
# 1. Build auth-check image
cd aws-production/templates/docker-workspace/build
docker build -f Dockerfile.auth-check -t auth-check:latest .

# 2. Test authorized user (mock)
docker run --rm \
  -e WORKSPACE_OWNER=authorized-user \
  -e WORKSPACE_NAME=test-ws \
  -e AUTH_SERVICE_URL=http://localhost:8100 \
  -e PROVISIONER_SECRET=test-secret \
  auth-check:latest
# Expected: exit 0, "[auth-check] AUTHORIZED: ..."

# 3. Test unauthorized user (mock)
docker run --rm \
  -e WORKSPACE_OWNER=unauthorized-user \
  -e WORKSPACE_NAME=test-ws \
  -e AUTH_SERVICE_URL=http://localhost:8100 \
  -e PROVISIONER_SECRET=test-secret \
  auth-check:latest
# Expected: exit 1, "[auth-check] DENIED: ..."

# 4. Test fail-closed (unreachable service)
docker run --rm \
  -e WORKSPACE_OWNER=anyone \
  -e WORKSPACE_NAME=test-ws \
  -e AUTH_SERVICE_URL=http://unreachable:9999 \
  -e PROVISIONER_SECRET=test-secret \
  auth-check:latest
# Expected: exit 1, "[auth-check] ERROR: Authorization service unreachable"
```

### Production: Test Terraform Validation

```bash
# Terraform plan will show the precondition check
cd aws-production/templates/docker-workspace
terraform plan
# For unauthorized user: Error in precondition — ACCESS DENIED
# For authorized user: Plan shows 3-container ECS task definition

# Validate Terraform syntax
terraform validate
```

### Validation Checklist

| Test | PoC | Production | Pass Criteria |
|------|:---:|:---:|---|
| Unauthorized user blocked at template | ✓ | ✓ | Terraform fails with ACCESS DENIED message |
| Authorized user can create workspace | ✓ | ✓ | Workspace provisions successfully |
| Docker CLI available in workspace | ✓ | ✓ | `docker version` shows client + server |
| Docker Compose works | ✓ | ✓ | `docker compose up` starts multi-container app |
| Workspace isolation | ✓ | ✓ | `docker ps` shows only user's containers |
| Init container blocks unauthorized (prod) | — | ✓ | ECS task fails before workspace starts |
| Init container fail-closed (prod) | — | ✓ | Task fails when auth service unreachable |
| DinD sidecar persistence | ✓ | ✓ | Images survive workspace restart |
| Group change takes effect after re-login | ✓ | ✓ | Adding user to group + re-login → access granted |
