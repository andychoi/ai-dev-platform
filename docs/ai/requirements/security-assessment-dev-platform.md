# Security Assessment: Dev Platform for External Contractors

## Executive Summary

This document assesses the current security architecture for external contractor access and proposes how a Coder-based development platform can provide equivalent or improved security controls while enhancing developer productivity.

**Current State:** Azure VDI + Cisco AnyConnect + Azure AD
**Proposed State:** Coder WebIDE + Azure AD + Zero Trust Architecture

---

## 1. Current Security Architecture Assessment

### 1.1 Current Components

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        CURRENT CONTRACTOR ACCESS                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                  │
│  │  Contractor  │    │    Cisco     │    │   Azure      │                  │
│  │    Device    │───▶│  AnyConnect  │───▶│    VDI       │                  │
│  │  (Untrusted) │    │    (VPN)     │    │  (Windows)   │                  │
│  └──────────────┘    └──────────────┘    └──────────────┘                  │
│         │                   │                   │                           │
│         │                   │                   ▼                           │
│         │            ┌──────────────┐    ┌──────────────┐                  │
│         └───────────▶│   Azure AD   │    │   Firewall   │                  │
│           SSO + MFA  │   (IdP)      │    │   Rules      │                  │
│                      └──────────────┘    └──────────────┘                  │
│                                                │                           │
│                                                ▼                           │
│                                    ┌────────────────────┐                  │
│                                    │  On-Prem Resources │                  │
│                                    │  - Databases       │                  │
│                                    │  - Git Servers     │                  │
│                                    │  - Build Systems   │                  │
│                                    └────────────────────┘                  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Current Security Controls

| Layer | Control | Implementation | Effectiveness |
|-------|---------|----------------|---------------|
| **Identity** | SSO | Azure AD | ✅ Strong |
| **Identity** | MFA | Azure AD MFA | ✅ Strong |
| **Network** | VPN | Cisco AnyConnect | ⚠️ Moderate |
| **Endpoint** | Virtual Desktop | Azure VDI | ✅ Strong |
| **Network** | Segmentation | VDI Firewall | ✅ Strong |
| **Data** | DLP | VDI-level controls | ⚠️ Moderate |
| **Audit** | Logging | Varies by system | ⚠️ Fragmented |

### 1.3 Current Architecture Strengths

1. **Strong Identity Foundation**
   - Azure AD provides enterprise-grade identity management
   - MFA significantly reduces credential-based attacks
   - Centralized user lifecycle management

2. **Network Isolation**
   - Cisco AnyConnect provides encrypted tunnel
   - VDI acts as bastion host
   - Firewall rules limit lateral movement

3. **Data Protection**
   - Data stays within VDI environment
   - No direct data transfer to contractor devices
   - Controlled clipboard/file transfer

### 1.4 Current Architecture Weaknesses

| Issue | Impact | Risk Level |
|-------|--------|------------|
| **VPN Attack Surface** | VPN concentrators are high-value targets | High |
| **VDI Resource Overhead** | Full Windows desktop for dev work is expensive | Medium |
| **Slow Provisioning** | VDI setup takes hours/days | Medium |
| **Poor Developer Experience** | VDI latency affects productivity | Medium |
| **Fragmented Audit Trail** | Logs spread across VPN, VDI, apps | High |
| **Broad Network Access** | VPN grants wide network visibility | High |
| **Session Persistence** | VDI sessions can remain connected | Medium |
| **Update Management** | VDI images require maintenance | Medium |

### 1.5 Risk Assessment - Current State

| Risk Category | Current Risk | Notes |
|---------------|--------------|-------|
| Unauthorized Access | Low | MFA + VPN provides good defense |
| Lateral Movement | Medium | VDI firewall helps but VPN exposes network |
| Data Exfiltration | Medium | VDI controls exist but can be bypassed |
| Audit Compliance | Medium | Fragmented logging across systems |
| Availability | Medium | VDI/VPN outages affect all contractors |
| Cost Efficiency | High | VDI licenses + VPN infrastructure expensive |

---

