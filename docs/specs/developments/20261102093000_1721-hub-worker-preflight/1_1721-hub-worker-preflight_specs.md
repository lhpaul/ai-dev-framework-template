# Hub Worker Preflight — Spec

## Overview

An operator running a workflow hub with Cursor My Machines / Remote Control needs to know that the worker can reach the hub, its configured product checkouts, and their GitHub repositories before orchestration changes anything. The preflight reports actionable failures early so the operator can correct the worker environment and retry. It complements the existing dispatch profiles and does not change the worker runtime.

## Use Cases

### Prepare a worker for a bounded hub run

**Actor**: Operator or workflow runner using My Machines / Remote Control.

**Preconditions**: The hub and its intended product repositories are configured for the worker. The operator has selected the worker directory and a bounded workflow command.

**Steps**:

1. The operator identifies the hub checkout used by the worker, including an explicitly registered worker directory when applicable.
2. Before orchestration mutates any artifact, the runner checks the worker directory, configured local product checkouts, and GitHub access from the worker environment.
3. The runner reports whether these checks passed or identifies a failed check and how to correct it.
4. On success, the bounded run continues under the existing dispatch profile and workflow gates. On failure, the operator fixes the environment and starts the checks again before mutation.

**Postconditions**: A successful preflight establishes the required local and GitHub read access for the checked configuration at the time of the check. A failed or inconclusive preflight prevents the bounded run from proceeding to mutation.

**Information shown**: A concise result and actionable diagnostic for any failed check. Sensitive credential material is not displayed.

**Considerations**: A missing, invalid, or incorrect worker directory, missing local mapping or checkout, inaccessible GitHub repository, and unavailable or unauthenticated GitHub tooling must produce a failure. A warning about a dirty or out-of-sync checkout does not itself authorize changes to it.

## Business Rules

- Apply the preflight to My Machines / Remote Control workflow-hub runs before any orchestration mutation, including branch, tracker, or PR changes. The `/run-item`, `/run-items`, and `/run-epic` entrypoints must direct such runs to it.
- Validate the worker's hub directory and every configured local product checkout; an explicit worker directory is acceptable when it identifies the intended hub checkout.
- Verify GitHub read access to the hub and configured product repositories using the worker's own environment. Inability to verify access is a failure, not a pass.
- Preflight is read-only: it must not create or change checkouts, configuration, credentials, branches, tracker items, or remote repository state.
- Diagnostics must not disclose tokens, credential-bearing URLs, or private configuration contents.
- Success is a point-in-time read-access result, not proof of write permission, future access, clean working trees, or permission to bypass subsequent workflow gates.
- Dispatch profile selection remains declared according to the existing Cursor profile contract; preflight does not infer the execution target or change handoff, review, merge, or checkpoint authority.

## Preflight Decision Gate

| Context and current evidence | Outcome | Required next action |
| --- | --- | --- |
| My Machines / Remote Control hub run; all required checks pass | Pass | Continue with the existing dispatch and workflow gates before mutation. |
| My Machines / Remote Control hub run; any required check fails or cannot be verified | Stop | Report the failed or inconclusive check and a correction; retry before mutation. |
| A required input is missing, invalid, or ambiguous | Stop | Identify the input to correct; do not treat it as a pass. |
| Another execution target or repository mode | Existing behavior | Follow its existing workflow; this preflight does not add a requirement there. |

The check uses the worker environment and current configuration at execution time; earlier successful results cannot replace a fresh check for a new run. If a warning and failure occur together, the failure wins. The operator runbook, dispatch-profile documentation, and the three bounded command entrypoints must describe the same gate.

## Acceptance Criteria

- [ ] An operator can run a documented preflight for a My Machines / Remote Control hub worker, including a worker registered with an explicit directory.
- [ ] A valid hub worker, configured local product checkouts, and reachable GitHub repositories pass before a bounded run mutates anything.
- [ ] A wrong or missing worker directory, missing or invalid local product checkout, missing GitHub authentication, or inaccessible configured repository fails before mutation with an actionable diagnostic. A failed or inconclusive check never reports success.
- [ ] The preflight does not mutate local or remote workflow artifacts or reveal secrets, and its success does not claim write access.
- [ ] The operator runbook and dispatch-profile documentation explain the preflight and its limitations, and `/run-item`, `/run-items`, and `/run-epic` reference it for My Machines / Remote Control hub execution.
- [ ] Existing dispatch profile, review, checkpoint, and merge rules remain in force.

## Out of Scope

- Starting or registering a worker, provisioning credentials, or changing Cursor product behavior.
- Automatically detecting execution targets or changing hosted Cloud and desktop behavior.
- Repairing, synchronizing, or cleaning checkouts, and proving write access.
