# Coder WebIDE Integration - Implementation Plan

## Overview

This document outlines the phased implementation plan for deploying Coder as a secure web-based development platform for contractors. The plan includes local Docker testing (MacBook Pro/Linux) before production Kubernetes deployment.

## Implementation Phases

```mermaid
gantt
    title Coder WebIDE Implementation Timeline
    dateFormat  YYYY-MM-DD
    section Phase 1: Local Testing
    Docker environment setup     :p1a, 2026-02-05, 2d
    Coder installation          :p1b, after p1a, 1d
    Basic workspace templates    :p1c, after p1b, 2d
    Local validation            :p1d, after p1c, 2d

    section Phase 2: Security Hardening
    Network policies            :p2a, after p1d, 3d
    Authentication setup        :p2b, after p2a, 2d
    Audit logging              :p2c, after p2b, 2d

    section Phase 3: Production Prep
    K8s infrastructure          :p3a, after p2c, 5d
    Template finalization       :p3b, after p3a, 3d
    Security review             :p3c, after p3b, 5d

    section Phase 4: Rollout
    Pilot deployment           :p4a, after p3c, 5d
    User onboarding            :p4b, after p4a, 5d
    Full rollout               :p4c, after p4b, 10d
```

---

## Phase 1: Local Docker Testing (MacBook Pro / Linux)

### Objective
Set up a complete Coder environment locally using Docker to validate the platform before production deployment.

### Prerequisites

| Requirement | MacBook Pro | Linux |
|-------------|-------------|-------|
| Docker Desktop | 4.x+ | Docker Engine 24.x+ |
| Docker Compose | v2.x (included) | v2.x |
| RAM | 8GB minimum (16GB recommended) | 8GB minimum |
| Disk Space | 20GB free | 20GB free |
| CPU | 4 cores | 4 cores |

### Task 1.1: Docker Environment Setup

**Duration**: 2 days

#### Steps:

1. **Install Docker (if not present)**

   **MacBook Pro**:
   ```bash
   # Download Docker Desktop from docker.com
   # Or use Homebrew:
   brew install --cask docker
   ```

   **Linux (Ubuntu/Debian)**:
   ```bash
   # Install Docker Engine
   curl -fsSL https://get.docker.com | sh
   sudo usermod -aG docker $USER
   newgrp docker

   # Install Docker Compose
   sudo apt-get install docker-compose-plugin
   ```

2. **Create project directory**
   ```bash
   mkdir -p ~/coder-test/{data,templates,workspace-images}
   cd ~/coder-test
   ```

3. **Create Docker Compose configuration**

   ```yaml
   # ~/coder-test/docker-compose.yml
   version: "3.9"

   services:
     postgres:
       image: postgres:15-alpine
       container_name: coder-postgres
       environment:
         POSTGRES_USER: coder
         POSTGRES_PASSWORD: coder_password_change_me
         POSTGRES_DB: coder
       volumes:
         - postgres_data:/var/lib/postgresql/data
       healthcheck:
         test: ["CMD-SHELL", "pg_isready -U coder -d coder"]
         interval: 5s
         timeout: 5s
         retries: 5
       networks:
         - coder-network

     coder:
       image: ghcr.io/coder/coder:latest
       container_name: coder-server
       depends_on:
         postgres:
           condition: service_healthy
       environment:
         CODER_PG_CONNECTION_URL: "postgresql://coder:coder_password_change_me@postgres:5432/coder?sslmode=disable"
         CODER_ACCESS_URL: "http://localhost:7080"
         CODER_HTTP_ADDRESS: "0.0.0.0:7080"
         # For local testing - disable HTTPS redirect
         CODER_SECURE_AUTH_COOKIE: "false"
         CODER_TELEMETRY: "false"
         # Enable Docker provisioner for local templates
         CODER_PROVISIONER_DAEMONS: "3"
       ports:
         - "7080:7080"
       volumes:
         - /var/run/docker.sock:/var/run/docker.sock
         - coder_data:/home/coder/.config/coderv2
       networks:
         - coder-network
       group_add:
         - ${DOCKER_GID:-999}

   volumes:
     postgres_data:
     coder_data:

   networks:
     coder-network:
       driver: bridge
   ```

