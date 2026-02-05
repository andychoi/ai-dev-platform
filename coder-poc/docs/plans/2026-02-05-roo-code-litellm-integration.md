# Roo Code + LiteLLM Integration Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Pre-install Roo Code (AI coding agent) into every Coder workspace, pointed at a centrally-managed LiteLLM proxy that holds master API keys, enforces per-developer budgets/rate-limits, and logs every AI interaction.

**Architecture:** Replace the existing custom AI Gateway (`ai-gateway/`) with LiteLLM proxy, which provides an OpenAI-compatible API that Roo Code speaks natively. Roo Code is pre-installed in the workspace Docker image and auto-configured on startup via `roo-cline.autoImportSettingsPath` to point at the LiteLLM proxy. Developers never see or handle API keys.

**Tech Stack:** LiteLLM (Python proxy), PostgreSQL (key/usage storage), Roo Code VS Code extension, Coder templates (Terraform), Docker Compose

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Developer's Browser                               │
│                    (code-server WebIDE)                              │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  Roo Code Extension                                          │   │
│  │  Provider: OpenAI Compatible                                 │   │
│  │  Base URL: http://litellm:4000                               │   │
│  │  API Key: <per-user virtual key from LiteLLM>               │   │
│  └─────────────────────────┬────────────────────────────────────┘   │
│                             │                                        │
└─────────────────────────────┼────────────────────────────────────────┘
                              │ (all requests within coder-network)
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  LiteLLM Proxy (Port 4000)                                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────┐   │
│  │ Virtual  │  │  Rate    │  │  Budget  │  │  Audit           │   │
│  │ Keys     │  │  Limits  │  │  Control │  │  Logging         │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────────────┘   │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  PostgreSQL (litellm DB) — keys, usage, budgets              │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────┬───────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
       ┌────────────┐  ┌────────────┐  ┌────────────┐
       │ Anthropic  │  │   AWS      │  │  (future)  │
       │ Claude API │  │  Bedrock   │  │  Gemini    │
       └────────────┘  └────────────┘  └────────────┘
```

## Key Design Decisions

1. **LiteLLM replaces custom AI Gateway** — LiteLLM provides virtual keys, budgets, rate limiting, audit logs, and an OpenAI-compatible API out of the box. The custom `ai-gateway/` becomes redundant.

2. **Roo Code over Continue/Cody** — Roo Code is a more capable agentic assistant (can execute commands, edit files, run tests). It replaces Continue and Cody as the primary AI assistant.

3. **Per-user virtual keys** — Each developer gets a LiteLLM virtual key with budget/rate limits. Keys are injected via Coder agent environment at workspace startup. No master API keys exposed.

4. **Auto-import settings** — Roo Code supports `roo-cline.autoImportSettingsPath` in VS Code `settings.json`. A config file is generated at workspace startup with the user's virtual key and LiteLLM endpoint pre-configured.

5. **Agent execution is sandboxed** — Roo Code runs inside the container. Its "exploration" (file edits, terminal commands, test runs) is limited to that workspace. Combined with `no-new-privileges` and restricted sudo, this is safe.

---

## Task 1: Add LiteLLM Service to Docker Compose

**Files:**
- Modify: `docker-compose.yml` (add `litellm` service after the `ai-gateway` service)
- Create: `litellm/config.yaml` (LiteLLM configuration)
- Modify: `.env` (add LiteLLM env vars)
- Modify: `postgres/init.sql` (add `litellm` database)

### Step 1: Create LiteLLM config directory and config.yaml

Create `litellm/config.yaml`:

```yaml
# LiteLLM Proxy Configuration
# Replaces custom AI Gateway with standardized OpenAI-compatible proxy

