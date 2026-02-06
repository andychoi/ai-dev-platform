# Contractor Workspace Template for Coder
# This template creates a Docker-based development workspace

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
  default      = "10"
  mutable      = false
  icon         = "/icon/database.svg"

  option {
    name  = "10 GB"
    value = "10"
  }
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
  default      = "javascript"
  mutable      = true
  icon         = "/icon/code.svg"

  option {
    name  = "JavaScript/TypeScript"
    value = "javascript"
  }
  option {
    name  = "Python"
    value = "python"
  }
  option {
    name  = "Java/Kotlin"
    value = "java"
  }
  option {
    name  = "C#/.NET"
    value = "dotnet"
  }
  option {
    name  = "Go"
    value = "go"
  }
}

# AI assistant preference
data "coder_parameter" "ai_assistant" {
  name         = "ai_assistant"
  display_name = "AI Coding Agent"
  description  = "AI coding agent for development assistance"
  type         = "string"
  default      = "roo-code"
  mutable      = true
  icon         = "/icon/widgets.svg"

  option {
    name  = "Roo Code (Recommended)"
    value = "roo-code"
  }
  option {
    name  = "None"
    value = "none"
  }
}

# LiteLLM virtual key (generated per-user by admin)
data "coder_parameter" "litellm_api_key" {
  name         = "litellm_api_key"
  display_name = "AI API Key"
  description  = "Your AI API key (provided by platform admin)"
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
  default      = "claude-sonnet"
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
# Developer databases: Individual (per-user) or Team (shared)
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
# CODER AGENT
# The agent runs inside the workspace and enables Coder features
# ============================================================================

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  dir  = "/home/coder/workspace"

  # Display name in Coder UI
  # Security: Control which connection methods are available
  display_apps {
    vscode          = false  # Disabled: Prevents local VS Code connection
    vscode_insiders = false  # Disabled: Same as above
    web_terminal    = true   # Enabled: Browser-based terminal only
    ssh_helper      = false  # Disabled: Prevents SSH/SCP file transfer
    port_forwarding_helper = false  # Disabled: Prevents port forwarding
  }

  # Disable devcontainer detection (requires Docker-in-Docker which we don't support)
  env = {
    CODER_AGENT_DEVCONTAINERS_ENABLE = "false"
  }

  # Startup script runs when workspace starts
  startup_script = <<-EOT
    #!/bin/bash
    set -e

    echo "=== Starting workspace initialization ==="

    # Configure git with user info
    git config --global user.name "${data.coder_workspace_owner.me.name}"
    git config --global user.email "${data.coder_workspace_owner.me.email}"

    # Configure Git credential caching for Gitea
    # SECURITY: Use in-memory cache instead of plaintext file storage
    if [ -n "${data.coder_parameter.git_username.value}" ] && [ -n "${data.coder_parameter.git_password.value}" ]; then
      echo "Configuring Git credentials for Gitea (secure cache)..."

      # Use credential cache (in-memory, expires after 8 hours)
      git config --global credential.helper 'cache --timeout=28800'

      # Extract host from Git server URL
      GIT_HOST=$(echo "${data.coder_parameter.git_server_url.value}" | sed -E 's|https?://([^/]+).*|\1|')

      # Prime the credential cache using git-credential protocol
      # Credentials are stored in memory only, not on disk
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
    # AI AGENT CONFIGURATION (Roo Code + LiteLLM)
    # ==========================================================================
    AI_ASSISTANT="${data.coder_parameter.ai_assistant.value}"
    LITELLM_KEY="${data.coder_parameter.litellm_api_key.value}"
    AI_MODEL="${data.coder_parameter.ai_model.value}"
    AI_GATEWAY_URL="${data.coder_parameter.ai_gateway_url.value}"

    if [ "$AI_ASSISTANT" = "roo-code" ] && [ -n "$LITELLM_KEY" ]; then
      echo "Configuring Roo Code with LiteLLM proxy..."

      # Determine model name for LiteLLM
      case "$AI_MODEL" in
        "claude-sonnet")         LITELLM_MODEL="claude-sonnet-4-5" ;;
        "claude-haiku")          LITELLM_MODEL="claude-haiku-4-5" ;;
        "claude-opus")           LITELLM_MODEL="claude-opus-4" ;;
        "bedrock-claude-sonnet") LITELLM_MODEL="bedrock-claude-sonnet" ;;
        "bedrock-claude-haiku")  LITELLM_MODEL="bedrock-claude-haiku" ;;
        *)                       LITELLM_MODEL="claude-sonnet-4-5" ;;
      esac

      # Generate Roo Code auto-import config with the user's virtual key
      # Uses providerProfiles format required by Roo Code v3.x+
      mkdir -p /home/coder/.config/roo-code
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

      echo "Roo Code configured: model=$LITELLM_MODEL, gateway=litellm:4000"

      # Set environment variables for CLI AI tools
      cat >> ~/.bashrc << AICONFIG
