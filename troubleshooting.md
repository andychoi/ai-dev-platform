# troubleshooting.md
# Coder WebIDE PoC – Troubleshooting

## Login & SSO Issues

### OIDC Login Fails for Existing User

Cause: login_type=password

Detect:

docker exec postgres psql -U coder -d coder -c \
"SELECT email, login_type FROM users;"

Fix:

docker exec postgres psql -U coder -d coder -c \
"UPDATE users SET login_type='oidc' WHERE email='user@example.com';"

---

### Redirect URI Error

Cause: mismatch between CODER_ACCESS_URL and Authentik config.

Configure both:

http://localhost:7080/api/v2/users/oidc/callback  
http://host.docker.internal:7080/api/v2/users/oidc/callback

---

## Workspace & Agent Issues

### Agent Never Connects

Cause: CODER_ACCESS_URL=localhost

Fix:

CODER_ACCESS_URL=http://host.docker.internal:7080

Recreate container and workspaces:

docker compose up -d coder

---

### Terminal Stuck “Trying to connect…”

Cause: shell is /bin/false

Fix in Dockerfile:

RUN useradd -m -s /bin/bash -u 1001 coder && usermod -s /bin/bash coder

---

### Agent START_ERROR (docker ps)

Cause: devcontainer detection enabled

Fix in template:

resource "coder_agent" "main" {
  env = {
    CODER_AGENT_DEVCONTAINERS_ENABLE = "false"
  }
}

---

## Template & Config Issues

### Template Changes Not Applied

Required:
1. Push template
2. Delete and recreate workspaces

---

### .env Changes Ignored

Cause: docker compose restart

Fix:

docker compose up -d <service>

---

## OAuth Noise

### Disable Default GitHub Login

CODER_OAUTH2_GITHUB_DEFAULT_PROVIDER_ENABLE: "false"

---

End of troubleshooting.md