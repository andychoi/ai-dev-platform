# =============================================================================
# AEM 6.5 Workspace Template — ECS Fargate (Production)
#
# Provisions a Fargate task per workspace with EFS-backed persistent storage.
# AEM quickstart JAR is downloaded from S3 on first start (persists on EFS).
#
# Key differences from contractor-workspace:
#   - Java 11 (not polyglot) — AEM 6.5 requirement
#   - Maven 3.9.9 from Apache archive
#   - AEM Author/Publisher JVM instances inside the container
#   - S3 download for proprietary JAR + license (IAM task role, no keys)
#   - Graceful shutdown script (prevents CRX repository corruption)
#   - Higher default resources (4 CPU, 8 GB RAM, 50 GB disk)
#   - stopTimeout: 120 (AEM needs time to flush CRX)
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

variable "aem_workspace_task_role_arn" {
  description = "IAM role ARN for AEM workspace task (CloudWatch Logs + S3 artifacts read)"
  type        = string
}

variable "artifacts_bucket_name" {
  description = "S3 bucket name containing AEM artifacts (JAR + license under aem/ prefix)"
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
  description  = "CPU cores allocated to the workspace (AEM Author needs at least 4)"
  type         = "number"
  default      = "4"
  mutable      = true

  option { name = "4 Cores (Standard)";              value = "4" }
  option { name = "8 Cores (Author + Publisher)";     value = "8" }
}

data "coder_parameter" "memory_gb" {
  name         = "memory_gb"
  display_name = "Memory (GB)"
  description  = "RAM allocation (AEM Author alone needs 4+ GB)"
  type         = "number"
  default      = "8"
  mutable      = true

  option { name = "8 GB (Author only)";              value = "8" }
  option { name = "16 GB (Author + Publisher)";       value = "16" }
  option { name = "30 GB (Performance)";              value = "30" }
}

data "coder_parameter" "disk_size" {
  name         = "disk_size"
  display_name = "Disk Size (GB)"
  description  = "Persistent storage (AEM crx-quickstart is ~5 GB unpacked)"
  type         = "number"
  default      = "50"
  mutable      = false

  option { name = "50 GB";  value = "50" }
  option { name = "100 GB"; value = "100" }
}

# =============================================================================
# AEM-SPECIFIC PARAMETERS
# =============================================================================

data "coder_parameter" "aem_publisher_enabled" {
  name         = "aem_publisher_enabled"
  display_name = "Enable AEM Publisher"
  description  = "Start a Publisher instance alongside Author (requires more RAM)"
  type         = "string"
  default      = "false"
  mutable      = false

  option { name = "Disabled (Author only)";           value = "false" }
  option { name = "Enabled (Author + Publisher)";     value = "true" }
}

data "coder_parameter" "aem_author_jvm_opts" {
  name         = "aem_author_jvm_opts"
  display_name = "Author JVM Memory"
  description  = "Heap allocation (-Xms/-Xmx) for AEM Author instance"
  type         = "string"
  default      = "-Xms2g -Xmx3g"
  mutable      = true

  option { name = "2 GB (Standard)";                  value = "-Xms1g -Xmx2g" }
  option { name = "3 GB (Recommended)";               value = "-Xms2g -Xmx3g" }
  option { name = "4 GB (Large projects)";            value = "-Xms3g -Xmx4g" }
}

data "coder_parameter" "aem_publisher_jvm_opts" {
  name         = "aem_publisher_jvm_opts"
  display_name = "Publisher JVM Memory"
  description  = "Heap allocation (-Xms/-Xmx) for AEM Publisher instance"
  type         = "string"
  default      = "-Xms512m -Xmx1g"
  mutable      = true

  option { name = "1 GB (Standard)";                  value = "-Xms512m -Xmx1g" }
  option { name = "2 GB (Large projects)";            value = "-Xms1g -Xmx2g" }
}

data "coder_parameter" "aem_debug_port" {
  name         = "aem_debug_port"
  display_name = "JPDA Debug Port"
  description  = "Remote debug port for AEM Author (VS Code attaches here)"
  type         = "number"
  default      = "5005"
  mutable      = true
}