model_list:
  # Claude Sonnet 4.5 via Anthropic API
  - model_name: claude-sonnet-4-5
    litellm_params:
      model: anthropic/claude-sonnet-4-5-20250929
      api_key: os.environ/ANTHROPIC_API_KEY
    model_info:
      max_tokens: 8192
      input_cost_per_token: 0.000003
      output_cost_per_token: 0.000015

  # Claude Haiku 4.5 via Anthropic API
  - model_name: claude-haiku-4-5
    litellm_params:
      model: anthropic/claude-haiku-4-5-20251001
      api_key: os.environ/ANTHROPIC_API_KEY
    model_info:
      max_tokens: 8192
      input_cost_per_token: 0.0000008
      output_cost_per_token: 0.000004

  # Claude Opus 4 via Anthropic API
  - model_name: claude-opus-4
    litellm_params:
      model: anthropic/claude-opus-4-20250514
      api_key: os.environ/ANTHROPIC_API_KEY
    model_info:
      max_tokens: 8192
      input_cost_per_token: 0.000015
      output_cost_per_token: 0.000075

  # Claude Sonnet 4.5 via AWS Bedrock
  - model_name: bedrock-claude-sonnet
    litellm_params:
      model: bedrock/us.anthropic.claude-sonnet-4-5-20250929-v1:0
      aws_access_key_id: os.environ/AWS_ACCESS_KEY_ID
      aws_secret_access_key: os.environ/AWS_SECRET_ACCESS_KEY
      aws_region_name: os.environ/AWS_REGION

  # Claude Haiku 4.5 via AWS Bedrock
  - model_name: bedrock-claude-haiku
    litellm_params:
      model: bedrock/us.anthropic.claude-haiku-4-5-20251001-v1:0
      aws_access_key_id: os.environ/AWS_ACCESS_KEY_ID
      aws_secret_access_key: os.environ/AWS_SECRET_ACCESS_KEY
      aws_region_name: os.environ/AWS_REGION

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  database_url: os.environ/DATABASE_URL

litellm_settings:
  # Default budget per end-user (developers)
  max_end_user_budget: 10.00
  # Drop params not supported by provider instead of erroring
  drop_params: true
  # Enable logging
  success_callback: ["log_to_db"]
  failure_callback: ["log_to_db"]
```

### Step 2: Add LiteLLM database to PostgreSQL init script

Add to `postgres/init.sql`:

```sql
-- LiteLLM database for virtual keys, usage tracking, budgets
CREATE USER litellm WITH PASSWORD 'litellm';
CREATE DATABASE litellm OWNER litellm;
GRANT ALL PRIVILEGES ON DATABASE litellm TO litellm;
```

### Step 3: Add LiteLLM environment variables to `.env`

Add to `.env`:

```bash
# =============================================================================
# LITELLM PROXY CONFIGURATION
# Centralized AI gateway with per-user keys, budgets, and audit logging
# =============================================================================

# Master key for LiteLLM admin API (generate with: openssl rand -base64 32)
# Must start with 'sk-'
LITELLM_MASTER_KEY=sk-poc-litellm-master-key-change-in-production

# LiteLLM database URL
LITELLM_DATABASE_URL=postgresql://litellm:litellm@postgres:5432/litellm

# Default per-user budget (USD)
LITELLM_DEFAULT_USER_BUDGET=10.00

