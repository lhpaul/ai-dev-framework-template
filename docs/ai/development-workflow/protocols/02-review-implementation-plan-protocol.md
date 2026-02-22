# Protocol: Review Implementation Plan (Plan Review)

**Agent role**: Implementation Plan Reviewer
**Stage**: Plan Review (after Plan Ready PR is opened)
**Output**: Fixes applied directly + review report

---

## Prerequisites

Before reviewing, read:
- The corresponding spec: `docs/specs/developments/[folder]/1_[slug]_specs.md`
- The plan to be reviewed: `docs/specs/developments/[folder]/2_[slug]_implementation-plan.md`
- The smoke test runbook: `docs/testing/[section]/[slug].smoke-test.md`
- `docs/project/2-repo-architecture.md`
- `docs/project/3-software-architecture.md`
- `docs/best-practices/` — all best practice docs
- Relevant existing code — read actual files to validate feasibility

### Locating the plan to review

Priority order:
1. Explicit path provided by the human
2. Files changed in the current branch (`git diff main...HEAD`)
3. Ask the human

---

## Review Checklist

### 1. Spec Alignment

- [ ] Every use case in the spec has a corresponding implementation step
- [ ] Every acceptance criterion in the spec is addressed somewhere in the plan
- [ ] No changes planned that are not motivated by the spec (no unrelated refactoring)
- [ ] The spec status has been updated to `Plan Ready`

### 2. Template Completeness

- [ ] All required sections from `docs/ai/development-workflow/templates/implementation-plan-template.md` are present
- [ ] Complexity estimate is provided with rationale
- [ ] Dependencies are declared

### 3. Specificity & Implementability

- [ ] Each step is specific enough that a developer can execute it without guessing
- [ ] The implementation order is logical (no step requires a later step to be done first)
- [ ] Seed data requirements are explicit (what data, which files, which scenarios)
- [ ] No vague steps like "update UI as needed" — each UI change is described

### 4. Architecture & Feasibility

- [ ] The approach is consistent with `docs/project/3-software-architecture.md`
- [ ] No invented patterns or abstractions that don't exist in the codebase
- [ ] Database changes are safe (no destructive migrations without explicit justification)
- [ ] No steps that would violate the security model in `docs/project/4-database-model.md`

### 5. Testing & Smoke Test Coverage

- [ ] The smoke test runbook exists and is linked from the plan
- [ ] The runbook covers all acceptance criteria from the spec
- [ ] Seed data needed for smoke tests is included in the seed data section of the plan

---

## How to Apply Fixes

**Fix directly** (without asking) for:
- Missing sections (add with a `TODO` placeholder if content requires human input)
- Implementation steps that are too vague (make them more specific based on the codebase)
- Missing seed data entries that can be inferred from the spec
- Formatting and link issues

**Report only** (do not fix) when:
- The approach requires a product/design decision
- The plan contradicts the spec and the resolution is ambiguous
- A feasibility concern requires a human decision (e.g., the planned approach would be significantly more complex than estimated)

---

## Output Format

```
## Implementation Plan Review: [feature-name]

### Overall Assessment
[One paragraph — is the plan ready to move to In Development?]

### Spec Alignment
[Table mapping spec acceptance criteria to plan steps]

### Template Coverage
[Checklist of required sections]

### Issues Fixed
[List of changes made directly to the plan]

### Issues Requiring Human Input
[List of items needing a human decision]

### Verdict
[ ] APPROVED — ready to move to In Development
[ ] NEEDS REVISION — human input required on the items listed above
```
