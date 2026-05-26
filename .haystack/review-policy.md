# Review Policies

## Reviewer and workflow automation scripts
- **Paths**: `scripts/development-workflow/**/*.sh`
- **Severity**: critical
- **Reason**: These scripts drive gating, merge, labeling, and escalation decisions; subtle logic or error-handling mistakes can silently misclassify PR readiness or perform unsafe repository actions.

## GitHub workflows security and triggering
- **Paths**: `.github/workflows/**`
- **Severity**: critical
- **Reason**: Trigger, permission, concurrency, and fork-guard changes can weaken security posture or disable required automation despite passing syntax checks.

## Protocols and agent guidance contracts
- **Paths**: `docs/workflow/development-workflow/protocols/**`, `docs/workflow/development-workflow/templates/**`, `REVIEW.md`, `AGENTS.md`, `.ai-dev-workflow.yaml`, `.pr_agent.toml`
- **Severity**: high
- **Reason**: These files define operational contracts for humans and automation; subtle wording or ordering changes can cause systematic mis-execution not caught by linting.

## Agent surface command and skill files
- **Paths**: `.claude/**`, `.cursor/**`, `.codex/**`
- **Severity**: medium
- **Reason**: Edits on only one surface can create inconsistent agent behavior and broken cross-tool expectations that automated checks may not detect end-to-end.

## Tracker and review routing configuration
- **Paths**: `.coderabbit.yaml`, `sync-manifest.yaml`
- **Severity**: high
- **Reason**: Configuration changes can silently alter reviewer coverage, routing, or sync behavior, causing skipped checks or incorrect automation decisions.

## Changelog and release parsing logic
- **Paths**: `CHANGELOG.md`, `scripts/lint/check-changelog-duplicate-headers.sh`
- **Severity**: high
- **Reason**: Release/tag automation depends on strict changelog structure; malformed sections can produce incorrect versioning or failed release flows.

## Instructions
- If a change alters fail-open vs fail-closed behavior for review, thread, or CI gates, a human must judge whether the reliability-versus-safety tradeoff is acceptable.
- If retry counts, polling intervals, or timeout budgets change in automation loops, a human must confirm the new timing preserves reliability without masking failures.
- If workflow/protocol step order changes, a human must verify invariants and downstream assumptions still hold.
- If handling of transient API/network failures is changed (degrade, retry, escalate, or continue), a human must assess false-clean and operational risk.
- If lock, cleanup, reset, restore, unlock, or branch-deletion behavior changes, a human must validate safeguards against data loss.
- If template/config field semantics used by downstream consumers change, a human must evaluate backward compatibility and migration impact.
- If non-blocking findings are dismissed as false positive or out-of-scope, a human must verify the rationale and tracking are sufficient.
- If reviewer coverage is reduced due to unavailability or environment constraints, a human must decide whether to proceed or require rerun in a fully reachable environment.
- If a rerun is skipped because a fix is classified as trivial, a human must confirm the change is truly non-structural and does not alter control flow or protocol meaning.
- If bot retrigger conditions across commits are changed, a human must assess the tradeoff between review completeness, CI churn, and operator load.
