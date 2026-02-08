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
| **AI integration** | No governed path to give developers AI tools without exposing API keys |

> *"What started as an exciting software project became a maintenance burden needing constant attention."*
> — Elliot, Head of Internal Infrastructure, Skydio

---

## The Container Alternative

Replace heavyweight VDI VMs with lightweight, purpose-built containers that run only what developers need — an IDE backend, a terminal, and project tooling. No desktop rendering, no OS licensing, no configuration drift.

```
 VDI (Traditional)                    Coder (Container-Based)
 ─────────────────                    ──────────────────────
 ┌──────────────────┐                 ┌──────────────────┐
 │  Windows Desktop │ ◄── RDP/VDI ──  │  Browser Tab     │
 │  VS Code         │    stream       │  (VS Code Web)   │
 │  Runtime         │                 └────────┬─────────┘
 │  OS + Drivers    │                          │ text only
 │  Full VM (8+ GB) │                 ┌────────▼─────────┐
 └──────────────────┘                 │  Container (1 GB) │
 Always-on, per-user                  │  IDE backend only │
 Windows license required             │  Ephemeral, shared│
                                      │  infra             │
                                      └──────────────────┘
                                      On-demand, no license
```

**Key insight:** CDEs only run the IDE backend remotely, communicating via efficient text protocols — not streaming a full graphical desktop. Bandwidth requirements drop by an order of magnitude.

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

| Dimension | Traditional VDI | Coder (Industry) | Our Platform |
|-----------|----------------|-------------------|--------------|
| Environment setup | 5-15 min | 30-60 sec | 30-60 sec |
| Onboarding | 1-2 weeks | < 1 hour | < 1 hour |
| Cost vs VDI | Baseline | **90% reduction** | **90% reduction** |
| Configuration drift | Per-VM | Template-based | Template-based |
| Desktop streaming | Yes (high bandwidth) | No (text only) | No (text only) |
| OS licensing | Windows per-VM | None | None |
| **AI coding agents** | None / unmanaged | BYO | **Roo Code + OpenCode + Claude Code** |
| **AI cost control** | None | None | **Per-user budgets with hard caps** |
| **AI behavior enforcement** | None | None | **Server-side tamper-proof (3 levels)** |
| **AI audit trail** | None | None | **Every request: user, model, tokens, cost** |
| **PII/secret guardrails** | None | None | **Auto-mask or block sensitive data** |
| Offboarding | Retrieve laptop, rotate creds | Delete workspace | Delete workspace + revoke SSO |

---

## Cost Comparison

### Per-Developer Monthly Cost (50 users)

```
 VDI (Traditional)          Coder (Our Platform)
 ─────────────────          ────────────────────
 VM compute:    $80-150     Container:    $10-25
 Windows license: $15-25    OS license:      $0
 Storage:        $20-40     Shared EFS:    $5-10
 VDI broker:     $10-20     Coder:           $0 (OSS)
 Support/admin:  $30-50     Template-based: $5-10
 AI tools:       N/A        AI (LiteLLM):  $5-10
 ─────────────────          ────────────────────
 Total: $155-285/user/mo    Total: $25-55/user/mo
                            ═══════════════════
                            70-80% savings
```

> *At 50 developers: **$7,750-$14,250/mo (VDI)** vs **$1,250-$2,750/mo (Coder)***

---

## Why This Matters Now

1. **AI agents are here** — Roo Code, OpenCode, Claude Code CLI are production-ready. VDI has no governed way to deploy them.

2. **Cost pressure is real** — VDI cloud spend is the #1 infrastructure complaint from developer teams. 90% reduction is proven, not theoretical.

3. **Contractor security is non-negotiable** — Browser-only access with container isolation eliminates the data exfiltration risk that VDI merely relocates.

4. **Onboarding speed is competitive advantage** — 1 hour vs 2 weeks means contractors deliver value from day one.

---

## One Slide Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│   FROM VDI TO CODER: PROVEN AT SCALE                            │
│                                                                  │
│   90%     cost reduction    (Skydio, J.B. Hunt)                 │
│   1 hr    new hire → first commit  (was 1-2 weeks)              │
│   0       API keys on contractor devices                        │
│   3       AI agents with server-side governance                 │
│   17      integrated services, single deployment                │
│                                                                  │
│   "Skydio reduced cloud computing costs by 90% by              │
│    automating shutdown of unused VMs and GPUs, making           │
│    those resources available to other teams."                    │
│                                    — coder.com/success-stories   │
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
