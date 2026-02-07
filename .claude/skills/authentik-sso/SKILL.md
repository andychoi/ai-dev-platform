---
name: authentik-sso
description: Authentik identity provider - OIDC/OAuth2 configuration, user management, SSO troubleshooting
---

# Authentik SSO Skill

## Overview

Authentik is the identity provider (IdP) for the Coder WebIDE POC, providing OIDC/OAuth2 authentication for all services.

## Access

| Endpoint | URL |
|----------|-----|
| Admin UI | http://localhost:9000/if/admin/ |
| User Settings | http://localhost:9000/if/user/ |
| Health Check | http://localhost:9000/-/health/ready/ |

## Credentials

### Admin Account

| Field | Value |
|-------|-------|
| Username | `akadmin` |
| Password | `admin` |
| Role | Superuser |

### Test Users

All test users have password: `password123`

| Username | Email | Groups |
|----------|-------|--------|
| `appmanager` | `appmanager@example.com` | App Managers |
| `contractor1` | `contractor1@example.com` | - |
| `contractor2` | `contractor2@example.com` | - |
| `contractor3` | `contractor3@example.com` | - |
| `readonly` | `readonly@example.com` | - |

## OAuth2/OIDC Providers

### Configured Applications

| Application | Client ID | Redirect URI |
|-------------|-----------|--------------|
| Coder | `coder` | `https://host.docker.internal:7443/api/v2/users/oidc/callback` |
| Gitea | `gitea` | `http://localhost:3000/user/oauth2/Authentik/callback` |
| MinIO | `minio` | `http://localhost:9001/oauth_callback` |
| Platform Admin | `platform-admin` | `http://localhost:5050/auth/callback` |
| LiteLLM | `litellm` | `http://localhost:4000/sso/callback` |

### OIDC Endpoints

| Endpoint | URL Pattern |
|----------|-------------|
| Discovery | `http://host.docker.internal:9000/application/o/{app}/.well-known/openid-configuration` |
| Authorization | `http://host.docker.internal:9000/application/o/authorize/` |
| Token | `http://host.docker.internal:9000/application/o/token/` |
| User Info | `http://host.docker.internal:9000/application/o/userinfo/` |
| End Session | `http://localhost:9000/application/o/{app}/end-session/` |

