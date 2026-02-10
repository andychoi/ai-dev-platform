# AEM 6.5 Workspace Template Plan

## Context

The team develops custom AEM (Adobe Experience Manager) 6.5 components — Sling Models, HTL templates, Touch UI dialogs, client libraries — using the standard AEM Maven archetype. A new Coder workspace template is needed so contractors can develop, build, deploy, and debug AEM in an isolated browser-based environment.

**Key decisions:**
- **AEM 6.5 On-Premise** (requires Java 11, NOT 21)
- **JVM in workspace** — Author + optional Publisher run as Java processes inside the container
- **Standard archetype** — core, ui.apps, ui.content, ui.frontend, dispatcher modules
- **AEM quickstart JAR is proprietary** — NOT baked into image; admin pre-places it

---

## Files Created (6 new files)

| File | Purpose |
|------|---------|
| `coder-poc/templates/aem-workspace/build/Dockerfile` | Image: Java 11 + Maven 3.9 + AEM extensions |
| `coder-poc/templates/aem-workspace/build/settings.json` | VS Code config with Java 11 runtime + AEM file associations |
| `coder-poc/templates/aem-workspace/build/maven-settings.xml` | Maven settings with Adobe public repo + AEM server credentials |
| `coder-poc/templates/aem-workspace/main.tf` | Terraform: params, AEM startup/shutdown, Coder apps, Docker resources |
| `coder-poc/egress/aem-workspace.conf` | Template-specific egress rules (port 80 for HTTP Maven repos) |
| `coder-poc/templates/aem-workspace/build/.vscode/launch.json` | Debug config for JPDA attach to AEM Author |

---

## Step 1: Dockerfile

**Base:** `workspace-base:latest` (NOT java-workspace — that has Java 21, AEM 6.5 needs Java 11)

**Installs:**
- `openjdk-11-jdk` (AEM 6.5 requirement)
- Maven 3.9.9 from Apache archive (Ubuntu apt only has 3.6.x)
- `xmlstarlet` (JCR content XML manipulation)
- `build-essential` (native npm modules for ui.frontend)

**PATH lockdown update:** Add Java 11 bin + Maven bin

**VS Code extensions:**
- `redhat.java` + `vscjava.vscode-java-debug` + `vscjava.vscode-java-dependency` + `vscjava.vscode-maven` (Java dev)
- `k--kato.intellij-idea-keybindings` (JetBrains migrants)
- `dotjoshjohnson.xml` (JCR content XML editing)

**Pre-creates:** `/home/coder/aem/author/`, `/home/coder/aem/publisher/`, `/home/coder/.m2/`

**Reference pattern:** `coder-poc/templates/java-workspace/build/Dockerfile`

---

## Step 2: maven-settings.xml

Pre-configured with:
- **Adobe Public Repository** (`https://repo.adobe.com/nexus/content/groups/public/`) — activeByDefault profile
- **Server credentials** for `aem-author` (admin/admin) and `aem-publisher` (admin/admin) — used by `maven-content-package-plugin` for `autoInstallSinglePackage` profile

---

## Step 3: settings.json (VS Code)

Copy base `workspace-base/build/settings.json` and modify/add:
- `java.configuration.runtimes` → **JavaSE-11** at `/usr/lib/jvm/java-11-openjdk-amd64` (override base Java 21)
- `java.completion.favoriteStaticMembers` → Add `org.apache.sling.api.resource.ResourceUtil.*`
- `maven.executable.path` → `/opt/apache-maven-3.9.9/bin/mvn`
- `java.configuration.maven.userSettings` → `/home/coder/.m2/settings.xml`
- `files.associations` → Map `*.htl` to html, `*.content.xml` / `.content.xml` to xml
- `files.exclude` → Add `**/target`, `**/crx-quickstart/launchpad`
- `xml.format.splitAttributes` → true (JCR XML convention)
- `java.debug.settings.hotCodeReplace` → "auto" (live reload during debug)
- `[xml]` and `[java]` → tabSize 4 (AEM convention)

---

## Step 4: Egress Rules

**File:** `coder-poc/egress/aem-workspace.conf`

Only addition: `port:80` for legacy HTTP Maven repositories. Port 443 is already allowed globally (for Anthropic Enterprise + npm/Maven HTTPS). AEM Author/Publisher run inside the container — no egress needed.

---

## Step 5: main.tf (largest file)

**Fork from:** `coder-poc/templates/java-workspace/main.tf` (1,091 lines), then modify.

### Parameters — Modified from java-workspace

| Parameter | Change from java-workspace |
|-----------|---------------------------|
| `cpu_cores` | Default **4** (was 2). Options: 4/6/8 |
| `memory_gb` | Default **8** (was 4). Options: 8/12/16 |
| `disk_size` | Default **50** (was 10). Options: 50/100 |

### Parameters — New (AEM-specific)

| Parameter | Type | Default | Mutable | Description |
|-----------|------|---------|---------|-------------|
| `aem_jar_path` | string | `/home/coder/aem/aem-quickstart.jar` | No | Path to proprietary quickstart JAR |
| `aem_publisher_enabled` | string | `false` | No | Enable Publisher instance |
| `aem_author_jvm_opts` | string | `-Xmx2048m` | Yes | Author heap: 2G/3G/4G |
| `aem_publisher_jvm_opts` | string | `-Xmx1024m` | Yes | Publisher heap: 1G/2G |
| `aem_debug_port` | number | `5005` | Yes | JPDA remote debug port |
| `aem_admin_password` | string | `admin` | Yes | AEM admin password |

### Agent env block