4. **Start the environment**
   ```bash
   # Get Docker group ID (Linux) or use default (Mac)
   export DOCKER_GID=$(getent group docker | cut -d: -f3 2>/dev/null || echo "999")

   # Start services
   docker compose up -d

   # Check logs
   docker compose logs -f coder
   ```

5. **Create initial admin user**
   ```bash
   # Wait for Coder to be ready
   docker exec -it coder-server coder login http://localhost:7080 --first-user-username admin --first-user-email admin@local.test --first-user-password SecureP@ssw0rd
   ```

### Task 1.2: Coder CLI Installation

**Duration**: 0.5 days

```bash
# MacBook Pro
brew install coder/coder/coder

# Linux
curl -fsSL https://coder.com/install.sh | sh

# Verify installation
coder version

# Login to local instance
coder login http://localhost:7080
```

### Task 1.3: Create Workspace Template

**Duration**: 2 days

1. **Create template directory**
   ```bash
   mkdir -p ~/coder-test/templates/contractor-dev
   cd ~/coder-test/templates/contractor-dev
   ```

2. **Create Terraform template for Docker**

   ```hcl
   # ~/coder-test/templates/contractor-dev/main.tf

   terraform {
     required_providers {
       coder = {
         source = "coder/coder"
       }
       docker = {
         source = "kreuzwerker/docker"
       }
     }
   }

   data "coder_provisioner" "me" {}
   data "coder_workspace" "me" {}
   data "coder_workspace_owner" "me" {}

   provider "docker" {}

   # Parameters for customization
   data "coder_parameter" "cpu_cores" {
     name         = "cpu_cores"
     display_name = "CPU Cores"
     description  = "Number of CPU cores for the workspace"
     default      = "2"
     mutable      = true
     option {
       name  = "2 Cores"
       value = "2"
     }
     option {
       name  = "4 Cores"
       value = "4"
     }
   }

   data "coder_parameter" "memory_gb" {
     name         = "memory_gb"
     display_name = "Memory (GB)"
     description  = "RAM allocation for the workspace"
     default      = "4"
     mutable      = true
     option {
       name  = "4 GB"
       value = "4"
     }
     option {
       name  = "8 GB"
       value = "8"
     }
   }

   data "coder_parameter" "project_repo" {
     name         = "project_repo"
     display_name = "Project Repository"
     description  = "Git repository to clone (optional)"
     default      = ""
     mutable      = true
   }

   resource "coder_agent" "main" {
     arch = data.coder_provisioner.me.arch
     os   = "linux"
     dir  = "/home/coder"

     startup_script = <<-EOT
       #!/bin/bash
       set -e

       # Clone project if specified
       if [ -n "${data.coder_parameter.project_repo.value}" ]; then
         git clone "${data.coder_parameter.project_repo.value}" ~/project || true
       fi

       # Start code-server
       code-server --auth none --bind-addr 0.0.0.0:8080 &

       echo "Workspace ready!"
     EOT

     metadata {
       key          = "cpu"
       display_name = "CPU Usage"
       script       = "top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | cut -d. -f1"
       interval     = 10
       timeout      = 1
     }

     metadata {
       key          = "memory"
       display_name = "Memory Usage"
       script       = "free -m | awk 'NR==2{printf \"%.0f%%\", $3*100/$2}'"
       interval     = 10
       timeout      = 1
     }

     metadata {
       key          = "disk"
       display_name = "Disk Usage"
       script       = "df -h /home/coder | awk 'NR==2{print $5}'"
       interval     = 60
       timeout      = 1
     }
   }

   # VS Code Web App
   resource "coder_app" "code-server" {
     agent_id     = coder_agent.main.id
     slug         = "code-server"
     display_name = "VS Code"
     icon         = "/icon/code.svg"
     url          = "http://localhost:8080?folder=/home/coder"
     subdomain    = true
     share        = "owner"

     healthcheck {
       url       = "http://localhost:8080/healthz"
       interval  = 5
       threshold = 10
     }
   }

   # Terminal App
   resource "coder_app" "terminal" {
     agent_id     = coder_agent.main.id
     slug         = "terminal"
     display_name = "Terminal"
     icon         = "/icon/terminal.svg"
     command      = "/bin/bash"
   }

   # Docker image for the workspace
   resource "docker_image" "workspace" {
     name = "contractor-workspace:latest"
     build {
       context = "${path.module}/image"
       tag     = ["contractor-workspace:latest"]
     }
     triggers = {
       dir_sha1 = sha1(join("", [for f in fileset("${path.module}/image", "*") : filesha1("${path.module}/image/${f}")]))
     }
   }

   # Docker container for workspace
   resource "docker_container" "workspace" {
     name  = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
     image = docker_image.workspace.image_id

     # Run as non-root user
     user = "1000:1000"

     # Resource limits
     cpu_shares = data.coder_parameter.cpu_cores.value * 1024
     memory     = data.coder_parameter.memory_gb.value * 1024 * 1024 * 1024

     # Environment
     env = [
       "CODER_AGENT_TOKEN=${coder_agent.main.token}",
       "GIT_AUTHOR_NAME=${data.coder_workspace_owner.me.name}",
       "GIT_AUTHOR_EMAIL=${data.coder_workspace_owner.me.email}",
     ]

     # Hostname
     hostname = data.coder_workspace.me.name

     # Entry point
     entrypoint = ["sh", "-c", coder_agent.main.init_script]

     # Persistent volume
     volumes {
       volume_name    = docker_volume.workspace.name
       container_path = "/home/coder"
     }

     # Network
     networks_advanced {
       name = "coder-test_coder-network"
     }

     # Keep container running
     must_run = true
     start    = true

     # Lifecycle
     lifecycle {
       ignore_changes = all
     }
   }

   # Persistent volume for workspace data
   resource "docker_volume" "workspace" {
     name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"

     lifecycle {
       prevent_destroy = false
     }
   }
   ```

