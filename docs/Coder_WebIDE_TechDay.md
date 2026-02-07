# Coder WebIDE Platform -- Tech Day Presentation

**Audience:** CTO / Technical Leadership
**Format:** Tech Day presentation notes with live demo
**Date:** February 2026

---

## 1. Executive Summary

We built a browser-based development platform that gives contractors full IDE access -- VS Code, terminal, AI coding agents -- without issuing VPN credentials, laptops, or API keys. The platform runs 14 integrated services on Docker Compose today and has a production deployment plan for AWS (ECS Fargate + managed services). Every contractor works in an isolated container with OIDC SSO, per-user AI budgets, tamper-proof behavior controls, and a complete audit trail. The result: contractors can write, test, and ship code from any browser, while we retain full control over source code, AI spend, and access lifecycle.

**Key stats:**

| Metric | Value |
|--------|-------|
| Services integrated | 14 (PoC Docker Compose) |
| Access method | Browser-only (VS Code Desktop, SSH, port forwarding disabled) |
| Authentication | OIDC SSO via Authentik (Azure AD federation ready) |
| AI tools | Roo Code (VS Code agent) + OpenCode (terminal agent) |
| AI proxy | LiteLLM with per-user virtual keys, budgets, and audit |
| AI enforcement | Server-side tamper-proof behavior controls (3 levels) |
| Production target | AWS ECS Fargate, ~8-week deployment timeline |

---

## 2. Problem Statement

### Why Contractors Need Isolated Dev Environments

Organizations routinely engage contractors for software development. The traditional approach -- issue a laptop, grant VPN access, distribute credentials -- creates significant risk that scales with contractor count.

### Risks of the Traditional Model

| Risk | Description | Impact |
|------|-------------|--------|
| **Data exfiltration** | Contractor has local copies of source code on personal/issued hardware | IP leaves the organization permanently |
| **Credential sprawl** | VPN creds, Git tokens, API keys, DB passwords distributed to external parties | Attack surface grows linearly with headcount |
| **Shadow AI usage** | Contractors paste proprietary code into ChatGPT, Copilot, or personal AI accounts | Code enters third-party training data; no audit trail |
| **Inconsistent offboarding** | Revoking access requires touching VPN, Git, cloud IAM, laptop retrieval | Incomplete offboarding = persistent access |
| **Compliance gaps** | No centralized audit trail for contractor actions across systems | SOC 2, GDPR, and regulatory exposure |

### What We Need

- **Zero-install access** -- browser only, no software on contractor machines
- **Complete isolation** -- per-user containers, no cross-workspace visibility
- **Centralized AI governance** -- every AI request logged, budgeted, and policy-controlled
- **Instant offboarding** -- delete workspace, revoke SSO, done
- **Audit everything** -- logins, workspace lifecycle, AI usage, Git operations

---

## 3. Solution Architecture

### High-Level Architecture

```
 CONTRACTORS (Browser Only)
 ==============================
 |  Web IDE  |  Web Terminal  |
 ==============================
              |
         HTTPS (TLS)
              |
 ==============================  APPLICATION LAYER
 |                            |
 |  Coder Server (7443)       |  Workspace orchestration, templates, RBAC
 |                            |
 |  Authentik (9000)          |  OIDC identity provider, MFA, Azure AD ready
 |  Gitea (3000)              |  Self-hosted Git with OIDC integration
 |  LiteLLM (4000)            |  AI proxy: routing, budgets, audit, enforcement
 |  Key Provisioner (8100)    |  Automated virtual key lifecycle
 |  Platform Admin (5050)     |  Unified admin dashboard
 |  Drone CI (8080)           |  CI/CD pipelines
 |                            |
 ==============================
              |
 ==============================  DATA LAYER
 |                            |
 |  PostgreSQL                |  Coder, Authentik, LiteLLM databases
 |  Redis                     |  Sessions, cache
 |  MinIO                     |  S3-compatible object storage
 |  DevDB / TestDB            |  Developer and test databases
 |                            |
 ==============================
              |
 ==============================  WORKSPACE LAYER
 |                            |
 |  [WS-1: Alice]  [WS-2: Bob]  [WS-N: ...]
 |  code-server + Coder agent + Roo Code + OpenCode
 |  Per-user container, non-root, resource-limited
 |                            |
 ==============================
              |
         AI PROVIDERS
  (AWS Bedrock / Anthropic API)
```

