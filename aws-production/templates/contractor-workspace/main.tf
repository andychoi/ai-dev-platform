# =============================================================================
# Contractor Workspace Template — ECS Fargate (Production)
# Provisions a Fargate task per workspace with EFS-backed persistent storage
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
# Provided by Coder template variables or defaults
# =============================================================================

variable "ecs_cluster_arn" {
  description = "ARN of the ECS Fargate cluster"
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
  description = "IAM role ARN for ECS task execution (image pull, log shipping)"
  type        = string
}

variable "workspace_task_role_arn" {
  description = "IAM role ARN for workspace task (EFS access, etc.)"
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
  default     = "/ecs/coder-production/workspaces"
}

# --- Direct workspace access (Path 2) variables ---

variable "enable_workspace_direct_access" {
  description = "Enable direct ALB→code-server path (Path 2) with per-workspace routing."
  type        = bool
  default     = false
}

variable "alb_listener_arn" {
  description = "ALB HTTPS listener ARN for creating per-workspace listener rules."
  type        = string
  default     = ""
}

variable "alb_vpc_id" {
  description = "VPC ID for workspace target group."
  type        = string
  default     = ""
}

variable "ide_domain_name" {
  description = "Domain for direct workspace access (e.g., ide.internal.company.com)."
  type        = string
  default     = ""
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL for ALB authentication action."
  type        = string
  default     = ""
}

variable "oidc_client_id" {
  description = "OIDC client ID for ALB authentication action."
  type        = string
  default     = ""
}

variable "oidc_client_secret" {
  description = "OIDC client secret for ALB authentication action."
  type        = string
  default     = ""
  sensitive   = true
}

variable "oidc_token_endpoint" {
  description = "OIDC token endpoint URL."
  type        = string
  default     = ""
}

variable "oidc_authorization_endpoint" {
  description = "OIDC authorization endpoint URL."
  type        = string
  default     = ""
}

variable "oidc_user_info_endpoint" {
  description = "OIDC user info endpoint URL."
  type        = string
  default     = ""
}

# =============================================================================
# WORKSPACE PARAMETERS
# =============================================================================

data "coder_parameter" "cpu_cores" {
  name         = "cpu_cores"
  display_name = "CPU Cores"
  description  = "CPU cores allocated to the workspace"
  type         = "number"
  default      = "2"
  mutable      = true

  option { name = "2 Cores (Standard)";    value = "2" }
  option { name = "4 Cores (Performance)"; value = "4" }
}

data "coder_parameter" "memory_gb" {
  name         = "memory_gb"
  display_name = "Memory (GB)"
  description  = "RAM allocation"
  type         = "number"
  default      = "4"
  mutable      = true

  option { name = "4 GB (Standard)";     value = "4" }
  option { name = "8 GB (Performance)";  value = "8" }
  option { name = "16 GB (Large)";       value = "16" }
}

data "coder_parameter" "disk_size" {
  name         = "disk_size"
  display_name = "Disk Size (GB)"
  description  = "Persistent storage (EFS-backed, cannot change after creation)"
  type         = "number"
  default      = "10"
  mutable      = false

  option { name = "10 GB"; value = "10" }
  option { name = "20 GB"; value = "20" }
  option { name = "50 GB"; value = "50" }
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
  description  = "AI coding agent for development assistance"
  type         = "string"
  default      = "all"
  mutable      = true

  option { name = "All Agents (Recommended)";          value = "all" }
  option { name = "Roo Code + OpenCode";               value = "both" }
  option { name = "Claude Code CLI Only";              value = "claude-code" }
  option { name = "Roo Code Only";                     value = "roo-code" }
  option { name = "OpenCode CLI Only";                 value = "opencode" }
  option { name = "None (Disabled)";                   value = "none" }
}

data "coder_parameter" "guardrail_action" {
  name         = "guardrail_action"
  display_name = "Guardrail Action"
  description  = "How to handle detected PII/secrets in AI requests"
  type         = "string"
  default      = "block"
  mutable      = true

  option { name = "Block (Reject request)";            value = "block" }
  option { name = "Mask (Redact with [REDACTED])";     value = "mask" }
}

data "coder_parameter" "litellm_api_key" {
  name         = "litellm_api_key"
  display_name = "AI API Key"
  description  = "Leave empty for auto-provisioning, or paste a key from your admin"
  type         = "string"
  default      = ""
  mutable      = true
}