3. **Create workspace Docker image**

   ```bash
   mkdir -p ~/coder-test/templates/contractor-dev/image
   ```

   ```dockerfile
   # ~/coder-test/templates/contractor-dev/image/Dockerfile
   FROM ubuntu:22.04

   # Avoid prompts during package installation
   ENV DEBIAN_FRONTEND=noninteractive

   # Install base dependencies
   RUN apt-get update && apt-get install -y \
       curl \
       wget \
       git \
       vim \
       sudo \
       openssh-client \
       ca-certificates \
       gnupg \
       lsb-release \
       jq \
       htop \
       locales \
       && rm -rf /var/lib/apt/lists/*

   # Set locale
   RUN locale-gen en_US.UTF-8
   ENV LANG=en_US.UTF-8

   # Install Node.js 20
   RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
       && apt-get install -y nodejs \
       && npm install -g npm@latest

   # Install Python 3
   RUN apt-get update && apt-get install -y \
       python3 \
       python3-pip \
       python3-venv \
       && rm -rf /var/lib/apt/lists/*

   # Install code-server (VS Code in browser)
   RUN curl -fsSL https://code-server.dev/install.sh | sh

   # Install Coder agent
   RUN curl -fsSL https://coder.com/install.sh | sh

   # Create coder user
   RUN useradd -m -s /bin/bash -u 1000 coder \
       && echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/coder

   # Setup home directory
   USER coder
   WORKDIR /home/coder

   # Pre-configure VS Code settings
   RUN mkdir -p /home/coder/.local/share/code-server/User
   COPY --chown=coder:coder settings.json /home/coder/.local/share/code-server/User/settings.json

   # Configure git
   RUN git config --global init.defaultBranch main \
       && git config --global pull.rebase false

   # Keep container running
   CMD ["sleep", "infinity"]
   ```

   ```json
   // ~/coder-test/templates/contractor-dev/image/settings.json
   {
     "editor.fontSize": 14,
     "editor.tabSize": 2,
     "editor.formatOnSave": true,
     "terminal.integrated.fontSize": 14,
     "files.autoSave": "afterDelay",
     "workbench.colorTheme": "Default Dark Modern",
     "git.autofetch": true
   }
   ```

