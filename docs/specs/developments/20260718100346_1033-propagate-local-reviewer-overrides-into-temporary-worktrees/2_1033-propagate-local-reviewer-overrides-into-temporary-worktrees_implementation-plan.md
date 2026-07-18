# Local Reviewer Override Continuity - Implementation Plan

**Spec**: `1_1033-propagate-local-reviewer-overrides-into-temporary-worktrees_specs.md`
**Smoke test runbook**: `docs/testing/workflow/1033-local-reviewer-override-continuity.smoke-test.md`

## Summary

**Approach**: Carry an initiating checkout's resolved local reviewer context into
temporary-worktree reviewer execution without copying the local configuration
file. Preserve field-level resolution so unspecified local fields continue to
use the shared policy.

**Estimated complexity**: M

**Rationale**: The review loop and its configuration helpers need a private,
explicit source context plus regression coverage for both local and shared paths.

**Dependencies**: None

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `2280735` |
| Local resolution | `workflow-config-resolver.py review-overrides` | Local overrides resolve from the current repo root only |
| Review-loop path | `rg -n 'WORKFLOW_APPLY_LOCAL_REVIEW_OVERRIDES' scripts/development-workflow` | The loop resolves a temporary target-branch config and needs initiator context |

## Layer-by-Layer Changes

### Shared Packages / Libraries

- [ ] Extend `scripts/development-workflow/workflow-lib.sh` with a
  caller-supplied, read-only local-override source context that resolves only
  the local policy fields and leaves unspecified values on the shared policy.
- [ ] Keep source reporting explicit and redact local paths/configuration
  contents from PR-visible output.

### Infrastructure / Configuration

- [ ] Update `scripts/development-workflow/pr-review-loop.sh` to capture the
  initiating context before temporary worktree/target-branch execution and use
  it for draft and ready reviewer policy resolution.
- [ ] Preserve existing availability handling when no local override exists or
  when the resolved policy cannot be used.

## Testing Strategy

**Test types**: Shell harness and smoke test.

1. A partial local override retains shared reviewer choices not overridden (AC1).
2. A temporary configuration uses the initiating effective policy (AC1, AC4).
3. An unavailable effective policy does not silently fall back (AC2).
4. No local override uses the shared path unchanged (AC3).
5. Local settings never appear in tracked output (AC5) and existing gates stay
   unchanged (AC6).

## Seed Data

None; harness fixtures provide temporary configuration only.

## Documentation Updates

- [ ] `docs/workflow/development-workflow/provider-contingency-runner-failover.md` — document the effective-policy source and unavailable-policy handling.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Partial override drops shared reviewers | Medium | High | Add field-level merge fixture and assert the complete effective policy. |
| Local configuration leaks | Low | High | Pass source context transiently and assert PR-visible output is redacted. |

## Implementation Order

1. Add the read-only initiating override-source contract in the shared helper.
2. Thread it through reviewer-loop temporary configuration resolution.
3. Add harness fixtures for partial override, absent override, unavailable policy, and redaction.
4. Update failover documentation and the smoke runbook.
5. Run the focused harness, shell syntax/static checks, Markdown lint, and the smoke runbook.
6. Update `CHANGELOG.md` under `[Unreleased]` with `**Preserve local reviewer overrides** (#1033): ...`.