data "coder_parameter" "aem_admin_password" {
  name         = "aem_admin_password"
  display_name = "AEM Admin Password"
  description  = "Password for the AEM admin user"
  type         = "string"
  default      = "admin"
  mutable      = true
}

# =============================================================================
# COMMON PARAMETERS (same as contractor-workspace)
# =============================================================================

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

  # AI assistant selection helpers
  ai_assistant = data.coder_parameter.ai_assistant.value
  enable_roo   = contains(["all", "both", "roo-code"], local.ai_assistant) ? "true" : "false"
  enable_oc    = contains(["all", "both", "opencode"], local.ai_assistant) ? "true" : "false"
  enable_cc    = contains(["all", "claude-code"], local.ai_assistant) ? "true" : "false"

  # Fargate valid CPU/memory combinations (larger sizes for AEM)
  # 4 vCPU: 8192-30720 MB (in 1024 increments)
  # 8 vCPU: 16384-61440 MB (in 4096 increments)
  fargate_cpu = {
    "4" = "4096"
    "8" = "8192"
  }
  fargate_memory = {
    "8"  = "8192"
    "16" = "16384"
    "30" = "30720"
  }

  # LiteLLM endpoint via Cloud Map service discovery
  litellm_url = "http://litellm.coder-production.local:4000"

  # Key Provisioner endpoint via Cloud Map
  key_provisioner_url = "http://key-provisioner.coder-production.local:8100"

  # Direct access hostname: {owner}--{ws}.ide.domain
  workspace_hostname = "${data.coder_workspace_owner.me.name}--${lower(data.coder_workspace.me.name)}.${var.ide_domain_name}"
}

