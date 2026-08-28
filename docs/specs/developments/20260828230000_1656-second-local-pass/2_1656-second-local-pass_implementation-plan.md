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

**Dependencies**: **#1648 and #1651 must both be implemented and merged before
this item's implementation PR opens, in that order.** The condition needs the
local reviewer's most recent verdict *and* the commit it describes, and neither
exists on the base branch today:

- **#1648** adds `reviewed_heads[]`, the per-reviewer commit.
- **#1651** adds `platform_results` and
  `reviewer_loop_local_latest_verdict <history_payload> <configured_platforms>`
  — the selector this item's condition calls, with that two-argument signature.
  #1651 itself depends on #1648, so the chain is **#1648 → #1651 → #1656**.

An earlier revision of this plan named only #1648 and called the selector with
one argument. That was wrong twice: the helper belongs to #1651, and its
signature takes the configured-platform list, without which `not_configured`
cannot be distinguished from `not_yet_run` — a distinction this item's
`no_evidence` row depends on.

Defining a second selector here instead was considered and rejected: two
readers of the same ledger field is how the two drift, and #1651's already
handles the four absence cases this condition must classify.

#1649's plan is merged and its implementation is not; the two touch adjacent
code but not the same lines, and this plan records the boundary in
**Interaction with #1649** rather than sequencing them.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short origin/develop-internal-reviewer-effectiveness` | `d55d3e7f` |
| The ready-phase gate does not consult the local reviewer | `sed -n '8580,8616p' scripts/development-workflow/pr-review-loop.sh` | The gate is `ensure_pr_ready_for_ready_phase "$pr_number"`, whose only job is converting the PR to ready; on success it sets `phase_after_clean_started=1` and dispatch proceeds. Nothing between the two reads any reviewer's result |
| A blocking result ends the cycle | `sed -n '8736,8750p' scripts/development-workflow/pr-review-loop.sh` | On `needs_fixes` or `escalate` the loop `break`s out of the platform iteration in normal mode, so within a run a later cycle re-dispatches from the top — which is why the gap is not "every run" but the cases enumerated in the Summary |
| The pre-dispatch head snapshot exists | `sed -n '8515,8519p' scripts/development-workflow/pr-review-loop.sh` | `loop_head_sha` is captured from `gh pr view --json headRefOid` before any reviewer runs, and is the value #1648 classifies against. The guard compares to it and takes no new snapshot |
| Two caps already bound the run | `sed -n '7174,7195p' scripts/development-workflow/pr-review-loop.sh` | A per-run cap (`CYCLE_COUNT` / `MAX_CYCLES`, default 10) and a lifetime cap (`TOTAL_CYCLE_COUNT` / `MAX_TOTAL_CYCLES`) from the #1502 dual-cap work. The guard adds no third counter |
| …but neither bounds a repeated identical entry | `sed -n '/^reviewer_loop_history_entries_count()/,/^}/p' scripts/development-workflow/pr-review-loop.sh` | The lifetime count is `unique` over `head_sha \| result`, so repeated `needs_fixes` entries at one head count **once**, and `CYCLE_COUNT` resets each invocation. A refusal reported as `needs_fixes` would therefore repeat indefinitely — which is why the refusal is `escalate` |
| The platform list is filtered before the loop | `sed -n '674,704p' scripts/development-workflow/pr-review-loop.sh` | `filter_phase_after_clean_platforms` removes configured ready-phase platforms absent from this invocation. An invocation can therefore contain ready-phase platforms and **no** local reviewer, which is the first of the Summary's three cases |
| The configuration is not read when `--platform` is given | `sed -n '8330,8342p' scripts/development-workflow/pr-review-loop.sh` | `workflow_config_review_platforms` is consulted only when the platform list is otherwise empty. So the invocation's `platforms` array cannot answer *is this reviewer configured for the repository* — the guard resolves that separately |

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
| The verdict selector exists, with two arguments | `reviewer_loop_local_latest_verdict <payload> <configured_platforms>`, introduced by #1651 | #1651's merged plan | 2026-08-28, repo SHA `d55d3e7f` | #1651 and #1656 | `Conflict` — see below |
| The ready-phase gate's insertion point | `pr-review-loop.sh:8580-8616` | The file | 2026-08-28, repo SHA `d55d3e7f` | `pr-review-loop.sh`, #1649 | `Conflict` — see below |

