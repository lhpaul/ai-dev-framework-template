# Orchestrator Worktree Isolation for Concurrent Items - Implementation Plan

**Spec**: [1_1205-orchestrator-worktree-isolation-for-concurrent-items_specs.md](1_1205-orchestrator-worktree-isolation-for-concurrent-items_specs.md)
**Smoke test runbook**: [1205-orchestrator-worktree-isolation-for-concurrent-items.smoke-test.md](../../../testing/workflow/1205-orchestrator-worktree-isolation-for-concurrent-items.smoke-test.md)

---

## Summary

**Approach**: Tighten the documented dispatch contract for concurrent mutating
batch work. Protocol 90 will require an explicit isolation manifest before any
parallel file-mutating Work Item Runner dispatch, and Protocol 91 plus the
agent/skill command surfaces will require each runner to verify its assigned
worktree and branch before mutation.

**Estimated complexity**: M

**Rationale**: The behavior spans the portfolio orchestrator, item runner
handoffs, Claude/Cursor/Codex command surfaces, and review guidance. The change
is documentation and workflow-contract focused, but it must keep several mirrored
agent surfaces aligned.

**Dependencies**: None. Issue #1200 is related but distinct; this plan must keep
dispatch-time shared-tree contamination separate from nested-agent PR creation.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `d26edf4` |
| Template-fit check | Read `.ai-dev-workflow.yaml` and spec overview | `template.is_template: true`; spec is workflow-template generic and passes Step 0. |
| Existing dispatch surfaces | `grep -rl "90-batch-orchestrate-work-protocol\\|91-orchestrate-work-protocol\\|workflow-item-orchestrator\\|run-items" .claude/agents/ .cursor/agents/ .codex/skills/ .agents/skills/ 2>/dev/null \| sort` | Identified run-items, orchestrator, and item-orchestrator surfaces listed in this plan. |
| Isolation terminology search | `rg -n "isolation|worktree|BATCH_CONTEXT|run-items" docs/workflow/development-workflow .agents/skills .codex/skills .claude .cursor REVIEW.md AGENTS.md` | Existing BATCH_CONTEXT and worktree discipline exists in Protocol 90/91, item-orchestrator prompts, and developer prompts; missing explicit `isolation: "worktree"` dispatch manifest. |

---

## Layer-by-Layer Changes

### Workflow Protocols

- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
  - Add a mandatory concurrent-mutating-dispatch isolation manifest before Step 4 dispatch.
  - Define "mutating runner" and the allowed read-only carve-out.
  - Require each mutating item to list item id, branch, worktree path, and `isolation: "worktree"`.
  - Add duplicate/missing worktree assignment stop conditions.
  - Add final-summary audit output for pass, pre-mutation stop, or escalation.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
  - Add the per-runner pre-mutation self-check for `BATCH_CONTEXT=true`.
  - Require expected worktree path, observed path, expected branch, and observed branch in the runner summary.
  - State that wrong CWD or wrong branch stops before mutation; possible out-of-worktree mutation escalates to human inspection.

### Command And Skill Surfaces

- [ ] `.agents/skills/run-items/SKILL.md`
  - Require the isolation manifest before dispatching two or more concurrent file-mutating items.
  - Include `isolation: "worktree"` and distinct worktree paths in the handoff guidance.
- [ ] `.agents/skills/run-items/agents/openai.yaml`
  - Mirror the concise default-prompt requirement for `isolation: "worktree"`.
- [ ] `.codex/skills/workflow-orchestrator/SKILL.md`
  - Require Codex orchestration to build and verify the isolation manifest before worker dispatch.
- [ ] `.codex/skills/workflow-item-orchestrator/SKILL.md`
  - Require the `BATCH_CONTEXT=true` pre-mutation worktree/branch self-check and summary evidence.
- [ ] `.codex/skills/workflow-item-orchestrator/agents/openai.yaml`
  - Mirror the item-runner default-prompt requirement.
- [ ] `.claude/commands/run-items.md`
  - Add user-facing command guidance for concurrent mutating batches.
- [ ] `.cursor/commands/run-items.md`
  - Add the same user-facing command guidance for Cursor.
- [ ] `.claude/agents/orchestrator.md`
  - Require isolation manifest construction and duplicate/missing path stops.
- [ ] `.cursor/agents/orchestrator.md`
  - Mirror the orchestrator requirement.
- [ ] `.claude/agents/item-orchestrator.md`
  - Require pre-mutation self-check evidence when `BATCH_CONTEXT=true`.
- [ ] `.cursor/agents/item-orchestrator.md`
  - Mirror the item-orchestrator self-check requirement.

### Review And Documentation

- [ ] `REVIEW.md`
  - Add a workflow-review check that concurrent mutating batch dispatches include the isolation manifest and runner self-check evidence.
- [ ] `AGENTS.md`
  - Update only if the run-items command table or top-level command description needs a concise note. Keep detailed behavior in template-owned workflow docs.

### Tests And Validation

- [ ] Run markdown lint for all changed Markdown workflow files.
- [ ] Run the heuristic Markdown linter for workflow docs.
- [ ] Run live search after implementation to confirm every updated surface uses the same core terms: `isolation: "worktree"`, distinct worktree path, pre-mutation self-check, and issue #1200 distinction.

---

## Cross-Cutting Checklist Plan

This change modifies a cross-cutting orchestration safety requirement. The
implementation must update every affected protocol, agent, skill, command, and
review surface listed above. The live enumeration command in the Verification
Log identified the required run-items/orchestrator/item-orchestrator mirrors.

The developer must not update only Protocol 90. Reviewers should treat missing
mirror updates as blocking because a partial rollout would leave at least one
runner surface able to dispatch concurrent mutating agents without the isolation
contract.

---

