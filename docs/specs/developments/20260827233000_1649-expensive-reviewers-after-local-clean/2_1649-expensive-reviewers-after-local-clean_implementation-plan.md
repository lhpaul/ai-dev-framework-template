# Run Expensive Reviewers Only After Local Clean Evidence — Implementation Plan

**Spec**: None — Refactor item. Source brief:
[issue #1649](https://github.com/lhpaul/ai-dev-framework-template/issues/1649)
(epic [#1647](https://github.com/lhpaul/ai-dev-framework-template/issues/1647))
**Smoke test runbook**:
[1649-expensive-reviewers-after-local-clean.smoke-test.md](../../../testing/workflow/1649-expensive-reviewers-after-local-clean.smoke-test.md)

---

## Summary

**Approach**: The reviewer loop already has a phase mechanism —
`phase_after_clean_platforms` (alias `ready_phase_platforms`) — that holds a
platform back until the loop reaches it, and the loop breaks out before that
point when an earlier platform returns non-clean. What the phase gate does *not*
check is whether the accumulated evidence is (a) about the current head and
(b) complete: it evaluates only earlier reviewer verdicts from this same run,
never review threads, never baseline CI, and it has no notion of a stale local
clean result. This plan adds a dedicated pre-dispatch gate for `codex-github`
that requires four current-head conditions — local reviewer clean and current,
PR-Agent clean, zero unresolved review threads, and green non-reviewer baseline
checks — evaluated immediately before the platform is dispatched, fail-closed
when any input is missing or stale, with one explicit documented override for
manual escalation.

**Estimated complexity**: L

**Rationale**: The gate itself is a bounded addition, but it sits on the loop's
hottest control path, must compose with three existing mechanisms that already
decide whether a platform runs (`phase_after_clean`, `--pre-after-clean-only`,
and the cycle caps), and it consumes evidence that sibling item #1648
introduces. Getting the composition wrong either makes the gate inert or
silently stops `codex-github` from ever running, and both failures are invisible
in a green check rollup.

**Dependencies**: **#1648 must be merged to
`develop-internal-reviewer-effectiveness` before this item's implementation
PR opens.** This plan consumes `LOCAL_AI_CONFIGURED` and
`LOCAL_AI_HEAD_CURRENT`, which #1648 introduces, and the fail-closed semantics
this gate applies to a missing `LOCAL_AI_CONFIGURED` are the ones #1648 defines.
The plan PRs are independent and may be reviewed in parallel; only the
implementation is ordered.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `7998d43d` (base `develop-internal-reviewer-effectiveness`) |
| Phase mechanism exists | `grep -n "phase_after_clean_platforms\|append_ready_phase_platforms" scripts/development-workflow/pr-review-loop.sh` | `append_ready_phase_platforms` delegates to `append_phase_after_clean_platforms`; `is_phase_after_clean_platform` decides membership; the ready-phase list is emitted as `READY_PHASE_PLATFORM_LIST` |
| Phase gate contents | `sed -n '8576,8616p' scripts/development-workflow/pr-review-loop.sh` | Before the first phase platform runs, the loop calls `ensure_pr_ready_for_ready_phase` and nothing else; that function only reads `isDraft` and runs `gh pr ready` |
| Gate checks no evidence | `sed -n '6211,6256p' scripts/development-workflow/pr-review-loop.sh` | `ensure_pr_ready_for_ready_phase` inspects draft state and the rate limit only — no head SHA, no review threads, no CI, no reviewer verdicts |
| Non-clean short-circuit is per-run | Observed on PR #1660: a cycle where `local-ai-reviewer` returned `needs_fixes` emitted `READY_PHASE_SKIP_REASON=needs_fixes` and `PHASE_AFTER_CLEAN_STARTED=0`; a later clean cycle emitted `PHASE_AFTER_CLEAN_STARTED=1` | The existing hold-back works, but it is decided entirely by verdicts collected within the same invocation |
| `codex-github` dispatch path | `grep -n "codex-github" scripts/development-workflow/pr-review-loop.sh` | Dispatched via `run_codex_github_review` at the `codex-github)` case of `run_platform_review`; `codex_github_defaults_should_apply` already tests membership with `array_contains_value` |
| `codex-github` is not configured here | `sed -n '/^review:/,/^ *guardrails:/p' .ai-dev-workflow.yaml` | This repository's `on_draft.github` is `local-ai-reviewer, pr-agent` and `on_ready.github` is `bugbot`; `codex-github` appears in neither, so the gate must be inert-by-absence here and exercised through harness fixtures |
| Evidence keys come from #1648 | `gh pr view 1660 --json state --jq .state` and the plan on that PR | `LOCAL_AI_CONFIGURED` / `LOCAL_AI_HEAD_CURRENT` are defined by #1648, whose plan PR #1660 is `ready-for-human-review` and not yet merged |
| Baseline vs reviewer checks | `grep -n "REVIEWER_CHECKS\|REVIEWER_CHECK_COUNT" scripts/development-workflow/pr-ci-loop.sh` | `pr-ci-loop.sh` already separates reviewer-owned checks from baseline checks and emits `REVIEWER_CHECKS` / `REVIEWER_CHECKS_JSON`, so the gate can reuse that classification rather than inventing one |
| `codex-github` integration doc exists | `ls docs/workflow/development-workflow/integrations/` | `codex-github.md` is present alongside `local-ai-reviewer.md`, `pr-agent.md`, and `bugbot.md`, so the gate's documentation target already exists and no new file is created |
| Reviewer-loop protocol target | `grep -c "" docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` | 1142 lines; this is the protocol that documents loop behavior, and is the right home for the gate's normative description |
| Cycle caps | `grep -n "MAX_CYCLES\|MAX_TOTAL_CYCLES" scripts/development-workflow/pr-review-loop.sh` | Dual caps (`max_cycles` per run, `max_total_cycles` per PR lifetime) already bound retries; the gate must not add a retry path outside them |

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved base branch for this item | `develop-internal-reviewer-effectiveness` | `integration-branch:internal-reviewer-effectiveness` label on #1649; Protocol 91 § Integration-branch base override | 2026-08-27, repo SHA `7998d43d` | Epic #1647 items #1648–#1657; the only other open PR on this base is #1660 (#1648's plan) | `Verified` |
| Source of the current-head local evidence | `LOCAL_AI_CONFIGURED` / `LOCAL_AI_HEAD_CURRENT` from #1648 | #1648's implementation plan on PR #1660 | 2026-08-27, repo SHA `7998d43d` | #1648 and #1649 only | `Conflict` — see below |

**Conflict record.** The evidence keys this gate consumes do not exist on the
base branch yet: #1648's plan PR #1660 is `ready-for-human-review` and unmerged,
so no implementation has landed. Affected plan statements: every reference to
`LOCAL_AI_CONFIGURED` and `LOCAL_AI_HEAD_CURRENT`, and the fail-closed rule for
a missing local evidence key.

**Resolution status**: `Resolved` by sequencing, not by weakening the plan. This
is a plan-stage artifact; the ordering requirement is recorded in
**Dependencies** and enforced in **Implementation Order** step 0, which stops
before any code change if #1648 is not merged into
`develop-internal-reviewer-effectiveness`. Decision owner: LH — if #1648 is
rejected or materially changed in human review, this plan must be revised before
implementation rather than adapted during it.

---

## Layer-by-Layer Changes

### Backend / API

Not applicable — this repository ships workflow tooling, not a service.

### Shared Packages / Libraries

`scripts/development-workflow/pr-review-loop.sh` (shell contract: `bash`):

- [ ] Add `EXPENSIVE_REVIEWER_PLATFORMS`, a constant list whose only member is
      `codex-github`. The gate keys off this list rather than hard-coding the
      platform name at the call site, so a later item can add a second expensive
      reviewer without touching the gate logic. It is intentionally not
      configurable from `.ai-dev-workflow.yaml`: which reviewers are expensive is
      a property of the reviewer, not of the repository.
- [ ] Add `is_expensive_reviewer_platform <platform>` using the existing
      `array_contains_value` helper, mirroring `is_phase_after_clean_platform`.
- [ ] Add `expensive_reviewer_gate <pr_number> <platform> <head_sha>` returning
      `0` to dispatch and `1` to hold back, and printing one
      `EXPENSIVE_GATE_*` key=value block. It evaluates four conditions against
      `loop_head_sha` (the pre-dispatch snapshot #1648 makes authoritative) and
      **stops at the first unmet one**, so the reported reason names a single
      cause:

      | # | Condition | Unmet reason |
      | --- | --- | --- |
      | 1 | `LOCAL_AI_CONFIGURED` is `1` and `LOCAL_AI_HEAD_CURRENT` is `1` | `local_evidence_stale` when `LOCAL_AI_HEAD_CURRENT` is `0`; `local_evidence_missing` when it is empty or `LOCAL_AI_CONFIGURED` is unset; `local_reviewer_not_configured` when `LOCAL_AI_CONFIGURED` is `0` |
      | 2 | Every non-expensive platform already run in this invocation returned `clean` or `skipped` | `peer_reviewer_not_clean` |
      | 3 | Zero unresolved, non-outdated review threads at `loop_head_sha` | `unresolved_threads` |
      | 4 | Every non-reviewer check on `loop_head_sha` is `SUCCESS`, `SKIPPED`, or `NEUTRAL` | `baseline_checks_not_green` when one failed; `baseline_checks_pending` when one is still running |

- [ ] **Fail closed on every unknown.** If any input cannot be read, the gate
      holds the platform back with one of exactly three reasons — there is no
      generic unknown state:

      | Unreadable input | Reason |
      | --- | --- |
      | `loop_head_sha` is empty (the pre-dispatch head read failed) | `evidence_unavailable_head` |
      | The review-threads query failed | `evidence_unavailable_review_threads` |
      | The check-rollup query failed | `evidence_unavailable_checks` |

      Holding back is cheap — the expensive reviewer runs on the next
      invocation — while dispatching on unknown evidence is the waste this item
      exists to remove. The gate never fails the loop: it returns `1`, and the
      loop records the platform as skipped rather than as a blocking verdict, so
      the aggregate result is unchanged.
- [ ] Call the gate from the per-platform block, immediately before
      `run_platform_review`, only when `is_expensive_reviewer_platform` matches.
      It composes with the existing phase mechanism rather than replacing it: a
      platform that is both a phase platform and an expensive reviewer must pass
      `ensure_pr_ready_for_ready_phase` **and** this gate, in that order, and
      `--pre-after-clean-only` still excludes phase platforms before either runs.
- [ ] **Explicit override**: `PR_REVIEW_LOOP_FORCE_EXPENSIVE_REVIEWERS=1`
      bypasses the gate for manual escalation. When set, the gate still
      evaluates and still emits its full `EXPENSIVE_GATE_*` block, then reports
      `EXPENSIVE_GATE_RESULT=forced` with the reason it would otherwise have
      given, and dispatches. The override never hides why the gate would have
      held back — a forced run that later wastes reviewer cycles must be
      traceable to the condition that was overridden.
- [ ] Emit gate telemetry on the loop's stdout contract, per expensive platform:
      `EXPENSIVE_GATE_PLATFORM`, `EXPENSIVE_GATE_RESULT`
      (`dispatched` | `held` | `forced`), `EXPENSIVE_GATE_REASON` (empty when
      `dispatched`), and `EXPENSIVE_GATE_HEAD` (the `loop_head_sha` the gate
      evaluated). All values stay inside the `[A-Za-z0-9:_-]` token charset the
      Protocol 91 carry-forward snippet admits.
- [ ] Record the gate outcome in the reviewer-loop summary comment as an
      `**Expensive reviewer gate:**` line, and in the `reviewer_loop_history.v1`
      entry as an `expensive_gate` object (`platform`, `result`, `reason`,
      `head`). Both are additive; readers dereference with defaults, so the
      schema stays `v1`, consistent with #1648's treatment of `reviewed_heads`.
- [ ] Document the gate, its four conditions, its fail-closed rule, and the
      override variable in the `--help` usage block.

### Frontend / UI

Not applicable — no user interface in this repository.

### Infrastructure / Configuration

- [ ] No `.ai-dev-workflow.yaml` schema change. `codex-github` is already a
      valid value in `review.on_draft.github` / `review.on_ready.github`; the
      gate applies wherever it is configured. In this repository it is
      configured nowhere, so the gate is inert here by absence — which is why
      every scenario below is a harness fixture rather than a live run.

### Documentation

- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
      — document the gate: the four conditions, the fail-closed rule, the
      `held` outcome being a skip rather than a blocking verdict, and the
      override variable with the expectation that its use is justified in the PR.
- [ ] `docs/workflow/development-workflow/integrations/codex-github.md` — add a
      section describing the gate so a reader configuring the reviewer learns
      when it will actually run, when it will be held back, and how to override.
      The file exists (confirmed in the Verification Log); no new file is
      created.

---

## Testing Strategy

**Test types**: Unit (shell harness), plus the smoke test runbook.

**Key scenarios to test**:

1. `is_expensive_reviewer_platform` matches `codex-github` and rejects
   `local-ai-reviewer`, `pr-agent`, and `bugbot` — the gate must not
   accidentally hold back a cheap reviewer.
2. All four conditions met → `EXPENSIVE_GATE_RESULT=dispatched`,
   `EXPENSIVE_GATE_REASON` empty, and `run_platform_review` is called.
3. `LOCAL_AI_HEAD_CURRENT=0` → `held` / `local_evidence_stale`, and
   `run_platform_review` is **not** called — the core of brief scope bullet 1.
4. `LOCAL_AI_CONFIGURED` unset → `held` / `local_evidence_missing`. This is the
   fail-closed case for brief scope bullet 2 and pairs with #1648's rule that an
   absent key is telemetry loss rather than non-applicability.
5. `LOCAL_AI_CONFIGURED=0` → `held` / `local_reviewer_not_configured`. Distinct
   from scenario 4: the loop is correctly configured, there is simply no local
   evidence to gate on, and dispatching an expensive reviewer with no cheap
   pre-filter is exactly what this item prevents.
6. A peer reviewer returned `needs_fixes` earlier in the same invocation →
   `held` / `peer_reviewer_not_clean`.
7. One unresolved non-outdated review thread → `held` / `unresolved_threads`;
   the same thread marked outdated → `dispatched`.
8. A failing baseline check → `held` / `baseline_checks_not_green`; a pending
   one → `held` / `baseline_checks_pending`; a reviewer-owned check that is
   pending → `dispatched`, because a reviewer's own check must not gate the
   reviewer.
9. Each unreadable input in turn → `held` with its specific reason —
   `evidence_unavailable_head` for an empty `loop_head_sha`,
   `evidence_unavailable_review_threads` for a failed threads query,
   `evidence_unavailable_checks` for a failed check rollup — and the loop's
   aggregate result is unchanged in all three. The gate skips; it does not
   escalate.
10. `PR_REVIEW_LOOP_FORCE_EXPENSIVE_REVIEWERS=1` with condition 1 unmet →
    `EXPENSIVE_GATE_RESULT=forced`, `EXPENSIVE_GATE_REASON=local_evidence_stale`
    preserved, and `run_platform_review` **is** called — the override path of
    brief scope bullet 3, proving the reason survives the override.
11. Composition with the phase mechanism: a platform that is both a phase
    platform and an expensive reviewer runs `ensure_pr_ready_for_ready_phase`
    first and the gate second; when the gate holds, the PR has still been
    converted to ready and the loop does not treat the hold as a phase failure.
12. Composition with `--pre-after-clean-only`: an expensive reviewer that is
    also a phase platform is filtered out before the gate is consulted, and the
    gate emits no telemetry for it — no phantom `held` record for a platform
    that was never in scope.
13. A ledger entry written without `expensive_gate` still parses through
    `reviewer_loop_history_payload_from_existing` — `v1` backward compatibility,
    same contract as #1648's added fields.

**Files**:

- `scripts/development-workflow/tests/test-pr-review-loop.sh` — scenarios 1–9
  and 13, as new cases in the existing `HARNESS_MODE=1` harness.
- `scripts/development-workflow/tests/test-expensive-reviewer-gate.sh` — a new
  suite for scenarios 10–12, the composition and override cases, which need
  their own mock scaffolding for the phase and filter paths. It must declare:

  ```text
  # covers: scripts/development-workflow/pr-review-loop.sh
  # covers: docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md
  ```

  Both lines are required. In `select-test-suites.sh` the naming-convention
  fallback runs only when a suite declares nothing (`declared=0`), and the
  convention would map `test-expensive-reviewer-gate.sh` to a
  `scripts/development-workflow/expensive-reviewer-gate.sh` that does not exist,
  so this suite must declare its coverage explicitly or it would only ever run
  when the test file itself changes.

**Smoke test runbook**:
`docs/testing/workflow/1649-expensive-reviewers-after-local-clean.smoke-test.md`

**Regression suite**: The repository's regression surface is the
`workflow-tests.yml` harness selection; the two suites above are the regression
coverage for this change.

### Planted-violation proofs (mandatory before `ready-for-human-review`)

This plan adds a new automated gate, so `REVIEW.md` § Planted-violation proof
and `docs/best-practices/3-testing.md` § Planted-Violation Proofs apply, and the
pure-refactor exemption does not. Two demonstrated runs per proof, each citing a
concrete file and line:

| # | Violation to plant | Where | Check that must fail, then pass |
| --- | --- | --- | --- |
| P1 | Stale local evidence: `LOCAL_AI_HEAD_CURRENT=0` with all other conditions met | the gate fixture in `scripts/development-workflow/tests/test-pr-review-loop.sh` | the gate holds and `run_platform_review` is not called; setting it to `1` dispatches |
| P2 | Missing local evidence: `LOCAL_AI_CONFIGURED` unset | same fixture | the gate holds with `local_evidence_missing`; exporting `LOCAL_AI_CONFIGURED=1` dispatches — the proof that an unknown is refused rather than assumed clean |
| P3 | Unreadable evidence: make the review-threads query fail | same fixture | the gate holds with `evidence_unavailable_review_threads` and the loop's aggregate result is unchanged; restoring the query dispatches |
| P4 | Gate bypass regression: remove the `is_expensive_reviewer_platform` guard so the gate is never consulted | a scratch copy of the per-platform block | scenario 3 fails because the platform is dispatched with stale evidence; restoring the guard passes — the proof that the gate is actually wired into the dispatch path and not merely defined |

Record all four in the implementation PR under a `Planted-Violation Proofs`
heading, each with the command, the file and line of the planted violation, and
both outcomes.

### Parser-risk addendum

Not applicable. The gate compares tokens the loop already produces
(`LOCAL_AI_*` values, platform names, check conclusions) and performs no
text scanning, regex extraction, or structured-text parsing of its own. Review
threads and check conclusions are read through `gh --jq`, which is existing
parsing this plan does not modify.

### Concurrent-event-source addendum

Not applicable. The gate is evaluated synchronously inside the loop's existing
sequential per-platform iteration, holds no state between invocations, and
introduces no listeners, timers, or async callbacks. The one shared mutable
input is the per-invocation record of peer reviewer verdicts, which is written
by the same sequential block that already writes `platform_result_tokens`.

---

## Seed Data

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Gate condition fixture | A table-driven set of the four conditions with each one independently unmet, driving scenarios 2–8 | inline in `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Unreadable-input mocks | Mock `gh` commands that exit non-zero for the threads query and for the check rollup, driving scenario 9 and proof P3 | inline in `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Composition fixture | A platform list where `codex-github` is both a phase platform and an expensive reviewer, driving scenarios 11 and 12 | inline in `scripts/development-workflow/tests/test-expensive-reviewer-gate.sh` |
| Legacy ledger payload | A `reviewer_loop_history.v1` entry with no `expensive_gate` object, driving scenario 13 | inline heredoc in `scripts/development-workflow/tests/test-pr-review-loop.sh` |

No repository fixture files are added; both suites build their fixtures inline
with mock `gh` commands and require no network access.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
      — document the gate, its four conditions, the fail-closed rule, the `held`
      outcome being a skip rather than a blocking verdict, and the override
      variable.
- [ ] `docs/workflow/development-workflow/integrations/codex-github.md` — add a
      section describing the gate, its four conditions, and the override, so the
      gate is discoverable from the reviewer's own integration page rather than
      only from the loop protocol.
- [ ] `REVIEW.md` — no change. The gate decides when a reviewer runs, not what
      the review contract requires.
- [ ] `AGENTS.md` — no change. It does not enumerate reviewer-loop gates.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The gate silently stops `codex-github` from ever running | Med | High — the expensive reviewer's findings are the reason this epic exists; losing them entirely is worse than running it too often | Every hold emits `EXPENSIVE_GATE_RESULT=held` with a single named reason in both the summary comment and the ledger, so a permanent hold is visible rather than silent; scenario 2 pins the dispatch path and P4 proves the gate is wired in rather than defined-but-unreachable |
| The gate is defined but never consulted, leaving behavior unchanged | Med | High — the item would appear complete while changing nothing | The call site is in the per-platform block immediately before `run_platform_review`, and proof P4 removes the guard and requires scenario 3 to fail — a gate that is not wired in cannot pass its own proof |
| Fail-closed on unreadable evidence turns a transient API blip into a permanent hold | Med | Med | A hold is per-invocation, not sticky: the next loop invocation re-evaluates, and the existing dual cycle caps bound how many invocations happen. The gate adds no retry path of its own, so it cannot loop |
| The gate contradicts the existing phase mechanism | Med | High — two gates disagreeing on whether a platform runs is worse than either alone | Composition is specified explicitly (phase gate first, then this gate; `--pre-after-clean-only` filters before both) and pinned by scenarios 11 and 12, including the no-phantom-telemetry case |
| Implementation starts before #1648 lands and wires the gate to keys that do not exist | Med | High — the gate would read unset variables and hold everything, or be written against a guessed contract | Recorded as a Conflict in the Cross-Cutting check and as Implementation Order step 0, which is a hard stop that verifies #1648 is merged into the approved base before any edit |
| A reviewer's own check gates that reviewer | Low | Med — `codex-github` would wait on a check it is responsible for producing | Condition 4 evaluates non-reviewer checks only, reusing the reviewer/baseline classification `pr-ci-loop.sh` already emits rather than a new one; scenario 8's third case pins it |

---

## Code Samples

```bash
# Illustrative — adapt during implementation.
EXPENSIVE_REVIEWER_PLATFORMS=(codex-github)

is_expensive_reviewer_platform() {
  array_contains_value "$1" "${EXPENSIVE_REVIEWER_PLATFORMS[@]}"
}

# Returns 0 to dispatch, 1 to hold back. Never fails the loop.
# Stops at the first unmet condition so the reason names one cause.
expensive_reviewer_gate() {
  local pr_number="$1"
  local platform="$2"
  local head_sha="$3"
  local reason=""

  if [ -z "$head_sha" ]; then
    reason="evidence_unavailable_head"
  elif [ -z "${LOCAL_AI_CONFIGURED:-}" ]; then
    reason="local_evidence_missing"
  elif [ "$LOCAL_AI_CONFIGURED" = "0" ]; then
    reason="local_reviewer_not_configured"
  elif [ "${LOCAL_AI_HEAD_CURRENT:-}" = "0" ]; then
    reason="local_evidence_stale"
  elif [ -z "${LOCAL_AI_HEAD_CURRENT:-}" ]; then
    reason="local_evidence_missing"
  fi
  # ... conditions 2-4 follow the same shape, each appending its own reason ...

  print_kv EXPENSIVE_GATE_PLATFORM "$platform"
  print_kv EXPENSIVE_GATE_HEAD "$head_sha"
  if [ -n "$reason" ]; then
    print_kv EXPENSIVE_GATE_REASON "$reason"
    if [ "${PR_REVIEW_LOOP_FORCE_EXPENSIVE_REVIEWERS:-0}" = "1" ]; then
      print_kv EXPENSIVE_GATE_RESULT forced
      return 0
    fi
    print_kv EXPENSIVE_GATE_RESULT held
    return 1
  fi
  print_kv EXPENSIVE_GATE_RESULT dispatched
  print_kv EXPENSIVE_GATE_REASON ""
  return 0
}
```

Summary-comment line, illustrative:

```markdown
**Expensive reviewer gate:** codex-github — held (local_evidence_stale) at head `6780c658eebc8879d61e56842445749c1195b13f`
```

---

## Implementation Order

0. **Hard stop — dependency check.** Confirm #1648 is merged into
   `develop-internal-reviewer-effectiveness` and that
   `LOCAL_AI_CONFIGURED` / `LOCAL_AI_HEAD_CURRENT` exist in
   `pr-review-loop.sh` on the base branch. **Verify**:
   `gh pr view 1660 --json state,baseRefName` returns `MERGED` with the
   integration branch as base, and `grep -n 'LOCAL_AI_CONFIGURED'
   scripts/development-workflow/pr-review-loop.sh` on the rebased branch
   returns a hit. If either fails, stop and report — do not implement against a
   guessed contract.
1. Add `EXPENSIVE_REVIEWER_PLATFORMS` and `is_expensive_reviewer_platform` near
   the existing `is_phase_after_clean_platform` helper. **Verify**: source with
   `HARNESS_MODE=1` and confirm scenario 1's matches and non-matches.
2. Add `expensive_reviewer_gate` with conditions 1–4 in the documented order and
   the fail-closed branch for every unreadable input. **Verify**: drive the
   condition fixture and confirm each unmet condition yields its single named
   reason.
3. Wire the gate into the per-platform block immediately before
   `run_platform_review`, guarded by `is_expensive_reviewer_platform`.
   **Verify**: scenario 3 shows `run_platform_review` is not called on a hold.
4. Add the override branch and confirm the reason survives it. **Verify**:
   scenario 10.
5. Emit the four `EXPENSIVE_GATE_*` keys and document them in `--help`.
   **Verify**: run `pr-review-loop.sh --help` and confirm the gate, its four
   conditions, the fail-closed rule, and the override variable are described.
6. Add the summary-comment line and the `expensive_gate` ledger object.
   **Verify**: build an entry in the harness and confirm the object shape, and
   that a legacy entry without it still parses (scenario 13).
7. Update
   `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
   and
   `docs/workflow/development-workflow/integrations/codex-github.md` per
   **Documentation Updates**. **Verify**: both files describe the same four
   conditions, the same fail-closed rule, and the same override variable name.
8. Add the unit cases to `test-pr-review-loop.sh` and create
   `test-expensive-reviewer-gate.sh` with both `# covers:` lines.
   **Verify**: both suites exit 0, and
   `scripts/development-workflow/select-test-suites.sh` selects the new suite
   for a change touching only `pr-review-loop.sh`.
9. Produce the four planted-violation proofs (P1–P4) and record them in the PR
   under a `Planted-Violation Proofs` heading. **Verify**: each shows two runs
   at a concrete file and line — failing with the violation planted, passing
   once removed.
10. Run `shellcheck` on the changed script and `markdownlint-cli2` on the
    changed protocol document, this plan, and the runbook. **Verify**: both
    tools exit 0.
11. Add a changelog fragment
    `changelog.d/1649.changed.expensive-reviewers-after-local-clean.md`
    containing exactly:

    ```markdown
    - **Gate expensive reviewers on current-head local evidence** (#1649): `codex-github` now runs only after the local reviewer, peer reviewers, review threads, and baseline checks are clean on the current head, and holds back fail-closed when that evidence is missing or stale.
    ```

12. Update project docs per **Documentation Updates** above (step 7 covers
    them; no other project doc is affected).
