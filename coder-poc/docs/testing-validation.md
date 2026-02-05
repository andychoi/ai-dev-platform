# Dev Platform Testing & Validation Guide

This document describes test scenarios and validation procedures for the Coder WebIDE Dev Platform.

## Table of Contents

1. [Infrastructure Validation](#1-infrastructure-validation)
2. [User Role Testing](#2-user-role-testing)
3. [Workspace Testing](#3-workspace-testing)
4. [Security Testing](#4-security-testing)
5. [AI Integration Testing](#5-ai-integration-testing)
6. [Integration Testing](#6-integration-testing)

---

## 1. Infrastructure Validation

### 1.1 Service Health Checks

Run the automated validation script:

```bash
./scripts/validate.sh
```

Manual verification:

| Service | URL | Expected |
|---------|-----|----------|
| Coder | http://localhost:7080/api/v2/buildinfo | JSON with version |
| Gitea | http://localhost:3000 | Login page |
| Drone CI | http://localhost:8080 | Login page |
| LiteLLM | http://localhost:4000/health | `{"status":"healthy"}` |
| MinIO Console | http://localhost:9001 | Login page |
| MinIO S3 API | http://localhost:9002/minio/health/live | Health check response |
| Mailpit | http://localhost:8025 | Web UI |
| Authentik | http://localhost:9000/-/health/ready/ | HTTP 204 (No Content) |

### 1.2 Database Connectivity

```bash
# PostgreSQL (main) - verify with Coder user
docker exec postgres pg_isready -U coder -d coder

# Check all databases exist
docker exec postgres psql -U postgres -c "\l" | grep -E "coder|authentik|platform"

# TestDB
docker exec testdb psql -U appuser -d testapp -c "SELECT 'OK' as status;"
```

### 1.3 Network Isolation

```bash
# Run security validation
./scripts/validate-security.sh

# Manual checks
# PostgreSQL should NOT be accessible from host
nc -z localhost 5432 && echo "FAIL: Postgres exposed" || echo "PASS: Postgres internal"

# Redis should NOT be accessible from host
nc -z localhost 6379 && echo "FAIL: Redis exposed" || echo "PASS: Redis internal"
```

---

## 2. User Role Testing

### 2.1 Test Users

| Username | Role | Password | Purpose |
|----------|------|----------|---------|
| admin | Owner | Admin123! | Full admin testing |
| app-manager | Template Admin | Manager123! | Template management |
| contractor1 | Member | Contractor123! | Standard user testing |
| contractor2 | Member | Contractor123! | Multi-user testing |

### 2.2 Admin User Tests

Login as: `admin`

| Test | Steps | Expected Result |
|------|-------|-----------------|
| View all users | Deployment → Users | See all users list |
| Create user | Users → Create User | User created successfully |
| View audit logs | Deployment → Audit Logs | See all actions |
| Manage templates | Templates → Edit | Can edit any template |
| View all workspaces | Workspaces (filter: All) | See all user workspaces |
| Stop any workspace | Workspaces → Stop | Can stop others' workspaces |
| SSH to workspace | Workspace → Terminal | SSH access works |

### 2.3 Template Admin Tests

Login as: `app-manager`

| Test | Steps | Expected Result |
|------|-------|-----------------|
| View templates | Templates | See all templates |
| Create template | Templates → Create | Can create new template |
| Edit template | Templates → Edit | Can modify template |
| View workspaces | Workspaces | See own + viewable workspaces |
| Cannot manage users | Check sidebar | "Users" not visible |
| Cannot view audit | Check sidebar | "Audit Logs" not visible |

### 2.4 Member (Contractor) Tests

Login as: `contractor1`

| Test | Steps | Expected Result |
|------|-------|-----------------|
| View templates | Templates | See available templates |
| Create workspace | Workspaces → Create | Can create from template |
| Access own workspace | Workspaces → Open | IDE/Terminal works |
| Cannot edit templates | Templates | No edit button visible |
| Cannot see others | Workspaces | Only own workspaces |
| Cannot access admin | Check sidebar | No admin options |

### 2.5 Screen Comparison

#### Admin Screen
```
┌─────────────────────────────────────────┐
│ ☰ Coder                    [admin ▼]   │
├─────────────────────────────────────────┤
│ 📦 Workspaces                           │
│ 📋 Templates                            │
│ 👥 Users                    ← Admin    │
│ 📊 Audit Logs               ← Admin    │
│ ⚙️ Deployment               ← Admin    │
│   └─ General                            │
│   └─ Security                           │
│   └─ Network                            │
│   └─ Provisioners                       │
└─────────────────────────────────────────┘
```

#### Member (Contractor) Screen
```
┌─────────────────────────────────────────┐
│ ☰ Coder               [contractor1 ▼]  │
├─────────────────────────────────────────┤
│ 📦 Workspaces                           │
│ 📋 Templates                            │
│                                         │
│                                         │
│        (No admin options visible)       │
│                                         │
│                                         │
└─────────────────────────────────────────┘
```

---

## 3. Workspace Testing

### 3.1 Workspace Lifecycle

| Test | Steps | Expected Result |
|------|-------|-----------------|
| Create | Templates → contractor-workspace → Create | Workspace builds successfully |
| Start | Workspace → Start | Container starts, agent connects |
| Access IDE | Workspace → VS Code | code-server opens in browser |
| Access Terminal | Workspace → Terminal | Web terminal works |
| SSH Access | `coder ssh <workspace>` | SSH connection successful |
| Stop | Workspace → Stop | Container stops gracefully |
| Delete | Workspace → Delete | Workspace removed |

### 3.2 Workspace Parameters

Test parameter selection during creation:

| Parameter | Options | Verification |
|-----------|---------|--------------|
| CPU Cores | 2, 4 | `nproc` in terminal |
| Memory | 4GB, 8GB | `free -h` in terminal |
| AI Provider | Bedrock, Anthropic | Check `~/.config/roo-code/settings.json` |
| AI Model | Sonnet, Haiku, Opus | Check `~/.config/roo-code/settings.json` |
| Git Repo | URL | Repo cloned to `/home/coder/workspace` |

### 3.3 Persistence Testing

```bash
# In workspace terminal:
# 1. Create a file
echo "test data" > ~/workspace/test-persistence.txt

# 2. Stop workspace from Coder UI

# 3. Start workspace again

# 4. Verify file exists
cat ~/workspace/test-persistence.txt  # Should show "test data"
```

---

## 4. Security Testing

### 4.1 Automated Security Scan

```bash
./scripts/validate-security.sh
```

### 4.2 Access Control Tests

| Test | Steps | Expected Result |
|------|-------|-----------------|
| Unauthenticated API | `curl http://localhost:7080/api/v2/users/me` | 401 Unauthorized |
| Wrong credentials | Login with bad password | Login rejected |
| Session timeout | Wait for session expiry | Redirected to login |
| Cross-user access | contractor1 access contractor2's workspace | 403 Forbidden |

### 4.3 Network Security Tests

```bash
# From workspace terminal, test network restrictions

# Should SUCCEED (internal services)
curl http://gitea:3000          # Git server
curl http://litellm:4000       # LiteLLM (AI Proxy)
curl http://testdb:5432        # Should timeout (no HTTP)

# Should FAIL (if external blocked)
curl https://google.com        # External internet
```

### 4.4 Secret Exposure Tests

```bash
# Check no secrets in container inspect
docker inspect coder-server 2>/dev/null | grep -i "password\|secret\|key" | grep -v "null\|\"\"" || echo "PASS: No obvious secrets"

# Check environment variables in workspaces
# (Inside workspace)
env | grep -i "password\|secret\|key" || echo "PASS: No secrets in env"
```

---

## 5. AI Integration Testing

### 5.1 Coder AI Bridge (Built-in Chat)

| Test | Steps | Expected Result |
|------|-------|-----------------|
| Open AI Chat | Click AI icon in Coder | Chat panel opens |
| Send message | Type question, send | Response from Bedrock |
| No sign-in prompt | Start using | No Google/GitHub auth popup |

Prerequisites:
- AWS credentials configured in docker-compose.yml
- `CODER_AIBRIDGE_BEDROCK_*` environment variables set

### 5.2 Roo Code Extension (VS Code)

Inside workspace VS Code:

| Test | Steps | Expected Result |
|------|-------|-----------------|
| Verify installed | Check Activity Bar for Roo Code icon | Icon visible in sidebar |
| Open Roo Code | Click Roo Code icon in Activity Bar | Roo Code panel opens |
| Check LiteLLM config | Roo Code settings | Shows LiteLLM as API provider |
| AI request test | Ask Roo Code to explain a code snippet | Response generated via LiteLLM |

Verify configuration:
```bash
# In workspace terminal
cat ~/.config/roo-code/settings.json
# Should show LiteLLM provider configuration
```

### 5.3 LiteLLM Logging

```bash
# Check LiteLLM logs for requests
docker logs litellm --tail 20

# Should see request logs with workspace IDs
```

---

## 6. Integration Testing

### 6.1 Git Integration (Gitea)

| Test | Steps | Expected Result |
|------|-------|-----------------|
| Clone repo | `git clone http://gitea:3000/...` | Repo cloned |
| Commit | `git add . && git commit -m "test"` | Commit created |
| Push | `git push` | Changes pushed (with creds) |
| Webhook | Push triggers CI | Drone CI triggered |

### 6.2 CI/CD Integration (Drone)

| Test | Steps | Expected Result |
|------|-------|-----------------|
| Access Drone | http://localhost:8080 | Login page |
| Link repo | Activate repository | Pipeline configured |
| Trigger build | Push to repo | Build runs |
| View logs | Build → Logs | Build output visible |

### 6.3 Storage Integration (MinIO)

```bash
# From workspace (if mc installed)
mc alias set local http://minio:9002 minioadmin minioadmin
mc mb local/test-bucket
mc cp test.txt local/test-bucket/
mc ls local/test-bucket/
```

### 6.4 Email Testing (Mailpit)

1. Trigger email (e.g., Gitea password reset)
2. Open http://localhost:8025
3. Verify email received and rendered correctly

---

## Test Results Template

Use this template to document test runs:

```markdown
## Test Run: YYYY-MM-DD

**Tester:** [Name]
**Environment:** Dev Platform PoC v1.0

### Summary
- Total Tests: XX
- Passed: XX
- Failed: XX
- Skipped: XX

### Failed Tests
| Test | Expected | Actual | Notes |
|------|----------|--------|-------|
| | | | |

### Issues Found
1. [Issue description]

### Sign-off
- [ ] Infrastructure validated
- [ ] User roles verified
- [ ] Security tests passed
- [ ] Integration tests passed
```

---

## Automated Test Commands

Quick validation commands:

```bash
# Full infrastructure check
./scripts/validate.sh

# Security validation
./scripts/validate-security.sh

# Access control tests
./scripts/test-access-control.sh

# All-in-one
./scripts/validate.sh && ./scripts/validate-security.sh && echo "All tests passed!"
```
