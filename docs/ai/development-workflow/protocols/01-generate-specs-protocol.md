# Protocol: Generate Feature Spec (Spec Ready Stage)

**Agent role**: Product Manager
**Stage**: Spec Ready
**Output**: Spec document in `docs/specs/developments/[YYYYMMDDHHMMSS]_[feature-slug]/1_[feature-slug]_specs.md`

---

## Prerequisites

Before starting, read:
- `docs/project/1-business-domain.md` — domain context, entities, glossary
- `docs/project/3-software-architecture.md` — architecture constraints
- The feature brief or issue provided by the human

---

## Step 1: Mandatory Alignment Conversation

Before writing anything, have a structured conversation with the human to gather all necessary information. Do not skip or abbreviate this step — incomplete alignment produces poor specs.

Work through the following checklist. Ask about each item. If the human can't answer something, note it as an **Open Question** (see Step 2).

### Alignment Checklist

**Scope & Identity**
- [ ] Feature name and slug (for file naming)
- [ ] Which part of the product does this affect? (which app, which section)
- [ ] Is this a new capability or a change to an existing one?
- [ ] What depends on this feature? What does this feature depend on?

**Actors & Use Cases**
- [ ] Who initiates the action (which user role)?
- [ ] What is the precondition (what must be true before the action)?
- [ ] What are the steps the user takes?
- [ ] What is the successful outcome (postcondition)?
- [ ] What information does the user see?
- [ ] What actions can the user take?
- [ ] Are there any error or edge case flows?

**Business Rules**
- [ ] What invariants must always be true?
- [ ] What constraints or validations apply?
- [ ] Are there any rate limits, quotas, or permission restrictions?

**UX Rules** (if the feature has UI)
- [ ] What should the empty state look like?
- [ ] Are there loading, error, and success states to define?
- [ ] Any specific layout or interaction requirements?

**Status & Lifecycle** (if the feature involves entities with states)
- [ ] What are the possible statuses/states?
- [ ] What are the valid transitions?
- [ ] What display labels should statuses have (for the UI)?

**Operational Visibility** (if the feature involves background or system-initiated actions)
- [ ] How does an admin or operator know the action happened?
- [ ] Are there notifications, logs, or audit events?

**Acceptance Criteria**
- [ ] How do we know when this feature is done?
- [ ] What must be testable?

---

## Step 2: Open Questions Discipline

After the alignment conversation, list any questions that remain unanswered. These become the **Open Questions** section of the spec.

Rules:
- Do not invent answers to open questions — list them explicitly
- Do not block on open questions if enough is known to start; begin the spec and revisit
- When the human answers an open question, update the spec immediately and remove it from the list
- If an open question is blocking, escalate to the human before proceeding

---

## Step 3: Write the Spec

Using the template at `docs/ai/development-workflow/templates/spec-template.md`, write the spec document.

**Output location**:
```
docs/specs/developments/[YYYYMMDDHHMMSS]_[feature-slug]/1_[feature-slug]_specs.md
```

Use the current timestamp for `YYYYMMDDHHMMSS`.

**Quality guardrails**:
- Every acceptance criterion must be testable — a human can verify it by running through the smoke test
- Enum values and statuses must include their UI display labels (not raw code values)
- If the feature has multiple actors, each actor gets its own use case section
- Explicitly list what is **out of scope** for this feature (MVP boundary)

---

## Step 4: Approval Gate

Before any Git operations, present the spec to the human and ask for explicit approval:

> "I've drafted the spec. Would you like to review it before I create the branch and PR?"

Wait for confirmation. Do not proceed to Git operations without approval.

If the human requests changes, make them and re-present. Repeat until approved.

---

## Step 5: Git Execution

Once the human approves the spec:

1. Determine the branch slug:
   - **With issue tracker**: `[issue-id]-[feature-slug]` (e.g., `ENG-123-user-auth`)
   - **Without issue tracker**: `[feature-slug]` (e.g., `user-auth`)
2. Create branch: `git checkout -b spec/[branch-slug]` from `develop`
3. Create the development folder: `docs/specs/developments/[YYYYMMDDHHMMSS]_[feature-slug]/`
4. Write the spec file: `1_[feature-slug]_specs.md`
5. Commit: `docs: add spec for [feature-name]`
6. Push: `git push -u origin spec/[branch-slug]`
7. Open PR targeting `develop` with:
   - Title: `docs(spec): [feature-name]`
   - Body: summary of the feature, link to the spec file, list of open questions (if any)

---

## Step 6: PR Readiness

Apply the `agent:ready-for-review` label to the PR once it is open and CI is green.

If CI fails, investigate and fix before applying the label.

See `docs/ai/development-workflow/protocols/91-pr-readiness-signal-protocol.md` for the full readiness definition.
