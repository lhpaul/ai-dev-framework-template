# AI Evaluation Layer for PR-Agent "Possible Issue" Findings — Implementation Plan

**Spec**: [1_562-pr-agent-ai-evaluation-layer_specs.md](./1_562-pr-agent-ai-evaluation-layer_specs.md)
**Smoke test runbook**: [../../../testing/workflow/562-pr-agent-ai-evaluation-layer.smoke-test.md](../../../testing/workflow/562-pr-agent-ai-evaluation-layer.smoke-test.md)

---

## Summary

**Approach**: Add a new function `run_pr_agent_possible_issue_evaluation` to
`pr-review-loop.sh` and call it from the two `clean` result paths inside
`run_pr_agent_review`. The function extracts "Possible Issue" labels from the
advisory label set, short-circuits if none are found, and otherwise dispatches
the `code-reviewer` agent (via a `gh pr comment` message to the orchestrator
caller) with the PR-Agent comment body and PR number. The caller interprets
the agent's verdict: if a fix was pushed the loop re-runs from the top; if the
finding is acknowledged the loop emits `clean`. If the agent is unavailable the
function logs a warning and exits cleanly, preserving the existing advisory-only
behaviour.

**Estimated complexity**: M

**Rationale**: The change is confined to a single shell script
(`pr-review-loop.sh`) plus a new output key (`POSSIBLE_ISSUE_EVAL_OUTCOME`) and
a smoke test runbook. The agent dispatch is expressed as a structured instruction
to the orchestrator caller rather than a direct agent invocation inside Bash,
keeping the script's Unix conventions intact. No new external dependencies are
introduced; the fallback path (advisory-only) is a trivial `return 0`.

**Dependencies**: None

---

## Verification Log

| Check                                                | Command / query                                                                              | Result                                                                                     |
| ---------------------------------------------------- | -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Repo revision                                        | `git rev-parse --short HEAD`                                                                 | `ddeb154`                                                                                  |
| Occurrences of "Possible Issue" in pr-review-loop.sh | `grep -c "Possible Issue" scripts/development-workflow/pr-review-loop.sh`                    | 1 (only in a comment; no runtime handling exists yet)                                      |
| Advisory label extraction function                   | `grep -n "_pr_agent_extract_advisory_labels" scripts/development-workflow/pr-review-loop.sh` | Lines 1114–1139 (function body), 1206, 1284 (call sites)                                   |
| Clean result paths in run_pr_agent_review            | Lines 1203–1223 (Phase 1 clean path) and 1281–1301 (Phase 3 clean path)                      | Two symmetric `clean` case blocks; both emit `ADVISORY_LABELS`                             |
| Aggregate clean exit                                 | Line 2651–2657                                                                               | Final `case "$aggregate_result" in clean)` block calls `_post_review_summary` and `exit 0` |
| Smoke test directory                                 | `ls docs/testing/workflow/`                                                                   | Confirmed path exists; naming pattern is `<issue>-<slug>.smoke-test.md`                    |

---

## Layer-by-Layer Changes

### Scripts / Automation Layer

