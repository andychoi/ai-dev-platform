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