# =============================================================================
# CODER AGENT
# =============================================================================

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"
  dir  = "/home/coder/workspace"

  display_apps {
    vscode                 = false
    vscode_insiders        = false
    web_terminal           = true
    ssh_helper             = false
    port_forwarding_helper = false
  }

  env = {
    CODER_AGENT_DEVCONTAINERS_ENABLE = "false"
    JAVA_HOME                        = "/usr/lib/jvm/java-11-openjdk-amd64"
  }

  # ===========================================================================
  # STARTUP SCRIPT
  # ===========================================================================
  startup_script = <<-EOT
    #!/bin/bash
    set -e

    echo "=== Starting AEM workspace initialization ==="

    # ── Phase 1: S3 artifact download (first start only) ──────────────
    AEM_JAR="/home/coder/aem/aem-quickstart.jar"
    ARTIFACTS_BUCKET="${var.artifacts_bucket_name}"

    if [ ! -f "$AEM_JAR" ]; then
      echo "AEM JAR not found on EFS — downloading from S3..."
      mkdir -p /home/coder/aem

      if aws s3 cp "s3://$ARTIFACTS_BUCKET/aem/aem-quickstart.jar" "$AEM_JAR" 2>/dev/null; then
        echo "AEM quickstart JAR downloaded from S3"
      else
        echo ""
        echo "============================================================"
        echo "  AEM QUICKSTART JAR NOT FOUND IN S3"
        echo "============================================================"
        echo ""
        echo "  Expected at: s3://$ARTIFACTS_BUCKET/aem/aem-quickstart.jar"
        echo ""
        echo "  Admin: upload files to S3:"
        echo "    aws s3 cp aem-quickstart.jar s3://$ARTIFACTS_BUCKET/aem/"
        echo "    aws s3 cp license.properties s3://$ARTIFACTS_BUCKET/aem/"
        echo ""
        echo "  VS Code and Maven are ready — you can work on code"
        echo "  without AEM running. Restart workspace after upload."
        echo "============================================================"
        echo ""
      fi

      if [ ! -f /home/coder/aem/license.properties ]; then
        aws s3 cp "s3://$ARTIFACTS_BUCKET/aem/license.properties" /home/coder/aem/license.properties 2>/dev/null \
          || echo "WARNING: license.properties not found in S3"
      fi
    else
      echo "AEM JAR already present on EFS (skipping S3 download)"
    fi

    # ── Phase 2: Git configuration ────────────────────────────────────
    git config --global user.name "${data.coder_workspace_owner.me.name}"
    git config --global user.email "${data.coder_workspace_owner.me.email}"

    if [ -n "${data.coder_parameter.git_repo.value}" ]; then
      REPO_DIR="$HOME/workspace/$(basename '${data.coder_parameter.git_repo.value}' .git)"
      if [ ! -d "$REPO_DIR" ]; then
        git clone "${data.coder_parameter.git_repo.value}" "$REPO_DIR" 2>/dev/null || true
      fi
    fi

    # ── Phase 3: Maven settings recovery ──────────────────────────────
    if [ ! -f /home/coder/.m2/settings.xml ]; then
      echo "Restoring Maven settings.xml (first start or volume reset)..."
      mkdir -p /home/coder/.m2
      cat > /home/coder/.m2/settings.xml << 'MAVENSETTINGS'
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.2.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.2.0
                              https://maven.apache.org/xsd/settings-1.2.0.xsd">
  <servers>
    <server>
      <id>aem-author</id>
      <username>admin</username>
      <password>${data.coder_parameter.aem_admin_password.value}</password>
    </server>
    <server>
      <id>aem-publisher</id>
      <username>admin</username>
      <password>${data.coder_parameter.aem_admin_password.value}</password>
    </server>
  </servers>
  <profiles>
    <profile>
      <id>adobe-public</id>
      <activation>
        <activeByDefault>true</activeByDefault>
      </activation>
      <repositories>
        <repository>
          <id>adobe-public-releases</id>
          <name>Adobe Public Repository</name>
          <url>https://repo.adobe.com/nexus/content/groups/public/</url>
          <releases><enabled>true</enabled><updatePolicy>never</updatePolicy></releases>
          <snapshots><enabled>false</enabled></snapshots>
        </repository>
      </repositories>
      <pluginRepositories>
        <pluginRepository>
          <id>adobe-public-releases</id>
          <name>Adobe Public Repository</name>
          <url>https://repo.adobe.com/nexus/content/groups/public/</url>
          <releases><enabled>true</enabled><updatePolicy>never</updatePolicy></releases>
          <snapshots><enabled>false</enabled></snapshots>
        </pluginRepository>
      </pluginRepositories>
    </profile>
  </profiles>
