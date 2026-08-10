---
name: automated-reviewer-loop
model: fast
description: Run the automated reviewer loop (and CI loop) for a PR. Use when the user wants to run the reviewer loop on a specific PR or the current branch's PR until it is ready for human review or escalated.
---

Follow the standalone automated reviewer loop protocol:

`docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`

## Repository Mode Context

Keep reviewer-loop routing thin. In `workflow_hub`, pass selected product
repository context through to shared reviewer and CI scripts for product
implementation PRs; hub-owned spec, plan, and workflow PRs continue to target
the hub. Do not duplicate product repository selection logic in this wrapper.

That document is the single source of truth. Key responsibilities:

- Determine target PR from user input (explicit number, "current" branch, or all open workflow PRs if requested)
- Step 7a runs **two sequential passes** for implementation PRs (Pass 1: Spec Compliance, then Pass 2: Code Quality) before converting to non-draft. Spec and plan PRs remain single-pass.
- Run Step 7 (`pr-review-loop.sh`) to completion, then Step 8 (`pr-ci-loop.sh`), both in the foreground of the same turn. Never start either script in the background and end your turn to wait for it — the completion notification goes to your dispatcher, not to you, and doing so parks you permanently, indistinguishable from a dead runner (see Protocol 91 Step 7/Step 8 "run in the foreground" rule). If you must background one, poll it yourself until it returns before doing anything else. Do not pass `--platform` unless intentionally overriding: the script reads `.ai-dev-workflow.yaml` and uses `review.on_draft.github` plus `review.on_ready.github` when no `--platform` is given.
- Dispatch the matching fixer agent (spec-reviewer, implementation-plan-reviewer, or code-reviewer) when the platform reports needs_fixes, up to max_cycles
- When `BATCH_CONTEXT=true`, pass the full Protocol 90 isolation assignment to any fixer handoff: resolved absolute worktree path, expected branch, artifact repo root, approved base branch, mutation classification, and `isolation: "worktree"`.
- Apply `ready-for-human-review` / `needs-fixes` per 92-pr-readiness-signal-protocol.md. For `spec/*` and `implementation-plan/*` PRs, route through Protocol 91 Step 8a so `check-documentation-stage-alignment.sh` runs before `ready-for-human-review`.
- Track all blocking findings across cycles in an issue ledger. After each fixer push, post a fix commit comment listing resolved issues. When the loop terminates, post a final summary table on the PR using `gh pr comment`.
- Use the helper scripts in `scripts/development-workflow/`
