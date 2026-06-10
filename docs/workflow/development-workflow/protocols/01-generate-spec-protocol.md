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

### Product Constraint Examples

- ✅ Good (product constraint): “An agent can belong to multiple broker companies in the future; this module is scoped to the selected company.”
- ❌ Too technical for spec: “Use `public.agents` + `public.agent_memberships` and keep the API 1:1 under the hood.”

## Prerequisites

Before starting, read:

- `docs/project/1-business-domain.md` — domain context, entities, glossary
- `docs/project/3-software-architecture.md` — architecture constraints
- The feature brief. If you have an issue tracker configured, follow `docs/workflow/development-workflow/integrations/issue-tracker.md` to get the current brief.

**Tracker workflow status**: The **Work Item Runner** owns workflow-status transitions for this stage. When this protocol is run under normal orchestration, expect the runner to set **Writing Spec** before dispatch, **Spec in Review** when the PR is human-ready, and **Spec Ready** only after merge. If you invoke this protocol standalone, mirror the same status progression manually.

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

#### Measurement Requirements (if product analytics matter)

- [ ] Which user actions, funnels, or outcomes should be measured?
- [ ] What product questions should this feature help answer?
- [ ] Are there privacy, consent, retention, or anonymization constraints that must shape the analytics requirements?

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
- When all questions are resolved, **delete the entire Open Questions section** — the heading (`## Open Questions`) and its entire body. Do NOT leave the heading in place or replace the content with a placeholder comment such as `<!-- No open questions at this time -->`
- If an open question is blocking, escalate to the human before proceeding

---

## Step 3: Write the Spec

Using the template at `docs/workflow/development-workflow/templates/spec-template.md`, write the spec document.

**Output location**:

<!-- prettier-ignore -->
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
- Use **domain and user language** in use cases, business rules, and UX sections — do not embed API field names, JSON keys, method names, or other code identifiers (they belong in the implementation plan, not the product spec)
- For multi-entity or high-edge-case briefs: keep **terminology consistent** across sections, keep acceptance criteria **verifiable in a test environment**, and use **Open Questions** (when present in the template) only for genuine product ambiguities — not as a dump for implementation unknowns (those belong in the plan or out-of-scope deferrals)

### Before opening the draft PR (Document Quality Gate)

Run this gate after writing the spec and before opening the draft PR. This gate
does not replace the internal review gate, automated reviewer loop, CI, or human
review; it reduces avoidable first-pass review churn.

Record the result in the draft PR description under a `Document Quality Gate`
section. Each checked item must say `Checked` or `Not applicable`, with a short
rationale for every `Not applicable` item:

```markdown
## Document Quality Gate

- Brief coverage: Checked - all brief objectives map to acceptance criteria or out of scope.
- Internal consistency: Checked - terminology and status labels are consistent.
- Behavioral guarantees: Not applicable - this spec does not introduce guarantees beyond ACs.
- Reviewer-risk categories: Checked - API surface, concurrency, snapshot semantics, edge cases, and template placeholders reviewed.
```

Before the PR is opened, verify:

- Brief coverage: every tracker brief objective appears in the Coverage Matrix or
  an explicit out-of-scope deferral.
- Internal consistency: the same product concept, status, actor, and user-facing
  term has the same name and meaning in every section.
- Naming and casing consistency: user-visible labels, enum display labels, and
  workflow statuses use one spelling/casing throughout.
- Behavioral guarantees: every guarantee, limit, ordering rule, or invariant is
  backed by acceptance criteria or a business rule that makes it testable.
- Reviewer-risk categories: common high-signal reviewer concerns are checked:
  API-surface completeness, concurrency correctness, single-snapshot or
  consistency semantics, missing edge cases, vague actors/triggers, untestable
  ACs, hidden dependencies, accidental implementation design, and stale
  template content.
- Placeholder cleanup: the template-placeholder grep below returns no output.
- Not-applicable rationale: any omitted optional section or checklist item has a
  brief rationale in the PR description log.

**Template placeholder removal (mandatory — run before every spec PR)**:

After writing the spec, verify that no template placeholder content remains in the output file. These are the most common artifacts that trigger CodeRabbit findings on spec PRs:

1. **`Depends on` line**: If the feature has no dependencies, the `**Depends on**:` line must be removed entirely. If dependencies exist, replace the placeholder slugs with the actual feature slugs. Never leave the line with bracketed placeholders (e.g., `[feature-slug-1, feature-slug-2]`) or the original HTML comment form.

2. **`Language` instruction block**: The `**Language**: ...` block in the Overview is a template instruction, not spec content. Remove it entirely before committing. Replace it with actual spec prose (2–4 sentences describing what the feature does and why it exists).

3. **Unfilled section placeholders**: Every section that remains in the spec must contain real content. Remove or fill:
   - `<!-- Replace this comment with ... -->` comments (replace with real content)
   - `[Step 1]`, `[Step 2]`, `[What data the user sees]`, and similar bracketed placeholder lines in use cases
   - `[Rule 1: an invariant...]`, `[UX rule 1: ...]`, and similar bracketed placeholder items in lists
   - `[Out of scope item 1]`, `[Out of scope item 2]` lines under Out of Scope
   - `[Question 1]`, `[Question 2]` lines under Open Questions (fill with real questions or delete the section)
   - `[Code value]`, `[Display label]`, `[Description]` cells in the Statuses table