**Conflict record.** Three. First, the condition needs each reviewer's reviewed
head, which does not exist on the base branch: #1648's plan is merged, its
implementation is not. Second, it calls #1651's verdict selector, which is in
the same state — and whose two-argument signature is what separates
`not_configured` from `not_yet_run`. Third, #1649 adds its own gate in the same
region. Affected plan statements: the guard's condition and its insertion
point.

**Resolution status**: `Resolved`. The first two by sequencing —
**Implementation Order step 0**, a hard stop on the chain #1648 → #1651 →
#1656. The second by scope, recorded in
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
      `reviewer_loop_local_pass_required <history_payload> <loop_head_sha> <configured_platforms>`,
      printing one of five values — three that owe a pass and two that do not:

      | Local reviewer's most recent verdict | Value | Owes a pass |
      | --- | --- | --- |
      | clean, on `loop_head_sha` | `not_required` | no |
      | clean, on any other commit | `head_changed` | yes |
      | not clean — findings, skipped, unavailable | `prior_findings` | yes |
      | no verdict, and the reviewer **is** configured | `no_evidence` | yes |
      | the reviewer is **not configured** for this repository | `no_local_reviewer` | no — see below |

      **Absence owes a pass — but only where a pass is possible.** The fourth
      row is the one a permissive reading gets wrong: a pull request whose
      history says nothing about a *configured* local reviewer has not been
      locally reviewed, and treating silence as satisfaction is the same
      fail-open this epic exists to close. It is the ordinary state of an
      invocation whose `--platform` list omits the reviewer, and the reviewer is
      there to be dispatched.

      **The fifth row is a different fact and must not be folded into it.**
      #1651's selector returns `not_configured` when the repository has no local
      reviewer configured at all — not omitted from this invocation, but absent
      from `review.on_draft.runner`. There is nothing to dispatch, so a pass is
      not merely unowed, it is impossible.

      That row **proceeds**, and the choice is deliberate. Refusing would block
      the ready-phase gate on every pull request in every repository that has
      not adopted a local reviewer — which this template must keep working for,
      and which no amount of retrying could clear. Proceeding is not a silent
      pass either: `LOCAL_SECOND_PASS_REASON` carries `no_local_reviewer`, so a
      reader can tell *the gate was satisfied* from *there was nothing to
      satisfy it with*, and #1657 can exclude those repositories from any
      effectiveness rate rather than counting them as clean.

      Conflating the two rows is what an implementer would otherwise have to
      invent behavior for: a dispatch of a reviewer that does not exist.

      **The list the condition receives must be the repository's, not the
      invocation's**, and this is the part most easily got wrong. The loop's
      `platforms` array is invocation-filtered, and `pr-review-loop.sh` skips
      `workflow_config_review_platforms` entirely when explicit `--platform`
      arguments are supplied — so passing `platforms` would report
      `not_configured` for a reviewer that **is** configured and merely omitted
      from this run. That is the motivating case of this whole item, and it
      would proceed without a pass: a fail-open produced by the very argument
      added to prevent one.

      So the guard resolves its own input. Add
      `reviewer_loop_repo_configured_platforms`, which reads
      `workflow_config_review_platforms` from the configuration file
      **unconditionally**, independent of `--platform`, and caches the result
      for the run. The condition receives that value and never the `platforms`
      array. Scenario 2b pins it with an explicit `--platform` invocation that
      omits a configured local reviewer.

      The five values are distinct rather than a boolean because they are
      reported, and a reader wanting to know *why* a pass ran cannot recover it
      from `1`.

      **The payload it reads must include the current round.** #1651's selector
      is a pure query over one payload, and its caller composes the round's
      in-memory `platform_results` and `reviewed_heads[]` into `entries[]` as a
      synthetic entry before selecting. This condition inherits that
      requirement, and it is not optional here: by the time the guard runs, the
      local reviewer has usually already reported **in this cycle**, and its
      verdict lives only in memory — the ledger entry carrying it is written at
      the end of the cycle. Reading the persisted payload alone would make every
      ordinary run owe a pass it does not need, which is scenario 4's case and
      the opposite of the item's purpose. The composition is the same helper
      #1651's call site uses; this is a second caller of it, not a second copy.

