# Content Guardrails — PII, Financial & Sensitive Data Protection

This document describes the content guardrail system that prevents AI prompts and responses from containing PII, financial data, credentials, and other sensitive information.

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Guardrail Levels](#2-guardrail-levels)
3. [Built-in Patterns](#3-built-in-patterns)
4. [Custom Patterns](#4-custom-patterns)
5. [Configuration Reference](#5-configuration-reference)
6. [Per-Key Guardrail Assignment](#6-per-key-guardrail-assignment)
7. [Testing & Validation](#7-testing--validation)
8. [Future: Presidio ML-Based Detection](#8-future-presidio-ml-based-detection)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Architecture Overview

The guardrail system is a **server-side, tamper-proof** content filter that runs inside the LiteLLM proxy. It scans every chat completion request **before** it reaches the upstream model provider, ensuring sensitive data never leaves the platform.

```
┌──────────────────────────────────────────────────────────────────────┐
│                     REQUEST LIFECYCLE                                 │
│                                                                      │
│  User Prompt                                                         │
│       │                                                              │
│       ▼                                                              │
│  ┌─────────────────────┐                                            │
│  │  LiteLLM Proxy      │                                            │
│  │                     │                                            │
│  │  1. Enforcement Hook│◄── Injects design-first system prompt      │
│  │     (pre_call)      │                                            │
│  │  2. Guardrails Hook │◄── Scans for PII/financial/secrets         │
│  │     (pre_call)      │    BLOCKS if detected (high severity)      │
│  │                     │    WARNS if detected (medium severity)      │
│  │                     │                                            │
│  │  3. Model Call      │──► Anthropic / Bedrock                     │
│  │                     │                                            │
│  │  4. Langfuse Log    │──► Trace analytics (async, no content)     │
│  │     (post_call)     │                                            │
│  └─────────────────────┘                                            │
│       │                                                              │
│       ▼                                                              │
│  AI Response (only if guardrails passed)                             │
└──────────────────────────────────────────────────────────────────────┘
```

### Key Properties

| Property | Detail |
|----------|--------|
| **Tamper-proof** | Runs at proxy layer; workspaces cannot bypass it |
| **Pre-call blocking** | PII never reaches the model provider |
| **Per-key configurable** | Different guardrail levels per workspace/user |
| **Hot-reloadable** | Custom patterns editable without restart (mtime-cached) |
| **Zero external deps** | Built-in regex patterns; no sidecar services needed |

---

## 2. Guardrail Levels

Each LiteLLM virtual key has a `guardrail_level` in its metadata. The level determines how aggressively patterns are enforced.

| Level | High Severity | Medium Severity | Use Case |
|-------|--------------|-----------------|----------|
| `off` | Pass through | Pass through | Trusted/admin users, testing |
| `standard` | **Block** | Warn (log only) | Default for contractor workspaces |
| `strict` | **Block** | **Block** | Financial/healthcare workloads |

- **Block** = Request rejected with HTTP 400 and descriptive error message
- **Warn** = Request allowed through; pattern logged at WARNING level

Default level is controlled by `DEFAULT_GUARDRAIL_LEVEL` env var (defaults to `standard`).

---

## 3. Built-in Patterns

These patterns are always available without any external files.

### PII Patterns

| Pattern | Severity | Standard | Strict | Example |
|---------|----------|----------|--------|---------|
| `us_ssn` | high | Block | Block | `078-05-1120` |
| `email_address` | medium | Warn | Block | `john@example.com` |
| `phone_us` | medium | Warn | Block | `(555) 123-4567` |
| `passport_us` | high | Block | Block | `A12345678` |

### Financial Patterns

| Pattern | Severity | Standard | Strict | Example |
|---------|----------|----------|--------|---------|
| `credit_card_visa` | high | Block | Block | `4532-0150-0000-1234` |
| `credit_card_mastercard` | high | Block | Block | `5425-2334-3010-9903` |
| `credit_card_amex` | high | Block | Block | `3714-496353-98431` |
| `iban` | high | Block | Block | `GB29NWBK60161331926819` |
| `bank_routing_aba` | medium | Warn* | Block* | `021000021` |
| `swift_bic` | medium | Warn* | Block* | `NWBKGB2L` |

\* *Context-required patterns — only match when financial keywords (bank, transfer, routing, etc.) are present in the same message.*

### Secret & Credential Patterns

| Pattern | Severity | Standard | Strict | Example |
|---------|----------|----------|--------|---------|
| `aws_access_key` | high | Block | Block | `AKIAIOSFODNN7EXAMPLE` |
| `aws_secret_key` | medium | Warn* | Block* | 40-char base64 string |
| `github_token` | high | Block | Block | `ghp_ABCDEF...` |
| `generic_api_key` | high | Block | Block | `sk-proj-abc123...` |
| `private_key_pem` | high | Block | Block | `-----BEGIN RSA PRIVATE KEY-----` |
| `jwt_token` | high | Block | Block | `eyJhbG...` |
| `slack_token` | high | Block | Block | `xoxb-...` |
| `connection_string` | high | Block | Block | `postgres://user:pass@host/db` |

\* *Context-required — only flagged when near relevant keywords.*

---

## 4. Custom Patterns

Add organization-specific patterns by editing `litellm/guardrails/patterns.json`. Changes take effect on the next request (no restart needed).

### Example: Adding Employee ID and Project Code Patterns

```json
{
  "employee_id": {
    "pattern": "\\bEMP-\\d{6}\\b",
    "label": "Employee ID",
    "category": "pii",
    "severity": "high",
    "action": "block"
  },
  "internal_project_code": {
    "pattern": "\\bPROJ-[A-Z]{2}-\\d{4}\\b",
    "label": "Internal project code",
    "category": "compliance",
    "severity": "medium",
    "action": "flag"
  },
  "medical_record_number": {
    "pattern": "\\bMRN[:\\s]?\\d{7,10}\\b",
    "label": "Medical record number",
    "category": "pii",
    "severity": "high",
    "action": "block"
  }
}
```

### Pattern Format

| Field | Required | Description |
|-------|----------|-------------|
| `pattern` | Yes | Python regex (escaped for JSON) |
| `label` | Yes | Human-readable name shown in error messages |
| `category` | Yes | `pii`, `financial`, `secret`, or `compliance` |
| `severity` | Yes | `high` (blocked in standard+strict) or `medium` (blocked only in strict) |
| `action` | Yes | `block` (reject request) or `flag` (log warning) |
| `context_required` | No | If `true`, only matches when financial keywords present |

Custom patterns **override** built-in patterns with the same name.

---

## 5. Configuration Reference

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GUARDRAILS_ENABLED` | `true` | Master switch — set to `false` to disable all scanning |
| `DEFAULT_GUARDRAIL_LEVEL` | `standard` | Default level for keys without `guardrail_level` metadata |
| `GUARDRAILS_DIR` | `/app/guardrails` | Directory containing `patterns.json` |

### Files

| File | Purpose |
|------|---------|
| `litellm/guardrails_hook.py` | Main hook — `GuardrailsHook` class + built-in patterns |
| `litellm/guardrails/patterns.json` | Custom patterns (hot-reloadable) |
| `litellm/config.yaml` | Registers hook in `callbacks` list |

### LiteLLM Config (config.yaml)

The guardrails hook is registered alongside the enforcement hook:

```yaml
litellm_settings:
  callbacks: ["enforcement_hook.proxy_handler_instance", "guardrails_hook.guardrails_instance"]
```

### Docker Compose Mounts

```yaml
volumes:
  - ./litellm/guardrails_hook.py:/app/guardrails_hook.py:ro
  - ./litellm/guardrails:/app/guardrails:ro
```

---

## 6. Per-Key Guardrail Assignment

Guardrail levels are stored in LiteLLM virtual key metadata, following the same pattern as enforcement levels.

### At Key Creation (via Key Provisioner)

```bash
curl -X POST http://localhost:8100/api/v1/keys/workspace \
  -H "Authorization: Bearer $PROVISIONER_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "workspace_id": "abc-123",
    "username": "contractor1",
    "enforcement_level": "design-first",
    "guardrail_level": "strict"
  }'
```

### Direct Key Creation (via LiteLLM Admin API)

```bash
curl -X POST http://localhost:4000/key/generate \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "key_alias": "workspace-abc-123",
    "max_budget": 10.0,
    "metadata": {
      "guardrail_level": "strict",
      "enforcement_level": "standard"
    }
  }'
```

### Guardrail Level by Workspace Type

| Workspace Type | Recommended Guardrail | Rationale |
|----------------|----------------------|-----------|
| General development | `standard` | Blocks high-severity; warns on medium |
| Financial/healthcare | `strict` | Blocks all detected patterns |
| Admin/testing | `off` | No scanning (trusted users) |
| CI/CD pipelines | `standard` | Prevents accidental secret exposure |

---

## 7. Testing & Validation

### Run the Test Suite

```bash
cd coder-poc
bash scripts/test-guardrails.sh
```

The test script validates:
1. **Static checks** — Files exist, classes defined, patterns registered
2. **Config checks** — LiteLLM config and Docker Compose correct
3. **Live tests** (if services running):
   - PII detection (SSN blocked, email warned)
   - Financial detection (credit cards, IBANs blocked)
   - Secret detection (AWS keys, GitHub tokens, private keys blocked)
   - Clean prompt passthrough (no false positives)
   - Level comparison (off/standard/strict behavior)

### Manual Testing

```bash
# Set up
export MASTER_KEY="your-litellm-master-key"

# Create a test key with strict guardrails
KEY=$(curl -s -X POST http://localhost:4000/key/generate \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"key_alias":"test-guard","max_budget":0.01,"metadata":{"guardrail_level":"strict"}}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['key'])")

# Test: should be blocked (SSN)
curl -X POST http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-haiku-4-5","messages":[{"role":"user","content":"My SSN is 078-05-1120"}]}'

# Test: should pass through (clean prompt)
curl -X POST http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-haiku-4-5","messages":[{"role":"user","content":"What is 2+2?"}],"max_tokens":5}'

# Cleanup
curl -s -X POST http://localhost:4000/key/delete \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"keys\":[\"$KEY\"]}"
```

### Check Logs

```bash
# See guardrail warnings and blocks
docker compose logs litellm 2>&1 | grep -i guardrail

# See specific pattern matches
docker compose logs litellm 2>&1 | grep "Guardrail BLOCKED"
docker compose logs litellm 2>&1 | grep "Guardrail warning"
```

---

## 8. Future: Presidio ML-Based Detection

The current system uses regex patterns (Layer 1). For ML-based entity recognition (names, addresses, medical terms), Presidio can be added as Layer 2.

### What Presidio Adds

| Capability | Regex (Current) | Presidio (Future) |
|-----------|-----------------|-------------------|
| SSN, credit cards | Yes | Yes |
| Person names | No | **Yes** (NLP-based) |
| Street addresses | No | **Yes** |
| Medical terms (PHI) | No | **Yes** |
| Context-aware detection | Limited | **Strong** |
| False positive rate | Low | Lower |

### Adding Presidio

1. Add containers to `docker-compose.yml`:

```yaml
presidio-analyzer:
  image: mcr.microsoft.com/presidio-analyzer:latest
  ports:
    - "5002:5002"
  networks:
    - coder-network

presidio-anonymizer:
  image: mcr.microsoft.com/presidio-anonymizer:latest
  ports:
    - "5001:5001"
  networks:
    - coder-network
```

2. Add env vars to litellm service:

```yaml
- PRESIDIO_ANALYZER_API_BASE=http://presidio-analyzer:5002
- PRESIDIO_ANONYMIZER_API_BASE=http://presidio-anonymizer:5001
```

3. Add to `config.yaml`:

```yaml
guardrails:
  - guardrail_name: "presidio-pii"
    litellm_params:
      guardrail: presidio
      mode: "post_call"
      presidio_filter_scope: "both"
      output_parse_pii: true
      pii_entities_config:
        CREDIT_CARD: "BLOCK"
        US_SSN: "BLOCK"
        PERSON: "MASK"
        EMAIL_ADDRESS: "MASK"
        LOCATION: "MASK"
```

This is optional infrastructure and is documented here for future reference.

---

## 9. Troubleshooting

### Guardrails Not Blocking

| Symptom | Cause | Fix |
|---------|-------|-----|
| No patterns detected | `GUARDRAILS_ENABLED=false` | Set to `true` in `.env`, run `docker compose up -d litellm` |
| Hook not loaded | Container not restarted after config change | `docker compose up -d litellm` (not `restart`) |
| Hook loaded but not firing | `call_type` mismatch — LiteLLM proxy sends `acompletion`, not `completion` | Ensure hook accepts both: `call_type not in ("completion", "acompletion")` |
| 500 error on first request | Metadata keys (`_comment`, `_format`) in `patterns.json` treated as patterns | Filter non-pattern entries: skip keys starting with `_` or missing `pattern` field |
| Key has `guardrail_level=off` | Key metadata disables scanning | Check key metadata via `/key/info` |
| Pattern not matching | Regex doesn't cover the format | Add custom pattern to `patterns.json` |

### False Positives

| Symptom | Cause | Fix |
|---------|-------|-----|
| Code blocked as API key | `generic_api_key` pattern too broad | Use `standard` level (warns instead of blocks) for dev workspaces |
| Random numbers blocked | `bank_routing_aba` matches 9-digit numbers | Pattern has `context_required: true` — check financial keywords |
| JWT in code examples blocked | `jwt_token` matches example JWTs | Use `guardrail_level=off` for keys used in documentation work |

### Checking Hook Status

```bash
# Verify hook is loaded
curl -s -H "Authorization: Bearer $MASTER_KEY" \
  http://localhost:4000/get/config/callbacks | python3 -m json.tool

# Expected output includes:
# "guardrails_hook.guardrails_instance"
```

### Blocked Request Error Format

When a request is blocked, the response looks like:

```json
{
  "error": {
    "message": "Request blocked by content guardrails. Detected sensitive data: US Social Security Number. Categories: pii. Remove sensitive information before sending to AI. Guardrail level: standard",
    "type": "invalid_request_error",
    "code": 400
  }
}
```
