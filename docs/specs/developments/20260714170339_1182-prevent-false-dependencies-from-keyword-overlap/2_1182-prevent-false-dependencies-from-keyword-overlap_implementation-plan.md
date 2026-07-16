# Prevent False Dependencies From Keyword Overlap - Implementation Plan

**Spec**: [1_1182-prevent-false-dependencies-from-keyword-overlap_specs.md](1_1182-prevent-false-dependencies-from-keyword-overlap_specs.md)
**Smoke test runbook**: [docs/testing/workflow/1182-prevent-false-dependencies-from-keyword-overlap.smoke-test.md](../../../testing/workflow/1182-prevent-false-dependencies-from-keyword-overlap.smoke-test.md)

---

## Summary

**Approach**: Add a workflow helper that builds a conservative spec-dispatch
context for Backlog spec starts, then require Protocol 90 and Protocol 91 to use
that context before dispatching spec work. The helper will record
human-confirmed design decisions, classify terminology overlap as `Dependent`,
`Orthogonal`, or `Unclear`, and emit concise JSON that orchestrators pass to the
spec writer without inventing dependency context from keywords alone.

**Estimated complexity**: M

**Rationale**: The change touches orchestration protocols, mirrored agent/skill
guidance, a new shell helper, and workflow tests. The implementation is bounded
to workflow tooling, but the relationship logic needs careful conservative
classification and regression coverage for false-positive dependency cases.

**Dependencies**: None. This plan targets `develop` and does not require another
feature to merge first.

---

## Verification Log

| Check | Command / query | Result |
| ----- | --------------- | ------ |
| Repo revision | `git rev-parse --short HEAD` | `38829f7` |
| Template-fit check | Read `.ai-dev-workflow.yaml` | `template.is_template: true`; spec is workflow-tooling behavior and framework-agnostic. |
| Issue state | `gh issue view 1182 --json number,title,state,projectItems,url` | Issue #1182 is open and project status is `Writing Plan`. |
| Spec-dispatch and dependency surfaces | `rg -n "spec-dispatch\|dispatch spec\|Writing Spec\|Dependency gate\|Dependency check" docs/workflow/development-workflow/protocols scripts/development-workflow .claude .cursor .codex/skills .agents/skills` | Existing dependency handling is concentrated in `90-batch-orchestrate-work-protocol.md`, `91-orchestrate-work-protocol.md`, `01-generate-spec-protocol.md`, and scope resolver helpers; no relationship outcome model exists. |
| Mirrored stage guidance | `grep -rl "90-batch-orchestrate-work-protocol\|91-orchestrate-work-protocol\|01-generate-spec-protocol" .claude/agents/ .cursor/agents/ .codex/skills/ .agents/skills/ \| sort` | 12 guidance files reference the affected orchestration/spec stages and are listed below. |
| Existing workflow tests | `find scripts/development-workflow/tests -maxdepth 1 -type f -name 'test-*.sh' \| sort` | Shell helper tests live under `scripts/development-workflow/tests/`; add a focused helper test there. |

---

## Layer-by-Layer Changes

### Database / Data Layer

- [ ] No database or persistent storage changes. The data model is an ephemeral
  JSON dispatch-context object generated at run time and passed through
  orchestrator handoff metadata.
- [ ] No seed data is required. Workflow tests will use shell fixtures and
  stubbed `gh issue view` output.

### Workflow Helper / Business Logic

- [ ] Add `scripts/development-workflow/spec-dispatch-context.sh`.
- [ ] Helper inputs:
  - `--selected <issue-number>`: the Backlog item about to enter spec writing.
  - `--items <comma-separated-issue-numbers>`: the current in-scope batch or a
    single-item scope.
  - Optional `--confirmed-decision-file <path>`: newline-delimited JSON records
    captured by the orchestrator from current-session human corrections or
    approvals. Each record uses `issue`, `summary`, and optional `source`.
  - Optional `--json`: emit machine-readable output; default can print a concise
    text summary for humans.
