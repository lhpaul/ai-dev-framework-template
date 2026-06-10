# Smoke Test Runbook: Development Integration Branches

**Feature**: Development Integration Branches (#628)
**Spec**: [1_628-development-integration-branches_specs.md](../../specs/developments/20260515122533_628-development-integration-branches/1_628-development-integration-branches_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] This repository is the ai-dev-framework-template or a downstream repo with the same workflow tooling.
- [ ] `gh` CLI is authenticated to a repository where you can create issues, labels, and branches.
- [ ] You have a local clone with `develop` checked out and up to date.
- [ ] The implementation PRs for #628 are merged to `develop`.

---

## Test Data

| Item                    | Value                                          |
| ----------------------- | ---------------------------------------------- |
| Epic slug               | `test-integration-smoke`                       |
| Integration branch name | `develop-test-integration-smoke`               |
| Sub-item label          | `integration-branch:test-integration-smoke`    |
| Test repository         | Current repository (ai-dev-framework-template) |

---

## Smoke Test Steps

### Step 1: Verify the add-backlog-item protocol describes multi-item epic detection

**Maps to**: Acceptance Criterion 8 (documentation files describe the concept)

1. Open `docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md`.
2. Confirm a section exists that covers:
   - Identifying a multi-item request
   - Choosing a slug
   - Creating an epic issue with the `epic` label
   - Applying `integration-branch:<slug>` to each sub-item
   - Linking native GitHub sub-issues with `addSubIssue` when supported
   - Verifying both `subIssues` on the epic and `parent` on each sub-item
3. Confirm the single-item exemption is stated.

**Expected result**: The protocol contains the multi-item epic detection section with all seven sub-steps above.

---

### Step 2: Verify protocols 90 and 91 describe the base-branch override

**Maps to**: Acceptance Criterion 2 and 3 (documentation files describe PR targeting and branch creation)

1. Open `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`.
2. Search for "integration-branch".
3. Confirm the portfolio orchestrator step describes:
   - Reading the `integration-branch:<slug>` label from the sub-item
   - Deriving `develop-<slug>`
   - Creating `develop-<slug>` from `develop` if it does not exist
   - Passing `BASE_BRANCH=develop-<slug>` in the handoff

4. Open `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`.
5. Search for "integration-branch".
6. Confirm the work item runner step describes:
   - The same label check
   - Integration branch creation if missing
   - Base-branch override for all PRs

**Expected result**: Both protocols contain the integration-branch base-override section with label check, branch creation, and handoff metadata.

---

### Step 3: Verify the graduation protocol exists and is complete

**Maps to**: Acceptance Criteria 4, 5, 6 (graduation command, merge commit, branch deletion)

1. Open `docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md`.
2. Confirm the file exists.
3. Confirm it contains:
   - Step 1: Resolve slug → `develop-<slug>`
   - Step 2: Verify all sub-items are merged (blocking gate), preferring native GitHub sub-issues and falling back to `integration-branch:<slug>` labels for legacy epics
   - Step 3: Open graduation PR with merge-commit note and sub-item summary
   - Step 4: Run reviewer loop and CI
   - Step 5: Delete `develop-<slug>` after merge

**Expected result**: The protocol file exists and contains all five steps above.

---

### Step 4: Verify the README documents the branch type and graduation command

**Maps to**: Acceptance Criterion 8

1. Open `docs/workflow/development-workflow/README.md`.
2. In the "Branch Naming" table, confirm a row for `develop-<slug>` exists.
3. In the "Commands By Stage" table, confirm a row for "Graduate integration branch" exists referencing `05b-graduate-development-protocol.md`.

**Expected result**: Both table rows are present.

---

### Step 5: Verify developer protocol contains the base-branch note

**Maps to**: Acceptance Criterion 2 (all PR types for a sub-item target `develop-<slug>`)

1. Open `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`.
2. Search for "integration-branch".
3. Confirm a note exists near the branching step instructing the developer to use `develop-<slug>` when the label is present.

**Expected result**: The note is present and references the `integration-branch:<slug>` label check.

---

### Step 6: Verify single-item developments are unaffected (dry-run reasoning)

**Maps to**: Acceptance Criterion 7

1. In protocols 90 and 91, confirm each integration-branch section has an explicit "single-item exemption" or equivalent guard that skips the label check when no `integration-branch:*` label is present.
2. In protocol 03, confirm the branching note is conditional on the `integration-branch:<slug>` label (so unlabeled items keep default behavior).
3. Confirm the default base branch (`develop`) is still used when the label is absent.

**Expected result**: Each affected protocol contains an explicit guard preserving the existing behavior for single-item developments.

---

### Step 7: Verify native GitHub sub-issue guidance

**Maps to**: Native sub-issue creation, verification, and fallback requirements

1. Open `docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md`.
2. Search for `addSubIssue`.
3. Confirm the protocol shows how to resolve `EPIC_ID` and `SUB_ISSUE_ID`, call the GraphQL mutation, and preserve the `integration-branch:<slug>` label as the automation contract.
4. Search for `subIssues(first: 50)`, `pageInfo { hasNextPage endCursor }`, and `parent { number title }`.
5. Confirm the protocol includes both epic-side and child-side verification commands, including pagination guidance for large epics.
6. Open `docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md`.
7. Confirm graduation discovery prefers native `subIssues`, verifies child-side `parent`, documents native pagination handling, and still documents the `--limit 1000` label fallback for legacy epics.

**Expected result**: Native GitHub sub-issues are the preferred grouping relationship for GitHub providers, while the existing integration-branch label remains the base-branch routing contract and fallback discovery path.

---

### Last Step: Assertions checklist

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC 1: `00-add-backlog-item-protocol.md` contains the multi-item epic detection step with epic creation, slug derivation, and `integration-branch:<slug>` label application.
- [ ] AC 2: Protocols 90, 91, and 03 describe opening all PRs for a labeled sub-item against `develop-<slug>` instead of `develop`.
- [ ] AC 3: Protocols 90 and 91 describe creating `develop-<slug>` from `develop` if it does not exist before the first sub-item PR.
- [ ] AC 4: `05b-graduate-development-protocol.md` exists and opens a PR from `develop-<slug>` to `develop` with a sub-item summary.
- [ ] AC 5: The graduation protocol states the merge strategy must be a **merge commit** (not squash or rebase).
- [ ] AC 6: The graduation protocol's Step 5 deletes `develop-<slug>` after the graduation PR is merged.
- [ ] AC 7: Protocols 90 and 91 contain explicit single-item exemption guards, and protocol 03 conditionally applies `develop-<slug>` only when `integration-branch:<slug>` is present.
- [ ] AC 8: The following five files all contain integration-branch concept, naming convention, label schema, and/or graduation command: `docs/workflow/development-workflow/README.md`, `00-add-backlog-item-protocol.md`, `90-batch-orchestrate-work-protocol.md`, `91-orchestrate-work-protocol.md`, `05b-graduate-development-protocol.md`.
- [ ] #884: GitHub-provider multi-item backlog creation requires native sub-issues when supported, verifies epic-side `subIssues` and child-side `parent`, and documents label-only fallback for unsupported repositories.

---

## Seed Data Reference

No seed data required. This smoke test validates documentation content only.

---

## Troubleshooting

| Symptom                                                 | Likely cause                                       | Fix                                                                |
| ------------------------------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------ |
| `05b-graduate-development-protocol.md` not found        | Implementation step skipped or file path incorrect | Check `docs/workflow/development-workflow/protocols/` for the file |
| Protocol 90 or 91 has no "integration-branch" section   | Implementation step incomplete                     | Re-run the implementation for the affected protocol                |
| README branch-naming table missing `develop-<slug>` row | README update was skipped                          | Add the row per Implementation Order Step 2a                       |

---

## Known Limitations

- This runbook validates documentation content by manual inspection only. There are no automated tests that execute the integration-branch workflow end-to-end (creating real branches, labels, and PRs). An end-to-end test would require a dedicated test repository and is out of scope for the MVP.