</settings>
MAVENSETTINGS
      echo "Maven settings.xml restored"
    fi

    # ── Phase 4: AEM Instance Management ──────────────────────────────
    AEM_PUBLISHER_ENABLED="${data.coder_parameter.aem_publisher_enabled.value}"
    AEM_AUTHOR_JVM="${data.coder_parameter.aem_author_jvm_opts.value}"
    AEM_PUBLISHER_JVM="${data.coder_parameter.aem_publisher_jvm_opts.value}"
    AEM_DEBUG_PORT="${data.coder_parameter.aem_debug_port.value}"
    AEM_ADMIN_PASS="${data.coder_parameter.aem_admin_password.value}"
    AEM_BASE_JVM_OPTS="-XX:+UseG1GC -XX:MaxMetaspaceSize=512m -Djava.awt.headless=true -Dorg.apache.sling.commons.log.file=logs/error.log"

    if [ -f "$AEM_JAR" ]; then
      # --- AEM Author startup ---
      echo "Starting AEM Author instance..."
      mkdir -p /home/coder/aem/author
      cd /home/coder/aem/author

      # Copy license.properties (AEM expects it in working dir)
      if [ -f /home/coder/aem/license.properties ] && [ ! -f /home/coder/aem/author/license.properties ]; then
        cp /home/coder/aem/license.properties /home/coder/aem/author/license.properties
      fi

      if [ ! -d /home/coder/aem/author/crx-quickstart ]; then
        echo "First start detected — AEM will unpack crx-quickstart (takes 5-10 minutes)..."
      fi

      java $AEM_AUTHOR_JVM $AEM_BASE_JVM_OPTS \
        -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:$AEM_DEBUG_PORT \
        -Dsling.run.modes=author \
        -jar "$AEM_JAR" \
        -p 4502 -r author -nobrowser -nofork \
        > /home/coder/aem/author/stdout.log 2>&1 &
      echo $! > /home/coder/aem/author.pid
      echo "AEM Author starting (PID: $(cat /home/coder/aem/author.pid), debug port: $AEM_DEBUG_PORT)..."

      # Wait for Author to be ready (up to 10 minutes for first start)
      echo "Waiting for AEM Author to become ready..."
      for i in $(seq 1 60); do
        if curl -sf -o /dev/null http://localhost:4502/libs/granite/core/content/login.html; then
          echo "AEM Author is ready! (took ~$((i * 10))s)"
          break
        fi
        if [ $i -eq 60 ]; then
          echo "WARNING: AEM Author did not become ready in 10 minutes."
          echo "  Check logs: tail -f /home/coder/aem/author/crx-quickstart/logs/error.log"
        fi
        sleep 10
      done

      # --- AEM Publisher startup (if enabled) ---
      if [ "$AEM_PUBLISHER_ENABLED" = "true" ]; then
        echo "Starting AEM Publisher instance..."
        mkdir -p /home/coder/aem/publisher
        cd /home/coder/aem/publisher

        if [ -f /home/coder/aem/license.properties ] && [ ! -f /home/coder/aem/publisher/license.properties ]; then
          cp /home/coder/aem/license.properties /home/coder/aem/publisher/license.properties
        fi

        if [ ! -d /home/coder/aem/publisher/crx-quickstart ]; then
          echo "First Publisher start — AEM will unpack crx-quickstart..."
        fi

        java $AEM_PUBLISHER_JVM $AEM_BASE_JVM_OPTS \
          -Dsling.run.modes=publish \
          -jar "$AEM_JAR" \
          -p 4503 -r publish -nobrowser -nofork \
          > /home/coder/aem/publisher/stdout.log 2>&1 &
        echo $! > /home/coder/aem/publisher.pid
        echo "AEM Publisher starting (PID: $(cat /home/coder/aem/publisher.pid))..."

        for i in $(seq 1 60); do
          if curl -sf -o /dev/null http://localhost:4503/libs/granite/core/content/login.html; then
            echo "AEM Publisher is ready! (took ~$((i * 10))s)"
            break
          fi
          if [ $i -eq 60 ]; then
            echo "WARNING: AEM Publisher did not become ready in 10 minutes."
          fi
          sleep 10
        done
      fi
    fi

    # ── Phase 5: AI Agent Configuration ───────────────────────────────
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
        "claude-sonnet-4-5": { "name": "Claude Sonnet 4.5" },
        "claude-haiku-4-5": { "name": "Claude Haiku 4.5" },
        "claude-opus-4": { "name": "Claude Opus 4" }
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
        if ${local.enable_cc}; then
          mkdir -p "$HOME/.claude"
          cat > "$HOME/.claude/settings.json" <<CCEOF
{
  "permissions": {
    "allow": ["Bash(git *)", "Bash(npm *)", "Bash(mvn *)", "Bash(java *)", "Read", "Write", "Edit", "Glob", "Grep"],
    "deny": ["Bash(rm -rf *)"]
  }
}
CCEOF
          echo "alias claude-litellm='ANTHROPIC_BASE_URL=\"$LITELLM_URL/anthropic\" ANTHROPIC_API_KEY=\"\$OPENAI_API_KEY\" ANTHROPIC_AUTH_TOKEN=\"\" claude'" >> "$HOME/.bashrc"
          echo "# Claude Code: run 'claude login' on first use, then 'claude' to start" >> "$HOME/.bashrc"
        fi

        # --- Common environment variables ---
        cat >> "$HOME/.bashrc" <<AIENV
# AI Configuration (LiteLLM)
export AI_GATEWAY_URL=$LITELLM_URL
export OPENAI_API_BASE=$LITELLM_URL/v1
export OPENAI_API_KEY=$LITELLM_KEY
export AI_MODEL=$LITELLM_MODEL
AIENV
      fi
    fi

    # ── Phase 6: AEM convenience aliases ──────────────────────────────
    cat >> ~/.bashrc << 'AEMALIAS'

