# =============================================================================
# Docker-Enabled Workspace Template — ECS EC2 (Production)
#
# Extends the standard contractor-workspace with:
#   - EC2 capacity provider (instead of Fargate) for Docker support
#   - Rootless DinD sidecar container in the ECS task
#   - Auth init container (defense-in-depth authorization)
#   - Terraform precondition on "docker-users" group membership
#
# See: coder-poc/docs/DOCKER-DEV.md Section 16-17
# =============================================================================

terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# =============================================================================
# INFRASTRUCTURE VARIABLES
# =============================================================================

variable "ecs_cluster_arn" {
  description = "ARN of the ECS cluster (must have EC2 Docker capacity provider)"
  type        = string
}

variable "ec2_docker_capacity_provider" {
  description = "Name of the EC2 Docker capacity provider"
  type        = string
}

variable "efs_file_system_id" {
  description = "EFS file system ID for persistent workspace storage"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for workspace task networking"
  type        = list(string)
}

variable "workspace_security_group_id" {
  description = "Security group ID for workspace tasks"
  type        = string
}

variable "task_execution_role_arn" {
  description = "IAM role ARN for ECS task execution"
  type        = string
}

variable "workspace_task_role_arn" {
  description = "IAM role ARN for workspace task"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "log_group_name" {
  description = "CloudWatch log group for workspace tasks"
  type        = string
  default     = "/ecs/coder-production/docker-workspaces"
}

variable "auth_check_image" {
  description = "ECR image URI for the auth-check init container"
  type        = string
}

variable "workspace_image" {
  description = "ECR image URI for the Docker-enabled workspace (includes Docker CLI)"
  type        = string
  default     = "docker-workspace:latest"
}

variable "dind_image" {
  description = "Docker-in-Docker rootless image"
  type        = string
  default     = "docker:dind-rootless"
}

# =============================================================================
# WORKSPACE PARAMETERS
# =============================================================================

data "coder_parameter" "cpu_cores" {
  name         = "cpu_cores"
  display_name = "CPU Cores"
  description  = "CPU cores allocated to the workspace (Docker workspaces need more)"
  type         = "number"
  default      = "4"
  mutable      = true

  option { name = "2 Cores (Minimal)";     value = "2" }
  option { name = "4 Cores (Recommended)"; value = "4" }
}

data "coder_parameter" "memory_gb" {
  name         = "memory_gb"
  display_name = "Memory (GB)"
  description  = "RAM allocation (Docker daemon + workspace + user containers)"
  type         = "number"
  default      = "8"
  mutable      = true

  option { name = "8 GB (Standard)";     value = "8" }
  option { name = "16 GB (Performance)"; value = "16" }
}

data "coder_parameter" "git_repo" {
  name         = "git_repo"
  display_name = "Git Repository"
  description  = "Repository to clone on start (optional)"
  type         = "string"
  default      = ""
  mutable      = true
}

data "coder_parameter" "ai_assistant" {
  name         = "ai_assistant"
  display_name = "AI Assistant"
  description  = "AI coding agent"
  type         = "string"
  default      = "all"
  mutable      = true

  option { name = "All Agents (Recommended)"; value = "all" }
  option { name = "Roo Code + OpenCode";      value = "both" }
  option { name = "Claude Code CLI Only";     value = "claude-code" }
  option { name = "None (Disabled)";          value = "none" }
}

data "coder_parameter" "litellm_api_key" {
  name         = "litellm_api_key"
  display_name = "AI API Key"
  description  = "Leave empty for auto-provisioning"
  type         = "string"
  default      = ""
  mutable      = true
}

data "coder_parameter" "ai_model" {
  name         = "ai_model"
  display_name = "AI Model"
  type         = "string"
  default      = "bedrock-claude-haiku"
  mutable      = true

  option { name = "Claude Sonnet 4.5 (Recommended)"; value = "claude-sonnet" }
  option { name = "Claude Haiku 4.5 (Fast)";         value = "claude-haiku" }
  option { name = "Bedrock Claude Sonnet (AWS)";      value = "bedrock-claude-sonnet" }
  option { name = "Bedrock Claude Haiku (AWS)";       value = "bedrock-claude-haiku" }
}

# =============================================================================
# LOCALS
# =============================================================================

locals {
  workspace_name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"

  ai_model_map = {
    "claude-sonnet"         = "claude-sonnet-4-5"
    "claude-haiku"          = "claude-haiku-4-5"
    "bedrock-claude-sonnet" = "bedrock-claude-sonnet"
    "bedrock-claude-haiku"  = "bedrock-claude-haiku"
  }
  ai_model_id = lookup(local.ai_model_map, data.coder_parameter.ai_model.value, "claude-sonnet-4-5")

  # Service discovery endpoints
  litellm_url         = "http://litellm.coder-production.local:4000"
  key_provisioner_url = "http://key-provisioner.coder-production.local:8100"

  # Authorization: user must be in "docker-users" group
  docker_authorized = contains(data.coder_workspace_owner.me.groups, "docker-users")

  # EC2 CPU/memory (not Fargate limits — EC2 is more flexible)
  ec2_cpu = {
    "2" = "2048"
    "4" = "4096"
  }
  ec2_memory = {
    "8"  = "8192"
    "16" = "16384"
  }
}

# =============================================================================
# ACCESS CONTROL: Layer 1 — Terraform Precondition
# Blocks workspace creation if user is not in "docker-users" group.
# =============================================================================

resource "null_resource" "docker_access_check" {
  count = local.docker_authorized ? 0 : 1

  lifecycle {
    precondition {
      condition     = local.docker_authorized
      error_message = <<-EOT
        ACCESS DENIED: Docker workspace requires membership in the "docker-users" group.

        Your groups: ${jsonencode(data.coder_workspace_owner.me.groups)}

        To request access:
          1. Ask your platform admin to add you to "docker-users" in your identity provider
          2. Log out and log back in (group changes sync on login)
          3. Try creating this workspace again

        If you don't need Docker, use the standard contractor-workspace template.
      EOT
    }
  }
}

# =============================================================================
# CODER AGENT
# =============================================================================

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

  startup_script = <<-EOT
    #!/bin/bash
    set -e

    echo "=== Docker-enabled workspace starting ==="

    # Wait for DinD sidecar to be ready
    echo "Waiting for Docker daemon (rootless DinD sidecar)..."
    for attempt in $(seq 1 30); do
      if docker info >/dev/null 2>&1; then
        echo "Docker daemon ready (attempt $attempt)"
        docker version --format 'Client: {{.Client.Version}}, Server: {{.Server.Version}}'
        break
      fi
      [ "$attempt" = "30" ] && echo "WARNING: Docker daemon not ready after 30 attempts"
      sleep 2
    done

    # Clone git repo if specified
    if [ -n "${data.coder_parameter.git_repo.value}" ]; then
      REPO_DIR="$HOME/workspace/$(basename '${data.coder_parameter.git_repo.value}' .git)"
      if [ ! -d "$REPO_DIR" ]; then
        git clone "${data.coder_parameter.git_repo.value}" "$REPO_DIR" 2>/dev/null || true
      fi
    fi

    # Configure AI agents (same as contractor-workspace)
    AI_ASSISTANT="${data.coder_parameter.ai_assistant.value}"
    LITELLM_KEY="${data.coder_parameter.litellm_api_key.value}"
    LITELLM_MODEL="${local.ai_model_id}"
    LITELLM_URL="${local.litellm_url}"
    PROVISIONER_URL="${local.key_provisioner_url}"

    if [ "$AI_ASSISTANT" != "none" ] && [ -z "$LITELLM_KEY" ] && [ -n "$PROVISIONER_SECRET" ]; then
      echo "Auto-provisioning AI API key..."
      for attempt in 1 2 3; do
        RESPONSE=$(curl -sf -X POST "$PROVISIONER_URL/api/v1/keys/workspace" \
          -H "Authorization: Bearer $PROVISIONER_SECRET" \
          -H "Content-Type: application/json" \
          -d "{\"workspace_id\": \"${data.coder_workspace.me.id}\", \"username\": \"${data.coder_workspace_owner.me.name}\", \"workspace_name\": \"${data.coder_workspace.me.name}\"}" \
          2>/dev/null) && break
        sleep 5
      done
      [ -n "$RESPONSE" ] && LITELLM_KEY=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('key',''))" 2>/dev/null || echo "")
    fi

    if [ -n "$LITELLM_KEY" ]; then
      echo "export AI_GATEWAY_URL=$LITELLM_URL" >> "$HOME/.bashrc"
      echo "export OPENAI_API_BASE=$LITELLM_URL/v1" >> "$HOME/.bashrc"
      echo "export OPENAI_API_KEY=$LITELLM_KEY" >> "$HOME/.bashrc"
      echo "export AI_MODEL=$LITELLM_MODEL" >> "$HOME/.bashrc"

      # Claude Code CLI (Anthropic Enterprise — native auth)
      # Run 'claude login' on first use. Tokens persist in ~/.claude/.
      # Alternative: claude-litellm (governed route via LiteLLM)
      if [ "$AI_ASSISTANT" = "claude-code" ] || [ "$AI_ASSISTANT" = "all" ]; then
        echo "alias claude-litellm='ANTHROPIC_BASE_URL=\"$LITELLM_URL/anthropic\" ANTHROPIC_API_KEY=\"\$OPENAI_API_KEY\" ANTHROPIC_AUTH_TOKEN=\"\" claude'" >> "$HOME/.bashrc"
        echo "# Claude Code: run 'claude login' on first use, then 'claude' to start" >> "$HOME/.bashrc"
      fi
    fi

    echo "=== Docker workspace ready ==="
    echo "Docker: DOCKER_HOST=tcp://127.0.0.1:2375 (rootless DinD sidecar)"
  EOT

  metadata {
    key          = "docker_containers"
    display_name = "Docker Containers"
    script       = "docker ps -q 2>/dev/null | wc -l || echo 'N/A'"
    interval     = 15
    timeout      = 3
    order        = 1
  }

  metadata {
    key          = "docker_status"
    display_name = "Docker Status"
    script       = "docker info --format '{{.ServerVersion}}' 2>/dev/null || echo 'Not Ready'"
    interval     = 30
    timeout      = 3
    order        = 2
  }
}