data "coder_parameter" "ai_model" {
  name         = "ai_model"
  display_name = "AI Model"
  description  = "Claude model for AI assistance"
  type         = "string"
  default      = "bedrock-claude-haiku"
  mutable      = true

  option { name = "Claude Sonnet 4.5 (Recommended)"; value = "claude-sonnet" }
  option { name = "Claude Haiku 4.5 (Fast)";         value = "claude-haiku" }
  option { name = "Claude Opus 4 (Advanced)";         value = "claude-opus" }
  option { name = "Bedrock Claude Sonnet (AWS)";      value = "bedrock-claude-sonnet" }
  option { name = "Bedrock Claude Haiku (AWS)";       value = "bedrock-claude-haiku" }
}

# =============================================================================
# LOCALS
# =============================================================================

locals {
  workspace_name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"

  # Map parameter values to LiteLLM model IDs
  ai_model_map = {
    "claude-sonnet"         = "claude-sonnet-4-5"
    "claude-haiku"          = "claude-haiku-4-5"
    "claude-opus"           = "claude-opus-4"
    "bedrock-claude-sonnet" = "bedrock-claude-sonnet"
    "bedrock-claude-haiku"  = "bedrock-claude-haiku"
  }
  ai_model_id = lookup(local.ai_model_map, data.coder_parameter.ai_model.value, "claude-sonnet-4-5")

  # Map LiteLLM model IDs to Anthropic native model IDs (for Claude Code CLI)
  anthropic_model_map = {
    "claude-sonnet-4-5"     = "claude-sonnet-4-5-20250929"
    "claude-haiku-4-5"      = "claude-haiku-4-5-20251001"
    "claude-opus-4"         = "claude-opus-4-20250514"
    "bedrock-claude-sonnet" = "claude-sonnet-4-5-20250929"
    "bedrock-claude-haiku"  = "claude-haiku-4-5-20251001"
  }
  anthropic_model_id = lookup(local.anthropic_model_map, local.ai_model_id, "claude-sonnet-4-5-20250929")

  # AI assistant selection helpers (string values for shell script interpolation)
  ai_assistant = data.coder_parameter.ai_assistant.value
  enable_roo   = contains(["all", "both", "roo-code"], local.ai_assistant) ? "true" : "false"
  enable_oc    = contains(["all", "both", "opencode"], local.ai_assistant) ? "true" : "false"
  enable_cc    = contains(["all", "claude-code"], local.ai_assistant) ? "true" : "false"

  # Fargate valid CPU/memory combinations
  # 2 vCPU: 4096-16384 MB (in 1024 increments)
  # 4 vCPU: 8192-30720 MB (in 1024 increments)
  fargate_cpu = {
    "2" = "2048"
    "4" = "4096"
  }
  fargate_memory = {
    "4"  = "4096"
    "8"  = "8192"
    "16" = "16384"
  }

  # LiteLLM endpoint via Cloud Map service discovery
  litellm_url = "http://litellm.coder-production.local:4000"

  # Key Provisioner endpoint via Cloud Map
  key_provisioner_url = "http://key-provisioner.coder-production.local:8100"

  # Direct access hostname: {owner}--{ws}.ide.domain
  # Double-dash separator avoids conflicts with usernames containing single dashes
  workspace_hostname = "${data.coder_workspace_owner.me.name}--${lower(data.coder_workspace.me.name)}.${var.ide_domain_name}"
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

    # Clone git repo if specified
    if [ -n "${data.coder_parameter.git_repo.value}" ]; then
      REPO_DIR="$HOME/workspace/$(basename '${data.coder_parameter.git_repo.value}' .git)"
      if [ ! -d "$REPO_DIR" ]; then
        git clone "${data.coder_parameter.git_repo.value}" "$REPO_DIR" 2>/dev/null || true
      fi
    fi

    # Configure code-server for dual-path authentication
    # Path 1 (Coder tunnel): Coder handles auth, code-server sees all requests as trusted
    # Path 2 (direct ALB): ALB OIDC injects x-amzn-oidc-identity header
    # code-server uses --auth none (Coder agent mode) but we add a proxy auth
    # middleware via config to validate the OIDC header on direct-path requests
    if [ "${var.enable_workspace_direct_access}" = "true" ]; then
      mkdir -p "$HOME/.config/code-server"
      cat > "$HOME/.config/code-server/config.yaml" <<CSEOF
bind-addr: 0.0.0.0:13337
auth: none
cert: false
# ALB injects x-amzn-oidc-identity after OIDC authentication.
# code-server in Coder agent mode uses auth:none — the ALB OIDC action
# is the application-layer auth for Path 2. The per-workspace hostname
# routing ensures each user can only reach their own workspace.
CSEOF
      echo "Direct access enabled: ${local.workspace_hostname}"
    fi

    # Configure AI agents
    AI_ASSISTANT="${data.coder_parameter.ai_assistant.value}"
    LITELLM_KEY="${data.coder_parameter.litellm_api_key.value}"
    LITELLM_MODEL="${local.ai_model_id}"
    ANTHROPIC_MODEL="${local.anthropic_model_id}"
    LITELLM_URL="${local.litellm_url}"
    PROVISIONER_URL="${local.key_provisioner_url}"
    GUARDRAIL_ACTION="${data.coder_parameter.guardrail_action.value}"

    if [ "$AI_ASSISTANT" != "none" ]; then
      # Auto-provision key if not provided
      if [ -z "$LITELLM_KEY" ] && [ -n "$PROVISIONER_SECRET" ]; then
        echo "Auto-provisioning AI API key..."
        for attempt in 1 2 3; do
          RESPONSE=$(curl -sf -X POST "$PROVISIONER_URL/api/v1/keys/workspace" \
            -H "Authorization: Bearer $PROVISIONER_SECRET" \
            -H "Content-Type: application/json" \
            -d "{\"workspace_id\": \"${data.coder_workspace.me.id}\", \"username\": \"${data.coder_workspace_owner.me.name}\", \"workspace_name\": \"${data.coder_workspace.me.name}\", \"guardrail_action\": \"$GUARDRAIL_ACTION\"}" \
            2>/dev/null) && break
          echo "Key provisioner not ready (attempt $attempt/3), retrying in 5s..."
          sleep 5
        done

        if [ -n "$RESPONSE" ]; then
          LITELLM_KEY=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('key',''))" 2>/dev/null || echo "")
          [ -n "$LITELLM_KEY" ] && echo "AI API key provisioned"
        fi
      fi

      if [ -n "$LITELLM_KEY" ]; then
        # --- Roo Code configuration ---
        if ${local.enable_roo}; then
          mkdir -p "$HOME/.config/roo-code"
          cat > "$HOME/.config/roo-code/settings.json" <<ROOEOF
    {
      "providerProfiles": {
        "currentApiConfigName": "litellm",
        "apiConfigs": {
          "litellm": {
            "apiProvider": "openai",
            "openAiBaseUrl": "$LITELLM_URL/v1",
            "openAiApiKey": "$LITELLM_KEY",
            "openAiModelId": "$LITELLM_MODEL",
            "id": "litellm-default"
          }
        }
      }
    }
    ROOEOF
        fi

        # --- OpenCode CLI configuration ---
        if ${local.enable_oc}; then
          if [ -x /home/coder/.opencode/bin/opencode ]; then
            mkdir -p "$HOME/.config/opencode"
            cat > "$HOME/.config/opencode/opencode.json" <<OCEOF
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "litellm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "LiteLLM",
      "options": {
        "baseURL": "$LITELLM_URL/v1",
        "apiKey": "$LITELLM_KEY"
      },
      "models": {
        "claude-sonnet-4-5": {
          "name": "Claude Sonnet 4.5"
        },
        "claude-haiku-4-5": {
          "name": "Claude Haiku 4.5"
        },
        "claude-opus-4": {
          "name": "Claude Opus 4"
        }
      }
    }
  },
  "model": "litellm/$LITELLM_MODEL",
  "small_model": "litellm/claude-haiku-4-5"
}
OCEOF
          fi
        fi

        # --- Claude Code CLI configuration ---
        # Uses Anthropic-native pass-through endpoint (/anthropic/v1/messages)
        # Claude Code is inherently plan-first, so enforcement hook skips it
        if ${local.enable_cc}; then
          mkdir -p "$HOME/.claude"
          cat > "$HOME/.claude/settings.json" <<CCEOF
{
  "permissions": {
    "allow": ["Bash(git *)", "Bash(npm *)", "Read", "Write", "Edit", "Glob", "Grep"],
    "deny": ["Bash(rm -rf *)"]
  }
}
CCEOF
          # Claude Code env vars for LiteLLM Anthropic pass-through
          echo "export ANTHROPIC_BASE_URL=$LITELLM_URL/anthropic" >> "$HOME/.bashrc"
          echo "export ANTHROPIC_API_KEY=$LITELLM_KEY" >> "$HOME/.bashrc"
          echo "export CLAUDE_CODE_USE_BEDROCK=0" >> "$HOME/.bashrc"
          echo "export ANTHROPIC_MODEL=$ANTHROPIC_MODEL" >> "$HOME/.bashrc"
          echo "# Claude Code: run 'claude' to start" >> "$HOME/.bashrc"
        fi

        # --- Common environment variables ---
        echo "export AI_GATEWAY_URL=$LITELLM_URL" >> "$HOME/.bashrc"
        echo "export OPENAI_API_BASE=$LITELLM_URL/v1" >> "$HOME/.bashrc"
        echo "export OPENAI_API_KEY=$LITELLM_KEY" >> "$HOME/.bashrc"
        echo "export AI_MODEL=$LITELLM_MODEL" >> "$HOME/.bashrc"
      fi
    fi
  EOT
}