### Core Components

| Component | Purpose |
|-----------|---------|
| **Coder** | Workspace orchestration -- provisions, manages, and destroys per-user development containers |
| **Authentik** | OIDC identity provider with MFA support; federation-ready for Azure AD, Okta, or AWS IAM Identity Center |
| **Gitea** | Self-hosted Git server with OIDC integration; eliminates dependency on external Git providers |
| **LiteLLM** | Centralized AI proxy -- OpenAI-compatible API with per-user virtual keys, budget enforcement, rate limiting, and audit logging |
| **Key Provisioner** | Microservice that isolates the LiteLLM master key; auto-provisions scoped virtual keys for workspaces |
| **Roo Code** | AI coding agent in VS Code (agentic coding, chat, file operations, test generation) |
| **OpenCode** | Terminal-based AI coding agent (TUI, file editing, command execution) |
| **PostgreSQL** | Shared database for Coder, Authentik, and LiteLLM (separate databases, shared instance) |
| **Redis** | Session cache for Authentik; pub/sub for Coder |
| **MinIO** | S3-compatible object storage for artifacts and build outputs |

---

## 4. Key Capabilities

| Capability | Implementation | Business Value |
|------------|---------------|----------------|
| **Browser-only access** | VS Code Desktop, SSH, and port forwarding disabled in Coder templates; code-server + web terminal only | No software on contractor machines; no data leaves the browser session |
| **Zero-trust workspace isolation** | Per-user Docker containers; non-root (UID 1000); CPU/memory limits; `CODER_DISABLE_WORKSPACE_SHARING=true` | No cross-workspace access; lateral movement impossible |
| **Enterprise SSO** | Authentik OIDC with identity sync across Coder, Gitea; Azure AD federation ready | Single identity lifecycle; offboard once, revoke everywhere |
| **AI-assisted development** | Roo Code (VS Code) + OpenCode (terminal) via centralized LiteLLM proxy | Contractors get AI coding tools without direct access to API keys or provider accounts |
| **Per-user AI budgets** | LiteLLM virtual keys with hard spend caps ($5-$20/day), rate limits (30-60 RPM), model restrictions | Predictable AI costs; no surprise bills; granular cost attribution |
| **AI behavior controls** | Server-side enforcement hook (LiteLLM callback) + client-side config reinforcement; 3 levels: unrestricted, standard, design-first | Tamper-proof control over AI agent behavior; new contractors get guardrails; experienced devs get freedom |
| **Audit trail** | Every AI request logged: user, model, tokens, cost, timestamp; Coder audit logs for workspace lifecycle | Full accountability; compliance-ready metadata logging; privacy-first (no prompt content by default) |
| **Self-hosted Git** | Gitea with OIDC integration; internal network only | Source code never leaves the platform; no external Git dependency |

> **Key Takeaway:** The platform provides the full modern developer experience -- IDE, terminal, AI agents, Git, CI/CD -- in a browser, while retaining complete organizational control over code, credentials, AI usage, and access lifecycle.

---

## 5. AI Integration Deep Dive

### Why a Centralized AI Proxy

Distributing API keys to contractors is the AI equivalent of distributing database passwords. It creates unauditable, unbudgeted, uncontrollable access to expensive services.

| Dimension | Direct API Keys to Contractors | Centralized LiteLLM Proxy |
|-----------|-------------------------------|--------------------------|
| Cost control | Honor system | Hard per-user budget caps with automatic cutoff |
| Audit trail | None | Every request logged: user, model, tokens, cost |
| Key exposure | Raw provider keys in workspace env | Virtual keys only; master key never exposed |
| Model governance | Contractors choose any model | Model access restricted per key scope |
| Behavior control | None | Server-side enforcement hook (tamper-proof) |
| Provider flexibility | Locked to one provider | Transparent routing to Bedrock, Anthropic, or future providers |
| Offboarding | Must rotate provider keys | Revoke virtual key; immediate effect |

### Three Enforcement Levels

