# Stale Tracker Status Transitions in the Orchestrator — Spec

**Issue**: #487

---

## Overview

The workflow orchestrator and its supporting scripts sometimes set the wrong tracker status when a spec or plan PR is merged (Case A), and may leave the tracker stuck at "In Development" when a dispatch is abandoned before any PR is created (Case B). Both problems cause subsequent batch runs to misread the true state of an item, leading to incorrect parallelisation decisions and, in the worst case, duplicate dispatch. This spec defines the rules and acceptance criteria to fix both cases and prevent duplicate dispatch.

---

## Use Cases

### Use Case 1: Spec or Plan PR Merges — Tracker Shows Correct "Ready" Status

**Actor**: Automated system (GitHub Actions workflow, post-merge-cleanup script, or orchestrator protocol rule) triggered immediately after a spec or plan PR is merged to the integration branch.

**Preconditions**:

- A spec PR (branch type `spec/*`) or plan PR (branch type `implementation-plan/*`) has just been merged to the integration branch.
- The linked work item exists in the project tracker.

**Steps**:

1. The automated system detects the merge event.
2. The system identifies the branch type (spec or plan) from the merged branch name.
3. The system maps the branch type to the correct "Ready" status:
   - Spec PR merged → tracker status becomes "Spec Ready".
   - Plan PR merged → tracker status becomes "Plan Ready".
4. The system updates the tracker item to the mapped status.

**Postconditions**:

- The tracker item reflects "Spec Ready" (for spec merges) or "Plan Ready" (for plan merges).
- The tracker item is **not** set to "Merged" for spec or plan merges.

**Information shown**:

- The project tracker displays the updated status immediately after the merge is processed.

**Actions available**:

- The next orchestrator run can safely read the tracker status and advance the item to the next pipeline stage without manual correction.

**Considerations**:

- If the tracker item is already in a further-advanced status (e.g., already "In Development" when the spec PR merges), the system must not roll the status back — leave it as-is.
- The automated system applies the correction regardless of whether it is triggered by the GitHub Actions workflow, the post-merge-cleanup script, or the orchestrator protocol rule. All three must agree on the same branch-type → status mapping.

---

### Use Case 2: Abandoned "In Development" Status Is Detected and Corrected at Next Dispatch

**Actor**: Orchestrator (portfolio orchestrator or work item runner) at the start of a new batch or item run.

**Preconditions**:

- A work item's tracker status is "In Development".
- No implementation PR exists for that item (it was never created, or the branch does not exist).
- A prior orchestrator run set "In Development" before dispatching, but the dispatch was abandoned (e.g., a blocker was hit, or the batch was held by a human) without ever creating a PR.

**Steps**:

1. The orchestrator reads the tracker status for the item and sees "In Development".
2. The orchestrator checks whether an implementation PR (or branch) exists for that item.
3. No PR and no branch are found.
4. The orchestrator treats the stale "In Development" status as equivalent to "Plan Ready" for dispatch-decision purposes.
5. The orchestrator updates the tracker status to "Plan Ready" to correct the stale state.
6. The orchestrator proceeds to dispatch the item from the implementation stage as normal.

**Postconditions**:

- The tracker item reflects "Plan Ready" (corrected from the stale "In Development").
- The orchestrator dispatches the implementation work as if the item had been in "Plan Ready" all along.
- A log entry or comment notes the correction so it is visible in retrospective analysis.

**Information shown**:

- The project tracker shows "Plan Ready" for the item (corrected).
- The orchestrator's run log shows a note about the stale status correction.

**Actions available**:

- The item proceeds normally to implementation dispatch.
- Human reviewers can verify the correction in the run log if needed.

**Considerations**:

- The check must be performed at the start of the batch run (portfolio orchestrator, Step 2.5) and at the start of any single-item run (work item runner, Step 2 pre-dispatch check).
- If a branch (even without a PR) exists for the item, the status is not stale — the item is genuinely in progress and should not be reset.
- This correction applies only to items orchestrated through protocol 90 (batch portfolio orchestrator) or protocol 91 (work item runner dispatched from it). Direct manual runner invocations outside this orchestration path are out of scope.

---

### Use Case 3: Duplicate Dispatch Is Prevented When "In Development" Is Stale

**Actor**: Orchestrator initiating a new batch or item run.

**Preconditions**:

