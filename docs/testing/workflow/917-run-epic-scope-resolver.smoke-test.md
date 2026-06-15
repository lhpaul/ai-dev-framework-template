# Smoke Test Runbook: Run Epic Scope Resolver

**Feature**: Run Epic Scope Resolver
**Spec**: [1_917-run-epic-scope-resolver_specs.md](../../specs/developments/20260612124828_917-run-epic-scope-resolver/1_917-run-epic-scope-resolver_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are reviewing the implementation PR for #917.
- [ ] The PR targets `develop-delegated-epic-orchestration`.
- [ ] The implementation diff is available locally.
- [ ] No live GitHub mutation is required; fixture tests use stubbed `gh`
      responses.

---

## Test Data

| Item | Value |
| --- | --- |
| Resolver helper | `scripts/development-workflow/run-epic-scope-resolver.sh` |
| Resolver tests | `scripts/development-workflow/tests/test-run-epic-scope-resolver.sh` |
| Installer tests | `scripts/development-workflow/tests/test-install-codex-skills.sh` |
| Resolver protocol | `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` |
| Claude command | `.claude/commands/run-epic.md` |
| Cursor command | `.cursor/commands/run-epic.md` |
| Codex alias | `.agents/skills/run-epic/SKILL.md` |

---

## Smoke Test Steps

### Step 1: Verify Epic Scope Resolution

**Maps to**: AC1, AC10

1. Run the resolver fixture test harness.
2. Inspect the native sub-issue fixture cases.
3. Confirm the test covers all sub-issue pages before producing an execution
   set.
4. Confirm the no-sub-issues fixture reports the condition clearly.

**Expected result**: Epic resolution lists every resolved child item with
workflow state and does not silently treat an empty epic as a single-item set.

### Step 2: Verify Explicit Item Scope

**Maps to**: AC2

1. Inspect the explicit item-list fixture cases.
2. Confirm the resolver reports only listed items.
3. Confirm duplicate items are normalized without adding siblings, parent
   issues, label-matched issues, or milestone-matched issues.

**Expected result**: Explicit item lists are a hard scope boundary.

### Step 3: Verify Base Branch Inference

**Maps to**: AC3, AC4, AC5, AC6

1. Inspect fixture cases for a supplied base override.
2. Inspect fixture cases where all items share one
   `integration-branch:<slug>` label.
3. Inspect fixture cases where no item has an integration branch.
4. Inspect fixture cases where items have conflicting integration branch labels.

**Expected result**: The resolver uses the supplied base first, then a shared
integration branch, then `develop`; conflicting labels without an override are
reported as ambiguous.

### Step 4: Verify Execution Grouping

**Maps to**: AC7

1. Inspect fixture items for eligible, blocked, already merged, in review,
   ambiguous, and out-of-scope states.
2. Confirm every resolved item appears in exactly one group.
3. Confirm human-readable output and JSON output use the same group names.

**Expected result**: Grouping is complete, stable, and readable.

### Step 5: Verify Read-Only Behavior

**Maps to**: AC8, AC9

1. Inspect the resolver helper for `gh` and `git` command usage.
2. Confirm the fixture test fails if the resolver invokes mutating commands
   such as issue edit, project item edit, PR creation, PR merge, branch
   creation, issue close, or GraphQL mutation.
3. Confirm the resolver output includes a read-only guarantee.

**Expected result**: Resolver-only runs do not mutate tracker, branch, PR, or
issue state.

### Step 6: Verify Command Surfaces

**Maps to**: AC1 through AC10

1. Open the Claude, Cursor, and Codex command wrappers.
2. Confirm each wrapper points to the resolver protocol.
3. Run the installer test harness.
4. Confirm `run-epic` is included in real-repo command alias coverage.

**Expected result**: All supported agent surfaces expose the resolver command
without redefining behavior outside the protocol.

### Step 7: Run Automated Validation

**Maps to**: AC1 through AC10

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-run-epic-scope-resolver.sh
   bash scripts/development-workflow/tests/test-install-codex-skills.sh
   npx markdownlint-cli2 "docs/workflow/development-workflow/**/*.md" "docs/testing/workflow/917-run-epic-scope-resolver.smoke-test.md" "AGENTS.md"
   ```

2. Confirm all commands pass.

**Expected result**: Resolver behavior, alias installation, and documentation
formatting are validated.

---

## Assertions Checklist

- [ ] AC1: Epic resolver reports each native sub-issue with title, Status,
      Type, Priority, dependency state, labels, linked PR state, and issue
      state.
- [ ] AC2: Explicit item-list resolver reports only listed items.
- [ ] AC3: Supplied base override controls the execution-set base branch.
- [ ] AC4: Shared integration-branch label infers `develop-<slug>`.
- [ ] AC5: No integration-branch label infers `develop`.
- [ ] AC6: Conflicting base signals produce an ambiguous execution set.
- [ ] AC7: Every resolved item is grouped as eligible, blocked, already merged,
      in review, ambiguous, or out of scope.
- [ ] AC8: Resolver-only runs do not start Backlog items, update tracker
      status, create branches, open PRs, merge PRs, close issues, or delete
      branches.
- [ ] AC9: Resolver output includes a read-only guarantee.
- [ ] AC10: Epic with no resolvable native sub-issues reports that condition
      clearly.

---

## Seed Data Reference

No persistent seed data is required. Fixture tests provide stubbed GitHub issue,
Project, PR, label, and sub-issue responses.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Resolver cannot classify Project fields | Stub or live issue is missing Project item data | Report missing fields and avoid legacy-label classification when Project fields are available. |
| Resolver includes unlisted sibling items | Explicit item-list path reused epic or label expansion | Keep explicit item-list resolution isolated from parent, sibling, label, and milestone discovery. |
| Resolver mutates tracker or PR state | Helper used a mutating `gh` call | Replace with read-only API calls and add the command to the no-mutation fixture guard. |
| Markdown links fail lint | Relative link depth is wrong | Run `markdownlint-cli2` and fix the link from the file's directory. |

---

## Known Limitations

- The resolver is read-only. It does not start Backlog items, triage review
  findings, classify merge risk, merge PRs, or write audit comments.
- Label, milestone, and integration-branch-only scope inputs are deferred to
  later `/run-epic` work.
