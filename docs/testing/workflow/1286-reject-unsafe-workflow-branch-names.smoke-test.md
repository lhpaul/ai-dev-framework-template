# Smoke Test Runbook: Reject Unsafe Workflow Branch Names

**Feature**: Reject unsafe generated workflow branch names
**Spec**: [branch-name validation spec](../../specs/developments/20260727094154_1286-reject-hash-in-workflow-branch-names/1_1286-reject-hash-in-workflow-branch-names_specs.md)
**Created in**: Plan Ready stage

---

## Prerequisites

- [ ] Run from a clean clone with Bash, Git, and the workflow scripts available.
- [ ] Do not use an existing shared branch as a test target.

## Smoke Test Steps

### Step 1: Accept compliant names

1. Run the validator for representative `spec/1858-safe-name`,
   `implementation-plan/1858-safe-name`, `feature/1858-safe-name`,
   `fix/1858-safe-name`, `refactor/1858-safe-name`, and
   `hotfix/1858-safe-name` inputs.
2. Verify: every command exits successfully without requiring manual approval.

### Step 2: Reject unsafe names before push

**Maps to**: Acceptance Criteria 2-5 and 7.

1. Run the validator with `fix/#1858-safe-name`.
2. Verify: it fails, names the convention failure, and suggests
   `fix/1858-safe-name`.
3. Repeat for `?`, `^`, `~`, `:`, backslash, and space variants.
4. Verify: no branch creation, push, or PR command is attempted after a
   rejection.

### Step 3: Verify recovery guidance

**Maps to**: Acceptance Criterion 8.

1. Start with a non-compliant local branch containing a harmless committed change.
2. Follow the documented recovery path to create a compliant replacement branch.
3. Verify: the original branch is preserved, no force-push is used, and the
   replacement branch can enter the normal review workflow.

## Assertions Checklist

- [ ] Bare numeric tracker identifiers are used in generated workflow branches.
- [ ] Every listed unsafe character is rejected before push.
- [ ] The rejection supplies a compliant correction.
- [ ] Valid workflow names remain accepted.
- [ ] Recovery preserves shared history and restores normal check triggering.

## Known Limitations

- This runbook verifies repository convention enforcement; it does not claim
  every unsafe character has identical behavior in every GitHub webhook path.
