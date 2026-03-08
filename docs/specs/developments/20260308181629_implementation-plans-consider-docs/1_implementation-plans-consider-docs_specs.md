# Implementation Plans Consider Project Documentation — Spec

**Status**: Spec Ready

---

## Guiding principle (important)

This stage is intentionally **product-focused**:

- Write **user-facing behavior**, permissions, UX rules, and acceptance criteria.
- Avoid prescribing **implementation details** (database tables/columns, specific endpoints, file paths, class names, or migration design). Those belong in the **Implementation Plan** stage.
- If a technical constraint matters to the product (e.g., “plan reviewers must check that doc updates are listed”), express it as a **product requirement** without mandating exact protocol text.

## Overview

Implementation plans produced in the Plan Ready stage often omit or under-specify which project documentation (under `docs/`) must be updated after implementation. The repository already provides an implementation plan template with a “Documentation Updates” section, but plan writers do not consistently use it and plan reviewers do not consistently enforce it. This feature fixes that workflow bug: plan writers must consider and list project doc updates where applicable, and plan reviewers must verify that the Documentation Updates section is present and meaningfully filled (or explicitly marked as not applicable).

---

## Use Cases

### Use Case 1: Tech lead produces an implementation plan that includes documentation impact

**Actor**: Tech lead (plan writer)
**Preconditions**: An approved spec exists for the development; the tech lead is writing the implementation plan from the template.

**Steps**:
1. Tech lead reads the spec and codebase to draft the implementation plan.
2. Tech lead considers which project docs (under `docs/`) are affected by the planned changes (e.g. `docs/project/*`, `AGENTS.md`, `docs/best-practices/*`, runbooks, architecture or repo-structure docs).
3. Tech lead fills the “Documentation Updates” section of the plan with concrete items (e.g. “`docs/project/2-repo-architecture.md` — add new package X”) or explicitly states that no project doc updates are required.
4. Tech lead submits the plan for review.

**Postconditions**: The implementation plan includes a Documentation Updates section that either lists specific doc updates or states that none are needed.

**Information shown**:
- The plan document, including the Documentation Updates section.

**Actions available**:
- Plan reviewer reviews the plan (including Documentation Updates).

**Considerations**:
- Some developments genuinely require no changes to project docs; “none required” is a valid outcome and must be explicit rather than an empty or missing section.

---

### Use Case 2: Plan reviewer verifies that documentation updates are addressed

**Actor**: Implementation plan reviewer
**Preconditions**: A draft implementation plan exists for a development with an approved spec.

**Steps**:
1. Reviewer checks that the plan uses the full template, including the “Documentation Updates” section.
2. Reviewer verifies that the section is meaningfully filled: either it lists specific docs and what to update, or it explicitly states that no project doc updates are required (with brief justification where helpful).
3. If the section is missing, empty, or vague (e.g. “update docs as needed”), reviewer requests revision.
4. Reviewer completes the rest of the plan review per existing protocol.

**Postconditions**: Only plans that properly address documentation updates (or explicitly waive them) pass the plan review.

**Information shown**:
- The plan document and the spec.

**Actions available**:
- Request revisions, or approve the plan.

**Considerations**:
- Reviewer must not invent doc-update requirements; they only enforce that the writer has considered and documented the decision.

---

## Business Rules

- Every implementation plan must contain a “Documentation Updates” section (as defined by the implementation plan template).
- The Documentation Updates section must be explicitly filled: either list specific files under `docs/` (or root-level docs like `AGENTS.md`) and what to update, or state that no project documentation updates are required.
- Plan reviewers must treat a missing, empty, or vague Documentation Updates section as a reason to request revision; they must not approve plans that omit this consideration.
- “Project documentation” means docs that describe the project, its architecture, repo structure, best practices, and runbooks (e.g. under `docs/` and root-level `AGENTS.md` / `README.md` as applicable). It does not mean inline code comments or API doc generators.

---

## Acceptance Criteria

- [ ] When a tech lead produces an implementation plan, the plan includes a “Documentation Updates” section that either (a) lists specific project docs and what to update, or (b) explicitly states that no project documentation updates are required.
- [ ] Plan reviewers reject or request revision of plans that lack a Documentation Updates section or that leave it empty or vague (e.g. “update docs as needed” with no specific files or “N/A” without stating no updates required).
- [ ] Given a plan with a missing or vague Documentation Updates section, a reviewer following the plan review protocol can identify it as a reason to request revision using only the plan document and the review checklist (no additional context required).

---

## Out of Scope (MVP)

- Changing the content or structure of individual project docs (e.g. rewriting `2-repo-architecture.md`); only the workflow for listing doc updates is in scope.
- Requiring updates to inline code documentation or generated API docs.
- Automating the actual editing of docs; the feature only requires that plans list what to update so the implementer can do it.
- Adding or changing UI for plan authoring or review; workflow and protocol changes only.

