# Dev Platform

**A secure, browser-based development environment with AI-powered coding assistance.**

Dev Platform provides complete infrastructure for secure contractor/remote developer access through browser-based IDEs, with built-in AI assistance via a multi-provider gateway.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Objectives

### 1. Enhanced Security & Compliance
- **Zero-trust access** - No direct shell, RDP, or database access from untrusted devices
- **Workspace isolation** - Containerized environments with defined boundaries
- **Centralized control** - Code stays on company infrastructure, not local devices
- **SSO integration** - Enterprise identity via OIDC (Authentik for PoC, Azure AD for production)

### 2. Cost Reduction vs Traditional VDI
| Aspect | Traditional VDI | Coder Workspaces |
|--------|-----------------|------------------|
| Resource usage | Full VM per user | Lightweight containers |
| Startup time | 5-15 minutes | 30-60 seconds |
| License costs | Windows + VDI | Open source core |
| Scaling | Manual provisioning | Auto-scaling |

**Expected savings:** 40-60% infrastructure cost reduction vs VDI.

### 3. Fast Developer Onboarding
- **Day-one productivity** - Fully configured environment in minutes
- **Template-based** - Standardized setups eliminate "works on my machine"
- **Self-service** - Developers create workspaces without IT tickets

### 4. AI-Assisted Development Platform
Aligned with [Coder's Enterprise AI Development vision](https://coder.com/blog/coder-enterprise-grade-platform-for-self-hosted-ai-development):
- **AI Workspaces** - Isolated environments for AI agent + developer collaboration
- **Agent Boundaries** - Security model restricting AI access while maintaining productivity
- **AI Gateway** - Centralized proxy (LiteLLM) for Claude with rate limiting, budget caps, and audit
- **Design-First Enforcement** - Server-side AI behavior controls (unrestricted, standard, design-first)
- **Future-ready** - Infrastructure for autonomous coding agents (Claude Code, Roo Code, OpenCode)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         BROWSER                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │  Coder UI   │  │   VS Code   │  │ Admin Panel │             │
│  │  (HTTPS)    │  │  (WebIDE)   │  │   :5050     │             │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘             │
└─────────┼────────────────┼────────────────┼─────────────────────┘
          │ :7443          │                │
          ▼                ▼                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      DOCKER NETWORK                              │
│                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │    Coder    │  │   LiteLLM   │  │   Gitea     │             │
│  │  (TLS)     │  │   (AI GW)   │  │  (Git)      │             │
│  │  :7443     │  │   :4000     │  │  :3000      │             │
│  └──────┬──────┘  └──────┬──────┘  └─────────────┘             │
│         │                │                                       │
│  ┌──────┴──────┐  ┌──────┴──────┐  ┌─────────────┐             │
│  │ Workspaces  │  │    Key      │  │  Authentik  │             │
│  │ (code-srv)  │  │ Provisioner │  │  (SSO/OIDC) │             │
│  │  :8080      │  │  :8100      │  │  :9000      │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
│                                                                  │
└──────────────────────────┼───────────────────────────────────────┘
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
   │  Anthropic  │  │ AWS Bedrock │  │   Google    │
   │   Claude    │  │  (Fallback) │  │  (Planned)  │
   └─────────────┘  └─────────────┘  └─────────────┘
```

## Features

### Coder WebIDE
Secure, browser-based development environments:
- **HTTPS Required**: TLS-enabled access for browser secure context (extension webviews)
- **VS Code in Browser**: Full IDE with extension support (code-server)
- **Workspace Isolation**: Per-user sandboxed containers with egress controls
- **Auto-Shutdown**: Idle resource management

### Multi-Provider AI Gateway (LiteLLM)
Secure, audited AI access through a centralized proxy:

| Provider | Status | Models |
|----------|--------|--------|
| Anthropic | Active | Claude Sonnet 4.5, Haiku 4.5, Opus 4 |
| AWS Bedrock | Active (fallback) | Claude via Bedrock |
| Google Gemini | Planned | Gemini Pro |

- **Key Provisioner**: Auto-provisioned scoped virtual keys per workspace (master key never exposed)
- **Budget Caps**: Per-user, per-workspace spending limits
- **Rate Limiting**: RPM/TPM controls per key scope
- **Enforcement Levels**: Server-side AI behavior control (unrestricted, standard, design-first)
- **OpenAI-Compatible**: Unified `/v1/chat/completions` endpoint

### AI Agents (3 options)
| Agent | Interface | Use Case |
|-------|-----------|----------|
| Roo Code | VS Code sidebar | Interactive development (webview UI) |
| OpenCode | Terminal TUI | Terminal-based AI coding |
| Claude Code | Terminal CLI | Anthropic native CLI (plan-first workflow) |

### Self-Hosted Git & Storage
- **Gitea**: Lightweight Git server with web UI and OIDC
- **MinIO**: S3-compatible object storage with OIDC
- **DevDB**: Per-workspace PostgreSQL databases (auto-provisioned)

## Quick Start

### Prerequisites
- Docker & Docker Compose
- API keys for AI providers (at minimum `ANTHROPIC_API_KEY`)

### Setup

```bash
# Clone the repository
git clone https://github.com/andychoi/dev-platform.git
cd dev-platform/coder-poc

# Copy and configure environment
cp .env.example .env
# Edit .env — set ANTHROPIC_API_KEY at minimum

# Add hosts entry (required for OIDC)
echo "127.0.0.1 host.docker.internal" | sudo tee -a /etc/hosts

# Start the platform
docker compose up -d

# Run initial setup
./scripts/setup.sh
```

### Access Services

| Service | URL | Description |
|---------|-----|-------------|
| **Coder** | `https://host.docker.internal:7443` | WebIDE management (**HTTPS required**) |
| Coder API | `http://localhost:7080` | API for scripts/automation (HTTP) |
| Platform Admin | `http://localhost:5050` | Admin dashboard |
| LiteLLM | `http://localhost:4000/ui` | AI proxy admin |
| Authentik | `http://host.docker.internal:9000` | SSO/Identity Provider |
| Gitea | `http://localhost:3000` | Git server |
| MinIO | `http://localhost:9001` | S3-compatible storage |
| Langfuse | `http://localhost:3100` | AI observability |

> **HTTPS is required for Coder.** `http://host.docker.internal` is NOT a browser secure context — extension webviews (Roo Code, etc.) will render blank without HTTPS. Accept the self-signed certificate warning on first visit.

## Documentation

| Document | Description |
|----------|-------------|
| [Documentation Index](./docs/README.md) | Full documentation index |
| [PoC Planning](./docs/poc-planning/README.md) | Original requirements, design, and implementation |
| **Platform Docs** | |
| [AI Integration](./shared/docs/AI.md) | AI architecture, enforcement, guardrails |
| [Key Management](./shared/docs/KEY-MANAGEMENT.md) | Virtual key provisioning and taxonomy |
| [Security](./shared/docs/SECURITY.md) | Security architecture and controls |
| [Roo Code + LiteLLM](./shared/docs/ROO-CODE-LITELLM.md) | AI agent setup and troubleshooting |
| [Claude Code + LiteLLM](./shared/docs/CLAUDE-CODE-LITELLM.md) | Claude CLI integration |
| [FAQ](./shared/docs/FAQ.md) | End-user questions |
| **Operations** | |
| [Runbook](./coder-poc/docs/runbook.md) | Operations and troubleshooting |
| [Admin How-To](./coder-poc/docs/ADMIN-HOWTO.md) | Admin procedures (templates, TLS, users) |
| [HTTPS Architecture](./coder-poc/docs/HTTPS.md) | TLS setup, Traefik evaluation |
| [SSO Configuration](./coder-poc/docs/AUTHENTIK-SSO.md) | Authentik OIDC setup |
| **Production** | |
| [Production Plan](./aws-production/PRODUCTION-PLAN.md) | AWS production migration |

## Project Structure

```
dev-platform/
├── coder-poc/                  # PoC deployment (Docker Compose)
│   ├── docker-compose.yml      # Full stack (14 services)
│   ├── templates/              # Coder workspace templates
│   │   ├── python-workspace/   # Main template (Terraform)
│   │   └── workspace-base/     # Base Docker image
│   ├── scripts/                # Setup and management scripts
│   ├── litellm/                # LiteLLM proxy config
│   ├── platform-admin/         # Admin dashboard (Flask)
│   ├── certs/                  # TLS certificates (self-signed)
│   ├── egress/                 # Network egress exception files
│   ├── gitea/                  # Git server configuration
│   └── docs/                   # PoC operations docs
│       ├── runbook.md
│       ├── ADMIN-HOWTO.md
│       ├── HTTPS.md            # TLS architecture + Traefik evaluation
│       ├── INFRA.md
│       └── AUTHENTIK-SSO.md
├── shared/                     # Shared code and docs
│   ├── docs/                   # Platform-wide documentation (15 files)
│   ├── litellm-hooks/          # Enforcement + guardrails hooks
│   ├── key-provisioner/        # AI key auto-provisioning service
│   └── scripts/                # Shared test scripts
├── aws-production/             # AWS production deployment
│   ├── PRODUCTION-PLAN.md      # Migration strategy
│   ├── terraform/              # IaC modules (VPC, ECS, RDS, ALB, IAM, S3, etc.)
│   ├── scripts/                # Deployment scripts
│   └── docs/                   # Production-specific docs
├── docs/                       # Documentation index + planning
│   └── poc-planning/           # Original requirements, design docs
└── .claude/skills/             # Claude AI assistant skills (7 domains)
```

## Configuration

### Environment Variables

```bash
# AI Providers (at minimum one required)
ANTHROPIC_API_KEY=sk-ant-...       # Primary — Anthropic direct
AWS_ACCESS_KEY_ID=AKIA...          # Fallback — AWS Bedrock
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=us-east-1

# Coder (HTTPS required)
CODER_ACCESS_URL=https://host.docker.internal:7443
CODER_TLS_ENABLE=true

# LiteLLM
LITELLM_MASTER_KEY=sk-litellm-master-...
PROVISIONER_SECRET=...             # For workspace key auto-provisioning
```

### AI Gateway Usage

```bash
# Test via LiteLLM (OpenAI-compatible endpoint)
curl -X POST http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -d '{
    "model": "claude-sonnet-4-5",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 100
  }'
```

## Contributing

Contributions welcome! Please read the documentation in `docs/` and `CLAUDE.md` before submitting PRs.

## License

MIT
