# AEM 6.5 Workspace Template for Coder
# Docker-based AEM development workspace with Author + optional Publisher
#
# Key differences from java-workspace:
#   - Java 11 (not 21) — AEM 6.5 requirement
#   - Maven 3.9.9 from Apache archive
#   - AEM Author/Publisher JVM instances inside the container
#   - Graceful shutdown script (prevents CRX repository corruption)
#   - Higher default resources (4 CPU, 8 GB RAM, 50 GB disk)

terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

# Coder provider data sources
data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Docker provider - connects to local Docker daemon
provider "docker" {}

# ============================================================================
# WORKSPACE PARAMETERS
# ============================================================================

data "coder_parameter" "cpu_cores" {
  name         = "cpu_cores"
  display_name = "CPU Cores"
  description  = "Number of CPU cores (AEM Author needs at least 4)"
  type         = "number"
  default      = "4"
  mutable      = true
  icon         = "/icon/memory.svg"

  option {
    name  = "4 Cores (Standard)"
    value = "4"
  }
  option {
    name  = "6 Cores (Author + Publisher)"
    value = "6"
  }
  option {
    name  = "8 Cores (Performance)"
    value = "8"
  }
}

data "coder_parameter" "memory_gb" {
  name         = "memory_gb"
  display_name = "Memory (GB)"
  description  = "RAM allocation (AEM Author alone needs 4+ GB)"
  type         = "number"
  default      = "8"
  mutable      = true
  icon         = "/icon/memory.svg"

  option {
    name  = "8 GB (Author only)"
    value = "8"
  }
  option {
    name  = "12 GB (Author + Publisher)"
    value = "12"
  }
  option {
    name  = "16 GB (Performance)"
    value = "16"
  }
}

data "coder_parameter" "disk_size" {
  name         = "disk_size"
  display_name = "Disk Size (GB)"
  description  = "Persistent storage (AEM crx-quickstart is ~5 GB unpacked)"
  type         = "number"
  default      = "50"
  mutable      = false
  icon         = "/icon/database.svg"

  option {
    name  = "50 GB"
    value = "50"
  }
  option {
    name  = "100 GB"
    value = "100"
  }
}

# ============================================================================
# AEM-SPECIFIC PARAMETERS
# ============================================================================

data "coder_parameter" "aem_jar_path" {
  name         = "aem_jar_path"
  display_name = "AEM Quickstart JAR Path"
  description  = "Path to the proprietary AEM quickstart JAR (admin pre-places this)"
  type         = "string"
  default      = "/home/coder/aem/aem-quickstart.jar"
  mutable      = false
  icon         = "/icon/database.svg"
}

data "coder_parameter" "aem_publisher_enabled" {
  name         = "aem_publisher_enabled"
  display_name = "Enable AEM Publisher"
  description  = "Start a Publisher instance alongside Author (requires more RAM)"
  type         = "string"
  default      = "false"
  mutable      = false
  icon         = "/icon/database.svg"

  option {
    name  = "Disabled (Author only)"
    value = "false"
  }
  option {
    name  = "Enabled (Author + Publisher)"
    value = "true"
  }
}

data "coder_parameter" "aem_author_jvm_opts" {
  name         = "aem_author_jvm_opts"
  display_name = "Author JVM Heap"
  description  = "Max heap size for AEM Author instance"
  type         = "string"
  default      = "-Xmx2048m"
  mutable      = true
  icon         = "/icon/memory.svg"

  option {
    name  = "2 GB (Standard)"
    value = "-Xmx2048m"
  }
  option {
    name  = "3 GB (Recommended)"
    value = "-Xmx3072m"
  }
  option {
    name  = "4 GB (Large projects)"
    value = "-Xmx4096m"
  }
}

data "coder_parameter" "aem_publisher_jvm_opts" {
  name         = "aem_publisher_jvm_opts"
  display_name = "Publisher JVM Heap"
  description  = "Max heap size for AEM Publisher instance"
  type         = "string"
  default      = "-Xmx1024m"
  mutable      = true
  icon         = "/icon/memory.svg"

  option {
    name  = "1 GB (Standard)"
    value = "-Xmx1024m"
  }
  option {
    name  = "2 GB (Large projects)"
    value = "-Xmx2048m"
  }
}

data "coder_parameter" "aem_debug_port" {
  name         = "aem_debug_port"
  display_name = "JPDA Debug Port"
  description  = "Remote debug port for AEM Author (VS Code attaches here)"
  type         = "number"
  default      = "5005"
  mutable      = true
  icon         = "/icon/code.svg"
}

data "coder_parameter" "aem_admin_password" {
  name         = "aem_admin_password"
  display_name = "AEM Admin Password"
  description  = "Password for the AEM admin user"
  type         = "string"
  default      = "admin"
  mutable      = true
  icon         = "/icon/lock.svg"
}

# ============================================================================
# COMMON PARAMETERS (same as java-workspace)
# ============================================================================

data "coder_parameter" "git_repo" {
  name         = "git_repo"
  display_name = "Git Repository"
  description  = "Repository to clone on workspace start (optional)"
  type         = "string"
  default      = ""
  mutable      = true
  icon         = "/icon/git.svg"
}

data "coder_parameter" "dotfiles_repo" {
  name         = "dotfiles_repo"
  display_name = "Dotfiles Repository"
  description  = "Personal dotfiles to apply (optional)"
  type         = "string"
  default      = ""
  mutable      = true
  icon         = "/icon/widgets.svg"
}

