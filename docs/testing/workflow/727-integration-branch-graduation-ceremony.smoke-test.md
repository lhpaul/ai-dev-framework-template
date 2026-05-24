# Smoke Test Runbook: Integration Branch Graduation Ceremony

**Feature**: Integration Branch Graduation Ceremony (issue #727)
**Spec**: [docs/specs/developments/20260524190405_integration-branch-graduation-ceremony/1_integration-branch-graduation-ceremony_specs.md](../../specs/developments/20260524190405_integration-branch-graduation-ceremony/1_integration-branch-graduation-ceremony_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The updated protocol documents have been merged to `develop`
- [ ] You have a GitHub repository with at least one `develop-<slug>` integration branch where all planned sub-items have merged implementation PRs (or you can simulate this with a test branch)
- [ ] `gh` CLI is authenticated and `git fetch origin` has been run

---

## Test Data

| Item | Value |
| ---- | ----- |
| Integration branch slug | `test-graduation-smoke` (or any existing completed epic slug) |
| Integration branch name | `develop-test-graduation-smoke` |
| Sub-item issue labels | `integration-branch:test-graduation-smoke` |
| Epic issue | A GitHub issue labeled `integration-branch:test-graduation-smoke` with all planned sub-items having merged PRs |

---

## Smoke Test Steps

### Step 1: Verify Protocol 05b Step 0 (Human Approval Gate)

**Maps to**: AC-2

1. Open `docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md`.
2. Confirm that a Step 0 (Human Approval Gate) section appears before Step 1 (Resolve the Slug).
3. Confirm it states that the agent must not open a graduation PR without explicit human approval.
4. Confirm it requires the agent to surface a summary of included sub-items to the human before proceeding.

**Expected result**: Step 0 is present and clearly states the human-approval requirement.

---

### Step 2: Verify Protocol 05b CHANGELOG Handling (Step 2.5)

**Maps to**: AC-6, BR-5

1. In `05b-graduate-development-protocol.md`, confirm a CHANGELOG handling step exists between sub-item verification and PR opening.
2. Confirm it states that `[Unreleased]` CHANGELOG entries from `develop-<slug>` must be present in the graduation PR diff.
3. Confirm it includes the note that the absorb commit must be part of the graduation branch, NOT a separate prior merge.

**Expected result**: CHANGELOG handling step is present with the BR-5 constraint clearly stated.

---

### Step 3: Verify Protocol 05b PR Body Requirements

**Maps to**: AC-3, AC-4, AC-5

1. In `05b-graduate-development-protocol.md`, locate Step 3 (Open the Graduation PR).
2. Confirm the PR title format is: `Graduate \`<slug>\` integration branch to develop`.
3. Confirm the PR body requirements include: a bulleted list with `#<issue> <title> (PR #<pr>)` format for each sub-item.
4. Confirm the PR body must include a statement that the merge strategy must be a **merge commit** (not squash or rebase).

**Expected result**: All three PR body requirements match the spec (AC-3, AC-4, AC-5).

---

### Step 4: Verify Protocol 05b `ready-for-regression` Exemption

**Maps to**: AC-7, BR-6

1. In `05b-graduate-development-protocol.md`, locate Step 4 (Run the Standard Review Loop).
2. Confirm it explicitly states that `ready-for-regression` is NOT required for graduation PRs.

**Expected result**: The exemption note is present.

---

### Step 5: Verify Protocol 05b Post-Merge Cleanup (Epic Issue and Optional Sub-Items)

**Maps to**: AC-8, AC-9, AC-10

1. In `05b-graduate-development-protocol.md`, locate Step 5 (Post-Merge Cleanup).
2. Confirm it includes: remote branch deletion (`git push origin --delete develop-<slug>`).
3. Confirm it includes: epic issue closure guidance (close when core deliverable is done, leave open if optional sub-items remain with a note).
4. Confirm it includes: optional sub-item disposition — surface remaining open sub-items to the human for reassignment, cancellation, or deferral to a new epic.
5. Confirm it includes: stale worktree cleanup guidance.

**Expected result**: All five post-merge cleanup sub-steps are present.

---

### Step 6: Verify Protocol 90 Step 1b Graduation Eligibility Surfacing

**Maps to**: AC-11, AC-12

1. Open `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`.
2. Navigate to Step 1b (Enrich with VCS state).
3. Locate the integration branch enumeration passage: "When gathering VCS state, also collect the set of open `develop-<slug>` integration branches..."
4. Confirm that a "Graduation eligibility check" block immediately follows this passage.
5. Confirm the block describes: querying sub-items for each integration branch, checking for merged implementation PRs, and surfacing eligible branches to the human with the sub-item list.
6. Confirm the block does NOT auto-graduate — it only surfaces eligibility to the human.

**Expected result**: Graduation eligibility surfacing block is present in Step 1b; it is human-decision-required only.

---

### Step 7: Verify Protocol 90 Step 1c Portfolio Map Entry

**Maps to**: AC-12

1. In `90-batch-orchestrate-work-protocol.md`, navigate to Step 1c (Build the portfolio map).
2. Confirm the portfolio map bullet list includes an entry for graduation-eligible integration branches.

**Expected result**: The portfolio map lists graduation-eligible integration branches as a distinct state.

---

### Step 8: Verify Protocol 90 Step 5.1 `ready-for-regression` Exemption for Graduation PRs

**Maps to**: AC-7, BR-6

1. In `90-batch-orchestrate-work-protocol.md`, navigate to Step 5.1 (PR verification table).
2. Locate the `ready-for-regression` row.
3. Confirm the "Pass condition" cell includes an exemption for graduation PRs (head branch `develop-<slug>`, base branch `develop`).
4. Confirm the remediation column does not prescribe applying the label to graduation PRs.

**Expected result**: The Step 5.1 table explicitly exempts graduation PRs from the `ready-for-regression` requirement.

---

### Step 9: Verify Protocol 91 Branch-Prefix Table Update

**Maps to**: AC-7, BR-6

1. Open `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`.
2. Navigate to the `ready-for-regression` branch-prefix table in Step 7b / Step 8a.
3. Confirm the table includes a row for graduation PRs (`develop-<slug>` head, `develop` base) with `ready-for-regression` NOT required.
4. Confirm the catch-all note below the table explicitly lists graduation branches as a known/expected non-implementation PR type (not a configuration anomaly).

**Expected result**: The branch-prefix table has the graduation PR row; the catch-all note is updated.

---

### Last Step: Validate and Close

- Verify all assertions in the checklist below are met
- No manual application of `ready-for-regression` is needed for any protocol-guided graduation PR review

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC-2: Protocol 05b Step 0 requires explicit human approval before any graduation action
- [ ] AC-3: Protocol 05b Step 3 specifies the graduation PR title format exactly
- [ ] AC-4: Protocol 05b Step 3 requires the PR body to list every sub-item with issue and PR numbers
- [ ] AC-5: Protocol 05b Step 3 requires the PR body to state the merge-commit requirement
- [ ] AC-6: Protocol 05b Step 2.5 specifies CHANGELOG handling with the "absorb must be in the graduation branch" constraint
- [ ] AC-7: Protocol 05b Step 4, Protocol 90 Step 5.1, and Protocol 91 Step 8a all agree that `ready-for-regression` is NOT required for graduation PRs
- [ ] AC-8: Protocol 05b Step 5 includes remote branch deletion
- [ ] AC-9: Protocol 05b Step 5 includes epic issue closure guidance
- [ ] AC-10: Protocol 05b Step 5 includes optional sub-item disposition (surface to human for reassignment/cancellation/deferral)
- [ ] AC-11: Protocol 90 Step 1b references Protocol 05b for the graduation ceremony
- [ ] AC-12: Protocol 90 Step 1b explicitly enumerates `develop-<slug>` branches and checks graduation eligibility

---

## Seed Data Reference

No application seed data required. Protocol documents are the only artifacts under test.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| Step 5.1 still flags graduation PR for missing `ready-for-regression` | The Step 5.1 table update was missed or the branch name pattern check was not added | Re-read `90-batch-orchestrate-work-protocol.md` Step 5.1 and verify the exemption is present |
| Protocol 91 table catch-all note still reports graduation branch as anomaly | The catch-all note update was missed | Re-read `91-orchestrate-work-protocol.md` Step 8a and verify the note is updated |
| Protocol 05b still missing CHANGELOG step | Implementation order Step 1 was partially applied | Re-read `05b-graduate-development-protocol.md` and verify Step 2.5 is present |

---

## Known Limitations

- This runbook tests protocol document correctness, not live execution of the graduation ceremony. A full end-to-end graduation test requires a real or simulated epic with completed sub-items on a `develop-<slug>` branch.