- [ ] **`scripts/development-workflow/pr-review-loop.sh`** — add the
      `run_pr_agent_possible_issue_evaluation` function (see Architecture section)
      and call it from both `clean` case blocks inside `run_pr_agent_review`
      (Phase 1 and Phase 3).

  Specifically:
  - Add helper `_extract_possible_issue_labels` that filters the pipe-delimited
    advisory label string and returns only entries whose label matches
    `"Possible Issue"` (case-insensitive). Returns empty string when no match.
  - Add main function `run_pr_agent_possible_issue_evaluation` that:
    1. Calls `_extract_possible_issue_labels` on the advisory label string.
    2. Returns immediately (clean short-circuit) when no "Possible Issue" labels
       are found.
    3. Emits a structured `PR_AGENT_POSSIBLE_ISSUE_EVAL` output key containing
       the finding text and PR metadata for the orchestrator caller to consume
       when dispatching the code-reviewer agent.
    4. Reads the eval outcome from `POSSIBLE_ISSUE_EVAL_OUTCOME` env var
       (set by the orchestrator after the agent finishes); valid values:
       `fix_pushed` (loop should re-run), `acknowledged` (proceed clean),
       `unavailable` (fall back to advisory-only).
    5. Returns exit code `0` for `acknowledged` and `unavailable`; returns exit
       code `3` (new sentinel: "re-run requested") for `fix_pushed`.
    6. When `unavailable`: emits a `WARN` line to stderr and includes the
       advisory label in the loop summary unchanged.
  - In the Phase 1 `clean` case block: after extracting `_advisory_labels`,
    call `run_pr_agent_possible_issue_evaluation`. If it exits `3`, set
    `verdict="rerun_requested"` and handle at call-site (return non-zero so the
    caller re-invokes `run_pr_agent_review` on the new HEAD).
  - In the Phase 3 `clean` case block: apply the same pattern.
  - Add `POSSIBLE_ISSUE_EVAL_OUTCOME` to the `print_kv` output when the
    evaluation ran (values: `fix_pushed`, `acknowledged`, `unavailable`, or
    absent when no "Possible Issue" label was present).

- [ ] **`scripts/development-workflow/pr-review-loop.sh`** — update
      `_post_review_summary` to include the evaluation outcome in the advisory
      section text when `POSSIBLE_ISSUE_EVAL_OUTCOME` is set.

### Documentation / Protocol Layer

- [ ] **`docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`**
      — add a subsection under "Procedure (per PR)" that describes the new
      "Possible Issue" evaluation step: when it runs, how the orchestrator caller
      dispatches the code-reviewer agent, and how the outcome is fed back via
      `POSSIBLE_ISSUE_EVAL_OUTCOME`.

- [ ] **`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`**
      — add a note in Step 7 (or the Step 7 → automated reviewer loop description)
      explaining that when `pr-review-loop.sh` emits `PR_AGENT_POSSIBLE_ISSUE_EVAL`,
      the Work Item Runner must dispatch the code-reviewer agent and then re-invoke
      the loop with `POSSIBLE_ISSUE_EVAL_OUTCOME` set.

### Testing Layer

- [ ] **`docs/testing/workflow/562-pr-agent-ai-evaluation-layer.smoke-test.md`**
      — new smoke test runbook covering all six acceptance criteria.

---

## Architecture

### New function: `_extract_possible_issue_labels`

<!-- Illustrative — adapt during implementation -->

```bash
# Returns pipe-delimited labels that match "possible issue" (case-insensitive).
# Input: pipe-delimited advisory labels string (e.g. "Possible Issue|Edge Case")
# Output: pipe-delimited matching labels, or empty string.
_extract_possible_issue_labels() {
  local advisory="$1"
  local result=""
  local label
  local _labels_normalized
  _labels_normalized="$(printf '%s' "$advisory" | tr '|' '\n')"
  while IFS= read -r label; do
    [ -z "$label" ] && continue
    local label_lower
    label_lower="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')"
    if [ "$label_lower" = "possible issue" ]; then
      if [ -n "$result" ]; then
        result="${result}|${label}"
      else
        result="$label"
      fi
    fi
  done <<_EXTRACT_POSSIBLE_ISSUE_LABELS_
$_labels_normalized
_EXTRACT_POSSIBLE_ISSUE_LABELS_
  printf '%s' "$result"
}
```

### New function: `run_pr_agent_possible_issue_evaluation`

<!-- Illustrative — adapt during implementation -->

