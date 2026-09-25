# Smoke Test Runbook: Plan Gate Proportionality

**Feature**: Review gates weigh test-scope proportionality instead of literal conformance
**Source of truth**: GitHub issue #1785 (Refactor item — no spec)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

This is a workflow-contract change. The runbook is executed from a terminal at
the repository root against the implementation branch; there is no application
to launch and no UI to inspect. No design assets were discovered for this item
(no `## Design assets` section in the work item and no `assets/` directory in
the development folder), so this runbook contains no design-fidelity step.

---

## Prerequisites

- [ ] The implementation branch is checked out and up to date
- [ ] `jq`, `git`, and Node's `markdownlint-cli2` from the repository's
      `node_modules` are available
- [ ] Optional, for Step 4 only: the `codex` CLI is installed and authenticated

---

## Test Data

| Item | Value |
| --- | --- |
| Canonical document | `docs/workflow/development-workflow/test-scope-proportionality.md` |
| Strict checklist | `docs/workflow/development-workflow/strict-plan-checks.md` |
| New check identifier | `test_scope_proportionality` |
| Fail fixture | `scripts/development-workflow/tests/fixtures/strict-plan-plans/test_scope_proportionality/` |
| Pass fixture | `scripts/development-workflow/tests/fixtures/strict-plan-plans-pass/test_scope_proportionality/` |

---

## Smoke Test Steps

### Step 1: The strict registry still parses, and admits the new row

**Maps to**: advisory-flag criterion

1. Confirm the checklist declares one level-3 heading per identifier and no
   stray ones:

   ```bash
   grep -c '^### ' docs/workflow/development-workflow/strict-plan-checks.md
   grep -n '^### \|^Source:' docs/workflow/development-workflow/strict-plan-checks.md
   ```

2. Run the reviewer's own extractors against the edited checklist:

   ```bash
   HARNESS_MODE=1 bash -c '
     source scripts/development-workflow/local-ai-reviewer.sh
     extract_strict_checklist_known_checks docs/workflow/development-workflow/strict-plan-checks.md
     extract_strict_plan_sections docs/workflow/development-workflow/strict-plan-checks.md
   '
   ```

**Expected result**: both extractors succeed (non-zero exit means the document
was refused). The identifier list contains `test_scope_proportionality`, its
`Source` value is `not_required`, and the number of extracted identifiers equals
the `grep -c` count from sub-step 1.

### Step 2: The advisory signal is carried, and absence is carried too

**Maps to**: advisory-flag criterion

1. Run the reviewer test suite:

   ```bash
   bash scripts/development-workflow/tests/test-local-ai-reviewer.sh
   ```

**Expected result**: the suite passes. Its planted fail/pass pair for
`test_scope_proportionality` shows the identifier surfacing at the fixture's
path and line in the fail variant, and not appearing at all in the pass variant.
No previously passing scenario regresses — in particular, the scenario that
drops an identifier absent from the checklist still counts it as unknown.

### Step 3: Nothing downstream of the reviewer changed

**Maps to**: advisory-flag criterion (non-blocking property)

1. Run the loop suite and the doctrine lint:

   ```bash
   bash scripts/development-workflow/tests/test-pr-review-loop.sh
   bash scripts/lint/review-doctrine-lint.sh
   ```

**Expected result**: both pass. The strict findings remain non-blocking: no
verdict in either suite flips because a `test_scope_proportionality` finding
exists.

### Step 4 (optional — requires the `codex` CLI): model-level behavior

**Maps to**: advisory-flag criterion

1. Run the manual strict-plan smoke helper for the new identifier only:

   ```bash
   SMOKE_FIXTURE_ONLY=test_scope_proportionality \
     bash scripts/development-workflow/tests/run-strict-plan-smoke-fixtures.sh
   ```

**Expected result**: the fail variant reports a `test_scope_proportionality`
finding; the pass variant reports none. Record both outputs. If the CLI is
unavailable, record the step as skipped with that reason — do not record it as
passing.

### Step 5: A coverage-equivalent reduction is not blocking

**Maps to**: blocking-threshold criterion, recorded-deviation criterion

