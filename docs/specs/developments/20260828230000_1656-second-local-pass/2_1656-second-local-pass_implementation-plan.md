# Second Local Pass Before Ready-Phase Reviewers — Implementation Plan

**Spec**: None — Refactor item. Source brief:
[issue #1656](https://github.com/lhpaul/ai-dev-framework-template/issues/1656)
(epic [#1647](https://github.com/lhpaul/ai-dev-framework-template/issues/1647))
**Smoke test runbook**:
[1656-second-local-pass.smoke-test.md](../../../testing/workflow/1656-second-local-pass.smoke-test.md)

---

## Summary

**Approach**: Before the first ready-phase reviewer runs, the loop calls
`ensure_pr_ready_for_ready_phase` — which converts the pull request to ready and
nothing else. It does not ask whether the local reviewer has reported clean on
the commit about to be reviewed. Within an ordinary run the local reviewer
usually has, because platforms are dispatched in order every cycle; the gap is
in the cases where it has not, and those are the ordinary operating cases of
this repository: an invocation whose `--platform` list omits the local reviewer,
a `--draft-github-only` run followed by a separate ready-phase run, and a head
that moved after the local reviewer last spoke.

This plan adds one guard immediately before that gate: if the local reviewer's
most recent verdict is not **clean on `loop_head_sha`**, dispatch it once more
and require that pass to be clean before any ready-phase reviewer is activated.

**The design is a re-dispatch, not a refusal.** #1649 gates `codex-github`
behind current-head local clean evidence and stops when the evidence is
missing. This item is the other half: when the evidence is missing **because a
fix landed**, the loop can produce it rather than escalate, and only escalates
when the second pass itself is not clean. The two are complementary and the
plan states where each applies, because implementing both as refusals would
make the loop unable to advance after any local finding.

**Estimated complexity**: M

**Rationale**: The insertion point is one place and the condition is three
comparisons. What makes it more than small is that it adds a reviewer dispatch
**inside** an existing loop that already has two cycle caps and a documented
escalation contract — so the guard has to be provably incapable of running
twice for the same head, and its interaction with both caps has to be decided
rather than inherited.

**Dependencies**: **#1648 must be implemented and merged before this item's
implementation PR opens.** The condition reads the local reviewer's reviewed
head per reviewer, which is #1648's `reviewed_heads[]`. #1649's plan is merged
and its implementation is not; the two touch adjacent code but not the same
lines, and this plan records the boundary in **Interaction with #1649** rather
than sequencing them.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short origin/develop-internal-reviewer-effectiveness` | `d55d3e7f` |
| The ready-phase gate does not consult the local reviewer | `sed -n '8580,8616p' scripts/development-workflow/pr-review-loop.sh` | The gate is `ensure_pr_ready_for_ready_phase "$pr_number"`, whose only job is converting the PR to ready; on success it sets `phase_after_clean_started=1` and dispatch proceeds. Nothing between the two reads any reviewer's result |
| A blocking result ends the cycle | `sed -n '8736,8750p' scripts/development-workflow/pr-review-loop.sh` | On `needs_fixes` or `escalate` the loop `break`s out of the platform iteration in normal mode, so within a run a later cycle re-dispatches from the top — which is why the gap is not "every run" but the cases enumerated in the Summary |
| The pre-dispatch head snapshot exists | `sed -n '8515,8519p' scripts/development-workflow/pr-review-loop.sh` | `loop_head_sha` is captured from `gh pr view --json headRefOid` before any reviewer runs, and is the value #1648 classifies against. The guard compares to it and takes no new snapshot |
| Two caps already bound the run | `sed -n '7174,7195p' scripts/development-workflow/pr-review-loop.sh` | A per-run cap (`CYCLE_COUNT` / `MAX_CYCLES`, default 10) and a lifetime cap (`TOTAL_CYCLE_COUNT` / `MAX_TOTAL_CYCLES`) from the #1502 dual-cap work. The guard is bounded by them and adds no third counter |
| The platform list is filtered before the loop | `sed -n '674,704p' scripts/development-workflow/pr-review-loop.sh` | `filter_phase_after_clean_platforms` removes configured ready-phase platforms absent from this invocation. An invocation can therefore contain ready-phase platforms and **no** local reviewer, which is the first of the Summary's three cases |

**What this log does not establish.** It does not show how often a ready-phase
reviewer has run on a head the local reviewer never saw. The loop does not
record that today; recording it is #1651's work, and this item's guard is what
would make the count zero afterwards.

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved base branch for this item | `develop-internal-reviewer-effectiveness` | `integration-branch:internal-reviewer-effectiveness` label on #1656 | 2026-08-28, repo SHA `d55d3e7f` | Epic #1647 items | `Verified` |
| Per-reviewer head evidence exists | Introduced by #1648 | #1648's merged plan | 2026-08-28, repo SHA `d55d3e7f` | #1648 and #1656 | `Conflict` — see below |
| The ready-phase gate's insertion point | `pr-review-loop.sh:8580-8616` | The file | 2026-08-28, repo SHA `d55d3e7f` | `pr-review-loop.sh`, #1649 | `Conflict` — see below |

**Conflict record.** Two. First, the condition needs each reviewer's reviewed
head, which does not exist on the base branch: #1648's plan is merged, its
implementation is not. Second, #1649 adds its own gate in the same region.
Affected plan statements: the guard's condition and its insertion point.

**Resolution status**: `Resolved`. The first by sequencing — **Implementation
Order step 0**, a hard stop on #1648. The second by scope, recorded in
**Interaction with #1649**: that item decides *whether to dispatch* an expensive
reviewer given the evidence; this one decides *whether to produce* the evidence
first. Decision owner: LH — if #1649 is implemented as a single combined gate,
this plan must be revised rather than layered on top.

### Not applicable

**Overall result for this check**: `Applicable` — the three rows above must be
re-verified at implementation start.

**Surfaces with no assumption**: no database, no runtime service, no
user-facing surface, no scheduled job, no external API, no deployment target.

---

## Layer-by-Layer Changes

### Database / Data Layer

Not applicable.

### Backend / API

Not applicable — this repository ships workflow tooling, not a service.

### Shared Packages / Libraries

- [ ] **Decide whether a second pass is owed.** Add
      `reviewer_loop_local_pass_required <history_payload> <loop_head_sha>`,
      printing one of four values — three that owe a pass and one that does
      not:

      | Local reviewer's most recent verdict | Value | Owes a pass |
      | --- | --- | --- |
      | clean, on `loop_head_sha` | `not_required` | no |
      | clean, on any other commit | `head_changed` | yes |
      | not clean — findings, skipped, unavailable | `prior_findings` | yes |
      | no verdict in this pull request's history | `no_evidence` | yes |

      **Absence owes a pass.** The fourth row is the one a permissive reading
      gets wrong: a pull request whose history says nothing about the local
      reviewer has not been locally reviewed, and treating silence as
      satisfaction is the same fail-open this epic exists to close. It is also
      the ordinary state of an invocation whose `--platform` list omits the
      local reviewer.

      The four values are distinct rather than a boolean because they are
      reported, and a reader wanting to know *why* a pass ran cannot recover it
      from `1`.

- [ ] **Run the pass, immediately before the ready-phase gate.** At
      `pr-review-loop.sh:8580`, before `ensure_pr_ready_for_ready_phase`:

      1. If `reviewer_loop_local_pass_required` returns `not_required`, do
         nothing and proceed exactly as today.
      2. Otherwise dispatch `run_local_ai_reviewer_review` once, through the
         same `run_platform_review` path every platform uses, so its output is
         parsed, recorded and forwarded identically.
      3. If that pass is **clean**, proceed to the gate.
      4. If it is anything else, end the cycle with that result — the same
         `needs_fixes` / `escalate` path a first-pass finding takes — and do
         **not** convert the pull request to ready.

      Step 4 is what makes the guard worth having: a ready-phase reviewer is not
      merely delayed, and the pull request is not converted, so the expensive
      reviewers are not woken at all.

- [ ] **Make repetition impossible, by construction rather than by counting.**
      A flag, `local_second_pass_done_for_head`, holding the head the pass ran
      against. The guard runs only when that value differs from
      `loop_head_sha`, so:

      - it cannot run twice for one head, in one cycle or across cycles;
      - it *can* run again when the head genuinely moved, which is the case the
        brief asks for;
      - it needs no counter of its own, so it cannot drift from the caps.

      **Keying on the head rather than on a per-cycle boolean is the whole
      anti-loop argument.** A boolean reset each cycle would allow one pass per
      cycle forever; a head-keyed flag allows one pass per *commit*, and commits
      only appear when someone pushes. The loop cannot manufacture the condition
      that lets it run again.

- [ ] **Leave both cycle caps alone.** The pass does not increment
      `CYCLE_COUNT` or `TOTAL_CYCLE_COUNT`: it is a dispatch within a cycle, as
      every other platform dispatch is, and the cycle it belongs to is already
      counted. Incrementing would make the caps mean two different things —
      cycles for platforms, cycles-plus-passes for this one — and would shorten
      every run that needed a pass.

      What the caps still bound is the **run**: a pull request whose local
      reviewer never goes clean produces one pass per cycle until
      `MAX_CYCLES` escalates the run with `max_cycles_exceeded`, exactly as it
      does today for a reviewer that never goes clean. Scenario 8 pins that.

- [ ] **Report it.** Two `print_kv` lines:

      ```text
      LOCAL_SECOND_PASS=0|1
      LOCAL_SECOND_PASS_REASON=not_required|head_changed|prior_findings|no_evidence
      ```

      `LOCAL_SECOND_PASS_REASON` is emitted **even when the pass did not run**,
      carrying `not_required`. A key that appears only on the interesting path
      makes its absence ambiguous — an old script, a skipped guard and a
      satisfied condition all look alike — and this is telemetry #1657 will
      read.

      The same two values are added to the ledger entry, so a later report can
      count passes per pull request without re-reading stdout.

### Frontend / UI

- [ ] One line in the reviewer-loop summary when the pass ran, naming the
      reason and the result: `second local pass: head_changed → clean`.

### Infrastructure / Configuration

- [ ] Document both keys and the four reasons in the `--help` block and in
      Protocol 93.

---

## Interaction with #1649

The two items touch the same region and answer different questions. Stated as a
table so an implementer holding both plans can see the seam:

| | #1649 | This item |
| --- | --- | --- |
| Question | may an **expensive** reviewer be dispatched on this evidence? | should the loop **produce** the missing evidence first? |
| Applies to | `codex-github` specifically | the ready-phase gate, whatever platforms follow it |
| When evidence is missing | refuse, fail-closed | dispatch the local reviewer once, then decide |
| Result if that fails | escalate | end the cycle with the pass's own result |

**They compose in one order and not the other.** This item's pass runs first, at
the gate; #1649's check then sees evidence that is either current-clean or
absent-because-the-pass-failed, and in the second case the cycle has already
ended. Implemented the other way round — #1649 refusing before this item can
produce the evidence — the loop could never advance past a local finding,
because the thing that would clear the refusal is the dispatch the refusal
prevents.

If #1649 is implemented as a single combined gate rather than a check, this plan
must be revised rather than layered on it. That is a hard stop in Implementation
Order step 0.

---

## Testing Strategy

**Test types**: Unit (shell harness), plus the smoke test runbook.

**Key scenarios to test**:

1. `reviewer_loop_local_pass_required` returns each of its four values, one case
   per row of its table.
2. `no_evidence` is returned for a history with entries that never name the
   local reviewer — not `not_required`. Silence is not satisfaction, and this is
   the value an invocation without the local reviewer produces.
3. `head_changed` is returned when the local reviewer's clean verdict names a
   commit that is an **ancestor** of `loop_head_sha` — the ordinary
   fix-was-pushed case — and also when it names an unrelated commit. Both owe a
   pass; neither is `not_required`.
4. With `not_required`, the gate is reached with **no** extra dispatch: the
   platform sequence is byte-for-byte what it is today.
5. With any other value, the local reviewer is dispatched exactly once before
   the gate, through `run_platform_review`, and its output is parsed and
   forwarded like any platform's.
6. A **clean** second pass proceeds to the gate and the pull request is
   converted to ready.
7. A **needs_fixes** second pass ends the cycle with `needs_fixes`, does **not**
   convert the pull request, and dispatches no ready-phase platform. Asserted on
   all three, because converting-but-not-dispatching would leave the pull
   request in a state the loop did not intend.
8. The guard runs **at most once per head**: two cycles with no new commit
   dispatch it once; a cycle after a new commit dispatches it again. Asserted by
   counting dispatches, not by reading the flag.
9. Neither `CYCLE_COUNT` nor `TOTAL_CYCLE_COUNT` changes because a pass ran: two
   runs over identical input, one needing a pass and one not, report the same
   counts.
10. A pull request whose local reviewer never goes clean escalates with
    `max_cycles_exceeded` at the same cycle count as today — the guard adds
    passes, not cycles, so the run is not shortened.
11. `LOCAL_SECOND_PASS_REASON` is emitted on **every** run, including
    `not_required`, and `LOCAL_SECOND_PASS` is `0` there.
12. Both values reach the ledger entry and the loop summary, and the summary
    line names the reason and the result.
13. The guard is a no-op when no ready-phase platform is configured: with
    `phase_after_clean_enabled` at 0, nothing is dispatched whatever the
    condition says. The pass exists to protect the gate; with no gate there is
    nothing to protect, and dispatching anyway would double the local reviewer's
    cost on every draft-only run.

**Files**:

- `scripts/development-workflow/tests/test-pr-review-loop.sh` — all thirteen, in
  the existing `HARNESS_MODE=1` harness.

**Smoke test runbook**:
`docs/testing/workflow/1656-second-local-pass.smoke-test.md`

**Regression suite**: the harness named above.

---

## Seed Data

| Fixture | Contents | Location |
| --- | --- | --- |
| Verdict histories | Four `reviewer_loop_history.v1` payloads, one per row of the condition table: local clean on `loop_head_sha`; local clean on an ancestor; local `needs_fixes`; and entries that never name the local reviewer | inline in `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Unrelated-commit history | A local clean verdict on a commit with no ancestry relationship to `loop_head_sha`, for scenario 3's second half | inline in the same file |
| Two-cycle fixture | A run of two cycles with no new commit, and one where a commit lands between them, for scenario 8's dispatch count | inline in the same file |
| Draft-only fixture | An invocation with no ready-phase platform configured, for scenario 13 | inline in the same file |

---

## Documentation Updates

- `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
  — the guard, its four reasons, and the two keys.
- The `--help` block of `pr-review-loop.sh`.
- `changelog.d/1656.changed.second-local-pass.md` — `changed` rather than
  `added`: the ready-phase gate already existed and this alters when it fires.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The guard loops — a pass that keeps triggering itself | Med | **High** — a run that never terminates, or one that burns its cycle budget on repeated local reviews | The flag is keyed on the **head**, so a second pass requires a new commit, which the loop cannot manufacture. Scenario 8 counts dispatches across cycles; proof **P1** replaces the key with a per-cycle boolean |
| Silence is read as satisfaction | **High** — `not_required` is the natural default for "nothing to compare" | **High** — a pull request the local reviewer never examined passes the gate, which is the exact fail-open this epic exists to close | `no_evidence` owes a pass. Scenario 2 and proof **P2** |
| The pass increments a cycle cap | Med | Med — every run needing a pass gets a shorter budget, and `max_cycles_exceeded` starts meaning two different things | The pass is a dispatch inside an already-counted cycle. Scenarios 9 and 10; proof **P3** increments |
| A failed pass converts the pull request anyway | Med | Med — the pull request is left ready with no reviewer dispatched, a state the loop never intended | The cycle ends before the gate. Scenario 7 asserts all three consequences; proof **P4** converts first |
| The guard runs when there is no gate to protect | Med | Low — doubles the local reviewer's cost on every draft-only run | No-op when `phase_after_clean_enabled` is 0. Scenario 13 and proof **P5** |
| This item and #1649 are implemented as one refusal | Med | **High** — the loop can never advance past a local finding, because the evidence that would clear the refusal is the dispatch the refusal prevents | The order is stated in **Interaction with #1649** and enforced by Implementation Order step 0 |

---

## Code Samples

<!-- workflow-shell-contract: bash -->

```bash
# Four values, not a boolean: the reason is reported, and `1` cannot be read
# backwards into a cause.
reviewer_loop_local_pass_required() {
  local payload="${1:-}" head="${2:-}" verdict outcome verdict_head

  verdict="$(reviewer_loop_local_latest_verdict "$payload")"
  outcome="$(printf '%s' "$verdict" | jq -r '.outcome // "unknown"')"
  verdict_head="$(printf '%s' "$verdict" | jq -r '.head_sha // ""')"

  # Absence owes a pass. A history that says nothing about the local reviewer
  # has not been locally reviewed, and `not_required` here would let an
  # invocation that omits the reviewer walk straight through the gate.
  case "$outcome" in
    not_yet_run|not_configured|unknown) printf 'no_evidence\n'; return 0 ;;
    clean) ;;
    *) printf 'prior_findings\n'; return 0 ;;
  esac

  if [ -n "$head" ] && [ "$verdict_head" = "$head" ]; then
    printf 'not_required\n'
  else
    printf 'head_changed\n'
  fi
}
```

---

## Planted-Violation Proofs

`REVIEW.md` → Core Rules → Verification Discipline requires two demonstrated
runs per proof, each citing a concrete file and line. The five proofs fall into
two groups:

| Group | Count | Proofs | What the plant reproduces |
| --- | --- | --- | --- |
| Fail-open | **2** | P2, P4 | the gate reached, or the pull request converted, without the evidence |
| Loop and cost | **3** | P1, P3, P5 | a guard that repeats, shortens the run, or runs where there is nothing to guard |

| # | Violation to plant | Where | Check that must fail, then pass |
| --- | --- | --- | --- |
| P1 | Key the flag on a per-cycle boolean instead of the head | a scratch copy of the guard | scenario 8 fails: two cycles with no new commit dispatch the local reviewer twice, and a pull request whose reviewer never goes clean burns its whole budget on repeated local reviews. The plant looks equivalent — one pass per cycle reads as "at most once" — and only counting dispatches across cycles separates them; restoring the head key passes |
| P2 | Return `not_required` when the history names no local verdict | same scratch copy | scenario 2 fails: a pull request the local reviewer never examined reaches the gate and its ready-phase reviewers run, which is the fail-open this item exists to close. Every other scenario passes, because they all supply a verdict; restoring `no_evidence` passes |
| P3 | Increment `CYCLE_COUNT` when the pass runs | a scratch copy of the dispatch block | scenarios 9 and 10 fail: a run needing a pass reports a different count than an identical run that does not, and `max_cycles_exceeded` arrives earlier — so the guard silently shortens every run it helps; restoring the no-op passes |
| P4 | Call `ensure_pr_ready_for_ready_phase` before checking the pass's result | same scratch copy | scenario 7 fails on its conversion assertion: a failed pass leaves the pull request converted to ready with no reviewer dispatched — a state the loop never intended and a human has to undo. The `needs_fixes` result is still reported, so a test asserting only the result passes; restoring the order passes |
| P5 | Run the guard even when no ready-phase platform is configured | same scratch copy | scenario 13 fails: every draft-only run dispatches the local reviewer twice, doubling the cost of the cheapest gate for no benefit — the pass exists to protect a gate that is not there; restoring the no-op passes |

Two proofs plant the fail-open direction, and P2 is the one to read twice: it is
the natural default, it passes every scenario that supplies a verdict, and the
pull requests it lets through are exactly the ones nobody reviewed locally.

---

## Implementation Order

0. **Hard stop**: confirm #1648 is implemented and merged, and read #1649's
   implementation — merged or in flight — to confirm it is a *check* and not a
   combined gate. If it is combined, stop and revise this plan.
1. Add `reviewer_loop_local_pass_required`. **Verify**: scenarios 1, 2 and 3 —
   all four values, `no_evidence` for silence, and both head-mismatch shapes.
2. Add the head-keyed flag and the dispatch, before
   `ensure_pr_ready_for_ready_phase`. **Verify**: scenarios 4, 5, 6, 7 and 8 —
   including the dispatch count across cycles and all three consequences of a
   failed pass.
3. Confirm the caps are untouched. **Verify**: scenarios 9 and 10.
4. Add the no-op when no ready-phase platform is configured. **Verify**:
   scenario 13.
5. Add both `print_kv` lines, the ledger fields and the summary line.
   **Verify**: scenarios 11 and 12.
6. Update Protocol 93, the `--help` block, and add
   `changelog.d/1656.changed.second-local-pass.md`. **Verify**: runbook Step 8.
7. Produce the five planted-violation proofs (P1-P5) and record them in the PR
   with the command, file, line and both outcomes for each.

---

## Rollback

Revert the implementation PR. It removes one condition function, one dispatch
block, one flag, two `print_kv` lines, two ledger fields, one summary line and
the documentation updates. The ready-phase gate returns to converting the pull
request without consulting the local reviewer, which is today's behavior;
nothing else reads the removed keys.
