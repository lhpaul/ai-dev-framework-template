# Developer Agent GitHub Actions Security Defaults — Spec

**Depends on**: none

---

## Overview

This feature ensures newly created or materially updated GitHub Actions workflow files include baseline security defaults before a pull request is opened. The goal is to prevent avoidable review churn caused by known CI security findings (over-privileged `GITHUB_TOKEN` and unpinned third-party actions). The developer workflow should produce secure-by-default workflow YAML in the first pass instead of relying on reviewer feedback loops to correct these issues.

---

## Use Cases

### Use Case 1: Agent creates a new workflow file with secure defaults

**Actor**: Developer agent implementing a task that adds `.github/workflows/*.yml`
**Preconditions**:
- The task requires adding a new GitHub Actions workflow file.
- The repository uses GitHub Actions with `uses:`-based reusable actions.

**Steps**:
1. The agent creates a new workflow YAML file.
2. The agent adds an explicit least-privilege `permissions` block for workflow jobs.
3. The agent pins every `uses:` action reference to a full commit SHA and keeps the human-readable version tag in an adjacent comment.
4. The agent evaluates whether path filters and concurrency controls are appropriate for the workflow trigger and purpose.

**Postconditions**:
- The workflow file follows repository security defaults at creation time.
- The PR is less likely to receive preventable CI security review findings.

**Information shown**:
- Workflow YAML clearly shows explicit `permissions`.
- Workflow YAML clearly shows SHA-pinned `uses:` references.

**Actions available**:
- The agent can proceed to PR readiness loops without a dedicated "security defaults fixup" cycle.

**Considerations**:
- A workflow may require broader permissions than `contents: read`; when so, the workflow must still declare explicit minimum required permissions rather than inheriting broad defaults.

---

### Use Case 2: Agent updates an existing workflow and keeps defaults intact

**Actor**: Developer agent modifying an existing workflow file as part of a different feature or fix
**Preconditions**:
- A workflow file under `.github/workflows/` is significantly modified.

**Steps**:
1. The agent edits triggers, jobs, or steps in an existing workflow.
2. The agent verifies existing `permissions` and `uses:` pinning still comply with the baseline defaults.
3. If the file lacks required defaults, the agent updates it during the same change.

**Postconditions**:
- Existing workflows do not regress on baseline security defaults during unrelated edits.

**Information shown**:
- Updated workflow continues to expose explicit permissions and pinned actions.

**Actions available**:
- The agent can include the workflow update in the same PR without introducing known CI security findings.

**Considerations**:
- "Significant modification" includes adding jobs/steps, changing triggers, or altering action references.

---

## Business Rules

- New or significantly modified workflow files under `.github/workflows/*.yml` must declare explicit `permissions` at workflow or job level.
- Default permission posture is least privilege; use `contents: read` unless a narrower/broader explicit scope is required by workflow behavior.
- Every `uses:` reference must be pinned to a full commit SHA; floating tags alone are not acceptable.
- Version tags should remain visible as adjacent comments for readability and maintenance.
- Path filters (`paths` / `paths-ignore`) should be added when the workflow only needs to run for a known subset of file changes.
- Concurrency groups should be added when duplicate concurrent runs on the same ref would be wasteful or harmful.

---

## Operational Visibility

- **Logs**: PR diffs for workflow files must make permissions and pinned action SHAs explicit and reviewable.
- **Notifications**: External automated reviewers should no longer raise recurring major findings for missing permissions or unpinned actions on newly authored workflows.
- **Audit trail**: Workflow files themselves provide durable evidence of explicit permissions and pinned references in git history.

---

## Acceptance Criteria

- [ ] AC1: When a task creates a new file under `.github/workflows/`, the resulting workflow contains an explicit `permissions` block with least-privilege defaults.
- [ ] AC2: Every `uses:` entry in newly created workflow files is pinned to a full commit SHA, with a nearby comment preserving the intended version tag.
- [ ] AC3: When an existing workflow is significantly modified, the resulting file still satisfies AC1 and AC2 (or is remediated in the same PR).
- [ ] AC4: The implementation workflow guidance includes a clear checklist that agents apply before opening a PR when workflow files are added or significantly modified.
- [ ] AC5: The checklist explicitly covers optional-but-recommended path filtering and concurrency controls, with agent behavior to evaluate and apply them when relevant.

---

## Out of Scope (MVP)

- Backfilling all historical workflow files in the repository that predate this change.
- Introducing a separate repository-wide linting or policy-enforcement service for workflow YAML.
- Defining a full policy catalog for all possible GitHub Actions security controls beyond the defaults in this spec.
- Requiring path filters or concurrency for workflows where they are not semantically appropriate.

