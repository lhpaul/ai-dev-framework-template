# [Feature Name] — Implementation Plan

**Spec**: [Link to spec file]
**Smoke test runbook**: [Link to runbook file]

---

## Summary

**Approach**: [2-3 sentences describing the high-level technical approach]

**Estimated complexity**: S / M / L
<!-- S: < 1 day | M: 1-3 days | L: 3+ days -->
**Rationale**: [Why this complexity estimate]

**Dependencies**: [List any features that must be Merged/Released before implementation starts, or "None"]

---

## Verification Log

> Record reproducible plan-time verification commands that influenced scope, counts, or file lists. Include repo revision and concrete results.

| Check | Command / query | Result |
|---|---|---|
| Repo revision | `git rev-parse --short HEAD` | [short SHA] |
| [Pattern/search validation] | `[exact command]` | [count and key paths] |

---

## Layer-by-Layer Changes

> Delete any layers that don't apply to this feature.

### Database / Data Layer

- [ ] [Migration or schema change 1]
- [ ] [Seed data change: what data, in which file, for which test scenario]

### Backend / API

- [ ] [Endpoint or function 1: method, path/name, what it does]
- [ ] [Service or business logic change]

### Shared Packages / Libraries

- [ ] [Package name: what changes]

### Frontend / UI

- [ ] [Component or page 1: what changes]
- [ ] [Routing change]
- [ ] [State management change]

### Infrastructure / Configuration

- [ ] [Environment variable, config, or infra change]

---

## Testing Strategy

**Test types**: [Unit / Integration / Smoke / Manual]

**Key scenarios to test**:
1. [Scenario 1 — maps to Acceptance Criterion N]
2. [Scenario 2]

**Smoke test runbook**: `docs/testing/[section]/[slug].smoke-test.md`

**Regression suite**: If the repository has an automated regression test suite, include a checklist item in the relevant layer for a new regression spec that covers the smoke test runbook scenarios above. Omit this if no regression suite exists in the repository.

### Parser-risk addendum (include only when Step 3 classifier applies)

- **Edge-case enumeration**: List concrete parser/scanner inputs that cover boundary variants, negative lookalikes, multi-match lines, and nested/overlapping patterns when relevant.
- **Unit test mapping**: Name a unit test file and map at least one automated unit test per enumerated edge case.
- **Suppression semantics (if applicable)**: Name recognized suppression directives, allowed placement, and behavior when multiple suppressions appear on one line.

---

## Seed Data

> List the specific seed data needed to test this feature after implementation.

| Entity | Values / Scenario | File |
|---|---|---|
| [Entity name] | [Specific values to seed] | [File path] |

---

## Documentation Updates

> Consider project documentation in `docs/`: `docs/project/`, `docs/best-practices/`, `AGENTS.md`, and any feature- or domain-specific docs. List each file that the developer must update after implementation and what to change. Use "None" only when the feature truly affects no project docs. These updates are NOT performed during Plan Ready — only listed here for the developer to execute.

- [ ] `docs/project/[file].md` — [what to update]
- [ ] `AGENTS.md` — [if project overview, commands, or conventions need updating]
- [ ] *(or "None" with brief justification if no project docs are affected)*

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| [Risk 1] | Low/Med/High | Low/Med/High | [How to mitigate] |

---

## Code Samples

> **If this plan includes code samples, mark each one as illustrative** — for example with a comment like `// Illustrative — adapt during implementation`. Detailed, production-ready implementation code belongs in the implementation PR, not in the plan. Reviewers will treat unlabelled code samples as real code and flag syntax or API issues.
>
> **Consistency rule**: when the plan references the same concept in multiple sections (e.g., a secret storage mechanism, an API pattern, a naming convention), ensure all references are consistent. Contradictions between sections accumulate review cycles. Do a final cross-read before marking the plan ready.

---

## Implementation Order

> Ordered steps. Later steps may depend on earlier ones.

1. [Step 1: e.g., create DB migration]
2. [Step 2: e.g., update data access layer / generated types]
3. [Step 3: e.g., implement API endpoint]
4. [Step 4: e.g., implement UI component]
5. [Step 5: e.g., wire up routing]
6. [Step 6: e.g., update seed data]
7. [Step 7: e.g., verify smoke test runbook]
8. [Step 8: Update project docs per **Documentation Updates** section above (if any)]
9. [Step 9: e.g., update CHANGELOG]