| Level | System Prompt Injected | Design Proposal Required | Code in First Response | Use Case |
|-------|----------------------|--------------------------|----------------------|----------|
| **Unrestricted** | None | No | Allowed | Quick tasks, experienced developers |
| **Standard** (default) | Lightweight 6-point reasoning checklist | Encouraged | Allowed | Daily development |
| **Design-First** | Full architect-mode prompt | **Mandatory** | **Blocked** | Complex features, new contractors |

### Dual Enforcement Architecture

```
 Workspace Template Parameter
 (ai_enforcement_level: standard | design-first | unrestricted)
              |
     +--------+--------+
     |                  |
     v                  v
 KEY PROVISIONER    STARTUP SCRIPT
 Stores level in    Writes client configs
 key metadata       with matching prompts
     |                  |
     v                  v
 LiteLLM Hook       Roo Code customInstructions
 (SERVER-SIDE)      OpenCode enforcement.md
 Reads metadata,    (CLIENT-SIDE)
 injects prompt     Advisory reinforcement
 TAMPER-PROOF       (user could modify)
```

**Server-side enforcement is the authoritative control.** The LiteLLM `CustomLogger` callback reads `enforcement_level` from the virtual key's metadata and prepends the mandatory system prompt to every chat completion request. This happens inside the proxy -- users cannot disable, modify, or bypass it from the workspace.

Client-side config (Roo Code `customInstructions`, OpenCode `enforcement.md`) reinforces the same rules in the tool's native UX but is advisory only.

### Cost Control

| Model Tier | Model | Relative Cost | Best For |
|------------|-------|---------------|----------|
| $ | Claude Haiku 4.5 | Lowest | Autocomplete, quick Q&A, simple tasks |
| $$ | Claude Sonnet 4.5 | Medium | General coding, code review, test generation |
| $$$ | Claude Opus 4.5 | Highest | Complex architecture, multi-file refactoring |

Budget controls per key scope:

| Key Scope | Budget | Rate Limit | Models Allowed | Duration |
|-----------|--------|------------|----------------|----------|
| Workspace | $5/day | 30 RPM | Sonnet + Haiku | Session |
| User (self-service) | $20/day | 60 RPM | Sonnet + Haiku | 30 days |
| CI pipeline | $10/run | 120 RPM | Haiku only | 1 hour |
| Agent (review) | $2/run | 60 RPM | Haiku only | 1 hour |
| Agent (write) | $8/run | 30 RPM | Sonnet | 2 hours |

### Key Isolation

The **master API key** (Anthropic/Bedrock credential) never leaves the LiteLLM container. The **Key Provisioner** microservice is the only component that holds the LiteLLM admin key. Workspaces authenticate to the provisioner with a shared infrastructure secret, receive a scoped virtual key, and use that key for all AI requests. Revoking a virtual key takes effect immediately.

> **Key Takeaway:** AI is a first-class platform capability, not an afterthought. Every AI interaction is authenticated, budgeted, behavior-controlled, and auditable -- with the master credentials completely isolated from contractors.

---

## 6. Security Posture

### Security Summary

| Domain | Implementation |
|--------|----------------|
| **Authentication** | OIDC via Authentik; MFA-ready (TOTP/WebAuthn); Azure AD federation supported |
| **Authorization** | Coder RBAC with 4 roles: Owner, Template Admin, Member, Auditor |
| **Session management** | 8-hour max session; secure cookies (HTTPS required); TLS 1.2+ |
| **Workspace isolation** | Per-user containers; non-root; no workspace sharing; VS Code Desktop/SSH/port forwarding disabled |
| **Network** | Data services internal-only (PostgreSQL, Redis, DevDB not exposed to host); workspace containers on shared Docker network (production: per-task ENI with security groups) |
| **AI security** | All AI traffic through audited LiteLLM proxy; enforcement hook for behavior control; three-layer AI lockdown |
| **Data protection** | No PII in prompts (policy); metadata-only logging by default; prompt content logging opt-in |
| **Secrets** | `.env` file (PoC); AWS Secrets Manager (production); master keys never in workspaces |

### Three-Layer AI Lockdown

Every competing AI feature is explicitly disabled to ensure all AI traffic routes through LiteLLM:

| Layer | What's Disabled | How |
|-------|----------------|-----|
| **1. Server environment** | Coder AI Bridge, GitHub OAuth | `CODER_AIBRIDGE_ENABLED=false`, `CODER_HIDE_AI_TASKS=true` |
| **2. VS Code settings** | Copilot, Copilot Chat, Cody, inline suggestions, VS Code chat | All `github.copilot.*`, `cody.*`, `chat.*` settings set to `false` |
| **3. Dockerfile** | Extension removal | `code-server --uninstall-extension` for Copilot, Copilot Chat, Cody |

### RBAC Permission Matrix

| Action | Owner | Template Admin | Member | Auditor |
|--------|-------|----------------|--------|---------|
| Create users | Yes | -- | -- | -- |
| Manage templates | Yes | Yes | -- | -- |
| View all workspaces | Yes | Yes | -- | -- |
| Create own workspace | Yes | Yes | Yes | -- |
| Access own workspace | Yes | Yes | Yes | -- |
| View audit logs | Yes | -- | -- | Yes |
| Deployment settings | Yes | -- | -- | -- |

> **Key Takeaway:** Security is defense-in-depth: OIDC authentication, RBAC authorization, container isolation, network segmentation, AI proxy enforcement, and three-layer lockdown of competing AI features. The platform is designed for zero-trust -- every action is authenticated and auditable.

---

## 7. Cost Model

### PoC Cost

The PoC runs as Docker Compose on a single host. Infrastructure cost is essentially zero beyond the host machine and upstream AI API keys. This makes it ideal for validation and demonstration.

### Production Estimate (AWS)

Based on the production plan targeting ECS Fargate + managed services:

#### Small Deployment (50 users, 20 concurrent workspaces)

| Resource | Specification | Monthly Cost |
|----------|---------------|--------------|
| ECS Fargate -- Platform services | Coder, Authentik, LiteLLM (always-on) | $175 |
| ECS Fargate -- Workspaces | 20 concurrent x 2 vCPU x 4 GB (Spot) | $450 |
| RDS PostgreSQL | db.r6g.large (Single-AZ) | $175 |
| ElastiCache Redis | cache.r6g.large | $200 |
| EFS (workspace storage) | ~200 GB | $60 |
| Internal ALB + NAT + S3 + Secrets + CloudWatch | Supporting services | $118 |
| Bedrock (AI) | ~$5/user/month average | $250 |
| **Total** | | **~$1,500/month** |

#### Medium Deployment (200 users, 50 concurrent workspaces)

| Resource | Specification | Monthly Cost |
|----------|---------------|--------------|
| ECS Fargate -- Platform + Workspaces | Scaled services + 50 concurrent workspaces | $1,510 |
| Managed data services | RDS, ElastiCache, EFS, S3 | $915 |
| Monitoring + networking | CloudWatch, Grafana, ALB, NAT | $184 |
| Bedrock (AI) | ~$5/user/month average | $1,000 |
| **Total** | | **~$3,760/month** |

#### Per-Developer Cost Drivers

| Cost Driver | Control Lever |
|-------------|---------------|
| Compute (vCPU + memory) | Workspace sizing parameters; Fargate Spot (~70% savings) |
| Storage (EFS) | EFS Intelligent-Tiering for inactive workspaces |
| AI usage (Bedrock/Anthropic) | Per-user budget caps; model-tier restrictions; usage analytics |

### Budget Controls

- **Hard caps:** Per-user virtual key budgets ($5-$20/day); automatic cutoff when exceeded
- **Model restrictions:** Keys can be scoped to cheaper models (Haiku-only for CI)
- **Alerts:** CloudWatch billing alarms at configurable thresholds
- **Analytics:** LiteLLM admin UI shows per-user spend; global spend API for reporting

> **Key Takeaway:** At ~$30/user/month for infrastructure + AI, this is cost-competitive with commercial alternatives while providing significantly more control. Budget caps on AI usage prevent cost surprises.

---

## 8. Production Readiness

### What's Done (PoC)

| Area | Status |
|------|--------|
| Full feature set | 14 services running in Docker Compose |
| OIDC SSO | Authentik integrated with Coder and Gitea |
| AI proxy | LiteLLM with per-user virtual keys, budgets, rate limits |
| AI enforcement | Server-side tamper-proof hook with 3 enforcement levels |
| Key management | Key Provisioner microservice; auto-provisioning on workspace start |
| AI tools | Roo Code (VS Code) + OpenCode (terminal) fully configured |
| AI lockdown | Three-layer lockdown: Copilot, Cody, AI Bridge all disabled |
| TLS | HTTPS on port 7443 (self-signed cert); secure context for webviews |
| Workspace isolation | Non-root containers, no sharing, VS Code/SSH/port forwarding disabled |
| Admin tooling | Platform admin dashboard, self-service key generation, service key management |
| Automated testing | Enforcement test suite, access control validation scripts |

