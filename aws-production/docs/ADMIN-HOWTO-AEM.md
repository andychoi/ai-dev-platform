# AEM Workspace — Admin How-To (Production)

## Overview

The AEM workspace template provides AEM 6.5 development environments on ECS Fargate.
The proprietary AEM quickstart JAR and license are delivered via S3 — admin uploads once,
workspaces download on first start, and EFS persistence means subsequent starts skip the download.

---

## S3 Artifact Upload

### Prerequisites

- AWS CLI configured with write access to the artifacts bucket
- AEM quickstart JAR from Adobe Software Distribution
- AEM license.properties from your license agreement

### Upload Commands

```bash
# Upload AEM quickstart JAR (~1.5 GB)
aws s3 cp aem-quickstart.jar s3://ARTIFACTS_BUCKET/aem/aem-quickstart.jar

# Upload license file
aws s3 cp license.properties s3://ARTIFACTS_BUCKET/aem/license.properties

# Verify uploads
aws s3 ls s3://ARTIFACTS_BUCKET/aem/
```

Replace `ARTIFACTS_BUCKET` with your actual bucket name (e.g., `coder-production-artifacts`).

### Access Control

AEM workspace tasks have an IAM role (`aem-workspace-task-role`) that grants:
- `s3:GetObject` on `artifacts/*` (scoped to `aem/*` prefix)
- `s3:ListBucket` with `aem/*` prefix condition

Workspaces **cannot** access other S3 prefixes. Regular contractor workspaces have **no** S3 access.

---

## Image Build & Deploy

### Build the Docker Image

```bash
cd aws-production/templates/aem-workspace/build

# Build locally
docker build -t aem-workspace:latest .

# Tag for ECR
docker tag aem-workspace:latest ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/aem-workspace:latest

# Login to ECR
aws ecr get-login-password --region REGION | docker login --username AWS --password-stdin ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com

# Push to ECR
docker push ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/aem-workspace:latest
```

### Push Template to Coder

```bash
cd aws-production/templates/aem-workspace
coder templates push aem-workspace --directory . --yes
```

### After Image Update

Existing workspaces continue using the old image. To pick up changes:
1. Push the new image to ECR
2. Push the updated template to Coder
3. Users must delete and recreate their workspaces (workspace immutability rule)

---

## Fargate Resource Sizing

AEM is memory-intensive. Choose sizing based on the workload:

| Configuration | CPU | Memory | Use Case |
|---------------|-----|--------|----------|
| Author only (standard) | 4 vCPU | 8 GB | Daily AEM development |
| Author only (large) | 4 vCPU | 16 GB | Large AEM projects, heavy builds |
| Author + Publisher | 8 vCPU | 16 GB | Full publishing pipeline |
| Author + Publisher (perf) | 8 vCPU | 30 GB | Large projects with both instances |

### JVM Heap Guidelines

| Component | Minimum | Recommended | Maximum |
|-----------|---------|-------------|---------|
| AEM Author | 2 GB | 3 GB | 4 GB |
| AEM Publisher | 512 MB | 1 GB | 2 GB |
| Maven builds | 512 MB | 1 GB | - |
| OS + code-server | ~1 GB | ~1.5 GB | - |

**Rule of thumb:** Total Fargate memory >= Author heap + Publisher heap + 3 GB (OS, Maven, code-server).

### First Start Time

| Phase | Duration | Notes |
|-------|----------|-------|
| S3 JAR download | 30-60s | ~1.5 GB over VPC endpoint |
| AEM crx-quickstart unpack | 5-10 min | First start only |
| AEM Author ready | 3-5 min | Subsequent starts |
| Total first start | ~10-15 min | AEM Author ready |
| Total subsequent start | ~3-5 min | JAR + crx-quickstart on EFS |

---

## Troubleshooting

### S3 Download Failure

**Symptom:** Startup logs show "AEM QUICKSTART JAR NOT FOUND IN S3"

**Diagnosis:**
```bash
# Check if files exist in S3
aws s3 ls s3://ARTIFACTS_BUCKET/aem/

# Check IAM role permissions (from the Fargate task)
# Look at CloudWatch logs for the workspace task
```

**Fixes:**
1. Verify files are uploaded to the correct bucket and prefix (`aem/`)
2. Verify the `artifacts_bucket_name` template variable matches the actual bucket
3. Verify the AEM workspace task role has `s3:GetObject` permission
4. Check VPC endpoint for S3 is configured (tasks in private subnets need it)

### AEM Out of Memory (OOM)

**Symptom:** AEM Author crashes after starting, CloudWatch shows OOM kill

**Diagnosis:**
```bash
# Check Fargate task stop reason
aws ecs describe-tasks --cluster CLUSTER --tasks TASK_ARN --query 'tasks[0].stoppedReason'
```

**Fixes:**
1. Increase memory allocation (template parameter `memory_gb`)
2. Reduce JVM heap if it's too close to the container limit
3. Ensure `Author JVM heap + Publisher JVM heap + 3GB < total memory`

### Slow First Start

**Symptom:** AEM Author takes >15 minutes on first start

**Expected:** First start unpacks crx-quickstart (~5 GB). This is normal.

**Fixes:**
1. Check EFS throughput mode (use "elastic" for burst workloads)
2. Ensure Fargate task has sufficient CPU (AEM unpacking is CPU-intensive)
3. Subsequent starts should be 3-5 minutes (crx-quickstart persists on EFS)

### CRX Repository Corruption

**Symptom:** AEM fails to start with repository errors after abrupt shutdown

**Prevention:**
- The template includes a graceful shutdown script with 120s `stopTimeout`
- AEM gets SIGTERM first, with 60s to flush before SIGKILL
- Never force-stop workspaces unless necessary

**Recovery:**
1. Delete the corrupted `crx-quickstart` directory
2. Restart the workspace (AEM will unpack fresh from JAR)
3. Content/code changes in the project are safe (they're in git, not CRX)

### License Missing

**Symptom:** AEM starts but shows license error page

**Fix:** Upload `license.properties` to S3:
```bash
aws s3 cp license.properties s3://ARTIFACTS_BUCKET/aem/license.properties
```
Then restart the workspace. The file will be downloaded to EFS.
