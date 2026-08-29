# Smoke Test: Strict Spec Contract Review (#1650)

**Item**: [#1650](https://github.com/lhpaul/ai-dev-framework-template/issues/1650)
**Spec**: [1_1650-strict-spec-contract-review_specs.md](../../specs/developments/20260829021000_1650-strict-spec-contract-review/1_1650-strict-spec-contract-review_specs.md)
**Plan**: [2_1650-strict-spec-contract-review_implementation-plan.md](../../specs/developments/20260829021000_1650-strict-spec-contract-review/2_1650-strict-spec-contract-review_implementation-plan.md)

Steps 1 through 5 feed crafted reviewer output through the **real** `jq`
programs in `local-ai-reviewer.sh`, not stubs: the two passes and the merge
between them are the thing under test, and a stub would test the plan rather
than the code. Where a step counts invocations, `LOCAL_AI_REVIEWER_COMMAND` is
pointed at a recording script that returns the crafted output.

---

## Step 1: A review with only strict findings is clean

**Maps to**: AC-3, and the spec's central claim.

1. Run a spec-stage review whose **ordinary** pass returns no findings and whose
   **strict** pass returns three findings, each carrying a `check` identifier
   the checklist defines.
2. Read `RESULT`, `BLOCKING_COUNT`, `STRICT_SPEC_COUNT`, and the
   `BLOCKING_<n>_*` and `STRICT_<n>_*` blocks.

**Expected result**: `RESULT=clean`, `BLOCKING_COUNT=0`,
`STRICT_SPEC_COUNT=3`; three `STRICT_<n>_*` entries; **no** `BLOCKING_<n>_*`
entries.

This is the step the whole feature stands on. The parser's existing invariant is
*every finding is blocking unless proven advisory* — `$unknown` is computed as
neither-blocking-nor-advisory and is emitted **as blocking**, forcing
`needs_fixes`. Merge the strict pass's findings into that array and every
specification review turns red, after which the pressure is to disable the
checks rather than fix the merge. Proof P1.

## Step 1a: The verdict comes from a review that never saw the checks

**Maps to**: AC-3, AC-16a.

1. Run a spec-stage review with the checklist present, ordinary pass clean,
   strict pass returning three findings. Record the full `key=value` output.
2. Run the **same** review with the checklist removed, so no strict pass is
   dispatched. Record the output.
3. Run the same review with the strict pass returning its own
   `result: "needs_fixes"`, and again with `result: "clean"`, the ordinary pass
   held fixed in both.
4. Run the same review three more times with the strict pass failing: non-zero
   exit, empty response, unparseable output.

**Expected result**: in step 2 the verdict, the blocking block, its order and
its numbering are **identical** to step 1 — only the `STRICT_SPEC_*` keys and
the `STRICT_<n>_*` block differ. In step 3 `RESULT` is identical across both
runs and equals the ordinary pass's verdict. In step 4 all three runs emit
`STRICT_SPEC_STATE=unavailable` with `STRICT_SPEC_REASON=strict_pass_failed`,
and their ordinary output matches step 2's.

**Step 2 is AC-3's own wording executed.** The criterion asks that a review with
strict findings report the same verdict as *the same review with the strict
checks disabled*, and with two passes that second review is a thing you can
actually run — it is the ordinary pass alone. No inference, no flag, no
comparison of fields within one response.

**Four repairs were tried and withdrawn before this**, all of them attempts to
reach AC-3 from a single invocation that saw both. Downgrading `needs_fixes`
when no ordinary blocker was parsed unblocks a reviewer that blocked for a
reason it never wrote as a finding. Deriving the verdict from the ordinary
findings is that move renamed. Escalating when the ordinary verdict was
unavailable introduces exactly the gate AC-18 forbids — "no label, no gate, no
escalation". Asking for a separate `ordinary_result` field and forwarding
`result` when it was missing left the verdict influenceable and called the
residue measurement.

They failed for one reason: a single invocation can only promise that what it
read did not affect what it concluded, and no parser can audit that promise —
the information is not in the response. Two invocations do not need the promise,
which is why this step can assert equality instead of reasoning about it.

Step 3 checks the other half: the strict response's own verdict field is never
read, so a reviewer that volunteers one cannot block by accident. Step 4 checks
that a failure in the checks costs the review nothing. Proofs P4, P8 and P9.

## Step 2: Ordinary findings are untouched

**Maps to**: the invisibility requirement.

1. Run a **non-spec-stage** review whose ordinary pass returns two blocking
   findings.
2. Compare the entire `key=value` output to the same input before this change,
   excluding the two keys this item always emits — `STRICT_SPEC_STATE` and
   `STRICT_SPEC_COUNT`. The three conditional keys are **not** excluded: none
   may appear here, and their absence is part of what the comparison asserts.
3. Count the invocations of `LOCAL_AI_REVIEWER_COMMAND`.

**Expected result**: byte-identical, and **one** invocation.

The ordinary pass is not edited at all — same prompt, same bundle content, same
`jq` program — so byte-identical output is the expected result rather than a
requirement the implementation has to work to meet. What this step actually
catches is the two failures that would not show anywhere else: an implementation
that rebuilds or renumbers the blocking lines while merging, and one that
dispatches the strict pass on a stage that should never see it, doubling the
cost of every plan and implementation review with nothing in the output to say
so. Proofs P4 and P8.

## Step 3: A mixed review is decided by the ordinary findings

**Maps to**: AC-3.

1. Run a review whose ordinary pass returns two blocking findings and whose
   strict pass returns three.

**Expected result**: `BLOCKING_COUNT=2`, `STRICT_SPEC_COUNT=3`,
`RESULT=needs_fixes` — driven by the two, not the three. Two `BLOCKING_<n>_*`
entries and three `STRICT_<n>_*` entries, with no overlap.

Check the two blocks do not share a finding. A strict finding appearing in
`BLOCKING_<n>_*` as well as its own block is forwarded by the loop as a blocker
whatever `BLOCKING_COUNT` says — the non-blocking guarantee would hold in the
reviewer and break one layer up. The two blocks are built from two different
responses, so this can only fail by an implementation that deliberately joins
them. Proof P3.

## Step 4: An unrecognised identifier is counted, not discarded and not blocking

**Maps to**: AC-2, AC-3.

1. Run a review whose strict pass returns a finding carrying
   `check: "not_a_real_check"`.
2. Repeat with `check: 7`, then `check: {}`, then `check: null`, then a finding
   with no `check` key at all.
2b. Then two responses that never claim the mode: one missing
   `mode: "strict_spec_checks"`, and one that is a complete **ordinary** review
   — `result` plus findings carrying `severity` and no `check`. Both are
   `strict_pass_failed`.

   The second is the realistic one. `LOCAL_AI_REVIEWER_COMMAND` is configurable,
   and a custom command that ignores `LOCAL_AI_REVIEWER_MODE` answers the strict
   call with its ordinary review. Every finding in it lacks a `check`, so
   without the mode marker all of them count as unknown and the pass reports
   `applied` with a large `unknown_count` — **an ordinary review recorded as a
   completed run of the strict checks**, and fabricated incidence in #1657's
   data. A silent contract needs a positive acknowledgement; this is it.

2a. Then four malformed responses: `{}` with no findings key at all,
   `{"findings": null}`, an object value, and a string value. All four are
   `strict_pass_failed`, **not** counts. Run `{"findings": []}` immediately
   after: it must be `applied` with count `0`.

   **The `{}` and `{"findings": []}` pair is the assertion that matters most in
   this runbook.** They differ by four characters. One is a pass that produced
   nothing — a reviewer that printed no usable JSON — and the other is a pass
   that examined a specification and found nothing wrong with it. Writing the
   parser as `.findings // .comments // .issues // []` collapses them, records
   the first as `applied` with count `0`, and feeds silence into #1657 as a
   zero. The object case is the quietest of the four: its property values are
   walked as findings, so a malformed response is recorded as a completed run
   with a large `unknown_count`.

**Expected result**: each is reported with `STRICT_<n>_CHECK=unknown`, counted
in `STRICT_SPEC_UNKNOWN_COUNT`, excluded from `STRICT_SPEC_COUNT` and
`STRICT_SPEC_CHECKS`, and **not** blocking: `RESULT` is the ordinary pass's
verdict in every run, and the parser does not abort on any of the four
non-string shapes.

**The fail-closed direction reverses with two passes, and this step is where the
reversal is asserted.** In a single-invocation design an unrecognised marker had
to be treated as blocking, because the marker was a way to opt out of blocking.
Here a strict-pass finding was never in the blocking set, so promoting it would
*add* a blocker the ordinary review never raised — AC-3 broken in the other
direction. Both failures are checked: it must not become blocking, and it must
not vanish either, which is what `STRICT_SPEC_UNKNOWN_COUNT` exists to make
impossible. Proof P2.

The exclusion from `STRICT_SPEC_COUNT` follows from what the count is for: it
feeds #1657's per-check incidence, and a finding naming no known check belongs
to no check's rate.

## Step 5: The identifier set comes from the checklist

**Maps to**: the closed-set rule.

1. Add a ninth section to a fixture checklist, with a new identifier.
2. Feed a finding carrying that identifier.

**Expected result**: it is strict, with no change to the parser or the tests.

The eight shipped checks pass whether the set is read from the document or
hard-coded in the parser, which is why this step adds a ninth. Two definitions
of a closed set is one definition that will drift. Proof P6.

Then the refusals, run as three more cases against fixture checklists:

3. A checklist containing `### Ambiguous Phrase` — a level-3 heading the
   identifier pattern does not match.
4. A checklist declaring the same identifier twice.
5. A checklist with no level-3 headings, and an empty file.

**Expected result**: every one yields `STRICT_SPEC_STATE=unavailable` with
`STRICT_SPEC_REASON=checklist_unreadable`, no `STRICT_SPEC_COUNT` value, and no
strict pass dispatched.

**Case 3 is the one to check hardest.** The tempting behaviour is to carry on
with the seven identifiers that did parse — the reviewer is then handed seven
checks, reports against seven, and the count reads as a completed run of a
checklist that has eight. That is a review that looks like it happened,
reproduced inside the mechanism built to detect exactly that, and it is why the
extractor compares its result against the document's level-3 heading count
instead of trusting what it managed to match.

## Step 6: The state, the count, and what is empty

**Maps to**: AC-15, AC-17, AC-17a.

1. Run at the spec stage with a readable checklist and no findings.
2. Run at a non-spec stage.
3. Run at the spec stage with the checklist unreadable.
4. Run where the stage cannot be resolved.
5. Run at the spec stage with a readable checklist and a strict pass that fails.
6. Read the ledger entry for each.

**Expected result**:

| Case | `STRICT_SPEC_STATE` | `STRICT_SPEC_REASON` | `STRICT_SPEC_COUNT` | `STRICT_SPEC_CHECKS` |
| --- | --- | --- | --- | --- |
| 1 | `applied` | **empty** | `0` | empty list |
| 2 | `not_applicable` | **empty** | **empty** | **empty** |
| 3 | `unavailable` | `checklist_unreadable` | **empty** | **empty** |
| 4 | `unavailable` | `stage_unresolved` | **empty** | **empty** |
| 5 | `unavailable` | `strict_pass_failed` | **empty** | **empty** |

Cases 3, 4 and 5 share a state and must not share a record. The three causes
have three owners — a missing checklist is the repository's, an unresolvable
stage is the pull request's, a failed pass is the reviewer command's or its
environment's — and a reader given only `unavailable` cannot tell which to go
and see. Proof P7.

Case 5 is the row the specification originally lacked: its matrix enumerated the
three inputs that decide whether the checks *start* and not the one that decides
whether they *finish*. That is the `gate_matrix` shape check 3 exists to catch,
found in the document defining check 3. It is fixed by a **separate spec pull
request**, which this plan depends on — a plan pull request that edits its own
approved spec is a workflow-stage violation, so the gap goes back through the
spec stage rather than riding along with the plan.

Case 1 against cases 3 and 4 is the assertion that matters: `0` means the checks
ran and found nothing, and it is the only thing distinguishing a clean
specification from one they never examined. A `0` written for `unavailable`
would put unexamined rounds into #1657's denominator and make the rate wrong in
the flattering direction — the direction nobody questions. Proof P5.

Read the ledger too, not only stdout: the per-round record is what a later
report reads, and the distinction has to survive into it. The `strict_spec`
object mirrors the output — a key emitted is a field present, a key not emitted
is a field **absent** rather than null — with one exception, `count`, which is
always present and `null` outside `applied`. Check the absences with `has()`,
not by comparing values: `count` must be readable on every round so a consumer
can tell `0` from "did not run" without also reading the state, while a `reason`
present and null on an `applied` round is a field inviting interpretation it has
no meaning for.

## Step 7: The summary shows strict findings separately

**Maps to**: the spec's outcome table.

1. Run a review producing three strict findings and no blocking ones.
2. Read the reviewer-loop summary comment.

**Expected result**: one grouped section for strict findings, each line naming
its check, distinct from the blocking-findings area. The section is absent when
the state is not `applied`, and absent when the count is zero.

The spec's outcome table touches the comment surface in exactly one row. A
reader seeing no strict section cannot tell the other four rows apart from
comments alone, which is why the state is in the reviewer output and the ledger
on every review.

## Step 8: Distinct checks, not one entry per finding

**Maps to**: the per-pull-request incidence rule.

1. Feed three findings drawn from a pair of checks.

**Expected result**: `STRICT_SPEC_CHECKS` names that pair.

Incidence is counted per pull request per check; a key listing an identifier
once per finding would make a check that fires three times on one specification
look like three specifications.

## Step 8a: The checks fire on planted violations

**Maps to**: AC-4 through AC-13.

1. Run the reviewer, checklist supplied, against each of the **eleven** fixture
   specifications: **eight** positives, one per check, each with a single
   planted instance of that check's shape; and **three** negatives, one per
   acceptance criterion that requires no finding — a gate enumerating every
   reachable combination (AC-7); a gate that short-circuits and **states its
   evaluation order** (AC-6a); and an unsettled phrase confined to a rationale
   (AC-13).
2. Record which check fired on each.
3. Repeat all eleven with the checklist **absent**, and record again.

**Expected result**: with the checklist, each of the eight positives produces a
finding from its own check, and **none** of the three negatives produces one.
Without it, the state is `unavailable` and no strict finding appears.

The AC-6a negative is the one easiest to leave out and the most informative:
a gate that short-circuits *and says so* must produce no `gate_matrix` finding,
while the same gate without its stated order must produce one. It is the pair
that distinguishes the check from one that simply demands every Boolean
combination — which would fire on most correctly-written gates, including this
epic's own.

**This step is recorded, not gated**, and the reason is the same one that makes
the findings non-blocking: whether a model notices a planted contradiction is
not deterministic. A step that failed the build when one check missed its own
fixture would be red for reasons no implementer could fix, and the fix would be
to delete the step.

The **second** run is what gives the first its meaning. A check firing on its
planted violation shows the reviewer is capable; a check firing *only* when the
checklist is supplied shows this feature caused it. Without the contrast the
step proves the model is good at reading, not that the checks do anything.

A check that fires in neither run is a finding about that check — worth having
before its counts start accumulating, and exactly the kind of thing #1657's
report would otherwise take months to surface.

## Step 8b: One check, two rounds, counted once

**Maps to**: AC-17c.

1. Run two review rounds on the same pull request, both producing a finding from
   the same check — the second because the first was not acted on, which AC-18
   requires to be re-reported.
2. Read both ledger entries and compute the per-check incidence for the pull
   request.

**Expected result**: two rounds, each recording that identifier; the pull
request counts that check **once**.

Deduplication *within* a round is Step 8. This is deduplication *across* rounds,
and it is the one that matters for the measurement: a finding nobody acts on is
re-reported every round by design, so summing rounds would make a check look
more frequent the longer its specification took to merge. The identifiers are
unioned across rounds, never added.

## Step 9: Documentation agrees

**Maps to**: the documentation-drift risk.

1. Read `docs/workflow/development-workflow/strict-spec-checks.md`.
2. Read the strict-check section of the integration document.
3. Read Protocol 93's reviewer-loop history section.
4. Run `scripts/development-workflow/local-ai-reviewer.sh --help`.
5. Read `changelog.d/1650.added.strict-spec-contract-review.md`.
6. Read `.github/workflows/markdown-lint.yml`'s `paths` filter.

**Expected result**: the checklist's identifiers match the spec's list exactly;
the three surfaces describe the same five keys, three states, three
`unavailable` reasons, the two-pass structure and what each pass may affect, and
the unknown-identifier classification; none describes a strict finding as
blocking or as affecting the verdict; and the `paths` filter lists the
checklist, so a checklist-only change is still linted.

## Step 10: Static checks

1. Run `shellcheck` on `scripts/development-workflow/local-ai-reviewer.sh`.
2. Run

   <!-- workflow-shell-contract: bash -->

   ```bash
   python3 scripts/lint/workflow-shell-guard-lint.py \
     --base-ref origin/develop-internal-reviewer-effectiveness
   ```

3. Run `markdownlint-cli2` **and** `markdown-heuristic-lint.py` on the changed
   documentation. Both: the second is CI-only, so a document can pass every
   reviewer and fail the build.

**Expected result**: all exit 0.

## Step 11: Planted-violation proofs

1. Read the implementation PR's `Planted-Violation Proofs` heading.
2. Confirm P1 through P9 each record the command, the file and line of the
   planted violation, and both outcomes.

**Expected result**: nine proofs in two groups — **five** blocking, **four**
measurement, per the plan's proof-group table.

P1 is the one to read first: with the two responses merged the feature does not
merely fail, it turns every specification review red, and the resulting pressure
is to disable the checks rather than to fix the merge.

---

## Rollback verification

Revert the implementation PR and re-run Steps 1 and 2. A spec-stage review must
return to a single invocation, with no `STRICT_*` key in its output. The
ordinary pass needs no verification beyond that, because reverting cannot
regress it: nothing in it was changed.