- [ ] **Run the pass, immediately before the ready-phase gate.** At
      `pr-review-loop.sh:8580`, before `ensure_pr_ready_for_ready_phase`:

      1. If `reviewer_loop_local_pass_required` returns `not_required` **or**
         `no_local_reviewer`, do nothing and proceed exactly as today. Both are
         the table's non-owing rows, and they exempt for different reasons: the
         first has current evidence, the second has no reviewer to produce any.
         Listing only `not_required` here would have `no_local_reviewer` fall
         through to a dispatch of a reviewer that does not exist — which is the
         contradiction the table exists to prevent, reintroduced by an "and
         otherwise" that predates the fifth value.
      2. Otherwise — `head_changed`, `prior_findings` or `no_evidence` —
         dispatch the local reviewer once and process its output
         through the **same code the platform loop uses**. That needs a small
         extraction first: `run_platform_review` only dispatches — the parsing,
         the aggregation, the `print_kv` forwarding, the
         `platform_result_records` accumulation and the reviewed-head collection
         all live inline in the platform loop, *after* its call. A guard-side
         call to `run_platform_review` alone would produce output nobody parsed
         and a pass that appears in no ledger entry.

         So the plan extracts that inline block into
         `reviewer_loop_process_platform_output <platform_name> <platform_index> <output> <status>`,
         called from both the platform loop and the guard. The extraction is
         **behaviour-preserving by requirement, not by intention**: scenario 5a
         runs a pull request that needs no pass and asserts the loop's entire
         `key=value` output is byte-identical to the same run before this
         change. An extraction that quietly reorders or drops a key would pass
         every other scenario in this plan.
      3. If that pass is **clean**, proceed to the gate.
      4. If it is anything else, end the cycle with that result — the same
         `needs_fixes` / `escalate` path a first-pass finding takes — and do
         **not** convert the pull request to ready.

      Step 4 is what makes the guard worth having: a ready-phase reviewer is not
      merely delayed, and the pull request is not converted, so the expensive
      reviewers are not woken at all.

- [ ] **Make repetition impossible without opening a hole, across invocations
      as well as within one.** A **ledger field**,
      `local_second_pass_failed_head`, holding the head a pass ran against and
      failed on — written into the entry, not held in a variable.

      An in-memory flag would not survive the run. The loop is re-invoked after
      every blocking result, which is exactly what a failed pass produces: the
      next invocation starts with an empty flag, sees the same non-clean
      verdict, and dispatches again. The guarantee would then be "at most once
      per head **per invocation**", which on a pull request whose local reviewer
      never goes clean is one dispatch per invocation forever — the loop this
      item is supposed to prevent, arrived at from outside the run instead of
      inside it.

      The guard therefore reads the most recent ledger entry carrying the field
      and compares it to `loop_head_sha`. The ledger is already the loop's
      cross-invocation memory; this is one more field in it, not a new
      mechanism. It produces a three-way guard, not a two-way one:

      | Condition | Recorded failed head matches `loop_head_sha` | Action |
      | --- | --- | --- |
      | `not_required` | — | proceed to the gate; no dispatch |
      | owes a pass | no | **dispatch once**; clean → proceed, otherwise end the cycle and record the head |
      | owes a pass | yes | **refuse**: end the run with **`escalate`**, reason `failed_for_head`, no dispatch and no conversion |

      **The third row is the one a two-way guard gets wrong**, and it is not a
      corner case — it is the next cycle after any failed pass. A flag that only
      suppresses the dispatch leaves the condition still owing a pass, nothing
      running, and the gate reached with no current clean evidence: a fail-open
      created by the anti-loop mechanism itself. Refusing instead is
      deterministic, costs no dispatch, and keeps the guarantee the item exists
      for.

      **It refuses with `escalate`, not `needs_fixes`, and that is what makes
      the refusal bounded.** The lifetime cap counts `unique` entries keyed on
      `head_sha|result` (`reviewer_loop_history_entries_count`), so repeated
      `needs_fixes` entries at one head count **once** — and `CYCLE_COUNT`
      resets every invocation. A refusal that reported `needs_fixes` could
      therefore repeat across invocations forever without either cap advancing:
      the boundedness would be asserted and untrue.

      `escalate` is terminal for the run and routes to a human, which is also
      the honest signal. Nothing has changed since the last failure — same head,
      same verdict, no dispatch — so a result that invites another automated
      attempt invites one the loop already knows is futile. Scenario 10a pins
      that the refusal does not depend on a cap to terminate.

      A **clean** pass records nothing and needs to record nothing: the verdict
      it produced is clean on `loop_head_sha`, so the condition itself returns
      `not_required` on every later cycle and in every later invocation. The
      field exists only for the failed case.

      Keying on the head rather than on a per-cycle boolean is still the
      anti-loop argument, and persisting it is what makes the argument hold
      where it matters: at most one *dispatch* per commit, across the whole pull
      request rather than per run, and commits only appear when someone pushes.
      The loop cannot manufacture the condition that lets it dispatch again.

