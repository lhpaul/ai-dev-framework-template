# Protocol: Run Epic

**Agent role**: Epic Runner (`run-epic`)
**Purpose**: Convert a native GitHub epic into a bounded execution set, then
run an explicitly authorized delegated review and merge loop with pre-merge
risk classification, audit evidence, cleanup, and rediscovery

The first phase is a **read-only resolver protocol**, not an implementation
protocol. It exists to make scoped multi-item work explicit before an agent
starts specs, plans, branches, PRs, tracker updates, reviewer loops, merges, or
cleanup. Delegation flags are captured during resolution but do not make the
resolver mutating. Later delegated execution phases must stay inside that
resolved scope.

---

## Routing From /run-work

`/run-work` does **not** enter this protocol for epic targets. Protocol 96 returns
`redirect_epic` with `REDIRECT_COMMAND` (e.g. `/run-epic --epic <n>`) and performs
no mutation. Re-invoke `/run-epic` directly.

**Read-only phase before mutation** (BR6, AC4): The scope resolver must complete
before any item is created, reviewed, merged, or cleaned up. This is the existing
read-only contract for this protocol and is not changed by routing.

`/run-epic` invoked directly (without `/run-work`) is a **compatibility/advanced
alias** that also enters this protocol. Its behavior is unchanged.

See `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`
for the full routing specification.

---

## Overview

Use this protocol when a human invokes `/run-epic`, `$run-epic`, or asks to run
a native GitHub epic as a delegated workflow batch. For explicit item lists, use
`/run-items` instead.

The resolver accepts one scope source:

```bash
./scripts/development-workflow/run-epic-scope-resolver.sh --epic <issue-number>
```

Optional flags:

- `--base <branch>`: override base-branch inference for the execution base.
  In `workflow_hub` mode this is the product implementation PR base, not proof
  that the hub repository itself must have a branch with that name.
- `--delegate-review`: allow the runner to make the normal human-review gate
  decision for this invocation.
- `--may-merge`: allow the runner to merge acceptable in-scope PRs through the
  repository merge protocol.
- `--may-start-backlog <true|false>`: control whether in-scope Backlog items
  may be started.
- `--max-risk <low|medium|high>`: maximum risk the runner may merge without
  human input.
- `--json`: emit machine-readable output for an orchestrator handoff.

**Delegation flags as the invocation-override layer**: `--delegate-review`,
`--may-merge`, `--may-start-backlog`, and `--max-risk` are the
**invocation-override** layer (highest priority) of the three-layer guardrails
precedence defined in
`docs/workflow/development-workflow/guardrails-enforcement.md` (section 1).
The repository `guardrails` config block in `.ai-dev-workflow.yaml` is the base
layer. An invocation override may narrow or widen authority only within what the
repository config and the effective autonomy mode permit — it cannot grant
authority the mode forbids. This protocol and Protocols 90/91 share **one
policy path**: the same run-epic helpers (`run-epic-risk-classifier.sh`,
`run-epic-delegated-gate.sh`, `run-epic-audit-trail.sh`) and the same
enforcement gates described in `guardrails-enforcement.md` section 3. There is
no separate policy model for `/run-epic` vs. `/run-work` routing.

The resolver is read-only even when delegation flags are supplied. It must not
update tracker status, create branches, open or edit PRs, merge PRs, close
issues, or delete branches.

When autonomy policy is missing or ambiguous, derive a recommended policy from
the resolver output before any mutating stage begins. For a single combined
read-only step (scope + repository guardrails snapshot + policy recommendation),
use [`bounded-run-prelude.md`](../bounded-run-prelude.md) and
`run-bounded-prelude.sh` — the same path `/run-item` uses before Protocol 91.

```bash
./scripts/development-workflow/run-epic-policy-recommender.sh --scope <resolver-json> --original-command "<requested command>" [--base <branch>] [--delegate-review|--no-delegate-review] [--may-merge|--no-may-merge] [--may-start-backlog <true|false>] [--max-risk <low|medium|high>] [--checkpoints-file <json-array>] [--json]
```

The recommender is also read-only. It must not update tracker status, create
branches, open or edit PRs, merge PRs, close issues, delete branches, or post
comments. It produces recommended, selected, and effective policy values plus a
copy-paste equivalent command for audit evidence. Use `--no-delegate-review` or
`--no-may-merge` when the selected policy explicitly disables a recommended
positive default.

