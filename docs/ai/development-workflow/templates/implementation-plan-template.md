# [Feature Name] — Implementation Plan

**Status**: Plan Ready
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

**Smoke test runbook**: [`docs/testing/[section]/[slug].smoke-test.md`](../../testing/[section]/[slug].smoke-test.md)

---

## Seed Data

> List the specific seed data needed to test this feature after implementation.

| Entity | Values / Scenario | File |
|---|---|---|
| [Entity name] | [Specific values to seed] | [File path] |

---

## Documentation Updates

> List docs that need to be updated after implementation. These are NOT performed during Plan Ready.

- [ ] `docs/project/[file].md` — [what to update]
- [ ] `AGENTS.md` — [if project overview needs updating]

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| [Risk 1] | Low/Med/High | Low/Med/High | [How to mitigate] |

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
8. [Step 8: e.g., update CHANGELOG]
