# Smoke Test: Second Local Pass Before Ready-Phase Reviewers (#1656)

**Item**: [#1656](https://github.com/lhpaul/ai-dev-framework-template/issues/1656)
**Plan**: [2_1656-second-local-pass_implementation-plan.md](../../specs/developments/20260828230000_1656-second-local-pass/2_1656-second-local-pass_implementation-plan.md)

Steps 1 and 2 source the loop with `HARNESS_MODE=1` and call the condition
directly; the rest exercise the assembled behavior. Sourcing enables
`set -euo pipefail`; call anything that returns non-zero as a normal answer
inside an `if` or with `|| true`.

---

## Step 1: The condition's five values

**Maps to**: brief scope bullets 1 and 2.

1. Call `reviewer_loop_local_pass_required` with a history whose local verdict is
   **clean on `loop_head_sha`**.
2. Call it with a local clean verdict on an **ancestor** of `loop_head_sha`.
3. Call it with a local clean verdict on an **unrelated** commit.
4. Call it with a local **needs_fixes** verdict.
5. Call it with entries that **never name** the local reviewer, and a
   configured-platform list that **contains** it.
6. Call it with the same history and a configured-platform list that **does
   not** contain it.
7. Run the loop with an explicit `--platform` list that **omits** a local
   reviewer the repository *does* configure, and read the condition's value.

**Expected result**: `not_required`, `head_changed`, `head_changed`,
`prior_findings`, `no_evidence`, `no_local_reviewer`; and case 7 returns
`no_evidence`, owing a pass.

Case 7 is where the list comes from, and it is the item's motivating scenario.
`pr-review-loop.sh` skips `workflow_config_review_platforms` entirely when
explicit `--platform` arguments are supplied, and the `platforms` array is
invocation-filtered — so handing that array to the condition would report
`no_local_reviewer` for a reviewer that **is** configured and merely omitted,
and the run would proceed without a pass. A fail-open produced by the argument
added to prevent one. The guard resolves the repository's configured list
independently of `--platform`. Proof P11.

Cases 5 and 6 differ **only** in the configured-platform list, and they must not
collapse. Case 5 is a configured reviewer that has not spoken — dispatchable, so
a pass is owed. Case 6 is a repository with no local reviewer at all: there is
nothing to dispatch, so the guard **proceeds** and reports
`no_local_reviewer` rather than owing a pass it could never discharge.

Proceeding there is deliberate. Refusing would block the ready-phase gate on
every pull request in every repository that has not adopted a local reviewer,
which no amount of retrying could clear. It is not a silent pass either: the
reason distinguishes *the gate was satisfied* from *there was nothing to satisfy
it with*, which is what lets #1657 exclude those repositories from a rate rather
than count them as clean. Proof P10.

Case 5 is the one a permissive reading gets wrong. A history that says nothing
about the local reviewer has not been locally reviewed, and `not_required` there
would let an invocation whose `--platform` list omits the reviewer walk straight
through the gate — the fail-open this epic exists to close. It is also not a
rare state: `filter_phase_after_clean_platforms` lets an invocation carry
ready-phase platforms and no local reviewer at all. Proof P2.

Cases 2 and 3 both owe a pass. An ancestor is the ordinary fix-was-pushed case;
an unrelated commit is a force-push. Neither is evidence about the commit the
ready-phase reviewers are about to read.

## Step 2: Six reasons, not a boolean

**Maps to**: the reporting contract.

1. Read `LOCAL_SECOND_PASS_REASON` on a run where the pass did not run.

**Expected result**: the key is present and reads `not_required`; and
`LOCAL_SECOND_PASS` is `0`.

`not_required` and `failed_for_head` are both "the pass did not run" and must
not be collapsed: one is a satisfied gate, the other a blocked one, and that is
the distinction #1657 needs most.

Emitting the reason only on the interesting path would make its absence
ambiguous — an old script, a skipped guard and a satisfied condition would all
look alike — and this is telemetry #1657 will read.

## Step 3: No extra dispatch when the evidence is current

**Maps to**: brief scope bullet 3, the cost half.

1. Run the loop on a pull request whose local reviewer is clean on
   `loop_head_sha`.
2. Compare the platform dispatch sequence to the same run before this change.

3. Compare the loop's `key=value` output to the same run before this change,
   **excluding** `LOCAL_SECOND_PASS` and `LOCAL_SECOND_PASS_REASON`, which this
   item adds on every run by design.

**Expected result**: the dispatch sequence is identical, and every `key=value`
line that existed before this change is byte-for-byte identical. The guard adds nothing to the path it does not need to
protect.

Two different things are being checked. The **dispatch** comparison depends on
the condition seeing the current round: by the time the guard runs, the local
reviewer has usually already reported in this cycle, and its verdict lives only
in memory — the ledger entry carrying it is written at the end of the cycle.
Reading the persisted payload alone makes every ordinary run owe a pass it does
not need. Proof P7.

The **output** comparison is about the extraction. The parsing, aggregation,
forwarding and ledger accumulation live inline in the platform loop after
`run_platform_review`, so the guard cannot reuse them without extracting them
into a shared function first. That extraction touches the busiest block in the
script, and this is the only check that it changed nothing. Proof P8.

## Step 4: A clean second pass opens the gate

**Maps to**: the brief's outcome.

1. Run the loop on a pull request whose local reviewer reported findings, then
   push a fix so `loop_head_sha` moves.
2. Let the loop reach the ready-phase gate.

**Expected result**: the local reviewer is dispatched **once** before
`ensure_pr_ready_for_ready_phase`; it reports clean; the pull request is
converted; ready-phase reviewers run. `LOCAL_SECOND_PASS=1`,
`LOCAL_SECOND_PASS_REASON=head_changed`.

Assert the pass appears in the **ledger entry** and the `key=value` output, not
only that the gate opened. A guard that calls `run_platform_review` and skips
the shared processor still decides the gate correctly and records nothing — the
telemetry would then say the gate opened with no evidence of what opened it.
Proof P8.

## Step 4a: A head that moves during the pass closes the gate

**Maps to**: the current-head guarantee.

1. Run the loop so the guard dispatches a pass, and push a commit **while the
   pass is running**.
2. Let the pass return clean.

3. Read the ledger entry for that round and the loop's cycle count.

**Expected result**: the gate does **not** open. The cycle ends with
`needs_fixes` and the loop's **existing** reason `head_moved_during_run`; no
ready-phase platform is dispatched; the round is **not counted** as a cycle and
no fixer is dispatched for it. `LOCAL_SECOND_PASS_REASON` carries the finer
`head_moved_during_pass`.

Reusing the established token is deliberate. `head_moved_during_run` already
carries two contracts — `reviewer_loop_history_entries_count` excludes entries
holding it from the qualifying set, and Protocol 91 treats it as nothing-to-fix
— and both are exactly right for a mid-pass move: the head moved, there is
nothing for a fixer to do, and the round did no review work. A newly minted
token inherits neither, so it would consume a cycle and send a fixer after
nothing. The distinction that matters for telemetry lives in this item's own
key. Proof P14.

Without the re-read, a clean verdict for the *old* commit opens the gate and
expensive reviewers read code the local reviewer never saw — the guarantee this
item exists to provide, broken on its own success path. Every scenario with a
stable head passes without it, which is all of the others.

The loop's existing end-of-run head-move check cannot substitute: it fires
*after* the dispatch it would need to prevent. Detecting the race requires
looking at the moment before the gate opens.

The re-read is the plan's only second head snapshot, and it classifies nothing —
its sole use is the equality test, and its sole outcome a refusal. The pass's
recorded evidence stays attributed to `loop_head_sha`, as #1648 requires.
Proof P13.

## Step 5: A failed second pass closes it, and changes nothing else

**Maps to**: the brief's outcome, the failure half.

1. Same as Step 4, but the second pass reports `needs_fixes`.
2. Repeat once per remaining non-clean result: `escalate`; `skipped` with
   reason `unavailable`; `skipped` with reason `not_configured`; `skipped` with
   any other reason; `needs_rerun`; and an unparseable result. Run these through
   the **real** shared processor, not a stub.

**Expected result**: for **every** case, three things, all asserted:

- the cycle ends with `needs_fixes`;
- the pull request is **not** converted to ready;
- **no** ready-phase platform is dispatched.

The `skipped` rows are the ones that invert. The shared processor treats a
skipped platform as **not blocking** — correct for an ordinary platform, and
wrong for this pass: the guard dispatched it *because* the gate needs evidence,
and a skipped pass produced none. Without the guard's override, a skipped pass
opens the ready-phase gate on a review that did not happen — the fail-open this
item exists to close, arriving through the machinery the guard borrows. Run them
through the real processor, because the inversion lives in what the processor
does with the result rather than in what the guard reads. Proof P15.

Asserting only the result would pass an implementation that converts the pull
request first and then reports the failure — leaving it ready, with no reviewer
dispatched, in a state the loop never intended and a human has to undo. Proof
P4.

## Step 6: At most once per head, and again when the head moves

**Maps to**: brief scope bullet 3, the loop half.

1. Run two cycles with **no** new commit between them and count local-reviewer
   dispatches.
2. Run a cycle, land a commit, run another cycle, and count again.

3. After a **failed** pass, run another cycle at the same head.
3a. After a **failed** pass ends the run, start a **new invocation** of the loop
   at the same head.
4. After a **clean** pass, run another cycle at the same head.

**Expected result**: case 1 dispatches the guard's pass **once**; case 2
dispatches it twice. Cases 3 and 3a both **refuse with `escalate`** — the run
ends with reason `failed_for_head`, no dispatch, no conversion. Case 4 takes
the `not_required` path: no dispatch, no refusal.

Case 3a is the hole an in-memory flag leaves, and it is the ordinary case rather
than an edge: the loop is re-invoked after every blocking result, which is what
a failed pass produces. A variable starts empty in the new invocation, the
verdict is still non-clean, and the guard dispatches again — one dispatch per
invocation forever. The failed head therefore lives in the **ledger**, the
loop's existing cross-invocation memory. Case 3 passes with a variable, so only
crossing an invocation separates the two. Proof P9.

Case 3 is the hole a two-way guard leaves. Suppressing the dispatch without
refusing means the condition still owes a pass, nothing runs, and the gate is
reached with no current clean evidence — a fail-open created by the anti-loop
mechanism itself, on the very next cycle after any failed pass. Case 1's
dispatch count passes either way, which is what makes it worth its own case.
Proof P6.

Case 4 needs no flag: the verdict a clean pass produced is clean on
`loop_head_sha`, so the condition returns `not_required` on its own. The flag
exists only for the failed case.

Count dispatches, not the flag. A per-cycle boolean reads as "at most once" and
is not: it allows one pass per cycle forever, and on a pull request whose local
reviewer never goes clean it burns the entire cycle budget on repeated local
reviews. Keying the flag on the head allows one pass per **commit**, and the
loop cannot manufacture a commit. Proof P1.

## Step 7: The caps mean what they meant

**Maps to**: brief scope bullet 3, the cap half.

1. Run two identical inputs, one needing a pass and one not, and compare
   `CYCLE_COUNT` and `TOTAL_CYCLE_COUNT`.
2. Run a pull request whose local reviewer never goes clean, **with the head
   moving each time**, to `max_cycles_exceeded`, and note the cycle count.
3. With the head **unchanged**, run a second invocation after a failed pass.

**Expected result**: case 1's counts are equal. Case 2 escalates at the same
count as before this change. Case 3 escalates immediately with
`failed_for_head`.

Case 3 is why the refusal is `escalate` and not `needs_fixes`. The lifetime cap
counts `unique` `head_sha|result` pairs, so repeated identical `needs_fixes`
entries at one head count **once**, and `CYCLE_COUNT` resets every invocation —
a refusal reported as `needs_fixes` would repeat forever with **both caps
standing still**, and the boundedness this item claims would be asserted and
untrue. `escalate` is terminal for the run, and it is the honest signal: nothing
changed since the last failure, so another automated attempt is one the loop
already knows is futile. Proof P12.

The pass is a dispatch inside a cycle that is already counted. Incrementing a
cap would make `max_cycles_exceeded` mean two different things — cycles for
platforms, cycles-plus-passes here — and would silently shorten every run the
guard helps. Proof P3.

## Step 8: No gate, no guard

**Maps to**: the cost of protecting nothing.

1. Run with no ready-phase platform configured — `phase_after_clean_enabled` at
   0 — and a condition that would otherwise owe a pass.

**Expected result**: no extra dispatch; the run is what it is today.

The pass exists to protect the ready-phase gate. With no gate, dispatching
anyway doubles the local reviewer's cost on every draft-only run for no benefit.
Proof P5.

## Step 9: The two keys, the ledger and the summary

**Maps to**: the reporting contract.

1. Read the loop's `key=value` stdout on a run where the pass ran and on one
   where it did not.
2. Read the reviewer-loop history entry for both.
3. Read the summary comment on the run where it ran.

**Expected result**: both keys present in both runs; both values in both ledger
entries; and a summary line naming the reason and the result — `second local
pass: head_changed → clean`.

## Step 9a: Composed with #1649 on the motivating case

**Maps to**: the cross-item contract.

1. Run an explicit `--platform` invocation that omits a local reviewer the
   repository configures, on a pull request whose local verdict is stale.
2. Let the guard dispatch the pass and produce a current-head clean result.
3. Observe whether `codex-github` is dispatched or refused.

**Expected result**: the pass runs, the evidence is current-head clean, and
`codex-github` is **not** refused.

This is the one case where two correct units disagree. #1649's check derives
`local_ai_configured` from the invocation-filtered `platforms[]`, which on this
run does not contain the local reviewer — so it would report
`local_reviewer_not_configured` and refuse, while the evidence it wants is
sitting in the ledger. Both must read the repository's configured list, through
the same helper this item adds.

Assert it end to end rather than on either item's unit tests: each is correct in
isolation, and the failure is only visible where they meet.

## Step 10: Documentation agrees

**Maps to**: the documentation-drift risk.

1. Read the guard's description in
   `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`.
2. Run `scripts/development-workflow/pr-review-loop.sh --help`.
3. Read `changelog.d/1656.changed.second-local-pass.md`.

**Expected result**: both surfaces describe the same **eight** reasons — the
five conditions plus `failed_for_head`, `head_moved_during_pass` and
`local_pass_unavailable` — and the same two keys, and neither describes the pass as consuming a cycle or as running
without a ready-phase platform. The fragment is `changed`, not `added` — the
ready-phase gate already existed and this alters when it fires.

## Step 11: Static checks

1. Run `shellcheck` on `scripts/development-workflow/pr-review-loop.sh`.
2. Run

   <!-- workflow-shell-contract: bash -->

   ```bash
   python3 scripts/lint/workflow-shell-guard-lint.py \
     --base-ref origin/develop-internal-reviewer-effectiveness
   ```

3. Run `markdownlint-cli2` on the changed documentation.

**Expected result**: all three exit 0.

## Step 12: Planted-violation proofs

1. Read the implementation PR's `Planted-Violation Proofs` heading.
2. Confirm P1 through P15 each record the command, the file and line of the
   planted violation, and both outcomes.

**Expected result**: fifteen proofs in three groups — **seven** fail-open,
**five** loop and cost, **three** integration, per the plan's proof-group
table.

P2 is the one to read twice: returning `not_required` for a history with no
local verdict is the natural default, it passes every scenario that supplies a
verdict, and the pull requests it lets through are exactly the ones nobody
reviewed locally.

---

## Rollback verification

Revert the implementation PR and re-run Steps 3 and 4. No extra dispatch may
occur in either, and neither key may appear in the loop's output.