### Human-checkpoint recommendations

Before mutation, the recommender classifies per-item human checkpoints from
read-only scope metadata (title, type, labels, tracker status). High-leverage
signals default to checkpoints:

- **Plan + technical**: database schema, migration, or persistent data-model
  wording.
- **Spec + product**: unresolved product language, open questions, empty
  Acceptance Criteria sections, or placeholder-only acceptance criteria when
  the item is still in Backlog or spec stage. A populated Acceptance Criteria
  heading is normal issue structure and is not a checkpoint signal by itself.
- **Plan or implementation + both**: ambiguous product/technical tradeoffs.
- **Implementation + technical**: security, auth, permission, or other
  sensitive-change wording.

The JSON output includes `recommendedPolicy.checkpoints`,
`selectedPolicy.checkpoints`, `effectivePolicy.checkpoints`, and
`checkpointPolicy` (`recommended`, `selected`, `effective`) for audit evidence.
Each checkpoint record carries `item_number`, `stage`, `domain`, `reason`,
`required_human_action`, and `satisfaction_state` (`pending` by default).

Humans may accept recommendations as-is, customize them, or waive defaults with
documented rationale before mutation begins. Pass an explicit selected checkpoint
array with `--checkpoints-file <json-array>`; waived entries must include
`waiver_rationale`. When recommendations exist and no `--checkpoints-file` is
supplied, confirmation is required before mutation — silent auto-waiver is not
permitted.

The preflight summary must show checkpoint policy alongside autonomy policy so
the human can accept, customize, or waive checkpoints before mutation. Two common
examples:

- **Plan-stage database/schema checkpoint**: an item titled "Add tenant billing
  migrations" should recommend a `plan` / `technical` checkpoint with a required
  action such as "approve the migration and rollback plan". A later
  implementation PR remains blocked until that plan-stage checkpoint is
  `satisfied` or `waived`.
- **Implementation-stage sensitive-change checkpoint**: an item touching auth,
  permissions, security-sensitive automation, or merge behavior should recommend
  an `implementation` / `technical` checkpoint with a required action such as
  "approve the sensitive implementation before delegated merge".

Checkpoint enforcement now spans PR readiness labels, delegated gates, batch
merge, and audit comments. The lifecycle validation path is documented in
[`docs/testing/workflow/1024-human-checkpoint-lifecycle.smoke-test.md`](../../../testing/workflow/1024-human-checkpoint-lifecycle.smoke-test.md).

When a later delegated run reaches a candidate PR merge decision, classify that
PR with:

```bash
./scripts/development-workflow/run-epic-risk-classifier.sh --pr <pr-number> --max-risk <low|medium|high> [--repo-root <path>] [--product-repo <name>]
```

In `workflow_hub` mode, pass `--repo-root` and `--product-repo` (or rely on
`github_repo` / `productRepo.name` in `--input` evidence) so hub `ci_policy` is
applied when the evidence omits `ciPolicy` / `ci_policy`.

The risk classifier is also read-only. It must not run reviewer loops, poll CI,
update tracker status, change labels, create comments, merge PRs, close issues,
or delete branches. It is an additional pre-merge gate and does not replace the
reviewer loop, CI loop, unresolved-thread checks, merge-state checks, readiness
labels, or repository merge protocol.

Delegated decision runs also record audit comments with:

```bash
./scripts/development-workflow/run-epic-audit-trail.sh render-pr-disposition --input <file>
./scripts/development-workflow/run-epic-audit-trail.sh apply-pr-disposition --input <file> --pr <pr-number>
./scripts/development-workflow/run-epic-audit-trail.sh render-epic-ledger --input <file>
./scripts/development-workflow/run-epic-audit-trail.sh apply-epic-ledger --input <file> --epic <issue-number>
```

Audit comments are evidence records only; they do not grant merge authority.

Before an authorized merge decision, run the delegated gate with the current
candidate PR, resolver policy, reviewer, CI, risk, scope, and audit evidence:

```bash
./scripts/development-workflow/run-epic-delegated-gate.sh --input <file> [--policy <file>] [--repo-root <path>] [--product-repo <name>]
```