# ── AEM Development Aliases ──────────────────────────────────────────
# Build & Deploy
alias aem-build='mvn clean install -PautoInstallSinglePackage -Daem.host=localhost -Daem.port=4502'
alias aem-deploy='mvn clean install -PautoInstallSinglePackage -Daem.host=localhost -Daem.port=4502 -DskipTests'
alias aem-deploy-core='(cd core && mvn clean install -PautoInstallBundle -Dsling.install.url=http://localhost:4502/system/console)'
alias aem-deploy-apps='(cd ui.apps && mvn clean install -PautoInstallPackage -Daem.host=localhost -Daem.port=4502)'
alias aem-deploy-content='(cd ui.content && mvn clean install -PautoInstallPackage -Daem.host=localhost -Daem.port=4502)'
alias aem-deploy-frontend='(cd ui.frontend && npm run build) && (cd ui.apps && mvn clean install -PautoInstallPackage -Daem.host=localhost -Daem.port=4502)'
alias aem-deploy-publish='mvn clean install -PautoInstallSinglePackagePublish -Daem.publish.host=localhost -Daem.publish.port=4503 -DskipTests'

# Logs
alias aem-logs='tail -f /home/coder/aem/author/crx-quickstart/logs/error.log'
alias aem-logs-publish='tail -f /home/coder/aem/publisher/crx-quickstart/logs/error.log'

# Status
alias aem-status='echo "Author:"; curl -sf -o /dev/null -w "  HTTP %%{http_code}\n" http://localhost:4502/libs/granite/core/content/login.html || echo "  Stopped"; echo "Publisher:"; curl -sf -o /dev/null -w "  HTTP %%{http_code}\n" http://localhost:4503/libs/granite/core/content/login.html || echo "  Stopped/Disabled"'
alias aem-bundles='curl -sf -u admin:admin http://localhost:4502/system/console/bundles.json | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"Bundles: {d[\"s\"][3]}/{d[\"s\"][0]} active ({d[\"s\"][4]} fragments)\")" 2>/dev/null || echo "AEM not running or not ready"'
AEMALIAS

    # Export AEM JVM opts for alias functions
    cat >> ~/.bashrc <<AEMENV
export AEM_AUTHOR_JVM="$AEM_AUTHOR_JVM"
export AEM_PUBLISHER_JVM="$AEM_PUBLISHER_JVM"
export AEM_BASE_JVM_OPTS="$AEM_BASE_JVM_OPTS"
export AEM_DEBUG_PORT="$AEM_DEBUG_PORT"
AEMENV

    # ── Phase 7: Configure code-server and start ──────────────────────
    # Direct access configuration (Path 2)
    if [ "${var.enable_workspace_direct_access}" = "true" ]; then
      mkdir -p "$HOME/.config/code-server"
      cat > "$HOME/.config/code-server/config.yaml" <<CSEOF
