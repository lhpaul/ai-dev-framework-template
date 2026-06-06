# Smoke Test Runbook: Tracker Type Field Classification

**Feature**: Tracker Type field classification
**Spec**: Refactor work item #828 brief
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] `gh` is authenticated for the repository and project owner.
- [ ] `.ai-dev-workflow.yaml` uses `issue_tracker.provider: github_projects`.
- [ ] The configured GitHub Project has a `Type` single-select field with
      `Feature`, `Bug`, `Refactor`, and `Workflow` options.
- [ ] The local branch includes the implementation for #828.

## Test Data

| Item | Value |
| --- | --- |
| Temporary workflow issue | Created during the smoke test, then closed |
| Temporary bug issue | Created during the smoke test, then closed |
| Project number | Value from `.ai-dev-workflow.yaml` or `GITHUB_PROJECT_NUMBER` |

## Smoke Test Steps

### Step 1: Create temporary issues without classification labels

1. Create one temporary issue whose project Type will be set to `Workflow`.
2. Create one temporary issue whose project Type will be set to `Bug`.
3. Add both issues to the configured project board.
4. Confirm neither issue has `workflow`, `bug`, `enhancement`, or `type:*`
   classification labels.

**Expected result**: Both temporary issues exist on the board without retired
classification labels.

### Step 2: Set project Type values

1. Set the first temporary issue's project Type to `Workflow`.
2. Set the second temporary issue's project Type to `Bug`.
3. Read each issue back through the workflow helper or documented GraphQL query.

**Expected result**: The first issue reports Type `Workflow`; the second reports
Type `Bug`.

### Step 3: Verify Workflow Type discovery

1. Run the Workflow Type discovery helper or the documented equivalent command.
2. Confirm the output includes the temporary Workflow issue.
3. Confirm the output does not include the temporary Bug issue.

**Expected result**: Workflow discovery is based on project Type, not labels.

### Step 4: Verify Backlog route classification

1. Run the orchestrator or next-action classification path against the temporary
   Bug issue.
2. Confirm the issue is treated as a fast-track bug/fix candidate based on Type.
3. Run the workflow discovery path against the temporary Workflow issue.
4. Confirm it remains discoverable as workflow-framework work without the
   `workflow` label.

**Expected result**: Type values drive classification and routing.

### Step 5: Verify operational labels are unchanged

1. Inspect an implementation PR or test PR using `ready-for-human-review`,
   `ready-for-regression`, and `needs-fixes`.
2. Confirm the implementation did not remove or replace these operational labels.

**Expected result**: Operational PR labels still exist and continue to drive
review/CI behavior.

### Last Step: Cleanup

- Close the temporary issues.
- Remove them from the project board if desired.
- Verify no temporary classification labels were created.

## Assertions Checklist

- [ ] Workflow issue discovery works through project Type `Workflow`.
- [ ] Bug/fix routing works through project Type `Bug`.
- [ ] Retired classification labels are not required for the tested flows.
- [ ] Operational labels remain unchanged.
- [ ] Temporary issues are closed or cleaned up after the test.

## Seed Data Reference

No persistent seed data is required. The smoke test creates temporary GitHub
issues and closes them before completion.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Type option cannot be set | Project Type field is missing the option | Add `Workflow`, `Bug`, `Feature`, and `Refactor` options in project settings |
| Discovery returns no Workflow issues | Helper is still filtering by label or the issue is not on the board | Confirm the issue is on the board and inspect the helper query |
| Temporary issue still has `workflow` label | Test setup copied an older command | Remove the label and rerun setup using Type-only classification |

## Known Limitations

- This smoke test requires write access to the configured GitHub Project.
- The cleanup step may leave closed test issues visible in GitHub history.