### What's Needed for Production

| Item | AWS Service | Effort | Status |
|------|-------------|--------|--------|
| VPC + networking | VPC, subnets, NAT, VPC endpoints | Week 1-2 | Terraform modules drafted |
| Compute | ECS Fargate cluster + Cloud Map | Week 1-2 | Terraform modules drafted |
| Database | Amazon RDS (PostgreSQL 16, Single-AZ) | Week 1-2 | Terraform module drafted |
| Cache | Amazon ElastiCache (Redis 7.x) | Week 1-2 | Terraform module drafted |
| Storage | S3 + EFS (per-workspace access points) | Week 1-2 | Terraform modules drafted |
| TLS | ACM certificates + Internal ALB | Week 3-4 | Terraform module drafted |
| Secrets | AWS Secrets Manager + IAM task roles | Week 1-2 | Terraform modules drafted |
| Monitoring | CloudWatch + Managed Grafana | Week 7 | Planned |
| Backup/DR | RDS snapshots, EFS backups, S3 cross-region | Week 8 | Planned |
| CI/CD | GitLab CI + AWS Runner | Week 8 | Planned |
| Security hardening | Workspace isolation via security groups, VPC Flow Logs, GuardDuty | Week 5-6 | Planned |
| Load testing | Concurrent workspace scaling validation | Week 8 | Planned |

**Total estimated timeline:** 8 weeks from start to production-ready.

> **Key Takeaway:** The PoC has validated every integration point. Production is primarily an infrastructure migration -- replacing Docker Compose with AWS managed services. No application-level changes needed. Terraform modules are already drafted for all major components.

---

## 9. Comparison with Alternatives

| Dimension | This Platform | GitHub Codespaces | Gitpod | VPN + Laptop |
|-----------|---------------|-------------------|--------|-------------|
| **Data control** | Full -- self-hosted, all data on our infrastructure | Microsoft-hosted; code on GitHub | SaaS or self-hosted option | Full (but data on contractor device) |
| **AI integration** | Centralized proxy with per-user budgets, behavior enforcement, audit | Copilot bundled (separate billing) | BYO AI extensions | Ad hoc; no governance |
| **AI cost control** | Hard per-user budget caps, model restrictions, usage analytics | Per-seat Copilot pricing | None built-in | None |
| **AI behavior enforcement** | Server-side tamper-proof enforcement hook (3 levels) | None | None | None |
| **SSO** | OIDC via Authentik; Azure AD/Okta federation ready | GitHub Enterprise SSO | SSO via Gitpod Enterprise | Corporate VPN + AD |
| **Audit trail** | Full: workspace lifecycle + AI usage + Git operations | GitHub audit log (limited AI) | Workspace logs only | Fragmented across systems |
| **Customization** | Full control: templates, extensions, network, tooling | Limited to devcontainer spec | Moderate | Full (unmanaged) |
| **Offline access** | Not supported (browser-required) | Not supported | Not supported | Full offline access |
| **Data residency** | Choose: on-prem or any AWS region | Microsoft regions | EU or US | On contractor device |
| **Contractor offboarding** | Delete workspace + revoke SSO = instant, complete | Remove from GitHub org | Remove from Gitpod org | Retrieve laptop + rotate all creds |
| **Cost (50 users)** | ~$1,500/mo infra + AI usage | ~$1,950/mo ($39/user) | ~$2,000/mo ($40/user) | Laptop cost + VPN + support burden |

> **Key Takeaway:** This platform uniquely combines full data control, centralized AI governance with tamper-proof enforcement, and per-user budget caps. Commercial alternatives offer convenience but lack the AI cost control and behavior enforcement capabilities.

---

## 10. Demo Flow (5 minutes)

A suggested sequence for a live demonstration:

| Step | What to Show | What It Demonstrates |
|------|-------------|---------------------|
| **1** | Open Coder dashboard at `https://host.docker.internal:7443`. Show workspace list. | Platform entry point; HTTPS secure context |
| **2** | Create a new workspace. Select "AI Behavior Mode: design-first" template parameter. | Self-service provisioning; configurable enforcement |
| **3** | Wait for workspace to build (~30s). Show build log -- key provisioner auto-generates AI key. | Automated key provisioning; no manual API key setup |
| **4** | Click "code-server" to open VS Code in the browser. Show that VS Code Desktop and SSH buttons are absent. | Browser-only access; connection method lockdown |
| **5** | Open Roo Code sidebar. Send a message: "Write a REST API for user management." Observe that the AI responds with a design proposal first, not code. | Design-first enforcement in action |
| **6** | Open terminal. Run `opencode` and send a message to show the terminal AI agent working. | Dual AI tools (GUI + CLI), same LiteLLM backend |
| **7** | Open LiteLLM admin UI (`http://localhost:4000/ui`). Show the virtual key created for this workspace, its budget, rate limit, and usage. | Per-user budget caps; usage visibility |
| **8** | Show the platform admin dashboard (`http://localhost:5050`). Highlight AI spend overview across all users. | Centralized cost visibility |

**Talking points during demo:**
- "Notice the contractor never sees an API key -- it was auto-provisioned."
- "The design-first enforcement is server-side -- the contractor cannot disable it."
- "When this contractor's engagement ends, we delete the workspace and the virtual key is immediately revoked."

---

## 11. Q&A Topics

### "What happens when a contractor's engagement ends?"

Delete their Coder workspace (removes the container and all local state), revoke their Authentik SSO account, and their LiteLLM virtual key is immediately invalidated. No laptop retrieval, no credential rotation, no multi-system cleanup. The entire offboarding is three actions and takes under a minute.

### "Can we restrict which models contractors use?"

Yes. Virtual keys carry a `models` allowlist. A workspace key can be scoped to Haiku-only (cheapest), Sonnet + Haiku (standard), or all models. CI pipeline keys are typically Haiku-only. This is enforced at the LiteLLM proxy level -- if a restricted key tries to call Opus, the request is rejected.

### "How do we handle data sovereignty?"

All infrastructure is self-hosted (PoC: Docker Compose on your own hardware; production: your AWS account in your chosen region). AI requests route through AWS Bedrock, which processes data in the region you select -- no data leaves your chosen jurisdiction. Anthropic direct API is an optional fallback with its own data handling terms.

### "What's the migration path from the PoC?"

The production plan replaces Docker Compose components with AWS managed services (RDS for PostgreSQL, ElastiCache for Redis, EFS + S3 for storage, ECS Fargate for compute). No application-level changes are needed. Terraform modules are already drafted for all major components. Estimated timeline: 8 weeks. The PoC continues to run in parallel during migration for development and testing.

### "What about offline/disconnected scenarios?"

This platform requires a browser and network connectivity -- there is no offline mode. This is a deliberate security decision: keeping all code and AI interactions server-side prevents data from persisting on contractor devices. For roles that genuinely require offline development, the traditional laptop model remains appropriate. The two approaches can coexist.

### "How does this compare to just using GitHub Codespaces?"

Codespaces provides a similar browser-based IDE experience but with Microsoft-hosted infrastructure. Key differences: we retain full data control (self-hosted), we have centralized AI cost governance with hard per-user budget caps (Codespaces has Copilot but no cost controls), and we have a tamper-proof enforcement layer for AI behavior that no commercial alternative offers. Codespaces is simpler to operate; this platform offers more control.

### "What if a contractor needs access to internal services?"

Workspace containers share a Docker network with internal services (databases, Git, etc.) in the PoC. In production, ECS security groups control which services workspaces can reach. The platform supports fine-grained network policies: workspaces can access Gitea (Git), LiteLLM (AI), and designated internal databases, while being blocked from reaching other workspaces or production systems.

### "What's the cost per contractor?"

At the small deployment scale (50 users, 20 concurrent), total infrastructure + AI costs approximately $1,500/month, or ~$30/user/month. The largest variable is AI usage, which is controlled by per-user budget caps. Infrastructure costs scale sub-linearly: the platform services are shared overhead, and workspace compute scales with concurrency (not total users).

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-06 | Platform Team | Initial tech day presentation document |
