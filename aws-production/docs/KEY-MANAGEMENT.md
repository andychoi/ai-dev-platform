# Key Management — Production

## Overview

The Key Provisioner service acts as a secure intermediary between Coder workspaces and LiteLLM. It holds the LiteLLM master API key and issues scoped virtual keys on behalf of workspaces and services. No workspace or CI job ever sees the master key directly.

This design enforces:

- **Least-privilege access** — each key is scoped to a specific use case with budget and rate limits.
- **Auditability** — every key carries metadata identifying who created it, when, and for what purpose.
- **Revocability** — keys can be revoked individually without affecting other consumers.

In production, all secrets are stored in AWS Secrets Manager, services are discovered via Cloud Map, and infrastructure is managed through Terraform.

---

## Key Taxonomy

| Scope            | Budget (USD) | RPM  | Models Allowed                          | Duration  | Use Case                                      |
|------------------|-------------|------|-----------------------------------------|-----------|-----------------------------------------------|
| `workspace`      | $5/day      | 30   | `claude-sonnet-4-5`, `claude-haiku-3-5` | Session   | Interactive Roo Code / OpenCode in workspace   |
| `user`           | $20/day     | 60   | `claude-sonnet-4-5`, `claude-haiku-3-5` | 30 days   | Self-service key for CLI or local tools        |
| `ci`             | $10/run     | 120  | `claude-haiku-3-5`                      | 1 hour    | CI pipeline code review / generation           |
| `agent:review`   | $2/run      | 60   | `claude-haiku-3-5`                      | 1 hour    | Automated PR review agent                      |
| `agent:write`    | $8/run      | 30   | `claude-sonnet-4-5`                     | 2 hours   | Automated code generation agent                |

---

## Architecture

```
┌─────────────────────────────┐
│   Workspace Container (ECS) │
│                             │
│  ┌───────────┐              │
│  │ Roo Code  │──┐           │
│  └───────────┘  │           │
│  ┌───────────┐  │           │
│  │ OpenCode  │──┤           │
│  └───────────┘  │           │
│                 │           │
│  startup.sh ────┤           │
│  (auto-provision)           │
└─────────┬───────────────────┘
          │ POST /api/v1/keys/workspace
          │ (provisioner-secret header)
          │ (Cloud Map DNS resolution)
          ▼
┌─────────────────────────────────────────────┐
│   Key Provisioner (ECS Service)             │
│   key-provisioner.coder-production.local    │
│   Port 8100                                 │
│                                             │
│  - Validates requests                       │
│  - Applies scope rules                      │
│  - Stores metadata                          │
│  - Calls LiteLLM API                        │
│  - Secrets from AWS Secrets Manager         │
└─────────┬───────────────────────────────────┘
          │ POST /key/generate
          │ (master-key header)
          │ (Cloud Map DNS resolution)
          ▼
┌─────────────────────────────────────────────┐
│   LiteLLM Proxy (ECS Service)               │
│   litellm.coder-production.local            │
│   Port 4000                                 │
│                                             │
│  - Issues virtual key                       │
│  - Enforces budget/RPM                      │
│  - Routes to Anthropic                      │
│  - Backed by RDS PostgreSQL                 │
└─────────────────────────────────────────────┘
```

### Infrastructure Components

- **ECS Services** — Key Provisioner and LiteLLM run as Fargate tasks in a private subnet.
- **Cloud Map** — Service discovery under the `coder-production.local` namespace provides DNS resolution between services.
- **AWS Secrets Manager** — All secrets (master key, provisioner secret, Anthropic API key) are injected into ECS task definitions as secret environment variables.
- **RDS PostgreSQL** — LiteLLM's key store is backed by RDS, ensuring virtual keys persist across task restarts.
- **ALB** — Application Load Balancer terminates TLS and routes external traffic to services.

---

## Metadata Schema

Every virtual key created through the provisioner carries structured metadata stored in LiteLLM:

```json
{
  "scope": "workspace",
  "key_type": "virtual",
  "created_by": "key-provisioner",
  "created_at": "2026-02-06T14:30:00Z",
  "workspace_id": "ws-abc123",
  "workspace_name": "contractor-alice",
  "coder_user": "alice",
  "coder_user_id": "usr-def456",
  "expires_at": "2026-02-06T22:00:00Z",
  "budget_usd": 5.0,
  "rpm_limit": 30,
  "models": ["claude-sonnet-4-5", "claude-haiku-3-5"]
}
```

Fields:

