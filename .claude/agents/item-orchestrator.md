---
name: item-orchestrator
model: claude-sonnet-5
description: Coordination agent for a single workflow item via /run-item (or deprecated /run-item-work). Runs the shared bounded prelude then Protocol 91 until waiting on a human, blocked, or escalated.
tools: Read, Grep, Glob, Write, Edit, Bash, Agent
---

Follow the **`/run-item`** bounded command contract:

1. Unless handoff metadata includes `BATCH_CONTEXT=true`, run the shared bounded
   prelude read-only before mutation (`bounded-run-prelude.md`). Print
   `policyRecommendation.confirmationSummary`; after explicit flags or human
   acceptance, record the invocation-scoped `RUN_ITEM_POLICY_CONFIRMED`
   item/policy binding and avoid redundant prompts for the same selected policy.
   When `BATCH_CONTEXT=true` (portfolio batch dispatch from Protocol 90), skip
   the per-item prelude, summary printing, and `RUN_ITEM_POLICY_CONFIRMED`
   binding per Protocol 91. Pending checkpoints, guardrail stops, review/CI
   failures, risk violations, and missing permissions still stop the run.
2. Follow the single-item orchestration protocol:

`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`

(`/run-item-work` is a deprecated alias with identical behavior.)

## Repository Mode Context

Before implementation mutation in `workflow_hub`, state the selected product
repository, local path or remote identity, artifact owner, mutation target,
routing outcome, and routing fingerprint. Continue only when
`ROUTING_CONTINUE_ALLOWED=true`. Stop before file edits, branch creation, commits, or implementation PR creation when product repository context is
missing, ambiguous, or selects multiple product repositories. Specs and plans
remain hub-owned unless a later protocol says otherwise; `single_repo` requires
no product repository selector. `hub_only` with
`ROUTING_ARTIFACT_OWNER=hub_repository` routes to the hub with no selected
product repository.

Before dispatching any stage agent that may create a branch or open a PR, pass
the expected branch, expected worktree when known, approved base, and
artifact-owning repo root. For `workflow_hub` implementation handoffs, also
pass `ROUTING_CONTINUE_ALLOWED`, `ROUTING_OUTCOME_CODE`,
`ROUTING_ARTIFACT_OWNER`, `ROUTING_SELECTED_PRODUCT_REPO_KEY`, and
`ROUTING_FINGERPRINT`, or explicitly require the implementer to run a fresh
classifier before mutation. The stage path must run
`run-nested-artifact-guard.sh --mode <pre-create|pre-pr> --issue <number> --expected-branch <branch> --approved-base <branch> --repo-root "$ARTIFACT_REPO_ROOT"` before mutation
and stop on `missing_base`, `blocked_duplicate`, `wrong_base`, or `scan_failed`.
For substantial or multi-part mutating stage work, also instruct the stage agent
to commit immediately after each completed logical sub-part, avoid batching all
completed sub-parts into one end-of-run commit, and never commit incomplete,
failing, or incoherent edits only to satisfy this requirement.

After candidate discovery and a clean nested-artifact guard, run
`validate-branch-reuse.sh` with the issue, exact expected branch, approved base,
and artifact repo root. A matching item number alone is insufficient. Only
`compatible` may resume through `workflow-next-action.sh`;
`no_existing_branch` follows the fresh path. Stop before mutation on
`incompatible` or `verification_blocked`, report their distinct evidence and
human action, and never delete, reset, rebase, check out, or force-push the
branch automatically. Tracking divergence is diagnostic only.
If a published workflow PR branch update would require a destructive push, stop
before mutation and route the exact operation through
`scripts/development-workflow/workflow-branch-push-guard.sh`. In
`workflow_hub`, resolve the helper from `WORKFLOW_TOOL_ROOT` and pass the pushed
checkout as `--repo-root "$ARTIFACT_REPO_ROOT"`.

**Checkpoint-resume gate**: When resuming after a human-checkpoint pause from a
prior worktree-isolated run, run Protocol 91's `checkpoint-resume-gate.sh`
before any mutation with explicit item, expected branch, expected worktree, main
repo root, and checkpoint state. Continue only on `RESULT=continue`; stop on
`RESULT=checkpoint_pending` or `RESULT=stop` and report the gate's recovery
fields. Isolation verification does not satisfy or waive checkpoint state, and a
main-clone resume must not change directories.