The gate is read-only. It explains whether the runner may proceed to merge,
must fix and rerun, must stop for human authority/setup, or is blocked by
missing state. It does not replace `/run-item-work`, reviewer-loop, CI-loop,
risk classification, audit comments, merge, cleanup, or tracker updates.
The gate consumes an assembled evidence file; live PR reads happen in the risk
classifier, audit helper, reviewer loop, CI loop, and normal GitHub checks.
In `workflow_hub` mode, pass `--repo-root` and `--product-repo` (or include
`productRepo.name` in the evidence file) so hub `ci_policy` is applied when
the evidence omits `ciPolicy` / `ci_policy`.

---

## Step 1: Validate Scope Input

Require `--epic <issue-number>`. The `--items` flag is not a user-facing option
for `/run-epic`; operators who need explicit item lists should use `/run-items`
instead.

The epic issue number must be a positive integer. Reject empty values, zero, and
non-numeric tokens before any repository or tracker lookup.

---

## Step 2: Resolve Epic Children

For `--epic`, read native GitHub sub-issues using GraphQL pagination.

Required behavior:

- Read all pages of `subIssues`.
- Verify the child-side parent relationship when GitHub exposes it.
- If the epic has no native sub-issues, report an empty scope clearly.
- Do not fall back to integration branch labels as an epic membership source.
  Labels remain routing metadata, not membership metadata.

### Linear provider

When `issue_tracker.provider` is `linear`, GitHub GraphQL is not available for
sub-issue enumeration. Apply this flow instead:

1. **For `--epic`** — query the Linear parent item's child issues via the
   Linear MCP `issue.children` or equivalent relationship query. Collect each
   child item's identifier, title, status, type, priority, and dependencies.
   If the Linear item has no children, report an empty scope clearly — do not
   treat the parent item itself as the only scope item.

2. **For internal explicit-item paths** — when a script passes `--items`
   internally, the explicit list is a hard scope boundary (BR-7). Do not expand
   to siblings, parent epics, or label-matched items. Fetch each listed item's
   metadata via the Linear MCP before passing it to the scope resolver. Users
   invoking `/run-epic` directly should use `/run-items` instead.

3. **Pass pre-resolved data** — the scope resolver (`run-epic-scope-resolver.sh`)
   cannot reach Linear itself. Supply item metadata as structured input. The
   resolver will emit `PROVIDER=linear` and `TRACKER_READ_DEFERRED=yes` in its
   output, confirming that item statuses came from the orchestrator's
   pre-resolved set rather than from a live Linear query by the script.

4. **Interpret `TRACKER_READ_DEFERRED=yes`** — when this line appears in scope
   output, it confirms the resolver consumed orchestrator-supplied item data.
   Apply the statuses from your pre-resolved context when grouping items as
   eligible, blocked, in review, etc.

See [`linear.md`](../integrations/linear.md) for the bridge pattern and the
full `TRACKER_ACTION_REQUIRED=` reference table.

---

## Step 3: Enrich Each Item

For each in-scope item, collect best-effort read-only metadata:

- Issue number, title, and open / closed state.
- Labels, including any `integration-branch:<slug>` label.
- Project Status, Type, and Priority when available.
- Dependency signal from issue body references such as `Depends on #123`.
- Linked open or merged PRs whose branch names match the item number.

If a metadata read fails for one item, keep the item in the result as
`ambiguous` with a short reason instead of silently dropping it.

---

## Step 4: Infer Base Branch

Use this precedence:

1. Supplied `--base <branch>`.
2. One shared `integration-branch:<slug>` label across in-scope items, resolved
   as `develop-<slug>`.
3. No integration label, resolved as `develop`.
4. Conflicting integration labels, resolved as ambiguous unless `--base` is
   supplied.

When conflicting integration labels are ambiguous, every item in the result is
ambiguous. A later mutating workflow must stop until a human supplies `--base`
or narrows the scope.

### Workflow Hub Base Context

In `workflow_hub` mode, the resolved base branch is attached to the product
implementation path. Do not validate that branch against the hub repository
remote before a selected product repository is known. A hub repository may use
`main` for hub-owned specs, plans, and workflow PRs while its product
repositories use `develop` for implementation PRs.

Hub-owned spec and plan stages use the hub artifact base branch from the current
hub repository, typically its default branch. Product implementation, reviewer,
CI, merge, cleanup, and post-merge branch validation use the selected product
repository and the resolved execution base.

---

## Step 5: Group Items

Assign each item to one group:

- `eligible`: no known blocker, no ready/open review PR, and not already merged.
- `blocked`: dependency signal points to an open dependency.
- `already_merged`: tracker status, issue state, or merged PR indicates the work
  is already complete.
- `in_review`: tracker status or open PR indicates the item is waiting for review
  or merge.
- `ambiguous`: missing / conflicting data prevents a deterministic next action.
- `out_of_scope`: reserved for consumers that compare resolver output against a
  later bounded handoff. Out-of-scope PRs must never be included in delegated
  merge or batch-merge commands.

Do not mutate anything based on these groups. The resolver only describes the
execution set.

---

## Step 6: Handoff

Print:

- Scope source and item count.
- Base branch, inference reason, workflow mode, base branch ownership target,
  and base branch validation note.
- Read-only guarantee.
- Grouped item list with issue number, title, status, type, and issue state.

When `--json` is supplied, emit valid JSON containing the same fields plus the
full item metadata. The JSON must include `workflowMode`,
`baseBranchAppliesTo`, and `baseBranchValidationNote` alongside `baseBranch` so
downstream orchestrators can validate the base in the repository that owns the
next mutating artifact. Downstream orchestrators must treat this JSON as the
bounded scope contract and must not opportunistically mutate items outside it.

The output must also include the invocation policy:

- Delegated review authority.
- Delegated merge authority.
- Backlog-start policy.
- Maximum allowed autonomous merge risk.

### Step 6a: Recommend Missing Autonomy Policy

If any effective policy value was not explicitly supplied by the human, or if
the base branch is ambiguous, run the policy recommender against the saved
resolver output before tracker, branch, PR, label, or merge mutation.

Recommended defaults should favor the most automatic safe configuration:

- `--may-start-backlog true` when the requested scope includes Backlog items
  and no dependency blocker or ambiguity is detected.
- `--delegate-review` when configured internal reviewers are available for the
  current runner.
- `--may-merge` when delegated review is available, the scope is explicit, and
  no authority, setup, or base ambiguity is present.
- `--base <branch>` when the resolver inferred one unambiguously.
- `--max-risk low` for docs, spec, plan, test, or narrow text-only changes.
- `--max-risk medium` for workflow scripts, orchestration behavior, merge or
  cleanup automation, or shared workflow tooling when later
  `why_safe_to_merge` evidence can be produced.
- Human-checkpoint recommendations per eligible item when metadata signals
  schema/migration, product ambiguity, tradeoff ambiguity, or sensitive
  implementation work (see **Human-checkpoint recommendations** above).
- Never recommend `high` by default. High-risk work requires explicit human
  selection.

Present a preflight summary before mutation: scoped issues, grouped states,
base branch, recommended policy, recommended checkpoints (if any), risk
rationale, and the copy-paste equivalent command. If confirmation is required,
ask in-place and continue in the same run when the human accepts. Do not ask
repeatedly for the same policy choice within the same invocation once
selected/effective policy has been recorded.

Exact invocations with all effective policy values already supplied may skip the
confirmation prompt, but they still record the original command, recommended
policy, selected policy, effective policy, and copy-paste equivalent command in
the later audit trail.

If the recommender reports an ambiguous base, unavailable reviewers, missing
authority, or risk tolerance above the safe recommendation, stop before mutation
and explain the specific gate.

---

## Step 7: Classify PR Risk Before Delegated Merge

This step applies only after a later delegated run has advanced an in-scope item
to a candidate PR merge decision. It does not run during the resolver-only
handoff.

Before an autonomous merge decision:

1. Confirm the PR is in the resolved execution set or was created for an
   in-scope item.
2. Confirm the normal readiness evidence is current: reviewer loop, CI loop,
   readiness labels, unresolved-thread audit, and merge state.
3. Run `run-epic-risk-classifier.sh` for the candidate PR with the invocation's
   maximum allowed risk.
4. Continue toward merge only when the classifier reports
   `merge_permitted: true` and the normal repository merge protocol is also
   clean.
5. If the classifier reports `blocked`, fix the deterministic blocker when
   safe, then rerun validation, reviewer loop, CI loop, and risk
   classification.
6. If the classifier reports a risk above `--max-risk`, stop or escalate rather
   than widening authority silently.

Risk levels:

- `low`: docs, tests, narrow workflow text, or isolated helper changes with
  clean readiness evidence and no blockers.
- `medium`: workflow scripts, orchestration behavior, merge or cleanup
  automation, or shared workflow tooling with contained blast radius and clean
  readiness evidence.