- [ ] **Leave both cycle caps alone.** The pass does not increment
      `CYCLE_COUNT` or `TOTAL_CYCLE_COUNT`: it is a dispatch within a cycle, as
      every other platform dispatch is, and the cycle it belongs to is already
      counted. Incrementing would make the caps mean two different things —
      cycles for platforms, cycles-plus-passes for this one — and would shorten
      every run that needed a pass.

      What the caps still bound is the **run**: a pull request whose local
      reviewer never goes clean produces **one dispatch for the first head**,
      then a refusal on every later cycle at that head, until `MAX_CYCLES`
      escalates the run with `max_cycles_exceeded` — the same escalation and the
      same cycle count as today, with fewer dispatches than a per-cycle guard
      would make. Scenarios 8 and 8a pin both halves.

- [ ] **Report it.** Two `print_kv` lines:

      ```text
      LOCAL_SECOND_PASS=0|1
      LOCAL_SECOND_PASS_REASON=not_required|head_changed|prior_findings|no_evidence|no_local_reviewer|failed_for_head
      ```

      `failed_for_head` is the refusal row — the pass did not run **and** the
      gate was refused — and it is distinct from `not_required`, where the pass
      did not run because none was owed. Collapsing the two would make the
      telemetry unable to tell a satisfied gate from a blocked one, which is the
      distinction #1657 needs most.

      `LOCAL_SECOND_PASS_REASON` is emitted **even when the pass did not run**,
      carrying `not_required`. A key that appears only on the interesting path
      makes its absence ambiguous — an old script, a skipped guard and a
      satisfied condition all look alike — and this is telemetry #1657 will
      read.

      The same two values are added to the ledger entry, together with
      `local_second_pass_failed_head` — which is not merely telemetry but the
      guard's own cross-invocation memory, and is why it lives in the ledger
      rather than in a variable.

### Frontend / UI

- [ ] One line in the reviewer-loop summary when the pass ran, naming the
      reason and the result: `second local pass: head_changed → clean`.

### Infrastructure / Configuration

- [ ] Document both keys and **all six** reasons — the five conditions plus
      `failed_for_head` — in the `--help` block and in Protocol 93. The two
      easiest to omit are the ones that report neither a satisfied nor a
      repaired gate: `failed_for_head`, a **blocked** one, and
      `no_local_reviewer`, one with nothing to satisfy it.

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

**One consequence of the repository-configured list reaches #1649 and must be
recorded there rather than assumed.** #1649's plan derives
`local_ai_configured` from the invocation-filtered `platforms[]`. On the
motivating case — an explicit `--platform` run that omits a configured local
reviewer — this item's guard now dispatches that reviewer and produces
current-head clean evidence, and #1649 would still report
`local_reviewer_not_configured` and refuse `codex-github`. The evidence exists;
the check cannot see that it was allowed to.

The fix belongs to whichever item lands second, and this plan states which:
**#1649 must derive `local_ai_configured` from the repository's configured list**
— `reviewer_loop_repo_configured_platforms`, the helper this item adds — rather
than from `platforms[]`. If #1649 is implemented first, this is a one-line
follow-up in its file; if this item is implemented first, the helper is already
there. Implementation Order step 0 requires reading #1649's implementation and
confirming which case applies, and scenario 12a asserts the composed behaviour
end to end.

If #1649 is implemented as a single combined gate rather than a check, this plan
must be revised rather than layered on it. That is a hard stop in Implementation
Order step 0.

---

## Testing Strategy

**Test types**: Unit (shell harness), plus the smoke test runbook.

**Key scenarios to test**:

1. `reviewer_loop_local_pass_required` returns each of its five values, one case
   per row of its table.
2. `no_evidence` is returned for a history with entries that never name the
   local reviewer **while the reviewer is configured** — not `not_required`.
   Silence is not satisfaction, and this is the value an invocation whose
   `--platform` list omits a configured reviewer produces.
2b. An explicit `--platform` invocation that **omits** a configured local
   reviewer returns `no_evidence` and owes a pass — not `no_local_reviewer`.
   The condition reads the repository's configured list, resolved
   independently, and never the invocation-filtered `platforms` array, which is
   empty of the reviewer in exactly this case. This is the item's motivating
   scenario, and passing the wrong list turns it into a fail-open.