- [ ] Helper output data model:
  - `selected`: issue number, title, and short brief excerpt.
  - `confirmedDecisions[]`: human-confirmed decisions that match the selected
    item, sourced from the optional decision file and matching issue comments.
  - `relationships[]`: one entry per other in-scope item with meaningful
    terminology overlap. Each entry includes `issue`, `title`, `outcome`
    (`Dependent`, `Orthogonal`, or `Unclear`), `overlapTerms[]`,
    `evidence[]`, and `dispatchInstruction`.
  - `blocking`: boolean. `true` only when at least one `Unclear` relationship
    could alter product scope, ordering, dependencies, acceptance criteria, or
    out-of-scope boundaries.
  - `humanAction`: present when `blocking=true`, naming the missing decision.
- [ ] Matching algorithm:
  - Tokenize selected and peer issue title/body text into normalized significant
    terms and two-word phrases.
  - Ignore common stopwords and workflow boilerplate terms such as `issue`,
    `spec`, `plan`, `implementation`, `workflow`, `agent`, `add`, and `update`.
  - Treat overlap as meaningful only when at least two significant terms overlap
    or one normalized phrase overlaps.
  - Classify `Dependent` only with concrete evidence: explicit issue reference,
    dependency phrase (`depends on`, `blocked by`, `requires`, `waiting on`), a
    shared acceptance criterion that names the other issue, or a
    human-confirmed prerequisite.
  - Classify `Orthogonal` when meaningful overlap exists but issue objectives
    describe independent outcomes and no concrete dependency evidence appears.
  - Classify `Unclear` when overlap exists and the available text contains
    coupling language that could affect scope, ordering, dependencies,
    acceptance criteria, or out-of-scope boundaries, but lacks concrete evidence
    for either dependency or independence.
- [ ] Human-confirmed decision detection:
  - Recognize current-session decisions from `--confirmed-decision-file`.
  - Recognize issue-comment decisions when a comment contains explicit human
    decision language such as `confirmed`, `approved`, `correction`,
    `clarifying`, or `decision`, and references the selected issue or appears on
    the selected issue.
  - Use the newest matching decision when multiple decisions conflict; include
    the older source in `evidence[]` so the orchestrator can stop if the conflict
    remains ambiguous.

### Workflow Protocols

- [ ] Update
  `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`.
  Add a pre-dispatch relationship-context gate after candidate selection and
  dependency checks but before tracker mutation and Work Item Runner dispatch.
  The protocol must require the Portfolio Orchestrator to run the helper for
  every Backlog item that will enter spec writing and to include the resulting
  relationship summary in the proposed batch and stage-agent handoff.
- [ ] Update
  `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`.
  For single-item Backlog spec starts, require the Work Item Runner to run the
  helper with the selected item as a one-item scope and any handoff-provided
  current-session decision file before invoking
  `01-generate-spec-protocol.md`.
- [ ] Update
  `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md`.
  In Step 1, require the product-manager/spec writer to read and preserve any
  supplied spec-dispatch context, treating confirmed decisions and relationship
  outcomes as product constraints while keeping implementation details deferred
  to the plan stage.
- [ ] Update `docs/workflow/development-workflow/integrations/issue-tracker.md`
  to document that issue comments can be a source of human-confirmed design
  decisions for spec dispatch.
- [ ] Update `docs/workflow/development-workflow/README.md` to note that
  Backlog spec starts distinguish explicit dependencies from shared terminology
  before spec dispatch.

### Agent / Skill Guidance

- [ ] Update batch orchestration guidance:
  - `.claude/agents/orchestrator.md`
  - `.cursor/agents/orchestrator.md`
  - `.codex/skills/workflow-orchestrator/SKILL.md`
  - `.agents/skills/run-items/SKILL.md`
- [ ] Update single-item orchestration guidance:
  - `.claude/agents/item-orchestrator.md`
  - `.cursor/agents/item-orchestrator.md`
  - `.codex/skills/workflow-item-orchestrator/SKILL.md`
  - `.agents/skills/run-item/SKILL.md`
- [ ] Update spec-writer guidance:
  - `.claude/agents/product-manager.md`
  - `.cursor/agents/product-manager.md`
  - `.codex/skills/workflow-spec-writer/SKILL.md`
- [ ] Guidance must state that shared keywords alone are not dependency
  evidence and that `Unclear` blocking output stops spec dispatch until a human
  provides the missing relationship decision.

### Infrastructure / Configuration