# AI Configuration (Roo Code + LiteLLM)
export AI_GATEWAY_URL="http://litellm:4000"
export OPENAI_API_BASE="http://litellm:4000/v1"
export OPENAI_API_KEY="$LITELLM_KEY"
export AI_MODEL="$LITELLM_MODEL"
alias ai-models="echo 'Agent: Roo Code, Model: $LITELLM_MODEL, Gateway: litellm:4000'"
alias ai-usage="curl -s http://litellm:4000/user/info -H 'Authorization: Bearer $LITELLM_KEY' | python3 -m json.tool"
AICONFIG

    elif [ "$AI_ASSISTANT" = "none" ]; then
      echo "AI assistant disabled"
    else
      echo "Note: AI assistant requires an API key. Ask your platform admin for one."
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

      # DevDB connection info
      export DEVDB_HOST="devdb"
      export DEVDB_PORT="5432"
      export DEVDB_ADMIN_USER="workspace_provisioner"
      export DEVDB_ADMIN_PASSWORD="provisioner123"

      if [ "$DB_TYPE" = "individual" ]; then
        # Create individual database: dev_{username}
        DB_NAME="dev_$${WORKSPACE_OWNER//[^a-zA-Z0-9]/_}"

        # Check if database exists and create user credentials
        PGPASSWORD="$DEVDB_ADMIN_PASSWORD" psql -h "$DEVDB_HOST" -p "$DEVDB_PORT" \
          -U "$DEVDB_ADMIN_USER" -d devdb -t -A \
          -c "SELECT * FROM provisioning.create_individual_db('$WORKSPACE_OWNER', '$WORKSPACE_ID');" \
          > /tmp/db_creds.txt 2>/dev/null || true

        if [ -f /tmp/db_creds.txt ] && [ -s /tmp/db_creds.txt ]; then
          DB_NAME=$(cut -d'|' -f1 < /tmp/db_creds.txt)
          DB_USER=$(cut -d'|' -f2 < /tmp/db_creds.txt)
          DB_PASS=$(cut -d'|' -f3 < /tmp/db_creds.txt)

          echo "Individual database provisioned: $DB_NAME"

          # Save to environment
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
        # Create/connect to team database: team_{name}
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

    # Start code-server (redirect output to prevent "pipes not closed" warning)
    echo "Starting code-server..."
    code-server --auth none --bind-addr 0.0.0.0:8080 /home/coder/workspace > /tmp/code-server.log 2>&1 &

    echo "=== Workspace ready ==="
    echo "Git Server: ${data.coder_parameter.git_server_url.value}"
    echo "AI Gateway: $${AI_GATEWAY_URL}"
    if [ "$DB_TYPE" != "none" ]; then
      echo "Database: $${DEVDB_NAME:-not provisioned} (type: $DB_TYPE)"
    fi
  EOT

  # Shutdown script runs when workspace stops
  shutdown_script = <<-EOT
    #!/bin/bash
    echo "Workspace shutting down..."
    pkill -f code-server || true
  EOT

  # Metadata displayed in Coder dashboard
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
}

# ============================================================================
# CODER APPS
# Web applications accessible from the Coder dashboard
# ============================================================================

# VS Code in browser (code-server)
resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code"
  icon         = "/icon/code.svg"
  url          = "http://localhost:8080?folder=/home/coder/workspace"
  subdomain    = false  # Use path-based routing (no wildcard DNS needed)
  share        = "owner"

  healthcheck {
    url       = "http://localhost:8080/healthz"
    interval  = 5
    threshold = 10
  }
}

# NOTE: Web terminal is provided by `web_terminal = true` in display_apps
# No separate coder_app needed for terminal - the built-in web_terminal handles this

# ============================================================================
# DOCKER RESOURCES
# ============================================================================

# Reference pre-built workspace image directly (no pull/build)
# Build once with: docker build -t contractor-workspace:latest ./build
locals {
  workspace_image = "contractor-workspace:latest"
}

# Persistent volume for workspace data
resource "docker_volume" "workspace_data" {
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}-data"

  lifecycle {
    # Keep volume even if workspace is deleted (for data recovery)
    # Set to true in production
    prevent_destroy = false
  }
}

# Workspace container
resource "docker_container" "workspace" {
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  image    = local.workspace_image
  hostname = lower(data.coder_workspace.me.name)

  # Run as non-root user
  user = "1001:1001"

  # Resource constraints
  cpu_shares = data.coder_parameter.cpu_cores.value * 1024
  memory     = data.coder_parameter.memory_gb.value * 1024 * 1024 * 1024

  # Environment variables
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
    # TLS: Trust the self-signed Coder certificate so the agent can connect via HTTPS
    "SSL_CERT_FILE=/certs/coder.crt",
    "NODE_EXTRA_CA_CERTS=/certs/coder.crt",
  ]

  # Start the Coder agent
  # Install self-signed TLS cert into system trust store before agent init
  # (agent downloads its binary via curl from Coder over HTTPS)
  entrypoint = ["sh", "-c", <<-EOT
    if [ -f /certs/coder.crt ]; then
      sudo cp /certs/coder.crt /usr/local/share/ca-certificates/coder.crt
      sudo update-ca-certificates
    fi
    ${coder_agent.main.init_script}
  EOT
  ]

  # Mount persistent volume
  volumes {
    volume_name    = docker_volume.workspace_data.name
    container_path = "/home/coder"
  }

  # Mount TLS certificate so agent trusts self-signed Coder cert
  volumes {
    host_path      = "/Users/andymini/ai/dev-platform/coder-poc/certs"
    container_path = "/certs"
    read_only      = true
  }

  # Connect to Coder network
  networks_advanced {
    name = "coder-network"
  }

  # Container settings
  must_run    = true
  start       = true
  restart     = "unless-stopped"
  working_dir = "/home/coder/workspace"

  # SECURITY: Prevent privilege escalation in containers
  security_opts = ["no-new-privileges:true"]

  # Lifecycle
  lifecycle {
    ignore_changes = [
      # Ignore changes that Coder manages
      env,
    ]
  }

  # Labels for identification
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