```hcl
env = {
  CODER_AGENT_DEVCONTAINERS_ENABLE = "false"
  CLAUDE_CODE_DISABLE_AUTOUPDATE   = "1"
  JAVA_HOME = "/usr/lib/jvm/java-11-openjdk-amd64"
}
```

### Startup Script — New AEM phases inserted

Phases 1-2 (git config, repo clone) — identical to java-workspace.

**Phase 3 (NEW): Maven settings recovery**
- If `/home/coder/.m2/settings.xml` missing (persistent volume wiped it), recreate from template default

**Phase 4 (NEW): AEM Instance Management**
```
1. Check if AEM JAR exists at aem_jar_path
   - If missing: Print clear instructions (where to get it, how to place it)
   - If present: Continue to start

2. AEM Author startup:
   - mkdir -p /home/coder/aem/author && cd
   - If crx-quickstart/ doesn't exist: first-start (copy JAR, takes 5-10 min)
   - Start AEM Author as background JVM process:
     java $JVM_OPTS -agentlib:jdwp=...:address=*:5005 -jar aem-quickstart.jar -p 4502 -r author -nobrowser -nofork &
   - Save PID to /home/coder/aem/author.pid
   - Wait loop: curl login page up to 5 minutes

3. AEM Publisher startup (if enabled):
   - Same pattern on port 4503, no JPDA debug
   - Save PID to /home/coder/aem/publisher.pid
```

Phases 5-8 (AI agents, database, Ollama, code-server) — identical to java-workspace.

**Phase 9 (NEW): AEM convenience aliases**
```
aem-build          — mvn clean install -PautoInstallSinglePackage
aem-deploy         — Same but -DskipTests
aem-deploy-core    — Deploy only core bundle
aem-deploy-apps    — Deploy only ui.apps
aem-deploy-content — Deploy only ui.content
aem-deploy-frontend — Build frontend + deploy
aem-deploy-publish — Deploy to Publisher
aem-logs           — tail Author error.log
aem-logs-publish   — tail Publisher error.log
aem-status         — curl check Author + Publisher
aem-bundles        — OSGi bundle summary from /system/console/bundles.json
aem-start-author   — Manual start
aem-stop-author    — Kill by PID
aem-start-publisher / aem-stop-publisher
```

**Phase 10: Enhanced status output**
```
AEM Author: http://localhost:4502 (JPDA debug: 5005)
  CRXDE:    http://localhost:4502/crx/de
  Packages: http://localhost:4502/crx/packmgr
  Console:  http://localhost:4502/system/console
AEM Publisher: http://localhost:4503 (if enabled)
```

### Shutdown Script (NEW — critical for AEM)

Graceful AEM shutdown prevents CRX repository corruption:
1. Read PID from `/home/coder/aem/author.pid`
2. `kill $PID` (SIGTERM for graceful)
3. Wait up to 60 seconds
4. Force-kill if still running
5. Same for Publisher
6. Kill code-server

### Coder Apps (3 total)

| App | Port | Healthcheck |
|-----|------|-------------|
| VS Code | 8080 | `/healthz` every 5s |
| AEM Author | 4502 | `/libs/granite/core/content/login.html` every 15s, threshold 40 (~10 min) |
| AEM Publisher | 4503 | Same, always registered (shows "unhealthy" when disabled) |

### Metadata Widgets (4 new)

| Widget | Script | Interval |
|--------|--------|----------|
| AEM Author Status | curl login page → "Running"/"Starting"/"Stopped" | 15s |
| AEM Publisher Status | Same + "Disabled" if not enabled | 15s |
| OSGi Bundles | Parse `/system/console/bundles.json` → "X/Y active" | 30s |
| Author JVM Heap | `ps -o rss=` on PID → "X MB used" | 15s |

### Claude Code Permissions

Allow: `mvn`, `java`, `node`, `npm`, `git`, file operations
Deny: `curl`, `wget`, `ssh`, `scp`

### Docker Container

- Image: `aem-workspace:latest`
- Egress mount: `coder-poc/egress/aem-workspace.conf` → `/etc/egress-template.conf`
- All other Docker config identical to java-workspace

---

## Step 6: launch.json (debug config)

Pre-configured VS Code debug launch configuration for JPDA attach to AEM Author on port 5005:
```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "java",
      "name": "Attach to AEM Author",
      "request": "attach",
      "hostName": "localhost",
      "port": 5005
    }
  ]
}
```

Copied into the workspace image at `/home/coder/.local/share/code-server/User/` or injected via startup script if the workspace project doesn't have its own `.vscode/launch.json`.

---

## Verification Checklist

1. **Image build:** `docker build -t aem-workspace:latest .` → verify `java -version` shows 11, `mvn --version` shows 3.9.9
2. **Template push:** `coder templates push aem-workspace` → verify appears in Coder UI
3. **Without JAR:** Create workspace → startup prints "JAR NOT FOUND" with instructions → VS Code opens, Java LSP works
4. **With JAR:** Place JAR at `/home/coder/aem/aem-quickstart.jar` → restart → Author starts → Coder app goes green
5. **Maven build:** Clone archetype project → `aem-build` → packages deploy to Author
6. **Debug:** VS Code → "Attach to AEM Author" → breakpoint in Sling Model → triggered on page request
7. **AI tools:** Roo Code, Claude Code, OpenCode all work (same pattern as java-workspace)
8. **Shutdown:** Stop workspace → logs show graceful AEM shutdown → restart → AEM starts faster (existing crx-quickstart)
9. **Publisher:** Create workspace with Publisher enabled → both instances start → `aem-status` shows both running