## 2. Proposed Architecture: Coder WebIDE Platform

### 2.1 Proposed Components

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        PROPOSED CONTRACTOR ACCESS                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐         ┌──────────────┐                                 │
│  │  Contractor  │  HTTPS  │    Coder     │                                 │
│  │   Browser    │────────▶│   Server     │                                 │
│  │  (Any Device)│         │   (WebIDE)   │                                 │
│  └──────────────┘         └──────────────┘                                 │
│         │                        │                                          │
│         │                        ▼                                          │
│         │                 ┌──────────────┐                                 │
│         │    OIDC/SAML    │   Azure AD   │                                 │
│         └────────────────▶│   (IdP)      │                                 │
│           SSO + MFA       │              │                                 │
│                           └──────────────┘                                 │
│                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │                    ISOLATED WORKSPACE NETWORK                          │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                   │ │
│  │  │ Workspace A │  │ Workspace B │  │ Workspace C │                   │ │
│  │  │ (Container) │  │ (Container) │  │ (Container) │                   │ │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘                   │ │
│  │         │                │                │                           │ │
│  │         └────────────────┼────────────────┘                           │ │
│  │                          ▼                                            │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐ │ │
│  │  │                    SERVICE MESH / NETWORK POLICY                 │ │ │
│  │  │   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐           │ │ │
│  │  │   │   Git   │  │   DB    │  │   AI    │  │  Build  │           │ │ │
│  │  │   │ Server  │  │ (Proxy) │  │ Gateway │  │ System  │           │ │ │
│  │  │   └─────────┘  └─────────┘  └─────────┘  └─────────┘           │ │ │
│  │  └─────────────────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Coder Authorization Capabilities

Coder provides built-in RBAC and integrates with enterprise identity providers:

| Capability | Coder Feature | Azure AD Integration |
|------------|---------------|---------------------|
| **Authentication** | OIDC/SAML | ✅ Native support |
| **MFA** | Delegated to IdP | ✅ Azure AD MFA |
| **User Provisioning** | SCIM (Enterprise) | ✅ Auto-provisioning |
| **Role-Based Access** | Built-in RBAC | Groups → Roles mapping |
| **Template Access** | Template ACLs | Group-based permissions |
| **Resource Quotas** | Per-user/group limits | Enforceable |
| **Session Management** | Configurable timeouts | Policy-driven |

#### Coder RBAC Model

