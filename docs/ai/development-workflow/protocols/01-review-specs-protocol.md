# Protocol: Review Feature Spec (Spec Review)

**Agent role**: Spec Reviewer
**Stage**: Spec Review (after Spec Ready PR is opened)
**Output**: Fixes applied directly + review report

---

## Prerequisites

Before reviewing, read:
- `docs/project/1-business-domain.md` — domain context and glossary
- `docs/project/3-software-architecture.md` — architecture constraints
- The spec to be reviewed

### Locating the spec to review

Priority order:
1. Explicit path provided by the human (`docs/specs/developments/[folder]/1_[slug]_specs.md`)
2. The spec file changed in the current branch (`git diff main...HEAD`)
3. Ask the human

---

## Review Checklist

### 1. Template Compliance

- [ ] All required sections from `docs/ai/development-workflow/templates/spec-template.md` are present
- [ ] Status field is correct (`Spec Ready`)
- [ ] No placeholder text left unfilled (unless explicitly marked as Open Question)

### 2. Completeness & Clarity

- [ ] The feature name and slug are clear
- [ ] At least one use case is fully defined (actor, preconditions, steps, postconditions)
- [ ] Every use case has a clear actor and trigger
- [ ] Error cases and edge cases are addressed or explicitly deferred to a later iteration
- [ ] The MVP scope boundary is explicit (what's out of scope)

### 3. Business Rules

- [ ] Business rules are listed and unambiguous
- [ ] No two rules contradict each other
- [ ] Rules are enforceable (not vague aspirations)

### 4. Acceptance Criteria

- [ ] At least one acceptance criterion per use case
- [ ] Every criterion is testable — a human can verify it by following a smoke test
- [ ] No criterion is ambiguous ("it works" is not a valid criterion)

### 5. Status & Enum Discipline

- [ ] If the feature introduces statuses or enum values, each has a defined UI display label
- [ ] Status transitions are defined (from → to, trigger)
- [ ] No raw code values exposed in the spec as if they were the display labels

### 6. Consistency with Project Conventions

- [ ] Entity names match `docs/project/1-business-domain.md`
- [ ] No new entities introduced without a description
- [ ] The feature doesn't contradict existing business rules

---

## How to Apply Fixes

**Fix directly** (without asking) for:
- Missing required sections (add them with placeholder content marked `TODO`)
- Ambiguous acceptance criteria (rewrite to be testable)
- Missing display labels for enums/statuses
- Typos, formatting issues, broken links

**Report only** (do not fix) when:
- A product decision is needed (e.g., "should this also apply to admin users?")
- The scope boundary is unclear and needs human input
- A business rule is missing or contradictory and requires clarification

---

## Output Format

Deliver a review report with:

```
## Spec Review: [feature-name]

### Overall Assessment
[One paragraph summary — is the spec ready to move to Plan Ready?]

### Template Coverage
[Table or checklist showing which sections are present/missing]

### Issues Fixed
[List of changes made directly to the spec]

### Issues Requiring Human Input
[List of items that need a product/design decision]

### Open Questions
[Carry over any open questions from the spec, plus any new ones surfaced during review]

### Verdict
[ ] APPROVED — ready to move to Plan Ready
[ ] NEEDS REVISION — human input required on the items listed above
```
