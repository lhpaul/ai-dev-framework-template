# Workflow Agents and Command Wrappers Product Repository Awareness - Implementation Plan

**Spec**: [1_879-workflow-agents-product-repo-aware_specs.md](1_879-workflow-agents-product-repo-aware_specs.md)
**Smoke test runbook**: [879-workflow-agents-product-repo-aware.smoke-test.md](../../../testing/workflow/879-workflow-agents-product-repo-aware.smoke-test.md)

---

## Summary

**Approach**: Update workflow agent prompts and command-wrapper guidance so
each stage states repository mode and artifact ownership before acting. Keep
wrappers thin by routing product-repository selection through shared scripts and
helpers from #875/#878 instead of embedding separate selection rules in Claude,
Cursor, Codex, or `.agents` files.

**Estimated complexity**: M

**Rationale**: The changes are mostly documentation and prompt updates, but the
write set is broad and must stay consistent across agent surfaces. The highest
risk is omitting one runner surface or letting a wrapper duplicate logic that
should remain in shared scripts.

**Dependencies**: #874 and #875 must be merged into `develop-workflow-hub-mode`
before implementation starts. #878 should be merged first or implemented in the
same integration branch before this item is used for product implementation
work, because wrappers should delegate repository routing to the product-aware
scripts.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `8b30a37` |
| Approved spec | `sed -n '1,360p' docs/specs/developments/20260610165352_879-workflow-agents-product-repo-aware/1_879-workflow-agents-product-repo-aware_specs.md` | Spec requires mode-aware orchestrators, stage agents, reviewers, smoke testers, and wrappers across Claude, Cursor, Codex, and `.agents`. |
| Agent and wrapper inventory | `find .claude .cursor .codex/skills .agents/skills -maxdepth 3 -type f \( -name '*.md' -o -name '*.yaml' -o -name 'SKILL.md' \) \| sort` | Inventory includes Claude/Cursor agents and commands, Codex skills, and `.agents` command aliases. |
| Repository mode guidance | `sed -n '1,320p' docs/workflow/development-workflow/repository-modes.md` | Existing #874/#875 guidance documents owner split for specs, plans, code PRs, CI, reviewer loops, and product repo selection. |
| Existing stage protocols | `rg -n "BATCH_CONTEXT\|BASE_BRANCH\|reviewer loop\|smoke" docs/workflow/development-workflow/protocols .claude/agents .cursor/agents .codex/skills .agents/skills` | Current prompts contain worktree and review-loop handoff rules but do not consistently require product repository context declaration. |

---

## Layer-by-Layer Changes

### Workflow Protocols and Shared Guidance

- [ ] Update `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`.
      - Require workflow hub runs to include selected product repository context
        in Work Item Runner handoffs before implementation work.
      - Preserve `single_repo` behavior without requiring `--repo`.
- [ ] Update `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`.
      - Require item-orchestrator summaries and stage-agent handoffs to state
        mode, artifact owner, selected product repository, local path or remote
        identity, and mutation target before code mutation.
      - Stop before mutation when product repository selection is missing or
        ambiguous.
- [ ] Update `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md`
      and `02-generate-implementation-plan-protocol.md`.
      - State that specs and plans remain hub-owned in `workflow_hub` mode
        unless future docs explicitly say otherwise.
      - State the target repository for spec/plan PR creation.
- [ ] Update `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`.
      - Require developer handoff metadata to identify selected product
        repository before implementation branch creation, file edits, commits,
        and PR creation in workflow hub mode.
      - Keep `single_repo` branch behavior unchanged.
- [ ] Update `docs/workflow/development-workflow/protocols/04-smoke-test-protocol.md`.
      - Require smoke testers to report whether the runbook or implementation
        artifact is hub-owned or product-repository-owned.
- [ ] Update `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`.
      - Require reviewer-loop wrappers to pass through repository context to
        shared scripts instead of re-implementing selection.

### Claude Agent and Command Surfaces

- [ ] Update `.claude/agents/orchestrator.md`.
- [ ] Update `.claude/agents/item-orchestrator.md`.
- [ ] Update `.claude/agents/product-manager.md`.
- [ ] Update `.claude/agents/tech-lead.md`.
- [ ] Update `.claude/agents/developer.md`.
- [ ] Update `.claude/agents/spec-reviewer.md`.
- [ ] Update `.claude/agents/implementation-plan-reviewer.md`.
- [ ] Update `.claude/agents/code-reviewer.md`.
- [ ] Update `.claude/agents/automated-reviewer-loop.md`.
- [ ] Update `.claude/agents/smoke-tester.md`.
- [ ] Update command wrappers:
      `.claude/commands/run-work.md`,
      `.claude/commands/run-item-work.md`,
      `.claude/commands/run-reviewer-loop.md`,
      `.claude/commands/generate-new-feature.md` if present,
      `.claude/commands/generate-implementation-plan.md` if present,
      `.claude/commands/implement-development.md` if present,
      `.claude/commands/review-spec.md` if present,
      `.claude/commands/review-implementation-plan.md` if present,
      `.claude/commands/review-code.md` if present, and
      `.claude/commands/post-merge-cleanup.md`.