2a. `no_local_reviewer` is returned when the reviewer is **not configured for
   the repository**, and the guard **proceeds** without dispatching. Asserted as
   a distinct value from both `no_evidence` and `not_required`: the first would
   dispatch a reviewer that does not exist, the second would report a satisfied
   gate where there was nothing to satisfy it with. The two inputs differ only
   in the configured-platform list passed to #1651's selector, which is why that
   argument is not optional.
3. `head_changed` is returned when the local reviewer's clean verdict names a
   commit that is an **ancestor** of `loop_head_sha` — the ordinary
   fix-was-pushed case — and also when it names an unrelated commit. Both owe a
   pass; neither is `not_required`.
4. With `not_required`, the gate is reached with **no** extra dispatch: the
   platform sequence is byte-for-byte what it is today.
5. With any other value, the local reviewer is dispatched exactly once before
   the gate, and its output is processed by
   `reviewer_loop_process_platform_output` — the same function the platform loop
   calls — so the pass is parsed, aggregated, forwarded and recorded in the
   ledger entry like any platform's.
5a. The extraction is behaviour-preserving: for a pull request that needs **no**
   pass, every `key=value` line that existed before this change is byte-identical
   to the same run before it — the comparison excludes `LOCAL_SECOND_PASS` and
   `LOCAL_SECOND_PASS_REASON`, which this item adds on every run by design. This is the scenario that fails if the extraction drops
   or reorders a key, and every other scenario here would pass with that defect.
5b. The condition sees the **current round**: a cycle in which the local
   reviewer already reported clean, whose ledger entry is not yet written,
   returns `not_required`. Reading the persisted payload alone returns
   `head_changed` or `no_evidence` and makes every ordinary run owe a pass.
6. A **clean** second pass proceeds to the gate and the pull request is
   converted to ready.
7. A **needs_fixes** second pass ends the cycle with `needs_fixes`, does **not**
   convert the pull request, and dispatches no ready-phase platform. Asserted on
   all three, because converting-but-not-dispatching would leave the pull
   request in a state the loop did not intend.
8. The guard dispatches **at most once per head**: two cycles with no new
   commit dispatch it once; a cycle after a new commit dispatches it again.
   Asserted by counting dispatches, not by reading the field.
8c. The guarantee survives **re-invocation**: after a failed pass ends a run, a
   **new** invocation of the loop at the same head refuses with `escalate`
   rather than dispatching again. This is the case an in-memory flag loses, and it is not
   hypothetical — the loop is re-invoked after every blocking result, which is
   what a failed pass produces.
8a. After a **failed** pass, the next cycle at the same head **refuses**: the
   run ends with `escalate` and reason `failed_for_head`, no local reviewer is
   dispatched, and the pull request is not converted. A guard
   that only suppressed the dispatch would let this cycle reach the gate with no
   current clean evidence — the fail-open the anti-loop flag would otherwise
   create.
8b. After a **clean** pass, later cycles take the `not_required` path with no
   dispatch and no refusal, because the verdict the pass produced is clean on
   `loop_head_sha`. The flag is never set for a clean pass and none is needed.
9. Neither `CYCLE_COUNT` nor `TOTAL_CYCLE_COUNT` changes because a pass ran: two
   runs over identical input, one needing a pass and one not, report the same
   counts.
10. A pull request whose local reviewer never goes clean reaches
    `max_cycles_exceeded` at the same cycle count as today when the head keeps
    moving — the guard adds no cycles, and one dispatch per head.
10a. When the head does **not** move, the refusal terminates without relying on
    a cap: the second invocation at that head escalates with `failed_for_head`.
    Asserted directly, because the lifetime cap counts `unique`
    `head_sha|result` pairs and would never advance on repeated identical
    entries — a refusal reported as `needs_fixes` would repeat forever with both
    caps standing still.
11. `LOCAL_SECOND_PASS_REASON` is emitted on **every** run, including
    `not_required`, and `LOCAL_SECOND_PASS` is `0` there.
12. Both values reach the ledger entry and the loop summary, and the summary
    line names the reason and the result.
12a. Composed with #1649 on the motivating case: an explicit `--platform` run
    that omits a configured local reviewer dispatches the pass, produces
    current-head clean evidence, and `codex-github` is **not** refused. Asserted
    end to end rather than on each item's own unit, because the failure is
    exactly that two correct units disagree about what "configured" means.
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
  — the guard, all **six** reasons including `no_local_reviewer` and
  `failed_for_head`, the two keys,
  and the `local_second_pass_failed_head` ledger field.