4. **Push template to Coder**
   ```bash
   cd ~/coder-test/templates/contractor-dev

   # Build the image first
   docker build -t contractor-workspace:latest ./image

   # Create and push template
   coder templates create contractor-dev --directory .
   ```

### Task 1.4: Validate Local Environment

**Duration**: 2 days

#### Validation Checklist

| Test | Command/Action | Expected Result |
|------|---------------|-----------------|
| Coder UI accessible | Open http://localhost:7080 | Login page displays |
| Admin login works | Login with admin credentials | Dashboard loads |
| Template visible | Check Templates page | `contractor-dev` listed |
| Create workspace | Create new workspace | Workspace starts successfully |
| VS Code loads | Click VS Code icon | Editor opens in browser |
| Terminal works | Open integrated terminal | Shell prompt available |
| Git operations | Clone a public repo | Clone succeeds |
| File persistence | Create file, restart workspace | File persists |
| Resource limits | Check htop in workspace | CPU/Memory limited |

#### Test Script

```bash
#!/bin/bash
# ~/coder-test/validate.sh

echo "=== Coder Local Validation ==="

# Test 1: API Health
echo -n "API Health Check: "
if curl -s http://localhost:7080/api/v2/buildinfo | jq -e '.version' > /dev/null; then
    echo "PASS"
else
    echo "FAIL"
fi

# Test 2: Template exists
echo -n "Template Exists: "
if coder templates list | grep -q "contractor-dev"; then
    echo "PASS"
else
    echo "FAIL"
fi

# Test 3: Create test workspace
echo "Creating test workspace..."
coder create test-workspace --template contractor-dev --parameter cpu_cores=2 --parameter memory_gb=4 -y

# Test 4: Wait for workspace
echo -n "Workspace Ready: "
sleep 30
if coder list | grep -q "test-workspace.*Running"; then
    echo "PASS"
else
    echo "FAIL"
fi

# Test 5: SSH connectivity
echo -n "SSH Connection: "
if coder ssh test-workspace -- echo "Hello from workspace" 2>/dev/null | grep -q "Hello"; then
    echo "PASS"
else
    echo "FAIL"
fi

# Cleanup
echo "Cleaning up..."
coder delete test-workspace -y

echo "=== Validation Complete ==="
```

---

## Phase 2: Security Hardening

### Objective
Implement security controls for production readiness.

### Task 2.1: Network Policies (Docker)

**Duration**: 3 days

```yaml
# ~/coder-test/docker-compose.security.yml
version: "3.9"

services:
  coder:
    # Add security configurations
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    read_only: false
    tmpfs:
      - /tmp

networks:
  coder-network:
    driver: bridge
    internal: false
  workspace-network:
    driver: bridge
    internal: true  # Isolated from internet
```

### Task 2.2: Authentication Setup

**Duration**: 2 days

1. **OIDC Configuration (for testing with Authentik)**

   ```yaml
   # Add to docker-compose.yml
   authentik-server:
     image: ghcr.io/goauthentik/server:2024.2
     container_name: authentik-server
     environment:
       AUTHENTIK_POSTGRESQL__HOST: postgres
       AUTHENTIK_POSTGRESQL__NAME: authentik
       AUTHENTIK_POSTGRESQL__USER: authentik
       AUTHENTIK_POSTGRESQL__PASSWORD: ${AUTHENTIK_DB_PASSWORD}
       AUTHENTIK_SECRET_KEY: ${AUTHENTIK_SECRET_KEY}
       AUTHENTIK_REDIS__HOST: authentik-redis
     ports:
       - "9000:9000"
       - "9443:9443"
     networks:
       - coder-network

   authentik-worker:
     image: ghcr.io/goauthentik/server:2024.2
     command: worker
     environment:
       # Same as authentik-server
     networks:
       - coder-network

   authentik-redis:
     image: redis:7-alpine
     networks:
       - coder-network
   ```

