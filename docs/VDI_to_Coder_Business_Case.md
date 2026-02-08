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
| OS licensing | Windows per-VM | None (Linux) | None (Linux) |
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

### Per-Developer Monthly Cost (50 users)

```
 Windows VDI (Full Stack)                  Linux Containers (Coder)
 ──────────────────────────                ─────────────────────────

 COMPUTE & INFRASTRUCTURE                  COMPUTE & INFRASTRUCTURE
 VM compute:          $80-150              Container:         $10-25
 Windows license:      $15-25              OS license:            $0
 Storage:              $20-40              Shared EFS:         $5-10
 VDI broker:           $10-20              Coder:          $0 (OSS)

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
 TOTAL:  $184-368/user/mo                  TOTAL:  $25-55/user/mo
                                           ═══════════════════════
                                           80-85% savings
```

### What Makes the Difference

| Cost Category | Windows VDI | Linux Container | Savings |
|---------------|-------------|-----------------|---------|
| Compute + storage | $110-210 | $15-35 | ~80% (containers share resources, on-demand) |
| Endpoint security licenses | $24-58 | $0 | **100%** (no Windows = no per-endpoint agents) |
| Admin labor (per-user share) | $35-75 | $5-10 | **85-90%** (templates replace per-VM ops) |
| OS licensing | $15-25 | $0 | **100%** |
| AI tools | N/A | $5-10 | AI is additive, not a cost increase |

> *At 50 developers: **$9,200-$18,400/mo (VDI)** vs **$1,250-$2,750/mo (Coder)***
> *The security stack alone costs more than the entire Coder platform.*

### Admin Labor: The Invisible Multiplier

Windows VDI requires dedicated staff for operations that simply don't exist with Linux containers:

| Admin Task | Windows VDI (per month) | Linux Containers |
|-----------|------------------------|-----------------|
| **Windows patching** | Patch Tuesday per VM; test → stage → deploy; reboot scheduling | Rebuild container image; zero-downtime rollout |
| **Security agent lifecycle** | Deploy, upgrade, troubleshoot EDR/Zscaler/DLP per VM; handle agent conflicts | No agents to manage |
| **AD / Group Policy** | Domain join, GPO updates, certificate rotation, SCCM compliance scans | OIDC SSO — one identity provider, no domain |
| **Incident triage** | EDR alerts per VM; DLP policy violations; Zscaler tunnel failures | Platform-level alerts only; no per-container noise |
| **Vulnerability remediation** | Per-VM scanning (Qualys/Rapid7/Nessus), manual remediation tracking | `apt-get upgrade` in Dockerfile; push to all |
| **License tracking** | Windows, VDI broker, EDR, Zscaler, DLP — per-seat true-ups annually | OSS Coder; Linux; no per-seat licensing |
| **User onboarding** | AD account → VDI pool assignment → agent deployment → compliance check → 1-2 weeks | SSO login → workspace auto-provisions → 1 hour |
| **User offboarding** | AD disable → VDI cleanup → license deallocation → compliance audit | Delete workspace → revoke SSO → done in minutes |

**Estimated FTE impact:** A 50-developer VDI fleet typically requires 0.5-1.0 FTE of combined Windows admin + security admin + VDI support. With containers, the same team manages the platform with ~0.1 FTE — the rest is automated by templates and SSO.

---

## Why This Matters Now

1. **The security stack costs more than the platform** — EDR + Zscaler + DLP licenses alone ($24-58/user/mo) exceed the entire cost of a container-based platform ($25-55/user/mo including AI). Linux containers eliminate 100% of per-endpoint security licensing.

2. **Admin labor doesn't scale** — Every Windows VDI added means more patching, more agent troubleshooting, more AD management. Containers are immutable — update the image once, all workspaces inherit the change. You manage templates, not VMs.

3. **AI agents are here** — Roo Code, OpenCode, Claude Code CLI are production-ready. VDI has no governed way to deploy them. Container-based platforms provide AI with built-in budgets, enforcement, and audit.

4. **Cost pressure is real** — VDI cloud spend + security licenses + admin labor is the #1 infrastructure complaint. 80-90% total cost reduction is proven by Skydio and J.B. Hunt.

5. **Contractor security is stronger, not weaker** — Browser-only access with container isolation + server-side guardrails replaces DLP agents that contractors can circumvent. No data ever reaches a local device.

---

## One Slide Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│   FROM WINDOWS VDI TO LINUX CONTAINERS: PROVEN AT SCALE         │
│                                                                  │
│   80-85%  total cost reduction (compute + security + admin)     │
│   100%    endpoint security licensing eliminated                │
│           (no EDR, no Zscaler, no DLP agents)                   │
│   90%     admin labor reduction (templates replace per-VM ops)  │
│   1 hr    new hire → first commit  (was 1-2 weeks)              │
│   0       API keys on contractor devices                        │
│   3       AI agents with server-side governance                 │
│                                                                  │
│   "Skydio reduced cloud computing costs by 90% by              │
│    automating shutdown of unused VMs and GPUs, making           │
│    those resources available to other teams."                    │
│                                    — coder.com/success-stories   │
│                                                                  │
│   The Windows endpoint security stack alone costs more          │
│   than the entire Linux container platform.                      │
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
