# Development Integration Branches — Spec

---

## Overview

When a large development effort is split across multiple backlog items (spec, plan, and implementation for several related sub-features), each item currently lands on `develop` as it completes. This means a release can ship incomplete work if only some sub-items are done. This feature introduces **development integration branches** — named staging branches of the form `develop-<slug>` — that collect all sub-item PRs for a grouped development, holding them off `develop` until the entire feature is ready. An explicit graduation command then merges the integration branch into `develop` as a single, tested unit.

---

## Use Cases

### Use Case 1: Grouping Backlog Items Under an Epic to Trigger an Integration Branch

**Actor**: Agent running the add-backlog-item workflow (product manager or orchestrator)
**Preconditions**: The human has asked to add two or more related backlog items that together form a single coherent feature.

**Steps**:

1. The agent identifies that the requested items form a multi-item development (two or more backlog items with a shared goal).
2. The agent creates an **epic** in the issue tracker to group the items, choosing a human-readable slug (e.g., `multi-tenant-billing`).
3. The agent attaches each sub-item to the epic and applies a shared label (e.g., `integration-branch:<slug>`) to each sub-item so that workflow agents can detect their shared integration branch.
4. The epic and its sub-items are visible in the issue tracker with their shared label.

**Postconditions**: The epic exists in the tracker with all sub-items linked and labeled. Subsequent workflow agents that process any sub-item can discover the integration branch name from the label.

**Information shown**:

- Epic title and slug
- List of sub-items linked to the epic
- Shared `integration-branch:<slug>` label on each sub-item

**Actions available**:

- Add more sub-items to the epic at any time before graduation
- View the epic to see overall progress across all sub-items

**Considerations**:

- If the human adds only a single item initially but later decides to expand it to a multi-item development, they must apply the `integration-branch:<slug>` label retroactively and create the epic before any sub-item PRs are opened. The spec does not cover retroactive regrouping of already-merged sub-items.
- The agent decides whether an integration branch is warranted based on whether the request clearly describes two or more distinct deliverable items. When in doubt, the agent asks.

---

### Use Case 2: Sub-Item PR Targets the Integration Branch (Not `develop`)

**Actor**: Agent running any workflow stage (spec, plan, implementation, fix, or refactor) on a sub-item
**Preconditions**: The sub-item has the `integration-branch:<slug>` label. The integration branch `develop-<slug>` has been created (see Use Case 3).

**Steps**:

1. The agent reads the sub-item's labels and identifies the `integration-branch:<slug>` label.
2. The agent derives the integration branch name: `develop-<slug>`.
3. All PRs for this sub-item (spec, plan, implementation, and any follow-on fixes or refactors raised during testing) target `develop-<slug>` instead of `develop`.
4. The PR is opened, reviewed, and merged into `develop-<slug>` through the normal workflow (review gate → automated reviewers → CI → human review → merge).
5. The merged work accumulates on `develop-<slug>`. `develop` is not touched.

**Postconditions**: The sub-item's changes are on the integration branch. `develop` is unaffected until graduation.

**Information shown**:

- PR base branch shows `develop-<slug>` (not `develop`)
- CHANGELOG entries for the sub-item are written normally under `[Unreleased]` on the integration branch

**Actions available**:

- Review and merge the PR as usual

**Considerations**:

- This applies to **all** PR types for the sub-item: spec PRs, plan PRs, implementation PRs, and any fix or refactor PRs that arise during integration testing. No sub-item PR for a labeled item ever targets `develop` directly.
- When a fix or refactor is raised after the planned sub-items are merged — for example, a bug found during integration testing on the integration branch — those PRs also target `develop-<slug>`.

---

### Use Case 3: Creating the Integration Branch

**Actor**: Human (or orchestrator agent on behalf of the human)
**Preconditions**: An epic exists in the tracker with at least two sub-items labeled `integration-branch:<slug>`.

**Steps**:

1. The human (or the orchestrator, when dispatching the first sub-item in the epic) verifies that no `develop-<slug>` branch exists yet.
2. The integration branch is created from the tip of `develop`: `git checkout -b develop-<slug> develop` (or the equivalent from `origin/develop`).
3. The branch is pushed to the remote.
4. Subsequent sub-item PRs use `develop-<slug>` as their base.

**Postconditions**: `develop-<slug>` exists on the remote and is ready to receive sub-item PRs.

**Information shown**:

- Confirmation that the branch was created and pushed

**Actions available**:

- Begin dispatching sub-item work

**Considerations**:

- The branch naming format is `develop-<slug>` using a hyphen. The `develop/<slug>` form is disallowed because git cannot simultaneously have a branch named `develop` and branches under the `develop/` namespace prefix.
- Creating the integration branch is the responsibility of the orchestrator when it first dispatches a sub-item that lacks the branch. If the branch already exists (e.g., a prior sub-item created it), skip this step.

---

### Use Case 4: Graduating the Integration Branch to `develop`

**Actor**: Human issuing the `/graduate-development <slug>` command after completing integration testing
**Preconditions**: All planned sub-items in the epic are merged to `develop-<slug>`. The human has tested the complete feature on the integration branch and is satisfied it is ready to land on `develop`.

