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

**Consumer-mode fixture** (`template.is_template` absent, `false`, or an
unrecognized value in `.ai-dev-workflow.yaml`) — this template repository
itself is framework mode and refuses `--type Workflow` on creation (#1583),
so Steps 1–2 below must run against a consumer-mode repository or fixture.

1. Create one temporary issue and plan to set its project Type to `Workflow`.
2. Create one temporary issue and plan to set its project Type to `Bug`.
3. Add both issues to the configured project board.
4. Confirm neither issue has `workflow`, `bug`, `enhancement`, or `type:*`
   classification labels.

**Expected result**: Both temporary issues exist on the board without retired
classification labels.

### Step 2: Set project Type values

1. Set the first temporary issue's project Type to `Workflow`.
2. Set the second temporary issue's project Type to `Bug`.
3. Read each issue back through the workflow helper:

   ```bash
   bash -lc "source scripts/development-workflow/workflow-lib.sh; update_tracker_type_best_effort '$WORKFLOW_ISSUE' 'Workflow'; update_tracker_type_best_effort '$BUG_ISSUE' 'Bug'"
   bash -lc "source scripts/development-workflow/workflow-lib.sh; get_tracker_type_for_issue '$WORKFLOW_ISSUE'; echo; get_tracker_type_for_issue '$BUG_ISSUE'"
   ```

**Expected result**: The first issue reports Type `Workflow`; the second reports
Type `Bug`.

### Step 3: Verify Workflow Type discovery

`list_open_workflow_type_issues` keeps Workflow-only filtering in both
repository modes and is unchanged by #1583, so this step remains a correct
test of it in either mode. Framework-mode discovery of every open item
regardless of Type is covered separately by
`1583-template-mode-type-routing.smoke-test.md`'s wrapper steps.

1. Run the Workflow Type discovery helper:

   ```bash
   bash -lc 'source scripts/development-workflow/workflow-lib.sh; list_open_workflow_type_issues'
   ```

2. Confirm the output includes the temporary Workflow issue.
3. Confirm the output does not include the temporary Bug issue.

**Expected result**: Workflow discovery is based on project Type, not labels.

### Step 4: Verify Backlog route classification

1. Run the orchestrator or next-action classification path against the temporary
   Bug issue.
2. Confirm the issue is treated as a fast-track bug/fix candidate based on Type.
3. **Consumer-mode fixture**: run the workflow discovery path against the
   temporary Workflow issue. Confirm it remains discoverable as
   workflow-framework work without the `workflow` label.
4. **Framework-mode outcome** (`template.is_template: true`): a Backlog item
   with Type `Workflow`, no development-folder artifacts, and no
   implementation branch/PR is **held** as misclassified
   (`framework-mode-backlog-type-gate.sh` / `NEXT_ACTION=hold-misclassified-type`
   in a scan, or a single-item `missing_tracker_context` stop) rather than
   routed as discoverable framework work (#1583).

**Expected result**: Type values drive classification and routing, with
framework-mode Backlog+Workflow items held instead of routed.

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

- [ ] Workflow issue discovery works through project Type `Workflow` (`list_open_workflow_type_issues`, both modes).
- [ ] Bug/fix routing works through project Type `Bug`.
- [ ] Retired classification labels are not required for the tested flows.
- [ ] Operational labels remain unchanged.
- [ ] **Consumer-mode**: Backlog + Type `Workflow` remains discoverable/routable as workflow-framework work.
- [ ] **Framework-mode**: Backlog + Type `Workflow` with no artifacts/branch/PR is held as misclassified, not routed.
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
