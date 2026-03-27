# Protocol: Automated Reviewer Loop (Standalone)

**Agent role**: Runner of the automated reviewer loop
**Purpose**: Run the automated reviewer loop and CI loop for one or more PRs until each PR is clean and ready for human review, or escalate to human

This protocol is **standalone**: it can be invoked for any open PR (or set of PRs) without full orchestration. It reuses **Step 7** and **Step 8** of `90-orchestrate-work-protocol.md` as-is; this document only adds how to choose the target PR(s) and how to report.

---

## When to use

- A human asks to run the automated reviewer loop on a specific PR or on the current branch's PR
- You want to advance one or more open PRs through automated review and CI without running full workflow discovery
- After pushing fixes to a PR, to re-run the loop until clean or escalate

---

## Scope: which PR(s)

Determine the target PR(s) in this order:

1. **Explicit PR number** — from the command or user message (e.g. "run reviewer loop on PR 42")
2. **Current branch** — if the user said "current" or "this PR" or did not specify: resolve the PR for the current branch, e.g. `gh pr view --json number --jq '.number'` from the repo root (or equivalent)
3. **Multiple PRs** — only if the user explicitly asked for "all open workflow PRs" or similar; then discover open PRs (e.g. branches `spec/*`, `implementation-plan/*`, `feature/*`, `fix/*`, `hotfix/*`) and run the loop for each, one at a time unless the tool supports parallel runs

If no PR can be determined, ask the user to specify a PR number or to run from a branch that has an open PR.

---

## Procedure (per PR)

### Pre-flight: check for existing unresolved review findings

Before running any scripts, inspect the PR's current review state:

```bash
gh pr view <number> --json reviews
gh api repos/{owner}/{repo}/pulls/<number>/comments
```

For each configured review platform (listed in `.ai-dev-workflow.yaml` under `review_platforms`), check whether the platform has already posted a review with blocking findings that have **not** been addressed in a commit pushed after that review. This situation arises when a platform posts its review after a previous run timed out and the agent moved on.

If unresolved findings exist: dispatch a fixer agent, wait for the push, then proceed to the scripts. Do not re-trigger the reviewer loop against stale findings — fix first.

### Run the loops

Execute **Step 7a: Claude Code Review**, **Step 7: Automated Reviewer Loop**, and **Step 8: CI Loop** exactly as defined in `90-orchestrate-work-protocol.md` (scripts, result interpretation, sequential platform policy, fixer mapping, parameters, and labels). Do not duplicate that logic here — follow 90.

For each PR: run Step 7a first (Claude code review), then Step 7 to completion, then Step 8. Dispatch fixers and re-run as specified in 90 until the PR is clean and ready for human review or escalated. After Step 8 returns `green`, run `gh pr ready <pr_number>` before applying `agent:ready-for-review`.

### PR feedback tracking and comments

Follow the "PR feedback tracking and comments" subsection of Step 7 in `90-orchestrate-work-protocol.md`:

- Maintain a PR feedback ledger tracking all blocking findings across cycles (keyed by `(platform, path, body_snippet)`).
- After each fixer push, post a **fix commit comment** on the PR listing which findings that commit resolved and any remaining open findings.
- When the loop terminates, post a **final summary table** on the PR with all findings and their statuses (`resolved` / `unresolved`).
- If the result is `skipped` (no platforms configured), do not post a summary comment.

---

## Summary to the user

After processing the requested PR(s), report:

- **Ready for human review**: PR link, branch, and that Claude code review, every configured automated reviewer, and CI are all clean (or skipped). Confirm that `gh pr ready` was run to convert the draft PR to ready.
- **Escalated**: PR link, reason (max cycles, timeout, or review platform escalate).
- **Skipped**: If no review platform is configured, or a configured platform is currently unsupported and therefore skipped, note that in the result for the listed PR(s).

The final summary comment posted on the PR (per the PR feedback tracking subsection) serves as the durable record; the summary to the user is a concise pointer to the PR and its outcome.
