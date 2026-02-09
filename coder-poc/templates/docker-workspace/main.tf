# Docker-Enabled Workspace Template for Coder (PoC Option C: Rootless DinD)
#
# Same as python-workspace but adds a rootless DinD sidecar container.
# The workspace container connects to it via DOCKER_HOST=tcp://...
#
# See: coder-poc/docs/DOCKER-DEV.md Section 5

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
# These allow users to customize their workspace when creating it
# ============================================================================

data "coder_parameter" "cpu_cores" {
  name         = "cpu_cores"
  display_name = "CPU Cores"
  description  = "Number of CPU cores allocated to the workspace"
  type         = "number"
  default      = "2"
  mutable      = true
  icon         = "/icon/memory.svg"

  option {
    name  = "2 Cores (Standard)"
    value = "2"
  }
  option {
    name  = "4 Cores (Performance)"
    value = "4"
  }
}

data "coder_parameter" "memory_gb" {
  name         = "memory_gb"
  display_name = "Memory (GB)"
  description  = "RAM allocation for the workspace"
  type         = "number"
  default      = "4"
  mutable      = true
  icon         = "/icon/memory.svg"

  option {
    name  = "4 GB (Standard)"
    value = "4"
  }
  option {
    name  = "8 GB (Performance)"
    value = "8"
  }
}

data "coder_parameter" "disk_size" {
  name         = "disk_size"
  display_name = "Disk Size (GB)"
  description  = "Persistent storage for workspace data"
  type         = "number"
  default      = "20"
  mutable      = false
  icon         = "/icon/database.svg"

  option {
    name  = "20 GB"
    value = "20"
  }
  option {
    name  = "50 GB"
    value = "50"
  }
}

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

# Developer background - helps customize experience
data "coder_parameter" "developer_background" {
  name         = "developer_background"
  display_name = "Developer Background"
  description  = "Your primary IDE background (for keybindings and UI)"
  type         = "string"
  default      = "vscode"
  mutable      = true
  icon         = "/icon/code.svg"

  option {
    name  = "VS Code User"
    value = "vscode"
  }
  option {
    name  = "IntelliJ/JetBrains User"
    value = "intellij"
  }
  option {
    name  = "Visual Studio User"
    value = "visualstudio"
  }
  option {
    name  = "Vim/Neovim User"
    value = "vim"
  }
}

# Primary language stack
data "coder_parameter" "language_stack" {
  name         = "language_stack"
  display_name = "Primary Language"
  description  = "Your primary development language (optimizes extensions)"
  type         = "string"
  default      = "python"
  mutable      = true
  icon         = "/icon/code.svg"

  option {
    name  = "Python"
    value = "python"
  }
}

