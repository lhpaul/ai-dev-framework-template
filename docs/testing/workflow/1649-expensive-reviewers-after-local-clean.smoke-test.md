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
| Reviewer/baseline check classification | `configured_reviewer_check_names_json`, relocated to `scripts/development-workflow/workflow-lib.sh` |
| CI loop (its consumer; **not** called by the gate) | `scripts/development-workflow/pr-ci-loop.sh` |
| Suite selector | `scripts/development-workflow/select-test-suites.sh` |
| Loop harness suite | `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Gate suite (new) | `scripts/development-workflow/tests/test-expensive-reviewer-gate.sh` |
| Reviewer-loop protocol | `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` |
| Reviewer integration doc | `docs/workflow/development-workflow/integrations/codex-github.md` |
| Override variable | `PR_REVIEW_LOOP_FORCE_EXPENSIVE_REVIEWERS` |
| Deferral bound | `PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS` (default `3`, valid `1`-`999999`) |
| Bound resolver | `expensive_gate_resolve_max_deferrals`, mirroring `reviewer_loop_resolve_max_cycles` |

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

The four conditions are: the local reviewer clean and current; every reviewer
that **precedes** this one having produced acceptable evidence — a `clean`
result, or a `skipped` one whose reason is not a reviewer failure, deliberately
**not** every `skipped`; zero unresolved non-outdated review threads; and green
non-reviewer baseline checks. Steps 3 and 3d pin the second condition's two
halves.

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
| `local-ai-reviewer` entry of `platform_reviewed_heads` records a head that is not `loop_head_sha` | `deferred` / `local_evidence_stale` |
| That entry is absent while `local-ai-reviewer` is in the resolved list | `deferred` / `local_evidence_missing` |
| The derivation helper returns any value other than `0` or `1` | `deferred` / `local_evidence_missing` |
| `local-ai-reviewer` is not in the resolved platform list | `deferred` / `local_reviewer_not_configured` |
| Reorder suppressed, so a same-bucket peer has not run yet | `deferred` / `peer_reviewer_not_run` |
| A peer ran and returned `needs_fixes` or `escalate` | `deferred` / `peer_reviewer_not_clean` |
| A peer ran and returned `skipped` / `unavailable`, `timeout`, or `unauthorized` | `deferred` / `peer_reviewer_not_clean` |
| A peer ran and returned `skipped` with a reason in `EXPENSIVE_GATE_ACCEPTED_SKIP_REASONS` (`not_configured`, `explicit-skip`, `release_pr`, `unsupported-platform`) | contributes to `dispatched` |
| A peer ran and returned `skipped` with an unknown or empty reason | `deferred` / `peer_reviewer_not_clean` |
| One unresolved, non-outdated review thread | `deferred` / `unresolved_threads` |
| The same thread marked outdated | `dispatched` |
| A non-reviewer check failed | `deferred` / `baseline_checks_not_green` |
| A non-reviewer check still running | `deferred` / `baseline_checks_pending` |
| A reviewer-owned check still running | `dispatched` |
| The check rollup is empty | `deferred` / `baseline_checks_unobserved` |
| The rollup contains only reviewer-owned checks | `deferred` / `baseline_checks_unobserved` |
| The threads or checks query returns a live head different from `loop_head_sha` | `deferred` / `evidence_head_moved` |

**Expected result**: each row returns exactly its stated result, and
`run_platform_review` is not called on any `deferred` row. Three rows carry most
of the weight:

- Every row here is driven through the **in-loop state** — the resolved platform
  list and `platform_reviewed_heads` — never by exporting
  `LOCAL_AI_CONFIGURED` or `LOCAL_AI_HEAD_CURRENT`. Those are stdout keys the
  gate must ignore (Step 3e), so a fixture that set them would be testing an
  interface the implementation is required not to have.
- The **unexpected-value** row is the one a deny-list implementation fails.
  Condition 1 must be an exact-match allow-list requiring the literal `1` from
  each derivation helper; testing only for `0` and empty would let any other
  value fall through and dispatch with no valid evidence, the opposite of
  fail-closed.
- The **`LOCAL_AI_CONFIGURED=0`** row must defer, not dispatch. The brief
  requires the expensive reviewer to run only after current-head local clean
  evidence and to fail closed when it is absent, and it permits an explicit
  manual override rather than an implicit automatic one. A consumer that never
  configures a local reviewer is released by the deferral cap in Step 4b or the
  override in Step 5, both explicit.
- The **suppressed-reorder** row must fire `peer_reviewer_not_run`. That reason
  is a defensive assertion: after `reorder_expensive_reviewers_last` runs, every
  platform in the reviewer's peer set has already executed, so seeing it in a
  normal run means the reorder did not happen. Note the peer set is scoped by
  phase — Step 3d covers it — so a draft-phase `codex-github` must **not** wait
  on a ready-phase `bugbot`.
- The **`skipped`** rows must split by a positive allow-list: four accepted
  (`not_configured`, `explicit-skip`, `release_pr`, `unsupported-platform`) and
  everything else rejected, including `unavailable`, `timeout`, `unauthorized`,
  an unknown reason, and an empty one. Deciding this by asking whether
  `reviewer_failed_label_required_for_result` returns false would be a deny-list:
  that helper returns false for any reason it does not recognise, so a future
  reviewer's new skip reason would silently become acceptable evidence. The
  membership test decides; the helper call confirms. Accepting every skip would let
  `codex-github` dispatch when a configured peer was unavailable, timed out, or
  was refused for credentials — no cheap pre-filter actually ran, which is the
  state the item exists to prevent. Acceptance must be decided by calling
  `reviewer_failed_label_required_for_result`, not by a duplicated list, so a
  future change to that helper carries this gate with it.
- The **reviewer-owned pending check** row must dispatch: a reviewer's own check
  must never gate that reviewer, or `codex-github` would wait on a check it is
  responsible for producing.
- The two **empty-set** rows are the vacuous-green guard. "Every member is
  green" is trivially true of an empty set, so an unguarded implementation would
  dispatch on a head whose CI has not registered yet. The gate does not try to
  tell "this repository has no baseline CI" from "the checks have not appeared
  yet" — one snapshot cannot — so both defer, and the deferral cap sends the
  genuinely-no-CI repository to a human, which is the right owner for the
  decision to run an expensive reviewer with no CI at all.

### Step 3c: Expensive reviewers are reordered to the end

**Maps to**: the "platform ordering decides whether the gate is effective" risk.

1. Resolve a platform list that declares `codex-github` before `pr-agent` and
   `local-ai-reviewer`.
2. Run `reorder_expensive_reviewers_last` and read the resulting `PLATFORM_LIST`
   and `EXPENSIVE_REVIEWERS_REORDERED`.
3. Repeat with a list that is already in the correct order.

4. Resolve a two-bucket list with `codex-github` in `review.on_draft.github`
   and `bugbot` in `review.on_ready.github`, and run the reorder.

**Expected result**: `codex-github` ends last, the relative order of the
remaining platforms is unchanged, and `EXPENSIVE_REVIEWERS_REORDERED=1` is
emitted. The already-correct list is untouched and the flag is unset. Detection
without reordering is not sufficient: the loop would never reach the cheap
reviewers before the gate, so it would defer at the same point on every
invocation and the deferral could never resolve.

In the two-bucket run, `codex-github` must end last **among the draft
platforms** and still precede `bugbot`. A single global partition would place it
after `bugbot` and therefore after the ready-phase transition, silently
inverting the configuration contract that `review.on_draft.github` reviewers run
before `gh pr ready`. Confirm the buckets themselves are still in their original
order.

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

### Step 3d: The peer set is scoped by phase, not the whole list

**Maps to**: the "peer set and phase-bucket reorder contradict each other" risk.

1. Configure `codex-github` and `pr-agent` on draft and `bugbot` on ready. Run
   the loop with `pr-agent` clean and `bugbot` not yet run.
2. Configure `codex-github` on ready with `pr-agent` and `local-ai-reviewer` on
   draft, all draft platforms clean. Run the loop.
3. Suppress the reorder so a same-bucket peer has not run. Run the loop.

**Expected result**: run 1 **dispatches** — `codex-github`'s peer set is
`pr-agent` only, not `bugbot`, because a draft-phase reviewer necessarily runs
before a ready-phase one. Run 2 dispatches, with the whole draft bucket in the
peer set. Run 3 defers with `peer_reviewer_not_run`.

Run 1 is the one a whole-list peer set fails: it would wait on a `bugbot` that
cannot have run yet and defer on every invocation until the cap, deadlocking the
exact configuration Step 3c exists to support. The peer set is well-defined only
because of the reorder — after it, "precedes this reviewer" and "should have
produced evidence before this reviewer" are the same set.

### Step 3e: The local evidence is derived in-loop, not read from the environment

**Maps to**: the "gate reads the local evidence from the environment" risk.

1. With #1648's actual producer populating `platform_reviewed_heads` — **not**
   with `LOCAL_AI_CONFIGURED` / `LOCAL_AI_HEAD_CURRENT` pre-seeded as
   variables — run the gate for a current head, a stale head, an unreported
   head, and a run where `local-ai-reviewer` is not configured.
2. Compare the gate's inputs with the values the run later prints as
   `LOCAL_AI_CONFIGURED` and `LOCAL_AI_HEAD_CURRENT`.
3. Grep the gate implementation for reads of those two names as variables.

**Expected result**: the derived values match the printed ones in all four
runs, and the gate reads neither name from the environment. #1648 defines them
as top-level stdout keys printed once at end of run, so an environment read
would be unset during the platform iteration and the gate would defer on every
invocation — inert in the worst way, always refusing. The stdout keys are the
serialization of the same in-loop state, not a second source of truth.

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

5. Seed a ledger whose history marker is present but whose JSON block is
   unparseable, and run again.
6. Remove the summary comment entirely — an absent ledger — and run again.

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

Step 6 must **not** escalate: `EXPENSIVE_GATE_DEFERRALS=0` and the gate defers
or dispatches normally. An absent ledger is every PR's first reviewer-loop run,
not a failure; escalating there would bypass the bounded deferrals on every PR
without prior history and the bound would never be exercised. The counter must
mirror the three states `reviewer_loop_history_entries_count` already
distinguishes — absent, readable, unreadable — rather than collapsing the first
into the third.

`EXPENSIVE_GATE_DEFERRALS` shows the distance to the cap in every other run.

This bound cannot be delegated to the existing dual cycle caps:
`reviewer_loop_history_entries_count` buckets qualifying entries `unique` over
`head_sha` + `result`, so repeated `needs_fixes` on one unchanged head — exactly
the shape of a deferral loop — counts once and advances neither cap.

### Step 4c: The deferral bound is validated

**Maps to**: the "misconfigured deferral bound" risk.

1. Call `expensive_gate_resolve_max_deferrals` with
   `PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS` unset, empty, `1`, `999999`, `0`,
   `-1`, `1000000`, `abc`, `2.5`, and a value with surrounding whitespace.
2. Read `EXPENSIVE_GATE_MAX_DEFERRALS` in a gate run for each.

**Expected result**: `3` for unset and empty; the configured value for `1` and
`999999`; `3` with a `WARN` on stderr naming the rejected value for the rest.
`EXPENSIVE_GATE_MAX_DEFERRALS` reports the effective value every time.

Both failure directions matter. An unvalidated non-integer reaches
`[ "$deferrals" -ge "$max" ]`, which raises `integer expression expected` and
evaluates false — the cap never trips and the deferral loop is unbounded again.
An unvalidated `0` or negative trips the cap before the first deferral, so every
gated PR escalates immediately. The resolver mirrors
`reviewer_loop_resolve_max_cycles` on purpose: two bounds resolvers in one
script that disagree about what a bad value means would be its own defect.

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

### Step 6b: A defer does not start the ready phase

**Maps to**: the "defer still triggers the ready-phase transition" risk.

1. Configure `codex-github` on draft and `bugbot` on ready.
2. Make the gate defer for any reason from Step 3, and run the loop.
3. Read the PR's draft state, the phase telemetry, and whether
   `ensure_pr_ready_for_ready_phase` was called.

**Expected result**: the loop breaks out at the defer.
`ensure_pr_ready_for_ready_phase` is not called, `gh pr ready` is not run, the
PR stays draft, and no `EXPENSIVE_GATE_*` or phase telemetry is emitted for
`bugbot`. Setting the `needs_fixes` aggregate without breaking out would leave
the iteration running, and the later ready-phase platform would convert the PR
out of draft even though the draft-phase expensive reviewer never ran — a
visible, hard-to-undo side effect produced by a gate whose purpose was to not
proceed.

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

### Step 7e: The shared classification moved without changing behavior

**Maps to**: the "shared classification is duplicated or the gate blocks on the
CI loop" risk.

1. Confirm `configured_reviewer_check_names_json` is defined in
   `workflow-lib.sh` and no longer in `pr-ci-loop.sh`.
2. Run `scripts/development-workflow/tests/test-pr-ci-loop.sh`.
3. Grep the gate's implementation for any invocation of `pr-ci-loop.sh`.

**Expected result**: one definition, in the library both scripts already source;
`pr-ci-loop.sh` still emits identical `REVIEWER_CHECK_COUNT`, `REVIEWER_CHECKS`
and `REVIEWER_CHECKS_JSON`; and the gate calls `pr-ci-loop.sh` nowhere. The gate
takes a single non-blocking snapshot of the check rollup — invoking the polling
CI loop would block the reviewer loop inside a gate and conflate "CI is not
green yet" with "the gate says wait".

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
2. Confirm P1–P19 from the plan each record the command, the file and line of
   the planted violation, and both outcomes.

**Expected result**: nineteen proofs, each showing the check failing with the
violation present and passing once removed. Four carry the most weight: P4
deletes the `expensive_reviewer_gate` call so the function is defined but
unreachable, and requires Step 3's stale-evidence row to fail — that is what
proves the gate is wired into the dispatch path. P5 deletes the
`reorder_expensive_reviewers_last` call and requires Step 3c to fail. P6 makes a
defer leave the aggregate unchanged and requires Step 3b to fail. P7 replaces
the dedicated deferral counter with the existing cycle caps and requires
Step 4b to fail, demonstrating that those caps do not bound a deferral loop, and
P8 makes an unreadable ledger count as zero and requires Step 4b's fifth run to
fail. P9 replaces the per-bucket partition with a global one and requires
Step 3c's two-bucket run to fail. P10 accepts any `skipped` peer and requires
Step 3's three rejected-skip rows to fail. P11 makes an absent ledger return
`-1` and requires Step 4b's sixth run to fail. P12 rewrites condition 1 as a
deny-list and requires Step 3's unexpected-value rows to fail. P13 widens the
peer set back to the whole resolved list and requires Step 3d's first run to
fail. P14 makes the baseline-check helper treat every check as a baseline check
and requires Step 3's reviewer-owned-pending row to fail. P15 removes the
short-circuit on a defer and requires Step 6b to fail. P16 makes an empty
check set read as green and requires Step 3's two empty-set rows to fail. P17
reads the local evidence from the environment and requires Step 3e to fail. P18
removes the bound validation and requires Step 4c to fail in both directions.
P19 drops the allow-list membership test and requires Step 3's unknown-reason
and empty-reason rows to fail.

### Step 10: Documentation states one contract

1. Read the gate section of
   `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`.
2. Read the gate section of
   `docs/workflow/development-workflow/integrations/codex-github.md`.

**Expected result**: both name the same conditions in the same order, the same
fail-closed rule, the same `dispatched` / `deferred` / `forced` /
`deferral_cap` outcomes, the same statement that a defer sets the aggregate to
`needs_fixes` rather than passing as a clean skip, the same reordering of
expensive reviewers last within their own phase bucket, never across the
draft/ready boundary, the same
`PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS` bound and its escalation, and the same
override variable. Reading them against the Step 3, 3b, 3c and 4b expectations
must surface no contradiction.

### Step 11: Static checks

1. Run `shellcheck` on `scripts/development-workflow/pr-review-loop.sh`,
   `pr-ci-loop.sh`, and `workflow-lib.sh` — the relocation touches all three.
2. Run `markdownlint-cli2` on the two changed documentation files, this runbook,
   and the implementation plan.

**Expected result**: both tools exit 0.

---

## Rollback

Revert the implementation PR. The change is additive — one gate function, one
call site, one reorder step, one deferral counter, six `EXPENSIVE_GATE_*` keys
plus `EXPENSIVE_REVIEWERS_REORDERED`, one summary line, and one optional ledger
object —
and reverting restores the previous behavior, in which an expensive reviewer
runs as soon as the phase mechanism reaches it. Ledger entries already written
with `expensive_gate` remain parseable by the reverted reader, which dereferences
unknown fields with defaults. No configuration migration is involved: the gate
reads no `.ai-dev-workflow.yaml` key that this item adds.