2. **Coder OIDC Environment Variables**

   ```bash
   # Add to coder service environment
   CODER_OIDC_ISSUER_URL: "http://authentik-server:9000/application/o/coder/"
   CODER_OIDC_CLIENT_ID: "coder"
   CODER_OIDC_CLIENT_SECRET: "${CODER_OIDC_CLIENT_SECRET}"
   CODER_OIDC_SIGN_IN_TEXT: "Sign in with SSO"
   CODER_DISABLE_PASSWORD_AUTH: "false"  # Keep for testing
   ```

   **CRITICAL**: For local development, access Coder via `http://host.docker.internal:7080`, NOT `localhost`.
   This is required for OIDC callbacks to work correctly due to cookie domain matching.

### Task 2.3: Audit Logging

**Duration**: 2 days

```yaml
# Add logging service
loki:
  image: grafana/loki:latest
  ports:
    - "3100:3100"
  volumes:
    - loki_data:/loki
  networks:
    - coder-network

grafana:
  image: grafana/grafana:latest
  ports:
    - "3000:3000"
  environment:
    GF_AUTH_ANONYMOUS_ENABLED: "true"
  volumes:
    - grafana_data:/var/lib/grafana
  networks:
    - coder-network
```

---

## Phase 3: Production Kubernetes Deployment

> **Note:** For detailed production deployment planning, see [Production Implementation Plan](../../../aws-production/PRODUCTION-PLAN.md) which includes a 6-week timeline and addresses 68 identified security issues.

### Objective
Deploy Coder to production Kubernetes cluster.

### Task 3.1: Kubernetes Infrastructure

**Duration**: 5 days

```yaml
# k8s/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: coder
  labels:
    name: coder
---
apiVersion: v1
kind: Namespace
metadata:
  name: contractor-workspaces
  labels:
    name: contractor-workspaces
```

```yaml
# k8s/coder-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coder
  namespace: coder
spec:
  replicas: 2
  selector:
    matchLabels:
      app: coder
  template:
    metadata:
      labels:
        app: coder
    spec:
      serviceAccountName: coder
      containers:
        - name: coder
          image: ghcr.io/coder/coder:latest
          envFrom:
            - configMapRef:
                name: coder-config
            - secretRef:
                name: coder-secrets
          ports:
            - containerPort: 7080
          resources:
            requests:
              cpu: 500m
              memory: 1Gi
            limits:
              cpu: 2000m
              memory: 4Gi
          livenessProbe:
            httpGet:
              path: /api/v2/buildinfo
              port: 7080
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /api/v2/buildinfo
              port: 7080
            initialDelaySeconds: 5
            periodSeconds: 5
```

### Task 3.2: Helm Chart Installation (Alternative)

```bash
# Add Coder Helm repo
helm repo add coder https://helm.coder.com/v2
helm repo update

# Install Coder
helm install coder coder/coder \
  --namespace coder \
  --create-namespace \
  --values values.yaml
```

```yaml
# values.yaml
coder:
  env:
    - name: CODER_ACCESS_URL
      value: "https://coder.company.com"
    - name: CODER_WILDCARD_ACCESS_URL
      value: "*.coder.company.com"
    - name: CODER_PG_CONNECTION_URL
      valueFrom:
        secretKeyRef:
          name: coder-db-url
          key: url

  ingress:
    enable: true
    host: "coder.company.com"
    wildcardHost: "*.coder.company.com"
    tls:
      enable: true
      secretName: coder-tls

  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 2000m
      memory: 4Gi

postgresql:
  enabled: false  # Use external PostgreSQL
```

