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

Execute **Step 7: Automated Reviewer Loop** and **Step 8: CI Loop** exactly as defined in `90-orchestrate-work-protocol.md` (scripts, result interpretation, sequential platform policy, fixer mapping, parameters, and labels). Do not duplicate that logic here — follow 90.

For each PR, run Step 7 to completion, then Step 8; dispatch fixers and re-run as specified in 90 until the PR is clean and ready for human review or escalated.

### Issue tracking and PR comments

Follow the "Issue tracking and PR comments" subsection of Step 7 in `90-orchestrate-work-protocol.md`:

- Maintain an issue ledger tracking all blocking findings across cycles (keyed by `(platform, path, body_snippet)`).
- After each fixer push, post a **fix commit comment** on the PR listing which issues that commit resolved and any remaining open issues.
- When the loop terminates, post a **final summary table** on the PR with all issues and their statuses (`resolved` / `unresolved`).
- If the result is `skipped` (no platforms configured), do not post a summary comment.

---

## Summary to the user

After processing the requested PR(s), report:

- **Ready for human review**: PR link, branch, and that every configured automated reviewer plus CI are clean (or skipped).
- **Escalated**: PR link, reason (max cycles, timeout, or review platform escalate).
- **Skipped**: If no review platform is configured, or a configured platform is currently unsupported and therefore skipped, note that in the result for the listed PR(s).

The final summary comment posted on the PR (per the issue tracking subsection) serves as the durable record; the summary to the user is a concise pointer to the PR and its outcome.
