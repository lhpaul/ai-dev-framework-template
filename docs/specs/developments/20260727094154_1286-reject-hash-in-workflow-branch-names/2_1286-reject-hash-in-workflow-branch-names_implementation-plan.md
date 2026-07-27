# Reject Unsafe Generated Workflow Branch Names - Implementation Plan

**Spec**: [branch-name validation spec](1_1286-reject-hash-in-workflow-branch-names_specs.md)
**Smoke test runbook**: [workflow branch-name validation](../../../testing/workflow/1286-reject-unsafe-workflow-branch-names.smoke-test.md)

---

## Summary

**Approach**: Add one Bash-3.2-compatible branch-name validator, invoke it at
the workflow branch-creation and pre-push boundaries, and make the canonical
protocol guidance show compliant names and a non-destructive recovery path.

**Estimated complexity**: M

**Rationale**: The behavior is small, but it is cross-cutting workflow tooling:
the guard, protocol instructions, tests, and tool-specific mirrors must agree.

**Dependencies**: None.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `99b8e73` |
| Existing unsafe example | `rg -n -F 'fix/#' .` | No checked-in example; the issue is the incident source. |
| Existing validator | `sed -n '1,120p' scripts/development-workflow/check-workflow-branch.sh` | Checks existence only; no naming-policy validation. |
| Reuse validation | `rg -n 'invalid workflow branch name' scripts/development-workflow/validate-branch-reuse.sh` | Rejects empty/whitespace values but does not enforce the unsafe-character convention. |
| Existing test coverage | `rg -n -i 'branch.*(valid|invalid|validate|reject)' scripts/development-workflow/tests` | Reuse tests cover whitespace but not hash-bearing workflow names. |

## Layer-by-Layer Changes

### Workflow validation

- [ ] Add `scripts/development-workflow/validate-workflow-branch-name.sh` with
  a single input branch name, accepted workflow prefixes, and a deterministic
  rejection for `#`, `?`, `^`, `~`, `:`, backslash, and spaces.
- [ ] Emit a non-zero result that identifies the rejected name, explains the
  convention, and shows a bare-numeric example such as `fix/1858-slug`.
- [ ] Keep Git ref syntax validation distinct from workflow convention
  validation; callers must receive a clear workflow-policy failure before push.

### Workflow entry points and guidance

- [ ] Invoke the new validator before branch creation and before push in the
  full-pipeline, refactor, fast-track, and hotfix branch instructions in
  `03-implement-development-protocol.md`.
- [ ] Add the same pre-creation validation requirement to the spec and plan
  protocol branch steps, where tracked stage branches are constructed.
- [ ] Update Protocol 91's creator-dispatch branch guard so resumed and fresh
  runner paths share the validation boundary.
- [ ] Update the Codex and Claude/Cursor creator guidance that mirrors those
  branch instructions; use the bare issue number in all examples.
- [ ] Add recovery guidance: preserve the original branch, create and push a
  compliant replacement branch through the normal PR path, verify checks start,
  and never force-push shared history.

### Tests

- [ ] Add a focused Bash test harness for the validator.
- [ ] Cover valid `spec/`, `implementation-plan/`, `feature/`, `fix/`,
  `refactor/`, and `hotfix/` issue-prefixed names.
- [ ] Cover each unsafe character, especially hash-bearing names, and assert
  the corrective example is present.
- [ ] Preserve existing reuse-validation whitespace coverage; add only the
  integration assertion needed to prove creator paths call the new guard.

## Testing Strategy

**Test types**: Focused Bash unit harness, existing workflow shell lint, and
manual smoke evidence.

**Key scenarios**:

1. Valid issue-prefixed workflow names pass (AC1, AC6, AC7).
2. A hash-bearing name fails before a branch/push command and provides a
   compliant replacement (AC2, AC4, AC5, AC7).
3. Every other listed unsafe character fails at the same boundary (AC3).
4. Recovery instructions create a replacement branch without force-push and
   checks appear for the replacement PR (AC8).

**Smoke test runbook**: `docs/testing/workflow/1286-reject-unsafe-workflow-branch-names.smoke-test.md`

### Parser-risk addendum

The validator is parser-risk because it scans branch-name text. Unit cases will
cover each boundary character, a valid lookalike branch, repeated unsafe
characters, and prefix/issue-number formatting. Suppressions do not apply.

## Seed Data

No database or application seed data is required. Test fixtures use temporary
repository branches and string inputs only.

## Documentation Updates

- [ ] `AGENTS.md` — add the branch-convention rule and recovery reference if
  the existing branch table remains the user-facing canonical location.
- [ ] `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md`
  — require validation before tracked spec branch creation.
- [ ] `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`
  — require validation before tracked plan branch creation.
- [ ] `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`
  — require validation before implementation branch creation/push and document recovery.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
  — include the guard in creator dispatch and branch reuse guidance.
- [ ] `.agents/skills/run-item/SKILL.md`, `.codex/skills/workflow-implementer/SKILL.md`,
  `.claude/agents/developer.md`, and `.cursor/agents/developer.md` — keep branch guidance aligned where it is duplicated.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Guard rejects legitimate names | Low | Medium | Restrict it to documented workflow prefixes and test accepted forms. |
| A branch path bypasses the guard | Medium | High | Enumerate every creator path and add an integration assertion. |
| Guidance drifts across tools | Medium | Medium | Update the canonical protocols and all identified mirrors together. |

## Implementation Order

1. Implement the isolated validator and its focused test harness.
2. Run the new harness and ShellCheck before wiring callers.
3. Add guard invocation to branch-creation/push paths and Protocol 91.
4. Update mirrored agent/skill guidance and recovery documentation.
5. Add integration assertions that the changed paths invoke the guard.
6. Run focused tests, `shellcheck`, `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`, Markdown lint, and `git diff --check`.
7. Execute the smoke runbook and confirm valid names proceed while unsafe names stop before a push.
8. Update `CHANGELOG.md` under `[Unreleased]` during the implementation PR with `- **Reject unsafe workflow branch names** (#1286): prevent invalid generated workflow branches before push.`
