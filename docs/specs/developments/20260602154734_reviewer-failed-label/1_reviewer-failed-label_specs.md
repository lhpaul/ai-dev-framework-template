# reviewer-failed label — Spec

---

## Overview

When one or more automated reviewer platforms fail, time out, or become unavailable during the PR reviewer loop, the failure is currently invisible at a glance on the PR card — operators must read the full reviewer-loop summary comment to detect problems. This feature adds a `reviewer-failed` label that `pr-review-loop.sh` applies to a PR whenever at least one configured platform reports a non-trivial failure (escalation or a skip caused by being unavailable, timing out, or encountering a thread-check failure). The label self-heals: it is removed on the next loop run that completes cleanly, so the PR card always reflects current reviewer health.

---

## Use Cases

### Use Case 1: Platform failure is flagged on the PR card

**Actor**: Automated orchestrator running `pr-review-loop.sh` against an open PR
**Preconditions**: At least one platform in `.ai-dev-workflow.yaml` is configured and the loop has just completed a run

**Steps**:

1. The loop runs and at least one platform reports `RESULT=escalate` or `RESULT=skipped` with reason `unavailable`, `timeout`, or `thread-check-failed`.
2. The script checks whether the `reviewer-failed` label exists in the repository; if not, it creates it with a distinct color.
3. The script applies the `reviewer-failed` label to the PR.

**Postconditions**: The PR card displays the `reviewer-failed` label. Operators scanning the PR list or board can immediately see which PRs have reviewer health issues without opening the summary comment.

**Information shown**:

- The `reviewer-failed` label appears on the PR card in the GitHub UI and in `gh pr list` output.

**Actions available**:

- Operators can investigate the reviewer-loop summary comment to identify which platform failed and why.
- Operators can re-run the reviewer loop after resolving the underlying issue to trigger self-heal.

**Considerations**:

- The label may coexist with `ready-for-human-review` — a PR can be considered clean by the platforms that did respond while another platform failed.
- The label must not be applied when the only skip reason is `not_configured` (platform not declared in `.ai-dev-workflow.yaml`). A platform that is simply not configured is not a failure.

---

### Use Case 2: Self-heal on a subsequent clean loop run

**Actor**: Automated orchestrator running `pr-review-loop.sh` against a PR that currently carries the `reviewer-failed` label
**Preconditions**: The PR has the `reviewer-failed` label from a prior loop run; the current loop run has completed with all platforms returning `clean` or `skipped/not_configured`

**Steps**:

1. The loop runs and every platform that completed returns `clean` or `skipped` with reason `not_configured`.
2. The script detects that no non-trivial failures occurred in this run.
3. The script removes the `reviewer-failed` label from the PR.

**Postconditions**: The `reviewer-failed` label is absent from the PR card, reflecting that the most recent loop run encountered no platform failures.

**Information shown**:

- The `reviewer-failed` label is no longer visible on the PR card.

**Considerations**:

- If the label is already absent (e.g., it was never applied or was already removed), the removal step is a no-op.
- The removal applies only when the current run produces no non-trivial failures — a run that still has at least one failing platform leaves the label in place.

---

### Use Case 3: Label creation is idempotent

**Actor**: Automated orchestrator running `pr-review-loop.sh` for the first time on a repository
**Preconditions**: The `reviewer-failed` label does not yet exist in the repository

**Steps**:

1. The loop determines that the `reviewer-failed` label must be applied to the PR.
2. The script checks whether the label exists in the repository.
3. The label does not exist, so the script creates it with a distinct color.
4. The script applies the newly created label to the PR.

**Postconditions**: The `reviewer-failed` label exists in the repository and is applied to the PR.

**Considerations**:

- On subsequent runs, the label already exists — the creation step is a no-op.
- Label creation must not block the loop from completing its normal output contract even if the label API call fails; the script should log a warning and continue.

---

## Business Rules

- The `reviewer-failed` label is applied when at least one platform in the current loop run reports `RESULT=escalate` or `RESULT=skipped` with reason `unavailable`, `timeout`, or `thread-check-failed`.
- The `reviewer-failed` label is NOT applied when the only platforms that did not return `clean` were skipped with reason `not_configured`. A platform that is not declared in `.ai-dev-workflow.yaml` is not a failure.
- The `reviewer-failed` label is removed when the current loop run completes with every platform returning `clean` or `skipped/not_configured`.
- The label name is exactly `reviewer-failed` — no variation.
- Label creation is idempotent: the script creates the label in the repository only if it does not already exist.
- The `reviewer-failed` label may coexist with `ready-for-human-review` on the same PR; neither label blocks the other.
- The label may coexist with `needs-fixes`; platform failure and blocking reviewer findings are independent signals.

---

## Acceptance Criteria

- [ ] AC-1: After a loop run where at least one platform returns `RESULT=escalate` or `RESULT=skipped` with reason `unavailable`, `timeout`, or `thread-check-failed`, the label `reviewer-failed` is present on the PR.
- [ ] AC-2: After a subsequent loop run where every platform returns `clean` or `skipped/not_configured`, the label `reviewer-failed` is removed from the PR.
- [ ] AC-3: The label is NOT applied when the only skip reason across all platforms is `not_configured`.
- [ ] AC-4: The `reviewer-failed` label and the `ready-for-human-review` label can both be present on the same PR simultaneously (no conflict, no mutual exclusion logic).
- [ ] AC-5: The `reviewer-failed` GitHub label is created with a distinct color in the repository the first time it is needed, and the creation is idempotent (running the script again when the label already exists does not error or duplicate the label).

---

## Out of Scope (MVP)

- Configuring the label name via `.ai-dev-workflow.yaml` — the label name is hardcoded as `reviewer-failed` in this iteration.
- Per-platform granularity labels (e.g., `reviewer-failed/haystack`) — a single aggregate label covers all platform failures.
- Slack or email notifications triggered by the label change.
- Historical tracking of how many times a PR has been labeled `reviewer-failed`.
- Dashboard or reporting views over `reviewer-failed` label history across all PRs.