data "coder_parameter" "developer_background" {
  name         = "developer_background"
  display_name = "Developer Background"
  description  = "Your primary IDE background (for keybindings and UI)"
  type         = "string"
  default      = "intellij"
  mutable      = true
  icon         = "/icon/code.svg"

  option {
    name  = "IntelliJ/JetBrains User"
    value = "intellij"
  }
  option {
    name  = "VS Code User"
    value = "vscode"
  }
  option {
    name  = "Eclipse User"
    value = "eclipse"
  }
  option {
    name  = "Vim/Neovim User"
    value = "vim"
  }
}

data "coder_parameter" "ai_assistant" {
  name         = "ai_assistant"
  display_name = "AI Coding Agent"
  description  = "AI coding agent for development assistance"
  type         = "string"
  default      = "both"
  mutable      = true
  icon         = "/icon/widgets.svg"

  option {
    name  = "All Agents (Roo Code + OpenCode + Claude Code)"
    value = "all"
  }
  option {
    name  = "Roo Code + OpenCode"
    value = "both"
  }
  option {
    name  = "Claude Code CLI"
    value = "claude-code"
  }
  option {
    name  = "Roo Code Only"
    value = "roo-code"
  }
  option {
    name  = "OpenCode CLI Only"
    value = "opencode"
  }
  option {
    name  = "None"
    value = "none"
  }
}

data "coder_parameter" "litellm_api_key" {
  name         = "litellm_api_key"
  display_name = "AI API Key"
  description  = "Leave empty for auto-provisioning, or paste a key from your admin"
  type         = "string"
  default      = ""
  mutable      = true
  icon         = "/icon/widgets.svg"
}

data "coder_parameter" "ai_model" {
  name         = "ai_model"
  display_name = "AI Model"
  description  = "Select the AI model for chat and code assistance"
  type         = "string"
  default      = "glm-4.7"
  mutable      = true
  icon         = "/icon/widgets.svg"

  option {
    name  = "GLM-4.7 (Local, Default)"
    value = "glm-4.7"
  }
  option {
    name  = "Claude Sonnet 4.5 (Balanced)"
    value = "claude-sonnet"
  }
  option {
    name  = "Claude Haiku 4.5 (Fast)"
    value = "claude-haiku"
  }
  option {
    name  = "Claude Opus 4 (Advanced)"
    value = "claude-opus"
  }
  option {
    name  = "Bedrock Claude Sonnet (AWS)"
    value = "bedrock-claude-sonnet"
  }
  option {
    name  = "Bedrock Claude Haiku (AWS)"
    value = "bedrock-claude-haiku"
  }
}

data "coder_parameter" "ai_gateway_url" {
  name         = "ai_gateway_url"
  display_name = "AI Gateway URL"
  description  = "URL of the AI Gateway proxy (LiteLLM)"
  type         = "string"
  default      = "http://litellm:4000"
  mutable      = true
  icon         = "/icon/widgets.svg"
}

data "coder_parameter" "ai_enforcement_level" {
  name         = "ai_enforcement_level"
  display_name = "AI Behavior Mode"
  description  = "Controls how AI agents approach tasks. Set by admin at workspace creation."
  type         = "string"
  default      = "standard"
  mutable      = false
  icon         = "/icon/widgets.svg"

  option {
    name  = "Standard - Think step-by-step (Recommended)"
    value = "standard"
  }
  option {
    name  = "Design-First - Design proposal before code"
    value = "design-first"
  }
  option {
    name  = "Unrestricted - Original tool behavior"
    value = "unrestricted"
  }
}

data "coder_parameter" "guardrail_action" {
  name         = "guardrail_action"
  display_name = "Sensitive Data Handling"
  description  = "How to handle detected PII, secrets, and financial data in AI prompts."
  type         = "string"
  default      = "mask"
  mutable      = false
  icon         = "/icon/widgets.svg"

  option {
    name  = "Mask - Redact sensitive data and proceed (Recommended)"
    value = "mask"
  }
  option {
    name  = "Block - Reject requests containing sensitive data"
    value = "block"
  }
}

data "coder_parameter" "egress_extra_ports" {
  name         = "egress_extra_ports"
  display_name = "Network Egress Exceptions"
  description  = "Extra TCP ports this workspace can reach (comma-separated, admin-only)."
  type         = "string"
  default      = ""
  mutable      = false
  icon         = "/icon/lock.svg"
}

data "coder_parameter" "git_server_url" {
  name         = "git_server_url"
  display_name = "Git Server URL"
  description  = "URL of the Git server (e.g., http://gitea:3000)"
  type         = "string"
  default      = "http://gitea:3000"
  mutable      = true
  icon         = "/icon/git.svg"
}

data "coder_parameter" "git_username" {
  name         = "git_username"
  display_name = "Git Username"
  description  = "Your username for the Git server"
  type         = "string"
  default      = ""
  mutable      = true
  icon         = "/icon/git.svg"
}

data "coder_parameter" "git_password" {
  name         = "git_password"
  display_name = "Git Password"
  description  = "Your password for the Git server (stored securely)"
  type         = "string"
  default      = ""
  mutable      = true
  icon         = "/icon/git.svg"
}

