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
checks — evaluated immediately before the platform is dispatched, fail-closed when any input is
missing or stale, with one explicit documented override for manual escalation.
A gate that holds the reviewer back **defers** rather than skipping: it sets the
loop's aggregate to `needs_fixes` so readiness is withheld and Step 7 re-runs,
which is what makes the deferral guaranteed rather than merely hoped for.

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
| Cycle caps exist | `grep -n "MAX_CYCLES\|MAX_TOTAL_CYCLES" scripts/development-workflow/pr-review-loop.sh` | Dual caps are present: `max_cycles` per run and `max_total_cycles` per PR lifetime |
| Cycle caps cannot bound deferrals | `sed -n '7371,7390p' scripts/development-workflow/pr-review-loop.sh` | `reviewer_loop_history_entries_count` reduces qualifying entries with `unique` over `(.head_sha) + "\|" + (.result)` before counting, on both the lifetime and per-run axes. Repeated `needs_fixes` results on one unchanged head — the exact shape of a deferral loop — therefore collapse to a single count and advance neither cap. This is why the gate needs its own occurrence-counted, head-scoped deferral counter rather than reusing these |

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
      `0` to dispatch and `1` to defer, and printing one `EXPENSIVE_GATE_*`
      key=value block. It evaluates the conditions below against
      `loop_head_sha` (the pre-dispatch snapshot #1648 makes authoritative) and
      **stops at the first unmet one**, so the reported reason names a single
      cause.

      | # | Condition | Unmet reason |
      | --- | --- | --- |
      | 1 | `LOCAL_AI_CONFIGURED` is `1` and `LOCAL_AI_HEAD_CURRENT` is `1` | `local_evidence_stale` when `LOCAL_AI_HEAD_CURRENT` is `0`; `local_evidence_missing` when it is empty or `LOCAL_AI_CONFIGURED` is unset; `local_reviewer_not_configured` when `LOCAL_AI_CONFIGURED` is `0` |
      | 2 | **Every** non-expensive platform in the resolved platform list has already run in this invocation **and** returned `clean` or `skipped` | `peer_reviewer_not_run` when one has not run yet; `peer_reviewer_not_clean` when one ran and did not return clean or skipped |
      | 3 | Zero unresolved, non-outdated review threads | `unresolved_threads` |
      | 4 | Every non-reviewer check is `SUCCESS`, `SKIPPED`, or `NEUTRAL` | `baseline_checks_not_green` when one failed; `baseline_checks_pending` when one is still running |

- [ ] **Reorder expensive reviewers to the end of the platform list.** Add
      `reorder_expensive_reviewers_last`, called once after the platform list is
      resolved and before the iteration begins: it partitions `platforms` into
      non-expensive followed by expensive, preserving relative order within each
      partition. Detection alone is not enough — a configuration listing
      `codex-github` before `pr-agent` would otherwise defer at the same point on
      every invocation, because the loop would never reach `pr-agent` before the
      gate, and the deferral would never resolve. Reordering makes the gate's
      precondition reachable rather than merely checked. Emit
      `EXPENSIVE_REVIEWERS_REORDERED=1` and the reordered `PLATFORM_LIST` when
      the partition changed the order, so the behavior is visible rather than a
      silent rewrite of the caller's configuration.
- [ ] **Condition 2 compares against the full resolved list**
      (`platforms[@]` minus the expensive ones), not the results collected up to
      this index. After reordering, every non-expensive platform has run by the
      time the gate is consulted, so `peer_reviewer_not_run` is a defensive
      assertion rather than an expected outcome: if it ever fires, the reorder
      did not happen and the gate says so instead of silently dispatching.
- [ ] **Bind conditions 3 and 4 to the same head as the reviewer evidence.**
      Both queries must return the live head alongside their payload, and the
      gate must compare it to `loop_head_sha`. If they differ, the PR moved
      while the loop ran: the thread and check evidence describes a newer commit
      than the reviewer verdicts, and combining them would authorize dispatch on
      inconsistent evidence. Defer with `evidence_head_moved`. This mirrors the
      head-move guard the loop already applies to its own clean verdict, and
      reuses the same `loop_head_sha` snapshot rather than introducing a second
      notion of "current".
- [ ] **A defer is not a clean skip.** Recording a deferred expensive reviewer
      as `skipped` while leaving the aggregate result unchanged would let
      Protocol 92's readiness conditions accept the run — `Result: clean` or
      `Result: skipped` both satisfy them — so a PR could reach
      `ready-for-human-review` having never run the reviewer, and nothing would
      guarantee the "next invocation" this gate relies on. Instead, when the
      gate defers, the loop sets its aggregate to `needs_fixes` with
      `REASON=expensive_gate_deferred`. That is the loop's existing mechanism
      for "not finished yet": Protocol 91 re-runs Step 7 on a non-clean result,
      the readiness label is withheld, and the deferral is therefore guaranteed
      to be retried rather than merely hoped for.
- [ ] **Bound the deferrals with their own counter — the existing caps do not
      cover them.** `reviewer_loop_history_entries_count` buckets qualifying
      entries as `unique` over `head_sha + "|" + result`, so repeated
      `needs_fixes` results on one unchanged head collapse to a single count on
      both the per-run and lifetime axes. Deferrals are exactly that shape: the
      head does not move while the gate waits, so an unbounded number of
      deferral cycles would advance neither cap. Add a dedicated counter that
      reads the ledger for entries whose `expensive_gate.result` is `deferred`
      **and** whose `expensive_gate.head` equals the current `loop_head_sha`,
      counted as occurrences rather than uniques, bounded by
      `PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS` (default `3`). On reaching the
      cap the loop stops deferring and escalates with `RESULT=escalate` and
      `REASON=expensive_gate_deferral_cap`, naming the condition that kept
      failing, so a stuck gate reaches a human instead of cycling silently. The
      counter resets naturally when the head moves, because it is scoped to
      `loop_head_sha`.
- [ ] **The deferral counter is itself fail-closed.** If the ledger cannot be
      read or does not parse — the same `unavailable` state
      `reviewer_loop_history_entries_count` already reports as `-1` — the
      counter cannot prove the sequence is bounded, so the gate must not defer
      again on an unproven budget. It escalates immediately with
      `EXPENSIVE_GATE_RESULT=deferral_cap` and
      `REASON=expensive_gate_deferral_budget_unreadable`, carrying the
      condition that triggered the gate, and emits
      `EXPENSIVE_GATE_DEFERRALS=-1` so the unreadable state is distinguishable
      from a count of zero. Escalating on an unreadable budget is the
      conservative choice: a human sees the gate immediately, whereas deferring
      on an unknown budget is precisely the unbounded loop this counter exists
      to prevent.
- [ ] **A repository with no local reviewer defers, it does not dispatch.**
      When `LOCAL_AI_CONFIGURED` is `0` there is no current-head local clean
      evidence, and the brief requires `codex-github` to run *only after* that
      evidence exists and to fail closed when it is missing — it permits an
      explicit manual override, not an implicit automatic one. The gate
      therefore defers with `local_reviewer_not_configured`. The consequence for
      a consumer that deliberately does not configure `local-ai-reviewer` is
      handled by the deferral cap below, which escalates to a human after a
      bounded number of deferrals rather than blocking forever, and by
      `PR_REVIEW_LOOP_FORCE_EXPENSIVE_REVIEWERS` for a one-off run. Both are
      explicit; neither silently relaxes the gate.
- [ ] **Fail closed on every unknown.** If any input cannot be read, the gate
      defers with one of exactly three reasons — there is no generic unknown
      state:

      | Unreadable input | Reason |
      | --- | --- |
      | `loop_head_sha` is empty (the pre-dispatch head read failed) | `evidence_unavailable_head` |
      | The review-threads query failed | `evidence_unavailable_review_threads` |
      | The check-rollup query failed | `evidence_unavailable_checks` |

      Deferring is cheap — the expensive reviewer runs on the retry the
      `needs_fixes` aggregate forces — while dispatching on unknown evidence is
      the waste this item exists to remove.
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
      deferred — a forced run that later wastes reviewer cycles must be
      traceable to the condition that was overridden. A forced run does not set
      the `needs_fixes` aggregate: the human took the decision explicitly.
- [ ] Emit gate telemetry on the loop's stdout contract, per expensive platform:
      `EXPENSIVE_GATE_PLATFORM`, `EXPENSIVE_GATE_RESULT`
      (`dispatched` | `deferred` | `forced` | `deferral_cap`),
      `EXPENSIVE_GATE_REASON` (the unmet-condition reason; empty when
      `dispatched`), `EXPENSIVE_GATE_HEAD` (the `loop_head_sha` the gate
      evaluated), and `EXPENSIVE_GATE_DEFERRALS` (how many deferrals the ledger
      already records for this head, so the distance to the cap is visible
      before it trips). `EXPENSIVE_REVIEWERS_REORDERED` is emitted once per run,
      not per platform. All values stay inside the `[A-Za-z0-9:_-]` token charset the
      Protocol 91 carry-forward snippet admits.
- [ ] Record the gate outcome in the reviewer-loop summary comment as an
      `**Expensive reviewer gate:**` line, and in the `reviewer_loop_history.v1`
      entry as an `expensive_gate` object (`platform`, `result`, `reason`,
      `head`). Both are additive; readers dereference with
      defaults, so the schema stays `v1`, consistent with #1648's treatment of
      `reviewed_heads`.
- [ ] Document the gate in the `--help` usage block: its conditions and their
      evaluation order, its fail-closed rule, the `deferred` aggregate
      behavior, the bounded deferral counter and its escalation, the
      reordering of expensive reviewers to the end of the platform list, and
      the override variable.

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
      — document the gate: the conditions and their evaluation order, the
      order-independence of condition 2, the head binding of conditions 3 and 4,
      the fail-closed rule, the fact that a `deferred` outcome sets the
      aggregate to `needs_fixes` (so readiness is withheld and Step 7 re-runs)
      rather than passing as a clean skip, the bounded deferral counter and its
      `expensive_gate_deferral_cap` escalation, the reordering of expensive
      reviewers to the end of the platform list, and the override variable with the expectation that its use is
      justified in the PR.
- [ ] `docs/workflow/development-workflow/integrations/codex-github.md` — add a
      section describing the gate so a reader configuring the reviewer learns
      when it will actually run, when it will be deferred, and how to override.
      The file exists (confirmed in the Verification Log); no new file is
      created.

---

## Testing Strategy

**Test types**: Unit (shell harness), plus the smoke test runbook.

**Key scenarios to test**:

1. `is_expensive_reviewer_platform` matches `codex-github` and rejects
   `local-ai-reviewer`, `pr-agent`, and `bugbot` — the gate must not
   accidentally hold back a cheap reviewer.
2. All conditions met → `EXPENSIVE_GATE_RESULT=dispatched`,
   `EXPENSIVE_GATE_REASON` empty, and `run_platform_review` is called.
3. `LOCAL_AI_HEAD_CURRENT=0` → `deferred` / `local_evidence_stale`,
   `run_platform_review` is **not** called, and the loop's aggregate becomes
   `needs_fixes` / `expensive_gate_deferred` — the core of brief scope bullet 1,
   and the proof that a defer withholds readiness instead of passing as a skip.
4. `LOCAL_AI_CONFIGURED` unset → `deferred` / `local_evidence_missing`. The
   fail-closed case for brief scope bullet 2, pairing with #1648's rule that an
   absent key is telemetry loss rather than non-applicability.
5. `LOCAL_AI_CONFIGURED=0` → `deferred` / `local_reviewer_not_configured`.
   Distinct from scenario 4 (`missing` means the telemetry never arrived; this
   means the platform is genuinely not configured), and deliberately still a
   defer: the brief requires the expensive reviewer to run only after
   current-head local clean evidence and to fail closed when it is absent. The
   consumer that never configures a local reviewer is released by the deferral
   cap in scenario 13 or by the override in scenario 15, both explicit.
6. `reorder_expensive_reviewers_last` moves `codex-github` to the end of a
   platform list that declared it first, preserves the relative order of the
   remaining platforms, emits `EXPENSIVE_REVIEWERS_REORDERED=1`, and leaves an
   already-correct list untouched with the flag unset. This is what makes the
   gate's precondition reachable: without it the loop would defer at the same
   point on every invocation and the deferral would never resolve.
7. Condition 2 after reordering: with every non-expensive platform run and
   `clean`, → `dispatched`. With the reorder suppressed so a peer has not run,
   → `deferred` / `peer_reviewer_not_run` — the defensive assertion firing
   rather than the gate silently dispatching.
8. A peer reviewer that ran and returned `needs_fixes` → `deferred` /
   `peer_reviewer_not_clean` — distinct from scenario 7's `peer_reviewer_not_run`.
9. One unresolved non-outdated review thread → `deferred` /
   `unresolved_threads`; the same thread marked outdated → `dispatched`.
10. A failing baseline check → `deferred` / `baseline_checks_not_green`; a
    pending one → `deferred` / `baseline_checks_pending`; a reviewer-owned check
    that is pending → `dispatched`, because a reviewer's own check must not gate
    the reviewer.
11. The threads or checks query returns a live head different from
    `loop_head_sha` → `deferred` / `evidence_head_moved`. Without this, evidence
    from a newer commit could authorize dispatch against reviewer verdicts taken
    on an older one.
12. Each unreadable input in turn → `deferred` with its specific reason —
    `evidence_unavailable_head` for an empty `loop_head_sha`,
    `evidence_unavailable_review_threads` for a failed threads query,
    `evidence_unavailable_checks` for a failed check rollup.
13. The deferral cap: with the ledger already recording
    `PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS` deferrals for the current
    `loop_head_sha`, the next run → `EXPENSIVE_GATE_RESULT=deferral_cap`,
    `RESULT=escalate`, `REASON=expensive_gate_deferral_cap`, and the reason that
    kept failing is still reported. With one fewer recorded deferral it defers
    normally. This is the scenario the existing dual caps cannot cover, because
    they bucket `needs_fixes` uniquely by head and result.
14. The deferral counter is head-scoped: deferrals recorded against a different
    `expensive_gate.head` do not count toward the cap for the current head, so a
    new push starts the budget over.
15. `PR_REVIEW_LOOP_FORCE_EXPENSIVE_REVIEWERS=1` with condition 1 unmet →
    `EXPENSIVE_GATE_RESULT=forced`, `EXPENSIVE_GATE_REASON=local_evidence_stale`
    preserved, `run_platform_review` **is** called, and the aggregate is **not**
    set to `needs_fixes` — the override path of brief scope bullet 3, proving
    both that the reason survives and that an explicit human decision is not
    re-blocked.
16. Composition with the phase mechanism: a platform that is both a phase
    platform and an expensive reviewer runs `ensure_pr_ready_for_ready_phase`
    first and the gate second; when the gate defers, the PR has still been
    converted to ready and the defer is not reported as a phase failure.
17. Composition with `--pre-after-clean-only`: an expensive reviewer that is
    also a phase platform is filtered out before the gate is consulted, and the
    gate emits no telemetry for it — no phantom `deferred` record for a platform
    that was never in scope.
18. A ledger entry written without `expensive_gate` still parses through
    `reviewer_loop_history_payload_from_existing` — `v1` backward compatibility,
    same contract as #1648's added fields.

19. The deferral budget is unreadable (the ledger is absent, unparseable, or
    reports the `unavailable` state) → `EXPENSIVE_GATE_RESULT=deferral_cap`,
    `REASON=expensive_gate_deferral_budget_unreadable`,
    `EXPENSIVE_GATE_DEFERRALS=-1`, and the loop escalates. Without this the
    bounded-deferral guarantee would hold only when the ledger happens to be
    readable, which is not a guarantee.

**Files**:

- `scripts/development-workflow/tests/test-pr-review-loop.sh` — scenarios 1–14,
  18 and 19, as new cases in the existing `HARNESS_MODE=1` harness.
- `scripts/development-workflow/tests/test-expensive-reviewer-gate.sh` — a new
  suite for scenarios 15–17, the override and composition cases, which need
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
| P1 | Stale local evidence: `LOCAL_AI_HEAD_CURRENT=0` with all other conditions met | the gate fixture in `scripts/development-workflow/tests/test-pr-review-loop.sh` | the gate defers, `run_platform_review` is not called, and the aggregate is `needs_fixes` / `expensive_gate_deferred`; setting it to `1` dispatches |
| P2 | Missing local evidence: `LOCAL_AI_CONFIGURED` unset | same fixture | the gate defers with `local_evidence_missing`; exporting `LOCAL_AI_CONFIGURED=1` dispatches — the proof that an unknown is refused rather than assumed clean |
| P3 | Unreadable evidence: make the review-threads query fail | same fixture | the gate defers with `evidence_unavailable_review_threads` **and** the aggregate becomes `needs_fixes` / `expensive_gate_deferred`, so readiness is withheld; restoring the query dispatches and leaves the aggregate clean |
| P4 | Gate-not-wired regression: **delete the `expensive_reviewer_gate` call** from the per-platform block, leaving the function defined but unreachable | a scratch copy of the per-platform block in `scripts/development-workflow/pr-review-loop.sh` | scenario 3 fails, because `codex-github` is dispatched with stale local evidence and no `EXPENSIVE_GATE_*` telemetry is emitted; restoring the call passes. Deleting the call is the correct mutation: removing the `is_expensive_reviewer_platform` guard instead would consult the gate for *every* platform, which is a different defect and would not leave the gate unreachable |
| P5 | Ordering regression: **delete the `reorder_expensive_reviewers_last` call**, leaving a platform list that declares `codex-github` before `pr-agent` | a scratch copy of the platform-resolution block | scenario 6 fails and scenario 7's suppressed-reorder case shows the gate deferring on every invocation with `peer_reviewer_not_run` — a deferral that can never resolve; restoring the call passes |
| P6 | Readiness regression: make a defer leave the aggregate result unchanged instead of setting `needs_fixes` | a scratch copy of the gate call site | scenario 3's aggregate assertion fails, and a run in which `codex-github` never executed would satisfy Protocol 92's readiness conditions; restoring the `needs_fixes` aggregate passes |
| P7 | Unbounded-deferral regression: replace the head-scoped deferral counter with the existing `reviewer_loop_history_entries_count` caps | a scratch copy of the cap check | scenario 13 fails, because repeated `needs_fixes` results on one unchanged head collapse under that function's `unique` bucketing by `head_sha` + `result` and neither cap ever trips; restoring the dedicated counter escalates with `expensive_gate_deferral_cap` |
| P8 | Unreadable-budget regression: make the ledger read fail, and change the counter to treat the failure as a count of zero | the deferral-budget fixture in `scripts/development-workflow/tests/test-pr-review-loop.sh` | scenario 19 fails, because the gate defers on an unproven budget instead of escalating; restoring the fail-closed branch escalates with `expensive_gate_deferral_budget_unreadable` |

Record all eight in the implementation PR under a `Planted-Violation Proofs`
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
| Gate condition fixture | A table-driven set of the conditions with each one independently unmet, driving scenarios 2–5 and 8–11 | inline in `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Platform-order fixture | A resolved list declaring `codex-github` first, and an already-correct list, driving scenarios 6 and 7 | inline in `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Unreadable-input mocks | Mock `gh` commands that exit non-zero for the threads query and for the check rollup, driving scenario 12 and proof P3 | inline in `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Deferral-budget fixtures | Ledger payloads carrying `PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS` `expensive_gate.result=deferred` entries at the current head, one fewer, the same count at a different head, and an unparseable payload — driving scenarios 13, 14 and 19 and proof P7 | inline heredocs in `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Composition fixture | A platform list where `codex-github` is both a phase platform and an expensive reviewer, driving scenarios 16 and 17 | inline in `scripts/development-workflow/tests/test-expensive-reviewer-gate.sh` |
| Legacy ledger payload | A `reviewer_loop_history.v1` entry with no `expensive_gate` object, driving scenario 18 | inline heredoc in `scripts/development-workflow/tests/test-pr-review-loop.sh` |

No repository fixture files are added; both suites build their fixtures inline
with mock `gh` commands and require no network access.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
      — document the gate: its conditions and evaluation order, the
      order-independence of condition 2, the head binding of conditions 3 and 4,
      the fail-closed rule, the `deferred` outcome setting the aggregate to
      `needs_fixes` so readiness is withheld and Step 7 re-runs, the
      bounded deferral counter and its escalation, the reordering of expensive
      reviewers to the end of the platform list, and the override variable.
- [ ] `docs/workflow/development-workflow/integrations/codex-github.md` — add a
      section describing the gate, its conditions, and the override, so the
      gate is discoverable from the reviewer's own integration page rather than
      only from the loop protocol.
- [ ] `REVIEW.md` — no change. The gate decides when a reviewer runs, not what
      the review contract requires.
- [ ] `AGENTS.md` — no change. It does not enumerate reviewer-loop gates.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The gate silently stops `codex-github` from ever running | Med | High — the expensive reviewer's findings are the reason this epic exists; losing them entirely is worse than running it too often | A defer is never terminal and never unbounded: it sets the aggregate to `needs_fixes` / `expensive_gate_deferred` so readiness is withheld and Step 7 re-runs, and a head-scoped counter escalates with `expensive_gate_deferral_cap` after `PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS` deferrals so a stuck gate reaches a human. Every defer names one reason in both the summary comment and the ledger, and `EXPENSIVE_GATE_DEFERRALS` shows the distance to the cap before it trips. Scenarios 3, 13 and 14 pin the three halves |
| A deferral loop is invisible to the existing cycle caps | Med | High — the gate could cycle indefinitely on one unchanged head with neither cap advancing | `reviewer_loop_history_entries_count` buckets qualifying entries `unique` over `head_sha + "\|" + result`, so repeated `needs_fixes` on one head counts once; the plan therefore adds its own occurrence-counted, head-scoped deferral counter rather than relying on those caps, and proof P7 plants the reliance to demonstrate that it does not bound anything |
| A consumer that never configures a local reviewer is blocked forever | Med | High — downstream template consumers would stall | The brief requires fail-closed on missing local evidence, so the gate defers rather than inventing an implicit dispatch. The release valves are explicit: the deferral cap escalates to a human after a bounded number of tries, and `PR_REVIEW_LOOP_FORCE_EXPENSIVE_REVIEWERS` covers a one-off run. Scenario 5 pins the defer and scenario 13 the escalation |
| The gate is defined but never consulted, leaving behavior unchanged | Med | High — the item would appear complete while changing nothing | The call site is in the per-platform block immediately before `run_platform_review`, and proof P4 deletes that call outright and requires scenario 3 to fail — a gate that is not wired in cannot pass its own proof |
| Fail-closed on unreadable evidence turns a transient API blip into a permanent defer | Med | Med | A defer is per-invocation, not sticky: the `needs_fixes` aggregate makes Protocol 91 re-run Step 7, which re-evaluates from scratch. The bound is the gate's own head-scoped deferral counter, not the existing dual cycle caps — those cannot see a deferral loop, as the Verification Log records — and an unreadable budget escalates rather than deferring again. The gate adds no retry path of its own, so it cannot loop |
| The gate contradicts the existing phase mechanism | Med | High — two gates disagreeing on whether a platform runs is worse than either alone | Composition is specified explicitly (phase gate first, then this gate; `--pre-after-clean-only` filters before both) and pinned by scenarios 13 and 14, including the no-phantom-telemetry case |
| Implementation starts before #1648 lands and wires the gate to keys that do not exist | Med | High — the gate would read unset variables and hold everything, or be written against a guessed contract | Recorded as a Conflict in the Cross-Cutting check and as Implementation Order step 0, which is a hard stop that verifies #1648 is merged into the approved base before any edit |
| A reviewer's own check gates that reviewer | Low | Med — `codex-github` would wait on a check it is responsible for producing | Condition 4 evaluates non-reviewer checks only, reusing the reviewer/baseline classification `pr-ci-loop.sh` already emits rather than a new one; scenario 9's third case pins it |
| Platform ordering decides whether the gate is effective | Med | High — a config listing `codex-github` first would either dispatch it before the cheap reviewers ran, or defer at the same point forever | Detection is not enough, so the loop reorders: `reorder_expensive_reviewers_last` moves expensive platforms to the end before iteration, making the gate's precondition reachable; condition 2 still compares against the full resolved list, so `peer_reviewer_not_run` fires as a defensive assertion if the reorder did not happen. Scenarios 6 and 7 and proof P5 pin both halves |
| Thread and CI evidence describes a newer commit than the reviewer verdicts | Med | High — dispatch would be authorized on an inconsistent mix of two heads | Conditions 3 and 4 require the live head returned with their queries to equal `loop_head_sha`, and defer with `evidence_head_moved` otherwise; scenario 10 pins it |

---

## Code Samples

```bash
# Illustrative — adapt during implementation.
EXPENSIVE_REVIEWER_PLATFORMS=(codex-github)

is_expensive_reviewer_platform() {
  array_contains_value "$1" "${EXPENSIVE_REVIEWER_PLATFORMS[@]}"
}

# Returns 0 to dispatch, 1 to defer. Stops at the first unmet condition so the
# reason names one cause. A defer is not a clean skip: the caller sets the
# aggregate to needs_fixes / expensive_gate_deferred so readiness is withheld
# and Protocol 91 re-runs Step 7.
expensive_reviewer_gate() {
  local pr_number="$1"
  local platform="$2"
  local head_sha="$3"
  local reason=""
  local deferrals

  if [ -z "$head_sha" ]; then
    reason="evidence_unavailable_head"
  elif [ -z "${LOCAL_AI_CONFIGURED:-}" ]; then
    reason="local_evidence_missing"
  elif [ "$LOCAL_AI_CONFIGURED" = "0" ]; then
    # No current-head local evidence exists. The brief requires fail-closed
    # here; the deferral cap and the explicit override are the release valves.
    reason="local_reviewer_not_configured"
  elif [ "${LOCAL_AI_HEAD_CURRENT:-}" = "0" ]; then
    reason="local_evidence_stale"
  elif [ -z "${LOCAL_AI_HEAD_CURRENT:-}" ]; then
    reason="local_evidence_missing"
  fi
  # Conditions 2-4 follow, each appending its own reason and each comparing the
  # live head returned by its query against "$head_sha" before trusting it.

  # Occurrences, not uniques, and scoped to this head — the existing cycle
  # caps bucket needs_fixes uniquely by head+result and so cannot bound a
  # deferral loop on an unchanged head.
  deferrals="$(expensive_gate_deferral_count "$head_sha")"

  print_kv EXPENSIVE_GATE_PLATFORM "$platform"
  print_kv EXPENSIVE_GATE_HEAD "$head_sha"
  print_kv EXPENSIVE_GATE_REASON "$reason"
  print_kv EXPENSIVE_GATE_DEFERRALS "$deferrals"
  if [ -n "$reason" ]; then
    if [ "${PR_REVIEW_LOOP_FORCE_EXPENSIVE_REVIEWERS:-0}" = "1" ]; then
      print_kv EXPENSIVE_GATE_RESULT forced
      return 0
    fi
    if [ "$deferrals" -ge "${PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS:-3}" ]; then
      # Stop cycling; escalate so a human sees which condition kept failing.
      print_kv EXPENSIVE_GATE_RESULT deferral_cap
      return 1
    fi
    print_kv EXPENSIVE_GATE_RESULT deferred
    return 1
  fi
  print_kv EXPENSIVE_GATE_RESULT dispatched
  return 0
}
```

Summary-comment line, illustrative:

```markdown
**Expensive reviewer gate:** codex-github — deferred (local_evidence_stale) at head `6780c658eebc8879d61e56842445749c1195b13f`. The reviewer was not run; this loop result is `needs_fixes` so readiness is withheld and Step 7 will re-run.
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
2. Add `reorder_expensive_reviewers_last`, called once after the platform list
   is resolved and before iteration, and emit `EXPENSIVE_REVIEWERS_REORDERED`
   when it changed the order. **Verify**: scenario 6 — a list declaring
   `codex-github` first ends with it last, relative order is otherwise
   preserved, and an already-correct list is untouched with the flag unset.
3. Add `expensive_gate_deferral_count`, reading occurrences of
   `expensive_gate.result == "deferred"` scoped to `expensive_gate.head` from
   the ledger, and returning `-1` when the ledger is absent, unparseable, or
   reports the `unavailable` state. **Verify**: scenarios 13, 14 and 19 — the
   count reflects only the current head, and an unreadable ledger yields `-1`
   rather than `0`.
4. Add `expensive_reviewer_gate` with the conditions in the documented order,
   the full-platform-list comparison for condition 2, the live-head comparison
   for conditions 3 and 4, the fail-closed branch for every unreadable input,
   and the deferral-cap branch. **Verify**: drive the condition fixture and
   confirm each unmet condition yields its single named reason, and that the
   cap escalates rather than deferring a fourth time.
5. Wire the gate into the per-platform block immediately before
   `run_platform_review`, guarded by `is_expensive_reviewer_platform`. A
   `deferred` result sets the aggregate to `needs_fixes` with
   `REASON=expensive_gate_deferred`; a `deferral_cap` result sets it to
   `escalate` with `REASON=expensive_gate_deferral_cap`, or
   `REASON=expensive_gate_deferral_budget_unreadable` when the counter returned
   `-1`. **Verify**: scenario 3 shows `run_platform_review` is not called and
   the aggregate is `needs_fixes`; scenarios 13 and 19 show both escalations.
6. Add the override branch, confirm the reason survives it, and confirm a
   `forced` result does **not** set the `needs_fixes` aggregate. **Verify**:
   scenario 15.
7. Emit the `EXPENSIVE_GATE_*` keys and `EXPENSIVE_REVIEWERS_REORDERED`, and
   document them in `--help`.
   **Verify**: run `pr-review-loop.sh --help` and confirm the gate, its
   conditions, the fail-closed rule, the `deferred` aggregate behavior, the
   reordering, `PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS`, and the override
   variable are described.
8. Add the summary-comment line and the `expensive_gate` ledger object
   (`platform`, `result`, `reason`, `head`). **Verify**: build an entry in the
   harness and confirm the object shape, that `expensive_gate_deferral_count`
   reads it back, and that a legacy entry without it still parses
   (scenario 18).
9. Update
   `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
   and
   `docs/workflow/development-workflow/integrations/codex-github.md` per
   **Documentation Updates**. **Verify**: both files describe the same four
   conditions, the same fail-closed rule, and the same override variable name.
10. Add the unit cases to `test-pr-review-loop.sh` and create
    `test-expensive-reviewer-gate.sh` with both `# covers:` lines.
    **Verify**: both suites exit 0, and
    `scripts/development-workflow/select-test-suites.sh` selects the new suite
    for a change touching only `pr-review-loop.sh`.
11. Produce the eight planted-violation proofs (P1–P8) and record them in the PR
    under a `Planted-Violation Proofs` heading. **Verify**: each shows two runs
    at a concrete file and line — failing with the violation planted, passing
    once removed.
12. Run `shellcheck` on the changed script and `markdownlint-cli2` on the
    changed protocol document, this plan, and the runbook. **Verify**: both
    tools exit 0.
13. Add a changelog fragment
    `changelog.d/1649.changed.expensive-reviewers-after-local-clean.md`
    containing exactly:

    ```markdown
    - **Gate expensive reviewers on current-head local evidence** (#1649): `codex-github` now runs only after the local reviewer, peer reviewers, review threads, and baseline checks are clean on the current head, and defers fail-closed when that evidence is missing or stale.
    ```

14. Update project docs per **Documentation Updates** above (step 9 covers
    them; no other project doc is affected).