- The `--help` block of `pr-review-loop.sh`.
- `changelog.d/1656.changed.second-local-pass.md` — `changed` rather than
  `added`: the ready-phase gate already existed and this alters when it fires.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The guard loops — a pass that keeps triggering itself | Med | **High** — a run that never terminates, or one that burns its cycle budget on repeated local reviews | Keyed on the **head**, so a second dispatch requires a new commit, which the loop cannot manufacture. Scenario 8 counts dispatches across cycles; proof **P1** replaces the key with a per-cycle boolean |
| The refusal repeats forever because no cap counts it | **High** — `needs_fixes` is the natural result for a blocked gate | **High** — the boundedness the plan claims is asserted and untrue, and the run never terminates on an unchanged head | The refusal is `escalate`, terminal for the run. Scenario 10a runs a second invocation; proof **P12** reports `needs_fixes` |
| The anti-loop state is lost between invocations | **High** — the loop is re-invoked after every blocking result, which is what a failed pass produces | **High** — one dispatch per invocation forever, the same loop arrived at from outside the run | The failed head lives in the ledger, the loop's existing cross-invocation memory. Scenario 8c and proof **P9** |
| The anti-loop flag creates a fail-open | **High** — a two-way guard is the obvious shape | **High** — the cycle after a failed pass reaches the gate with no current clean evidence, and the mechanism meant to bound the guard is what lets it through | Three-way guard: dispatch, refuse, or proceed. Scenario 8a and proof **P6** |
| Silence is read as satisfaction | **High** — `not_required` is the natural default for "nothing to compare" | **High** — a pull request the local reviewer never examined passes the gate, which is the exact fail-open this epic exists to close | `no_evidence` owes a pass. Scenario 2 and proof **P2** |
| The pass increments a cycle cap | Med | Med — every run needing a pass gets a shorter budget, and `max_cycles_exceeded` starts meaning two different things | The pass is a dispatch inside an already-counted cycle. Scenarios 9 and 10; proof **P3** increments |
| A failed pass converts the pull request anyway | Med | Med — the pull request is left ready with no reviewer dispatched, a state the loop never intended | The cycle ends before the gate. Scenario 7 asserts all three consequences; proof **P4** converts first |
| The extraction changes the ordinary path | Med — it touches the busiest block in the script | **High** — every run's output shifts, and the cause is a refactor nobody was reviewing for behaviour | Byte-identical output required for a run needing no pass, in its own commit so the diff is readable. Scenario 5a and proof **P8** |
| The condition receives the invocation's platform list | **High** — `platforms` is in scope and looks right | **High** — an explicit `--platform` run omitting a configured reviewer reports `no_local_reviewer` and proceeds, which is the item's motivating case turned into a fail-open | The repository's configured list is resolved independently of `--platform`, by its own helper. Scenario 2b and proof **P11** |
| The condition ignores the current round | **High** — the persisted payload is the obvious input | Med — every ordinary run dispatches the local reviewer twice, and the guard becomes a tax on the path it was meant to leave alone | The round's in-memory results are composed in first, using #1651's helper. Scenarios 4 and 5b, proof **P7** |
| The guard runs when there is no gate to protect | Med | Low — doubles the local reviewer's cost on every draft-only run | No-op when `phase_after_clean_enabled` is 0. Scenario 13 and proof **P5** |
| #1649 keeps deriving `local_ai_configured` from `platforms[]` | **High** — that is what its merged plan says | **High** — the guard produces the evidence and #1649 refuses anyway, so the motivating case still cannot reach `codex-github` | Both read `reviewer_loop_repo_configured_platforms`; step 0 requires confirming or changing it. Scenario 12a asserts the composition end to end |
| This item and #1649 are implemented as one refusal | Med | **High** — the loop can never advance past a local finding, because the evidence that would clear the refusal is the dispatch the refusal prevents | The order is stated in **Interaction with #1649** and enforced by Implementation Order step 0 |

---

## Code Samples

<!-- workflow-shell-contract: bash -->

