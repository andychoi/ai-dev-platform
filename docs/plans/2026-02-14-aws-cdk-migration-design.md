# AWS Production Infrastructure — CDK Migration Design

**Date:** 2026-02-14
**Status:** Approved
**Language:** TypeScript
**Location:** `aws-production-cdk/` (alongside existing `aws-production/` Terraform)

---

## Scope

**In scope (CDK):** VPC, ECS Fargate cluster, ALB, RDS, ElastiCache, EFS, S3, Secrets Manager, IAM roles, ACM, CloudWatch, Service Discovery, and ECS service/task definitions for platform services (Coder, LiteLLM, Key Provisioner, Langfuse stack).

**Out of scope (stays Terraform):** Workspace templates (`contractor-workspace`, `docker-workspace`, `aem-workspace`) — Coder's provisioner is Terraform-native.

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Language | TypeScript | Best CDK ecosystem support, native type safety |
| Location | New directory alongside | Both coexist during migration, Terraform stays as reference |
| Stack strategy | 4 layered stacks | Independent deployment per layer, controlled blast radius |
| Construct style | L2 (explicit) | Full control over resources; L3 patterns fight production complexity |

---

## Stack Architecture

### Dependency Chain

```
NetworkStack (VPC, SGs, VPC Endpoints, CloudMap)
    |
DataStack (RDS, Redis, EFS, S3, Secrets)
    |
PlatformStack (ECS, ALB, ACM, Coder, LiteLLM, KeyProvisioner)
    |
ObservabilityStack (ClickHouse, Langfuse Web, Langfuse Worker)
```

Each stack only depends on the one above. Redeploying PlatformStack does not touch NetworkStack or DataStack.

---

### NetworkStack

Resources:
- **VPC** (10.0.0.0/16, 2 AZs)
  - 2 public subnets (10.0.0.0/24, 10.0.1.0/24) — NAT Gateway only
  - 2 private app subnets (10.0.10.0/24, 10.0.11.0/24) — ECS Fargate
  - 2 private data subnets (10.0.20.0/24, 10.0.21.0/24) — RDS, ElastiCache
- **NAT Gateway** — single-AZ for cost savings
- **VPC Endpoints** — S3 (gateway), ECR, Secrets Manager, CloudWatch, Bedrock, STS, EFS
- **Security Groups:**
  - `sg-alb`: inbound 443 from VPC CIDR
  - `sg-ecs-services`: ALB → 7080, 9000, 4000, 3000, 8100
  - `sg-ecs-workspaces`: ALB → 13337, outbound to LiteLLM(4000), DNS(53), HTTPS(443)
  - `sg-rds`: inbound 5432 from sg-ecs-services
  - `sg-redis`: inbound 6379 from sg-ecs-services
  - `sg-efs`: inbound 2049 from sg-ecs-services + sg-ecs-workspaces
- **CloudMap** — private DNS namespace `coder-production.local`

Exports: `vpc`, `securityGroups`, `serviceDiscoveryNamespace`

---

### DataStack

Resources:
- **RDS PostgreSQL 16** — r6g.large, single-AZ, 100→500 GB auto-scale, KMS encryption, 30-day backup, SSL required
- **ElastiCache Redis 7.x** — r6g.large, 1 primary + 1 replica, TLS + KMS
- **EFS** — general purpose, bursting throughput, KMS, lifecycle to IA after 30 days, mount targets in both app subnets
- **S3 Buckets** (5): terraform-state (versioned), backups, artifacts, langfuse-events, langfuse-media
- **DynamoDB** — `terraform-locks` table (for Terraform state locking)
- **Secrets Manager** (8 entries):
  - `prod/coder/oidc` — Azure AD client ID + secret
  - `prod/alb/oidc` — ALB direct path OIDC
  - `prod/litellm/master-key`
  - `prod/litellm/anthropic-api-key`
  - `prod/key-provisioner/secret`
  - `prod/langfuse/*` — auth, ClickHouse
  - RDS credentials — auto-managed by CDK `DatabaseInstance`

Exports: `database`, `redis`, `fileSystem`, `buckets`, `secrets`

---

### PlatformStack

Resources:
- **ECS Cluster** — Fargate + Fargate Spot capacity providers, container insights
- **ACM Certificate** — `coder.company.com`, `*.company.com`, `ide.company.com` (DNS validation)
- **Internal ALB** — HTTPS:443, host-based routing
- **IAM** — 1 shared execution role + 4 per-service task roles

