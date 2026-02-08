# From VDI to Containers: The Business Case for Coder

**One-page executive brief** | Reference: [Skydio Success Story](https://coder.com/success-stories/skydio), [J.B. Hunt Success Story](https://coder.com/success-stories/jbhunt)

---

## The VDI Problem

Virtual Desktop Infrastructure was designed for general-purpose remote access — not software development. When used as developer environments, VDI creates compounding pain:

| VDI Pain Point | Real-World Impact |
|----------------|-------------------|
| **Latency** | Full desktop rendered & streamed per keystroke; developers far from VDI region experience 100-300ms input lag — unusable for coding |
| **Slow startup** | 5-15 min to get a working environment; breaks flow state |
| **Configuration drift** | Each developer self-configures their VM; "works on my machine" proliferates |
| **Onboarding** | 1-2 weeks to provision, configure, and validate a new developer's environment |
| **Cost** | Full Windows VM per developer + VDI licenses + storage; always-on even when idle |
| **Patching burden** | VMs with full persistence require the same update/patch cadence as end-user devices |
| **Endpoint security tax** | Every Windows VM requires a full security agent stack (EDR, Zscaler, DLP) — adds cost, RAM, CPU, and boot time |
| **AI integration** | No governed path to give developers AI tools without exposing API keys |

> *"What started as an exciting software project became a maintenance burden needing constant attention."*
> — Elliot, Head of Internal Infrastructure, Skydio

---

## The Hidden Cost: Windows Endpoint Security Stack

Every Windows VDI instance must run the same security agent stack as a corporate laptop. This is the cost most VDI business cases undercount:

```
┌─────────────────────────────────────────────────────────────────┐
│               TYPICAL WINDOWS VDI SECURITY STACK                 │
│                                                                  │
│  ┌─────────────────────────────────────────────────────┐        │
│  │  EDR Agent (CrowdStrike / Carbon Black / Defender)  │        │
│  │  Real-time process monitoring, behavioral analysis  │        │
│  │  RAM: 300-500 MB  │  CPU: 2-5%  │  $5-15/endpoint  │        │
│  └─────────────────────────────────────────────────────┘        │
│  ┌─────────────────────────────────────────────────────┐        │
│  │  Zscaler Agent (ZIA + ZPA / ZTNA)                   │        │
│  │  All traffic tunneled through cloud proxy            │        │
│  │  RAM: 200-400 MB  │  Latency: +20-50ms │ $8-20/user│        │
│  └─────────────────────────────────────────────────────┘        │
│  ┌─────────────────────────────────────────────────────┐        │
│  │  DLP Agent (Digital Guardian / Symantec / Forcepoint)│        │
│  │  File scanning, clipboard monitoring, USB block     │        │
│  │  RAM: 200-400 MB  │  CPU: 2-5%  │  $8-15/endpoint  │        │
│  └─────────────────────────────────────────────────────┘        │
│  ┌─────────────────────────────────────────────────────┐        │
│  │  Additional: AV, SCCM/Intune, certificate mgmt     │        │
│  │  Windows Update, Group Policy, vulnerability scans  │        │
│  │  RAM: 200-500 MB  │  Ongoing admin overhead         │        │
│  └─────────────────────────────────────────────────────┘        │
│                                                                  │
│  TOTAL OVERHEAD PER VDI:                                        │
│    RAM:      900 MB - 1.8 GB consumed by security agents        │
│    CPU:      5-15% baseline (before developer does anything)     │
│    Boot:     +60-120 sec (agents initialize, scan, phone home)   │
│    License:  $21-50/endpoint/month (EDR + Zscaler + DLP)         │
│    Admin:    Per-VM patching, policy updates, agent upgrades     │
└─────────────────────────────────────────────────────────────────┘
```

### Why Linux Containers Eliminate This Entirely

| Security Concern | Windows VDI Approach | Linux Container Approach |
|-----------------|---------------------|--------------------------|
| **Malware / ransomware** | EDR agent per VM ($5-15/mo) | No Windows = no Windows malware. Immutable container image; read-only base layer |
| **Network security** | Zscaler agent per VM ($8-20/mo) + latency penalty | Platform-level egress firewall; containers only reach whitelisted services. No per-container agent |
| **Data loss prevention** | Digital Guardian per VM ($8-15/mo); clipboard/USB/file monitoring | Browser-only access — no local filesystem, no clipboard to host, no USB. Code never leaves the container |
| **Vulnerability management** | SCCM/Intune scan per VM; Windows patch Tuesday | Rebuild container image once → all workspaces get the update. `apt-get upgrade` in Dockerfile |
| **Endpoint compliance** | Per-VM health checks, certificate management | No endpoint to manage. The container IS the endpoint, and it's ephemeral |
| **Identity / access** | AD Group Policy, per-VM domain join | OIDC SSO (Authentik); RBAC at platform level; no domain join |

**The fundamental shift:** Instead of bolting security agents onto every VM, security moves to the **platform layer** — container isolation, network policy, and server-side guardrails. No per-instance agents, no per-instance licenses, no per-instance patching.

---

## The Container Alternative

Replace heavyweight VDI VMs with lightweight, purpose-built containers that run only what developers need — an IDE backend, a terminal, and project tooling. No desktop rendering, no OS licensing, no security agent stack.

```
 Windows VDI (Traditional)            Linux Container (Coder)
 ────────────────────────             ──────────────────────
 ┌──────────────────────┐             ┌──────────────────┐
 │  Windows Desktop     │             │  Browser Tab     │
 │  VS Code             │ ◄── RDP ──  │  (VS Code Web)   │
 │  Runtime             │   stream    └────────┬─────────┘
 │  OS + Drivers        │                      │ text only
 │  ─────────────────── │             ┌────────▼─────────┐
 │  EDR Agent      ▓▓▓  │             │  Container (1 GB) │
 │  Zscaler Agent  ▓▓   │             │  IDE backend only │
 │  DLP Agent      ▓▓   │             │  No security      │
 │  AV + SCCM      ▓    │             │   agents needed   │
 │  ─────────────────── │             │  Ephemeral, shared│
 │  Full VM (8-16 GB)   │             │  infra             │
 └──────────────────────┘             └──────────────────┘
 Always-on, per-user                  On-demand, no license
 ~1.5 GB RAM for agents alone        Security at platform layer
 $21-50/mo in security licenses       $0 endpoint security cost
```

**Key insight:** CDEs only run the IDE backend remotely, communicating via efficient text protocols — not streaming a full graphical desktop. No Windows OS means no Windows security stack. Bandwidth requirements and per-endpoint costs both drop by an order of magnitude.

---

## Industry Results

### Skydio — Autonomous Drone Company

| Metric | Before (Homegrown VDI) | After (Coder) |
|--------|----------------------|----------------|
| **Cloud compute cost** | Baseline | **90% reduction** |
| **New hire → first commit** | 1 week | **1 hour** |
| **GPU/VM utilization** | Always-on, per-user | Auto-shutdown; shared across teams |
| **Environment updates** | Manual per-VM | Push to all workspaces via template |
| **Specialized workflows** | Manual setup | Terraform templates (GPU, 3D rendering, ML) |

Skydio builds everything in-house — hardware, software, AI — and needed environments ranging from embedded firmware to deep learning training. Coder templates let them define each workflow once and provision it in seconds.

*Source: [coder.com/success-stories/skydio](https://coder.com/success-stories/skydio)*

### J.B. Hunt — Fortune 500 Logistics

| Metric | Before (Azure VDI) | After (Coder on GKE) |
|--------|-------------------|----------------------|
| **Cloud spend** | ~$X per developer/month (4-CPU, 16 GB VM + Windows license) | **< 10% of original** |
| **Environments managed** | 150+ individual VDI instances | Handful of Kubernetes pods |
| **Onboarding** | Up to 2 weeks | Minutes |
| **"Works on my machine"** | Frequent | Eliminated (standardized containers) |
| **SRE support burden** | High (per-VM troubleshooting) | Low (template-based, self-healing) |

*Source: [coder.com/success-stories/jbhunt](https://coder.com/success-stories/jbhunt)*

---

## Our Platform: VDI Benefits + AI Governance

This platform takes the container-based approach proven by Skydio and J.B. Hunt and adds **centralized AI governance** — the missing piece for organizations adopting AI coding agents.

| Dimension | Windows VDI | Coder (Industry) | Our Platform |
|-----------|------------|-------------------|--------------|
| Environment setup | 5-15 min | 30-60 sec | 30-60 sec |
| Onboarding | 1-2 weeks | < 1 hour | < 1 hour |
| Cost vs VDI | Baseline | **90% reduction** | **90% reduction** |
| Configuration drift | Per-VM | Template-based | Template-based |
| Desktop streaming | Yes (high bandwidth) | No (text only) | No (text only) |
| Windows VDA + RDS CAL | $12-20/user/mo | None (Linux) | None (Linux) |
| M365 E1 (offshore web-only) | $8/user/mo | N/A | Decoupled — email/Teams only |
| EDR agent | Per-VM ($5-15/mo) | None | None |
| Zscaler / ZTNA | Per-user ($8-20/mo) | None | Platform egress firewall |
| DLP agent | Per-VM ($8-15/mo) | None | Server-side guardrails |
| Security admin labor | Per-VM patching, policy, agent upgrades | Minimal | Template-based, zero per-container |
| Windows / AD admin | Domain join, GPO, SCCM, Intune | None | OIDC SSO (Authentik) |
| **AI coding agents** | None / unmanaged | BYO | **Roo Code + OpenCode + Claude Code** |
| **AI cost control** | None | None | **Per-user budgets with hard caps** |
| **AI behavior enforcement** | None | None | **Server-side tamper-proof (3 levels)** |
| **AI audit trail** | None | None | **Every request: user, model, tokens, cost** |
| **PII/secret guardrails** | None | None | **Auto-mask or block sensitive data** |
| Offboarding | Retrieve laptop, rotate creds, remove from AD | Delete workspace | Delete workspace + revoke SSO |

---

## Cost Comparison

### Per-Developer Monthly Cost (50 offshore contractors)

```
 Windows VDI (Full Stack)                  Linux Containers (Coder)
 ──────────────────────────                ─────────────────────────

 COMPUTE & INFRASTRUCTURE                  COMPUTE & INFRASTRUCTURE
 VM compute:          $80-150              Container:         $10-25
 Storage:              $20-40              Shared EFS:         $5-10
 VDI broker (Citrix/   $10-20              Coder:          $0 (OSS)
   Horizon/AVD):

 MICROSOFT & OS LICENSING                  OS & PRODUCTIVITY
 Windows VDA license:   $4-7              Linux:                 $0
 M365 E1 (web-only,   $8/user             (no Windows = no VDA,
   download prohib.)                        no RDS CAL, no M365
 RDS CAL:              $5-8                for dev environment)
 Windows Server:       $3-5
   (per-user share)
                      ────────
 Subtotal:           $20-28

 ENDPOINT SECURITY STACK                   ENDPOINT SECURITY
 EDR (CrowdStrike):    $5-15              (not needed):          $0
 Zscaler (ZIA/ZPA):    $8-20              Platform firewall:     $0
 DLP (Digital Guard.): $8-15              Server-side guard:     $0
 AV / add'l agents:    $3-8              ────────────────────
                      ────────            Subtotal:              $0
 Subtotal:           $24-58

 ADMIN & OPERATIONS (per-user share)       ADMIN & OPERATIONS
 Windows admin:        $15-30              (template-based):   $5-10
   (AD/GPO/SCCM/Intune/patching)            (rebuild image once,
 Security admin:       $10-25               applies to all)
   (agent deploy/upgrade/policy/
    incident triage per VM)
 VDI support:          $10-20
                      ────────
 Subtotal:           $35-75

 AI TOOLS                                  AI TOOLS
 AI tools:              N/A                AI (LiteLLM):       $5-10

 ══════════════════════════                ═════════════════════════
 TOTAL:  $199-399/user/mo                  TOTAL:  $25-55/user/mo
                                           ═══════════════════════
                                           80-87% savings
```

### Microsoft Licensing Deep Dive

For offshore contractors on Windows VDI, the Microsoft licensing stack alone is significant:

| License | Cost/user/mo | Required For | Eliminated by Linux? |
|---------|-------------|-------------|---------------------|
| **Windows VDA** | $4-7 | Right to run Windows in virtual environment (required for non-SA devices) | **Yes** — Linux containers, no Windows OS |
| **M365 E1** (web-only) | $8 | Email, Teams, SharePoint (download prohibited for offshore) | **Partially** — still needed for email/Teams if used, but NOT a VDI dependency |
| **RDS CAL** | $5-8 | Remote Desktop Services per-user access | **Yes** — browser-based access, no RDP |
| **Windows Server** (per-user share) | $3-5 | Server OS for VDI host | **Yes** — Linux host + containers |

**Key distinction:** M365 E1 is a productivity license (email, Teams), not a VDI license. With Linux containers:
- **Windows VDA + RDS CAL + Windows Server = eliminated** ($12-20/user/mo saved)
- **M365 E1 = still needed** if contractors use Outlook/Teams, but it's decoupled from the dev environment
- **Total Microsoft savings** from VDI migration: $12-20/user/mo (VDA + RDS + Server), with E1 continuing only for email/collaboration

> *For 50 offshore contractors: **$600-1,000/mo in Microsoft licensing eliminated** from the dev environment alone — before counting compute, security, or admin savings.*

### What Makes the Difference

| Cost Category | Windows VDI | Linux Container | Savings |
|---------------|-------------|-----------------|---------|
| Compute + storage | $110-210 | $15-35 | ~80% (containers share resources, on-demand) |
| Microsoft licensing (VDA/RDS/Server) | $12-20 | $0 | **100%** (no Windows in dev environment) |
| M365 E1 | $8 | $8 (if email/Teams still used) | 0% (productivity, not dev infra) |
| Endpoint security licenses | $24-58 | $0 | **100%** (no Windows = no per-endpoint agents) |
| Admin labor (per-user share) | $35-75 | $5-10 | **85-90%** (templates replace per-VM ops) |
| AI tools | N/A | $5-10 | AI is additive, not a cost increase |

> *At 50 offshore contractors: **$9,950-$19,950/mo (VDI)** vs **$1,250-$2,750/mo (Coder)***
> *Microsoft licensing + security stack together ($36-78/user) costs more than the entire Coder platform ($25-55/user).*

### Admin Labor: The Invisible Multiplier

Windows VDI requires dedicated staff for operations that simply don't exist with Linux containers:

| Admin Task | Windows VDI (per month) | Linux Containers |
|-----------|------------------------|-----------------|
| **Windows patching** | Patch Tuesday per VM; test → stage → deploy; reboot scheduling | Rebuild container image; zero-downtime rollout |
| **Security agent lifecycle** | Deploy, upgrade, troubleshoot EDR/Zscaler/DLP per VM; handle agent conflicts | No agents to manage |
| **AD / Group Policy** | Domain join, GPO updates, certificate rotation, SCCM compliance scans | OIDC SSO — one identity provider, no domain |
| **Incident triage** | EDR alerts per VM; DLP policy violations; Zscaler tunnel failures | Platform-level alerts only; no per-container noise |
| **Vulnerability remediation** | Per-VM scanning (Qualys/Rapid7/Nessus), manual remediation tracking | `apt-get upgrade` in Dockerfile; push to all |
| **License tracking** | Windows VDA, RDS CAL, M365 E1, VDI broker, EDR, Zscaler, DLP — per-seat true-ups annually; offshore contractors require download-prohibited E1 | OSS Coder; Linux; no per-seat licensing |
| **User onboarding** | AD account → VDI pool assignment → agent deployment → compliance check → 1-2 weeks | SSO login → workspace auto-provisions → 1 hour |
| **User offboarding** | AD disable → VDI cleanup → license deallocation → compliance audit | Delete workspace → revoke SSO → done in minutes |

**Estimated FTE impact:** A 50-developer VDI fleet typically requires 0.5-1.0 FTE of combined Windows admin + security admin + VDI support. With containers, the same team manages the platform with ~0.1 FTE — the rest is automated by templates and SSO.

---

## Scaling Cost Comparison: 100 / 200 / 300 Developers

Real-world demand is not static. The baseline DevOps team (100 developers) is always-on, but project-based contractors ramp up and down. This section compares costs at three tiers:

- **100 developers** — Baseline DevOps team (permanent)
- **200 developers** — Baseline + 100 project contractors
- **300 developers** — Baseline + 200 project contractors

### VDI: Linear Scaling (Every Seat = Full Stack)

Every additional VDI developer requires a full Windows VM + security agents + Microsoft licenses + admin effort. Costs scale 1:1 with headcount.

```
                        100 devs        200 devs        300 devs
                        (baseline)      (+100 proj)     (+200 proj)
 ─────────────────────────────────────────────────────────────────
 Compute + storage      $11,000-21,000  $22,000-42,000  $33,000-63,000
 Microsoft licensing    $2,000-2,800    $4,000-5,600    $6,000-8,400
   (VDA+RDS+Server)
 M365 E1 (web-only)     $800            $1,600          $2,400
 Security stack         $2,400-5,800    $4,800-11,600   $7,200-17,400
   (EDR+Zscaler+DLP)
 Admin labor            $3,500-7,500    $7,000-15,000   $10,500-22,500
 VDI broker license     $1,000-2,000    $2,000-4,000    $3,000-6,000
 ─────────────────────────────────────────────────────────────────
 TOTAL (monthly)        $20,700-40,100  $41,400-79,800  $62,100-119,700
 TOTAL (annual)         $248K-481K      $497K-958K      $745K-$1.44M
 ─────────────────────────────────────────────────────────────────
 Admin FTE required     1-2 FTE         2-4 FTE         3-6 FTE
 CDM provisioning team  0.5-1 FTE       1-2 FTE         1.5-3 FTE
```

**VDI pain at scale:** Adding 100 project contractors means 100 more VMs to provision, 100 more security agent deployments, 100 more Windows licenses, and proportionally more admin headcount. When the project ends, those VMs sit idle or require decommissioning effort.

### Coder: Sub-Linear Scaling (Shared Platform, Concurrency-Based Compute)

Container platforms scale differently. The platform infrastructure (Kubernetes cluster, Coder server, SSO, AI proxy) is shared — adding users adds containers, not VMs or agents. Compute scales with **concurrency** (how many developers work simultaneously), not **headcount**.

```
                        100 devs        200 devs        300 devs
                        (baseline)      (+100 proj)     (+200 proj)
 ─────────────────────────────────────────────────────────────────
 Container compute      $1,500-3,500    $2,500-5,500    $3,500-7,500
   (concurrency-based:
    ~60% active at once)
 Shared storage (EFS)   $500-1,000      $800-1,500      $1,000-2,000
 Coder Enterprise       $3,000-5,000    $6,000-10,000   $9,000-15,000
   license ($30-50/user)
 AI tools (LiteLLM)     $500-1,000      $1,000-2,000    $1,500-3,000
 Platform admin labor   $2,000-4,000    $2,500-5,000    $3,000-6,000
 ─────────────────────────────────────────────────────────────────
 TOTAL (monthly)        $7,500-14,500   $12,800-24,000  $18,000-33,500
 TOTAL (annual)         $90K-174K       $154K-288K      $216K-402K
 ─────────────────────────────────────────────────────────────────
 Platform admin FTE     0.25-0.5 FTE    0.5-0.75 FTE    0.5-1 FTE
 Provisioning team      0 (self-serve)  0 (self-serve)  0 (self-serve)
```

**Why compute scales sub-linearly:**
- Not all 300 developers work at the same time — workspaces auto-stop after idle timeout
- Kubernetes right-sizes pods based on actual resource usage, not allocated VM capacity
- Adding 100 project contractors may only need 30-40% more compute (concurrency < headcount)
- When the project ends, workspaces are deleted — compute drops immediately, zero decommissioning

### Side-by-Side: Annual Cost at Scale

```
 Developers    VDI (annual)          Coder (annual)      Savings        Savings %
 ─────────────────────────────────────────────────────────────────────────────────
 100           $248K - $481K         $90K - $174K        $158K-307K     62-64%
 200           $497K - $958K         $154K - $288K       $343K-670K     69-70%
 300           $745K - $1.44M        $216K - $402K       $529K-$1.04M   71-72%
```

> **Key insight:** Savings percentage *increases* with scale. VDI costs grow linearly (every seat adds compute + licenses + security + admin). Container costs grow sub-linearly (shared platform, concurrency-based compute, zero per-endpoint licensing). At 300 developers, VDI admin alone (3-6 FTE) costs more than the entire container platform.

### Coder Enterprise: Platform Investment

The cost comparison above includes **Coder Enterprise** (not OSS) to reflect production-grade deployment with:

| Coder Enterprise Feature | Value |
|--------------------------|-------|
| **Template RBAC** | Per-template visibility — show only relevant templates to each team |
| **High availability** | Multi-replica Coder server with automatic failover |
| **Audit logging** | Detailed workspace lifecycle events for compliance |
| **Quotas** | Per-user and per-group resource quotas |
| **Premium support** | Vendor SLA, direct engineering support |
| **Appearance customization** | Branded login page, custom messaging |

**Estimated license:** $30-50/user/month (varies by contract size; volume discounts at 200+ seats). Contact [coder.com/pricing](https://coder.com/pricing) for exact quotes.

**Platform admin effort for Coder:**

| Task | Effort | Frequency |
|------|--------|-----------|
| Template maintenance (Dockerfile + Terraform) | 2-4 hrs/template | Monthly or on-demand |
| Coder server upgrades | 1-2 hrs | Quarterly |
| SSO / identity management (Authentik) | 1-2 hrs | On-demand |
| LiteLLM model config + budget review | 1-2 hrs | Monthly |
| Monitoring / alerting review | 1-2 hrs | Weekly |
| User support (mostly self-serve) | 2-4 hrs | Weekly |
| **Total** | **~0.25-0.5 FTE at 100 devs; ~0.5-1 FTE at 300 devs** | |

Compared to VDI's 4.5-9 combined FTE at 300 developers (3-6 admin + 1.5-3 CDM provisioning), Coder requires 0.5-1 FTE total — a **80-90% reduction in operational headcount**.

---

## CDM Team vs Self-Service Provisioning

The biggest operational difference is not compute or licensing — it's **who provisions environments and how long it takes**.

> **Terminology:** "Requestor" below refers to the **system DevOps manager** (for existing systems) or **project manager** (for new projects or significant changes) — the person responsible for their team's development environments.

### Current Model: CDM Team Provisions VDI

```
 DevOps/Project Manager            CDM Team                         Developer
 ────────────────────────────────────────────────────────────────────────────
 1. Submit request  ──────────►  2. Receive ticket
    (ServiceNow/email)           3. Allocate VM from pool
                                 4. Install tools & runtimes
                                 5. Deploy security agents         ◄── 3-5 days
                                    (EDR, Zscaler, DLP)
                                 6. Configure AD/GPO/certificates
                                 7. Run compliance check
                                 8. Assign user, send credentials ─►  9. First login
                                                                      10. Self-configure
                                                                          remaining tools
                                                                          ◄── 1-2 weeks
                                                                              total
```

**CDM team bottleneck at scale:**

| Team Size | Provisioning Requests/mo | CDM FTE Needed | Avg Wait Time |
|-----------|-------------------------|----------------|---------------|
| 100 (stable) | 5-10 (turnover/new projects) | 0.5-1 | 3-5 days |
| 200 (+100 project) | 100+ (initial ramp) then 10-15/mo | 1-2 (peak: 3+) | 1-2 weeks at ramp |
| 300 (+200 project) | 200+ (initial ramp) then 15-20/mo | 1.5-3 (peak: 5+) | 2-3 weeks at ramp |

At project ramp-up, the CDM team becomes the critical path. 200 contractors waiting for VDI provisioning at 5 per day = **6-8 weeks** before all developers are productive.

### New Model: DevOps/Project Manager Self-Service with Coder

```
 DevOps/Project Manager                          Developer
 ────────────────────────────────────────────────────────────────
 1. Select template   ──── (dropdown: backend /
    matching role           frontend / data-eng /
                            ML / full-stack)

 2. Set team size     ──── (workspace count)

 3. Invite via SSO    ──── (email/OIDC group) ──►  4. Click SSO login
                                                   5. Workspace auto-provisions
                                                      (30-60 seconds)
                                                   6. Tools, runtimes, AI agents
                                                      pre-configured
                                                   ◄── < 1 hour total
```

**Key differences:**

| Dimension | VDI (CDM Team) | Coder (Self-Service) |
|-----------|---------------|---------------------|
| **Who provisions** | CDM team (specialized staff) | DevOps manager or project manager (self-serve) |
| **Time to first commit** | 1-2 weeks | < 1 hour |
| **Provisioning at scale (200 devs)** | 6-8 weeks (CDM bottleneck) | Same day (parallel auto-provision) |
| **Environment consistency** | CDM follows runbook; drift happens | Template guarantees identical environments |
| **Right-sizing** | CDM picks from 2-3 VM sizes | Templates match role: backend (4 CPU/8 GB), ML (8 CPU/32 GB + GPU) |
| **Decommissioning** | CDM ticket → VM cleanup → license release → compliance audit | Delete workspace (1 click); SSO revoke |
| **CDM team involvement** | Required for every provision/deprovision | Zero — CDM focuses on platform, not provisioning |
| **Cost of project ramp-up** | CDM overtime + contractor wait time + lost productivity | Zero marginal provisioning cost |

### Impact on Project Economics

For a 6-month project adding 200 contractors:

```
                                    VDI                     Coder
 ────────────────────────────────────────────────────────────────
 Ramp-up delay                      6-8 weeks               Same day
 Lost productivity (ramp delay)     200 devs × 6 weeks      $0
                                    × $60-80/hr =
                                    $2.9M-3.8M in
                                    delayed billable hours

 CDM team cost (project)            2-3 FTE × 6 mo          $0 (self-serve)
                                    = $60K-135K

 Decommission cost (project end)    CDM ticket per dev       1-click bulk delete
                                    + compliance audit
                                    = $15K-30K

 Per-developer monthly run          $199-399/user            $64-112/user
   (incl. Enterprise license)                                (with Coder Enterprise)
 ────────────────────────────────────────────────────────────────
 6-month project total (200 devs)   $314K-$544K              $77K-134K
   (run cost only, excl. ramp)      + $3M-4M ramp delay      + $0 ramp delay
```

> **The ramp-up delay cost alone ($2.9M-3.8M in delayed billable hours) dwarfs the entire 6-month platform cost.** Self-service provisioning isn't just a convenience — it's the difference between a project starting on time and starting 6 weeks late.

---

## Operating Model: Roles & Responsibilities

### Linux Containers Still Need Patching — But the Model is Fundamentally Different

A common objection: "You still need to patch Linux." True — but the effort is O(1), not O(n):

| Aspect | Windows VDI (per-VM patching) | Linux Container (image-based patching) |
|--------|------------------------------|---------------------------------------|
| **What gets patched** | Each individual VM (300 VMs = 300 patch jobs) | The **base Docker image** (1 image = all workspaces) |
| **How** | SCCM/Intune push → test → stage → deploy → reboot scheduling → compliance verify per VM | `apt-get upgrade` in Dockerfile → `docker build` → push template |
| **Downtime per dev** | Reboot window per VM, staggered rollout (1-2 hrs/VM over days) | Zero — new workspaces get the new image; existing pick it up on next restart |
| **Patch Tuesday effort** | 2-3 days for 300 VMs (test, stage, deploy, verify, handle failures) | 2-4 hours total (rebuild image, test, push template) |
| **Rollback** | Manual per-VM; risky | Revert Dockerfile commit; instant rollback to prior image |
| **Compliance verification** | Per-VM scan (Qualys/Rapid7/Nessus); remediation tracking per VM | Scan the image once; all workspaces inherit the result |
| **Security agent updates** | EDR, Zscaler, DLP agent upgrades per VM (quarterly, with conflicts) | No agents — nothing to upgrade |
| **Who does it** | CDM team + Windows admin (per-VM work) | Platform team (one-time image build) |
| **Effort at 300 devs** | 300 VMs × patch/verify/reboot = 1-2 FTE continuous | 1 Dockerfile change = same effort as 10 devs |

> **Key distinction:** "Zero patching" means zero **per-container** patching, not zero patching overall. The platform team patches the Dockerfile (base image) once per cycle — one change propagates to all workspaces. This is the same model used by every container-based platform in production (Kubernetes, ECS, etc.).

### Team Responsibility Matrix

Four teams interact with this platform. The table below defines clear ownership:

| Responsibility | CDM Team | Infra / Network | Platform Team (Coder) | AWS Cloud Team |
|---------------|----------|-----------------|----------------------|----------------|
| **VDI provisioning** | Current owner → **eliminated** for Coder workspaces | — | — | — |
| **Container image patching** | — | — | **Own**: Rebuild Dockerfile, test, push template (monthly + CVE) | — |
| **Container security scanning** | — | — | **Own**: Trivy/Grype scan on image build; fix before push | — |
| **Coder server operation** | — | — | **Own**: Upgrades, config, monitoring, template management | — |
| **Template creation / maintenance** | — | — | **Own**: Dockerfile + Terraform per role; test + publish | — |
| **SSO / identity (Authentik)** | User lifecycle (onboard/offboard from HR system) | — | **Own**: Authentik config, OIDC groups, RBAC mapping | — |
| **AI gateway (LiteLLM)** | — | — | **Own**: Model config, budgets, guardrails, key management | — |
| **Kubernetes / EKS cluster** | — | — | Workload deployment, pod sizing, namespace config | **Own**: Cluster lifecycle, node groups, auto-scaling, upgrades |
| **Networking / egress** | — | **Own**: Firewall rules, VPN, DNS, egress whitelisting | Request changes as needed | VPC, subnet, security group config |
| **AWS infrastructure** | — | — | Define resource requirements (EKS node sizes, EFS, RDS) | **Own**: Provision EKS, RDS, EFS, IAM roles, cost optimization |
| **Security compliance** | Endpoint compliance → **shifts to platform-level** | Network security policy | **Own**: Container security, guardrail policy, audit logs | Cloud security posture (GuardDuty, Config, CloudTrail) |
| **User onboarding** | Identity lifecycle (HR-driven) | — | **Minimal** — self-service via SSO; template auto-provisions | — |
| **User offboarding** | Trigger from HR system | — | Revoke SSO → workspaces auto-deactivate | — |
| **Incident response** | — | Network incidents | Platform / workspace incidents; AI guardrail alerts | AWS infrastructure incidents |
| **Cost management** | — | — | LiteLLM budget monitoring; workspace auto-stop tuning | AWS cost allocation tags; Reserved Instance planning |

### What Changes for Each Team

**CDM Team — Freed from per-developer provisioning:**
- **Before:** Receives ticket → provisions VDI → installs tools → deploys security agents → configures AD/GPO → runs compliance check → assigns user. Repeat for every developer. 0.5-3 FTE depending on scale.
- **After:** No longer provisions dev environments. Retains identity lifecycle management (onboard/offboard from HR system) and non-dev infrastructure. CDM staff can be redeployed to other infrastructure work.

**Platform Team (NEW ROLE) — Owns the Coder platform:**
- Small team (0.5-1 FTE at 300 devs) responsible for: template maintenance, image patching, Coder server operation, SSO config, AI gateway management, monitoring.
- This is **not an additional headcount** — it replaces the VDI admin + security admin + CDM provisioning roles (4.5-9 FTE at 300 devs). Net reduction: 4-8 FTE.
- Skills required: Docker/Kubernetes, Terraform, Linux administration, SSO/OIDC concepts. No Windows admin skills needed.

**Infra / Network Team — Unchanged scope:**
- Continues to own network security, firewall rules, DNS, VPN. No new responsibilities.
- May receive egress whitelist requests from the platform team (e.g., allow containers to reach specific Git servers or package registries).

**AWS Cloud Team — Infrastructure provider:**
- Provisions and manages EKS cluster, RDS (Coder database), EFS (shared storage), IAM roles.
- Does **not** touch workspaces, templates, or developer tools.
- Existing cloud team skills apply directly — EKS is standard Kubernetes.

### Transition: CDM Team Impact

```
                        VDI Model (Current)              Coder Model (Target)
 ─────────────────────────────────────────────────────────────────────────────
 CDM Team               0.5-3 FTE                        0 FTE (provisioning
   (provisioning)        (scales with headcount)           eliminated by
                                                          self-service)

 Windows Admin           1-2 FTE                          0 FTE (no Windows)
   (patching/AD/GPO)

 Security Admin           0.5-1.5 FTE                     0 FTE (no per-VM
   (agent lifecycle)       (EDR/Zscaler/DLP per VM)        agents)

 VDI Support              0.5-1 FTE                       0 FTE (no VDI)
   (broker/session mgmt)

 Platform Team            0 FTE                           0.5-1 FTE (new role)
   (Coder/K8s/templates)

 ─────────────────────────────────────────────────────────────────────────────
 TOTAL at 300 devs       4.5-9 FTE                       0.5-1 FTE
 Net change                                              -4 to -8 FTE
                                                         (80-90% reduction)
```

> **CDM team members are not eliminated — they are redeployed.** Their Windows admin, security agent, and provisioning skills are freed up for other infrastructure modernization work. The platform team role requires different skills (containers, Kubernetes, IaC) and may be staffed from existing DevOps or SRE teams.

---

## Why This Matters Now

1. **The security stack costs more than the platform** — EDR + Zscaler + DLP licenses alone ($24-58/user/mo) exceed the entire cost of a container-based platform including Coder Enterprise ($64-112/user/mo vs $199-399 for VDI). Linux containers eliminate 100% of per-endpoint security licensing.

2. **Admin labor doesn't scale** — Every Windows VDI added means more patching, more agent troubleshooting, more AD management. At 300 developers, VDI needs 4.5-9 FTE for admin + provisioning; Coder needs 0.5-1 FTE. Containers are immutable — update the image once, all workspaces inherit the change.

3. **CDM provisioning is the hidden bottleneck** — Adding 200 project contractors takes 6-8 weeks via CDM team (5 VMs/day). Self-service provisioning with Coder: same day. The ramp-up delay cost ($2.9M-3.8M in lost billable hours) dwarfs the entire platform investment.

4. **AI agents are here** — Roo Code, OpenCode, Claude Code CLI are production-ready. VDI has no governed way to deploy them. Container-based platforms provide AI with built-in budgets, enforcement, and audit.

5. **Cost savings increase with scale** — At 100 developers: 62-64% savings. At 300 developers: 71-72% savings. VDI scales linearly; containers scale sub-linearly (shared platform, concurrency-based compute).

6. **Contractor security is stronger, not weaker** — Browser-only access with container isolation + server-side guardrails replaces DLP agents that contractors can circumvent. No data ever reaches a local device.

---

## One Slide Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│   FROM WINDOWS VDI TO LINUX CONTAINERS: PROVEN AT SCALE         │
│                                                                  │
│   62-72%  total cost reduction (incl. Coder Enterprise license) │
│   100%    endpoint security licensing eliminated                │
│           (no EDR, no Zscaler, no DLP agents)                   │
│   80-90%  admin headcount reduction (0.5-1 FTE vs 4.5-9 FTE)   │
│   < 1 hr  new hire → first commit  (was 1-2 weeks)              │
│   Same    day project ramp-up  (was 6-8 weeks via CDM team)     │
│   0       API keys on contractor devices                        │
│   3       AI agents with server-side governance                 │
│                                                                  │
│   At 300 developers:                                             │
│     VDI:   $745K - $1.44M/yr + 4.5-9 FTE                       │
│     Coder: $216K - $402K/yr  + 0.5-1 FTE                       │
│                                                                  │
│   Self-service provisioning eliminates CDM bottleneck —         │
│   DevOps/project managers provision directly.                    │
│   Ramp delay cost ($2.9M-3.8M for 200 contractors)              │
│   dwarfs the entire platform investment.                         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## References

- [Skydio Reduces Cloud Computing Costs by 90% with Coder](https://coder.com/success-stories/skydio)
- [J.B. Hunt Reduces Developer VDI Costs by 90% with Coder](https://coder.com/success-stories/jbhunt)
- [Coder: A Better VDI Alternative for Developers](https://coder.com/blog/coder-better-vdi-alternative-for-developers)
- [Comparison of Development Environments](https://coder.com/blog/comparison-of-development-environments)
- [From VDI to CDEs: Solving Remote Development Challenges (JetBrains)](https://blog.jetbrains.com/codecanvas/2024/12/from-vdi-to-cdes-solving-remote-development-challenges/)

---

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-08 | Platform Team | Initial version — VDI to Coder business case with Skydio/J.B. Hunt references |
| 1.1 | 2026-02-08 | Platform Team | Add Windows endpoint security stack analysis (EDR/Zscaler/DLP), admin labor costs, FTE impact |
| 1.2 | 2026-02-08 | Platform Team | Break out Microsoft licensing (VDA, M365 E1, RDS CAL, Windows Server); offshore contractor context |
| 1.3 | 2026-02-08 | Platform Team | Add scaling comparison (100/200/300 devs); Coder Enterprise license; CDM team vs self-service provisioning; project ramp-up economics |
| 1.4 | 2026-02-08 | Platform Team | Add Operating Model: R&R matrix (CDM/Infra/Platform/AWS), Linux patching clarification, CDM team transition impact |
