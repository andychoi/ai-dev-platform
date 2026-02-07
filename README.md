# Dev Platform

**A secure, browser-based development environment with AI-powered coding assistance.**

Dev Platform provides a complete infrastructure for secure contractor/remote developer access through browser-based IDEs, with built-in AI assistance via a multi-provider gateway.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Objectives

### 1. Enhanced Security & Compliance
- **Zero-trust access** - No direct shell, RDP, or database access from untrusted devices
- **Workspace isolation** - Containerized environments with defined boundaries
- **Centralized control** - Code stays on company infrastructure, not local devices
- **SSO integration** - Enterprise identity via OIDC (Authentik, Azure AD, Okta)

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
- **AI Gateway** - Centralized proxy for Claude, Bedrock with rate limiting & audit
- **Future-ready** - Infrastructure for autonomous coding agents (Claude Code, Cursor)

## Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         BROWSER                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │  Coder UI   │  │   VS Code   │  │  Drone CI   │             │
│  │  :7080      │  │  (WebIDE)   │  │   :8080     │             │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘             │
└─────────┼────────────────┼────────────────┼─────────────────────┘
          │                │                │
          ▼                ▼                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      DOCKER NETWORK                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │    Coder    │  │ AI Gateway  │  │   Gitea     │             │
│  │  Workspaces │  │   :8090     │  │   :3000     │             │
│  └─────────────┘  └──────┬──────┘  └─────────────┘             │
│                          │                                       │
└──────────────────────────┼───────────────────────────────────────┘
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
   │  Anthropic  │  │ AWS Bedrock │  │   Google    │
   │   Claude    │  │             │  │   Gemini    │
   └─────────────┘  └─────────────┘  └─────────────┘
```

## Features

### 🖥️ Coder WebIDE
Secure, browser-based development environments:
- **Zero Trust**: No direct network access from untrusted devices
- **VS Code in Browser**: Full IDE with extension support
- **Workspace Isolation**: Per-user sandboxed environments
- **Auto-Shutdown**: Idle resource management

### 🤖 Multi-Provider AI Gateway
Secure, audited AI access:

| Provider | Status | Models |
|----------|--------|--------|
| Anthropic | ✅ Active | Claude 3/3.5 (Opus, Sonnet, Haiku) |
| AWS Bedrock | ✅ Active | Claude, Titan |
| Google Gemini | 🔜 Planned | Gemini Pro |

- **No Credential Exposure**: API keys stored in gateway only
- **Rate Limiting**: Per-user request controls
- **Audit Logging**: Full request/response tracking
- **OpenAI-Compatible**: Unified `/v1/chat/completions` endpoint

### 🔧 Self-Hosted Git & CI
- **Gitea**: Lightweight Git server with web UI
- **Drone CI**: Container-native continuous integration
- **Access Control**: Fine-grained repository permissions

## Quick Start

### Prerequisites
- Docker & Docker Compose
- API keys for AI providers (optional)

### Setup

```bash
# Clone the repository
git clone https://github.com/andychoi/dev-platform.git
cd dev-platform/coder-poc

# Copy and configure environment
cp .env.example .env
# Edit .env with your API keys and settings

# Start the platform
docker compose up -d

# Run initial setup
./scripts/setup.sh
```

### Access Services

| Service | URL | Description |
|---------|-----|-------------|
| Coder | http://host.docker.internal:7080 | WebIDE management (use this URL for OIDC) |
| AI Gateway | http://localhost:8090 | AI proxy endpoint |
| Gitea | http://localhost:3000 | Git server |
| Drone CI | http://localhost:8080 | CI/CD pipelines |
| Authentik | http://localhost:9000 | SSO/Identity Provider |
| MinIO | http://localhost:9001 | S3-compatible storage |

## Documentation

| Document | Description |
|----------|-------------|
| [Documentation Index](./docs/README.md) | Full documentation index |
| [PoC Planning](./docs/poc-planning/README.md) | Original requirements, design, and implementation planning |
| [Platform Docs](./shared/docs/) | AI integration, security, keys, guardrails, FAQ |
| [Operations](./coder-poc/docs/runbook.md) | Runbook and troubleshooting |
| [Production Plan](./aws-production/PRODUCTION-PLAN.md) | AWS production migration |

## Project Structure

```
dev-platform/
├── coder-poc/              # PoC deployment (Docker Compose)
│   ├── templates/          # Coder workspace templates
│   ├── scripts/            # Setup and management scripts
│   ├── litellm/            # LiteLLM AI proxy config and hooks
│   ├── egress/             # Network egress exception files
│   ├── certs/              # TLS certificates
│   ├── gitea/              # Git server configuration
│   ├── docs/               # PoC operations (runbook, infra, SSO)
│   └── docker-compose.yml  # Full stack definition
├── shared/                 # Shared code and docs
│   ├── docs/               # Platform-wide documentation
│   ├── litellm-hooks/      # LiteLLM enforcement + guardrails hooks
│   ├── key-provisioner/    # AI key auto-provisioning service
│   └── scripts/            # Shared scripts
├── aws-production/         # AWS production deployment planning
├── docs/                   # Documentation index + planning
│   └── poc-planning/       # Original requirements, design, implementation docs
└── .claude/skills/         # Claude AI assistant skills
```

## Configuration

### Environment Variables

```bash
# AI Providers
ANTHROPIC_API_KEY=sk-ant-...
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=us-east-1

# Services
CODER_ACCESS_URL=http://host.docker.internal:7080
GITEA_DOMAIN=localhost:3000
```

### AI Gateway Usage

```bash
# Direct API call
curl -X POST http://localhost:8090/v1/claude/v1/messages \
  -H "Content-Type: application/json" \
  -H "X-Workspace-ID: my-workspace" \
  -d '{
    "model": "claude-3-sonnet-20240229",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 1024
  }'

# OpenAI-compatible endpoint
curl -X POST http://localhost:8090/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-3-sonnet-20240229",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

## Contributing

Contributions welcome! Please read the documentation in `docs/` before submitting PRs.

## License

MIT