# AI assistant preference
data "coder_parameter" "ai_assistant" {
  name         = "ai_assistant"
  display_name = "AI Coding Agent"
  description  = "AI coding agent for development assistance"
  type         = "string"
  default      = "both"
  mutable      = true
  icon         = "/icon/widgets.svg"

  option {
    name  = "Roo Code + OpenCode (Recommended)"
    value = "both"
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

# LiteLLM virtual key (auto-provisioned if left empty)
data "coder_parameter" "litellm_api_key" {
  name         = "litellm_api_key"
  display_name = "AI API Key"
  description  = "Leave empty for auto-provisioning, or paste a key from your admin"
  type         = "string"
  default      = ""
  mutable      = true
  icon         = "/icon/widgets.svg"
}

# AI Model selection
data "coder_parameter" "ai_model" {
  name         = "ai_model"
  display_name = "AI Model"
  description  = "Select the AI model for chat and code assistance"
  type         = "string"
  default      = "bedrock-claude-haiku"
  mutable      = true
  icon         = "/icon/widgets.svg"

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

# AI Gateway URL
data "coder_parameter" "ai_gateway_url" {
  name         = "ai_gateway_url"
  display_name = "AI Gateway URL"
  description  = "URL of the AI Gateway proxy (LiteLLM)"
  type         = "string"
  default      = "http://litellm:4000"
  mutable      = true
  icon         = "/icon/widgets.svg"
}

# AI Behavior Mode (enforcement level)
data "coder_parameter" "ai_enforcement_level" {
  name         = "ai_enforcement_level"
  display_name = "AI Behavior Mode"
  description  = "Controls how AI agents approach tasks. Set by admin at workspace creation — cannot be changed by the user afterward."
  type         = "string"
  default      = "standard"
  mutable      = false  # SECURITY: Immutable — admin sets this, contractors cannot change it
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

# ==========================================================================
# NETWORK EGRESS EXCEPTIONS (Admin-Controlled)
# ==========================================================================

data "coder_parameter" "egress_extra_ports" {
  name         = "egress_extra_ports"
  display_name = "Network Egress Exceptions"
  description  = "Extra TCP ports this workspace can reach (comma-separated, admin-only). Example: 8443,8888,3128. Set at workspace creation by admin."
  type         = "string"
  default      = ""
  mutable      = false  # SECURITY: Immutable — only admin sets this at workspace creation
  icon         = "/icon/lock.svg"
}

# ==========================================================================
# GIT SERVER CONFIGURATION (Gitea Integration)
# ==========================================================================

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

# ==========================================================================
# DATABASE CONFIGURATION
# ==========================================================================

data "coder_parameter" "database_type" {
  name         = "database_type"
  display_name = "Database Type"
  description  = "Type of database to provision for this workspace"
  type         = "string"
  default      = "individual"
  mutable      = false
  icon         = "/icon/database.svg"

  option {
    name  = "Individual (Personal Database)"
    value = "individual"
  }
  option {
    name  = "Team (Shared Database)"
    value = "team"
  }
  option {
    name  = "None (No Database)"
    value = "none"
  }
}

data "coder_parameter" "team_database_name" {
  name         = "team_database_name"
  display_name = "Team Database Name"
  description  = "Name of the team database (only for Team type, e.g., 'frontend-team')"
  type         = "string"
  default      = ""
  mutable      = false
  icon         = "/icon/database.svg"
}

# ============================================================================
# LOCALS
# ============================================================================

locals {
  workspace_image = "docker-workspace:latest"
  dind_name       = "dind-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"

  # Authorization: user must be in "docker-users" group (Authentik → OIDC → Coder)
  docker_authorized = contains(data.coder_workspace_owner.me.groups, "docker-users")
}

# ============================================================================
# ACCESS CONTROL: Docker Workspace Authorization
#
# Coder OSS has no template ACLs. This check enforces group-based access:
#   1. Admin creates "docker-users" group in Authentik
#   2. Authentik OIDC token includes "groups" claim
#   3. Coder syncs groups (CODER_OIDC_GROUP_FIELD=groups)
#   4. This template checks data.coder_workspace_owner.me.groups
#
# Users NOT in "docker-users" get a clear error at workspace creation time.
# See: coder-poc/docs/DOCKER-DEV.md Section 17
# ============================================================================

resource "null_resource" "docker_access_check" {
  count = local.docker_authorized ? 0 : 1

  lifecycle {
    precondition {
      condition     = local.docker_authorized
      error_message = <<-EOT
        ACCESS DENIED: Docker workspace requires membership in the "docker-users" group.

        Your groups: ${jsonencode(data.coder_workspace_owner.me.groups)}

        To request access:
          1. Ask your platform admin to add you to the "docker-users" group in Authentik
          2. Log out and log back in (group changes sync on login)
          3. Try creating this workspace again

        If you don't need Docker, use the standard python-workspace template instead.
      EOT
    }
  }
}

# ============================================================================
# ROOTLESS DinD SIDECAR (Option C: Secure Docker support)
# ============================================================================

# Persistent volume for DinD data (Docker images, layers, containers)
resource "docker_volume" "dind_data" {
  # Block provisioning if user is not authorized
  depends_on = [null_resource.docker_access_check]

  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}-dind"

  lifecycle {
    prevent_destroy = false
  }
}

# Rootless DinD sidecar — isolated Docker daemon per workspace
resource "docker_container" "dind" {
  name    = local.dind_name
  image   = "docker:dind-rootless"
  restart = "unless-stopped"

  # Rootless DinD requires these security opts instead of --privileged
  security_opts = ["seccomp=unconfined", "apparmor=unconfined"]

  # Disable TLS for simplicity (traffic stays within Docker network)
  env = [
    "DOCKER_TLS_CERTDIR=",
  ]

  # Expose Docker API on port 2375 (no TLS, internal network only)
  ports {
    internal = 2375
  }

  # Persistent Docker data (images survive workspace restarts)
  volumes {
    volume_name    = docker_volume.dind_data.name
    container_path = "/home/rootless/.local/share/docker"
  }

  # Resource constraints for the DinD sidecar
  memory     = 2 * 1024 * 1024 * 1024  # 2 GB for Docker daemon + user containers
  cpu_shares = 1024                      # 1 CPU share

  # Same network as workspace
  networks_advanced {
    name = "coder-network"
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
  labels {
    label = "coder.workspace.role"
    value = "dind-sidecar"
  }
}

# ============================================================================
# CODER AGENT
# ============================================================================

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  dir  = "/home/coder/workspace"

  display_apps {
    vscode          = false
    vscode_insiders = false
    web_terminal    = true
    ssh_helper      = false
    port_forwarding_helper = false
  }

  # Docker is available via the DinD sidecar
  env = {
    CODER_AGENT_DEVCONTAINERS_ENABLE = "false"
  }

  startup_script = <<-EOT
    #!/bin/bash
    set -e

    echo "=== Starting Docker-enabled workspace initialization ==="

    # Configure git with user info
    git config --global user.name "${data.coder_workspace_owner.me.name}"
    git config --global user.email "${data.coder_workspace_owner.me.email}"

    # Configure Git credential caching for Gitea
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
      echo "Git credentials cached in memory for $${GIT_HOST} (expires in 8h)"
    fi

    # Clone project repository if specified
    if [ -n "${data.coder_parameter.git_repo.value}" ]; then
      echo "Cloning repository: ${data.coder_parameter.git_repo.value}"
      if [ ! -d "/home/coder/workspace/.git" ]; then
        git clone "${data.coder_parameter.git_repo.value}" /home/coder/workspace || true
      else
        echo "Repository already cloned, pulling latest..."
        cd /home/coder/workspace && git pull || true
      fi
    fi

    # Apply dotfiles if specified
    if [ -n "${data.coder_parameter.dotfiles_repo.value}" ]; then
      echo "Applying dotfiles from: ${data.coder_parameter.dotfiles_repo.value}"
      coder dotfiles "${data.coder_parameter.dotfiles_repo.value}" -y || true
    fi

    # ==========================================================================
    # DOCKER: Wait for DinD sidecar to be ready
    # ==========================================================================
    echo "Waiting for Docker daemon (rootless DinD sidecar)..."
    for attempt in $(seq 1 30); do
      if docker info >/dev/null 2>&1; then
        echo "Docker daemon ready (attempt $attempt)"
        docker version --format 'Client: {{.Client.Version}}, Server: {{.Server.Version}}'
        break
      fi
      if [ "$attempt" = "30" ]; then
        echo "WARNING: Docker daemon not ready after 30 attempts"
      fi
      sleep 2
    done

    # ==========================================================================
    # AI AGENT CONFIGURATION (same as python-workspace)
    # ==========================================================================
    AI_ASSISTANT="${data.coder_parameter.ai_assistant.value}"
    LITELLM_KEY="${data.coder_parameter.litellm_api_key.value}"
    AI_MODEL="${data.coder_parameter.ai_model.value}"
    AI_GATEWAY_URL="${data.coder_parameter.ai_gateway_url.value}"
    ENFORCEMENT_LEVEL="${data.coder_parameter.ai_enforcement_level.value}"

    if [ "$AI_ASSISTANT" != "none" ]; then
      case "$AI_MODEL" in
        "claude-sonnet")         LITELLM_MODEL="claude-sonnet-4-5" ;;
        "claude-haiku")          LITELLM_MODEL="claude-haiku-4-5" ;;
        "claude-opus")           LITELLM_MODEL="claude-opus-4" ;;
        "bedrock-claude-sonnet") LITELLM_MODEL="bedrock-claude-sonnet" ;;
        "bedrock-claude-haiku")  LITELLM_MODEL="bedrock-claude-haiku" ;;
        *)                       LITELLM_MODEL="claude-sonnet-4-5" ;;
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

      # Configure AI tools if we have a key
      if [ -n "$LITELLM_KEY" ]; then
        # --- Roo Code configuration ---
        if [ "$AI_ASSISTANT" = "roo-code" ] || [ "$AI_ASSISTANT" = "both" ]; then
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
        if [ "$AI_ASSISTANT" = "opencode" ] || [ "$AI_ASSISTANT" = "both" ]; then
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
- If asked to "just do it", remind that design review is required by policy
- Small fixes (typos, formatting, single-line changes) are exempt but still need brief explanation
- Avoid speculative changes outside the stated scope
- Prefer clarity and maintainability over cleverness
- If context is insufficient, ask clarifying questions FIRST
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
        "claude-sonnet-4-5": { "name": "Claude Sonnet 4.5" },
        "claude-haiku-4-5": { "name": "Claude Haiku 4.5" },
        "claude-opus-4": { "name": "Claude Opus 4" },
        "bedrock-claude-sonnet": { "name": "Bedrock Claude Sonnet" },
        "bedrock-claude-haiku": { "name": "Bedrock Claude Haiku" }
      }
    }
  },
  "model": "litellm/$LITELLM_MODEL",
  "small_model": "litellm/claude-haiku-4-5"
}
OPENCODECONFIG
            echo "OpenCode configured: model=litellm/$LITELLM_MODEL enforcement=$ENFORCEMENT_LEVEL"
          else
            echo "Note: OpenCode CLI not found at ~/.opencode/bin/opencode, skipping configuration"
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
        echo "AI environment configured: gateway=litellm:4000"
      else
        echo "Note: No AI API key available. Ask your platform admin or use the self-service script."
      fi
    else
      echo "AI assistant disabled"
    fi

    # ==========================================================================
    # DATABASE PROVISIONING
    # ==========================================================================
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

    # Start code-server
    echo "Starting code-server..."
    code-server --auth none --bind-addr 0.0.0.0:8080 /home/coder/workspace > /tmp/code-server.log 2>&1 &

    echo "=== Docker-enabled workspace ready ==="
    echo "Git Server: ${data.coder_parameter.git_server_url.value}"
    echo "AI Gateway: $${AI_GATEWAY_URL}"
    echo "AI Behavior: $${ENFORCEMENT_LEVEL}"
    echo "Docker: DOCKER_HOST=tcp://${local.dind_name}:2375 (rootless DinD)"
    if [ "$DB_TYPE" != "none" ]; then
      echo "Database: $${DEVDB_NAME:-not provisioned} (type: $DB_TYPE)"
    fi
  EOT

  shutdown_script = <<-EOT
    #!/bin/bash
    echo "Workspace shutting down..."
    pkill -f code-server || true
  EOT

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

  # Docker-specific metadata
  metadata {
    key          = "docker_containers"
    display_name = "Docker Containers"
    script       = "docker ps -q 2>/dev/null | wc -l || echo 'N/A'"
    interval     = 15
    timeout      = 3
    order        = 5
  }

  metadata {
    key          = "docker_status"
    display_name = "Docker Status"
    script       = "docker info --format '{{.ServerVersion}}' 2>/dev/null || echo 'Not Ready'"
    interval     = 30
    timeout      = 3
    order        = 6
  }
}

