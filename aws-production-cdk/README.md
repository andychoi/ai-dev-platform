# AWS Production Infrastructure (CDK)

AWS CDK (TypeScript) implementation of the Coder WebIDE production infrastructure on AWS ECS Fargate.

Replaces the Terraform modules in `aws-production/terraform/` for platform infrastructure, while Coder workspace templates remain Terraform-native.

## Architecture Overview

```
                           VPN
                            │
                    ┌───────▼───────┐
                    │  Internal ALB  │  (HTTPS:443, ACM cert)
                    │  Host routing  │
                    └───┬───┬───┬───┘
                        │   │   │
         ┌──────────────┘   │   └──────────────┐
         ▼                  ▼                   ▼
   ┌───────────┐    ┌────────────┐    ┌──────────────┐
   │   Coder   │    │  LiteLLM   │    │   Langfuse   │
   │   :7080   │    │   :4000    │    │    :3000     │
   │  1×Fargate│    │ 2×Fargate  │    │  1×Fargate   │
   └─────┬─────┘    └─────┬──────┘    └──────┬───────┘
         │                │                   │
         │          ┌─────▼──────┐    ┌───────▼────────┐
         │          │  Bedrock   │    │  ClickHouse    │
         │          │ (IAM role) │    │  1×Fargate     │
         │          └────────────┘    └────────────────┘
         │
   ┌─────▼──────────────────────────────────────┐
   │         Workspace Tasks (Fargate Spot)      │
   │  ┌──────┐ ┌──────┐ ┌──────┐               │
   │  │ WS-1 │ │ WS-2 │ │ WS-N │  :13337 each │
   │  └──┬───┘ └──┬───┘ └──┬───┘               │
   └─────┼────────┼────────┼────────────────────┘
         └────────┴────────┘
                  │
   ┌──────────────▼──────────────────┐
   │         Data Layer              │
   │  RDS PostgreSQL  │  Redis       │
   │  EFS             │  S3          │
   └─────────────────────────────────┘
```

## Stack Architecture

4 layered CDK stacks deployed in dependency order:

```
NetworkStack        VPC, subnets, NAT, security groups, VPC endpoints, CloudMap
     │
DataStack           RDS PostgreSQL, ElastiCache Redis, EFS, S3 buckets, Secrets Manager
     │
PlatformStack       ECS cluster, ALB, ACM, IAM roles, Coder, LiteLLM, Key Provisioner
     │
ObservabilityStack  ClickHouse, Langfuse Web, Langfuse Worker
```

Each stack can be deployed independently. Redeploying PlatformStack does not touch NetworkStack or DataStack.

## Scope

| Managed by CDK | Managed by Terraform |
|----------------|----------------------|
| VPC, subnets, NAT, VPC endpoints | Workspace templates (contractor, docker, AEM) |
| ECS Fargate cluster | Per-workspace ECS tasks |
| Internal ALB + ACM | Per-workspace ALB listener rules (Path 2) |
| RDS, ElastiCache, EFS, S3 | Per-workspace EFS access points |
| Secrets Manager | — |
| IAM roles (platform + workspace) | — |
| Service Discovery (CloudMap) | — |
| Platform services (Coder, LiteLLM, Key Provisioner, Langfuse) | — |