```
┌─────────────────────────────────────────────────────────────────┐
│                      CODER RBAC HIERARCHY                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Organization                                                    │
│  └── Groups (synced from Azure AD)                              │
│      ├── internal-developers                                     │
│      │   └── Templates: all                                     │
│      │   └── Quotas: high                                       │
│      │                                                          │
│      ├── contractors-project-alpha                              │
│      │   └── Templates: contractor-workspace-alpha              │
│      │   └── Quotas: medium                                     │
│      │   └── Max workspaces: 1                                  │
│      │                                                          │
│      └── contractors-project-beta                               │
│          └── Templates: contractor-workspace-beta               │
│          └── Quotas: medium                                     │
│          └── Max workspaces: 1                                  │
│                                                                  │
│  Template Permissions:                                           │
│  ├── contractor-workspace-alpha                                 │
│  │   └── Git: alpha-repos only                                  │
│  │   └── DB: alpha-db (read-only)                              │
│  │   └── AI: enabled                                           │
│  │                                                              │
│  └── contractor-workspace-beta                                  │
│      └── Git: beta-repos only                                   │
│      └── DB: none                                               │
│      └── AI: disabled                                           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Security Requirements for Dev Platform

### 3.1 Authentication Requirements

| ID | Requirement | Priority | Current | Proposed |
|----|-------------|----------|---------|----------|
| AUTH-01 | SSO via Azure AD OIDC/SAML | P0 | ✅ VPN+VDI | ✅ Coder OIDC |
| AUTH-02 | MFA enforcement | P0 | ✅ Azure MFA | ✅ Azure MFA |
| AUTH-03 | Conditional Access policies | P1 | ✅ Azure CA | ✅ Azure CA |
| AUTH-04 | Session timeout (max 8 hours) | P0 | ⚠️ Manual | ✅ Configurable |
| AUTH-05 | Re-authentication for sensitive ops | P1 | ❌ No | ✅ Supported |
| AUTH-06 | Service account restrictions | P1 | ⚠️ Partial | ✅ Token scopes |

### 3.2 Authorization Requirements

| ID | Requirement | Priority | Current | Proposed |
|----|-------------|----------|---------|----------|
| AUTHZ-01 | Role-based access control | P0 | ⚠️ VDI groups | ✅ Coder RBAC |
| AUTHZ-02 | Project-based workspace isolation | P0 | ⚠️ Manual | ✅ Templates |
| AUTHZ-03 | Resource quotas per user/group | P1 | ❌ No | ✅ Built-in |
| AUTHZ-04 | Template access control | P0 | N/A | ✅ ACLs |
| AUTHZ-05 | Just-in-time access provisioning | P2 | ❌ No | ✅ SCIM |
| AUTHZ-06 | Privileged access management | P1 | ⚠️ Partial | ✅ Audit + approval |

### 3.3 Network Security Requirements

| ID | Requirement | Priority | Current | Proposed |
|----|-------------|----------|---------|----------|
| NET-01 | No VPN required | P1 | ❌ VPN required | ✅ Browser only |
| NET-02 | Zero direct network access | P0 | ⚠️ VPN exposes | ✅ No network access |
| NET-03 | Service-specific connectivity | P0 | ⚠️ Firewall rules | ✅ Service mesh |
| NET-04 | Workspace network isolation | P0 | ⚠️ VDI shared | ✅ Per-container |
| NET-05 | Egress filtering | P0 | ⚠️ Partial | ✅ Network policy |
| NET-06 | TLS 1.3 for all connections | P0 | ✅ Yes | ✅ Yes |

### 3.4 Data Protection Requirements

| ID | Requirement | Priority | Current | Proposed |
|----|-------------|----------|---------|----------|
| DATA-01 | No data on contractor device | P0 | ✅ VDI | ✅ Browser only |
| DATA-02 | Clipboard restrictions | P1 | ✅ VDI policy | ✅ Configurable |
| DATA-03 | File download prevention | P0 | ⚠️ Partial | ✅ No download |
| DATA-04 | Code stays in environment | P0 | ✅ VDI | ✅ Container |
| DATA-05 | Secrets management | P0 | ⚠️ Manual | ✅ Vault integration |
| DATA-06 | Database access via proxy only | P0 | ⚠️ Firewall | ✅ Service proxy |

### 3.5 Audit & Compliance Requirements

| ID | Requirement | Priority | Current | Proposed |
|----|-------------|----------|---------|----------|
| AUDIT-01 | Centralized audit logging | P0 | ⚠️ Fragmented | ✅ Unified |
| AUDIT-02 | Session recording | P1 | ⚠️ VDI recording | ✅ Terminal logging |
| AUDIT-03 | Git operation logging | P0 | ⚠️ Separate | ✅ Integrated |
| AUDIT-04 | AI request logging | P0 | N/A | ✅ AI Gateway |
| AUDIT-05 | Real-time alerting | P1 | ⚠️ Partial | ✅ SIEM integration |
| AUDIT-06 | Compliance reporting | P1 | ⚠️ Manual | ✅ Automated |

### 3.6 Operational Requirements

| ID | Requirement | Priority | Current | Proposed |
|----|-------------|----------|---------|----------|
| OPS-01 | Provisioning time < 5 minutes | P1 | ❌ Hours/days | ✅ < 2 minutes |
| OPS-02 | Auto-shutdown idle resources | P1 | ⚠️ Manual | ✅ Automatic |
| OPS-03 | Self-service workspace creation | P1 | ❌ IT ticket | ✅ Self-service |
| OPS-04 | Template versioning | P1 | ⚠️ VDI images | ✅ Git-based |
| OPS-05 | Disaster recovery | P0 | ✅ Azure DR | ✅ K8s DR |
| OPS-06 | High availability | P0 | ✅ Azure HA | ✅ K8s HA |

---

## 4. Security Comparison Matrix

### 4.1 Attack Surface Comparison

| Attack Vector | Current (VDI) | Proposed (Coder) | Improvement |
|---------------|---------------|------------------|-------------|
| VPN Vulnerabilities | Exposed | Eliminated | ✅ Major |
| Desktop OS Exploits | Windows VDI | Minimal container | ✅ Major |
| Credential Theft | MFA protected | MFA + short sessions | ✅ Minor |
| Lateral Movement | Firewall rules | Network policy | ✅ Major |
| Data Exfiltration | VDI controls | No file access | ✅ Major |
| Insider Threat | Limited logging | Full audit trail | ✅ Major |
| Supply Chain | VDI image | Container image | ⚠️ Similar |
| Phishing | MFA protected | MFA protected | ⚠️ Same |

### 4.2 Compliance Mapping

| Framework | Control | Current | Proposed |
|-----------|---------|---------|----------|
| **SOC 2** | Access Control | ✅ | ✅ Enhanced |
| **SOC 2** | Audit Logging | ⚠️ | ✅ Enhanced |
| **SOC 2** | Change Management | ⚠️ | ✅ Enhanced |
| **ISO 27001** | A.9 Access Control | ✅ | ✅ Enhanced |
| **ISO 27001** | A.12 Operations | ⚠️ | ✅ Enhanced |
| **NIST 800-53** | AC (Access Control) | ✅ | ✅ Enhanced |
| **NIST 800-53** | AU (Audit) | ⚠️ | ✅ Enhanced |
| **Zero Trust** | Never trust, always verify | ⚠️ | ✅ Native |

---

## 5. Implementation Phases

### Phase 1: Foundation (Weeks 1-4)
- [ ] Deploy Coder in isolated environment
- [ ] Configure Azure AD OIDC integration
- [ ] Implement MFA enforcement
- [ ] Create base workspace template
- [ ] Set up audit logging

### Phase 2: Security Hardening (Weeks 5-8)
- [ ] Implement network policies
- [ ] Configure RBAC and template ACLs
- [ ] Set up database proxy
- [ ] Deploy AI Gateway with rate limiting
- [ ] Enable session recording

### Phase 3: Integration (Weeks 9-12)
- [ ] SIEM integration for alerting
- [ ] Secrets management (Vault)
- [ ] CI/CD pipeline integration
- [ ] Compliance reporting automation
- [ ] Documentation and runbooks

### Phase 4: Pilot (Weeks 13-16)
- [ ] Onboard 5-10 pilot contractors
- [ ] Gather feedback and metrics
- [ ] Security assessment
- [ ] Performance tuning
- [ ] Incident response testing

### Phase 5: Production Rollout
- [ ] Phased migration from VDI
- [ ] Full contractor onboarding
- [ ] VDI decommissioning plan
- [ ] Ongoing monitoring and improvement

---

## 6. Risk Mitigation

### 6.1 Residual Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Coder vulnerability | Low | High | Regular patching, WAF |
| Azure AD compromise | Low | Critical | Conditional Access, PIM |
| Container escape | Very Low | High | Hardened images, seccomp |
| Insider data theft | Low | High | DLP, audit logging |
| Service availability | Low | Medium | HA deployment, DR |

### 6.2 Comparison: Risk Profile

```
                    RISK REDUCTION COMPARISON

  Risk Area              Current        Proposed
  ─────────────────────────────────────────────────
  Network Exposure       ████████░░     ██░░░░░░░░  (-60%)
  Endpoint Security      ████░░░░░░     ██░░░░░░░░  (-50%)
  Data Loss              ████████░░     ████░░░░░░  (-40%)
  Audit Gaps             ████████░░     ██░░░░░░░░  (-60%)
  Operational Cost       ████████████   ████░░░░░░  (-65%)
  Provisioning Time      ████████████   ██░░░░░░░░  (-80%)

  ░ = Lower Risk/Cost    █ = Higher Risk/Cost
