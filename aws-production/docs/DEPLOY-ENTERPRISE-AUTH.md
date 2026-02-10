# AWS Deployment Guide — Claude Code Enterprise Auth Migration

**Date:** 2026-02-10
**Scope:** Migrate Claude Code CLI from LiteLLM pass-through to Anthropic Enterprise native auth
**Environments:** PoC (Docker Compose) + AWS Production (ECS Fargate)
**Prerequisite:** Anthropic Enterprise licensing active (50 seats, per-seat subscription)

---

## Table of Contents

1. [Overview](#1-overview)
2. [What Changed](#2-what-changed)
3. [Pre-Deployment Checklist](#3-pre-deployment-checklist)
4. [Step 1 — Verify AWS Security Group (Port 443)](#step-1--verify-aws-security-group-port-443)
5. [Step 2 — Build Updated Workspace Image](#step-2--build-updated-workspace-image)
6. [Step 3 — Push Updated Templates to Coder](#step-3--push-updated-templates-to-coder)
7. [Step 4 — Recreate Workspaces](#step-4--recreate-workspaces)
8. [Step 5 — Verify Enterprise Auth Works](#step-5--verify-enterprise-auth-works)
9. [Step 6 — Deploy PoC (Docker Compose)](#step-6--deploy-poc-docker-compose)
10. [Step 7 — Post-Deployment Validation](#step-7--post-deployment-validation)
11. [Rollback Plan](#rollback-plan)
12. [FAQ](#faq)

---

## 1. Overview

### Before (LiteLLM Pass-Through)

```
Claude Code CLI → ANTHROPIC_BASE_URL → litellm:4000/anthropic → Anthropic API
                   (env var in container)    (LiteLLM proxy)
```

Claude Code was routed through LiteLLM's Anthropic pass-through endpoint. The workspace set `ANTHROPIC_BASE_URL` and `ANTHROPIC_API_KEY` environment variables at startup, and Claude Code thought it was talking to Anthropic but was actually going through LiteLLM for budget/guardrails/audit.

In PoC, the default route was Ollama on the host Mac (`ANTHROPIC_BASE_URL=http://host.docker.internal:11434`).

### After (Anthropic Enterprise)

```
Claude Code CLI → api.anthropic.com (HTTPS, port 443)
                   (native auth via `claude login`)
```

Claude Code now authenticates directly with Anthropic using Enterprise per-seat licensing. No `ANTHROPIC_BASE_URL` or `ANTHROPIC_API_KEY` needed. Users run `claude login` once, and tokens persist in `~/.claude/`.

**Fallback aliases are available:**

| Alias | Route | Use Case |
|-------|-------|----------|
| `claude` | Anthropic Enterprise (direct) | Default — full model access, latest features |
| `claude-litellm` | LiteLLM proxy (governed) | Budget tracking, guardrails, audit logging |
| `claude-local` | Ollama on host Mac (PoC only) | Offline, GPU-accelerated open-weight models |

### What Does NOT Change

- Roo Code configuration (LiteLLM, OpenAI-compatible)
- OpenCode configuration (LiteLLM, OpenAI-compatible)
- LiteLLM `config.yaml` (models, Bedrock routing)
- Key provisioner (still provisions keys for Roo Code/OpenCode)
- Ollama bashrc section + `OLLAMA_HOST` in container env (PoC)
- `~/.claude/settings.json` tool permissions
- Workspace base Dockerfile

---

## 2. What Changed

### Files Modified (10 total)

| File | Change | Environment |
|------|--------|-------------|
| `coder-poc/egress/global.conf` | Added `port:443` for Anthropic HTTPS | PoC |
| `coder-poc/templates/python-workspace/main.tf` | Removed Ollama env vars, added Enterprise auth + aliases | PoC |
| `coder-poc/templates/java-workspace/main.tf` | Same as python-workspace | PoC |
| `coder-poc/templates/nodejs-workspace/main.tf` | Same as python-workspace | PoC |
| `coder-poc/templates/dotnet-workspace/main.tf` | Same as python-workspace | PoC |
| `coder-poc/templates/docker-workspace/main.tf` | Same as python-workspace | PoC |
| `aws-production/templates/contractor-workspace/main.tf` | Removed LiteLLM env vars, added `claude-litellm` alias | Production |
| `aws-production/templates/docker-workspace/main.tf` | Added `claude-litellm` alias | Production |
| `shared/docs/FAQ.md` | Updated login FAQ, added Enterprise login FAQ | Both |
| `shared/docs/CLAUDE-CODE-LITELLM.md` | Doc history noting Enterprise migration | Both |

### Template Changes Detail

**Removed from `coder_agent.env` (PoC):**
```hcl
# These are GONE — no longer set at agent level
ANTHROPIC_BASE_URL  = "http://host.docker.internal:11434"
ANTHROPIC_AUTH_TOKEN = "ollama"
```

**Removed from bashrc (PoC):**
```bash
# These are GONE — no longer exported to shell
export ANTHROPIC_BASE_URL="http://host.docker.internal:11434"
export ANTHROPIC_AUTH_TOKEN="ollama"
```

**Removed from bashrc (Production):**
```bash
# These are GONE — no longer exported to shell
export ANTHROPIC_BASE_URL=$LITELLM_URL/anthropic
export ANTHROPIC_API_KEY=$LITELLM_KEY
export CLAUDE_CODE_USE_BEDROCK=0
export ANTHROPIC_MODEL=$ANTHROPIC_MODEL
```

**Added (both):**
```bash
# Governed fallback via LiteLLM (budget tracking, guardrails, audit)
alias claude-litellm='ANTHROPIC_BASE_URL="..." ANTHROPIC_API_KEY="$OPENAI_API_KEY" ANTHROPIC_AUTH_TOKEN="" claude'

# PoC only — local Ollama on host Mac
alias claude-local='ANTHROPIC_BASE_URL="http://host.docker.internal:11434" ANTHROPIC_AUTH_TOKEN="ollama" claude'
```

---

## 3. Pre-Deployment Checklist

### Anthropic Enterprise

- [ ] Enterprise contract signed (50 seats, 1-year term)
- [ ] Anthropic admin console access confirmed
- [ ] Admin can invite users + manage seats
- [ ] Enterprise SSO configured in Anthropic admin (if using SSO for `claude login`)
- [ ] Verify `api.anthropic.com` and `auth.anthropic.com` are reachable from workspace network

### AWS (Production)

- [ ] Confirm `sg-ecs-workspaces` allows port 443 outbound (already configured — see Step 1)
- [ ] NAT Gateway is running (required for workspaces to reach `api.anthropic.com`)
- [ ] ECR has latest workspace image (or will be rebuilt in Step 2)
- [ ] Coder deploy token (`CODER_DEPLOY_TOKEN`) is valid for template push
- [ ] GitLab CI runner has access to ECS cluster

### PoC (Docker Compose)

- [ ] Docker Compose environment running (`docker compose ps`)
- [ ] Coder admin session available (`coder login`)
- [ ] Egress firewall script supports `port:` rules (already does)

### Communication

- [ ] Users informed about `claude login` requirement on first use
- [ ] FAQ updated (already done in this change)
- [ ] Support team briefed on the 3 routes (Enterprise, LiteLLM, Ollama)

---

## Step 1 — Verify AWS Security Group (Port 443)

**Why:** Claude Code CLI needs HTTPS (port 443) outbound to reach `api.anthropic.com` and `auth.anthropic.com`.

**Expected:** Port 443 outbound is **already allowed** in the workspace security group. This step is verification only.

### 1.1 Verify via AWS Console

1. Open **VPC > Security Groups**
2. Find `coder-production-ecs-workspaces` (or your `sg-ecs-workspaces`)
3. Check **Outbound rules** tab
4. Confirm: `HTTPS (443) → 0.0.0.0/0 → Allow`

### 1.2 Verify via Terraform

```bash
cd aws-production/terraform

# Check the security group rule in main.tf
grep -A5 "workspaces_https" main.tf
```

Expected output:
```hcl
resource "aws_vpc_security_group_egress_rule" "workspaces_https" {
  security_group_id = aws_security_group.ecs_workspaces.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS outbound (NAT)"
}
```

### 1.3 Verify via AWS CLI

```bash
aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=sg-XXXXXXXXX" \
  --query "SecurityGroupRules[?IsEgress && FromPort==\`443\`]" \
  --output table \
  --region us-west-2
```

**Result:** If port 443 outbound exists, no Terraform changes needed. Move to Step 2.

> **Note:** Unlike the PoC egress firewall (which uses iptables and can't filter by domain), AWS Security Groups are stateful and already scoped. Port 443 outbound was already needed for pip/npm installs and Bedrock API calls.

---

## Step 2 — Build Updated Workspace Image

**Why:** The template `main.tf` changes (env vars, bashrc, aliases) take effect at workspace **startup script** time, not at image build time. However, if you've made any Dockerfile changes, rebuild now.

### 2.1 Check if Dockerfile Changed

```bash
# If the only changes are in main.tf, skip the image rebuild
git diff --name-only HEAD~1 -- aws-production/templates/*/build/
```

If no Dockerfile changes: **skip to Step 3**.

### 2.2 Rebuild and Push (if needed)

**Via GitLab CI (recommended):**

```bash
# Tag a release to trigger the CI pipeline
git tag v2.x.x-enterprise-auth
git push origin v2.x.x-enterprise-auth

# CI pipeline runs:
# 1. build-workspace-image → builds + pushes to ECR
# 2. scan-workspace-image → Trivy scan
# 3. deploy-* → manual approval gates
```

**Manual (emergency):**

```bash
# Authenticate to ECR
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.us-west-2.amazonaws.com/coder-workspace

# Build
docker build \
  -t ${AWS_ACCOUNT_ID}.dkr.ecr.us-west-2.amazonaws.com/coder-workspace:latest \
  aws-production/templates/contractor-workspace/build/

# Push
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.us-west-2.amazonaws.com/coder-workspace:latest
```

---

## Step 3 — Push Updated Templates to Coder

**Why:** The `main.tf` changes (removed env vars, new aliases, updated startup messages) must be pushed to Coder so new/recreated workspaces use the updated template.

### 3.1 Via GitLab CI (recommended)

The `push-workspace-template` job runs automatically after `deploy-coder`:

```yaml
# .gitlab-ci.yml (already configured)
push-workspace-template:
  script:
    - coder templates push contractor-workspace --directory templates/contractor-workspace --yes
```

Trigger by tagging a release or running the job manually.

### 3.2 Manual Push (Production)

```bash
# Get Coder CLI from the production ALB
CODER_URL=https://coder.${DOMAIN_NAME}
curl -fsSL ${CODER_URL}/bin/coder-linux-amd64 -o /usr/local/bin/coder
chmod +x /usr/local/bin/coder

# Authenticate
export CODER_URL
export CODER_SESSION_TOKEN=${CODER_DEPLOY_TOKEN}

# Push contractor-workspace template
coder templates push contractor-workspace \
  --directory aws-production/templates/contractor-workspace \
  --yes

# Push docker-workspace template (if used)
coder templates push docker-workspace \
  --directory aws-production/templates/docker-workspace \
  --yes
```

### 3.3 Verify Template Version

```bash
coder templates versions list contractor-workspace
```

Confirm the latest version has today's date.

---

## Step 4 — Recreate Workspaces

**Why:** Environment variables (`ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY`) are baked into the workspace at startup time. Template push alone does NOT update running workspaces. Users must recreate their workspaces to pick up the new template.

### 4.1 Communicate to Users

Send to all Claude Code users:

> **Action Required:** Claude Code is migrating to Anthropic Enterprise auth.
>
> **What you need to do:**
> 1. Push any uncommitted work to Git
> 2. Delete your current workspace
> 3. Create a new workspace from the updated template
> 4. On first use of `claude`, run `claude login` and follow the browser flow
>
> **Your Roo Code and OpenCode continue to work unchanged.**
>
> **New aliases available:**
> - `claude` — Anthropic Enterprise (default)
> - `claude-litellm` — Governed route via LiteLLM
> - `claude-local` — Ollama on host Mac (PoC only)

### 4.2 Admin-Forced Recreation (if needed)

```bash
# List all workspaces
coder list --all

# For each workspace that needs updating:
coder delete <workspace-name> --orphan  # keeps EFS data
# User recreates from updated template
```

> **Important:** EFS access points persist across workspace deletion. User data in `/home/coder` survives recreation. However, any custom `.bashrc` additions will be overwritten by the new startup script.

### 4.3 Gradual Rollout (recommended)

1. Push template (Step 3)
2. Test with one admin workspace first
3. Announce to users — let them recreate at their convenience
4. Set a deadline (e.g., 1 week) for all workspaces to be recreated
5. After deadline, admin-delete remaining old workspaces

---

## Step 5 — Verify Enterprise Auth Works

### 5.1 Create Test Workspace

```bash
# Create a workspace from the updated template
coder create test-enterprise --template contractor-workspace
```

### 5.2 Open Terminal and Run Claude

```bash
# In the workspace terminal:
claude

# Expected: "Select login method" prompt
# Select: "Claude account with subscription" (option 1)
# Follow browser-based login flow
# Auth token saved in ~/.claude/
```

### 5.3 Verify Aliases Work

```bash
# Governed route (LiteLLM)
claude-litellm
# Expected: Claude starts, routed through LiteLLM
# Verify: ai-usage shows the request

# Local route (PoC only)
claude-local
# Expected: Claude starts, routed to Ollama on host Mac
```

### 5.4 Verify No Stale Env Vars

```bash
# These should NOT be set (Enterprise auth doesn't use them)
echo "ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL"
echo "ANTHROPIC_AUTH_TOKEN=$ANTHROPIC_AUTH_TOKEN"
echo "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY"

# Expected: all empty
```

### 5.5 Verify Roo Code Still Works

1. Open VS Code (code-server) in the workspace
2. Click Roo Code icon in sidebar
3. Send a test message
4. Verify it works via LiteLLM (unchanged)

### 5.6 Verify OpenCode Still Works

```bash
opencode
# Expected: starts normally, connects to LiteLLM
```

---

## Step 6 — Deploy PoC (Docker Compose)

### 6.1 Push All 5 PoC Templates

```bash
cd coder-poc

# Push each template
for template in python java nodejs dotnet docker; do
  echo "Pushing ${template}-workspace..."
  docker exec -e CODER_URL=https://host.docker.internal:7443 \
    -e CODER_SESSION_TOKEN=$ADMIN_TOKEN \
    coder-server \
    coder templates push ${template}-workspace \
    --directory /tmp/${template}-workspace \
    --yes
done
```

Or use the setup script:

```bash
cd coder-poc
./scripts/setup-workspace.sh
```

### 6.2 Verify Egress Firewall

```bash
# Check that port 443 is in the global egress config
docker exec <workspace-container> cat /etc/egress-global.conf | grep "port:443"

# Test HTTPS connectivity from workspace
docker exec <workspace-container> curl -sf https://api.anthropic.com/ -o /dev/null && echo "OK" || echo "BLOCKED"
```

### 6.3 Recreate Test Workspace

1. Delete existing workspace in Coder UI
2. Create new workspace from updated template
3. Run `claude` — should show Enterprise login prompt
4. Run `claude-litellm` — should connect via LiteLLM
5. Run `claude-local` — should connect to host Ollama

---

## Step 7 — Post-Deployment Validation

### 7.1 Smoke Tests

| Test | Command | Expected |
|------|---------|----------|
| Claude Enterprise auth | `claude` → login flow | Login prompt, browser auth, token saved |
| Claude session persistence | Restart workspace, run `claude` | No login prompt (token persisted in `~/.claude/`) |
| `claude-litellm` alias | `claude-litellm` | Claude starts via LiteLLM, `ai-usage` shows request |
| `claude-local` alias (PoC) | `claude-local` | Claude starts via Ollama |
| Roo Code | Click sidebar icon | AI panel opens, can chat |
| OpenCode | `opencode` | TUI starts, can chat |
| No stale env vars | `env \| grep ANTHROPIC` | Only aliases, no exports |
| Port 443 outbound | `curl -sf https://api.anthropic.com/` | Connection succeeds |
| EFS persistence | Delete + recreate workspace | `~/.claude/` tokens survive |

### 7.2 Monitoring

**Anthropic Admin Console:**
- Verify seat usage (should show active seats after users log in)
- Check usage per user
- Review any rate limiting or policy violations

**LiteLLM (for `claude-litellm` usage):**
- `ai-usage` in workspace terminal
- LiteLLM admin UI at `http://localhost:4000/ui` (PoC) or `https://ai.${DOMAIN_NAME}/ui` (production)
- Langfuse dashboard for request traces

### 7.3 CloudWatch (Production)

```bash
# Check workspace logs for startup errors
aws logs filter-log-events \
  --log-group-name /ecs/coder-production/workspaces \
  --filter-pattern "Claude Code" \
  --start-time $(date -d '1 hour ago' +%s000) \
  --region us-west-2
```

---

## Rollback Plan

### If Enterprise Auth Fails

**Symptom:** Users can't `claude login`, Anthropic Enterprise service is down, etc.

**Immediate workaround (no template change needed):**

```bash
# Users can switch to the governed LiteLLM route
claude-litellm
```

This alias is baked into the updated templates and works without Enterprise auth.

### Full Rollback (revert to LiteLLM default)

If you need to fully revert:

```bash
# 1. Revert the template changes
git revert <commit-hash>

# 2. Push reverted templates
coder templates push contractor-workspace --directory templates/contractor-workspace --yes

# 3. Users recreate workspaces (or admin deletes + recreates)
```

**PoC egress:** The `port:443` rule in `egress/global.conf` is harmless to keep — it was already needed for pip/npm installs in some cases. Remove it only if you want to tighten the firewall.

### Partial Rollback (per-user)

For individual users who can't use Enterprise auth:

```bash
# Add to their ~/.bashrc manually
export ANTHROPIC_BASE_URL="http://litellm:4000/anthropic"  # PoC
# or
export ANTHROPIC_BASE_URL="http://litellm.coder-production.local:4000/anthropic"  # Production
export ANTHROPIC_API_KEY="$OPENAI_API_KEY"
```

---

## FAQ

### Q: Do users need to re-login after workspace restart?

**A:** No. The `claude login` auth token is saved in `~/.claude/` which is on the persistent volume (Docker volume in PoC, EFS in production). It survives workspace restarts and even workspace deletion + recreation (EFS access points persist).

### Q: What if a user's Enterprise seat is revoked?

**A:** Running `claude` will fail with an auth error. The user can still use `claude-litellm` (governed LiteLLM route) as a fallback — this uses their auto-provisioned LiteLLM virtual key, not their Enterprise seat.

### Q: Does this affect AI cost tracking?

**A:** Partially. Requests via `claude` (Enterprise direct) are tracked in the **Anthropic admin console** (not LiteLLM/Langfuse). Requests via `claude-litellm` are still tracked in LiteLLM + Langfuse. If you need unified cost tracking, use `claude-litellm` exclusively.

### Q: Why not remove LiteLLM Anthropic pass-through entirely?

**A:** LiteLLM's Anthropic pass-through is still used by the `claude-litellm` alias for governed usage (budget caps, content guardrails, audit logging). It also serves as a fallback if Enterprise auth is unavailable. Roo Code and OpenCode continue to use LiteLLM's OpenAI-compatible endpoint.

### Q: Can I enforce Enterprise-only (block `claude-litellm`)?

**A:** Yes. Remove the `claude-litellm` alias from the template's bashrc section. Without `ANTHROPIC_BASE_URL` set, `claude` only works via Enterprise auth. However, keeping the alias as a fallback is recommended.

### Q: Does this require any AWS Secrets Manager changes?

**A:** No. The `prod/litellm/anthropic-api-key` secret stays — it's used by LiteLLM for the Anthropic API fallback (Bedrock is primary). Enterprise auth is handled client-side by Claude Code CLI, not server-side.

### Q: What about the `anthropic_model_map` locals in the production template?

**A:** The `anthropic_model_map` and `anthropic_model_id` locals in `contractor-workspace/main.tf` are now unused (they were for the `ANTHROPIC_MODEL` export which was removed). They're harmless dead code — remove them in a follow-up cleanup if desired.

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-10 | Platform Team | Initial version — Enterprise auth migration deployment guide |