# ============================================================================
# CODER APPS
# ============================================================================

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

# ============================================================================
# DOCKER RESOURCES
# ============================================================================

# Persistent volume for workspace data
resource "docker_volume" "workspace_data" {
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}-data"

  lifecycle {
    prevent_destroy = false
  }
}

# Workspace container
resource "docker_container" "workspace" {
  # DinD sidecar must be running before workspace starts
  depends_on = [docker_container.dind]

  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  image    = local.workspace_image
  hostname = lower(data.coder_workspace.me.name)

  user = "1001:1001"

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
    # Docker: Point to rootless DinD sidecar
    "DOCKER_HOST=tcp://${local.dind_name}:2375",
    # AI Configuration
    "AI_MODEL=${data.coder_parameter.ai_model.value}",
    "AI_GATEWAY_URL=${data.coder_parameter.ai_gateway_url.value}",
    "LITELLM_API_KEY=${data.coder_parameter.litellm_api_key.value}",
    "ENFORCEMENT_LEVEL=${data.coder_parameter.ai_enforcement_level.value}",
    # Key Provisioner
    "PROVISIONER_SECRET=poc-provisioner-secret-change-in-production",
    # TLS
    "SSL_CERT_FILE=/certs/coder.crt",
    "NODE_EXTRA_CA_CERTS=/certs/coder.crt",
    # Network egress exceptions
    "EGRESS_EXTRA_PORTS=${data.coder_parameter.egress_extra_ports.value}",
  ]

  entrypoint = ["sh", "-c", <<-EOT
    if [ -f /certs/coder.crt ]; then
      sudo cp /certs/coder.crt /usr/local/share/ca-certificates/coder.crt
      sudo update-ca-certificates
    fi
    sudo /usr/local/bin/setup-firewall.sh || echo "WARNING: Firewall setup failed (iptables may not be available)"
    ${coder_agent.main.init_script}
  EOT
  ]

  volumes {
    volume_name    = docker_volume.workspace_data.name
    container_path = "/home/coder"
  }

  volumes {
    host_path      = "/Users/andymini/ai/dev-platform/coder-poc/certs"
    container_path = "/certs"
    read_only      = true
  }

  volumes {
    host_path      = "/Users/andymini/ai/dev-platform/coder-poc/egress/global.conf"
    container_path = "/etc/egress-global.conf"
    read_only      = true
  }
  volumes {
    host_path      = "/Users/andymini/ai/dev-platform/coder-poc/egress/contractor-workspace.conf"
    container_path = "/etc/egress-template.conf"
    read_only      = true
  }

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

output "docker_host" {
  value       = "tcp://${local.dind_name}:2375"
  description = "Docker daemon endpoint (rootless DinD sidecar)"
}