| Field            | Type     | Description                                          |
|------------------|----------|------------------------------------------------------|
| `scope`          | string   | One of: `workspace`, `user`, `ci`, `agent:review`, `agent:write` |
| `key_type`       | string   | Always `virtual`                                     |
| `created_by`     | string   | `key-provisioner` for auto-provisioned, username for self-service |
| `created_at`     | ISO 8601 | Timestamp of key creation                            |
| `workspace_id`   | string   | Coder workspace ID (if applicable)                   |
| `workspace_name` | string   | Coder workspace name (if applicable)                 |
| `coder_user`     | string   | Username who owns the key                            |
| `coder_user_id`  | string   | Coder user ID                                        |
| `expires_at`     | ISO 8601 | Key expiration time (null for non-expiring)          |
| `budget_usd`     | float    | Maximum spend allowed                                |
| `rpm_limit`      | int      | Requests per minute                                  |
| `models`         | string[] | Allowed model names matching LiteLLM config          |

---

## Auto-Provisioning Flow

When a workspace starts, the following sequence runs automatically via the startup script:

1. **Workspace starts** — Coder agent executes the template startup script inside the ECS task.
2. **Startup script checks for existing key** — if `LITELLM_API_KEY` is already set and valid, skip provisioning.
3. **Script calls the provisioner** — sends a POST request to the key provisioner via Cloud Map DNS:
   ```bash
   curl -s -X POST http://key-provisioner.coder-production.local:8100/api/v1/keys/workspace \
     -H "Content-Type: application/json" \
     -H "X-Provisioner-Secret: ${PROVISIONER_SECRET}" \
     -d '{
       "workspace_id": "'${CODER_WORKSPACE_ID}'",
       "workspace_name": "'${CODER_WORKSPACE_NAME}'",
       "coder_user": "'${CODER_USERNAME}'",
       "coder_user_id": "'${CODER_USER_ID}'"
     }'
   ```
4. **Provisioner validates** — checks the provisioner secret (loaded from AWS Secrets Manager), verifies the workspace identity, and applies scope rules for `workspace` type keys.
5. **Provisioner calls LiteLLM** — creates a virtual key via `POST http://litellm.coder-production.local:4000/key/generate` using the master key.
6. **Provisioner returns the virtual key** — response includes the key and metadata.
7. **Script configures AI tools** — writes the virtual key into:
   - Roo Code auto-import settings at `~/.config/roo-code/settings.json`
   - OpenCode configuration at `~/.config/opencode/config.json`
   - Environment variable `LITELLM_API_KEY` for CLI usage

```bash
# Simplified auto-provisioning logic from startup.sh
if [ -z "${LITELLM_API_KEY}" ]; then
  RESPONSE=$(curl -s -X POST http://key-provisioner.coder-production.local:8100/api/v1/keys/workspace \
    -H "Content-Type: application/json" \
    -H "X-Provisioner-Secret: ${PROVISIONER_SECRET}" \
    -d "{
      \"workspace_id\": \"${CODER_WORKSPACE_ID}\",
      \"workspace_name\": \"${CODER_WORKSPACE_NAME}\",
      \"coder_user\": \"${CODER_USERNAME}\",
      \"coder_user_id\": \"${CODER_USER_ID}\"
    }")

  LITELLM_API_KEY=$(echo "$RESPONSE" | jq -r '.key')
  export LITELLM_API_KEY

  # Write Roo Code config
  mkdir -p ~/.config/roo-code
  cat > ~/.config/roo-code/settings.json <<EOF
{
  "currentApiConfigName": "LiteLLM",
  "apiConfigs": {
    "LiteLLM": {
      "apiProvider": "openai",
      "openAiBaseUrl": "http://litellm.coder-production.local:4000/v1",
      "openAiApiKey": "${LITELLM_API_KEY}",
      "openAiModelId": "claude-sonnet-4-5"
    }
  }
}
EOF
fi
```

---

## Self-Service Keys

Workspace users can generate their own keys using the `generate-ai-key.sh` script. This is useful for CLI tools or personal experimentation outside the auto-provisioned scope.

### Prerequisites

- Active Coder session (logged in via browser)
- Coder session token available (set via `CODER_SESSION_TOKEN` or extracted from browser)

### Usage

