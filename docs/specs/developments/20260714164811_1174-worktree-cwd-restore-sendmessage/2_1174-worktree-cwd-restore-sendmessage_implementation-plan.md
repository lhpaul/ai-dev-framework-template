# Worktree CWD Restore on Checkpoint Resume - Implementation Plan

**Spec**:
[1_1174-worktree-cwd-restore-sendmessage_specs.md](1_1174-worktree-cwd-restore-sendmessage_specs.md)
**Smoke test runbook**:
[1174-worktree-cwd-restore-sendmessage.smoke-test.md](../../../testing/workflow/1174-worktree-cwd-restore-sendmessage.smoke-test.md)

---

## Summary

**Approach**: Add a reusable checkpoint-resume worktree preflight helper that
can verify or safely re-enter the expected item worktree before mutation. Wire
that helper into the canonical run-item and run-epic checkpoint-resume guidance,
then mirror the same operator-facing requirement across the supported command
and Codex skill surfaces.

**Estimated complexity**: M

**Rationale**: The code change is small, but the workflow surface is broad:
one helper, shell tests, two canonical protocols, and mirrored command/skill
guidance must stay consistent.

**Dependencies**: None.

**Template-fit check**: Passed. `.ai-dev-workflow.yaml` sets
`template.is_template: true`, and the item improves generic workflow tooling
shipped by the template rather than a downstream framework-specific runtime.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `d26edf4` |
| Full repo revision | `git rev-parse HEAD` | `d26edf45de5fbc7a95313ba087ad95130b88cb65` |
| Template repository detection | `sed -n '1,240p' .ai-dev-workflow.yaml` | `template.is_template: true`; mode omitted, so plan artifacts are single-repo owned |
| Tracker status | `gh issue view 1174 --json number,title,projectItems,state` | Issue `#1174` is open and project status is `Writing Plan` |
| Existing artifact scope | `find docs/specs/developments/20260714164811_1174-worktree-cwd-restore-sendmessage -maxdepth 1 -type f -print` | Existing spec only: `1_1174-worktree-cwd-restore-sendmessage_specs.md` |
| Current worktree guard | `rg -n "worktree_cwd_guard_init|--check-cwd" scripts/development-workflow/worktree-cwd-guard.sh docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Existing guard protects active worktree sessions and one-shot CWD checks, but does not resolve a checkpoint-resume worktree from a resumed main-clone CWD |
| Command and skill surfaces | `grep -rl "run-item\\|run-epic\\|checkpoint\\|worktree" .agents/skills/run-item .agents/skills/run-item-work .agents/skills/run-epic .codex/skills/workflow-item-orchestrator .claude/commands/run-item.md .claude/commands/run-item-work.md .claude/commands/run-epic.md .cursor/commands/run-item.md .cursor/commands/run-item-work.md .cursor/commands/run-epic.md` | Surfaces found: `.agents/skills/run-item/SKILL.md`, `.agents/skills/run-epic/SKILL.md`, `.codex/skills/workflow-item-orchestrator/SKILL.md`, Claude/Cursor run-item and run-epic commands, and run-item-work aliases |
| Cross-cutting planning search | `grep -rl "02-generate-implementation-plan-protocol\\|03-implement-development-protocol" .claude/agents/ .cursor/agents/ .codex/skills/` | Existing cross-cutting checklist references are in `.claude/agents/developer.md`, `.claude/agents/tech-lead.md`, `.cursor/agents/developer.md`, `.cursor/agents/tech-lead.md`, `.codex/skills/workflow-plan-writer/SKILL.md`, and `.codex/skills/workflow-implementer/SKILL.md`; this plan does not modify that checklist |
| Worktree helper tests | `find scripts/development-workflow/tests -maxdepth 1 -type f -name 'test-worktree*' -print` | No dedicated worktree-resume preflight test exists yet |

---

## Layer-by-Layer Changes

### Workflow Helper Scripts

- [ ] Add `scripts/development-workflow/worktree-resume-preflight.sh`.
      The helper must:
      - accept the expected item identifier, expected branch, optional expected
        worktree path, optional main repo root, and `--json`;
      - inspect the current CWD and branch;
      - inspect registered worktrees with `git worktree list --porcelain`;
      - continue when already inside the expected worktree;
      - emit a re-entry directive when exactly one registered worktree matches
        the expected branch and the current CWD is the main clone;
      - fail closed when the expected worktree is missing, ambiguous, or on a
        mismatched branch;
      - never switch branches, edit files, update PRs, update labels, or update
        tracker state.
- [ ] Reuse `scripts/development-workflow/worktree-cwd-guard.sh` for the final
      active-CWD assertion after re-entry instead of duplicating its main-clone
      detection logic.
- [ ] Add `scripts/development-workflow/tests/test-worktree-resume-preflight.sh`
      with fixture repositories and registered worktrees.

### Workflow Protocols

- [ ] Update
      `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      to add a "checkpoint-resume worktree preflight" step before any
      mutation after a resumed human-checkpoint session.
