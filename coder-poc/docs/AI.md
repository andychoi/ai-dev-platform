# AI Integration Architecture - Dev Platform

This document describes how AI capabilities are integrated into the Coder WebIDE Development Platform, including API access, coding assistance, chat interfaces, and code review workflows.

## Table of Contents

1. [AI Architecture Overview](#1-ai-architecture-overview)
2. [AI Providers & Models](#2-ai-providers--models)
3. [Disabled AI Features (Copilot, Cody, AI Bridge)](#3-disabled-ai-features-copilot-cody-coder-ai-bridge)
4. [Roo Code Extension](#4-roo-code-extension)
5. [LiteLLM Proxy](#5-litellm-proxy)
6. [AI-Assisted Development Workflows](#6-ai-assisted-development-workflows)
7. [Code Review with AI](#7-code-review-with-ai)
8. [Security & Compliance](#8-security--compliance)
9. [Configuration Reference](#9-configuration-reference)
10. [Troubleshooting](#10-troubleshooting)
11. [LiteLLM Gateway Benefits](#11-litellm-gateway-benefits)
12. [Design-First AI Enforcement Layer](#12-design-first-ai-enforcement-layer)

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
│  │  │ Coder Chat   │  │   Roo Code   │  │  OpenCode +   │           │   │
│  │  │ (DISABLED)   │  │  (VS Code)    │  │  CLI Tools    │           │   │
│  │  └──────────────┘  └───────┬───────┘  └───────┬───────┘           │   │
│  └─────────────────────────────┼──────────────────┼─────────────────────┘   │
│                                │                  │                          │
│                                ▼                  ▼                          │
│                        ┌─────────────────┐  ┌─────────────────┐              │
│                        │  Roo Code API  │  │    LiteLLM      │              │
│                        │  (via LiteLLM) │  │    (Proxy)      │              │
│                        └────────┬────────┘  └────────┬────────┘              │
│                                 │                    │                        │
│                                 └────────────────────┘                        │
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
| ~~Chat Assistant~~ | ~~Coder Built-in~~ | ~~Disabled~~ | Use Roo Code chat instead |
| Code Completion | Roo Code | Bedrock/Anthropic (via LiteLLM) | Autocomplete while typing |
| Code Generation | Roo Code | Bedrock/Anthropic (via LiteLLM) | Generate code from description |
| Code Review | Roo Code | Bedrock/Anthropic (via LiteLLM) | Automated code review |
| Refactoring | Roo Code | Bedrock/Anthropic (via LiteLLM) | Code improvement suggestions |
| Documentation | Roo Code | Bedrock/Anthropic (via LiteLLM) | Generate docs/comments |
| Test Generation | Roo Code | Bedrock/Anthropic (via LiteLLM) | Generate unit tests |
| CLI AI Agent | OpenCode CLI | Bedrock/Anthropic (via LiteLLM) | Terminal-based agentic coding |
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

## 3. Disabled AI Features (Copilot, Cody, Coder AI Bridge)

### 3.1 Overview

All built-in and third-party AI chat features are **explicitly disabled** in this platform. AI capabilities are provided exclusively through **Roo Code + LiteLLM** for centralized control, auditing, and cost management.

### 3.2 What is Disabled

| Feature | How Disabled | Why |
|---------|-------------|-----|
| **Coder AI Bridge** | `CODER_AIBRIDGE_ENABLED=false`, `CODER_HIDE_AI_TASKS=true` | Bypasses LiteLLM proxy; no per-user budgets or audit |
| **GitHub Copilot** | Extension uninstalled in Dockerfile; all `github.copilot.*` settings set to `false` | Proprietary; requires GitHub sign-in; not available on Open VSX |
| **Copilot Chat** | `github.copilot.chat.enabled=false`; extension uninstalled | Same as Copilot; not compatible with code-server |
| **VS Code inline chat** | `inlineChat.mode=off` | Part of Copilot ecosystem |
| **VS Code inline suggestions** | `editor.inlineSuggest.enabled=false` | Prevents ghost-text from non-LiteLLM sources |
| **VS Code chat panel** | `chat.agent.enabled=false`, `chat.commandCenter.enabled=false` | Built-in chat not available in code-server (Copilot not in VS Code OSS core yet) |
| **Sourcegraph Cody** | `cody.enabled=false`, `cody.autocomplete.enabled=false`; extension uninstalled | Requires external Sourcegraph auth |
| **GitHub default OAuth** | `CODER_OAUTH2_GITHUB_DEFAULT_PROVIDER_ENABLE=false` | Prevents GitHub sign-in popup in Coder UI |

### 3.3 Lockdown Implementation

**Layer 1 — Coder Server (docker-compose.yml):**
```yaml
environment:
  CODER_AIBRIDGE_ENABLED: "false"
  CODER_HIDE_AI_TASKS: "true"
  CODER_OAUTH2_GITHUB_DEFAULT_PROVIDER_ENABLE: "false"
```

**Layer 2 — VS Code Settings (settings.json):**
```json
{
  "chat.agent.enabled": false,
  "chat.commandCenter.enabled": false,
  "github.copilot.enable": { "*": false },
  "github.copilot.editor.enableAutoCompletions": false,
  "github.copilot.chat.enabled": false,
  "github.copilot.renameSuggestions.triggerAutomatically": false,
  "inlineChat.mode": "off",
  "editor.inlineSuggest.enabled": false,
  "cody.enabled": false,
  "cody.autocomplete.enabled": false
}
```

**Layer 3 — Dockerfile (explicit extension removal):**
```dockerfile
# Remove Copilot/Cody if present from base image or sideload
RUN code-server --uninstall-extension github.copilot 2>/dev/null || true \
    && code-server --uninstall-extension github.copilot-chat 2>/dev/null || true \
    && code-server --uninstall-extension sourcegraph.cody-ai 2>/dev/null || true
```

### 3.4 Why Not Use code-server's Built-in Chat?

code-server v4.108.2 (based on VS Code 1.108.2 stable) does **not** have a usable built-in AI chat:

1. **`github.copilot.chat.customOAIModels`** (Bring Your Own Key) is VS Code Insiders-only — not graduated to stable
2. **Copilot Chat** is not available on Open VSX (code-server's extension marketplace)
3. **VS Code OSS core** has not yet fully integrated the open-sourced Copilot Chat (in progress as of early 2026)
4. **Sideloading Copilot** causes authentication errors and hangs in code-server

Once VS Code OSS integrates the open-sourced chat with custom model support, code-server will inherit it automatically. Until then, **Roo Code is the primary AI interface**.

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

Keys are **auto-provisioned** during workspace creation by the **key-provisioner** microservice (port 8100). The provisioner isolates the LiteLLM master key — workspace containers never see it. Keys can also be generated manually via `setup-litellm-keys.sh` or self-service via `generate-ai-key.sh`.

See `docs/KEY-MANAGEMENT.md` for the full key taxonomy (workspace, user, CI, agent scopes) and management workflows.

> **Note:** The legacy AI Gateway (port 8090) has been replaced by LiteLLM (port 4000) as the AI proxy.

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
# Coder AI Bridge (DISABLED - we use Roo Code + LiteLLM instead)
CODER_AIBRIDGE_ENABLED=false
CODER_HIDE_AI_TASKS=true

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
# AI Model selection (routed through LiteLLM)
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
| AI chat shows sign-in prompt | AI Bridge or Copilot not fully disabled | Verify `CODER_AIBRIDGE_ENABLED=false` and all Copilot settings in `settings.json` |
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

## 11. LiteLLM Gateway Benefits

Sections 4–5 describe **how** LiteLLM and Roo Code are configured. This section explains **why** the centralized gateway approach is valuable — and how platform administrators and developers can leverage it for cost control, usage analytics, and continuous improvement of AI-assisted development.

### 11.1 Why a Centralized AI Gateway

Routing all AI traffic through LiteLLM provides capabilities that are impossible when developers call provider APIs directly.

| Dimension | Direct API Access | LiteLLM Gateway |
|-----------|-------------------|-----------------|
| **Cost control** | Each developer manages own budget | Centralized per-user budgets with hard limits |
| **Audit trail** | No visibility into usage | Every request logged with user, model, tokens, latency |
| **Multi-provider routing** | Developer manages provider keys | Gateway routes to Bedrock, Anthropic, or future providers transparently |
| **Prompt analytics** | No data to analyze | Aggregated metrics reveal usage patterns and efficiency |
| **Developer coaching** | No feedback loop | Token and error metrics enable targeted improvement |
| **Budget enforcement** | Honor system | Hard spend caps per user/team with automatic cutoff |
| **Rate limiting** | Provider-level only | Per-user RPM/TPM limits prevent noisy-neighbor issues |
| **Key isolation** | Raw API keys in workspaces | Workspaces only see scoped virtual keys; master key never exposed |

### 11.2 Token Metrics & Cost Allocation

LiteLLM tracks token usage at every layer — per-request, per-user, and per-workspace — enabling detailed cost attribution.

#### What Is Tracked Per Request

| Metric | Description |
|--------|-------------|
| Input tokens | Tokens in the prompt (user message + context) |
| Output tokens | Tokens in the model response |
| Model | Which model was used (e.g., `claude-sonnet`, `claude-haiku`) |
| Latency | End-to-end response time |
| Cost | Calculated cost based on model pricing |
| User ID | Which user made the request (from virtual key) |
| Workspace ID | Which workspace the request originated from (from key metadata) |
| Status | Success or failure (and error type if failed) |

#### Data Flow

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Roo Code /  │────>│   LiteLLM    │────>│  PostgreSQL  │────>│  Dashboard / │
│  OpenCode    │     │   Proxy      │     │  (spend_logs)│     │  Admin API   │
│              │     │              │     │              │     │              │
│  Request     │     │  • Auth      │     │  • token_ct  │     │  • /ui       │
│  with        │     │  • Route     │     │  • cost      │     │  • /spend/   │
│  virtual key │     │  • Log       │     │  • user_id   │     │    logs      │
│              │     │  • Callback  │     │  • model     │     │  • /global/  │
│              │     │              │     │  • timestamp │     │    spend     │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
```

#### How to Access Token Metrics

| Method | Who | How |
|--------|-----|-----|
| **Workspace self-service** | Developers | `ai-usage` alias (shows personal spend) |
| **Model listing** | Developers | `ai-models` alias (shows available models) |
| **LiteLLM Admin UI** | Admins | `http://litellm:4000/ui` — visual dashboard for keys, spend, and models |
| **Platform Admin dashboard** | Admins | Port 5050 — platform-wide AI spend overview |
| **Spend logs API** | Admins | `GET /spend/logs` — per-request spend details |
| **Global spend API** | Admins | `GET /global/spend/logs` — aggregated spend across all users |
| **User info API** | Admins | `GET /user/info` — per-user budget remaining and total spend |

#### Cost Breakdown by Model Tier

| Tier | Model | Relative Cost | Best For |
|------|-------|---------------|----------|
| $ | Claude Haiku 4.5 | Lowest | Autocomplete, quick tasks, simple Q&A |
| $$ | Claude Sonnet 4.5 | Medium | General coding, code review, test generation |
| $$$ | Claude Opus 4.5 | Highest | Complex architecture, multi-file refactoring |

Tracking cost per model tier helps administrators identify optimization opportunities — for example, if 60% of spend goes to Opus but most tasks are simple code generation, there's an opportunity to encourage Sonnet or Haiku usage.

### 11.3 Prompt Logging & Analysis

The gateway enables analysis of AI usage patterns to improve efficiency and outcomes.

#### What Is Captured

LiteLLM's `log_to_db` callbacks capture **request metadata** for every AI call:

- Timestamp and duration
- User ID and workspace ID
- Model name and provider
- Input and output token counts
- Success/failure status and error type
- Cost (calculated from token counts and model pricing)

#### Privacy-First Approach

> **Important:** Prompt content (the actual messages sent to the AI) is **NOT stored by default**. Only metadata is logged. Content logging is opt-in and requires explicit configuration by a platform administrator.

This means out-of-the-box:
- Admins can see *how much* each user is using AI, *which models*, and *at what cost*
- Admins **cannot** see *what* developers are asking the AI
- Content logging, if enabled for coaching/training programs, should follow organizational privacy policies

#### Analytics Enabled by Metadata (No Content Logging Required)

| Insight | How It's Derived |
|---------|-----------------|
| Usage volume per user | Count of requests per user over time |
| Cost per user/team | Sum of per-request costs grouped by user |
| Model preference distribution | Count of requests per model across the platform |
| Error rate per user | Ratio of failed to successful requests |
| Token efficiency trends | Average tokens per request over time (declining = improving) |
| Peak usage periods | Request volume by hour/day for capacity planning |
| Inactive users | Virtual keys with zero spend (unused AI allocation) |

#### When Content Logging Is Enabled (Opt-In)

For organizations that choose to enable content logging (e.g., for AI training programs):

- Admins can review prompt patterns to identify common anti-patterns (e.g., prompts that lack context, overly broad requests)
- Aggregated prompt statistics reveal which teams/users get the best results per token
- Token-to-output-quality ratio helps identify inefficient prompting styles
- Patterns can be anonymized and used to build organization-specific prompt engineering guides

#### Relevant API Endpoints

```bash
# Per-user spend details
curl -s http://litellm:4000/spend/logs \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -d '{"user_id": "contractor1"}'

# Global spend across all users
curl -s http://litellm:4000/global/spend/logs \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -d '{"start_date": "2026-02-01", "end_date": "2026-02-28"}'
```

### 11.4 Developer Skill Improvement through AI Usage Insights

The gateway's analytics create a feedback loop that helps developers become more effective at using AI tools.

#### Token Efficiency Tracking

Developers who write clear, specific prompts use fewer tokens and get better results. The gateway surfaces metrics like average tokens per successful task completion. Over time, developers can see their own efficiency trends via the `ai-usage` command and adjust their approach.

#### Model Selection Guidance

Analytics show when developers routinely use expensive models (Opus) for simple tasks that Haiku could handle. Administrators can share model selection guidance:

- **Haiku** — autocomplete, simple Q&A, boilerplate generation
- **Sonnet** — code review, multi-file changes, test generation
- **Opus** — complex architecture decisions, novel problem-solving

#### Prompt Pattern Recognition

Aggregated data reveals which prompt structures yield better outcomes:

- **Effective:** providing file context + examples + constraints ("Refactor this function to use async/await. Here's the current code: ...")
- **Less effective:** vague requests without context ("Fix the bug")

These patterns can be compiled into team-specific prompt engineering guides.

#### Usage Trend Coaching

Teams with declining token efficiency or increasing error rates may benefit from:

- Prompt engineering workshops
- Pair programming sessions focused on AI interaction
- Sharing best practices from high-efficiency team members

#### Comparative Benchmarking

Anonymized team-level metrics help identify and propagate best practices. For example, "Team A uses 40% fewer tokens for similar tasks because they provide file context upfront in their prompts."

#### Prompt Quality Indicators

| Indicator | What It Measures | Good Sign | Improvement Opportunity |
|-----------|-----------------|-----------|------------------------|
| Tokens per task | Efficiency | Lower count, successful outcome | Write more specific prompts |
| Retry rate | First-attempt success | Few retries | Provide more context upfront |
| Model match | Right-sizing | Haiku for simple, Sonnet for complex | Review model selection guidance |
| Error rate | Prompt clarity | Low error rate | Improve prompt structure |
| Budget utilization | Value extraction | Steady, predictable spend | Identify unused capacity or waste |

### 11.5 Admin Analytics Capabilities

Platform administrators have access to comprehensive AI usage data through multiple interfaces.

#### Dashboard & Reporting

| Capability | Interface | Description |
|------------|-----------|-------------|
| Platform-wide AI spend | Platform Admin (port 5050) | Total spend, trends, and forecasts |
| Per-user consumption | LiteLLM Admin UI (`/ui`) | Token usage and cost per virtual key |
| Per-team aggregation | Spend logs API | Group by key metadata for team-level reporting |
| Model popularity | Admin UI / API | Which models are used most and their cost distribution |
| Budget threshold alerts | LiteLLM config | Proactive alerts when users approach budget limits |
| Provider health | LiteLLM logs | Bedrock vs Anthropic success rates and latency |
| Unused key detection | Key info API | Keys with zero spend indicate inactive users |

#### Actionable Admin Workflows

1. **Monthly cost review** — Query `/global/spend/logs` for the period, group by user/team, compare against budgets
2. **Right-sizing budgets** — Identify users consistently under or over budget and adjust allocations
3. **Model optimization** — If Opus spend is disproportionately high, publish guidance on when to use cheaper models
4. **Onboarding effectiveness** — Compare token efficiency of new vs experienced users to gauge AI onboarding quality
5. **Capacity planning** — Use peak-hour request volumes to plan for scaling (relevant in production deployments)
6. **Inactive user cleanup** — Identify virtual keys with no recent spend and deactivate to maintain hygiene

---

## 12. Design-First AI Enforcement Layer

### 12.1 Overview

The enforcement layer controls how AI agents approach development tasks. It replicates the qualities that make Claude Code CLI effective — opinionated system prompts, forced design-before-code loops, and tool discipline — and applies them server-side through LiteLLM.

### 12.2 Enforcement Levels

| Level | System Prompt Injected | Design Proposal Required | Code in First Response | Use Case |
|-------|----------------------|--------------------------|----------------------|----------|
| `unrestricted` | No | No | Allowed | Quick tasks, experienced devs |
| `standard` | Lightweight reasoning | No (encouraged) | Allowed | Daily development (default) |
| `design-first` | Full architect mode | Yes (mandatory) | Blocked | Complex features, new contractors |

### 12.3 How It Works

**Server-side (tamper-proof):** A LiteLLM `CustomLogger` callback reads `enforcement_level` from the virtual key's metadata and prepends the appropriate system prompt to every chat completion request. Users cannot bypass this — it's enforced at the proxy layer.

**Client-side (UX reinforcement):** The workspace startup script also configures enforcement instructions directly in Roo Code (`customInstructions`) and OpenCode (`instructions` file). This gives the AI agent upfront context in addition to the server-side prompt.

```
┌─────────────────────────────────────────────────────┐
│  Workspace Template Parameter                        │
│  ai_enforcement_level: standard | design-first |     │
│                        unrestricted                  │
└────────────────┬────────────────────┬────────────────┘
                 │                    │
    ┌────────────▼──────────┐  ┌─────▼──────────────────┐
    │  Key Provisioner      │  │  Startup Script         │
    │  stores level in      │  │  writes client configs  │
    │  key metadata         │  │  with matching prompts  │
    └────────────┬──────────┘  └─────┬──────────────────┘
                 │                    │
    ┌────────────▼──────────┐  ┌─────▼──────────────────┐
    │  LiteLLM Hook         │  │  Roo Code settings.json │
    │  (SERVER-SIDE)        │  │  OpenCode enforcement.md│
    │  reads key metadata   │  │  (CLIENT-SIDE)          │
    │  injects prompt       │  │  advisory reinforcement │
    │  TAMPER-PROOF         │  │                         │
    └───────────────────────┘  └─────────────────────────┘
```

### 12.4 Configuration

Users select their enforcement level when creating or updating a workspace:

- **AI Behavior Mode** parameter in the workspace template
- Default: `standard`
- Mutable: Yes (can be changed without recreating workspace, but server-side level on existing keys persists — see note below)

**Key files:**

| File | Purpose |
|------|---------|
| `litellm/enforcement_hook.py` | LiteLLM callback — reads metadata, injects prompt |
| `litellm/prompts/unrestricted.md` | Empty (no injection) |
| `litellm/prompts/standard.md` | Lightweight reasoning prompt |
| `litellm/prompts/design-first.md` | Full architect-mode prompt |
| `key-provisioner/app.py` | Stores enforcement_level in key metadata |
| `templates/contractor-workspace/main.tf` | Template parameter + client configs |

### 12.5 Prompt Editing

Prompts are loaded from `/app/prompts/*.md` inside the LiteLLM container (bind-mounted from `coder-poc/litellm/prompts/`). They are cached by file modification time — edit the files on the host and changes take effect on the next API call without restarting LiteLLM.

### 12.6 Idempotency Note

When a workspace key already exists (workspace restart), the enforcement level from the original key creation is used. Changing the template parameter alone won't update server-side enforcement for existing keys — the key must be rotated. This is a security benefit (prevents downgrade attacks) and is acceptable for PoC.

### 12.7 Verification

```bash
# Run the enforcement layer test suite
./scripts/test-enforcement.sh

# Check LiteLLM logs for enforcement hook loading
docker logs litellm 2>&1 | grep enforcement

# Test enforcement injection manually
curl -s http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer <workspace-key>" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-sonnet-4-5","messages":[{"role":"user","content":"hello"}],"max_tokens":10}'
```

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-04 | Platform Team | Initial version |
| 1.1 | 2026-02-05 | Platform Team | Replace Continue/Cody with Roo Code; replace AI Gateway with LiteLLM |
| 1.2 | 2026-02-05 | Platform Team | Disable Copilot/Cody/AI Bridge; document three-layer lockdown |
| 1.3 | 2026-02-06 | Platform Team | Add OpenCode CLI, key-provisioner service, auto-provisioning |
| 1.4 | 2026-02-06 | Platform Team | Add Section 11: LiteLLM Gateway Benefits (analytics, coaching, admin capabilities) |
| 1.5 | 2026-02-06 | Platform Team | Add Section 12: Design-First AI Enforcement Layer |
