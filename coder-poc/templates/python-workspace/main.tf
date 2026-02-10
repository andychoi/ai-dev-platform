# Python Workspace Template for Coder
# Docker-based Python development workspace

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
  default      = "gemma3"
  mutable      = true
  icon         = "/icon/widgets.svg"

  option {
    name  = "Gemma 3 12B (Local, Default)"
    value = "gemma3"
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

data "coder_parameter" "guardrail_action" {
  name         = "guardrail_action"
  display_name = "Sensitive Data Handling"
  description  = "How to handle detected PII, secrets, and financial data in AI prompts. Block rejects the request; Mask replaces sensitive values with [REDACTED] and proceeds."
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

# ==========================================================================
# NETWORK EGRESS EXCEPTIONS (Admin-Controlled)
# Comma-separated list of extra TCP ports the workspace can reach.
# Used for approved internal services not in the default allowlist.
# Only Template Admins can set this — contractors cannot change it.
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
    # Ollama: Route Claude Code CLI to host Mac's Ollama server (GPU-accelerated)
    # Requires: launchctl setenv OLLAMA_HOST "0.0.0.0" on host Mac + restart Ollama
    ANTHROPIC_BASE_URL  = "http://host.docker.internal:11434"
    ANTHROPIC_AUTH_TOKEN = "ollama"
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
    # AI AGENT CONFIGURATION (Roo Code + OpenCode + LiteLLM)
    # ==========================================================================
    AI_ASSISTANT="${data.coder_parameter.ai_assistant.value}"
    LITELLM_KEY="${data.coder_parameter.litellm_api_key.value}"
    AI_MODEL="${data.coder_parameter.ai_model.value}"
    AI_GATEWAY_URL="${data.coder_parameter.ai_gateway_url.value}"
    ENFORCEMENT_LEVEL="${data.coder_parameter.ai_enforcement_level.value}"
    GUARDRAIL_ACTION="${data.coder_parameter.guardrail_action.value}"

    # Claude Code CLI is a plan-first agent by design — it already reasons before
    # coding, asks for confirmation, and follows structured workflows natively.
    # The enforcement hook (design-first/standard prompts) was built to replicate
    # Claude Code's behavior in other agents. Applying it back is redundant.
    # Budget, rate limits, guardrails (PII/secrets), and audit logging still apply.
    if [ "$AI_ASSISTANT" = "claude-code" ]; then
      ENFORCEMENT_LEVEL="unrestricted"
    fi

    if [ "$AI_ASSISTANT" != "none" ]; then
      # Determine model name for LiteLLM
      case "$AI_MODEL" in
        "gemma3")                LITELLM_MODEL="gemma3" ;;
        "claude-sonnet")         LITELLM_MODEL="claude-sonnet-4-5" ;;
        "claude-haiku")          LITELLM_MODEL="claude-haiku-4-5" ;;
        "claude-opus")           LITELLM_MODEL="claude-opus-4" ;;
        "bedrock-claude-sonnet") LITELLM_MODEL="bedrock-claude-sonnet" ;;
        "bedrock-claude-haiku")  LITELLM_MODEL="bedrock-claude-haiku" ;;
        *)                       LITELLM_MODEL="gemma3" ;;
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
        if [ "$AI_ASSISTANT" = "roo-code" ] || [ "$AI_ASSISTANT" = "both" ] || [ "$AI_ASSISTANT" = "all" ]; then
          echo "Configuring Roo Code with LiteLLM proxy..."
          mkdir -p /home/coder/.config/roo-code

          # Build custom instructions based on enforcement level
          CUSTOM_INSTRUCTIONS=""
          case "$ENFORCEMENT_LEVEL" in
            "standard")
              CUSTOM_INSTRUCTIONS="You are a thoughtful software engineer. Think step-by-step before coding. Explain your approach before implementing. Consider existing codebase patterns. Prefer incremental, focused changes. When modifying code, explain what and why."
              ;;
            "design-first")
              CUSTOM_INSTRUCTIONS="DESIGN-FIRST REQUIRED: Before writing ANY code, present a design proposal (problem, approach, files to modify, tradeoffs). Ask for confirmation before implementing. Never write code in the same response as the design proposal. Small fixes are exempt but still need brief explanation."
              ;;
          esac

          # Write settings with optional customInstructions
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
          # Always write config if the binary exists (don't rely on PATH/command -v)
          if [ -x /home/coder/.opencode/bin/opencode ]; then
            echo "Configuring OpenCode CLI with LiteLLM proxy..."
            mkdir -p /home/coder/.config/opencode

            # Write enforcement instructions file for non-unrestricted levels
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

            # Write opencode.json (with or without instructions)
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
        "gemma3": { "name": "Gemma 3 12B (Local)" },
        "claude-sonnet-4-5": { "name": "Claude Sonnet 4.5" },
        "claude-haiku-4-5": { "name": "Claude Haiku 4.5" },
        "claude-opus-4": { "name": "Claude Opus 4" },
        "bedrock-claude-sonnet": { "name": "Bedrock Claude Sonnet" },
        "bedrock-claude-haiku": { "name": "Bedrock Claude Haiku" }
      }
    }
  },
  "model": "litellm/$LITELLM_MODEL",
  "small_model": "litellm/gemma3"
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
            echo "Configuring Claude Code CLI with LiteLLM proxy (Anthropic pass-through)..."
            mkdir -p /home/coder/.claude

            cat > /home/coder/.claude/settings.json << 'CLAUDECONFIG'
{
  "permissions": {
    "allow": [
      "Bash(git log:*)",
      "Bash(git diff:*)",
      "Bash(git status:*)",
      "Bash(python:*)",
      "Bash(python3:*)",
      "Bash(pip:*)",
      "Bash(pip3:*)",
      "Bash(pytest:*)",
      "Bash(poetry:*)",
      "Bash(uv:*)",
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

        # Claude Code CLI environment (Ollama on host Mac)
        if [ "$AI_ASSISTANT" = "claude-code" ] || [ "$AI_ASSISTANT" = "all" ]; then
          cat >> ~/.bashrc << CLAUDEENV
# Claude Code CLI (Ollama on host Mac — GPU-accelerated)
export ANTHROPIC_BASE_URL="http://host.docker.internal:11434"
export ANTHROPIC_AUTH_TOKEN="ollama"
# Governed route via LiteLLM (budget tracking, guardrails, audit)
alias claude-litellm='ANTHROPIC_BASE_URL="http://litellm:4000/anthropic" ANTHROPIC_API_KEY="$OPENAI_API_KEY" ANTHROPIC_AUTH_TOKEN="" claude'
CLAUDEENV
        fi
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

    # ==========================================================================
    # OLLAMA — Host Mac's Ollama server (GPU-accelerated)
    # The ollama CLI in the container acts as a client to the host's server.
    # Requires: launchctl setenv OLLAMA_HOST "0.0.0.0" on host Mac
    # ==========================================================================
    OLLAMA_URL="http://host.docker.internal:11434"

    if curl -sf "$OLLAMA_URL" >/dev/null 2>&1; then
      echo "Host Ollama reachable at $OLLAMA_URL"
    else
      echo "WARNING: Host Ollama not reachable at $OLLAMA_URL"
      echo "  → On your Mac, run: launchctl setenv OLLAMA_HOST \"0.0.0.0\" and restart Ollama"
    fi

    # Add Ollama environment to shell
    cat >> ~/.bashrc << 'OLLAMACONFIG'
# Ollama — Host Mac's Ollama server (GPU-accelerated)
export OLLAMA_HOST=http://host.docker.internal:11434
OLLAMACONFIG

    # Start code-server (redirect output to prevent "pipes not closed" warning)
    echo "Starting code-server..."
    code-server --auth none --bind-addr 0.0.0.0:8080 /home/coder/workspace > /tmp/code-server.log 2>&1 &

    echo "=== Workspace ready ==="
    echo "Git Server: ${data.coder_parameter.git_server_url.value}"
    echo "AI Gateway: $${AI_GATEWAY_URL}"
    echo "AI Agent: $${AI_ASSISTANT}"
    echo "AI Behavior: $${ENFORCEMENT_LEVEL}"
    echo "Ollama: host.docker.internal:11434 (host Mac)"
    if [ "$AI_ASSISTANT" = "claude-code" ] || [ "$AI_ASSISTANT" = "all" ]; then
      echo "Claude Code: litellm:4000/anthropic (Anthropic pass-through)"
    fi
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
  workspace_image = "python-workspace:latest"
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
    "ENFORCEMENT_LEVEL=${data.coder_parameter.ai_enforcement_level.value}",
    # Key Provisioner: Secret for auto-provisioning AI API keys
    "PROVISIONER_SECRET=poc-provisioner-secret-change-in-production",
    # TLS: Trust the self-signed Coder certificate so the agent can connect via HTTPS
    "SSL_CERT_FILE=/certs/coder.crt",
    "NODE_EXTRA_CA_CERTS=/certs/coder.crt",
    # Network egress exceptions (admin-controlled, read by setup-firewall.sh)
    "EGRESS_EXTRA_PORTS=${data.coder_parameter.egress_extra_ports.value}",
    # Ollama: Point CLI to host Mac's Ollama server (GPU-accelerated)
    "OLLAMA_HOST=http://host.docker.internal:11434",
  ]

  # Start the Coder agent
  # Install self-signed TLS cert into system trust store before agent init
  # (agent downloads its binary via curl from Coder over HTTPS)
  entrypoint = ["sh", "-c", <<-EOT
    if [ -f /certs/coder.crt ]; then
      sudo cp /certs/coder.crt /usr/local/share/ca-certificates/coder.crt
      sudo update-ca-certificates
    fi
    # SECURITY: Apply network egress firewall rules
    sudo /usr/local/bin/setup-firewall.sh || echo "WARNING: Firewall setup failed (iptables may not be available)"
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

  # SECURITY: Egress firewall exception files (read-only)
  # Global: applies to ALL workspaces across ALL templates
  volumes {
    host_path      = "/Users/andymini/ai/dev-platform/coder-poc/egress/global.conf"
    container_path = "/etc/egress-global.conf"
    read_only      = true
  }
  # Template-specific: applies only to this template's workspaces
  volumes {
    host_path      = "/Users/andymini/ai/dev-platform/coder-poc/egress/contractor-workspace.conf"
    container_path = "/etc/egress-template.conf"
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

  # SECURITY: NET_ADMIN required for iptables egress firewall rules
  # The firewall script runs once at startup via sudo, then the coder user
  # cannot modify rules (iptables not in sudoers allowlist)
  capabilities {
    add = ["NET_ADMIN"]
  }

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
