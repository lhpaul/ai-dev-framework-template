# Incremental Commit Requirement for Dispatch — Implementation Plan

**Spec**: [1_1176-incremental-commit-requirement-for-dispatch_specs.md](1_1176-incremental-commit-requirement-for-dispatch_specs.md)
**Smoke test runbook**: [1176-incremental-commit-requirement-for-dispatch.smoke-test.md](../../../testing/workflow/1176-incremental-commit-requirement-for-dispatch.smoke-test.md)

---

## Summary

**Approach**: Add an explicit incremental checkpoint-commit requirement to the
item dispatch contract and mirror it into the runner-facing agent and skill
surfaces that prepare or receive item handoffs. Recovery guidance will treat the
latest committed checkpoint, including local commits in an assigned worktree, as
the preferred resume boundary while preserving the existing review, CI,
readiness-label, tracker, and merge gates.

**Estimated complexity**: M

**Rationale**: The runtime behavior is documentation and prompt guidance, but it
crosses multiple workflow surfaces: Protocol 90 batch dispatch, Protocol 91 item
handoffs and fixer redispatch, Protocol 95 epic dispatch, mirrored Claude/Cursor
agents, Codex skills, and review guidance. The key risk is contradictory commit
instructions, especially around fixer agents that currently push only once per
review cycle.

**Dependencies**: None.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `38829f7` |
| Template-fit check | Read `.ai-dev-workflow.yaml` and issue #1176 spec | `template.is_template: true`; spec is workflow-tooling guidance and framework-agnostic. |
| Dispatch and recovery protocol surfaces | `rg -l "Stage-agent handoff branch-skip requirement|Fixer agent worktree isolation rule|For each item in the batch, prepare a short handoff|redispatch / resume|Checkpoint-resume worktree preflight" docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md docs/workflow/development-workflow/protocols/95-run-epic-protocol.md \| sort` | 3 files: Protocols 90, 91, and 95. |
| Existing incremental-commit language | `rg -n "commit immediately|completed logical sub-part|batch all|end-of-run commit|incremental commit|committed checkpoint|No partial work committed" docs/workflow .claude/agents .cursor/agents .codex/skills .agents/skills REVIEW.md scripts/development-workflow \|\| true` | No existing dispatch requirement; only unrelated release wording and permission-denial "No partial work committed" text. |
| Worktree/dispatch mirrored surfaces | `rg -l 'BATCH_CONTEXT branch-skip rule|Pre-mutation isolation self-check|Stage-agent handoff branch-skip requirement|Worktree git discipline|Dispatch the matching stage agent|workflow-item-orchestrator|workflow-orchestrator' .claude/agents .cursor/agents .codex/skills .agents/skills \| sort` | Core runner-facing matches include `.claude/agents/developer.md`, `.cursor/agents/developer.md`, `.claude/agents/item-orchestrator.md`, `.cursor/agents/item-orchestrator.md`, `.agents/skills/run-item/SKILL.md`, `.codex/skills/workflow-implementer/SKILL.md`, `.codex/skills/workflow-item-orchestrator/SKILL.md`, and `.codex/skills/workflow-orchestrator/SKILL.md`. |
| Planning checklist impact search | `grep -rl "02-generate-implementation-plan-protocol\\|03-implement-development-protocol" .claude/agents/ .cursor/agents/ .codex/skills/ \| sort` | 6 files reference planning or implementation protocols: `.claude/agents/developer.md`, `.cursor/agents/developer.md`, `.claude/agents/tech-lead.md`, `.cursor/agents/tech-lead.md`, `.codex/skills/workflow-implementer/SKILL.md`, `.codex/skills/workflow-plan-writer/SKILL.md`. |

---

## Layer-by-Layer Changes

### Workflow Protocols

- [ ] Update `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` so each mutating Work Item Runner handoff for substantial or multi-part work includes an **Incremental commit requirement**:
  - commit immediately after each completed logical sub-part;
  - do not intentionally batch all completed sub-parts into one end-of-run commit;
  - single-step work may still produce one final commit when there is no meaningful completed intermediate checkpoint;
  - the reason is crash recovery for committed partial progress;
  - the instruction is scoped to the assigned item, branch, and worktree.