```bash
# Evaluate "Possible Issue" advisory labels found in a PR-Agent clean result.
# Reads POSSIBLE_ISSUE_EVAL_OUTCOME from environment (set by orchestrator caller).
# Returns:
#   0  — no "Possible Issue" label found (short-circuit), OR
#         finding acknowledged, OR agent unavailable (advisory-only fallback)
#   3  — fix was pushed; caller must re-run the loop on the new HEAD
run_pr_agent_possible_issue_evaluation() {
  local advisory_labels="$1"  # pipe-delimited, already extracted from comment
  local comment_body="$2"     # full PR-Agent comment body (for agent context)
  local pr_number="$3"
  local branch_name="$4"

  local possible_issue_labels
  possible_issue_labels="$(_extract_possible_issue_labels "$advisory_labels")"

  # Short-circuit: no "Possible Issue" advisory labels present.
  if [ -z "$possible_issue_labels" ]; then
    return 0
  fi

  # Emit structured key for the orchestrator caller to consume.
  print_kv PR_AGENT_POSSIBLE_ISSUE_EVAL "${pr_number}@@@${branch_name}"
  print_kv_escaped PR_AGENT_POSSIBLE_ISSUE_BODY "$comment_body"

  # Read the eval outcome set by the orchestrator after code-reviewer agent finishes.
  local eval_outcome="${POSSIBLE_ISSUE_EVAL_OUTCOME:-}"

  case "$eval_outcome" in
    fix_pushed)
      print_kv POSSIBLE_ISSUE_EVAL_OUTCOME "fix_pushed"
      return 3  # sentinel: re-run the loop
      ;;
    acknowledged)
      print_kv POSSIBLE_ISSUE_EVAL_OUTCOME "acknowledged"
      return 0
      ;;
    unavailable|"")
      echo "WARN: code-reviewer agent unavailable or eval outcome not set for 'Possible Issue' finding — falling back to advisory-only (clean)" >&2
      print_kv POSSIBLE_ISSUE_EVAL_OUTCOME "unavailable"
      return 0
      ;;
    *)
      echo "WARN: unknown POSSIBLE_ISSUE_EVAL_OUTCOME '${eval_outcome}' — falling back to advisory-only (clean)" >&2
      print_kv POSSIBLE_ISSUE_EVAL_OUTCOME "unavailable"
      return 0
      ;;
  esac
}
```

### Call site integration

In both `clean` case blocks of `run_pr_agent_review` (Phase 1 and Phase 3),
after extracting `_advisory_labels`, call:

<!-- Illustrative — adapt during implementation -->

```bash
# After: _advisory_labels="$(_pr_agent_extract_advisory_labels "$comment_body")"
local _eval_status=0
run_pr_agent_possible_issue_evaluation \
  "$_advisory_labels" "$comment_body" "$pr_number" "$branch_name" || _eval_status=$?
if [ "$_eval_status" -eq 3 ]; then
  # Fix was pushed — signal to caller to re-run.
  print_kv RESULT needs_rerun
  print_kv PLATFORM "$platform"
  print_kv PR_NUMBER "$pr_number"
  print_kv BRANCH "$branch_name"
  print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
  return 3
fi
# Evaluation complete (acknowledged or unavailable) — fall through to clean emission.
```

### Orchestrator-side handling

The Work Item Runner (Protocol 91) and the automated reviewer loop agent (Protocol 93)
must handle the new `RESULT=needs_rerun` / exit-3 output from `run_pr_agent_review`:

1. Check whether `PR_AGENT_POSSIBLE_ISSUE_EVAL` is set in the script output.
2. If set: dispatch the `code-reviewer` agent with:
   - The PR number and branch
   - The PR-Agent comment body (from `PR_AGENT_POSSIBLE_ISSUE_BODY`)
   - Instruction: determine whether the finding is a real bug or acceptable;
     if a real bug, push a fix commit; if acceptable, post a substantive
     acknowledgment comment on the PR explaining the reasoning.
3. After the agent finishes:
   - If agent pushed a fix: set `POSSIBLE_ISSUE_EVAL_OUTCOME=fix_pushed` and
     re-invoke `pr-review-loop.sh` from the top (normal re-run cycle).
   - If agent posted an acknowledgment: set `POSSIBLE_ISSUE_EVAL_OUTCOME=acknowledged`
     and re-invoke `pr-review-loop.sh` so it re-reads the PR-Agent comment and
     exits clean on this HEAD.
   - If agent is unavailable / timed out: set `POSSIBLE_ISSUE_EVAL_OUTCOME=unavailable`
     and re-invoke `pr-review-loop.sh` so it falls back to advisory-only.