data "coder_parameter" "database_type" {
  name         = "database_type"
  display_name = "Database Type"
  description  = "Type of database to provision for this workspace"
  type         = "string"
  default      = "none"
  mutable      = false
  icon         = "/icon/database.svg"

  option {
    name  = "None (No Database)"
    value = "none"
  }
  option {
    name  = "Individual (Personal Database)"
    value = "individual"
  }
  option {
    name  = "Team (Shared Database)"
    value = "team"
  }
}

data "coder_parameter" "team_database_name" {
  name         = "team_database_name"
  display_name = "Team Database Name"
  description  = "Name of the team database (only for Team type)"
  type         = "string"
  default      = ""
  mutable      = false
  icon         = "/icon/database.svg"
}

# ============================================================================
# CODER AGENT
# ============================================================================

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"
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
    CLAUDE_CODE_DISABLE_AUTOUPDATE   = "1"
    JAVA_HOME                        = "/usr/lib/jvm/java-11-openjdk-amd64"
  }

  # ===========================================================================
  # STARTUP SCRIPT
  # ===========================================================================
  startup_script = <<-EOT
    #!/bin/bash
    set -e

    echo "=== Starting AEM workspace initialization ==="

    # ── Phase 1: Git configuration ────────────────────────────────────
    git config --global user.name "${data.coder_workspace_owner.me.name}"
    git config --global user.email "${data.coder_workspace_owner.me.email}"

    if [ -n "${data.coder_parameter.git_username.value}" ] && [ -n "${data.coder_parameter.git_password.value}" ]; then
      echo "Configuring Git credentials for Gitea (secure cache)..."
      git config --global credential.helper 'cache --timeout=28800'
      GIT_HOST=$(echo "${data.coder_parameter.git_server_url.value}" | sed -E 's|https?://([^/]+).*|\1|')
      echo "protocol=http
host=$${GIT_HOST}
username=${data.coder_parameter.git_username.value}
password=${data.coder_parameter.git_password.value}
" | git credential approve
      echo "protocol=https
