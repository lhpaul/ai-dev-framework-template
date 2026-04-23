# Protocol: Generate Implementation Plan (Plan Ready Stage)

**Agent role**: Tech Lead
**Stage**: Plan Ready
**Output**: Implementation plan in `docs/specs/developments/[timestamp]_[feature-slug]/2_[feature-slug]_implementation-plan.md` + smoke test runbook in `docs/testing/`

---

## Prerequisites

Before starting, read:

- The approved spec: `docs/specs/developments/[timestamp]_[feature-slug]/1_[feature-slug]_specs.md` (Full Pipeline only — Refactor items have no spec; use the work item brief from the tracker or human instead)
- `docs/project/2-repo-architecture.md` — repository structure
- `docs/project/3-software-architecture.md` — tech stack and design patterns
- `docs/project/4-database-model.md` — data model (if applicable)
- `docs/best-practices/` — all best practice docs
- Relevant existing code — read actual files, don't assume structure
- **Project documentation**: Scan `docs/` (e.g. `docs/project/`, `docs/best-practices/`, `AGENTS.md`, and any feature- or domain-specific docs) so the plan can explicitly list which of these need updates after implementation.
- If an issue tracker exists for this item, follow `docs/workflow/development-workflow/integrations/issue-tracker.md` for expectations while the work item is entering **Writing Plan** (Full Pipeline: after spec is merged; Refactor: directly from Backlog).

**Tracker workflow status**: The **Work Item Runner** owns workflow-status transitions for this stage. When this protocol is run under normal orchestration, expect the runner to set **Writing Plan** before dispatch, **Plan in Review** when the PR is human-ready, and **Plan Ready** only after merge. If you invoke this protocol standalone, mirror the same status progression manually.

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

Default behavior is **max autonomy**: once you have read the approved spec (or the work item brief for Refactor items), inspected the codebase, and there is no unresolved architectural ambiguity, continue through plan writing, commit, push, and draft-PR creation without an extra pause.

Pause only if:

- The human explicitly asked to review the approach before plan writing
- The proposed approach has a material architecture tradeoff or ambiguity you cannot resolve safely
- A blocking architecture decision prevents opening the draft PR

---

## Step 3: Write the Implementation Plan

Using the template at `docs/workflow/development-workflow/templates/implementation-plan-template.md`, write the implementation plan.

**Output location**:

```markdown
docs/specs/developments/[timestamp]_[feature-slug]/2_[feature-slug]_implementation-plan.md
```

**Quality guardrails**:

- All layers that will change must be covered
- The implementation order must be logical and executable (no steps that require a later step to be done first)
- Every change must reference an acceptance criterion from the spec (for Refactor items, reference the work item brief or stated restructuring goals instead)
- Seed data requirements must be explicit — what data, in which files, for which test scenarios
- **Documentation**: Explicitly consider project documentation in `docs/`. The plan must list every doc in `docs/` (including `AGENTS.md` if relevant) that the developer must update after implementation, or state "None" only when the feature truly affects no project docs. Do not plan the doc edits — only list them for the developer to execute.
- **Pattern completeness checks**: When the spec intent implies "all files/items matching pattern X", do not trust stale enumerations. Re-run a live repo query at plan-write time and use those results in the plan's file list and counts.
- **Explicit freeze exception**: You may copy a fixed enumeration only when the spec explicitly freezes scope to a named subset; quote that spec section in the plan.
- **Verification Log required**: Every plan must include a reproducible Verification Log (command/query, repo SHA, and resulting counts/paths that drive scope statements).
- **CHANGELOG literal format**: When the Implementation Order includes a literal CHANGELOG entry for the developer to copy, it must follow the project's `**Bold Title** (#N):` format (e.g., `- **Fix tech-lead CHANGELOG format** (#226): ...`). Never use conventional-commit format (`fix(scope): message`) in a CHANGELOG literal — that format is for git commit messages, not CHANGELOG entries. The impl agent will copy the literal verbatim; a wrong format wastes a reviewer cycle.

### Parser-risk plans: custom parsers, regex, and structured-text scanning

Treat this block as conditional guidance. Apply it only when the plan is parser-risk.

**Classification (parser-risk):** classify a plan as parser-risk when Layer-by-Layer changes introduce or materially change any of the following:

- Files under conventional tooling paths such as `scripts/lint/`, `scripts/parse/`, or similar parse/lint scanner directories
- New or renamed modules whose names imply lint/parser/scanner/tokenizer/regex-engine responsibilities (for example `*lint*.py`, `*parser*.mjs`, `*scanner*.ts`)
- Explicit behavior described as regex-heavy scanning, structured-text parsing, or rule engines over markdown, code, config, or logs