---

## Testing Strategy

**Test types**: Smoke (manual workflow execution)

**Key scenarios to test**:

1. **Possible Issue present — real bug**: Run loop on a PR where PR-Agent returns
   clean with a "Possible Issue" advisory. Verify the code-reviewer agent is
   dispatched, a fix commit is pushed, and the loop re-runs from the top.
   Maps to Acceptance Criterion 2.

2. **Possible Issue present — acceptable finding**: Run loop on a PR where PR-Agent
   returns clean with a "Possible Issue" advisory. Configure the agent to
   acknowledge the finding. Verify a substantive acknowledgment comment is posted
   and the loop exits clean.
   Maps to Acceptance Criteria 1 and 3.

3. **Other advisory labels only**: Run loop on a PR where PR-Agent returns clean
   with advisory labels that are NOT "Possible Issue" (e.g., "Edge Case",
   "Logic Gap"). Verify no code-reviewer agent dispatch occurs and the loop
   exits clean immediately.
   Maps to Acceptance Criterion 4.

4. **Spec/chore PR with Possible Issue**: Run loop on a spec or chore PR
   (implementation-plan/\* branch) where PR-Agent returns a "Possible Issue"
   advisory. Verify the evaluation sub-step runs (not exempted) and exits clean
   after acknowledgment.
   Maps to Acceptance Criterion 5.

5. **Agent unavailable fallback**: Simulate agent dispatch failure
   (POSSIBLE_ISSUE_EVAL_OUTCOME unset or empty). Verify the loop logs a
   warning, emits `POSSIBLE_ISSUE_EVAL_OUTCOME=unavailable`, and exits clean
   with the advisory label still present in the loop summary.
   Maps to Acceptance Criterion 6.

6. **No advisory labels (baseline)**: Run loop on a PR where PR-Agent returns
   "No major issues detected". Verify no evaluation step is triggered.
   Maps to Acceptance Criterion 1 (negative path).

**Smoke test runbook**: `docs/testing/workflow/562-pr-agent-ai-evaluation-layer.smoke-test.md`

---

## Seed Data

| Entity                                 | Values / Scenario                                                                                | File              |
| -------------------------------------- | ------------------------------------------------------------------------------------------------ | ----------------- |
| Test PR with "Possible Issue" advisory | Any open PR in the repo can be used; the smoke test describes how to simulate the advisory label | N/A — see runbook |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
      — add subsection describing the "Possible Issue" evaluation step and how the
      orchestrator caller handles `PR_AGENT_POSSIBLE_ISSUE_EVAL` output.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      — add note in the Step 7 description about `PR_AGENT_POSSIBLE_ISSUE_EVAL`
      dispatch and `POSSIBLE_ISSUE_EVAL_OUTCOME` feedback loop.

---

## Risks & Mitigations

| Risk                                                                            | Likelihood | Impact | Mitigation                                                                                                                                                             |
| ------------------------------------------------------------------------------- | ---------- | ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `POSSIBLE_ISSUE_EVAL_OUTCOME` env var not set by caller                         | Med        | Low    | Treat empty value as `unavailable`; fallback is advisory-only (no blocking)                                                                                            |
| PR-Agent comment body contains shell-unsafe characters                          | Low        | Med    | Use `print_kv_escaped` for `PR_AGENT_POSSIBLE_ISSUE_BODY`; orchestrator reads via `kv_value` which handles escaped newlines                                            |
| New `needs_rerun` RESULT value breaks existing callers                          | Low        | Med    | Existing callers read `RESULT` via `kv_value_default`; unknown values fall through to `escalate` in the main loop's `case` — add explicit `needs_rerun` handling there |
| Re-run loop subject to existing retry limits                                    | Low        | Low    | Spec explicitly states re-runs are subject to existing retry limits; no special bypass needed                                                                          |
| "Possible Issue" label string varies in capitalisation across PR-Agent versions | Low        | Low    | Matching is case-insensitive (see `_extract_possible_issue_labels`)                                                                                                    |

