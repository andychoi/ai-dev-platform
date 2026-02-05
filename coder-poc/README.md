# Coder WebIDE PoC

A proof-of-concept implementation for deploying [Coder](https://coder.com) as a secure web-based development platform for contractors and developers.

## Objectives

### 1. Enhanced Security & Compliance

- **Zero-trust access model** - No direct shell, RDP, or database access from untrusted devices
- **Isolated workspaces** - Each developer works in a containerized environment with defined boundaries
- **Centralized control** - All code stays on company infrastructure, never on local devices
- **Audit trail** - Complete visibility into workspace activity and resource usage
- **SSO integration** - Enterprise identity management via OIDC (Authentik, Azure AD, Okta)

### 2. Cost Reduction vs Traditional VDI

| Aspect | Traditional VDI | Coder Workspaces |
|--------|-----------------|------------------|
| Resource usage | Full VM per user | Lightweight containers |
| Startup time | 5-15 minutes | 30-60 seconds |
| License costs | Windows + VDI licenses | Open source core |
| Storage | Persistent VM disks | Ephemeral + persistent volumes |
| Scaling | Manual VM provisioning | Auto-scaling containers |

**Expected savings:** 40-60% reduction in infrastructure costs compared to VDI solutions.

### 3. Consistent & Fast Developer Onboarding

- **Day-one productivity** - New hires get a fully configured environment in minutes, not days
- **Template-based provisioning** - Standardized environments eliminate "works on my machine" issues
- **Pre-installed tools** - IDEs, SDKs, linters, and extensions ready out of the box
- **Dotfiles support** - Personal configurations automatically applied
- **Self-service** - Developers create workspaces without IT tickets

### 4. AI-Assisted Development Platform

Aligned with [Coder's Enterprise AI Development vision](https://coder.com/blog/coder-enterprise-grade-platform-for-self-hosted-ai-development):

- **AI Workspaces** - Isolated environments where AI agents and developers collaborate securely
- **Agent Boundaries** - Dual-firewall security model restricting AI agent access while maintaining productivity
- **AI Gateway** - Centralized proxy for Claude, AWS Bedrock, and other AI providers with rate limiting and audit logging
- **Prebuilt Workspaces** - Instant setup across any branch, reducing AI context initialization time
- **Future-ready** - Infrastructure designed for autonomous coding agents (Claude Code, Cursor, etc.)

## Overview

This PoC demonstrates how Coder can provide secure browser-based development environments, eliminating the need for direct shell, RDP, or database access from untrusted devices.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Contractor Browser                            │
└─────────────────────────┬───────────────────────────────────────┘
                          │ HTTPS
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Coder Server                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │  Dashboard  │  │   API       │  │ Provisioner │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└─────────────────────────┬───────────────────────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
┌───────────────┐ ┌───────────────┐ ┌───────────────┐
│  Workspace 1  │ │  Workspace 2  │ │  Workspace N  │
│  ┌─────────┐  │ │  ┌─────────┐  │ │  ┌─────────┐  │
│  │ VS Code │  │ │  │ VS Code │  │ │  │ VS Code │  │
│  │ (Web)   │  │ │  │ (Web)   │  │ │  │ (Web)   │  │
│  └─────────┘  │ │  └─────────┘  │ │  └─────────┘  │
└───────────────┘ └───────────────┘ └───────────────┘
```

## Quick Start

### Prerequisites

- **Docker Desktop** (Mac) or **Docker Engine** (Linux)
- **8GB RAM** minimum (16GB recommended)
- **20GB disk space**
- **curl** and **jq** installed

### One-Command Setup

```bash
# Clone and setup
cd coder-poc
./scripts/setup.sh
```

### Manual Setup

```bash
# 1. Start the infrastructure
docker compose up -d

# 2. Wait for services to be ready (30-60 seconds)
docker compose logs -f coder

# 3. Add hosts entry (required for OIDC)
echo "127.0.0.1 host.docker.internal" | sudo tee -a /etc/hosts

# 4. Create admin user (first time only)
# Open http://host.docker.internal:7080 and follow the setup wizard

# 5. Install Coder CLI
curl -fsSL https://coder.com/install.sh | sh

# 6. Login to Coder
coder login http://host.docker.internal:7080

# 7. Create the workspace template
cd templates/contractor-workspace
coder templates create contractor-workspace --directory .

# 8. Create your first workspace
coder create my-workspace --template contractor-workspace
```

### Setting Up Git Server (Gitea) and CI (Drone)

```bash
# 1. Setup Gitea with users, repositories, and access control
./scripts/setup-gitea.sh

# 2. Access Gitea at http://localhost:3000
# Login as gitea/admin123

# 3. Drone CI is automatically connected to Gitea
# Access at http://localhost:8080

# 4. Activate python-sample repository in Drone
# - Login to Drone via Gitea
# - Click "Sync" to see repositories
# - Activate python-sample
```

### Testing Access Control

```bash
# Run automated access control tests
./scripts/test-access-control.sh
```

This verifies:
- User authentication
- Repository access permissions
- Read/write/no-access scenarios
- Admin vs regular user capabilities

## Access Information

**Important:** For OIDC/SSO to work correctly, access Coder at `http://host.docker.internal:7080` instead of `localhost:7080`.

| Service | URL | Credentials |
|---------|-----|-------------|
| Dashboard Admin | http://localhost:5050 | admin / admin123 |
| Coder Dashboard | http://host.docker.internal:7080 | admin@example.com / CoderAdmin123! |
| Authentik Admin | http://localhost:9000 | akadmin / admin |
| Gitea (Git Server) | http://localhost:3000 | gitea / admin123 |
| Drone CI | http://localhost:8080 | Via Gitea OAuth |
| AI Gateway | http://localhost:8090 | N/A |
| MinIO Console | http://localhost:9001 | minioadmin / minioadmin |
| Mailpit (Email) | http://localhost:8025 | N/A |
| DevDB (Internal) | devdb:5432 | Trust auth (no password) |
| VS Code (in workspace) | Via Coder Dashboard | N/A |

### Test Users

Run `./scripts/setup-test-users.sh` to create test users across all systems.

**Coder Users** (for workspace access):

| Username | Email | Password |
|----------|-------|----------|
| admin | admin@example.com | CoderAdmin123! |
| contractor1 | contractor1@example.com | Password123! |
| contractor2 | contractor2@example.com | Password123! |
| contractor3 | contractor3@example.com | Password123! |
| readonly | readonly@example.com | Password123! |

**Gitea Users** (for Git access):

| Username | Password | Access Level |
|----------|----------|--------------|
| gitea | admin123 | Administrator (all repos) |
| contractor1 | password123 | python-sample (write), private-project (write), shared-libs (read) |
| contractor2 | password123 | python-sample (write) |
| contractor3 | password123 | shared-libs (write) |
| readonly | password123 | python-sample (read-only) |

> **Note:** The username `admin` is reserved in Gitea. Use `gitea` as the admin account.
> Coder requires stronger passwords (uppercase, special chars) than Gitea.

### Test Database (PostgreSQL)

An internal PostgreSQL database is available for testing workspace database connectivity.

| Property | Value |
|----------|-------|
| Host (from workspace) | testdb |
| Port | 5432 |
| Database | testapp |
| Full access | appuser / testpassword |
| Read-only | contractor / contractor123 |

**Testing connectivity from a workspace:**
```bash
# Full access (from workspace terminal)
psql -h testdb -U appuser -d testapp -c "SELECT * FROM app.users;"

# Read-only access
psql -h testdb -U contractor -d testapp -c "SELECT * FROM app.my_tasks;"

# Python example
python -c "
import psycopg2
conn = psycopg2.connect(host='testdb', database='testapp', user='contractor', password='contractor123')
cur = conn.cursor()
cur.execute('SELECT * FROM app.my_tasks')
print(cur.fetchall())
"
```

**Sample data includes:**
- `app.users` - User accounts (admin, developers, contractors)
- `app.projects` - Sample projects
- `app.tasks` - Task assignments
- `app.my_tasks` - Read-only view for contractors

> **Note:** The test database is internal-only (no host port exposed). It can only be accessed from within the Docker network (workspaces, AI Gateway, etc.)

### Developer Database (DevDB)

Each workspace can have its own database provisioned automatically:

| Type | Naming | Use Case |
|------|--------|----------|
| Individual | `dev_{username}` | Personal development |
| Team | `team_{template_name}` | Shared project database |

**Features:**
- Trust-based auth (no password needed from workspaces)
- Auto-provisioned on workspace start
- Environment variables pre-configured (`$DATABASE_URL`)

**Usage in workspace:**
```bash
# Connection info is pre-set
echo $DATABASE_URL
psql $DATABASE_URL

# Create tables
psql $DATABASE_URL -c "CREATE TABLE users (id SERIAL PRIMARY KEY, name TEXT);"
```

**Admin management:**
```bash
# List all databases
./scripts/manage-devdb.sh list

# Find orphaned databases
./scripts/manage-devdb.sh orphans

# Cleanup old databases
./scripts/manage-devdb.sh cleanup --dry-run
```

See [docs/DATABASE.md](docs/DATABASE.md) for full documentation.

### Authentik (Identity & RBAC)

Authentik provides identity management, RBAC, and approval workflows.

**Access:** http://localhost:9000
**Admin Login:** akadmin / admin (change in .env)

#### Features
- User management with groups and roles
- Approval workflows for access requests
- Self-service portal for contractors
- Audit logging
- Optional Azure AD federation

#### Setting Up Authentik SSO (Automated)

Run the automated SSO setup script:

```bash
./scripts/setup-authentik-sso-full.sh
```

This creates OAuth2 providers and applications for Coder, Gitea, MinIO, and Platform Admin.

**Start with SSO enabled:**

```bash
docker compose -f docker-compose.yml -f docker-compose.sso.yml up -d
```

**Important:** Access Coder at `http://host.docker.internal:7080` (not localhost) for OIDC to work correctly. Add to `/etc/hosts` if needed:

```bash
echo "127.0.0.1 host.docker.internal" | sudo tee -a /etc/hosts
```

### Setting Up Authentik SSO (Manual)

1. **Create OAuth2 Provider in Authentik:**
   - Go to Admin → Applications → Providers → Create
   - Type: OAuth2/OpenID Provider
   - Name: `Coder OIDC`
   - Client ID: `coder`
   - Redirect URIs: `http://host.docker.internal:7080/api/v2/users/oidc/callback`

2. **Create Application:**
   - Go to Admin → Applications → Applications → Create
   - Name: `Coder`
   - Slug: `coder`
   - Provider: Select `Coder OIDC` provider created above

3. **Configure Coder OIDC:**
   Use the docker-compose.sso.yml overlay or add to docker-compose.yml:
   ```yaml
   CODER_OIDC_ISSUER_URL: http://authentik-server:9000/application/o/coder/
   CODER_OIDC_CLIENT_ID: coder
   CODER_OIDC_CLIENT_SECRET: <client-secret-from-authentik>
   CODER_OIDC_SCOPES: openid,profile,email
   # Disable default GitHub login
   CODER_OAUTH2_GITHUB_DEFAULT_PROVIDER_ENABLE: "false"
   ```

4. **Restart Coder with SSO overlay:**
   ```bash
   docker compose -f docker-compose.yml -f docker-compose.sso.yml up -d coder
   ```

#### Creating Contractor Roles

1. **Create Groups:**
   - Go to Directory → Groups → Create
   - Example: `contractors-project-alpha`, `contractors-project-beta`

2. **Create Access Request Flow (optional):**
   - Go to Flows → Create
   - Designation: Enrollment
   - Add stages for justification, manager approval

3. **Assign Users to Groups:**
   - Directory → Users → Select user → Groups tab

## Database Architecture

All services share a single PostgreSQL container with separate databases:

```
┌─────────────────────────────────────────────────────────────┐
│                  PostgreSQL Container                        │
│                                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   coder     │  │  authentik  │  │  platform   │         │
│  │   (db)      │  │    (db)     │  │    (db)     │         │
│  ├─────────────┤  ├─────────────┤  ├─────────────┤         │
│  │ workspaces  │  │ users       │  │ audit_logs  │         │
│  │ templates   │  │ groups      │  │ analytics   │         │
│  │ audit       │  │ roles       │  │ reports     │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│        ↑                ↑                ↑                  │
│     Coder          Authentik        Platform API            │
└─────────────────────────────────────────────────────────────┘
```

| Database | User | Purpose |
|----------|------|---------|
| coder | coder | Workspaces, templates, provisioners |
| authentik | authentik | Users, groups, roles, SSO |
| platform | platform | Centralized audit, analytics (future) |

## Directory Structure

```
coder-poc/
├── docker-compose.yml              # Full infrastructure
├── docker-compose.sso.yml          # SSO overlay (generated by setup script)
├── .env.example                    # Environment variables template
├── .env.combined                   # Combined environment (for production)
├── .env.sso                        # SSO credentials (generated by setup script)
├── README.md                       # This file
├── postgres/
│   └── init.sql                    # Creates all databases and users
├── ai-gateway/                     # Multi-provider AI proxy
│   ├── gateway.py                  # Main application
│   ├── config.yaml                 # Provider configuration
│   ├── Dockerfile                  # Container image
│   └── requirements.txt            # Python dependencies
├── gitea/
│   └── app.ini                     # Gitea Git server configuration
├── testdb/
│   └── init.sql                    # Test database schema and sample data
├── sample-projects/
│   └── python-app/                 # Sample Python project with CI
│       ├── app.py                  # Application code
│       ├── test_app.py             # Test suite
│       ├── requirements.txt        # Dependencies
│       └── .drone.yml              # CI pipeline
├── scripts/
│   ├── setup.sh                    # Automated setup script
│   ├── setup-gitea.sh              # Gitea users & repos setup
│   ├── setup-authentik-sso-full.sh # Full Authentik SSO setup (creates apps + providers)
│   ├── setup-authentik-sso.sh      # Basic SSO setup
│   ├── validate.sh                 # Validation test suite
│   ├── test-access-control.sh      # Access control tests
│   └── cleanup.sh                  # Cleanup script
└── templates/
    └── contractor-workspace/
        ├── main.tf                 # Terraform template
        └── build/
            ├── Dockerfile          # Workspace image
            └── settings.json       # VS Code settings
```

## Usage Guide

### Creating a Workspace

**Via Web UI:**
1. Open http://localhost:7080
2. Click "Create Workspace"
3. Select "contractor-workspace" template
4. Configure options (CPU, Memory, Git repo)
5. Click "Create"

**Via CLI:**
```bash
# Basic workspace
coder create my-workspace --template contractor-workspace

# With options
coder create my-workspace --template contractor-workspace \
  --parameter cpu_cores=4 \
  --parameter memory_gb=8 \
  --parameter git_repo=https://github.com/user/repo.git
```

### Accessing VS Code

1. From the dashboard, click on your workspace
2. Click the "VS Code" button
3. VS Code opens in a new browser tab

### SSH Access

```bash
# Direct SSH
coder ssh my-workspace

# With VS Code Desktop (if installed)
coder config-ssh
code --remote ssh-remote+coder.my-workspace /home/coder/workspace
```

### Managing Workspaces

```bash
# List all workspaces
coder list

# Stop a workspace
coder stop my-workspace

# Start a workspace
coder start my-workspace

# Delete a workspace
coder delete my-workspace

# View workspace logs
coder logs my-workspace
```

## Configuration

### Environment Variables

Copy `.env.example` to `.env` and customize:

```bash
cp .env.example .env
```

| Variable | Default | Description |
|----------|---------|-------------|
| `CODER_PORT` | 7080 | Coder UI port |
| `POSTGRES_PASSWORD` | coderpassword | Database password |
| `CODER_ACCESS_URL` | http://host.docker.internal:7080 | External URL (use host.docker.internal for OIDC) |

### Workspace Template Parameters

| Parameter | Default | Options | Description |
|-----------|---------|---------|-------------|
| `cpu_cores` | 2 | 2, 4 | CPU cores allocated |
| `memory_gb` | 4 | 4, 8 | RAM in GB |
| `disk_size` | 10 | 10, 20, 50 | Persistent storage in GB |
| `git_repo` | (empty) | URL | Repository to clone |
| `dotfiles_repo` | (empty) | URL | Dotfiles to apply |

## Validation

### Infrastructure Validation

Run the validation script to verify everything is working:

```bash
./scripts/validate.sh
```

This tests:
- Infrastructure health (Coder, Gitea, Drone)
- API connectivity
- CLI functionality
- Template availability
- Workspace lifecycle (create, start, stop, delete)
- Tool availability (Git, Node.js, Python)

### Access Control Validation

Test repository access permissions:

```bash
./scripts/test-access-control.sh
```

This tests:
- User authentication against Gitea
- Repository read/write permissions
- Access denial for unauthorized users
- Admin vs non-admin capabilities

### CI Pipeline Validation

Test the CI pipeline end-to-end:

1. Create a workspace as contractor1
2. Clone python-sample: `git clone http://gitea:3000/gitea/python-sample.git`
3. Make a change and push
4. Check Drone CI at http://localhost:8080 for pipeline execution

## CI/CD Pipeline

The PoC includes a complete CI pipeline for Python applications using Drone CI.

### Pipeline Stages

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│ Install  │───▶│  Lint    │───▶│  Type    │───▶│  Test    │───▶│  Build   │
│          │    │ (flake8) │    │  Check   │    │ (pytest) │    │          │
└──────────┘    └──────────┘    │ (mypy)   │    └──────────┘    └──────────┘
                                └──────────┘
```

### Pipeline Features

| Stage | Tool | Purpose |
|-------|------|---------|
| format-check | Black | Code formatting verification |
| lint | Flake8 | Style and error checking |
| type-check | MyPy | Static type analysis |
| test | Pytest | Unit tests with 80% coverage requirement |
| build | Python | Verification run |

### Triggering the Pipeline

The pipeline runs automatically on:
- Push to `main` or `develop` branches
- Push to `feature/*` branches
- Pull requests

---

## Included Tools

The contractor workspace includes:

| Category | Tools |
|----------|-------|
| **Editors** | VS Code (code-server), vim, nano |
| **Languages** | Node.js 20, Python 3.11, Go 1.22 |
| **Package Managers** | npm, yarn, pnpm, pip |
| **Version Control** | Git, GitHub CLI |
| **Utilities** | curl, wget, jq, htop, tree |

### Pre-installed VS Code Extensions

- Python (ms-python.python)
- ESLint (dbaeumer.vscode-eslint)
- Prettier (esbenp.prettier-vscode)
- GitLens (eamodio.gitlens)
- Go (golang.go)

## Customization

### Adding Tools to Workspace Image

Edit `templates/contractor-workspace/build/Dockerfile`:

```dockerfile
# Example: Add Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
```

Then rebuild and push the template:

```bash
cd templates/contractor-workspace
coder templates push contractor-workspace --directory . --yes
```

### Adding VS Code Extensions

Edit `templates/contractor-workspace/build/Dockerfile`:

```dockerfile
RUN code-server --install-extension <extension-id>
```

## Troubleshooting

### Coder won't start

```bash
# Check logs
docker compose logs coder

# Common fix: ensure Docker socket permissions
sudo chmod 666 /var/run/docker.sock
```

### Workspace stuck in "Starting"

```bash
# Check workspace logs
coder logs <workspace-name>

# Force stop and retry
coder stop <workspace-name> --yes
coder start <workspace-name>
```

### Cannot connect to VS Code

1. Ensure workspace is in "Running" state
2. Check if code-server is running:
   ```bash
   coder ssh <workspace> -- pgrep -f code-server
   ```
3. Restart the workspace

### Template creation fails

```bash
# Validate Terraform syntax
cd templates/contractor-workspace
terraform init
terraform validate

# Check Docker can build the image
docker build -t test-workspace ./build
```

## Cleanup

Remove all PoC resources:

```bash
# Keep images
./scripts/cleanup.sh

# Remove everything including images
./scripts/cleanup.sh --images

# Remove CLI config too
./scripts/cleanup.sh --all
```

## Security Notes (PoC vs Production)

| Aspect | PoC | Production |
|--------|-----|------------|
| TLS | Disabled | Required (TLS 1.3) |
| Authentication | Local users | SSO/OIDC required |
| Network | Open | NetworkPolicy isolation |
| Secrets | Environment vars | Vault integration |
| Audit | Basic logs | Full audit trail |

## Next Steps

After validating the PoC:

1. **Security Review**: Conduct security assessment
2. **SSO Integration**: Configure OIDC with corporate IdP
3. **Network Policies**: Implement Kubernetes NetworkPolicies
4. **Audit Logging**: Set up centralized logging
5. **Pilot Program**: Onboard test contractors
6. **Production Deploy**: Migrate to Kubernetes

## References

- [Coder Documentation](https://coder.com/docs)
- [Coder GitHub](https://github.com/coder/coder)
- [Docker Provisioner](https://coder.com/docs/templates/docker)
- [Workspace Templates](https://coder.com/docs/templates)

## Support

For issues with this PoC, check:
1. [Coder Community](https://coder.com/community)
2. [GitHub Issues](https://github.com/coder/coder/issues)
