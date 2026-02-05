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

**A:** Open your web browser and navigate to the platform URL (e.g., `https://coder.company.com`). Log in with your credentials provided by the platform administrator.

---

### Q: What credentials do I need?

**A:** You need:
- **Platform login**: Username and password (or SSO if configured)
- **Git credentials**: Username and password for the Git server (provided separately)
- **No AI credentials needed**: AI features work automatically

**PoC Default Credentials:**

| System | Username | Password |
|--------|----------|----------|
| Coder | contractor1@example.com | Password123! |
| Gitea | contractor1 | password123 |

> Note: In production, SSO/OIDC will be used instead of local passwords.

---

### Q: Which browser should I use?

**A:** We recommend:
- ✅ Google Chrome (latest)
- ✅ Microsoft Edge (latest)
- ✅ Mozilla Firefox (latest)
- ⚠️ Safari (works, but Chrome/Edge preferred)

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

Your workspace will be ready in 2-5 minutes.

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
- Continue (AI assistant)

You can install additional extensions from the VS Code marketplace.

---

### Q: How do I open a terminal?

**A:** In the IDE:
- Press `` Ctrl+` `` (backtick)
- Or: Menu → Terminal → New Terminal
- Or: Click **"Terminal"** in the Coder dashboard

---

### Q: Can I install additional tools?

**A:** Yes, you have `sudo` access. Examples:
```bash
# Install system packages
sudo apt update && sudo apt install <package>

# Install Node packages globally
npm install -g <package>

# Install Python packages
pip install <package>
```

Note: Installed packages persist in your workspace.

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

**A:** There are two AI assistants:

**1. Coder Chat (Built-in)**
- Click the AI icon in the Coder dashboard
- Ask questions, get code help

**2. Continue (VS Code)**
- Press `Cmd/Ctrl+L` to open chat
- Press `Tab` for code autocomplete
- Select code and press `Cmd/Ctrl+I` to edit with AI

---

### Q: Do I need to sign in for AI features?

**A:** No! AI features are pre-configured and work immediately. No Google, GitHub, or other sign-in required.

---

### Q: Which AI model should I choose?

**A:**

| Model | Best For | Speed |
|-------|----------|-------|
| **Claude Sonnet 4.5** | Most tasks (default, balanced) | Fast |
| **Claude Haiku 4.5** | Quick autocomplete | Fastest |
| **Claude Opus 4.5** | Complex problems (advanced) | Slower |

You can change this when creating a workspace.

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

**A:** Yes! In Continue:
1. Select the code you want reviewed
2. Press `Cmd/Ctrl+L` to open chat
3. Type `/review` or "Review this code for bugs and improvements"

---

### Q: Are my prompts logged or stored?

**A:**
- Prompt **content** is not stored by default
- Request **metadata** (timestamp, tokens used) is logged for billing/audit
- AI responses are not persisted
- Check with your admin for specific policies

---

## 5. Git & Version Control

### Q: How do I clone a repository?

**A:** In the terminal:
```bash
# Using the Git server
git clone http://gitea:3000/username/repository.git

# Enter credentials when prompted
```

Or specify credentials inline:
```bash
git clone http://username:password@gitea:3000/username/repository.git
```

---

### Q: How do I configure Git credentials?

**A:** You have two options:

**Option 1: One-time setup**
```bash
git config --global credential.helper store
git clone http://gitea:3000/user/repo.git
# Enter credentials once - they'll be saved
```

**Option 2: Set during workspace creation**
- Enter Git username/password in workspace parameters
- Credentials are configured automatically

---

### Q: How do I push changes?

**A:**
```bash
# Stage changes
git add .

# Commit
git commit -m "Your commit message"

# Push
git push origin main
```

---

### Q: I can't push - permission denied!

**A:** Check:
1. You have write access to the repository
2. Your credentials are correct
3. You're pushing to the right branch

Contact your admin if issues persist.

---

### Q: Where is the Git server?

**A:** The internal Git server is at:
- Web UI: `http://localhost:3000` (or provided URL)
- Clone URL: `http://gitea:3000/username/repo.git` (from workspace)

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
1. **Check Continue**: Press `Cmd/Ctrl+L` - does the sidebar open?
2. **Check config**: In terminal, run `cat ~/.continue/config.json`
3. **Restart workspace**: Sometimes fixes configuration issues
4. **Check model**: Try switching to a different AI model
5. **Contact admin**: There may be a service issue

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

### Q: How do I create a new template?

**A:**
1. Copy the existing template directory
2. Modify `main.tf` for your requirements
3. Update `Dockerfile` with needed tools
4. Test locally with `coder templates push --test`
5. Push: `coder templates push <template-name>`

See the INFRA.md documentation for details.

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
```bash
# Make changes to template files

# Push update
coder templates push <template-name> \
  --directory ./templates/<template-name> \
  --yes

# Existing workspaces will use old version
# New workspaces will use new version
# Users can update their workspace to get new template
```

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

## Quick Reference Card

```
╔═══════════════════════════════════════════════════════════════════════════╗
║                          QUICK REFERENCE                                   ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                            ║
║  KEYBOARD SHORTCUTS (VS Code)                                             ║
║  ───────────────────────────                                              ║
║  Cmd/Ctrl + L         Open AI chat (Continue)                             ║
║  Cmd/Ctrl + I         Edit with AI                                        ║
║  Cmd/Ctrl + `         Open terminal                                       ║
║  Cmd/Ctrl + P         Quick file open                                     ║
║  Cmd/Ctrl + Shift + P Command palette                                     ║
║  Tab                  Accept AI autocomplete                               ║
║                                                                            ║
║  USEFUL COMMANDS                                                          ║
║  ───────────────                                                          ║
║  /review              AI code review                                       ║
║  /test                Generate tests                                       ║
║  /explain             Explain selected code                                ║
║  /edit                Edit with instructions                               ║
║                                                                            ║
║  GIT WORKFLOW                                                             ║
║  ────────────                                                             ║
║  git clone http://gitea:3000/user/repo.git                                 ║
║  git add . && git commit -m "message"                                     ║
║  git push origin main                                                      ║
║                                                                            ║
║  GETTING HELP                                                             ║
║  ────────────                                                             ║
║  • AI Assistant: Cmd/Ctrl + L                                             ║
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
