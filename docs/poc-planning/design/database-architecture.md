# Database Architecture for Dev Platform

## Overview

This document defines the database architecture for the Dev Platform, covering both PoC and production deployments.

---

## Current PoC Architecture

### Separate Databases (Current)

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         POC DATABASE LAYOUT                               │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐             │
│  │   postgres     │  │  authentik-db  │  │    testdb      │             │
│  │   (Coder)      │  │    (RBAC)      │  │    (App)       │             │
│  ├────────────────┤  ├────────────────┤  ├────────────────┤             │
│  │ • workspaces   │  │ • users        │  │ • app.users    │             │
│  │ • templates    │  │ • groups       │  │ • app.projects │             │
│  │ • provisioners │  │ • roles        │  │ • app.tasks    │             │
│  │ • audit_logs   │  │ • permissions  │  │                │             │
│  │ • api_keys     │  │ • flows        │  │                │             │
│  │ • licenses     │  │ • audit_events │  │                │             │
│  └────────────────┘  └────────────────┘  └────────────────┘             │
│         ↑                   ↑                   ↑                        │
│      Coder              Authentik          Workspaces                    │
│                                                                           │
│  Issues:                                                                  │
│  ✗ Fragmented audit logs                                                 │
│  ✗ No unified reporting                                                  │
│  ✗ Multiple backup strategies                                            │
│  ✗ No cross-service analytics                                            │
│                                                                           │
└──────────────────────────────────────────────────────────────────────────┘
```

### PoC Data Flows

| Service | Database | Data Stored |
|---------|----------|-------------|
| Coder | postgres | Workspaces, templates, provisioners, audit |
| Authentik | authentik-db | Users, groups, roles, SSO config, flows |
| AI Gateway | (none - logs to file) | Request/response logs |
| Gogs | SQLite (internal) | Repos, users, permissions |
| Drone | SQLite (internal) | Builds, pipelines |
| Test DB | testdb | Sample application data |

---

## Production Architecture Options

### Option A: Consolidated PostgreSQL Cluster

Single PostgreSQL cluster with multiple databases for all services.

```
┌──────────────────────────────────────────────────────────────────────────┐
│                    OPTION A: CONSOLIDATED CLUSTER                         │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │                    PostgreSQL Cluster (HA)                          │  │
│  │                     Primary + Replica(s)                            │  │
│  ├────────────────────────────────────────────────────────────────────┤  │
│  │                                                                     │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐│  │
│  │  │  coder   │ │authentik │ │ platform │ │  audit   │ │ analytics││  │
│  │  │   db     │ │   db     │ │   db     │ │   db     │ │   db     ││  │
│  │  ├──────────┤ ├──────────┤ ├──────────┤ ├──────────┤ ├──────────┤│  │
│  │  │workspaces│ │  users   │ │ projects │ │  logs    │ │ metrics  ││  │
│  │  │templates │ │  groups  │ │  config  │ │  events  │ │ reports  ││  │
│  │  │provisners│ │  roles   │ │ settings │ │  traces  │ │ dashbords││  │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘│  │
│  │                                                                     │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                    │                                      │
│                    ┌───────────────┼───────────────┐                     │
│                    ▼               ▼               ▼                     │
│              ┌──────────┐   ┌──────────┐   ┌──────────┐                 │
│              │  Coder   │   │Authentik │   │ Platform │                 │
│              │          │   │          │   │   API    │                 │
│              └──────────┘   └──────────┘   └──────────┘                 │
│                                                                           │
│  Benefits:                              Drawbacks:                        │
│  ✓ Single backup strategy              ✗ Single point of failure         │
│  ✓ Unified connection management       ✗ Resource contention             │
│  ✓ Cross-database queries              ✗ Blast radius on issues          │
│  ✓ Simpler operations                  ✗ Harder to scale individually    │
│                                                                           │
└──────────────────────────────────────────────────────────────────────────┘
```

### Option B: Federated Databases with Central Audit (Recommended)

Separate databases per service with centralized audit/analytics database.

```
┌──────────────────────────────────────────────────────────────────────────┐
│              OPTION B: FEDERATED WITH CENTRAL AUDIT (Recommended)         │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐ │
│  │                     SERVICE DATABASES (Isolated)                     │ │
│  │                                                                      │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │ │
│  │  │    Coder     │  │  Authentik   │  │    Gogs      │              │ │
│  │  │  PostgreSQL  │  │  PostgreSQL  │  │  PostgreSQL  │              │ │
│  │  │              │  │              │  │              │              │ │
│  │  │ • workspaces │  │ • users      │  │ • repos      │              │ │
│  │  │ • templates  │  │ • groups     │  │ • orgs       │              │ │
│  │  │ • audit      │  │ • roles      │  │ • webhooks   │              │ │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘              │ │
│  │         │                 │                 │                       │ │
│  └─────────┼─────────────────┼─────────────────┼───────────────────────┘ │
│            │                 │                 │                         │
│            │    Event Stream │(Kafka/NATS)     │                         │
│            └─────────────────┼─────────────────┘                         │
│                              ▼                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐ │
│  │                    CENTRAL PLATFORM DATABASE                         │ │
│  │                                                                      │ │
│  │  ┌──────────────────────────────────────────────────────────────┐  │ │
│  │  │                    platform_db (PostgreSQL)                   │  │ │
│  │  ├──────────────────────────────────────────────────────────────┤  │ │
│  │  │                                                               │  │ │
│  │  │  audit_logs          │  platform_config   │  analytics       │  │ │
│  │  │  ─────────────       │  ────────────────  │  ──────────      │  │ │
│  │  │  • event_id          │  • projects        │  • usage_metrics │  │ │
│  │  │  • timestamp         │  • environments    │  • cost_data     │  │ │
│  │  │  • service           │  • integrations    │  • reports       │  │ │
│  │  │  • user_id           │  • feature_flags   │  • dashboards    │  │ │
│  │  │  • action            │                    │                  │  │ │
│  │  │  • resource          │  user_directory    │  access_reviews  │  │ │
│  │  │  • details (jsonb)   │  ────────────────  │  ──────────────  │  │ │
│  │  │  • source_ip         │  • user_id (ref)   │  • review_id     │  │ │
│  │  │  • session_id        │  • display_name    │  • user_id       │  │ │
│  │  │                      │  • department      │  • access_level  │  │ │
│  │  │                      │  • manager         │  • expires_at    │  │ │
│  │  │                      │  • contractor_end  │  • approved_by   │  │ │
│  │  │                      │                    │                  │  │ │
│  │  └──────────────────────────────────────────────────────────────┘  │ │
│  │                                                                      │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                                                                           │
│  Benefits:                                                                │
│  ✓ Service isolation (failure containment)                               │
│  ✓ Independent scaling                                                   │
│  ✓ Unified audit & compliance                                            │
│  ✓ Cross-service analytics                                               │
│  ✓ Clean separation of concerns                                          │
│                                                                           │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Recommended Schema: Central Platform Database

