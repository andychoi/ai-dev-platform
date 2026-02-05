# AI Gateway Architecture for Coder WebIDE

## Overview

The AI Gateway provides secure, audited access to multiple AI providers from within Coder workspaces. This document describes the architecture, supported providers, and configuration options.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              WORKSPACE                                       │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐            │
│  │   Claude CLI    │  │    Continue     │  │   Custom Apps   │            │
│  │                 │  │   Extension     │  │   (Python/JS)   │            │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘            │
│           │                    │                    │                      │
│           └────────────────────┼────────────────────┘                      │
│                                │                                           │
│                                ▼                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │                    Environment Variables                             │  │
│  │  ANTHROPIC_BASE_URL = http://ai-gateway:8090/v1/claude              │  │
│  │  AWS_BEDROCK_ENDPOINT = http://ai-gateway:8090/v1/bedrock           │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ HTTP (internal network)
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           AI GATEWAY (Port 8090)                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        MIDDLEWARE STACK                              │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ │   │
│  │  │   Auth   │ │   Rate   │ │  Audit   │ │  Cache   │ │ Request  │ │   │
│  │  │  Check   │→│  Limit   │→│  Logger  │→│ (opt.)   │→│Validator │ │   │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘ │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                          ROUTER LAYER                                │   │
│  │                                                                      │   │
│  │   /v1/claude/*  →  Anthropic Adapter                                │   │
│  │   /v1/bedrock/* →  AWS Bedrock Adapter                              │   │
│  │   /v1/gemini/*  →  Google Gemini Adapter (planned)                  │   │
│  │   /v1/chat/*    →  Unified Chat (auto-routes by model)              │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│         ┌──────────────────────────┼──────────────────────────┐            │
│         ▼                          ▼                          ▼            │
│  ┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐    │
│  │    Anthropic    │      │      AWS        │      │     Google      │    │
│  │     Adapter     │      │ Bedrock Adapter │      │  Gemini Adapter │    │
│  ├─────────────────┤      ├─────────────────┤      ├─────────────────┤    │
│  │ • API key mgmt  │      │ • IAM auth      │      │ • API key mgmt  │    │
│  │ • Request fmt   │      │ • Request fmt   │      │ • Request fmt   │    │
│  │ • Response norm │      │ • Response norm │      │ • Response norm │    │
│  └────────┬────────┘      └────────┬────────┘      └────────┬────────┘    │
│           │                        │                        │              │
└───────────┼────────────────────────┼────────────────────────┼──────────────┘
            │                        │                        │
            ▼                        ▼                        ▼
    ┌───────────────┐      ┌───────────────┐      ┌───────────────┐
    │   Anthropic   │      │      AWS      │      │    Google     │
    │      API      │      │    Bedrock    │      │   AI Studio   │
    │               │      │               │      │               │
    │ api.anthropic │      │ bedrock.aws   │      │ generative    │
    │     .com      │      │    .com       │      │ language.api  │
    └───────────────┘      └───────────────┘      └───────────────┘
```

## Supported Providers

### 1. Anthropic Claude (Active)

| Feature | Status |
|---------|--------|
| Messages API | ✅ Supported |
| Streaming | ✅ Supported |
| Tool Use | ✅ Supported |
| Vision | ✅ Supported |

**Supported Models:**
- claude-3-opus-20240229
- claude-3-sonnet-20240229
- claude-3-haiku-20240307
- claude-3-5-sonnet-20241022

**Endpoint:** `/v1/claude/*`

**Usage:**
```bash
# Direct API call
curl -X POST http://ai-gateway:8090/v1/claude/v1/messages \
  -H "Content-Type: application/json" \
  -H "X-Workspace-ID: $CODER_WORKSPACE_ID" \
  -d '{
    "model": "claude-3-sonnet-20240229",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 1024
  }'

# Using Claude CLI (pre-configured)
claude chat "Explain this code"
```

### 2. AWS Bedrock (Active)

| Feature | Status |
|---------|--------|
| Invoke Model | ✅ Supported |
| Streaming | ✅ Supported |
| Converse API | ✅ Supported |

**Supported Models:**
- anthropic.claude-3-opus-20240229-v1:0
- anthropic.claude-3-sonnet-20240229-v1:0
- anthropic.claude-3-haiku-20240307-v1:0
- amazon.titan-text-express-v1
- amazon.titan-text-lite-v1

**Endpoint:** `/v1/bedrock/*`

**Usage:**
```bash
# Invoke model
curl -X POST http://ai-gateway:8090/v1/bedrock/invoke \
  -H "Content-Type: application/json" \
  -H "X-Workspace-ID: $CODER_WORKSPACE_ID" \
  -d '{
    "model_id": "anthropic.claude-3-sonnet-20240229-v1:0",
    "body": {
      "anthropic_version": "bedrock-2023-05-31",
      "messages": [{"role": "user", "content": "Hello"}],
      "max_tokens": 1024
    }
  }'
```

### 3. Google Gemini (Planned)

| Feature | Status |
|---------|--------|
| Generate Content | 🔜 Planned |
| Streaming | 🔜 Planned |
| Vision | 🔜 Planned |

**Planned Models:**
- gemini-pro
- gemini-pro-vision

**Endpoint:** `/v1/gemini/*`

## API Endpoints

### Health & Info

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Gateway health status |
| `/v1/providers` | GET | List available providers |
| `/v1/usage` | GET | User usage statistics |

### Unified Chat (OpenAI-compatible)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/v1/chat/completions` | POST | Unified chat endpoint |

**Example:**
```json
POST /v1/chat/completions
Headers:
  X-Workspace-ID: ws-abc123
  X-Provider: anthropic

Body:
{
  "model": "claude-3-sonnet-20240229",
  "messages": [
    {"role": "user", "content": "Hello, Claude!"}
  ],
  "max_tokens": 1024,
  "temperature": 0.7
}
```

## Security

### Authentication Flow

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│Workspace │    │  Gateway │    │ Provider │    │  Audit   │
│          │    │          │    │   API    │    │   Log    │
└────┬─────┘    └────┬─────┘    └────┬─────┘    └────┬─────┘
     │               │               │               │
     │ Request +     │               │               │
     │ Workspace ID  │               │               │
     │──────────────►│               │               │
     │               │               │               │
     │               │ Validate      │               │
     │               │ workspace     │               │
     │               │───────────────│               │
     │               │               │               │
     │               │ Inject API    │               │
     │               │ credentials   │               │
     │               │──────────────►│               │
     │               │               │               │
     │               │    Response   │               │
     │               │◄──────────────│               │
     │               │               │               │
     │               │ Log request   │               │
     │               │───────────────┼──────────────►│
     │               │               │               │
     │    Response   │               │               │
     │◄──────────────│               │               │
     │               │               │               │
```

### Security Features

| Feature | Description |
|---------|-------------|
| **No credential exposure** | API keys stored in gateway only |
| **Workspace validation** | Requests must include valid workspace ID |
| **Rate limiting** | Per-user request limits |
| **Audit logging** | All requests logged with user/workspace |
| **Request validation** | Max tokens, prompt length enforced |
| **Network isolation** | Gateway only accessible from workspace network |

### Audit Log Format

```json
{
  "timestamp": "2026-02-04T12:00:00Z",
  "event": "ai_request",
  "user": "contractor1",
  "workspace": "ws-abc123",
  "provider": "anthropic",
  "model": "claude-3-sonnet-20240229",
  "tokens_in": 150,
  "tokens_out": 500,
  "latency_ms": 1200,
  "status": 200
}
```

## Rate Limiting

### Default Limits

| Scope | Limit |
|-------|-------|
| Global | 1000 req/min |
| Per User (default) | 60 req/min |
| Per User (tokens) | 100,000 tokens/min |

### Configuration

```yaml
# ai-gateway/config.yaml
rate_limits:
  global:
    requests_per_minute: 1000
    tokens_per_minute: 1000000

  default:
    requests_per_minute: 60
    tokens_per_minute: 100000

  users:
    admin:
      requests_per_minute: 200
    contractor1:
      requests_per_minute: 100
```

## Deployment

### Docker Compose

```yaml
ai-gateway:
  build:
    context: ./ai-gateway
  environment:
    - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
    - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
    - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
    - AWS_REGION=${AWS_REGION:-us-east-1}
    - GOOGLE_API_KEY=${GOOGLE_API_KEY}
  ports:
    - "8090:8090"
  networks:
    - coder-network
```

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `ANTHROPIC_API_KEY` | For Claude | Anthropic API key |
| `AWS_ACCESS_KEY_ID` | For Bedrock | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | For Bedrock | AWS secret key |
| `AWS_REGION` | For Bedrock | AWS region (default: us-east-1) |
| `GOOGLE_API_KEY` | For Gemini | Google AI API key |
| `AI_GATEWAY_PORT` | No | Gateway port (default: 8090) |
| `RATE_LIMIT_RPM` | No | Default rate limit (default: 60) |

## Workspace Integration

### Environment Setup (Automatic)

When a workspace starts, the following is configured:

```bash
# ~/.bashrc additions
export ANTHROPIC_BASE_URL=http://ai-gateway:8090/v1/claude
export AWS_BEDROCK_ENDPOINT=http://ai-gateway:8090/v1/bedrock

# Convenience aliases
alias ai-chat="curl -X POST $AI_GATEWAY_URL/v1/chat/completions ..."
alias ai-usage="curl $AI_GATEWAY_URL/v1/usage ..."
```

### Continue Extension Config

```json
{
  "models": [
    {
      "title": "Claude (via Gateway)",
      "provider": "anthropic",
      "model": "claude-3-sonnet-20240229",
      "apiBase": "http://ai-gateway:8090/v1/claude"
    }
  ]
}
```

## Future Enhancements

### Google Gemini Support

```
Status: Planned for Phase 2
ETA: Q2 2026

Features:
- Generate content
- Multi-turn conversations
- Vision capabilities
- Function calling
```

### Additional Providers

| Provider | Status | Notes |
|----------|--------|-------|
| OpenAI | Considered | For GPT-4 access |
| Mistral | Considered | Open-source alternative |
| Ollama | Planned | Self-hosted models |

### Cost Tracking

```
Status: Planned for Phase 3

Features:
- Per-project cost allocation
- Budget alerts
- Usage dashboards
```

## Troubleshooting

### Gateway not responding

```bash
# Check health
curl http://localhost:8090/health

# Check logs
docker logs ai-gateway

# Verify network
docker exec <workspace> ping ai-gateway
```

### Provider errors

```bash
# Check provider status
curl http://localhost:8090/v1/providers

# Test specific provider
curl http://localhost:8090/v1/claude/health
```

### Rate limit errors

```bash
# Check current usage
curl http://localhost:8090/v1/usage \
  -H "X-Workspace-ID: $CODER_WORKSPACE_ID"

# Response shows remaining limits
```

## References

- [Anthropic API Documentation](https://docs.anthropic.com/)
- [AWS Bedrock Documentation](https://docs.aws.amazon.com/bedrock/)
- [Google Gemini API](https://ai.google.dev/docs)
