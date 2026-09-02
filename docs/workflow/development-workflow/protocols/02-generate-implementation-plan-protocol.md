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

**Repository mode ownership**: Resolve repository mode before writing or
reviewing plan artifacts. Missing mode or explicit `single_repo` means the
current repository owns the plan. In `workflow_hub` mode, the hub owns
implementation plans and plan PRs unless a future workflow contract explicitly
says otherwise. In `product_repo` mode, report the configured hub owner or stop
if planning ownership is ambiguous; do not create duplicate hub-owned plans in
the product repository.

---

## Step 0: Template-Fit Check (Template Repositories Only)

**Applies to**: Repositories where `.ai-dev-workflow.yaml` sets `template.is_template: true`.

**When to run**: At the very start of this protocol — before writing any plan content,
before the alignment conversation, and before inspecting the codebase for implementation
details.

**Purpose**: Catch framework-specific features early, before a full plan-writing cycle
is wasted on work that will be immediately discarded.

### Detection

Read `.ai-dev-workflow.yaml`. If `template.is_template` is `true`, this repository is
a framework template and this step is **mandatory**. If `template.is_template` is
absent, `false`, or empty, skip this step entirely.

Note: `template.repository` is a different field — it points to the **upstream**
template that this repository was derived from (set by downstream consumer projects,
not by the template itself). Do not use `template.repository` as the detection signal.

### Evaluation criteria

A spec (or work item brief) is **too framework-specific** for a generic template when
it satisfies one or more of the following:

- It references a specific language, runtime, or framework (e.g., React, Rails, Django,
  Go, Vue, Angular, Spring Boot, Laravel) that is **not** part of the template's own
  toolchain (i.e., not used by the template repository itself for its own workflow
  tooling).
- Its acceptance criteria, implementation steps, or examples are only meaningful to
  downstream projects built on a particular technology stack.
- Its primary value is providing a library-specific pattern, component, or integration
  that only applies to consumers using one particular framework.

A spec is **generic enough** if:

- It improves the workflow tooling, documentation, protocols, or scripts that the
  template itself ships.
- It adds or improves something every downstream project would benefit from, regardless
  of their tech stack.
- Its acceptance criteria are expressed in framework-agnostic terms.

### Action

**If the spec passes the fit check** (generic enough): continue to Step 1 normally.
No output or comment is required.

**If the spec fails the fit check** (too framework-specific): surface the following
warning to the human and **halt before writing any plan content**:

> ⚠️ **Template-fit check failed**: This spec appears to be framework-specific
> ([detected framework/technology]). Implementation plans in this template repository
> should be generic and applicable to all downstream consumers regardless of their
> tech stack. Writing a framework-specific plan wastes a full review cycle and the
> work will likely be discarded.
>
> **Please confirm one of the following before proceeding:**
>
> 1. The spec is actually generic — explain why the framework reference does not make
>    this template-specific, and I will proceed.
> 2. The scope should be narrowed — describe how to make the spec generic, and I will
>    write a plan for the narrowed scope.
> 3. This item should be cancelled — close the issue as out-of-scope for the template.

Do **not** proceed to Step 1 until the human has responded and confirmed one of the
above options. Do **not** write any plan content, create any branch, or open any PR
while this check is pending.

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

<!-- prettier-ignore -->
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
- **Changelog fragment literal format**: When the Implementation Order includes a literal changelog fragment body for the developer to copy, it must follow the project's `**Bold Title** (#N):` bullet format (e.g., `- **Fix tech-lead CHANGELOG format** (#226): ...`). Never use conventional-commit format (`fix(scope): message`) in a changelog literal — that format is for git commit messages, not release notes. The impl agent will copy the literal verbatim; a wrong format wastes a reviewer cycle.
- **Verification command simplicity**: Verification steps in Implementation Order steps must be simple and human-readable. Follow these rules:
  - Prefer prose assertions ("confirm the output lists only the renamed files") over exact file counts or byte counts.
  - Avoid multi-flag grep one-liners that are difficult to verify by reading (e.g., complex exclusion scopes, self-referencing exclusion globs, chained pipes with hard-coded counts).
  - For mass-rename or substitution operations: include an explicit "run the command and confirm the output matches expectations" sanity check rather than prescribing the exact expected count — counts go stale as the repo evolves and breed fix commits when reviewers find mismatches.
  - A verification step is correct if a developer can execute it, read the output, and confidently determine pass/fail without consulting an external reference.

### Executable workflow shell snippets

When a plan adds executable shell guidance on a framework-owned surface, name
its shell contract in the Layer-by-Layer changes: `bash` for snippets that
launch Bash explicitly, or `bash-zsh` for portable snippets. Include the
diff-aware snippet-linter command and Bash/zsh behavioral evidence whenever
iteration or positional argument splitting is illustrated.

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

