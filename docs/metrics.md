**Why not just track "lines of code"?** Lines of code is a notoriously poor productivity metric — a contractor who deletes 500 lines of dead code is adding more value than one who writes 500 lines of boilerplate. The metrics below focus on output signals (commits, PRs, builds) and engagement signals (session time, AI usage patterns) rather than raw volume.
  
**Privacy-first design matters here.** 
Measure utilization, not surveillance.

  Tier 1: Available Today (just read existing data)
  ┌────────────┬────────────────────────────────┬────────────────────────────┐
  │  Category  │             Metric             │           Signal           │
  ├────────────┼────────────────────────────────┼────────────────────────────┤
  │ Engagement │ Daily workspace uptime         │ Is the contractor working? │
  ├────────────┼────────────────────────────────┼────────────────────────────┤
  │ Engagement │ AI requests/day                │ Are they actively coding?  │
  ├────────────┼────────────────────────────────┼────────────────────────────┤
  │ Cost       │ AI spend vs budget             │ Budget utilization         │
  ├────────────┼────────────────────────────────┼────────────────────────────┤
  │ Compliance │ Enforcement level + violations │ Following design-first?    │
  └────────────┴────────────────────────────────┴────────────────────────────┘
  Tier 2: Quick Wins (add Gitea polling to Platform Admin)
  ┌───────────────┬────────────────────┬──────────────────────┐
  │   Category    │       Metric       │        Signal        │
  ├───────────────┼────────────────────┼──────────────────────┤
  │ Output        │ Commits/day        │ Code production rate │
  ├───────────────┼────────────────────┼──────────────────────┤
  │ Output        │ PRs opened/merged  │ Feature completion   │
  ├───────────────┼────────────────────┼──────────────────────┤
  │ Quality       │ Build pass rate    │ Code quality         │
  ├───────────────┼────────────────────┼──────────────────────┤
  │ Collaboration │ PR review activity │ Team participation   │
  └───────────────┴────────────────────┴──────────────────────┘
  Tier 3: Advanced (new development needed)
  ┌────────────────────┬─────────────────────────┬──────────────────────────────┐
  │      Category      │         Metric          │            Signal            │
  ├────────────────────┼─────────────────────────┼──────────────────────────────┤
  │ Efficiency         │ AI tokens per commit    │ AI leverage efficiency       │
  ├────────────────────┼─────────────────────────┼──────────────────────────────┤
  │ Patterns           │ Work hour distribution  │ Schedule consistency         │
  ├────────────────────┼─────────────────────────┼──────────────────────────────┤
  │ Trends             │ Week-over-week velocity │ Ramp-up / productivity trend │
  ├────────────────────┼─────────────────────────┼──────────────────────────────┤
  │ Cost-effectiveness │ AI cost per merged PR   │ ROI on AI tooling            │
  └────────────────────┴─────────────────────────┴──────────────────────────────┘

  Coder audit log integration — add workspace session duration calculation from start/stop events (already available via /api/v2/audit).
  All the data sources exist and are accessible via APIs your platform-admin service already talks to. The main work is aggregation and presentation.

## Visibility & Access Control

Metrics are scoped by role using Authentik OIDC groups. The Platform Admin dashboard enforces this at every level — list pages, detail pages, and API endpoints.

### Authentik Group Requirements

| Group | Role | Visibility |
|-------|------|------------|
| `coder-admins` / `platform-admins` | Platform Admin | All users, all metrics, all pages |
| `coder-template-admins` | App Manager | Only users in shared `team-*` groups |
| *(none of the above)* | Contractor | Self-view only (own detail page) |

### Team Scoping via `team-*` Groups

App managers see only the contractors in their team. This is enforced by Authentik `team-*` groups:

```
team-appmanager
  ├── appmanager       (manager — coder-template-admins)
  ├── contractor1      (member — coder-members)
  └── contractor2      (member — coder-members)
```

When appmanager logs in, the Activity page and User Detail page filter to contractor1 and contractor2 only. contractor3 (in a different team or no team) is not visible.

### OIDC Configuration (3 layers must align)

1. **Authentik groups**: User must be a member of the relevant groups
2. **OIDC scope mapping**: The `groups` scope mapping must be assigned to the Platform Admin OIDC provider (scope name: `groups`, expression: `return [group.name for group in request.user.ak_groups.all()]`)
3. **Flask OIDC client**: Must request `scope: openid profile email groups`

If any layer is missing, groups will be empty in the session and role-based access silently falls back to the most restrictive level.

### `AUTHENTIK_API_TOKEN`

Team group membership lookups require a runtime API call to Authentik. The `AUTHENTIK_API_TOKEN` in `.env` must be set (created by `scripts/setup-authentik-rbac.sh`). Without it, team scoping is unavailable and template-admins get full access as a fallback.

### Pages Affected

| Page | Route | Scoping |
|------|-------|---------|
| Activity | `/activity` | Admin/template-admin only; team-filtered list |
| User Detail | `/users/<username>` | Admin sees all; template-admin sees team; others see self |
| Users | `/users` | All authenticated users (list only, no sensitive data) |
| AI Usage | `/ai-usage` | All authenticated users (aggregate data) |