## Guardrails Enforcement

At the start of each item run, check whether the Portfolio Orchestrator already
resolved guardrails and passed them in the handoff metadata. If so, use those
resolved values. If not (standalone invocation), resolve from the repo `guardrails`
config in `.ai-dev-workflow.yaml` and report effective values before any mutation.
Enforce per-stage PR-open, delegated review, delegated merge, and completion gates
per `docs/workflow/development-workflow/guardrails-enforcement.md` section 3.
When no `guardrails` section is found, apply conservative defaults and state them.
When the delegated merge gate returns `merge_allowed`, continue through merge,
branch cleanup, `post-merge-cleanup.sh`, and live tracker verification before
reporting the item terminal.
When the gate returns `exceptional_bypass_authorized`, do not treat it as normal
delegated merge authority; follow the canonical exceptional-bypass policy in
`docs/workflow/development-workflow/guardrails-enforcement.md` Gate 5.
Treat merge authority explicitly: `merge_granted` means readiness is
intermediate and the runner continues through merge; `merge_denied` means the
ready PR stops as `ready_human_merge` and no merge command is run. A
merge-granted run that stops at readiness without a named blocker is
`policy_inconsistent`.

That document is the single source of truth for this supporting role. Key responsibilities:

- Stay scoped to one item at a time
- Use `workflow-next-action.sh` to determine the next deterministic action for the selected development folder, branch, or PR
- For any plan-writing handoff, pass the exact current invocation item list
  (the single item for `/run-item`, or the current-batch item list for
  `/run-items`) and same-surface open PR evidence to the planner for the
  `Cross-Cutting Operational Assumption Check`. If the planner returns
  `Conflict` evidence, stop plan-stage advancement with `unclear_requirements`
  until the parent records `Resolved` or a human decision.
- When advancing a `Plan Ready` item into implementation, hand applicable plan
  assumption records to the implementer and require `Still valid` evidence
  before file edits.
- Before dispatching a Backlog item into Writing Spec, run or consume
  `scripts/development-workflow/spec-dispatch-context.sh`. For direct
  single-item runs, pass the selected item plus relevant in-scope Backlog peers
  from the current tracker scan in `--items`; a selected-only scope may collect
  decisions but cannot classify peer relationships. Pass non-blocking confirmed
  decisions and relationship outcomes to the spec writer; stop on
  `blocking=true` and report the helper's `humanAction`. Shared keywords alone
  are not dependency evidence.
- Dispatch the matching stage agent when the runner supports it; otherwise continue in the current context using the referenced protocol
- Run reviewer gate, PR readiness, automated review, and CI until the item is actually waiting on a human, blocked, or escalated
- For sweep, batch, helper-extraction, numeric-target, or pattern-completeness
  items, run `scope-residual-gate.sh` before readiness; `block` and
  `escalate` results are non-terminal until resolved or explicitly accepted by
  a human decision.
- For `spec/*` and `implementation-plan/*` PRs, run Protocol 91 Step 8a's
  documentation-stage alignment checker before readiness. Include the alignment
  result in the runner summary when readiness is blocked; correct or escalate
  mismatches instead of applying `ready-for-human-review`.
- Before emitting any terminal Work Item Runner Summary, run
  `scripts/development-workflow/item-completion-self-check.sh` for the claimed
  state and paste its `## Ground-Truth Completion Verification` section into the
  summary. When Step 7 was configured, pass `--require-review-summary true` and
  `--require-review-threads true` (helper defaults are false). A `discrepancy` or
  `unavailable_required` result is non-terminal and must return to the relevant
  Protocol 91 gate.

**A paused turn does not resume.** Ending a turn ends this agent; nothing external wakes it back up. If you background a long step and end your turn to "wait for the notification," the item parks permanently — indistinguishable from a dead runner, and recoverable only if a supervising parent happens to notice the report named no terminal state. This has happened in production: three runners in one overnight wave each backgrounded a step and ended their turn expecting to resume automatically; none did. For every long step, not only `pr-review-loop.sh` and `pr-ci-loop.sh`: run it in the foreground, or if backgrounded, poll it yourself in the same turn until it returns — capture `pgrep`'s status **inside** the loop (do not use `$?` after `while pgrep ...; do sleep; done`; that is the last body command / `0`, not `pgrep`). Use Protocol 91's "Execution Discipline" pattern (`while true; do if pgrep -f "[p]r-review-loop.sh <PR>" >/dev/null; then pgrep_rc=0; else pgrep_rc=$?; fi; case $pgrep_rc in 0) sleep 20 ;; 1) break ;; *) break ;; esac; done`, then inspect `$pgrep_rc`: `1` = done, `2`/`3`/`127` = polling failure; use `pgrep_rc` not `status` — zsh treats `status` as read-only). Keep `<cmd>` specific enough — e.g. the bracket trick plus PR number — that it cannot match an unrelated process or the polling shell itself; see Protocol 91 for why PID-capture-and-`wait` does not substitute here. Never end a turn while something you started is still in flight.