These parser-risk and suppression requirements are the complete required
acceptance intent and terminology. Historical template or workflow-hub
development artifacts may offer supplementary context, but they can be absent
in receiving repositories and must never block plan authoring or sync
validation.

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

### Cross-cutting operational assumption check

Treat this block as mandatory for every implementation plan. Its purpose is to
prevent a plan from silently encoding an operational fact that another item or
pull request is changing in the same workflow window.

**Classification:** classify the check as applicable when the plan relies on a
cross-cutting operational assumption that concurrent work could invalidate.
Examples include environment targets, linked cloud projects, approved base
branches, artifact ownership, selected product repositories, canonical
configuration values, or similarly shared operational facts. Architecture
choices, implementation preferences, and shared terminology are not sufficient
by themselves; the evidence must concern the same operational assumption
surface.

When applicable, include a `Cross-Cutting Operational Assumption Check` section
with the assumption value, authoritative source, verification time and repo
revision, bounded current invocation / same-surface open PR scope, and result.
The result must be `Verified`, `Conflict`, or `Resolved`. A conflict row must
record competing evidence, affected plan statements, resolution status, and
decision owner.

Do not replace the bounded relevance check with an unbounded scan of every open
pull request. If no applicable operational assumption exists, include a concise
`Not applicable` rationale and do not scan every open PR. Shared keywords alone
must not be classified as a conflict unless another item or PR changes the same
operational assumption surface.

When the bounded check finds a conflict or unverifiable source, return the
evidence to the parent orchestrator. The parent records either `Resolved` with
the authoritative interpretation and decision owner, or stops with
`Human decision required` / `unclear_requirements` when available evidence is
insufficient. Implementation must remain blocked until the plan records that
resolution.

The seven logical outcomes for this gate are:

| Gate input | Allowed outcome | Required next action |
| --- | --- | --- |
| Applicable operational assumption and bounded evidence agrees | `Verified` | Record value, source, verification time, bounded scope, and result; continue planning |
| Applicable assumption has conflicting or unverifiable evidence | `Conflict` | Record competing evidence and affected statements; return to the parent orchestrator |
| Parent has sufficient authoritative evidence | `Resolved` | Record selected interpretation and decision owner; update the plan |
| Parent lacks sufficient evidence | `Human decision required` | Stop with `unclear_requirements` and request a human decision |
| No applicable operational assumption | `Not applicable` | Record concise rationale; do not scan every open PR |
| Implementation-start source check matches plan record | `Still valid` | Record the current result and begin implementation |
| Implementation-start source changed, conflicts, or cannot be verified | `Stale or conflicting` | Stop before file edits and return evidence to the parent orchestrator |

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

### Design-asset discovery and fidelity steps

Before finalizing the runbook for UI-facing work, discover design assets using
the order in [`design-assets.md`](../design-assets.md) (issue-body
`## Design assets`, tracker attachments, linked files, `<dev-folder>/assets/`).

- **When assets exist**: include at least one expected-vs-actual fidelity step
  that names the reference asset(s). Fidelity is a lightweight visual
  comparison, not a pixel-diff platform.
- **When none exist**: omit fidelity steps; do **not** invent a baseline or
  fail the plan for missing mockups.
- If locations conflict, ask the human once which reference is authoritative.
  Sibling issues are never asset sources for this item.

---

## Step 5: Git Execution

If no blocking human decision remains:

1. Determine the branch slug:
   - **With issue tracker**: `[issue-id]-[feature-slug]` (e.g., `ENG-123-user-auth`)
   - **Without issue tracker**: `[feature-slug]` (e.g., `user-auth`)
