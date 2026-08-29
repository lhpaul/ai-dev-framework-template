# Smoke Test: Strict Spec Contract Review (#1650)

**Item**: [#1650](https://github.com/lhpaul/ai-dev-framework-template/issues/1650)
**Spec**: [1_1650-strict-spec-contract-review_specs.md](../../specs/developments/20260829021000_1650-strict-spec-contract-review/1_1650-strict-spec-contract-review_specs.md)
**Plan**: [2_1650-strict-spec-contract-review_implementation-plan.md](../../specs/developments/20260829021000_1650-strict-spec-contract-review/2_1650-strict-spec-contract-review_implementation-plan.md)

Steps 1 through 5 feed crafted reviewer output through the **real** `jq` program
in `local-ai-reviewer.sh`, not a stub: the partition is the thing under test, and
a stub would test the plan rather than the code.

---

## Step 1: A review with only strict findings is clean

**Maps to**: AC-3, and the spec's central claim.

1. Feed reviewer output whose `findings[]` are three findings, each carrying a
   `strict_check` identifier the checklist defines.
2. Read `RESULT`, `BLOCKING_COUNT`, `STRICT_SPEC_COUNT`, and the
   `BLOCKING_<n>_*` and `STRICT_<n>_*` blocks.

**Expected result**: `RESULT=clean`, `BLOCKING_COUNT=0`,
`STRICT_SPEC_COUNT=3`; three `STRICT_<n>_*` entries; **no** `BLOCKING_<n>_*`
entries.

This is the step the whole feature stands on, and the one an implementation is
most likely to fail. The parser's current invariant is *every finding is
blocking unless proven advisory* — `$unknown` is computed as neither-blocking-
nor-advisory and is emitted **as blocking**, forcing `needs_fixes`. Add eight
checks without partitioning first and every specification review turns red,
after which the pressure is to disable the checks rather than fix the parser.
Proof P1.

## Step 1a: The verdict comes from the ordinary review

**Maps to**: AC-3.

1. Feed output with `ordinary_result: "clean"`, `result: "needs_fixes"`, three
   known strict findings and no ordinary blocking ones.
2. Feed output with `ordinary_result: "needs_fixes"` and ordinary blocking
   findings.
3. Feed output with **no** `ordinary_result` and three strict findings — four
   times: `result` `needs_fixes` and `clean`, each with ordinary findings
   present and absent.
4. Feed output with no `ordinary_result` and **no** strict findings.

**Expected result**: case 1 emits `clean`, no flag. Case 2 emits `needs_fixes`.
All four of case 3 emit the verdict `result` already carried — unchanged — plus
`STRICT_SPEC_VERDICT_UNVERIFIED=1`. Nothing is inferred, nothing gates, nothing
escalates; the flag is the only difference from today's output. Case 4 uses
`result` exactly as today, with no flag.

The partition fixes the count and not the verdict: the parser's last branch
honours the reviewer's own `result`, so a reviewer that read the checks, found
three contradictions and concluded `needs_fixes` blocks with
`BLOCKING_COUNT=0` — strict findings changing the verdict, which AC-3 forbids.

**Three repairs were tried and withdrawn**, and this step is written to reject
all of them. Downgrading `needs_fixes` whenever no ordinary blocker was parsed
unblocks a reviewer that blocked for a reason it never wrote as a finding.
Deriving from the ordinary findings is that one again under another name.
Escalating the round introduces exactly the gate AC-18 forbids — "no label, no
gate, no escalation".

What is left is the baseline: with the strict checks switched off, `result` is
the verdict, so using `result` unchanged is the only fallback provably identical
to the counterfactual AC-3 measures against. The residue — a reviewer that folds
strict findings into `result` and omits `ordinary_result` — is not detectable
from the response, so it is measured by the flag and counted by #1657 rather
than guessed at here.

Case 3's four runs are one case, deliberately: the emitted verdict must equal
`result` whatever `result` said and whatever findings were present, and testing
only the `needs_fixes` shape would leave an implementation free to infer in the
other three.

Case 2 matters as much as case 1 — `ordinary_result` is used in both
directions, not only to unblock. Case 4 is what scenario 5's byte-identical
requirement rests on: a reviewer emitting no strict findings behaves exactly as
before, flag included, because with no strict findings there is nothing that
could have influenced the verdict. Proofs P8 and P9.

What the four runs of case 3 do **not** assert is that the verdict was
uninfluenced — only that this parser did not influence it. A reviewer that folds
strict findings into `result` and omits `ordinary_result` is indistinguishable
here from a legitimate `needs_fixes`, which is why the flag exists and why
#1657 counts its rate rather than this test asserting it away.

## Step 2: Ordinary findings are untouched

**Maps to**: the invisibility requirement.

1. Feed reviewer output with two ordinary blocking findings and no strict ones.
2. Compare the entire `key=value` output to the same input before this change,
   excluding the four `STRICT_SPEC_*` keys this item may emit here:
   `STRICT_SPEC_STATE`, `STRICT_SPEC_COUNT`, `STRICT_SPEC_REASON` and
   `STRICT_SPEC_CHECKS`.
   `STRICT_SPEC_VERDICT_UNVERIFIED` is **not** excluded: it requires a strict
   finding, so its absence here is part of what the comparison asserts.

**Expected result**: byte-identical.

The partition binds `$findings` to the ordinary subset and leaves every
downstream computation textually unchanged — that is the whole design. This step
is what catches an implementation that rebuilds or re-sorts the blocking lines
while partitioning: a renumbered index or a changed order is invisible to every
other step here. Proof P4.

## Step 3: A mixed review is decided by the ordinary findings

**Maps to**: AC-3.

1. Feed output with two ordinary blocking findings and three strict ones.

**Expected result**: `BLOCKING_COUNT=2`, `STRICT_SPEC_COUNT=3`,
`RESULT=needs_fixes` — driven by the two, not the three. Two `BLOCKING_<n>_*`
entries and three `STRICT_<n>_*` entries, with no overlap.

Check the two blocks do not share a finding. A strict finding appearing in
`BLOCKING_<n>_*` as well as its own block is forwarded by the loop as a blocker
whatever `BLOCKING_COUNT` says — the non-blocking guarantee would hold in the
reviewer and break one layer up. Proof P3.

## Step 4: An unknown marker is not a strict finding

**Maps to**: the fail-closed direction.

1. Feed a finding carrying `strict_check: "not_a_real_check"`.
2. Feed a finding carrying `strict_check: 7`, then `strict_check: {}`, then
   `strict_check: null`.

**Expected result**: none is strict. Each is classified as an ordinary finding
— which, being unrecognised, means blocking — and `RESULT=needs_fixes`.

This is the direction that matters. If the marker alone were trusted, it would
become a way to opt out of blocking: a reviewer that mislabels, or a later
prompt that over-applies the field, silently downgrades real findings and
nothing in the output shows it. Fail-closed means an unknown marker costs a
false blocker, which is visible and arguable, rather than a missed one, which is
neither. Proof P2.

## Step 5: The identifier set comes from the checklist

**Maps to**: the closed-set rule.

1. Add a ninth section to a fixture checklist, with a new identifier.
2. Feed a finding carrying that identifier.

**Expected result**: it is strict, with no change to the parser or the tests.

The eight shipped checks pass whether the set is read from the document or
hard-coded in the parser, which is why this step adds a ninth. Two definitions
of a closed set is one definition that will drift. Proof P6.

## Step 6: The state, the count, and what is empty

**Maps to**: AC-15, AC-17, AC-17a.

1. Run at the spec stage with a readable checklist and no findings.
2. Run at a non-spec stage.
3. Run at the spec stage with the checklist unreadable.
4. Run where the stage cannot be resolved.
5. Read the ledger entry for each.

**Expected result**:

| Case | `STRICT_SPEC_STATE` | `STRICT_SPEC_REASON` | `STRICT_SPEC_COUNT` | `STRICT_SPEC_CHECKS` |
| --- | --- | --- | --- | --- |
| 1 | `applied` | **empty** | `0` | empty list |
| 2 | `not_applicable` | **empty** | **empty** | **empty** |
| 3 | `unavailable` | `checklist_unreadable` | **empty** | **empty** |
| 4 | `unavailable` | `stage_unresolved` | **empty** | **empty** |

Cases 3 and 4 share a state and must not share a record. The two causes have
different owners — a missing checklist is the repository's, an unresolvable
stage is the pull request's — and a reader given only `unavailable` cannot tell
which to go and fix. The more likely of the two is also the more fixable.
Proof P7.

Case 1 against cases 3 and 4 is the assertion that matters: `0` means the checks
ran and found nothing, and it is the only thing distinguishing a clean
specification from one they never examined. A `0` written for `unavailable`
would put unexamined rounds into #1657's denominator and make the rate wrong in
the flattering direction — the direction nobody questions. Proof P5.

Read the ledger too, not only stdout: the per-round record is what a later
report reads, and the distinction has to survive into it.

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
the three surfaces describe the same five keys, three states, two `unavailable`
reasons, the `ordinary_result` contract with its `result` fallback, and the
unverified flag's two conditions; none describes
a strict finding as blocking or as affecting the verdict; and the `paths` filter
lists the checklist, so a checklist-only change is still linted.

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

P1 is the one to read first: without the partition the feature does not merely
fail, it turns every specification review red, and the resulting pressure is to
disable the checks rather than to fix the parser.

---

## Rollback verification

Revert the implementation PR and re-run Steps 1 and 2. A review whose findings
all carry `strict_check` markers must be classified as it was before the feature
existed — the markers ignored — and no `STRICT_*` key may appear.