- [ ] No infrastructure, CI, dependency, or environment-variable changes.
  Implement the helper with existing shell, `gh`, `jq`, `awk`, `sed`, and `tr`
  tooling already used by workflow scripts.

---

## Testing Strategy

**Test types**: Unit shell tests, protocol/document lint, smoke/manual workflow
verification.

**Key scenarios to test**:

1. Orthogonal overlap maps to AC-1, AC-5, and AC-6: two issues share a product
   area phrase but describe independent outcomes; helper emits `Orthogonal` and
   no dependency instruction.
2. Confirmed decision preservation maps to AC-2: selected issue has a
   current-session or issue-comment decision; helper includes a concise decision
   summary in `confirmedDecisions[]`.
3. Dependent evidence maps to AC-3: peer issue text explicitly says it depends
   on the selected item or vice versa; helper emits `Dependent` with concrete
   evidence.
4. Unclear relationship maps to AC-4: issue text uses coupling language without
   concrete evidence; helper emits `Unclear`, `blocking=true`, and a human
   action.
5. Issue #1182 example maps to AC-6: `unit stages` within one component instance
   is orthogonal to `multiple component instances` despite both mentioning
   public-site components.
6. Workflow-level coverage maps to AC-7: Protocol 90 and Protocol 91 both
   require the helper before Backlog spec dispatch, and the smoke runbook
   verifies the handoff language.
7. Plan-stage mechanism decision maps to AC-8: implementation uses the helper,
   JSON data model, conservative matching algorithm, and no persistent storage.

**Smoke test runbook**:
`docs/testing/workflow/1182-prevent-false-dependencies-from-keyword-overlap.smoke-test.md`

**Regression suite**: Add
`scripts/development-workflow/tests/test-spec-dispatch-context.sh` and include it
in the workflow test execution path used by CI or local validation.

### Parser-risk addendum

This plan is parser-risk because it introduces structured text scanning over
issue titles, bodies, comments, and optional decision records.

**Edge-case enumeration**:

1. Boundary-character variants: `public-site`, `public site`,
   `public_site`, and quoted `"public site"` normalize to comparable tokens.
2. Negative lookalikes: a peer issue that says `not dependent on #N` must not be
   classified as `Dependent` merely because `dependent on #N` appears inside the
   sentence.
3. Multiple occurrences on one line: repeated overlap terms or repeated issue
   references on one line do not duplicate relationship entries or evidence.
4. Nested or overlapping constructs: a sentence such as `requires clarification,
   not #123` must not be treated as `requires #123`.
5. Issue #1182 regression: overlapping `public site components` language plus
   separate objectives classifies as `Orthogonal`.
6. Conflicting human decisions: newest explicit human decision wins only when
   source ordering is available; otherwise the helper emits `Unclear` with both
   evidence records.
7. Low-impact overlap: one shared generic term such as `component` or
   `workflow` is ignored and does not create a relationship row.

**Unit test mapping**:

- `scripts/development-workflow/tests/test-spec-dispatch-context.sh`
  - Test 1 covers boundary-character variants.
  - Test 2 covers negative lookalikes.
  - Test 3 covers multiple occurrences on one line.
  - Test 4 covers nested or overlapping constructs.
  - Test 5 covers the issue #1182 Orthogonal regression.
  - Test 6 covers conflicting human decisions.
  - Test 7 covers low-impact overlap filtering.

**Suppression semantics**: Not applicable. The feature does not add inline
suppression directives.

### Concurrent-event-source addendum

Not applicable. The implementation is invoked synchronously during orchestration
and does not introduce concurrent event listeners, sockets, timers, queues, or
shared mutable state across execution contexts.

---

## Seed Data

| Entity | Values / Scenario | File |
| ------ | ----------------- | ---- |
| Stubbed GitHub issues | Orthogonal public-site components, explicit dependent issues, unclear coupling language, and the issue #1182 regression pair | `scripts/development-workflow/tests/test-spec-dispatch-context.sh` fixtures |
| Stubbed decision records | JSONL records with selected issue, summary, source, and conflicting newest/oldest cases | Temporary files created by `scripts/development-workflow/tests/test-spec-dispatch-context.sh` |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
  - add the Portfolio Orchestrator pre-dispatch relationship-context gate.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
  - add the Work Item Runner Backlog spec-dispatch context requirement.
