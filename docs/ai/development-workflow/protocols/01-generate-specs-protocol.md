# Protocol: Generate Feature Spec (Spec Ready Stage)

**Agent role**: Product Manager
**Stage**: Spec Ready
**Output**: Spec document in `docs/specs/developments/[YYYYMMDDHHMMSS]_[feature-slug]/1_[feature-slug]_specs.md`

---

## Product-first boundary (critical)

The **Spec Ready** stage is intentionally **product-focused**. It must answer:

- What should the feature do?
- Who can do it?
- What are the rules and UX expectations?
- How do we verify it’s done?

It should **not** prescribe technical design (DB schema changes, table/column names, migration approaches, endpoint/service/class/file naming). Those are the responsibility of the **Plan Ready (Implementation Plan)** stage.

If the human brings up technical details during alignment, reframe them into **product constraints** and record the technical choice as “to be decided in the implementation plan”.

### Examples

- ✅ Good (product constraint): “An agent can belong to multiple broker companies in the future; this module is scoped to the selected company.”
- ❌ Too technical for spec: “Use `public.agents` + `public.agent_memberships` and keep the API 1:1 under the hood.”

## Prerequisites

Before starting, read:

- `docs/project/1-business-domain.md` — domain context, entities, glossary
- `docs/project/3-software-architecture.md` — architecture constraints
- The feature brief. If you have an issue tracker configured, follow `docs/ai/development-workflow/integrations/issue-tracker.md` to get the current brief.

---

## Step 1: Mandatory Alignment Conversation

Before writing anything, have a structured conversation with the human to gather all necessary information. Do not skip or abbreviate this step — incomplete alignment produces poor specs.

If an issue tracker exists for this item, start by summarizing what you read from the issue (title/description + recent comments). If the human manually pasted this context for you, skip the summary. Then confirm with the human:

- “Is this still the current and intended scope?”
- “Are there any other decisions or constraints not captured here?”

Work through the following checklist. Ask about each item. If the human can't answer something, note it as an **Open Question** (see Step 2).

### Alignment Checklist

#### Core Objective

- [ ] Feature name and slug (for file naming)
- [ ] Which part of the product does this affect? (which app, which section)
- [ ] Is this a new capability or a change to an existing one?
- [ ] What depends on this feature? What does this feature depend on?

#### Actors & Use Cases

- [ ] Who initiates the action (which user role)?
- [ ] What is the precondition (what must be true before the action)?
- [ ] What are the steps the user takes?
- [ ] What is the successful outcome (postcondition)?
- [ ] What information does the user see?
- [ ] What actions can the user take?
- [ ] Are there any error or edge case flows?

#### Business Rules

- [ ] What invariants must always be true?
- [ ] What constraints or validations apply?
- [ ] Are there any rate limits, quotas, or permission restrictions?

#### UX Rules (if the feature has UI)

- [ ] What should the empty state look like?
- [ ] Are there loading, error, and success states to define?
- [ ] Any specific layout or interaction requirements?

#### Status & Lifecycle (if the feature involves entities with states)

- [ ] What are the possible statuses/states?
- [ ] What are the valid transitions?
- [ ] What display labels should statuses have (for the UI)?

#### Operational Visibility (if the feature involves background or system-initiated actions)

- [ ] How does an admin or operator know the action happened?
- [ ] Are there notifications, logs, or audit events?

#### Success Criteria

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

```markdown
docs/specs/developments/[YYYYMMDDHHMMSS]_[feature-slug]/1_[feature-slug]_specs.md
```

Use the current timestamp for `YYYYMMDDHHMMSS`.

**Quality guardrails**:

- Every acceptance criterion must be testable — a human can verify it by running through the smoke test
- Enum values and statuses must include their UI display labels (not raw code values)
- If the feature has multiple actors, each actor gets its own use case section
- Explicitly list what is **out of scope** for this feature (MVP boundary)
- Keep spec decisions **product-facing**; defer technical design to the implementation plan

### Examples

```markdown
# Spec: [feature-name]
...
```

---

## Step 4: Human Review Shortcut (Optional)

Default behavior is **max autonomy**: once the alignment conversation is complete and there are no unresolved blocking product questions, continue through branch creation, the review gate, PR creation, and PR readiness without asking for an extra "review before PR" confirmation.

Pause only if:

- The human explicitly asked to review the draft before Git operations
- The spec still contains a blocking product ambiguity
- The reviewer gate returns `NEEDS REVISION` for a product decision you cannot make unilaterally

---

## Step 5: Git Execution

If no blocking human decision remains:

1. Determine the branch slug:
   - **With issue tracker**: `[issue-id]-[feature-slug]` (e.g., `ENG-123-user-auth`)
   - **Without issue tracker**: `[feature-slug]` (e.g., `user-auth`)
2. Create branch: `git checkout -b spec/[branch-slug]` from `develop`
3. Create the development folder: `docs/specs/developments/[YYYYMMDDHHMMSS]_[feature-slug]/`
4. Write the spec file: `1_[feature-slug]_specs.md`
5. Commit: `docs: add spec for [feature-name]`
6. Push: `git push -u origin spec/[branch-slug]`
7. **Reviewer gate (before opening PR)**:
   - Run the spec review gate on this branch using `REVIEW.md`
   - If your runner has a native review feature, use it against `REVIEW.md`; otherwise use the compatibility wrapper `docs/ai/development-workflow/protocols/01-review-specs-protocol.md`
   - Apply fixes directly on the branch, commit, and push again if needed
   - If the verdict is **NEEDS REVISION** due to product decisions, stop and request human input before opening a PR
8. Open PR targeting `develop` with:
   - Title: `docs(spec): [feature-name]`
   - Body: summary of the feature, link to the spec file, list of open questions (if any)
9. Resolve PR readiness to completion:
   - Run `./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch spec/[branch-slug]` when an automated review platform is configured
   - If blocking comments exist, continue fixing them on the same branch until the loop is clean or escalates
   - Run `./scripts/development-workflow/pr-ci-loop.sh <pr_number>`
   - Apply `agent:ready-for-review` only after CI is green and automated review is clean (or skipped)

---

## Step 6: PR Readiness

Do not treat "PR opened" as completion. This stage is complete only when one of the following terminal conditions is reached:

- `agent:ready-for-review` has been applied and the PR is waiting on a human merge decision
- A blocking product question surfaced and the run has explicitly escalated to the human
- The automated review or CI loop timed out and the run has escalated to the human

See `docs/ai/development-workflow/protocols/91-pr-readiness-signal-protocol.md` for the full readiness definition.