```

---

## 7. Cost-Benefit Analysis

### 7.1 Current Costs (Estimated Annual)

| Component | Cost/User/Month | 100 Contractors |
|-----------|-----------------|-----------------|
| Azure VDI | $150-300 | $180,000-360,000 |
| Cisco AnyConnect | $10-20 | $12,000-24,000 |
| VDI Management | $50 | $60,000 |
| **Total** | **$210-370** | **$252,000-444,000** |

### 7.2 Proposed Costs (Estimated Annual)

| Component | Cost/User/Month | 100 Contractors |
|-----------|-----------------|-----------------|
| Coder (self-hosted) | $0 | $0 |
| Compute (containers) | $30-50 | $36,000-60,000 |
| Platform management | $30 | $36,000 |
| **Total** | **$60-80** | **$72,000-96,000** |

### 7.3 Savings

| Metric | Savings |
|--------|---------|
| Annual Cost Reduction | $180,000-348,000 (70%+) |
| Provisioning Time | Hours → Minutes |
| IT Overhead | Reduced by 60% |
| Security Incidents | Expected reduction 40%+ |

---

## 8. Recommendations

### 8.1 Primary Recommendation

**Proceed with Coder WebIDE platform** as a replacement for Azure VDI for contractor development access, with the following conditions:

1. **Maintain Azure AD as Identity Provider** - Leverage existing MFA and Conditional Access policies
2. **Implement Zero Trust Architecture** - No implicit trust, verify every request
3. **Deploy in Phases** - Start with pilot, validate security, then expand
4. **Keep VDI as Fallback** - Maintain limited VDI capacity during transition

### 8.2 Security Enhancements Over Current State

1. **Eliminate VPN Attack Surface** - Browser-only access removes VPN vulnerabilities
2. **Unified Audit Trail** - Single source of truth for all contractor activity
3. **Granular Access Control** - Project-specific templates vs broad VDI access
4. **Faster Incident Response** - Workspace termination in seconds vs VDI cleanup

### 8.3 Prerequisites for Production

1. Azure AD OIDC configuration completed
2. Network policies tested and validated
3. Audit logging integrated with SIEM
4. Incident response playbooks documented
5. Security assessment by internal team

---

## 9. Appendix

### A. Azure AD OIDC Configuration

```yaml
# Coder OIDC Configuration for Azure AD
CODER_OIDC_ISSUER_URL: https://login.microsoftonline.com/{tenant-id}/v2.0
CODER_OIDC_CLIENT_ID: {application-id}
CODER_OIDC_CLIENT_SECRET: {client-secret}
CODER_OIDC_SCOPES: openid,profile,email
CODER_OIDC_EMAIL_DOMAIN: company.com,contractors.company.com
CODER_OIDC_GROUP_FIELD: groups
CODER_OIDC_ALLOWED_GROUPS: contractor-developers,internal-developers
```

### B. Network Policy Example

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: contractor-workspace-policy
spec:
  podSelector:
    matchLabels:
      coder.com/workspace-owner-group: contractors
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: coder
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: gogs
        - podSelector:
            matchLabels:
              app: testdb
        - podSelector:
            matchLabels:
              app: ai-gateway
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
```

### C. Audit Log Schema

```json
{
  "timestamp": "2026-02-04T10:30:00Z",
  "event_type": "workspace.created",
  "user": {
    "id": "uuid",
    "email": "contractor@external.com",
    "groups": ["contractors-project-alpha"]
  },
  "workspace": {
    "id": "uuid",
    "name": "alpha-dev-1",
    "template": "contractor-workspace-alpha"
  },
  "source_ip": "203.0.113.50",
  "user_agent": "Mozilla/5.0...",
  "azure_ad_session": "session-id",
  "result": "success"
}
```

---

## Document Control

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-04 | Dev Platform Team | Initial draft |

## References

- [Coder Security Documentation](https://coder.com/docs/admin/security)
- [Azure AD OIDC Integration](https://coder.com/docs/admin/auth#azure-ad)
- [NIST Zero Trust Architecture](https://www.nist.gov/publications/zero-trust-architecture)
- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
