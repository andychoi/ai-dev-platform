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
  display_name = "AI Coding Assistant"
  description  = "Enable AI coding assistance (requires API key)"
  type         = "string"
  default      = "continue"
  mutable      = true
  icon         = "/icon/widgets.svg"

  option {
    name  = "Continue (Open Source)"
    value = "continue"
  }
  option {
    name  = "Cody (Sourcegraph)"
    value = "cody"
  }
  option {
    name  = "None"
    value = "none"
  }
}

# AI Provider selection
data "coder_parameter" "ai_provider" {
  name         = "ai_provider"
  display_name = "AI Provider"
  description  = "Select the AI provider for coding assistance"
  type         = "string"
  default      = "bedrock"
  mutable      = true
  icon         = "/icon/widgets.svg"

  option {
    name  = "AWS Bedrock (Recommended)"
    value = "bedrock"
  }
  option {
    name  = "Anthropic API (Direct)"
    value = "anthropic"
  }
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
    name  = "Claude Opus 4.5 (Advanced)"
    value = "claude-opus"
  }
}

# AI Gateway URL
data "coder_parameter" "ai_gateway_url" {
  name         = "ai_gateway_url"
  display_name = "AI Gateway URL"
  description  = "URL of the AI Gateway proxy"
  type         = "string"
  default      = "http://ai-gateway:8090"
  mutable      = true
  icon         = "/icon/widgets.svg"
}

# AWS Region for Bedrock
data "coder_parameter" "aws_region" {
  name         = "aws_region"
  display_name = "AWS Region"
  description  = "AWS region for Bedrock API (if using Bedrock provider)"
  type         = "string"
  default      = "us-east-1"
  mutable      = true
  icon         = "/icon/aws.svg"

  option {
    name  = "US East (N. Virginia)"
    value = "us-east-1"
  }
  option {
    name  = "US West (Oregon)"
    value = "us-west-2"
  }
  option {
    name  = "EU (Frankfurt)"
    value = "eu-central-1"
  }
  option {
    name  = "Asia Pacific (Tokyo)"
    value = "ap-northeast-1"
  }
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

    # Configure AI settings
    echo "Configuring AI assistant..."
    AI_GATEWAY_URL="${data.coder_parameter.ai_gateway_url.value}"
    AI_PROVIDER="${data.coder_parameter.ai_provider.value}"
    AI_MODEL="${data.coder_parameter.ai_model.value}"

    # Determine model IDs based on provider and selection
    case "$AI_MODEL" in
      "claude-sonnet")
        BEDROCK_MODEL="us.anthropic.claude-sonnet-4-5-20250929-v1:0"
        ANTHROPIC_MODEL="claude-sonnet-4-5-20250929"
        ;;
      "claude-haiku")
        BEDROCK_MODEL="us.anthropic.claude-haiku-4-5-20251001-v1:0"
        ANTHROPIC_MODEL="claude-haiku-4-5-20251001"
        ;;
      "claude-opus")
        BEDROCK_MODEL="us.anthropic.claude-opus-4-20250514-v1:0"
        ANTHROPIC_MODEL="claude-opus-4-20250514"
        ;;
      *)
        BEDROCK_MODEL="us.anthropic.claude-sonnet-4-5-20250929-v1:0"
        ANTHROPIC_MODEL="claude-sonnet-4-5-20250929"
        ;;
    esac

    # Set environment variables for AI tools
    cat >> ~/.bashrc << AICONFIG
# AI Configuration
export AI_GATEWAY_URL="${data.coder_parameter.ai_gateway_url.value}"
export AI_PROVIDER="${data.coder_parameter.ai_provider.value}"
export AI_MODEL="${data.coder_parameter.ai_model.value}"

# AWS Bedrock Configuration
export AWS_REGION="$${AWS_REGION:-us-east-1}"
export BEDROCK_MODEL="$BEDROCK_MODEL"

# Anthropic Configuration
export ANTHROPIC_MODEL="$ANTHROPIC_MODEL"
export ANTHROPIC_BASE_URL="${data.coder_parameter.ai_gateway_url.value}/v1"

# Alias for quick AI access
alias ai-models="echo 'Provider: ${data.coder_parameter.ai_provider.value}, Model: ${data.coder_parameter.ai_model.value}'"
AICONFIG

    # Configure Continue extension based on provider
    AWS_REGION="${data.coder_parameter.aws_region.value}"
    mkdir -p ~/.continue
    if [ "$AI_PROVIDER" = "bedrock" ]; then
      cat > ~/.continue/config.json << CONTINUECONFIG
{
  "models": [
    {
      "title": "Claude ($AI_MODEL via Bedrock)",
      "provider": "bedrock",
      "model": "$BEDROCK_MODEL",
      "region": "$AWS_REGION"
    }
  ],
  "tabAutocompleteModel": {
    "title": "Claude Haiku (Autocomplete)",
    "provider": "bedrock",
    "model": "us.anthropic.claude-haiku-4-5-20251001-v1:0",
    "region": "$AWS_REGION"
  },
  "embeddingsProvider": { "provider": "transformers.js" },
  "contextProviders": [
    { "name": "code" }, { "name": "docs" }, { "name": "diff" },
    { "name": "terminal" }, { "name": "problems" }, { "name": "codebase" }
  ],
  "allowAnonymousTelemetry": false
}
CONTINUECONFIG
    else
      cat > ~/.continue/config.json << CONTINUECONFIG
{
  "models": [
    {
      "title": "Claude ($AI_MODEL via API)",
      "provider": "anthropic",
      "model": "$ANTHROPIC_MODEL",
      "apiBase": "${data.coder_parameter.ai_gateway_url.value}/v1"
    }
  ],
  "tabAutocompleteModel": {
    "title": "Claude Haiku (Autocomplete)",
    "provider": "anthropic",
    "model": "claude-haiku-4-5-20251001",
    "apiBase": "${data.coder_parameter.ai_gateway_url.value}/v1"
  },
  "embeddingsProvider": { "provider": "transformers.js" },
  "contextProviders": [
    { "name": "code" }, { "name": "docs" }, { "name": "diff" },
    { "name": "terminal" }, { "name": "problems" }, { "name": "codebase" }
  ],
  "allowAnonymousTelemetry": false
}
CONTINUECONFIG
    fi

    echo "AI configured: Provider=$AI_PROVIDER, Model=$AI_MODEL"

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
    "AI_PROVIDER=${data.coder_parameter.ai_provider.value}",
    "AI_MODEL=${data.coder_parameter.ai_model.value}",
    "AI_GATEWAY_URL=${data.coder_parameter.ai_gateway_url.value}",
    # AWS Configuration for Bedrock
    "AWS_REGION=${data.coder_parameter.aws_region.value}",
    "AWS_DEFAULT_REGION=${data.coder_parameter.aws_region.value}",
  ]

  # Start the Coder agent
  entrypoint = ["sh", "-c", coder_agent.main.init_script]

  # Mount persistent volume
  volumes {
    volume_name    = docker_volume.workspace_data.name
    container_path = "/home/coder"
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
