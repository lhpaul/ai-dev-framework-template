# fix(post-merge-cleanup): Contradictory Log Output and Missing Tracker Status Update — Spec

---

## Overview

`scripts/development-workflow/post-merge-cleanup.sh` has two bugs that recur on every spec/plan/implementation branch merge. First, it emits mutually contradictory log lines for the same branch when the branch prefix is `spec/*` or `implementation-plan/*`: one code path correctly extracts the issue number and prints a "stays open" message, while a separate code path falls through to "No issue number detected" and prints a spurious skip message. Second, the script never updates the GitHub Projects v2 Status field after a merge; for implementation branches it closes the GitHub issue but leaves the project board at the in-flight status, and for spec/plan branches it neither closes the issue nor transitions the status. Both bugs have recurred on every batch merge since the script was introduced.

---

## Use Cases

### Use Case 1: Developer runs post-merge-cleanup after merging a spec PR

**Actor**: Developer (or automated orchestrator) invoking `post-merge-cleanup.sh <branch>` where `<branch>` matches `spec/<number>-<slug>`

**Preconditions**:
- The spec branch has been merged on GitHub (PR merged, remote branch deleted)
- The developer's local repo still has the local spec branch

**Steps**:
1. Developer (or orchestrator) runs `./scripts/development-workflow/post-merge-cleanup.sh spec/184-post-merge-cleanup-log-and-tracker`
2. Script fetches origin, switches to `develop`, pulls, removes any linked worktree, deletes the local branch
3. Script detects the branch prefix is `spec/*` and extracts the issue number `184`
4. Script logs exactly one message acknowledging the spec merge and that the issue stays open
5. Script updates the GitHub Projects v2 Status field for issue #184 to `Spec Ready`
6. Script exits cleanly

**Postconditions**:
- Local branch is deleted; developer is on `develop`
- GitHub Projects v2 Status for issue #184 is `Spec Ready`
- No contradictory log lines appear in the output

**Information shown**:
- A single informational log line: issue number detected, issue stays open, status updated to `Spec Ready`
- No "No issue number detected" message for this branch

**Actions available**:
- Developer can immediately begin the next workflow stage for issue #184 (write plan)

**Considerations**:
- If the GitHub Projects lookup fails (network error, missing project config), the script should log a warning and exit with a non-zero code rather than silently continue
- If the project item for the issue does not exist, log a warning and continue (do not abort cleanup)

---

### Use Case 2: Developer runs post-merge-cleanup after merging an implementation-plan PR

**Actor**: Developer (or automated orchestrator) invoking `post-merge-cleanup.sh <branch>` where `<branch>` matches `implementation-plan/<number>-<slug>`

**Preconditions**:
- The implementation-plan branch has been merged on GitHub
- The developer's local repo still has the local implementation-plan branch

**Steps**:
1. Developer runs `./scripts/development-workflow/post-merge-cleanup.sh implementation-plan/184-post-merge-cleanup-log-and-tracker`
2. Script fetches, switches to `develop`, pulls, removes worktree if any, deletes local branch
3. Script detects the branch prefix is `implementation-plan/*` and extracts the issue number
4. Script logs exactly one message: issue stays open, status will be updated to `Plan Ready`
5. Script updates the GitHub Projects v2 Status field to `Plan Ready`
6. Script exits cleanly

**Postconditions**:
- Local branch is deleted; developer is on `develop`
- GitHub Projects v2 Status is `Plan Ready`
- No contradictory log lines appear

**Considerations**:
- Same GitHub Projects failure handling as Use Case 1

---

### Use Case 3: Developer runs post-merge-cleanup after merging a feature/fix/refactor/hotfix PR

**Actor**: Developer (or automated orchestrator) invoking `post-merge-cleanup.sh <branch>` where `<branch>` matches `feature/*`, `fix/*`, `refactor/*`, or `hotfix/*`

**Preconditions**:
- The implementation branch has been merged on GitHub
- The developer's local repo still has the local implementation branch
- A GitHub issue with the extracted issue number exists and is OPEN

**Steps**:
1. Developer runs `./scripts/development-workflow/post-merge-cleanup.sh feature/184-post-merge-cleanup-log-and-tracker`
2. Script fetches, switches to `develop`, pulls, removes worktree if any, deletes local branch
3. Script detects the branch prefix is `feature/*` and extracts the issue number
4. Script closes the GitHub issue with "Closed by PR #NNN" comment (existing behavior, preserved)
5. Script updates the GitHub Projects v2 Status field to `Merged`
6. Script exits cleanly

**Postconditions**:
- Local branch is deleted; developer is on `develop`
- GitHub issue is closed
- GitHub Projects v2 Status is `Merged`
- No contradictory log lines appear

