# Developer Agent: GitHub Actions Workflow Security Defaults — Spec

**Depends on**: none

---

## Overview

Pull requests that introduce or materially change GitHub Actions workflow files (`.github/workflows/*.yml`) have repeatedly incurred extra automated-review cycles when common security defaults are missing: broad default `GITHUB_TOKEN` permissions and unpinned third-party actions. Those gaps are well-documented CI hygiene; they should be satisfied **before** a development PR is opened, not discovered by external reviewers afterward.

This feature defines a **mandatory pre-PR checklist** for any implementation work that creates a new workflow file under `.github/workflows/` or makes a substantial change to an existing one (beyond trivial wording). The checklist is anchored in the repository’s implementation workflow documentation so every contributor—especially AI agents following `03-implement-development-protocol.md`—applies least-privilege token permissions, pins action versions to immutable SHAs, and considers path filters and concurrency where appropriate **before** the PR exists.

---

## Use Cases

### Use Case 1: Agent adds or rewrites a GitHub Actions workflow as part of a feature

**Actor**: AI developer agent (or human) executing the implementation-development protocol  
**Preconditions**: The planned change set includes a new file under `.github/workflows/*.yml` or edits that materially change job behavior, triggers, or security posture of an existing workflow (not a typo-only or comment-only tweak).

**Steps**:
1. Agent drafts the workflow YAML locally following repository conventions.
2. Before opening or updating the development PR, the agent walks the **GitHub Actions workflow security checklist** defined in the implementation protocol (see Business Rules).
3. The agent adjusts the workflow so every checklist item is satisfied or explicitly justified in the PR description when an exception is unavoidable.
4. Agent opens or updates the PR with the workflow changes.

**Postconditions**:
- The workflow declares explicit `permissions` scoped to the minimum required for the job (read-only work defaults to `contents: read` unless a broader permission is justified).
- Every `uses:` reference for third-party actions points to a full commit SHA, with the human-readable version called out in an adjacent comment.
- Where applicable, triggers are scoped with `paths` / `paths-ignore`, and concurrent runs are controlled with `concurrency`, matching the checklist guidance.

**Information shown**:
- Reviewers see a workflow that already meets the checklist, reducing Major automated-review findings for missing permissions or floating tags.

**Actions available**:
- If the checklist cannot be met without a product decision (e.g., workflow must write packages), the agent escalates with rationale before opening the PR.

**Considerations**:
- Trivial edits (spelling in comments, renaming a step title) do not trigger the full checklist; material changes do.

---

### Use Case 2: Agent’s PR does not touch workflow files

**Actor**: AI developer agent  
**Preconditions**: No changes under `.github/workflows/` are part of the branch.

**Steps**:
1. Agent completes implementation per protocol without applying the workflow checklist.

**Postconditions**:
- No requirement to apply the GitHub Actions workflow checklist for that PR.

---

### Use Case 3: Maintainer verifies documentation and agent behavior

**Actor**: Maintainer or workflow owner  
**Preconditions**: Spec is approved; subsequent plan/implementation will embed the checklist in documentation.

**Steps**:
1. Maintainer opens the implementation-development protocol (or linked canonical section).
2. Maintainer confirms the checklist is present, readable, and matches this spec’s Business Rules.
3. During review of a PR that adds or changes workflows, maintainer spot-checks that the checklist was followed.

**Postconditions**:
- Documentation is the source of truth for what “done” means before PR open for workflow changes.

---

## Business Rules

- The **GitHub Actions workflow security checklist** must live in or be linked prominently from `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` so agents using that protocol cannot miss it. A short standalone file under `docs/best-practices/stack/` is allowed only if the protocol links to it as canonical for this checklist (implementation-plan stage decides exact structure).
- For any new or materially changed workflow under `.github/workflows/*.yml`, the implementing agent must complete the checklist **before** opening the development PR (or before pushing workflow changes if the PR already exists and the agent is adding workflows in a follow-up commit—same gate: no workflow PR state without checklist compliance).
- The checklist must require, at minimum:
  - **Least-privilege `permissions`**: an explicit `permissions:` block at workflow or job level set to the minimum needed; when the job only reads repository content, default guidance is `contents: read` unless a broader permission is documented as required.
  - **Pinned actions**: every `uses:` reference uses the action’s full commit SHA with the release tag noted in a trailing comment (for example: `actions/checkout@<sha>  # v4.x.x`).
  - **Path filters**: when the workflow only needs to run for certain paths, `paths:` / `paths-ignore:` should be used on triggers.
  - **Concurrency**: when duplicate runs on the same ref would be harmful, a `concurrency:` group should be declared.
- Exceptions (e.g., a workflow that must `write` to `pull-requests`) must be justified in the PR description; the checklist still must be consciously completed, not skipped silently.

---

## Acceptance Criteria

- [ ] `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` contains a clearly titled section (or a single prominent link to a canonical subsection) for **GitHub Actions workflow security** used during implementation.
- [ ] That section includes an explicit checklist covering: explicit minimum `permissions:` (with default read-only guidance), pinning `uses:` to full SHAs with version comments, optional path-based triggers, and optional concurrency controls—aligned with the Business Rules above.
- [ ] The protocol text states that the checklist must be satisfied **before** a development PR is opened when the change adds or materially modifies `.github/workflows/*.yml`.
- [ ] A reviewer can confirm compliance by reading the protocol and the workflow file(s) in a single pass, without needing undocumented tribal knowledge.

---

## Out of Scope (MVP)

- Bulk retrofitting every existing workflow in the repository in one effort (each workflow may be updated opportunistically).
- Changing required GitHub App or organization policy settings, or third-party reviewer configurations (e.g., CodeRabbit rules).
- Prescribing specific SHA values (those drift; the requirement is the **pattern**, not particular pins).

---

## Open Questions

None — the backlog issue (#200) provides sufficient scope for the spec stage.