- [ ] Update `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` in three places:
  - stage-agent handoff requirements, so creator agents see the same checkpoint-commit instruction before work starts;
  - fixer-agent handoff requirements, reconciling incremental **local commits** with the existing anti-churn rule that fixer agents should push once per review cycle;
  - supervision/recovery guidance, so interrupted runs inspect the item branch, local worktree commits, and uncommitted edits before resuming.
- [ ] Update `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` so epic-scoped item execution passes the same incremental-commit requirement into child item handoffs and recovery language.
- [ ] Update `docs/workflow/development-workflow/README.md` to summarize incremental commits as a recoverability convention in the orchestrator/runner overview without changing the staged lifecycle.
- [ ] Update `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` so direct developer-stage runs understand that multi-part implementation work should create coherent checkpoint commits after completed sub-parts, while broken/incomplete edits must not be committed.

### Agent And Skill Guidance

- [ ] Update dispatcher/runner prompts that prepare item handoffs:
  - `.claude/agents/orchestrator.md`
  - `.cursor/agents/orchestrator.md`
  - `.claude/agents/item-orchestrator.md`
  - `.cursor/agents/item-orchestrator.md`
  - `.agents/skills/run-item/SKILL.md`
  - `.agents/skills/run-items/SKILL.md`
  - `.agents/skills/run-epic/SKILL.md`
  - `.codex/skills/workflow-orchestrator/SKILL.md`
  - `.codex/skills/workflow-item-orchestrator/SKILL.md`
- [ ] Update stage-agent surfaces that can perform substantial mutating work:
  - `.claude/agents/product-manager.md`
  - `.cursor/agents/product-manager.md`
  - `.claude/agents/tech-lead.md`
  - `.cursor/agents/tech-lead.md`
  - `.claude/agents/developer.md`
  - `.cursor/agents/developer.md`
  - `.codex/skills/workflow-spec-writer/SKILL.md`
  - `.codex/skills/workflow-plan-writer/SKILL.md`
  - `.codex/skills/workflow-implementer/SKILL.md`
  - `.codex/skills/workflow-spec-writer/agents/openai.yaml`
  - `.codex/skills/workflow-plan-writer/agents/openai.yaml`
  - `.codex/skills/workflow-implementer/agents/openai.yaml`
- [ ] Update compact OpenAI skill prompts where they carry the same dispatch contract:
  - `.agents/skills/run-item/agents/openai.yaml`
  - `.agents/skills/run-items/agents/openai.yaml`
  - `.agents/skills/run-epic/agents/openai.yaml`
  - `.codex/skills/workflow-orchestrator/agents/openai.yaml`
  - `.codex/skills/workflow-item-orchestrator/agents/openai.yaml`

### Review Guidance

- [ ] Update `REVIEW.md` for PRs that add or modify item dispatch, stage-agent handoff, or recovery behavior:
  - reviewers should confirm the incremental commit requirement is visible before mutating item work starts;
  - reviewers should confirm the guidance does not weaken internal review, automated reviewer loop, CI, readiness labels, tracker transitions, or human merge policy;
  - reviewers should confirm fixer-agent guidance preserves the push-once reviewer-loop rule while allowing local checkpoint commits.

### Tests And Runbooks

- [ ] Add the smoke test runbook at `docs/testing/workflow/1176-incremental-commit-requirement-for-dispatch.smoke-test.md`.
- [ ] No database, API, UI, infrastructure, or seed-data changes are required.

---

## Cross-Cutting Guidance Assessment

This change modifies a cross-surface workflow safety convention, not a parser,
API, or concurrent event source. It does not add a new planning checklist to
Protocol 02, so Protocol 02 itself does not need a new checklist block. The
tech-lead and plan-writer receiving-agent prompts still need the concise
incremental-commit instruction because they can be dispatched for substantial
plan-stage work.

The implementation must still update all dispatch, receiver, recovery, and
review surfaces named above. Leaving the requirement only in Protocol 90 would
not satisfy AC1 or AC8 because stage agents and recovery operators would not
consistently see it at the point of work.

---

## Testing Strategy

**Test types**: Documentation lint, smoke/manual workflow verification.

**Key scenarios to test**:

1. Batch item dispatch includes the incremental commit requirement before work starts (AC1, AC2, AC3, AC7, AC8).
2. Stage-agent and fixer handoffs preserve item/worktree scope and do not authorize sibling edits or recovery actions (AC7).
3. Recovery guidance treats committed checkpoint commits as the preferred resume boundary and treats no newer commit as acceptable evidence when no completed sub-part existed (AC4, AC5).
4. PR readiness guidance remains unchanged: review, reviewer loop, CI, readiness labels, tracker status, and human merge policy still gate readiness (AC6).

**Smoke test runbook**: `docs/testing/workflow/1176-incremental-commit-requirement-for-dispatch.smoke-test.md`

**Regression suite**: No executable regression suite currently covers these Markdown workflow contracts. The implementation should run markdown lint and the workflow heuristic markdown linter over the changed docs.

---

## Seed Data

No seed data is required.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` — add the batch-dispatch incremental commit requirement.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — add stage-agent, fixer-agent, and recovery checkpoint-commit guidance.
- [ ] `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` — add epic-scoped item handoff and recovery guidance.
- [ ] `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` — align direct developer-stage commit guidance with coherent checkpoint commits.
- [ ] `docs/workflow/development-workflow/README.md` — summarize the recoverability convention in the workflow overview.
- [ ] `REVIEW.md` — add review checks for dispatch/recovery guidance changes.
- [ ] Agent and skill files listed in **Agent And Skill Guidance** — mirror the dispatch requirement in every runner-facing and stage-receiving surface.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Fixer-agent guidance conflicts with the existing reviewer-loop push-once rule. | Medium | Medium | Specify that coherent local checkpoint commits are allowed or required for substantial fixer work, but the fixer still pushes once after all addressable fixes for the cycle are complete. |
| Agents commit broken intermediate states just to satisfy the new requirement. | Medium | Medium | Define a logical sub-part as a coherent checkpoint and explicitly exempt incomplete, failing, or incoherent edits. |
| The requirement is only added to one protocol and is not visible to receiving agents. | Medium | High | Update Protocols 90/91/95 plus the mirrored orchestrator, item-orchestrator, and developer skill/agent surfaces. Verify with smoke-test searches. |
| Recovery operators assume commits replace validation. | Low | High | Preserve existing review, reviewer-loop, CI, readiness-label, tracker, and merge gate language in protocols and `REVIEW.md`. |

---

## Code Samples

No production code samples are required. Any implementation snippets should be
plain Markdown guidance, not executable shell.

---

## Implementation Order

1. Update Protocol 90 batch handoff text to include the incremental checkpoint-commit requirement for mutating item dispatches. Keep the read-only carve-out unchanged.
2. Update Protocol 91 stage-agent handoff text so every creator-stage handoff carries the requirement with the existing scope and worktree instructions.
3. Update Protocol 91 fixer-agent text so substantial fixer work may create coherent local checkpoint commits but still pushes once per review cycle after all addressable fixes are complete.
4. Update Protocol 91 recovery/supervision text so recovery inspects item branch history, local worktree commits, and uncommitted edits before deciding whether to resume from the latest committed checkpoint or treat the absence of a newer checkpoint as evidence that no completed sub-part existed.
5. Update Protocol 95 epic handoff and recovery text so epic-scoped item agents receive the same requirement before work starts.
6. Update the mirrored orchestrator and item-orchestrator agent/skill files named in this plan. Keep wording intentionally parallel to the protocol text.
7. Update stage-receiving guidance in the product-manager, tech-lead, developer, workflow-spec-writer, workflow-plan-writer, and workflow-implementer surfaces listed in **Agent And Skill Guidance**.
8. Update `REVIEW.md` to add dispatch/recovery review checks and ensure reviewers verify that validation gates remain unchanged.
9. Update `docs/workflow/development-workflow/README.md` with a short operator-facing overview of the recoverability convention.
10. Add/update the implementation `CHANGELOG.md` entry under `[Unreleased]` using this literal format:
    `- **Require incremental checkpoint commits for item dispatch** (#1176): Adds recoverability guidance requiring coherent checkpoint commits after completed logical sub-parts of long-running item work.`
11. Run documentation verification:
    - `npx markdownlint-cli2 "docs/specs/developments/**/*.md" "docs/testing/workflow/**/*.md" "CHANGELOG.md"`
    - `find docs/specs/developments docs/testing/workflow -name "*.md" -print0 | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md`
    - `bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md`
12. Run the smoke test runbook and confirm all AC-mapped assertions pass.
