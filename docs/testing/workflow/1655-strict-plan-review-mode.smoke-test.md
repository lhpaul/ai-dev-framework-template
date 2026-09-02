# Smoke Test: Strict Implementation-Plan Review (#1655)

**Item**: [#1655](https://github.com/lhpaul/ai-dev-framework-template/issues/1655)
**Spec**: [1_1655-strict-plan-review-mode_specs.md](../../specs/developments/20260831062000_1655-strict-plan-review-mode/1_1655-strict-plan-review-mode_specs.md)
**Plan**: [2_1655-strict-plan-review-mode_implementation-plan.md](../../specs/developments/20260831062000_1655-strict-plan-review-mode/2_1655-strict-plan-review-mode_implementation-plan.md)

Steps 1 through 7 feed crafted reviewer output through the **real** `jq`
programs and the **real** supply step in `local-ai-reviewer.sh`, not stubs. The
supply is as much the thing under test as the parser: a plan read from the wrong
revision produces findings that are internally consistent and wrong. Where a
step counts invocations, `LOCAL_AI_REVIEWER_COMMAND` is a recording script.

Steps 8 and 9 need a real model.

---

## Step 1: The documents come from the reviewed head

**Maps to**: AC-12, AC-12a, AC-12b.

1. Build a temporary repository. Commit a plan document. Then rewrite the
   working-tree copy with visibly different text, leaving the commit alone.
2. Run a plan-stage review against the committed revision and capture the
   bundle the strict pass receives.
3. Repeat with the plan document **empty** at the committed revision.
4. Repeat with the listed path absent from the committed revision, so
   `git show` fails.

**Expected result**: in step 2 the supplied `text` is the **committed** text,
not the working tree's. In step 3 the state is `applied` — an empty document is
examined and reported through findings, not through a state. In step 4 the state
is `unavailable` with `STRICT_PLAN_REASON=strict_pass_failed`, and the
invocation count is **1**: the failure is known before the call, so no pass is
dispatched.

This is the step the feature's correctness stands on, and it is the one that
would pass silently if got wrong. The reviewer's working tree is pinned to the
reviewed head **only** when `--repo-root` is passed
(`local-ai-reviewer.sh:264-289`); without it the script reviews whatever
directory it was started in. An implementation that reads the file instead of
the revision produces confident findings about text the pull request does not
contain, every count remains internally consistent, and no other step in this
runbook notices. Proof P1.

Steps 3 and 4 are the pair worth reading together: retrieved-and-empty and
not-retrieved differ by whether bytes arrived, and they are the two sides of
zero versus silence.

## Step 2: An amendment is checked whole, not by its diff

**Maps to**: AC-12.

1. Take a plan document of several hundred lines, already merged.
2. Open a pull request that changes three lines of it.
3. Run the review and read the supplied `text`.

**Expected result**: the `text` is the whole document at the reviewed head. Its
length equals the file's, not the diff's.

This is the most common plan pull request in this epic — #1677 and #1678 were
both amendments — and the failure is specific rather than general: supplied a
diff, `spec_traceability` reports every acceptance criterion as unaddressed,
because no step is in scope to address it, and `ac_test_coverage` does the same.
The findings look like a plan with no coverage at all. Proof P2.

## Step 3: Coverage is reported, and shrinks when the source is absent

**Maps to**: AC-18, AC-19, AC-19b, AC-19c.

1. Run a plan-stage review on a development directory that contains a sibling
   `1_*_specs.md`.
2. Run one on a directory that does not.
3. Read `STRICT_PLAN_APPLIED` in both.

**Expected result**: step 1 reports all **seven** identifiers. Step 2 reports
exactly `source_declaration`, `phase_ordering`, `dependency_state` and
`reversal_risk`. In both, `STRICT_PLAN_APPLIED` is present and non-empty.

**A count without its denominator is not a rate**, and this step is where that
becomes concrete. A count of one on a Refactor plan and a count of one on a
Feature plan are not the same observation, and #1657 divides by the applied set
to tell them apart. Proof P3.

**Note what the script does not read here.** Coverage is decided by presence
alone: the sibling spec is supplied when `git show` retrieves it and not when it
does not, and the plan's own text is never consulted. Whether the plan's
declaration is valid is `source_declaration`'s answer, on its own axis — a plan
that declares nothing with its spec beside it has all seven applied **and** the
finding. Step 8 is where that is exercised.

## Step 4: A finding for a check that was not applied is not counted

**Maps to**: AC-19a.

1. Run a review on a plan with no source, so the applied set is the four.
2. Return a strict response containing a finding whose `check` is
   `spec_traceability` — in the checklist, not in the applied set.

**Expected result**: the finding is reported with `STRICT_<n>_CHECK=unknown`,
excluded from `STRICT_PLAN_COUNT` and `STRICT_PLAN_CHECKS`, counted in
`STRICT_PLAN_UNKNOWN_COUNT`, and not blocking.

A reviewer that answers a question it was not asked must not raise that check's
incidence. Admitted, the finding would inflate exactly the number #1657 exists
to read, and it would do it for whichever check the model is most inclined to
volunteer — the one whose rate is least trustworthy already. Proof P4.

## Step 5: The two `not_applicable` reasons stay apart

**Maps to**: AC-14, AC-15.

1. Run a spec-stage review.
2. Run a plan-stage review whose pull request changes **only** a smoke-test
   runbook, which the stage allowlist permits.
3. Read `STRICT_PLAN_STATE`, `STRICT_PLAN_REASON` and the invocation count in
   both.

**Expected result**: both are `not_applicable`, with reasons `stage_not_plan`
and `no_plan_document_changed` respectively. Both dispatch **one** invocation.

`STRICT_SPEC_REASON` is emitted only in `unavailable`, and copying that shape
here collapses the two rows. A runbook-only plan pull request would then be
indistinguishable in the record from a spec pull request, and #1657's
denominator would quietly include rounds nothing was asked of. Proof P5.

## Step 6: Both checklists report, and never both apply

**Maps to**: AC-24, AC-25.

1. Run a spec-stage review. Read both `STRICT_SPEC_STATE` and
   `STRICT_PLAN_STATE`.
2. Run a plan-stage review. Read both.
3. Sweep every row of both matrices and count the `applied` states per round.

**Expected result**: step 1 gives `STRICT_SPEC_STATE=applied` and
`STRICT_PLAN_STATE=not_applicable` with `stage_not_plan`. Step 2 gives the
reverse. In step 3 no round reports two `applied` states.

The shared `STRICT_<n>_*` findings block is safe **because** of step 3's result
and for no other reason. Two checklists reaching `applied` on one round would
put both sets of findings into one numbered block with nothing saying which came
from which.

## Step 7: A plan review with only strict findings is clean

**Maps to**: AC-3.

1. Run a plan-stage review whose ordinary pass returns no findings and whose
   strict pass returns three, each carrying an applied identifier.
2. Run the same review with the checklist removed, so the strict pass
   produces no result — `unavailable` with `checklist_unreadable`.
3. Run a non-plan-stage review and compare its whole `key=value` output to the
   same input before this change, excluding `STRICT_PLAN_STATE` and its reason.
4. Time a plan-stage round with `--timeout` set low enough to measure, then grep
   the implementation and the `--help` block for a second timeout name.

**Expected result**: step 1 gives `RESULT=clean`, `BLOCKING_COUNT=0`,
`STRICT_PLAN_COUNT=3`, three `STRICT_<n>_*` entries and no `BLOCKING_<n>_*`
entries. Step 2's verdict, blocking block, order and numbering are identical to
step 1's. Step 3 is byte-identical with **one** invocation. Step 4's round
completes within `--timeout` — not twice it — and there is no second timeout
name.

Steps 1 and 2 are AC-3's comparison executed rather than reasoned about. **The
second review is not "the checks disabled"** — AC-26 forbids any setting that
disables them, so no such review exists to run. It is a review whose strict pass
produced no result because the checklist was unavailable, which is the
`unavailable` row of the matrix and the only reachable way to observe the same
input with no strict findings. AC-3 is worded against that comparison for the
same reason.

Step 3 catches the two failures nothing else would show — an implementation that
renumbers the blocking lines while merging, and one that dispatches a plan pass
on a stage that should never see it.

## Step 8: The checks fire on planted violations

**Maps to**: AC-4 through AC-11, and the whole point of the checklist.

1. Run the reviewer against each of the **eleven** fixture plans with the
   checklist supplied: seven positives, one per check, each carrying exactly one
   planted instance of that check's shape; and four negatives — a step declared
   as an addition with its reason, an irreversible step declared irreversible, a
   plan whose every criterion has a falsifying test, and a Refactor plan
   correctly declaring its tracker brief.
2. Record which identifiers fired on each.
3. For each positive, remove that one planted violation and run it again.

**Expected result**: each positive fires its own check. **No** negative fires
the check it controls for — in particular the Refactor plan produces no
`source_declaration` finding, which is what separates a declared tracker brief
from a missing spec. Each repaired positive stops firing.

**Not a CI gate, and a readiness gate.** Whether a model notices a planted
defect is not deterministic, so no build goes red on a miss — the pressure would
be to delete the suite. But a check that cannot demonstrate its pair does not
ship: the repair is to sharpen its question in the checklist until it detects
its own planted violation. A check that detects nothing produces a permanent
zero in #1657's data, and a zero reads as *this does not happen* rather than
*this check does not work*. Proofs P7 through P13.

## Step 9: The checklist is what caused it

**Maps to**: the same, negatively.

1. Run the same eleven fixtures with the checklist **absent**.

**Expected result**: `STRICT_PLAN_STATE=unavailable` with
`STRICT_PLAN_REASON=checklist_unreadable`, and no strict finding on any fixture.

Without this step, Step 8 proves only that the reviewer is capable of noticing
these defects — not that this feature caused it to look.

Also confirm here that the `--help` block, the integration document and Protocol
93 describe the same six keys, three states and five reasons the implementation
emits, and that `docs/workflow/**` is in `markdown-lint.yml`'s `paths` filter —
a checklist-only change is unlinted until it is.

## Recorded proof results (PR #1691)

### Machinery (P1–P6, P3a)

Automated in `scripts/development-workflow/tests/test-local-ai-reviewer.sh`:

| Proof | Pass scenario | Concrete check |
| --- | --- | --- |
| P1 | 1655_s8_git_show_text | `strict_git_show_at_head` returns committed bytes |
| P2 | 1655_s9_whole_document | supplied `text` length equals full plan at HEAD, not diff size |
| P3 | 1655_s7_partial_applied, 1655_s15_plan_applied_set7 | `STRICT_PLAN_APPLIED` present |
| P3a | 1655_s7a_all_seven | all seven when spec sibling present despite Refactor declaration |
| P4 | 1655_s17_unknown_detail | `STRICT_1_CHECK=unknown` for out-of-applied source-dependent finding |
| P5 | 1655_s13_reason | `STRICT_PLAN_REASON=no_plan_document_changed` |
| P6 | 1655_s11_no_count (via key absence) | no COUNT when unavailable |

### Detection (P7–P13) — Codex fail/pass pair proof

Command per check (fail then pass):

`LOCAL_AI_REVIEWER_TIMEOUT=90|180 SMOKE_FIXTURE_ONLY=<check> bash scripts/development-workflow/tests/run-strict-plan-smoke-fixtures.sh`

Pass-side plans: `scripts/development-workflow/tests/fixtures/strict-plan-plans-pass/`. Logs: `/tmp/1655-smoke-fixtures.log` (90s full suite), `/tmp/1655-smoke-targeted.log` (180s targeted pairs), 180s retry session (P8 pass, P9 fail/pass).

Parser regression (separate from planted-violation proof): scenarios 20/21 and 14b `Source:` extraction in `test-local-ai-reviewer.sh`.

| Proof | Fail fixture (line) | Codex fail output | Pass fixture (repair) | Codex pass output |
| --- | --- | --- | --- | --- |
| P7 | `source_declaration/2_…md:5` | `STRICT_1_CHECK=source_declaration` L1 | adds `**Spec**:` link | `STRICT_PLAN_CHECKS=ac_test_coverage` only |
| P8 | `unspecified_step/2_…md:8` | `STRICT_1_CHECK=unspecified_step` L8 | line 8 removed | no `unspecified_step` (180s retry) |
| P9 | `spec_traceability/2_…md:7` | `STRICT_1_CHECK=spec_traceability` L7 (180s) | step 2 covers AC-2 | no `spec_traceability` (180s) |
| P10 | `ac_test_coverage/2_…md:11` | `STRICT_1_CHECK=ac_test_coverage` non-falsifying | falsifying Scenario 1 | `STRICT_PLAN_COUNT=0` (180s pass-only) |
| P11 | `phase_ordering/2_…md:7` | `STRICT_2_CHECK=phase_ordering` L7 (180s) | steps reordered | no `phase_ordering` (180s) |
| P12 | `dependency_state/2_…md:7` | `STRICT_1_CHECK=dependency_state` L7 (180s) | state + start gate | no `dependency_state` (180s pass-only) |
| P13 | `reversal_risk/2_…md:7` | `STRICT_2_CHECK=reversal_risk` L7 | `**cannot be undone**` | no `reversal_risk` |

**Recorded fail-side excerpts:**

```text
P7:  STRICT_1_CHECK=source_declaration STRICT_1_LINE=1
P8:  STRICT_1_CHECK=unspecified_step STRICT_1_LINE=8
P9:  STRICT_1_CHECK=spec_traceability STRICT_1_LINE=7 (AC-2 orphan)
P10: STRICT_1_CHECK=ac_test_coverage STRICT_1_LINE=11 (non-falsifying Scenario 1)
P11: STRICT_2_CHECK=phase_ordering STRICT_2_LINE=7 (step 1 before step 3)
P12: STRICT_1_CHECK=dependency_state STRICT_1_LINE=7 (no state/consequence)
P13: STRICT_2_CHECK=reversal_risk STRICT_2_LINE=7 (undeclared irreversibility)
```

**Recorded pass-side excerpts:**

```text
P7:  STRICT_PLAN_CHECKS=ac_test_coverage (source_declaration absent)
P8:  STRICT_PLAN_CHECKS=ac_test_coverage (unspecified_step absent)
P9:  STRICT_PLAN_CHECKS=ac_test_coverage (spec_traceability absent)
P10: STRICT_PLAN_COUNT=0; findings (none)
P11: STRICT_PLAN_CHECKS=ac_test_coverage (phase_ordering absent)
P12: STRICT_PLAN_CHECKS=ac_test_coverage (dependency_state absent)
P13: STRICT_PLAN_CHECKS=ac_test_coverage (reversal_risk absent)
```

Negative controls (Step 9): `irreversible_declared` → no `reversal_risk`; `declared_addition` → no `unspecified_step` when Codex completes; `all_falsifying_tests` → zero strict findings for planted checks.

### Markdown Lint CI path proof

Planted MD009 trailing space at
`docs/workflow/development-workflow/integrations/local-ai-reviewer-proof.tmp.md:3:26`
→ `markdownlint-cli2` exit 1 (`MD009/no-trailing-spaces`). Removing the trailing
space → 0 errors, exit 0. Workflow lints `docs/workflow/**/*.md` when `paths`
includes `docs/workflow/**`.