- `high`: auth, secrets, GitHub permissions, release automation, branch deletion
  behavior, cross-repo PR credentials, broad shared libraries, or unclear
  behavior changes.
- `blocked`: hard-blocking readiness, setup, credential, tracker/base, merge
  state, force-push, destructive-action, or reviewer/thread conditions.

Medium-risk autonomous merge decisions require a complete "why safe to merge"
explanation covering scope, tests, reviewer outcome, CI outcome, and rollback or
cleanup risk. Missing evidence blocks the merge decision.

---

## Step 8: Delegated Review and Fix Loop

This step applies only when the invocation policy includes `--delegate-review`.
Without delegated review authority, any PR that reaches the normal
`ready-for-human-review` handoff remains waiting for human review.

**Pre-dispatch: create the integration branch once before dispatching parallel agents.**
If the resolved base branch is an integration branch that does not yet exist on
the owning remote, create and push it exactly once before dispatching any
in-scope item agents. In `workflow_hub` mode, "owning remote" means the selected
product repository for product implementation work, not the hub repository:

```bash
git checkout -b <base-branch> origin/<product-default-branch>  # or the appropriate upstream
git push -u origin <base-branch>
```

Do this in the orchestrator context, not inside a dispatched agent. Parallel
agents must not race to create the same branch from `develop` — this produces
divergent starting HEADs and stacked-branch contamination across sibling items.

**Current mitigation — pre-branch HEAD guard (short-term)**: Each agent protocol
(Protocols 01, 02, and 03) now includes a mandatory pre-branch HEAD verification
step. Before running `git checkout -b`, every agent compares its current HEAD
SHA against the expected base (`origin/develop` or the integration branch). If
they differ — indicating that a sibling agent moved the checkout — the agent
aborts immediately with a clear error rather than silently stacking its branch
on top of a sibling's commits. When the guard fires, recovery is: (1) reset the
working tree to the expected base with `git checkout develop && git pull origin
develop`, then (2) re-run the agent from branch creation.

**Nested artifact guard**: Before dispatching any child item that may create a
branch or open a PR, run `run-nested-artifact-guard.sh` with the resolved
execution base:

```bash
ARTIFACT_REPO_ROOT="${ARTIFACT_REPO_ROOT:-$(pwd)}"
./scripts/development-workflow/run-nested-artifact-guard.sh \
  --mode pre-create \
  --issue <issue-number> \
  --expected-branch <branch-prefix>/<slug> \
  --approved-base <base-branch> \
  --repo-root "$ARTIFACT_REPO_ROOT"
```

Run the same helper with `--mode pre-pr` before a child opens or readies a PR.
`RESULT=missing_base`, `RESULT=blocked_duplicate`, `RESULT=wrong_base`, and
`RESULT=scan_failed` block delegated progress until the canonical path is
resumed or an explicit split is approved and recorded with `--allow-split true`.
Use the repository root that owns the child artifact. In `workflow_hub` mode,
product implementation branches and PRs must scan the selected product checkout;
hub-owned spec and plan artifacts use the hub checkout.

**Intended long-term fix — worktree isolation**: The durable solution to
shared-checkout contamination is to dispatch each parallel agent into a
separate `git worktree` (one worktree per item). With worktree isolation, each
agent has its own working tree backed by the shared `.git` directory, so no
agent can disturb another's HEAD or uncommitted changes. Protocol 91 Step 3
already supports this model via the `BATCH_CONTEXT=true` / worktree path
contract. Future `/run-epic` parallel dispatch should set `isolation: worktree`
(or equivalent) so item-orchestrators create a dedicated worktree before
handing off to each agent, making the pre-branch guard redundant for parallel
runs while keeping it as a backstop for single-checkout fallback.

**Checkpoint-resume gate**: When an epic-scoped item resumes
after a human-checkpoint pause and the prior run used a dedicated item
worktree, run Protocol 91's checkpoint-resume gate before any mutation in
the resumed session:

```bash
./scripts/development-workflow/checkpoint-resume-gate.sh \
  --item <item-id> \
  --expected-branch <branch-prefix>/<slug> \
  --expected-worktree <worktree-path> \
  --main-repo-root <main-repo-root> \
  --checkpoint-state <pending|satisfied|waived> \
  --json
```

