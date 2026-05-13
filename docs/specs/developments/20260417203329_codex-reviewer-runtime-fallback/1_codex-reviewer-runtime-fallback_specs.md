# Codex Reviewer Runtime Fallback — Spec

**Depends on**: <!-- none -->

---

## Overview

The Step 7a internal review gate in Protocol 91 runs all reviewers listed in
`review.internal_reviewers` (`.ai-dev-workflow.yaml`) before converting a draft
PR to non-draft. When run from a Claude Code subagent, the Codex reviewer is
unreachable (the Codex CLI / runtime is not accessible in that execution context),
yet the gate currently proceeds silently with only the `claude` reviewer — no
warning is emitted, the skipped reviewer is not counted, and the operator cannot
tell the gate was partially executed.

This spec defines a runtime-availability check mechanism and a configurable
fallback policy so that every Step 7a execution is transparent about which
reviewers actually ran, warns when any declared reviewer is unreachable, and
either halts the gate or proceeds only after explicit human acknowledgement.

---

## Use Cases

### Use Case 1: Reviewer Unreachable — Warning and Skip (Default `warn` Policy)

**Actor**: Work Item Runner (orchestrator agent or human-delegated CI run)
**Preconditions**:

- `.ai-dev-workflow.yaml` lists two or more internal reviewers (e.g., `claude`
  and `codex`).
- Step 7a is about to start for a draft PR.
- At least one listed reviewer (e.g., `codex`) is not reachable from the current
  runner (e.g., Claude Code subagent context).
- The repo's `internal_reviewers_unavailable_policy` is `warn` (default).

**Steps**:

1. The Work Item Runner reads the `review.internal_reviewers` list.
2. Before dispatching any reviewer, the runner performs a runtime-availability
   check for each listed reviewer.
3. For `codex`, the check determines that the Codex CLI / runtime is not
   reachable from the current execution context.
4. The runner emits a warning to the PR (via `gh pr comment`) and to the console
   log:
   > `WARNING: internal_reviewer 'codex' unreachable from current runner
(Claude Code subagent) — skipping. Only 'claude' will run in this Step 7a
cycle. Reviewer coverage is reduced from 2 to 1.`
5. The runner records the skipped reviewer as `skipped (unreachable)` — not
   `approved` and not `needs_revision`.
6. The runner dispatches the remaining reachable reviewer (`claude`) and awaits
   its verdict.
7. If `claude` returns `APPROVED`, the runner posts a Step 7a summary comment
   listing which reviewers ran and which were skipped, then proceeds to `gh pr
ready` (converting the draft PR to non-draft).
8. If `claude` returns `NEEDS REVISION`, the runner applies fixes and re-runs
   the full available reviewer list (only `claude` in this context) as normal.

**Postconditions**:

- The draft PR is converted to non-draft after all reachable reviewers approve.
- A warning comment in the PR records that `codex` was unreachable and skipped.
- The Step 7a summary comment lists the effective reviewer set for this cycle.
- The reviewer coverage gap is visible to human reviewers inspecting the PR.

**Information shown**:

- Warning message in PR comments: which reviewer was skipped and why.
- Step 7a summary comment: which reviewers ran, which were skipped, and the
  effective verdict.

**Actions available**:

- The human reviewer can inspect the PR and choose not to merge if the reduced
  reviewer coverage is unacceptable for that change.
- The human can re-run Step 7a in a runner context where all reviewers are
  available before approving.

**Considerations**:

- If ALL reviewers are unreachable, the hard-fail rule (BR-3) applies
  regardless of the configured policy.

---

### Use Case 2: Reviewer Unreachable — Hard Fail (Zero Reachable, Any Policy)

**Actor**: Work Item Runner
**Preconditions**:

- All listed internal reviewers are unreachable from the current runner (zero
  reachable regardless of configured policy).

**Steps**:

1. The Work Item Runner performs the runtime-availability check.
2. No reachable reviewer is found (all listed reviewers are unavailable).
3. The runner posts a Step 7a summary comment to the PR that serves as both
   the error notification and the BR-7-mandated summary. The comment must include:
   - Effective reviewer set: none (zero reachable)
   - Skipped reviewers: all listed reviewers, each with reason `unreachable`
   - Final verdict: `hard-fail / blocked`
   - Remediation guidance, for example:
     > `Step 7a BLOCKED: no internal reviewer is reachable from the current
runner. Effective reviewer set: none. Skipped: [codex (unreachable),
claude (unreachable)]. Verdict: hard-fail. To unblock: run Step 7a from a
runner that supports all configured reviewers, or temporarily override
'review.internal_reviewers' via .tmp/template-config.json.`
4. The runner does NOT convert the draft PR to non-draft.
5. The runner stops and reports the item as "blocked — no reviewer available"
   to the Portfolio Orchestrator or human operator.

