# Authentik SSO Integration Guide

This guide covers setting up Single Sign-On (SSO) for the Coder WebIDE Platform using Authentik, while maintaining local login as a fallback.

## Architecture

```
                    ┌─────────────────┐
                    │    Authentik    │
                    │   (SSO Provider)│
                    └────────┬────────┘
                             │ OIDC/OAuth2
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
   ┌─────────┐         ┌─────────┐         ┌─────────┐
   │  Coder  │         │  Gitea   │         │  MinIO  │
   │ Primary │         │ Primary │         │ Primary │
   │  + Local│         │  + Local│         │  + Local│
   └─────────┘         └─────────┘         └─────────┘
```

## Authentication Strategy: SSO + Local Fallback

Each service supports dual authentication:
- **Primary**: Authentik SSO (OIDC/OAuth2)
- **Fallback**: Local admin accounts (for emergency access if Authentik is down)

## Quick Start

### 0. Add Required hosts Entry (One-time)

**CRITICAL:** Your browser needs to resolve `authentik-server` for SSO callbacks:

```bash
sudo sh -c 'echo "127.0.0.1    authentik-server" >> /etc/hosts'
```

Also ensure `host.docker.internal` is resolvable (required for Coder):
```bash
# Check if already present
grep host.docker.internal /etc/hosts || echo "127.0.0.1 host.docker.internal" | sudo tee -a /etc/hosts
```

### 1. Run SSO Setup Script

```bash
# Option A: Automated setup (recommended)
./scripts/setup-authentik-sso-full.sh

# Option B: Manual setup
# Create API token (one-time)
docker exec authentik-server ak shell -c "
from authentik.core.models import Token, User
user = User.objects.get(username='akadmin')
token, _ = Token.objects.get_or_create(
    identifier='platform-admin-api',
    defaults={'user': user, 'intent': 'api', 'expiring': False}
)
print(f'TOKEN:{token.key}')
"

# Run basic setup script
export AUTHENTIK_TOKEN="<token-from-above>"
./scripts/setup-authentik-sso.sh
```

### 2. Access Authentik Admin

- URL: http://localhost:9000/if/admin/
- Login: `akadmin` / `admin`

## Service Configuration

### Coder (OIDC)

1. **Create OAuth2 Provider in Authentik**:
   - Go to: Applications → Providers → Create
   - Type: OAuth2/OpenID Provider
   - Name: `Coder OIDC`
   - Client ID: `coder` (or auto-generated)
   - Client Secret: (auto-generated, copy this)
   - Redirect URIs (add BOTH for cookie compatibility):
     ```
     http://localhost:7080/api/v2/users/oidc/callback
     http://host.docker.internal:7080/api/v2/users/oidc/callback
     ```
   - Signing Key: Select default

2. **Link to Application**:
   - Go to: Applications → Applications → Coder WebIDE
   - Set Provider: `Coder OIDC`

3. **Configure Coder** (docker-compose.yml):
   ```yaml
   environment:
     # SSO via Authentik
     CODER_OIDC_ISSUER_URL: "http://authentik-server:9000/application/o/coder/"
     CODER_OIDC_CLIENT_ID: "<client-id>"
     CODER_OIDC_CLIENT_SECRET: "<client-secret>"
     CODER_OIDC_ALLOW_SIGNUPS: "true"
     CODER_OIDC_EMAIL_DOMAIN: ""  # Allow all domains

     # IMPORTANT: Keep local login as fallback
     CODER_DISABLE_PASSWORD_AUTH: "false"
   ```

4. **Local Fallback Account**:
   - Email: `admin@example.com`
   - Password: `CoderAdmin123!`

### Gitea (OAuth2)

1. **Create OAuth2 Provider in Authentik**:
   - Type: OAuth2/OpenID Provider
   - Name: `Gitea OIDC`
   - Client ID: `gitea`
   - Redirect URIs: `http://localhost:3000/user/oauth2/Authentik/callback`

   **Note:** The callback URL path includes the Authentication Name you set in Gitea (case-sensitive).