- [ ] `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md`
  - add spec-writer consumption rules for confirmed decisions and relationship
    outcomes.
- [ ] `docs/workflow/development-workflow/integrations/issue-tracker.md`
  - document issue comments as a human-confirmed decision source.
- [ ] `docs/workflow/development-workflow/README.md`
  - summarize that Backlog spec dispatch distinguishes true dependencies from
    keyword overlap.
- [ ] Agent and Codex skill guidance listed in **Agent / Skill Guidance** above
  - mirror the new orchestration and spec-writer responsibilities.
- [ ] `CHANGELOG.md`
  - implementation PR only; add under `[Unreleased]` using:
    `- **Prevent false dependency dispatch context** (#1182): Added spec-dispatch relationship context so orchestrators do not infer dependencies from keyword overlap alone.`

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| ---- | ---------- | ------ | ---------- |
| Helper over-classifies dependency from ambiguous wording | Medium | High | Require concrete dependency evidence for `Dependent`; otherwise emit `Orthogonal` or blocking `Unclear`. |
| Helper misses human-confirmed decisions in current session text | Medium | Medium | Accept an explicit decision JSONL file from the orchestrator and also scan issue comments as a durable source. |
| Mirrored guidance drifts across Claude, Cursor, Codex, and command skills | Medium | Medium | Update every guidance file found in the Verification Log and add review checklist coverage through the smoke runbook. |
| Shell text normalization becomes brittle | Medium | Medium | Keep matching conservative, use fixture-based tests for boundary and negative cases, and avoid relying on exact counts for human verification. |
| Orchestrators include too much context in spec prompts | Low | Medium | Helper emits concise `dispatchInstruction` text and protocols require only relevant relationship context. |

---

## Code Samples

No code samples. The implementation PR should add production shell code and
tests directly.

---

## Implementation Order

1. Create `scripts/development-workflow/spec-dispatch-context.sh` with argument
   validation, issue/comment loading through `gh issue view`, token/phrase
   normalization, confirmed-decision collection, relationship classification,
   and JSON/text output.
2. Add `scripts/development-workflow/tests/test-spec-dispatch-context.sh` with
   stubbed `gh` fixtures covering the parser-risk edge cases and the Dependent,
   Orthogonal, and Unclear outcomes.
3. Run the new helper tests and confirm the output distinguishes dependency
   evidence from keyword overlap:
   `bash scripts/development-workflow/tests/test-spec-dispatch-context.sh`.
4. Update Protocol 90 so batch Backlog spec starts run the helper before tracker
   mutation/dispatch, show relationship outcomes in the batch proposal, and pass
   the generated dispatch context to Work Item Runners.
5. Update Protocol 91 so single-item Backlog spec starts run or consume the
   helper output before invoking the spec writer, and stop when `blocking=true`
   names an `Unclear` relationship.
6. Update Protocol 01 so the spec writer preserves supplied confirmed decisions
   and relationship outcomes as product constraints without converting
   implementation choices into spec requirements.
7. Update the batch orchestration, item orchestration, and product-manager
   guidance files listed above to mirror the new protocol responsibilities.
8. Update `docs/workflow/development-workflow/integrations/issue-tracker.md`
   and `docs/workflow/development-workflow/README.md` per the Documentation
   Updates section.
9. Update `CHANGELOG.md` under `[Unreleased]` with:
   `- **Prevent false dependency dispatch context** (#1182): Added spec-dispatch relationship context so orchestrators do not infer dependencies from keyword overlap alone.`
10. Run local validation:
    - `bash scripts/development-workflow/tests/test-spec-dispatch-context.sh`
    - `npx markdownlint-cli2 "docs/specs/developments/**/*.md" "docs/testing/workflow/**/*.md" "CHANGELOG.md"`
    - `find docs/specs/developments docs/testing/workflow -name "*.md" -print0 | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md`
    - `shellcheck scripts/development-workflow/spec-dispatch-context.sh scripts/development-workflow/tests/test-spec-dispatch-context.sh`
    - `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`
11. Use the smoke test runbook to verify that the issue #1182 example produces
    Orthogonal dispatch context and that Unclear output stops before spec
    dispatch.