- [ ] Update
      `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`
      to require the same resume preflight before delegated epic execution
      continues after a checkpointed pause.
- [ ] Ensure both protocols state that successful worktree re-entry does not
      satisfy, waive, or clear any pending human checkpoint.
- [ ] Ensure both protocols name the stop output fields: item, expected branch,
      expected worktree when known, observed directory, observed branch when
      available, failure reason, and human recovery action.

### Command and Skill Surfaces

- [ ] Update `.agents/skills/run-item/SKILL.md` and
      `.agents/skills/run-item/agents/openai.yaml`.
- [ ] Update `.agents/skills/run-item-work/SKILL.md` and
      `.agents/skills/run-item-work/agents/openai.yaml` to state that the
      deprecated alias inherits the same resume preflight.
- [ ] Update `.agents/skills/run-epic/SKILL.md` and
      `.agents/skills/run-epic/agents/openai.yaml`.
- [ ] Update `.codex/skills/workflow-item-orchestrator/SKILL.md` and
      `.codex/skills/workflow-item-orchestrator/agents/openai.yaml`.
- [ ] Update `.claude/commands/run-item.md`,
      `.claude/commands/run-item-work.md`, and `.claude/commands/run-epic.md`.
- [ ] Update `.cursor/commands/run-item.md`,
      `.cursor/commands/run-item-work.md`, and `.cursor/commands/run-epic.md`.

### Review Surface

- [ ] Do not change `REVIEW.md` for this item. Its existing plan-review
      checklist already covers parser-risk, cross-cutting enumeration, shell
      snippet safety, and guardrails-related workflow changes; this feature
      does not introduce a new review checklist category.

### Database / Data Layer

- [ ] Not applicable. No schema, seed data, or persistent data changes.

### Backend / API

- [ ] Not applicable. No API or service endpoint changes.

### Frontend / UI

- [ ] Not applicable. No UI or browser workflow changes.

### Infrastructure / Configuration

- [ ] Not applicable. No CI, secret, environment variable, or deployment
      configuration changes.

---

## Parser-Risk Addendum

This plan is parser-risk because the new helper parses structured output from
`git worktree list --porcelain`.

### Edge-Case Enumeration

1. **Already in expected worktree**: current CWD is the registered worktree path
   or a child directory of it, and the worktree branch equals the expected
   branch.
2. **Main clone with one matching worktree**: current CWD is the main repo root
   and exactly one registered worktree has `branch refs/heads/<expected>`.
3. **Main clone with missing worktree**: current CWD is the main repo root and
   no registered worktree matches the expected branch.
4. **Ambiguous worktree registration**: more than one parsed worktree entry
   appears to match the expected branch or path.
5. **Mismatched branch**: an expected worktree path exists but its parsed
   `branch` entry differs from the expected branch.
6. **Detached or incomplete worktree entry**: a parsed entry has no `branch`
   line, has a `detached` line, or is otherwise missing the data needed to
   prove ownership.
