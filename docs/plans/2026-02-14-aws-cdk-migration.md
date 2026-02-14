# AWS CDK Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rewrite the AWS production infrastructure (currently in Terraform) as AWS CDK TypeScript, covering VPC through ECS service definitions — excluding Coder workspace templates which stay as Terraform.

**Architecture:** 4 layered CDK stacks (Network → Data → Platform → Observability) using L2 constructs. Each stack exports typed interfaces consumed by the next. PlatformStack also exports SSM Parameters for the Terraform workspace templates to consume.

**Tech Stack:** AWS CDK v2, TypeScript, Jest (CDK assertions), `aws-cdk-lib` constructs for VPC, ECS Fargate, ALB, RDS, ElastiCache, EFS, S3, Secrets Manager, IAM, ACM, CloudMap.

**Reference Terraform:** `aws-production/terraform/` (main.tf, services.tf, modules/*)
**Design doc:** `docs/plans/2026-02-14-aws-cdk-migration-design.md`

---

## Task 1: Project Scaffolding

**Files:**
- Create: `aws-production-cdk/package.json`
- Create: `aws-production-cdk/tsconfig.json`
- Create: `aws-production-cdk/cdk.json`
- Create: `aws-production-cdk/jest.config.js`
- Create: `aws-production-cdk/.gitignore`
- Create: `aws-production-cdk/.npmrc`

**Step 1: Initialize CDK project**

```bash
cd /Users/andymini/ai/ai-dev-platform
mkdir -p aws-production-cdk
cd aws-production-cdk
npx cdk init app --language typescript
```

Expected: Project scaffolded with `bin/`, `lib/`, `test/`, `package.json`, `cdk.json`.

**Step 2: Install additional dependencies**

```bash
cd /Users/andymini/ai/ai-dev-platform/aws-production-cdk
npm install
```

Expected: `node_modules/` created, `aws-cdk-lib` and `constructs` installed.

**Step 3: Create directory structure**

```bash
cd /Users/andymini/ai/ai-dev-platform/aws-production-cdk
mkdir -p lib/stacks lib/constructs lib/config test/stacks
```

**Step 4: Remove default scaffold files**

Delete the auto-generated `lib/aws-production-cdk-stack.ts` and `test/aws-production-cdk.test.ts` — we'll create our own.

**Step 5: Verify project builds**

```bash
cd /Users/andymini/ai/ai-dev-platform/aws-production-cdk
npx tsc --noEmit
```

Expected: No errors.

**Step 6: Commit**

```bash
git add aws-production-cdk/
git commit -m "feat: scaffold AWS CDK project for production infrastructure"
```

---

## Task 2: Environment Config

**Files:**
- Create: `aws-production-cdk/lib/config/environment.ts`

**Step 1: Write the environment config type and defaults**

```typescript
// aws-production-cdk/lib/config/environment.ts

export interface EnvironmentConfig {
  // AWS account & region
  account: string;
  region: string;

  // Naming
  project: string;
  environment: string;

  // Networking
  vpcCidr: string;
  availabilityZones: string[];

  // Domain
  domain: string;
  hostedZoneId: string; // Route53 hosted zone (empty = skip DNS validation)

  // RDS
  rdsInstanceClass: string;
  rdsAllocatedStorage: number;
  rdsMaxAllocatedStorage: number;

  // ElastiCache
  redisNodeType: string;

  // Container images
  coderImage: string;
  litellmImage: string;
  keyProvisionerImage: string;
  langfuseImage: string;
  clickhouseImage: string;

  // OIDC (Azure AD)
  oidcIssuerUrl: string;
  oidcAuthorizationEndpoint: string;
  oidcTokenEndpoint: string;
  oidcUserInfoEndpoint: string;

  // Feature flags
  enableDockerWorkspaces: boolean;
  enableWorkspaceDirectAccess: boolean;

  // Custom LLM
  customLlmApiBase: string;

  // Tags
  tags: Record<string, string>;
}

export const productionConfig: EnvironmentConfig = {
  account: process.env.CDK_DEFAULT_ACCOUNT || '',
  region: 'us-west-2',

  project: 'coder',
  environment: 'production',

  vpcCidr: '10.0.0.0/16',
  availabilityZones: ['us-west-2a', 'us-west-2b'],

  domain: 'coder.company.com',
  hostedZoneId: '',

  rdsInstanceClass: 'r6g.large',
  rdsAllocatedStorage: 100,
  rdsMaxAllocatedStorage: 500,

  redisNodeType: 'cache.r6g.large',

  coderImage: 'ghcr.io/coder/coder:latest',
  litellmImage: 'ghcr.io/berriai/litellm:main-latest',
  keyProvisionerImage: '', // Built from shared/key-provisioner
  langfuseImage: 'langfuse/langfuse:latest',
  clickhouseImage: 'clickhouse/clickhouse-server:24-alpine',

  oidcIssuerUrl: 'https://login.microsoftonline.com/{tenant-id}/v2.0',
  oidcAuthorizationEndpoint: 'https://login.microsoftonline.com/{tenant-id}/oauth2/v2.0/authorize',
  oidcTokenEndpoint: 'https://login.microsoftonline.com/{tenant-id}/oauth2/v2.0/token',
  oidcUserInfoEndpoint: 'https://graph.microsoft.com/oidc/userinfo',

  enableDockerWorkspaces: false,
  enableWorkspaceDirectAccess: true,

  customLlmApiBase: 'https://h-chat-api.autoever.com/v2/api',

  tags: {
    Project: 'coder-webide',
    Environment: 'production',
    ManagedBy: 'cdk',
  },
};
```

**Step 2: Verify it compiles**

```bash
cd /Users/andymini/ai/ai-dev-platform/aws-production-cdk
npx tsc --noEmit
```

Expected: No errors.

**Step 3: Commit**

```bash
git add aws-production-cdk/lib/config/
git commit -m "feat: add typed environment config for CDK stacks"
```

---

## Task 3: NetworkStack

**Files:**
- Create: `aws-production-cdk/lib/stacks/network-stack.ts`
- Create: `aws-production-cdk/test/stacks/network-stack.test.ts`

**Reference:** `aws-production/terraform/modules/vpc/main.tf`

**Step 1: Write the failing test**

```typescript
// aws-production-cdk/test/stacks/network-stack.test.ts
import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { NetworkStack } from '../../lib/stacks/network-stack';
import { productionConfig } from '../../lib/config/environment';

describe('NetworkStack', () => {
  let template: Template;

  beforeAll(() => {
    const app = new cdk.App();
    const stack = new NetworkStack(app, 'TestNetworkStack', {
      env: { account: '123456789012', region: 'us-west-2' },
      config: productionConfig,
    });
    template = Template.fromStack(stack);
  });

  test('creates VPC with correct CIDR', () => {
    template.hasResourceProperties('AWS::EC2::VPC', {
      CidrBlock: '10.0.0.0/16',
      EnableDnsSupport: true,
      EnableDnsHostnames: true,
    });
  });

  test('creates 6 subnets (2 public + 2 private app + 2 private data)', () => {
    template.resourceCountIs('AWS::EC2::Subnet', 6);
  });

  test('creates NAT Gateway', () => {
    template.resourceCountIs('AWS::EC2::NatGateway', 1);
  });

  test('creates Internet Gateway', () => {
    template.resourceCountIs('AWS::EC2::InternetGateway', 1);
  });

  test('creates Cloud Map namespace', () => {
    template.hasResourceProperties('AWS::ServiceDiscovery::PrivateDnsNamespace', {
      Name: 'coder-production.local',
    });
  });

  test('creates security groups for ALB, ECS services, workspaces, RDS, Redis, EFS', () => {
    // At least 6 security groups (VPC default + our 6)
    const sgs = template.findResources('AWS::EC2::SecurityGroup');
    expect(Object.keys(sgs).length).toBeGreaterThanOrEqual(6);
  });

  test('creates S3 gateway endpoint', () => {
    template.hasResourceProperties('AWS::EC2::VPCEndpoint', {
      ServiceName: { 'Fn::Join': ['', ['com.amazonaws.', { Ref: 'AWS::Region' }, '.s3']] },
      VpcEndpointType: 'Gateway',
    });
  });
});
```

**Step 2: Run test to verify it fails**

```bash
cd /Users/andymini/ai/ai-dev-platform/aws-production-cdk
npx jest test/stacks/network-stack.test.ts --no-coverage
```

Expected: FAIL — `Cannot find module '../../lib/stacks/network-stack'`

**Step 3: Implement NetworkStack**

Create `aws-production-cdk/lib/stacks/network-stack.ts` with:

- VPC (10.0.0.0/16, 2 AZs) with 3 subnet tiers:
  - Public (10.0.0.0/24, 10.0.1.0/24) — `subnetType: PUBLIC`, single NAT Gateway
  - Private App (10.0.10.0/24, 10.0.11.0/24) — `subnetType: PRIVATE_WITH_EGRESS`
  - Private Data (10.0.20.0/24, 10.0.21.0/24) — `subnetType: PRIVATE_ISOLATED`
- VPC Endpoints: S3 (Gateway), ECR API, ECR Docker, Secrets Manager, CloudWatch Logs, STS, Bedrock Runtime, ECS, EFS, SSM
- 6 Security Groups:
  - `sg-alb`: ingress 443 from VPC CIDR
  - `sg-ecs-services`: ingress 7080, 4000, 3000, 8100, 8123, 9000, 3030 from sg-alb; ingress all from self
  - `sg-ecs-workspaces`: ingress 13337 from sg-alb; egress 4000 to sg-ecs-services, 443/53 to 0.0.0.0/0
  - `sg-rds`: ingress 5432 from sg-ecs-services
  - `sg-redis`: ingress 6379 from sg-ecs-services
  - `sg-efs`: ingress 2049 from sg-ecs-services + sg-ecs-workspaces
- CloudMap private DNS namespace: `coder-production.local`

Export interface:
```typescript
export interface NetworkStackOutputs {
  vpc: ec2.IVpc;
  securityGroups: {
    alb: ec2.ISecurityGroup;
    ecsServices: ec2.ISecurityGroup;
    ecsWorkspaces: ec2.ISecurityGroup;
    rds: ec2.ISecurityGroup;
    redis: ec2.ISecurityGroup;
    efs: ec2.ISecurityGroup;
  };
  namespace: servicediscovery.IPrivateDnsNamespace;
}
```

**Step 4: Run test to verify it passes**

```bash
cd /Users/andymini/ai/ai-dev-platform/aws-production-cdk
npx jest test/stacks/network-stack.test.ts --no-coverage
```

Expected: All tests PASS.

**Step 5: Synth to verify CloudFormation output**

```bash
cd /Users/andymini/ai/ai-dev-platform/aws-production-cdk
npx cdk synth NetworkStack --no-staging 2>&1 | head -50
```

Expected: Valid CloudFormation YAML with VPC, subnets, NAT, security groups.

**Step 6: Commit**

```bash
git add aws-production-cdk/lib/stacks/network-stack.ts aws-production-cdk/test/stacks/network-stack.test.ts
git commit -m "feat: add NetworkStack — VPC, subnets, SGs, VPC endpoints, CloudMap"
```

---

## Task 4: DataStack

**Files:**
- Create: `aws-production-cdk/lib/stacks/data-stack.ts`
- Create: `aws-production-cdk/test/stacks/data-stack.test.ts`

**Reference:** `aws-production/terraform/modules/{rds,elasticache,efs,s3,secrets}/main.tf`

**Step 1: Write the failing test**

```typescript
// aws-production-cdk/test/stacks/data-stack.test.ts
import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { NetworkStack } from '../../lib/stacks/network-stack';
import { DataStack } from '../../lib/stacks/data-stack';
import { productionConfig } from '../../lib/config/environment';

describe('DataStack', () => {
  let template: Template;

  beforeAll(() => {
    const app = new cdk.App();
    const networkStack = new NetworkStack(app, 'TestNetwork', {
      env: { account: '123456789012', region: 'us-west-2' },
      config: productionConfig,
    });
    const dataStack = new DataStack(app, 'TestData', {
      env: { account: '123456789012', region: 'us-west-2' },
      config: productionConfig,
      network: networkStack.outputs,
    });
    template = Template.fromStack(dataStack);
  });

  test('creates RDS PostgreSQL 16 instance', () => {
    template.hasResourceProperties('AWS::RDS::DBInstance', {
      Engine: 'postgres',
      EngineVersion: '16',
      DBInstanceClass: 'db.r6g.large',
      StorageEncrypted: true,
      DeletionProtection: true,
    });
  });

  test('creates ElastiCache Redis replication group', () => {
    template.hasResourceProperties('AWS::ElastiCache::ReplicationGroup', {
      Engine: 'redis',
      AtRestEncryptionEnabled: true,
      TransitEncryptionEnabled: true,
      AutomaticFailoverEnabled: true,
    });
  });

  test('creates EFS file system with encryption', () => {
    template.hasResourceProperties('AWS::EFS::FileSystem', {
      Encrypted: true,
      PerformanceMode: 'generalPurpose',
      ThroughputMode: 'bursting',
    });
  });

  test('creates EFS mount targets in app subnets', () => {
    template.resourceCountIs('AWS::EFS::MountTarget', 2);
  });

  test('creates 5 S3 buckets', () => {
    template.resourceCountIs('AWS::S3::Bucket', 5);
  });

  test('creates DynamoDB lock table', () => {
    template.hasResourceProperties('AWS::DynamoDB::Table', {
      TableName: 'terraform-locks',
      KeySchema: [{ AttributeName: 'LockID', KeyType: 'HASH' }],
    });
  });

  test('creates Secrets Manager secrets', () => {
    const secrets = template.findResources('AWS::SecretsManager::Secret');
    expect(Object.keys(secrets).length).toBeGreaterThanOrEqual(8);
  });
});
```

**Step 2: Run test to verify it fails**

```bash
cd /Users/andymini/ai/ai-dev-platform/aws-production-cdk
npx jest test/stacks/data-stack.test.ts --no-coverage
```

Expected: FAIL — cannot find module.

**Step 3: Implement DataStack**

Create `aws-production-cdk/lib/stacks/data-stack.ts` with:

- **RDS PostgreSQL 16:**
  - Instance class from config (r6g.large)
  - Allocated 100 GB, max 500 GB, GP3 storage
  - KMS encryption, SSL forced via parameter group (`rds.force_ssl=1`)
  - 30-day automated backup retention
  - Deletion protection enabled
  - Credentials auto-generated → Secrets Manager
  - Private data subnets, sg-rds security group
  - CloudWatch performance insights enabled

- **ElastiCache Redis 7.x:**
  - Replication group: 1 primary + 1 replica
  - Multi-AZ with automatic failover
  - At-rest + in-transit encryption (TLS)
  - Node type from config (cache.r6g.large)
  - Maintenance window: Sun 04:30-05:30 UTC
  - Snapshot window: 03:00-04:00 UTC, 7-day retention
  - Private data subnets, sg-redis security group

- **EFS:**
  - General purpose performance, bursting throughput
  - KMS encryption
  - Lifecycle: transition to IA after 30 days
  - Mount targets in both private app subnets
  - sg-efs security group

- **S3 Buckets (5):**
  - `{project}-terraform-state` — versioned
  - `{project}-backups` — versioned, 90-day noncurrent delete
  - `{project}-artifacts` — versioned
  - `{project}-langfuse-events`
  - `{project}-langfuse-media`
  - All: SSE-S3 encryption, public access blocked, bucket key enabled

- **DynamoDB:**
  - Table: `terraform-locks` (LockID HASH key, PAY_PER_REQUEST)

- **Secrets Manager (11 entries):**
  - `prod/coder/database` — RDS connection string (constructed from RDS outputs)
  - `prod/coder/oidc` — placeholder (Azure AD client ID + secret)
  - `prod/authentik/secret-key` — auto-generated 64 chars
  - `prod/litellm/master-key` — auto-generated 48 chars (prefixed `sk-`)
  - `prod/litellm/anthropic-api-key` — placeholder
  - `prod/litellm/database` — LiteLLM PostgreSQL connection string
  - `prod/key-provisioner/secret` — auto-generated 48 chars
  - `prod/langfuse/api-keys` — public + secret key pair
  - `prod/langfuse/auth` — NextAuth secret + salt + encryption key
  - `prod/langfuse/database` — Langfuse PostgreSQL connection string
  - `prod/langfuse/clickhouse` — auto-generated password

Export interface:
```typescript
export interface DataStackOutputs {
  database: {
    instance: rds.IDatabaseInstance;
    secret: secretsmanager.ISecret;
    endpoint: string;
    port: string;
  };
  redis: {
    endpoint: string;
    port: number;
  };
  fileSystem: efs.IFileSystem;
  buckets: {
    terraformState: s3.IBucket;
    backups: s3.IBucket;
    artifacts: s3.IBucket;
    langfuseEvents: s3.IBucket;
    langfuseMedia: s3.IBucket;
  };
  secrets: Record<string, secretsmanager.ISecret>;
}
```

**Step 4: Run test to verify it passes**

```bash
cd /Users/andymini/ai/ai-dev-platform/aws-production-cdk
npx jest test/stacks/data-stack.test.ts --no-coverage
```

Expected: All tests PASS.

**Step 5: Commit**

```bash
git add aws-production-cdk/lib/stacks/data-stack.ts aws-production-cdk/test/stacks/data-stack.test.ts
git commit -m "feat: add DataStack — RDS, ElastiCache, EFS, S3, Secrets, DynamoDB"
```

---

## Task 5: PlatformStack — ECS Cluster, ALB, ACM, IAM

**Files:**
- Create: `aws-production-cdk/lib/stacks/platform-stack.ts`
- Create: `aws-production-cdk/test/stacks/platform-stack.test.ts`

**Reference:** `aws-production/terraform/modules/{ecs,alb,acm,iam}/main.tf`, `aws-production/terraform/services.tf`

**Step 1: Write the failing test**

```typescript
// aws-production-cdk/test/stacks/platform-stack.test.ts
import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { NetworkStack } from '../../lib/stacks/network-stack';
import { DataStack } from '../../lib/stacks/data-stack';
import { PlatformStack } from '../../lib/stacks/platform-stack';
import { productionConfig } from '../../lib/config/environment';

describe('PlatformStack', () => {
  let template: Template;

  beforeAll(() => {
    const app = new cdk.App();
    const network = new NetworkStack(app, 'TestNetwork', {
      env: { account: '123456789012', region: 'us-west-2' },
      config: productionConfig,
    });
    const data = new DataStack(app, 'TestData', {
      env: { account: '123456789012', region: 'us-west-2' },
      config: productionConfig,
      network: network.outputs,
    });
    const platform = new PlatformStack(app, 'TestPlatform', {
      env: { account: '123456789012', region: 'us-west-2' },
      config: productionConfig,
      network: network.outputs,
      data: data.outputs,
    });
    template = Template.fromStack(platform);
  });

  test('creates ECS cluster with container insights', () => {
    template.hasResourceProperties('AWS::ECS::Cluster', {
      ClusterSettings: [{ Name: 'containerInsights', Value: 'enabled' }],
    });
  });

  test('creates internal ALB', () => {
    template.hasResourceProperties('AWS::ElasticLoadBalancingV2::LoadBalancer', {
      Scheme: 'internal',
      Type: 'application',
    });
  });

  test('creates HTTPS listener on port 443', () => {
    template.hasResourceProperties('AWS::ElasticLoadBalancingV2::Listener', {
      Port: 443,
      Protocol: 'HTTPS',
    });
  });

  test('creates ACM certificate', () => {
    template.resourceCountIs('AWS::CertificateManager::Certificate', 1);
  });

  test('creates 4 target groups (Coder, LiteLLM, KeyProvisioner, Langfuse)', () => {
    template.resourceCountIs('AWS::ElasticLoadBalancingV2::TargetGroup', 4);
  });

  test('creates Coder ECS service', () => {
    template.hasResourceProperties('AWS::ECS::Service', {
      DesiredCount: 1,
      LaunchType: Match.absent(),
    });
  });

  test('creates LiteLLM ECS service with 2 replicas', () => {
    template.hasResourceProperties('AWS::ECS::Service', {
      DesiredCount: 2,
    });
  });

  test('creates shared execution role with ECR and Secrets access', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: Match.objectLike({
        Statement: Match.arrayWith([
          Match.objectLike({
            Principal: { Service: 'ecs-tasks.amazonaws.com' },
          }),
        ]),
      }),
    });
  });

  test('creates SSM parameters for workspace bridge', () => {
    template.hasResourceProperties('AWS::SSM::Parameter', {
      Name: '/coder-production/cluster-arn',
    });
  });
});
```

**Step 2: Run test to verify it fails**

```bash
cd /Users/andymini/ai/ai-dev-platform/aws-production-cdk
npx jest test/stacks/platform-stack.test.ts --no-coverage
```

Expected: FAIL.

**Step 3: Implement PlatformStack shell (cluster, ALB, ACM, IAM — no service constructs yet)**

Create `aws-production-cdk/lib/stacks/platform-stack.ts` with:

- **ECS Cluster:** Fargate + Fargate Spot capacity providers, container insights
- **ACM Certificate:** `{domain}` + `*.{domain}` SAN, DNS validation if hostedZoneId set
- **Internal ALB:** HTTPS:443, sg-alb, private app subnets
- **Listener Rules:** Host-based routing (configured after constructs are added)
- **IAM Roles:**
  - Shared execution role: ECR pull, Secrets Manager `prod/*`, CloudWatch Logs
  - ECS Exec policy: SSM for debugging
  - Coder task role: Secrets, S3 state, ECS RunTask, EFS access points, IAM PassRole
  - LiteLLM task role: Bedrock InvokeModel, Secrets (master key + Anthropic)
  - Key Provisioner task role: Secrets (provisioner + master key)
  - Langfuse task role: Secrets, S3 events/media
  - Workspace task role: CloudWatch Logs only
  - AEM Workspace task role: CloudWatch Logs + S3 artifacts read

- **SSM Parameters (CDK→Terraform bridge):**
  - `/coder-production/cluster-arn`
  - `/coder-production/cluster-name`
  - `/coder-production/task-execution-role-arn`
  - `/coder-production/workspace-task-role-arn`
  - `/coder-production/workspace-sg-id`
  - `/coder-production/private-subnet-ids` (comma-separated)
  - `/coder-production/efs-id`
  - `/coder-production/alb-listener-arn`

**Step 4: Run test to verify it passes**

```bash
cd /Users/andymini/ai/ai-dev-platform/aws-production-cdk
npx jest test/stacks/platform-stack.test.ts --no-coverage
```

Expected: PASS.

**Step 5: Commit**

```bash
git add aws-production-cdk/lib/stacks/platform-stack.ts aws-production-cdk/test/stacks/platform-stack.test.ts
git commit -m "feat: add PlatformStack — ECS cluster, ALB, ACM, IAM roles, SSM bridge"
```

---

## Task 6: CoderService Construct

**Files:**
- Create: `aws-production-cdk/lib/constructs/coder-service.ts`
- Modify: `aws-production-cdk/lib/stacks/platform-stack.ts` (instantiate construct)

**Reference:** `aws-production/terraform/services.tf` — Coder section

**Step 1: Write the construct**

Create `aws-production-cdk/lib/constructs/coder-service.ts`:

- Fargate task definition: 1 vCPU (1024), 4 GB memory
- Container: Coder image, port 7080
- EFS volume mount: `/home/coder/.config/coderv2`
- Environment variables:
  - `CODER_ACCESS_URL=https://coder.{domain}`
  - `CODER_WILDCARD_ACCESS_URL=*.{domain}`
  - `CODER_HTTP_ADDRESS=0.0.0.0:7080`
  - `CODER_SECURE_AUTH_COOKIE=true`
  - `CODER_OIDC_ISSUER_URL` from config
  - `CODER_OIDC_ALLOW_SIGNUPS=true`
  - `CODER_OIDC_SCOPES=openid,profile,email`
  - `CODER_TELEMETRY=false`
  - `CODER_CACHE_DIRECTORY=/home/coder/.cache/coder`
- Secrets from Secrets Manager:
  - `CODER_PG_CONNECTION_URL` ← `prod/coder/database`
  - `CODER_OIDC_CLIENT_ID` ← `prod/coder/oidc` field `client_id`
  - `CODER_OIDC_CLIENT_SECRET` ← `prod/coder/oidc` field `client_secret`
- Fargate service: desired count 1, Fargate (not Spot — management plane)
- Cloud Map: `coder.coder-production.local`
- ALB target group: port 7080, health check `/api/v2/buildinfo`
- ALB listener rule: host `coder.{domain}`, priority 100
- ALB listener rule: host `*.{domain}`, priority 500 (wildcard for workspace apps)
- Task role: coderTaskRole
- Execution role: shared

**Step 2: Wire into PlatformStack**

Add `new CoderService(this, 'Coder', { ... })` to platform-stack.ts.

**Step 3: Run tests**

```bash
cd /Users/andymini/ai/ai-dev-platform/aws-production-cdk
npx jest test/stacks/platform-stack.test.ts --no-coverage
```

Expected: Existing tests still pass (Coder service now creates the service + target group resources).

**Step 4: Commit**

```bash
git add aws-production-cdk/lib/constructs/coder-service.ts aws-production-cdk/lib/stacks/platform-stack.ts
git commit -m "feat: add CoderService construct — task def, EFS, OIDC, ALB routing"
```

---

## Task 7: LiteLLMService Construct

**Files:**
- Create: `aws-production-cdk/lib/constructs/litellm-service.ts`
- Create: `aws-production-cdk/litellm/config.yaml` (copy from aws-production + custom LLM models)
- Modify: `aws-production-cdk/lib/stacks/platform-stack.ts` (instantiate)

**Reference:** `aws-production/terraform/services.tf` — LiteLLM section, `coder-poc/litellm/config.yaml`

**Step 1: Copy and update LiteLLM config**

Copy `aws-production/litellm/config.yaml` to `aws-production-cdk/litellm/config.yaml` and add the custom LLM models (from the h-chat corporate proxy work done earlier: custom-gpt-4o, custom-gemini-2.5-flash, custom-claude-haiku, etc.).

**Step 2: Write the construct**

Create `aws-production-cdk/lib/constructs/litellm-service.ts`:

- Fargate task definition: 0.5 vCPU (512), 2 GB memory
- Container: LiteLLM image, port 4000
- Command: `["--config", "/app/config.yaml", "--port", "4000"]`
- Config mounted as CDK Asset (S3 → ECS task):
  - `litellm/config.yaml` → `/app/config.yaml`
  - Note: For config files, use `ecs.ContainerDefinition.addMountPoints` with EFS or embed as env var.
  - Practical approach: Store config in Secrets Manager as a JSON blob, or use EFS path.
  - Simplest: Bake config into a custom Docker image layer, or use S3 init container.
  - Recommended for production: Store in S3, use init container to download. Or mount EFS.
- Environment:
  - `AWS_REGION_NAME=us-west-2`
  - `DEFAULT_ENFORCEMENT_LEVEL=standard`
  - `GUARDRAILS_ENABLED=true`
  - `LANGFUSE_HOST=http://langfuse-web.coder-production.local:3000`
  - `LITELLM_ANTHROPIC_DISABLE_URL_SUFFIX=true` (for custom Claude endpoints)
  - `CUSTOM_LLM_API_BASE` from config
  - `CUSTOM_LLM_CLAUDE_API_BASE={customLlmApiBase}/claude/messages`
- Secrets from Secrets Manager:
  - `DATABASE_URL` ← `prod/litellm/database`
  - `LITELLM_MASTER_KEY` ← `prod/litellm/master-key`
  - `ANTHROPIC_API_KEY` ← `prod/litellm/anthropic-api-key`
  - `CUSTOM_LLM_API_KEY` ← new secret `prod/custom-llm/api-key`
  - `LANGFUSE_PUBLIC_KEY` ← `prod/langfuse/api-keys` field `public_key`
  - `LANGFUSE_SECRET_KEY` ← `prod/langfuse/api-keys` field `secret_key`
- Fargate service: desired count 2, Fargate (not Spot — AI gateway must be reliable)
- Cloud Map: `litellm.coder-production.local`
- ALB target group: port 4000, health check `/health/readiness`
- ALB listener rule: host `ai.{domain}`, priority 400
- Task role: litellmTaskRole (with Bedrock InvokeModel)
- Execution role: shared

**Step 3: Wire into PlatformStack**

Add `new LiteLLMService(this, 'LiteLLM', { ... })` to platform-stack.ts.

**Step 4: Run tests**

```bash
cd /Users/andymini/ai/ai-dev-platform/aws-production-cdk
npx jest --no-coverage
```

Expected: All tests pass.

**Step 5: Commit**

```bash
git add aws-production-cdk/lib/constructs/litellm-service.ts aws-production-cdk/litellm/ aws-production-cdk/lib/stacks/platform-stack.ts
git commit -m "feat: add LiteLLMService construct — Bedrock IAM, config, custom LLM models"
```

---

## Task 8: KeyProvisionerService Construct

**Files:**
- Create: `aws-production-cdk/lib/constructs/key-provisioner-service.ts`
- Modify: `aws-production-cdk/lib/stacks/platform-stack.ts` (instantiate)

**Reference:** `aws-production/terraform/services.tf` — Key Provisioner section

**Step 1: Write the construct**

Create `aws-production-cdk/lib/constructs/key-provisioner-service.ts`:

- Fargate task definition: 0.25 vCPU (256), 512 MB memory
- Container: Key Provisioner image, port 8100
- Environment:
  - `LITELLM_URL=http://litellm.coder-production.local:4000`
  - `CODER_URL=https://coder.{domain}`
  - `PORT=8100`
- Secrets:
  - `LITELLM_MASTER_KEY` ← `prod/litellm/master-key`
  - `PROVISIONER_SECRET` ← `prod/key-provisioner/secret`
- Fargate service: desired count 1, Fargate
- Cloud Map: `key-provisioner.coder-production.local`
- ALB target group: port 8100, health check `/health`
- ALB listener rule: host `admin.{domain}`, priority 200
  - With OIDC authenticate action (Azure AD) before forward — admin UI requires auth
- Task role: keyProvisionerTaskRole
- Execution role: shared

**Step 2: Wire into PlatformStack, run tests**

```bash
cd /Users/andymini/ai/ai-dev-platform/aws-production-cdk
npx jest --no-coverage
```

**Step 3: Commit**

```bash
git add aws-production-cdk/lib/constructs/key-provisioner-service.ts aws-production-cdk/lib/stacks/platform-stack.ts
git commit -m "feat: add KeyProvisionerService construct — admin UI with OIDC auth"
```

---

## Task 9: ObservabilityStack — Langfuse + ClickHouse

**Files:**
- Create: `aws-production-cdk/lib/stacks/observability-stack.ts`
- Create: `aws-production-cdk/lib/constructs/langfuse-service.ts`
- Create: `aws-production-cdk/test/stacks/observability-stack.test.ts`

**Reference:** `aws-production/terraform/services.tf` — ClickHouse, Langfuse Web, Langfuse Worker sections

**Step 1: Write the failing test**

```typescript
// aws-production-cdk/test/stacks/observability-stack.test.ts
import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { NetworkStack } from '../../lib/stacks/network-stack';
import { DataStack } from '../../lib/stacks/data-stack';
import { PlatformStack } from '../../lib/stacks/platform-stack';
import { ObservabilityStack } from '../../lib/stacks/observability-stack';
import { productionConfig } from '../../lib/config/environment';

describe('ObservabilityStack', () => {
  let template: Template;

  beforeAll(() => {
    const app = new cdk.App();
    const network = new NetworkStack(app, 'Net', {
      env: { account: '123456789012', region: 'us-west-2' },
      config: productionConfig,
    });
    const data = new DataStack(app, 'Data', {
      env: { account: '123456789012', region: 'us-west-2' },
      config: productionConfig,
      network: network.outputs,
    });
    const platform = new PlatformStack(app, 'Platform', {
      env: { account: '123456789012', region: 'us-west-2' },
      config: productionConfig,
      network: network.outputs,
      data: data.outputs,
    });
    const obs = new ObservabilityStack(app, 'Obs', {
      env: { account: '123456789012', region: 'us-west-2' },
      config: productionConfig,
      network: network.outputs,
      data: data.outputs,
      platform: platform.outputs,
    });
    template = Template.fromStack(obs);
  });

  test('creates 3 ECS task definitions (ClickHouse, Langfuse Web, Langfuse Worker)', () => {
    template.resourceCountIs('AWS::ECS::TaskDefinition', 3);
  });

  test('creates 3 ECS services', () => {
    template.resourceCountIs('AWS::ECS::Service', 3);
  });

  test('creates Langfuse ALB target group', () => {
    template.hasResourceProperties('AWS::ElasticLoadBalancingV2::TargetGroup', {
      Port: 3000,
      Protocol: 'HTTP',
    });
  });
});
```

**Step 2: Run test to verify it fails**

```bash
cd /Users/andymini/ai/ai-dev-platform/aws-production-cdk
npx jest test/stacks/observability-stack.test.ts --no-coverage
```

Expected: FAIL.

**Step 3: Implement LangfuseService construct**

Create `aws-production-cdk/lib/constructs/langfuse-service.ts`:

**ClickHouse:**
- Task: 1 vCPU / 4 GB, ports 8123 (HTTP) + 9000 (native)
- Image: clickhouse/clickhouse-server:24-alpine
- EFS mount: `/var/lib/clickhouse`
- Environment: `CLICKHOUSE_DB=langfuse`, `CLICKHOUSE_USER=langfuse`
- Secrets: `CLICKHOUSE_PASSWORD` ← `prod/langfuse/clickhouse`
- Cloud Map: `clickhouse.coder-production.local`
- No ALB (internal only)

**Langfuse Web:**
- Task: 1 vCPU / 2 GB, port 3000
- Image: langfuse/langfuse:latest
- Environment:
  - `NEXTAUTH_URL=https://langfuse.{domain}`
  - `NODE_ENV=production`
  - `CLICKHOUSE_URL=http://clickhouse.coder-production.local:8123`
  - `CLICKHOUSE_MIGRATION_URL=clickhouse://clickhouse.coder-production.local:9000`
  - `REDIS_CONNECTION_STRING` (from ElastiCache endpoint)
  - `LANGFUSE_S3_EVENT_UPLOAD_BUCKET`
  - `LANGFUSE_S3_MEDIA_UPLOAD_BUCKET`
- Secrets: auth keys, DB URL, ClickHouse password
- Cloud Map: `langfuse-web.coder-production.local`
- ALB: host `langfuse.{domain}`, priority 300, target 3000, health `/api/public/health`

**Langfuse Worker:**
- Task: 0.5 vCPU / 1 GB, port 3030
- Same image, same env/secrets as Web
- Extra env: `LANGFUSE_WORKER_PORT=3030`
- Cloud Map: `langfuse-worker.coder-production.local`
- No ALB (background processing)

**Step 4: Implement ObservabilityStack**

Create `aws-production-cdk/lib/stacks/observability-stack.ts` that instantiates the LangfuseService construct.

**Step 5: Run tests**

```bash
cd /Users/andymini/ai/ai-dev-platform/aws-production-cdk
npx jest --no-coverage
```

Expected: All tests pass.

**Step 6: Commit**

```bash
git add aws-production-cdk/lib/stacks/observability-stack.ts aws-production-cdk/lib/constructs/langfuse-service.ts aws-production-cdk/test/stacks/observability-stack.test.ts
git commit -m "feat: add ObservabilityStack — ClickHouse, Langfuse Web/Worker"
```

---

## Task 10: App Entry Point — Wire All Stacks

**Files:**
- Modify: `aws-production-cdk/bin/app.ts`

**Step 1: Wire all stacks in dependency order**

```typescript
// aws-production-cdk/bin/app.ts
import * as cdk from 'aws-cdk-lib';
import { NetworkStack } from '../lib/stacks/network-stack';
import { DataStack } from '../lib/stacks/data-stack';
import { PlatformStack } from '../lib/stacks/platform-stack';
import { ObservabilityStack } from '../lib/stacks/observability-stack';
import { productionConfig } from '../lib/config/environment';

const app = new cdk.App();

const env = {
  account: productionConfig.account || process.env.CDK_DEFAULT_ACCOUNT,
  region: productionConfig.region,
};

const network = new NetworkStack(app, 'NetworkStack', { env, config: productionConfig });
const data = new DataStack(app, 'DataStack', { env, config: productionConfig, network: network.outputs });
const platform = new PlatformStack(app, 'PlatformStack', { env, config: productionConfig, network: network.outputs, data: data.outputs });
const observability = new ObservabilityStack(app, 'ObservabilityStack', { env, config: productionConfig, network: network.outputs, data: data.outputs, platform: platform.outputs });

// Explicit dependencies (CDK infers from cross-stack refs, but be explicit)
data.addDependency(network);
platform.addDependency(data);
observability.addDependency(platform);

app.synth();
```

**Step 2: Full synth of all stacks**

```bash
cd /Users/andymini/ai/ai-dev-platform/aws-production-cdk
npx cdk synth --no-staging 2>&1 | tail -20
```

Expected: 4 CloudFormation templates generated without errors.

**Step 3: Run all tests**

```bash
cd /Users/andymini/ai/ai-dev-platform/aws-production-cdk
npx jest --no-coverage
```

Expected: All tests pass.

**Step 4: List all stacks**

```bash
cd /Users/andymini/ai/ai-dev-platform/aws-production-cdk
npx cdk list
```

Expected output:
```
NetworkStack
DataStack
PlatformStack
ObservabilityStack
```

**Step 5: Commit**

```bash
git add aws-production-cdk/bin/app.ts
git commit -m "feat: wire all CDK stacks in app entry point"
```

---

## Task 11: Final Verification — Diff Against Terraform

**Step 1: Generate CloudFormation for each stack**

```bash
cd /Users/andymini/ai/ai-dev-platform/aws-production-cdk
npx cdk synth NetworkStack > /tmp/cdk-network.yaml
npx cdk synth DataStack > /tmp/cdk-data.yaml
npx cdk synth PlatformStack > /tmp/cdk-platform.yaml
npx cdk synth ObservabilityStack > /tmp/cdk-observability.yaml
```

**Step 2: Verify resource counts**

Manually check that the generated CloudFormation includes:
- [ ] 1 VPC, 6 subnets, 1 IGW, 1 NAT, 6+ security groups, 10+ VPC endpoints
- [ ] 1 RDS instance, 1 Redis replication group, 1 EFS, 5 S3 buckets, 1 DynamoDB table, 11 secrets
- [ ] 1 ECS cluster, 1 ALB, 1 ACM cert, 4 target groups, 5+ listener rules, 8 IAM roles
- [ ] 3 ECS task defs + 3 services (ClickHouse, Langfuse Web, Worker)
- [ ] 8 SSM parameters (CDK→Terraform bridge)

**Step 3: Run full test suite**

```bash
cd /Users/andymini/ai/ai-dev-platform/aws-production-cdk
npx jest --coverage
```

Expected: All tests pass, coverage report generated.

**Step 4: Final commit**

```bash
git add -A aws-production-cdk/
git commit -m "feat: complete AWS CDK production infrastructure — 4 stacks, 12 files"
```
