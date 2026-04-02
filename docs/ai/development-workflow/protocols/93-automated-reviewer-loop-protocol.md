# Protocol: Automated Reviewer Loop (Standalone)

**Agent role**: Runner of the automated reviewer loop
**Purpose**: Run the automated reviewer loop and CI loop for one or more PRs until each PR is clean and ready for human review, or escalate to human

This protocol is **standalone**: it can be invoked for any open PR (or set of PRs) without full orchestration. It reuses **Step 7** and **Step 8** of `91-orchestrate-work-protocol.md` as-is; this document only adds how to choose the target PR(s) and how to report.

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
3. **Multiple PRs** — only if the user explicitly asked for "all open workflow PRs" or similar; then discover open PRs (e.g. branches `spec/*`, `implementation-plan/*`, `feature/*`, `refactor/*`, `fix/*`, `hotfix/*`) and run the loop for each, one at a time unless the tool supports parallel runs

If no PR can be determined, ask the user to specify a PR number or to run from a branch that has an open PR.

---

## Procedure (per PR)

### Pre-flight: check for existing unresolved review findings

Before running any scripts, inspect the PR's current review state:

```bash
gh pr view <number> --json reviews
gh api repos/{owner}/{repo}/pulls/<number>/comments
```

#### Blocking classification (Devin)

Treat GitHub `COMMENTED` reviews from Devin (`devin-ai-integration`) whose body starts with `**Devin Review**` as **blocking**, the same as `CHANGES_REQUESTED`. Do not treat a `COMMENTED` Devin review as non-blocking just because the state is not `CHANGES_REQUESTED`.

#### What counts as an unresolved finding

A **blocking** inline comment or review from a configured platform (see `.ai-dev-workflow.yaml` under `review.platforms`) counts as **unresolved** when:

1. It applies to **any commit in this PR's history** (not only commits after the current `HEAD`). After merging the base branch (e.g. `develop`) into the PR branch, older bot comments are still open unless the **substantive issue** they describe is fixed in the codebase. A merge commit does not dismiss them.
2. There is no later resolved confirmation **for that same finding** (match by `(platform, path, body_snippet)` or Devin's inline comment id in the body, not by "most recent comment on the PR"). A resolved comment from Devin about *one* issue does not resolve a different blocking finding. Devin's resolved comments start with `✅` and must be excluded from blocking counts.

#### Merge / rebase trap

Do not assume the latest bot comment is the only active issue. A fixer may address a doc-only or secondary item while leaving an earlier code bug untouched. After each fixer push, verify the change fixes the **substantive problem** described in each open finding (e.g. the referenced file and behavior), not only a stale reference or a single resolved thread.

#### Stale review after timeout

Also handle the case where a platform posted blocking findings after a previous run timed out and the agent moved on: if those findings are still unresolved per the rules above, dispatch a fixer, wait for the push, then run the scripts.

If unresolved findings exist: dispatch a fixer agent, wait for the push, then proceed to the scripts. Do not re-trigger the reviewer loop against stale findings — fix first.

### Run the loops

Execute **Step 7a: Internal Review Gate**, **Step 7: Automated Reviewer Loop**, and **Step 8: CI Loop** exactly as defined in `91-orchestrate-work-protocol.md` (scripts, result interpretation, sequential platform policy, fixer mapping, parameters, and labels). Do not duplicate that logic here — follow 91.

For each PR: run Step 7a first (the stage-appropriate internal review gate). Once Step 7a produces `APPROVED`, run `gh pr ready <pr_number>` to convert the draft PR to non-draft, then run Step 7 to completion, then Step 8. Dispatch fixers and re-run as specified in 91 until the PR is clean and ready for human review or escalated. After Step 8 returns `green`, apply `ready-for-human-review` (the PR is already non-draft from the step after 7a).

### PR feedback tracking and comments

Follow the "PR feedback tracking and comments" subsection of Step 7 in `91-orchestrate-work-protocol.md`:

- **Ledger bootstrap:** Before starting Step 7, seed the PR feedback ledger with **all** open blocking findings visible on the PR across its full history (not only comments timestamped after the current `HEAD`). That way a fresh run does not declare clean while a code bug from an earlier commit on the branch is still open. Align with the pre-flight rules above. Note: `pr-review-loop.sh` performs a **stale findings recovery** for Devin — when Devin does not review the current HEAD (no check run), the script scans the full PR history for unresolved findings and reports `needs_fixes` with reason `stale_findings`.
- Maintain a PR feedback ledger tracking all blocking findings across cycles (keyed by `(platform, path, body_snippet)`).
- After each fixer push, post a **fix commit comment** on the PR listing which findings that commit resolved and any remaining open findings.
- When the loop terminates, post a **final summary table** on the PR with all findings and their statuses (`resolved` / `unresolved`).
- If the result is `skipped` (no platforms configured), do not post a summary comment.

---

## Summary to the user

After processing the requested PR(s), report:

- **Ready for human review**: PR link, branch, and that the internal review gate, every configured automated reviewer, and CI are all clean (or skipped). Confirm that `gh pr ready` was run (after Step 7a APPROVED, before Step 7) to convert the draft PR to non-draft.
- **Escalated**: PR link, reason (max cycles, timeout, or review platform escalate).
- **Skipped**: If no review platform is configured, or a configured platform is currently unsupported and therefore skipped, note that in the result for the listed PR(s).

The final summary comment posted on the PR (per the PR feedback tracking subsection) serves as the durable record; the summary to the user is a concise pointer to the PR and its outcome.