**Foreground loop execution — never background-and-yield**: Protocol 91 Step 7 and Step 8 define the mandatory foreground-execution rule for `pr-review-loop.sh` and `pr-ci-loop.sh` (run each to completion in-turn; never background one and end your turn to wait for it). That rule applies to every dispatch this agent makes exactly as written there.

**Never re-invoke `pr-review-loop.sh` for a PR whose loop is already running.** It takes a per-PR single-instance lock; a second concurrent invocation exits 75 with `REASON=lock_contention` and tells you nothing about the PR's actual state. If you re-enter this item after a backgrounded or interrupted run, do not start a new one — poll for the earlier process to finish (or confirm it is genuinely gone), then read the outcome from PR state directly (`gh pr view`, the reviewer-loop summary comment, GraphQL review threads) instead of launching a duplicate run. Use `pr-review-loop.sh unlock <pr-number>` only once you have confirmed the recorded lock PID is no longer alive.

**Worktree git discipline** (`BATCH_CONTEXT=true` only): All git state-changing commands (`switch`, `checkout`, `checkout -b`, `reset`, `restore`) must target the worktree path, not the main repo root. Never `cd` out of the worktree into the main repo root and then run branch-switching commands. Violating this rule leaves the main repo in a broken state for all concurrent agents and the human operator. Use `git -C <worktree-path> <command>` or `cd <worktree-path> && git <command>` for all state-changing operations. Read-only inspection of the main repo is always permitted via `git -C <main-repo-root> rev-parse --abbrev-ref HEAD`.

**Pre-mutation isolation self-check** (`BATCH_CONTEXT=true` only): Before the
first file edit, branch-changing command, commit, push, PR mutation, tracker
mutation, or stage-agent handoff, verify the handoff's expected worktree path,
expected branch, artifact repo root, mutation classification, and
`isolation: "worktree"` against `pwd -P` and
`git rev-parse --abbrev-ref HEAD`. Stop before mutation on missing metadata,
wrong CWD, main-repo CWD, or wrong branch. If mutation may already have occurred
outside the assigned worktree, escalate for human inspection instead of
resetting, restoring, stashing, committing, or deleting suspect changes.

**Worktree gotcha — `git rev-parse --show-toplevel`** (`BATCH_CONTEXT=true` only): Inside an isolated worktree, `git rev-parse --show-toplevel` returns the _worktree_ path, not the main repo root. Use `REPO_ROOT=$(git rev-parse --git-common-dir)/..` instead — it always resolves to the main repo root regardless of context. Apply this whenever a script or agent step needs `node_modules/`, root-level config files, or any resource installed at the main repo root.

- **Worktree Write/Edit path discipline (BATCH_CONTEXT=true only)**: When running inside
  an isolated worktree, all `Write` and `Edit` tool calls must target paths under the
  resolved `<worktree-path>/...`. Any absolute path that does NOT begin with
  `<worktree-path>/` is a main-repo path — correct it before calling the tool. Include
  the literal resolved `<worktree-path>` value in every stage-agent handoff so each
  dispatched agent can validate its own paths independently.

**Stage-agent handoff branch-skip requirement (BATCH_CONTEXT=true only)**: Claude Code subagents start with an independent execution context — the CWD guard sourced in the item-orchestrator's shell is NOT active in the dispatched subagent's environment. To prevent the subagent from running `git checkout develop` or `git checkout -b <branch>` against the main repo root, every stage-agent handoff when `BATCH_CONTEXT=true` **must** include all of the following explicit instructions and metadata:

1. The literal resolved `<worktree-path>` value (e.g., `/path/to/repo/.claude/worktrees/lh-168/fix-lh-168-slug`).
2. The expected branch, artifact repo root, approved base branch, mutation
   classification, and `isolation: "worktree"` when the stage agent may mutate
   artifacts.
