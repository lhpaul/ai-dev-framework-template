# Protocol: Run One Workflow Item

**Agent role**: Work Item Runner (`item-orchestrator`)
**Purpose**: Advance one workflow item, execute the next deterministic action, and keep that item moving until it reaches a real terminal condition

This is a **supporting protocol**. The Work Item Runner does not own a workflow stage, but it coordinates the stage-specific protocols for one development item at a time.

The portfolio-wide launcher is defined separately in `90-batch-orchestrate-work-protocol.md` as the **Portfolio Orchestrator** (`orchestrator`).

This protocol may be entered in either of two ways:

- A human invokes the Work Item Runner directly for one specific work item, branch, development folder, or PR
- The Portfolio Orchestrator dispatches the Work Item Runner after scanning the broader portfolio

---

## Routing From /run-work

`/run-work <single-non-epic-target>` enters this protocol after the routing
classifier (`scripts/development-workflow/run-work-router.sh`, Protocol 96)
determines the routing mode is `single_item`.

**`single_item` → `epic` upgrade** (AC5): When a single target resolves to an
epic-like issue (one with child items or native sub-issues), the router upgrades
from `single_item` to `epic` and routes to `95-run-epic-protocol.md` instead.

**Existing scope guard applies** (AC2): The hard-bounded scope guard in Step 1
already prevents out-of-scope mutations for item-specific invocations. No
additional scope narrowing is needed for the `single_item` routing case.

`/run-item-work` invoked directly (without `/run-work`) is a **compatibility/
advanced alias** that also enters this protocol. Its behavior is unchanged.

See `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`
for the full routing specification.

---

## Step 0: Load Effective Guardrails

Before any artifact-mutating action (before creating branches, opening PRs,
updating tracker status, or dispatching stage agents), the Work Item Runner
resolves and reports the **effective guardrails** for this run.

See `docs/workflow/development-workflow/guardrails-enforcement.md` for the
complete resolution rules, the config-field → run-epic-policy mapping table, the
named stop conditions, and the audit-evidence rules. This section summarizes the
in-protocol obligations only.

### Resolution

Resolve the effective guardrails by layering three sources (lowest to highest
priority):

1. Repository configuration — the `guardrails` block in `.ai-dev-workflow.yaml`.
2. Session overrides — values set earlier in the same conversation.
3. Invocation overrides — flags supplied with the current invocation (e.g.,
   `--delegate-review`, `--may-merge`, `--max-risk`).

When no `guardrails` section is present, apply the conservative defaults: mode
`manual`, no delegated merge, backlog starts confirmation-gated. See section 7
of `guardrails-enforcement.md`.

If the `guardrails` block is present but unreadable or internally contradictory,
stop immediately with the `guardrails_config_unreadable` stop condition before
any mutation. See section 6 of `guardrails-enforcement.md`.

### Report in the Work Item Runner Summary

Before taking any artifact-mutating action, state the following in the run
summary (including in dispatched-subagent handoffs when the Portfolio
Orchestrator resolves guardrails at the portfolio level and passes them down):

- Effective autonomy mode.
- Per-stage open/merge permissions (`may_open_pr`, `may_merge_pr`).
- Per-stage maximum merge risk (`max_merge_risk`).
- Backlog-start policy (`backlog_start.allow_without_confirmation`).
- Configured stop conditions.
- Audit requirements.
- Which values were changed by an invocation or session override (if any).

When the Portfolio Orchestrator resolved guardrails at the portfolio level and
passed them into this Work Item Runner handoff, the Work Item Runner inherits
those resolved guardrails rather than re-resolving them independently. Invocation
overrides supplied at the portfolio level flow through to the per-item gates
without re-prompting.

---

## Overview

The Work Item Runner:

1. Resolves the request to exactly one workflow item
2. Determines the next deterministic action for that item
3. Executes creator, review-gate, PR, CI, and automated-review work as one continuous control loop
4. Stops only when the item is truly waiting on a human, blocked, or escalated

### Bounded prelude (read-only gate)

When invoked through **`/run-item`** or the `/run-item-work` compatibility alias
with bounded scope flags, run the shared bounded prelude **before** any artifact
mutation in Step 1 or later:

```bash
./scripts/development-workflow/run-bounded-prelude.sh \
  --original-command "<invocation>" \
  <scope flags> \
  [--delegate-review ...] \
  --json
```

See [`bounded-run-prelude.md`](../bounded-run-prelude.md). If
`policyRecommendation.requiresConfirmation` is true, or guardrails cannot be
read (`guardrails_config_unreadable`), stop before mutation per
`guardrails-enforcement.md`.

### Persistent orchestration contract

A single Work Item Runner run should keep advancing the selected item until it reaches one of these **terminal conditions**:

- A PR is clean and waiting for human review / merge
- A human product or architecture decision is required
- The automated review loop or CI loop escalated after retry / timeout limits
- The item is blocked by an unmet dependency
- The request cannot be resolved to exactly one workflow item

These are **not** terminal conditions and must not stop the run:

- A creator stage finished drafting its output
- A reviewer found fixable PR feedback
- A branch was pushed and still needs a PR opened
- A PR is open but still waiting for CI or automated review to finish
- Automated review found blocking PR feedback that the matching fixer agent can address

---

## Step 1: Resolve the Target Item

When an issue tracker is configured in `.ai-dev-workflow.yaml`, **always query the tracker first** to get the item's current status before relying on VCS state. If the tracker is unavailable (API unreachable, no MCP server), **you MUST immediately warn the human** that status is being inferred from VCS and may be stale — do not silently proceed.

Prefer the helper scripts in `scripts/development-workflow/` for deterministic state inspection before falling back to ad hoc shell commands.

### Parallel batch indicator

**Check for a parallel batch context**: If this Work Item Runner was dispatched as part of a parallel batch by the Portfolio Orchestrator (`90-batch-orchestrate-work-protocol.md`), the handoff metadata will indicate `BATCH_CONTEXT=true`. Note this indicator; you will use it in Step 3 (Dispatch Strategy) to decide whether worktree isolation is required.

**CHANGELOG in parallel batches**: Each item in a parallel batch adds its own CHANGELOG entry as normal. CHANGELOG merge conflicts are resolved at merge time by the batch-merge auto-resolution (protocol 94 Step 4.3). Do not skip or consolidate CHANGELOG entries — see protocol 90 Step 3.6 for rationale.

### Explicit Item List Scope Guard

**Hard-refuse rule**: When the Work Item Runner is dispatched with an explicit item list (e.g., `ITEM_LIST=143,148,145` in handoff metadata, or a direct human invocation like `/run-item-work 143 148 145`), it **must not** take any artifact-mutating action on items outside that list. This rule applies to **all** of the following artifact mutations:

- Branch creation
- PR opening, labeling, or editing
- Tracker status updates
- Stage-agent dispatch
- CHANGELOG edits

**Detection**: An explicit item list is present when the handoff metadata or human invocation includes a bounded set of issue numbers, tracker IDs, branch names, or PR numbers. A single-item invocation targeting one specific item is self-scoping and does not require a list check beyond confirming that any encountered open PR or branch belongs to the same item.

**Out-of-scope item detection**: During Step 1 (resolve), Step 2 (determine next action), and at any point during execution, if the Work Item Runner encounters any open PR, branch, or tracker item that is **not** in the explicit list:

1. **Do not touch it** — skip all artifact mutations for that item.
2. **Log a WARNING** (do not silently skip):

   ```text
   WARNING: out-of-scope item detected — [branch/PR/issue identifier] is not in the explicit item list [<list>]. Skipping all actions for this item.
   ```

3. Include all detected out-of-scope items in the Step 6 summary under a dedicated "Out-of-Scope Items Detected (Skipped)" section.

**Corollary — no opportunistic advancement**: When an explicit list is active, the Work Item Runner must not opportunistically advance an out-of-scope item even if it appears clearly ready or related. Every such item gets the WARNING log and is skipped.

**Human override**: An explicit human instruction within the same session may expand the scope. The override must be stated explicitly. Log the override in the Step 6 summary.

Resolve the request to exactly one of the following:

1. **Backlog / tracker work item** — use when a human explicitly requests a not-yet-started item
2. **Development folder** — `docs/specs/developments/<timestamp>_<slug>`
3. **Workflow branch** — `spec/*`, `implementation-plan/*`, `feature/*`, `refactor/*`, `fix/*`, `hotfix/*`
4. **Open PR**

Use these helpers while resolving and resuming work:

```bash
./scripts/development-workflow/workflow-next-action.sh --development <path>
./scripts/development-workflow/workflow-next-action.sh --branch <branch>
./scripts/development-workflow/workflow-next-action.sh --pr <number>
```

If the request is portfolio-wide or refers to multiple items, stop using this protocol and switch to `90-batch-orchestrate-work-protocol.md`.

Important for `development folder` targets:

- `workflow-next-action.sh --development` is only reliable once the item is already `Spec Ready`, `Plan Ready`, or `In Development`.
- The script uses a VCS-level merged-PR check to distinguish `Plan Ready` (not yet started) from `Done` (branch merged and cleaned up). This is tracker-agnostic and requires only `gh`.
- The script **cannot** distinguish `Spec in Review` / `Plan in Review` from the corresponding merged state. If the target may still be waiting on a spec or plan PR merge, confirm the state via the issue tracker or by inspecting the workflow branch / PR directly before advancing.
- If `NEXT_ACTION=skip` is returned, the item is already done — do not redispatch.

When dispatching a subagent for this item, include a short "Tracker Work Item Summary" in the handoff:

- What the work item is asking for
- Any scope changes / decisions in recent comments
- Any ambiguity or conflict that still requires human confirmation

---

## Step 2: Determine the Next Deterministic Action

### What can advance now?

> **Guardrails check — backlog-start gate**: Before transitioning any Backlog
> item into Writing Spec, Writing Plan, or In Development for the first time,
> apply the backlog-start gate from `guardrails-enforcement.md` section 3 Gate 2.
> If `backlog_start.allow_without_confirmation` is not `true` in the effective
> guardrails, stop before starting the item and ask the human to confirm, naming
> the items proposed to start. Resuming an item already in progress is not a
> backlog start.

| Current state / detection                                          | Can advance if...                                                                                                                                   | Next action                                                                                                                                                                                                                                                                  |
| ------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Backlog (Feature)                                                  | Human has requested this specific item and tracker Type/brief classifies it as Feature                                                              | Set tracker status to **Writing Spec**, then run `01-generate-spec-protocol.md`                                                                                                                                                                                              |
| Backlog (Bug)                                                      | Human has requested this specific item and tracker Type/brief classifies it as Bug                                                                  | Run the cross-layer fast-track scope check below; if allowed, set tracker status to **In Development** and run `03-implement-development-protocol.md` Path 3, otherwise route to **Writing Spec**                                                                             |
| Backlog (Refactor)                                                 | Human has requested this specific item and tracker Type/brief classifies it as Refactor                                                             | Set tracker status to **Writing Plan**, then run `02-generate-implementation-plan-protocol.md` (skip spec)                                                                                                                                                                   |
| Backlog (Workflow)                                                 | Human has requested this specific item and tracker Type/brief classifies it as Workflow                                                             | Route by the brief's concrete path: full pipeline, refactor, or fast-track. If ambiguous, stop for a human decision rather than guessing.                                                                                                                                     |
| Writing Spec                                                       | Tracker **Writing Spec** — spec PR not yet human-ready                                                                                              | Continue spec branch/PR work (generate, internal review, reviewer tools, CI) until tracker moves to **Spec in Review**                                                                                                                                                       |
| Spec in Review                                                     | Tracker **Spec in Review** — spec PR ready for humans                                                                                               | Wait — human review / merge (unless addressing `needs-fixes`)                                                                                                                                                                                                                |
| Spec branch pushed, no PR yet                                      | Branch exists on local / remote / worktree; `stages.spec.may_open_pr` is `true` (default) — if `false`, do not open the PR and report the `stages.spec.may_open_pr` guardrail | Run the spec review gate via `REVIEW.md` / `01-review-spec-protocol.md`, open the PR, then finish PR readiness                                                                                                                                                               |
| Spec Ready                                                         | Spec PR is merged                                                                                                                                   | Set tracker status to **Writing Plan**, then run `02-generate-implementation-plan-protocol.md`                                                                                                                                                                               |
| Plan written locally, spec PR not yet merged                       | Plan branch exists locally or in worktree; spec PR is still open (not merged)                                                                       | **Ordering gate**: do NOT open the plan PR. Stop after the spec PR is `ready-for-human-review` and report: "spec PR is ready; plan is written and staged locally, but plan PR will not be opened until spec PR is confirmed merged." Resume in next run after spec PR merge. |
| Writing Plan                                                       | Tracker **Writing Plan** — plan PR not yet human-ready — spec PR already merged (Full Pipeline only; Refactor items are exempt — no spec PR exists) | Continue plan branch/PR work until tracker moves to **Plan in Review**                                                                                                                                                                                                       |
| Plan in Review                                                     | Tracker **Plan in Review** — plan PR ready for humans                                                                                               | Wait — human review / merge (unless addressing `needs-fixes`)                                                                                                                                                                                                                |
| Plan branch pushed, no PR yet                                      | Branch exists on local / remote / worktree; spec PR already merged (Full Pipeline only; Refactor items are exempt — no spec PR exists); `stages.plan.may_open_pr` is `true` (default) — if `false`, do not open the PR and report the `stages.plan.may_open_pr` guardrail | Run the plan review gate via `REVIEW.md` / `02-review-implementation-plan-protocol.md`, open the PR, then finish PR readiness                                                                                                                                                |
| Plan Ready                                                         | Plan PR is merged                                                                                                                                   | Set tracker status to **In Development**, then run `03-implement-development-protocol.md`                                                                                                                                                                                    |
| In Development                                                     | Tracker **In Development** — feature/fix PR not yet human-ready                                                                                     | Continue implementation branch/PR work (Step 7a, 7, 8) until tracker moves to **Development in Review**                                                                                                                                                                      |
| Development in Review                                              | Tracker **Development in Review** — feature/fix PR ready for humans                                                                                 | Wait — human review / merge (unless addressing `needs-fixes`)                                                                                                                                                                                                                |
| Dev branch pushed, no PR yet                                       | Branch exists on local / remote / worktree; `stages.implementation.may_open_pr` is `true` (default) — if `false`, do not open the PR and report the `stages.implementation.may_open_pr` guardrail | Open draft PR, run the internal review gate (Step 7a), run `gh pr ready` to convert to non-draft, then run automated reviewer loop (Step 7) and CI loop (Step 8)                                                                                                             |
| Draft PR open, internal review pending                             | PR is draft and the relevant internal review gate has not run yet or has open findings                                                              | Run the stage-specific internal review gate (Step 7a); apply fixes, push, repeat until clean. Once APPROVED, run `gh pr ready` to convert to non-draft                                                                                                                       |
| Non-draft PR open, no readiness label, external review not yet run | PR is non-draft (converted after Step 7a APPROVED), external review not yet run                                                                     | Run Step 7 (external automated reviewers) and Step 8 (CI)                                                                                                                                                                                                                    |
| PR open (non-draft), no readiness label                            | PR exists and latest push has not fully cleared                                                                                                     | Run Step 7 and Step 8 until clean or escalated                                                                                                                                                                                                                               |
| PR labeled `needs-fixes`                                           | Human or automated systems requested changes                                                                                                        | Address feedback, push, then run Step 7a, Step 7, and Step 8                                                                                                                                                                                                                 |
| PR labeled `ready-for-human-review`                                | —                                                                                                                                                   | Wait — human review / merge required                                                                                                                                                                                                                                         |

> **Integration-branch note**: When the item carries an `integration-branch:<slug>` label, the plan PR targets `develop-<slug>` instead of `develop`. The ordering gate (spec PR merged before plan PR) still applies, but to `develop-<slug>` not `develop`.

For GitHub Projects, the project **Type** field is authoritative for Backlog
route classification. Repository labels such as `workflow`, `bug`,
`enhancement`, and `type:*` are legacy classification hints only; do not rely on
them when Type is available.

