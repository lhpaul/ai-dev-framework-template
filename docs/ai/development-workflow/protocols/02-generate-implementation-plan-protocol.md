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

- [ ] Which project docs need to be updated after implementation? (Note: docs are NOT updated during Plan Ready — only identified)

---

## Step 2: Approval Gate

Present the proposed approach to the human and ask for explicit approval:

> "I've outlined the technical approach. Would you like to review it before I write the full plan?"

Wait for confirmation. Do not write the plan until the approach is approved.

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
- Do not plan documentation updates — only list them for the developer to execute

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

## Step 5: Approval Gate

Present the plan and runbook to the human:

> "The implementation plan and smoke test runbook are ready. Would you like to review them before I create the PR?"

---

## Step 6: Git Execution

Once approved:

1. Determine the branch slug:
   - **With issue tracker**: `[issue-id]-[feature-slug]` (e.g., `ENG-123-user-auth`)
   - **Without issue tracker**: `[feature-slug]` (e.g., `user-auth`)
2. Create branch: `git checkout -b implementation-plan/[branch-slug]` from `develop`
3. Write the plan file
4. Write the smoke test runbook
5. Update the spec status from `Spec Ready` to `Plan Ready` (in the spec file's status field)
6. Commit: `docs: add implementation plan for [feature-name]`
7. Push and open PR targeting `develop` with:
   - Title: `docs(plan): [feature-name]`
   - Body: summary of the approach, complexity estimate, key risks, link to plan and runbook

---

## Step 7: PR Readiness

Apply `agent:ready-for-review` label once CI is green.

See `docs/ai/development-workflow/protocols/91-pr-readiness-signal-protocol.md`.

