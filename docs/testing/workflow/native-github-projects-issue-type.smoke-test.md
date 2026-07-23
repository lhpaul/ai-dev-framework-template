# Smoke Test Runbook: Native GitHub Issue Type Classification

**Feature**: Native GitHub Issue Type Classification
**Spec**: [Native GitHub Issue Type Classification](../../specs/developments/20260723110048_1280-native-github-projects-issue-type/1_1280-native-github-projects-issue-type_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Check out the implementation branch for issue #1280.
- [ ] Confirm the In Development stage has added the native Issue Type fixtures
      and named assertions specified by the implementation plan; this Plan Ready
      runbook is not executable against the implementation-plan branch alone.
- [ ] Ensure Bash, Python 3, `jq`, and ShellCheck are available.
- [ ] Confirm no live GitHub Project mutation is required; the regression
      harness uses a mocked `gh` command and deterministic GraphQL responses.

## Test Data

| Item | Value |
| --- | --- |
| Test issue | Mock issue `#824` in project `PVT_project_1` |
| Configured field | Optional `Configured Type` fixture |
| Native source | `content.issueType.name` fixture |
| Custom sources | `Custom Type`, `CustomType`, and `Type` fixtures |

## Smoke Test Steps

### Step 1: Run the focused GitHub Projects regression harness

**Maps to**: AC-1 through AC-8

1. From the repository root, run:

   ```bash
   bash scripts/development-workflow/tests/test-workflow-lib-github-projects.sh
   ```

2. Confirm the harness exits successfully.
3. Confirm its native Issue Type assertions report `PASS`.
4. Confirm the existing GitHub Projects helper assertions remain green.

**Expected result**: The focused harness passes without calling a live GitHub
Project or reporting a regression in existing custom-field behavior.

### Step 2: Verify native-only classification and warning behavior

**Maps to**: AC-1, AC-2

1. In the harness output, locate the assertion for a project item whose custom
   fields are empty and whose native Issue Type is `Feature`.
2. Confirm the resolved type assertion reports `Feature`.
3. Confirm the paired stderr assertion reports that the existing
   missing-Type warning was not emitted.
4. Confirm the query-recording assertion proves the GraphQL request included
   `issueType`.

**Expected result**: Native `Feature` is returned from the real targeted-query
path represented by the mock, and it is treated as classified rather than
missing.

### Step 3: Verify the complete precedence chain

**Maps to**: AC-3, AC-4, AC-5

1. Confirm the configured-over-native assertion passes when configured,
   native, and custom sources contain different names.
2. Confirm the native-over-custom assertion passes when the configured source
   is empty.
3. Confirm the custom fallback assertions pass in this order when higher
   sources are empty:
   `Custom Type`, `CustomType`, then `Type`.

**Expected result**: Every precedence boundary selects the first non-empty
candidate in the configured → native → `Custom Type` → `CustomType` → `Type`
order.

### Step 4: Verify null, absent, and defensive fallback behavior

**Maps to**: AC-6

1. Confirm fixtures with absent or null native Issue Type return the first
   available custom value.
2. Confirm an empty native name does not stop fallback.
3. Confirm a non-object `content` value does not crash the parser and still
   permits custom fallback.
4. Confirm a native type on an item from another project is ignored.

**Expected result**: Unusable native content is equivalent to no native value,
and only the configured project's item can classify the issue.

### Step 5: Verify the genuinely unclassified path

**Maps to**: AC-7

1. Locate the all-sources-empty fixture assertion.
2. Confirm the helper returns an empty type.
3. Confirm stderr still contains the existing missing-Type warning.

**Expected result**: The feature does not invent a default or suppress the
warning for genuinely unclassified items.

### Step 6: Run shell quality checks

**Maps to**: AC-8

1. Run:

   ```bash
   shellcheck scripts/development-workflow/workflow-lib.sh \
     scripts/development-workflow/tests/test-workflow-lib-github-projects.sh
   python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop
   ```

2. Confirm both commands exit successfully.

**Expected result**: The helper and its harness satisfy the repository's shell
quality gates.

### Last Step: Validate & Shut Down

- Verify all assertions in the checklist below are met.
- No server, temporary issue, or live project resource requires cleanup.

## Assertions Checklist

- [ ] AC-1: Native Issue Type `Feature` resolves to `Feature`.
- [ ] AC-2: Native-only classification emits no missing-Type warning.
- [ ] AC-3: Configured classification wins over native Issue Type.
- [ ] AC-4: Native Issue Type wins over conventional custom fields.
- [ ] AC-5: Existing custom precedence remains `Custom Type`, `CustomType`,
      then `Type`.
- [ ] AC-6: Null, absent, empty, or unusable native content falls back without
      error.
- [ ] AC-7: Fully missing classification returns empty and preserves the
      warning.
- [ ] AC-8: Automated regression and shell quality checks pass.

## Seed Data Reference

No persistent seed data is required. The focused shell harness creates all
GraphQL response fixtures in a temporary mock directory and removes them on
exit.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| A native assertion is absent | The implementation did not add the planned regression cases | Compare the harness against the plan's Testing Strategy and add the missing named case |
| Native-only resolution is empty | The GraphQL selection or parser candidate is missing | Confirm the recorded query includes `issueType` and inspect native candidate extraction |
| Custom precedence changed | Native was inserted at the wrong candidate boundary | Restore configured → native → `Custom Type` → `CustomType` → `Type` |
| Harness tries to contact GitHub | The mock `gh` path was not initialized or was bypassed | Run the harness from the repository root and inspect its mock setup |
| Shell guard reports added-line findings | New shell code violates workflow guard rules | Correct the reported construct; do not suppress the guard |

## Known Limitations

- The deterministic harness validates the GraphQL response contract without
  requiring an organization that has native Issue Types enabled.
- It does not mutate or verify native Issue Type configuration through GitHub's
  UI or API because native-type writes are outside issue #1280.
