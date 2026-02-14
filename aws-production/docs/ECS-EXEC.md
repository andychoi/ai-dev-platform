# ECS Exec — Direct Fargate Container Access

Connect to Fargate containers via interactive shell without the Coder admin UI.

## Prerequisites

### AWS CLI

ECS Exec requires the [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html):

```bash
# macOS
brew install --cask session-manager-plugin

# Verify
session-manager-plugin --version
```

### IAM Permissions (Your Local AWS User/Role)

Your AWS identity needs these permissions to *initiate* ECS Exec sessions:

```json
{
  "Effect": "Allow",
  "Action": [
    "ecs:ExecuteCommand",
    "ecs:DescribeTasks"
  ],
  "Resource": "arn:aws:ecs:us-west-2:ACCOUNT_ID:task/coder-production-cluster/*"
}
```

> **Note:** The Terraform only configures the *task roles* (container-side permissions).
> Your local IAM user/role must separately have `ecs:ExecuteCommand`.

---

## Quick Reference

### List Running Tasks

```bash
# All tasks for a service
aws ecs list-tasks \
  --cluster coder-production-cluster \
  --service-name coder-production-coder \
  --region us-west-2

# All running tasks in the cluster
aws ecs list-tasks \
  --cluster coder-production-cluster \
  --region us-west-2
```

### Connect to a Container

```bash
aws ecs execute-command \
  --cluster coder-production-cluster \
  --task <TASK_ID> \
  --container <CONTAINER_NAME> \
  --interactive \
  --command "/bin/bash"
```

The `<TASK_ID>` is the full ARN or the short ID (e.g., `a1b2c3d4e5f6`).

---

## Service Quick Reference

| Service Name | Container Name | Default Shell |
|---|---|---|
| `coder-production-coder` | `coder` | `/bin/bash` |
| `coder-production-litellm` | `litellm` | `/bin/sh` |
| `coder-production-key-provisioner` | `key-provisioner` | `/bin/sh` |
| `coder-production-clickhouse` | `clickhouse` | `/bin/bash` |
| `coder-production-langfuse-web` | `langfuse-web` | `/bin/sh` |
| `coder-production-langfuse-worker` | `langfuse-worker` | `/bin/sh` |

> **Tip:** If `/bin/bash` fails, try `/bin/sh`. Alpine-based images only have `sh`.

---

## Common Operations

### Coder Server

```bash
# Get task ID
TASK_ID=$(aws ecs list-tasks \
  --cluster coder-production-cluster \
  --service-name coder-production-coder \
  --region us-west-2 \
  --query 'taskArns[0]' --output text)

# Interactive shell
aws ecs execute-command \
  --cluster coder-production-cluster \
  --task "$TASK_ID" \
  --container coder \
  --interactive \
  --command "/bin/bash"
```

### LiteLLM — Check DB Connectivity

```bash
TASK_ID=$(aws ecs list-tasks \
  --cluster coder-production-cluster \
  --service-name coder-production-litellm \
  --region us-west-2 \
  --query 'taskArns[0]' --output text)

aws ecs execute-command \
  --cluster coder-production-cluster \
  --task "$TASK_ID" \
  --container litellm \
  --interactive \
  --command "/bin/sh -c 'pg_isready -h \$DATABASE_HOST'"
```

### LiteLLM — Check Upstream API

```bash
aws ecs execute-command \
  --cluster coder-production-cluster \
  --task "$TASK_ID" \
  --container litellm \
  --interactive \
  --command "/bin/sh -c 'curl -s http://localhost:4000/health'"
```

### Key Provisioner — Check Config

```bash
TASK_ID=$(aws ecs list-tasks \
  --cluster coder-production-cluster \
  --service-name coder-production-key-provisioner \
  --region us-west-2 \
  --query 'taskArns[0]' --output text)

aws ecs execute-command \
  --cluster coder-production-cluster \
  --task "$TASK_ID" \
  --container key-provisioner \
  --interactive \
  --command "/bin/sh -c 'env | grep -E \"LITELLM_URL|CODER_URL|PROVISIONER\"'"
```

### ClickHouse — Query Check

```bash
TASK_ID=$(aws ecs list-tasks \
  --cluster coder-production-cluster \
  --service-name coder-production-clickhouse \
  --region us-west-2 \
  --query 'taskArns[0]' --output text)

aws ecs execute-command \
  --cluster coder-production-cluster \
  --task "$TASK_ID" \
  --container clickhouse \
  --interactive \
  --command "/bin/bash -c 'clickhouse-client --query \"SELECT count() FROM system.tables\"'"
```

### Run a One-Off Command (Non-Interactive)

```bash
aws ecs execute-command \
  --cluster coder-production-cluster \
  --task "$TASK_ID" \
  --container coder \
  --command "/bin/sh -c 'cat /etc/os-release'" \
  --interactive
```

> **Note:** The `--interactive` flag is always required by the CLI, even for
> non-interactive commands. The command itself determines interactivity.

---

