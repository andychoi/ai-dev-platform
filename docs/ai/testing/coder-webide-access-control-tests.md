# Coder WebIDE - Access Control Test Scenarios

## Overview

This document defines test scenarios for validating the secure development platform's access control mechanisms. These tests verify that contractors can only access resources they are authorized to use.

## Test Environment

### Services

| Service | URL | Purpose |
|---------|-----|---------|
| Coder | http://localhost:7080 | WebIDE platform |
| Gogs | http://localhost:3000 | Git server |
| Drone CI | http://localhost:8080 | CI/CD server |

### Test Users

| Username | Password | Role | Description |
|----------|----------|------|-------------|
| admin | admin123 | Administrator | Full access to all resources |
| contractor1 | password123 | Developer | Write access to python-sample, private-project |
| contractor2 | password123 | Developer | Write access to python-sample only |
| contractor3 | password123 | Developer | Write access to shared-libs only |
| readonly | password123 | Viewer | Read-only access to python-sample |

### Repository Access Matrix

| Repository | admin | contractor1 | contractor2 | contractor3 | readonly |
|------------|-------|-------------|-------------|-------------|----------|
| python-sample | owner | write | write | none | read |
| private-project | owner | write | none | none | none |
| shared-libs | owner | read | read | write | none |
| frontend-app | owner | none | none | none | none |

---

## Test Scenarios

### Category 1: Git Repository Access Control

#### TC-1.1: Authorized Clone - Write Access

**Objective**: Verify user with write access can clone repository

**Preconditions**:
- Workspace created for contractor1
- contractor1 has write access to python-sample

**Steps**:
1. Create workspace for contractor1 with Git credentials
2. Open terminal in workspace
3. Execute: `git clone http://gogs:3000/admin/python-sample.git`
4. Verify clone succeeds

**Expected Result**: Repository cloned successfully

**Test Script**:
```bash
# In workspace terminal
git clone http://gogs:3000/admin/python-sample.git
cd python-sample
ls -la
# Should show: app.py, test_app.py, requirements.txt, .drone.yml
```

---

#### TC-1.2: Authorized Clone - Read Access

**Objective**: Verify user with read-only access can clone repository

**Preconditions**:
- Workspace created for readonly user
- readonly has read access to python-sample

**Steps**:
1. Create workspace for readonly with Git credentials
2. Open terminal in workspace
3. Execute: `git clone http://gogs:3000/admin/python-sample.git`
4. Verify clone succeeds

**Expected Result**: Repository cloned successfully

---

#### TC-1.3: Unauthorized Clone - No Access

**Objective**: Verify user without access cannot clone private repository

**Preconditions**:
- Workspace created for contractor2
- contractor2 has NO access to private-project

**Steps**:
1. Create workspace for contractor2 with Git credentials
2. Open terminal in workspace
3. Execute: `git clone http://gogs:3000/admin/private-project.git`
4. Verify clone fails with permission error

**Expected Result**: Clone fails with 403 Forbidden or authentication error

**Test Script**:
```bash
# In workspace terminal (as contractor2)
git clone http://gogs:3000/admin/private-project.git
# Expected: fatal: Authentication failed or 403 Forbidden
echo $?  # Should be non-zero exit code
```

---

#### TC-1.4: Authorized Push - Write Access

**Objective**: Verify user with write access can push changes

**Preconditions**:
- Workspace created for contractor1
- contractor1 has write access to python-sample
- Repository already cloned

**Steps**:
1. Clone python-sample repository
2. Create a new file: `echo "test" > test-file.txt`
3. Stage and commit: `git add . && git commit -m "Test commit"`
4. Push: `git push origin main`
5. Verify push succeeds

**Expected Result**: Push completes successfully

**Test Script**:
```bash
# In workspace terminal (as contractor1)
cd python-sample
echo "# Test file $(date)" > test-contractor1.txt
git add test-contractor1.txt
git commit -m "Test commit from contractor1"
git push origin main
# Expected: Success
```

---

#### TC-1.5: Unauthorized Push - Read-Only Access

**Objective**: Verify user with read-only access cannot push changes

**Preconditions**:
- Workspace created for readonly user
- readonly has read-only access to python-sample
- Repository already cloned

**Steps**:
1. Clone python-sample repository
2. Create a new file: `echo "test" > test-file.txt`
3. Stage and commit: `git add . && git commit -m "Test commit"`
4. Push: `git push origin main`
5. Verify push fails with permission error

**Expected Result**: Push fails with 403 Forbidden

**Test Script**:
```bash
# In workspace terminal (as readonly)
cd python-sample
echo "# Unauthorized change" > unauthorized.txt
git add unauthorized.txt
git commit -m "Unauthorized commit attempt"
git push origin main
# Expected: remote: You do not have permission to push
```

---

### Category 2: Workspace Isolation