**Considerations**:
- If the issue is already closed, the close step is skipped (existing behavior, preserved)
- If no merged PR is found for the branch, issue close is skipped (existing behavior, preserved)
- GitHub Projects update is attempted regardless of issue-close outcome

---

### Use Case 4: Developer runs post-merge-cleanup on a branch with no issue number

**Actor**: Developer invoking `post-merge-cleanup.sh <branch>` on a branch that does not contain a numeric issue-number prefix (e.g., `feature/my-legacy-feature`)

**Preconditions**:
- The branch has been merged on GitHub

**Steps**:
1. Developer runs `./scripts/development-workflow/post-merge-cleanup.sh feature/my-legacy-feature`
2. Script performs git cleanup (fetch, switch, pull, delete branch)
3. Script detects no issue number in the branch name
4. Script logs exactly one message: "No issue number detected in branch name, skipping issue close and tracker update"
5. Script exits cleanly with no tracker update

**Postconditions**:
- Local branch is deleted; developer is on `develop`
- No GitHub issue or tracker changes are made

**Considerations**:
- This is a valid, non-error scenario for branches that predate the issue-number convention

---

## Business Rules

- **One log message per branch per concern**: The script must emit at most one log line describing the issue-number detection result (detected or not). It must never emit both "issue stays open" and "no issue number detected" for the same branch.
- **Status transition by branch type**: The project board status must be updated according to the merged branch prefix:
  - `spec/*` → `Spec Ready`
  - `implementation-plan/*` → `Plan Ready`
  - `feature/*`, `fix/*`, `refactor/*`, `hotfix/*` → `Merged`
- **Issue close by branch type**: Only `feature/*`, `fix/*`, `refactor/*`, and `hotfix/*` branches trigger issue close. Spec and plan branches do not close the issue.
- **GitHub Projects update is best-effort with warning on failure**: If the GitHub Projects lookup or GraphQL mutation fails (missing project config, network error, item not found), the script logs a warning but does not abort the git cleanup steps. Git cleanup always completes.
- **No silent no-ops**: If the project config required for the tracker update is absent (e.g., project number or owner not configured), the script logs an explicit warning rather than silently skipping.
- **Idempotent**: Running the script twice for the same already-cleaned-up state must not error (issue already closed, status already updated, branch already deleted are all acceptable).

---

## Operational Visibility

- **Logs**: Every significant decision in the script (issue number found/not found, tracker update attempted/succeeded/failed/skipped, issue close attempted/succeeded/skipped) is logged to stdout
- **Exit codes**: Non-zero exit for fatal precondition failures (branch not found, already on develop); zero exit when cleanup completed (even if tracker update warned)

---

## Acceptance Criteria

- [ ] When `post-merge-cleanup.sh` is run for a `spec/*` branch containing a numeric issue number, the output contains exactly one message about the issue (not two), and that message does not say "No issue number detected"
- [ ] When `post-merge-cleanup.sh` is run for an `implementation-plan/*` branch containing a numeric issue number, the output contains exactly one message about the issue (not two), and that message does not say "No issue number detected"
- [ ] When `post-merge-cleanup.sh` is run for a `feature/*`, `fix/*`, `refactor/*`, or `hotfix/*` branch containing a numeric issue number, the GitHub Projects v2 Status field for the associated issue is updated to `Merged` (in addition to the existing GitHub issue close behavior)
- [ ] When `post-merge-cleanup.sh` is run for a `spec/*` branch, the GitHub Projects v2 Status field for the associated issue is updated to `Spec Ready`
- [ ] When `post-merge-cleanup.sh` is run for an `implementation-plan/*` branch, the GitHub Projects v2 Status field for the associated issue is updated to `Plan Ready`
- [ ] When `post-merge-cleanup.sh` is run for a branch with no numeric issue number, the output contains exactly one message ("No issue number detected") and no tracker update is attempted
- [ ] If the GitHub Projects update fails (e.g., misconfigured project), the script logs a warning and still completes the git cleanup steps successfully (exits 0)

---

## Out of Scope (MVP)

- Changes to `pr-review-loop.sh`, `pr-ci-loop.sh`, `batch-merge.sh`, Protocol 91 Step 7a, Protocol 90 batching logic, or any `.claude/agents/*` files
- Updating the tracker status mid-workflow (only post-merge transitions are in scope)
- Supporting tracker providers other than GitHub Projects v2 (the fix targets the existing GitHub Projects integration)
- Adding a project-config discovery mechanism beyond what is already available via `gh` CLI (e.g., reading project number from `.ai-dev-workflow.yaml` is a separate improvement)
- Retroactively correcting already-drifted tracker statuses from past merges
