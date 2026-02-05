# Infrastructure Architecture - Dev Platform PoC

This document describes the infrastructure architecture, components, and deployment details for the Coder WebIDE Development Platform.

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Component Inventory](#2-component-inventory)
3. [Network Architecture](#3-network-architecture)
4. [Storage Architecture](#4-storage-architecture)
5. [Container Architecture](#5-container-architecture)
6. [Workspace Architecture](#6-workspace-architecture)
7. [Integration Points](#7-integration-points)
8. [Scaling Considerations](#8-scaling-considerations)
9. [Disaster Recovery](#9-disaster-recovery)
10. [Operations Guide](#10-operations-guide)

---

## 1. Architecture Overview

### 1.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           USER ACCESS LAYER                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   Browser   │  │  VS Code    │  │    CLI      │  │   Mobile    │        │
│  │  (Web IDE)  │  │  (Disabled) │  │  (Limited)  │  │  (Future)   │        │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘        │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           APPLICATION LAYER                                  │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         CODER SERVER (7080)                          │   │
│  │  • Workspace provisioning    • User management                       │   │
│  │  • Template management       • Session management                    │   │
│  │  • AI Bridge (Bedrock)       • Audit logging                        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │  Authentik   │  │    Gitea      │  │   Drone CI   │  │   LiteLLM    │   │
│  │    (9000)    │  │   (3000)     │  │    (8080)    │  │    (4000)    │   │
│  │  Identity    │  │  Git Server  │  │   CI/CD      │  │  AI Proxy    │   │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            DATA LAYER                                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │  PostgreSQL  │  │    Redis     │  │    MinIO     │  │   Mailpit    │   │
│  │  (internal)  │  │  (internal)  │  │  (9001/02)   │  │    (8025)    │   │
│  │  • coder     │  │  • sessions  │  │  • artifacts │  │  • email     │   │
│  │  • authentik │  │  • cache     │  │  • storage   │  │    testing   │   │
│  │  • platform  │  │              │  │              │  │              │   │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          WORKSPACE LAYER                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    DOCKER HOST / KUBERNETES                          │   │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐        │   │
│  │  │Workspace 1│  │Workspace 2│  │Workspace 3│  │Workspace N│        │   │
│  │  │ User: A   │  │ User: B   │  │ User: C   │  │ User: N   │        │   │
│  │  │ code-srv  │  │ code-srv  │  │ code-srv  │  │ code-srv  │        │   │
│  │  │ agent     │  │ agent     │  │ agent     │  │ agent     │        │   │
│  │  └───────────┘  └───────────┘  └───────────┘  └───────────┘        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Technology Stack

| Layer | Technology | Version |
|-------|------------|---------|
| Container Runtime | Docker | Latest |
| Orchestration | Docker Compose | 3.9 |
| WebIDE Platform | Coder | Latest |
| Database | PostgreSQL | 17 |
| Cache | Redis | 7 |
| Git Server | Gitea | Latest |
| CI/CD | Drone | 2.x |
| Identity | Authentik | 2024.2 |
| Object Storage | MinIO | Latest |
| Email Testing | Mailpit | Latest |
| LiteLLM | LiteLLM | Latest |

---

## 2. Component Inventory

### 2.1 Core Services

| Service | Container | Port(s) | Purpose | Dependencies |
|---------|-----------|---------|---------|--------------|
| coder | coder-server | 7080 | WebIDE platform | postgres |
| postgres | postgres | 5432 (internal) | Primary database | - |
| gitea | gitea | 3000, 10022 | Git server | - |
| drone-server | drone-server | 8080 | CI server | gitea |
| drone-runner | drone-runner | - | CI runner | drone-server |
| litellm | litellm | 4000 | AI API proxy (LiteLLM) | postgres |

### 2.2 Supporting Services

| Service | Container | Port(s) | Purpose | Dependencies |
|---------|-----------|---------|---------|--------------|
| authentik-server | authentik-server | 9000, 9443 | Identity provider | postgres, redis |
| authentik-worker | authentik-worker | - | Background jobs | postgres, redis |
| authentik-redis | authentik-redis | 6379 (internal) | Session cache | - |
| minio | minio | 9001, 9002 | Object storage | - |
| mailpit | mailpit | 8025, 1025 | Email testing | - |
| testdb | testdb | 5432 (internal) | Test database | - |
| devdb | devdb | 5432 (internal) | Developer databases | - |
| platform-admin | platform-admin | 5050 | Admin dashboard | devdb |

### 2.3 Resource Requirements

| Service | CPU | Memory | Disk |
|---------|-----|--------|------|
| coder | 0.5-2 cores | 512MB-2GB | 1GB |
| postgres | 0.5-1 core | 256MB-1GB | 10GB+ |
| gitea | 0.25-0.5 core | 256MB-512MB | 5GB+ |
| drone-server | 0.25 core | 256MB | 1GB |
| litellm | 0.25 core | 256MB | 100MB |
| authentik-server | 0.5 core | 512MB | 500MB |
| minio | 0.25 core | 512MB | 50GB+ |
| **Per Workspace** | 2-4 cores | 4-8GB | 10-50GB |

### 2.4 Container Images

```yaml
# Image registry sources
images:
  coder: ghcr.io/coder/coder:latest
  postgres: postgres:17-alpine
  gitea: gitea/gitea:latest
  drone: drone/drone:2
  drone-runner: drone/drone-runner-docker:1
  authentik: ghcr.io/goauthentik/server:2024.2
  redis: redis:7-alpine
  minio: minio/minio:latest
  mailpit: axllent/mailpit:latest
  litellm: ghcr.io/berriai/litellm:main-latest
  workspace: contractor-workspace (local build)
```

---

## 3. Network Architecture

### 3.1 Network Topology

```
┌─────────────────────────────────────────────────────────────────────┐
│                        HOST NETWORK                                  │
│  Ports: 7080, 3000, 4000, 8080, 9000, 9001, 9002, 8025              │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              │ Bridge
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                   coder-network (172.18.0.0/16)                      │
│                                                                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │
│  │ coder-server│  │    gitea     │  │   litellm   │                 │
│  │ 172.18.0.x  │  │ 172.18.0.x  │  │ 172.18.0.x  │                 │
│  └─────────────┘  └─────────────┘  └─────────────┘                 │
│                                                                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │
│  │  postgres   │  │   redis     │  │   minio     │                 │
│  │ 172.18.0.x  │  │ 172.18.0.x  │  │ 172.18.0.x  │                 │
│  └─────────────┘  └─────────────┘  └─────────────┘                 │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    WORKSPACE CONTAINERS                       │  │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐         │  │
│  │  │  ws-1   │  │  ws-2   │  │  ws-3   │  │  ws-n   │         │  │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘         │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### 3.2 Service Discovery

| Service | Internal DNS | Port |
|---------|--------------|------|
| PostgreSQL | postgres | 5432 |
| Redis | authentik-redis | 6379 |
| Gitea | gitea | 3000 |
| LiteLLM | litellm | 4000 |
| MinIO | minio | 9002 |
| Mailpit SMTP | mailpit | 1025 |
| TestDB | testdb | 5432 |

### 3.3 External Access URLs

| Service | Development URL | Production URL |
|---------|-----------------|----------------|
| Coder | http://localhost:7080 | https://coder.company.com |
| Gitea | http://localhost:3000 | https://git.company.com |
| Drone | http://localhost:8080 | https://ci.company.com |
| Authentik | http://localhost:9000 | https://auth.company.com |
| MinIO | http://localhost:9001 | https://storage.company.com |
| Mailpit | http://localhost:8025 | (dev only) |

---

## 4. Storage Architecture

### 4.1 Volume Mapping

| Volume | Container | Mount Point | Purpose |
|--------|-----------|-------------|---------|
| coder-poc-postgres | postgres | /var/lib/postgresql/data | Database storage |
| coder-poc-data | coder-server | /home/coder/.config/coderv2 | Coder state |
| coder-poc-gitea | gitea | /data | Git repositories |
| coder-poc-drone | drone-server | /data | CI data |
| coder-poc-minio | minio | /data | Object storage |
| coder-poc-authentik-* | authentik-* | /media, /templates | Identity data |
| coder-poc-testdb | testdb | /var/lib/postgresql/data | Test database |
| coder-poc-devdb | devdb | /var/lib/postgresql/data | Developer databases |
| coder-poc-litellm-logs | litellm | /var/log/litellm | LiteLLM logs |

### 4.2 Workspace Storage

```
┌─────────────────────────────────────────────────────────────────────┐
│                     WORKSPACE VOLUME STRUCTURE                       │
│                                                                      │
│  coder-{owner}-{workspace}-data                                     │
│  └── /home/coder/                                                   │
│      ├── workspace/        ← Project files (persistent)             │
│      ├── .config/          ← User configuration                     │
│      ├── .config/roo-code/  ← AI agent config (Roo Code)            │
│      ├── .local/           ← VS Code extensions/data                │
│      └── .bashrc           ← Shell configuration                    │
└─────────────────────────────────────────────────────────────────────┘
```

### 4.3 Backup Strategy

| Data | Frequency | Retention | Method |
|------|-----------|-----------|--------|
| PostgreSQL | Daily | 30 days | pg_dump to MinIO |
| Git repos | Real-time | Permanent | Git mirroring |
| Workspace volumes | On-demand | Per policy | Volume snapshot |
| Coder state | Daily | 7 days | Volume backup |

```bash
# Backup commands
# PostgreSQL
docker exec postgres pg_dumpall -U postgres | gzip > backup-$(date +%Y%m%d).sql.gz

# Volumes
docker run --rm -v coder-poc-postgres:/source:ro -v $(pwd):/backup \
  alpine tar czf /backup/postgres-vol-$(date +%Y%m%d).tar.gz -C /source .
```

---

## 5. Container Architecture

### 5.1 Container Lifecycle

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│ Created  │───>│ Running  │───>│ Stopped  │───>│ Removed  │
└──────────┘    └──────────┘    └──────────┘    └──────────┘
     │               │               │
     │               ▼               │
     │         ┌──────────┐         │
     └────────>│ Restarted│<────────┘
               └──────────┘
```

### 5.2 Restart Policies

| Service | Policy | Reason |
|---------|--------|--------|
| postgres | unless-stopped | Critical data service |
| coder | unless-stopped | Core platform |
| gitea | unless-stopped | Git availability |
| drone-* | unless-stopped | CI availability |
| litellm | unless-stopped | AI service |
| authentik-* | unless-stopped | Auth availability |
| minio | unless-stopped | Storage availability |
| mailpit | unless-stopped | Dev convenience |
| workspaces | unless-stopped | User convenience |

### 5.3 Health Checks

| Service | Check Type | Interval | Timeout | Retries |
|---------|------------|----------|---------|---------|
| postgres | pg_isready | 5s | 5s | 5 |
| coder | - | - | - | - |
| gitea | HTTP GET / | 10s | 5s | 5 |
| litellm | HTTP GET /health | 30s | 10s | 3 |
| authentik | HTTP GET /-/health/ready/ | 30s | 10s | 5 |
| minio | HTTP GET /minio/health/live | 10s | 5s | 5 |
| mailpit | HTTP GET / | 10s | 5s | 3 |
| redis | redis-cli ping | 5s | 5s | 5 |

### 5.4 Container Dependencies

```yaml
# Startup order
1. postgres, redis       # Data layer first
2. authentik-*          # Identity (depends on postgres, redis)
3. gitea                 # Git server
4. coder                # Platform (depends on postgres)
5. drone-server         # CI (depends on gitea)
6. drone-runner         # CI runner (depends on drone-server)
7. litellm, minio       # Supporting services
8. mailpit              # Dev tools
```

---

## 6. Workspace Architecture

### 6.1 Workspace Container Structure

```
┌─────────────────────────────────────────────────────────────────────┐
│                      WORKSPACE CONTAINER                             │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                     BASE IMAGE (Ubuntu 22.04)                │   │
│  │  • Node.js 20 LTS    • Python 3.11    • Go 1.22             │   │
│  │  • Java 21           • .NET 8         • Docker CLI          │   │
│  │  • Git, vim, curl    • PostgreSQL/MySQL clients             │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                              │                                       │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                      CODE-SERVER                             │   │
│  │  • VS Code in browser (port 8080)                           │   │
│  │  • Pre-installed extensions:                                 │   │
│  │    - Python, ESLint, Prettier, GitLens, Go                  │   │
│  │    - SQLTools, Java, C#, Roo Code                           │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                              │                                       │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                      CODER AGENT                             │   │
│  │  • Workspace lifecycle management                           │   │
│  │  • Metrics collection (CPU, memory, disk)                   │   │
│  │  • App proxying (code-server, terminal)                     │   │
│  │  • Startup/shutdown scripts                                 │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  User: coder (UID 1000) │ Workdir: /home/coder/workspace           │
└─────────────────────────────────────────────────────────────────────┘
```

### 6.2 Workspace Parameters

| Parameter | Options | Default | Impact |
|-----------|---------|---------|--------|
| cpu_cores | 2, 4 | 2 | Container CPU shares |
| memory_gb | 4, 8 | 4 | Container memory limit |
| disk_size | 10, 20, 50 | 10 | Volume size (GB) |
| ai_provider | bedrock, anthropic | bedrock | AI configuration |
| ai_model | sonnet, haiku, opus | sonnet | Model selection |
| aws_region | us-east-1, etc. | us-east-1 | Bedrock region |

### 6.3 Workspace Network Access

| Destination | Access | Purpose |
|-------------|--------|---------|
| gitea:3000 | ✓ Allowed | Git operations |
| litellm:4000 | ✓ Allowed | AI API access |
| testdb:5432 | ✓ Allowed | Database testing |
| minio:9002 | ✓ Allowed | Object storage |
| mailpit:1025 | ✓ Allowed | Email testing |
| Internet | ✗ Blocked* | Security |

*Can be configured per deployment requirements

---

## 7. Integration Points

### 7.1 Integration Architecture

```
┌───────────────────────────────────────────────────────────────────────────┐
│                          EXTERNAL INTEGRATIONS                             │
│                                                                            │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                   │
│  │  Azure AD   │    │ AWS Bedrock │    │  External   │                   │
│  │ (Optional)  │    │             │    │   APIs      │                   │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘                   │
│         │                  │                  │                           │
└─────────┼──────────────────┼──────────────────┼───────────────────────────┘
          │                  │                  │
          ▼                  ▼                  ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│    Authentik    │  │    LiteLLM      │  │     LiteLLM     │
│   OIDC/SAML     │  │   /v1/bedrock   │  │   /v1/external  │
└────────┬────────┘  └────────┬────────┘  └────────┬────────┘
         │                    │                    │
         └────────────────────┼────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │      CODER      │
                    │     SERVER      │
                    └─────────────────┘
```

### 7.2 Git Integration (Gitea)

```yaml
# Workspace git configuration
GIT_SERVER_URL: http://gitea:3000
GIT_AUTHOR_NAME: ${workspace_owner}
GIT_AUTHOR_EMAIL: ${workspace_owner_email}

# Credential flow
Workspace → Git Credential Store → Gitea API
```

### 7.3 CI/CD Integration (Drone)

```yaml
# Integration flow
Gitea Push → Webhook → Drone Server → Drone Runner → Build Container

# Drone configuration
DRONE_GITEA_SERVER: http://gitea:3000
DRONE_RPC_SECRET: ${shared_secret}
```

### 7.4 AI Integration

```yaml
# Coder AI Bridge (built-in chat)
CODER_AIBRIDGE_BEDROCK_ACCESS_KEY: ${AWS_ACCESS_KEY_ID}
CODER_AIBRIDGE_BEDROCK_ACCESS_KEY_SECRET: ${AWS_SECRET_ACCESS_KEY}
CODER_AIBRIDGE_BEDROCK_REGION: us-east-1

# Workspace AI (Roo Code extension)
AI_GATEWAY_URL: http://litellm:4000
AI_PROVIDER: bedrock
AI_MODEL: claude-sonnet
```

---

## 8. Scaling Considerations

### 8.1 Current Capacity (Single Host)

| Resource | Capacity | Limiting Factor |
|----------|----------|-----------------|
| Concurrent workspaces | 10-20 | Host CPU/memory |
| Users | 50-100 | Database connections |
| Git repos | Unlimited | Disk space |
| AI requests | 60/min | Rate limiting |

### 8.2 Scaling Options

#### Vertical Scaling
```
┌─────────────────────────────────────────┐
│            SINGLE HOST                   │
│  CPU: 8→16→32 cores                     │
│  RAM: 32→64→128 GB                      │
│  Disk: 500GB→1TB SSD                    │
│  Workspaces: 20→40→80                   │
└─────────────────────────────────────────┘
```

#### Horizontal Scaling (Kubernetes)
```
┌─────────────────────────────────────────────────────────────────────┐
│                     KUBERNETES CLUSTER                               │
│                                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │   Node 1     │  │   Node 2     │  │   Node 3     │              │
│  │  Workspaces  │  │  Workspaces  │  │  Workspaces  │              │
│  │   1-20       │  │   21-40      │  │   41-60      │              │
│  └──────────────┘  └──────────────┘  └──────────────┘              │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │              SHARED SERVICES (StatefulSet)                    │  │
│  │  PostgreSQL (HA) │ Redis Cluster │ MinIO Distributed         │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### 8.3 Scaling Thresholds

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| CPU usage | >70% | >90% | Scale up |
| Memory usage | >75% | >90% | Scale up |
| Disk usage | >70% | >85% | Expand/cleanup |
| DB connections | >80% | >95% | Pool tuning |
| Response time | >2s | >5s | Investigate |

---

## 9. Disaster Recovery

### 9.1 Recovery Point Objectives (RPO)

| Data | RPO | Backup Method |
|------|-----|---------------|
| User data | 24 hours | Daily backup |
| Git repos | 0 (real-time) | Continuous |
| Workspace state | 24 hours | Daily snapshot |
| Configuration | 0 | Version controlled |

### 9.2 Recovery Time Objectives (RTO)

| Scenario | RTO | Procedure |
|----------|-----|-----------|
| Service restart | <5 min | docker compose restart |
| Container failure | <5 min | Auto-restart |
| Host failure | <1 hour | Restore from backup |
| Data corruption | <4 hours | Point-in-time recovery |

### 9.3 Backup Procedures

```bash
#!/bin/bash
# Full platform backup

# 1. Database backup
docker exec postgres pg_dumpall -U postgres | \
  gzip > backups/postgres-$(date +%Y%m%d).sql.gz

# 2. Volume backups
for vol in postgres gitea drone minio coder-data; do
  docker run --rm \
    -v coder-poc-${vol}:/source:ro \
    -v $(pwd)/backups:/backup \
    alpine tar czf /backup/${vol}-$(date +%Y%m%d).tar.gz -C /source .
done

# 3. Configuration backup
tar czf backups/config-$(date +%Y%m%d).tar.gz \
  docker-compose.yml .env templates/ gitea/ litellm/

# 4. Upload to remote storage
mc cp backups/* remote/platform-backups/
```

### 9.4 Recovery Procedures

```bash
#!/bin/bash
# Platform recovery from backup

# 1. Stop services
docker compose down

# 2. Restore volumes
for vol in postgres gitea drone minio coder-data; do
  docker volume create coder-poc-${vol}
  docker run --rm \
    -v coder-poc-${vol}:/target \
    -v $(pwd)/backups:/backup \
    alpine tar xzf /backup/${vol}-YYYYMMDD.tar.gz -C /target
done

# 3. Restore database
docker compose up -d postgres
sleep 10
gunzip -c backups/postgres-YYYYMMDD.sql.gz | \
  docker exec -i postgres psql -U postgres

# 4. Start services
docker compose up -d
```

---

## 10. Operations Guide

### 10.1 Daily Operations

```bash
# Health check
./scripts/validate.sh

# View logs
docker compose logs -f --tail=100

# Check disk usage
docker system df
df -h

# Database status
docker exec postgres psql -U postgres -c "SELECT pg_database_size('coder');"
```

### 10.2 Common Operations

| Task | Command |
|------|---------|
| Start platform | `docker compose up -d` |
| Stop platform | `docker compose down` |
| Restart service | `docker compose restart <service>` |
| View logs | `docker compose logs <service>` |
| Update images | `docker compose pull && docker compose up -d` |
| Cleanup | `./scripts/cleanup.sh` |

### 10.3 Troubleshooting

| Issue | Diagnosis | Resolution |
|-------|-----------|------------|
| Service won't start | `docker compose logs <svc>` | Check dependencies, config |
| Workspace stuck | `coder workspaces list` | Force stop/delete |
| Database full | `docker exec postgres psql...` | Cleanup, expand volume |
| High CPU | `docker stats` | Identify container, scale |
| Network issues | `docker network inspect` | Check DNS, connectivity |

### 10.4 Maintenance Windows

| Task | Frequency | Duration | Impact |
|------|-----------|----------|--------|
| Security updates | Weekly | 15 min | Brief restart |
| Database vacuum | Weekly | 5 min | None |
| Log rotation | Daily | None | None |
| Full backup | Daily | 30 min | None |
| Major upgrade | Quarterly | 2 hours | Full outage |

---

## Appendix A: File Structure

```
coder-poc/
├── docker-compose.yml          # Main infrastructure definition
├── .env                        # Environment variables (gitignored)
├── CLAUDE.md                   # Project instructions
├── README.md                   # User documentation
│
├── docs/
│   ├── SECURITY.md            # Security documentation
│   ├── INFRA.md               # This document
│   └── testing-validation.md   # Test procedures
│
├── templates/
│   └── contractor-workspace/
│       ├── main.tf            # Terraform template
│       └── build/
│           ├── Dockerfile     # Workspace image
│           └── settings.json  # VS Code settings
│
├── scripts/
│   ├── setup.sh               # Initial setup
│   ├── setup-gitea.sh          # Git server setup
│   ├── setup-workspace.sh     # Coder setup
│   ├── setup-coder-users.sh   # User creation guide
│   ├── validate.sh            # Infrastructure validation
│   ├── validate-security.sh   # Security validation
│   ├── test-access-control.sh # Access tests
│   └── cleanup.sh             # Cleanup script
│
├── gitea/
│   ├── app.ini                # Gitea configuration
│   └── issue-templates/       # Issue templates
│
├── litellm/
│   └── config.yaml            # LiteLLM proxy config
│
├── postgres/
│   └── init.sql               # Database initialization
│
├── testdb/
│   └── init.sql               # Test database init
│
└── devdb/
    ├── init.sql               # Developer database init
    └── pg_hba.conf            # PostgreSQL auth config
```

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-04 | Platform Team | Initial version |