#### TC-2.1: Cross-Workspace File Access

**Objective**: Verify workspaces cannot access each other's files

**Preconditions**:
- Two workspaces created: ws-contractor1 and ws-contractor2
- Both workspaces running simultaneously

**Steps**:
1. Create workspace for contractor1, create file `/home/coder/secret.txt`
2. Create workspace for contractor2
3. From contractor2's workspace, attempt to access contractor1's files
4. Verify access is denied

**Expected Result**: No cross-workspace file access possible

**Test Script**:
```bash
# From contractor2's workspace
# Try to access contractor1's workspace (should fail)
ls /var/lib/docker/volumes/coder-contractor1-*/
# Expected: Permission denied

# Verify containers are isolated
docker ps  # Should only see own workspace
```

---

#### TC-2.2: Network Isolation Between Workspaces

**Objective**: Verify workspaces cannot directly communicate with each other

**Preconditions**:
- Two workspaces running on same Docker network

**Steps**:
1. Get IP address of workspace 1
2. From workspace 2, attempt to ping workspace 1
3. Attempt to connect to workspace 1's services

**Expected Result**: Network communication blocked by policy (in production with NetworkPolicy)

**Note**: In Docker PoC, basic isolation is via container boundaries. Full network isolation requires Kubernetes NetworkPolicy.

---

### Category 3: CI/CD Pipeline Access

#### TC-3.1: CI Pipeline Triggered on Push

**Objective**: Verify CI pipeline runs when authorized user pushes code

**Preconditions**:
- Drone CI connected to Gogs
- contractor1 has write access to python-sample
- .drone.yml exists in repository

**Steps**:
1. Clone python-sample as contractor1
2. Make a code change
3. Push to repository
4. Check Drone CI dashboard

**Expected Result**: CI pipeline triggered and runs all stages

**Verification**:
```bash
# Check Drone CI
curl -s http://localhost:8080/api/repos/admin/python-sample/builds | jq '.[0]'
# Should show recent build with status
```

---

#### TC-3.2: CI Pipeline Status Visibility

**Objective**: Verify CI status visible to authorized users only

**Steps**:
1. Login to Drone CI as contractor1
2. View python-sample builds - should succeed
3. Login as contractor3
4. Attempt to view python-sample builds - should fail

**Expected Result**: Build visibility matches repository access

---

### Category 4: Coder Platform Access

#### TC-4.1: Workspace Creation - Authorized Template

**Objective**: Verify users can only create workspaces from authorized templates

**Steps**:
1. Login to Coder as contractor1
2. View available templates
3. Create workspace from contractor-workspace template
4. Verify workspace is created successfully

**Expected Result**: Workspace created with correct resource limits

---

#### TC-4.2: Workspace Resource Limits

**Objective**: Verify workspace respects configured resource limits

**Preconditions**:
- Workspace created with 2 CPU cores, 4GB memory

**Steps**:
1. Open terminal in workspace
2. Check CPU allocation: `nproc`
3. Check memory allocation: `free -h`
4. Attempt to exceed limits with stress test

**Expected Result**: Resources capped at configured limits

**Test Script**:
```bash
# In workspace terminal
echo "CPU cores: $(nproc)"
echo "Memory: $(free -h | grep Mem | awk '{print $2}')"

# Verify limits are enforced
cat /sys/fs/cgroup/cpu/cpu.shares
cat /sys/fs/cgroup/memory/memory.limit_in_bytes
```

---

#### TC-4.3: Session Timeout

**Objective**: Verify workspace session times out after inactivity

**Steps**:
1. Login to Coder, create workspace
2. Open VS Code in browser
3. Leave idle for configured timeout period
4. Verify session is terminated

**Expected Result**: Session ends after timeout period

---

### Category 5: Data Exfiltration Prevention

#### TC-5.1: Clipboard Restriction (Production)

**Objective**: Verify clipboard copy/paste from workspace to local machine is restricted

**Note**: This test is for production environment with CSP headers configured.

**Steps**:
1. Open VS Code in workspace
2. Select code in editor
3. Attempt to copy (Ctrl+C)
4. Attempt to paste in local application

**Expected Result**: Paste fails or is blocked

---

#### TC-5.2: File Download Prevention (Production)

**Objective**: Verify users cannot download files from workspace

**Steps**:
1. Open VS Code in workspace
2. Right-click on file
3. Attempt to download/save locally

**Expected Result**: Download blocked or file appears empty

---

## Automated Test Script

