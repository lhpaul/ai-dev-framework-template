# Protocol: Generate Implementation Plan (Plan Ready Stage)

**Agent role**: Tech Lead
**Stage**: Plan Ready
**Output**: Implementation plan in `docs/specs/developments/[timestamp]_[feature-slug]/2_[feature-slug]_implementation-plan.md` + smoke test runbook in `docs/testing/`

---

## Prerequisites

Before starting, read:

- The approved spec: `docs/specs/developments/[timestamp]_[feature-slug]/1_[feature-slug]_specs.md`
- `docs/project/2-repo-architecture.md` — repository structure
- `docs/project/3-software-architecture.md` — tech stack and design patterns
- `docs/project/4-database-model.md` — data model (if applicable)
- `docs/best-practices/` — all best practice docs
- Relevant existing code — read actual files, don't assume structure
- **Project documentation**: Scan `docs/` (e.g. `docs/project/`, `docs/best-practices/`, `AGENTS.md`, and any feature- or domain-specific docs) so the plan can explicitly list which of these need updates after implementation.
- If an issue tracker exists for this item, follow `docs/ai/development-workflow/integrations/issue-tracker.md` for `Plan Ready` expectations before planning.

---

## Step 1: Mandatory Alignment Conversation

Before writing the plan, discuss the technical approach with the human. Work through the following items:

### Alignment Checklist

#### Approach & Complexity

- [ ] High-level technical approach — what layers need to change?
- [ ] Estimated complexity: Small (S), Medium (M), Large (L) — and rationale
- [ ] Key risks or unknowns

#### Dependencies

- [ ] Does this feature depend on any other feature being Merged/Released first?
- [ ] Any external service dependencies?

#### Layer-by-Layer Changes

For each layer affected, confirm what changes are needed:

- [ ] Database (schema, migrations, seed data changes)
- [ ] Backend / API (endpoints, services, functions)
- [ ] Shared packages / libraries
- [ ] Frontend / UI (components, routing, state)
- [ ] Infrastructure / configuration

#### Testing Strategy

- [ ] What test types apply? (unit, integration, end-to-end/smoke)
- [ ] What scenarios must be covered?
- [ ] What seed data is needed?

#### Implementation Order

- [ ] What must be done first? (e.g., DB migration before API before UI)
- [ ] Are there any circular dependencies in the implementation?

#### Documentation Updates

- [ ] Which project docs in `docs/` need to be updated after implementation? Consider `docs/project/`, `docs/best-practices/`, `AGENTS.md`, and any feature-specific docs. (Note: docs are NOT updated during Plan Ready — only identified and listed in the plan.)

---

## Step 2: Human Review Shortcut (Optional)

Default behavior is **max autonomy**: once you have read the approved spec, inspected the codebase, and there is no unresolved architectural ambiguity, continue through plan writing, reviewer gate, PR creation, and PR readiness without an extra pause.

Pause only if:

- The human explicitly asked to review the approach before plan writing
- The proposed approach has a material architecture tradeoff or ambiguity you cannot resolve safely
- The reviewer gate returns `NEEDS REVISION` for a decision that requires human input

---

## Step 3: Write the Implementation Plan

Using the template at `docs/ai/development-workflow/templates/implementation-plan-template.md`, write the implementation plan.

**Output location**:

```markdown
docs/specs/developments/[timestamp]_[feature-slug]/2_[feature-slug]_implementation-plan.md
```

**Quality guardrails**:

- All layers that will change must be covered
- The implementation order must be logical and executable (no steps that require a later step to be done first)
- Every change must reference an acceptance criterion from the spec
- Seed data requirements must be explicit — what data, in which files, for which test scenarios
- **Documentation**: Explicitly consider project documentation in `docs/`. The plan must list every doc in `docs/` (including `AGENTS.md` if relevant) that the developer must update after implementation, or state "None" only when the feature truly affects no project docs. Do not plan the doc edits — only list them for the developer to execute.

### Examples

```markdown
# Implementation Plan: [slug]
...
```

---

## Step 4: Write the Smoke Test Runbook

Create the smoke test runbook using the template at `docs/ai/development-workflow/templates/smoke-test-runbook-template.md`.

**Output location**:

```markdown
docs/testing/[app-or-section]/[feature-slug].smoke-test.md
```

The runbook must cover all acceptance criteria from the spec. Each criterion must have at least one testable step.

---

## Step 5: Git Execution

If no blocking human decision remains:

1. Determine the branch slug:
   - **With issue tracker**: `[issue-id]-[feature-slug]` (e.g., `ENG-123-user-auth`)
   - **Without issue tracker**: `[feature-slug]` (e.g., `user-auth`)
2. Create branch: `git checkout -b implementation-plan/[branch-slug]` from `develop`
3. Write the plan file
4. Write the smoke test runbook
5. **When the issue tracker is the source of truth**: update the issue status to `Plan Ready`; optionally also update the spec file's status field for backwards compatibility. **Otherwise (no issue tracker)**: update the spec file's status field to `Plan Ready` so the plan review checklist passes.
6. Commit: `docs: add implementation plan for [feature-name]`
7. Push: `git push -u origin implementation-plan/[branch-slug]`
8. **Reviewer gate (before opening PR)**:
   - Run the implementation plan reviewer protocol on this branch: `docs/ai/development-workflow/protocols/02-review-implementation-plan-protocol.md`
   - If your runner supports it, dispatch a dedicated `implementation-plan-reviewer` agent; otherwise self-review using the protocol checklist
   - Apply fixes directly on the branch, commit, and push again if needed
   - If the verdict is **NEEDS REVISION** due to plan/approach decisions, stop and request human input before opening a PR
9. Open PR targeting `develop` with:
   - Title: `docs(plan): [feature-name]`
   - Body: summary of the approach, complexity estimate, key risks, link to plan and runbook
10. Resolve PR readiness to completion:
   - Run `./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch implementation-plan/[branch-slug]` when an automated review platform is configured
   - If blocking comments exist, continue fixing them on the same branch until the loop is clean or escalates
   - Run `./scripts/development-workflow/pr-ci-loop.sh <pr_number>`
   - Apply `agent:ready-for-review` only after CI is green and automated review is clean (or skipped)

---

## Step 6: PR Readiness

Do not treat "plan written" or "PR opened" as completion. This stage is complete only when one of the following terminal conditions is reached:

- `agent:ready-for-review` has been applied and the PR is waiting on a human merge decision
- A blocking plan / architecture decision surfaced and the run has escalated to the human
- The automated review or CI loop timed out and the run has escalated to the human

See `docs/ai/development-workflow/protocols/91-pr-readiness-signal-protocol.md`.
