# Smoke Test Runbook: Local Reviewer Override Continuity

**Feature**: Local Reviewer Override Continuity
**Spec**: `docs/specs/developments/20260718100346_1033-propagate-local-reviewer-overrides-into-temporary-worktrees/1_1033-propagate-local-reviewer-overrides-into-temporary-worktrees_specs.md`

## Prerequisites

- [ ] Run the reviewer-loop harness with its local-override fixtures.

## Smoke Test Steps

1. Run the fixture with a partial initiating local override and a temporary
   worktree configuration.
   **Expected result**: the temporary execution uses the complete effective
   policy, retaining applicable shared reviewer choices.
2. Run the fixture without a local override.
   **Expected result**: shared-policy behavior is unchanged.
3. Run the unavailable-effective-policy fixture.
   **Expected result**: the existing stop/warning behavior is used and no
   different reviewer is substituted silently.
4. Inspect generated output.
   **Expected result**: it names the policy source but contains no local
   configuration content or local path.

## Assertions Checklist

- [ ] AC1–AC4: Effective reviewer policy is preserved and visible safely.
- [ ] AC5: Local configuration is not tracked or exposed.
- [ ] AC6: Existing review, CI, tracker, and merge gates remain unchanged.

## Known Limitations

- This runbook uses harness fixtures rather than a disposable live PR.