bind-addr: 0.0.0.0:13337
auth: none
cert: false
CSEOF
      echo "Direct access enabled: ${local.workspace_hostname}"
    fi

    # Inject default launch.json if workspace project doesn't have one
    if [ ! -f /home/coder/workspace/.vscode/launch.json ]; then
      mkdir -p /home/coder/workspace/.vscode
      cat > /home/coder/workspace/.vscode/launch.json << 'LAUNCHJSON'
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "java",
      "name": "Attach to AEM Author",
      "request": "attach",
      "hostName": "localhost",
      "port": 5005
    }
  ]
}
LAUNCHJSON
    fi

    echo ""
    echo "=== AEM Workspace Ready ==="
    echo "AI Agent: $${AI_ASSISTANT}"
    if [ -f "$AEM_JAR" ]; then
      echo "AEM Author:    http://localhost:4502 (JPDA debug: $AEM_DEBUG_PORT)"
      echo "  CRXDE:       http://localhost:4502/crx/de"
      echo "  Packages:    http://localhost:4502/crx/packmgr"
      echo "  Console:     http://localhost:4502/system/console"
      if [ "$AEM_PUBLISHER_ENABLED" = "true" ]; then
        echo "AEM Publisher: http://localhost:4503"
      fi
    else
      echo "AEM: Not started (upload JAR to s3://$ARTIFACTS_BUCKET/aem/)"
    fi
    echo ""
    echo "Aliases: aem-build, aem-deploy, aem-logs, aem-status, aem-bundles"
  EOT

  # ===========================================================================
  # SHUTDOWN SCRIPT — Graceful AEM shutdown (prevents CRX corruption)
  # ===========================================================================
  shutdown_script = <<-EOT
    #!/bin/bash
    echo "=== AEM Workspace shutting down ==="

    # Graceful AEM Author shutdown
    if [ -f /home/coder/aem/author.pid ]; then
      AUTHOR_PID=$(cat /home/coder/aem/author.pid)
      if kill -0 "$AUTHOR_PID" 2>/dev/null; then
        echo "Stopping AEM Author (PID: $AUTHOR_PID)..."
        kill "$AUTHOR_PID"
        for i in $(seq 1 30); do
          kill -0 "$AUTHOR_PID" 2>/dev/null || { echo "AEM Author stopped gracefully"; break; }
          sleep 2
        done
        if kill -0 "$AUTHOR_PID" 2>/dev/null; then
          echo "Force-killing AEM Author..."
          kill -9 "$AUTHOR_PID" 2>/dev/null
        fi
      fi
      rm -f /home/coder/aem/author.pid
    fi

    # Graceful AEM Publisher shutdown
    if [ -f /home/coder/aem/publisher.pid ]; then
      PUB_PID=$(cat /home/coder/aem/publisher.pid)
      if kill -0 "$PUB_PID" 2>/dev/null; then
        echo "Stopping AEM Publisher (PID: $PUB_PID)..."
        kill "$PUB_PID"
        for i in $(seq 1 30); do
          kill -0 "$PUB_PID" 2>/dev/null || { echo "AEM Publisher stopped gracefully"; break; }
          sleep 2
        done
        if kill -0 "$PUB_PID" 2>/dev/null; then
          echo "Force-killing AEM Publisher..."
          kill -9 "$PUB_PID" 2>/dev/null
        fi
      fi
      rm -f /home/coder/aem/publisher.pid
    fi

    pkill -f code-server || true
    echo "Workspace shutdown complete"
  EOT

  # ===========================================================================
  # METADATA WIDGETS
  # ===========================================================================

  metadata {
    key          = "cpu_usage"
    display_name = "CPU Usage"
    script       = "top -bn1 | grep 'Cpu(s)' | awk '{print int($2)}'"
    interval     = 10
    timeout      = 1
    order        = 1
  }

  metadata {
    key          = "memory_usage"
    display_name = "Memory Usage"
    script       = "free -m | awk 'NR==2{printf \"%.0f%%\", $3*100/$2}'"
    interval     = 10
    timeout      = 1
    order        = 2
  }

  metadata {
    key          = "disk_usage"
    display_name = "Disk Usage"
    script       = "df -h /home/coder | awk 'NR==2{print $5}'"
    interval     = 60
    timeout      = 1
    order        = 3
  }

  metadata {
    key          = "aem_author_status"
    display_name = "AEM Author"
    script       = <<-EOS
      if [ -f /home/coder/aem/author.pid ] && kill -0 $(cat /home/coder/aem/author.pid) 2>/dev/null; then
        if curl -sf -o /dev/null http://localhost:4502/libs/granite/core/content/login.html; then
          echo "Running"
        else
          echo "Starting..."
        fi
      else
        echo "Stopped"
      fi
    EOS
    interval     = 15
    timeout      = 5
    order        = 4
  }

  metadata {
    key          = "aem_publisher_status"
    display_name = "AEM Publisher"
    script       = <<-EOS
      if [ "${data.coder_parameter.aem_publisher_enabled.value}" != "true" ]; then
        echo "Disabled"
      elif [ -f /home/coder/aem/publisher.pid ] && kill -0 $(cat /home/coder/aem/publisher.pid) 2>/dev/null; then
        if curl -sf -o /dev/null http://localhost:4503/libs/granite/core/content/login.html; then
          echo "Running"
        else
          echo "Starting..."
        fi
      else
        echo "Stopped"
      fi
    EOS
    interval     = 15
    timeout      = 5
    order        = 5
  }

  metadata {
    key          = "osgi_bundles"
    display_name = "OSGi Bundles"
    script       = <<-EOS
      curl -sf -u admin:${data.coder_parameter.aem_admin_password.value} \
        http://localhost:4502/system/console/bundles.json 2>/dev/null \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"{d['s'][3]}/{d['s'][0]} active\")" \
        2>/dev/null || echo "N/A"
    EOS
    interval     = 30
    timeout      = 5
    order        = 6
  }

  metadata {
    key          = "author_jvm_heap"
    display_name = "Author JVM Heap"
    script       = <<-EOS
      if [ -f /home/coder/aem/author.pid ]; then
        PID=$(cat /home/coder/aem/author.pid)
        if kill -0 "$PID" 2>/dev/null; then
          RSS=$(ps -o rss= -p "$PID" 2>/dev/null | tr -d ' ')
          if [ -n "$RSS" ]; then
            echo "$((RSS / 1024)) MB"
          else
            echo "N/A"
          fi
        else
          echo "Stopped"
        fi
      else
        echo "N/A"
      fi
    EOS
    interval     = 15
    timeout      = 3
    order        = 7
  }
}