- [ ] For each updated Claude file, add only routing obligations and
      context-declaration language. Do not duplicate repository selection
      parsing rules.

### Cursor Agent and Command Surfaces

- [ ] Update `.cursor/agents/orchestrator.md`.
- [ ] Update `.cursor/agents/item-orchestrator.md`.
- [ ] Update `.cursor/agents/product-manager.md`.
- [ ] Update `.cursor/agents/tech-lead.md`.
- [ ] Update `.cursor/agents/developer.md`.
- [ ] Update `.cursor/agents/spec-reviewer.md`.
- [ ] Update `.cursor/agents/implementation-plan-reviewer.md`.
- [ ] Update `.cursor/agents/code-reviewer.md`.
- [ ] Update `.cursor/agents/automated-reviewer-loop.md`.
- [ ] Update `.cursor/agents/smoke-tester.md`.
- [ ] Update command wrappers:
      `.cursor/commands/run-work.md`,
      `.cursor/commands/run-item-work.md`,
      `.cursor/commands/run-reviewer-loop.md`,
      `.cursor/commands/generate-new-feature.md`,
      `.cursor/commands/generate-implementation-plan.md`,
      `.cursor/commands/implement-development.md`,
      `.cursor/commands/review-spec.md`,
      `.cursor/commands/review-implementation-plan.md`,
      `.cursor/commands/review-code.md`,
      `.cursor/commands/post-merge-cleanup.md`, and
      `.cursor/commands/prepare-commit.md` only if implementation branch
      ownership affects commit guidance.

### Codex and `.agents` Skill Surfaces

- [ ] Update `.codex/skills/workflow-orchestrator/SKILL.md` and
      `.codex/skills/workflow-orchestrator/agents/openai.yaml`.
- [ ] Update `.codex/skills/workflow-item-orchestrator/SKILL.md` and
      `.codex/skills/workflow-item-orchestrator/agents/openai.yaml`.
- [ ] Update `.codex/skills/workflow-spec-writer/SKILL.md`.
- [ ] Update `.codex/skills/workflow-plan-writer/SKILL.md`.
- [ ] Update `.codex/skills/workflow-implementer/SKILL.md`.
- [ ] Update `.codex/skills/workflow-spec-reviewer/SKILL.md`,
      `.codex/skills/workflow-plan-reviewer/SKILL.md`, and
      `.codex/skills/workflow-code-reviewer/SKILL.md`.
- [ ] Update `.codex/skills/workflow-reviewer-loop/SKILL.md`.
- [ ] Update `.codex/skills/post-merge-cleanup/SKILL.md` if cleanup handoff
      context is mentioned there.
- [ ] Update `.agents/skills/run-work/SKILL.md` and
      `.agents/skills/run-work/agents/openai.yaml`.
- [ ] Update `.agents/skills/run-item-work/SKILL.md` and
      `.agents/skills/run-item-work/agents/openai.yaml`.
- [ ] Update `.agents/skills/run-reviewer-loop/SKILL.md` and
      `.agents/skills/run-reviewer-loop/agents/openai.yaml`.
- [ ] Update `.agents/skills/code-review/SKILL.md` and
      `.agents/skills/code-review/agents/openai.yaml`.

### Tests and Validation

- [ ] Add
      `scripts/development-workflow/tests/test-workflow-agent-product-repo-guidance.sh`.
- [ ] Test for required prompt fragments rather than exact full-file text.
- [ ] Cover:
      - orchestrator and item-orchestrator mention selected product repository
        context in workflow hub implementation handoffs
      - product-manager and tech-lead say specs/plans are hub-owned in workflow
        hub mode
      - developer prompts require selected product repository before mutation
      - reviewers and smoke testers report artifact repository owner
      - reviewer-loop wrappers call shared scripts/helpers instead of
        inventing selection logic
      - single-repo prompts remain valid and do not require `--repo`
- [ ] Update `scripts/development-workflow/tests/test-install-codex-skills.sh`
      only if skill metadata changes require fixture expectations.

### Documentation

