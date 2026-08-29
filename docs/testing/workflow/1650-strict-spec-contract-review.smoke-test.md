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

## Step 2: Ordinary findings are untouched

**Maps to**: the invisibility requirement.

1. Feed reviewer output with two ordinary blocking findings and no strict ones.
2. Compare the entire `key=value` output to the same input before this change,
   excluding `STRICT_SPEC_STATE`, `STRICT_SPEC_COUNT` and `STRICT_SPEC_CHECKS`.

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

| Case | `STRICT_SPEC_STATE` | `STRICT_SPEC_COUNT` | `STRICT_SPEC_CHECKS` |
| --- | --- | --- | --- |
| 1 | `applied` | `0` | empty list |
| 2 | `not_applicable` | **empty** | **empty** |
| 3 | `unavailable` | **empty** | **empty** |
| 4 | `unavailable` | **empty** | **empty** |

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

## Step 9: Documentation agrees

**Maps to**: the documentation-drift risk.

1. Read `docs/workflow/development-workflow/strict-spec-checks.md`.
2. Read the strict-check section of the integration document.
3. Read Protocol 93's reviewer-loop history section.
4. Run `scripts/development-workflow/local-ai-reviewer.sh --help`.
5. Read `changelog.d/1650.added.strict-spec-contract-review.md`.
6. Read `.github/workflows/markdown-lint.yml`'s `paths` filter.

**Expected result**: the checklist's identifiers match the spec's list exactly;
the three surfaces describe the same three keys and three states; none describes
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
2. Confirm P1 through P6 each record the command, the file and line of the
   planted violation, and both outcomes.

**Expected result**: six proofs in two groups — **three** blocking, **three**
measurement, per the plan's proof-group table.

P1 is the one to read first: without the partition the feature does not merely
fail, it turns every specification review red, and the resulting pressure is to
disable the checks rather than to fix the parser.

---

## Rollback verification

Revert the implementation PR and re-run Steps 1 and 2. A review whose findings
all carry `strict_check` markers must be classified as it was before the feature
existed — the markers ignored — and no `STRICT_*` key may appear.