### Core Tables

```sql
-- =============================================================================
-- PLATFORM DATABASE SCHEMA
-- Central database for audit, analytics, and platform configuration
-- =============================================================================

-- Audit Logs (all services write here)
CREATE TABLE audit_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    timestamp       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    service         VARCHAR(50) NOT NULL,  -- 'coder', 'authentik', 'ai-gateway', 'gogs'
    event_type      VARCHAR(100) NOT NULL, -- 'workspace.created', 'user.login', etc.
    user_id         VARCHAR(255),          -- User identifier (email or ID)
    user_email      VARCHAR(255),
    resource_type   VARCHAR(100),          -- 'workspace', 'template', 'repository'
    resource_id     VARCHAR(255),
    action          VARCHAR(50) NOT NULL,  -- 'create', 'read', 'update', 'delete'
    outcome         VARCHAR(20) NOT NULL,  -- 'success', 'failure', 'denied'
    source_ip       INET,
    user_agent      TEXT,
    session_id      VARCHAR(255),
    details         JSONB,                 -- Service-specific details
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_logs_timestamp ON audit_logs(timestamp DESC);
CREATE INDEX idx_audit_logs_user ON audit_logs(user_id, timestamp DESC);
CREATE INDEX idx_audit_logs_service ON audit_logs(service, timestamp DESC);
CREATE INDEX idx_audit_logs_event ON audit_logs(event_type, timestamp DESC);

-- User Directory (aggregated view from Authentik)
CREATE TABLE user_directory (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    authentik_id    VARCHAR(255) UNIQUE NOT NULL,
    email           VARCHAR(255) UNIQUE NOT NULL,
    display_name    VARCHAR(255),
    user_type       VARCHAR(50) NOT NULL,  -- 'employee', 'contractor', 'service'
    department      VARCHAR(100),
    manager_email   VARCHAR(255),
    status          VARCHAR(20) NOT NULL DEFAULT 'active',  -- 'active', 'suspended', 'offboarded'
    contractor_company  VARCHAR(255),
    contractor_start    DATE,
    contractor_end      DATE,
    last_login      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_user_directory_email ON user_directory(email);
CREATE INDEX idx_user_directory_type ON user_directory(user_type);
CREATE INDEX idx_user_directory_status ON user_directory(status);

-- Access Assignments (what users can access)
CREATE TABLE access_assignments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES user_directory(id),
    resource_type   VARCHAR(50) NOT NULL,  -- 'project', 'template', 'repository'
    resource_id     VARCHAR(255) NOT NULL,
    access_level    VARCHAR(50) NOT NULL,  -- 'read', 'write', 'admin'
    granted_by      UUID REFERENCES user_directory(id),
    granted_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at      TIMESTAMPTZ,
    revoked_at      TIMESTAMPTZ,
    revoked_by      UUID REFERENCES user_directory(id),
    justification   TEXT,
    UNIQUE(user_id, resource_type, resource_id)
);

CREATE INDEX idx_access_user ON access_assignments(user_id);
CREATE INDEX idx_access_resource ON access_assignments(resource_type, resource_id);
CREATE INDEX idx_access_expires ON access_assignments(expires_at) WHERE expires_at IS NOT NULL;

-- Access Requests (approval workflow)
CREATE TABLE access_requests (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_id    UUID REFERENCES user_directory(id),
    resource_type   VARCHAR(50) NOT NULL,
    resource_id     VARCHAR(255) NOT NULL,
    access_level    VARCHAR(50) NOT NULL,
    justification   TEXT NOT NULL,
    duration_days   INTEGER,
    status          VARCHAR(20) NOT NULL DEFAULT 'pending',  -- 'pending', 'approved', 'rejected', 'expired'
    approver_id     UUID REFERENCES user_directory(id),
    approved_at     TIMESTAMPTZ,
    rejection_reason TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_requests_status ON access_requests(status);
CREATE INDEX idx_requests_requester ON access_requests(requester_id);

-- Projects (logical grouping)
CREATE TABLE projects (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(255) NOT NULL UNIQUE,
    description     TEXT,
    owner_id        UUID REFERENCES user_directory(id),
    status          VARCHAR(20) NOT NULL DEFAULT 'active',
    coder_template  VARCHAR(255),          -- Associated Coder template
    gogs_org        VARCHAR(255),          -- Associated Gogs organization
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- AI Usage Tracking
CREATE TABLE ai_usage (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    timestamp       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    user_id         UUID REFERENCES user_directory(id),
    workspace_id    VARCHAR(255),
    provider        VARCHAR(50) NOT NULL,  -- 'anthropic', 'bedrock', 'gemini'
    model           VARCHAR(100) NOT NULL,
    tokens_input    INTEGER NOT NULL,
    tokens_output   INTEGER NOT NULL,
    latency_ms      INTEGER,
    status          VARCHAR(20) NOT NULL,
    cost_usd        DECIMAL(10, 6)
);

CREATE INDEX idx_ai_usage_user ON ai_usage(user_id, timestamp DESC);
CREATE INDEX idx_ai_usage_timestamp ON ai_usage(timestamp DESC);

-- Usage Metrics (aggregated)
CREATE TABLE usage_metrics (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    date            DATE NOT NULL,
    metric_type     VARCHAR(50) NOT NULL,  -- 'workspace_hours', 'ai_tokens', 'git_commits'
    user_id         UUID REFERENCES user_directory(id),
    project_id      UUID REFERENCES projects(id),
    value           DECIMAL(20, 4) NOT NULL,
    unit            VARCHAR(20) NOT NULL,
    UNIQUE(date, metric_type, user_id, project_id)
);

CREATE INDEX idx_metrics_date ON usage_metrics(date DESC);
CREATE INDEX idx_metrics_user ON usage_metrics(user_id, date DESC);
```