- An item's tracker status is "In Development" (potentially stale from a prior abandoned dispatch).
- No implementation PR or branch exists for the item.
- The orchestrator considers dispatching the item.

**Steps**:

1. The orchestrator checks the tracker status and sees "In Development".
2. The orchestrator runs the branch/PR existence check (same check as in Use Case 2).
3. No PR and no branch are found — the "In Development" status is confirmed stale.
4. The orchestrator corrects the status to "Plan Ready" and treats the item as eligible for a single dispatch.
5. The orchestrator marks the item as dispatched for this run and does not enqueue it a second time.

**Postconditions**:

- The item is dispatched exactly once in the run, not twice.
- The tracker reflects the corrected status before dispatch begins.

**Considerations**:

- This rule applies both when the orchestrator discovers the stale status during the initial batch scan and when a single-item runner encounters it.
- If a second item in the same batch also resolves to the same corrected-from-stale state, each is dispatched independently; the rule prevents one item from being dispatched twice, not from dispatching two separate items.

---

## Business Rules

- **BR-1 Spec-merge status**: When a spec PR is merged, the tracker status for the linked item must be set to "Spec Ready". It must never be set to "Merged".
- **BR-2 Plan-merge status**: When a plan PR is merged, the tracker status for the linked item must be set to "Plan Ready". It must never be set to "Merged".
- **BR-3 Implementation-merge status**: When an implementation PR (feature, fix, refactor, hotfix) is merged, the tracker status must be set to "Merged". The item's issue is also closed at this point.
- **BR-4 No-rollback rule**: If a tracker item's status is already in a further-advanced state than the post-merge mapping would set (e.g., already "In Development" when a spec or plan PR merges), the status must not be rolled back. The no-rollback rule takes precedence over BR-1 and BR-2.
- **BR-5 Stale "In Development" detection**: An "In Development" tracker status is considered stale if and only if no implementation branch and no implementation PR exist for the item. Both conditions (no branch and no PR) must be true; the existence of either invalidates the stale determination.
- **BR-6 Stale correction target**: A stale "In Development" status must be corrected to "Plan Ready" before dispatch. It must not be corrected to any other status.
- **BR-7 Stale check scope**: Stale "In Development" detection and correction applies only to items orchestrated through protocol 90 or protocol 91 (when dispatched from protocol 90). It does not apply to direct, ad-hoc manual runner invocations outside this orchestration path.
- **BR-8 Duplicate dispatch prevention**: Within a single orchestrator run, an item whose stale status has been corrected from "In Development" to "Plan Ready" must be dispatched at most once. The correction event itself must not cause a second dispatch of the same item within that run.
- **BR-9 Consistent mapping across surfaces**: The branch-type → tracker-status mapping in BR-1, BR-2, and BR-3 must be identical across all three enforcement surfaces: the GitHub Actions workflow (`update-tracker-on-merge.yml`), the post-merge-cleanup script, and the protocol rule in Step 10 of protocol 91.
- **BR-10 Log stale correction**: When a stale "In Development" status is corrected, the orchestrator must emit a log entry describing the item identifier, the old status ("In Development"), and the new status ("Plan Ready").

---

## Statuses / Enum Values

Existing workflow tracker statuses (no new values introduced by this fix):

| Status label   | Description                                                                    |
| -------------- | ------------------------------------------------------------------------------ |
| Spec Ready     | Spec PR has been merged; item is waiting for implementation plan to be written |
| Plan Ready     | Plan PR has been merged; item is waiting for implementation to begin           |
| In Development | Implementation dispatch is active — an implementation branch or PR exists      |
| Merged         | Implementation PR has been merged; the work item is complete                   |

**Relevant transitions corrected by this fix**:

- Spec PR merged → "Spec Ready" (not "Merged")
- Plan PR merged → "Plan Ready" (not "Merged")
- Stale "In Development" (no branch/PR) detected at dispatch time → corrected to "Plan Ready"

---

## Operational Visibility

- **Logs**: The orchestrator must log a human-readable correction note whenever it resets a stale "In Development" status to "Plan Ready", including the item identifier and the prior status.
- **Audit trail**: The stale-status correction must be visible in the orchestrator's run summary (the Work Item Runner Summary and/or batch orchestrator output), so retrospective analysis can identify how many items were corrected per run.

---

## Acceptance Criteria