host=$${GIT_HOST}
username=${data.coder_parameter.git_username.value}
password=${data.coder_parameter.git_password.value}
" | git credential approve
      echo "Git credentials cached for $${GIT_HOST} (expires in 8h)"
    fi

    # ── Phase 2: Repository clone ─────────────────────────────────────
    if [ -n "${data.coder_parameter.git_repo.value}" ]; then
      echo "Cloning repository: ${data.coder_parameter.git_repo.value}"
      if [ ! -d "/home/coder/workspace/.git" ]; then
        git clone "${data.coder_parameter.git_repo.value}" /home/coder/workspace || true
      else
        echo "Repository already cloned, pulling latest..."
        cd /home/coder/workspace && git pull || true
      fi
    fi

    if [ -n "${data.coder_parameter.dotfiles_repo.value}" ]; then
      echo "Applying dotfiles from: ${data.coder_parameter.dotfiles_repo.value}"
      coder dotfiles "${data.coder_parameter.dotfiles_repo.value}" -y || true
    fi

    # ── Phase 3: Maven settings recovery ──────────────────────────────
    # Persistent volume may not have settings.xml on first mount
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
    AEM_JAR="${data.coder_parameter.aem_jar_path.value}"
    AEM_PUBLISHER_ENABLED="${data.coder_parameter.aem_publisher_enabled.value}"
    AEM_AUTHOR_JVM="${data.coder_parameter.aem_author_jvm_opts.value}"
    AEM_PUBLISHER_JVM="${data.coder_parameter.aem_publisher_jvm_opts.value}"
    AEM_DEBUG_PORT="${data.coder_parameter.aem_debug_port.value}"
    AEM_ADMIN_PASS="${data.coder_parameter.aem_admin_password.value}"

    if [ ! -f "$AEM_JAR" ]; then
      echo ""
      echo "============================================================"
      echo "  AEM QUICKSTART JAR NOT FOUND"
      echo "============================================================"
      echo ""
      echo "  Expected at: $AEM_JAR"
      echo ""
      echo "  The AEM quickstart JAR is proprietary and cannot be"
      echo "  baked into the workspace image."
      echo ""
      echo "  To get started:"
      echo "    1. Obtain the JAR from Adobe Software Distribution"
      echo "       (https://experience.adobe.com/#/downloads/content/software-distribution/en/aem.html)"
      echo "    2. Upload it to your workspace:"
      echo "       coder scp local:aem-quickstart-6.5.x.jar <workspace>:$AEM_JAR"
      echo "    3. Restart the workspace"
      echo ""
      echo "  VS Code and Maven are ready — you can work on code"
      echo "  without AEM running. Deploy when AEM is available."
      echo "============================================================"
      echo ""
    else
      # --- AEM Author startup ---
      echo "Starting AEM Author instance..."
      mkdir -p /home/coder/aem/author
      cd /home/coder/aem/author

      # Copy JAR on first start (crx-quickstart doesn't exist yet)
      if [ ! -d /home/coder/aem/author/crx-quickstart ]; then
        echo "First start detected — copying quickstart JAR (initial unpack takes 5-10 minutes)..."
        cp "$AEM_JAR" /home/coder/aem/author/aem-quickstart.jar
      fi

      # Start Author with JPDA debug enabled
      java $AEM_AUTHOR_JVM \
        -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:$AEM_DEBUG_PORT \
        -Dsling.run.modes=author \
        -jar /home/coder/aem/author/aem-quickstart.jar \
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

        if [ ! -d /home/coder/aem/publisher/crx-quickstart ]; then
          echo "First Publisher start — copying quickstart JAR..."
          cp "$AEM_JAR" /home/coder/aem/publisher/aem-quickstart.jar
        fi

        java $AEM_PUBLISHER_JVM \
          -Dsling.run.modes=publish \
          -jar /home/coder/aem/publisher/aem-quickstart.jar \
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
    AI_MODEL="${data.coder_parameter.ai_model.value}"
    AI_GATEWAY_URL="${data.coder_parameter.ai_gateway_url.value}"
    ENFORCEMENT_LEVEL="${data.coder_parameter.ai_enforcement_level.value}"
    GUARDRAIL_ACTION="${data.coder_parameter.guardrail_action.value}"

    if [ "$AI_ASSISTANT" = "claude-code" ]; then
      ENFORCEMENT_LEVEL="unrestricted"
    fi

    if [ "$AI_ASSISTANT" != "none" ]; then
      case "$AI_MODEL" in
        "glm-4.7")              LITELLM_MODEL="glm-4.7" ;;
        "claude-sonnet")         LITELLM_MODEL="claude-sonnet-4-5" ;;
        "claude-haiku")          LITELLM_MODEL="claude-haiku-4-5" ;;
        "claude-opus")           LITELLM_MODEL="claude-opus-4" ;;
        "bedrock-claude-sonnet") LITELLM_MODEL="bedrock-claude-sonnet" ;;
        "bedrock-claude-haiku")  LITELLM_MODEL="bedrock-claude-haiku" ;;
        *)                       LITELLM_MODEL="glm-4.7" ;;
      esac

      # Auto-provision key if not provided
      if [ -z "$LITELLM_KEY" ]; then
        echo "Auto-provisioning AI API key via key-provisioner..."
        PROVISIONER_URL="http://key-provisioner:8100"
        WORKSPACE_ID="${data.coder_workspace.me.id}"
        WORKSPACE_OWNER="${data.coder_workspace_owner.me.name}"
        WORKSPACE_NAME="${data.coder_workspace.me.name}"

        for attempt in 1 2 3; do
          RESPONSE=$(curl -sf -X POST "$PROVISIONER_URL/api/v1/keys/workspace" \
            -H "Authorization: Bearer $PROVISIONER_SECRET" \
            -H "Content-Type: application/json" \
            -d "{\"workspace_id\": \"$WORKSPACE_ID\", \"username\": \"$WORKSPACE_OWNER\", \"workspace_name\": \"$WORKSPACE_NAME\", \"enforcement_level\": \"$ENFORCEMENT_LEVEL\"}" \
            2>/dev/null) && break
          echo "Key provisioner not ready (attempt $attempt/3), retrying in 5s..."
          sleep 5
        done

        if [ -n "$RESPONSE" ]; then
          LITELLM_KEY=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('key',''))" 2>/dev/null || echo "")
          if [ -n "$LITELLM_KEY" ]; then
            REUSED=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('reused',False))" 2>/dev/null || echo "")
            echo "AI API key provisioned (reused=$REUSED)"
          else
            echo "WARNING: Key provisioner returned empty key"
          fi
        else
          echo "WARNING: Could not reach key provisioner after 3 attempts"
        fi
      fi

      if [ -n "$LITELLM_KEY" ]; then
        # --- Roo Code configuration ---
        if [ "$AI_ASSISTANT" = "roo-code" ] || [ "$AI_ASSISTANT" = "both" ] || [ "$AI_ASSISTANT" = "all" ]; then
          echo "Configuring Roo Code with LiteLLM proxy..."
          mkdir -p /home/coder/.config/roo-code

          CUSTOM_INSTRUCTIONS=""
          case "$ENFORCEMENT_LEVEL" in
            "standard")
              CUSTOM_INSTRUCTIONS="You are a thoughtful software engineer. Think step-by-step before coding. Explain your approach before implementing. Consider existing codebase patterns. Prefer incremental, focused changes. When modifying code, explain what and why."
              ;;
            "design-first")
              CUSTOM_INSTRUCTIONS="DESIGN-FIRST REQUIRED: Before writing ANY code, present a design proposal (problem, approach, files to modify, tradeoffs). Ask for confirmation before implementing. Never write code in the same response as the design proposal. Small fixes are exempt but still need brief explanation."
              ;;
          esac

          if [ -n "$CUSTOM_INSTRUCTIONS" ]; then
            cat > /home/coder/.config/roo-code/settings.json << ROOCONFIG
{
  "providerProfiles": {
    "currentApiConfigName": "litellm",
    "apiConfigs": {
      "litellm": {
        "apiProvider": "openai",
        "openAiBaseUrl": "http://litellm:4000/v1",
        "openAiApiKey": "$LITELLM_KEY",
        "openAiModelId": "$LITELLM_MODEL",
        "id": "litellm-default"
      }
    }
  },
  "globalSettings": {
    "customInstructions": "$CUSTOM_INSTRUCTIONS"
  }
}
ROOCONFIG
          else
            cat > /home/coder/.config/roo-code/settings.json << ROOCONFIG
{
  "providerProfiles": {
    "currentApiConfigName": "litellm",
    "apiConfigs": {
      "litellm": {
        "apiProvider": "openai",
        "openAiBaseUrl": "http://litellm:4000/v1",
        "openAiApiKey": "$LITELLM_KEY",
        "openAiModelId": "$LITELLM_MODEL",
        "id": "litellm-default"
      }
    }
  }
}
ROOCONFIG
          fi
          echo "Roo Code configured: model=$LITELLM_MODEL enforcement=$ENFORCEMENT_LEVEL"
        fi

        # --- OpenCode CLI configuration ---
        if [ "$AI_ASSISTANT" = "opencode" ] || [ "$AI_ASSISTANT" = "both" ] || [ "$AI_ASSISTANT" = "all" ]; then
          if [ -x /home/coder/.opencode/bin/opencode ]; then
            echo "Configuring OpenCode CLI with LiteLLM proxy..."
            mkdir -p /home/coder/.config/opencode

            OPENCODE_INSTRUCTIONS=""
            if [ "$ENFORCEMENT_LEVEL" != "unrestricted" ]; then
              case "$ENFORCEMENT_LEVEL" in
                "standard")
                  cat > /home/coder/.config/opencode/enforcement.md << 'ENFORCEMENTMD'