> **Linear provider — deferred status reads**: When `workflow-next-action.sh`
> (or `workflow-batch-plan.sh`) returns a `TRACKER_ACTION_REQUIRED=read_status
> issue=<id>` line in place of an empty status, the item's status was deferred —
> the shell helper could not reach Linear directly. The orchestrator must supply
> the known Linear status from its pre-resolved context (fetched in Protocol 90
> Step 1a) to determine the next action for this item. Do not treat the
> `TRACKER_ACTION_REQUIRED=` line as a workflow status string; filter it out and
> substitute the orchestrator's authoritative value. See
> [Step 8b](#step-8b-update-tracker-status) for the `TRACKER_UPDATE_REQUIRED:`
> contract, which also applies to Linear status transitions that subagents cannot
> perform inline. See [`linear.md`](../integrations/linear.md) for the bridge
> pattern and full reference table.

### Cross-layer scope check (mandatory before fast-track dispatch)

**When to run**: Before classifying a backlog item as Fast Track and dispatching it to `03-implement-development-protocol.md` Path 3, run this check. It applies to any item whose tracker Type, issue metadata, or brief suggests a bug fix or simple change (i.e., not a feature requiring a spec).

**What to check**: Inspect the issue title, body, and any linked spec or plan document for concrete signals that the change spans more than one architectural layer simultaneously. Examples of multi-layer signals:

- Issue body mentions two or more of: database schema, API endpoint, UI component, data pipeline, storage, mapper, presentation layer.
- Issue body or a linked spec/plan describes coordinating changes across distinct subsystems (e.g., "update the model, the API, and the UI").
- Any linked spec or plan document covers more than one architectural layer.

**Decision rule (deterministic)**:

- **No concrete multi-layer signal found** → the item may proceed as fast-track.
- **At least one concrete multi-layer signal found** → the item must NOT be fast-tracked. Route it to the Full Pipeline (spec → plan → implement) so all layers are planned and coordinated. Update the tracker status to **Writing Spec** and dispatch `01-generate-spec-protocol.md`.

This check is deterministic: it does not rely on heuristics alone. A vague or general description is not a multi-layer signal. At least one concrete signal — where the issue or linked document text explicitly mentions two or more distinct architectural layers — is required to block fast-track.

### Pre-dispatch tracker status update (single-item path)

When the Work Item Runner is invoked **directly** (not via Protocol 90) and the item's tracker status is stale — for example, a Refactor item is still `Backlog` even though the plan is merged and implementation is about to start — the runner must update the tracker status **before** dispatching the creator agent. Use the same transition table as Protocol 90 Step 2.5:

| Next action to dispatch                                                                       | Tracker status to set |
| --------------------------------------------------------------------------------------------- | --------------------- |
| Write Spec                                                                                    | `Writing Spec`        |
| Write Plan                                                                                    | `Writing Plan`        |
| Implement (feature/fix/refactor/hotfix branch)                                                | `In Development`      |
| Resume in-progress stage (status already `Writing Spec`, `Writing Plan`, or `In Development`) | No change — skip      |

This mirrors what Protocol 90 does at the portfolio level in Step 2.5 and ensures the tracker reflects the correct in-flight state regardless of whether the item was dispatched by the Portfolio Orchestrator or invoked directly by a human.

If the tracker is unavailable, log a warning and proceed — do not block advancement.

### Stale `In Development` pre-dispatch check (AC-6, AC-7, AC-8, AC-10)

**Scope** (BR-7): This check applies **only** when the Work Item Runner was dispatched from the Portfolio Orchestrator (i.e., `BATCH_CONTEXT=true` is present in the handoff metadata). A direct human invocation of `item-orchestrator` will encounter an "In Development" status and should prompt the human for confirmation rather than automatically resetting the tracker — the human may intentionally be resuming in-progress work. When `BATCH_CONTEXT=true` is not set, skip this sub-step.

**When `BATCH_CONTEXT=true`**: If the item's tracker status is exactly `In Development` at this point in Step 2, run the following check before dispatching:

1. **Guard — skip if issue number is invalid**: Before running the branch and PR checks, verify that `ISSUE_NUMBER` is a non-empty positive integer. GitHub issue numbers are always positive integers; a non-integer value indicates a data problem and would cause `git ls-remote` to search for unintended patterns. If invalid, set `HAS_BRANCH` and `HAS_PR` to `1` to force the "genuinely in progress" outcome (step 4) and skip the network checks entirely:

   ```bash
   if ! echo "${ISSUE_NUMBER:-}" | grep -qE '^[1-9][0-9]*$'; then
     echo "WARNING: invalid ISSUE_NUMBER '${ISSUE_NUMBER:-}' — skipping stale detection; treating item as genuinely in progress."
     HAS_BRANCH=1  # force "genuinely in progress" — skip network checks below
     HAS_PR=1
   fi
   ```

2. **Check for an existing implementation branch or open PR** (skip if guard above set `HAS_BRANCH=1`):

   ```bash
   # Only check implementation-stage branches (feature/fix/refactor/hotfix).
   # spec/* and implementation-plan/* branches persist on the remote after merge
   # and must not be treated as evidence that implementation is active.
   # git ls-remote uses bare-number forms only (feature/123-slug, feature/123).
   # Tracker-prefixed forms (feature/ENG-123-slug) are detected by the more-precise
   # gh pr list regex below; broad globs like *-123-* false-positive on unrelated
   # branches containing the issue number in their slug (e.g. feature/456-add-123-logs).
   # Use pipefail so a network/auth failure propagates; on failure, skip stale
   # detection and treat the item as genuinely in progress (fail-open).
   # Only run if the guard above did not already set HAS_BRANCH/HAS_PR=1.
   if [ "${HAS_BRANCH:-0}" -eq 0 ] && [ "${HAS_PR:-0}" -eq 0 ]; then
     HAS_BRANCH=$(set -o pipefail; git ls-remote origin \
       "refs/heads/feature/${ISSUE_NUMBER}-*" \
       "refs/heads/feature/${ISSUE_NUMBER}" \
       "refs/heads/fix/${ISSUE_NUMBER}-*" \
       "refs/heads/fix/${ISSUE_NUMBER}" \
       "refs/heads/refactor/${ISSUE_NUMBER}-*" \
       "refs/heads/refactor/${ISSUE_NUMBER}" \
       "refs/heads/hotfix/${ISSUE_NUMBER}-*" \
       "refs/heads/hotfix/${ISSUE_NUMBER}" \
       2>/dev/null | wc -l | tr -d ' ') || {
       echo "WARNING: git ls-remote failed for issue #${ISSUE_NUMBER} — skipping stale detection."
       HAS_BRANCH=1  # treat as genuinely in progress
     }

     # The jq regex includes an optional tracker-prefix group ([A-Z][A-Z0-9]*-)
     # to match both feature/123-slug and feature/ENG-123-slug forms.
     # Do NOT use || echo 0: a gh failure must not be interpreted as "no PR exists".
     # On failure, treat as genuinely in progress (fail-open).
     HAS_PR=$(gh pr list --state open --limit 1000 \
       --json number,headRefName \
       --jq "[.[] | select(.headRefName | test(\"^(feature|fix|refactor|hotfix)/([A-Z][A-Z0-9]*-)?${ISSUE_NUMBER}(-|\$)\"))] | length" \
       2>/dev/null) || {
       echo "WARNING: gh pr list failed for issue #${ISSUE_NUMBER} — skipping stale detection."
       HAS_PR=1  # treat as genuinely in progress
     }
   fi
   ```

3. **If both checks return zero** (no branch, no PR): the "In Development" status is stale (BR-5). Apply the correction:
   - Log a `STALE_STATUS_CORRECTION:` line:

     ```text
     STALE_STATUS_CORRECTION: issue #<N> tracker shows 'In Development' but no branch or PR found. Correcting to 'Plan Ready'.
     ```

   - Update the tracker status to `Plan Ready` using `update_tracker_status_best_effort` (BR-6).

   - Continue dispatching the implementation stage as if the item was `Plan Ready` (the pre-dispatch tracker status update, which ran earlier in this step and was a no-op because the status was already "In Development", will re-run for the corrected dispatch and advance the tracker back to `In Development`). The brief "Plan Ready" state between the stale reset and the new dispatch is intentional and transient — the orchestrator runs sequentially, so no concurrent observer will act on this intermediate value.

4. **If either check returns non-zero** (branch or PR found): the item is genuinely in progress — do not reset the status. Resume from the existing branch or PR using `workflow-next-action.sh` (AC-8).

### Pre-dispatch branch check

Before dispatching any creator-stage agent, run all three checks below. An existing branch or active worktree means work already exists and should be resumed rather than restarted.

```bash
git branch -r | grep "<branch-prefix>/<slug>"
git branch | grep "<branch-prefix>/<slug>"
git worktree list | grep "<branch-prefix>/<slug>"
```

| Stage about to dispatch | Branch / worktree to check for |
| ----------------------- | ------------------------------ |
| Write spec              | `spec/[slug]`                  |
| Write plan              | `implementation-plan/[slug]`   |
| Implement (Feature)     | `feature/[slug]`               |
| Implement (Refactor)    | `refactor/[slug]`              |

If any check returns a match: **do not re-dispatch**. Resume from the existing branch or PR with `workflow-next-action.sh`.

### Integration-branch base override (sub-items with `integration-branch:<slug>` label)

Before dispatching any creator-stage agent, check whether the item carries an `integration-branch:<slug>` label:

```bash
gh issue view <issue-number> --json labels --jq '.labels[].name | select(startswith("integration-branch:"))'
```

If the label is present:

1. **Derive the integration branch name**: `develop-<slug>` (replace `<slug>` with the value after `integration-branch:`).
2. **Resolve the branch owner**. In `single_repo`, the integration branch is
   owned by the current repository. In `workflow_hub`, it is the product
   implementation base and must be checked against the selected product
   repository, not the hub repository. Hub-owned spec and plan artifacts still
   target the hub artifact base branch.
3. **Verify the branch exists on the owning remote** (output `0` = does not
   exist, `1` = exists):

   ```bash
   OWNING_REPO_ROOT="<current-or-selected-product-repository-root>"
   OWNING_REMOTE="origin"
   BRANCH_EXISTS=$(set -o pipefail; git -C "$OWNING_REPO_ROOT" ls-remote "$OWNING_REMOTE" "refs/heads/develop-<slug>" 2>/dev/null | wc -l | tr -d ' ') || {
     echo "WARNING: failed to verify whether develop-<slug> exists on the owning remote; skipping auto-create for this item."
     continue  # or return 1 / exit 1 depending on surrounding loop/function context
   }
   ```

4. **If the branch does not exist** (`BRANCH_EXISTS` is `0`), create and push it
   from the owning repository's default implementation branch:

   ```bash
   OWNING_REPO_ROOT="<current-or-selected-product-repository-root>"
   OWNING_REMOTE="origin"
   DEFAULT_IMPLEMENTATION_BRANCH="<default-implementation-branch>"
   git -C "$OWNING_REPO_ROOT" fetch "$OWNING_REMOTE" "$DEFAULT_IMPLEMENTATION_BRANCH"
   git -C "$OWNING_REPO_ROOT" checkout -B develop-<slug> "$OWNING_REMOTE/$DEFAULT_IMPLEMENTATION_BRANCH"
   git -C "$OWNING_REPO_ROOT" push -u "$OWNING_REMOTE" develop-<slug>
   git -C "$OWNING_REPO_ROOT" switch "$DEFAULT_IMPLEMENTATION_BRANCH"
   ```

   Log: `INFO: created integration branch develop-<slug> from origin/<default-implementation-branch> for sub-item #<issue-number>.`

5. **Record the implementation base branch**: store `BASE_BRANCH=develop-<slug>`
   and pass it to stage-agent dispatch metadata. In `single_repo`, spec, plan,
   implementation, fix, and refactor PRs target `develop-<slug>`. In
   `workflow_hub`, only product implementation, fix, refactor, review, CI, merge,
   and cleanup actions use `develop-<slug>` in the selected product repository;
   hub-owned spec and plan PRs target the hub artifact base branch.

**Single-item exemption**: When the item carries no `integration-branch:*` label, skip this check. The default base branch (`develop`) applies.

### Repository-mode context declaration

Before any mutation-oriented action, resolve and state repository ownership:

- `WORKFLOW_MODE`
- artifact owner for the current stage
- selected product repository name when implementation work is product-owned
- local path or remote identity when available
- mutation target for file edits, branch creation, commits, PR creation,
  reviewer-loop execution, CI polling, and cleanup
- base branch validation target

Missing mode or explicit `single_repo` keeps the current repository as the owner
and does not require `--repo`. In `workflow_hub`, specs and plans remain
hub-owned unless a future contract says otherwise. Product implementation work
must target the selected product repository. If the selected product repository
is missing or ambiguous, stop before file mutation, branch creation, commit, or
implementation PR creation.

In `workflow_hub`, do not validate a product execution base such as `develop`
against the hub repository before product repository selection. Hub-owned spec
and plan branches use the hub artifact base branch, typically the hub
repository default branch. Product implementation branches use the selected
product repository checkout and that product repository's resolved base branch
(`BASE_BRANCH` from the run-epic scope when present, otherwise the product
entry's `default_branch`).

### Spec-Plan ordering gate

**The plan PR must never be opened before the spec PR has been merged to the integration branch.**

This gate applies whenever the spec and plan are written in the same agent run (i.e., the Work Item Runner advances from spec to plan writing without a human merge in between). The root cause is that reviewers check for the spec file on the target branch — if the spec is only on an unmerged spec branch, the plan PR fails review with "spec file not present on branch."

**Rule: when spec writing and plan writing happen in the same run:**

1. Write the plan content locally on the plan branch (the plan may be written proactively, but it must not be pushed or a PR opened yet).
2. Open the spec PR and advance it to `ready-for-human-review` following the full PR readiness chain (Step 7a, Step 7, Step 8).
3. Resolve `EXPECTED_SPEC_BASE`: in `workflow_hub`, use the hub artifact base
   branch; otherwise use `BASE_BRANCH` when present, falling back to `develop`.
4. Stop and report to the orchestrator with the following structured message:

   > Spec PR #N is `ready-for-human-review`. Plan is written and staged locally on branch `implementation-plan/<slug>`, but the plan PR will not be opened until the spec PR is confirmed merged to `<expected-spec-base>`. On the next dispatch (after spec merge is confirmed), push the plan branch and open the plan PR.

5. On the next dispatch (after spec merge is confirmed via `gh pr view <spec_pr> --json state` returning `MERGED`), push the plan branch and open the plan PR. The plan content was written in the prior run; do not regenerate it.

**Verification before opening a plan PR:**

Before calling `gh pr create` for any `implementation-plan/*` branch, confirm the spec PR is merged:

```bash
# Check whether the spec PR is merged into the expected base branch.
# EXPECTED_SPEC_BASE is the hub artifact base in workflow_hub mode; otherwise it
# is "develop" by default, or "develop-<slug>" when integration-branch:<slug> is present.
# Substitute <spec_pr_number> and <expected-base> with actual values before running:
gh pr view <spec_pr_number> --json state,baseRefName \
  --jq 'select(.state=="MERGED" and .baseRefName=="<expected-spec-base>") | "OK"'
# Expected output: OK
# If no output: the spec PR is not merged into the expected base branch — do not open the plan PR
```

If the spec PR is still `OPEN`, apply the ordering gate above and stop. If the spec PR is `CLOSED` (rejected without merge), do **not** open the plan PR and do **not** apply the ordering gate — escalate to the human, because the spec was rejected and the plan cannot proceed without a merged spec.

**Exception — Refactor items (no spec):** Items following the Refactor path (`02-generate-implementation-plan-protocol.md` without a preceding spec step) are exempt from this gate. There is no spec PR to wait for.

(When the item carries an `integration-branch:<slug>` label in `single_repo`,
"spec PR merged to the integration branch" means merged to `develop-<slug>`, not
to `develop`. In `workflow_hub`, hub-owned spec and plan PRs use the hub
artifact base instead, even when product implementation work uses
`develop-<slug>`.)

### Dependency check

Before advancing the item, check its spec's `Depends on` field. If any dependency is not yet `Merged` or `Released`, stop and report the blocked state to the human.

---

## Step 3: Dispatch Strategy

Use the matching workflow agent / skill for the next stage when your runner supports handoff. Otherwise continue in the current session by following the referenced stage protocol directly.

**Subagent assignment by stage:**

| Stage action                | Preferred execution path                                                                                                                |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Write spec                  | `product-manager`                                                                                                                       |
| Review spec                 | Native review against `REVIEW.md` or the compatibility wrapper `01-review-spec-protocol.md`                                             |
| Write plan                  | `tech-lead`                                                                                                                             |
| Review plan                 | Native review against `REVIEW.md` or the compatibility wrapper `02-review-implementation-plan-protocol.md`                              |
| Implement feature           | `developer`                                                                                                                             |
| Review code (post-draft-PR) | `code-reviewer` agent (Claude Code: `/code-review`); for other runners use compatibility wrapper `03-review-implementation-protocol.md` |

### Worktree isolation for parallel batches

**When dispatched as part of a parallel batch** (`BATCH_CONTEXT=true` in the handoff metadata):

1. **Create a dedicated worktree** for this item before executing any stage work. This ensures complete isolation from other concurrent Work Item Runners in the batch.

2. Determine the appropriate base branch for the worktree:

   **If `BASE_BRANCH` is present in the handoff metadata** (set by the
   Portfolio Orchestrator when the item carries an `integration-branch:<slug>`
   label or by run-epic policy), use `origin/<BASE_BRANCH>` as the base for
   product implementation, fix, and refactor worktrees except for `hotfix/*`.
   In `workflow_hub`, this branch must be checked in the selected product
   repository, not in the hub repository. Hub-owned `spec/*` and
   `implementation-plan/*` worktrees ignore the product `BASE_BRANCH` and use
   `origin/<hub-artifact-base-branch>` instead.

   **If `BASE_BRANCH` is absent**, use the default table:

| Item type                     | Base branch      |
| ----------------------------- | ---------------- |
| Feature (`feature/`)          | `origin/<product-default-branch>` in `workflow_hub`, otherwise `origin/develop` |
| Refactor (`refactor/`)        | `origin/<product-default-branch>` in `workflow_hub`, otherwise `origin/develop` |
| Fast Track fix (`fix/`)       | `origin/<product-default-branch>` in `workflow_hub`, otherwise `origin/develop` |
| Hotfix (`hotfix/`)            | `origin/main`    |
| Spec (`spec/`)                | `origin/<hub-artifact-base-branch>` in `workflow_hub`, otherwise `origin/develop` |
| Plan (`implementation-plan/`) | `origin/<hub-artifact-base-branch>` in `workflow_hub`, otherwise `origin/develop` |

**Note:** Use `origin/<base>` (remote tracking) rather than local `<base>` to avoid git worktree conflicts if the local base branch is already checked out elsewhere.

3. Create the worktree. The command depends on whether the item's branch already exists:

```bash
# Fetch latest remote refs first
git fetch origin

# Case A: New item — branch does not exist yet
git worktree add <worktree-path> -b <branch-prefix>/<slug> origin/<base-branch>

# Case B: Resuming item — branch exists locally
git worktree add <worktree-path> <branch-prefix>/<slug>

# Case C: Resuming item — branch exists only on remote
git worktree add <worktree-path> -b <branch-prefix>/<slug> origin/<branch-prefix>/<slug>

cd <worktree-path>
```

Use the pre-dispatch branch check from Step 2 (`git branch --list`, `git branch -r --list`) to determine which case applies. Case B and C are common when resuming "In Development" items, PRs with `needs-fixes`, or any item with prior work.

**Branch-context verification — mandatory immediately after entering the worktree**

After `cd <worktree-path>`, verify the active branch before doing any work. `git switch` and `git worktree add` output is filtered by RTK (the shell proxy), suppressing the confirmation message — without explicit verification the agent cannot detect a wrong-branch outcome until a commit reveals the error (the Batch 33 incident: commits landed on `fix/pr-agent-classifier-label-aware-2` instead of the intended `fix/487-stale-tracker-status-transitions`). Use `git rev-parse --abbrev-ref HEAD`, which produces a single branch-name token and is RTK-safe:

```bash
# Verify branch context — always visible even through RTK filtering:
CURRENT=$(git rev-parse --abbrev-ref HEAD)
EXPECTED="<branch-prefix>/<slug>"
if [ "$CURRENT" != "$EXPECTED" ]; then
  echo "ERROR: expected branch $EXPECTED, currently on $CURRENT. Aborting."
  exit 1
fi
echo "Branch context verified: $CURRENT"
```

Apply the same verification pattern any time a `git switch` or `git checkout <branch>` is issued outside the worktree-creation path (e.g., when a stage protocol's recovery step asks to switch branches):

```bash
git switch <branch>
# Verify — always visible even through RTK filtering:
CURRENT=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT" != "<branch>" ]; then
  echo "ERROR: expected branch <branch>, currently on $CURRENT. Aborting."
  exit 1
fi
```

**Runtime CWD guard — activate immediately after entering the worktree**

After `cd <worktree-path>`, source and initialise the CWD guard. This provides runtime enforcement that catches branch-switching commands issued from the wrong directory **at execution time** rather than only at the post-agent Step 5.2 inspection:

```bash
# Derive main repo root reliably (never use --show-toplevel inside a worktree)
MAIN_REPO_ROOT="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
WORKTREE_PATH="$(pwd -P)"

# Source the guard (path is relative to the worktree, which mirrors the main repo structure)
source "$MAIN_REPO_ROOT/scripts/development-workflow/worktree-cwd-guard.sh"
worktree_cwd_guard_init "$WORKTREE_PATH" "$MAIN_REPO_ROOT"
```

Once initialised, replace bare `git switch`, `git checkout`, `git reset`, and `git restore` calls with the guarded wrappers exported by the script: `git_switch`, `git_checkout`, `git_reset`, and `git_restore`. If a stage protocol's step calls `git checkout develop && git checkout -b <branch>`, skip it entirely (the worktree was already created on the correct branch) — but if you must call it, use the guarded wrapper so any accidental main-repo targeting is caught immediately.

The guard is **non-blocking**: it emits a `GUARDRAIL WARNING` and returns exit code 1 on a CWD violation, but does not abort the outer shell. Check the return value or `set -e` in the enclosing script to convert warnings into hard failures where appropriate.

**Guard scope limitation — Claude Code subagents**: The `source`/`worktree_cwd_guard_init` sequence above applies to the item-orchestrator's own shell session. It does **not** propagate to Claude Code subagents dispatched via the `Agent` tool — each subagent starts with an independent execution context and has no knowledge of the parent's shell environment. The guard therefore cannot intercept branch-switching commands issued inside a stage subagent. For stage subagents (e.g., `developer`, `tech-lead`), worktree discipline is enforced entirely through the handoff prompt and the agent's own system-prompt rules. See "Stage-agent handoff branch-skip requirement" below.

**Stage-agent handoff branch-skip requirement** (`BATCH_CONTEXT=true` only): Every stage-agent handoff (to `developer`, `tech-lead`, `product-manager`, or any other stage agent) when `BATCH_CONTEXT=true` **must** include:

1. The literal resolved `<worktree-path>` value (e.g., `/path/to/repo/.claude/worktrees/lh-168/fix-lh-168-slug`).
2. The explicit instruction: "BATCH_CONTEXT=true — the worktree is already on branch `<branch>`. Do NOT run `git checkout develop`, `git checkout -b`, `git switch`, `git reset`, or `git restore` from the main repo root. Confirm CWD matches `<worktree-path>` before any git state-changing command."

Omitting either of these from the handoff is the root cause of the branch-leak pattern where stage subagents run Protocol 03's branching steps (`git checkout develop && git checkout -b <branch>`) from the main repo root CWD, silently switching the main working tree to the feature branch.

**Critical: Worktree Git Discipline** (`BATCH_CONTEXT=true` only)

**Pre-operation checklist — verify before every git state-changing command**

Before issuing any `git switch`, `git checkout`, `git checkout -b`, `git reset`, or `git restore` command, confirm both conditions below. If either check fails, do not run the command — correct the path or use the `-C` flag instead.

1. **Confirm you are operating inside the worktree, not the main repository root.**
   Run `pwd` and compare the output against `<worktree-path>`. If they differ, you are in the wrong directory. `cd <worktree-path>` or use `git -C <worktree-path>` before continuing.

2. **Confirm the command targets the current worktree branch, not a base branch.**
   Running `git checkout develop` (or any other base branch) inside the worktree will fail because `develop` is already checked out in the main working tree — git prevents the same branch from being checked out in two locations simultaneously. If a stage protocol's branching step says `git checkout develop && git checkout -b <branch>`, skip it entirely: the worktree was already created on the correct branch.

When operating inside a worktree, **never** run the following commands against the main repo root:

- `git switch <branch>`
- `git checkout <branch>`
- `git checkout -b <branch>`
- `git reset [--hard|--soft|--mixed] ...`
- `git restore ...`

These commands change the branch or modify files in the main working tree, breaking isolation for all concurrent agents and the human operator. Violating this rule leaves the main repo in a broken state (e.g., pointing at a feature branch) that blocks all subsequent agents and the human operator until manually corrected.

**Required alternatives:**

- Run all git operations scoped to the worktree: `cd <worktree-path> && git <command>`
- Or use the `-C` flag: `git -C <worktree-path> <command>`

Read-only inspection of the main repo is always permitted and must use `-C` without switching branches:

```bash
git -C <main-repo-root> rev-parse --abbrev-ref HEAD
```

**Optional — platform-specific: pre-tool-use hook guidance**

For runners that support pre-tool-use hooks (e.g., Claude Code), a non-blocking hook can be configured to warn when a prohibited git command is issued from the main repo root while a worktree is active. The hook should:

1. Intercept tool calls for `Bash` commands.
2. Check whether the command includes any of `switch`, `checkout`, `checkout -b`, `reset`, or `restore` as git subcommands.
3. Compare the working directory of the command against the main repo root path.
4. If the working directory matches the main repo root and the command is state-changing, emit a warning: `"GUARDRAIL WARNING: git state-changing command targeting main repo root detected while worktree is active. Use git -C <worktree-path> or cd <worktree-path> && git instead."`
5. The hook is **non-blocking** — it warns but does not abort the command. Blocking hooks can cause cascading failures when legitimate read-only commands are incorrectly matched.

This hook is advisory and not required for the guardrail to function. The Critical block above is the normative rule; this hook provides an additional safety signal for supported runners.

**Common worktree gotcha — `git rev-parse --show-toplevel` returns the worktree path, not the main repo root**

When an agent runs inside an isolated worktree (`.claude/worktrees/<branch>/`), `git rev-parse --show-toplevel` returns the _worktree_ path rather than the main repo root. Any script or agent instruction that relies on this command to locate `node_modules/`, project-level config files, or other resources installed at the main repo root will construct wrong paths.

Use `git rev-parse --git-common-dir` instead — it always points to the `.git` directory of the _main_ repo regardless of which worktree is active. Append `/..` to get the main repo root:

```bash
# Wrong — returns the worktree path when run inside an isolated worktree:
REPO_ROOT=$(git rev-parse --show-toplevel)

# Correct — always returns the main repo root, even from a worktree:
REPO_ROOT=$(git rev-parse --git-common-dir)/..
```

Apply this pattern whenever a stage agent, script, or implementation step needs to reference `node_modules/`, root-level config files, or any path that lives at the main repo root rather than in the worktree.

**Important — stage protocol compatibility**: When working inside a worktree created with this method, the stage protocol's initial branching steps (`git fetch origin`, `git checkout develop`, `git pull origin develop`, `git checkout -b ...`) are **already satisfied** by the worktree creation above. The stage agent should skip those steps and proceed directly to the implementation work. If the stage agent runs `git checkout develop` inside the worktree, it will fail because `develop` is already checked out in the main working tree and git prevents the same branch from being checked out in multiple worktrees simultaneously.

**Critical safety rule — never modify the main working tree's branch**: An agent running inside a worktree **must never** run `git checkout`, `git switch`, `git reset`, or any command that changes the checked-out branch of the **main working tree**. Violating this rule leaves the main repo in a broken state (e.g., pointing at a `worktree-agent-*` branch) that breaks subsequent operations for all other agents and for the human operator.

- All git operations must target **the current worktree only**. Never `cd` out of the worktree into the main repo root and then run branch-switching commands.
- If you need to read information from the main repo (e.g., inspect its current branch), use `git -C <main-repo-root> <command>` without switching branches, for example:

  ```bash
  git -C /path/to/main-repo rev-parse --abbrev-ref HEAD
  ```

- After the item reaches a terminal condition and **before** removing the worktree, verify the main working tree is still on the expected integration branch **and has no uncommitted modifications**. This check mirrors Protocol 90 Step 5.2 — use the same four-case handling described there. Resolve the expected branch from your workflow context (typically `develop` for this template, but use whatever `integration_branch` is configured for the repo):

  ```bash
  INTEGRATION_BRANCH="<integration-branch>"  # e.g., develop (or main in repos configured that way)
  MAIN_BRANCH=$(git -C <main-repo-root> rev-parse --abbrev-ref HEAD)
  MAIN_STATUS=$(git -C <main-repo-root> status --porcelain)

  if [ "$MAIN_BRANCH" != "$INTEGRATION_BRANCH" ] && [ -z "$MAIN_STATUS" ]; then
    # Case 1: Wrong branch + clean — auto-correct and log guardrail violation
    echo "GUARDRAIL: main working tree was on '$MAIN_BRANCH' after this agent completed. Expected '$INTEGRATION_BRANCH'. Auto-correcting."
    echo "IMPORTANT: Record this as a guardrail violation in retrospective notes — the agent likely ran in the main tree instead of the worktree, or leaked a branch switch."
    git -C <main-repo-root> switch "$INTEGRATION_BRANCH"
    # Proceed normally after correction

  elif [ "$MAIN_BRANCH" != "$INTEGRATION_BRANCH" ] && [ -n "$MAIN_STATUS" ]; then
    # Case 2: Wrong branch + dirty — halt and escalate
    echo "ERROR: main working tree is on '$MAIN_BRANCH' (expected '$INTEGRATION_BRANCH') AND has uncommitted modifications."
    echo "$MAIN_STATUS"
    echo "Do not proceed. The human must inspect, discard or commit these changes, and restore the main tree to '$INTEGRATION_BRANCH' before the next dispatch."
    exit 1

  elif [ "$MAIN_BRANCH" = "$INTEGRATION_BRANCH" ] && [ -z "$MAIN_STATUS" ]; then
    # Case 3: Correct branch + clean — proceed normally
    :

  elif [ "$MAIN_BRANCH" = "$INTEGRATION_BRANCH" ] && [ -n "$MAIN_STATUS" ]; then
    # Case 4: Correct branch + dirty — halt and escalate
    echo "WARNING: main working tree is on '$INTEGRATION_BRANCH' but has uncommitted modifications:"
    echo "$MAIN_STATUS"
    echo "Possible cause: a stage agent leaked file writes outside the worktree boundary."
    echo "Do NOT commit or discard these changes without human review. Do not dispatch additional agents."
    exit 1
  fi
  ```

  For Case 1, auto-correct is safe because the tree is clean — no uncommitted work is at risk. The guardrail violation must still be logged in retrospective notes because it indicates the isolation boundary was breached (the agent likely ran in the main tree rather than the worktree, or a stage protocol issued a branch-switching command that leaked into the main tree). For Cases 2 and 4, **stop and report to the human** — the human must inspect and resolve before the next batch dispatch.

**Critical safety rule — Write and Edit paths inside a worktree**: Every `Write` and
`Edit` tool call issued within an active worktree session **must** target a path under
`<worktree-path>/...`. Any path that does NOT begin with the resolved `<worktree-path>`
value is a main-repo path — treat it as a red flag and correct it before calling the tool.

- Before calling `Write` or `Edit`, mentally verify: "Does this absolute path start with
  `<worktree-path>/`?" If not, prepend `<worktree-path>/` to the relative portion of the
  path.
- The item-orchestrator must include the resolved literal value of `<worktree-path>` in
  every stage-agent handoff (not just the first), so each agent can validate paths against
  it independently.
- Paths under `<worktree-path>/.tmp/` are within the worktree boundary and are permitted.
- This rule applies only when `BATCH_CONTEXT=true` and a dedicated worktree exists; for
  non-batch runs, no reminder is injected.

**Optional: pre-tool-use hook for WORKTREE_ROOT validation**

A pre-tool-use hook can enforce the Write/Edit path rule automatically:

1. Set the `WORKTREE_ROOT` environment variable to the resolved worktree path when
   launching the agent session.
2. In the hook, intercept `Write` and `Edit` tool calls only.
3. If `WORKTREE_ROOT` is unset, skip the check (non-worktree session — no-op).
4. If the target path does not start with `$WORKTREE_ROOT`, emit:
   `"GUARDRAIL: Write/Edit target '<path>' is outside the designated worktree
'<WORKTREE_ROOT>'. Correct the path before proceeding."`
5. The hook is **non-blocking** — it warns but does not prevent the tool call. This
   allows the agent to correct the path in subsequent calls and prevents cascading
   failures from false positives.
6. The hook must NOT intercept read-only tools (`Read`, `Glob`, `Grep`).

7. **Suggested worktree path**: `<repo-root>/.claude/worktrees/<item-id>/<branch-prefix>-<slug>` where `<item-id>` is the issue number, tracker ID, or slug.

8. After the item reaches a terminal condition, the cleanup script will remove the worktree:

```bash
# IMPORTANT: Change directory to the main repo root BEFORE deleting the worktree
cd <repo-root>
git worktree remove <worktree-path>
```

**Critical safety rule:** You **must** `cd` to the repository root or any other valid directory **before** executing `git worktree remove`. If the shell's current working directory (CWD) is inside the worktree being deleted, the directory will cease to exist immediately after `git worktree remove` completes. All subsequent bash commands will fail with "directory not found" errors, causing the orchestration to break and requiring manual intervention or agent re-delegation.

After removing the worktree, verify that the CWD is still valid by running a simple command like `pwd` before executing any further shell operations.

**When not in a parallel batch**: Worktree creation is optional but recommended for large development folders or long-running work. If not using a dedicated worktree, ensure the working directory is clean before proceeding.

**Permission-denial early exit (subagent runs only)**: If at any point during the run the harness responds with the known harness failure pattern — a message containing the phrase `"Permission to use"` AND a denied tool name (`Edit`, `Write`, or `Bash`) — the subagent must **immediately stop all further work** and return the following structured string to the Portfolio Orchestrator:

```
SUBAGENT_PERMISSION_DENIAL: [tool] tool denied on <denied-target>. No partial work committed. Falling back to orchestrator inline execution.
```

The `<denied-target>` field identifies what was denied and must be populated as follows:

- **`Edit` or `Write` denial**: list every denied file path as a comma-separated list of repo-relative, normalized paths, sorted lexicographically, with no duplicates and no surrounding spaces (e.g., `.claude/agents/developer.md,.cursor/agents/developer.md`). When only one path was denied, write it without a trailing comma.
- **`Bash` denial**: use the denied command pattern as reported by the harness (e.g., `Bash(gh api:*)`). There is no file path to report for a Bash denial.

This field is mandatory in all cases so the orchestrator can identify and resolve the permission gap before retrying.

**No silent workarounds — this is an absolute rule**: When `Edit` or `Write` is denied for any path (including `.claude/agents/**`, `.cursor/agents/**`, or any other file), the subagent MUST NOT use any alternative mechanism to write the same content. The following substitutions are all explicitly prohibited:

- `Bash` with `echo`, `cat`, `tee`, `printf`, `>`, or any shell redirection
- Python subprocess (`python3 -c "open(...).write(...)"` or equivalent)
- `gh api --method PUT /repos/.../contents/...` (GitHub Contents API)
- Any other indirect write path

**Rationale**: These side-channel writes bypass the canonical `Edit`/`Write` tool pipeline, which means any pre-tool-use hooks (e.g., path validation, write tracking) do not fire. They also make it impossible for the Portfolio Orchestrator to detect that a permission gap exists and perform the correct inline fallback. Silent degradation to a workaround tool is a protocol violation that erodes the orchestrator's ability to track item state reliably.

Before exiting:

- Do **not** apply any PR labels.
- Do **not** commit any partial work.
- Do **not** update the tracker status.

The Portfolio Orchestrator will handle recovery via the inline fallback described in `90-batch-orchestrate-work-protocol.md` Step 4.1.

This protocol stays scoped to one item. It may call different stage agents over time, but it must not start scanning or dispatching unrelated items.

### CHANGELOG in parallel batches

See Protocol 90 Step 3.6 for the canonical CHANGELOG strategy in parallel batches. CHANGELOG merge conflicts are resolved at merge time by the batch-merge auto-resolution (Protocol 94 Step 4.3).

### Scope Boundary Rule for Dispatched Agents

When dispatching a stage agent (creator, reviewer, or fixer), include the following explicit instruction:

> **Critical scope rule**: This item is assigned only to [ISSUE_ID]. Modify **only** files directly related to this issue. If a finding or review comment requires changes outside this issue's scope (e.g., fixing issues in unrelated modules, applying a new pattern to the broader codebase, or addressing tech debt elsewhere), do **not** implement it. Instead:
>
> 1. Note it as a separate finding
> 2. Suggest opening a new issue if appropriate
> 3. Continue with in-scope work only
>
> This is critical in parallel batch orchestration where multiple agents work concurrently. Out-of-scope changes cause merge conflicts and waste review cycles.

This rule prevents agents from making changes that affect unrelated issues and causing downstream conflicts in batch runs.

---

## Step 3.5: Pre-flight Permission Self-Check (Subagent Runs Only)

**Applies to**: Work Item Runner subagents dispatched as part of a parallel batch (`BATCH_CONTEXT=true`). This step is **optional but recommended** — the permission-denial early-exit in Step 3 (above) covers mid-run failures even without the self-check.

Before calling any creator-stage agent or making any file edits, perform a lightweight sanity check to verify that both `Edit` and `Bash` are accessible:

1. **Test `Edit`**: Use the `Edit` tool to create `.tmp/permission-preflight.tmp` with a single comment line (`# preflight-check`). This is the primary check — the Batch 5 incident (#160) was specifically about `Edit` being denied while `Bash` remained available.
2. **Test `Bash`**: Use `Bash` to delete the temp file:

   ```bash
   rm -f .tmp/permission-preflight.tmp
   ```

If either tool call is denied (harness responds with a permission-denied message), exit immediately before any creator-stage work:

```
SUBAGENT_PERMISSION_DENIAL: [DENIED_TOOL] tool denied on <denied-target>. No partial work committed. Falling back to orchestrator inline execution.
```

**Self-check rules**:

- Always target `.tmp/` for the self-check write (this path is gitignored).
- Clean up the temp file after the check regardless of outcome.
- Never touch tracked files during the self-check.
- After the write, run a quick sanity check to ensure no tracked file was accidentally modified:

  ```bash
  git status --porcelain
  ```

  If the output is non-empty, clean up the `.tmp/permission-preflight.tmp` artifact, emit a distinct error (`SELF_CHECK_DIRTY_WORKTREE: unexpected tracked file modifications detected — see git status output above`), and abort for human inspection. Do **not** emit `SUBAGENT_PERMISSION_DENIAL:` for this case.

If the self-check succeeds, proceed normally to the creator-stage work.

---

## Step 4: Execute and Re-evaluate

Run the next deterministic action for the selected item, then immediately re-evaluate the item state.

Expected chain:

For spec and plan PRs, the creator-stage output includes the `Document Quality
Gate` log in the draft PR description before Step 7a begins. If the log is
missing or obviously incomplete, treat the creator stage as incomplete and fix
the PR description before running reviewer readiness loops.

`creator -> draft PR opened with Document Quality Gate log when applicable -> internal review gate with all review.on_draft.runner reviewers (Step 7a) -> draft GitHub reviewer gate with review.on_draft.github -> gh pr ready -> ready GitHub reviewer phase with review.on_ready.github (Step 7) -> regression label (Step 7b, implementation PRs only) -> CI loop (Step 8) -> label readiness checklist (Step 8a) -> tracker status update (Step 8b) -> independent PR verification (Step 8c) -> wait or escalation`

After any subagent finishes, determine whether the item still has a deterministic next action:

```bash
./scripts/development-workflow/workflow-next-action.sh --branch <branch>
./scripts/development-workflow/workflow-next-action.sh --pr <number>
./scripts/development-workflow/workflow-next-action.sh --development <path>
```

Do not stop after a single creator or reviewer stage if the next action is deterministic.

---

## Step 5: Resume Rules

When work already exists, resume rather than restart.

- If a development folder already maps to `Spec Ready`, `Plan Ready`, or `In Development`, continue from that state
- If a workflow branch already exists, use `workflow-next-action.sh --branch <branch>`
- If a PR already exists, use `workflow-next-action.sh --pr <number>`
- If labels indicate `needs-fixes`, enter the fix loop instead of reopening the stage from scratch
- If a run aborts mid-turn due to model quota, stream timeout, or runner unavailability, follow [`provider-contingency-runner-failover.md`](../provider-contingency-runner-failover.md) before manually changing PR labels or restarting from scratch

The Work Item Runner owns the full control loop for this item until it reaches a terminal condition.

---

## Step 6: Notify Humans

After the selected item reaches a terminal condition, provide a concise summary:

```markdown
## Work Item Runner Summary

- Item: [identifier]
- Final state: ready for human review / waiting on human decision / blocked / escalated
- Path taken: plan written -> reviewed -> PR opened -> automated review clean -> CI green
- Next human action: merge PR / answer architecture question / unblock dependency
```

**Retrospective suggestion (standalone runs only)**:

If this Work Item Runner was invoked **directly by a human** (i.e., `BATCH_CONTEXT` is not set or is `false`), do **not** suggest a retrospective immediately after the terminal condition summary. The work is not complete yet — the human still needs to review and merge the PR.

Instead, suggest the retrospective **after the human confirms the PR has been merged** (e.g., via `/post-merge-cleanup` or an explicit "it's merged" message). At that point, offer:

> Would you like to run a retrospective on this session's work?

If the human agrees, follow `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md`. The retrospective will analyze the PRs from this item run using both GitHub data and the conversation context from this session.

**When `BATCH_CONTEXT=true`** (dispatched by the Portfolio Orchestrator): suppress the retrospective suggestion entirely. The Portfolio Orchestrator will suggest the retrospective after the full batch has been merged, not when PRs reach `ready-for-human-review`.

---

## Step 7a: Internal Review Gate (Draft PR)

**Guardrails check — delegated review gate**: Before entering this review
handoff, check whether the effective guardrails grant delegated review authority
for this stage. Per `guardrails-enforcement.md` section 3 Gate 4:

- If the effective mode is `delegated` or `autonomous` and the stage
  `may_merge_pr` is not explicitly `false`: the runner may make the review
  decision using the review-and-fix behavior described in this step.
- Otherwise: leave the PR at its normal `ready-for-human-review` handoff — do
  not make the review decision autonomously.

Run this step immediately after opening a draft PR, and again after any push that addresses internal-review findings.

### Draft-state pre-check (mandatory, before any reviewer is dispatched)

Before dispatching any reviewer, check whether the PR is currently in draft state:

```bash
gh pr view <pr_number> --json isDraft --jq '.isDraft'
```

If the result is `true` (PR is a draft), inspect the resolved
`review.on_draft.runner` list from `.ai-dev-workflow.yaml` (after any
`.ai-dev-workflow.local.yaml` override) and the `review.on_draft.github` /
`review.on_ready.github` lists.

If `coderabbit` is **only** listed under `review.on_ready.github`, keep the PR as
a draft during Step 7a. This is intentional: `.coderabbit.yaml` has
`reviews.auto_review.drafts: false`, so draft state prevents CodeRabbit from
starting before the draft GitHub reviewer gate. If `coderabbit` is listed under
`review.on_draft.github` while draft reviews are disabled, treat the reviewer
placement as a configuration issue to fix before Step 7: draft GitHub reviewers
are expected to support draft PRs.

If `coderabbit` is listed as a **runner reviewer** and is therefore required
inside Step 7a itself, convert the PR to non-draft before triggering reviewers:

```bash
gh pr ready <pr_number>
```

Post a comment on the PR explaining the action:

> `INFO: PR converted from draft to non-draft before Step 7a internal review. Reason: CodeRabbit is configured as an internal reviewer and '.coderabbit.yaml' sets 'auto_review.drafts: false' — CodeRabbit silently skips draft PRs. Converting now to ensure full reviewer coverage.`

**Why this matters**: CodeRabbit (and similar tools) configured with
`auto_review.drafts: false` do not post any skip notice when they bypass a draft
PR. That behavior is useful when CodeRabbit is intentionally configured as an
a ready-phase reviewer, because it lets the draft GitHub gate clear first. It is
unsafe when CodeRabbit is configured as a Step 7a runner reviewer, because the
internal review gate would silently pass with reduced coverage.

**Reviewer-to-draft-restriction mapping**:

| Reviewer     | Skips draft PRs when...                                                     |
| ------------ | --------------------------------------------------------------------------- |
| `coderabbit` | `.coderabbit.yaml` has `reviews.auto_review.drafts: false` (the default)    |
| `claude`     | Never — Claude Code agents always review regardless of draft state          |
| `codex`      | Never — Codex skill reviewers always review regardless of draft state       |

To check whether `.coderabbit.yaml` restricts draft PRs:

```bash
grep -E '^\s*drafts:\s*false' .coderabbit.yaml
```

If the file is absent or the key is not present, CodeRabbit defaults to `drafts: false` — treat it as draft-restricting.

**Important**: Do not convert a draft PR to non-draft merely because CodeRabbit
appears in `review.on_draft.github` or `review.on_ready.github`. Convert early
only when CodeRabbit is part of `review.on_draft.runner`. Otherwise, keep the
draft state until the draft GitHub reviewer gate below has passed.

If the PR is **not** in draft state, skip this pre-check entirely and proceed to the Design Review Gate.

### Design Review Gate (implementation PRs only)

This gate applies only to PRs on `feature/*`, `fix/*`, `refactor/*`, and `hotfix/*` branches (BR-1). It is skipped entirely for `spec/*` and `implementation-plan/*` branches — proceed directly to "Determining which reviewers to run" for those PR types.

#### Frontend-file detection

Inspect the PR's changed files:

```bash
gh pr diff <pr_number> --name-only
```

A file is **frontend** if any of the following conditions hold:

- Its extension is one of: `.html`, `.css`, `.scss`, `.sass`, `.less`, `.jsx`, `.tsx`, `.vue`, `.svelte` (BR-2)
- Its extension is `.js` or `.ts` **and** its path starts with one of these directory prefixes: `src/`, `app/`, `pages/`, `components/`, `public/`, `static/`, or `assets/` (BR-2)

`.js` and `.ts` files at the repository root or under `scripts/` are **not** treated as frontend.

These detection rules are extensible — downstream teams that need additional extensions or paths must update this list (and keep `.claude/agents/design-reviewer.md` and `.cursor/agents/design-reviewer.md` in sync).

#### Three execution paths

**Path A — No frontend changes detected (Use Case 2):**

Skip the design-reviewer agent entirely. No comment is posted. Proceed to "Determining which reviewers to run". This skip is not a failure (BR-10).

**Path B — Frontend changes detected, provider available (Use Case 1):**

Invoke the `design-reviewer` agent, passing:

- The PR number
- The list of changed frontend files
- The `PREVIEW_URL` environment variable (if set) or instructions to start the development server

After the agent posts its PR comment, parse the verdict from the comment header (the comment must begin with `## Design Review Summary` and the verdict must appear as `**Verdict**: <value>` — BR-9):

| Verdict          | Action                                                                                                                            |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `Approved`       | Proceed normally to "Determining which reviewers to run"                                                                          |
| `Needs Revision` | Treat as a review finding. Do not advance to `ready-for-human-review` until the issues are resolved or explicitly accepted (BR-5) |
| `Skipped`        | Development server was unreachable; log the skip and continue without blocking (BR-4)                                             |

**Path C — Frontend changes detected, provider unavailable (Use Case 3):**

Invoke the `design-reviewer` agent; it will detect provider unavailability, post a skip notice, and exit with verdict `Skipped`. Parse the `Skipped` verdict and continue without blocking the PR (BR-3).

#### Preview URL resolution

The design-reviewer agent resolves the preview base URL in this order (BR-11):

1. `PREVIEW_URL` environment variable, treated as the base URL (file-relative paths are appended).
2. Local development server started by the agent (the server address becomes the base URL).
3. If neither is available, the agent skips preview navigation and falls back to a report noting that no live preview was accessible.

#### Browser automation provider

The agent reads `browser_automation.provider` from `.ai-dev-workflow.yaml`. For this repository the provider is `playwright_cli`. The agent must not hard-code a provider value (BR-8).

### Determining which reviewers to run

Read the `review.on_draft.runner` list from `.ai-dev-workflow.yaml`. For local
developer overrides, prefer `.ai-dev-workflow.local.yaml` (gitignored) with the
same nested review shape:

```yaml
review:
  on_draft:
    runner:
      - cursor
  internal_reviewers_unavailable_policy: warn
```

The local YAML file takes precedence over `.ai-dev-workflow.yaml`. This allows
developers without access to all configured review tools to run a subset, such
as only `cursor`, without changing the shared config.

Supported runner reviewer values: `claude`, `cursor`, `codex`, `coderabbit`.

If neither config file defines `review.on_draft.runner`, fall back to running
the stage-appropriate reviewer once (default behavior: `claude`).

When the local file supplies an override, log the following before running the
availability check:

> `INFO: Using review.on_draft.runner override from .ai-dev-workflow.local.yaml: [<override-list>]. Original list: [<yaml-list>].`

No warning comment is posted for reviewers intentionally removed by the override list (`override-excluded`). If any reviewer still present in the override list is unreachable at runtime, post the standard warning comment for those unreachable reviewers (the runtime-availability check still applies to the override list).

### Runtime-availability check

Before dispatching any reviewer, classify each entry in the resolved list as `reachable` or `unreachable`. For `claude`, `cursor`, and `codex`, the check is deterministic and requires no external network call — runner identity is a sufficient proxy for reviewer reachability because the gate only dispatches reviewers the current runner can invoke without a cross-runner CLI handoff. For `coderabbit`, reachability is determined at runtime via an App installation check (see below).

#### Reachability classification table

| Runner context                                    | `claude` reachable? | `cursor` reachable? | `codex` reachable? | `coderabbit` reachable?           |
| ------------------------------------------------- | ------------------- | ------------------- | ------------------ | --------------------------------- |
| Claude Code (direct human session)                | Yes                 | No                  | No                 | Determined at runtime (App check) |
| Claude Code subagent (dispatched by orchestrator) | Yes                 | No                  | No                 | Determined at runtime (App check) |
| Cursor direct session or subagent                 | No                  | Yes                 | No                 | Determined at runtime (App check) |
| Codex runner / Codex skill                        | Yes                 | No                  | Yes                | Determined at runtime (App check) |
| Direct human (shell / CI with `gh`)               | Yes                 | Yes                 | Yes                | Determined at runtime (App check) |

To determine `coderabbit` reachability, the runner checks whether `coderabbitai[bot]` has any prior activity on the repository (App installation signal — via `gh api repos/{owner}/{repo}/installation` or by checking the PR for a prior CodeRabbit comment), **and** confirms that `.coderabbit.yaml` does not disable auto-review (`reviews.auto_review.enabled: true` required). If either check fails, classify `coderabbit` as `unreachable`.

Note: the `auto_review.drafts: false` restriction is **not** treated as an unreachability condition here — it is handled upstream by the "Draft-state pre-check" at the top of Step 7a, which converts any draft PR to non-draft before this reachability check runs. By the time the reachability check executes, the PR is guaranteed to be non-draft (if the pre-check determined that a draft-restricting reviewer was in the list).

#### Policy resolution

After classifying each reviewer, apply the configured policy. Read
`internal_reviewers_unavailable_policy` from `.ai-dev-workflow.yaml` (or its
local override in `.ai-dev-workflow.local.yaml`). This policy key is retained
for compatibility even though the reviewer list moved to
`review.on_draft.runner`. If the key is absent, the default is `warn`.

To override the policy locally without changing shared config, prefer
`.ai-dev-workflow.local.yaml`:

```yaml
review:
  on_draft:
    runner:
      - cursor
  internal_reviewers_unavailable_policy: warn
```

Allowed values: `warn` (default), `fail-if-any-unavailable`.

| Condition                                                 | Policy                    | Action                                                                                                                                                                                                                                                                                           |
| --------------------------------------------------------- | ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Zero reviewers reachable                                  | Any                       | **Hard-fail** — post the Step 7a summary comment (as error/blocked comment per Use Case 2) and stop. Do NOT call `gh pr ready`. Escalate to human.                                                                                                                                               |
| One or more reviewers unreachable, at least one reachable | `warn` (default)          | Post a warning comment to the PR naming each unreachable reviewer and the runner context, record each as `skipped (unreachable)`, then proceed with the reachable subset.                                                                                                                        |
| Any reviewer unreachable                                  | `fail-if-any-unavailable` | **Hard-fail** — same outcome as zero-reachable (no reviewers dispatched, PR stays draft, escalate to human) even when some reviewers are reachable. Post the Step 7a summary comment using the hard-fail comment format **Case B** below and stop. Do NOT call `gh pr ready`. Escalate to human. |
| All reviewers reachable                                   | Any                       | Proceed normally — no warning comment, no deviation from the existing flow.                                                                                                                                                                                                                      |

#### Warning comment format (one or more unreachable, `warn` policy)

Post via `gh pr comment` before dispatching any reviewer. Use the following wording for each unreachable reviewer:

> `WARNING: internal_reviewer '<reviewer>' unreachable from current runner (<runner-context>) — skipping. Only '<reachable-list>' will run in this Step 7a cycle. Reviewer coverage is reduced from <total> to <reachable-count>.`

Example for `codex` unreachable from a Claude Code subagent with
`review.on_draft.runner: [claude, codex]`:

> `WARNING: internal_reviewer 'codex' unreachable from current runner (Claude Code subagent) — skipping. Only 'claude' will run in this Step 7a cycle. Reviewer coverage is reduced from 2 to 1.`

#### Hard-fail comment format

Post via `gh pr comment`. This comment doubles as the BR-7 mandatory Step 7a summary comment in the hard-fail case. Use the appropriate template based on the hard-fail condition:

**Case A — Zero reviewers reachable (any policy):**

> `Step 7a BLOCKED: no internal reviewer is reachable from the current runner. Effective reviewer set: none. Reachable: []. Unreachable: [<reviewer> (unreachable), ...]. Verdict: hard-fail. To unblock: run Step 7a from a runner that supports all configured reviewers, or temporarily override 'review.on_draft.runner' via .ai-dev-workflow.local.yaml.`

**Case B — `fail-if-any-unavailable` policy triggered (one or more reviewers unreachable, but at least one was reachable):**

> `Step 7a BLOCKED: policy 'fail-if-any-unavailable' triggered — one or more internal reviewers are unreachable. No reviewers were dispatched. Effective reviewer set: none (policy block). Reachable: [<reachable-list>]. Unreachable: [<reviewer> (unreachable), ...]. Verdict: hard-fail. To unblock: run Step 7a from a runner where all configured reviewers are reachable, or set internal_reviewers_unavailable_policy to 'warn' temporarily, or override 'review.on_draft.runner' via .ai-dev-workflow.local.yaml.`

### Reviewer dispatch map

For each reviewer in the resolved list, dispatch the stage-appropriate agent:

| Reviewer     | PR branch prefix                                  | Agent / protocol to dispatch                                                                                           |
| ------------ | ------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `claude`     | `spec/*`                                          | `spec-reviewer` or `01-review-spec-protocol.md`                                                                        |
| `claude`     | `implementation-plan/*`                           | `implementation-plan-reviewer` or `02-review-implementation-plan-protocol.md`                                          |
| `claude`     | `feature/*` / `refactor/*` / `fix/*` / `hotfix/*` | `code-reviewer` or `03-review-implementation-protocol.md`                                                              |
| `cursor`     | `spec/*`                                          | Cursor `spec-reviewer` agent or `01-review-spec-protocol.md`                                                          |
| `cursor`     | `implementation-plan/*`                           | Cursor `implementation-plan-reviewer` agent or `02-review-implementation-plan-protocol.md`                             |
| `cursor`     | `feature/*` / `refactor/*` / `fix/*` / `hotfix/*` | Cursor `code-reviewer` agent or `03-review-implementation-protocol.md`                                                 |
| `codex`      | `spec/*`                                          | `workflow-spec-reviewer` Codex skill against `REVIEW.md`                                                               |
| `codex`      | `implementation-plan/*`                           | `workflow-plan-reviewer` Codex skill against `REVIEW.md`                                                               |
| `codex`      | `feature/*` / `refactor/*` / `fix/*` / `hotfix/*` | `workflow-code-reviewer` Codex skill against `REVIEW.md`                                                               |
| `coderabbit` | `spec/*`                                          | Trigger CodeRabbit via push (auto-review); poll for `coderabbitai[bot]` response — see `coderabbit.md` Step 7a section |
| `coderabbit` | `implementation-plan/*`                           | Trigger CodeRabbit via push (auto-review); poll for `coderabbitai[bot]` response — see `coderabbit.md` Step 7a section |
| `coderabbit` | `feature/*` / `refactor/*` / `fix/*` / `hotfix/*` | Trigger CodeRabbit via push (auto-review); poll for `coderabbitai[bot]` response — see `coderabbit.md` Step 7a section |

### Branch-type detection

Before running any reviewers, classify the PR branch to determine which execution path applies:

- **Implementation PR**: branch matches `feature/*`, `fix/*`, `refactor/*`, `hotfix/*`, or `backport/hotfix/*`. These PRs follow the **two-pass** review procedure below.
- **Non-implementation PR**: branch matches `spec/*` or `implementation-plan/*`. These PRs follow the existing **single-pass** review procedure and are not affected by this section's two-pass rules.

### Multi-reviewer execution rules

Run all configured internal reviewers **sequentially** in the order listed. Each reviewer runs against `REVIEW.md`, applies deterministic fixes directly, and commits + pushes if needed.

Initialize `internal_review_cycle = 0` at the start of Step 7a. Increment each time the full Pass 1 → Pass 2 cycle is restarted (for implementation PRs) or the full reviewer list is restarted (for non-implementation PRs). Escalate to human when `internal_review_cycle` reaches `max_internal_review_cycles` (default: 5).

#### Non-implementation PRs (spec/_, implementation-plan/_): single-pass

| Outcome                                                                                                   | Action                                                                                                                                                                        |
| --------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| All reviewers `APPROVED`                                                                                  | Post the Step 7a summary comment (see below), then run `gh pr ready <pr_number>` to convert the draft PR to non-draft, then continue to Step 7 (external automated reviewers) |
| Any reviewer returns `NEEDS REVISION` (fixable) and `internal_review_cycle < max_internal_review_cycles`  | Fixes already applied by the agent; increment `internal_review_cycle`; re-run **all** internal reviewers from the beginning of the list                                       |
| Any reviewer returns `NEEDS REVISION` (fixable) and `internal_review_cycle >= max_internal_review_cycles` | Post the Step 7a summary comment with verdict `escalated — max cycles reached`, then escalate to human                                                                        |
| Any reviewer returns `NEEDS REVISION` (product/design decision)                                           | Post the Step 7a summary comment with verdict `escalated — human decision required`, then stop and escalate to human before proceeding                                        |

All internal reviewers must APPROVE before `gh pr ready` is called. If any reviewer finds issues, fix them and re-run ALL internal reviewers.

#### Implementation PRs (feature/_, fix/_, refactor/_, hotfix/_): two-pass

Implementation PRs run two sequential passes before `gh pr ready` is called. Pass 2 is never dispatched until all reviewers have approved Pass 1 for the current commit.

**Pass 1 (Spec Compliance)**: each reviewer evaluates only the `### Pass 1: Spec Compliance` sub-checklist from `REVIEW.md`. The orchestrator passes the active pass name (`Pass 1: Spec Compliance`) in the dispatch prompt so the reviewer scopes its findings accordingly.

**Pass 2 (Code Quality)**: each reviewer evaluates only the `### Pass 2: Code Quality` sub-checklist from `REVIEW.md`. The orchestrator passes the active pass name (`Pass 2: Code Quality`) in the dispatch prompt. Pass 2 is dispatched only after all reviewers have approved Pass 1.

**Multi-reviewer ordering within each pass**: when multiple internal reviewers are configured, all reviewers complete Pass 1 before any reviewer's Pass 2 is dispatched.

**Same-commit SHA requirement**: when both passes run without a trivial-fix skip, both passes must approve at the same commit SHA before `gh pr ready` is called. When Pass 1 is skipped under the trivial-fix path (see below), only Pass 2 must approve at the current commit SHA — Pass 1's earlier approval (at a prior SHA) remains valid for that cycle.

| Outcome                                                                                                                                                                          | Action                                                                                                                                                                                                                                                                                  |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| All reviewers `APPROVED` on Pass 1                                                                                                                                               | Proceed to Pass 2 for all reviewers                                                                                                                                                                                                                                                     |
| Any reviewer returns `NEEDS REVISION` on Pass 1 (fixable) and `internal_review_cycle < max_internal_review_cycles`                                                               | Fixes already applied; increment `internal_review_cycle`; restart from Pass 1 for all reviewers                                                                                                                                                                                         |
| Any reviewer returns `NEEDS REVISION` on Pass 1 (fixable) and `internal_review_cycle >= max_internal_review_cycles`                                                              | Post the Step 7a summary comment with verdict `escalated — max cycles reached`, then escalate to human                                                                                                                                                                                  |
| Any reviewer returns `NEEDS REVISION` on Pass 1 (product/design decision)                                                                                                        | Post the Step 7a summary comment with verdict `escalated — human decision required`, then stop and escalate to human                                                                                                                                                                    |
| All reviewers `APPROVED` on Pass 2                                                                                                                                               | Post the Step 7a summary comment (see below), then run `gh pr ready <pr_number>` to convert the draft PR to non-draft, then continue to Step 7 (external automated reviewers)                                                                                                           |
| Any reviewer returns `NEEDS REVISION` on Pass 2 (fixable) — fix is **non-trivial** — and `internal_review_cycle < max_internal_review_cycles`                                    | Fixes already applied; increment `internal_review_cycle`; restart from **Pass 1** for all reviewers                                                                                                                                                                                     |
| Any reviewer returns `NEEDS REVISION` on Pass 2 (fixable) — fix is **trivial** (all three trivial-fix conditions met) — and `internal_review_cycle < max_internal_review_cycles` | Skip Pass 1 re-run; increment `internal_review_cycle`; post a skip note (see Trivial-fix skip rule); restart from **Pass 2** only. The same-SHA requirement does not apply to Pass 1 for this cycle — only Pass 2 must approve at the current commit SHA before `gh pr ready` is called |
| Any reviewer returns `NEEDS REVISION` on Pass 2 (fixable) and `internal_review_cycle >= max_internal_review_cycles`                                                              | Post the Step 7a summary comment with verdict `escalated — max cycles reached`, then escalate to human                                                                                                                                                                                  |
| Any reviewer returns `NEEDS REVISION` on Pass 2 (product/design decision)                                                                                                        | Post the Step 7a summary comment with verdict `escalated — human decision required`, then stop and escalate to human                                                                                                                                                                    |

Both passes must complete with all reviewers `APPROVED` before `gh pr ready` is called. The `internal_review_cycle` counter increments on every fix cycle — whether the fix is trivial (Pass 2 restart only) or non-trivial (full Pass 1 → Pass 2 restart). This ensures that repeated trivial-fix cycles are bounded by `max_internal_review_cycles` and cannot loop indefinitely.

#### Step 7a summary comment (mandatory)

A Step 7a summary comment **must always be posted to the PR** when the gate exits — whether all reviewers ran, some were skipped, or the gate hard-failed (BR-7). Post via `gh pr comment` immediately before `gh pr ready` (in the success path) or immediately before stopping (in the hard-fail or escalation paths).

Required fields:

- **PR type**: implementation (two-pass) or non-implementation (single-pass)
- **Effective reviewer set**: which reviewers actually ran (excluding skipped/unreachable ones)
- **Skipped reviewers**: each reviewer skipped, with reason (e.g., `unreachable`, `override-excluded`)
- **Final verdict**: `APPROVED`, `hard-fail`, or `escalated — <reason>`

Example format for a **non-implementation PR** (single-pass):

```markdown
### Step 7a Internal Review Gate Summary

**PR type**: Non-implementation (single-pass)
**Effective reviewer set**: claude
**Skipped reviewers**: codex (unreachable from Claude Code subagent)
**Verdict**: APPROVED

All reachable internal reviewers approved. Note: codex was unreachable from the current runner — reviewer coverage was reduced from 2 to 1. Human reviewers may re-run Step 7a from a Codex-capable runner if full coverage is required.
```

Example format for an **implementation PR** (two-pass):

```markdown
### Step 7a Internal Review Gate Summary

**PR type**: Implementation (two-pass)
**Effective reviewer set**: claude
**Skipped reviewers**: codex (unreachable from Claude Code subagent)

**Pass 1 (Spec Compliance)**

- claude: APPROVED (0 findings)

**Pass 2 (Code Quality)**

- claude: APPROVED after 1 fix cycle (1 finding resolved)

**Verdict**: APPROVED
All passes approved at commit `abc1234`.
```

In the hard-fail case (zero reachable reviewers or `fail-if-any-unavailable` policy triggered), the hard-fail comment posted in the Runtime-availability check section above **already satisfies BR-7** — do not post a second summary comment.

**Note**: The Step 7a summary comment is a distinct requirement from the Step 7 "Automated Reviewer Loop Summary" comment checked in Step 8c. The Step 7a summary covers the internal gate only; Step 8c's check targets the external automated reviewer loop (Step 7). These are separate comments and neither substitutes for the other.

### Step 7a loop parameters

| Parameter                    | Default | Description                                                                                                                                                                                                                                    |
| ---------------------------- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `max_internal_review_cycles` | 5       | Max fix cycles before escalating. For implementation PRs, increments on every Pass 2 fix — trivial (Pass 2 restart only) or non-trivial (full Pass 1 → Pass 2 restart). For non-implementation PRs, counts full single-pass restarts as before |

Step 7a runs **before** Step 7 (external reviewers). Only proceed to Step 7 once all internal reviewers in Step 7a produce `APPROVED`. After any fixer push triggered by Step 7 (external reviewers), re-run Step 7a (all internal reviewers) to ensure the stage-specific internal review gate is still clean — **unless the push qualifies as a trivial fix** (see "Trivial-fix skip rule" below).

### Trivial-fix skip rule

The trivial-fix skip rule applies in two distinct contexts within the orchestration loop:

**Context A — Pass 2 internal review (implementation PRs only)**: When a reviewer returns `NEEDS REVISION` on Pass 2 during Step 7a, the fixer applies a fix and pushes. If the fix is trivial (all three conditions below), the orchestrator skips the Pass 1 re-run and restarts from Pass 2 only. See the two-pass outcome table above.

**Context B — Step 7 fixer pushes (all PR types)**: When Step 7 (external reviewers) dispatches a fixer agent and the agent pushes a fix commit, the orchestrator normally re-runs Step 7a in full before proceeding. If the fix is trivial, the orchestrator skips the full Step 7a re-run and proceeds directly to Step 7. For implementation PRs, "full Step 7a re-run" means running both Pass 1 and Pass 2 again.

**Trivial-fix classification**: A fixer push qualifies as trivial if and only if **all** of the following conditions hold:

1. The fixer agent self-certifies that its changes are non-structural by including the phrase `TRIVIAL_FIX: non-structural` in its commit message or in its response to the orchestrator.
2. The diff contains **only** changes to plain text in string literals, comments, documentation prose, or inline numeric values — no logic, no control-flow, no added/removed function or variable declarations, no new imports, no structural markup changes (e.g., adding/removing table columns or list items in a protocol document).
3. The number of lines changed (additions + deletions) is 10 or fewer across the entire commit.

**When all three conditions are met (Context B)**: skip the Step 7a re-run and proceed directly to Step 7 (re-run the external automated reviewers on the new push). Post a one-line PR comment noting the skip:

> `Step 7a re-run skipped: fixer push classified as trivial (non-structural, ≤10 lines). Proceeding directly to Step 7.`

**When any condition is not met (Context B)**: re-run Step 7a in full as normal before proceeding to Step 7.

**Orchestrator verification**: The orchestrator must not rely solely on the fixer's self-certification. Before skipping (in either context), independently verify conditions 2 and 3 by inspecting the diff:

```bash
# Count changed lines and check for structural changes
git diff HEAD~1 HEAD --stat
git diff HEAD~1 HEAD -- .
```

If the diff includes any non-text change (e.g., new function, new import, changed conditional, structural markup change), override the fixer's self-certification and do not apply the trivial-fix skip.

**Scope of skip**: The initial Step 7a run (after a draft PR is opened) is always full and cannot be skipped. Step 7a re-runs triggered by Pass 1 findings (i.e., `internal_review_cycle > 0` for findings from Pass 1) are also never skipped.

---

## Step 7: Automated Reviewer Loop

If one or more automated code review platforms are configured (see [`integrations/pr-review-platform.md`](../integrations/pr-review-platform.md)), run this loop after **any push to a PR branch**. If no review platform is configured, skip this step and report `⏭️ skipped` in the Step 6 summary.

**Standalone use:** This step (and Step 8) can be run for a single PR without full orchestration — see [`93-automated-reviewer-loop-protocol.md`](93-automated-reviewer-loop-protocol.md) and the `/run-reviewer-loop` command (Cursor) or `automated-reviewer-loop` agent (Claude Code) or `workflow-reviewer-loop` skill (Codex).

**Important:** Run Step 7 **to completion** and use its result before running Step 8. Do not run Step 7 in the background while proceeding to Step 8. The review loop can take several minutes (poll interval × wait for bot). Only when the script exits with `clean` or `skipped` may you continue to Step 8.

The helper script evaluates configured platforms sequentially. For each platform it checks for **existing** blocking findings from the bot (e.g. from a review that already ran on PR open) before posting a new trigger. If it finds any, it exits with `needs_fixes` without moving on to later platforms — so the fixer addresses them first; after a push, the next run starts again from the first configured platform. Supported platforms include `greptile`, `devin`, `coderabbit`, and `codex-github` (Codex GitHub App — async bot reviewer handled deterministically by `pr-review-loop.sh`).

> **CodeRabbit silence patterns**: CodeRabbit occasionally does not respond after a push — either because reviews are auto-paused after many commits ("Reviews paused" comment) or because it silently fails to auto-trigger. `pr-review-loop.sh` handles both cases automatically by posting `@coderabbitai review`. If the loop appears stalled with no CodeRabbit activity, see the [CodeRabbit silence patterns section in Protocol 93](93-automated-reviewer-loop-protocol.md#coderabbit-silence-patterns) for diagnostic steps and escalation criteria before intervening manually.

Initialize `cycle = 0` once per orchestration run for the PR. Increment `cycle` each time a fixer agent is dispatched. Do not reset `cycle` after a fixer push; escalate when the run reaches `max_cycles`.

### PR feedback tracking and comments

Maintain a **PR feedback ledger** alongside the cycle counter. Each entry tracks:

| Field              | Description                                                                  |
| ------------------ | ---------------------------------------------------------------------------- |
| `id`               | Sequential integer assigned in discovery order                               |
| `platform`         | Review platform name (e.g. `greptile`, `devin`)                              |
| `path`             | File path                                                                    |
| `line`             | Line number (display-only — can shift between commits)                       |
| `body_snippet`     | First 120 chars of the finding body (used as matching key — line-shift-safe) |
| `discovered_cycle` | Cycle when first seen                                                        |
| `status`           | `open` · `resolved` · `unresolved`                                           |
| `resolved_commit`  | Short SHA (set when resolved)                                                |

**Matching key**: `(platform, path, body_snippet)` — not line number, since lines shift after fixes. If a finding looks like a restatement of existing open PR feedback (same platform, same file, similar description), match it rather than creating a duplicate.

**Ledger updates:**

- After each review run with `needs_fixes`: parse `BLOCKING_N_*` output, add new entries or leave existing open ones unchanged.
- After each fixer push + re-review: any open entry whose key no longer appears in the new output is marked `resolved` with the fixer's commit SHA.
- When the loop terminates: any still-open entry is marked `unresolved`.

#### Commit SHA verification (mandatory before marking resolved)

Before recording a `resolved_commit` SHA in any ledger entry and before posting the fix commit comment, the agent **must** verify that the cited commit actually exists in the repository:

```bash
git log --oneline | grep "^<short_sha>"
# or equivalently:
git rev-parse --verify <short_sha> 2>/dev/null && echo "exists" || echo "not found"
```

If the SHA is not found in `git log`, the agent must **not** record it as the `resolved_commit` and must **not** claim the finding is resolved. Instead, the agent must commit any staged or unstaged changes first, obtain the real commit SHA from `git log`, and then record that SHA:

```bash
# If changes exist but were never committed:
git add <changed-files>
git commit -m "<commit message>"
REAL_SHA=$(git log --oneline -1 | awk '{print $1}')
```

**Rationale**: An agent may edit files in a worktree and mentally track a planned commit SHA without ever running `git commit`. Recording a non-existent SHA in the ledger produces an audit trail that cannot be verified, misleads human reviewers who inspect the commit history, and can cause the PR to be labeled `ready-for-human-review` with uncommitted fixes. The verification step is the only reliable guard against this class of error.

**Escalation if commit fails**: If `git commit` fails (e.g., due to a pre-commit hook or empty diff), the agent must investigate and resolve the failure before marking any finding resolved. Do not silently skip the commit and record a fabricated SHA.

#### Fix commit comment

Post via `gh pr comment` immediately after updating the ledger following a fixer push:

```markdown
### Automated Fix: commit `<short_sha>`

Addressed **N** finding(s) from cycle M:

| #   | Platform | File            | Description               |
| --- | -------- | --------------- | ------------------------- |
| 1   | greptile | `src/foo.ts:42` | First 80 chars of body... |

<details><summary>Remaining open findings: K</summary>

| #   | Platform | File           | Description               |
| --- | -------- | -------------- | ------------------------- |
| 3   | greptile | `src/baz.ts:5` | First 80 chars of body... |

</details>
```

If 0 findings were resolved: post a shorter note — "Pushed fixes for cycle M. 0 findings resolved so far — re-running review to check."

#### Resolve inline review comments

After each fixer push, reply to each addressed inline review comment on the PR to mark it as resolved. Use `gh api` to post a reply to each comment whose ledger entry transitioned to `resolved`:

```bash
gh api "repos/{owner}/{repo}/pulls/<pr_number>/comments/<comment_id>/replies" \
  -f body="Fixed in commit \`<short_sha>\`."
```

This is **mandatory** — do not skip this step. Unresolved inline comments cause confusion when humans review the PR on GitHub, even if the underlying issue was already fixed. When delegating to a fixer subagent, include explicit instructions to reply to each addressed comment.

#### Final summary comment (script-owned for `clean` and `escalate`)

**`pr-review-loop.sh` automatically posts an "Automated Reviewer Loop Summary" PR comment on `clean`, `needs_fixes`, and `escalate` exits.** You do not need to post this comment manually for those exit paths. The comment body matches the regex used by `workflow-next-action.sh` and the Step 8c verification gate:

```
Automated Reviewer Loop Summary|Reviewer Loop Summary|No blocking PR feedback
```

The script updates the summary in place on `needs_fixes` exits, including non-terminal fix cycles, so stale clean summaries cannot mask active reviewer findings. `skipped` exits (no platforms configured) do not post a summary comment.

The script-posted comment format:

```markdown
### Automated Reviewer Loop Summary

**Result:** clean — no blocking findings | escalated (reason) | max cycles reached — N blocking finding(s) unresolved
**Platforms:** greptile, devin
**Findings:** N blocking, N suggestions
**Ready reviewer phase:** No net-new blocker was found after the draft GitHub gate.
**Ready-phase platforms:** haystack

_Posted automatically by `pr-review-loop.sh`._
```

### Draft GitHub gate before ready-phase reviewers

When `.ai-dev-workflow.yaml` contains `review.on_ready.github`, run the external
reviewer loop in two PR lifecycle phases:

Run the reviewer loop in two phases: keep the PR as draft and run
`review.on_draft.github` platforms (`--draft-github-only`) until they are clean,
then convert to non-draft with `gh pr ready` and run the full loop so
`review.on_ready.github` platforms see a clean-gated ready PR. The legacy
`--pre-after-clean-only` flag remains accepted as an alias for
`--draft-github-only` during the transition release. For the full runbook and
`READY_PHASE_*` telemetry details, see the **"Draft GitHub gate before
ready-phase reviewers"** section in
[`93-automated-reviewer-loop-protocol.md`](93-automated-reviewer-loop-protocol.md).

After running the helper script (it reads `.ai-dev-workflow.yaml` for the platform list automatically):

```bash
./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch <branch_name>
```

Interpret the result as follows:

| Result                                  | Action                                                                                                                                                                                                                                                                                                                                                                                     |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `clean`                                 | Summary comment posted automatically by the script. If `ADVISORY_LABELS` is non-empty, document a disposition for each advisory finding and update the summary comment before proceeding — see "Advisory finding dispositions" in `93-automated-reviewer-loop-protocol.md`. Then continue to Step 7b (implementation PRs) → Step 8 → **Step 8a** (which contains the mandatory GraphQL `reviewThreads` pre-Check-4 gate). **Do NOT apply `ready-for-human-review` directly from this step** — `clean` from the script only means no blocking inline comments or `CHANGES_REQUESTED` reviews were found; it does NOT mean all review threads are resolved. The GraphQL check in Step 8a is the authoritative gate. |
| `skipped`                               | Continue to Step 7b (implementation PRs) then Step 8 (no summary comment posted — Step 8c skips the check)                                                                                                                                                                                                                                                                                 |
| `needs_fixes` and `cycle < max_cycles`  | Summary comment posted or updated automatically by the script. Increment `cycle`, dispatch the matching fixer agent, wait for a push, then run Step 7 again                                                                                                                                                                                                                                |
| `needs_fixes` and `cycle >= max_cycles` | Summary comment posted or updated automatically by the script. Escalate to human                                                                                                                                                                                                                                                                                                          |
| `needs_rerun` (exit code 3)             | (Reserved — not currently emitted.) Treat as `escalate` if encountered unexpectedly.                                                                                                                                                                                                                                                                                                      |
| `escalate`                              | Summary comment posted automatically by the script. Escalate to human                                                                                                                                                                                                                                                                                                                      |

### PR-Agent "Possible Issue" advisory labels

When `pr-review-loop.sh` returns `RESULT=clean` with `ADVISORY_LABELS` containing
`Possible Issue` entries, PR-Agent flagged advisory concerns but no hard-blockers.
**No orchestrator action is required.** The script auto-acknowledges these findings
and exits clean. See `93-automated-reviewer-loop-protocol.md` for the full advisory
label disposition rules.

**Step 7a summary (Internal Review Gate) is still agent-owned.** The script-posted summary covers Step 7 (external automated reviewers) only. The Step 7a summary comment (`### Step 7a Internal Review Gate Summary`) must still be posted by the orchestrator/agent after the internal review gate completes. Do not conflate the two: they serve different verification purposes and are checked by different gates.

### Re-query reviewThreads after each push (mandatory)

**After every push that addresses reviewer feedback — including the push that causes `pr-review-loop.sh` to return `clean` — you MUST NOT apply `ready-for-human-review` before the GraphQL `reviewThreads` pre-Check-4 gate in Step 8a runs and passes.**

Do not rely on thread state observed before the push, and do not rely on the reviewer loop script's exit code as a thread-resolution signal. Bot reviewers (CodeRabbit, Devin, or any configured platform) may open new review threads within seconds of a push landing. Thread state cached from before the push will not include these new threads.

The required sequence after each fixer push is:

1. Push the fix commit.
2. Run `pr-review-loop.sh` (wait for bot response and poll for `clean` / `needs_fixes`).
3. **Re-issue the GraphQL `reviewThreads` query** (the same query in Step 8a's pre-Check-4 gate) to get the current thread state for the latest push.
4. If new unresolved threads are found: treat this as `needs_fixes` — handle them (dispatch a fixer or resolve via reply), then repeat from step 1.
5. Only when the re-issued query returns no unresolved bot-authored threads: proceed to Step 7b (implementation PRs) then Step 8.

**This check is not optional and cannot be skipped, even when the review loop script reported `clean`.** The script checks review state (blocking inline comments and `CHANGES_REQUESTED` reviews), not the resolved/unresolved state of `reviewThreads`. New threads created by a push may appear after the script's poll window closes. The GraphQL query is the only authoritative source for thread resolution state.

> **Critical — `clean` does not mean threads are resolved**: The reviewer loop script (`pr-review-loop.sh`) classifies some CodeRabbit findings as advisory/non-blocking and exits `clean` without requiring those threads to be marked resolved. An agent that equates `RESULT=clean` with "all threads resolved" will apply `ready-for-human-review` while unresolved threads remain on the PR. Always treat the GraphQL `reviewThreads` query result as the sole authoritative signal for thread resolution state — never the script exit code.

### Blocking vs. suggestion classification

When an automated review platform returns inline comments, classify them before deciding whether the PR needs fixes.

- Treat a comment as a **soft suggestion** only when every non-empty, non-code line starts with an advisory prefix such as `Consider`, `You might`, `An alternative`, `Optionally`, `It could be cleaner to`, `Perhaps`, `Maybe`, `You could`, `One option is`, or `Alternatively`.
- Treat any other inline comment as **blocking**.
- Treat `CHANGES_REQUESTED` reviews from any automated reviewer as **blocking**. Treat `COMMENTED` reviews from Devin as **blocking** when the body starts with `**Devin Review**` OR when the review is accompanied by unresolved inline PR review comments from `devin-ai-integration[bot]`; a `COMMENTED` Devin review is non-blocking only when neither condition holds. For other platforms, `COMMENTED` reviews are not automatically blocking. See `93-automated-reviewer-loop-protocol.md` for full Devin blocking classification rules.

Soft suggestions may be reported in summaries, but they do not change the loop result to `needs_fixes`. Any blocking finding does.

### Inline fix rule (attempt before sub-agent dispatch)

Before dispatching a fixer sub-agent, check whether ALL blocking findings are **mechanical** — meeting every one of these criteria:

1. **Single file across the batch**: all blocking findings reference the **same single file** (one file total across the batch — not one file per finding). If two findings name two different files, the inline path does not apply; dispatch a sub-agent.
2. **Fully described**: each finding's body completely and unambiguously specifies the change (e.g., "replace `grep '^\s*'` with `grep '^[[:space:]]*'`", "add `--limit 100` to the `gh issue list` call", "remove the `states:OPEN` argument").
3. **Small scope**: the total estimated change across all blocking findings is ≤ 5 lines.

**When ALL criteria are met — apply the fixes directly** in the current session using Edit/Bash tools:

1. Apply every blocking finding in one pass (follow the batching rule: all in one commit).
2. Commit with a descriptive message (e.g., `fix: address [platform] findings inline ([brief description])`).
3. Push the commit. _(Push before resolving threads — if push fails, threads must not be falsely marked resolved.)_
4. Reply to each finding's review thread with the fix description and commit SHA.
5. Resolve each addressed thread via the GraphQL `resolveReviewThread` mutation.
6. **Increment `cycle`** (the same counter used in the sub-agent loop). Inline fix retries are bounded by `max_cycles` exactly like sub-agent retries — the inline path is a faster lane, not an unbounded one.
7. Run `pr-review-loop.sh` again from the top of Step 7. If it returns `clean`, proceed normally. If the loop still reports unresolved blocking findings **and** `cycle >= max_cycles`, escalate to human (the just-pushed fix is always given a chance to be verified before escalating).

**Do not dispatch a sub-agent for mechanical findings.** Sub-agent startup overhead (context loading, planning) typically costs 10–20 minutes for changes that take 30 seconds to apply directly.

**When ANY criterion fails** — fall through to the sub-agent dispatch path below. The inline path is a fast lane, not a mandatory gate. When in doubt about whether a finding is fully described or single-file, dispatch the sub-agent.

**Fixing agent by PR branch type:**

| PR branch prefix                                  | Compatibility fixer to dispatch when direct fixes are needed |
| ------------------------------------------------- | ------------------------------------------------------------ |
| `spec/*`                                          | `spec-reviewer`                                              |
| `implementation-plan/*`                           | `implementation-plan-reviewer`                               |
| `feature/*` / `refactor/*` / `fix/*` / `hotfix/*` | `code-reviewer`                                              |

**Fixer agent worktree isolation rule (mandatory for parallel batches):**

When this Work Item Runner was dispatched as part of a parallel batch (`BATCH_CONTEXT=true`), all fixer agents dispatched from this step **must** receive `BATCH_CONTEXT=true` and the resolved `<worktree-path>` in their handoff. Fixer agents that run without these values will use main-repo absolute file paths in `Read`/`Edit`/`Write` calls while committing via the worktree git context — causing their changes to be written to the main working tree and left uncommitted on the integration branch instead of on the isolated feature branch.

Required fixer handoff values (parallel batches only):

- `BATCH_CONTEXT=true`
- `WORKTREE_PATH=<resolved-absolute-worktree-path>` — the same path used when this item was first dispatched
- The explicit branch-skip instruction: "BATCH_CONTEXT=true — the worktree is already on branch `<branch>`. Do NOT run `git checkout develop`, `git checkout -b`, `git switch`, `git reset`, or `git restore` from the main repo root."

**Fixer agent batching rule (mandatory):**

When dispatching a fixer agent, include the following explicit instruction:

> **Critical batching rule**: Do NOT address findings one-by-one with a separate push after each fix. Reviewer bots (e.g. Devin) start a new review cycle within 5–8 minutes of each push. If you push before all addressable fixes are done, the reviewer will start re-reviewing stale state while you are still working — creating a "one cycle behind" loop that can spin for dozens of cycles.
>
> Required sequence for every fixer dispatch:
>
> 1. **Read ALL blocking findings first** — before touching any file, collect the complete list of open blocking findings from the current review cycle.
> 2. **Apply ALL addressable fixes** — implement every fix you can address in this dispatch, across all files.
> 3. **One commit, then push** — bundle every fix into a single commit and push once. Do not push after each individual fix.
>
> Findings that cannot be addressed in this dispatch (e.g. require a human decision, are out of scope, or are genuinely contradictory) should be noted and left for human review. Do not skip a push just because one finding is unresolvable — push the rest.

### Attempt-context injection rule (Step 7 fixer dispatch)

This rule governs what the orchestrator prepends to the fixer agent's prompt on each
dispatch. It applies to fixer agents dispatched from this step only (Step 7 external
automated reviewers); Step 7a (internal review gate) fixer cycles are unaffected.

**First dispatch (cycle = 1)**

No attempt-context prefix is added. The fixer receives only the standard
blocking-findings list and the batching rule above.

**Retry dispatches (cycle ≥ 2)**

Before dispatching the fixer, the orchestrator prepends an attempt-context header
to the fixer's prompt using the following format:

> Attempt N/M: prior attempt(s) tried [per-attempt summaries]. The following findings
> remain open: [standard blocking-findings list]. Try a different approach for each
> remaining finding.

Where:

- `N` = the current `cycle` value (matches the loop's `cycle` counter exactly)
- `M` = `max_cycles` (the loop escalation limit — default: 10)
- `[per-attempt summaries]` = one entry per prior dispatch, each one-to-two plain-language
  sentences describing what that attempt changed and which findings it addressed or left
  open. Derive each entry from the PR feedback ledger and the fixer's commit message /
  response for that cycle.
- `[standard blocking-findings list]` = the same findings list passed in any dispatch —
  the attempt-context prefix does not replace it

**Accumulating summaries across retries**

For cycle N, include summaries for all N-1 prior attempts, not only the most recent.
Each entry should be keyed to its cycle number for clarity:

> Attempt 1: rewrote the `foo()` function signature in `bar.sh`; MD009 trailing-space
> finding on line 42 remained open.
> Attempt 2: removed trailing space on line 42; `relative-links` finding on `baz.md`
> remained open.

**Fallback when no prior-attempt summary is available**

If no summary was recorded for a prior attempt (e.g., the fixer did not respond or
the attempt had no ledger entries), use the minimal fallback:

> Attempt N/M: prior attempt did not fully resolve all findings. Try a different approach.

**Reappearance notation**

When a finding that was marked `resolved` in a prior cycle reappears in the current
ledger (same `(platform, path, body_snippet)` key, status reverted to `open`), the
per-attempt summary for the cycle in which it was "resolved" must note the reappearance:

> Attempt 2: removed trailing space on line 42 (fix did not hold — finding reappeared
> in cycle 3).

**In-session state only**

Attempt summaries live in the orchestrator's in-session state for the duration of the
PR's review loop. They are not persisted to disk or to any external tracker. They are
discarded when the orchestration session ends.

### Loop parameters

| Parameter       | Value  | Description                                                        |
| --------------- | ------ | ------------------------------------------------------------------ |
| `poll_interval` | 2 min  | Time to wait between review status checks                          |
| `max_wait`      | 20 min | Max wait **per fix cycle** for the reviewer to respond             |
| `max_cycles`    | 10     | Max number of times a fixing agent is dispatched before escalating |

---

## Step 7b: Regression Label (Implementation PRs Only)

After Step 7 completes with result `clean` or `skipped`, and **before** entering Step 8, apply the `ready-for-regression` label on implementation PRs to trigger label-gated e2e/regression CI checks.

**Applies to**: PRs on branches `feature/*`, `fix/*`, `refactor/*`, `hotfix/*`, `backport/hotfix/*`
**Does not apply to**: PRs on branches `spec/*`, `implementation-plan/*`, or graduation PRs (`develop-<slug>` → `develop`) — see the label derivation table in Step 8a for the graduation PR exemption (BR-6)

> **`refactor/*` is not exempt**: `refactor/*` branches require `ready-for-regression` exactly like `fix/*` and `feature/*` branches. Refactors that reach `ready-for-human-review` without this label will bypass e2e/regression CI. Apply the label unconditionally for any `refactor/*` PR — do not infer exemption from the content of the refactor (e.g., "it's documentation-only" or "it changes no logic").

**`BATCH_CONTEXT=true` — this step is mandatory and must not be skipped in parallel dispatch**: When agents are dispatched with `BATCH_CONTEXT=true`, they follow a compressed execution path (worktree isolation, branch-skip rules, reduced context). Step 7b is a required step in that path and must be executed **between Step 7 and Step 8** without exception for **all** implementation branch types (`feature/*`, `fix/*`, `refactor/*`, `hotfix/*`, `backport/hotfix/*`). The orchestrator's Step 5.1 catches a missing label at the end of the batch, but the agent is the primary responsible party and must not rely on Step 5.1 as a fallback.

```bash
# Only for implementation PRs:
gh pr edit <pr_number> --add-label "ready-for-regression"
```

This label triggers the `e2e-regression.yml` workflow (or project-specific equivalents). Step 8's CI loop (`pr-ci-loop.sh`) will then naturally pick up the e2e check as part of its green/red polling via `statusCheckRollup`.

The `gh pr edit --add-label` command is idempotent — applying a label that already exists is a no-op. When the label is already present from a previous cycle, the `synchronize` event from the latest push will have already re-triggered the workflow.

Skip this step entirely for spec and plan PRs, and for graduation PRs (`develop-<slug>` → `develop`).

### Step 7b completion confirmation

After applying the label, **verify it was applied successfully** before proceeding to Step 8:

```bash
# Verify ready-for-regression label is present (implementation PRs only):
gh pr view <pr_number> --json labels --jq '.labels[].name' | grep -q "^ready-for-regression$" && echo "✅ Step 7b complete: ready-for-regression label verified"
```

If the verification fails (label not present), do not proceed to Step 8. Re-run the `gh pr edit --add-label` command and verify again. This confirmation is required — Step 8a will block on a missing label and force a CI loop re-run, wasting cycles.

See [`integrations/e2e-regression.md`](../integrations/e2e-regression.md) for the full integration guide, including downstream customization.

---

## Step 8: CI Loop

**Guardrails check — delegated merge gate**: After the CI loop and readiness
checks complete (Step 8a), before merging, apply the delegated merge gate from
`guardrails-enforcement.md` section 3 Gate 5. When `stages.<stage>.may_merge_pr`
is `true` in the effective guardrails, assemble the evidence object and run:

```bash
./scripts/development-workflow/run-epic-risk-classifier.sh \
  --pr <pr-number> --max-risk <stages.<stage>.max_merge_risk>

./scripts/development-workflow/run-epic-delegated-gate.sh --input <evidence-file>
```

Merge only when the gate returns `merge_allowed` **and** every required-evidence
check in section 3 Gate 5 of `guardrails-enforcement.md` passes. For medium-risk
decisions, include a complete "why safe to merge" explanation. A risk classified
above the stage `max_merge_risk` stops the run and names the `high_risk_change`
guardrail. When `may_merge_pr` is `false`, do not merge automatically — leave the
PR at the `ready-for-human-review` handoff.

**Only after Step 7 (and Step 7b for implementation PRs) has completed**, wait for required checks to settle.

Prefer the helper script:

```bash
./scripts/development-workflow/pr-ci-loop.sh <pr_number>
```

Interpret the result as follows:

| Result    | Action                                                                                                         |
| --------- | -------------------------------------------------------------------------------------------------------------- |
| `green`   | Proceed to Step 8a (label readiness checklist) → Step 8b (tracker status) → Step 8c (independent verification) |
| `red`     | Apply `needs-fixes`, dispatch the matching fixer agent, wait for a push, then return to Step 7                 |
| `timeout` | Escalate to human; do not apply `ready-for-human-review`                                                       |

---

## Step 8a: Label Readiness Checklist (Hard Gate)

**Before applying `ready-for-human-review`**, verify all required readiness conditions are met. This is a hard gate — do not skip or defer.

> **Warning — `pr-review-loop.sh clean` does NOT authorize applying `ready-for-human-review`**: A `clean` exit from the reviewer loop script means no blocking inline comments or `CHANGES_REQUESTED` reviews were detected. It does NOT mean all review threads are resolved. The GraphQL `reviewThreads` pre-Check-4 gate below (exit code 4) is the only authoritative check for thread resolution state. Agents that skip this gate and apply the label based solely on the script's `clean` result will leave unresolved bot-authored threads on the PR. Run this checklist in full every time — including the GraphQL pre-Check-4 gate — regardless of what Step 7 reported.

### Exit code contract

| Exit Code | Meaning                                                                                          | Action                                              |
| --------- | ------------------------------------------------------------------------------------------------ | --------------------------------------------------- |
| 0         | PR is ready (CI green, non-draft, regression label verified for implementation PRs, no unresolved threads) | Apply `ready-for-human-review`               |
| 1         | PR is still in draft                                                                             | Run `gh pr ready` first                             |
| 2         | `ready-for-regression` label applied this run                                                    | Re-run Step 8 (pr-ci-loop.sh) before returning here |
| 3         | `ready-for-regression` label missing at pre-Check-4 gate                                         | Apply label, re-run Step 8                          |
| 4         | Unresolved review threads at pre-Check-4 gate                                                    | Resolve threads, push fixes, re-run checklist       |
| 5         | CI not green at readiness gate                                                                    | Run Step 8 (pr-ci-loop.sh) and fix failing checks   |
| 6         | Late-arriving async bot threads detected after label application                                  | Remove `ready-for-human-review`, add `needs-fixes`, return to Step 7a |
| 7         | Latest reviewer-loop summary is missing or has a non-clean terminal result                       | Do not label ready; escalate or return to reviewer loop |

When adding a new gate to this checklist, allocate the next unused exit code and update this table. Exit codes must not collide.

> **Critical**: For implementation PRs (`feature/*`, `fix/*`, `refactor/*`, `hotfix/*`, `backport/hotfix/*`), you **must** confirm that `ready-for-regression` was applied in Step 7b **before** reaching this checklist. If it was not, apply it now (see Check 2 below) — do not proceed to `ready-for-human-review` without it. The orchestrator's Step 5.1 will catch and correct a missing `ready-for-regression` label, but the agent is the primary responsible party and must not rely on the orchestrator as a fallback.

### Label derivation rule

Required labels are determined by the **branch prefix**, not by the content of the PR (e.g., whether it changes code vs. documentation). An agent must never infer labels from what was changed inside the PR.

| Branch prefix                                    | Requires `ready-for-regression` | When to apply                                                                                                                                                    |
| ------------------------------------------------ | ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `feature/*`                                      | Yes                             | Step 7b (before Step 8); confirmed here in Step 8a Check 2                                                                                                      |
| `fix/*`                                          | Yes                             | Step 7b (before Step 8); confirmed here in Step 8a Check 2                                                                                                      |
| `refactor/*`                                     | Yes                             | Step 7b (before Step 8); confirmed here in Step 8a Check 2                                                                                                      |
| `hotfix/*`                                       | Yes                             | Step 7b (before Step 8); confirmed here in Step 8a Check 2                                                                                                      |
| `backport/hotfix/*`                              | Yes                             | Step 7b (before Step 8); confirmed here in Step 8a Check 2. See Protocol 03 Path 4 backport readiness steps.                                                    |
| `spec/*`                                         | No                              | —                                                                                                                                                                |
| `implementation-plan/*`                          | No                              | —                                                                                                                                                                |
| `develop-<slug>` (graduation PR, base `develop`) | No — explicitly exempt (BR-6)   | Graduation PRs carry no new implementation; label not required. Do not log the absence as a protocol deviation. See `05b-graduate-development-protocol.md` Step 4. |

Any branch that does not match a recognized prefix above — **other than graduation branches (`develop-<slug>` → `develop`, which are a known and expected non-implementation PR type)** — is treated as non-implementation (i.e., `ready-for-regression` is NOT required), but should be treated as a configuration anomaly and reported to the human.

### Infrastructure Dependency Scan (pre-readiness)

Before running the readiness checklist below, perform a best-effort scan of the PR diff to detect infrastructure dependencies that require human setup before the feature can be safely enabled. This scan runs on **every pass through Step 8a** — including after fixer pushes — so the label and PR body section always reflect the current diff (BR-6).

**Timing**: Run after CI is green and all automated reviewer loops are clean (Step 7 complete), but before applying `ready-for-human-review`. The scan result does **not** block readiness — `needs-setup` co-exists with `ready-for-human-review` (BR-3, BR-4).

**Scan procedure**:

1. Read the PR diff:

   ```bash
   gh pr diff <pr_number>
   ```

2. Scan the diff for infrastructure dependency signals on **added lines** (lines starting with `+`). The following heuristics are best-effort and intentionally incomplete (BR-9 — false negatives are acceptable):
   - **New environment variable references**: added lines matching patterns like `process.env.NEW_VAR`, `os.environ["NEW_VAR"]`, `$NEW_VAR` in shell scripts, or new entries added to `.env.example`, `.env.template`, or similar env-template files.
   - **New GitHub Actions secret references**: added lines in `.github/workflows/**` files that reference `${{ secrets.NEW_SECRET }}`.
   - **New config key additions to environment-specific config files**: added keys in files named `*.env`, `.env.*`, `config/production.*`, or similar deployment-configuration files.
   - **Explicit setup TODO comments added in the diff**: added comments containing phrases like `# TODO: set`, `# Set this to`, `# Required: configure`, or similar that indicate a value must be externally provided.

3. **If one or more signals are found**:

   a. Construct a `## Pre-merge Setup` section listing each detected requirement with (BR-8):
   - Requirement name
   - Type (e.g., environment variable, GitHub Actions secret, DNS record, service account token)
   - Plain-language description of the expected value
   - Where to set it (e.g., GitHub Actions secrets, Railway environment, DNS provider)

   b. Replace any existing `## Pre-merge Setup` section in the PR body with the newly constructed one, then update the PR body. This step runs on every pass through Step 8a (including after fixer pushes), so the section must always reflect the current diff — never accumulate stale or duplicate sections:

   ```bash
   # Remove any existing ## Pre-merge Setup block (from header to next ## heading or EOF),
   # then append the updated block at the end of the cleaned body.
   CURRENT_BODY=$(gh pr view <pr_number> --json body --jq '.body')
   CLEANED_BODY=$(echo "$CURRENT_BODY" | python3 -c "
   import sys, re
   body = sys.stdin.read()
   # Remove existing ## Pre-merge Setup section (from the heading to next ## heading or end of string)
   body = re.sub(r'\n## Pre-merge Setup\n.*?(?=\n## |\Z)', '', body, flags=re.DOTALL)
   print(body.rstrip())
   ")
   UPDATED_BODY="${CLEANED_BODY}

   ## Pre-merge Setup
   <requirements list>"
   gh pr edit <pr_number> --body "$UPDATED_BODY"
   ```

   c. Apply the `needs-setup` label (BR-1 — the label must always accompany the section):

   ```bash
   gh pr edit <pr_number> --add-label "needs-setup"
   ```

   **Note**: The `needs-setup` GitHub label must exist in the repository's label settings before this step can succeed. Suggested color: `#fbca04` (yellow). If the label does not exist, create it in the repository's **Issues → Labels** settings first.

4. **If no signals are found**:

   Ensure `needs-setup` is not present and no `## Pre-merge Setup` section exists in the PR body. If either is present from a prior scan (e.g., a previous commit introduced an env var that has since been removed), remove them:

   ```bash
   # Remove label only if it is currently present (avoids silencing real API/auth errors)
   HAS_SETUP_LABEL=$(gh pr view <pr_number> --json labels --jq '.labels[].name' | grep -c "^needs-setup$" || true)
   if [ "$HAS_SETUP_LABEL" -gt 0 ]; then
     gh pr edit <pr_number> --remove-label "needs-setup"
   fi

   # Remove the ## Pre-merge Setup section from the PR body if present
   # (Read body, strip the section and all content until the next ## heading or EOF, write back)
   CURRENT_BODY=$(gh pr view <pr_number> --json body --jq '.body')
   CLEANED_BODY=$(echo "$CURRENT_BODY" | python3 -c "
   import sys, re
   body = sys.stdin.read()
   body = re.sub(r'\n## Pre-merge Setup\n.*?(?=\n## |\Z)', '', body, flags=re.DOTALL)
   print(body.rstrip())
   ")
   gh pr edit <pr_number> --body "$CLEANED_BODY"
   ```

5. After the scan: proceed to the readiness checklist below. The presence of `needs-setup` is a valid co-label with `ready-for-human-review` and does **not** block this checklist or prevent `ready-for-human-review` from being applied (BR-3). The checklist script does not check for or remove `needs-setup` — it is a deliberate signal, not a stale label.

### Human Checkpoint Label Sync (pre-readiness)

When the run carries an effective checkpoint policy (`checkpoints[]` on the epic
invocation policy or a `checkpoint-policy.json` file saved at policy selection
time), synchronize the `human-checkpoint-required` label and stable PR comment
**after** CI and automated review are clean and **before** applying
`ready-for-human-review`. This runs on every pass through Step 8a — including
after fixer pushes — so label state always reflects current checkpoint
satisfaction.

**Timing**: Run after the infrastructure dependency scan above and before Check
4 (`ready-for-human-review` application) in the readiness checklist.

**Procedure**:

1. Resolve the linked work item number (`ITEM_NUMBER`) and branch name
   (`BRANCH`) for the PR.
2. Locate the effective checkpoint policy JSON array (from epic handoff metadata,
   `checkpoint-policy.json` in the run working directory, or
   `invocation_policy.effective_policy.checkpoints`).
3. Detect satisfaction from human signals and sync labels:

   ```bash
   ./scripts/development-workflow/run-epic-checkpoint-lifecycle.sh sync-pr-labels \
     --pr "$PR_NUMBER" \
     --item "$ITEM_NUMBER" \
     --branch "$BRANCH" \
     --checkpoints-file checkpoint-policy.json \
     --write-checkpoints-file checkpoint-policy.json
   ```

4. When `BLOCKING_COUNT` is greater than zero, apply `ready-for-human-review`
   **and** keep `human-checkpoint-required` (both labels may coexist per
   protocol 92 BR-11/BR-3). Record checkpoint reason and required human action
   in the `<!-- run-epic:checkpoint-status -->` comment posted by the script.
5. When all applicable checkpoints are `satisfied` or `waived`, the script
   removes `human-checkpoint-required` automatically.
6. During fix cycles (Step 9): when applying `needs-fixes`, do **not** remove
   `human-checkpoint-required` while checkpoints remain `pending`.

**Skip condition**: When no checkpoint policy is in scope for this run (no
`checkpoints[]` and no `checkpoint-policy.json`), skip this subsection.

Run this checklist for **every PR**:

```bash
PR_NUMBER=<pr_number>
BRANCH=<branch_name>  # e.g., feature/foo, spec/bar, fix/baz

# Determine PR type (implementation vs. spec/plan)
case "$BRANCH" in
  feature/*|fix/*|hotfix/*|refactor/*|backport/hotfix/*)
    IS_IMPLEMENTATION_PR=true
    ;;
  spec/*|implementation-plan/*)
    IS_IMPLEMENTATION_PR=false
    ;;
  *)
    IS_IMPLEMENTATION_PR=false
    echo "WARNING: Branch '$BRANCH' does not match a recognized prefix (feature/*, fix/*, refactor/*, hotfix/*, backport/hotfix/*, spec/*, implementation-plan/*). Treating as non-implementation PR. Report this anomaly to the human."
    ;;
esac

# Check 0: CI must be green on the PR's head SHA.
# This is a hard gate — do NOT apply ready-for-human-review when any check is
# failing or still pending. Run Step 8 (pr-ci-loop.sh) first if CI is not green.
HEAD_SHA=$(gh pr view "$PR_NUMBER" --json headRefOid --jq '.headRefOid')
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
CI_FAILING=$(gh api "repos/$REPO/commits/$HEAD_SHA/check-runs" \
  --jq '[.check_runs[] | select(.status == "completed" and .conclusion != "success" and .conclusion != "skipped" and .conclusion != "neutral")] | length')
CI_PENDING=$(gh api "repos/$REPO/commits/$HEAD_SHA/check-runs" \
  --jq '[.check_runs[] | select(.status != "completed")] | length')
if [ "$CI_FAILING" -gt 0 ] || [ "$CI_PENDING" -gt 0 ]; then
  echo "ERROR: CI is not green — ${CI_FAILING} failing and ${CI_PENDING} pending check(s) on $HEAD_SHA."
  echo "Run Step 8 (pr-ci-loop.sh) and resolve all failures before applying ready-for-human-review."
  exit 5  # Exit code 5 = "CI not green at readiness gate"
fi
echo "✅ CI is green on $HEAD_SHA."

# Check 0.5: latest automated reviewer-loop summary must be clean or skipped.
# A non-clean terminal result such as RESULT=escalate, needs_fixes, timeout, or
# pending_timeout must never advance to ready-for-human-review, even if CI is green.
if ! LOOP_SUMMARY_BODY=$(gh pr view "$PR_NUMBER" --json comments --jq '
  [.comments[]
   | select(.body | test("Automated Reviewer Loop Summary|Reviewer Loop Summary|No blocking PR feedback"))]
  | sort_by(.createdAt)
  | last
  | .body // ""); then
  echo "ERROR: Cannot verify automated reviewer-loop result — gh pr view failed."
  echo "Retry the GitHub query or resolve the CLI/API failure before applying ready-for-human-review."
  exit 7  # Exit code 7 = "reviewer-loop summary missing or non-clean"
fi
if [ -z "$LOOP_SUMMARY_BODY" ]; then
  echo "ERROR: Cannot verify automated reviewer-loop result — no reviewer-loop summary comment found."
  echo "Run Step 7 (pr-review-loop.sh) before applying ready-for-human-review."
  exit 7  # Exit code 7 = "reviewer-loop summary missing or non-clean"
fi
if echo "$LOOP_SUMMARY_BODY" | grep -Eiq '(^|[*[:space:]])Result:([*[:space:]])*(clean|skipped)([[:space:]—.,;:)]|$)|No blocking PR feedback'; then
  echo "✅ Automated reviewer-loop summary result is clean/skipped."
else
  echo "ERROR: Latest automated reviewer-loop summary is not clean/skipped."
  echo "RESULT=escalate or any non-clean terminal reviewer-loop result MUST NOT apply ready-for-human-review."
  echo "Escalate to the human or return to the reviewer loop according to Step 7."
  exit 7  # Exit code 7 = "reviewer-loop summary missing or non-clean"
fi

# Check 1: PR is non-draft
DRAFT=$(gh pr view "$PR_NUMBER" --json isDraft --jq '.isDraft')
if [ "$DRAFT" = "true" ]; then
  echo "ERROR: PR is still a draft. Run 'gh pr ready $PR_NUMBER' first."
  exit 1
fi

# Check 2: ready-for-regression label applied (implementation PRs only)
# IMPORTANT: This label MUST have been applied in Step 7b before Step 8 ran.
# If it is missing here, apply it now, log the deviation, and RE-RUN Step 8
# (pr-ci-loop.sh) before continuing — the label triggers e2e/regression CI and
# that workflow MUST be waited upon. Do NOT skip directly to Check 3/4.
if [ "$IS_IMPLEMENTATION_PR" = "true" ]; then
  HAS_REGRESSION_LABEL=$(gh pr view "$PR_NUMBER" --json labels --jq '.labels[].name' | grep -c "^ready-for-regression$" || true)
  if [ "$HAS_REGRESSION_LABEL" -eq 0 ]; then
    echo "WARNING: Implementation PR is missing 'ready-for-regression' label — Step 7b was not completed before Step 8."
    echo "Applying 'ready-for-regression' label now and logging as protocol deviation."
    gh pr edit "$PR_NUMBER" --add-label "ready-for-regression"
    echo "PROTOCOL_DEVIATION: ready-for-regression was missing on PR #${PR_NUMBER} at Step 8a — applied by agent. Step 7b must be run before Step 8 in future cycles."
    echo "Re-running Step 8 CI loop to wait for the e2e/regression workflow triggered by the label..."
    # EXIT this checklist script and re-run Step 8 before returning here.
    # The caller (orchestrator or agent) MUST run pr-ci-loop.sh again and only
    # re-enter Step 8a once CI is green.
    exit 2  # Exit code 2 = "label applied, re-run Step 8 required"
  fi
fi

# Check 3: needs-fixes label — remove if present (stale at this point: CI is green and reviews are clean)
HAS_NEEDS_FIXES=$(gh pr view "$PR_NUMBER" --json labels --jq '.labels[].name' | grep -c "^needs-fixes$" || true)
if [ "$HAS_NEEDS_FIXES" -gt 0 ]; then
  echo "INFO: Removing stale 'needs-fixes' label (CI is green and reviews are clean)."
  gh pr edit "$PR_NUMBER" --remove-label "needs-fixes"
fi

# ⛔ STOP — Mandatory pre-Check-4 verification (implementation PRs only)
# Do NOT proceed to Check 4 until you have explicitly verified ready-for-regression is present.
# This verification is REQUIRED even if you believe Step 7b was completed — agents under token
# pressure have skipped Step 7b in past batches, causing PRs to be labeled ready-for-human-review
# without the regression label and bypassing e2e/regression CI.
if [ "$IS_IMPLEMENTATION_PR" = "true" ]; then
  echo "⛔ STOP: Verifying ready-for-regression label before applying ready-for-human-review..."
  REGRESSION_PRESENT=$(gh pr view "$PR_NUMBER" --json labels --jq '.labels[].name' | grep -c "^ready-for-regression$" || true)
  if [ "$REGRESSION_PRESENT" -eq 0 ]; then
    echo "ERROR: Cannot proceed to Check 4 — ready-for-regression label is NOT present."
    echo "You MUST apply ready-for-regression (Step 7b) and re-run pr-ci-loop.sh (Step 8) before continuing."
    exit 3  # Exit code 3 = "ready-for-regression missing at pre-Check-4 gate"
  fi
  echo "✅ ready-for-regression verified present."
fi

# ⛔ STOP — Mandatory GraphQL reviewThreads verification (all PRs with configured review platforms)
# Do NOT proceed to Check 4 until you have explicitly verified all review threads are resolved.
# This verification is REQUIRED even if you believe your internal tracking shows all threads resolved —
# agents have bypassed this check in past batches by asserting reviews were "clean" based on self-
# tracking rather than querying the API, causing PRs to be labeled ready-for-human-review with
# unresolved blocking findings.
#
# NOTE: Skip this check ONLY when Step 7 was 'skipped' because no review platforms are configured.
echo "⛔ STOP: Verifying all review threads are resolved via GraphQL before applying ready-for-human-review..."
CODEX_BOT_LOGIN="${CODEX_GITHUB_BOT_LOGIN:-chatgpt-codex-connector[bot]}"
# GraphQL author.login omits the "[bot]" suffix present in REST API logins; strip it.
CODEX_BOT_LOGIN="${CODEX_BOT_LOGIN%\[bot\]}"
JQ_FILTER="[.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved == false)
        | select((.isOutdated // false) == false)
        | select(.comments.nodes[0].author.login as \$a | [\"coderabbitai\",\"devin-ai-integration\",\"greptile-apps\",\"$CODEX_BOT_LOGIN\"] | index(\$a) != null)
        | select((.comments.nodes[0].body // \"\") | test(\"✅ Addressed\") | not)] | length"
UNRESOLVED_COUNT=$(gh api graphql -f query='
  query($owner:String!, $repo:String!, $number:Int!) {
    repository(owner:$owner, name:$repo) {
      pullRequest(number:$number) {
        reviewThreads(first: 100) {
          nodes { isResolved isOutdated comments(first: 1) { nodes { author { login } body } } }
        }
      }
    }
  }' -f owner="<owner>" -f repo="<repo>" -F number="$PR_NUMBER" \
  --jq "$JQ_FILTER")

if [ "$UNRESOLVED_COUNT" -gt 0 ]; then
  echo "ERROR: Cannot proceed to Check 4 — $UNRESOLVED_COUNT unresolved review thread(s) found."
  echo "You MUST resolve all bot-authored review threads before applying ready-for-human-review."
  echo "Run the GraphQL query from Step 8c to identify unresolved threads, address them, push fixes,"
  echo "and re-run this checklist from the beginning."
  exit 4  # Exit code 4 = "unresolved review threads at pre-Check-4 gate"
fi
echo "✅ GraphQL verification: all review threads resolved. Proceeding to Check 4."

# Check 4: ready-for-human-review label NOT yet applied (we are about to apply it)
HAS_HUMAN_REVIEW_LABEL=$(gh pr view "$PR_NUMBER" --json labels --jq '.labels[].name' | grep -c "^ready-for-human-review$" || true)
if [ "$HAS_HUMAN_REVIEW_LABEL" -gt 0 ]; then
  echo "INFO: PR already has 'ready-for-human-review' label. Skipping re-application."
else
  echo "Applying 'ready-for-human-review' label..."
  gh pr edit "$PR_NUMBER" --add-label "ready-for-human-review"
fi

echo "✅ Label readiness checklist passed. PR is ready for human review."
```

### 8a.1: Async Bot Thread Re-check (Mandatory for async review platforms)

**When to run this substep:**

- After the label readiness checklist passes (all checks = exit 0)
- Before proceeding to Step 8b
- Only when `review.on_draft.github` or `review.on_ready.github` in `.ai-dev-workflow.yaml` includes `codex-github` or any other known async-posting review bot

**Why this substep exists:**
Review bots like the Codex GitHub App (`codex-github`) post `reviewThreads` asynchronously. A thread can arrive **after** the Step 8a pre-Check-4 GraphQL verification described in the label readiness checklist but **before** or **during** the Step 8c post-label verification. Without an explicit re-check, these late-arriving threads slip through as unresolved and cause the orchestrator's Step 5.1 to redispatch the agent.

**Procedure:**

1. **Wait for async bot threads**:

   ```bash
   # Sleep to allow async bots time to post new threads after the agent's pre-Check-4 query
   echo "Waiting 10 seconds for async-posting review bots (e.g., codex-github) to post any new threads..."
   sleep 10
   ```

2. **Re-query review threads**:

   Before running the query, resolve the Codex bot login. Use the value of `CODEX_GITHUB_BOT_LOGIN` if set; otherwise default to `"chatgpt-codex-connector[bot]"` (the default used by `codex-github-reviewer.sh`). Strip the `[bot]` suffix because GraphQL `author.login` values omit it:

   ```bash
   CODEX_BOT_LOGIN="${CODEX_GITHUB_BOT_LOGIN:-chatgpt-codex-connector[bot]}"
   # GraphQL author.login omits the "[bot]" suffix present in REST API logins; strip it.
   CODEX_BOT_LOGIN="${CODEX_BOT_LOGIN%\[bot\]}"
   ```

   ```bash
   JQ_FILTER="[.data.repository.pullRequest.reviewThreads.nodes[]
         | select(.isResolved == false)
         | select((.isOutdated // false) == false)
         | select(.comments.nodes[0].author.login as \$a | [\"coderabbitai\",\"devin-ai-integration\",\"greptile-apps\",\"$CODEX_BOT_LOGIN\"] | index(\$a) != null)
         | select((.comments.nodes[0].body // \"\") | test(\"✅ Addressed\") | not)] | length"
   UNRESOLVED_RECHECK=$(gh api graphql -f query='
     query($owner:String!, $repo:String!, $number:Int!) {
       repository(owner:$owner, name:$repo) {
         pullRequest(number:$number) {
           reviewThreads(first: 100) {
             nodes { isResolved isOutdated comments(first: 1) { nodes { author { login } body } } }
           }
         }
       }
     }' -f owner="<owner>" -f repo="<repo>" -F number="$PR_NUMBER" \
     --jq "$JQ_FILTER")
   ```

3. **Handle late-arriving threads**:
   - If `$UNRESOLVED_RECHECK -gt 0`: New unresolved threads were discovered. Remove `ready-for-human-review`, add `needs-fixes`, and return to Step 7a to address them:
     ```bash
     if [ "$UNRESOLVED_RECHECK" -gt 0 ]; then
       echo "⚠️ LATE-ARRIVING THREADS: Re-check detected $UNRESOLVED_RECHECK new unresolved thread(s) from async bots."
       echo "Removing ready-for-human-review label and returning to Step 7a."
       gh pr edit "$PR_NUMBER" --remove-label "ready-for-human-review"
       gh pr edit "$PR_NUMBER" --add-label "needs-fixes"
       echo "Return to Step 7a to address the newly-discovered threads."
       exit 6  # Exit code 6 = "late-arriving async bot threads detected"
     fi
     ```
   - If `$UNRESOLVED_RECHECK -eq 0`: No new threads found. Continue to Step 8b.

**Note**: This re-check is especially important when `codex-github` is a configured Step 7 review platform. The Codex GitHub App bot response is inherently asynchronous — the re-check adds a safety net to catch race conditions without requiring orchestrator intervention.

**Interpretation**:

- **All checks pass (exit 0)**: Continue to Step 8b (update tracker status) and then Step 8c (independent PR verification); only report the PR as ready after Step 8c also passes
- **Any check fails**: Stop and fix the condition. Do not apply `ready-for-human-review` until all checks pass
  - If `PR is still a draft` (exit 1): Human error; run `gh pr ready <pr_number>` manually
  - If `missing ready-for-regression` on implementation PR (exit 2 from Check 2): The label has been applied by Check 2. **Do not continue to Check 3/4.** Re-run `pr-ci-loop.sh` (Step 8) first to wait for the e2e/regression workflow triggered by the label. Only re-enter Step 8a after CI is green again. This ensures the e2e/regression check completes before the PR is marked ready.
  - If `ready-for-regression not verified` on implementation PR (exit 3 from pre-Check-4 gate): Step 7b was not completed. Apply the label via Step 7b, run Step 8 (CI loop), and re-enter Step 8a from the beginning. This gate is a hard block — `ready-for-human-review` cannot be applied until `ready-for-regression` is verified present.
  - If `unresolved review threads found` (exit 4 from GraphQL pre-Check-4 gate): The GraphQL query returned unresolved bot-authored review threads. Address the findings, push fixes, and re-enter Step 8a from the beginning. This gate is a hard block — `ready-for-human-review` cannot be applied until the GraphQL query confirms all threads are resolved. **Do not rely on self-tracked thread state** — the GraphQL query is the authoritative check.
  - If `late-arriving async bot threads detected` (exit 6 from Step 8a.1 re-check): Late-arriving threads from async bots (e.g., `codex-github`) were discovered after the pre-Check-4 gate. Remove `ready-for-human-review`, add `needs-fixes`, and return to Step 7a. This indicates a race condition where the bot posted its thread after the initial verification but before the label was applied.
  - If `reviewer-loop summary missing or non-clean` (exit 7 from Check 0.5): The latest automated reviewer-loop summary comment is absent or its `Result:` line is not `clean`/`skipped`. Do not apply `ready-for-human-review`. For `RESULT=escalate`, `pending_timeout`, `timeout`, `needs_fixes`, or any other non-clean terminal result, escalate or re-enter Step 7 according to the reviewer-loop result.
  - If `needs-fixes` is present (Check 3): The label is stale at this point (CI is green and reviews are clean), so it is automatically removed before proceeding to apply `ready-for-human-review`

This checklist ensures the label sequence is always complete and all CI checks (including e2e/regression) have passed before the PR is declared ready for human review.

---

## Step 8b: Update Tracker Status

**Guardrails check — completion gate**: Before marking an item complete for a
stage (updating tracker status to `Spec in Review`, `Plan in Review`, or
`Development in Review`), apply the completion gate from `guardrails-enforcement.md`
section 3 Gate 6:

1. Confirm the stage outcome against **live state** — the PR status must be
   `MERGED` for stage-complete transitions, or the `ready-for-human-review`
   label must be present and verified for in-review transitions. Never infer
   completion from stale memory, branch names, or prior resolver output.
2. If `audit.pr_disposition_record` is `required` in the effective guardrails,
   confirm the PR disposition record has been written (or will be written
   immediately after) before setting the tracker status. If the audit record
   cannot be produced, apply the `missing_audit_evidence` stop condition.

After the label readiness checklist passes, update the tracker status to reflect the PR is waiting for human review:

- For **spec PRs** (`spec/*`): set tracker status to `Spec in Review`
- For **plan PRs** (`implementation-plan/*`): set tracker status to `Plan in Review`
- For **implementation PRs** (`feature/*`, `fix/*`, `refactor/*`, `hotfix/*`): set tracker status to `Development in Review`

### Routing: CLI vs. MCP

How to perform the update depends on the configured `issue_tracker.provider` in `.ai-dev-workflow.yaml` and the execution context:

#### GitHub Projects (provider: `github_projects`) — use `gh` CLI

GitHub Projects status updates are fully supported via `gh` CLI and require no MCP server. Subagents in any execution context (including parallel batch runs) **must** use the CLI update pattern rather than MCP. Follow the "One-shot status update (recommended pattern)" section in [`docs/workflow/development-workflow/integrations/github-projects.md`](../integrations/github-projects.md) for the full commands and ID-resolution steps.

#### Other providers (Linear, Jira, etc.) — report and defer

For issue tracker providers that have no supported `gh`-equivalent CLI, MCP server access is required. Because MCP servers are not available in subagent execution contexts:

- **Subagents** must **not** attempt the tracker update directly. Instead, include the required transition in the summary returned to the orchestrator:

  ```
  TRACKER_UPDATE_REQUIRED: set issue #<N> status to "<target_status>"
  ```

- **The orchestrator** (or the human invoking the Work Item Runner directly) is responsible for performing the MCP-based status update after the subagent returns.

If neither the CLI path nor MCP is available, log a warning and continue — do not block labeling or PR readiness on a tracker update failure.

---

## Step 8c: Post-Label Independent Verification (Hard Gate)

After Steps 8a and 8b complete, perform one final independent verification of the actual PR state via `gh pr view` before reporting the PR as ready for human review. **Do not rely on prior step outputs or agent self-reports** — query GitHub directly.

```bash
gh pr view <pr_number> --json baseRefName,isDraft,labels,statusCheckRollup,comments
```

For the `reviewThreads` resolution check, `gh pr view --json` does not expose `reviewThreads`; use the GraphQL API directly. **This query is mandatory — do not skip it or rely on self-tracked thread state:**

```bash
gh api graphql -f query='
  query($owner:String!, $repo:String!, $number:Int!) {
    repository(owner:$owner, name:$repo) {
      pullRequest(number:$number) {
        reviewThreads(first: 100) {
          nodes { isResolved comments(first: 1) { nodes { author { login } body } } }
        }
      }
    }
  }' -f owner=<owner> -f repo=<repo> -F number=<pr_number> \
  | jq '.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved == false)
        | select(.comments.nodes[0].author.login as $a | ["coderabbitai","devin-ai-integration","greptile-apps"] | index($a) != null)
        | select((.comments.nodes[0].body // "") | test("✅ Addressed") | not)'
```

The bot login list above is a superset covering all platforms supported by `pr-review-loop.sh` (`coderabbit`, `devin`, `greptile`). The current default GitHub reviewer config in `.ai-dev-workflow.yaml` uses `review.on_draft.github: [pr-agent]` and `review.on_ready.github: [haystack]`. Update the list if your project uses different or additional review bots.

The output must contain no unresolved threads from configured bot reviewers (e.g. `coderabbitai`, `devin-ai-integration`) before this step passes. A thread is considered resolved when `isResolved: true` **or** the first comment body contains `✅ Addressed` (CodeRabbit appends this when a fix commit lands). Any unresolved bot-authored thread that does not meet either condition — regardless of severity, including Nitpick and Trivial — blocks this check. For PRs with more than 100 threads, implement cursor-based pagination: add `pageInfo { hasNextPage endCursor }` to the `reviewThreads` field selection, capture `endCursor` from each response, and repeat the query with `reviewThreads(first: 100, after: $cursor)` until `hasNextPage` is false.

Verify all of the following. If any check fails, **do not report ready** — treat it the same as `needs-fixes` and re-enter the fix loop from Step 7a:

| Check                                           | Pass condition                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Base branch                                     | When `BASE_BRANCH` is present in the handoff metadata: `<BASE_BRANCH>` for all item types except `hotfix/*`. When `BASE_BRANCH` is absent: `develop` for `feature/*`, `fix/*`, `refactor/*`, `spec/*`, `implementation-plan/*`; `main` for `hotfix/*`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| PR is non-draft                                 | `isDraft: false`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `ready-for-human-review` label                  | Present in `labels[].name`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `ready-for-regression` label                    | Present in `labels[].name` for `feature/*`, `fix/*`, `refactor/*`, `hotfix/*`, `backport/hotfix/*`; absent/ignored for `spec/*`, `implementation-plan/*`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| No `needs-fixes` label                          | `needs-fixes` absent from `labels[].name`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `needs-setup` label (if present)                | **Valid co-label** — `needs-setup` may be present alongside `ready-for-human-review` when the diff contains infrastructure dependency signals. Its presence does **not** constitute a verification failure and does not block this check. Do not remove it.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `human-checkpoint-required` label (when checkpoints in scope) | When the run carries checkpoint policy for this item: present if and only if applicable checkpoints remain `pending`; absent when all applicable checkpoints are `satisfied` or `waived`. Valid co-label with `ready-for-human-review`. When no checkpoint policy is in scope, ignore this check. |
| Checkpoint status comment (when checkpoints in scope) | At least one PR comment containing `<!-- run-epic:checkpoint-status -->` whose blocking section matches the current label state. Skip when no checkpoint policy is in scope. |
| All automated-reviewer `reviewThreads` resolved | GraphQL query above returns empty output — `isResolved: true` (or first comment body contains `✅ Addressed`) for every thread authored by a configured bot login (skip this check only when Step 7 was `skipped` because no review platforms are configured)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Automated reviewer loop summary                 | At least one comment whose body contains `"Automated Reviewer Loop Summary"`, `"Reviewer Loop Summary"`, or `"No blocking PR feedback"` (skip this check only when Step 7 was `skipped` because no review platforms are configured), and the latest summary's `Result:` line is `clean` or `skipped`. **This is a hard requirement. Agents applying fixes MUST NOT remove or skip this check — the presence of the comment plus a clean/skipped result is the only reliable signal that Step 7 ran to completion successfully. A PR that has `ready-for-human-review` but lacks this comment or has `RESULT=escalate`, `pending_timeout`, `timeout`, `needs_fixes`, or any other non-clean terminal result is in an incomplete state and must re-run Step 7 or escalate.** (Note: the Step 7a summary comment posted by the internal review gate is a distinct comment from a distinct step — it does not satisfy this check. This check targets the external automated reviewer loop summary from Step 7 only.) |
| CI checks                                       | All required status checks have `state: SUCCESS` or `conclusion: success` in `statusCheckRollup` (no check in `PENDING`, `FAILURE`, or `ERROR` state)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |

If any check fails:

1. Log the specific failure(s) — include the PR number, failed check name, and observed value.
2. Apply `needs-fixes` if not already present: `gh pr edit <pr_number> --add-label "needs-fixes"`.
3. Remove `ready-for-human-review` if it was already applied: `gh pr edit <pr_number> --remove-label "ready-for-human-review"`.
4. Fix the root cause (wrong base branch, missing label, missing review comment, failing CI) and return to Step 7a.

Only after all checks pass should the Work Item Runner report the PR as terminal ("ready for human review").

---

## Step 9: Feedback Loop

When a human requests changes on a PR:

1. Remove `ready-for-human-review`
2. Add `needs-fixes`
3. Address the feedback
4. Push fixes
5. For spec and plan PRs, verify the PR description still contains a current `Document Quality Gate` log
6. Run Step 7a (internal review gate) — all internal reviewers must approve before proceeding
7. Run Step 7 (external automated reviewers)
8. Run Step 7b (implementation PRs only)
9. Run Step 8 (CI loop)
10. Run Step 8a (label readiness checklist) — this is **mandatory** to verify the PR is non-draft, `ready-for-regression` is applied on implementation PRs, and `ready-for-human-review` is applied
11. Run Step 8b (update tracker status)
12. Run Step 8c (post-label independent verification) — query GitHub directly to confirm base branch, labels, review comment, and CI before reporting ready
13. Notify human that feedback has been addressed and the PR is ready again

See `92-pr-readiness-signal-protocol.md` for label definitions.

---

## Step 10: Post-Merge Status Transitions

When a human confirms that a PR has been merged, update the issue tracker and clean up local state according to this table:

| Merged PR branch type                             | Set tracker status to |
| ------------------------------------------------- | --------------------- |
| `spec/*`                                          | Spec Ready            |
| `implementation-plan/*`                           | Plan Ready            |
| `feature/*` / `fix/*` / `refactor/*` / `hotfix/*` | Merged                |

**Key rules:**

- When a spec or plan PR is merged, set the tracker status to the corresponding **Ready** status (`Spec Ready` or `Plan Ready`) — **not** `Merged`. Only implementation PRs (feature, fix, refactor, hotfix) go to `Merged`.
- The `/post-merge-cleanup` skill and `post-merge-cleanup` command follow this same table when updating tracker status.
- After updating the tracker, clean up local branches and worktrees associated with the merged PR:

```bash
git fetch origin
cd <repo-root>                          # CRITICAL: change to repo root before removing worktree (see Step 3)
git worktree remove <worktree-path>     # remove worktree first (branch is checked out there)
git branch -D <merged-branch>           # force-delete local branch (squash merges need -D)
```

If the item's tracker status is already in a further-advanced state (e.g., already `In Development` when a spec PR merges), do not roll it back — leave it as-is and only clean up local branches/worktrees.

---

## Step 11: Guardrails Audit Recording

After any delegated review decision, fix, merge, block, or escalation decision,
record audit evidence if `audit.pr_disposition_record` is `required` in the
effective guardrails. See `guardrails-enforcement.md` section 8 for the full
rules and helper invocations.

**Named stop-and-name behavior**: At any decision point during the run, if a
configured stop condition is met or required state is missing, stop before the
guarded action and report:

1. The exact stop condition name (from `guardrails-enforcement.md` section 4).
2. The affected work item (issue number, PR number, or branch).
3. The human action required to unblock.

Stop conditions never weaken below the baseline human-stops defined in
`guardrails-enforcement.md` section 4. Every stop appears in the Work Item
Runner Summary under a "Stops" section with its named cause, affected item, and
unblocking action.