---

## Code Samples

> All code above is **illustrative** — adapt during implementation. Function
> signatures, variable names, and exact shell idioms must be verified against the
> current state of `pr-review-loop.sh` at implementation time.

---

## Implementation Order

1. **Add `_extract_possible_issue_labels` to `pr-review-loop.sh`** — insert near
   the existing `_pr_agent_extract_advisory_labels` function (around line 1114).
   Verify: call the function with a pipe-delimited test string containing
   "Possible Issue" and confirm it returns only that label.

2. **Add `run_pr_agent_possible_issue_evaluation` to `pr-review-loop.sh`** —
   insert after `_extract_possible_issue_labels`. Verify: with
   `POSSIBLE_ISSUE_EVAL_OUTCOME=acknowledged` the function returns 0; with
   `POSSIBLE_ISSUE_EVAL_OUTCOME=fix_pushed` it returns 3; with an empty
   `POSSIBLE_ISSUE_EVAL_OUTCOME` it returns 0 and emits a WARN to stderr.

3. **Wire call site in Phase 1 `clean` block** (around line 1203) — add the
   evaluation call and `needs_rerun` return path. Verify: with
   `POSSIBLE_ISSUE_EVAL_OUTCOME=fix_pushed` the `run_pr_agent_review` function
   now returns exit 3 and emits `RESULT=needs_rerun`.

4. **Wire call site in Phase 3 `clean` block** (around line 1281) — same
   pattern as Step 3. Verify: same outcome under same conditions.

5. **Add `needs_rerun` handling to the outer `run_platform_review` / main
   loop** — in `run_platform_review`, propagate exit 3 from
   `run_pr_agent_review`. In the outer platform loop, when
   `platform_result=needs_rerun`, set `aggregate_result="needs_rerun"` and
   break (same as `needs_fixes` but triggers a loop re-run rather than a
   fixer dispatch). Add `needs_rerun` handling in the final `case
"$aggregate_result"` block: emit `RESULT=needs_rerun` with exit code 3 so
   orchestrator callers distinguish it from `needs_fixes`.

6. **Update `_post_review_summary`** — when `POSSIBLE_ISSUE_EVAL_OUTCOME` is set
   in the output, append the outcome to the advisory section text (e.g.,
   "Evaluated by code-reviewer: acknowledged" or "fix pushed — loop re-ran").

7. **Update Protocol 93** (`93-automated-reviewer-loop-protocol.md`) — add a
   subsection under "Procedure (per PR)" documenting the "Possible Issue"
   evaluation step and the orchestrator dispatch contract. Verify: the new
   section references `PR_AGENT_POSSIBLE_ISSUE_EVAL` and
   `POSSIBLE_ISSUE_EVAL_OUTCOME` by name.

8. **Update Protocol 91** (`91-orchestrate-work-protocol.md`) — add a note in
   the Step 7 automated reviewer loop description about the new output key and
   how the Work Item Runner handles it. Verify: the note appears in the Step 7
   section (not Steps 7a or 7b).

9. **Verify the smoke test runbook** — execute the runbook steps for each of
   the six acceptance criteria (using the `POSSIBLE_ISSUE_EVAL_OUTCOME`
   environment variable to simulate different agent verdicts in local testing).

10. **Update `CHANGELOG.md`** under `[Unreleased]`:

    ```
    - **Add AI evaluation layer for PR-Agent "Possible Issue" findings** (#562): When
      PR-Agent returns clean with a "Possible Issue" advisory label, the reviewer loop
      now dispatches the code-reviewer agent to evaluate the finding. If a real bug is
      found the agent pushes a fix and the loop re-runs; if the finding is acceptable
      the agent posts a substantive acknowledgment comment and the loop proceeds clean.
      Other advisory labels remain non-blocking and unevaluated. A fallback to
      advisory-only behaviour is preserved when the agent is unavailable.
    ```