## Helper Script

Copy-paste this function into your shell for quick access:

```bash
# Usage: ecs-exec <service-short-name> [container] [command]
# Example: ecs-exec coder
# Example: ecs-exec litellm litellm "/bin/sh -c 'curl localhost:4000/health'"
ecs-exec() {
  local CLUSTER="coder-production-cluster"
  local REGION="us-west-2"
  local SERVICE="coder-production-${1:?Usage: ecs-exec <service> [container] [command]}"
  local CONTAINER="${2:-$1}"
  local CMD="${3:-/bin/sh}"

  local TASK_ID
  TASK_ID=$(aws ecs list-tasks \
    --cluster "$CLUSTER" \
    --service-name "$SERVICE" \
    --region "$REGION" \
    --query 'taskArns[0]' --output text)

  if [ "$TASK_ID" = "None" ] || [ -z "$TASK_ID" ]; then
    echo "No running tasks found for service: $SERVICE"
    return 1
  fi

  echo "Connecting to $SERVICE (task: ${TASK_ID##*/})..."
  aws ecs execute-command \
    --cluster "$CLUSTER" \
    --task "$TASK_ID" \
    --container "$CONTAINER" \
    --region "$REGION" \
    --interactive \
    --command "$CMD"
}
```

**Examples:**

```bash
ecs-exec coder                    # Shell into Coder
ecs-exec litellm                  # Shell into LiteLLM
ecs-exec key-provisioner          # Shell into Key Provisioner
ecs-exec clickhouse clickhouse    # Shell into ClickHouse
ecs-exec langfuse-web             # Shell into Langfuse Web
```

---

## Terraform Changes

ECS Exec is enabled by three Terraform components:

### 1. VPC Endpoint (`modules/vpc/main.tf`)

The `ssmmessages` VPC interface endpoint keeps SSM traffic within the VPC
instead of routing through the NAT gateway:

```hcl
ssmmessages = "com.amazonaws.${data.aws_region.current.name}.ssmmessages"
```

### 2. IAM Policy (`modules/iam/main.tf`)

A shared `ecs-exec` policy grants SSM Messages permissions and is attached
to every platform task role (Coder, LiteLLM, Key Provisioner, Authentik, Langfuse):

```hcl
actions = [
  "ssmmessages:CreateControlChannel",
  "ssmmessages:CreateDataChannel",
  "ssmmessages:OpenControlChannel",
  "ssmmessages:OpenDataChannel",
]
```

### 3. Service Flag (`services.tf`)

Each `aws_ecs_service` resource has:

```hcl
enable_execute_command = true
```

This tells Fargate to inject the SSM agent sidecar into every task launched
by that service.

---

## Troubleshooting

### "TargetNotConnectedException"

The SSM agent inside the task hasn't connected yet or lost connection.

```bash
# Check if the task has ECS Exec enabled
aws ecs describe-tasks \
  --cluster coder-production-cluster \
  --tasks "$TASK_ID" \
  --region us-west-2 \
  --query 'tasks[0].enableExecuteCommand'
# Should return: true

# Check managed agent status
aws ecs describe-tasks \
  --cluster coder-production-cluster \
  --tasks "$TASK_ID" \
  --region us-west-2 \
  --query 'tasks[0].containers[*].managedAgents'
```

If `enableExecuteCommand` is `false`, the task was launched before the
Terraform change. Force a new deployment:

```bash
aws ecs update-service \
  --cluster coder-production-cluster \
  --service coder-production-coder \
  --force-new-deployment \
  --region us-west-2
```

### "An error occurred (InvalidParameterException)"

Usually means the Session Manager Plugin is not installed:

```bash
session-manager-plugin --version
# If not found: brew install --cask session-manager-plugin
```

### "AccessDeniedException"

Your local IAM user/role is missing `ecs:ExecuteCommand`. This is separate
from the task role permissions configured in Terraform.

### Container Exits Immediately

Some containers (like LiteLLM) may not have `/bin/bash`. Use `/bin/sh`:

```bash
aws ecs execute-command \
  --cluster coder-production-cluster \
  --task "$TASK_ID" \
  --container litellm \
  --interactive \
  --command "/bin/sh"
```

---

## Security Considerations

- ECS Exec sessions are logged to CloudWatch Logs (via Container Insights)
- Consider restricting `ecs:ExecuteCommand` to specific IAM roles (e.g., ops team only)
- ECS Exec is intentionally **not** enabled for workspace tasks — use `coder ssh` for workspace access
- All SSM traffic routes through the VPC endpoint (never traverses the public internet)

---

## Alternative Access Methods

| Method | Interactive? | Use Case |
|---|---|---|
| **ECS Exec** | Yes | Debug platform services |
| **CloudWatch Logs** | No (read-only) | View logs without shell access |
| **`coder ssh`** | Yes (workspaces only) | Developer workspace access |

### CloudWatch Logs

```bash
aws logs tail /ecs/coder-production/coder --follow --region us-west-2
```