4. **Optional sections left with only placeholder content**: Sections such as `## UX Rules`, `## Statuses / Enum Values`, and `## Operational Visibility` include a delete instruction in the template (`<!-- Delete this section if... -->`). If a section is not applicable, delete the entire section including its heading. Never leave a section containing only the placeholder comment or example rows.

Run this grep to catch the most common unfilled placeholder patterns before committing:

```bash
grep -n "\[Step [0-9]\]\|\[Who initiates\|\[What must be\|\[Rule [0-9]\|\[UX rule\|\[Out of scope item\|\[Question [0-9]\|\[Code value\|\[Display label\|\[Description\]\|\[feature-slug-[0-9]\|<!-- Delete this section\|<!-- Replace this comment\|<!-- Depends on:\|\*\*Language\*\*:" \
  docs/specs/developments/<timestamp>_<slug>/1_<slug>_specs.md
```

If this grep returns any output, address each match before opening the PR.

### Brief Coverage Requirements (mandatory when a tracker brief exists)

When a tracker issue or work-item brief exists, add these artifacts before opening the draft PR:

1. Build a **Brief Objective List** from discrete requirement bullets/checklists in the brief.
2. Create a **Coverage Matrix** that maps every brief objective to either:
   - one or more acceptance criteria, or
   - an explicit entry under `## Out of Scope (MVP)`.
3. For each objective deferred to out of scope, include a **Deferral Note** with:
   - the objective wording (or stable paraphrase),
   - rationale for deferral, and
   - whether human confirmation is requested.

No objective may be silently dropped. If an objective is not mapped in the matrix, the spec is incomplete and must not proceed to PR-ready steps.

### Spec Snippet Example

```markdown
# Spec: [feature-name]

...
```

---

## Step 4: Human Review Shortcut (Optional)

Default behavior is **max autonomy**: once the alignment conversation is complete and there are no unresolved blocking product questions, continue through branch creation, commit, push, and draft-PR creation without asking for an extra "review before PR" confirmation.

Pause only if:

- The human explicitly asked to review the draft before Git operations
- The spec still contains a blocking product ambiguity
- A blocking product decision prevents opening the draft PR

---

## Step 5: Git Execution

If no blocking human decision remains:

1. Determine the branch slug:
   - **With issue tracker**: `[issue-id]-[feature-slug]` (e.g., `ENG-123-user-auth`)
   - **Without issue tracker**: `[feature-slug]` (e.g., `user-auth`)
2. Create branch: `git checkout -b spec/[branch-slug]` from `develop`
3. Create the development folder: `docs/specs/developments/[YYYYMMDDHHMMSS]_[feature-slug]/`
4. Write the spec file: `1_[feature-slug]_specs.md`
5. **Board membership check (when a tracker issue ID is present)**: If an issue number is available (i.e., the workflow uses a configured issue tracker and an issue ID was provided or created), call `ensure_on_project_board <issue_number> "Writing Spec"` (sourcing `scripts/development-workflow/workflow-lib.sh`). If the issue is already on the project board, this is a no-op. If it is not, the function adds it and sets initial status to "Writing Spec". On any API failure, the function logs a warning and continues — this step must never block the commit or PR creation. Skip this step entirely when no issue ID is present (no-tracker workflows).
6. **Do NOT update CHANGELOG**: `spec/*` branches are exempt from CHANGELOG entries. The changelog policy only applies to `feature/*`, `fix/*`, `refactor/*`, and `hotfix/*` branches. Do not create or modify `CHANGELOG.md` in this PR.
7. Commit: `docs: add spec for [feature-name]`
8. Push: `git push -u origin spec/[branch-slug]`
9. Open a **draft** PR targeting `develop` with:
   - Title: `docs(spec): [feature-name]`
   - Body: summary of the feature, link to the spec file, list of open questions (if any)
   - When a tracker brief exists: Coverage Matrix summary (each brief objective mapped to AC reference(s) or Out-of-Scope entry) and Deferral Notes for each objective intentionally moved to Out of Scope
   - `Document Quality Gate` log from the pre-PR gate above
10. Return the branch + PR details to the **Work Item Runner**

---

## Step 6: Handoff to Work Item Runner

After the draft PR exists, the **Work Item Runner** owns the rest of the lifecycle for this item:

- Run the internal spec review gate (`spec-reviewer` / `01-review-spec-protocol.md`) on the draft PR
- Run the automated reviewer loop and CI loop to completion
- Apply `ready-for-human-review` and move the tracker to **Spec in Review** when the PR is human-ready
- Stop only when the PR is waiting on human review / merge or the run has escalated

If this protocol is invoked **standalone** rather than through the Work Item Runner, hand off manually by following `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` from the newly opened draft PR.

See `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` and `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md`.
