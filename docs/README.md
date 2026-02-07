# Documentation Index

This directory contains comprehensive documentation for the Coder WebIDE Development Platform.

## Documentation Structure

| Folder | Purpose | Audience |
|--------|---------|----------|
| `docs/poc-planning/` | Original planning docs (requirements, design, implementation) | Architects, Project Managers |
| `shared/docs/` | Platform-wide operational documentation (AI, security, guardrails, keys) | All Teams |
| `coder-poc/docs/` | PoC-specific operations (runbook, infrastructure, SSO) | Developers, Operators |
| `aws-production/` | Production migration planning | Platform Team |

## Quick Links

### Getting Started
- [Main README](../README.md) - Project overview and quick start
- [CLAUDE.md](../CLAUDE.md) - AI assistant operating context
- [Runbook](../coder-poc/docs/runbook.md) - Operations and troubleshooting
- [FAQ](../shared/docs/FAQ.md) - End-user frequently asked questions

### PoC Planning (`docs/poc-planning/`)

Original project development lifecycle documents. See [poc-planning/README.md](poc-planning/README.md) for full index.

| Phase | Key Document |
|-------|-------------|
| Requirements | [Coder WebIDE Requirements](poc-planning/requirements/coder-webide-integration.md) |
| Design | [AI Gateway Architecture](poc-planning/design/coder-webide-ai-gateway.md) |
| Planning | [Implementation Roadmap](poc-planning/planning/coder-webide-integration.md) |
| Implementation | [Implementation Guide](poc-planning/implementation/coder-webide-implementation-guide.md) |
| Testing | [Access Control Tests](poc-planning/testing/coder-webide-access-control-tests.md) |

### Platform Documentation (`shared/docs/`)

| Document | Description |
|----------|-------------|
| [AI.md](../shared/docs/AI.md) | AI integration and enforcement architecture |
| [SECURITY.md](../shared/docs/SECURITY.md) | Security architecture and controls |
| [RBAC-ACCESS-CONTROL.md](../shared/docs/RBAC-ACCESS-CONTROL.md) | Roles, permissions, and service access matrix |
| [WEB-TERMINAL-SECURITY.md](../shared/docs/WEB-TERMINAL-SECURITY.md) | Terminal hardening (egress, sudo, audit) |
| [GUARDRAILS.md](../shared/docs/GUARDRAILS.md) | Content guardrails (PII/financial/secret detection) |
| [KEY-MANAGEMENT.md](../shared/docs/KEY-MANAGEMENT.md) | Virtual key taxonomy and management |
| [ROO-CODE-LITELLM.md](../shared/docs/ROO-CODE-LITELLM.md) | Roo Code + LiteLLM integration |
| [OPENCODE.md](../shared/docs/OPENCODE.md) | OpenCode CLI setup |
| [DATABASE.md](../shared/docs/DATABASE.md) | Developer database management |
| [MINIO-FAQ.md](../shared/docs/MINIO-FAQ.md) | MinIO/S3 usage patterns |
| [FAQ.md](../shared/docs/FAQ.md) | End-user frequently asked questions |
| [AI-GATEWAY-BENEFITS.md](../shared/docs/AI-GATEWAY-BENEFITS.md) | AI gateway benefits and analytics |
| [ENTERPRISE-FEATURE-REVIEW.md](../shared/docs/ENTERPRISE-FEATURE-REVIEW.md) | Enterprise IT feature assessment |
| [POC-SECURITY-REVIEW.md](../shared/docs/POC-SECURITY-REVIEW.md) | Security audit findings and remediation status |

### Operational Documentation (`coder-poc/docs/`)

| Document | Description |
|----------|-------------|
| [runbook.md](../coder-poc/docs/runbook.md) | Operations guide and troubleshooting |
| [ADMIN-HOWTO.md](../coder-poc/docs/ADMIN-HOWTO.md) | Admin procedures |
| [AUTHENTIK-SSO.md](../coder-poc/docs/AUTHENTIK-SSO.md) | SSO configuration with Authentik |
| [INFRA.md](../coder-poc/docs/INFRA.md) | Infrastructure and service details |
| [PRODUCTION.md](../coder-poc/docs/PRODUCTION.md) | Production readiness |
| [testing-validation.md](../coder-poc/docs/testing-validation.md) | Testing procedures |

### Presentation
- [TechDay Presentation](Coder_WebIDE_TechDay.md) - CTO/leadership presentation notes

### Production Planning
- [Production Plan](../aws-production/PRODUCTION-PLAN.md) - AWS production migration plan

## Key Differences: PoC vs Production

| Aspect | PoC Implementation | Production Target |
|--------|-------------------|-------------------|
| Orchestration | Docker Compose | ECS Fargate / Kubernetes |
| Identity | Authentik (OIDC) | Authentik or enterprise IdP |
| Secrets | Environment variables | AWS Secrets Manager |
| TLS | Self-signed cert (port 7443) | CA-signed certs |
| Network | Docker bridge + iptables egress | K8s NetworkPolicy / VPC |

## Update History

| Date | Description |
|------|-------------|
| 2026-02-07 | Reorganized: renamed docs/ai/ to docs/poc-planning/, added new docs to index, fixed TLS status |
| 2026-02-05 | Documentation refresh - aligned with current codebase |
| 2026-02-04 | Initial comprehensive documentation |
