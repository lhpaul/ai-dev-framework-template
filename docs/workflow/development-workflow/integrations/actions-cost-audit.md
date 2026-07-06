# Integration: Actions Cost Audit

Use `scripts/development-workflow/actions-cost-audit.sh` when maintainers need a
lightweight view of recent GitHub Actions run volume before changing workflow
defaults, running retrospectives, or reviewing downstream template-sync cost
risk.

The helper uses normal repository workflow-run visibility through `gh run list`.
It does not call billing APIs, does not require billing-admin access, and does
not mutate workflow files or repository settings.

---

## Quick Start

From the repository root:

```bash
./scripts/development-workflow/actions-cost-audit.sh --limit 100
```

To inspect another repository or apply a recent timestamp cutoff:

```bash
./scripts/development-workflow/actions-cost-audit.sh \
  --repo owner/repo \
  --since 2026-07-01T00:00:00Z
```

The output is markdown so it can be pasted into a retrospective, a template-sync
review, or a follow-up issue.

---

## What The Audit Shows

The workflow summary groups recent runs by workflow and reports:

- run count;
- completed run count;
- runs excluded from duration totals because timestamp data is incomplete;
- total wall time from completed runs with usable timestamps;
- average wall time from completed runs with usable timestamps;
- dominant trigger events;
- recent run IDs or URLs for follow-up inspection.

Wall time is a comparable cost signal, not an exact billable-minute or dollar
calculation. Use GitHub billing and usage dashboards for authoritative billing
data.

---

## Public And Private Cost Framing

Public template repositories using standard GitHub-hosted runners are generally
zero-billable for Actions minutes. That does not prove the same workflow default
is safe for private downstream repositories: inherited workflows can consume
included or paid runner minutes once synchronized into a private repository.

Larger runners, self-hosted runners, artifact/cache storage, and account plan
terms can have different billing behavior. Treat this audit as a workflow-run
volume and wall-time review, then use billing dashboards when exact costs are
needed.

---

## Recommendation Outcomes

Use these outcomes in the generated worksheet:

| Outcome | Use when |
| --- | --- |
| `keep` | The workflow is high-signal: CI, reviewer gate, release gate, real regression, or real deploy value. |
| `narrow` | The workflow is valuable but runs on more events, branches, or paths than necessary. |
| `make opt-in` | The workflow is a placeholder or occasional diagnostic that should not run automatically downstream. |
| `replace` | The workflow is useful but should move to a cheaper or more targeted mechanism. |
| `disable` | The workflow no longer provides enough value to justify even low-cost automatic runs. |
| `investigate` | More data is needed before changing triggers or defaults. |

Prefer `keep` for high-signal checks even when they are visibly expensive:
required CI, reviewer readiness gates, release gates, real regression suites, and
real deployment workflows protect quality and release safety. Cost reduction
should start with low-signal fan-out, placeholder jobs, duplicated checks, broad
path triggers, or workflows that no longer gate a meaningful decision.

The consolidated `.github/workflows/pr-policy.yml` workflow is an example of a
`replace` outcome: it preserves reviewer-loop and regression-readiness policy
while replacing redundant lightweight PR policy fan-out with one API-only job.

---

## Data Limitations

The helper reports limitations directly in the output:

- runs with missing or unparseable timestamps are counted but excluded from wall
  time totals;
- `--limit` can hide older high-volume workflows;
- `--since` filters only the runs returned inside the inspected limit;
- GitHub CLI authentication or repository permissions can prevent run history
  access.

If the helper reports no data, increase `--limit`, remove `--since`, or confirm
that the current `gh` account can read Actions runs for the repository.

---

## Validation

Focused coverage lives in:

```bash
bash scripts/development-workflow/tests/test-actions-cost-audit.sh
```

The test uses a mocked `gh` command and validates aggregation, incomplete data,
empty data, permission failures, recommendation outcomes, and public/private
cost-risk framing without live network access.