2. Resolve the plan artifact base branch, then create the branch from that base.
   In `workflow_hub` mode, implementation plans are hub-owned and use the hub
   repository's artifact base branch, typically the hub default branch. Do not
   use the product implementation base (`--base develop` from `/run-epic`) as
   proof that the hub repository must have `develop`.

   Before branch creation, validate the constructed tracked branch with
   validate-workflow-branch-name.sh. Use the bare numeric issue identifier
   (for example, implementation-plan/1858-safe-name, never
   implementation-plan/#1858-safe-name); the guard rejects unsafe characters
   before any push.

   Then run the **pre-branch HEAD verification** to prevent stacked-branch
   contamination in shared-checkout parallel execution:

   ```bash
   set -euo pipefail
   ARTIFACT_BASE_BRANCH="<artifact-base-branch>"
   git fetch origin
   git checkout "$ARTIFACT_BASE_BRANCH" && git pull origin "$ARTIFACT_BASE_BRANCH"
   EXPECTED_SHA=$(git rev-parse "origin/${ARTIFACT_BASE_BRANCH}") \
     || { echo "ERROR: git rev-parse origin/${ARTIFACT_BASE_BRANCH} failed — verify the remote ref exists." >&2; exit 1; }
   ACTUAL_SHA=$(git rev-parse HEAD) \
     || { echo "ERROR: git rev-parse HEAD failed — check repository state." >&2; exit 1; }
   if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
     echo "ERROR: HEAD ($ACTUAL_SHA) does not match origin/${ARTIFACT_BASE_BRANCH} ($EXPECTED_SHA)." >&2
     echo "A sibling agent may have moved this checkout. Abort rather than create a stacked branch." >&2
     exit 1
   fi
   echo "Pre-branch HEAD check passed: HEAD matches origin/${ARTIFACT_BASE_BRANCH}"
   if [ -n "${ISSUE_NUMBER:-}" ]; then
     ./scripts/development-workflow/run-nested-artifact-guard.sh \
       --mode pre-create \
       --issue "$ISSUE_NUMBER" \
       --expected-branch "implementation-plan/[branch-slug]" \
       --approved-base "$ARTIFACT_BASE_BRANCH"
   fi
   git checkout -b implementation-plan/[branch-slug]
   ```

   If the check fails, do not proceed. Report the mismatch to the caller so the working tree can be reset before retrying.
3. Write the plan file
4. Write the smoke test runbook
5. **Board membership check (when a tracker issue ID is present)**: If an issue number is available, call `ensure_on_project_board <issue_number> "Writing Plan"` (sourcing `scripts/development-workflow/workflow-lib.sh`). If the issue is already on the project board, this is a no-op. If it is not, the function adds it and sets initial status to "Writing Plan". On any API failure, the function logs a warning and continues — this step must never block the commit or PR creation. Skip this step entirely when no issue ID is present (no-tracker workflows).
6. **Cross-section consistency self-check (mandatory — do not skip)**:

   Before committing, verify that every symbol and structural decision that appears more than once in the plan has a consistent definition across all occurrences. Contradictory definitions discovered during implementation waste implementation cycles and cause agent confusion.

   Procedure:
   1. Collect all items that appear more than once across plan sections: function/method names, constant names, decision index labels (e.g., "Decision 1", "ADR-3"), file paths, directory names, and route/URL structures.
   2. For each repeated item, compare every occurrence across all sections of the plan document.
   3. If any two occurrences define or describe the item differently, fix the inconsistency before proceeding.

   Common sources of inconsistency to check:
   - A function described with different signatures or parameters in the "Architecture" section vs. the "Implementation Order" steps.
   - A constant defined with one value in the overview and a different value in the verification step.
   - A decision (e.g., "Decision 1: use X") referenced as "Decision 2" or with a different rationale in another section.
   - A file path or directory structure described one way in the "Files to modify" or "Architecture" section and a different way in the "Implementation Order" steps or summary (e.g., a route file placed under `routes/api/` in one section but under `api/routes/` in another).
   - A URL or route pattern defined in one section (e.g., `/api/v1/users`) that conflicts with a different pattern in another section (e.g., `/v1/api/users`).

   Fix all inconsistencies found before moving to the lint check. Do not proceed to commit with known cross-section contradictions.

7. **Document Quality Gate (mandatory — do not skip)**:

   Run this gate after the cross-section consistency self-check and before
   opening the draft PR. This gate does not replace the internal review gate,
   automated reviewer loop, CI, or human review; it reduces avoidable first-pass
   review churn.

   Record the result in the draft PR description under a `Document Quality Gate`
   section. Each checked item must say `Checked` or `Not applicable`, with a
   short rationale for every `Not applicable` item:

   ```markdown
   ## Document Quality Gate

   - Spec/brief coverage: Checked - all ACs map to implementation steps and tests.
   - Implementation-order consistency: Checked - file list and order agree.
   - Verification support: Checked - broad claims cite Verification Log evidence.
   - Complex workflow decision-gate matrix: Not applicable - this plan does not add or modify workflow decision-gate behavior.
   - Parser/API/concurrency checklist: Not applicable - no parser, API-surface, snapshot, or concurrent-event signals.
   ```

   Before the PR is opened, verify:

   - Spec/brief coverage: every acceptance criterion and in-scope brief objective
     maps to implementation steps and test/smoke coverage.
   - Implementation-order consistency: file lists, helper names, constants,
     routes, status names, and branch/PR operations agree across all sections.
   - Verification support: broad claims about existing behavior, file coverage,
     or tool semantics cite a Verification Log command or a concrete source file.
   - Behavioral guarantees: every guarantee such as idempotency, bounded retries,
     ordering, or "at most once" names the mechanism that enforces it.
   - Complex workflow decision-gate matrix: when the plan adds or modifies a
     complex workflow decision gate, classify it and include matrix coverage
     before PR handoff. A complex workflow decision-gate change is any workflow
     documentation or protocol change whose behavior depends on multiple inputs,
     outcomes, next-action branches, status labels, exit states, examples, or
     mirrored workflow surfaces. Matrix evidence must identify the gate inputs,
     allowed outcomes, required next actions, mirror surfaces, and examples when
     examples are part of the changed surface. If the plan does not change
     decision-gate behavior, record a short not-applicable rationale. If an
     expected input, outcome, example, or mirror surface is marked not
     applicable, include the rationale in the matrix row.
   - Parser/API/concurrency checklist completeness: when parser-risk,
     API-surface, single-snapshot or consistency-semantics, or
     concurrent-event-source signals apply, the required checklist sections are
     present and mapped to tests.
   - CHANGELOG literal format: required implementation CHANGELOG entries appear
     exactly as they should be added later, including section and issue number.
   - Not-applicable rationale: any skipped checklist category has a brief
     rationale in the PR description log.

8. **Pre-commit lint check (mandatory — do not skip)**:

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

9. **Do NOT update CHANGELOG**: `implementation-plan/*` branches are exempt from CHANGELOG entries. The changelog policy only applies to `feature/*`, `fix/*`, `refactor/*`, and `hotfix/*` branches. Do not create or modify `CHANGELOG.md` in this PR.
10. Commit: `docs: add implementation plan for [feature-name]`
11. Push with an explicit refspec so the destination never depends on local
    `push.default`, then verify the remote head matches local before opening the
    PR (issue #1593):

    <!-- workflow-shell-contract: bash-zsh -->
    ```bash
    git push origin "implementation-plan/[branch-slug]:implementation-plan/[branch-slug]"

    # Verify the push actually landed: a refused or mis-aimed push must not pass as
    # success (issue #1593). The refusal message is multi-line and can be truncated
    # to nothing by shell-output filtering.
    LOCAL_SHA=$(git rev-parse HEAD)
    REMOTE_SHA=$(git ls-remote origin "refs/heads/implementation-plan/[branch-slug]" | cut -f1)
    if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
      echo "STOP: guardrail 'unclear_requirements' halted this run."
      echo "Item: branch implementation-plan/[branch-slug] and its pull request."
      echo "Cause: the push did not land — local $LOCAL_SHA, remote ${REMOTE_SHA:-<absent>}."
      echo "Human action: check the branch upstream and push permissions, re-run"
      echo "  git push origin \"implementation-plan/[branch-slug]:implementation-plan/[branch-slug]\", and confirm the remote head matches before continuing."
      exit 1
    fi
    ```
12. Before opening the draft PR, run the nested-artifact guard again in `pre-pr`
    mode when a positive numeric issue number is available:

    ```bash
    ./scripts/development-workflow/run-nested-artifact-guard.sh \
      --mode pre-pr \
      --issue "$ISSUE_NUMBER" \
      --expected-branch "implementation-plan/[branch-slug]" \
      --approved-base "$ARTIFACT_BASE_BRANCH"
    ```

    Treat `RESULT=missing_base`, `RESULT=blocked_duplicate`,
    `RESULT=wrong_base`, or `RESULT=scan_failed` as a hard stop before PR
    creation. A deliberate split requires explicit parent-run approval and
    `--allow-split true` with the approved base recorded in the run summary.
13. Open a **draft** PR targeting the plan artifact base branch with:
    - Title: `docs(plan): [feature-name]`
    - Body: summary of the approach, complexity estimate, key risks, link to plan and runbook
    - `Document Quality Gate` log from the pre-PR gate above
    - For complex workflow decision-gate plans: the consistency matrix or a
      pointer to it, using the canonical fields from the Document Quality Gate
      above; for non-gate plans, the not-applicable rationale is enough
14. Return the branch + PR details to the **Work Item Runner**

---

## Step 6: Handoff to Work Item Runner

After the draft PR exists, the **Work Item Runner** owns the rest of the lifecycle for this item:

- Run the internal plan review gate (`implementation-plan-reviewer` / `02-review-implementation-plan-protocol.md`) on the draft PR
- Run the automated reviewer loop and CI loop to completion
- Apply `ready-for-human-review` and move the tracker to **Plan in Review** when the PR is human-ready
- Stop only when the PR is waiting on human review / merge or the run has escalated

For sweep, batch, helper-extraction, or pattern-completeness work, the plan must
name the residual verification strategy and evidence source that implementation
will use before `ready-for-human-review`. The plan should identify whether the
evidence is occurrence/file counts, linked follow-up residuals, out-of-scope
rationale, or apparent caller evidence for helper outputs.

If this protocol is invoked **standalone** rather than through the Work Item Runner, hand off manually by following `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` from the newly opened draft PR.

See `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` and `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md`.