## Development Guidelines

You are a thoughtful software engineer. Follow these practices:

1. **Think before coding** — Understand the problem fully before writing code
2. **Explain your approach** — State what you plan to do and why before implementing
3. **Consider the existing codebase** — Read and understand existing patterns before modifying
4. **Incremental changes** — Prefer small, focused changes over large rewrites
5. **Edge cases** — Consider error handling and boundary conditions
6. **Simplicity** — Choose the simplest solution that meets requirements

When modifying existing code, explain what you're changing and why.
ENFORCEMENTMD
                  ;;
                "design-first")
                  cat > /home/coder/.config/opencode/enforcement.md << 'ENFORCEMENTMD'
## MANDATORY: Design-First Development Process

You are a senior software architect and engineer. You MUST follow a structured workflow.

### Before Writing ANY Code

1. **Design Proposal** (REQUIRED for non-trivial changes):
   - Describe the problem or requirement
   - Outline your approach (architecture, data flow, key abstractions)
   - List files to create or modify
   - Identify tradeoffs and alternatives considered
   - State assumptions and risks

2. **Await Confirmation** — Present your design and ask:
   "Shall I proceed with this approach?"
   Do NOT write implementation code until confirmed.

3. **Implement Incrementally** — After confirmation:
   - Reference your design as you implement
   - If the design needs revision, stop and propose changes
   - Keep changes minimal and focused on the stated scope

### Rules
- NEVER skip the design step for non-trivial changes
- NEVER write code in the same response as the design proposal
- Small fixes (typos, formatting, single-line changes) are exempt but still need brief explanation
ENFORCEMENTMD
                  ;;
              esac
              OPENCODE_INSTRUCTIONS='"instructions": ["/home/coder/.config/opencode/enforcement.md"],'
            fi

            cat > /home/coder/.config/opencode/opencode.json << OPENCODECONFIG
{
  "\$schema": "https://opencode.ai/config.json",
  $OPENCODE_INSTRUCTIONS
  "provider": {
    "litellm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "LiteLLM",
      "options": {
        "baseURL": "http://litellm:4000/v1",
        "apiKey": "$LITELLM_KEY"
      },
      "models": {
        "glm-4.7": { "name": "GLM-4.7 (Local)" },
        "claude-sonnet-4-5": { "name": "Claude Sonnet 4.5" },
        "claude-haiku-4-5": { "name": "Claude Haiku 4.5" },
        "claude-opus-4": { "name": "Claude Opus 4" },
        "bedrock-claude-sonnet": { "name": "Bedrock Claude Sonnet" },
        "bedrock-claude-haiku": { "name": "Bedrock Claude Haiku" }
      }
    }
  },
  "model": "litellm/$LITELLM_MODEL",
  "small_model": "litellm/glm-4.7"
}
OPENCODECONFIG
            echo "OpenCode configured: model=litellm/$LITELLM_MODEL enforcement=$ENFORCEMENT_LEVEL"
          else
            echo "Note: OpenCode CLI not found at ~/.opencode/bin/opencode, skipping configuration"
          fi
        fi

        # --- Claude Code CLI configuration ---
        if [ "$AI_ASSISTANT" = "claude-code" ] || [ "$AI_ASSISTANT" = "all" ]; then
          if command -v claude >/dev/null 2>&1; then
            echo "Configuring Claude Code CLI..."
            mkdir -p /home/coder/.claude

            cat > /home/coder/.claude/settings.json << 'CLAUDECONFIG'
{
  "permissions": {
    "allow": [
      "Bash(git log:*)",
      "Bash(git diff:*)",
      "Bash(git status:*)",
      "Bash(mvn:*)",
      "Bash(java:*)",
      "Bash(node:*)",
      "Bash(npm:*)",
      "Bash(ls:*)",
      "Bash(cat:*)",
      "Bash(find:*)",
      "Bash(grep:*)",
      "Read",
      "Write",
      "Edit"
    ],
    "deny": [
      "Bash(curl:*)",
      "Bash(wget:*)",
      "Bash(ssh:*)",
      "Bash(scp:*)"
    ]
  }
}
CLAUDECONFIG
            echo "Claude Code configured: gateway=litellm:4000/anthropic enforcement=$ENFORCEMENT_LEVEL"
          else
            echo "Note: Claude Code CLI not found, skipping configuration"
          fi
        fi

        # --- Environment variables for CLI AI tools ---
        cat >> ~/.bashrc << AICONFIG
