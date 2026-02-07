# Production Deployment Guide - Dev Platform

This document provides guidance for deploying the Coder WebIDE Development Platform in a production environment.

## Table of Contents

1. [Production Readiness Assessment](#1-production-readiness-assessment)
2. [Infrastructure Requirements](#2-infrastructure-requirements)
3. [Security Enhancements](#3-security-enhancements)
4. [High Availability Architecture](#4-high-availability-architecture)
5. [Deployment Options](#5-deployment-options)
6. [Configuration Changes](#6-configuration-changes)
7. [Monitoring & Observability](#7-monitoring--observability)
8. [Operational Procedures](#8-operational-procedures)
9. [Migration Checklist](#9-migration-checklist)
10. [Cost Estimation](#10-cost-estimation)

---

## 1. Production Readiness Assessment

**Related Document:** See [PRODUCTION-PLAN.md](../../aws-production/PRODUCTION-PLAN.md) for the detailed implementation plan addressing security issues from the PoC review.

### 1.1 Current PoC vs Production

| Aspect | PoC (Current) | Production (Required) |
|--------|---------------|----------------------|
| **TLS/HTTPS** | Self-signed TLS (port 7443) | CA-signed TLS 1.2+ |
| **Authentication** | Local auth + OIDC (Authentik) | SSO/OIDC + MFA |
| **Database** | Single instance (PostgreSQL 17) | HA cluster or managed |
| **Secrets** | .env file | Vault/Secrets Manager |
| **Backups** | Manual | Automated, tested |
| **Monitoring** | Docker logs | Centralized + alerting |
| **Scaling** | Single host | Auto-scaling capable |
| **DR** | None | Documented, tested |
| **SLA** | None | 99.9%+ target |

**Note:** The PoC already includes Authentik for OIDC/SSO. MFA can be enabled in Authentik configuration.

### 1.2 Gap Analysis

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         PRODUCTION READINESS GAP                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  CRITICAL (Must Fix)           HIGH (Should Fix)        MEDIUM (Nice to Have)│
│  ─────────────────────         ─────────────────        ────────────────────│
│  □ Enable TLS/HTTPS            □ HA database            □ CDN for static    │
│  □ Change default passwords    □ Auto-scaling           □ Blue-green deploy │
│  □ Enable MFA                  □ Log aggregation        □ Chaos testing     │
│  □ Secrets management          □ Metrics/alerting       □ Cost optimization │
│  □ Backup automation           □ WAF/DDoS protection    □ Multi-region      │
│  □ Network segmentation        □ Vulnerability scanning                     │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Infrastructure Requirements

### 2.1 Compute Requirements

#### Minimum Production Setup (50 users, 20 concurrent workspaces)

| Component | Instance Type (AWS) | vCPU | Memory | Storage |
|-----------|---------------------|------|--------|---------|
| Coder Server | t3.large | 2 | 8 GB | 50 GB SSD |
| PostgreSQL | db.t3.medium (RDS) | 2 | 4 GB | 100 GB |
| Redis | cache.t3.small | 1 | 1.5 GB | - |
| Workspace Nodes | t3.xlarge x 2 | 4 | 16 GB | 200 GB each |
| Load Balancer | ALB | - | - | - |

#### Recommended Production Setup (200 users, 50 concurrent workspaces)

| Component | Instance Type (AWS) | vCPU | Memory | Storage |
|-----------|---------------------|------|--------|---------|
| Coder Server (HA) | t3.xlarge x 2 | 4 | 16 GB | 100 GB |
| PostgreSQL | db.r5.large (RDS Multi-AZ) | 2 | 16 GB | 500 GB |
| Redis | cache.r5.large (Cluster) | 2 | 13 GB | - |
| Workspace Nodes | c5.2xlarge x 4 | 8 | 16 GB | 500 GB each |
| Load Balancer | ALB | - | - | - |
| WAF | AWS WAF | - | - | - |

### 2.2 Network Requirements

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         PRODUCTION NETWORK ARCHITECTURE                      │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                              INTERNET                                │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                              ┌─────┴─────┐                                 │
│                              │    WAF    │                                 │
│                              │  + DDoS   │                                 │
│                              └─────┬─────┘                                 │
│                                    │                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         PUBLIC SUBNET                                │   │
│  │  ┌─────────────────┐    ┌─────────────────┐                         │   │
│  │  │  Load Balancer  │    │   Bastion Host  │                         │   │
│  │  │  (ALB/NLB)      │    │   (SSH Jump)    │                         │   │
│  │  └────────┬────────┘    └─────────────────┘                         │   │
│  └───────────┼─────────────────────────────────────────────────────────┘   │
│              │                                                              │
│  ┌───────────┼─────────────────────────────────────────────────────────┐   │
│  │           │              PRIVATE SUBNET (App)                        │   │
│  │  ┌────────┴────────┐    ┌─────────────────┐    ┌─────────────────┐  │   │
│  │  │  Coder Server   │    │  Coder Server   │    │   AI Gateway    │  │   │
│  │  │   (Primary)     │    │   (Secondary)   │    │                 │  │   │
│  │  └─────────────────┘    └─────────────────┘    └─────────────────┘  │   │
│  │                                                                      │   │
│  │  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐  │   │
│  │  │      Gitea       │    │     Drone       │    │    Authentik    │  │   │
│  │  │   Git Server    │    │     CI/CD       │    │    Identity     │  │   │
│  │  └─────────────────┘    └─────────────────┘    └─────────────────┘  │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                       PRIVATE SUBNET (Data)                          │   │
│  │  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐  │   │
│  │  │   PostgreSQL    │    │     Redis       │    │     MinIO       │  │   │
│  │  │   (Multi-AZ)    │    │   (Cluster)     │    │  (Distributed)  │  │   │
│  │  └─────────────────┘    └─────────────────┘    └─────────────────┘  │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                      PRIVATE SUBNET (Workspaces)                     │   │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐        │   │
│  │  │ Worker 1  │  │ Worker 2  │  │ Worker 3  │  │ Worker N  │        │   │
│  │  │Workspaces │  │Workspaces │  │Workspaces │  │Workspaces │        │   │
│  │  └───────────┘  └───────────┘  └───────────┘  └───────────┘        │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.3 DNS & Domain Requirements

| Subdomain | Service | Purpose |
|-----------|---------|---------|
| coder.company.com | Coder | Main WebIDE access |
| *.coder.company.com | Workspace apps | Subdomain apps (wildcard) |
| git.company.com | Gitea | Git server |
| ci.company.com | Drone | CI/CD |
| auth.company.com | Authentik | Identity provider |
| storage.company.com | MinIO | Object storage (optional) |

---

## 3. Security Enhancements

**Related Document:** See [POC-SECURITY-REVIEW.md](POC-SECURITY-REVIEW.md) for the comprehensive security audit findings (68 issues identified, 2 already fixed).

### 3.1 TLS/HTTPS Configuration

```yaml
# Traefik configuration for TLS
# traefik/traefik.yml
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

certificatesResolvers:
  letsencrypt:
    acme:
      email: admin@company.com
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web

# Or use internal CA for private networks
tls:
  certificates:
    - certFile: /certs/company.crt
      keyFile: /certs/company.key
```

### 3.2 Secrets Management

#### HashiCorp Vault Integration

```yaml
# docker-compose.production.yml
services:
  vault:
    image: vault:latest
    cap_add:
      - IPC_LOCK
    environment:
      VAULT_ADDR: http://127.0.0.1:8200
    volumes:
      - vault_data:/vault/data
    command: server -config=/vault/config/config.hcl

  coder:
    environment:
      # Fetch secrets from Vault
      CODER_PG_CONNECTION_URL: vault:secret/data/coder/database#connection_string
      AWS_ACCESS_KEY_ID: vault:secret/data/aws#access_key
      AWS_SECRET_ACCESS_KEY: vault:secret/data/aws#secret_key
```

#### AWS Secrets Manager Alternative

```bash
# Fetch secrets at container startup
aws secretsmanager get-secret-value \
  --secret-id prod/coder/database \
  --query SecretString --output text
```

### 3.3 MFA Configuration

```yaml
# Authentik MFA policy
policies:
  - name: require-mfa
    kind: expression
    expression: |
      # Require MFA for all users
      return ak_is_mfa_configured(request.user)

flows:
  - name: default-authentication
    stages:
      - identification
      - password
      - mfa-validation  # Add MFA stage
```

### 3.4 Network Security

```yaml
# Security groups (AWS example)
security_groups:
  alb:
    ingress:
      - port: 443, cidr: 0.0.0.0/0      # HTTPS from anywhere
      - port: 80, cidr: 0.0.0.0/0       # HTTP redirect

  app:
    ingress:
      - port: 7080, source: alb         # From ALB only
      - port: 22, source: bastion       # SSH from bastion only

  database:
    ingress:
      - port: 5432, source: app         # From app tier only
      - port: 6379, source: app         # Redis from app tier

  workspace:
    ingress:
      - port: all, source: app          # From Coder server
    egress:
      - port: 5432, dest: database      # To databases
      - port: 3000, dest: app           # To Git server
      - port: 8090, dest: app           # To AI Gateway
```

### 3.5 Container Security

**Related Document:** See [SECURITY.md](SECURITY.md) for the complete security architecture and controls.

**Note:** The PoC now runs Coder as non-root (UID 1000) with Docker socket access via group membership. Production hardening adds additional controls:

```yaml
# Production container hardening
services:
  coder:
    user: "1000:1000"  # Already in PoC
    group_add:
      - ${DOCKER_GID:-1}  # Already in PoC
    security_opt:
      - no-new-privileges:true
      - seccomp:seccomp-profile.json
    read_only: true
    tmpfs:
      - /tmp:size=100M
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G
        reservations:
          cpus: '0.5'
          memory: 1G
```

---

## 4. High Availability Architecture

### 4.1 HA Components

| Component | HA Strategy | RPO | RTO |
|-----------|-------------|-----|-----|
| Coder Server | Active-Active behind LB | 0 | <1 min |
| PostgreSQL | Multi-AZ RDS / Patroni | <1 min | <5 min |
| Redis | Cluster mode | 0 | <1 min |
| Gitea | Active-Passive | <5 min | <15 min |
| MinIO | Distributed mode | 0 | <1 min |

### 4.2 Database HA

#### Option 1: AWS RDS Multi-AZ (Recommended)

```yaml
# Terraform example
resource "aws_db_instance" "coder" {
  identifier        = "coder-production"
  engine            = "postgres"
  engine_version    = "17"
  instance_class    = "db.r5.large"
  allocated_storage = 500

  multi_az               = true
  backup_retention_period = 30
  backup_window          = "03:00-04:00"

  vpc_security_group_ids = [aws_security_group.db.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  performance_insights_enabled = true
  monitoring_interval         = 60
}
```

#### Option 2: Patroni Cluster (Self-managed)

```yaml
# Patroni configuration
bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
  postgresql:
    use_pg_rewind: true
    parameters:
      max_connections: 200
      shared_buffers: 4GB
      wal_level: replica
      hot_standby: on
      max_wal_senders: 10
      max_replication_slots: 10
```

### 4.3 Session Persistence

```yaml
# Redis Cluster for sessions
services:
  redis:
    image: redis:7-alpine
    command: >
      redis-server
      --cluster-enabled yes
      --cluster-config-file nodes.conf
      --cluster-node-timeout 5000
      --appendonly yes
    deploy:
      replicas: 6  # 3 master + 3 replica
```

---

## 5. Deployment Options

### 5.1 Option A: Docker Compose (Small Scale)

**Best for:** <50 users, single region, simpler operations

```yaml
# docker-compose.production.yml
version: "3.9"

services:
  traefik:
    image: traefik:v2.10
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik:/etc/traefik
      - letsencrypt:/letsencrypt

  coder:
    image: ghcr.io/coder/coder:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.coder.rule=Host(`coder.company.com`)"
      - "traefik.http.routers.coder.tls.certresolver=letsencrypt"
    environment:
      CODER_ACCESS_URL: https://coder.company.com
      CODER_WILDCARD_ACCESS_URL: "*.coder.company.com"
      CODER_PG_CONNECTION_URL: ${DATABASE_URL}
      CODER_SECURE_AUTH_COOKIE: "true"
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G
```

### 5.2 Option B: Kubernetes (Recommended for Scale)

**Best for:** >50 users, multi-region, enterprise requirements

```yaml
# Helm values for Coder
# values-production.yaml
coder:
  replicaCount: 2

  image:
    repo: ghcr.io/coder/coder
    tag: latest

  service:
    type: ClusterIP

  ingress:
    enable: true
    className: nginx
    host: coder.company.com
    wildcardHost: "*.coder.company.com"
    tls:
      enable: true
      secretName: coder-tls

  env:
    - name: CODER_PG_CONNECTION_URL
      valueFrom:
        secretKeyRef:
          name: coder-secrets
          key: database-url
    - name: CODER_SECURE_AUTH_COOKIE
      value: "true"

  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 2000m
      memory: 4Gi

  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            topologyKey: kubernetes.io/hostname
```

```bash
# Deploy with Helm
helm repo add coder https://helm.coder.com/v2
helm upgrade --install coder coder/coder \
  -f values-production.yaml \
  -n coder --create-namespace
```

### 5.3 Option C: AWS ECS/Fargate

**Best for:** AWS-native, serverless compute for control plane

```yaml
# CloudFormation / Terraform
# ECS Task Definition
resource "aws_ecs_task_definition" "coder" {
  family                   = "coder"
  requires_compatibilities = ["FARGATE"]
  network_mode            = "awsvpc"
  cpu                     = 2048
  memory                  = 4096
  execution_role_arn      = aws_iam_role.ecs_execution.arn
  task_role_arn          = aws_iam_role.coder_task.arn

  container_definitions = jsonencode([
    {
      name  = "coder"
      image = "ghcr.io/coder/coder:latest"
      portMappings = [
        {
          containerPort = 7080
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "CODER_ACCESS_URL"
          value = "https://coder.company.com"
        }
      ]
      secrets = [
        {
          name      = "CODER_PG_CONNECTION_URL"
          valueFrom = aws_secretsmanager_secret.db_url.arn
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/coder"
          awslogs-region        = "us-east-1"
          awslogs-stream-prefix = "coder"
        }
      }
    }
  ])
}
```

---

## 6. Configuration Changes

### 6.1 Environment Variables (Production)

```bash
# .env.production

# Coder Configuration
CODER_ACCESS_URL=https://coder.company.com
CODER_WILDCARD_ACCESS_URL=*.coder.company.com
CODER_SECURE_AUTH_COOKIE=true
CODER_STRICT_TRANSPORT_SECURITY=true
CODER_STRICT_TRANSPORT_SECURITY_OPTIONS=max-age=31536000; includeSubDomains

# Security
CODER_DISABLE_WORKSPACE_SHARING=true
CODER_DISABLE_PATH_APPS=true
CODER_DISABLE_OWNER_WORKSPACE_ACCESS=false  # Enable for high-security
CODER_MAX_SESSION_EXPIRY=8h
CODER_SESSION_DURATION=1h

# Rate Limiting
CODER_RATE_LIMIT_DISABLE_ALL=false
CODER_RATE_LIMIT_API=60

# AI Bridge (Bedrock)
CODER_AIBRIDGE_BEDROCK_ACCESS_KEY=${AWS_ACCESS_KEY_ID}
CODER_AIBRIDGE_BEDROCK_ACCESS_KEY_SECRET=${AWS_SECRET_ACCESS_KEY}
CODER_AIBRIDGE_BEDROCK_REGION=us-east-1

# Telemetry (optional - disable if required)
CODER_TELEMETRY=false

# Logging
CODER_VERBOSE=false
CODER_LOG_HUMAN=/dev/stderr
CODER_LOG_JSON=true
```

### 6.2 Template Changes

```terraform
# Production workspace template changes

resource "coder_agent" "main" {
  # Security: Disable all external connection methods
  display_apps {
    vscode                 = false
    vscode_insiders        = false
    web_terminal           = true
    ssh_helper             = false
    port_forwarding_helper = false
  }
}

resource "docker_container" "workspace" {
  # Resource limits
  cpu_shares = data.coder_parameter.cpu_cores.value * 1024
  memory     = data.coder_parameter.memory_gb.value * 1024 * 1024 * 1024
  memory_swap = data.coder_parameter.memory_gb.value * 1024 * 1024 * 1024  # No swap

  # Security options
  security_opts = ["no-new-privileges:true"]

  # Read-only root filesystem with specific writable paths
  read_only = true
  tmpfs = {
    "/tmp" = "size=1G,mode=1777"
    "/run" = "size=100M,mode=755"
  }

  # Limit capabilities
  capabilities {
    drop = ["ALL"]
    add  = ["CHOWN", "SETUID", "SETGID"]
  }
}
```

---

## 7. Monitoring & Observability

### 7.1 Monitoring Stack

```yaml
# Prometheus + Grafana + Loki
services:
  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.retention.time=30d'

  grafana:
    image: grafana/grafana:latest
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_PASSWORD}
      GF_AUTH_GENERIC_OAUTH_ENABLED: true
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/dashboards:/etc/grafana/provisioning/dashboards
      - ./grafana/datasources:/etc/grafana/provisioning/datasources

  loki:
    image: grafana/loki:latest
    volumes:
      - ./loki-config.yml:/etc/loki/config.yml
      - loki_data:/loki
    command: -config.file=/etc/loki/config.yml

  promtail:
    image: grafana/promtail:latest
    volumes:
      - /var/log:/var/log:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./promtail-config.yml:/etc/promtail/config.yml
```

### 7.2 Key Metrics

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| coder_workspace_count | >80% capacity | >95% capacity | Scale workers |
| coder_api_latency_p99 | >2s | >5s | Investigate |
| postgres_connections | >80% | >95% | Increase pool |
| node_cpu_usage | >70% | >90% | Scale/optimize |
| node_memory_usage | >75% | >90% | Scale/optimize |
| node_disk_usage | >70% | >85% | Expand/cleanup |

### 7.3 Alerting Rules

```yaml
# prometheus/alerts.yml
groups:
  - name: coder
    rules:
      - alert: CoderHighLatency
        expr: histogram_quantile(0.99, coder_api_request_duration_seconds_bucket) > 5
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Coder API latency is high"

      - alert: CoderWorkspaceFailure
        expr: increase(coder_workspace_build_failed_total[5m]) > 3
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Multiple workspace build failures"

      - alert: DatabaseConnectionsHigh
        expr: pg_stat_activity_count / pg_settings_max_connections > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Database connections approaching limit"
```

### 7.4 Dashboards

Key dashboards to create:

1. **Platform Overview**
   - Active workspaces
   - User sessions
   - API request rate
   - Error rate

2. **Infrastructure Health**
   - Node CPU/Memory/Disk
   - Container health
   - Database metrics

3. **Security Dashboard**
   - Failed login attempts
   - Unusual API activity
   - Audit log events

4. **AI Usage**
   - Request volume
   - Token consumption
   - Model usage distribution

---

## 8. Operational Procedures

### 8.1 Deployment Pipeline

```yaml
# .github/workflows/deploy-production.yml
name: Deploy to Production

on:
  push:
    tags:
      - 'v*'

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v3

      - name: Run Tests
        run: ./scripts/validate.sh

      - name: Security Scan
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'fs'
          severity: 'CRITICAL,HIGH'

      - name: Deploy to Production
        run: |
          # Blue-green deployment
          kubectl set image deployment/coder \
            coder=ghcr.io/coder/coder:${{ github.ref_name }}
          kubectl rollout status deployment/coder

      - name: Smoke Tests
        run: ./scripts/smoke-tests.sh

      - name: Notify
        uses: slackapi/slack-github-action@v1
        with:
          payload: |
            {"text": "Deployed ${{ github.ref_name }} to production"}
```

### 8.2 Backup Procedures

```bash
#!/bin/bash
# scripts/backup-production.sh

set -e

BACKUP_BUCKET="s3://company-backups/coder"
DATE=$(date +%Y%m%d-%H%M%S)

echo "Starting production backup: ${DATE}"

# 1. Database backup
echo "Backing up PostgreSQL..."
pg_dump -h $DB_HOST -U $DB_USER $DB_NAME | \
  gzip | \
  aws s3 cp - "${BACKUP_BUCKET}/postgres/backup-${DATE}.sql.gz"

# 2. Verify backup
aws s3 ls "${BACKUP_BUCKET}/postgres/backup-${DATE}.sql.gz"

# 3. Cleanup old backups (keep 30 days)
aws s3 ls "${BACKUP_BUCKET}/postgres/" | \
  while read -r line; do
    createDate=$(echo $line | awk '{print $1}')
    if [[ $(date -d "$createDate" +%s) -lt $(date -d "30 days ago" +%s) ]]; then
      fileName=$(echo $line | awk '{print $4}')
      aws s3 rm "${BACKUP_BUCKET}/postgres/${fileName}"
    fi
  done

echo "Backup completed: ${DATE}"
```

### 8.3 Incident Response

```markdown
## Incident Response Playbook

### Severity Levels
- **P1 (Critical)**: Platform down, all users affected
- **P2 (High)**: Major feature broken, many users affected
- **P3 (Medium)**: Minor feature issue, some users affected
- **P4 (Low)**: Cosmetic issue, minimal impact

### P1 Response
1. Acknowledge incident within 5 minutes
2. Create incident channel: #incident-YYYYMMDD-description
3. Assign incident commander
4. Begin diagnosis:
   - Check monitoring dashboards
   - Review recent deployments
   - Check infrastructure status
5. Communicate status every 15 minutes
6. Implement fix or rollback
7. Verify resolution
8. Post-incident review within 48 hours
```

### 8.4 Maintenance Procedures

| Task | Frequency | Window | Impact |
|------|-----------|--------|--------|
| Security patches | Weekly | Sunday 02:00-04:00 | Rolling restart |
| Database maintenance | Weekly | Sunday 03:00-04:00 | None (online) |
| Certificate renewal | 60 days before expiry | Anytime | None |
| Major upgrades | Quarterly | Scheduled | 1-2 hour outage |
| Disaster recovery test | Quarterly | Scheduled | None (DR env) |

---

## 9. Migration Checklist

### 9.1 Pre-Migration

```markdown
## Pre-Migration Checklist

### Infrastructure
- [ ] Production environment provisioned
- [ ] Network configured (VPC, subnets, security groups)
- [ ] DNS records created
- [ ] TLS certificates obtained
- [ ] Load balancer configured
- [ ] Database provisioned (RDS/managed)
- [ ] Redis cluster provisioned
- [ ] Storage (EBS/EFS) provisioned

### Security
- [ ] Secrets moved to Vault/Secrets Manager
- [ ] IAM roles created
- [ ] Security groups configured
- [ ] WAF rules configured
- [ ] Audit logging enabled

### Monitoring
- [ ] Prometheus deployed
- [ ] Grafana dashboards created
- [ ] Alerting rules configured
- [ ] Log aggregation configured
- [ ] On-call schedule set

### Documentation
- [ ] Runbooks created
- [ ] Incident response plan documented
- [ ] Backup/restore procedures tested
- [ ] DR plan documented
```

### 9.2 Migration Steps

```markdown
## Migration Steps

### Phase 1: Infrastructure (Week 1)
1. Deploy base infrastructure
2. Configure networking
3. Set up monitoring
4. Deploy supporting services (Gitea, Drone, etc.)

### Phase 2: Data Migration (Week 2)
1. Set up database replication from PoC
2. Migrate Git repositories
3. Migrate MinIO data
4. Verify data integrity

### Phase 3: Application Deployment (Week 3)
1. Deploy Coder to production
2. Migrate templates
3. Configure OIDC/SSO
4. Test workspace creation

### Phase 4: User Migration (Week 4)
1. Create user accounts
2. Migrate user workspaces (if needed)
3. User acceptance testing
4. Training sessions

### Phase 5: Cutover (Week 5)
1. Final data sync
2. DNS cutover
3. Monitor closely
4. Decommission PoC
```

### 9.3 Post-Migration

```markdown
## Post-Migration Checklist

- [ ] All users can login
- [ ] Workspace creation works
- [ ] Git operations work
- [ ] AI features work
- [ ] CI/CD pipelines work
- [ ] Backups verified
- [ ] Monitoring working
- [ ] Alerts firing correctly
- [ ] Performance baseline established
- [ ] Documentation updated
- [ ] Runbooks tested
- [ ] Team trained
```

---

## 10. Cost Estimation

### 10.1 AWS Cost Estimate (Monthly)

#### Small (50 users, 20 concurrent workspaces)

| Resource | Specification | Monthly Cost |
|----------|---------------|--------------|
| EC2 (Coder) | t3.large | $60 |
| EC2 (Workers) | t3.xlarge x 2 | $240 |
| RDS (PostgreSQL) | db.t3.medium Multi-AZ | $130 |
| ElastiCache (Redis) | cache.t3.small | $25 |
| ALB | 1 ALB + traffic | $30 |
| EBS Storage | 500 GB | $50 |
| Data Transfer | 100 GB | $10 |
| **Total** | | **~$545/month** |

#### Medium (200 users, 50 concurrent workspaces)

| Resource | Specification | Monthly Cost |
|----------|---------------|--------------|
| EC2 (Coder) | t3.xlarge x 2 | $240 |
| EC2 (Workers) | c5.2xlarge x 4 | $980 |
| RDS (PostgreSQL) | db.r5.large Multi-AZ | $350 |
| ElastiCache (Redis) | cache.r5.large cluster | $200 |
| ALB | 1 ALB + traffic | $50 |
| EBS Storage | 2 TB | $200 |
| S3 (backups) | 500 GB | $12 |
| Data Transfer | 500 GB | $45 |
| WAF | Base + rules | $30 |
| **Total** | | **~$2,100/month** |

### 10.2 Cost Optimization

| Optimization | Savings | Trade-off |
|--------------|---------|-----------|
| Reserved Instances (1-year) | 30-40% | Commitment |
| Spot Instances for workers | 60-70% | Interruption risk |
| Right-sizing | 20-30% | Requires monitoring |
| Auto-scaling | Variable | Complexity |
| Storage tiering | 20-40% | Access latency |

---

## Appendix A: Production Checklist Summary

```
╔═══════════════════════════════════════════════════════════════════════════╗
║                    PRODUCTION READINESS CHECKLIST                          ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                            ║
║  SECURITY                          INFRASTRUCTURE                          ║
║  ─────────                         ──────────────                          ║
║  □ TLS/HTTPS enabled               □ HA database configured                ║
║  □ Default passwords changed       □ Redis cluster deployed                ║
║  □ MFA enabled                     □ Load balancer configured              ║
║  □ Secrets in Vault                □ Auto-scaling configured               ║
║  □ Network segmentation            □ Backups automated                     ║
║  □ WAF configured                  □ DR tested                             ║
║  □ Audit logging enabled           □ DNS configured                        ║
║                                                                            ║
║  MONITORING                        OPERATIONS                              ║
║  ──────────                        ──────────                              ║
║  □ Prometheus deployed             □ Runbooks created                      ║
║  □ Grafana dashboards              □ Incident response plan                ║
║  □ Alerting configured             □ On-call schedule                      ║
║  □ Log aggregation                 □ Deployment pipeline                   ║
║  □ Uptime monitoring               □ Team trained                          ║
║                                                                            ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-04 | Platform Team | Initial version |
| 1.1 | 2026-02-05 | Platform Team | Added cross-references to POC-SECURITY-REVIEW.md, SECURITY.md, and PRODUCTION-PLAN.md; updated container security notes to reflect current non-root configuration |