1. Read the Gate A matrix in `REVIEW.md` and the canonical document.
2. Take the case of an implementation that ships fewer test rows than the plan
   projected, with a complete Test-Scope Deviation Record, where the only
   objection available to the reviewer is that the delivered number differs from
   the plan's number.

**Expected result**: the documents direct the reviewer to row A3 — not blocking,
`suggestion` at most, record accepted. Neither document permits blocking on the
count alone, and neither instructs the implementer to rebuild the projected set.

### Step 6: A coverage-losing reduction is blocking, with both halves stated

**Maps to**: blocking-threshold criterion

1. Take the same delta, but where the removed rows were the only exercise of a
   named behavior the change ships.

**Expected result**: the documents direct the reviewer to row A2 — blocking,
and the finding must name both the specific coverage lost and the defect class
that now escapes. A finding that names only one half does not satisfy the rule.

### Step 6b: A net-larger swap that drops unique coverage is still blocking

**Maps to**: blocking-threshold criterion (count-is-not-an-input rule)

1. Take a delta where the delivered test scope is **equal to or larger** than
   the plan's projection in item count, but the change drops items that were
   the only exercise of a named behavior — a swap, a consolidation, or a
   rewrite that nets out even or up.

**Expected result**: exclusion **X2 does not apply** — a removal that nets even
or larger is still a removal. The delta therefore enters the table and is
resolved by the plan marking and the record, exactly as the equivalent
shrinking delta would be, and is never closed on the total alone.

Then confirm Gate A is stated as **two independent scope questions settled
before any row is read** — X1 (what the delta touches) and X2 (whether anything
was removed) — followed by a table whose rows turn only on marking, record, and
harm statement. Confirm the `Item count is never a gate input` paragraph ties
the swap case to X2 explicitly.

Finally check all three directions the two dimensions must keep separate:

- An **addition-only** scaffolding delta (nothing removed, no deviation record)
  is excluded by X2 and produces no finding. It must **not** reach A4 and
  become `important`.
- A **behavior or acceptance-criterion** delta that leaves the projected tests
  intact is excluded by X1 and stays `blocking` under the unchanged Pass 1
  rule. It must **not** be absorbed by X2 and silently pass.
- A *smaller* but coverage-equivalent reduction must still reach A3 (record
  present) or A4 (record missing), and a reduced `**Binding enumeration**` must
  still reach A5/A6. Neither exclusion may absorb them.

### Step 7: A missing record is requested, not used to block — unless harm can be named

**Maps to**: recorded-deviation criterion

1. Take an indicative test-scope reduction shipped with no Test-Scope
   Deviation Record, where no reviewer can name either half of a
   Coverage-Harm Statement.
2. Take the same missing-record case, but where the reviewer can name both
   the specific coverage lost and the defect class that now escapes.

**Expected result**: step 1 lands on row A4 — `important`, request the
record before `ready-for-human-review`. Step 2 lands on row A7 —
`blocking`: a stated harm is blocking whether or not the record was
written, so the missing record does not downgrade it, and the record is
also requested. Confirm Protocol 03 tells the implementer to write the
record during the Pre-Submission Self-Review Pass and to include it in the
Path 1 and Path 2 PR descriptions, so the request has a defined place to
land.

### Step 8: Explicit binding still binds, and behavior deltas are untouched

**Maps to**: blocking-threshold criterion, authoring-guidance criterion

1. Take an enumeration the plan marked with the exact literal
   `**Binding enumeration**`, reduced by the implementation.
2. Separately, take a delta that changes observable behavior or drops coverage
   of an acceptance criterion.

**Expected result**: the first case lands on row A5 or A6 — blocking. The second
is excluded by X1 — blocking under the unchanged Pass 1 rule, with no
Coverage-Harm Statement required beyond naming the criterion or behavior. Also
confirm the non-weakening clause is present: review of production-code
correctness and of third-party reviewer output is explicitly unchanged.

### Step 9: Authoring and review agree

**Maps to**: authoring-guidance criterion

1. Read the Protocol 02 Step 3 quality guardrails.

**Expected result**: an enumeration is indicative unless marked with the exact
literal; the author is told to state coverage intent and to justify any number
given; and the note explaining that this rule and the pattern-completeness /
freeze-exception rules govern different axes is present, so the two do not read
as contradictory. The same default appears, in one sentence, in the tech-lead
mirrors for each supported tool.