**Note:** Always use `host.docker.internal:9000` — it works for both containers and browser. Never use `authentik-server:9000` (browser can't resolve Docker service names).

## Managing Users

### Create User

```bash
docker exec authentik-server ak shell -c "
from authentik.core.models import User
user = User.objects.create(
    username='newuser',
    email='newuser@example.com',
    name='New User',
    is_active=True
)
user.set_password('password123')
user.save()
print(f'Created: {user.username}')
"
```

### List Users

```bash
docker exec authentik-server ak shell -c "
from authentik.core.models import User
for u in User.objects.filter(is_active=True):
    print(f'{u.username}: {u.email}')
"
```

### Reset Password

```bash
docker exec authentik-server ak shell -c "
from authentik.core.models import User
user = User.objects.get(username='username')
user.set_password('newpassword')
user.save()
print('Password updated')
"
```

### Delete User

```bash
docker exec authentik-server ak shell -c "
from authentik.core.models import User
User.objects.filter(username='username').delete()
print('User deleted')
"
```

## Managing Groups

### Create Group

```bash
docker exec authentik-server ak shell -c "
from authentik.core.models import Group
group, created = Group.objects.get_or_create(name='New Group')
print(f'Group: {group.name}, created: {created}')
"
```

### Add User to Group

```bash
docker exec authentik-server ak shell -c "
from authentik.core.models import User, Group
user = User.objects.get(username='username')
group = Group.objects.get(name='Group Name')
user.ak_groups.add(group)
print(f'Added {user.username} to {group.name}')
"
```

## Managing OAuth2 Providers

### List Providers

```bash
docker exec authentik-server ak shell -c "
from authentik.providers.oauth2.models import OAuth2Provider
for p in OAuth2Provider.objects.all():
    print(f'{p.name}: client_id={p.client_id}')
    print(f'  redirect_uris: {p.redirect_uris}')
"
```

### Update Redirect URI

```bash
docker exec authentik-server ak shell -c "
from authentik.providers.oauth2.models import OAuth2Provider
p = OAuth2Provider.objects.get(name='Provider Name')
p.redirect_uris = '''http://localhost:3000/callback
http://localhost:3000/'''
p.save()
print('Updated')
"
```

### Get Client Secret

```bash
docker exec authentik-server ak shell -c "
from authentik.providers.oauth2.models import OAuth2Provider
p = OAuth2Provider.objects.get(name='Gitea OIDC')
print(f'Client ID: {p.client_id}')
print(f'Client Secret: {p.client_secret}')
"
```

## API Token Management

### Create API Token

```bash
docker exec authentik-server ak shell -c "
from authentik.core.models import Token, User
user = User.objects.get(username='akadmin')
token, created = Token.objects.get_or_create(
    identifier='api-token',
    defaults={'user': user, 'intent': 'api', 'expiring': False}
)
print(f'Token: {token.key}')
"
```

### Use API

```bash
AUTHENTIK_TOKEN="your-token-here"
curl -s "http://localhost:9000/api/v3/core/users/" \
  -H "Authorization: Bearer ${AUTHENTIK_TOKEN}"
```

## Single Sign-On Flow

```
┌──────────┐     ┌──────────┐     ┌───────────┐
│  User    │     │  Service │     │ Authentik │
│ Browser  │     │ (Gitea)  │     │   (IdP)   │
└────┬─────┘     └────┬─────┘     └─────┬─────┘
     │                │                  │
     │ Click "Login   │                  │
     │ with Authentik"│                  │
     │───────────────▶│                  │
     │                │                  │
     │                │ Redirect to      │
     │◀───────────────│ /authorize       │
     │                                   │
     │ Follow redirect                   │
     │──────────────────────────────────▶│
     │                                   │
     │                   Login page      │
     │◀──────────────────────────────────│
     │                                   │
     │ Enter credentials                 │
     │──────────────────────────────────▶│
     │                                   │
     │                   Redirect with   │
     │◀────────────────── auth code      │
     │                                   │
     │ Follow redirect  │                │
     │─────────────────▶│                │
     │                  │                │
     │                  │ Exchange code  │
     │                  │ for token      │
     │                  │───────────────▶│
     │                  │                │
     │                  │◀───────────────│
     │                  │ Access token   │
     │                  │                │
     │    Session       │                │
     │◀─────────────────│                │
     │    created       │                │
```

## Single Logout Flow

When configured, signing out of a service also signs out of Authentik:

1. User clicks "Sign Out" in Gitea
2. Gitea redirects to `authentik/end-session/?post_logout_redirect_uri=...`
3. Authentik ends the SSO session
4. Authentik redirects back to Gitea
5. User must re-authenticate for any service

## Troubleshooting

### Redirect URI Mismatch

Error: "The request fails due to a missing, invalid, or mismatching redirection URI"

**Solution:**
```bash
# Check what URI the service is sending
# (visible in error URL as redirect_uri parameter)

# Update Authentik provider to match
docker exec authentik-server ak shell -c "
from authentik.providers.oauth2.models import OAuth2Provider
p = OAuth2Provider.objects.get(name='Provider Name')
p.redirect_uris = 'http://correct/callback/url'
p.save()
"
```

### User Exists but Can't Login

Check if user is active:
```bash
docker exec authentik-server ak shell -c "
from authentik.core.models import User
u = User.objects.get(username='username')
print(f'Active: {u.is_active}')
"
```

### Session Not Ending

Ensure end-session endpoint is accessible via localhost:
- Services should redirect to `http://localhost:9000/...` (not `authentik-server:9000`)

### View Logs

```bash
docker logs authentik-server 2>&1 | tail -50
docker logs authentik-worker 2>&1 | tail -50
```

## Backup

### Export Users

```bash
docker exec authentik-server ak shell -c "
import json
from authentik.core.models import User
users = [{
    'username': u.username,
    'email': u.email,
    'name': u.name,
    'is_active': u.is_active
} for u in User.objects.all()]
print(json.dumps(users, indent=2))
"
```

### Database Backup

```bash
docker exec authentik-postgresql pg_dump -U authentik authentik > authentik-backup.sql
```