## Testing Strategy

**Test types**: Documentation lint, workflow contract review, smoke test.

**Key scenarios to test**:

1. A two-item mutating `/run-items` batch includes an isolation manifest with
   unique worktree paths for both items. Maps to AC-1 and AC-2.
2. A concurrent mutating batch with a missing isolation assignment stops before
   dispatch. Maps to AC-3.
3. A concurrent mutating batch with duplicate worktree paths stops before
   dispatch. Maps to AC-4.
4. A `BATCH_CONTEXT=true` item runner reports expected and observed worktree and
   branch before its first mutation. Maps to AC-5 through AC-7.
5. A runner that may already have mutated outside its assigned worktree escalates
   rather than auto-resetting or auto-committing. Maps to AC-8.
6. A read-only concurrent batch can proceed without mandatory isolation only
   when every non-isolated runner is explicitly classified read-only. Maps to
   AC-9.
7. The final summary distinguishes dispatch-time shared-tree contamination from
   the separate #1200 nested-agent PR risk. Maps to AC-10 through AC-12.

**Smoke test runbook**:
`docs/testing/workflow/1205-orchestrator-worktree-isolation-for-concurrent-items.smoke-test.md`

**Regression suite**: No shell helper is required for the MVP unless the
implementation adds executable enforcement. If executable enforcement is added,
extend the closest workflow shell test under
`scripts/development-workflow/tests/` to cover missing and duplicate isolation
assignments.

### Parser-risk addendum

Not applicable. The planned MVP changes workflow protocols, command docs, agent
prompts, and review guidance; it does not introduce a parser, scanner, or
regex-heavy structured-text rule.

### Concurrent-event-source addendum

Not applicable. The feature is about concurrent agent dispatch policy, not
runtime event listeners, socket callbacks, timers, or async shared state inside
software being shipped.

---

## Seed Data

No seed data is required. Testing uses workflow command scenarios and sample
batch handoff summaries.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` - add isolation manifest, stop conditions, and summary evidence.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` - add per-runner pre-mutation worktree and branch self-check evidence.
- [ ] `REVIEW.md` - add reviewer check for concurrent mutating dispatch isolation evidence.
- [ ] `.agents/skills/run-items/SKILL.md` and `.agents/skills/run-items/agents/openai.yaml` - mirror the run-items command contract.
- [ ] `.codex/skills/workflow-orchestrator/SKILL.md`, `.codex/skills/workflow-item-orchestrator/SKILL.md`, and `.codex/skills/workflow-item-orchestrator/agents/openai.yaml` - mirror Codex orchestration and runner behavior.
- [ ] `.claude/commands/run-items.md` and `.cursor/commands/run-items.md` - mirror user-facing command behavior.
- [ ] `.claude/agents/orchestrator.md`, `.cursor/agents/orchestrator.md`, `.claude/agents/item-orchestrator.md`, and `.cursor/agents/item-orchestrator.md` - mirror agent dispatch and runner self-check behavior.
- [ ] `AGENTS.md` - update only if the concise top-level run-items command description needs a note after protocol changes.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Mirror drift across command, agent, and skill surfaces | Medium | High | Use the live enumeration command before and after implementation; update all listed surfaces in one PR. |
| Over-constraining read-only concurrent exploration | Low | Medium | Preserve the explicit read-only carve-out and require classification evidence only for non-isolated runners. |
| Confusing this issue with #1200 nested-agent PR behavior | Medium | Medium | Add an explicit distinction in Protocol 90, Protocol 91, and REVIEW.md. |
| Adding prose without actionable stop conditions | Medium | High | Define missing assignment, duplicate path, wrong CWD, wrong branch, and possible prior mutation as named outcomes with required actions. |

---

## Code Samples

No production code samples are required. The implementation may include
illustrative summary snippets in the workflow docs, but they must be marked as
examples and kept consistent across mirrored surfaces.

---

## Implementation Order

1. Update Protocol 90 with the concurrent mutating dispatch isolation manifest:
   item id, branch, worktree path, isolation mode, and read-only classification
   when applicable.
2. Add Protocol 90 stop conditions for missing isolation, duplicate worktree
   path, and non-isolated mutating runner. Include final-summary audit language.
3. Update Protocol 91 so `BATCH_CONTEXT=true` runners verify expected worktree
   path and branch before any file edit, branch-changing command, commit, or
   push.
4. Update the run-items command and skill mirrors:
   `.agents/skills/run-items/SKILL.md`,
   `.agents/skills/run-items/agents/openai.yaml`,
   `.claude/commands/run-items.md`, and `.cursor/commands/run-items.md`.
5. Update orchestrator and item-orchestrator mirrors for Claude, Cursor, and
   Codex using the file list in this plan.
6. Update `REVIEW.md` with a blocking review check for concurrent mutating batch
   isolation evidence and the #1200 distinction.
7. Run the live mirror search from the Verification Log and confirm all expected
   surfaces include the isolation contract or an explicit rationale for no
   change.
8. Run markdown lint and the workflow heuristic linter:
   `npx markdownlint-cli2 "docs/workflow/development-workflow/**/*.md" ".agents/skills/**/*.md" ".codex/skills/**/*.md" ".claude/**/*.md" ".cursor/**/*.md" "REVIEW.md" "AGENTS.md"`
   and
   `find docs/specs/developments docs/testing/workflow -name "*.md" -print0 | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md`.
9. Execute the smoke test runbook and record results in the implementation PR.
10. Do not update `CHANGELOG.md` during the plan stage. During implementation,
    add an `[Unreleased]` entry using the project format:
    `- **Require Worktree Isolation for Concurrent Runners** (#1205): Require concurrent mutating batch dispatches to use distinct isolated worktrees and pre-mutation runner self-checks.`