Service Constructs:

**CoderService:**
- Task: 1 vCPU / 4 GB, port 7080
- EFS mount: `/home/coder/.config/coderv2`
- Env: `CODER_ACCESS_URL`, `CODER_OIDC_*`, `CODER_SECURE_AUTH_COOKIE`
- Secrets: DB connection, OIDC client
- ALB: `coder.company.com` → 7080
- Service Discovery: `coder.coder-production.local`

**LiteLLMService:**
- Task: 0.5 vCPU / 2 GB, port 4000, 2 replicas
- IAM: Bedrock `InvokeModel` on task role
- Config + hooks mounted as assets
- ALB: `ai.company.com` → 4000
- Service Discovery: `litellm.coder-production.local`

**KeyProvisionerService:**
- Task: 0.25 vCPU / 512 MB, port 8100
- ALB: `admin.company.com` → 8100
- Service Discovery: `key-provisioner.coder-production.local`

Exports: `cluster`, `alb`, `workspaceOutputs` (for Terraform template consumption)

---

### ObservabilityStack

Resources:

**ClickHouse:** 1 vCPU / 4 GB, ports 8123 + 9000, EFS mount `/var/lib/clickhouse`

**Langfuse Web:** 1 vCPU / 2 GB, port 3000, ALB route `langfuse.company.com`

**Langfuse Worker:** 0.5 vCPU / 1 GB, background processing (no ALB)

---

## CDK–Terraform Bridge

PlatformStack exports `workspaceOutputs` as CloudFormation outputs and SSM Parameters. Terraform workspace templates consume them:

```typescript
// CDK exports
workspaceOutputs: {
  clusterArn: string
  taskExecutionRoleArn: string
  workspaceTaskRoleArn: string
  workspaceSecurityGroupId: string
  privateSubnetIds: string[]
  efsFileSystemId: string
  albListenerArn: string
}
```

```hcl
# Terraform workspace template consumes via SSM
data "aws_ssm_parameter" "cluster_arn" {
  name = "/coder-production/cluster-arn"
}
```

---

## Project Structure

```
aws-production-cdk/
├── bin/
│   └── app.ts                              # CDK app entry (~40 lines)
├── lib/
│   ├── config/
│   │   └── environment.ts                  # Typed config (~50 lines)
│   ├── stacks/
│   │   ├── network-stack.ts                (~200 lines)
│   │   ├── data-stack.ts                   (~250 lines)
│   │   ├── platform-stack.ts               (~150 lines)
│   │   └── observability-stack.ts          (~100 lines)
│   └── constructs/
│       ├── coder-service.ts                (~150 lines)
│       ├── litellm-service.ts              (~150 lines)
│       ├── key-provisioner-service.ts      (~100 lines)
│       └── langfuse-service.ts             (~180 lines)
├── litellm/
│   └── config.yaml                         # Production LiteLLM config
├── cdk.json
├── tsconfig.json
├── package.json
└── README.md
```

~12 source files, ~1,370 lines estimated.

---

## Deployment

```bash
cd aws-production-cdk

# Bootstrap (first time per account/region)
npx cdk bootstrap aws://ACCOUNT/us-west-2

# Deploy all stacks (CDK resolves dependency order)
npx cdk deploy --all

# Deploy individually
npx cdk deploy NetworkStack
npx cdk deploy DataStack
npx cdk deploy PlatformStack
npx cdk deploy ObservabilityStack

# Preview changes
npx cdk diff PlatformStack
```

---

## Custom LLM Integration

The LiteLLM config includes custom corporate proxy models (from h-chat-api.autoever.com):
- OpenAI custom: `custom-gpt-4o`, `custom-gpt-4o-mini`, `custom-gpt-4.1`, `custom-gpt-4.1-mini`, `custom-gpt-4.1-nano`, `custom-o3-mini`
- Gemini custom: `custom-gemini-2.5-flash`, `custom-gemini-2.5-pro`, `custom-gemini-2.0-flash`
- Claude custom: `custom-claude-haiku`, `custom-claude-sonnet`, `custom-claude-opus`

Environment variables `CUSTOM_LLM_API_KEY`, `CUSTOM_LLM_API_BASE`, `CUSTOM_LLM_CLAUDE_API_BASE` are stored in Secrets Manager and passed to the LiteLLM ECS task.
