# Frequently Asked Questions - Dev Platform

This FAQ document answers common questions for end users (contractors/developers) and app managers about using the Coder WebIDE Development Platform.

## Table of Contents

1. [Getting Started](#1-getting-started)
2. [Workspaces](#2-workspaces)
3. [IDE & Coding](#3-ide--coding)
4. [AI Assistant](#4-ai-assistant)
5. [Git & Version Control](#5-git--version-control)
6. [Collaboration](#6-collaboration)
7. [Troubleshooting](#7-troubleshooting)
8. [App Manager Questions](#8-app-manager-questions)
9. [Security & Compliance](#9-security--compliance)

---

## 1. Getting Started

### Q: How do I access the platform?

**A:** Open your web browser and navigate to the platform URL provided by your admin.

**PoC Access:**
```
https://host.docker.internal:7443
```

On first visit you'll see a browser certificate warning (self-signed cert) — accept it to continue. If you want to eliminate the warning permanently:

```bash
# macOS — trust the self-signed cert
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  "$(pwd)/coder-poc/certs/coder.crt"
```

Log in with your credentials (SSO or local account).

---

### Q: What credentials do I need?

**A:** You need:
- **Platform login**: Username and password (or SSO if configured)
- **Git credentials**: Username and password for the Git server (provided separately)
- **No AI credentials needed**: AI features work automatically

**PoC Default Credentials:**

| System | Username | Password |
|--------|----------|----------|
| Coder (SSO) | contractor1 | `Contractor123!` (via Authentik) |
| Gitea | contractor1 | `password123` |

> Note: In production, SSO/OIDC will be used instead of local passwords. Log in via "Sign in with SSO" on the Coder login page.

---

### Q: Which browser should I use?

**A:** We recommend:
- ✅ Google Chrome (latest) — best compatibility
- ✅ Microsoft Edge (latest)
- ✅ Mozilla Firefox (latest)
- ⚠️ Safari (works, but Chrome/Edge preferred)

> **Important (PoC):** The platform uses HTTPS with a self-signed certificate. You must accept the browser's certificate warning on first visit. If extension panels (like Roo Code) appear blank, see the [Secure Context troubleshooting](#q-extension-panels-are-blank-roo-code-etc) section below.

---

### Q: Can I use VS Code Desktop instead of the browser?

**A:** No. For security reasons, VS Code Desktop connections are disabled. All development is done through the secure browser-based IDE (code-server).

---

### Q: Can I SSH into my workspace?

**A:** No. SSH access is disabled for security. Use the web-based terminal instead, which provides the same functionality.

---

## 2. Workspaces

### Q: What is a workspace?

**A:** A workspace is your personal development environment. It's a container that includes:
- VS Code IDE (in browser)
- Terminal access
- Pre-installed development tools
- Your project files
- AI coding assistance

Think of it as your own virtual development machine.

---

### Q: How do I create a workspace?

**A:**
1. Log into the platform
2. Click **"Workspaces"** in the sidebar
3. Click **"Create Workspace"**
4. Select the **"contractor-workspace"** template
5. Configure options (CPU, memory, AI model)
6. Click **"Create"**

Your workspace will be ready in 2-5 minutes. AI features are configured automatically — no API key entry needed.

---

### Q: How do I start/stop my workspace?

**A:**
- **Start**: Click the play button (▶) next to your workspace
- **Stop**: Click the stop button (⏹) next to your workspace
- **Auto-stop**: Workspaces may automatically stop after inactivity (configurable)

**Tip**: Stop your workspace when not in use to save resources.

---

### Q: Will I lose my work if the workspace stops?

**A:** No! Your files are saved on a persistent volume. When you restart, everything will be exactly as you left it.

---

### Q: How do I delete a workspace?

**A:**
1. Go to **Workspaces**
2. Click the three-dot menu (⋮) next to your workspace
3. Select **"Delete"**
4. Confirm deletion

⚠️ **Warning**: Deletion is permanent. Make sure your code is pushed to Git before deleting.

---

### Q: Can I have multiple workspaces?

**A:** Yes, you can create multiple workspaces (e.g., one per project). Check with your admin for any limits.

---

### Q: How do I change my workspace resources (CPU/memory)?

**A:**
1. Stop your workspace
2. Click workspace settings (gear icon)
3. Adjust CPU and memory settings
4. Save and restart

Note: Some settings require recreating the workspace.

---

## 3. IDE & Coding

### Q: How do I open the IDE?

**A:**
1. Start your workspace
2. Click **"VS Code"** button (or the code icon)
3. The IDE opens in a new browser tab

---

### Q: What programming languages are supported?

**A:** The workspace comes with:

| Language | Version | Package Manager |
|----------|---------|-----------------|
| JavaScript/TypeScript | Node.js 20 | npm, yarn, pnpm |
| Python | 3.11 | pip |
| Go | 1.22 | go modules |
| Java | 21 | Maven, Gradle |
| C#/.NET | 8.0 | dotnet CLI |

---

### Q: What extensions are pre-installed?

**A:** Common extensions include:
- Python, ESLint, Prettier
- GitLens
- Go, Java, C# support
- SQLTools (database)
- Roo Code (AI coding agent — VS Code sidebar)

**Terminal AI tools** (not extensions — run from the terminal):
- OpenCode CLI — run `opencode`
- Claude Code CLI — run `claude`

You can install additional extensions from the VS Code marketplace.

---

### Q: How do I open a terminal?

**A:** In the IDE:
- Press `` Ctrl+` `` (backtick)
- Or: Menu → Terminal → New Terminal
- Or: Click **"Terminal"** in the Coder dashboard

---

### Q: Can I install additional tools?

**A:** You can install language-level packages, but system package installation is restricted for security:

```bash
# Allowed: Language package managers
npm install -g <package>       # Node.js global packages
pip install <package>           # Python packages
go install <package>            # Go packages

# Allowed: Refresh package index (read-only)
sudo apt-get update

# NOT allowed: Installing system packages
# sudo apt-get install <package>  ← BLOCKED (security restriction)
```

If you need a system-level tool that isn't pre-installed, contact your admin to request it be added to the workspace template image.

Note: Language-level packages persist in your workspace (installed under `/home/coder`).

---

### Q: How do I access databases?

**A:** Use the **SQLTools** extension:
1. Click the database icon in the sidebar
2. Add a new connection
3. Enter the database details:
   - Host: `testdb` (or your database host)
   - Port: `5432` (PostgreSQL) or `3306` (MySQL)
   - Credentials: Provided by your admin

---

### Q: My workspace is slow. What can I do?

**A:**
1. **Increase resources**: Stop workspace, increase CPU/memory, restart
2. **Close unused tabs**: Too many editor tabs consume memory
3. **Disable unused extensions**: Some extensions are resource-heavy
4. **Clear terminal history**: Long terminal history can slow things down

---

## 4. AI Assistant

### Q: How do I use the AI assistant?

**A:** Your workspace can include up to three AI coding tools, all pre-configured and ready to use. Which ones are available depends on the "AI Coding Agent" option selected when creating your workspace.

**Roo Code** (VS Code sidebar):
- Click the **Roo Code icon** in the VS Code Activity Bar to open the AI panel
- Roo Code is an agentic AI assistant that can edit files, run terminal commands, and review code
- Describe what you need in natural language and Roo Code will execute multi-step tasks

**OpenCode** (terminal TUI):
- Run `opencode` in your terminal to launch the AI coding agent
- OpenCode is a terminal-based UI — great for SSH-style workflows and quick tasks

**Claude Code** (terminal CLI):
- Run `claude` in your terminal to launch the Claude Code CLI agent
- Claude Code is Anthropic's native CLI — it plans before coding, asks for confirmation, and follows structured workflows
- Best for complex multi-file tasks, refactoring, and codebase exploration

All three agents share your auto-provisioned LiteLLM virtual key (same budget, same audit trail).

> **Note:** The built-in Coder Chat, GitHub Copilot, and Cody are all disabled. Roo Code, OpenCode, and Claude Code are the only AI interfaces, and all route requests through the platform's centralized LiteLLM proxy for auditing and cost control.

---

### Q: Do I need to sign in or enter an API key for AI features?

**A:** No! When your workspace is created, a personal LiteLLM API key is automatically provisioned for you behind the scenes. Roo Code is pre-configured and works immediately — no sign-in, no key pasting, no setup required.

Your key has per-user budget and rate limits managed by the platform. You can check your usage at any time:

```bash
ai-usage    # Shows your spend, remaining budget, and request count
ai-models   # Shows your active model and gateway
```

---

### Q: Why is GitHub Copilot / Cody disabled?

**A:** These extensions are disabled for security and compliance reasons:

1. **Audit trail** — Copilot and Cody bypass the centralized LiteLLM proxy, making AI usage untrackable
2. **Cost control** — Without LiteLLM virtual keys, there's no per-user budget enforcement
3. **External auth** — Both require signing in to external services (GitHub, Sourcegraph), which is not allowed in this isolated environment
4. **Extension marketplace** — code-server uses Open VSX, not the Microsoft Marketplace; Copilot is not available on Open VSX

Roo Code provides equivalent (and more powerful) capabilities through LiteLLM.

---

### Q: Which AI model should I choose?

**A:** You select an AI model when creating a workspace. Available options:

| Model | Best For | Speed | Provider |
|-------|----------|-------|----------|
| **Claude Sonnet 4.5** | Most tasks (default, balanced) | Fast | Anthropic + Bedrock fallback |
| **Claude Haiku 4.5** | Quick autocomplete, simple tasks | Fastest | Anthropic + Bedrock fallback |
| **Claude Opus 4** | Complex architecture, deep reasoning | Slower | Anthropic only |
| **Bedrock Claude Sonnet (AWS)** | Force AWS Bedrock routing | Fast | AWS Bedrock |
| **Bedrock Claude Haiku (AWS)** | Force AWS Bedrock routing | Fastest | AWS Bedrock |

**Tip:** "Claude Sonnet 4.5" is the best default for most developers. It automatically falls back to AWS Bedrock if the Anthropic API is unavailable (LiteLLM model group routing).

---

### Q: What can I ask the AI?

**A:** Examples:
- "Explain this code"
- "Write a function that..."
- "Find bugs in this code"
- "Convert this to TypeScript"
- "Write unit tests for this"
- "How do I use the database?"
- "What's wrong with this error?"

---

### Q: How do I get code autocomplete?

**A:**
1. Start typing code
2. Wait a moment for suggestions (gray text)
3. Press `Tab` to accept
4. Press `Esc` to dismiss

---

### Q: Can I use AI for code review?

**A:** Yes! In Roo Code:
1. Select the code you want reviewed
2. Click the Roo Code icon in the sidebar to open the AI panel
3. Ask "Review this code for bugs and improvements"

---

### Q: What is design-first enforcement?

**A:** Design-first enforcement is a platform feature that controls how AI agents approach your tasks. Depending on the enforcement level set for your workspace, the AI may be required to propose a design before writing any code.

There are three levels:

| Level | Behavior |
|-------|----------|
| `unrestricted` | AI responds normally with no constraints |
| `standard` (default) | AI is encouraged to reason through changes before coding |
| `design-first` | AI **must** propose a design first and cannot output code in its initial response |

This is enforced server-side through LiteLLM — you cannot disable it from within your workspace. It is selected when creating a workspace (the "AI Behavior Mode" parameter).

---

### Q: How do I change the AI behavior mode?

**A:** The AI behavior mode (enforcement level) is set when you create a workspace. To change it:

1. Create a new workspace and select a different "AI Behavior Mode" option
2. Or ask your admin to rotate your LiteLLM virtual key with an updated enforcement level

Changing the mode on an existing workspace requires workspace recreation or key rotation because the enforcement level is stored in your LiteLLM key's metadata (server-side, not in your workspace config).

See [AI.md Section 12](AI.md#12-design-first-ai-enforcement-layer) for the full explanation.

---

### Q: Are my prompts logged or stored?

**A:**
- Prompt **content** is not stored by default
- Request **metadata** (timestamp, tokens used) is logged for billing/audit
- AI responses are not persisted
- Check with your admin for specific policies

---

## 5. Git & Version Control

### Q: What Git URL do I use to clone a repo?

**A:** It depends on **where you are running the command**:

| Where | Git URL | Why |
|-------|---------|-----|
| **Inside a workspace** (terminal) | `http://gitea:3000/org/repo.git` | `gitea` is the Docker network hostname |
| **From your host machine** | `http://localhost:3000/org/repo.git` | `localhost:3000` is mapped to the Gitea container |
| **From a browser** | `http://localhost:3000` | Browse repos, manage settings |

**Common mistake:** Using `localhost` inside a workspace. Inside a container, `localhost` means the container itself — Gitea isn't running there. Always use `gitea:3000` from workspace terminals.

```bash
# WRONG (inside workspace) — "Connection refused"
git clone http://localhost:3000/gitea/python-sample.git

# CORRECT (inside workspace)
git clone http://gitea:3000/gitea/python-sample.git

# ALSO WORKS (inside workspace) — but takes a roundabout path via host
git clone http://host.docker.internal:3000/gitea/python-sample.git
```

---

### Q: Why does `git push` fail with "Unauthorized" or "Authentication failed"?

**A:** HTTP push to Gitea requires credentials. Clone may work for public repos without auth, but push always needs it.

**Fix — embed credentials in the remote URL:**

```bash
# cd into your cloned repo first!
cd ~/python-sample

# Set remote with credentials
git remote set-url origin http://contractor1:password123@gitea:3000/gitea/python-sample.git

# Now push works
git push origin main
```

**Or use the credential helper** (saves credentials after first prompt):

```bash
git config --global credential.helper store
git push origin main
# Enter username: contractor1
# Enter password: password123
# Credentials are saved for future pushes
```

> **Tip:** If you're unsure of your Gitea password, check with your admin or see the test user table in this FAQ's "Getting Started" section.

---

### Q: I get "fatal: not a git repository" — what's wrong?

**A:** You're running a git command outside a cloned repo. You need to `cd` into the repo directory first.

```bash
# See what's in your home directory
ls ~/

# If you cloned python-sample, it'll be in a subfolder
cd ~/python-sample

# Now git commands work
git status
git remote -v
```

If you're not sure where you cloned it:

```bash
# Search for git repos
find /home/coder -name ".git" -type d 2>/dev/null
```

---

### Q: How do I clone a repo and push changes (full workflow)?

**A:** Complete example from inside a workspace terminal:

```bash
# 1. Clone (use gitea:3000, NOT localhost)
git clone http://contractor1:password123@gitea:3000/gitea/python-sample.git
cd python-sample

# 2. Make changes
echo "# My change" >> README.md

# 3. Configure git identity (first time only)
git config --global user.name "Contractor One"
git config --global user.email "contractor1@example.com"

# 4. Commit
git add .
git commit -m "Update README"

# 5. Push
git push origin main
```

---

### Q: Can I use SSH for Git instead of HTTP?

**A:** Yes, Gitea SSH is available on port 10022 (remapped from 22):

```bash
# From inside workspace
git clone ssh://git@gitea:22/gitea/python-sample.git

# From host machine
git clone ssh://git@localhost:10022/gitea/python-sample.git
```

You'll need to add your SSH public key in Gitea: `http://localhost:3000/user/settings/keys`.

---

### Q: Where is the Git server? How do I browse repos?

**A:**

| Access | URL | Notes |
|--------|-----|-------|
| Web UI (from browser) | `http://localhost:3000` | Browse repos, manage settings, create tokens |
| Git HTTP (from workspace) | `http://gitea:3000` | Clone/push/pull |
| Git SSH (from workspace) | `ssh://git@gitea:22` | SSH clone/push |
| Git HTTP (from host) | `http://localhost:3000` | Clone/push from host terminal |
| Git SSH (from host) | `ssh://git@localhost:10022` | SSH from host |

---

### Q: How do I configure Git credentials permanently?

**A:** Three options, from simplest to most secure:

**Option 1: Credential helper store** (saves plaintext in `~/.git-credentials`)
```bash
git config --global credential.helper store
# Next push will prompt once, then credentials are saved
```

**Option 2: Embed in remote URL** (visible in `git remote -v`)
```bash
git remote set-url origin http://user:pass@gitea:3000/org/repo.git
```

**Option 3: Gitea access token** (recommended for automation)
1. Go to `http://localhost:3000/user/settings/applications`
2. Create a new token with repo permissions
3. Use the token as the password:
```bash
git remote set-url origin http://contractor1:YOUR_TOKEN@gitea:3000/org/repo.git
```

---

### Q: `host.docker.internal` works but `localhost` doesn't (or vice versa) — why?

**A:** These names resolve differently depending on where you are:

| Name | Inside a container | On host machine |
|------|--------------------|-----------------|
| `localhost` | The container itself | The host machine |
| `host.docker.internal` | The host machine | The host machine (if `/etc/hosts` configured) |
| `gitea` | The Gitea container | Does NOT resolve |
| `coder-server` | The Coder container | Does NOT resolve |

**Rule of thumb:**
- **Inside workspace terminal:** use container names (`gitea:3000`, `litellm:4000`)
- **On your host / in browser:** use `localhost:PORT`
- **For Coder specifically:** use `https://host.docker.internal:7443` (OIDC cookies require it)

---

## 6. Collaboration

### Q: Can I share my workspace with others?

**A:** No. For security, workspace sharing is disabled. Each developer has their own isolated workspace.

To collaborate:
1. Push your code to the Git server
2. Others can pull and work in their own workspace
3. Use Git branches for parallel work

---

### Q: How do I request a new workspace template?

**A:**
1. Go to the Git server: `http://localhost:3000`
2. Navigate to the `template-requests` repository
3. Create a new Issue using the template
4. Fill out all required information
5. Submit for review

The platform team will review and respond within 2-3 business days.

---

### Q: Can I see other users' workspaces?

**A:** No. You can only see and access your own workspaces.

Admins may have visibility into all workspaces for support purposes.

---

## 7. Troubleshooting

### Q: My workspace won't start!

**A:** Try these steps:
1. **Wait**: First start can take 2-5 minutes
2. **Refresh**: Refresh the page
3. **Check logs**: Click workspace → Logs
4. **Recreate**: If stuck, delete and recreate
5. **Contact admin**: If issues persist

---

### Q: The IDE is not loading!

**A:**
1. Check that your workspace is running (green status)
2. Try a hard refresh: `Cmd/Ctrl+Shift+R`
3. Clear browser cache
4. Try a different browser
5. Check your internet connection

---

### Q: I lost my work!

**A:**
1. **Check Git**: Did you commit and push?
2. **Workspace volume**: Your files should be in `/home/coder/workspace`
3. **Recent files**: Check VS Code → File → Open Recent
4. **Contact admin**: They may be able to recover from backups

**Prevention**: Always commit and push your work regularly!

---

### Q: AI is not working!

**A:**
1. **Check config**: In terminal, run `ai-models` to verify your agent, model, and gateway are set
2. **Check budget**: Run `ai-usage` — you may have hit your spending limit
3. **Check Roo Code**: Click the Roo Code icon in the sidebar — does the AI panel open?
4. **Check Claude Code**: Run `claude --version` in terminal — if "command not found", the image needs rebuilding (ask admin)
5. **Check API key**: Run `echo $ANTHROPIC_API_KEY` (for Claude Code) or `cat ~/.config/roo-code/settings.json` (for Roo Code) — verify key is present
6. **Rebuild workspace**: If the API key is missing or Claude Code isn't installed, delete and recreate the workspace
7. **Contact admin**: There may be a service issue with LiteLLM

---

### Q: Claude Code shows "Select login method" prompt!

**A:** This means the `ANTHROPIC_BASE_URL` and `ANTHROPIC_API_KEY` environment variables are not configured. Without these, Claude Code tries to authenticate directly with Anthropic (which is not how this platform works).

**Quick fix** (run in your workspace terminal):

```bash
export ANTHROPIC_BASE_URL="http://litellm:4000/anthropic"
export ANTHROPIC_API_KEY="$OPENAI_API_KEY"
claude
```

To make it permanent (survives terminal restarts):

```bash
echo 'export ANTHROPIC_BASE_URL="http://litellm:4000/anthropic"' >> ~/.bashrc
echo "export ANTHROPIC_API_KEY=\"$OPENAI_API_KEY\"" >> ~/.bashrc
source ~/.bashrc
claude
```

**Why this happened:** Your workspace was likely created before Claude Code support was added to the template. The `$OPENAI_API_KEY` is your existing LiteLLM virtual key (shared by all AI agents). For a permanent fix, recreate the workspace from the updated template.

---

### Q: Extension panels are blank (Roo Code, etc.)!

**A:** This is caused by a **browser secure context issue**. The `crypto.subtle` API (needed by code-server for webview nonces) is only available over HTTPS or `localhost`.

**Diagnose:** Open browser console (F12) on the code-server page:
```javascript
console.log(window.isSecureContext);  // false = this is the problem
console.log(crypto.subtle);           // undefined = confirms it
```

**Fix (HTTPS — default):** Access Coder via `https://host.docker.internal:7443` (not HTTP port 7080). Accept the self-signed certificate warning.

**Alternative (Chrome flag):** If HTTPS is not available, launch Chrome with:
```bash
# macOS
open -a "Google Chrome" --args --unsafely-treat-insecure-origin-as-secure="http://host.docker.internal:7080"
```

Or set via `chrome://flags/#unsafely-treat-insecure-origin-as-secure`.

---

### Q: Terminal commands are slow!

**A:**
1. Check your internet connection
2. The workspace might need more resources
3. Clear terminal: `clear` or `Cmd/Ctrl+K`
4. Long-running commands may appear slow - check with `htop`

---

### Q: How do I report a bug?

**A:**
1. Go to the Git server
2. Open the `template-requests` repository
3. Create an Issue using the "Template Issue Report" template
4. Include:
   - What you were doing
   - What happened
   - What you expected
   - Screenshots if helpful

---

## 8. App Manager Questions

### Q: What is a workspace template?

**A:** A workspace template is a Terraform configuration (`.tf` files) that defines what a workspace looks like: the Docker image, resource limits, startup scripts, parameters (AI model, Git credentials, etc.), and IDE setup. Templates live in `coder-poc/templates/<name>/`.

Key files in a template:
- `main.tf` — Terraform config defining the workspace container, agent, apps, and user parameters
- `build/Dockerfile` — Docker image with pre-installed tools, extensions, and system config
- `build/settings.json` — VS Code settings baked into the image

There is **no YAML editor or web UI** for editing templates. You edit `.tf` files locally and push via CLI.

---

### Q: How do I create a new template?

**A:**
1. Copy an existing template directory as a starting point:
   ```bash
   cp -r coder-poc/templates/python-workspace coder-poc/templates/my-template
   ```
2. Edit `main.tf` — change parameters, resources, startup scripts
3. Edit `build/Dockerfile` — extend `workspace-base:latest` and add language-specific tools
4. Build the Docker images:
   ```bash
   # Build base first (if not already built)
   docker build -t workspace-base:latest coder-poc/templates/workspace-base/build
   # Build your template image
   docker build -t my-template:latest coder-poc/templates/my-template/build
   ```
5. Push to Coder (via Docker exec, no host CLI needed):
   ```bash
   docker cp coder-poc/templates/my-template coder-server:/tmp/my-template
   docker exec -e CODER_URL=http://localhost:7080 -e CODER_SESSION_TOKEN=$TOKEN \
     coder-server coder templates create my-template --directory /tmp/my-template --yes
   ```

See ADMIN-HOWTO.md for the full walkthrough and INFRA.md for architecture details.

---

### Q: How do I manage users?

**A:**
1. Log in as admin
2. Go to **Deployment → Users**
3. **Create**: Click "Create User"
4. **Edit**: Click user → Edit
5. **Suspend**: Click user → Suspend
6. **Delete**: Click user → Delete

---

### Q: How do I assign roles?

**A:** Available roles:
- **Owner**: Full admin access
- **Template Admin**: Manage templates, view workspaces
- **Member**: Create workspaces only
- **Auditor**: View audit logs only

To assign:
1. Go to **Users → Select User**
2. Click **Edit**
3. Select role(s)
4. Save

---

### Q: How do I view audit logs?

**A:**
1. Log in as admin or auditor
2. Go to **Deployment → Audit Logs**
3. Filter by:
   - User
   - Action type
   - Date range
4. Export if needed

---

### Q: How do I monitor resource usage?

**A:**
1. **Per workspace**: Workspace → Metrics (CPU, memory, disk)
2. **Platform-wide**: Docker stats or monitoring dashboard
3. **Database**: Check connection counts, query performance

---

### Q: How do I update templates?

**A:**
1. Edit the template files locally (`main.tf`, `build/Dockerfile`, etc.)
2. If you changed the Dockerfile, rebuild images and push:
   ```bash
   cd coder-poc
   REBUILD_IMAGE=true ./scripts/setup-workspace.sh
   ```
3. If you only changed `main.tf` (no Dockerfile changes), push without rebuilding:
   ```bash
   cd coder-poc
   ./scripts/setup-workspace.sh
   ```

For a single template manual push, see [ADMIN-HOWTO.md — Pushing a Template to Coder](../coder-poc/docs/ADMIN-HOWTO.md#pushing-a-template-to-coder).

**Important:**
- Existing workspaces keep using the old template version
- New workspaces automatically use the latest version
- Users can click "Update" on their workspace to adopt template changes
- Some changes (Dockerfile tools, agent URLs, env vars) require workspace **deletion and recreation** — not just an update

---

### Q: How do I handle user requests for tools/access?

**A:**
1. Review request in `template-requests` repository
2. Assess security implications
3. If approved:
   - Add to template Dockerfile
   - Or grant on case-by-case basis
4. Respond to the request Issue
5. Close with resolution

---

### Q: What's the difference between stopping and deleting a workspace?

**A:**

| Action | Data | Can Recover? | Billing |
|--------|------|--------------|---------|
| **Stop** | Preserved | Yes (restart) | No charge* |
| **Delete** | Destroyed | No | No charge |

*Check with your cloud provider for storage costs.

---

## 9. Security & Compliance

### Q: Is my code secure?

**A:** Yes, we implement multiple security layers:
- 🔒 Each workspace is isolated
- 🔒 No SSH or external VS Code access
- 🔒 Network is segmented
- 🔒 All traffic is encrypted (HTTPS)
- 🔒 Code stays in the platform

---

### Q: Can other users see my code?

**A:** No. Your workspace is completely isolated. Only you (and admins for support) can access it.

---

### Q: Is AI safe to use with sensitive code?

**A:**
- AI requests use encrypted connections
- Code is not stored by the AI provider
- No training on your data (with Bedrock/Anthropic)
- Metadata (not content) is logged for audit

**Best practice**: Don't include passwords, API keys, or PII in AI prompts.

---

### Q: Can I download files from my workspace?

**A:** File download is restricted for security. To get code out:
1. Push to the Git server
2. Or use approved file transfer methods (ask admin)

---

### Q: What happens to my data when I leave?

**A:**
1. Your access is revoked
2. Workspaces may be deleted after a retention period
3. Git commits remain (owned by the organization)
4. Contact your admin for specific policies

---

### Q: Who can see my AI conversations?

**A:**
- **You**: Full access to your history
- **Admins**: May see metadata (not content) in audit logs
- **No one else**: Conversations are not shared

---

### Q: How are AI API keys managed?

**A:** LiteLLM virtual keys are **automatically provisioned** when a workspace is created:

1. User creates a workspace and selects an AI model
2. Terraform calls the LiteLLM API to look up or generate a key for that user
3. The key is injected into the workspace configuration (Roo Code, environment variables)
4. Users never see or handle raw API keys

**Admin tasks:**
- **View keys**: LiteLLM Admin UI at `http://localhost:4000/ui`
- **Adjust budgets**: Edit per-user limits in LiteLLM
- **Revoke a key**: Delete the key in LiteLLM — the user's workspace will lose AI access until rebuilt
- **Monitor usage**: Platform Admin dashboard → AI Usage page

> Keys are scoped per-user (by Coder username) and include budget and rate limits. The `setup-litellm-keys.sh` script is no longer required for normal operation but can still be used for bulk key management.

---

## Quick Reference Card

```
╔═══════════════════════════════════════════════════════════════════════════╗
║                          QUICK REFERENCE                                   ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                            ║
║  KEYBOARD SHORTCUTS (VS Code)                                             ║
║  ───────────────────────────                                              ║
║  Roo Code icon        Open AI agent (sidebar)                              ║
║  Cmd/Ctrl + `         Open terminal                                       ║
║  Cmd/Ctrl + P         Quick file open                                     ║
║  Cmd/Ctrl + Shift + P Command palette                                     ║
║                                                                            ║
║  AI CODING TOOLS                                                          ║
║  ────────────────                                                         ║
║  • Roo Code: Click icon in Activity Bar (VS Code sidebar)                 ║
║  • OpenCode: Run `opencode` in terminal (TUI agent)                       ║
║  • Claude Code: Run `claude` in terminal (CLI agent)                      ║
║  • All share your auto-provisioned LiteLLM key                            ║
║                                                                            ║
║  GIT WORKFLOW                                                             ║
║  ────────────                                                             ║
║  git clone http://gitea:3000/user/repo.git                                 ║
║  git add . && git commit -m "message"                                     ║
║  git push origin main                                                      ║
║                                                                            ║
║  GETTING HELP                                                             ║
║  ────────────                                                             ║
║  • AI Agent: Roo Code (sidebar), `opencode`, or `claude` (terminal)       ║
║  • Bug report: Create Issue in template-requests repo                     ║
║  • Platform admin: [Contact info]                                         ║
║                                                                            ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-04 | Platform Team | Initial version |
| 1.1 | 2026-02-06 | Platform Team | HTTPS URLs, Bedrock model options, secure context troubleshooting, template management how-to |
| 1.2 | 2026-02-06 | Platform Team | OpenCode CLI references, auto-provisioned keys, updated AI assistant section |
| 1.3 | 2026-02-07 | Platform Team | Fixed sudo/apt-get section (now restricted), updated credentials to match RBAC doc |
| 1.4 | 2026-02-09 | Platform Team | Added Claude Code CLI references, updated template push docs, updated Quick Reference |