CDK exports infrastructure IDs via **SSM Parameters** that Terraform workspace templates consume (see [CDK-Terraform Bridge](#cdk-terraform-bridge)).

## Prerequisites

- Node.js 18+
- AWS CLI configured with appropriate credentials
- AWS CDK CLI: `npm install -g aws-cdk`
- First-time: CDK bootstrap in target account

## Quick Start

```bash
cd aws-production-cdk

# Install dependencies
npm install

# Bootstrap CDK (first time per account/region)
npx cdk bootstrap aws://ACCOUNT_ID/us-west-2

# Preview changes
npx cdk diff --all

# Deploy all stacks
npx cdk deploy --all

# Deploy individual stack
npx cdk deploy PlatformStack
```

## Configuration

All environment-specific values are in `lib/config/environment.ts`:

```typescript
{
  account: '123456789012',
  region: 'us-west-2',
  domain: 'coder.company.com',
  vpcCidr: '10.0.0.0/16',
  rdsInstanceClass: 'r6g.large',
  redisNodeType: 'cache.r6g.large',
  coderImage: 'ghcr.io/coder/coder:latest',
  litellmImage: 'ghcr.io/berriai/litellm:main-latest',
  oidcIssuerUrl: 'https://login.microsoftonline.com/{tenant}/v2.0',
  enableDockerWorkspaces: false,
  enableWorkspaceDirectAccess: true,
  customLlmApiBase: 'https://h-chat-api.autoever.com/v2/api',
  // ...
}
```

To customize for a different environment, modify the `productionConfig` object or create additional config objects (e.g., `stagingConfig`).

## Project Structure

```
aws-production-cdk/
├── bin/
│   └── aws-production-cdk.ts      # App entry — instantiates all stacks
├── lib/
│   ├── config/
│   │   └── environment.ts         # Typed config (domain, AZs, instance sizes)
│   ├── stacks/
│   │   ├── network-stack.ts       # VPC, subnets, NAT, SGs, VPC endpoints, CloudMap
│   │   ├── data-stack.ts          # RDS, ElastiCache, EFS, S3, Secrets, DynamoDB
│   │   ├── platform-stack.ts      # ECS cluster, ALB, ACM, IAM, services
│   │   └── observability-stack.ts # Langfuse + ClickHouse
│   └── constructs/
│       ├── coder-service.ts       # Coder ECS task + ALB + CloudMap
│       ├── litellm-service.ts     # LiteLLM ECS task + Bedrock IAM + ALB
│       ├── key-provisioner-service.ts  # Key Provisioner + OIDC admin auth
│       └── langfuse-service.ts    # ClickHouse + Langfuse Web + Worker
├── litellm/
│   └── config.yaml                # LiteLLM proxy config (models, hooks)
├── test/
│   └── stacks/                    # CDK assertion tests per stack
├── cdk.json
├── tsconfig.json
└── package.json
```

## Resource Details

### NetworkStack

| Resource | Configuration |
|----------|---------------|
| VPC | 10.0.0.0/16, DNS support + hostnames enabled |
| Public subnets (×2) | 10.0.0.0/24, 10.0.1.0/24 — NAT Gateway only |
| Private app subnets (×2) | 10.0.10.0/24, 10.0.11.0/24 — ECS Fargate tasks |
| Private data subnets (×2) | 10.0.20.0/24, 10.0.21.0/24 — RDS, ElastiCache (isolated) |
| NAT Gateway | Single-AZ (cost optimization) |
| VPC Endpoints | S3 (gateway), ECR API, ECR Docker, Secrets Manager, CloudWatch, STS, Bedrock, ECS, EFS, SSM |
| CloudMap | `coder-production.local` private DNS namespace |

**Security Groups:**

| SG | Inbound | From |
|----|---------|------|
| sg-alb | 443 | VPC CIDR |
| sg-ecs-services | 7080, 4000, 3000, 8100, 8123, 9000 | sg-alb |
| sg-ecs-workspaces | 13337 | sg-alb |
| sg-rds | 5432 | sg-ecs-services |
| sg-redis | 6379 | sg-ecs-services |
| sg-efs | 2049 | sg-ecs-services, sg-ecs-workspaces |

### DataStack

| Resource | Configuration |
|----------|---------------|
| RDS PostgreSQL 16 | r6g.large, 100→500 GB auto-scale, KMS, SSL forced, 30-day backup, deletion protection |
| ElastiCache Redis 7.x | r6g.large, 1 primary + 1 replica, Multi-AZ, TLS + KMS, 7-day snapshots |
| EFS | General purpose, bursting, KMS, IA lifecycle 30 days |
| S3 (×5) | terraform-state, backups (90d noncurrent delete), artifacts, langfuse-events, langfuse-media |
| DynamoDB | `terraform-locks` table (PAY_PER_REQUEST) |
| Secrets Manager (×11) | See [Secrets Reference](#secrets-reference) |

### PlatformStack — Services

| Service | CPU/Memory | Replicas | Port | ALB Host | Service Discovery |
|---------|-----------|----------|------|----------|-------------------|
| Coder | 1 vCPU / 4 GB | 1 | 7080 | `coder.{domain}`, `*.{domain}` | `coder.coder-production.local` |
| LiteLLM | 0.5 vCPU / 2 GB | 2 | 4000 | `ai.{domain}` | `litellm.coder-production.local` |
| Key Provisioner | 0.25 vCPU / 512 MB | 1 | 8100 | `admin.{domain}` (OIDC auth) | `key-provisioner.coder-production.local` |

### ObservabilityStack — Services

| Service | CPU/Memory | Replicas | Port | ALB Host |
|---------|-----------|----------|------|----------|
| ClickHouse | 1 vCPU / 4 GB | 1 | 8123, 9000 | Internal only |
| Langfuse Web | 1 vCPU / 2 GB | 1 | 3000 | `langfuse.{domain}` |
| Langfuse Worker | 0.5 vCPU / 1 GB | 1 | 3030 | Internal only |

### IAM Roles

| Role | Key Permissions |
|------|----------------|
| Shared Execution | ECR pull, Secrets Manager `prod/*`, CloudWatch Logs |
| Coder Task | Secrets, S3 state, ECS RunTask, EFS access points, IAM PassRole |
| LiteLLM Task | Bedrock InvokeModel, Secrets (master key + Anthropic) |
| Key Provisioner Task | Secrets (provisioner + master key) |
| Langfuse Task | Secrets, S3 read/write (events + media) |
| Workspace Task | CloudWatch Logs only |
| AEM Workspace Task | CloudWatch Logs + S3 read `artifacts/aem/*` |

## CDK-Terraform Bridge

CDK exports infrastructure IDs as **SSM Parameters** so Terraform workspace templates can consume them without coupling:

| SSM Parameter | Value |
|---------------|-------|
| `/coder-production/cluster-arn` | ECS cluster ARN |
| `/coder-production/cluster-name` | ECS cluster name |
| `/coder-production/task-execution-role-arn` | Shared execution role ARN |
| `/coder-production/workspace-task-role-arn` | Workspace task role ARN |
| `/coder-production/workspace-sg-id` | Workspace security group ID |
| `/coder-production/private-subnet-ids` | Comma-separated private app subnet IDs |
| `/coder-production/efs-id` | EFS file system ID |
| `/coder-production/alb-listener-arn` | ALB HTTPS listener ARN (for Path 2) |

**Terraform workspace template usage:**

```hcl
data "aws_ssm_parameter" "cluster_arn" {
  name = "/coder-production/cluster-arn"
}

data "aws_ssm_parameter" "efs_id" {
  name = "/coder-production/efs-id"
}
```

## Secrets Reference

| Secret Path | Contents | Managed By |
|-------------|----------|------------|
| `prod/coder/database` | PostgreSQL connection string | CDK (constructed from RDS) |
| `prod/coder/oidc` | Azure AD client_id + client_secret | Manual (Azure AD registration) |
| `prod/authentik/secret-key` | Auto-generated 64 chars | CDK |
| `prod/litellm/master-key` | Auto-generated `sk-` prefixed key | CDK |
| `prod/litellm/anthropic-api-key` | Anthropic API key (fallback) | Manual |
| `prod/litellm/database` | LiteLLM PostgreSQL connection | CDK |
| `prod/key-provisioner/secret` | Auto-generated shared secret | CDK |
| `prod/langfuse/api-keys` | Public + secret key pair | CDK |
| `prod/langfuse/auth` | NextAuth secret + salt + encryption key | CDK |
| `prod/langfuse/database` | Langfuse PostgreSQL connection | CDK |
| `prod/langfuse/clickhouse` | ClickHouse password | CDK |

**Manual steps after first deploy:**
1. Update `prod/coder/oidc` with Azure AD app registration credentials
2. Update `prod/litellm/anthropic-api-key` with Anthropic API key (Bedrock fallback)

## Custom LLM Integration

LiteLLM is configured with corporate proxy models via `h-chat-api.autoever.com`:

| Model Name | Provider | API Format |
|------------|----------|------------|
| `custom-gpt-4o`, `custom-gpt-4o-mini`, `custom-gpt-4.1`, `custom-gpt-4.1-mini`, `custom-gpt-4.1-nano`, `custom-o3-mini` | Azure OpenAI | OpenAI chat completions |
| `custom-gemini-2.5-flash`, `custom-gemini-2.5-pro`, `custom-gemini-2.0-flash` | Gemini | Native Gemini API |
| `custom-claude-haiku`, `custom-claude-sonnet`, `custom-claude-opus` | Anthropic | Anthropic Messages API |

All custom models share a single API key stored in `prod/custom-llm/api-key`.

Environment variables:
- `CUSTOM_LLM_API_BASE` = `https://h-chat-api.autoever.com/v2/api` (OpenAI + Gemini)
- `CUSTOM_LLM_CLAUDE_API_BASE` = `https://h-chat-api.autoever.com/v2/api/claude/messages` (Claude)
- `LITELLM_ANTHROPIC_DISABLE_URL_SUFFIX=true` (prevents LiteLLM from appending `/v1/messages`)

## ALB Routing Rules

| Priority | Host Pattern | Target | Auth |
|----------|-------------|--------|------|
| 100 | `coder.{domain}` | Coder (7080) | Coder OIDC session |
| 200 | `admin.{domain}` | Key Provisioner (8100) | ALB OIDC action (Azure AD) |
| 300 | `langfuse.{domain}` | Langfuse Web (3000) | — |
| 400 | `ai.{domain}` | LiteLLM (4000) | Virtual key auth |
| 500 | `*.{domain}` | Coder wildcard (7080) | Coder OIDC session |
| Dynamic | `{owner}--{ws}.ide.{domain}` | Workspace (13337) | ALB OIDC action (Path 2) |

## Dual-Path Access Model

```
Path 1 (Tunnel):   Browser → ALB → Coder (7080) → agent tunnel → code-server
                   Auth: Coder OIDC session
                   Requires: Coder server running

Path 2 (Direct):   Browser → ALB (OIDC auth) → code-server (13337) directly
                   Auth: ALB OIDC action + per-workspace subdomain
                   Requires: Only ALB + Azure AD (survives Coder restarts)
```

## Testing

```bash
# Run all tests
npx jest

# Run tests for a specific stack
npx jest test/stacks/network-stack.test.ts

# With coverage
npx jest --coverage
```

Tests use CDK `assertions` library to verify synthesized CloudFormation templates.

## Common Operations

**Update a service image:**
```bash
# Edit coderImage in lib/config/environment.ts, then:
npx cdk diff PlatformStack
npx cdk deploy PlatformStack
```

**Add a new model to LiteLLM:**
1. Add model entry to `litellm/config.yaml`
2. Redeploy: `npx cdk deploy PlatformStack`

**Rotate a secret:**
1. Update value in AWS Secrets Manager console
2. Restart the ECS service: `aws ecs update-service --force-new-deployment`

**Change instance sizes:**
```bash
# Edit rdsInstanceClass or redisNodeType in lib/config/environment.ts, then:
npx cdk diff DataStack
npx cdk deploy DataStack
```

## Cost Estimate (50 users, 20 concurrent workspaces)

| Resource | Monthly |
|----------|---------|
| ECS Fargate (platform services) | ~$105 |
| ECS Fargate (workspaces, Spot) | ~$450 |
| RDS PostgreSQL (r6g.large) | ~$175 |
| ElastiCache Redis (r6g.large) | ~$200 |
| Internal ALB | ~$25 |
| EFS (200 GB) | ~$60 |
| S3 | ~$3 |
| Secrets Manager | ~$5 |
| CloudWatch | ~$50 |
| NAT Gateway | ~$35 |
| Bedrock (Claude) | ~$250 |
| **Total** | **~$1,360/mo** |

## Related Documentation

- [Production Plan](../aws-production/PRODUCTION-PLAN.md) — Full architecture guide, decision log
- [CDK Design Doc](../docs/plans/2026-02-14-aws-cdk-migration-design.md) — Design decisions and rationale
- [Implementation Plan](../docs/plans/2026-02-14-aws-cdk-migration.md) — Task-by-task build plan
- [Security Architecture](../shared/docs/SECURITY.md) — Network isolation, threat model
- [Key Management](../shared/docs/KEY-MANAGEMENT.md) — Virtual key provisioning
- [LiteLLM Config](../coder-poc/docs/runbook.md) — AI gateway operations
