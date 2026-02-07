# PoC Planning Documents

This directory contains the original planning, design, and requirements documents created during the PoC development phase (January-February 2026). These documents represent the project's development lifecycle from initial requirements through implementation and testing.

**Status:** Historical reference. The PoC has been built and is operational. For current operational documentation, see:
- `shared/docs/` — Platform-wide docs (AI integration, security, keys, guardrails)
- `coder-poc/docs/` — PoC operations (runbook, infrastructure, SSO)
- `aws-production/` — Production deployment planning

## Document Map

### Requirements (What We Need)

| Document | Description | Still Relevant? |
|----------|-------------|-----------------|
| [coder-webide-integration.md](requirements/coder-webide-integration.md) | Functional & non-functional requirements | Core requirements still valid |
| [coder-webide-limitations-remediation.md](requirements/coder-webide-limitations-remediation.md) | Developer tool limitations & remediation strategies | Phase 2/3 roadmap |
| [security-assessment-dev-platform.md](requirements/security-assessment-dev-platform.md) | Security comparison: current VDI vs proposed WebIDE | Policy framework still valid |

### Design (How We'll Build It)

| Document | Description | Status |
|----------|-------------|--------|
| [coder-webide-integration.md](design/coder-webide-integration.md) | Target production architecture (Kubernetes) | Superseded by Docker PoC; reference for K8s migration |
| [coder-webide-ai-gateway.md](design/coder-webide-ai-gateway.md) | AI gateway / LiteLLM architecture | Accurately reflects current implementation |
| [database-architecture.md](design/database-architecture.md) | Database design (federated model) | Phase 3 roadmap; PoC uses simpler model |
| [rbac-solutions-comparison.md](design/rbac-solutions-comparison.md) | Identity provider evaluation (6 options) | Decision made: Authentik selected |
| [coder-webide-limitations-solutions.md](design/coder-webide-limitations-solutions.md) | Concrete solutions for developer tool gaps | Phase 2/3 implementation reference |

### Planning (What We'll Do First)

| Document | Description | Status |
|----------|-------------|--------|
| [coder-webide-integration.md](planning/coder-webide-integration.md) | 4-phase implementation roadmap with timelines | Phase 1 complete; Phases 2-4 remain |

### Implementation (Building It)

| Document | Description | Status |
|----------|-------------|--------|
| [coder-webide-implementation-guide.md](implementation/coder-webide-implementation-guide.md) | PoC implementation guide, architecture, risk register | Current and accurate |

### Testing (Validating It)

| Document | Description | Status |
|----------|-------------|--------|
| [coder-webide-access-control-tests.md](testing/coder-webide-access-control-tests.md) | 15+ access control test scenarios | Partially executed; automation opportunity |