```bash
# Five values, not a boolean: the reason is reported, and `1` cannot be read
# backwards into a cause.
reviewer_loop_local_pass_required() {
  local payload="${1:-}" head="${2:-}" configured="${3:-}"
  local verdict outcome verdict_head

  # #1651's selector, with its two-argument signature: the configured-platform
  # list is what separates `not_configured` from `not_yet_run`, and this
  # condition's `no_evidence` row needs both.
  verdict="$(reviewer_loop_local_latest_verdict "$payload" "$configured")"
  outcome="$(printf '%s' "$verdict" | jq -r '.outcome // "unknown"')"
  verdict_head="$(printf '%s' "$verdict" | jq -r '.head_sha // ""')"

  # Absence owes a pass. A history that says nothing about the local reviewer
  # has not been locally reviewed, and `not_required` here would let an
  # invocation that omits the reviewer walk straight through the gate.
  case "$outcome" in
    # Not configured is not the same as configured-and-silent: there is nothing
    # to dispatch, so the guard proceeds and says so rather than owing a pass it
    # could never discharge.
    not_configured) printf 'no_local_reviewer\n'; return 0 ;;
    not_yet_run|unknown) printf 'no_evidence\n'; return 0 ;;
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
runs per proof, each citing a concrete file and line. The twelve proofs fall into
three groups:

| Group | Count | Proofs | What the plant reproduces |
| --- | --- | --- | --- |
| Fail-open | **5** | P2, P4, P6, P10, P11 | the gate reached, or the pull request converted, without the evidence |
| Loop and cost | **4** | P1, P3, P5, P12 | a guard that repeats, shortens the run, or runs where there is nothing to guard |
| Integration | **3** | P7, P8, P9 | a guard wired in beside the pipeline rather than into it |

| # | Violation to plant | Where | Check that must fail, then pass |
| --- | --- | --- | --- |
| P1 | Key the flag on a per-cycle boolean instead of the head | a scratch copy of the guard | scenario 8 fails: two cycles with no new commit dispatch the local reviewer twice, and a pull request whose reviewer never goes clean burns its whole budget on repeated local reviews. The plant looks equivalent — one pass per cycle reads as "at most once" — and only counting dispatches across cycles separates them; restoring the head key passes |
| P7 | Read the persisted payload without composing the current round | a scratch copy of the condition | scenario 5b fails: a cycle whose local reviewer has already reported clean owes a pass anyway, so every ordinary run dispatches the reviewer twice — the guard becomes a tax on the path it was meant to leave alone. Scenario 4's no-dispatch case fails with it, which is the visible symptom; restoring the composition passes both |
| P9 | Hold the failed head in a shell variable instead of the ledger | a scratch copy of the guard | scenario 8c fails: the invocation after a failed pass starts with an empty variable, sees the same non-clean verdict, and dispatches again — one dispatch per invocation forever on a pull request whose reviewer never goes clean. Scenario 8's within-run count still passes, because a variable survives a run; only crossing an invocation separates them; restoring the ledger field passes |
| P8 | Call `run_platform_review` from the guard without processing its output | a scratch copy of the dispatch block | scenario 5's ledger assertion fails: the pass runs, its verdict decides the gate, and it appears in no ledger entry and no `key=value` output — so the telemetry says the gate opened with no evidence of what opened it. The gate behaviour is still correct, which is what makes this the plant a hurried extraction invites; restoring the shared processor passes |
| P6 | Make the flag suppress the dispatch without refusing the gate | same scratch copy | scenario 8a fails: the cycle after a failed pass reaches the gate with no current clean evidence, because the condition still owes a pass and nothing runs — a fail-open created by the anti-loop mechanism itself. Scenario 8's dispatch count still passes, which is what makes this the plant a two-way guard invites; restoring the refusal passes both |
| P12 | Refuse with `needs_fixes` instead of `escalate` | same scratch copy | scenario 10a fails: the lifetime cap counts `unique` `head_sha\|result` pairs and `CYCLE_COUNT` resets each invocation, so an unchanged head refuses forever with neither cap advancing — the boundedness the plan claims would be asserted and untrue. Scenario 8a's single-refusal assertion still passes, which is why 10a runs a **second** invocation; restoring `escalate` passes both |
| P2 | Return `not_required` when the history names no local verdict | same scratch copy | scenario 2 fails: a pull request the local reviewer never examined reaches the gate and its ready-phase reviewers run, which is the fail-open this item exists to close. Every other scenario passes, because they all supply a verdict; restoring `no_evidence` passes |
| P11 | Pass the invocation's `platforms` array to the condition instead of the repository's configured list | a scratch copy of the guard's call site | scenario 2b fails: an explicit `--platform` run that omits a configured local reviewer reports `no_local_reviewer` and proceeds without a pass — the item's motivating case, turned into a fail-open by the argument added to prevent one. Every scenario that runs without `--platform` passes, because there the two lists coincide; restoring the independent resolution passes |
| P10 | Fold `not_configured` into `no_evidence` | same scratch copy | scenario 2a fails: a repository with no local reviewer configured owes a pass that cannot be dispatched, so either the guard blocks its ready-phase gate forever or an implementer invents a fallback the plan never specified. Scenario 2 passes, because a configured-but-silent reviewer is a different input; restoring the fifth value passes both |
| P3 | Increment `CYCLE_COUNT` when the pass runs | a scratch copy of the dispatch block | scenarios 9 and 10 fail: a run needing a pass reports a different count than an identical run that does not, and `max_cycles_exceeded` arrives earlier — so the guard silently shortens every run it helps; restoring the no-op passes |
| P4 | Call `ensure_pr_ready_for_ready_phase` before checking the pass's result | same scratch copy | scenario 7 fails on its conversion assertion: a failed pass leaves the pull request converted to ready with no reviewer dispatched — a state the loop never intended and a human has to undo. The `needs_fixes` result is still reported, so a test asserting only the result passes; restoring the order passes |
| P5 | Run the guard even when no ready-phase platform is configured | same scratch copy | scenario 13 fails: every draft-only run dispatches the local reviewer twice, doubling the cost of the cheapest gate for no benefit — the pass exists to protect a gate that is not there; restoring the no-op passes |

Five proofs plant the fail-open direction, and P2 is the one to read twice: it is
the natural default, it passes every scenario that supplies a verdict, and the
pull requests it lets through are exactly the ones nobody reviewed locally.

---

## Implementation Order

0. **Hard stop**: confirm **#1648 and #1651** are both implemented and merged,
   and that `reviewer_loop_local_latest_verdict` exists with the two-argument
   signature #1651's plan specifies. Then read #1649's implementation — merged
   or in flight — to confirm it is a *check* and not a combined gate, **and**
   that its `local_ai_configured` derives from the repository's configured list
   rather than from `platforms[]`. If it derives from `platforms[]`, change it
   to use `reviewer_loop_repo_configured_platforms` as part of this item. If it
   is a combined gate, stop and revise this plan.
1. Add `reviewer_loop_repo_configured_platforms`, reading the configuration
   unconditionally, and `reviewer_loop_local_pass_required`, calling #1651's
   selector with both of its arguments and never with the `platforms` array.
   **Verify**: scenarios 1, 2, 2a, 2b and 3 — all five values,
   `no_evidence` for a silent but configured reviewer, `no_local_reviewer` for
   an unconfigured one, and both head-mismatch shapes.
1a. Extract the platform loop's inline post-dispatch block into
   `reviewer_loop_process_platform_output`, changing nothing else. **Verify**:
   scenario 5a — byte-identical `key=value` output for a run that needs no pass.
   Do this as its own commit, so the extraction's diff can be read on its own.
2. Add the three-way guard — dispatch, refuse, or proceed — with the flag
   recording in the ledger the head a pass **failed** on, before
   `ensure_pr_ready_for_ready_phase`, and compose the current round into the
   payload before evaluating the condition. **Verify**: scenarios 4, 5, 5b, 6,
   7, 8, 8a, 8b and 8c — the dispatch count across cycles, all three consequences of a failed
   pass, the refusal on the next cycle at the same head, and the `not_required`
   path after a clean pass.
3. Confirm the caps are untouched and that the refusal terminates without one.
   **Verify**: scenarios 9, 10 and 10a.
4. Add the no-op when no ready-phase platform is configured. **Verify**:
   scenario 13.
5. Add both `print_kv` lines, the ledger fields and the summary line.
   **Verify**: scenarios 11 and 12.
6. Update Protocol 93, the `--help` block, and add
   `changelog.d/1656.changed.second-local-pass.md`. **Verify**: runbook **Step
   10**, which reads both surfaces and the fragment against each other — Step 8
   is the no-gate/no-guard case.
7. Produce the twelve planted-violation proofs (P1-P12) and record them in the PR
   with the command, file, line and both outcomes for each.

---

## Rollback

Revert the implementation PR. It removes one condition function, one dispatch
block, one flag, two `print_kv` lines, two ledger fields, one summary line and
the documentation updates. The ready-phase gate returns to converting the pull
request without consulting the local reviewer, which is today's behavior;
nothing else reads the removed keys.