# =============================================================================
# CODER APPS
# =============================================================================

# VS Code in browser (code-server)
resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code"
  url          = "http://localhost:13337/?folder=/home/coder/workspace"
  icon         = "/icon/code.svg"
  subdomain    = false
  share        = "owner"
}

# AEM Author — accessible from Coder dashboard
resource "coder_app" "aem-author" {
  agent_id     = coder_agent.main.id
  slug         = "aem-author"
  display_name = "AEM Author"
  icon         = "/icon/database.svg"
  url          = "http://localhost:4502"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:4502/libs/granite/core/content/login.html"
    interval  = 15
    threshold = 40
  }
}

# AEM Publisher — always registered (shows "unhealthy" when disabled)
resource "coder_app" "aem-publisher" {
  agent_id     = coder_agent.main.id
  slug         = "aem-publisher"
  display_name = "AEM Publisher"
  icon         = "/icon/database.svg"
  url          = "http://localhost:4503"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:4503/libs/granite/core/content/login.html"
    interval  = 15
    threshold = 40
  }
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
  cpu                      = lookup(local.fargate_cpu, tostring(data.coder_parameter.cpu_cores.value), "4096")
  memory                   = lookup(local.fargate_memory, tostring(data.coder_parameter.memory_gb.value), "8192")
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.aem_workspace_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "dev"
      image     = "aem-workspace:latest"
      essential = true

      command = ["sh", "-c", coder_agent.main.init_script]

      portMappings = [
        { containerPort = 13337, protocol = "tcp" },
        { containerPort = 4502,  protocol = "tcp" },
        { containerPort = 4503,  protocol = "tcp" },
        { containerPort = 5005,  protocol = "tcp" },
      ]

      environment = [
        { name = "CODER_AGENT_TOKEN", value = coder_agent.main.token },
        { name = "JAVA_HOME",         value = "/usr/lib/jvm/java-11-openjdk-amd64" },
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

      # AEM needs time to flush CRX on shutdown
      stopTimeout = 120

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
    "coder.template"    = "aem-workspace"
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
    "coder.template"    = "aem-workspace"
  }
}

# =============================================================================
# PATH 2: PER-WORKSPACE DIRECT ACCESS (ALB → code-server)
# =============================================================================

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

resource "aws_lb_listener_rule" "workspace_direct" {
  count = var.enable_workspace_direct_access ? 1 : 0

  listener_arn = var.alb_listener_arn

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
