# Smoke Test Runbook: Planless Batch Overlap Fallback

**Feature**: Brief-derived overlap classification for planless batch items
**Spec**: [1_1289-planless-overlap-fallback_specs.md](../../specs/developments/20260723110047_1289-planless-overlap-fallback/1_1289-planless-overlap-fallback_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

- [ ] The implementation branch is checked out.
- [ ] Python 3, Bash, and `jq` are available.
- [ ] The overlap classifier and its shell harness exist.
- [ ] Fixture batch records contain current title/brief snapshots rather than
      live mutable tracker references.

---

## Test Data

| Item | Target evidence |
| --- | --- |
| Route item A | `GET /api/users/:id` |
| Route item B | route `/api/users/:id` |
| Parent-route item | `/api/users` |
| Function item A | `resolvePolicy()` |
| Function item B | function `resolvePolicy` |
| Plan item A/B | shared `scripts/development-workflow/pr-review-loop.sh` |
| Unrelated item | helper `checkpoint-resume-gate.sh` |
| Generic-only pair | shared words `workflow`, `batch`, `review`, `implementation` |
| Matching decision | Current batch fingerprint, sorted pair ID, current evidence hash, `allow_parallel` |
| Stale decision | Different batch, pair, or evidence hash |

---

## Smoke Test Steps

### Step 1: Run the Classifier Harness

**Maps to**: Acceptance Criteria 1-9

1. Run
   `bash scripts/development-workflow/tests/test-workflow-batch-overlap.sh`.
2. Confirm all parser, precedence, decision, grouping, and stability cases pass.

**Expected result**: The harness exits successfully with zero failed cases.

### Step 2: Detect a Same-Route Concrete Overlap

**Maps to**: Acceptance Criteria 1, 3, 5

1. Build two planless implementation records naming
   `GET /api/users/:id` and route `/api/users/:id`.
2. Run the classifier in JSON mode.

**Expected result**: The pair is `concrete`, its shared typed route is visible,
`confirmationRequired` is false, and default dispatch is serial.

### Step 3: Detect a Same-Function Concrete Overlap

**Maps to**: Acceptance Criteria 2, 3, 5

1. Build two planless records naming `resolvePolicy()` and function
   `resolvePolicy`.
2. Run the classifier.

**Expected result**: The pair is concrete with a function signal and is assigned
to a serial group.

### Step 4: Require Pair-Scoped Approval for Suspected Overlap

**Maps to**: Acceptance Criteria 4, 5, 9

1. Compare `/api/users` with `/api/users/:id`.
2. Run without a decision file.
3. Run with a matching current `allow_parallel` record.
4. Repeat with stale batch, pair, and evidence identities.

**Expected result**: The missing/stale cases remain serial and request a current
decision. Only the matching record makes the pair parallel-eligible, and the
accepted decision appears in output.

### Step 5: Preserve Plan Evidence Precedence

**Maps to**: Acceptance Criteria 3, 6

1. Give two items an exact shared plan file and unrelated brief targets.
2. Run the classifier.
3. Give two items distinct plan files but related brief signals.

**Expected result**: Exact plan overlap remains concrete and serial. Distinct
plan files plus related briefs are suspected; fallback never downgrades plan
evidence.

### Step 6: Keep Unrelated and Generic-Only Items Eligible

**Maps to**: Acceptance Criteria 7, 8

1. Compare specific unrelated file/route/function targets.
2. Compare briefs that share only generic workflow vocabulary.

**Expected result**: Both pairs report `no_actionable_overlap` and remain
parallel-eligible, with wording that does not claim proven independence.

### Step 7: Verify Lane and Serial Handoff Behavior

**Maps to**: Acceptance Criteria 3, 4, 7

1. Run
   `bash scripts/development-workflow/tests/test-workflow-batch-lanes.sh`.
2. Inspect concrete and unconfirmed suspected fixtures.
3. Confirm higher priority, earlier creation, then lexicographic ID controls
   which item stays in the current lane.
4. Confirm a held serial item requires the preceding implementation PR to
   merge into the approved base before dispatch from the refreshed base.

**Expected result**: Concrete and unconfirmed suspected groups do not dispatch
concurrently; unrelated items remain subject only to existing gates.

### Step 8: Verify Confirmation and Final Summary Evidence

**Maps to**: Acceptance Criteria 5, 9, 10

1. Inspect Protocol 90 (the Batch Orchestration protocol) and all run-work /
   run-items surfaces listed in the plan.
2. Confirm the pre-dispatch summary shows pair IDs, signals, classification,
   uncertainty, and next action.
3. Confirm the final summary records serial/parallel/held disposition and any
   accepted pair-scoped decision.

**Expected result**: Every supported multi-item entry point uses the same
evidence and disposition contract.

### Last Step: Validate and Shut Down

- Run router, bounded-prelude, shell guard, ShellCheck, and Markdown lint
  regressions from the implementation plan.
- Verify every assertion below.
- Remove temporary classifier and decision fixtures.

---

## Assertions Checklist

- [ ] Same-route planless pairs are concrete before dispatch. AC-1.
- [ ] Same-function planless pairs are concrete before dispatch. AC-2.
- [ ] Concrete pairs serialize and resume only after approved-base merge. AC-3.
- [ ] Suspected pairs require current pair-scoped parallel approval or
      serialize. AC-4.
- [ ] Confirmation evidence names pair, signals, classification, and action.
      AC-5.
- [ ] Plan-derived exact overlap remains authoritative. AC-6.
- [ ] Unrelated specific targets remain parallel-eligible. AC-7.
- [ ] Generic-only shared terminology does not create overlap. AC-8.
- [ ] Final summary records disposition and accepted human decisions. AC-9.
- [ ] Run-work, run-items, and orchestrator mirrors use one gate contract.
      AC-10.

---

## Seed Data Reference

No database seed data is required.

| Entity | Scenario | How to load |
| --- | --- | --- |
| Batch item JSON | Plan-known, planless, mixed, unrelated, and generic-only items | Generated by the overlap harness |
| Decision JSONL | Current and stale batch/pair/evidence identities | Generated by the overlap harness |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Generic briefs serialize | Target extraction accepted uncued workflow words | Inspect typed signal cues and stoplist tests |
| Same route is only suspected | Route normalization differs across method/backtick forms | Compare normalized typed route values |
| Plan overlap becomes non-concrete | Fallback result overwrote plan precedence | Preserve exact plan intersection as monotonic concrete |
| Stale approval unlocks parallel dispatch | Decision identity omitted batch or evidence hash | Validate all three decision identity fields |
| A-B/B-C dispatch together | Pair results were not collapsed into a serial group | Build connected components before lane assignment |

---

## Known Limitations

- Best-effort brief parsing cannot infer targets that the plan and current brief
  never name.
- `no_actionable_overlap` is deliberately not proof of independence.