- [ ] **AC-1** When a spec PR is merged, the linked tracker item's status transitions to "Spec Ready". An automated check (script or CI step) verifies this mapping in `update-tracker-on-merge.yml` for the `spec/*` branch prefix.
- [ ] **AC-2** When a plan PR is merged, the linked tracker item's status transitions to "Plan Ready". An automated check verifies this mapping in `update-tracker-on-merge.yml` for the `implementation-plan/*` branch prefix.
- [ ] **AC-3** When an implementation PR is merged (feature, fix, refactor, or hotfix branch), the linked tracker item's status transitions to "Merged". An automated check verifies this mapping in `update-tracker-on-merge.yml`.
- [ ] **AC-4** The post-merge-cleanup script applies the same branch-type → status mapping as `update-tracker-on-merge.yml` (Spec Ready for spec merges, Plan Ready for plan merges, Merged for implementation merges). A reviewer can verify this by comparing the script's mapping table against the workflow's.
- [ ] **AC-5** Step 10 of protocol 91 explicitly states the branch-type → status mapping (Spec Ready, Plan Ready, Merged) and prohibits setting "Merged" for spec or plan merges. A reviewer can verify this by reading the rule table in Step 10.
- [ ] **AC-6** When the orchestrator (portfolio or single-item) encounters a tracker item in "In Development" status with no implementation branch and no implementation PR, it corrects the status to "Plan Ready" and logs the correction before dispatching.
- [ ] **AC-7** After the stale "In Development" status is corrected to "Plan Ready", the orchestrator dispatches the item exactly once in the same run (duplicate dispatch is prevented).
- [ ] **AC-8** A stale-detection check that finds a branch or PR for the item does not correct the status — the item is treated as genuinely in progress.
- [ ] **AC-9** An automated check script exists that verifies `update-tracker-on-merge.yml` maps each supported branch prefix (`spec/*`, `implementation-plan/*`, `feature/*`, `fix/*`, `refactor/*`, `hotfix/*`) to the correct target status. The script exits non-zero if any mapping is incorrect or missing.
- [ ] **AC-10** The stale correction and log note are visible in the orchestrator's run summary output, enabling retrospective analysis to identify corrected items.

---

## Out of Scope (MVP)

- **Automatic rollback of stale "In Development" status without human confirmation**: this fix detects and corrects the stale status at the next orchestrator dispatch, not in real time as the dispatch abandonment happens.
- **Case B detection outside orchestrated runs**: correcting stale statuses for items that were dispatched outside protocol 90/91 (e.g., direct manual agent runs not invoked through the orchestrator) is not addressed by this fix.
- **Automated rollback when a branch is deleted without a merged PR**: detecting abandonment at branch-deletion time and rolling back the status is explicitly deferred. The fix uses re-validation at next dispatch (per alignment Q2(b)).
- **Notifications or alerts when a stale status is detected**: this fix only logs the correction. Separate alerting or notification tooling is out of scope.
- **Correcting stale statuses other than "In Development"**: only the "In Development" → "Plan Ready" correction is in scope. Other stale-status scenarios (e.g., stale "Writing Spec" or "Writing Plan") are deferred.

---

## Brief Coverage Matrix

| Brief objective                                                                    | Covered by                                     |
| ---------------------------------------------------------------------------------- | ---------------------------------------------- |
| Case A: Plan PR merge incorrectly advances tracker to "Merged"                     | AC-1, AC-2, AC-3, AC-4, AC-5; BR-1, BR-2, BR-9 |
| Case A root cause: Step 10 rule or post-merge-cleanup applies wrong status         | AC-4, AC-5; BR-9                               |
| Case A fix scope: protocol rule + script + GitHub Actions workflow                 | AC-1–AC-5; BR-9 (all three surfaces)           |
| Case B: Pre-dispatch "In Development" left stale after abandoned dispatch          | AC-6, AC-7, AC-8; BR-5, BR-6, BR-7             |
| Case B mechanism: re-validate at next dispatch                                     | Use Case 2; BR-5, BR-6                         |
| Case B detection owner: both protocol 90 (portfolio) and protocol 91 (item runner) | Use Case 2, BR-7                               |
| Duplicate dispatch risk                                                            | Use Case 3; AC-7; BR-8                         |
| Automated acceptance test for `update-tracker-on-merge.yml` mapping                | AC-9                                           |
| Log / operational visibility for stale corrections                                 | AC-10; BR-10                                   |