# code-server
resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code"
  url          = "http://localhost:13337/?folder=/home/coder/workspace"
  icon         = "/icon/code.svg"
  subdomain    = false
  share        = "owner"
}

# =============================================================================
# EFS ACCESS POINT
# =============================================================================

resource "aws_efs_access_point" "home" {
  depends_on     = [null_resource.docker_access_check]
  file_system_id = var.efs_file_system_id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = "/docker-workspaces/${data.coder_workspace_owner.me.name}/${data.coder_workspace.me.name}"

    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "0755"
    }
  }

  tags = { Name = local.workspace_name }
}

# =============================================================================
# ECS TASK DEFINITION
# Three containers: auth-check (init) → workspace (main) + dind (sidecar)
# =============================================================================

resource "aws_ecs_task_definition" "workspace" {
  depends_on               = [null_resource.docker_access_check]
  family                   = local.workspace_name
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  cpu                      = lookup(local.ec2_cpu, tostring(data.coder_parameter.cpu_cores.value), "4096")
  memory                   = lookup(local.ec2_memory, tostring(data.coder_parameter.memory_gb.value), "8192")
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.workspace_task_role_arn

  container_definitions = jsonencode([

    # ─── Init Container: Authorization Check (Layer 2) ───────────────
    # Runs before workspace starts. Calls authorization service to verify
    # user is in "docker-users" group. Exits 1 = task fails.
    {
      name      = "auth-check"
      image     = var.auth_check_image
      essential = false  # Must complete before dependents start

      environment = [
        { name = "WORKSPACE_OWNER", value = data.coder_workspace_owner.me.name },
        { name = "WORKSPACE_NAME",  value = data.coder_workspace.me.name },
        { name = "AUTH_SERVICE_URL", value = local.key_provisioner_url },
      ]

      secrets = [
        {
          name      = "PROVISIONER_SECRET"
          valueFrom = "arn:aws:secretsmanager:${var.aws_region}:*:secret:coder-production/provisioner-secret"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "${local.workspace_name}-auth"
        }
      }
    },

    # ─── Workspace Container (Main) ─────────────────────────────────
    {
      name      = "dev"
      image     = var.workspace_image
      essential = true

      dependsOn = [
        { containerName = "auth-check", condition = "SUCCESS" },
        { containerName = "dind",       condition = "START" },
      ]

      command = ["sh", "-c", coder_agent.main.init_script]

      portMappings = [
        { containerPort = 13337, protocol = "tcp" }
      ]

      environment = [
        { name = "CODER_AGENT_TOKEN", value = coder_agent.main.token },
        { name = "DOCKER_HOST",       value = "tcp://127.0.0.1:2375" },
      ]

      mountPoints = [
        {
          sourceVolume  = "home"
          containerPath = "/home/coder"
          readOnly      = false
        }
      ]

      linuxParameters = {
        initProcessEnabled = true
      }

      user = "1000:1000"

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = local.workspace_name
        }
      }
    },

    # ─── DinD Sidecar (Rootless Docker Daemon) ──────────────────────
    {
      name      = "dind"
      image     = var.dind_image
      essential = true

      dependsOn = [
        { containerName = "auth-check", condition = "SUCCESS" },
      ]

      environment = [
        { name = "DOCKER_TLS_CERTDIR", value = "" },
      ]

      portMappings = [
        { containerPort = 2375, protocol = "tcp" }
      ]

      # Rootless DinD needs relaxed security but NOT --privileged
      linuxParameters = {
        initProcessEnabled = true
      }

      # DinD gets its own memory limit (separate from workspace)
      memory = 2048

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "${local.workspace_name}-dind"
        }
      }
    }
  ])

  volume {
    name = "home"

    efs_volume_configuration {
      file_system_id     = var.efs_file_system_id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.home.id
        iam             = "ENABLED"
      }
    }
  }

  tags = {
    Name              = local.workspace_name
    "coder.workspace" = data.coder_workspace.me.name
    "coder.owner"     = data.coder_workspace_owner.me.name
    "coder.template"  = "docker-workspace"
  }
}

# =============================================================================
# ECS SERVICE — Uses EC2 Docker Capacity Provider
# =============================================================================

resource "aws_ecs_service" "workspace" {
  name            = local.workspace_name
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.workspace.arn
  desired_count   = data.coder_workspace.me.start_count

  # EC2 capacity provider — NOT Fargate
  capacity_provider_strategy {
    capacity_provider = var.ec2_docker_capacity_provider
    weight            = 1
    base              = 1
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.workspace_security_group_id]
    assign_public_ip = false
  }

  tags = {
    Name              = local.workspace_name
    "coder.workspace" = data.coder_workspace.me.name
    "coder.owner"     = data.coder_workspace_owner.me.name
    "coder.template"  = "docker-workspace"
  }
}