**Postconditions**:

- The draft PR remains in draft state.
- A Step 7a summary comment (satisfying BR-7) is posted to the PR, listing all
  skipped reviewers with reason, and the hard-fail verdict.
- The item is escalated to human for resolution.

**Information shown**:

- Step 7a summary comment listing all listed reviewers as unreachable and the
  hard-fail verdict, with remediation guidance.

**Actions available**:

- The human can run Step 7a from a runner context where reviewers are available
  (e.g., invoke the Codex `workflow-spec-reviewer` skill directly).
- The human can override `internal_reviewers` locally via
  `.tmp/template-config.json` to run a reduced set, then re-trigger Step 7a.

**Considerations**:

- This use case applies regardless of the configured policy: when zero reviewers
  are reachable, the gate must hard-fail even under the `warn` default policy.
  BR-3 is a floor that no policy can override.

---

### Use Case 3: All Reviewers Reachable — Normal Flow (No Change)

**Actor**: Work Item Runner
**Preconditions**:

- All listed internal reviewers are reachable from the current runner.

**Steps**:

1. The Work Item Runner performs the runtime-availability check for each
   reviewer.
2. All reviewers pass the availability check.
3. The runner proceeds with the existing Step 7a multi-reviewer loop without any
   change to behavior.

**Postconditions**:

- All reviewers run as declared; the gate behaves as today.

**Considerations**:

- No additional comments or warnings are posted in this flow.

---

### Use Case 4: Local Override to Suppress Unavailable Reviewer

**Actor**: Developer or CI operator
**Preconditions**:

- The developer cannot access one of the listed internal reviewers from their
  local environment or CI runner.
- The developer has created `.tmp/template-config.json` with an
  `overrides.review.internal_reviewers` key listing only the reviewers they can
  invoke.

**Steps**:

1. The Work Item Runner reads `.tmp/template-config.json` and finds the
   `overrides.review.internal_reviewers` override.
2. The runner uses the override list for Step 7a instead of the
   `.ai-dev-workflow.yaml` list.
3. The runtime-availability check runs against the override list.
4. All reviewers in the override list are reachable; Step 7a runs normally.
5. The runner logs that the override was applied:
   > `INFO: Using internal_reviewers override from .tmp/template-config.json:
[claude]. Original list: [claude, codex].`

**Postconditions**:

- Step 7a runs with the reduced reviewer set declared in the override.
- A log entry notes that the override was applied.
- No warning comment is posted to the PR (the developer knowingly overrode the
  list).

**Considerations**:

- The override file is gitignored; it does not affect shared config.
- The override only suppresses the availability check warning; it does not bypass
  the gate if any overridden reviewer is itself unreachable.

---

## Business Rules

- **BR-1 — Availability check required**: Before dispatching any reviewer in
  Step 7a, the Work Item Runner must verify that each listed reviewer is
  reachable from the current execution context. The check must be deterministic
  and fast (no external network call required — runner identity is sufficient as
  a proxy for reviewer reachability).

- **BR-2 — Unreachable reviewer is skipped, not approved**: A reviewer that
  fails the availability check must be recorded as `skipped (unreachable)` for
  that Step 7a cycle. It must NOT count as an implicit approval.

- **BR-3 — No reachable reviewer triggers hard fail**: If zero reviewers from
  the resolved list are reachable, Step 7a must stop and escalate regardless of
  the configured policy. The draft PR must not be converted to non-draft in this
  state.

- **BR-4 — Policy: `warn` (default)**: When one or more (but not all) reviewers
  are unreachable, the default policy is to warn and proceed with the reachable
  subset. The warning must be posted as a PR comment and recorded in the Step 7a
  summary.