### Step 10: The worked example is present and consistent

**Maps to**: worked-example criterion

1. Read the worked example in the canonical document.

**Expected result**: it describes the historical case — a documentation
deliverable whose plan carried a large literal fixture manifest, and a curated
revision rejected as a unilateral scope reduction — and shows both outcomes
under the revised gate (row A3 when the only objection is the number, row A2
when concrete coverage loss can be named). The historical figures are labelled
as a record of what happened, not as a requirement. The example contradicts no
rule stated beside it.

### Step 11: Consistency sweep

**Maps to**: all criteria

1. Re-run the discovery greps from the plan's Verification Log:

   ```bash
   grep -rn "source_declaration" scripts/development-workflow/tests/ \
     docs/workflow/development-workflow/integrations/ docs/testing/workflow/
   grep -rl "02-generate-implementation-plan-protocol\|03-implement-development-protocol" \
     .claude/ .cursor/ .codex/ .agents/
   ```

2. Run the markdown gates over the changed documents:

   ```bash
   ./node_modules/.bin/markdownlint-cli2 \
     "docs/specs/developments/20260923091837_1785-plan-gate-proportionality/*.md" \
     "docs/testing/workflow/1785-plan-gate-proportionality.smoke-test.md" \
     "changelog.d/1785.changed.plan-gate-proportionality.md"
   python3 scripts/lint/markdown-heuristic-lint.py \
     docs/specs/developments/20260923091837_1785-plan-gate-proportionality/2_1785-plan-gate-proportionality_implementation-plan.md \
     docs/testing/workflow/1785-plan-gate-proportionality.smoke-test.md \
     changelog.d/1785.changed.plan-gate-proportionality.md
   ```

**Expected result**: every identifier-count and applied-set statement found by
the first grep matches the edited checklist; every agent or skill surface found
by the second is either updated or justified as unchanged; and both linters
report no violations.

### Last Step: Record results

- Record PASS/FAIL per step with the observed output
- Record Step 4 as skipped, with its reason, when the CLI is unavailable

---

## Assertions Checklist

- [ ] A test-scope enumeration delta is blocking only when the reviewer states
      both the specific coverage lost and the defect class that escapes
- [ ] Item count is never a gate input: a delta that nets even or larger while
      dropping uniquely-covering items is still treated as the equivalent
      shrinking delta, and an addition-only delta is excluded by X2 with no
      finding
- [ ] A Test-Scope Deviation Record format exists, and the gate documents how it
      is evaluated, including the missing-record outcome
- [ ] Plan-authoring guidance makes enumerations indicative unless marked with
      the exact binding literal, and asks for coverage intent otherwise
- [ ] Plan review surfaces an advisory, never-blocking signal when projected
      test scaffolding outweighs the deliverable it protects
- [ ] The motivating scenario is captured as a worked example showing both the
      not-blocking and the blocking outcome
- [ ] Production-code correctness review and third-party reviewer-output
      matching are explicitly unchanged

---

## Seed Data Reference

None. The only inputs are the fixture plans listed under **Test Data**, which
ship with the implementation.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| An extractor in Step 1 exits non-zero | The checklist gained a level-3 heading that is not an identifier, or a section has zero or two `Source:` lines | Restore the one-heading-one-`Source:`-line shape for every section |
| Step 2 fails on an applied-set expectation | A hard-coded identifier list was not re-derived after the checklist changed | Re-run the Step 11 discovery grep and update every hit that enumerates identifiers |
| `review-doctrine-lint.sh` fails | The new entry is malformed, references the incident, or the catalogue exceeded its byte bound | Fix the entry shape and wording; if the bound is breached, merge or remove a pattern rather than raising the bound |
| Step 4 produces no finding in the fail variant | The fixture does not plainly exhibit the finding shape, or the model timed out | Sharpen the fixture, or raise `LOCAL_AI_REVIEWER_TIMEOUT` and retry |

---

## Known Limitations

- Steps 5 through 10 verify the written contract, not runtime enforcement: the
  prose rules instruct reviewers and authors and have no automated check to
  exercise. They are deliberately not given a planted-violation proof.
- Step 4 depends on a third-party CLI and on model behavior, so it is advisory
  evidence rather than a gate.