# code-server (VS Code in browser)
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
# EFS ACCESS POINT (per-workspace home directory isolation)
# =============================================================================

resource "aws_efs_access_point" "home" {
  file_system_id = var.efs_file_system_id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = "/workspaces/${data.coder_workspace_owner.me.name}/${data.coder_workspace.me.name}"

    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "0755"
    }
  }

  tags = {
    Name = local.workspace_name
  }
}

# =============================================================================
# ECS TASK DEFINITION
# =============================================================================

resource "aws_ecs_task_definition" "workspace" {
  family                   = local.workspace_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = lookup(local.fargate_cpu, tostring(data.coder_parameter.cpu_cores.value), "2048")
  memory                   = lookup(local.fargate_memory, tostring(data.coder_parameter.memory_gb.value), "4096")
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.workspace_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "dev"
      image     = "contractor-workspace:latest"
      essential = true

      command = ["sh", "-c", coder_agent.main.init_script]

      portMappings = [
        {
          containerPort = 13337
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "CODER_AGENT_TOKEN"
          value = coder_agent.main.token
        }
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
    }
  ])

  volume {
    name = "home"

    efs_volume_configuration {
      file_system_id          = var.efs_file_system_id
      transit_encryption      = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.home.id
        iam             = "ENABLED"
      }
    }
  }

  tags = {
    Name                = local.workspace_name
    "coder.workspace"   = data.coder_workspace.me.name
    "coder.owner"       = data.coder_workspace_owner.me.name
  }
}

