# Protocol: Automated Reviewer Loop (Standalone)

**Agent role**: Runner of the automated reviewer loop
**Purpose**: Run the automated reviewer loop and CI loop for one or more PRs until each PR is clean and ready for human review, or escalate to human

This protocol is **standalone**: it can be invoked for any open PR (or set of PRs) without running full orchestration. It implements the same Step 7 and Step 8 logic as `90-orchestrate-work-protocol.md`, so it is suitable for "run the reviewer loop on this PR" or "run the reviewer loop on all my open workflow PRs."

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

Execute **Step 7: Automated Reviewer Loop** and **Step 8: CI Loop** exactly as defined in `90-orchestrate-work-protocol.md`. Summary below; the orchestrator protocol is the source of truth for result interpretation, fixer mapping, and parameters.

### Step 7: Automated Reviewer Loop

If an automated code review platform is configured (see `integrations/pr-review-platform.md`), run the loop. If not configured, skip and report `⏭️ skipped` for this PR, then continue to Step 8.

- Initialize `cycle = 0` for this PR at the start of this run. Increment `cycle` each time you dispatch a fixer for this PR. Do not reset `cycle` after a fixer push.
- Run to completion before proceeding to Step 8 (do not run Step 7 in the background).

**Script:**

```bash
./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch <branch_name>
```

**Interpret result** (see 90-orchestrate-work-protocol.md for full table):

| Result | Action |
|---|---|
| `clean` | Continue to Step 8 |
| `skipped` | Continue to Step 8 |
| `needs_fixes` and `cycle < max_cycles` | Increment `cycle`, dispatch the matching fixer agent (see table in 90), wait for push, then run Step 7 again |
| `needs_fixes` and `cycle >= max_cycles` | Escalate to human; report and stop for this PR |
| `escalate` | Escalate to human; report and stop for this PR |

**Fixer by branch prefix** (from 90): `spec/*` → spec-reviewer; `implementation-plan/*` → implementation-plan-reviewer; `feature/*` / `fix/*` / `hotfix/*` → code-reviewer.

**Parameters** (from 90): `poll_interval` 2 min, `max_wait` 20 min per cycle, `max_cycles` 3.

### Step 8: CI Loop

Only after Step 7 has completed with `clean` or `skipped` for this PR:

**Script:**

```bash
./scripts/development-workflow/pr-ci-loop.sh <pr_number>
```

**Interpret result** (see 90):

| Result | Action |
|---|---|
| `green` | Apply `agent:ready-for-review`, remove `agent:needs-fixes` if present; report PR ready for human review |
| `red` | Apply `agent:needs-fixes`, dispatch the matching fixer agent, wait for push, then **return to Step 7** for this PR |
| `timeout` | Escalate to human; do not apply `agent:ready-for-review` |

Labels are defined in `91-pr-readiness-signal-protocol.md`.

---

## Summary to the user

After processing the requested PR(s), report:

- **Ready for human review**: PR link, branch, and that automated review and CI are clean (or review skipped).
- **Escalated**: PR link, reason (max cycles, timeout, or review platform escalate).
- **Skipped**: If no review platform is configured, note that automated review was skipped for the listed PR(s).