# AI Configuration (LiteLLM)
export PATH="/home/coder/.opencode/bin:\$PATH"
export AI_GATEWAY_URL="http://litellm:4000"
export OPENAI_API_BASE="http://litellm:4000/v1"
export OPENAI_API_KEY="$LITELLM_KEY"
export AI_MODEL="$LITELLM_MODEL"
alias ai-models="echo 'Agent: $AI_ASSISTANT, Model: $LITELLM_MODEL, Gateway: litellm:4000'"
alias ai-usage="curl -s http://litellm:4000/user/info -H 'Authorization: Bearer $LITELLM_KEY' | python3 -m json.tool"
AICONFIG

        if [ "$AI_ASSISTANT" = "claude-code" ] || [ "$AI_ASSISTANT" = "all" ]; then
          cat >> ~/.bashrc << CLAUDEENV
# Claude Code CLI (Anthropic Enterprise — native auth)
alias claude-litellm='ANTHROPIC_BASE_URL="http://litellm:4000/anthropic" ANTHROPIC_API_KEY="\$OPENAI_API_KEY" ANTHROPIC_AUTH_TOKEN="" claude'
alias claude-local='ANTHROPIC_BASE_URL="http://host.docker.internal:11434" ANTHROPIC_AUTH_TOKEN="ollama" claude'
CLAUDEENV
        fi
        echo "AI environment configured: gateway=litellm:4000"
      else
        echo "Note: No AI API key available. Ask your platform admin or use the self-service script."
      fi
    else
      echo "AI assistant disabled"
    fi

    # ── Phase 6: Database Provisioning ────────────────────────────────
    DB_TYPE="${data.coder_parameter.database_type.value}"
    TEAM_DB_NAME="${data.coder_parameter.team_database_name.value}"
    WORKSPACE_OWNER="${data.coder_workspace_owner.me.name}"
    WORKSPACE_ID="${data.coder_workspace.me.id}"

    if [ "$DB_TYPE" != "none" ]; then
      echo "Provisioning database (type: $DB_TYPE)..."
      export DEVDB_HOST="devdb"
      export DEVDB_PORT="5432"
      export DEVDB_ADMIN_USER="workspace_provisioner"
      export DEVDB_ADMIN_PASSWORD="provisioner123"

      if [ "$DB_TYPE" = "individual" ]; then
        DB_NAME="dev_$${WORKSPACE_OWNER//[^a-zA-Z0-9]/_}"
        PGPASSWORD="$DEVDB_ADMIN_PASSWORD" psql -h "$DEVDB_HOST" -p "$DEVDB_PORT" \
          -U "$DEVDB_ADMIN_USER" -d devdb -t -A \
          -c "SELECT * FROM provisioning.create_individual_db('$WORKSPACE_OWNER', '$WORKSPACE_ID');" \
          > /tmp/db_creds.txt 2>/dev/null || true

        if [ -f /tmp/db_creds.txt ] && [ -s /tmp/db_creds.txt ]; then
          DB_NAME=$(cut -d'|' -f1 < /tmp/db_creds.txt)
          DB_USER=$(cut -d'|' -f2 < /tmp/db_creds.txt)
          DB_PASS=$(cut -d'|' -f3 < /tmp/db_creds.txt)
          echo "Individual database provisioned: $DB_NAME"
          cat >> ~/.bashrc << DBCONFIG
# Developer Database Configuration
export DEVDB_HOST="devdb"
export DEVDB_PORT="5432"
export DEVDB_NAME="$DB_NAME"
export DEVDB_USER="$DB_USER"
export DATABASE_URL="postgresql://$DB_USER@devdb:5432/$DB_NAME"
DBCONFIG
        else
          echo "Note: DevDB not available - database not provisioned"
        fi

      elif [ "$DB_TYPE" = "team" ] && [ -n "$TEAM_DB_NAME" ]; then
        PGPASSWORD="$DEVDB_ADMIN_PASSWORD" psql -h "$DEVDB_HOST" -p "$DEVDB_PORT" \
          -U "$DEVDB_ADMIN_USER" -d devdb -t -A \
          -c "SELECT * FROM provisioning.create_team_db('$TEAM_DB_NAME', '$WORKSPACE_OWNER');" \
          > /tmp/db_creds.txt 2>/dev/null || true

        if [ -f /tmp/db_creds.txt ] && [ -s /tmp/db_creds.txt ]; then
          DB_NAME=$(cut -d'|' -f1 < /tmp/db_creds.txt)
          DB_USER=$(cut -d'|' -f2 < /tmp/db_creds.txt)
          echo "Team database configured: $DB_NAME"
          cat >> ~/.bashrc << DBCONFIG
# Team Database Configuration
export DEVDB_HOST="devdb"
export DEVDB_PORT="5432"
export DEVDB_NAME="$DB_NAME"
export DEVDB_USER="$DB_USER"
export DATABASE_URL="postgresql://$DB_USER@devdb:5432/$DB_NAME"
DBCONFIG
        fi
      fi
      rm -f /tmp/db_creds.txt
    fi

    # ── Phase 7: Ollama (Host Mac GPU) ────────────────────────────────
    OLLAMA_URL="http://host.docker.internal:11434"
    if curl -sf "$OLLAMA_URL" >/dev/null 2>&1; then
      echo "Host Ollama reachable at $OLLAMA_URL"
    else
      echo "WARNING: Host Ollama not reachable at $OLLAMA_URL"
    fi
    cat >> ~/.bashrc << 'OLLAMACONFIG'