- **BR-5 — Configurable strict policy**: A future-compatible
  `internal_reviewers_unavailable_policy` key in `.ai-dev-workflow.yaml` (or its
  local override) may be set to a stricter value (e.g., `fail-if-any-unavailable`)
  to halt Step 7a whenever any listed reviewer is unreachable — not just when all
  are unreachable. Under the default `warn` policy, the gate proceeds with a
  reduced reviewer set as long as at least one reviewer is reachable. The spec
  leaves the exact key name, enum values, and schema as an implementation decision
  for the plan stage.

- **BR-6 — Local override takes precedence**: If `.tmp/template-config.json`
  defines `overrides.review.internal_reviewers`, that list is used instead of
  the `.ai-dev-workflow.yaml` list. The availability check runs against the
  override list, not the base config.

- **BR-7 — Step 7a summary comment always posted**: Whether all reviewers ran,
  some were skipped, or the gate hard-failed, a summary comment must be posted
  to the PR before the gate exits. The comment must list: effective reviewer set,
  skipped reviewers (if any) with reason, and the final verdict. In the hard-fail
  case (Use Case 2), the error/blocked comment doubles as the summary comment and
  must include the same required fields (effective reviewer set = none, skipped
  reviewers = all listed with reason `unreachable`, verdict = `hard-fail`).

- **BR-8 — Runner identity is the availability proxy**: The runtime-availability
  check is based on the known runner context (e.g., "Claude Code subagent" knows
  it cannot invoke Codex CLI). A manifest-declared runner-to-reviewer mapping
  (longer-term) would make this check more explicit, but for now the runner
  protocol itself declares which reviewers it can invoke.

---

## Operational Visibility

- **PR Comments**: The Work Item Runner posts a warning comment to the PR
  whenever a reviewer is skipped due to being unreachable. The comment names the
  skipped reviewer and the runner context.
- **Step 7a Summary Comment**: A summary comment is always posted at the end of
  Step 7a, listing effective reviewers, skipped reviewers, and the final verdict.
  This comment is analogous to the "Automated Reviewer Loop Summary" in Step 7.
- **Console / Agent Log**: The warning and skip events are logged to the agent
  output so the Portfolio Orchestrator can observe them without querying the PR.
- **Audit Trail**: The PR comment history serves as the audit trail for reviewer
  availability gaps. Human reviewers can inspect it before merging.

---

## Acceptance Criteria

- [ ] When Step 7a is entered with `internal_reviewers: [claude, codex]` and
      `codex` is not reachable from the current runner, the runner emits a
      warning log and posts a warning comment to the draft PR identifying `codex`
      as unreachable and skipped.
- [ ] The warning comment appears before any reviewer is dispatched, so the PR
      history is complete even if a subsequent reviewer fails.
- [ ] `codex` being unreachable does not cause the gate to treat it as
      `APPROVED`. The skipped reviewer is listed as `skipped (unreachable)` in
      the Step 7a summary.
- [ ] When `claude` (the only reachable reviewer) returns `APPROVED`, the Step
      7a gate succeeds and `gh pr ready` is called, converting the PR to
      non-draft.
- [ ] The Step 7a summary comment lists: effective reviewer set, skipped
      reviewers (with reason), and the final verdict.
- [ ] When ALL listed reviewers are unreachable, the gate hard-fails, posts a
      blocking error comment, and the PR remains in draft state. The item is
      escalated to human.
- [ ] The `warn` policy (default) allows the gate to proceed with a reduced
      reviewer set as long as at least one reviewer is reachable and returns
      `APPROVED`.
- [ ] A local `.tmp/template-config.json` override for `internal_reviewers`
      suppresses the unavailability warning for reviewers that were explicitly
      excluded from the override list, and logs that the override was applied.
- [ ] Protocol 91 Step 7a wording is updated to include the runtime-availability
      check, the skip/warn/fail logic, and the summary comment requirement.

---

## Out of Scope (MVP)

- Implementing a manifest-based runner-to-reviewer capability declaration (the
  longer-term approach mentioned in the issue). This spec covers the runtime
  check at execution time; a static manifest is a follow-on improvement.
- Changing which reviewers are listed in `.ai-dev-workflow.yaml` — scope is
  limited to adding the availability check and fallback logic.
- Adding new reviewer types beyond `claude` and `codex`.
- Modifying `pr-review-loop.sh`, `post-merge-cleanup.sh`, Protocol 90 batching
  logic, or the worktree-discipline sections of Protocol 91 Steps 3-4 (those
  are the targets of #184, #192, #193).
- Implementing automated re-dispatch of skipped reviewers when a supporting
  runner becomes available.
