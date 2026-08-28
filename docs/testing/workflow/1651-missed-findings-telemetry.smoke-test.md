# Smoke Test: Missed-Finding Telemetry (#1651)

**Item**: [#1651](https://github.com/lhpaul/ai-dev-framework-template/issues/1651)
**Spec**: [1_1651-missed-findings-telemetry_specs.md](../../specs/developments/20260828014500_1651-missed-findings-telemetry/1_1651-missed-findings-telemetry_specs.md)
**Plan**: [2_1651-missed-findings-telemetry_implementation-plan.md](../../specs/developments/20260828014500_1651-missed-findings-telemetry/2_1651-missed-findings-telemetry_implementation-plan.md)

Steps 1 through 5 source the loop with `HARNESS_MODE=1` and call the derivation
directly; Steps 6 onward exercise the assembled behavior.

<!-- workflow-shell-contract: bash -->

```bash
HARNESS_MODE=1 source scripts/development-workflow/pr-review-loop.sh
```

Sourcing enables `set -euo pipefail` in this shell. Two of the functions below
return non-zero as a normal answer; call them inside an `if` or suffix with
`|| true`.

---

## Step 1: The most recent verdict wins, not the most recent clean one

**Maps to**: AC-4a.

1. Build a history payload with the local reviewer clean at iteration 2 and
   reporting findings at iteration 5.
2. Call `reviewer_loop_local_latest_verdict` with it.

**Expected result**: the iteration-5 verdict, outcome `needs_fixes`. The final
state is `not_clean`, and the round is neither a confirmed nor a possible miss.

This is the item's most likely implementation error and the reason the function
is named for recency. "The most recent clean verdict" is the same sentence with
the search order and the filter swapped, and it reads as the more helpful one —
it finds evidence where recency finds none. What it actually does is count a
round as missed on a verdict the reviewer itself had already superseded. Proof
P1.

## Step 2: "Has not run yet" and "will never run" stay apart

**Maps to**: AC-6.

1. Call the selector with a payload where the local reviewer appears in no
   entry and **is** in the configured platform list.
2. Call it with a payload where it is absent from the configured list.

**Expected result**: `not_yet_run` and `not_configured`, asserted as those two
values — not merely as two non-clean results.

A pull request early in its life and a repository that will never produce local
evidence are different facts about different repositories. Summed, they make a
report unable to tell a young pull request from an unconfigured project. Proof
P4.

## Step 3: A healthy but silent history is `unknown`

**Maps to**: AC-7.

1. Call the selector with entries that exist but establish no outcome for the
   local reviewer.

**Expected result**: `unknown`, a record still written, neither a confirmed nor
a possible miss.

`unknown` here is not a failure — the history is readable and simply does not
say. That is why it belongs in the denominator rather than being dropped.

## Step 4: Ancestry answers four ways on a healthy repository

**Maps to**: AC-1 through AC-4.

1. Build a temporary repository: a root commit, branch A of two commits, and
   branch B of two commits from the same root.
2. Call `reviewer_loop_commit_ancestry` for a commit against itself, against a
   descendant, against an ancestor, and across the two branches.

**Expected result**: `same`, `ancestor`, `descendant`, `unrelated`.

## Step 5: Ancestry that cannot be computed is `undecidable`, never `unrelated`

**Maps to**: the `unknown` mapping, and the guard the whole feature's honesty
rests on.

1. Call the function with a commit SHA that does not exist in the repository.
2. Call it in a repository state where `git merge-base --is-ancestor` exits with
   something other than 0 or 1.
3. Call it with an empty commit argument.

**Expected result**: `undecidable` in all three, mapping to local evidence state
`unknown`.

**Asserted as `undecidable` specifically.** `git merge-base --is-ancestor` exits
0 for yes, 1 for no, and something else for an error. Folding "not 0" into "no"
returns `unrelated` — a *decided* answer meaning a force-push severed the
relationship — for a question the repository could not answer at all. The record
would assert something that was never established, and the number built on it
would be wrong in a way no reader could see.

Step 4 passes with the fold in place. That asymmetry is why this step exists and
why its fixture deliberately deletes an object. Proof P3.

## Step 6: Every state is reachable

**Maps to**: AC-1 through AC-7.

1. Call `reviewer_loop_local_evidence_state` once per row of the plan's
   eleven-row mapping table.

**Expected result**: the ten spec states, with `unknown` reached twice — once
from an undecidable ancestry and once from an unrecognised outcome.

## Step 7: What creates a record, and what does not

**Maps to**: AC-5, AC-8, AC-9, AC-10.

1. Run a round whose blocking findings came from the **local** reviewer.
2. Run a round whose external findings are advisory only.
3. Run a round with external blocking findings whose local evidence state is
   `not_clean`.
4. Run two qualifying rounds with identical reviewer, commit and finding count.

**Expected result**: no record for 1 or 2; a record for 3; **two** records for
4, neither replacing the other.

Case 3 is the denominator, and it is the one an implementation drops first: a
record that is not a miss looks like noise. Without it the reported rate is
always 100%, because the numerator is the only thing counted. Proof P2.

Case 4 asserts that no de-duplication occurs even on identical records — the
loop genuinely ran twice, and two rounds finding the same thing is a real
observation about the reviewer, not a duplicate row.

## Step 8: An unwritable history reports only what was owed

**Maps to**: AC-7a, AC-7b.

1. With the history unwritable (`append_safe` at 0) and an external round
   reporting blocking findings on an establishable commit: run it.
2. With the history unwritable and **no** record owed — findings from the local
   reviewer, or advisory only: run it.

**Expected result**: case 1 writes no record, leaves the existing payload
byte-for-byte unchanged, and states in its output that telemetry could not be
recorded and why, naming the reason the loop already computed
(`malformed_history`, `unknown_schema`, or `prior_unavailable`). Case 2 produces
**no** telemetry-failure report.

Case 2 fails whenever the two tests are ordered the other way, and that ordering
is the natural one: writability is a property of the loop and eligibility a
property of the round, so a programmer checks the cheap global first. It then
reports a failure nobody was waiting for, on rounds this feature had nothing to
do with. Proof P5.

## Step 9: The summary line and its bound

**Maps to**: AC-13, AC-14, AC-14a, AC-15.

1. Render a record with three short paths.
2. Render a record whose three paths each exceed 60 characters.
3. Render an entry carrying twenty records with long paths.

**Expected result**: one line per record, each at most 200 characters, naming at
most three paths and **always** the total file count. Case 2 names **zero**
paths and still states the total, the state and the classification — a valid
line, not a failure. Case 3 adds at most twenty lines and 4,000 characters.

The bound is enforced by build order, not by truncation: the total and the state
are written before the paths, and paths stop at the first one that would exceed
the bound. Truncating a finished line removes the tail, which is where the state
and the classification live — leaving the reader a line of file names and no
verdict, exactly inverted from what it is for. Proof P6.

## Step 10: The ledger keeps its contract

**Maps to**: the additive-schema decision.

1. Read a history entry produced by the implementation.
2. Assert each of the eighteen existing fields by name and type, and the
   `phase_after_clean` object with its five keys.
3. Assert `missed_findings` is present and is an array.
4. Assert `schema` still reads `reviewer_loop_history.v1`.

**Expected result**: all present and unchanged; exactly one field added; the
schema string unchanged.

Asserted field by field rather than by counting, so an accidental rename cannot
be masked by an accidental addition. The schema string is deliberately not
bumped: the change is additive, and a bump would break a reader that validates
the string exactly while a new key it ignores would not.

## Step 11: Records carry their own classification

**Maps to**: AC-16, AC-17, AC-17a.

1. Read the records for a pull request that has one `clean_same_commit`, one
   `clean_earlier_commit` and three other states.
2. Produce the confirmed-miss count and the possible-miss count from the records
   alone.

**Expected result**: one confirmed, one possible, five records total. Neither
count folds into the other, and no reader-side mapping from state to
classification is needed.

`classification` is stored rather than re-derived because AC-17a requires a
later report to separate the counts, and a reader that re-derives it keeps a
second copy of the confirmed/possible rule. Two copies of a rule is one that
drifts.

## Step 12: The feature observes and nothing else

**Maps to**: AC-12.

1. Run a pull request to readiness with missed-finding records present.
2. Run the same pull request with the feature disabled.

**Expected result**: identical review outcome, readiness label and tracker
status. The records change what is *known*, never what happens.

## Step 13: Static checks

1. Run `shellcheck` on `scripts/development-workflow/pr-review-loop.sh`.
2. Run

   <!-- workflow-shell-contract: bash -->

   ```bash
   python3 scripts/lint/workflow-shell-guard-lint.py \
     --base-ref origin/develop-internal-reviewer-effectiveness
   ```

3. Run `markdownlint-cli2` on the changed documentation.

**Expected result**: all three exit 0.

## Step 14: Planted-violation proofs

1. Read the implementation PR's `Planted-Violation Proofs` heading.
2. Confirm P1 through P6 each record the command, the file and line of the
   planted violation, and both outcomes.

**Expected result**: six proofs in two groups — **four** overclaiming, **two**
contract, per the plan's proof-group table.

The overclaiming group carries the weight because that direction has no symptom:
each of its plants produces a plausible number, and a number is believed. P3 is
the one to read twice — its plant passes every test written against a healthy
repository.

---

## Rollback verification

Revert the implementation PR and re-run Steps 1 and 10. The derivation functions
must be absent, and a freshly written history entry must carry no
`missed_findings` key.