# Ollama — Host Mac's Ollama server (GPU-accelerated)
export OLLAMA_HOST=http://host.docker.internal:11434
OLLAMACONFIG

    # ── Phase 8: AEM convenience aliases ──────────────────────────────
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

# Instance management
aem-start-author() {
  local JAR="/home/coder/aem/aem-quickstart.jar"
  [ ! -f /home/coder/aem/author/aem-quickstart.jar ] && cp "$JAR" /home/coder/aem/author/aem-quickstart.jar
  cd /home/coder/aem/author
  java $${AEM_AUTHOR_JVM:-"-Xmx2048m"} \
    -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:$${AEM_DEBUG_PORT:-5005} \
    -Dsling.run.modes=author \
    -jar aem-quickstart.jar -p 4502 -r author -nobrowser -nofork > stdout.log 2>&1 &
  echo $! > /home/coder/aem/author.pid
  echo "AEM Author starting (PID: $!)"
  cd -
}

aem-stop-author() {
  if [ -f /home/coder/aem/author.pid ]; then
    local PID=$(cat /home/coder/aem/author.pid)
    if kill -0 "$PID" 2>/dev/null; then
      echo "Stopping AEM Author (PID: $PID)..."
      kill "$PID"
      for i in $(seq 1 30); do
        kill -0 "$PID" 2>/dev/null || { echo "AEM Author stopped"; rm -f /home/coder/aem/author.pid; return 0; }
        sleep 2
      done
      echo "Force-killing AEM Author..."
      kill -9 "$PID" 2>/dev/null
      rm -f /home/coder/aem/author.pid
    else
      echo "AEM Author not running (stale PID file)"
      rm -f /home/coder/aem/author.pid
    fi
  else
    echo "No Author PID file found"
  fi
}

aem-start-publisher() {
  local JAR="/home/coder/aem/aem-quickstart.jar"
  [ ! -f /home/coder/aem/publisher/aem-quickstart.jar ] && cp "$JAR" /home/coder/aem/publisher/aem-quickstart.jar
  cd /home/coder/aem/publisher
  java $${AEM_PUBLISHER_JVM:-"-Xmx1024m"} \
    -Dsling.run.modes=publish \
    -jar aem-quickstart.jar -p 4503 -r publish -nobrowser -nofork > stdout.log 2>&1 &
  echo $! > /home/coder/aem/publisher.pid
  echo "AEM Publisher starting (PID: $!)"
  cd -
}

aem-stop-publisher() {
  if [ -f /home/coder/aem/publisher.pid ]; then
    local PID=$(cat /home/coder/aem/publisher.pid)
    if kill -0 "$PID" 2>/dev/null; then
      echo "Stopping AEM Publisher (PID: $PID)..."
      kill "$PID"
      for i in $(seq 1 30); do
        kill -0 "$PID" 2>/dev/null || { echo "AEM Publisher stopped"; rm -f /home/coder/aem/publisher.pid; return 0; }
        sleep 2
      done
      echo "Force-killing AEM Publisher..."
      kill -9 "$PID" 2>/dev/null
      rm -f /home/coder/aem/publisher.pid
    else
      echo "AEM Publisher not running (stale PID file)"
      rm -f /home/coder/aem/publisher.pid
    fi
  else
    echo "No Publisher PID file found"
  fi
}
AEMALIAS

    # Export AEM JVM opts for alias functions
    cat >> ~/.bashrc << AEMENV
export AEM_AUTHOR_JVM="$AEM_AUTHOR_JVM"
export AEM_PUBLISHER_JVM="$AEM_PUBLISHER_JVM"
export AEM_DEBUG_PORT="$AEM_DEBUG_PORT"
AEMENV

    # ── Phase 9: Start code-server ────────────────────────────────────
    echo "Starting code-server..."

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

    code-server --auth none --bind-addr 0.0.0.0:8080 /home/coder/workspace > /tmp/code-server.log 2>&1 &

    # ── Phase 10: Status output ───────────────────────────────────────
    echo ""
    echo "=== AEM Workspace Ready ==="
    echo "Git Server: ${data.coder_parameter.git_server_url.value}"
    echo "AI Gateway: $${AI_GATEWAY_URL}"
    echo "AI Agent: $${AI_ASSISTANT}"
    echo "AI Behavior: $${ENFORCEMENT_LEVEL}"
    echo "Ollama: host.docker.internal:11434 (host Mac)"
    if [ "$AI_ASSISTANT" = "claude-code" ] || [ "$AI_ASSISTANT" = "all" ]; then
      echo "Claude Code: Anthropic Enterprise (run 'claude login' on first use)"
    fi
    if [ "$DB_TYPE" != "none" ]; then
      echo "Database: $${DEVDB_NAME:-not provisioned} (type: $DB_TYPE)"
    fi
    echo ""
    if [ -f "$AEM_JAR" ]; then
      echo "AEM Author:    http://localhost:4502 (JPDA debug: $AEM_DEBUG_PORT)"
      echo "  CRXDE:       http://localhost:4502/crx/de"
      echo "  Packages:    http://localhost:4502/crx/packmgr"
      echo "  Console:     http://localhost:4502/system/console"
      if [ "$AEM_PUBLISHER_ENABLED" = "true" ]; then
        echo "AEM Publisher: http://localhost:4503"
      fi
    else
      echo "AEM: Not started (quickstart JAR not found)"
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
        # Force-kill if still running after 60 seconds
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

    # Stop code-server
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
    key          = "running_processes"
    display_name = "Processes"
    script       = "ps aux | wc -l"
    interval     = 30
    timeout      = 1
    order        = 4
  }

  # AEM-specific metadata widgets
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
    order        = 5
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
    order        = 6
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
    order        = 7
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
    order        = 8
  }
}

