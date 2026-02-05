---
name: gitea
description: Gitea Git server - repository management, user permissions, OIDC integration with Authentik
---

# Gitea Git Server Skill

## Overview

Gitea is the Git server for the Coder WebIDE POC, providing repository hosting with OIDC authentication via Authentik.

## Access

| Endpoint | URL |
|----------|-----|
| Web UI | http://localhost:3000 |
| Git HTTP | http://gitea:3000 (internal) |
| API | http://localhost:3000/api/v1 |

## Credentials

### Admin Account

| Field | Value |
|-------|-------|
| Username | `gitea` |
| Password | `admin123` |
| Role | Site Administrator |

### Test Users

| Username | Password | Role | Restricted | Can Create Org |
|----------|----------|------|------------|----------------|
| `appmanager` | `password123` | App Manager | No | Yes |
| `contractor1` | `password123` | Contractor | Yes | No |
| `contractor2` | `password123` | Contractor | Yes | No |
| `contractor3` | `password123` | Contractor | Yes | No |
| `readonly` | `password123` | Read-only | Yes | No |

## Authentication Configuration

### OIDC/SSO (Authentik)

Gitea is configured with Authentik as an OAuth2 provider:

| Setting | Value |
|---------|-------|
| Provider Type | OpenID Connect |
| Authentication Name | `Authentik` |
| Client ID | `gitea` |
| Discovery URL | `http://authentik-server:9000/application/o/gitea/.well-known/openid-configuration` |
| Callback URL | `http://localhost:3000/user/oauth2/Authentik/callback` |

### Single Logout (SLO)

Configured via `app.ini`:
```ini
[service]
LOGOUT_REDIRECT_URL = http://localhost:9000/application/o/gitea/end-session/?post_logout_redirect_uri=http%3A%2F%2Flocalhost%3A3000%2F
```

When users sign out of Gitea, they are also signed out of Authentik.

### Auto-Registration

```ini
[oauth2_client]
ENABLE_AUTO_REGISTRATION = true
ACCOUNT_LINKING = auto
USERNAME = nickname
```

New users signing in via SSO are automatically created and linked.

## Permission Model

### User Types

1. **Admin** (`is_admin=1`): Full access, can manage users/orgs/repos
2. **Regular** (`is_restricted=0`): Can create repos, see public content
3. **Restricted** (`is_restricted=1`): Can only see repos explicitly granted

### Default Settings (app.ini)

```ini
[service]
DEFAULT_ALLOW_CREATE_ORGANIZATION = false
DEFAULT_USER_IS_RESTRICTED = true
```

New users are restricted by default; only admins can create organizations.

## Managing Users

### Create User (API)

```bash
curl -X POST "http://localhost:3000/api/v1/admin/users" \
  -u "gitea:admin123" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "newuser",
    "email": "newuser@example.com",
    "password": "password123",
    "must_change_password": false
  }'
```

### Set User Permissions (SQLite)

```bash
# Make user restricted (contractor)
docker exec gitea sqlite3 /data/gitea/gitea.db \
  "UPDATE user SET is_restricted=1, allow_create_organization=0 WHERE name='username';"

# Make user elevated (app manager)
docker exec gitea sqlite3 /data/gitea/gitea.db \
  "UPDATE user SET is_restricted=0, allow_create_organization=1 WHERE name='username';"
```

### List Users

```bash
docker exec gitea sqlite3 /data/gitea/gitea.db \
  "SELECT id, name, is_admin, is_restricted, allow_create_organization FROM user WHERE type=0;"
```

## Repository Management

### Create Repository

```bash
curl -X POST "http://localhost:3000/api/v1/user/repos" \
  -u "gitea:admin123" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-project",
    "description": "Project description",
    "private": true,
    "auto_init": true
  }'
```

### Add Collaborator

```bash
curl -X PUT "http://localhost:3000/api/v1/repos/owner/repo/collaborators/username" \
  -u "gitea:admin123" \
  -H "Content-Type: application/json" \
  -d '{"permission": "write"}'
```

Permissions: `read`, `write`, `admin`

## Workspace Integration

### Git Credential Configuration

In Coder workspaces, Git credentials are configured automatically:

```bash
# Stored in ~/.git-credentials
http://username:password@gitea:3000
```

### Clone from Workspace

```bash
git clone http://gitea:3000/owner/repo.git
```

## Configuration Files

### app.ini Location

- Container path: `/data/gitea/conf/app.ini`
- Host path: `./gitea/app.ini`

### Key Sections

```ini
[server]
ROOT_URL = http://localhost:3000/

[service]
DISABLE_REGISTRATION = false
DEFAULT_ALLOW_CREATE_ORGANIZATION = false
DEFAULT_USER_IS_RESTRICTED = true
LOGOUT_REDIRECT_URL = http://localhost:9000/...

[oauth2_client]
ENABLE_AUTO_REGISTRATION = true
ACCOUNT_LINKING = auto

[openid]
ENABLE_OPENID_SIGNIN = false
ENABLE_OPENID_SIGNUP = false
```

## Troubleshooting

### SSO Login Fails

1. Check redirect URI matches Authentik configuration:
   ```bash
   docker exec authentik-server ak shell -c "
   from authentik.providers.oauth2.models import OAuth2Provider
   p = OAuth2Provider.objects.get(name='Gitea OIDC')
   print(p.redirect_uris)
   "
   ```

2. Verify authentication source in Gitea:
   ```bash
   docker exec gitea sqlite3 /data/gitea/gitea.db \
     "SELECT name, cfg FROM login_source;"
   ```

### User Can't See Repos

1. Check if user is restricted:
   ```bash
   docker exec gitea sqlite3 /data/gitea/gitea.db \
     "SELECT is_restricted FROM user WHERE name='username';"
   ```

2. Add user as collaborator or org member via Admin UI

### Restart Gitea

```bash
docker compose restart gitea
```

## Database Backup

```bash
# Backup
docker exec gitea sqlite3 /data/gitea/gitea.db ".backup '/data/gitea/backup.db'"

# Copy to host
docker cp gitea:/data/gitea/backup.db ./gitea-backup.db
```