```bash
# Generate a self-service user key
./generate-ai-key.sh

# The script will:
# 1. Verify your Coder session token
# 2. Request a user-scoped key from the provisioner
# 3. Print the key and usage instructions

# Output example:
# Key generated successfully
# Key:     sk-litellm-user-abc123...
# Scope:   user
# Budget:  $20/day
# Expires: 2026-03-08
#
# Export it:
#   export LITELLM_API_KEY=sk-litellm-user-abc123...
#
# Or use with curl:
#   curl http://litellm.coder-production.local:4000/v1/chat/completions \
#     -H "Authorization: Bearer sk-litellm-user-abc123..." \
#     -H "Content-Type: application/json" \
#     -d '{"model": "claude-sonnet-4-5", "messages": [{"role": "user", "content": "Hello"}]}'
```

### How It Works

The script authenticates with the provisioner using the Coder session token (not the provisioner secret). The provisioner validates the token against Coder's API to confirm the user's identity, then issues a `user`-scoped key with the appropriate budget and rate limits.

---

## Service Keys

Administrators manage CI and agent keys using the `manage-service-keys.sh` script.

### Create a CI Key

```bash
./manage-service-keys.sh create ci \
  --name "github-actions-main" \
  --budget 10 \
  --duration 1h

# Output:
# CI key created
# Key:     sk-litellm-ci-def456...
# Scope:   ci
# Budget:  $10/run
# Expires: 2026-02-06T15:30:00Z
```

### Create an Agent Key

```bash
# Review agent (read-only, haiku only)
./manage-service-keys.sh create agent:review \
  --name "pr-review-bot" \
  --budget 2 \
  --duration 1h

# Write agent (sonnet access)
./manage-service-keys.sh create agent:write \
  --name "code-gen-bot" \
  --budget 8 \
  --duration 2h
```

### List Active Keys

```bash
./manage-service-keys.sh list

# Output:
# SCOPE          NAME                  BUDGET    RPM   EXPIRES              STATUS
# workspace      contractor-alice      $5/day    30    2026-02-06T22:00Z    active
# workspace      contractor-bob        $5/day    30    2026-02-06T22:00Z    active
# user           alice-cli             $20/day   60    2026-03-08T00:00Z    active
# ci             github-actions-main   $10/run   120   2026-02-06T15:30Z    active
# agent:review   pr-review-bot         $2/run    60    2026-02-06T15:30Z    active
# agent:write    code-gen-bot          $8/run    30    2026-02-06T16:30Z    expired
```

### Revoke a Key

```bash
./manage-service-keys.sh revoke --name "pr-review-bot"

# Output:
# Key "pr-review-bot" revoked
```

### Rotate a Key

```bash
./manage-service-keys.sh rotate --name "github-actions-main"

# Output:
# Key "github-actions-main" rotated
# Old key revoked
# New key: sk-litellm-ci-ghi789...
```

---

## Security Model

| Secret               | Production Location                                      | Who Accesses                      | Notes                                         |
|----------------------|----------------------------------------------------------|-----------------------------------|-----------------------------------------------|
| LiteLLM Master Key   | AWS Secrets Manager (`coder-prod/litellm/master-key`)    | Key Provisioner ECS task only    | Injected via ECS task definition secret ref    |
| Provisioner Secret   | AWS Secrets Manager (`coder-prod/provisioner/secret`)    | Startup scripts, admin scripts   | Injected via ECS task definition secret ref    |
| Virtual Keys         | Workspace env / tool configs                             | Individual workspace or service  | Scoped, budgeted, revocable                    |
| Anthropic API Key    | AWS Secrets Manager (`coder-prod/anthropic/api-key`)     | LiteLLM ECS task only            | Upstream provider credential, never exposed    |

### Key Principles

- The master key never leaves the provisioner process. Workspaces cannot call LiteLLM's `/key/generate` endpoint directly.
- Virtual keys are scoped by model, budget, and time. A `workspace` key cannot access models outside its allowed list.
- The provisioner secret is a shared secret used only by trusted infrastructure (startup scripts, admin tooling). It is not a user credential.
- All keys are revocable. Revoking a key takes effect immediately — in-flight requests may complete, but subsequent requests fail.
- In production, no secrets exist in environment files or source control. All secrets are stored in AWS Secrets Manager and referenced by ARN in ECS task definitions.

### Terraform Secret References

Secrets are referenced in Terraform ECS task definitions:

```hcl
# In the key-provisioner ECS task definition
secrets = [
  {
    name      = "LITELLM_MASTER_KEY"
    valueFrom = "arn:aws:secretsmanager:us-east-1:123456789012:secret:coder-prod/litellm/master-key"
  },
  {
    name      = "PROVISIONER_SECRET"
    valueFrom = "arn:aws:secretsmanager:us-east-1:123456789012:secret:coder-prod/provisioner/secret"
  }
]

# In the litellm ECS task definition
secrets = [
  {
    name      = "LITELLM_MASTER_KEY"
    valueFrom = "arn:aws:secretsmanager:us-east-1:123456789012:secret:coder-prod/litellm/master-key"
  },
  {
    name      = "ANTHROPIC_API_KEY"
    valueFrom = "arn:aws:secretsmanager:us-east-1:123456789012:secret:coder-prod/anthropic/api-key"
  }
]
```

---

## API Reference

### POST /api/v1/keys/workspace

Create a workspace-scoped virtual key. Called automatically by the startup script.

**Request:**

```bash
curl -X POST http://key-provisioner.coder-production.local:8100/api/v1/keys/workspace \
  -H "Content-Type: application/json" \
  -H "X-Provisioner-Secret: ${PROVISIONER_SECRET}" \
  -d '{
    "workspace_id": "ws-abc123",
    "workspace_name": "contractor-alice",
    "coder_user": "alice",
    "coder_user_id": "usr-def456"
  }'
```

**Response (200):**

```json
{
  "key": "sk-litellm-ws-abc123...",
  "scope": "workspace",
  "budget_usd": 5.0,
  "rpm_limit": 30,
  "models": ["claude-sonnet-4-5", "claude-haiku-3-5"],
  "expires_at": "2026-02-06T22:00:00Z",
  "metadata": {
    "workspace_id": "ws-abc123",
    "workspace_name": "contractor-alice",
    "coder_user": "alice",
    "coder_user_id": "usr-def456"
  }
}
```

**Error (401):**

```json
{
  "error": "invalid provisioner secret"
}
```

---

### POST /api/v1/keys/user

Create a user-scoped virtual key. Called by `generate-ai-key.sh`.

**Request:**

```bash
curl -X POST http://key-provisioner.coder-production.local:8100/api/v1/keys/user \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${CODER_SESSION_TOKEN}" \
  -d '{
    "coder_user": "alice"
  }'
```

**Response (200):**

```json
{
  "key": "sk-litellm-user-ghi789...",
  "scope": "user",
  "budget_usd": 20.0,
  "rpm_limit": 60,
  "models": ["claude-sonnet-4-5", "claude-haiku-3-5"],
  "expires_at": "2026-03-08T00:00:00Z"
}
```

---

### POST /api/v1/keys/service

Create a service-scoped virtual key (ci, agent:review, agent:write). Called by `manage-service-keys.sh`.

**Request:**

```bash
curl -X POST http://key-provisioner.coder-production.local:8100/api/v1/keys/service \
  -H "Content-Type: application/json" \
  -H "X-Provisioner-Secret: ${PROVISIONER_SECRET}" \
  -d '{
    "scope": "ci",
    "name": "github-actions-main",
    "budget_usd": 10,
    "duration": "1h"
  }'
```

**Response (200):**

```json
{
  "key": "sk-litellm-ci-def456...",
  "scope": "ci",
  "name": "github-actions-main",
  "budget_usd": 10.0,
  "rpm_limit": 120,
  "models": ["claude-haiku-3-5"],
  "expires_at": "2026-02-06T15:30:00Z"
}
```

---

### DELETE /api/v1/keys/{key_name}

Revoke an active key by name.

**Request:**

```bash
curl -X DELETE http://key-provisioner.coder-production.local:8100/api/v1/keys/pr-review-bot \
  -H "X-Provisioner-Secret: ${PROVISIONER_SECRET}"
```

**Response (200):**

```json
{
  "revoked": true,
  "name": "pr-review-bot",
  "revoked_at": "2026-02-06T14:45:00Z"
}
```

**Error (404):**

```json
{
  "error": "key not found",
  "name": "pr-review-bot"
}
```

---

## Troubleshooting

### Key Provisioner Unreachable

**Symptom:** Startup script fails with `connection refused` when calling `key-provisioner.coder-production.local:8100`.

**Cause:** The key-provisioner ECS service is not running, unhealthy, or Cloud Map DNS is not resolving.

**Fix:**