- [ ] Update `docs/workflow/development-workflow/repository-modes.md` with a
      short agent-obligations subsection if it does not already describe prompt
      expectations.
- [ ] Add the implementation changelog entry under `[Unreleased]` / `### Changed`:
      `- **Workflow agent product repository awareness** (#879): teaches Claude, Cursor, Codex, and command-wrapper prompts to declare repository context and route implementation work to selected product repositories in workflow hub mode.`

### Database / Frontend / Infrastructure

- [ ] None. This feature changes prompts, protocols, tests, and documentation
      only.

---

## Testing Strategy

**Test types**: Prompt-fragment shell tests, markdown lint, heuristic lint, and
skill-install regression tests if skill metadata changes.

**Key scenarios to test**:

1. Portfolio orchestrator and run-work preserve single-repo behavior without
   `--repo` (AC1, AC10).
2. Item orchestrator states selected product repository before mutation in
   workflow hub mode (AC2, AC9).
3. Product-manager and tech-lead create spec/plan artifacts in the documented
   owner repository (AC3).
4. Developer prompts require selected product repository for branches, commits,
   and implementation PRs (AC4, AC9).
5. Spec, plan, and code reviewers report artifact repository owner (AC5).
6. Smoke testers report runbook or implementation artifact owner (AC6).
7. Reviewer-loop wrappers pass shared repository context through to scripts and
   report the selected product repository (AC7, AC8).

**Smoke test runbook**:
`docs/testing/workflow/879-workflow-agents-product-repo-aware.smoke-test.md`

**Regression suite**:

- `bash scripts/development-workflow/tests/test-workflow-agent-product-repo-guidance.sh`
- `bash scripts/development-workflow/tests/test-install-codex-skills.sh`
- `npx markdownlint-cli2 "docs/specs/developments/20260610165352_879-workflow-agents-product-repo-aware/*.md" "docs/testing/workflow/879-workflow-agents-product-repo-aware.smoke-test.md" "CHANGELOG.md"`
- `python3 scripts/lint/markdown-heuristic-lint.py docs/testing/workflow/879-workflow-agents-product-repo-aware.smoke-test.md CHANGELOG.md`
- `bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md`

### Parser-risk Addendum

- **Edge-case enumeration**:
  - missing mode / `single_repo` prompt path
  - `workflow_hub` spec-writing path
  - `workflow_hub` plan-writing path
  - `workflow_hub` implementation path with selected product repository
  - `workflow_hub` implementation path with missing product repository
  - `product_repo` planning path that should point back to hub ownership
  - review of hub-owned spec PR
  - review of hub-owned plan PR
  - review of product-owned implementation PR
  - smoke test for hub-owned workflow runbook
  - smoke test for product-owned implementation artifact
  - command wrapper that should stay thin and call shared scripts
  - Codex skill alias that should route to canonical protocols
  - prompt text containing `--repo` language that must not make it mandatory in
    `single_repo`
- **Unit test mapping**: Add one named assertion per edge case in
  `scripts/development-workflow/tests/test-workflow-agent-product-repo-guidance.sh`.
- **Suppression semantics**: No suppression behavior is introduced.

---

## Seed Data

No persistent seed data is required. Tests inspect committed prompt and wrapper
files directly.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/repository-modes.md` - add or refine
      agent obligations for context declaration and owner reporting.
- [ ] `CHANGELOG.md` - add the implementation entry listed above.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| One runner surface is missed | Medium | High | Use the live inventory in the Verification Log and test required prompt fragments across Claude, Cursor, Codex, and `.agents`. |
| Wrappers duplicate selection rules | Medium | Medium | Keep wrapper text limited to calling canonical protocols/scripts and shared helpers. |
| Single-repo users see mandatory product-repo prompts | Medium | High | Test that single-repo language remains valid without `--repo`. |
| Developer prompt allows mutation before context declaration | Medium | High | Add explicit pre-mutation context statement requirements and tests. |

---

## Code Samples

No production code samples are required. Implementation should use concise
prompt text and shared terminology from `repository-modes.md`.

---

## Implementation Order

1. Update protocol ownership and handoff guidance in Protocols 90, 91, 01, 02,
   03, 04, and 93.
2. Update Claude agents and command wrappers listed in this plan.
3. Update Cursor agents and command wrappers listed in this plan.
4. Update Codex skills and `.agents` command aliases listed in this plan.
5. Add prompt-fragment tests for mode awareness, selected product repository
   declaration, owner reporting, missing-context stops, and thin-wrapper
   behavior.
6. Update `repository-modes.md` and `CHANGELOG.md`.
7. Run the regression suite from **Testing Strategy** and fix any failures.