2. **Configure Gitea Admin** (http://localhost:3000/admin/auths/new):
   - Authentication Type: OAuth2
   - Provider: OpenID Connect
   - **Authentication Name: `Authentik`** (this becomes part of the callback URL)
   - Client ID: `gitea` (or value from Authentik)
   - Client Secret: `<from-authentik>`
   - OpenID Connect Auto Discovery URL: `http://authentik-server:9000/application/o/gitea/.well-known/openid-configuration`

3. **Local Fallback Account**:
   - Username: `gitea`
   - Password: `admin123`

### MinIO (OIDC)

1. **Create OAuth2 Provider in Authentik**:
   - Name: `MinIO OIDC`
   - Client ID: `minio`
   - Redirect URIs: `http://localhost:9001/oauth_callback`

2. **Configure MinIO** (via docker-compose.sso.yml or environment):
   ```yaml
   environment:
     MINIO_IDENTITY_OPENID_CONFIG_URL: "http://authentik-server:9000/application/o/minio/.well-known/openid-configuration"
     MINIO_IDENTITY_OPENID_CLIENT_ID: "minio"
     MINIO_IDENTITY_OPENID_CLIENT_SECRET: "<client-secret>"
     MINIO_IDENTITY_OPENID_CLAIM_NAME: "policy"
     MINIO_IDENTITY_OPENID_SCOPES: "openid,profile,email"
     MINIO_IDENTITY_OPENID_REDIRECT_URI: "http://localhost:9001/oauth_callback"

     # IMPORTANT: Keep root user for fallback
     MINIO_ROOT_USER: "minioadmin"
     MINIO_ROOT_PASSWORD: "minioadmin"
   ```

3. **Local Fallback Account**:
   - Username: `minioadmin`
   - Password: `minioadmin`

### Platform Admin (OIDC)

Platform Admin supports both OIDC SSO and local authentication fallback.

1. **Create OAuth2 Provider in Authentik**:
   - Name: `Platform Admin OIDC`
   - Client ID: `platform-admin`
   - Redirect URIs: `http://localhost:5050/auth/callback`

2. **Configure Platform Admin** (via docker-compose.sso.yml or environment):
   ```yaml
   environment:
     OIDC_ENABLED: "true"
     OIDC_ISSUER_URL: "http://authentik-server:9000/application/o/platform-admin/"
     OIDC_CLIENT_ID: "platform-admin"
     OIDC_CLIENT_SECRET: "<client-secret>"
     LOCAL_AUTH_ENABLED: "true"
   ```

3. **Local Fallback Account**:
   - Username: `admin`
   - Password: `admin123`

### Drone CI

Drone authenticates through Gitea, so it inherits Gitea' authentication:
- If Gitea uses Authentik SSO → Drone uses SSO
- Gitea local login → Drone local login

## Enabling SSO with Docker Compose

After running `setup-authentik-sso-full.sh`, two files are generated:
- `.env.sso` - Environment variables with OAuth credentials
- `docker-compose.sso.yml` - Compose override with SSO configuration

### Start Services with SSO

```bash
# Start Coder and MinIO with SSO enabled
docker compose -f docker-compose.yml -f docker-compose.sso.yml up -d coder minio

# Or start all services
docker compose -f docker-compose.yml -f docker-compose.sso.yml up -d
```

### Verify SSO is Active

- Coder: Visit http://host.docker.internal:7080 - should show "Login with OIDC" option
- MinIO: Visit http://localhost:9001 - should show "Login with SSO" option
- Platform Admin: Visit http://localhost:5050 - should show "Sign in with Authentik SSO" option

## Emergency Access (Authentik Down)

If Authentik is unavailable, use these local accounts:

| Service | Username | Password |
|---------|----------|----------|
| Coder | admin@example.com | CoderAdmin123! |
| Gitea | gitea | admin123 |
| MinIO | minioadmin | minioadmin |
| Platform Admin | admin | admin123 |
| Authentik | akadmin | admin |

## User Provisioning

### Option 1: Manual in Authentik
Create users in Authentik Admin → Directory → Users

### Option 2: LDAP/AD Sync
Configure Authentik to sync from corporate directory:
- Authentik Admin → Directory → Federation → LDAP Sources

### Option 3: Self-Registration
Enable in Authentik flows if allowing contractors to self-register.

## Troubleshooting

### SSO Login Fails
1. Check Authentik is running: `curl http://localhost:9000/-/health/ready/`
2. Verify redirect URIs match exactly (case-sensitive!)
3. Check service can reach Authentik (Docker network)
4. Use local fallback account while debugging

### Cookie "oauth_state" Error
This happens when the browser domain doesn't match the redirect domain:
- **Always access Coder via `http://host.docker.internal:7080`** (NOT `localhost:7080`)
- Add both redirect URIs to Authentik provider (localhost AND host.docker.internal)
- Ensure `/etc/hosts` has entry for `host.docker.internal`

### Browser Can't Resolve authentik-server
The SSO callback redirects to `authentik-server`. Add hosts entry:
```bash
sudo sh -c 'echo "127.0.0.1    authentik-server" >> /etc/hosts'
```

### Coder User login_type Mismatch
Users created with password login cannot use OIDC:
```bash
# Check user login type
docker exec coder-server coder users list --column username,login_type

# Delete and recreate via OIDC if needed
docker exec coder-server coder users delete <username>
# Then login via OIDC to recreate
```

### Can't Access Authentik Admin
Use recovery mode:
```bash
docker exec -it authentik-server ak create_recovery_key 10 akadmin
# Use the generated link to reset access
```

### Service Can't Reach Authentik
Ensure services use internal Docker hostname:
- Internal (container-to-container): `http://authentik-server:9000`
- External (browser redirects): `http://localhost:9000`

## Security Considerations

1. **Separate Admin Accounts**: Use different admin accounts for SSO vs local fallback
2. **Strong Passwords**: Change default passwords in production
3. **Network Isolation**: Authentik should only be accessible from trusted networks
4. **Token Rotation**: Rotate API tokens periodically
5. **Audit Logging**: Enable Authentik audit logs for compliance

## API Token (for automation)

Store securely - this token has admin access:
```bash
export AUTHENTIK_TOKEN="<your-token>"
```

Use with API calls:
```bash
curl -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
  http://localhost:9000/api/v3/core/users/
```
