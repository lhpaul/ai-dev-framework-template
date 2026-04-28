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
- **Verification command simplicity**: Verification steps in Implementation Order steps must be simple and human-readable. Follow these rules:
  - Prefer prose assertions ("confirm the output lists only the renamed files") over exact file counts or byte counts.
  - Avoid multi-flag grep one-liners that are difficult to verify by reading (e.g., complex exclusion scopes, self-referencing exclusion globs, chained pipes with hard-coded counts).
  - For mass-rename or substitution operations: include an explicit "run the command and confirm the output matches expectations" sanity check rather than prescribing the exact expected count — counts go stale as the repo evolves and breed fix commits when reviewers find mismatches.
  - A verification step is correct if a developer can execute it, read the output, and confidently determine pass/fail without consulting an external reference.

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

### Cross-cutting checklist plans: safety, quality, or compliance categories

Treat this block as mandatory guidance whenever the plan **introduces or modifies a cross-cutting checklist** — defined as a safety, quality, or compliance category that applies across multiple independent feature implementations (e.g., a new async/concurrency safety checklist, a security review category, or a compliance verification gate added to the review or planning workflow).

**Classification (cross-cutting checklist):** classify a plan as cross-cutting checklist when the Layer-by-Layer changes include:

- Adding or renaming a checklist category in `REVIEW.md`, `02-generate-implementation-plan-protocol.md`, or any review/planning document
- Updating acceptance criteria that every feature plan or implementation must satisfy (e.g., "all plans must include a concurrency safety section")
- Introducing a new conditional guidance block in a planning or implementation protocol that applies based on a feature classification signal

If none of these signals apply, skip this entire block.

**Mandatory when cross-cutting checklist — Full file enumeration:** the plan's "Files to modify" section **must explicitly list every file** that needs updating. Do not list only the primary protocol file. At minimum, verify and include:

- `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` — tech-lead planning protocol
- `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` — developer implementation protocol
- `.claude/agents/developer.md` — Claude Code developer agent
- `.cursor/agents/developer.md` — Cursor developer agent
- `.claude/agents/tech-lead.md` — Claude Code tech-lead agent (if the change affects planning behavior)
- `.cursor/agents/tech-lead.md` — Cursor tech-lead agent (if the change affects planning behavior)
- `REVIEW.md` — human and automated reviewer checklist
- Any Codex skill files in `.codex/skills/` that invoke the affected stage (check `.codex/skills/workflow-plan-writer/SKILL.md`, `.codex/skills/workflow-implementer/SKILL.md`, and related skills)

Run a live search before writing the enumeration to avoid omissions:

```bash
# Find all agent/skill files that reference the affected protocol
grep -rl "02-generate-implementation-plan-protocol\|03-implement-development-protocol" .claude/agents/ .cursor/agents/ .codex/skills/
```

The tech-lead must explicitly include all applicable targets in the plan's "Files to modify" section rather than delegating discovery to the implementation agent.

### Concurrent-event-source plans: async and concurrency safety

Treat this block as conditional guidance. Apply it only when the plan introduces or modifies code with two or more concurrent event sources (e.g., real-time data listeners, network socket callbacks, timers or scheduled callbacks) that share mutable state.

**Classification (concurrent-event-source):** classify a plan as concurrent-event-source when the Layer-by-Layer changes involve any of the following:

- Two or more event listeners, socket callbacks, timers, or async queues that can execute concurrently
- Shared mutable state (variables, collections, counters, caches) that multiple execution contexts can read or write
- Initialization or teardown sequences that race with incoming events

If none of these signals apply, skip this entire block.

**Mandatory when concurrent-event-source — Checklist:** include a dedicated concurrency safety section in the plan. For each item below, document the design decision when the item applies, or note "not applicable" with a brief rationale:

- **Shared mutable state guards**: how is shared state protected from concurrent reads/writes? (e.g., access serialized through a single async queue, ownership transferred on each event, copy-on-update)
- **Re-entrancy / in-flight tracking**: can a second event arrive before the handler for the first event finishes? If yes, how is in-flight state tracked and new arrivals handled?
- **Event deduplication**: can the same logical event fire more than once (e.g., reconnect triggers, duplicate callbacks)? If yes, how is deduplication handled?
- **Listener and resource cleanup**: how are all registered listeners, timers, and handles removed when the feature is torn down or the component unmounts? What happens to in-flight operations at teardown?
- **Race conditions at initialization**: can events arrive before initialization completes? If yes, what happens to those events?
- **Race conditions at teardown**: can events arrive after teardown begins? If yes, how are they discarded or drained safely?
- **Error propagation across async boundaries**: how are errors from async callbacks surfaced? Are unhandled rejections or uncaught exceptions in callbacks visible to the caller or swallowed silently?

**Conditional — new concurrent patterns:** if the feature introduces concurrent event handling patterns not previously used in this codebase, note this explicitly and identify any architectural decisions that differ from existing patterns.

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
   # Resolve the repo root (works whether running in the main tree or an isolated worktree).
   # NOTE: git rev-parse --show-toplevel returns the *worktree* directory inside a worktree,
   # not the main repo. Use --git-common-dir instead, which always points to the shared .git/.
   REPO_ROOT=$(git rev-parse --git-common-dir)/..

   # Run markdownlint-cli2 using the repo root's node_modules
   "$REPO_ROOT/node_modules/.bin/markdownlint-cli2" \
     "docs/specs/developments/[timestamp]_[feature-slug]/2_[feature-slug]_implementation-plan.md" \
     "docs/testing/[app-or-section]/[feature-slug].smoke-test.md"
   ```

   Fix any reported violations before proceeding to the commit step. Common violations to look for:
   - **Broken relative links** (`relative-links`): verify every `[text](../../path/to/file.md)` path resolves from the file's location. Count the `../` segments carefully — off-by-one depth errors (e.g., `../../../../` where `../../../` is correct) will not be obvious by inspection alone. The lint step is the authoritative check.
   - **Trailing spaces** (MD009): no line should end with whitespace except intentional two-space hard line breaks.
   - **Missing trailing newline** (MD047): every file must end with a single newline.

   > **Worktree note**: When running inside a git worktree (e.g., when dispatched by the Portfolio Orchestrator), `node_modules/` does not exist inside the worktree directory. The `$(git rev-parse --git-common-dir)/..` expression resolves to the main repo root in both the main tree and any worktree.

6. **Do NOT update CHANGELOG**: `implementation-plan/*` branches are exempt from CHANGELOG entries. The changelog policy only applies to `feature/*`, `fix/*`, `refactor/*`, and `hotfix/*` branches. Do not create or modify `CHANGELOG.md` in this PR.
7. Commit: `docs: add implementation plan for [feature-name]`
8. Push: `git push -u origin implementation-plan/[branch-slug]`
9. Open a **draft** PR targeting `develop` with:
   - Title: `docs(plan): [feature-name]`
   - Body: summary of the approach, complexity estimate, key risks, link to plan and runbook
10. Return the branch + PR details to the **Work Item Runner**

---

## Step 6: Handoff to Work Item Runner

After the draft PR exists, the **Work Item Runner** owns the rest of the lifecycle for this item:

- Run the internal plan review gate (`implementation-plan-reviewer` / `02-review-implementation-plan-protocol.md`) on the draft PR
- Run the automated reviewer loop and CI loop to completion
- Apply `ready-for-human-review` and move the tracker to **Plan in Review** when the PR is human-ready
- Stop only when the PR is waiting on human review / merge or the run has escalated

If this protocol is invoked **standalone** rather than through the Work Item Runner, hand off manually by following `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` from the newly opened draft PR.

See `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` and `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md`.