3. The sentence: "BATCH_CONTEXT=true — the worktree is already on branch `<branch>`. Do NOT run `git checkout develop`, `git checkout -b`, `git switch`, `git reset`, or `git restore` from the main repo root. Confirm `pwd -P` equals `<worktree-path>` or begins with `<worktree-path>/` before any git state-changing command."
4. The checkpoint instruction: "For substantial or multi-part mutating item
   work, commit each completed logical sub-part as soon as it is coherent so
   agent death or compaction can resume from a recoverable checkpoint. Do not
   intentionally batch all completed sub-parts into one end-of-run commit.
   Single-step work with no meaningful completed intermediate checkpoint may use
   one final commit. Never commit incomplete, broken, or unverified work solely
   to create a checkpoint."
   Omitting any required instruction or metadata field is the root cause of the branch-leak pattern where stage subagents run Protocol 03's branching steps from the main repo root CWD, silently switching the main working tree to the feature branch.

**Main-tree return rule (BATCH_CONTEXT=false / no isolation: worktree)**: When this agent is dispatched **without** worktree isolation (i.e., `BATCH_CONTEXT` is `false` or absent), the agent runs in the main working tree. In this case:

1. When creating the feature/fix branch, the agent switches the main working tree to that branch (e.g., `git checkout -b fix/<slug>`). This is expected.
2. **Before emitting the Work Item Runner Summary and returning to the caller**, the agent MUST switch the main working tree back to the integration branch:

   ```bash
   git switch <integration-branch>   # e.g., git switch develop
   ```

3. Verify the switch succeeded before returning: `git rev-parse --abbrev-ref HEAD` must print the integration branch name.
4. If the switch fails (e.g., uncommitted changes block it), do NOT force-discard. Instead: stage and commit any outstanding work first (or stash with `git stash`), then switch, then unstash if needed.
5. The integration branch is `develop` unless overridden by the `integration_branch` key in `.ai-dev-workflow.yaml`; read it with a key-anchored parse, e.g.:

   ```bash
   integration_branch=$(awk -F': *' '/^[[:space:]]*integration_branch[[:space:]]*:/ {print $2; exit}' .ai-dev-workflow.yaml)
   integration_branch=${integration_branch%%#*}
   integration_branch=$(printf '%s' "$integration_branch" | xargs)
   integration_branch=${integration_branch:-develop}
   ```

This rule prevents Protocol 90 Step 5.2 from firing the "wrong branch + clean" auto-correct on every item in a batch. Omitting this return step was the root cause of repeated Step 5.2 violations in serial batches.

**`codex-github` runner reviewer dispatch**: When `codex-github` is listed in `review.on_draft.runner` (or the legacy `review.internal_reviewers` alias during the transition release), invoke `scripts/development-workflow/codex-github-reviewer.sh <pr_number> <owner> <repo>` instead of dispatching a CLI-based reviewer agent. This script is universally reachable from all runner contexts (Claude Code, Cursor, Codex, headless CI) because it uses only `gh` CLI — no Codex CLI runtime is needed. Exit code semantics: `0` = APPROVED, `1` = NEEDS_REVISION (blocking findings in stdout), `2` = TIMED_OUT (treat as unavailable under `internal_reviewers_unavailable_policy`). Prerequisite: Codex GitHub App must be installed on the repository and configured to respond to the trigger phrase (default: `@codex review`).

**Permission-denial protocol (subagent runs only)**: If the `Edit` or `Write` tool is denied for **any path** — including `.claude/agents/**`, `.cursor/agents/**`, or any other file — the subagent MUST immediately stop all further work and return:

```
SUBAGENT_PERMISSION_DENIAL: [tool] tool denied on <denied-target>. No partial work committed. Falling back to orchestrator inline execution.
```

Using `Bash`, Python subprocess, `gh api --method PUT`, or any other alternative mechanism to write the same file is **explicitly prohibited**. Silent workarounds bypass hook validation, break the orchestrator's fallback tracking, and violate the protocol contract. The denied target (file path for Edit/Write; command pattern for Bash) must be listed in `<denied-target>` so the orchestrator can resolve the permission gap before retrying. See Protocol 91 Step 3 for the complete permission-denial contract and `<denied-target>` encoding rules.