If none of these signals apply, skip this entire block.

**Mandatory when parser-risk — Edge-case enumeration:** include a dedicated subsection with concrete inputs (not vague statements like "handle edge cases"). Cover at minimum:

- Boundary-character variants
- Negative cases (strings that resemble matches but must not match)
- Multiple occurrences on one line
- Nested or overlapping constructs where relevant
- Normative-spec flexibility when applicable (for example CommonMark closing fence length >= opening fence length)

**Mandatory when parser-risk — Unit tests:** in the Testing Strategy, name a concrete unit test file and map at least one automated unit test per enumerated edge case. Smoke-only or manual-only plans are insufficient for parser-risk work.

**Conditional — Suppression semantics:** when the feature supports inline/directive suppressions, add a subsection naming:

- Which directives are recognized
- Where directives can appear
- How multiple suppressions on one line are interpreted

For acceptance intent and terminology, reference `docs/specs/developments/20260420120000_201-tech-lead-parser-regex-plan-requirements/1_201-tech-lead-parser-regex-plan-requirements_specs.md`.

### Examples

```markdown
# Implementation Plan: [slug]
...
```

---

## Step 4: Write the Smoke Test Runbook

Create the smoke test runbook using the template at `docs/workflow/development-workflow/templates/smoke-test-runbook-template.md`.

**Output location**:

```markdown
docs/testing/[app-or-section]/[feature-slug].smoke-test.md
```

The runbook must cover all acceptance criteria from the spec (or from the work item brief for Refactor items). Each criterion must have at least one testable step.

---

## Step 5: Git Execution

If no blocking human decision remains:

1. Determine the branch slug:
   - **With issue tracker**: `[issue-id]-[feature-slug]` (e.g., `ENG-123-user-auth`)
   - **Without issue tracker**: `[feature-slug]` (e.g., `user-auth`)
2. Create branch: `git checkout -b implementation-plan/[branch-slug]` from `develop`
3. Write the plan file
4. Write the smoke test runbook
5. **Pre-commit lint check (mandatory — do not skip)**:

   Run `markdownlint-cli2` on the plan file and smoke test runbook before staging. This catches broken relative links (wrong `../../` depth), trailing spaces, and missing trailing newlines that would otherwise fail CI and require a fix commit.

   ```bash
   # Resolve the repo root (works whether running in the main tree or a worktree)
   REPO_ROOT=$(git rev-parse --show-toplevel)

   # Run markdownlint-cli2 using the repo root's node_modules
   "$REPO_ROOT/node_modules/.bin/markdownlint-cli2" \
     "docs/specs/developments/[timestamp]_[feature-slug]/2_[feature-slug]_implementation-plan.md" \
     "docs/testing/[app-or-section]/[feature-slug].smoke-test.md"
   ```

   Fix any reported violations before proceeding to the commit step. Common violations to look for:
   - **Broken relative links** (`relative-links`): verify every `[text](../../path/to/file.md)` path resolves from the file's location. Count the `../` segments carefully — off-by-one depth errors (e.g., `../../../../` where `../../../` is correct) will not be obvious by inspection alone. The lint step is the authoritative check.
   - **Trailing spaces** (MD009): no line should end with whitespace except intentional two-space hard line breaks.
   - **Missing trailing newline** (MD047): every file must end with a single newline.

   > **Worktree note**: When running inside a git worktree (e.g., when dispatched by the Portfolio Orchestrator), `node_modules/` does not exist inside the worktree directory. Use `REPO_ROOT=$(git rev-parse --show-toplevel)` to locate the correct binary regardless of working directory.

6. Commit: `docs: add implementation plan for [feature-name]`
7. Push: `git push -u origin implementation-plan/[branch-slug]`
8. Open a **draft** PR targeting `develop` with:
   - Title: `docs(plan): [feature-name]`
   - Body: summary of the approach, complexity estimate, key risks, link to plan and runbook
9. Return the branch + PR details to the **Work Item Runner**

---

## Step 6: Handoff to Work Item Runner

After the draft PR exists, the **Work Item Runner** owns the rest of the lifecycle for this item:

- Run the internal plan review gate (`implementation-plan-reviewer` / `02-review-implementation-plan-protocol.md`) on the draft PR
- Run the automated reviewer loop and CI loop to completion
- Apply `ready-for-human-review` and move the tracker to **Plan in Review** when the PR is human-ready
- Stop only when the PR is waiting on human review / merge or the run has escalated

If this protocol is invoked **standalone** rather than through the Work Item Runner, hand off manually by following `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` from the newly opened draft PR.

See `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` and `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md`.