`RESULT=continue` means the session is already inside the expected worktree and
the checkpoint is satisfied or waived. `RESULT=checkpoint_pending` stops for a
human decision. `RESULT=stop` means the run must stop before mutation and report the item,
expected branch, expected worktree when known, observed directory, observed
branch when available, failure reason, and human recovery action. A stopped
main-clone session must be replaced with a fresh fully isolated runner; it must
not re-enter a worktree itself. Isolation verification never changes checkpoint state.

When resuming an interrupted mutating child run, inspect the child branch
history, local worktree commits, and uncommitted edits before mutation. Prefer
the latest committed checkpoint that represents a completed logical sub-part as
the resume boundary. Absence of a newer checkpoint is acceptable evidence that
no completed sub-part finished after the last checkpoint, but live branch, PR,
worktree, review, CI, and tracker state still control the next action.

For each in-scope item:

1. Advance the item with the existing `/run-item-work` or stage protocol. Do not
   duplicate spec, plan, implementation, reviewer-loop, or CI-loop behavior in
   this protocol.
2. When a PR reaches review handoff, inspect the latest reviewer-loop and
   Haystack result yourself.
3. If blocking findings are present, remove `ready-for-human-review` and
   `ready-for-regression`, apply deterministic fixes, push a normal follow-up
   commit, rerun local validation, rerun reviewer-loop, rerun CI-loop, audit
   unresolved threads, and reassess.
4. Do not amend and force-push published PR commits during delegated review or
   merge work.
5. If advisory findings remain, make an explicit fix-or-accept decision. Fix an
   advisory when it materially improves risk, maintainability, security, test
   coverage, or workflow reliability. Accepted advisories require rationale in
   the PR disposition audit. When `advisory_count > 0`, the runner must:
   - Fetch the individual findings from Haystack via:
     `bash scripts/development-workflow/haystack-reviewer.sh <pr_number> <owner> <repo>`
     (owner/repo can be resolved from the git remote or
     `WORKFLOW_TARGET_GITHUB_REPO`)
   - Assess each finding individually: decide fix or accept, and record the
     rationale
   - Write one `advisories[]` entry per finding in the PR disposition input —
     never a single catch-all entry covering multiple findings
6. Restore readiness labels only after reviewer-loop, CI-loop, unresolved
   threads, and final readiness checks are clean.

---

## Step 9: Record Audit Trail

After a delegated review, fix, merge, block, or escalation decision, create or
update the audit trail before considering the item complete.

Required behavior:

- Write one PR disposition comment for every PR that reaches the delegated
  review gate.
- Use the stable marker `<!-- run-epic:pr-disposition -->` so reruns update the
  existing comment.
- For native epic runs, update one parent epic ledger comment with marker
  `<!-- run-epic:epic-ledger -->`.
- For explicit item-list runs without a parent epic, report the epic ledger as
  not applicable while still writing PR disposition comments.
- Include reviewed head SHA, reviewer-loop result, blocking/advisory counts,
  advisory decisions and rationales, risk classification and reasons, merge
  authority, original command, recommended policy, selected policy, effective
  policy, copy-paste equivalent command, final decision, verification evidence,
  and protocol deviations.
- Redact secrets, credentials, tokens, and local-only paths before rendering or
  applying comments.

Reruns must update existing marker comments instead of creating duplicates.

---

## Step 10: Final Delegated Merge Gate

This step applies only when the invocation policy includes `--may-merge`.
Without delegated merge authority (`merge_denied`), the runner may prepare the
PR for human review but must not merge it; report `ready_human_merge` and name
the denying policy value. With delegated merge authority (`merge_granted`),
readiness is intermediate and every in-scope ready PR must continue through this
gate unless a named blocker produces `merge_blocked`.

Before merge:

1. Confirm the PR belongs to the resolved execution set.
2. Confirm the PR is not draft.
3. Confirm `ready-for-human-review` is present.
4. Confirm `ready-for-regression` is present when the branch prefix is
   `feature/*`, `fix/*`, `hotfix/*`, `refactor/*`, or `backport/hotfix/*`.
   Spec and implementation-plan PRs do not require this label.
5. Confirm CI is green and no required check is pending, failing, unavailable,
   or ambiguous.
6. Confirm merge state is clean.
7. Confirm `needs-setup` is absent.
8. Confirm no unresolved blocking automated-reviewer thread remains.
9. Confirm reviewer disposition is acceptable.
10. Confirm the risk classifier permits merge under the invocation's
    `--max-risk`.
