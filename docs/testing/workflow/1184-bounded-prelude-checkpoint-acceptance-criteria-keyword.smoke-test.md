# Smoke Test Runbook: Bounded Prelude Acceptance Criteria Checkpoint Parsing

**Feature**: Bounded Prelude Acceptance Criteria Checkpoint Parsing
**Spec**: [1_1184-bounded-prelude-checkpoint-acceptance-criteria-keyword_specs.md](../../specs/developments/20260714171029_1184-bounded-prelude-checkpoint-acceptance-criteria-keyword/1_1184-bounded-prelude-checkpoint-acceptance-criteria-keyword_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are in a clean checkout of the implementation branch.
- [ ] `jq`, `bash`, and the repository shell-test dependencies are available.
- [ ] No real tracker, PR, branch, or merge mutation is expected; the focused
      recommender test uses local JSON fixtures.

---

## Test Data

| Item | Value |
| --- | --- |
| Complete Backlog fixture | Problem statement, goal, scope, proposed solution, and populated testable Acceptance Criteria |
| Ambiguous Backlog fixture | Populated criteria plus explicit unresolved product or open-question language |
| Empty criteria fixture | Acceptance Criteria heading with no concrete criterion before the next section or end of body |
| Placeholder criteria fixture | Acceptance Criteria section containing only placeholder tokens such as `TBD`, `TODO`, `N/A`, or `to be defined` |
| Shared helper | `scripts/development-workflow/run-epic-policy-recommender.sh` |

---

## Smoke Test Steps

### Step 1: Run Focused Recommender Tests

**Maps to**: AC1, AC2, AC3, AC4, AC5, AC6, AC7, AC8

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-run-epic-policy-recommender.sh
   ```

2. Confirm the test output includes passing cases for complete populated
   acceptance criteria, unresolved product language, empty criteria, placeholder
   criteria, and existing schema/sensitive checkpoint behavior.

**Expected result**: The test exits successfully and reports no failed cases.

### Step 2: Verify Complete Downstream Issue Shape

**Maps to**: AC1, AC5, AC6, AC7

1. Inspect the complete Backlog fixture added to
   `test-run-epic-policy-recommender.sh`.
2. Confirm the body includes problem statement, goal, scope, proposed solution,
   and populated testable Acceptance Criteria.
3. Confirm the assertion expects zero spec/product checkpoints for that fixture.

**Expected result**: The populated Acceptance Criteria heading is treated as
normal issue structure and does not create a checkpoint by itself.

### Step 3: Verify Real Product Ambiguity Still Stops

**Maps to**: AC2, AC6, AC8

1. Inspect the ambiguity fixture added to
   `test-run-epic-policy-recommender.sh`.
2. Confirm the fixture includes a concrete ambiguity marker such as `Open
   question`, `unclear`, `ambiguous`, or `unresolved product`.
3. Confirm the assertion expects a `spec:product` checkpoint and reason text
   that names unresolved product requirements.

**Expected result**: Real unresolved product language still recommends a human
checkpoint before mutation.

### Step 4: Verify Empty Criteria Handling

**Maps to**: AC3, AC6, AC8

1. Inspect the empty Acceptance Criteria fixture.
2. Confirm the section has no concrete criterion before the next heading or end
   of body.
3. Confirm the assertion expects a `spec:product` checkpoint and reason text
   that names incomplete acceptance criteria.

**Expected result**: Empty acceptance criteria recommend a product checkpoint
with concrete incomplete-criteria reason text.

### Step 5: Verify Placeholder Criteria Handling

**Maps to**: AC4, AC6, AC8

1. Inspect the placeholder Acceptance Criteria fixture.
2. Confirm the criteria section contains placeholder-only content such as
   `TBD`, `TODO`, `N/A`, `placeholder`, or `to be defined`.
3. Confirm the assertion expects a `spec:product` checkpoint and reason text
   that names incomplete acceptance criteria.

**Expected result**: Placeholder acceptance criteria recommend a product
checkpoint with concrete incomplete-criteria reason text.

### Step 6: Validate Shared Prelude Contract

**Maps to**: AC5

1. Inspect `docs/workflow/development-workflow/bounded-run-prelude.md`.
2. Confirm it still documents `run-epic-policy-recommender.sh` as the single
   checkpoint recommender for `/run-item`, `/run-items`, and `/run-epic`.
3. Confirm no command-specific classifier was added outside the shared
   recommender path.

**Expected result**: The fixed behavior applies consistently to all bounded
prelude consumers.

### Last Step: Validate & Shut Down

- Verify all assertions in the checklist below are met.
- No application server or persistent test data needs cleanup.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] Complete populated Acceptance Criteria do not trigger a product checkpoint
      solely due to the phrase `acceptance criteria`. AC1
- [ ] Explicit unresolved product language still triggers a product checkpoint.
      AC2
- [ ] Empty Acceptance Criteria trigger a checkpoint with incomplete-criteria
      reason text. AC3
- [ ] Placeholder Acceptance Criteria trigger a checkpoint with
      incomplete-criteria reason text. AC4
- [ ] The shared bounded prelude path covers `/run-items` batch behavior after
      policy confirmation. AC5
- [ ] Reason text distinguishes normal headings from real ambiguity or
      incompleteness. AC6
- [ ] The complete downstream issue fixture includes problem statement, goal,
      scope, proposed solution, and testable acceptance criteria. AC7
- [ ] Verification includes at least one real ambiguity marker and at least one
      empty or placeholder acceptance-criteria case. AC8

---

## Seed Data Reference

The following seed data must be present:

| Entity | Scenario | How to load |
| --- | --- | --- |
| Local JSON fixture | Complete Backlog issue shape | Created inside `test-run-epic-policy-recommender.sh` |
| Local JSON fixture | Ambiguous Backlog issue | Created inside `test-run-epic-policy-recommender.sh` |
| Local JSON fixture | Empty criteria issue | Created inside `test-run-epic-policy-recommender.sh` |
| Local JSON fixture | Placeholder criteria issue | Created inside `test-run-epic-policy-recommender.sh` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Focused shell test fails before fixture assertions | Missing `jq` or shell environment mismatch | Install the missing local dependency or rerun in the repository development environment. |
| Complete criteria fixture still recommends a checkpoint | Classifier still treats the heading phrase as an ambiguity signal | Revisit the recommender helper split and ensure populated criteria are evaluated separately from unresolved-language markers. |
| Empty or placeholder criteria do not recommend a checkpoint | Section boundary or placeholder detection is too permissive | Add a narrower fixture and adjust criteria-section parsing. |
| Reason text mentions only `acceptance criteria` | Reason selection was not updated after classifier split | Emit separate reasons for unresolved product language versus incomplete criteria. |

---

## Known Limitations

- This runbook validates the shared recommender behavior through local fixtures.
  It does not require live GitHub Project mutation or a real `/run-items`
  tracker transition.