### Views for Reporting

```sql
-- Active contractors with their access
CREATE VIEW v_contractor_access AS
SELECT
    u.email,
    u.display_name,
    u.contractor_company,
    u.contractor_end,
    p.name as project_name,
    aa.access_level,
    aa.granted_at,
    aa.expires_at
FROM user_directory u
JOIN access_assignments aa ON u.id = aa.user_id
JOIN projects p ON aa.resource_type = 'project' AND aa.resource_id = p.id::text
WHERE u.user_type = 'contractor'
  AND u.status = 'active'
  AND aa.revoked_at IS NULL
  AND (aa.expires_at IS NULL OR aa.expires_at > NOW());

-- Audit summary by user
CREATE VIEW v_user_activity_summary AS
SELECT
    user_email,
    DATE(timestamp) as activity_date,
    COUNT(*) as total_events,
    COUNT(DISTINCT service) as services_used,
    COUNT(*) FILTER (WHERE outcome = 'failure') as failures
FROM audit_logs
WHERE timestamp > NOW() - INTERVAL '30 days'
GROUP BY user_email, DATE(timestamp);

-- AI cost by user/project
CREATE VIEW v_ai_cost_summary AS
SELECT
    u.email,
    p.name as project_name,
    DATE_TRUNC('month', ai.timestamp) as month,
    SUM(ai.tokens_input + ai.tokens_output) as total_tokens,
    SUM(ai.cost_usd) as total_cost
FROM ai_usage ai
JOIN user_directory u ON ai.user_id = u.id
LEFT JOIN projects p ON ai.workspace_id LIKE p.name || '%'
GROUP BY u.email, p.name, DATE_TRUNC('month', ai.timestamp);
```

