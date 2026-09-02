# Smoke Test Runbook: Cross-PR Closing Keyword Validation

**Feature**: Cross-PR closing keyword validation (#1644)
**Spec**: [`1_1644-cross-pr-closing-keyword-validation_specs.md`](../../specs/developments/20260827184933_1644-cross-pr-closing-keyword-validation/1_1644-cross-pr-closing-keyword-validation_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

This feature has no user interface and no application to log into. It runs as a
GitHub Actions workflow and writes to pull requests, so the smoke test exercises
it on real throwaway pull requests in the repository. The unit suite covers the
rules; this runbook covers the wiring the unit suite cannot see — that the
workflow is triggered, has the permissions it needs, and writes what the script
decided.

---

## Prerequisites

Before running this smoke test:

- [ ] **The feature is on `main`.** GitHub loads a `pull_request_target` workflow from the repository's default branch, and this repository's is `main` while pull requests target `develop`. The workflow does not fire from the implementation branch or from `develop`, so this runbook cannot be run before the release that merges it into `main`. Confirm with `git ls-remote origin refs/heads/main` and check that `.github/workflows/closing-keyword-scope.yml` exists at that commit.
- [ ] `gh` is authenticated against `lhpaul/ai-dev-framework-template` with permission to open and close pull requests.
- [ ] You can see the repository's Actions runs, to read a workflow log when a step says to.
- [ ] Do **not** delete the `multi-issue-intentional` label if the repository already has it. Label provisioning is repository-wide shared state, and this runbook never destroys it to create a test condition. Provisioning is covered by the unit suite against a stubbed API instead — see Step 4.

---

## Test Data

| Item | Value |
| --- | --- |
| Scratch issue | An open issue used only for this test — record its number as `<ISSUE>` |
| Owner pull request | Branch `fix/<ISSUE>-smoke-owner`, description says nothing about closing |
| Claimant pull request | Branch `fix/999999-smoke-claimant`, description declares `Closes #<ISSUE>` |
| Opt-out label | `multi-issue-intentional` |
| Report location | A comment on the claimant pull request |

Both pull requests target `develop`. Both are drafts, so no reviewer loop runs
against them.

---

## Smoke Test Steps

### Step 0: Create the scratch issue

- Open an issue titled `smoke test for #1644 — safe to close`.
- Record its number as `<ISSUE>`.

### Step 1: Open the claimant with no sibling

- Create branch `fix/999999-smoke-claimant` from `develop` with one trivial commit.
- Open a **draft** pull request whose description contains `Closes #<ISSUE>`.
- **Expected**: no comment is posted. Ownership is unestablished — no open pull request's branch names `<ISSUE>` — and absence of evidence is not a warning.

### Step 2: Open the owner, and watch the claimant change on its own

- Create branch `fix/<ISSUE>-smoke-owner` from `develop` with one trivial commit.
- Open a **draft** pull request from it. Its description declares nothing.
- **Expected**: within a workflow run, the **claimant** pull request — untouched — gains a comment naming `<ISSUE>` and pointing at the owner pull request by number.
- This is the sibling fan-out: the event happened on the owner, the write happened on the claimant.

### Step 3: Correct the claimant

- Edit the claimant's description to remove the `Closes #<ISSUE>` line.
- **Expected**: the existing comment is cleared or updated to a clean state. There is not a second comment.

### Step 4: Exercise the opt-out

- Restore `Closes #<ISSUE>` in the claimant's description and wait for the warning to return.
- Apply the `multi-issue-intentional` label to the claimant.
- **Expected**: the warning clears with no push to the pull request.
- Remove the label.
- **Expected**: the warning returns, again with no push.

**Provisioning is not tested here.** Two reasons, both structural rather than
preference: the label is repository-wide state that this runbook must not
destroy to create a test condition, and Step 1 already ran the validation, so
by this point the label may exist because of *this run* — which makes any
observation here unable to distinguish first-use creation from an earlier one.
The `label_created_on_first_use` and `concurrent_creation_does_not_fail` unit
tests cover it against a stubbed API, where the starting state is controlled.

### Step 5: Filtering follows the base branch

- Edit the claimant's **title** so it ends with an unclosed triple-backtick fence.
- **Expected**, with the base still `develop` (not the default branch): the warning clears, because the cleanup that would close the issue reads title and description as one text and the fence suppresses the reference.
- Retarget the claimant to the repository's default branch.
- **Expected**: the warning returns, because the platform closes from the description alone and never saw the title.
- Retarget it back to `develop` and remove the fence from the title.

### Step 6: Contested ownership is silent

- Create a second owner branch `fix/<ISSUE>-smoke-owner-2` and open a draft pull request from it.
- **Expected**: the claimant's warning clears. Two open pull requests name `<ISSUE>`, so ownership is contested and guessing an owner is the mistake this feature exists to catch.
- Close the second owner.
- **Expected**: the warning returns.

### Step 7: The check run is published and never blocks

- On the claimant pull request from Step 2, open the checks list.
- **Expected**: a check named `Closing-keyword scope` is present on the head commit, written by this workflow, and the pull request's mergeability is unchanged by it.
- Merge-block check: confirm the pull request is not held by this check in the merge box.
- **Expected**: it is not. This is the assertion that matters live — it is the first check run this repository writes, so `checks: write` working at all, and a non-`success` conclusion not blocking a merge, are both things only a real run can show.

**What this step deliberately does not do.** The *indeterminate* path — an unreadable input producing a `neutral` conclusion with the existing report left untouched — is **unit-only**, and the unit suite covers it across every gate input. Forcing it live would mean either reducing the workflow's permissions, which is a change to the default-branch workflow and outside what a smoke runbook should do to a shared repository, or invoking the validator with `--publish` by hand, which the design forbids: only the serialized workflow job publishes, and that rule is what makes the ordering guarantee hold. Neither is worth breaking for a live re-proof of behaviour the unit suite already asserts.

If a live proof is ever wanted, the way is a deliberate, reviewed pull request to `main` that lowers the workflow's `pull-requests` permission, observed and then reverted. That is a maintainer decision, not a runbook step.

### Last Step: Validate & shut down

- Close all scratch pull requests and delete their branches.
- Close the scratch issue.
- Leave the `multi-issue-intentional` label in place. It is repository-wide state and a real opt-out authors may need; this runbook neither created a condition by deleting it nor removes it afterwards.
- Confirm `develop` was not modified by any step.

---

## Assertions Checklist

- [ ] A claimant with no sibling is silent (Step 1).
- [ ] A warning appears on the claimant when the owner opens, with no change to the claimant (Step 2).
- [ ] The warning names the issue number and the sibling pull request (Step 2).
- [ ] Correcting the description clears the warning and leaves a single comment, not two (Step 3).
- [ ] Applying and removing the label works against a repository that already has it (Step 4). First-use creation is asserted by the unit suite, not here — see the note in Step 4.
- [ ] Applying the label clears the warning with no push; removing it restores the warning with no push (Step 4).
- [ ] An unclosed fence in the title suppresses the reference for a `develop`-targeting pull request, and does not for one targeting the default branch (Step 5).
- [ ] Retargeting between the default branch and `develop` re-evaluates the pull request (Step 5).
- [ ] Two owners make the result silent; closing one restores the warning (Step 6).
- [ ] An unreadable input leaves the existing comment untouched and posts nothing (Step 7).
- [ ] An indeterminate run leaves a neutral, non-blocking check and never a failing one (Step 7).
- [ ] A conclusive re-run replaces the neutral check, including when it is silent (Step 7).
- [ ] No step changed an issue's milestone, closed an issue, or altered any pull request's mergeability.

---

## Seed Data Reference

No database seed data. The test data is the scratch issue and the throwaway
pull requests created in the steps above; the branch names carry the ownership
signal the feature reads.

---

## Troubleshooting

| Symptom | Likely cause | What to check |
| --- | --- | --- |
| No comment appears in Step 2 | The sibling fan-out did not run | The workflow run for the **owner** pull request's `opened` event; it is the run that writes to the claimant |
| A second comment appears instead of an update | The existing report could not be read, so the run treated it as absent | The run log — an unreadable existing report should have produced an indeterminate outcome, not a duplicate |
| The neutral check never appears | The workflow lacks `checks: write` | The workflow's `permissions:` block. This is the repository's first check-run writer |
| The warning does not clear after applying the label | The label event did not trigger a run, or the label could not be read | The workflow's `pull_request_target` types include `labeled` and `unlabeled`; then the run log |
| A rename does not re-evaluate anything | Expected — see Known Limitations | Nothing to fix |

---

## Known Limitations

These are out of scope in the spec, not defects (alignment decision, option B; the spec was amended in #1703):

- **Renaming a pull request's own head branch, or a sibling's, does not re-evaluate anything.** GitHub Actions has no `renamed` activity type for pull requests. The result is corrected at the next event that does fire — an edit, a label change, or readiness — and if none fires, not at all: the delay is not bounded, which the spec's *Out of Scope* entry states.
- **Changing the repository's default branch does not re-evaluate open pull requests.** GitHub Actions has no event for it. Each pull request keeps the filtering its base implied until its next event.
- **Fork-originated pull requests are never validated**, by design: the repository forbids automated writes on them.

None of these is a correctness gap in the validation itself — invoking the
validator after any of them produces the right answer, and the unit suite
asserts that. What is out of scope is the automatic invocation.
