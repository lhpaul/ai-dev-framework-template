# Review Policies

## Workflow orchestration scripts require human review
- **Paths**: `scripts/development-workflow/**`, `scripts/**/codex-github-reviewer.sh`
- **Severity**: critical
- **Reason**: These scripts control reviewer verdicts, merge/CI gates, labels, locks, and cleanup; subtle logic errors can falsely advance unsafe PR states despite passing automated checks.

## GitHub Actions trust-boundary changes need human review
- **Paths**: `.github/workflows/**`
- **Severity**: critical
- **Reason**: Trigger, permission, fork-guard, and concurrency changes can silently alter trust boundaries or disable enforcement in ways lint/tests may not reveal.

## Protocol and agent contract docs need human review
- **Paths**: `docs/workflow/**`, `docs/protocols/**`, `docs/specs/**`, `AGENTS.md`, `REVIEW.md`, `.claude/**`, `.cursor/**`, `.codex/**`
- **Severity**: high
- **Reason**: These files define operational contracts for humans and agents; wording or sequencing drift can cause broad mis-execution even when syntax checks pass.

## Reviewer/sync configuration changes need human review
- **Paths**: `.coderabbit.yaml`, `.pr_agent.toml`, `.ai-dev-workflow.yaml`, `sync-manifest.yaml`
- **Severity**: high
- **Reason**: Configuration changes can silently disable reviewer coverage or propagate incorrect automation defaults across repositories.

## Changelog and release-coupled files need human review
- **Paths**: `CHANGELOG.md`, `.github/workflows/auto-tag-release.yml`
- **Severity**: high
- **Reason**: Structure or extraction changes can produce incorrect tags or release notes that are often only visible in production release flow.

## Instructions
- If a change removes or weakens a safety guard, fallback, unresolved-thread gate, or escalation path, a human must judge whether that risk tradeoff is intentional and acceptable.
- If automation behavior changes between blocking on failures and graceful degradation, a human must approve the availability-versus-safety tradeoff for that step.
- If reviewer-loop logic changes how aggressively it declares clean versus retries/rechecks, a human must verify the missed-signal risk is acceptable.
- If definitions of reviewer activity, blocking evidence, or clean completion are changed, a human must confirm the new semantics match policy intent.
- If workflow execution proceeds with reduced reviewer coverage due to unavailable/time-out reviewers or draft exclusions, a human must decide whether proceeding is acceptable for the PR risk.
- If label timing or branch/status transition rules change, a human must confirm lifecycle behavior still matches the intended end-to-end workflow.
- If detection/classification scope is broadened or narrowed (files, labels, signals, templates), a human must validate the false-positive/false-negative tradeoff.
- If findings are marked advisory, false-positive, accepted-risk, or deferred as out-of-scope, a human must verify the rationale is sound and operationally safe.
- If protocol/checklist wording changes, a human must confirm the revised text still reflects intended operational behavior and does not introduce contradictions.
