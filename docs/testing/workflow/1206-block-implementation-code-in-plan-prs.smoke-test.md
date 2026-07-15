# Smoke Test Runbook: Block Implementation Code in Plan PRs

**Feature**: Block implementation code in documentation-stage PRs
**Spec**: [1_1206-block-implementation-code-in-plan-prs_specs.md](../../specs/developments/20260714165420_1206-block-implementation-code-in-plan-prs/1_1206-block-implementation-code-in-plan-prs_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation branch is checked out.
- [ ] `gh` is authenticated for the repository if live PR mode is tested.
- [ ] The new stage-alignment checker test harness passes locally.
- [ ] Fixture inputs are available for aligned documentation-stage PRs,
      mismatched plan PRs, mismatched spec PRs, and empty documentation-stage
      changed-file lists.

---

## Test Data

| Item | Value |
| --- | --- |
| Aligned plan fixture | `implementation-plan/1206-example` with `docs/specs/developments/example/2_example_implementation-plan.md` and `docs/testing/workflow/example.smoke-test.md` |
| Mismatched plan fixture | `implementation-plan/1206-example` with `src/example.ts` or `supabase/migrations/20260714000000_example.sql` |
| Mismatched spec fixture | `spec/1206-example` with `src/example.ts` |
| Aligned spec fixture | `spec/1206-example` with `docs/specs/developments/example/1_example_specs.md` |
| Empty documentation-stage diff fixture | `implementation-plan/1206-empty` with no changed files |
| Stable warning marker | `<!-- documentation-stage-alignment -->` |

---

## Smoke Test Steps

### Step 1: Run the Automated Checker Tests

**Maps to**: Acceptance Criteria 1, 2, 3, 4, 5, 6, 7, 8, 10

1. Run `bash scripts/development-workflow/tests/test-check-documentation-stage-alignment.sh`.
2. Confirm the output reports passing cases for aligned plan, mismatched plan,
   mismatched spec, aligned spec, empty documentation-stage diff, resume-style
   fixture input, and stable warning comment behavior.

**Expected result**: The harness exits successfully and names all required
stage-alignment scenarios.

### Step 2: Verify Aligned Plan PR Behavior

**Maps to**: Acceptance Criteria 1, 8

1. Use fixture input or a disposable draft PR whose head branch starts with
   `implementation-plan/`.
2. Ensure the changed-file list contains only the plan document and its
   `.smoke-test.md` runbook.
3. Run the checker in fixture mode or live PR mode.

**Expected result**: The checker reports the PR as stage-aligned and does not
emit a readiness-blocking warning.

### Step 3: Verify Mismatched Plan PR Behavior

**Maps to**: Acceptance Criteria 2, 4, 5, 6, 10

1. Use fixture input or a disposable draft PR whose head branch starts with
   `implementation-plan/`.
2. Include at least one implementation file in the changed-file list, such as
   `src/example.ts` or a database migration path.
3. Run the checker.
4. Inspect the checker output or PR comment body.

**Expected result**: The checker reports a stage mismatch, names the expected
plan-stage artifact boundary, lists the unexpected file path, and makes clear
that the blocker is workflow stage collapse rather than code correctness. The
checker exits with Protocol 91 Step 8a exit code `8` for the mismatch.

### Step 4: Verify Mismatched Spec PR Behavior

**Maps to**: Acceptance Criteria 3, 4, 5, 6, 10

1. Use fixture input or a disposable draft PR whose head branch starts with
   `spec/`.
2. Include at least one implementation file in the changed-file list.
3. Run the checker.
4. Inspect the checker output or PR comment body.

**Expected result**: The checker reports a stage mismatch before readiness,
lists the unexpected file, and blocks automatic human-review readiness.

### Step 5: Verify Resume Behavior

**Maps to**: Acceptance Criteria 7

1. Use a fixture that represents an already-open documentation-stage PR with
   unexpected implementation files in its current diff.
2. Run the checker without creating new files in the current session.

**Expected result**: The checker evaluates the current diff and blocks
readiness even though the contamination pre-existed the resumed run.

### Step 6: Verify Stable Warning Comment Behavior

**Maps to**: Acceptance Criteria 4, 6

1. Run the checker once on a mismatched fixture or disposable PR.
2. Run it again after the warning marker already exists.

**Expected result**: The checker updates the existing
`<!-- documentation-stage-alignment -->` warning instead of creating duplicate
warning comments.

### Step 7: Validate Readiness Gate Integration

**Maps to**: Acceptance Criteria 2, 3, 5, 8, 9

1. Inspect Protocol 91 Step 8a in the implementation branch.
2. Confirm the stage-alignment checker runs before every
   `ready-for-human-review` application path, including Human Checkpoint Label
   Sync and the embedded readiness checklist.
3. Confirm the documented exception path is correction or human escalation, not
   a silent bypass.
4. Confirm valid documentation-only spec and plan PRs can continue through the
   normal review, CI, label, and tracker path.

**Expected result**: The readiness path blocks mismatched documentation-stage
PRs and leaves aligned documentation-stage PRs on the normal path.

### Last Step: Validate and Shut Down

- Verify all assertions below are satisfied.
- Remove any disposable local fixture directories or draft PRs created only for
  this smoke test.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] Aligned plan-stage PR changes can continue through readiness. AC1.
- [ ] Plan-stage PRs with implementation artifacts are detected before
      `ready-for-human-review`. AC2.
- [ ] Spec-stage PRs with implementation artifacts are detected before
      `ready-for-human-review`. AC3.
- [ ] Mismatch warnings name the expected stage and unexpected files. AC4.
- [ ] Mismatched documentation-stage fixtures exit with Protocol 91 Step 8a
      code `8`, while usage and infrastructure failures use separate non-zero
      codes. AC4, AC8.
- [ ] Work Item Runner readiness remains blocked until correction or
      escalation. AC5.
- [ ] Warning text identifies workflow stage collapse, not code correctness.
      AC6.
- [ ] Resume behavior evaluates the current PR diff. AC7.
- [ ] Valid documentation-only spec and plan PRs are not blocked. AC8.
- [ ] Empty changed-file lists on documentation-stage branches block readiness
      instead of passing as aligned. AC8, AC10.
- [ ] The implementation documents the selected enforcement and exception
      mechanism. AC9.
- [ ] Verification coverage includes mismatched plan, mismatched spec, and
      aligned documentation-stage plus empty-diff examples. AC10.

---

## Seed Data Reference

No database seed data is required.

| Entity | Scenario | How to load |
| --- | --- | --- |
| Fixture JSON or shell arrays | Branch names, changed-file lists, and expected checker verdicts | Generated inside the checker test harness |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Checker reports `not_applicable` for a documentation-stage fixture | Fixture branch does not start with `spec/` or `implementation-plan/` | Correct the head branch in the fixture |
| Live PR mode cannot read files | `gh` is unauthenticated or the PR number is wrong | Reauthenticate `gh` or rerun with the correct PR number |
| Warning comment duplicates | Stable marker lookup is not matching existing comments | Inspect comment body handling and marker matching in the checker |
| Aligned plan fixture is blocked | Allowed path rules omit plan runbooks | Confirm `docs/testing/**/*.smoke-test.md` is allowed for plan branches |

---

## Known Limitations

- This runbook validates the workflow guard, not a product UI.
- Live PR mode is optional for local smoke testing when fixture mode covers the
  same changed-file classification behavior.
