# Hub Worker Preflight — Spec

## Overview

An operator running a workflow hub with Cursor My Machines / Remote Control needs to know that the worker can reach the hub, its configured product checkouts, and their GitHub repositories before orchestration changes anything. The preflight reports actionable failures early so the operator can correct the worker environment and retry. It complements the existing dispatch profiles and does not change the worker runtime.

## Use Cases

### Prepare a worker for a bounded hub run

**Actor**: Operator or workflow runner using My Machines / Remote Control.

**Preconditions**: The hub and its intended product repositories are configured for the worker. The operator has selected the worker directory and a bounded workflow command.

**Steps**:

1. For a My Machines / Remote Control run, the operator identifies the hub checkout for this run and the worker directory, including an explicitly registered worker directory when applicable.
2. The operator invokes the documented preflight in the worker environment before the bounded run mutates anything. It checks the worker directory, configured local product checkouts, and GitHub access.
3. The preflight reports whether these checks passed or identifies a failed check and how to correct it; the operator provides the result to the bounded run.
4. On success, the bounded run continues under the existing dispatch profile and workflow gates. On failure, the operator fixes the environment and starts the checks again before mutation.

**Postconditions**: A successful preflight establishes the required local and GitHub read access for the checked configuration at the time of the check. A failed or inconclusive preflight prevents the bounded run from proceeding to mutation.

**Information shown**: A concise result and actionable diagnostic for any failed check. Sensitive credential material is not displayed.

**Considerations**: A missing, invalid, or incorrect worker directory, missing local mapping or checkout, inaccessible GitHub repository, and unavailable or unauthenticated GitHub tooling must produce a failure. Dirty or out-of-sync checkout warnings are optional; if provided, a warning-only result may pass, but does not authorize changes to the checkout.

## Business Rules

- For My Machines / Remote Control workflow-hub runs, the operator invokes the preflight before any orchestration mutation. The `/run-item`, `/run-items`, and `/run-epic` entrypoints instruct the operator to do so and require a successful result for the current run before proceeding. Mutation includes branch or file changes, tracker updates, PR changes, and other local or remote workflow writes.
- Validate the worker's hub directory against the hub checkout selected for this run and every configured local product checkout, even for a single-product item. An explicit worker directory is acceptable when it identifies that same hub checkout. An absent or empty product configuration fails rather than passing vacuously.
- Verify GitHub read access to the hub and configured product repositories using the worker's own environment. Inability to verify access is a failure, not a pass.
- Preflight is read-only: it must not create or change checkouts, configuration, credentials, branches, tracker items, or remote repository state.
- Diagnostics must identify the failed check and affected checkout or repository when known, and provide a corrective step. The preflight may stop at the first failed check; incomplete checks cannot yield success. Diagnostics must not disclose tokens, credential-bearing URLs, or private configuration contents.
- Success is a point-in-time read-access result, not proof of write permission, future access, clean working trees, or permission to bypass subsequent workflow gates.
- For a run identified as My Machines / Remote Control, the operator supplies the intended hub checkout; a missing or ambiguous hub selection stops before mutation. This feature does not add an execution-target declaration requirement to other runs. Dispatch profile selection remains a separate declaration under the existing Cursor profile contract: a dispatch profile does not by itself identify the execution target. Preflight does not infer the target or change handoff, review, merge, or checkpoint authority.

## Preflight Decision Gate

| Context and current evidence | Outcome | Required next action |
| --- | --- | --- |
| Operator-invoked preflight for a My Machines / Remote Control hub run; all required checks pass without warnings | Pass | Continue with the existing dispatch and workflow gates before mutation. |
| Operator-invoked preflight for a My Machines / Remote Control hub run; all required checks pass with optional warnings | Pass with warning | Report the warnings and continue with existing gates; do not modify checkouts to clear warnings. |
| My Machines / Remote Control hub run; any required check fails or cannot be verified | Stop | Report the failed or inconclusive check and a correction; retry before mutation. |
| My Machines / Remote Control hub run; the intended hub or another required preflight input is missing, invalid, or ambiguous | Stop | Identify the input to correct; do not treat it as a pass. |
| My Machines / Remote Control hub run; preflight has not been invoked or its result is unavailable | Stop | Instruct the operator to run the preflight and provide its current result before mutation. |
| Hosted Cloud or Cursor desktop run, or a non-hub repository mode | Existing behavior | Follow existing workflow gates; this feature adds no worker preflight requirement. |

Before the first mutation in a My Machines / Remote Control hub run, the operator invokes worker preflight and supplies its current result; the existing dispatch profile declaration and its own stop remain separate and must also be satisfied before mutation. Read-only checkpoints keep their existing profile rules and do not require worker preflight. The check uses the worker environment and current configuration at execution time; earlier successful results cannot replace a fresh check for a new run. If a warning and failure occur together, the failure wins. The operator runbook, Cursor dispatch-profile documentation, and Cursor command entrypoints for `/run-item`, `/run-items`, and `/run-epic` must describe the same gate.

## Acceptance Criteria

- [ ] An operator can run a documented preflight for a My Machines / Remote Control hub worker, including a worker registered with an explicit directory.
- [ ] The operator invokes preflight and supplies a successful current result before the bounded run mutates anything; a missing or unavailable result stops mutation with instructions to run it. A valid hub worker, configured local product checkouts, and reachable GitHub repositories pass.
- [ ] A wrong or missing worker directory, missing or invalid local product checkout, missing GitHub authentication, or inaccessible configured repository fails before mutation with a diagnostic identifying the failed check, affected checkout or repository when known, and a corrective step. A failed, incomplete, or inconclusive check, including a timeout or rate limit, never reports success. Earlier successful results cannot replace a fresh check for a new run.
- [ ] The preflight does not mutate local or remote workflow artifacts or reveal secrets, and its success does not claim write access.
- [ ] The operator runbook and Cursor dispatch-profile documentation explain the preflight and its limitations, and the Cursor `/run-item`, `/run-items`, and `/run-epic` command entrypoints reference it for My Machines / Remote Control hub execution.
- [ ] If optional dirty or sync warnings are provided, a warning-only result is reported and may pass without authorizing changes to the checkout.
- [ ] A My Machines / Remote Control hub run with a missing or ambiguous operator-selected hub checkout stops before mutation; a dispatch profile alone does not identify the execution target.
- [ ] A single-product run checks all configured products; absent or empty product configuration fails. The worker directory must identify the hub checkout selected by the operator for the run.
- [ ] Read-only checkpoints do not require preflight; existing dispatch profile, review, checkpoint, and merge rules remain in force independently of preflight.

## Out of Scope

- Starting or registering a worker, provisioning credentials, or changing Cursor product behavior.
- Automatically detecting execution targets or adding worker preflight to explicitly declared hosted Cloud or desktop runs.
- Repairing, synchronizing, or cleaning checkouts, and proving write access.