11. Confirm the PR disposition audit comment exists for the reviewed head SHA.
12. For sweep, batch, helper-extraction, numeric-target, or
    pattern-completeness sub-items, confirm the PR disposition or item summary
    includes residual gate evidence: `RESULT=pass` or `RESULT=not_applicable`.
    A blocked or escalated residual gate means the sub-item is not complete and
    must remain out of delegated merge.
13. Confirm the candidate PR is not a graduation PR
    (`develop-<slug>` -> `develop`) unless explicit graduation approval has
    been recorded in the assembled policy evidence as
    `graduationApproved: true`. `/run-epic` delegated merge authority applies to
    in-scope child PRs, not to integration-branch graduation. A graduation PR
    without this approval must stop with `graduation_approval_required` and be
    resumed through `/graduate-development <slug>`.
13. Run `run-epic-delegated-gate.sh` against the assembled evidence.

Proceed to the repository merge protocol only when the delegated gate reports
`merge_allowed`. If the gate reports `fix_required`, remove readiness labels,
fix, rerun validation/reviewer/CI, and return to Step 8. If it reports
`human_required`, stop for human authority, setup, or risk tolerance. If it
reports `blocked`, stop until required state is available.

If an in-scope child PR stops at readiness during a merge-granted run without a
named blocker from this step, report `policy_inconsistent` in the PR
disposition and epic ledger. Discovered PRs outside the resolved scope remain
`out_of_scope` and are never merged by this protocol.

---

## Step 11: Merge, Cleanup, Rediscovery, and Epic Closeout

When all gates permit merge:

1. Merge with the repository-approved merge path for the PR target branch.
   This merge step is for in-scope child PRs. If the candidate is a graduation
   PR (`develop-<slug>` -> `develop`), stop unless the explicit graduation
   approval evidence described in the delegated gate checklist is present.
2. Verify GitHub reports the PR state as `MERGED`.
3. Delete or prune the merged branch as appropriate.
4. Run post-merge cleanup for the correct base branch. For direct single-PR
   merges, use the cleanup helper after merge verification. In `workflow_hub`
   mode, pass `--repo <product-repo>` for product-owned implementation branches:

   ```bash
   ./scripts/development-workflow/post-merge-cleanup.sh [--repo <product-repo>] --base <base-branch> <merged-branch>
   ```

   For scoped batch merges, follow Protocol 94 so every merged PR runs its
   delete-branch and post-merge cleanup sequence.
5. Verify issue state and Project status — **with live re-read and re-apply**:

   a. Determine the expected post-merge tracker status from the merged branch type
      (see Protocol 91 Step 10 table: `feature/*` / `fix/*` / `refactor/*` /
      `hotfix/*` → `Merged`; `spec/*` → `Spec Ready`; `implementation-plan/*` →
      `Plan Ready`).

   b. Re-read the live tracker status from GitHub Projects:

      ```bash
      gh issue view <issue_number> --json projectItems \
        --jq '.projectItems[].status.name // "unknown"'
      ```

   c. If the live status does not match the expected post-merge value, re-apply
      the tracker update immediately before proceeding to the next item. Do not
      rely on the agent's earlier claim that the update succeeded — the live
      read is the authoritative source.

   d. Record the verification result (expected value, live-read value, and
      whether a re-apply was required) in the PR disposition audit comment for
      this item. Add a `tracker_status_verified` field with value `true` when
      the live status matched on first read, or `reapplied` when the re-apply
      was required. Add `tracker_status_mismatch` with a brief reason when the
      re-apply also fails.

6. Update the epic ledger.
7. Rerun scope resolution so newly unblocked items can advance.

After the final native child item reaches a terminal state, verify live native
sub-issues and Project statuses before closing the parent epic or marking it
complete. Do not close the parent epic from stale memory, branch names, or prior
resolver output alone.

Stop only when all in-scope items are merged, remaining items are blocked by a
real external condition or authority boundary, or the invocation policy forbids
starting the remaining Backlog work. Final stop messages must name the exact
gate: missing authority, risk classification, CI/check state, unresolved
reviewer findings, tracker ambiguity, delegated gate state, or backlog-start
policy. When all child items are merged but the integration branch has not been
explicitly approved for graduation, stop at `graduation_approval_required` and
report the integration branch as `ready_for_graduation`.