---

## Implementation Plan

### Phase 1: Add Platform Database to PoC

```yaml
# Add to docker-compose.yml
platform-db:
  image: postgres:15-alpine
  container_name: platform-db
  environment:
    POSTGRES_DB: platform
    POSTGRES_USER: platform
    POSTGRES_PASSWORD: ${PLATFORM_DB_PASSWORD:-platform}
  volumes:
    - platform_db:/var/lib/postgresql/data
    - ./platform-db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U platform -d platform"]
    interval: 5s
    timeout: 5s
    retries: 5
  networks:
    - coder-network
```

### Phase 2: Event Collection

Services emit events to central platform database:

```python
# Example: AI Gateway audit logging
import httpx
from datetime import datetime

async def log_audit_event(
    service: str,
    event_type: str,
    user_id: str,
    action: str,
    outcome: str,
    details: dict
):
    event = {
        "timestamp": datetime.utcnow().isoformat(),
        "service": service,
        "event_type": event_type,
        "user_id": user_id,
        "action": action,
        "outcome": outcome,
        "details": details
    }

    # Option 1: Direct DB insert
    # Option 2: Message queue (Kafka/NATS)
    # Option 3: HTTP API to platform service

    async with httpx.AsyncClient() as client:
        await client.post(
            "http://platform-api:8000/api/v1/audit",
            json=event
        )
```

### Phase 3: Platform API Service

Simple FastAPI service for platform operations:

```
platform-api/
├── main.py           # FastAPI application
├── models.py         # SQLAlchemy models
├── routers/
│   ├── audit.py      # Audit log endpoints
│   ├── users.py      # User directory sync
│   ├── access.py     # Access management
│   └── reports.py    # Reporting endpoints
└── Dockerfile
```

---

## Summary

| Aspect | PoC (Current) | Production (Recommended) |
|--------|---------------|--------------------------|
| Service DBs | Separate per service | Separate per service |
| Audit Logs | Fragmented | Centralized platform_db |
| User Directory | Authentik only | Synced to platform_db |
| Access Tracking | Per-service | Centralized |
| Analytics | None | platform_db + views |
| Reporting | Manual | Automated dashboards |

**Recommendation:** Keep service databases separate (isolation, independent scaling) but add a central `platform_db` for unified audit, user directory, and analytics.

---

## Document Control

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-04 | Dev Platform Team | Initial draft |
