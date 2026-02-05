# Documentation Index

This directory contains comprehensive documentation for the Coder WebIDE Development Platform.

## Documentation Structure

| Folder | Purpose | Audience |
|--------|---------|----------|
| `docs/ai/` | Strategic documentation (requirements, design, planning) | Architects, Project Managers |
| `coder-poc/docs/` | Operational documentation (how-to guides, troubleshooting) | Developers, Operators |
| `coder-production/` | Production migration planning | Platform Team |

## Quick Links

### Getting Started
- [Main README](../README.md) - Project overview and quick start
- [CLAUDE.md](../CLAUDE.md) - AI assistant operating context
- [Troubleshooting](../troubleshooting.md) - Common issues and fixes
- [Runbook](../runbook.md) - Operational procedures

### Strategic Documentation (`docs/ai/`)

#### Requirements
- [Coder WebIDE Requirements](ai/requirements/coder-webide-integration.md) - Functional & non-functional requirements
- [Limitations & Remediation](ai/requirements/coder-webide-limitations-remediation.md) - Developer tool limitations
- [Security Assessment](ai/requirements/security-assessment-dev-platform.md) - Security comparison

#### Design
- [System Architecture](ai/design/coder-webide-integration.md) - Complete architecture design
- [AI Gateway Design](ai/design/coder-webide-ai-gateway.md) - AI integration architecture
- [Database Architecture](ai/design/database-architecture.md) - Database design decisions
- [RBAC Comparison](ai/design/rbac-solutions-comparison.md) - Identity provider evaluation

#### Planning
- [Implementation Plan](ai/planning/coder-webide-integration.md) - Phased rollout plan

#### Implementation
- [Implementation Guide](ai/implementation/coder-webide-implementation-guide.md) - Complete implementation guide

#### Testing
- [Access Control Tests](ai/testing/coder-webide-access-control-tests.md) - Test scenarios

### Operational Documentation (`coder-poc/docs/`)

| Document | Description |
|----------|-------------|
| [AI.md](../coder-poc/docs/AI.md) | AI integration and Continue extension setup |
| [AUTHENTIK-SSO.md](../coder-poc/docs/AUTHENTIK-SSO.md) | SSO configuration with Authentik |
| [DATABASE.md](../coder-poc/docs/DATABASE.md) | Developer database management |
| [FAQ.md](../coder-poc/docs/FAQ.md) | End-user frequently asked questions |
| [INFRA.md](../coder-poc/docs/INFRA.md) | Infrastructure and service details |
| [SECURITY.md](../coder-poc/docs/SECURITY.md) | Security guidelines |
| [POC-SECURITY-REVIEW.md](../coder-poc/docs/POC-SECURITY-REVIEW.md) | Security review findings |
| [PRODUCTION.md](../coder-poc/docs/PRODUCTION.md) | Production readiness |
| [testing-validation.md](../coder-poc/docs/testing-validation.md) | Testing procedures |

### Production Planning

- [Production Plan](../coder-production/PRODUCTION-PLAN.md) - 6-week production migration plan (68 security issues)

## Document Conventions

- **PoC** = Proof of Concept (current Docker-based implementation)
- **Production** = Target Kubernetes deployment
- Dates in document headers indicate last update

## Key Differences: PoC vs Production

| Aspect | PoC Implementation | Production Target |
|--------|-------------------|-------------------|
| Orchestration | Docker Compose | Kubernetes |
| Identity | Authentik | Authentik or enterprise IdP |
| Secrets | Environment variables | HashiCorp Vault |
| TLS | Disabled | Required (TLS 1.3) |
| Network | Docker bridge | K8s NetworkPolicy |

## Update History

| Date | Description |
|------|-------------|
| 2026-02-05 | Documentation refresh - aligned with current codebase |
| 2026-02-04 | Initial comprehensive documentation |