**Steps**:

1. The human runs `/graduate-development <slug>` (or the equivalent workflow command).
2. The graduation agent verifies that all sub-items in the epic are in a terminal merged state on the integration branch.
3. The agent opens a graduation PR: `develop-<slug>` → `develop`.
4. The PR title follows the pattern: `feat(<slug>): graduate <slug> integration branch to develop`.
5. The PR description includes a summary of all sub-items included in the graduation and a brief description of what the feature delivers.
6. The graduation PR goes through the standard review process (automated reviewers → CI → human review).
7. The human merges the graduation PR using a **merge commit** (not squash) to preserve the full sub-item history on `develop`.
8. The `develop-<slug>` branch is deleted after the merge.

**Postconditions**: All sub-item changes are on `develop`. The integration branch is deleted. Releases cut from `develop` will include the full feature.

**Information shown**:

- Graduation PR with summary of included sub-items
- CHANGELOG on the integration branch carries all sub-item `[Unreleased]` entries; no separate consolidation is required — the history merges as-is

**Actions available**:

- Review and merge the graduation PR
- Add a summary CHANGELOG entry at the top of `[Unreleased]` before merging (optional, but encouraged for large features)

**Considerations**:

- The graduation command is human-initiated. Agents never graduate an integration branch autonomously.
- The merge strategy is **merge commit** to preserve sub-item history. Squash and rebase merges are disallowed for graduation PRs.
- If the human discovers additional bugs during testing that require more sub-item work, those fix PRs target `develop-<slug>` normally before the human re-issues the graduation command.

---

## Business Rules

- An integration branch is created when a development consists of two or more related backlog items. Single-item developments continue to target `develop` directly and are exempt from this workflow.
- The integration branch name must follow the pattern `develop-<slug>` (hyphen-separated). The `develop/<slug>` slash form is prohibited due to git's namespace conflict with the `develop` branch.
- Every PR for a sub-item belonging to an epic with the `integration-branch:<slug>` label must target `develop-<slug>`. This includes spec PRs, plan PRs, implementation PRs, and any fix or refactor PRs raised after the planned items are complete.
- CHANGELOG entries for sub-items are written normally under `[Unreleased]` on the integration branch using the standard per-item policy. No special CHANGELOG format is required for sub-items.
- The graduation PR must use a merge commit strategy. Squash and rebase are prohibited for graduation PRs.
- Graduation is always human-initiated via an explicit command. No agent graduates an integration branch without a human instruction.
- Keeping the integration branch up-to-date with `develop` is out of scope for the MVP. The human is responsible for pulling from `develop` manually before integration testing if needed.
- Hotfix and release workflows are orthogonal to integration branches and do not interact with them. Hotfixes branch from `main` and release branches branch from `develop`; neither targets or merges into an integration branch.
- Integration branches do not block releases. If a feature is not ready to graduate, its integration branch simply stays unmerged while releases proceed normally from `develop`.
- The product manager agent (spec stage) is responsible for identifying when a requested feature spans two or more distinct deliverable items and recommending the integration-branch workflow. This identification happens during the alignment conversation in the add-backlog-item or spec-writing stage.

---

## Acceptance Criteria

- [ ] When a human requests the creation of two or more related backlog items, the agent identifies the multi-item nature of the request and creates an epic grouping all sub-items, each labeled `integration-branch:<slug>`.
- [ ] A workflow agent processing a sub-item with the `integration-branch:<slug>` label opens all PRs for that sub-item (spec, plan, implementation, and any follow-on fix or refactor) targeting `develop-<slug>` instead of `develop`.
- [ ] An orchestrator agent creates the `develop-<slug>` branch from `develop` and pushes it to the remote before opening the first sub-item PR that would target it, if the branch does not already exist.
- [ ] The graduation command (`/graduate-development <slug>` or equivalent) opens a PR from `develop-<slug>` to `develop` with a summary of all included sub-items.
- [ ] The graduation PR uses a merge commit (not squash or rebase).
- [ ] The `develop-<slug>` branch is deleted after the graduation PR is successfully merged.
- [ ] Single-item developments (no epic, no `integration-branch` label) are unaffected: their PRs continue to target `develop` as before.
- [ ] The workflow documentation (relevant protocol files and the development workflow README) describes the integration branch concept, naming convention, label schema, and graduation command.

---

## Out of Scope (MVP)

- Automatically keeping the integration branch synchronized with `develop` (rebase or merge). The human pulls manually when needed.
- A UI or dashboard showing the status of all open integration branches and their sub-items.
- Automated detection that all sub-items are merged before allowing graduation — the graduation command verifies this, but there is no automated blocking gate on the integration branch itself.
- Support for nested integration branches (integration branches that themselves group other integration branches).
- Retroactive grouping of already-merged sub-item PRs into an integration branch after some have landed on `develop`.
- Changes to the hotfix or release branch workflows — they are orthogonal.
- Slug assignment logic — the add-backlog-item agent decides the slug; this spec does not prescribe the algorithm.