7. **Boundary path variants**: the current CWD is a subdirectory of the
   worktree, a sibling path with the same prefix, the main repo root, or a
   subdirectory of the main repo.
8. **Negative lookalikes**: branches such as
   `implementation-plan/11740-worktree-cwd-restore-sendmessage` or
   `feature/1174-worktree-cwd-restore-sendmessage` must not match the expected
   `implementation-plan/1174-worktree-cwd-restore-sendmessage`.
9. **Whitespace in worktree paths**: porcelain parsing must preserve paths with
   spaces instead of splitting on whitespace.
10. **Corrupt or unavailable worktree list**: a failing `git worktree list`
    command must produce a fail-closed stop result rather than a continue or
    re-entry result.

### Unit Test Mapping

Add tests in
`scripts/development-workflow/tests/test-worktree-resume-preflight.sh`:

| Edge case | Test coverage |
| --- | --- |
| 1 | `already_in_expected_worktree_allows_continue` |
| 2 | `main_clone_single_matching_worktree_returns_reentry` |
| 3 | `main_clone_missing_worktree_stops_before_mutation` |
| 4 | `ambiguous_matching_worktrees_stop_before_mutation` |
| 5 | `expected_path_wrong_branch_stops_before_mutation` |
| 6 | `detached_or_incomplete_entry_stops_before_mutation` |
| 7 | `path_boundary_subdir_allowed_sibling_rejected` |
| 8 | `branch_lookalikes_do_not_match` |
| 9 | `worktree_path_with_spaces_is_preserved` |
| 10 | `worktree_list_failure_stops_before_mutation` |

### Suppression Semantics

Not applicable. This feature does not introduce inline suppression directives.

---

## Cross-Cutting Surface Enumeration

This plan does not introduce a new cross-cutting checklist category under
Protocol 02. It does introduce a workflow safety requirement that must be
mirrored across run-item and run-epic surfaces so operators see the same
checkpoint-resume behavior.

Files to modify:

- `scripts/development-workflow/worktree-resume-preflight.sh`
- `scripts/development-workflow/tests/test-worktree-resume-preflight.sh`
- `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
- `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`
- `.agents/skills/run-item/SKILL.md`
- `.agents/skills/run-item/agents/openai.yaml`
- `.agents/skills/run-item-work/SKILL.md`
- `.agents/skills/run-item-work/agents/openai.yaml`
- `.agents/skills/run-epic/SKILL.md`
- `.agents/skills/run-epic/agents/openai.yaml`
- `.codex/skills/workflow-item-orchestrator/SKILL.md`
- `.codex/skills/workflow-item-orchestrator/agents/openai.yaml`
- `.claude/commands/run-item.md`
- `.claude/commands/run-item-work.md`
- `.claude/commands/run-epic.md`
- `.cursor/commands/run-item.md`
- `.cursor/commands/run-item-work.md`
- `.cursor/commands/run-epic.md`
- `docs/testing/workflow/1174-worktree-cwd-restore-sendmessage.smoke-test.md`
- `CHANGELOG.md` under `[Unreleased]` in the implementation PR only, using:
  `- **Restore worktree CWD on checkpoint resume** (#1174): Add a resume preflight so checkpointed worktree-isolated runs cannot continue from the main clone.`

Evaluated and intentionally not modified:

- `REVIEW.md` - existing checklist coverage is sufficient.
- `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`
  - this feature does not change plan-writing requirements.
- `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`
  - this feature targets item/epic checkpoint-resume orchestration, not the
    developer implementation protocol.
- `.claude/agents/developer.md`, `.cursor/agents/developer.md`,
  `.claude/agents/tech-lead.md`, and `.cursor/agents/tech-lead.md` - the live
  search found them as existing cross-cutting checklist consumers, but the new
  requirement belongs to item/epic orchestration surfaces.
- `.codex/skills/workflow-plan-writer/SKILL.md` and
  `.codex/skills/workflow-implementer/SKILL.md` - same rationale as above.
- `.codex/skills/workflow-orchestrator/SKILL.md`,
  `.agents/skills/run-items/SKILL.md`, `.claude/commands/run-items.md`, and
  `.cursor/commands/run-items.md` - portfolio and bounded-batch surfaces
  dispatch item runners but do not own checkpoint-resume execution directly.

---

## Concurrency Safety

This plan is not a concurrent-event-source plan under Protocol 02. It does not
add event listeners, socket callbacks, timers, async queues, or shared mutable
state across execution contexts.

- **Shared mutable state guards**: Not applicable - helper state is local to
  one shell process.
- **Re-entrancy / in-flight tracking**: Not applicable - each invocation emits a
  continue, re-entry, or stop decision and exits.
- **Event deduplication**: Not applicable - there is no event stream.
- **Listener and resource cleanup**: Not applicable - no listeners, timers, or
  handles are registered.
- **Race conditions at initialization**: Not applicable - the helper reads live
  git state at invocation time and fails closed when the state is insufficient.
- **Race conditions at teardown**: Not applicable - no teardown sequence is
  introduced.
- **Error propagation across async boundaries**: Not applicable - shell command
  failures become non-zero exits and structured stop output.

---

## Testing Strategy

**Test types**: Unit, smoke, manual documentation inspection.

**Key scenarios to test**:

1. A checkpointed `/run-item` resume that begins from the main clone re-enters
   the single registered expected worktree before mutation. Maps to AC1, AC3,
   AC6, AC9, and AC10.
2. A checkpointed `/run-epic` resume follows the same preflight and recovery
   wording. Maps to AC2, AC4, AC5, AC8, and AC9.
3. Missing, ambiguous, detached, or mismatched worktree state stops before
   mutation with clear recovery output. Maps to AC4 and AC6.
4. The existing initial-entry guard remains documented and tested separately
   from the new resume-side preflight. Maps to AC7.
5. Command and skill mirrors describe the same resume-side requirement. Maps to
   AC8.

**Smoke test runbook**:
`docs/testing/workflow/1174-worktree-cwd-restore-sendmessage.smoke-test.md`

**Regression suite**:

- [ ] Add `scripts/development-workflow/tests/test-worktree-resume-preflight.sh`
      and run it in the implementation PR.
- [ ] Run `bash scripts/development-workflow/tests/test-run-item-scope-resolver.sh`
      and `bash scripts/development-workflow/tests/test-run-epic-scope-resolver.sh`
      to confirm the adjacent resolver paths still pass.
- [ ] Run `bash scripts/development-workflow/tests/test-run-epic-checkpoint-lifecycle.sh`
      because checkpoint satisfaction must remain independent of worktree
      re-entry.
- [ ] Run `bash scripts/development-workflow/tests/test-run-bounded-prelude.sh`
      because checkpoint policy handoff text is part of the resumed run context.
- [ ] Run `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`
      for workflow shell changes.
- [ ] Run `npx markdownlint-cli2` on all touched markdown surfaces, the spec,
      the plan, the runbook, and `CHANGELOG.md`.

---

## Seed Data

No persistent seed data is required.

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Git fixture repo | Main clone on `develop`, isolated worktree on `implementation-plan/1174-worktree-cwd-restore-sendmessage` | Created inside the shell test temp directory |
| Ambiguous worktree fixtures | Multiple parsed porcelain entries that appear to match the expected branch or path | Created inside the shell test temp directory |
| Detached worktree fixture | Worktree entry without a trusted branch line | Created inside the shell test temp directory |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      - document checkpoint-resume worktree preflight for `/run-item`.
- [ ] `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`
      - document checkpoint-resume worktree preflight for `/run-epic`.
- [ ] `.agents/skills/run-item/SKILL.md`,
      `.agents/skills/run-item/agents/openai.yaml`,
      `.agents/skills/run-item-work/SKILL.md`, and
      `.agents/skills/run-item-work/agents/openai.yaml` - mirror the run-item
      requirement.
- [ ] `.agents/skills/run-epic/SKILL.md` and
      `.agents/skills/run-epic/agents/openai.yaml` - mirror the run-epic
      requirement.
- [ ] `.codex/skills/workflow-item-orchestrator/SKILL.md` and
      `.codex/skills/workflow-item-orchestrator/agents/openai.yaml` - mirror the
      item-orchestrator requirement.
- [ ] `.claude/commands/run-item.md`, `.claude/commands/run-item-work.md`,
      `.claude/commands/run-epic.md`, `.cursor/commands/run-item.md`,
      `.cursor/commands/run-item-work.md`, and `.cursor/commands/run-epic.md`
      - keep command surfaces aligned.
- [ ] `docs/testing/workflow/1174-worktree-cwd-restore-sendmessage.smoke-test.md`
      - update after implementation if helper names or exact commands change.
- [ ] `CHANGELOG.md` - add an `[Unreleased]` implementation entry. Do not edit
      `CHANGELOG.md` in this plan PR.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Worktree porcelain parsing mishandles paths with spaces or missing branch lines | Medium | High | Use delimiter-aware parsing in one helper and cover whitespace, detached, incomplete, and corrupt entries in shell tests |
| The helper accidentally mutates git state while trying to recover | Low | High | Keep the helper read-only; it emits a re-entry directive or requires the caller to `cd`, but does not run `git switch`, `git checkout`, `git reset`, or `git restore` |
| Run-item and run-epic surfaces drift | Medium | Medium | Update the canonical protocols first, then mirror concise references in all listed command and skill surfaces |
| Re-entry is mistaken for checkpoint satisfaction | Low | High | Protocol text must explicitly state that re-entry does not satisfy, waive, or remove checkpoint requirements, and checkpoint lifecycle tests must still pass |
| The main clone is already on another branch during resume | Medium | High | The preflight must inspect observed CWD and branch, log them, and fail closed or re-enter only when exactly one expected worktree is proven |

---

## Code Samples

No production code samples are included. The implementation should keep detailed
shell logic in `scripts/development-workflow/worktree-resume-preflight.sh` and
cover it with shell tests.

---

## Implementation Order

1. Add `scripts/development-workflow/worktree-resume-preflight.sh` as a
   read-only helper with `set -euo pipefail`, argument validation, structured
   text output, and optional `--json`.
2. Add `scripts/development-workflow/tests/test-worktree-resume-preflight.sh`
   with the parser-risk unit tests listed above.
3. Run the new shell test and fix parser or path-boundary failures before
   changing documentation.
4. Update Protocol 91 with the run-item checkpoint-resume worktree preflight,
   including safe re-entry, fail-closed output, and checkpoint independence.
5. Update Protocol 95 with the same run-epic checkpoint-resume requirement.
6. Update the run-item, run-item-work, run-epic, and item-orchestrator command
   and skill surfaces listed in **Cross-Cutting Surface Enumeration**.
7. Update this smoke-test runbook if command names or expected output fields
   differ from the plan.
8. Add the implementation `CHANGELOG.md` entry under `[Unreleased]` using:
   `- **Restore worktree CWD on checkpoint resume** (#1174): Add a resume preflight so checkpointed worktree-isolated runs cannot continue from the main clone.`
9. Run:
   `bash scripts/development-workflow/tests/test-worktree-resume-preflight.sh`.
10. Run adjacent regressions:
    `bash scripts/development-workflow/tests/test-run-item-scope-resolver.sh`,
    `bash scripts/development-workflow/tests/test-run-epic-scope-resolver.sh`,
    `bash scripts/development-workflow/tests/test-run-epic-checkpoint-lifecycle.sh`,
    and `bash scripts/development-workflow/tests/test-run-bounded-prelude.sh`.
11. Run:
    `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`.
12. Run `npx markdownlint-cli2` against all changed markdown files, the spec,
    the plan, the runbook, and `CHANGELOG.md`.
13. Complete the smoke runbook and record the main-clone branch check showing
    the shared checkout remains on `develop` after the resume attempt.
