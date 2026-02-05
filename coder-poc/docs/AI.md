# AI Integration Architecture - Dev Platform

This document describes how AI capabilities are integrated into the Coder WebIDE Development Platform, including API access, coding assistance, chat interfaces, and code review workflows.

## Table of Contents

1. [AI Architecture Overview](#1-ai-architecture-overview)
2. [AI Providers & Models](#2-ai-providers--models)
3. [Coder AI Bridge](#3-coder-ai-bridge)
4. [Roo Code Extension](#4-roo-code-extension)
5. [LiteLLM Proxy](#5-litellm-proxy)
6. [AI-Assisted Development Workflows](#6-ai-assisted-development-workflows)
7. [Code Review with AI](#7-code-review-with-ai)
8. [Security & Compliance](#8-security--compliance)
9. [Configuration Reference](#9-configuration-reference)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. AI Architecture Overview

### 1.1 AI Integration Points

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         DEV PLATFORM AI ARCHITECTURE                         │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         USER INTERFACES                              │   │
│  │  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐           │   │
│  │  │  Coder Chat   │  │   Roo Code   │  │  CLI Tools    │           │   │
│  │  │  (Built-in)   │  │  (VS Code)    │  │  (Terminal)   │           │   │
│  │  └───────┬───────┘  └───────┬───────┘  └───────┬───────┘           │   │
│  └──────────┼──────────────────┼──────────────────┼─────────────────────┘   │
│             │                  │                  │                          │
│             ▼                  ▼                  ▼                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐              │
│  │   AI Bridge     │  │  Roo Code API  │  │    LiteLLM      │              │
│  │ (Coder Server)  │  │  (via LiteLLM) │  │    (Proxy)      │              │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘              │
│           │                    │                    │                        │
│           └────────────────────┼────────────────────┘                        │
│                                │                                             │
│  ┌─────────────────────────────┼─────────────────────────────────────────┐  │
│  │                    AI PROVIDER LAYER                                   │  │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐       │  │
│  │  │   AWS Bedrock   │  │   Anthropic     │  │  Future: Google │       │  │
│  │  │   Claude API    │  │   Direct API    │  │   Gemini, etc.  │       │  │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘       │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 AI Capabilities Summary

| Capability | Interface | Provider | Use Case |
|------------|-----------|----------|----------|
| Chat Assistant | Coder Built-in | Bedrock/Anthropic | Quick questions, explanations |
| Code Completion | Roo Code | Bedrock/Anthropic (via LiteLLM) | Autocomplete while typing |
| Code Generation | Roo Code | Bedrock/Anthropic (via LiteLLM) | Generate code from description |
| Code Review | Roo Code | Bedrock/Anthropic (via LiteLLM) | Automated code review |
| Refactoring | Roo Code | Bedrock/Anthropic (via LiteLLM) | Code improvement suggestions |
| Documentation | Roo Code | Bedrock/Anthropic (via LiteLLM) | Generate docs/comments |
| Test Generation | Roo Code | Bedrock/Anthropic (via LiteLLM) | Generate unit tests |
| CLI Assistant | Terminal Tools | LiteLLM | Shell commands, debugging |

---

## 2. AI Providers & Models

### 2.1 Supported Providers

| Provider | Status | Authentication | Models |
|----------|--------|----------------|--------|
| **AWS Bedrock** | ✓ Active | IAM/Access Keys | Claude family |
| **Anthropic Direct** | ✓ Active | API Key | Claude family |
| Google Gemini | Planned | API Key | Gemini family |
| Azure OpenAI | Planned | Azure AD | GPT family |

### 2.2 Claude Model Selection

| Model | Best For | Speed | Context | Cost |
|-------|----------|-------|---------|------|
| **Claude Sonnet 4.5** | General coding, balanced | Fast | 200K | $$ |
| **Claude Haiku 4.5** | Autocomplete, quick tasks | Fastest | 200K | $ |
| **Claude Opus 4.5** | Complex analysis, architecture | Slower | 200K | $$$ |

### 2.3 Model Configuration

```yaml
# Workspace parameter selection
AI Model Options:
  - Claude Sonnet 4.5 (Balanced)     # Default - good for most tasks
  - Claude Haiku 4.5 (Fast)          # Best for autocomplete
  - Claude Opus 4.5 (Advanced)       # Complex reasoning tasks
```

### 2.4 Bedrock Model IDs

| Model | Bedrock Model ID |
|-------|------------------|
| Claude Sonnet 4.5 | `us.anthropic.claude-sonnet-4-5-20250929-v1:0` |
| Claude Haiku 4.5 | `us.anthropic.claude-haiku-4-5-20251001-v1:0` |
| Claude Opus 4.5 | `us.anthropic.claude-opus-4-20250514-v1:0` |

---

## 3. Coder AI Bridge

### 3.1 Overview

Coder AI Bridge is the **built-in AI chat** feature in Coder's web interface. It provides a ChatGPT-like experience directly within the platform.

```
┌─────────────────────────────────────────────────────────────────┐
│                      CODER WEB INTERFACE                         │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  [Workspaces] [Templates] [Users]              [AI Chat] │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                    │            │
│  ┌────────────────────────────────────┐  ┌────────┴────────┐  │
│  │                                    │  │   AI CHAT PANEL │  │
│  │         MAIN CONTENT               │  │                 │  │
│  │                                    │  │  User: How do   │  │
│  │                                    │  │  I deploy...?   │  │
│  │                                    │  │                 │  │
│  │                                    │  │  AI: Here's     │  │
│  │                                    │  │  how to...      │  │
│  │                                    │  │                 │  │
│  └────────────────────────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Configuration

```yaml
# docker-compose.yml - Coder AI Bridge settings
environment:
  # AWS Bedrock Configuration (Recommended)
  CODER_AIBRIDGE_BEDROCK_ACCESS_KEY: ${AWS_ACCESS_KEY_ID}
  CODER_AIBRIDGE_BEDROCK_ACCESS_KEY_SECRET: ${AWS_SECRET_ACCESS_KEY}
  CODER_AIBRIDGE_BEDROCK_REGION: us-east-1
  CODER_AIBRIDGE_BEDROCK_MODEL: "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
  CODER_AIBRIDGE_BEDROCK_SMALL_FAST_MODEL: "us.anthropic.claude-haiku-4-5-20251001-v1:0"

  # OR Anthropic Direct API
  # CODER_AIBRIDGE_ANTHROPIC_KEY: ${ANTHROPIC_API_KEY}
  # CODER_AIBRIDGE_ANTHROPIC_BASE_URL: https://api.anthropic.com/
```

### 3.3 Features

| Feature | Description |
|---------|-------------|
| **Chat Interface** | Conversational AI in sidebar |
| **Context Awareness** | Can reference workspace/project |
| **Code Blocks** | Syntax-highlighted code responses |
| **Copy to Editor** | One-click copy code snippets |
| **History** | Persisted conversation history |

### 3.4 No External Sign-in Required

When configured with Bedrock or Anthropic API keys at the server level, users do **NOT** need to sign in with Google, GitHub, or other OAuth providers. The AI works immediately.

---

## 4. Roo Code Extension

### 4.1 Overview

[Roo Code](https://github.com/RooVetGit/Roo-Code) is an AI-powered coding agent that integrates with VS Code (and code-server). It replaces the previously used Continue and Cody extensions, providing a more capable agentic coding experience. It provides:

- **Agentic Coding** - AI agent that can read, write, and execute code autonomously
- **Chat Sidebar** - In-IDE chat with full project context
- **File Operations** - Create, edit, and manage files through natural language
- **Terminal Integration** - Execute commands and analyze output
- **Custom Modes** - Configurable agent behavior profiles

### 4.2 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    CODE-SERVER (VS Code in Browser)              │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                     ROO CODE EXTENSION                      │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │ │
│  │  │   Chat      │  │   Agentic   │  │  File/Term  │        │ │
│  │  │   Panel     │  │   Engine    │  │  Operations │        │ │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘        │ │
│  │         │                │                │                │ │
│  │         └────────────────┼────────────────┘                │ │
│  │                          │                                  │ │
│  │                    ┌─────┴─────┐                           │ │
│  │                    │ Roo Code  │                           │ │
│  │                    │   Core    │                           │ │
│  │                    └─────┬─────┘                           │ │
│  └──────────────────────────┼─────────────────────────────────┘ │
│                             │                                    │
│                             ▼                                    │
│                    ┌─────────────────┐                          │
│                    │  OpenAI-compat  │                          │
│                    │  API endpoint   │                          │
│                    └────────┬────────┘                          │
│                             │                                    │
└─────────────────────────────┼────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │    LiteLLM      │
                    │  (litellm:4000) │
                    └────────┬────────┘
                             │
                    ┌────────┴────────┐
                    │  AWS Bedrock /  │
                    │  Anthropic API  │
                    └─────────────────┘
```

### 4.3 Configuration

Roo Code is configured via VS Code settings, which are automatically set during workspace startup. The extension connects to LiteLLM as an OpenAI-compatible API provider:

- **API Provider:** OpenAI Compatible
- **Base URL:** `http://litellm:4000`
- **API Key:** Per-user virtual key (provisioned by LiteLLM)
- **Model:** Configurable via workspace parameter (default: `bedrock/us.anthropic.claude-sonnet-4-5-20250929-v1:0`)

The per-user virtual key is automatically generated by the `setup-litellm-keys.sh` script and injected into the workspace at startup. This provides:

- Per-user budget tracking and limits
- Per-user rate limiting
- Centralized audit logging of all AI API usage
- No need to distribute raw provider API keys to workspaces

### 4.4 Key Features

| Feature | Description |
|---------|-------------|
| **Agentic Coding** | AI reads/writes/executes code with human oversight |
| **Chat** | Conversational AI with full project context |
| **File Operations** | Create, edit, delete files through natural language |
| **Terminal** | Execute commands and analyze output |
| **Multi-file Editing** | Coordinate changes across multiple files |
| **Code Review** | Review code for bugs, security, and improvements |
| **Test Generation** | Generate unit tests for existing code |
| **Documentation** | Generate docs and comments |

### 4.5 Roo Code vs Previous Extensions

| Feature | Continue | Cody | Roo Code |
|---------|----------|------|----------|
| Agentic capabilities | Limited | Limited | Full agent |
| File operations | No | No | Yes |
| Terminal integration | No | Limited | Yes |
| Custom modes | No | No | Yes |
| OpenAI-compatible API | Yes | No | Yes |
| Per-user key support | Manual | N/A | Via LiteLLM |

---

## 5. LiteLLM Proxy

### 5.1 Overview

[LiteLLM](https://docs.litellm.ai/) replaces the custom AI Gateway as the centralized AI API proxy. It provides:

- **OpenAI-compatible API** - Standard `/v1/chat/completions` endpoint
- **Per-user virtual keys** - Each user gets their own API key with budget and rate limits
- **Multi-provider routing** - Route to AWS Bedrock, Anthropic, OpenAI, and more
- **Budget management** - Set per-user spending limits
- **Rate limiting** - Per-key request rate limits
- **Audit logging** - Track all API usage per user
- **Admin UI** - Web dashboard for key and usage management

### 5.2 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         LITELLM PROXY                            │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                     INGRESS LAYER                           │ │
│  │  • Virtual key authentication (per-user keys)               │ │
│  │  • Rate limiting (per key)                                  │ │
│  │  • Budget enforcement                                       │ │
│  └─────────────────────────┬──────────────────────────────────┘ │
│                            │                                     │
│  ┌─────────────────────────┼──────────────────────────────────┐ │
│  │                   ROUTING LAYER                             │ │
│  │  ┌──────────────────────────────────────────────────┐       │ │
│  │  │  /v1/chat/completions (OpenAI-compatible)        │       │ │
│  │  │  /v1/models                                      │       │ │
│  │  │  /v1/completions                                 │       │ │
│  │  └────────────────────┬─────────────────────────────┘       │ │
│  └───────────────────────┼────────────────────────────────────┘ │
│                          │                                       │
│  ┌───────────────────────┼────────────────────────────────────┐ │
│  │              PROVIDER ADAPTERS                              │ │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐           │ │
│  │  │  Bedrock   │  │ Anthropic  │  │  OpenAI    │           │ │
│  │  │  Adapter   │  │  Adapter   │  │  Adapter   │           │ │
│  │  └────────────┘  └────────────┘  └────────────┘           │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                   AUDIT & TRACKING                          │ │
│  │  • Per-user token usage        • Budget tracking            │ │
│  │  • Request metadata            • Response time              │ │
│  │  • Model usage stats           • Error tracking             │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 5.3 Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/v1/chat/completions` | POST | OpenAI-compatible chat completions |
| `/v1/completions` | POST | OpenAI-compatible completions |
| `/v1/models` | GET | List available models |
| `/key/generate` | POST | Generate virtual key (admin) |
| `/key/info` | GET | Get key info and usage |
| `/user/info` | GET | Get user budget and usage |

### 5.4 Configuration

```yaml
# litellm/config.yaml
model_list:
  - model_name: claude-sonnet
    litellm_params:
      model: bedrock/us.anthropic.claude-sonnet-4-5-20250929-v1:0
      aws_access_key_id: os.environ/AWS_ACCESS_KEY_ID
      aws_secret_access_key: os.environ/AWS_SECRET_ACCESS_KEY
      aws_region_name: os.environ/AWS_REGION

  - model_name: claude-haiku
    litellm_params:
      model: bedrock/us.anthropic.claude-haiku-4-5-20251001-v1:0
      aws_access_key_id: os.environ/AWS_ACCESS_KEY_ID
      aws_secret_access_key: os.environ/AWS_SECRET_ACCESS_KEY
      aws_region_name: os.environ/AWS_REGION

  - model_name: claude-opus
    litellm_params:
      model: bedrock/us.anthropic.claude-opus-4-20250514-v1:0
      aws_access_key_id: os.environ/AWS_ACCESS_KEY_ID
      aws_secret_access_key: os.environ/AWS_SECRET_ACCESS_KEY
      aws_region_name: os.environ/AWS_REGION

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  database_url: os.environ/LITELLM_DATABASE_URL

litellm_settings:
  drop_params: true
  set_verbose: false
```

### 5.5 Per-User Virtual Keys

LiteLLM virtual keys allow per-user access control without distributing raw provider API keys:

```bash
# Generate a key for a user (via admin API)
curl -X POST http://localhost:4000/key/generate \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "contractor1",
    "max_budget": 10.00,
    "tpm_limit": 100000,
    "rpm_limit": 60
  }'

# Response includes the virtual key:
# { "key": "sk-...", "user_id": "contractor1" }
```

Keys are automatically provisioned during workspace creation via the `setup-litellm-keys.sh` script.

> **Note:** The legacy AI Gateway (port 8090) is still present in docker-compose.yml but LiteLLM (port 4000) is the preferred AI proxy going forward.

---

## 6. AI-Assisted Development Workflows

### 6.1 Code Generation Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                   CODE GENERATION WORKFLOW                       │
│                                                                  │
│  1. Developer describes requirement                              │
│     ┌─────────────────────────────────────────────────────────┐ │
│     │ User: "Create a function that validates email addresses  │ │
│     │       and returns true if valid, false otherwise"        │ │
│     └─────────────────────────────────────────────────────────┘ │
│                              │                                   │
│                              ▼                                   │
│  2. AI generates code                                           │
│     ┌─────────────────────────────────────────────────────────┐ │
│     │ def validate_email(email: str) -> bool:                  │ │
│     │     import re                                            │ │
│     │     pattern = r'^[a-zA-Z0-9_.+-]+@...'                  │ │
│     │     return bool(re.match(pattern, email))               │ │
│     └─────────────────────────────────────────────────────────┘ │
│                              │                                   │
│                              ▼                                   │
│  3. Developer reviews and accepts/modifies                      │
│     ┌─────────────────────────────────────────────────────────┐ │
│     │ [Accept] [Modify] [Reject] [Generate Tests]             │ │
│     └─────────────────────────────────────────────────────────┘ │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 Refactoring Workflow

```markdown
## AI-Assisted Refactoring

1. Select code to refactor
2. Press `Cmd/Ctrl+I` or use `/edit` command
3. Describe the refactoring:
   - "Extract this into a separate function"
   - "Convert to async/await"
   - "Apply SOLID principles"
   - "Optimize for performance"
4. Review AI suggestions
5. Accept or iterate
```

### 6.3 Documentation Workflow

```markdown
## Auto-Generate Documentation

1. Select function/class
2. Use `/comment` or ask in chat:
   - "Add docstring to this function"
   - "Generate JSDoc comments"
   - "Create README for this module"
3. AI generates documentation
4. Review and adjust
```

### 6.4 Test Generation Workflow

```markdown
## AI-Assisted Test Generation

1. Select function to test
2. Use `/test` command or ask:
   - "Generate unit tests for this function"
   - "Add edge case tests"
   - "Create integration tests"
3. AI generates test cases
4. Review coverage
5. Add to test suite
```

---

## 7. Code Review with AI

### 7.1 AI Code Review Process

```
┌─────────────────────────────────────────────────────────────────┐
│                    AI CODE REVIEW WORKFLOW                       │
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │  Developer   │───>│  Git Push    │───>│   CI/CD      │      │
│  │  Commits     │    │  to Branch   │    │   Pipeline   │      │
│  └──────────────┘    └──────────────┘    └──────┬───────┘      │
│                                                  │               │
│                                    ┌─────────────┴─────────────┐│
│                                    │                           ││
│                                    ▼                           ▼│
│                           ┌──────────────┐            ┌────────┴┐
│                           │  AI Review   │            │  Human  │
│                           │   Service    │            │  Review │
│                           └──────┬───────┘            └────┬────┘
│                                  │                         │     │
│                                  ▼                         │     │
│                           ┌──────────────┐                │     │
│                           │   Review     │<───────────────┘     │
│                           │   Comments   │                      │
│                           └──────┬───────┘                      │
│                                  │                              │
│                                  ▼                              │
│                           ┌──────────────┐                      │
│                           │   Merge or   │                      │
│                           │   Revise     │                      │
│                           └──────────────┘                      │
└─────────────────────────────────────────────────────────────────┘
```

### 7.2 Using Roo Code for Code Review

```bash
# In VS Code with Roo Code

# 1. View git diff
git diff main...feature-branch

# 2. Ask Roo Code to review
# Open Roo Code chat and paste the diff, or ask:
"Review the recent changes in this branch for:
- Security vulnerabilities
- Performance issues
- Code style violations
- Potential bugs"

# Roo Code can also read files directly:
"Review the files I changed in the last commit"
```

### 7.3 Review Checklist (AI-Assisted)

```markdown
## AI Code Review Checklist

### Security
- [ ] No hardcoded credentials
- [ ] Input validation present
- [ ] SQL injection prevention
- [ ] XSS prevention
- [ ] Authentication checks

### Code Quality
- [ ] Functions are single-purpose
- [ ] Variable names are descriptive
- [ ] No code duplication
- [ ] Error handling present
- [ ] Comments where needed

### Performance
- [ ] No N+1 queries
- [ ] Efficient algorithms
- [ ] Resource cleanup
- [ ] Caching considered

### Testing
- [ ] Unit tests added
- [ ] Edge cases covered
- [ ] Test names are descriptive
```

### 7.4 Custom Review Workflows

Roo Code supports custom modes for project-specific review workflows. You can configure these through VS Code settings or by asking Roo Code directly:

```
# Security review
"Review this code for security vulnerabilities including: SQL injection, XSS,
CSRF, authentication bypass, sensitive data exposure. Provide specific line
numbers and remediation."

# Performance review
"Analyze this code for performance issues including: time complexity, space
complexity, database queries, memory leaks, unnecessary computations.
Suggest optimizations."

# Style review
"Review this code against our team's style guide. Check naming conventions,
file organization, comment quality, and code structure."
```

Roo Code's agentic capabilities allow it to read multiple files, understand project context, and provide more comprehensive reviews than command-based approaches.

---

## 8. Security & Compliance

### 8.1 Data Flow Security

```
┌─────────────────────────────────────────────────────────────────┐
│                    SECURE AI DATA FLOW                           │
│                                                                  │
│  Workspace ──────────────────────────────────────────> AI API   │
│      │                                                    │      │
│      │  1. Code/prompt sent via HTTPS                    │      │
│      │  2. No persistent storage of prompts              │      │
│      │  3. Response received                             │      │
│      │  4. Audit log: metadata only (no content)         │      │
│      │                                                    │      │
│      └──────────────────────────────────────────────────>│      │
│                                                                  │
│  Security Controls:                                             │
│  • TLS 1.2+ in transit                                         │
│  • No prompt logging (configurable)                            │
│  • Rate limiting per workspace                                 │
│  • API keys never exposed to workspaces                        │
│  • Audit trail for compliance                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 8.2 Compliance Considerations

| Requirement | Implementation |
|-------------|----------------|
| Data residency | Use regional Bedrock endpoints |
| Audit logging | AI Gateway logs all requests |
| Access control | Workspace-bound API access |
| Data retention | Configurable, default 30 days |
| PII handling | Do not send PII to AI (policy) |

### 8.3 Best Practices

```markdown
## AI Usage Best Practices

### DO:
✓ Use AI for code generation, review, documentation
✓ Review all AI-generated code before committing
✓ Use AI to explain unfamiliar code
✓ Leverage AI for test generation

### DON'T:
✗ Send production credentials to AI
✗ Include PII in prompts
✗ Blindly accept AI suggestions
✗ Share proprietary algorithms unnecessarily
✗ Bypass human code review
```

---

## 9. Configuration Reference

### 9.1 Environment Variables

```bash
# Coder AI Bridge (Server-level)
CODER_AIBRIDGE_BEDROCK_ACCESS_KEY=${AWS_ACCESS_KEY_ID}
CODER_AIBRIDGE_BEDROCK_ACCESS_KEY_SECRET=${AWS_SECRET_ACCESS_KEY}
CODER_AIBRIDGE_BEDROCK_REGION=${AWS_REGION:-us-east-1}
# Optional: Override default models
# CODER_AIBRIDGE_BEDROCK_MODEL=us.anthropic.claude-sonnet-4-5-20250929-v1:0
# CODER_AIBRIDGE_BEDROCK_SMALL_FAST_MODEL=us.anthropic.claude-haiku-4-5-20251001-v1:0

# LiteLLM Proxy
LITELLM_MASTER_KEY=sk-poc-litellm-master-key-change-in-production
LITELLM_DATABASE_URL=postgresql://litellm:litellm@postgres:5432/litellm
LITELLM_DEFAULT_USER_BUDGET=10.00
LITELLM_DEFAULT_RPM=60

# AWS Bedrock (used by LiteLLM for model routing)
AWS_ACCESS_KEY_ID=<aws-access-key>
AWS_SECRET_ACCESS_KEY=<aws-secret-key>
AWS_REGION=us-east-1

# Anthropic Direct API (optional, used by LiteLLM if configured)
ANTHROPIC_API_KEY=<optional-anthropic-key>

# Workspace-level (auto-configured)
LITELLM_API_KEY=<per-user-virtual-key>  # Generated by setup-litellm-keys.sh
AI_GATEWAY_URL=http://litellm:4000      # LiteLLM proxy endpoint
```

### 9.2 Workspace Template Parameters

```terraform
# AI Provider selection
data "coder_parameter" "ai_provider" {
  name         = "ai_provider"
  display_name = "AI Provider"
  type         = "string"
  default      = "bedrock"

  option {
    name  = "AWS Bedrock (Recommended)"
    value = "bedrock"
  }
  option {
    name  = "Anthropic API (Direct)"
    value = "anthropic"
  }
}

# AI Model selection
data "coder_parameter" "ai_model" {
  name         = "ai_model"
  display_name = "AI Model"
  type         = "string"
  default      = "claude-sonnet"

  option {
    name  = "Claude Sonnet 4.5 (Balanced)"
    value = "claude-sonnet"
  }
  option {
    name  = "Claude Haiku 4.5 (Fast)"
    value = "claude-haiku"
  }
  option {
    name  = "Claude Opus 4.5 (Advanced)"
    value = "claude-opus"
  }
}
```

---

## 10. Troubleshooting

### 10.1 Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| AI chat shows sign-in prompt | Bedrock not configured | Add `CODER_AIBRIDGE_BEDROCK_*` env vars |
| Roo Code not connecting | Wrong API key or URL | Check `LITELLM_API_KEY` env var and LiteLLM health |
| Rate limit errors | Too many requests | Increase RPM limit in LiteLLM key settings |
| Slow responses | Model overloaded | Try claude-haiku instead of claude-sonnet |
| Authentication errors | Invalid virtual key | Regenerate key via `setup-litellm-keys.sh` |
| LiteLLM 401 errors | Invalid or expired key | Check key with `curl http://localhost:4000/key/info` |
| LiteLLM 503 errors | Provider not configured | Check `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are set |
| Budget exceeded | User hit spending limit | Increase budget via LiteLLM admin API |

### 10.2 Diagnostic Commands

```bash
# Check LiteLLM health
curl http://localhost:4000/health

# Check available models
curl http://localhost:4000/v1/models \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}"

# Check LiteLLM logs
docker logs litellm --tail 50

# Check key info
curl http://localhost:4000/key/info \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -d '{"key": "<user-virtual-key>"}'

# Test LiteLLM with a virtual key
curl -X POST http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer <user-virtual-key>" \
  -H "Content-Type: application/json" \
  -d '{"model": "claude-sonnet", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 100}'

# Check user budget and usage
curl http://localhost:4000/user/info \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -d '{"user_id": "contractor1"}'

# Verify Bedrock credentials
aws bedrock list-foundation-models --region us-east-1

# Legacy: Check AI Gateway health (if still running)
curl http://localhost:8090/health
```

### 10.3 Performance Tuning

Select models based on your use case:

| Use Case | Recommended Model | Notes |
|----------|-------------------|-------|
| Fast iteration | `claude-haiku` | Fastest, lowest cost |
| General coding | `claude-sonnet` | Default, balanced |
| Complex architecture | `claude-opus` | Best reasoning, highest cost |

Model selection is configured per-workspace via the template parameter.

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-04 | Platform Team | Initial version |
| 1.1 | 2026-02-05 | Platform Team | Replace Continue/Cody with Roo Code; replace AI Gateway with LiteLLM |
