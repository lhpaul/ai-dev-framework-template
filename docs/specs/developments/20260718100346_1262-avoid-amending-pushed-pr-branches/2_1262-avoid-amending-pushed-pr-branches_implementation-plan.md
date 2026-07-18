# Pushed Branch Update Discipline - Implementation Plan

**Spec**: `1_1262-avoid-amending-pushed-pr-branches_specs.md`
**Smoke test runbook**: `docs/testing/workflow/1262-pushed-branch-update-discipline.smoke-test.md`

## Summary

**Approach**: Add one canonical version-control rule for already-published PR
branches, then cross-reference it from delegated-review recovery guidance.

**Estimated complexity**: S

**Rationale**: Documentation-only change across two existing workflow surfaces.

**Dependencies**: None

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `2280735` |
| Existing guidance | `rg -n -i 'force-push|amend.*published' docs .codex scripts` | Existing no-force-push and recovery guidance lacks the follow-up-commit rule |

## Layer-by-Layer Changes

### Infrastructure / Configuration

- [ ] Update `docs/best-practices/2-version-control.md` with the canonical
  distinction between unpublished amendments and corrections after a PR branch
  is published; require focused follow-up commits in the latter case.
- [ ] Update `docs/workflow/development-workflow/provider-contingency-runner-failover.md`
  to point recovery work to the canonical rule and prohibit force-push recovery.

## Testing Strategy

**Test types**: Documentation smoke test and Markdown lint.

1. Verify the canonical guidance explicitly covers AC1–AC4.
2. Verify no guidance changes merge, CI, or branch-protection authority (AC5).

## Seed Data

None; this change has no runtime data.

## Documentation Updates

- [ ] `docs/best-practices/2-version-control.md` — add the canonical rule.
- [ ] `docs/workflow/development-workflow/provider-contingency-runner-failover.md` — align recovery instructions.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Guidance contradicts an existing rule | Low | Medium | Cross-reference the canonical version-control wording and lint both files. |

## Implementation Order

1. Add the canonical published-branch update rule and unpublished/local distinction.
2. Align failover recovery guidance with that rule.
3. Add the smoke runbook and run Markdown lint.
4. Update `CHANGELOG.md` under `[Unreleased]` with `**Clarify pushed branch updates** (#1262): ...`.