```bash
#!/bin/bash
# access-control-tests.sh
# Automated access control test suite

set -e

GOGS_URL="http://localhost:3000"
CODER_URL="http://localhost:7080"

echo "=== Access Control Test Suite ==="
echo ""

# Test 1.1: Authorized Clone (contractor1 -> python-sample)
echo "TC-1.1: Authorized Clone (Write Access)"
RESULT=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "contractor1:password123" \
    "${GOGS_URL}/api/v1/repos/admin/python-sample")
if [ "$RESULT" == "200" ]; then
    echo "  [PASS] contractor1 can access python-sample"
else
    echo "  [FAIL] contractor1 cannot access python-sample (HTTP $RESULT)"
fi

# Test 1.3: Unauthorized Clone (contractor2 -> private-project)
echo "TC-1.3: Unauthorized Clone (No Access)"
RESULT=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "contractor2:password123" \
    "${GOGS_URL}/api/v1/repos/admin/private-project")
if [ "$RESULT" == "404" ] || [ "$RESULT" == "403" ]; then
    echo "  [PASS] contractor2 cannot access private-project"
else
    echo "  [FAIL] contractor2 can access private-project (HTTP $RESULT)"
fi

# Test 1.2: Read-only Clone (readonly -> python-sample)
echo "TC-1.2: Read-Only Clone"
RESULT=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "readonly:password123" \
    "${GOGS_URL}/api/v1/repos/admin/python-sample")
if [ "$RESULT" == "200" ]; then
    echo "  [PASS] readonly can read python-sample"
else
    echo "  [FAIL] readonly cannot read python-sample (HTTP $RESULT)"
fi

# Test: contractor3 access to shared-libs (write)
echo "TC-1.x: contractor3 Write Access to shared-libs"
RESULT=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "contractor3:password123" \
    "${GOGS_URL}/api/v1/repos/admin/shared-libs")
if [ "$RESULT" == "200" ]; then
    echo "  [PASS] contractor3 can access shared-libs"
else
    echo "  [FAIL] contractor3 cannot access shared-libs (HTTP $RESULT)"
fi

# Test: contractor1 cannot access frontend-app
echo "TC-1.x: contractor1 No Access to frontend-app"
RESULT=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "contractor1:password123" \
    "${GOGS_URL}/api/v1/repos/admin/frontend-app")
if [ "$RESULT" == "404" ] || [ "$RESULT" == "403" ]; then
    echo "  [PASS] contractor1 cannot access frontend-app"
else
    echo "  [FAIL] contractor1 can access frontend-app (HTTP $RESULT)"
fi

echo ""
echo "=== Test Suite Complete ==="
```

---

## Test Execution Checklist

### Pre-Test Setup

- [ ] Docker Compose environment running
- [ ] Gogs initialized with users and repos (`./scripts/setup-gogs.sh`)
- [ ] Drone CI connected to Gogs
- [ ] Coder template pushed

### Test Execution

| Test ID | Description | Status | Notes |
|---------|-------------|--------|-------|
| TC-1.1 | Authorized Clone - Write | | |
| TC-1.2 | Authorized Clone - Read | | |
| TC-1.3 | Unauthorized Clone - No Access | | |
| TC-1.4 | Authorized Push - Write | | |
| TC-1.5 | Unauthorized Push - Read Only | | |
| TC-2.1 | Cross-Workspace File Access | | |
| TC-2.2 | Network Isolation | | |
| TC-3.1 | CI Pipeline on Push | | |
| TC-3.2 | CI Status Visibility | | |
| TC-4.1 | Workspace Creation | | |
| TC-4.2 | Resource Limits | | |
| TC-4.3 | Session Timeout | | |
| TC-5.1 | Clipboard Restriction | | Production only |
| TC-5.2 | File Download Prevention | | Production only |

### Post-Test Cleanup

- [ ] Delete test workspaces
- [ ] Revert test commits in repositories
- [ ] Review audit logs

---

## Expected Outcomes

### PoC Validation Criteria

| Criteria | Threshold | Measurement |
|----------|-----------|-------------|
| Access control accuracy | 100% | All unauthorized access attempts blocked |
| Workspace isolation | 100% | No cross-workspace data access |
| CI/CD integration | Working | Pipeline triggers on push |
| Resource limits | Enforced | Cannot exceed configured limits |

### Success Criteria for Production Readiness

1. **Security**: All access control tests pass
2. **Isolation**: Workspace isolation verified
3. **Auditability**: All access attempts logged
4. **Usability**: Developers can complete workflows
5. **Performance**: Workspace startup < 2 minutes

---

## Troubleshooting

### Common Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Clone fails with 401 | Invalid credentials | Verify username/password |
| Clone fails with 404 | Repository not found | Check repository name and access |
| Push fails with 403 | Insufficient permissions | Verify write access in Gogs |
| CI not triggering | Webhook not configured | Check Gogs webhook settings |
| Workspace won't start | Resource limits | Check Docker resources |

### Debug Commands

```bash
# Check Gogs logs
docker logs gogs

# Check Drone logs
docker logs drone-server

# Check Coder logs
docker logs coder-server

# Verify network connectivity
docker exec <workspace-container> ping gogs
```
