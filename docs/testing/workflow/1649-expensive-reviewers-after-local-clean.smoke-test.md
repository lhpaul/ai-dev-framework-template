# Smoke Test Runbook: Expensive Reviewers After Local Clean Evidence

**Feature**: Expensive-reviewer gate for the automated reviewer loop
**Spec**: None — Refactor item. Source brief:
[issue #1649](https://github.com/lhpaul/ai-dev-framework-template/issues/1649)
**Implementation plan**:
[2_1649-expensive-reviewers-after-local-clean_implementation-plan.md](../../specs/developments/20260827233000_1649-expensive-reviewers-after-local-clean/2_1649-expensive-reviewers-after-local-clean_implementation-plan.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

- [ ] You are reviewing the implementation PR for #1649.
- [ ] The PR targets `develop-internal-reviewer-effectiveness`.
- [ ] #1648 is merged into that branch, so `LOCAL_AI_CONFIGURED` and
      `LOCAL_AI_HEAD_CURRENT` exist in `pr-review-loop.sh`.
- [ ] `bash`, `jq`, and `git` are available. No network access and no live
      GitHub mutation are required — `codex-github` is configured in no bucket
      of this repository's `.ai-dev-workflow.yaml`, so every step runs against
      harness fixtures with mocked `gh` commands.

---

## Test Data

| Item | Value |
| --- | --- |
| Reviewer loop | `scripts/development-workflow/pr-review-loop.sh` |
| CI loop (reviewer/baseline check classification) | `scripts/development-workflow/pr-ci-loop.sh` |
| Suite selector | `scripts/development-workflow/select-test-suites.sh` |
| Loop harness suite | `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Gate suite (new) | `scripts/development-workflow/tests/test-expensive-reviewer-gate.sh` |
| Reviewer-loop protocol | `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` |
| Reviewer integration doc | `docs/workflow/development-workflow/integrations/codex-github.md` |
| Override variable | `PR_REVIEW_LOOP_FORCE_EXPENSIVE_REVIEWERS` |
| Deferral bound | `PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS` (default `3`) |

---

## Smoke Test Steps

### Step 1: Only expensive reviewers are gated

**Maps to**: the "must not hold back a cheap reviewer" risk.

1. Source the loop in harness mode:

   <!-- workflow-shell-contract: bash -->

   ```bash
   HARNESS_MODE=1 source scripts/development-workflow/pr-review-loop.sh
   ```

2. Call `is_expensive_reviewer_platform` with `codex-github`,
   `local-ai-reviewer`, `pr-agent`, and `bugbot`.

**Expected result**: success only for `codex-github`. A cheap reviewer that
matched would be held back by a gate that assumes an expensive one, inverting
the item's intent.

### Step 2: The gate dispatches when all conditions are met

**Maps to**: brief scope bullet 1.

1. Drive the condition fixture with `LOCAL_AI_CONFIGURED=1`,
   `LOCAL_AI_HEAD_CURRENT=1`, every peer reviewer `clean`, zero unresolved
   non-outdated threads, and all non-reviewer checks green.

**Expected result**: `EXPENSIVE_GATE_RESULT=dispatched`, an empty
`EXPENSIVE_GATE_REASON`, `EXPENSIVE_GATE_HEAD` equal to the run's
`loop_head_sha`, **no** `EXPENSIVE_GATE_ESCALATION` key at all — it appears only
on a `deferral_cap` result — and `run_platform_review` called once for
`codex-github`.

### Step 3: Each unmet condition defers with one named reason

**Maps to**: brief scope bullets 1 and 2.

Drive the fixture with exactly one condition unmet at a time and read
`EXPENSIVE_GATE_RESULT` and `EXPENSIVE_GATE_REASON`:

| Fixture state | Required result |
| --- | --- |
| `LOCAL_AI_HEAD_CURRENT=0` | `deferred` / `local_evidence_stale` |
| `LOCAL_AI_CONFIGURED` unset | `deferred` / `local_evidence_missing` |
| `LOCAL_AI_CONFIGURED=1`, `LOCAL_AI_HEAD_CURRENT` empty | `deferred` / `local_evidence_missing` |
| `LOCAL_AI_CONFIGURED=0` | `deferred` / `local_reviewer_not_configured` |
| Reorder suppressed, so `pr-agent` has not run yet | `deferred` / `peer_reviewer_not_run` |
| A peer reviewer ran and returned `needs_fixes` | `deferred` / `peer_reviewer_not_clean` |
| One unresolved, non-outdated review thread | `deferred` / `unresolved_threads` |
| The same thread marked outdated | `dispatched` |
| A non-reviewer check failed | `deferred` / `baseline_checks_not_green` |
| A non-reviewer check still running | `deferred` / `baseline_checks_pending` |
| A reviewer-owned check still running | `dispatched` |
| The threads or checks query returns a live head different from `loop_head_sha` | `deferred` / `evidence_head_moved` |

**Expected result**: each row returns exactly its stated result, and
`run_platform_review` is not called on any `deferred` row. Three rows carry most
of the weight:

- The **`LOCAL_AI_CONFIGURED=0`** row must defer, not dispatch. The brief
  requires the expensive reviewer to run only after current-head local clean
  evidence and to fail closed when it is absent, and it permits an explicit
  manual override rather than an implicit automatic one. A consumer that never
  configures a local reviewer is released by the deferral cap in Step 4b or the
  override in Step 5, both explicit.
- The **suppressed-reorder** row must fire `peer_reviewer_not_run`. That reason
  is a defensive assertion: after `reorder_expensive_reviewers_last` runs, every
  non-expensive platform has already executed, so seeing it in a normal run
  means the reorder did not happen.
- The **reviewer-owned pending check** row must dispatch: a reviewer's own check
  must never gate that reviewer, or `codex-github` would wait on a check it is
  responsible for producing.

### Step 3c: Expensive reviewers are reordered to the end

**Maps to**: the "platform ordering decides whether the gate is effective" risk.

1. Resolve a platform list that declares `codex-github` before `pr-agent` and
   `local-ai-reviewer`.
2. Run `reorder_expensive_reviewers_last` and read the resulting `PLATFORM_LIST`
   and `EXPENSIVE_REVIEWERS_REORDERED`.
3. Repeat with a list that is already in the correct order.

**Expected result**: `codex-github` ends last, the relative order of the
remaining platforms is unchanged, and `EXPENSIVE_REVIEWERS_REORDERED=1` is
emitted. The already-correct list is untouched and the flag is unset. Detection
without reordering is not sufficient: the loop would never reach the cheap
reviewers before the gate, so it would defer at the same point on every
invocation and the deferral could never resolve.

### Step 3b: A defer withholds readiness

**Maps to**: the "silently stops `codex-github` from ever running" risk.

1. Run the loop with the gate deferring for any reason from Step 3.
2. Read the loop's aggregate `RESULT` and `REASON`.
3. Apply the Protocol 92 readiness conditions to that result.

**Expected result**: the aggregate is `needs_fixes` with
`REASON=expensive_gate_deferred`, so `ready-for-human-review` is withheld and
Protocol 91 re-runs Step 7. A defer that left the aggregate `clean` or `skipped`
would satisfy Protocol 92 and let the PR reach human review having never run the
expensive reviewer, with nothing guaranteeing the retry the gate depends on.

### Step 4: Unreadable evidence defers, and does not escalate

**Maps to**: brief scope bullet 2 (fail-closed).

1. Make the review-threads query fail; run the gate.
2. Make the check-rollup query fail; run the gate.
3. Set `loop_head_sha` to the empty string; run the gate.
4. In each case, read the loop's aggregate `RESULT`.

**Expected result**: `deferred` with `evidence_unavailable_review_threads`,
`evidence_unavailable_checks`, and `evidence_unavailable_head` respectively, and
the aggregate `needs_fixes` / `expensive_gate_deferred` in all three. An
unreadable input must not dispatch the expensive reviewer, and must not be
recorded as a clean skip either — it is a retry, forced by the non-clean
aggregate.

### Step 4b: Deferrals are bounded, and the bound is this item's own

**Maps to**: the "deferral loop is invisible to the existing cycle caps" risk.

1. Seed the ledger with `PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS` entries whose
   `expensive_gate.result` is `deferred` and whose `expensive_gate.head` equals
   the current `loop_head_sha`. Run the gate.
2. Remove one seeded entry and run again.
3. Re-seed the entries against a *different* `expensive_gate.head` and run again.
4. Read `EXPENSIVE_GATE_DEFERRALS` in each run.

5. Make the ledger read fail, or seed an unparseable payload, and run again.

**Expected result**: step 1 gives `EXPENSIVE_GATE_RESULT=deferral_cap` with
`EXPENSIVE_GATE_ESCALATION=expensive_gate_deferral_cap` and the loop aggregate
`escalate` / `expensive_gate_deferral_cap`, still naming the condition that kept
failing. `EXPENSIVE_GATE_ESCALATION` is what distinguishes the two escalation
causes without re-deriving them from the count. Step 2 defers normally. Step 3 defers normally,
because the counter is head-scoped and a new push starts the budget over.
Step 5 also escalates, with `EXPENSIVE_GATE_RESULT=deferral_cap`,
`EXPENSIVE_GATE_ESCALATION=expensive_gate_deferral_budget_unreadable`,
`REASON=expensive_gate_deferral_budget_unreadable` and
`EXPENSIVE_GATE_DEFERRALS=-1` — an unreadable budget cannot prove the sequence
is bounded, so deferring again would reopen the unbounded loop the counter
exists to close, and `-1` keeps that state distinguishable from a count of zero.
`EXPENSIVE_GATE_DEFERRALS` shows the distance to the cap in every other run.

This bound cannot be delegated to the existing dual cycle caps:
`reviewer_loop_history_entries_count` buckets qualifying entries `unique` over
`head_sha` + `result`, so repeated `needs_fixes` on one unchanged head — exactly
the shape of a deferral loop — counts once and advances neither cap.

### Step 5: The override dispatches without hiding the reason

**Maps to**: brief scope bullet 3.

1. Set `PR_REVIEW_LOOP_FORCE_EXPENSIVE_REVIEWERS=1`.
2. Run the gate with `LOCAL_AI_HEAD_CURRENT=0`.

**Expected result**: `EXPENSIVE_GATE_RESULT=forced`,
`EXPENSIVE_GATE_REASON=local_evidence_stale` still present,
`run_platform_review` called, and the aggregate **not** set to `needs_fixes` —
the human took the decision explicitly, so the run is not re-blocked. The reason
surviving the override is the point: a forced run that later wastes reviewer
cycles must be traceable to the condition that was overridden.

### Step 6: Composition with the existing phase mechanism

**Maps to**: the "two gates disagreeing" risk.

1. Configure `codex-github` as both a phase platform and an expensive reviewer.
2. Run the loop and observe the order of operations.
3. Re-run with the gate holding, and inspect the PR's draft state and the loop's
   phase telemetry.
4. Re-run with `--pre-after-clean-only`.

**Expected result**: `ensure_pr_ready_for_ready_phase` runs first and the gate
second. When the gate defers, the PR has still been converted to ready and the
defer is not reported as a phase failure. Under `--pre-after-clean-only` the
platform is filtered out before the gate is consulted and **no**
`EXPENSIVE_GATE_*` telemetry is emitted for it — a phantom `deferred` record for
a platform that was never in scope would misreport why the reviewer did not
run.

### Step 7: Gate outcome is visible in both durable surfaces

**Maps to**: the "silently stops `codex-github` from ever running" risk.

1. Read the reviewer-loop summary comment produced by a `deferred` run.
2. Read the `reviewer_loop_history.v1` entry from the same run.
3. Parse a legacy entry that has no `expensive_gate` object.

**Expected result**: the summary carries one
`**Expensive reviewer gate:**` line naming the platform, result, reason, and
head, and stating that the reviewer was not run and readiness is withheld; the
ledger entry carries an `expensive_gate` object with the same values; and the
legacy entry still parses through
`reviewer_loop_history_payload_from_existing`, confirming the `v1` schema stayed
backward compatible. A repeated defer must be readable from the PR without
re-running anything.

### Step 8: The new suite is selected by the right change sets

**Maps to**: the `# covers:` declaration requirement in the plan.

1. Confirm `test-expensive-reviewer-gate.sh` declares both `# covers:` lines.
2. Run `scripts/development-workflow/select-test-suites.sh` against a change set
   touching only `scripts/development-workflow/pr-review-loop.sh`.
3. Run it again against a change set touching only the reviewer-loop protocol.

**Expected result**: the suite is selected in both runs. Without an explicit
declaration the naming convention would map this suite to a
`scripts/development-workflow/expensive-reviewer-gate.sh` that does not exist,
so it would run only when the test file itself changed.

### Step 9: Planted-violation proofs are present and two-directional

**Maps to**: `REVIEW.md` § Planted-violation proof.

1. Read the implementation PR description's `Planted-Violation Proofs` heading.
2. Confirm P1–P8 from the plan each record the command, the file and line of the
   planted violation, and both outcomes.

**Expected result**: eight proofs, each showing the check failing with the
violation present and passing once removed. Four carry the most weight: P4
deletes the `expensive_reviewer_gate` call so the function is defined but
unreachable, and requires Step 3's stale-evidence row to fail — that is what
proves the gate is wired into the dispatch path. P5 deletes the
`reorder_expensive_reviewers_last` call and requires Step 3c to fail. P6 makes a
defer leave the aggregate unchanged and requires Step 3b to fail. P7 replaces
the dedicated deferral counter with the existing cycle caps and requires
Step 4b to fail, demonstrating that those caps do not bound a deferral loop, and
P8 makes an unreadable ledger count as zero and requires Step 4b's fifth run to
fail.

### Step 10: Documentation states one contract

1. Read the gate section of
   `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`.
2. Read the gate section of
   `docs/workflow/development-workflow/integrations/codex-github.md`.

**Expected result**: both name the same conditions in the same order, the same
fail-closed rule, the same `dispatched` / `deferred` / `forced` /
`deferral_cap` outcomes, the same statement that a defer sets the aggregate to
`needs_fixes` rather than passing as a clean skip, the same reordering of
expensive reviewers to the end of the platform list, the same
`PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS` bound and its escalation, and the same
override variable. Reading them against the Step 3, 3b, 3c and 4b expectations
must surface no contradiction.

### Step 11: Static checks

1. Run `shellcheck` on `scripts/development-workflow/pr-review-loop.sh`.
2. Run `markdownlint-cli2` on the two changed documentation files, this runbook,
   and the implementation plan.

**Expected result**: both tools exit 0.

---

## Rollback

Revert the implementation PR. The change is additive — one gate function, one
call site, one reorder step, five stdout keys, one summary line, and one
optional ledger object —
and reverting restores the previous behavior, in which an expensive reviewer
runs as soon as the phase mechanism reaches it. Ledger entries already written
with `expensive_gate` remain parseable by the reverted reader, which dereferences
unknown fields with defaults. No configuration migration is involved: the gate
reads no `.ai-dev-workflow.yaml` key that this item adds.