---

## Phase 4: Rollout

### Task 4.1: Pilot Deployment

**Duration**: 5 days

| Activity | Description | Owner |
|----------|-------------|-------|
| Select pilot users | Choose 5-10 contractors | Project Manager |
| Create pilot templates | Project-specific templates | Platform Team |
| Training session | 1-hour onboarding | Platform Team |
| Monitor usage | Track metrics and issues | Platform Team |
| Gather feedback | Survey and interviews | Project Manager |

### Task 4.2: Full Rollout

**Duration**: 10 days

| Week | Milestone |
|------|-----------|
| Week 1 | Onboard 25% of contractors |
| Week 2 | Onboard 50% of contractors |
| Week 3 | Onboard 100% of contractors |
| Week 4 | Decommission old access methods |

---

## Quick Start Commands

### Local Development (Copy-Paste Ready)

```bash
# 1. Create project directory
mkdir -p ~/coder-test && cd ~/coder-test

# 2. Download docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: "3.9"
services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: coder
      POSTGRES_PASSWORD: coder_password
      POSTGRES_DB: coder
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U coder -d coder"]
      interval: 5s
      timeout: 5s
      retries: 5

  coder:
    image: ghcr.io/coder/coder:latest
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      CODER_PG_CONNECTION_URL: "postgresql://coder:coder_password@postgres:5432/coder?sslmode=disable"
      CODER_ACCESS_URL: "http://localhost:7080"
      CODER_HTTP_ADDRESS: "0.0.0.0:7080"
      CODER_TELEMETRY: "false"
    ports:
      - "7080:7080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    group_add:
      - "${DOCKER_GID:-999}"

volumes:
  postgres_data:
EOF

# 3. Start Coder
docker compose up -d

# 4. Wait for startup (30 seconds)
echo "Waiting for Coder to start..."
sleep 30

# 5. Create admin user
docker exec -it coder-test-coder-1 coder login http://localhost:7080 \
  --first-user-username admin \
  --first-user-email admin@local.test \
  --first-user-password 'SecureP@ssw0rd!'

# 6. Access Coder
echo "Coder is ready at: http://localhost:7080"
echo "Username: admin"
echo "Password: SecureP@ssw0rd!"
```

### Cleanup Commands

```bash
# Stop and remove containers
cd ~/coder-test
docker compose down

# Remove all data (destructive)
docker compose down -v

# Remove images
docker rmi ghcr.io/coder/coder:latest postgres:15-alpine
```

---

## Resource Requirements

### Local Testing

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 4 cores | 8 cores |
| RAM | 8 GB | 16 GB |
| Storage | 20 GB | 50 GB |
| Docker | 24.x | Latest |

### Production (per workspace)

| Resource | Minimum | Maximum |
|----------|---------|---------|
| CPU | 500m | 4 cores |
| RAM | 2 GB | 8 GB |
| Storage | 10 GB | 50 GB |

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Docker socket exposure | Use rootless Docker or Sysbox |
| Resource exhaustion | Implement strict quotas |
| Network escape | Apply network policies |
| Data loss | Regular PVC backups |

---

## Success Metrics

| Metric | Target |
|--------|--------|
| Workspace startup time | < 2 minutes |
| VS Code load time | < 10 seconds |
| Platform uptime | 99.5% |
| User satisfaction | > 4/5 rating |

---

## Next Steps

1. Execute Phase 1 local testing
2. Document findings and adjustments
3. Schedule security review
4. Plan pilot user selection
5. Prepare training materials

## References

- [Coder Docker Installation](https://coder.com/docs/install/docker)
- [Coder Kubernetes Installation](https://coder.com/docs/install/kubernetes)
- [Coder Templates](https://coder.com/docs/templates)
- [code-server Documentation](https://coder.com/docs/code-server)