# ============================================================================
# CODER APPS
# ============================================================================

# VS Code in browser (code-server)
resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code"
  icon         = "/icon/code.svg"
  url          = "http://localhost:8080?folder=/home/coder/workspace"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:8080/healthz"
    interval  = 5
    threshold = 10
  }
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
    threshold = 40  # ~10 minutes for first start
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

# ============================================================================
# DOCKER RESOURCES
# ============================================================================

locals {
  workspace_image = "aem-workspace:latest"
}

# Persistent volume for workspace data
resource "docker_volume" "workspace_data" {
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}-data"

  lifecycle {
    prevent_destroy = false
  }
}

# Workspace container
resource "docker_container" "workspace" {
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  image    = local.workspace_image
  hostname = lower(data.coder_workspace.me.name)

  user = "1001:1001"

  # Higher resource defaults for AEM
  cpu_shares = data.coder_parameter.cpu_cores.value * 1024
  memory     = data.coder_parameter.memory_gb.value * 1024 * 1024 * 1024

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "CODER_WORKSPACE_NAME=${data.coder_workspace.me.name}",
    "CODER_WORKSPACE_OWNER=${data.coder_workspace_owner.me.name}",
    "GIT_AUTHOR_NAME=${data.coder_workspace_owner.me.name}",
    "GIT_AUTHOR_EMAIL=${data.coder_workspace_owner.me.email}",
    "GIT_COMMITTER_NAME=${data.coder_workspace_owner.me.name}",
    "GIT_COMMITTER_EMAIL=${data.coder_workspace_owner.me.email}",
    # AI Configuration
    "AI_MODEL=${data.coder_parameter.ai_model.value}",
    "AI_GATEWAY_URL=${data.coder_parameter.ai_gateway_url.value}",
    "LITELLM_API_KEY=${data.coder_parameter.litellm_api_key.value}",
    "ENFORCEMENT_LEVEL=${data.coder_parameter.ai_enforcement_level.value}",
    # Key Provisioner
    "PROVISIONER_SECRET=poc-provisioner-secret-change-in-production",
    # TLS: Trust self-signed Coder certificate
    "SSL_CERT_FILE=/certs/coder.crt",
    "NODE_EXTRA_CA_CERTS=/certs/coder.crt",
    # Network egress exceptions
    "EGRESS_EXTRA_PORTS=${data.coder_parameter.egress_extra_ports.value}",
    # Ollama
    "OLLAMA_HOST=http://host.docker.internal:11434",
    # Java (AEM 6.5 requires Java 11)
    "JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64",
  ]

  # Install self-signed TLS cert + apply firewall + start agent
  entrypoint = ["sh", "-c", <<-EOT
    if [ -f /certs/coder.crt ]; then
      sudo cp /certs/coder.crt /usr/local/share/ca-certificates/coder.crt
      sudo update-ca-certificates
    fi
    sudo /usr/local/bin/setup-firewall.sh || echo "WARNING: Firewall setup failed (iptables may not be available)"
    ${coder_agent.main.init_script}
  EOT
  ]

  # Persistent volume
  volumes {
    volume_name    = docker_volume.workspace_data.name
    container_path = "/home/coder"
  }

  # TLS certificate
  volumes {
    host_path      = "/Users/andymini/ai/dev-platform/coder-poc/certs"
    container_path = "/certs"
    read_only      = true
  }

  # Egress firewall: global rules
  volumes {
    host_path      = "/Users/andymini/ai/dev-platform/coder-poc/egress/global.conf"
    container_path = "/etc/egress-global.conf"
    read_only      = true
  }
  # Egress firewall: AEM template rules
  volumes {
    host_path      = "/Users/andymini/ai/dev-platform/coder-poc/egress/aem-workspace.conf"
    container_path = "/etc/egress-template.conf"
    read_only      = true
  }

  # Connect to Coder network
  networks_advanced {
    name = "coder-network"
  }

  must_run    = true
  start       = true
  restart     = "unless-stopped"
  working_dir = "/home/coder/workspace"

  security_opts = ["no-new-privileges:true"]

  capabilities {
    add = ["NET_ADMIN"]
  }

  lifecycle {
    ignore_changes = [env]
  }

  labels {
    label = "coder.workspace.id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace.name"
    value = data.coder_workspace.me.name
  }
  labels {
    label = "coder.workspace.owner"
    value = data.coder_workspace_owner.me.name
  }
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "workspace_url" {
  value       = "Access VS Code at: ${data.coder_workspace.me.access_url}/apps/code-server"
  description = "URL to access the workspace"
}

output "aem_author_url" {
  value       = "AEM Author: ${data.coder_workspace.me.access_url}/apps/aem-author"
  description = "URL to access AEM Author via Coder"
}
