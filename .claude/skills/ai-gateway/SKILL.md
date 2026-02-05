---
name: ai-gateway
description: Multi-provider AI Gateway - Claude, Bedrock, Gemini proxying with rate limiting and audit logging
---

# AI Gateway Skill

## Overview

This skill provides guidance for configuring and using the multi-provider AI Gateway in the Coder WebIDE environment. The gateway proxies AI API calls to multiple providers while enforcing security, rate limiting, and audit logging.

## Supported Providers

| Provider | Endpoint | Models |
|----------|----------|--------|
| **Anthropic Claude** | `/v1/claude/*` | claude-sonnet-4-5, claude-haiku-4-5, claude-opus-4 |
| **AWS Bedrock** | `/v1/bedrock/*` | us.anthropic.claude-sonnet-4-5-*, us.anthropic.claude-haiku-4-5-*, amazon.titan-* |
| **Google Gemini** | `/v1/gemini/*` | gemini-pro, gemini-pro-vision (planned) |

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         AI Gateway (Port 8090)                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                │
│  │   Claude    │    │   Bedrock   │    │   Gemini    │                │
│  │   Adapter   │    │   Adapter   │    │   Adapter   │                │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘                │
│         │                  │                  │                        │
│  ┌──────┴──────────────────┴──────────────────┴──────┐                │
│  │                  Router Layer                      │                │
│  │  • Provider selection based on model/endpoint     │                │
│  │  • Request transformation                          │                │
│  │  • Response normalization                          │                │
│  └───────────────────────┬────────────────────────────┘                │
│                          │                                             │
│  ┌───────────────────────┴────────────────────────────┐                │
│  │                 Middleware Stack                    │                │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌───────┐ │                │
│  │  │  Auth    │ │  Rate    │ │  Audit   │ │ Cache │ │                │
│  │  │  Check   │ │  Limit   │ │  Logger  │ │       │ │                │
│  │  └──────────┘ └──────────┘ └──────────┘ └───────┘ │                │
│  └────────────────────────────────────────────────────┘                │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
                                   │
                    ┌──────────────┼──────────────┐
                    ▼              ▼              ▼
            ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
            │  Anthropic  │ │    AWS      │ │   Google    │
            │     API     │ │   Bedrock   │ │  AI Studio  │
            └─────────────┘ └─────────────┘ └─────────────┘
```

## Usage

### Claude CLI Configuration

```bash
# Set the gateway as the base URL
export ANTHROPIC_BASE_URL=http://ai-gateway:8090/v1/claude

# Use Claude CLI normally
claude chat "Hello, world"
```

### AWS Bedrock Configuration

```bash
# Configure AWS credentials (injected by gateway)
export AWS_BEDROCK_ENDPOINT=http://ai-gateway:8090/v1/bedrock

# Use boto3 or AWS CLI
aws bedrock-runtime invoke-model \
  --endpoint-url $AWS_BEDROCK_ENDPOINT \
  --model-id anthropic.claude-3-sonnet-20240229-v1:0 \
  --body '{"prompt": "Hello"}' \
  output.json
```

### Continue Extension Configuration

```json
// .vscode/settings.json
{
  "continue.models": [
    {
      "title": "Claude (via Gateway)",
      "provider": "anthropic",
      "model": "claude-3-opus-20240229",
      "apiBase": "http://ai-gateway:8090/v1/claude"
    },
    {
      "title": "Bedrock Claude",
      "provider": "bedrock",
      "model": "anthropic.claude-3-sonnet-20240229-v1:0",
      "apiBase": "http://ai-gateway:8090/v1/bedrock"
    }
  ]
}
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `AI_GATEWAY_PORT` | Gateway listen port | 8090 |
| `ANTHROPIC_API_KEY` | Anthropic API key | (required) |
| `AWS_ACCESS_KEY_ID` | AWS access key | (required for Bedrock) |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key | (required for Bedrock) |
| `AWS_REGION` | AWS region for Bedrock | us-east-1 |
| `GOOGLE_API_KEY` | Google AI API key | (planned) |
| `RATE_LIMIT_RPM` | Requests per minute | 60 |
| `AUDIT_LOG_LEVEL` | Logging level | info |

### Rate Limiting

```yaml
# ai-gateway/config.yaml
rate_limits:
  default:
    requests_per_minute: 60
    tokens_per_minute: 100000

  per_user:
    contractor1:
      requests_per_minute: 100
    contractor2:
      requests_per_minute: 50
```

### Audit Logging

All requests are logged with:
- Timestamp
- User ID (from workspace)
- Provider and model
- Request tokens
- Response tokens
- Latency
- Status code

```json
{
  "timestamp": "2026-02-04T12:00:00Z",
  "user": "contractor1",
  "workspace": "ws-abc123",
  "provider": "anthropic",
  "model": "claude-3-opus",
  "request_tokens": 150,
  "response_tokens": 500,
  "latency_ms": 1200,
  "status": 200
}
```

## Best Practices

### Model Selection

| Use Case | Recommended Model | Provider |
|----------|-------------------|----------|
| Code completion | claude-haiku-4-5 | Anthropic/Bedrock |
| Code review | claude-sonnet-4-5 | Anthropic/Bedrock |
| Complex analysis | claude-opus-4 | Anthropic/Bedrock |
| Cost-sensitive | amazon.titan-text-lite | Bedrock |

### Token Management

```bash
# Check your usage
curl http://ai-gateway:8090/v1/usage \
  -H "X-Workspace-ID: $CODER_WORKSPACE_ID"

# Response:
{
  "today": {
    "requests": 45,
    "tokens_in": 5000,
    "tokens_out": 15000
  },
  "limit": {
    "requests_remaining": 55,
    "tokens_remaining": 85000
  }
}
```

### Error Handling

```python
import httpx

def call_ai_gateway(prompt: str, model: str = "claude-3-sonnet"):
    try:
        response = httpx.post(
            "http://ai-gateway:8090/v1/claude/messages",
            json={
                "model": model,
                "messages": [{"role": "user", "content": prompt}],
                "max_tokens": 1000
            },
            timeout=60.0
        )
        response.raise_for_status()
        return response.json()
    except httpx.HTTPStatusError as e:
        if e.response.status_code == 429:
            print("Rate limited - wait and retry")
        elif e.response.status_code == 401:
            print("Authentication failed")
        raise
```

## Troubleshooting

### Gateway not responding

```bash
# Check health
curl http://localhost:8090/health

# Check logs
docker logs ai-gateway

# Verify network
docker exec <workspace> curl http://ai-gateway:8090/health
```

### Rate limit errors

```bash
# Check current limits
curl http://ai-gateway:8090/v1/limits

# Wait for reset (usually 1 minute)
```

### Provider errors

```bash
# Check provider status
curl http://ai-gateway:8090/v1/providers

# Test specific provider
curl http://ai-gateway:8090/v1/claude/health
curl http://ai-gateway:8090/v1/bedrock/health
```

## Security Considerations

1. **No direct API access** - All requests go through gateway
2. **Credentials never exposed** - API keys stored in gateway only
3. **Per-user rate limits** - Prevent abuse
4. **Full audit trail** - All requests logged
5. **Request validation** - Malformed requests rejected

## Future Enhancements

- [ ] Google Gemini integration
- [ ] OpenAI compatibility layer
- [ ] Prompt caching for common queries
- [ ] Cost allocation per project
- [ ] Model fallback on provider errors
