# HTTPS Architecture - Dev Platform PoC

How TLS is implemented in the PoC, why it's needed, and an evaluation of alternative approaches (including Traefik). This document covers architecture decisions; for operational procedures (cert regeneration, troubleshooting), see [ADMIN-HOWTO.md](ADMIN-HOWTO.md#4-https--tls-configuration).

## Table of Contents

1. [Why HTTPS Is Required](#1-why-https-is-required)
2. [Current Architecture: Coder Native TLS](#2-current-architecture-coder-native-tls)
3. [Traffic Flow](#3-traffic-flow)
4. [Service Protocol Map](#4-service-protocol-map)
5. [Workspace Agent TLS Trust](#5-workspace-agent-tls-trust)
6. [Traefik Evaluation](#6-traefik-evaluation)
7. [Option A: Traefik for Coder Only](#7-option-a-traefik-for-coder-only)
8. [Option B: Traefik as Unified HTTPS Gateway](#8-option-b-traefik-as-unified-https-gateway)
9. [Option C: Traefik for Browser-Facing Services](#9-option-c-traefik-for-browser-facing-services)
10. [Option D: No Traefik (Current)](#10-option-d-no-traefik-current)
11. [Comparison Matrix](#11-comparison-matrix)
12. [Coder + Traefik Gotchas](#12-coder--traefik-gotchas)
13. [Recommendation](#13-recommendation)
14. [When to Revisit](#14-when-to-revisit)

---

## 1. Why HTTPS Is Required

HTTPS is not optional in this stack. The root cause is the **browser secure context** requirement.

**Problem:** `http://host.docker.internal:7080` is NOT a secure context because `host.docker.internal` is neither `localhost` nor served over HTTPS. Without a secure context:

- `crypto.subtle` API is `undefined`
- code-server cannot generate webview iframe nonces
- **ALL** extension webviews render as blank panels (Roo Code, GitLens, etc.)
- This affects every VS Code extension with a webview, not just one

**Solution:** Serve Coder over HTTPS. The browser then treats the origin as a secure context, `crypto.subtle` works, and extension webviews render correctly.

**Diagnosis:** Open browser console on the Coder page:
```javascript
window.isSecureContext   // must be true
crypto.subtle            // must NOT be undefined
```

---

## 2. Current Architecture: Coder Native TLS

Coder handles TLS directly — no external reverse proxy.

**Configuration** (in `docker-compose.yml` / `.env`):

```bash
CODER_TLS_ENABLE=true
CODER_TLS_ADDRESS=0.0.0.0:7443
CODER_TLS_CERT_FILE=/certs/coder.crt
CODER_TLS_KEY_FILE=/certs/coder.key
CODER_TLS_MIN_VERSION=tls12
CODER_SECURE_AUTH_COOKIE=true
CODER_ACCESS_URL=https://host.docker.internal:7443
```

**Certificate:**

- Self-signed, RSA 2048-bit, SHA-256, 365-day validity
- Subject: `CN=host.docker.internal`
- SANs: `DNS:host.docker.internal`, `DNS:localhost`, `IP:127.0.0.1`
- Location: `coder-poc/certs/coder.crt` and `coder-poc/certs/coder.key`

**HTTP API remains active** on port 7080 for scripts and automation. `CODER_REDIRECT_TO_ACCESS_URL` is disabled so both ports work simultaneously.

---

## 3. Traffic Flow

### Browser Access (HTTPS)

```
Browser
  │
  │ HTTPS :7443
  ▼
Coder Server (native TLS termination)
  │
  │ Internal HTTP (Docker network)
  ├──▶ code-server :8080 (inside workspace container)
  ├──▶ LiteLLM :4000
  ├──▶ Gitea :3000
  └──▶ Authentik :9000
```

### Workspace Agent (HTTPS)

```
Workspace Container
  │
  │ HTTPS (trusts self-signed cert via update-ca-certificates)
  ▼
Coder Server :7443
```

### Script / Automation (HTTP)

```
Host machine or coder-server container
  │
  │ HTTP :7080
  ▼
Coder Server (API only, no browser access)
```

---

## 4. Service Protocol Map

| Service | Host Port | Protocol | TLS | Browser-Facing |
|---------|-----------|----------|-----|----------------|
| Coder (browser) | 7443 | HTTPS | Native | Yes |
| Coder (API) | 7080 | HTTP | No | No (scripts) |
| Authentik | 9000 | HTTP | No | Yes |
| Gitea | 3000 | HTTP | No | Yes |
| LiteLLM | 4000 | HTTP | No | Yes (admin UI) |
| Platform Admin | 5050 | HTTP | No | Yes |
| MinIO Console | 9001 | HTTP | No | Yes |
| MinIO S3 API | 9002 | HTTP | No | No |
| Key Provisioner | 8100 | HTTP | No | No |
| Langfuse | 3100 | HTTP | No | Yes |
| Mailpit | 8025 | HTTP | No | Yes |
| Portal | 3333 | HTTP | No | Yes |

Only Coder uses HTTPS. All other services are HTTP on the Docker network.

---

## 5. Workspace Agent TLS Trust

Workspace containers must trust the self-signed certificate so the Coder agent can connect back to the server over HTTPS.

The template handles this automatically:

1. **Volume mount:** Host cert directory → `/certs` (read-only)
2. **Entrypoint:** Runs `sudo update-ca-certificates` before agent init
3. **Environment variables:**
   - `SSL_CERT_FILE=/certs/coder.crt`
   - `NODE_EXTRA_CA_CERTS=/certs/coder.crt`

This means all processes in the workspace (git, curl, node, python, the Coder agent itself) trust the self-signed certificate.

---

## 6. Traefik Evaluation

Traefik is a reverse proxy that auto-discovers services via Docker labels. It watches the Docker socket for container events and dynamically generates routing rules. TLS termination happens at Traefik, so backends stay plain HTTP.

The following sections evaluate four approaches.

---

## 7. Option A: Traefik for Coder Only

Replace Coder's native TLS with Traefik. Other services unchanged.

```
Browser ──HTTPS:443──▶ Traefik ──HTTP:7080──▶ Coder
Browser ──HTTP:9000──▶ Authentik  (unchanged)
Browser ──HTTP:3000──▶ Gitea      (unchanged)
```

**Changes required:**
- Add Traefik container with the existing self-signed cert
- Disable `CODER_TLS_ENABLE` and related env vars
- Update `CODER_ACCESS_URL` to `https://host.docker.internal` (port 443)
- Update Authentik redirect URIs for the new callback URL
- Configure Traefik WebSocket support with infinite read timeout
- Update workspace agent cert trust to use Traefik's cert

| Pros | Cons |
|------|------|
| Cleaner URL (no `:7443`) | Adds a container for marginal benefit |
| Standard port 443 | WebSocket proxying needs careful configuration |
| Foundation to expand later | Still only Coder has HTTPS |
| | Workspace agent → Coder path adds a network hop |
| | OIDC redirect URIs must be updated |

---

## 8. Option B: Traefik as Unified HTTPS Gateway

Single HTTPS entry point for all browser-facing services. Subdomain-based routing.

```
Browser ──HTTPS:443──▶ Traefik
                        ├── coder.dev.local    → Coder :7080
                        ├── gitea.dev.local    → Gitea :3000
                        ├── auth.dev.local     → Authentik :9000
                        ├── ai.dev.local       → LiteLLM :4000
                        ├── admin.dev.local    → Platform Admin :5000
                        ├── minio.dev.local    → MinIO Console :9001
                        ├── s3.dev.local       → MinIO API :9002
                        ├── logs.dev.local     → Langfuse :3000
                        └── mail.dev.local     → Mailpit :8025
```

**Changes required:**
- Add Traefik container with wildcard cert for `*.dev.local`
- Add Docker labels to every service
- Set up local DNS: either `/etc/hosts` entries for each subdomain, or dnsmasq for `*.dev.local`
- Regenerate cert with SAN `*.dev.local`
- Update ALL OIDC configuration (issuer URLs, redirect URIs, cookie domains)
- Update `CODER_ACCESS_URL`, all script URLs, documentation
- Stop exposing individual host ports (optional but desired)

| Pros | Cons |
|------|------|
| Single port 443 — no memorizing 12+ ports | Requires local DNS setup (dnsmasq or `/etc/hosts`) |
| HTTPS everywhere — all services get secure context | Significant configuration effort |
| Clean URLs: `https://coder.dev.local` | All OIDC redirect URIs must be updated |
| Traefik dashboard for traffic visibility | Workspace agent communication gets more complex |
| Production-representative architecture | Debugging harder (extra proxy layer for all traffic) |
| Fewer exposed host ports | Coder workspace proxying through two proxy layers |

---

## 9. Option C: Traefik for Browser-Facing Services

Traefik handles TLS for browser-facing services. Internal/agent communication stays direct HTTP.

```
Browser ──HTTPS:443──▶ Traefik
                        ├── host.docker.internal         → Coder :7080
                        ├── host.docker.internal/gitea   → Gitea :3000
                        ├── host.docker.internal/admin   → Platform Admin :5000
                        └── host.docker.internal/auth    → Authentik :9000

Workspace Agent ──HTTP:7080──▶ Coder  (internal, bypasses Traefik)
LiteLLM, Key Provisioner      (internal only, no Traefik)
```

**Changes required:**
- Add Traefik with path-based routing rules
- Disable Coder native TLS
- Verify Gitea and Authentik can operate under a subpath prefix
- Split agent traffic (internal HTTP) from browser traffic (Traefik HTTPS)

| Pros | Cons |
|------|------|
| HTTPS for browser-facing services | Path-based routing conflicts with Coder's own routing |
| No local DNS changes needed | Gitea, Authentik don't support arbitrary subpath prefixes |
| Agents bypass Traefik (simpler, faster) | Mixed model: some traffic through Traefik, some direct |
| | OIDC issuer URL and redirect URIs need updating |

**Warning:** Path-based routing is fragile here. Coder uses its own path-based routing for workspace apps (e.g., `/apps/{workspace}/code-server`). Gitea and Authentik are not designed to run under a subpath prefix without explicit configuration, and Authentik in particular does not support this.

---

## 10. Option D: No Traefik (Current)

The existing Coder native TLS with `host.docker.internal:7443`.

| Pros | Cons |
|------|------|
| Already working and proven | Non-standard port `:7443` |
| No extra container or configuration | Only Coder has HTTPS |
| Simple mental model | 12+ ports to remember |
| Workspace agents trust one cert | Not production-representative |
| No WebSocket proxy concerns | Other browser-facing services are HTTP |
| Zero OIDC changes needed | |

---

## 11. Comparison Matrix

| Criteria | A: Coder Only | B: Full Gateway | C: Partial | D: Current |
|----------|:---:|:---:|:---:|:---:|
| Implementation effort | Low | High | Medium | None |
| HTTPS coverage | Coder only | All services | Browser services | Coder only |
| Port simplification | Minimal | Full (443 only) | Partial | None |
| WebSocket risk | Medium | Medium | Medium | None |
| OIDC impact | Low | High | Medium | None |
| Production readiness | Low | High | Medium | Low |
| PoC-appropriate | No | No | No | Yes |
| Debugging complexity | +1 layer | +1 layer | +1 layer | Baseline |

---

## 12. Coder + Traefik Gotchas

If Traefik is introduced, these Coder-specific issues must be addressed:

### WebSocket Timeouts

Coder terminals are long-lived WebSocket connections. Traefik's default read timeout (60s) will kill idle terminal sessions. Required Traefik configuration:

```yaml
# traefik dynamic config
http:
  serversTransports:
    coder:
      forwardingTimeouts:
        dialTimeout: "30s"
        responseHeaderTimeout: "0s"   # infinite
        idleConnTimeout: "0s"         # infinite
```

Or via Docker label:
```yaml
labels:
  - "traefik.http.middlewares.coder-timeout.headers.customResponseHeaders.X-Forwarded-Proto=https"
  - "traefik.http.services.coder.loadbalancer.server.scheme=http"
  - "traefik.http.services.coder.loadbalancer.responseForwarding.flushInterval=1ms"
```

Coder's documentation recommends setting `respondingTimeouts.readTimeout=0` for Traefik.

### Double-Proxy for Workspace Apps

Coder proxies workspace applications (code-server, port forwards) through its own built-in reverse proxy. Adding Traefik creates a double-proxy path:

```
Browser → Traefik → Coder → Workspace code-server
```

This increases latency and adds a failure point. Both proxy layers must correctly handle:
- WebSocket upgrade headers
- Large request/response bodies (file uploads)
- Server-Sent Events (SSE)
- HTTP/2 (if enabled)

### DERP Relay

Coder agents use DERP (Designated Encrypted Relay for Packets) for peer-to-peer coordination. Traefik must not interfere with DERP WebSocket connections at `/derp`.

### OIDC Redirect URIs

If `CODER_ACCESS_URL` changes (e.g., from `https://host.docker.internal:7443` to `https://host.docker.internal`), all OIDC redirect URIs in Authentik must be updated to match. The callback path is:

```
{CODER_ACCESS_URL}/api/v2/users/oidc/callback
```

---

## 13. Recommendation

**Stay with Option D (Coder native TLS) for the PoC.**

Rationale:

- The current setup works and is proven
- Traefik adds a container, configuration surface, and debugging complexity without solving a current problem
- The only HTTPS-requiring service is Coder (for `crypto.subtle` / secure context), and it already handles TLS natively
- WebSocket proxying for terminals and workspace apps is the highest-risk area, and native TLS avoids it entirely
- OIDC configuration is fragile; changing the access URL cascades to Authentik redirect URIs, cookie domains, and agent callbacks

The trade-off (non-standard port, HTTP-only for other services) is acceptable for a PoC where the primary user is a small team accessing services directly.

---

## 14. When to Revisit

Traefik (or another reverse proxy) becomes worth the investment when:

| Trigger | Why Traefik Helps |
|---------|-------------------|
| Moving to a real domain (not `host.docker.internal`) | Let's Encrypt auto-cert with DNS challenge |
| Deploying to a shared server | Standard port 443, centralized access control |
| Production / staging environment | HTTPS everywhere, access logs, rate limiting |
| Multiple users accessing browser-facing services | Consistent URLs, IP allowlisting |
| Need for centralized auth middleware | Traefik ForwardAuth with Authentik |

When that time comes, **Option B (unified gateway with subdomain routing)** is the target architecture. Implement it in a separate environment (e.g., `aws-production/`) rather than retrofitting the PoC.

### Sketch: Traefik for Production

```yaml
# Example structure (not for PoC)
services:
  traefik:
    image: traefik:v3
    ports:
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik:/etc/traefik
    command:
      - --providers.docker=true
      - --entrypoints.websecure.address=:443
      - --certificatesresolvers.letsencrypt.acme.dnschallenge=true

  coder:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.coder.rule=Host(`coder.example.com`)"
      - "traefik.http.routers.coder.tls.certresolver=letsencrypt"
      - "traefik.http.services.coder.loadbalancer.server.port=7080"
```

This is a starting point for production planning, not a ready-to-deploy configuration.
