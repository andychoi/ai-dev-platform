# Coder WebIDE: Secure AI-Ready Development Environments

**Developer Tech Day 2026**
*15-minute presentation + Q&A*

---

## Slide 1: Title

**Coder WebIDE**
*Secure, Cost-Effective, AI-Ready Development Environments*

- Presenter: [Your Name]
- Date: February 2026
- Duration: 15 minutes

---

## Slide 2: The Problem

**Traditional VDI Pain Points**

| Challenge | Impact |
|-----------|--------|
| Slow startup | 5-15 min to get a working environment |
| High cost | Windows licenses + VDI infrastructure |
| Resource waste | Full VM per developer, always running |
| Security gaps | Data on local devices, inconsistent policies |
| Onboarding delay | Days to weeks for new hire setup |

**The AI Challenge:**
- How do we give developers AI coding assistants (Claude, Copilot)?
- Without exposing API keys or leaking code to untrusted devices?

---

## Slide 3: The Solution - Coder WebIDE

**Browser-Based Development Environments**

```
┌──────────────────┐
│  Developer's     │  Any device, any location
│  Browser         │  No local code, no secrets
└────────┬─────────┘
         │ HTTPS only
         ▼
┌──────────────────────────────────────────┐
│           Coder Platform                  │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ │
│  │Workspace │ │Workspace │ │Workspace │ │
│  │ VS Code  │ │ VS Code  │ │ VS Code  │ │
│  │ Terminal │ │ Terminal │ │ Terminal │ │
│  └──────────┘ └──────────┘ └──────────┘ │
│         All code stays here              │
└──────────────────────────────────────────┘
```

**Key Insight:** Full VS Code experience in browser, code never leaves our infrastructure

---

## Slide 4: Four Key Objectives

### 1. Security & Compliance
- Zero-trust: No shell/RDP from untrusted devices
- SSO via Authentik (OIDC) - integrates with Azure AD
- Complete audit trail

### 2. Cost Reduction (40-60% vs VDI)
- Containers vs VMs: 10x density
- 30-60 sec startup vs 5-15 min
- No Windows/VDI licenses

### 3. Fast Onboarding
- New hire → productive in **minutes**, not days
- Standardized templates eliminate "works on my machine"

### 4. AI-Ready Platform
- Secure AI Gateway for Claude, Bedrock, Gemini
- Built for AI coding agents (Claude Code, Cursor)

---

## Slide 5: Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Platform Services                      │
├─────────────┬─────────────┬─────────────┬───────────────┤
│   Coder     │  Authentik  │   Gitea     │  AI Gateway   │
│   :7080     │  (SSO)      │  (Git)      │   :8090       │
│             │   :9000     │   :3000     │               │
└─────────────┴─────────────┴─────────────┴───────────────┘
        │                           │              │
        ▼                           ▼              ▼
┌─────────────┐             ┌─────────────┐  ┌──────────┐
│ Workspaces  │             │ Repositories│  │ Claude   │
│ (Containers)│◄───────────►│             │  │ Bedrock  │
└─────────────┘             └─────────────┘  │ Gemini   │
                                             └──────────┘
```

**All services containerized, self-hosted, enterprise-controlled**

---

## Slide 6: AI Gateway - Secure AI Access

**Problem:** Developers need AI assistants, but:
- Can't expose API keys to local machines
- Need audit trail of AI usage
- Need rate limiting and cost control

**Solution:** Centralized AI Gateway

| Feature | Benefit |
|---------|---------|
| No credential exposure | API keys in gateway only |
| Multi-provider | Claude, Bedrock, Gemini via single endpoint |
| Rate limiting | Per-user request controls |
| Audit logging | Full request/response tracking |
| Future-ready | Supports AI agents (Claude Code) |

```python
# From any workspace - no API key needed
curl http://ai-gateway:8090/v1/claude/messages \
  -d '{"model": "claude-sonnet-4", "messages": [...]}'
```

---

## Slide 7: Live Demo

**Demo Flow (3-4 minutes)**

1. **Login via SSO** (Authentik → Azure AD ready)
   - Show OIDC login flow

2. **Create Workspace** (30-60 seconds)
   - Select template
   - Watch container spin up

3. **VS Code in Browser**
   - Full IDE experience
   - Pre-installed extensions
   - Terminal access

4. **AI Assistant**
   - Use Claude via AI Gateway
   - Show audit log entry

5. **Git Workflow**
   - Clone from Gitea
   - Commit and push

---

## Slide 8: Results & Metrics

| Metric | Before (VDI) | After (Coder) | Improvement |
|--------|--------------|---------------|-------------|
| Environment startup | 5-15 min | 30-60 sec | **90%+ faster** |
| New hire onboarding | 2-5 days | < 1 hour | **95%+ faster** |
| Infrastructure cost | $X/user/mo | ~0.5X | **40-60% savings** |
| Security incidents | Manual audit | Full auto-audit | **100% visibility** |

**Developer Feedback:**
> "Finally, I can code from my iPad on the train"
> "AI assistant without fighting IT for API keys"
> "New contractor was coding within 30 minutes of signing NDA"

---

## Slide 9: Roadmap & Next Steps

**Current State:** PoC Complete ✅
- 14 services running
- SSO integrated
- AI Gateway operational

**Next Steps:**
1. **Pilot Program** - Q1 2026
   - 10-20 developers
   - Gather feedback

2. **Production Deployment** - Q2 2026
   - Kubernetes migration
   - HA/DR setup

3. **Enterprise Features** - Q3 2026
   - Azure AD federation
   - Advanced RBAC
   - Cost allocation per team

**Get Involved:**
- GitHub: github.com/andychoi/dev-platform
- Slack: #coder-webide-pilot
- Contact: [your-email]

---

## Slide 10: Q&A

**Questions?**

**Resources:**
- Coder: https://coder.com
- AI Platform Blog: https://coder.com/blog/coder-enterprise-grade-platform-for-self-hosted-ai-development
- PoC Repo: github.com/andychoi/dev-platform

**Key Takeaways:**
1. Browser-based IDE = security + flexibility
2. 40-60% cost savings vs traditional VDI
3. AI-ready infrastructure for the future
4. Minutes to productivity, not days

---

# Speaker Notes

## Timing Guide (15 minutes total)

| Slide | Time | Notes |
|-------|------|-------|
| 1. Title | 0:30 | Quick intro |
| 2. Problem | 1:30 | Connect with audience pain points |
| 3. Solution | 1:30 | High-level "aha" moment |
| 4. Objectives | 2:00 | Four key pillars |
| 5. Architecture | 1:30 | Technical overview |
| 6. AI Gateway | 1:30 | Differentiation point |
| 7. Live Demo | 4:00 | The exciting part |
| 8. Results | 1:30 | Prove the value |
| 9. Roadmap | 1:00 | Call to action |
| 10. Q&A | Buffer | Handle questions |

## Demo Backup Plan

If live demo fails:
- Have screenshots ready
- Pre-recorded video as backup
- Focus on architecture slides

## Anticipated Questions

1. **"How does this compare to GitHub Codespaces?"**
   - Self-hosted = full control, no data leaves our network
   - Custom AI gateway integration

2. **"What about existing VDI investments?"**
   - Can run alongside, gradual migration
   - Different use cases (dev vs general desktop)

3. **"Security audit?"**
   - PoC security review completed
   - Production hardening plan documented