# Default rate limit (requests per minute per key)
LITELLM_DEFAULT_RPM=60
```

### Step 4: Add LiteLLM service to docker-compose.yml

Add after the `ai-gateway` service block:

```yaml
  # LiteLLM Proxy - Centralized AI gateway with virtual keys and budgets
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
      - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-}
      - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-}
      - AWS_REGION=${AWS_REGION:-us-east-1}
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY:-sk-poc-litellm-master-key}
      - DATABASE_URL=${LITELLM_DATABASE_URL:-postgresql://litellm:litellm@postgres:5432/litellm}
    ports:
      - "4000:4000"
    volumes:
      - ./litellm/config.yaml:/app/config.yaml:ro
    command: ["--config", "/app/config.yaml", "--port", "4000"]
    networks:
      - coder-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

Also add `litellm_data` volume (not strictly needed since LiteLLM uses PostgreSQL, but good practice).

### Step 5: Verify the service starts

Run:
```bash
docker compose up -d postgres && sleep 5 && docker compose up -d litellm
```

Expected: LiteLLM starts and health check passes at `http://localhost:4000/health`.

### Step 6: Commit

```bash
git add litellm/ docker-compose.yml postgres/init.sql .env .env.example
git commit -m "feat: add LiteLLM proxy service for centralized AI gateway"
```

---

## Task 2: Create Per-User Virtual Keys via Setup Script

**Files:**
- Create: `scripts/setup-litellm-keys.sh` (generates virtual keys for all test users)

### Step 1: Write the setup script

Create `scripts/setup-litellm-keys.sh`:

```bash
#!/bin/bash
# Setup LiteLLM virtual keys for all test users
# Each key has per-user budget and rate limits

set -euo pipefail

LITELLM_URL="http://localhost:4000"
MASTER_KEY="${LITELLM_MASTER_KEY:-sk-poc-litellm-master-key-change-in-production}"

# Default limits
DEFAULT_RPM="${LITELLM_DEFAULT_RPM:-60}"
DEFAULT_BUDGET="${LITELLM_DEFAULT_USER_BUDGET:-10.00}"

# Users to create keys for (username:budget:rpm)
USERS=(
  "admin:50.00:200"
  "appmanager:20.00:100"
  "contractor1:10.00:60"
  "contractor2:10.00:60"
  "contractor3:10.00:60"
)

echo "=== Setting up LiteLLM virtual keys ==="
echo "LiteLLM URL: $LITELLM_URL"
echo ""

# Wait for LiteLLM to be ready
echo "Waiting for LiteLLM to be ready..."
for i in $(seq 1 30); do
  if curl -sf "$LITELLM_URL/health" > /dev/null 2>&1; then
    echo "LiteLLM is ready!"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: LiteLLM not ready after 30 seconds"
    exit 1
  fi
  sleep 1
done

echo ""

for user_config in "${USERS[@]}"; do
  IFS=':' read -r username budget rpm <<< "$user_config"

  echo "Creating key for: $username (budget: \$$budget, rpm: $rpm)"

  RESPONSE=$(curl -s -X POST "$LITELLM_URL/key/generate" \
    -H "Authorization: Bearer $MASTER_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"key_alias\": \"$username\",
      \"user_id\": \"$username\",
      \"max_budget\": $budget,
      \"rpm_limit\": $rpm,
      \"metadata\": {
        \"workspace_user\": \"$username\",
        \"created_by\": \"setup-script\"
      }
    }")

  KEY=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('key', 'ERROR'))" 2>/dev/null || echo "ERROR")

  if [ "$KEY" = "ERROR" ]; then
    echo "  WARNING: Failed to create key for $username"
    echo "  Response: $RESPONSE"
  else
    echo "  Key created: ${KEY:0:20}..."
    # Store key mapping for workspace provisioning
    echo "$username=$KEY" >> /tmp/litellm-keys.txt
  fi
done

echo ""
echo "=== LiteLLM keys setup complete ==="
echo "Keys saved to /tmp/litellm-keys.txt"
echo ""
echo "To retrieve a key later:"
echo "  curl -s $LITELLM_URL/key/info -H 'Authorization: Bearer $MASTER_KEY' -d '{\"key\": \"sk-...\"}'"
```

### Step 2: Make executable and test

Run:
```bash
chmod +x scripts/setup-litellm-keys.sh
./scripts/setup-litellm-keys.sh
```

Expected: Keys created for each user, saved to `/tmp/litellm-keys.txt`.

### Step 3: Commit

```bash
git add scripts/setup-litellm-keys.sh
git commit -m "feat: add LiteLLM virtual key setup script for per-user budgets"
```

---

## Task 3: Install Roo Code in Workspace Dockerfile

**Files:**
- Modify: `templates/contractor-workspace/build/Dockerfile` (replace Continue/Cody with Roo Code)

### Step 1: Replace AI assistant extensions in Dockerfile

In `templates/contractor-workspace/build/Dockerfile`, replace lines 173-175:

```dockerfile
# AI coding assistants (Claude CLI alternatives)
RUN code-server --install-extension continue.continue \
    && code-server --install-extension sourcegraph.cody-ai
```

With:

```dockerfile
# AI coding agent - Roo Code (agentic AI assistant)
# Pre-installed so every developer has it ready without manual setup
RUN code-server --install-extension rooveterinaryinc.roo-cline
```

### Step 2: Remove Continue config from Dockerfile

Remove lines 137-139 (Continue config copy):

```dockerfile
# Copy Continue AI assistant config
RUN mkdir -p /home/coder/.continue
COPY --chown=coder:coder continue-config.json /home/coder/.continue/config.json
```

### Step 3: Create Roo Code auto-import settings template

Create `templates/contractor-workspace/build/roo-code-settings.json`:

```json
{
  "apiProvider": "openai-compatible",
  "openAiCompatibleApiConfiguration": {
    "baseUrl": "http://litellm:4000/v1",
    "apiKey": "PLACEHOLDER_WILL_BE_SET_AT_STARTUP",
    "modelId": "claude-sonnet-4-5"
  }
}
```

This is a template — the actual API key is injected at workspace startup (Task 4).

### Step 4: Add Roo Code auto-import path to VS Code settings

In `templates/contractor-workspace/build/settings.json`, replace the Continue settings:

```json
  // AI assistant settings
  "continue.enableTabAutocomplete": true,
  "continue.showInlineTip": false,
```

With:

```json
  // AI agent - Roo Code (auto-imports config on startup)
  "roo-cline.autoImportSettingsPath": "/home/coder/.config/roo-code/settings.json",
```

### Step 5: Build and verify the image

Run:
```bash
cd templates/contractor-workspace/build
docker build -t contractor-workspace:latest .
```

Expected: Image builds successfully with Roo Code extension installed.

### Step 6: Verify Roo Code extension is installed

Run:
```bash
docker run --rm contractor-workspace:latest code-server --list-extensions | grep -i roo
```

Expected: `rooveterinaryinc.roo-cline` appears in output.

### Step 7: Commit

```bash
git add templates/contractor-workspace/build/Dockerfile \
        templates/contractor-workspace/build/settings.json \
        templates/contractor-workspace/build/roo-code-settings.json
git commit -m "feat: replace Continue/Cody with Roo Code agent in workspace image"
```

---

## Task 4: Configure Workspace Startup to Inject Roo Code Settings

**Files:**
- Modify: `templates/contractor-workspace/main.tf` (update startup script to configure Roo Code with LiteLLM key)

### Step 1: Update AI assistant parameter options

In `main.tf`, replace the `ai_assistant` parameter (lines 171-192):

```hcl
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
```

### Step 2: Add LiteLLM key parameter

Add a new parameter for the developer's LiteLLM virtual key:

```hcl
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
```

### Step 3: Replace AI configuration in startup script

Replace the existing AI configuration section (lines 431-528) in the startup script with:

```bash
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
        "claude-sonnet") LITELLM_MODEL="claude-sonnet-4-5" ;;
        "claude-haiku")  LITELLM_MODEL="claude-haiku-4-5" ;;
        "claude-opus")   LITELLM_MODEL="claude-opus-4" ;;
        *)               LITELLM_MODEL="claude-sonnet-4-5" ;;
      esac

      # Generate Roo Code auto-import config with the user's virtual key
      mkdir -p /home/coder/.config/roo-code
      cat > /home/coder/.config/roo-code/settings.json << ROOCONFIG
{
  "apiProvider": "openai-compatible",
  "openAiCompatibleApiConfiguration": {
    "baseUrl": "http://litellm:4000/v1",
    "apiKey": "$LITELLM_KEY",
    "modelId": "$LITELLM_MODEL"
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
```

### Step 4: Update the `ai_gateway_url` parameter default

Change the default to point to LiteLLM:

```hcl
data "coder_parameter" "ai_gateway_url" {
  name         = "ai_gateway_url"
  display_name = "AI Gateway URL"
  description  = "URL of the AI Gateway proxy (LiteLLM)"
  type         = "string"
  default      = "http://litellm:4000"
  mutable      = true
  icon         = "/icon/widgets.svg"
}
```

### Step 5: Add `LITELLM_API_KEY` to container environment

In the `docker_container` resource `env` list, add:

```hcl
    "LITELLM_API_KEY=${data.coder_parameter.litellm_api_key.value}",
```

### Step 6: Commit

```bash
git add templates/contractor-workspace/main.tf
git commit -m "feat: configure workspace startup to inject Roo Code + LiteLLM settings"
```

---

## Task 5: Update Documentation and Clean Up

**Files:**
- Modify: `docs/AI.md` (update AI documentation)
- Modify: `.env.example` (add LiteLLM vars)
- Modify: `README.md` (update service list)
- Remove: `templates/contractor-workspace/build/continue-config.json` (no longer needed)

### Step 1: Update `.env.example` with LiteLLM variables

Add the LiteLLM section (same as added to `.env` in Task 1 Step 3).

### Step 2: Remove Continue config file

```bash
rm templates/contractor-workspace/build/continue-config.json
```

### Step 3: Update README.md service table

Add LiteLLM to the services list:

```markdown
| LiteLLM | 4000 | AI API proxy (OpenAI-compatible) | Per-user keys, budgets, rate limits |
```

### Step 4: Commit

```bash
git add -A
git commit -m "docs: update documentation for Roo Code + LiteLLM integration"
```

---

## Task 6: Integration Testing

**Files:** No new files

### Step 1: Rebuild workspace image

```bash
cd templates/contractor-workspace/build
docker build -t contractor-workspace:latest .
```

### Step 2: Start all services

```bash
docker compose up -d
```

### Step 3: Generate virtual keys

```bash
./scripts/setup-litellm-keys.sh
```

### Step 4: Push updated template to Coder

```bash
# Get admin session token
CODER_SESSION=$(curl -s -X POST "http://localhost:7080/api/v2/users/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@example.com","password":"CoderAdmin123!"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_token',''))")

# Copy template to Coder server
docker cp templates/contractor-workspace/. coder-server:/tmp/contractor-workspace/

# Push template
docker exec -e CODER_SESSION_TOKEN="$CODER_SESSION" \
  -e CODER_URL="http://localhost:7080" \
  coder-server coder templates push contractor-workspace \
  --directory /tmp/contractor-workspace --yes
```

### Step 5: Create a test workspace with Roo Code

Create a workspace for `contractor1` and provide their LiteLLM virtual key. Verify:

1. Workspace starts successfully
2. Roo Code extension is visible in code-server sidebar
3. Roo Code is pre-configured with LiteLLM endpoint
4. Sending a message through Roo Code returns an AI response
5. Usage is tracked in LiteLLM (`curl http://localhost:4000/user/info -H "Authorization: Bearer <key>"`)

### Step 6: Verify rate limiting

Send rapid requests through Roo Code and confirm rate limiting kicks in at the configured RPM.

### Step 7: Verify budget enforcement

Check that LiteLLM tracks spend and would block requests once budget is exceeded.

### Step 8: Commit test results

```bash
git add -A
git commit -m "test: verify Roo Code + LiteLLM integration end-to-end"
```

---

## Task 7 (Optional): Deprecate Custom AI Gateway

**Files:**
- Modify: `docker-compose.yml` (comment out `ai-gateway` service)

### Step 1: Comment out the ai-gateway service

Once LiteLLM is confirmed working, comment out the `ai-gateway` service in `docker-compose.yml` and remove its port mapping. Keep the files in the repo for reference.

### Step 2: Update any remaining references

Search for `ai-gateway:8090` references and update to `litellm:4000`.

### Step 3: Commit

```bash
git add docker-compose.yml
git commit -m "refactor: deprecate custom AI gateway in favor of LiteLLM"
```

---

## Security Checklist

- [ ] Master API keys (Anthropic, AWS) only exist in `.env` and LiteLLM container — never in workspaces
- [ ] Developers only receive LiteLLM virtual keys with budget caps
- [ ] Virtual keys are scoped per-user with RPM rate limits
- [ ] All AI requests are logged to PostgreSQL via LiteLLM
- [ ] Roo Code runs inside container — file operations limited to workspace
- [ ] Container has `no-new-privileges` and restricted sudo
- [ ] LiteLLM admin API (master key) is not exposed to workspaces
- [ ] `.env` file is gitignored (contains secrets)

## Rollback Plan

If issues arise:
1. Remove `roo-cline.autoImportSettingsPath` from `settings.json` to disable auto-config
2. Re-enable Continue/Cody extensions in Dockerfile
3. Uncomment the `ai-gateway` service in docker-compose
4. Push old template version to Coder
5. Recreate workspaces
