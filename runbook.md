# runbook.md
# Coder WebIDE PoC – Runbook

## Architecture Overview

### Logical Architecture

Browser  
→ Coder (7080)  
→ Gitea (3000)  
→ MinIO (9001/9002)  
→ Authentik (OIDC, 9000)  
→ PostgreSQL / Redis  

### Workspace Container

- code-server (8080)
- Gitea
- AI Gateway
- Dev DB
- MinIO

---

## Environment Setup

### Host Networking (OIDC Requirement)

Ensure host.docker.internal exists:

grep -q "host.docker.internal" /etc/hosts || \
echo "127.0.0.1 host.docker.internal" | sudo tee -a /etc/hosts

Access URL:

http://host.docker.internal:7080

---

## Service Lifecycle

Startup order:

1. postgres, authentik-redis
2. authentik-server / worker
3. coder, gitea, minio
4. ai-gateway, mailpit

---

## User & Identity Management

### Role Model

- Admin: full control
- App Manager: org and repo creation
- Contractor: restricted visibility

All users must exist in Authentik and Gitea.
Coder users may auto-create via OIDC.

---

### Authentik – Create User

docker exec authentik-server ak shell -c "
from authentik.core.models import User
u=User.objects.create(username='USER',email='EMAIL',name='NAME')
u.set_password('password123'); u.save()
"

---

### Gitea – Create User

curl -X POST http://localhost:3000/api/v1/admin/users \
-u gitea:admin123 \
-H "Content-Type: application/json" \
-d '{"username":"USER","email":"EMAIL","password":"password123","must_change_password":false}'

Restrict contractor:

docker exec gitea sqlite3 /data/gitea/gitea.db \
"UPDATE user SET is_restricted=1, allow_create_organization=0 WHERE name='USER';"

---

## SSO Setup

### Automated Setup (Recommended)

Run the full SSO setup script:

```bash
cd coder-poc
./scripts/setup-authentik-sso-full.sh
```

This creates:
- OAuth2 providers in Authentik (Coder, Gitea, MinIO, Platform Admin)
- Applications linked to providers
- `.env.sso` with OIDC credentials
- `docker-compose.sso.yml` overlay

### Start with SSO

```bash
docker compose -f docker-compose.yml -f docker-compose.sso.yml up -d
```

### Disable Default GitHub Login

The SSO overlay includes:
```yaml
CODER_OAUTH2_GITHUB_DEFAULT_PROVIDER_ENABLE: "false"
```

This removes the default GitHub device flow login button.

### Create Authentik Applications (Manual)

If providers exist but apps don't:

```bash
docker exec authentik-server ak shell -c "
from authentik.providers.oauth2.models import OAuth2Provider
from authentik.core.models import Application

apps = [('Coder', 'coder'), ('Gitea', 'gitea'), ('MinIO', 'minio'), ('Platform Admin', 'platform-admin')]
for name, slug in apps:
    provider = OAuth2Provider.objects.get(name=f'{name} OIDC')
    Application.objects.get_or_create(slug=slug, defaults={'name': name, 'provider': provider})
"
```

---

## Operations

### Health Checks

curl -sf http://localhost:7080/api/v2/buildinfo
curl -sf http://localhost:3000/
curl -sf http://localhost:9000/-/health/ready/

---

### Template Management

docker cp templates/contractor-workspace coder-server:/tmp/contractor-workspace

docker exec \
-e CODER_SESSION_TOKEN="$TOKEN" \
-e CODER_URL="http://localhost:7080" \
coder-server coder templates push contractor-workspace \
--directory /tmp/contractor-workspace --yes

---

## Repository Structure

coder-poc/
- docker-compose.yml
- docker-compose.sso.yml
- .env.sso
- gitea/app.ini
- templates/
- scripts/
- docs/

Skills location: `.claude/skills/`

---

End of runbook.md