```bash
# Check ECS service status
aws ecs describe-services \
  --cluster coder-production \
  --services key-provisioner \
  --query 'services[0].{status:status,running:runningCount,desired:desiredCount}'

# Check Cloud Map service discovery
aws servicediscovery list-instances \
  --service-id <key-provisioner-service-id>

# Check task logs in CloudWatch
aws logs tail /ecs/coder-production/key-provisioner --follow

# Force new deployment if stuck
aws ecs update-service \
  --cluster coder-production \
  --service key-provisioner \
  --force-new-deployment
```

If the Terraform state needs updating:

```bash
cd terraform/modules/ecs
terraform plan -target=module.key_provisioner
terraform apply -target=module.key_provisioner
```

---

### Key Not Auto-Provisioned

**Symptom:** Workspace starts but Roo Code has no API key configured. `LITELLM_API_KEY` is empty.

**Cause:** The startup script failed silently, or the provisioner secret in Secrets Manager does not match.

**Fix:**

```bash
# Inside the workspace, check the startup log
cat /tmp/startup.log

# Verify the secret exists in AWS Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id coder-prod/provisioner/secret \
  --query 'SecretString' --output text

# Test the provisioner manually from within the VPC
curl -s http://key-provisioner.coder-production.local:8100/api/v1/keys/workspace \
  -H "Content-Type: application/json" \
  -H "X-Provisioner-Secret: ${PROVISIONER_SECRET}" \
  -d '{
    "workspace_id": "test",
    "workspace_name": "test",
    "coder_user": "test",
    "coder_user_id": "test"
  }'

# If the secret was rotated, force a new ECS deployment to pick it up
aws ecs update-service \
  --cluster coder-production \
  --service key-provisioner \
  --force-new-deployment
```

---

### Budget Exceeded

**Symptom:** AI requests return 429 or a budget error from LiteLLM.

**Cause:** The virtual key's budget has been exhausted.

**Fix:**

```bash
# Check key spend via LiteLLM
curl -s http://litellm.coder-production.local:4000/key/info \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -d '{"key": "sk-litellm-ws-abc123..."}'

# If budget is hit, either:
# 1. Wait for the budget period to reset
# 2. Revoke the old key and create a new one
./manage-service-keys.sh rotate --name "contractor-alice"
```

---

### Virtual Key Returns 401 from LiteLLM

**Symptom:** Requests with a virtual key get `401 Unauthorized` from LiteLLM.

**Cause:** The key has been revoked, expired, or LiteLLM's backing database lost the key record.

**Fix:**

```bash
# Verify the key exists in LiteLLM
curl -s http://litellm.coder-production.local:4000/key/info \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -d '{"key": "sk-litellm-ws-abc123..."}'

# Check RDS connectivity from LiteLLM
aws ecs execute-command \
  --cluster coder-production \
  --task <litellm-task-id> \
  --container litellm \
  --interactive \
  --command "/bin/sh -c 'pg_isready -h $DATABASE_HOST'"

# If key is missing, re-provision:
# For workspaces — restart the workspace (triggers startup script)
# For services — recreate with manage-service-keys.sh
```

---

### Provisioner Secret Mismatch After Rotation

**Symptom:** Provisioner returns `401 invalid provisioner secret`.

**Cause:** The secret was rotated in AWS Secrets Manager but the ECS task is still using the cached old value.

**Fix:**

```bash
# Force a new deployment to pick up the new secret
aws ecs update-service \
  --cluster coder-production \
  --service key-provisioner \
  --force-new-deployment

# Wait for the new task to be running
aws ecs wait services-stable \
  --cluster coder-production \
  --services key-provisioner

# Verify the new task picked up the secret
aws ecs execute-command \
  --cluster coder-production \
  --task <new-task-id> \
  --container key-provisioner \
  --interactive \
  --command "printenv PROVISIONER_SECRET"
```

Note: ECS tasks fetch secrets from Secrets Manager at launch time. Rotating a secret in Secrets Manager does not automatically update running tasks. You must force a new deployment.

---

### Cloud Map DNS Not Resolving

**Symptom:** `curl: (6) Could not resolve host: key-provisioner.coder-production.local`

**Cause:** The ECS service is not registered with Cloud Map, or the VPC DNS settings are misconfigured.

**Fix:**

```bash
# Verify the Cloud Map namespace exists
aws servicediscovery list-namespaces \
  --query "Namespaces[?Name=='coder-production.local']"

# Verify the service is registered
aws servicediscovery list-services \
  --query "Services[?Name=='key-provisioner']"

# Check registered instances
aws servicediscovery list-instances \
  --service-id <service-id>

# If missing, re-apply Terraform
cd terraform/modules/ecs
terraform plan
terraform apply
```
