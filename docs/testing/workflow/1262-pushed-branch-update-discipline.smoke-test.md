# Smoke Test Runbook: Pushed Branch Update Discipline

**Feature**: Pushed Branch Update Discipline
**Spec**: `docs/specs/developments/20260718100346_1262-avoid-amending-pushed-pr-branches/1_1262-avoid-amending-pushed-pr-branches_specs.md`

## Prerequisites

- [ ] A clean checkout of the implementation branch.

## Smoke Test Steps

1. Read the version-control guidance after locating the published-branch rule.
   **Expected result**: it requires a follow-up commit for a correction after a
   branch is pushed for review and distinguishes unpublished local amendments.
2. Read the failover recovery guidance.
   **Expected result**: it refers to the same no-force-push recovery rule.

## Assertions Checklist

- [ ] AC1–AC4: Published-branch guidance is clear, safe, and consistent.
- [ ] AC5: No merge, CI, or branch-protection behavior is changed.

## Known Limitations

- This documentation-only runbook does not perform a force-push.
