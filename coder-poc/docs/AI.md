# AI Integration Architecture - Dev Platform

This document describes how AI capabilities are integrated into the Coder WebIDE Development Platform, including API access, coding assistance, chat interfaces, and code review workflows.

## Table of Contents

1. [AI Architecture Overview](#1-ai-architecture-overview)
2. [AI Providers & Models](#2-ai-providers--models)
3. [Coder AI Bridge](#3-coder-ai-bridge)
4. [Continue Extension](#4-continue-extension)
5. [AI Gateway](#5-ai-gateway)
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
│  │  │  Coder Chat   │  │   Continue    │  │  CLI Tools    │           │   │
│  │  │  (Built-in)   │  │  (VS Code)    │  │  (Terminal)   │           │   │
│  │  └───────┬───────┘  └───────┬───────┘  └───────┬───────┘           │   │
│  └──────────┼──────────────────┼──────────────────┼─────────────────────┘   │
│             │                  │                  │                          │
│             ▼                  ▼                  ▼                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐              │
│  │   AI Bridge     │  │  Continue API   │  │   AI Gateway    │              │
│  │ (Coder Server)  │  │   (Direct)      │  │    (Proxy)      │              │
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
| Code Completion | Continue Extension | Bedrock/Anthropic | Autocomplete while typing |
| Code Generation | Continue Extension | Bedrock/Anthropic | Generate code from description |
| Code Review | Continue/Custom | Bedrock/Anthropic | Automated code review |
| Refactoring | Continue Extension | Bedrock/Anthropic | Code improvement suggestions |
| Documentation | Continue Extension | Bedrock/Anthropic | Generate docs/comments |
| Test Generation | Continue Extension | Bedrock/Anthropic | Generate unit tests |
| CLI Assistant | Terminal Tools | AI Gateway | Shell commands, debugging |

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

## 4. Continue Extension

### 4.1 Overview

[Continue](https://continue.dev) is an open-source AI coding assistant that integrates with VS Code (and code-server). It provides:

- **Tab Autocomplete** - AI-powered code suggestions
- **Chat Sidebar** - In-IDE chat with context
- **Inline Editing** - Edit code with AI assistance
- **Custom Commands** - Project-specific AI commands

### 4.2 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    CODE-SERVER (VS Code in Browser)              │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                     CONTINUE EXTENSION                      │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │ │
│  │  │   Chat      │  │ Autocomplete│  │  Commands   │        │ │
│  │  │   Panel     │  │   Engine    │  │   /edit     │        │ │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘        │ │
│  │         │                │                │                │ │
│  │         └────────────────┼────────────────┘                │ │
│  │                          │                                  │ │
│  │                    ┌─────┴─────┐                           │ │
│  │                    │  Continue │                           │ │
│  │                    │   Core    │                           │ │
│  │                    └─────┬─────┘                           │ │
│  └──────────────────────────┼─────────────────────────────────┘ │
│                             │                                    │
│                             ▼                                    │
│                    ┌─────────────────┐                          │
│                    │  ~/.continue/   │                          │
│                    │  config.json    │                          │
│                    └────────┬────────┘                          │
│                             │                                    │
└─────────────────────────────┼────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │   AWS Bedrock   │
                    │   or AI Gateway │
                    └─────────────────┘
```

### 4.3 Configuration

Configuration is stored in `~/.continue/config.json` and is automatically generated based on workspace parameters:

```json
{
  "models": [
    {
      "title": "Claude Sonnet (Bedrock)",
      "provider": "bedrock",
      "model": "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
      "region": "${AWS_REGION}",
      "profile": "default"
    },
    {
      "title": "Claude Haiku (Bedrock)",
      "provider": "bedrock",
      "model": "us.anthropic.claude-haiku-4-5-20251001-v1:0",
      "region": "${AWS_REGION}",
      "profile": "default"
    },
    {
      "title": "Claude Sonnet (Anthropic API)",
      "provider": "anthropic",
      "model": "claude-sonnet-4-5-20250929",
      "apiBase": "${AI_GATEWAY_URL}/v1"
    }
  ],
  "tabAutocompleteModel": {
    "title": "Claude Haiku (Fast)",
    "provider": "bedrock",
    "model": "us.anthropic.claude-haiku-4-5-20251001-v1:0",
    "region": "${AWS_REGION}"
  },
  "embeddingsProvider": {
    "provider": "transformers.js"
  },
  "contextProviders": [
    { "name": "code" },
    { "name": "docs" },
    { "name": "diff" },
    { "name": "terminal" },
    { "name": "problems" },
    { "name": "folder" },
    { "name": "codebase" }
  ],
  "slashCommands": [
    { "name": "edit", "description": "Edit selected code" },
    { "name": "comment", "description": "Add comments to code" },
    { "name": "share", "description": "Share code snippet" },
    { "name": "cmd", "description": "Generate shell command" },
    { "name": "commit", "description": "Generate commit message" }
  ],
  "customCommands": [
    {
      "name": "review",
      "prompt": "Review this code for bugs, security issues, and improvements.",
      "description": "Code review"
    },
    {
      "name": "test",
      "prompt": "Write comprehensive unit tests for this code.",
      "description": "Generate tests"
    },
    {
      "name": "explain",
      "prompt": "Explain this code in detail.",
      "description": "Explain code"
    }
  ],
  "allowAnonymousTelemetry": false
}
```

### 4.4 Key Features

| Feature | Shortcut | Description |
|---------|----------|-------------|
| **Chat** | `Cmd/Ctrl+L` | Open chat sidebar |
| **Autocomplete** | `Tab` | Accept AI suggestion |
| **Edit Selection** | `Cmd/Ctrl+I` | Edit selected code with AI |
| **Add to Context** | `Cmd/Ctrl+Shift+L` | Add file/selection to chat |
| **Generate Tests** | `/test` | Generate unit tests |
| **Explain Code** | `/explain` | Explain selected code |
| **Review Code** | `/review` | Review code for issues |

### 4.5 Context Providers

Continue can access various context sources to provide better assistance:

| Provider | Description | Configuration |
|----------|-------------|---------------|
| `code` | Current file and selection | Automatic |
| `docs` | Project documentation | Automatic |
| `diff` | Git diff (staged/unstaged) | Automatic |
| `terminal` | Recent terminal output | Automatic |
| `problems` | VS Code problems panel | Automatic |
| `codebase` | Index entire codebase | Requires embeddings |
| `folder` | Specific folder contents | Manual |

---

## 5. AI Gateway

### 5.1 Overview

The AI Gateway is a **custom proxy service** that provides:

- Centralized API key management
- Request/response logging
- Rate limiting
- Provider abstraction
- Audit trail for compliance

### 5.2 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         AI GATEWAY                               │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                     INGRESS LAYER                           │ │
│  │  • Authentication (workspace token)                         │ │
│  │  • Rate limiting (per workspace)                            │ │
│  │  • Request validation                                       │ │
│  └─────────────────────────┬──────────────────────────────────┘ │
│                            │                                     │
│  ┌─────────────────────────┼──────────────────────────────────┐ │
│  │                   ROUTING LAYER                             │ │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐       │ │
│  │  │/v1/     │  │/v1/     │  │/v1/chat │  │/v1/     │       │ │
│  │  │bedrock  │  │claude   │  │complete │  │gemini   │       │ │
│  │  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘       │ │
│  └───────┼────────────┼────────────┼────────────┼─────────────┘ │
│          │            │            │            │                │
│  ┌───────┼────────────┼────────────┼────────────┼─────────────┐ │
│  │       │      PROVIDER ADAPTERS  │            │              │ │
│  │  ┌────┴────┐  ┌────┴────┐  ┌────┴────┐  ┌────┴────┐       │ │
│  │  │ Bedrock │  │Anthropic│  │ OpenAI  │  │  Gemini │       │ │
│  │  │ Adapter │  │ Adapter │  │ Adapter │  │ Adapter │       │ │
│  │  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘       │ │
│  └───────┼────────────┼────────────┼────────────┼─────────────┘ │
│          │            │            │            │                │
│  ┌───────┼────────────┼────────────┼────────────┼─────────────┐ │
│  │       │       AUDIT LOGGING     │            │              │ │
│  │  • Request metadata             • Token usage               │ │
│  │  • Workspace ID                 • Response time             │ │
│  │  • User context                 • Error tracking            │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 5.3 Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/v1/chat/completions` | POST | Unified chat (routes to appropriate provider) |
| `/v1/claude/{path}` | GET/POST/PUT/DELETE | Anthropic Claude API proxy |
| `/v1/bedrock/invoke` | POST | AWS Bedrock model invocation |
| `/v1/bedrock/models` | GET | List available Bedrock models |
| `/v1/gemini/{path}` | GET/POST | Google Gemini API proxy (planned) |
| `/v1/usage` | GET | Token usage stats |
| `/v1/providers` | GET | Available providers |

### 5.4 Configuration

```yaml
# ai-gateway/config.yaml
server:
  port: 8090
  host: "0.0.0.0"
  read_timeout: 120s
  write_timeout: 120s

providers:
  anthropic:
    enabled: true
    base_url: "https://api.anthropic.com"
    api_version: "2023-06-01"
    models:
      - claude-sonnet-4-5-20250929
      - claude-haiku-4-5-20251001
      - claude-opus-4-20250514
    default_model: claude-sonnet-4-5-20250929

  bedrock:
    enabled: true
    region: "${AWS_REGION:-us-east-1}"
    models:
      - us.anthropic.claude-sonnet-4-5-20250929-v1:0
      - us.anthropic.claude-haiku-4-5-20251001-v1:0
      - us.anthropic.claude-opus-4-20250514-v1:0
    default_model: us.anthropic.claude-sonnet-4-5-20250929-v1:0

  gemini:
    enabled: false  # Enable when ready
    base_url: "https://generativelanguage.googleapis.com"

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
      tokens_per_minute: 500000

audit:
  enabled: true
  log_level: info
  log_format: json
  include_prompt: false   # Privacy: don't log prompts
  include_response: false # Privacy: don't log responses
  log_file: /var/log/ai-gateway/audit.log
```

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

### 7.2 Using Continue for Code Review

```bash
# In VS Code with Continue

# 1. View git diff
git diff main...feature-branch

# 2. Add diff to Continue context
# Select diff output, press Cmd/Ctrl+Shift+L

# 3. Ask for review
/review

# Or more specific:
"Review this code for:
- Security vulnerabilities
- Performance issues
- Code style violations
- Potential bugs"
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

### 7.4 Custom Review Commands

Add custom commands to Continue for project-specific reviews:

```json
// ~/.continue/config.json
{
  "customCommands": [
    {
      "name": "security-review",
      "prompt": "Review this code for security vulnerabilities including: SQL injection, XSS, CSRF, authentication bypass, sensitive data exposure. Provide specific line numbers and remediation.",
      "description": "Security-focused code review"
    },
    {
      "name": "perf-review",
      "prompt": "Analyze this code for performance issues including: time complexity, space complexity, database queries, memory leaks, unnecessary computations. Suggest optimizations.",
      "description": "Performance-focused review"
    },
    {
      "name": "style-review",
      "prompt": "Review this code against our team's style guide. Check naming conventions, file organization, comment quality, and code structure.",
      "description": "Style guide compliance review"
    }
  ]
}
```

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

# AI Gateway
AI_GATEWAY_PORT=8090
ANTHROPIC_API_KEY=<optional-anthropic-key>
AWS_ACCESS_KEY_ID=<aws-access-key>
AWS_SECRET_ACCESS_KEY=<aws-secret-key>
AWS_REGION=us-east-1
GOOGLE_API_KEY=<optional-google-key>  # For Gemini (planned)
AI_RATE_LIMIT_RPM=60

# AI Gateway Security (docker-compose.yml)
AI_GATEWAY_AUTH_ENABLED=true           # Set false for local dev only
AI_GATEWAY_AUTH_SECRET=<shared-secret> # For service-to-service auth
AI_GATEWAY_ALLOWED_ORIGINS=http://localhost:7080,http://host.docker.internal:7080
CODER_URL=http://coder-server:7080     # For token validation

# DevDB connection (usage tracking)
DEVDB_HOST=devdb
DEVDB_PORT=5432
DEVDB_USER=ai_gateway
DEVDB_PASSWORD=${DEVDB_AI_GATEWAY_PASSWORD:-aigateway123}
DEVDB_NAME=devdb

# Workspace-level (auto-configured)
AI_PROVIDER=bedrock
AI_MODEL=claude-sonnet
AI_GATEWAY_URL=http://ai-gateway:8090
AWS_REGION=us-east-1
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
| Continue not connecting | Wrong config | Check `~/.continue/config.json` |
| Rate limit errors | Too many requests | Reduce request frequency |
| Slow responses | Model overloaded | Try Haiku instead of Sonnet |
| Authentication errors | Invalid credentials | Verify AWS keys/permissions |
| Gateway 401 errors | Auth enabled but no token | Set `AI_GATEWAY_AUTH_ENABLED=false` for dev, or provide Bearer token |
| Gateway 503 errors | Provider not configured | Check `ANTHROPIC_API_KEY` or `AWS_ACCESS_KEY_ID` are set |

### 10.2 Diagnostic Commands

```bash
# Check AI Gateway health
curl http://localhost:8090/health

# Check available providers
curl http://localhost:8090/v1/providers

# Check AI Gateway logs
docker logs ai-gateway --tail 50

# Verify Bedrock credentials (from workspace)
aws bedrock list-foundation-models --region us-east-1

# Check Continue config
cat ~/.continue/config.json

# Test AI Gateway with authentication (using Coder session token)
curl -X POST http://localhost:8090/v1/chat/completions \
  -H "Authorization: Bearer <coder-session-token>" \
  -H "Content-Type: application/json" \
  -d '{"model": "claude-sonnet-4-5-20250929", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 100}'

# Test with API key (service-to-service)
curl -X POST http://localhost:8090/v1/chat/completions \
  -H "X-API-Key: <shared-secret>" \
  -H "X-Workspace-ID: test-workspace" \
  -H "Content-Type: application/json" \
  -d '{"model": "claude-sonnet-4-5-20250929", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 100}'

# Test Bedrock directly
aws bedrock-runtime invoke-model \
  --model-id us.anthropic.claude-sonnet-4-5-20250929-v1:0 \
  --body '{"prompt": "Hello", "max_tokens": 10}' \
  --region us-east-1 \
  output.json
```

### 10.3 Performance Tuning

```yaml
# Optimize for speed
tabAutocompleteModel:
  model: "claude-haiku"  # Faster model

# Optimize for quality
models:
  - model: "claude-opus"  # Better reasoning

# Balance
models:
  - model: "claude-sonnet"  # Default, balanced
```

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-04 | Platform Team | Initial version |
