# Smoke Test Runbook: Pre-Submission Self-Review Pass

**Feature**: Pre-submission self-review pass before opening implementation PRs
**Spec**: [1_799-pre-submission-self-review-pass_specs.md](../../specs/developments/20260602160610_799-pre-submission-self-review-pass/1_799-pre-submission-self-review-pass_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

- [ ] You are on an implementation branch produced from `develop` or `main` according to the branch type.
- [ ] The implementation PR has not been opened yet.
- [ ] The implementation branch has local changes committed or staged for review.

---

## Test Data

No seeded data is required. Use a representative implementation branch that changes at least one protocol or script file.

---

## Smoke Test Steps

### Step 1: Verify Full Pipeline Protocol Placement

**Maps to**: AC-1, AC-5, AC-6, AC-7

1. Open `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`.
2. Locate Full Pipeline Path 1.
3. Confirm a required pre-submission self-review step appears after implementation verification and before the board-membership / `gh pr create` instructions.
4. Confirm the step cites `git diff <base-branch>...HEAD`, references the Test Harness Coverage Checklist, and requires a PR-description self-review log.

**Expected result**: Full Pipeline agents must complete the pre-submission self-review pass before draft PR creation.

### Step 2: Verify Refactor Protocol Placement

**Maps to**: AC-2, AC-5, AC-7

1. Locate Refactor Path 2 in Protocol 03.
2. Confirm the same pre-submission self-review gate appears before draft PR creation.
3. Confirm the coverage check references implementation-plan acceptance criteria.

**Expected result**: Refactor agents must complete the gate and validate plan acceptance coverage before opening the PR.

### Step 3: Verify Fast Track Fix Protocol Placement

**Maps to**: AC-3, AC-5, AC-7

1. Locate Fast Track Fix Path 3 in Protocol 03.
2. Confirm the pre-submission self-review gate appears before draft PR creation.
3. Confirm the coverage check uses the issue body's stated problem and proposed fix instead of spec ACs.

**Expected result**: Fast Track Fix agents must complete stale-marker, sibling/caller, and stated-fix coverage checks before opening the PR.

### Step 4: Verify Hotfix Protocol Placement

**Maps to**: AC-4, AC-5, AC-7

1. Locate Hotfix Path 4 in Protocol 03.
2. Confirm the pre-submission self-review gate appears before draft PR creation.
3. Confirm the diff base is `main` for hotfixes.

**Expected result**: Hotfix agents use `main` as the base branch and complete the gate before opening the PR.

### Step 5: Verify Reviewer Enforcement

**Maps to**: AC-8

1. Open `REVIEW.md`.
2. Locate the code review checklist.
3. Confirm reviewers are instructed to flag stale debug/TODO/FIXME/review markers, caller inconsistencies, or uncovered spec/issue-body requirements that should have been caught by the pre-submission pass.

**Expected result**: Reviewers have an explicit contract to enforce the new pre-submission pass.

---

## Assertions Checklist

- [ ] Full Pipeline Path 1 includes the pre-submission self-review gate before draft PR creation.
- [ ] Refactor Path 2 includes the gate and references implementation-plan acceptance criteria.
- [ ] Fast Track Fix Path 3 includes the gate and references issue-body coverage.
- [ ] Hotfix Path 4 includes the gate and uses `main` as the diff base.
- [ ] The gate cites `git diff <base-branch>...HEAD` and not the two-dot form.
- [ ] The gate cross-references the Test Harness Coverage Checklist.
- [ ] The gate requires a PR-description self-review log.
- [ ] `REVIEW.md` contains the reviewer enforcement item.

---

## Seed Data Reference

No seed data is required.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| A path has `gh pr create` but no nearby self-review gate. | The implementation updated only one branch type. | Add the gate to every implementation path before PR creation. |
| The gate uses `git diff develop HEAD`. | The two-dot form was copied accidentally. | Replace with `git diff <base-branch>...HEAD` and document base resolution. |
| Reviewers have no checklist item for this behavior. | `REVIEW.md` was not updated. | Add the implementation-review check before marking the PR ready. |

---

## Known Limitations

- This is a protocol smoke test; enforcement is by workflow guidance and review checks, not a new CI rule.