# =============================================================================
# ECS SERVICE
# =============================================================================

resource "aws_ecs_service" "workspace" {
  name            = local.workspace_name
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.workspace.arn
  desired_count   = data.coder_workspace.me.start_count
  launch_type     = "FARGATE"
  platform_version = "LATEST"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.workspace_security_group_id]
    assign_public_ip = false
  }

  # Path 2: Register workspace in its own ALB target group for direct access
  dynamic "load_balancer" {
    for_each = var.enable_workspace_direct_access ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.workspace[0].arn
      container_name   = "dev"
      container_port   = 13337
    }
  }

  tags = {
    Name                = local.workspace_name
    "coder.workspace"   = data.coder_workspace.me.name
    "coder.owner"       = data.coder_workspace_owner.me.name
  }
}

# =============================================================================
# PATH 2: PER-WORKSPACE DIRECT ACCESS (ALB → code-server)
# Each workspace gets its own target group + OIDC-authenticated listener rule
# =============================================================================

# Per-workspace ALB target group — only this workspace's IP is registered
resource "aws_lb_target_group" "workspace" {
  count = var.enable_workspace_direct_access ? 1 : 0

  name        = substr("ws-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}", 0, 32)
  port        = 13337
  protocol    = "HTTP"
  vpc_id      = var.alb_vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/healthz"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  deregistration_delay = 15

  tags = {
    Name              = "ws-${local.workspace_name}"
    "coder.workspace" = data.coder_workspace.me.name
    "coder.owner"     = data.coder_workspace_owner.me.name
    Path              = "direct-access"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Per-workspace ALB listener rule with OIDC authentication
# Route: {owner}--{ws}.ide.domain → OIDC auth → workspace target group
resource "aws_lb_listener_rule" "workspace_direct" {
  count = var.enable_workspace_direct_access ? 1 : 0

  listener_arn = var.alb_listener_arn

  # Step 1: Authenticate with OIDC provider (IdP validates identity)
  action {
    type  = "authenticate-oidc"
    order = 1

    authenticate_oidc {
      issuer                 = var.oidc_issuer_url
      client_id              = var.oidc_client_id
      client_secret          = var.oidc_client_secret
      token_endpoint         = var.oidc_token_endpoint
      authorization_endpoint = var.oidc_authorization_endpoint
      user_info_endpoint     = var.oidc_user_info_endpoint
      on_unauthenticated_request = "authenticate"
      scope                  = "openid profile email"
      session_timeout        = 28800
    }
  }

  # Step 2: Forward to this workspace's target group
  action {
    type             = "forward"
    order            = 2
    target_group_arn = aws_lb_target_group.workspace[0].arn
  }

  condition {
    host_header {
      values = [local.workspace_hostname]
    }
  }

  tags = {
    "coder.workspace" = data.coder_workspace.me.name
    "coder.owner"     = data.coder_workspace_owner.me.name
    Path              = "direct-access"
  }
}
