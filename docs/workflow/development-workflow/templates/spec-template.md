# [Feature Name] — Spec

**Depends on**: <!-- List feature slugs this depends on, or remove this line -->

---

## Overview

<!-- 2-4 sentences describing what this feature does and why it exists. -->

**Language**: Describe outcomes in product and user terms. Do not use API field names, database column names, JSON keys, or code symbols in this document — use plain-language labels and map technical identifiers only in the implementation plan.

---

## Use Cases

### Use Case 1: [Name]

**Actor**: [Who initiates this action — user role]
**Preconditions**: [What must be true before this action can happen]

**Steps**:
1. [Step 1]
2. [Step 2]
3. ...

**Postconditions**: [What is true after the action succeeds]

**Information shown**:
- [What data the user sees on screen]

**Actions available**:
- [What the user can do from this state]

**Considerations**:
- [Edge cases, error states, or special scenarios]

---

### Use Case 2: [Name]

<!-- Repeat structure above for each use case -->

---

## Business Rules

- [Rule 1: an invariant that must always be true]
- [Rule 2]

---

## UX Rules

<!-- Delete this section if no UI is involved -->

- [UX rule 1: e.g., empty state shows X message]
- [UX rule 2: e.g., loading state must be shown while data fetches]

---

## Statuses / Enum Values

<!-- Delete this section if no statuses or enums are introduced -->

| Code value | Display label | Description |
|---|---|---|
| `pending` | Pending | [Description] |
| `active` | Active | [Description] |

**Valid transitions**:
- `pending` → `active` when [trigger]
- `active` → [next] when [trigger]

---

## Operational Visibility

<!-- Delete this section if this feature has no background/system-initiated actions -->

- **Logs**: [What is logged and where]
- **Notifications**: [Who is notified and when]
- **Audit trail**: [What events are recorded]

---

## Acceptance Criteria

<!-- Each criterion must be testable — a human can verify it by following a smoke test. -->

- [ ] [Criterion 1: e.g., "A user with role X can create a Y by doing Z. The created Y appears in the list."]
- [ ] [Criterion 2]
- [ ] [Criterion 3]

---

## Out of Scope (MVP)

<!-- Explicitly list what is NOT included in this iteration. -->

- [Out of scope item 1]
- [Out of scope item 2]

---

## Open Questions

<!-- List unresolved questions here. When all questions are answered, delete this entire section — the heading and everything below it. Do NOT replace it with a placeholder comment. -->

1. [Question 1]
2. [Question 2]
