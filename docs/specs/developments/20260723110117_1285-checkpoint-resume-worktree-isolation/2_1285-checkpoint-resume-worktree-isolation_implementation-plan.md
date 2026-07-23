# Checkpoint Resume Worktree Isolation - Implementation Plan

**Spec**:
[1_1285-checkpoint-resume-worktree-isolation_specs.md](1_1285-checkpoint-resume-worktree-isolation_specs.md)
**Smoke test runbook**:
[1285-checkpoint-resume-worktree-isolation.smoke-test.md](../../../testing/workflow/1285-checkpoint-resume-worktree-isolation.smoke-test.md)

---

## Summary

**Approach**: Replace the current advisory main-clone re-entry outcome with an
executable, fail-closed checkpoint-resume gate. The gate will require the full
isolation assignment and checkpoint state, delegate read-only worktree
validation to the existing preflight helper, and expose one consistent decision
contract across item, epic, and bounded-batch resume handoffs.

**Estimated complexity**: M

**Rationale**: The core shell behavior is bounded, but correctness depends on a
multi-input decision gate, parser-safe registered-worktree validation,
integration coverage of the real gate invocation, and consistent updates
across three orchestration paths and their mirrored command and skill surfaces.

**Dependencies**: Issue #1174 is closed and has tracker status `Released`.

**Template-fit check**: Passed. `.ai-dev-workflow.yaml` sets
`template.is_template: true`, and this item hardens generic workflow tooling
that the template ships to all downstream repositories.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse HEAD` | `21f23e3bbd3edc537381901bd08c9c4b11e28609` |
| Repository mode | `sed -n '1,220p' .ai-dev-workflow.yaml` | `template.is_template: true`; mode is omitted, so the repository is `single_repo` and owns the plan |
| Tracker status | `gh issue view 1285 --json number,title,projectItems,state` | Issue #1285 is open and has status `Writing Plan` |
| Dependency status | `gh issue view 1174 --json number,state,projectItems` | Issue #1174 is closed and has status `Released` |
| Merged spec gate | `gh pr list --state merged --search 'head:spec/1285-checkpoint-resume-worktree-isolation' --json number,state,baseRefName,mergedAt` | Spec PR #1315 is merged to `develop` |
| Existing executable isolation scope | `rg -n -l "worktree-resume-preflight\|checkpoint.resume preflight" scripts/development-workflow --glob '*.sh'` | Existing implementation is `worktree-resume-preflight.sh` plus its unit test; no combined checkpoint/isolation entry gate exists |
| Unsafe re-entry behavior | `rg -n "RESULT=reenter\|result=\"reenter\"\|re-enter expected worktree" scripts/development-workflow/worktree-resume-preflight.sh docs/workflow/development-workflow/protocols/{91-orchestrate-work-protocol,95-run-epic-protocol}.md` | The helper and Protocols 91/95 currently allow a resumed main-clone session to re-enter an item worktree |
| Canonical orchestration surfaces | `rg -n -l "checkpoint-resume\|redispatch / resume" docs/workflow/development-workflow/protocols/{90-batch-orchestrate-work-protocol,91-orchestrate-work-protocol,95-run-epic-protocol}.md` | Protocols 90, 91, and 95 own bounded-batch, item, and epic resume behavior |
| Item and epic mirrors | `rg -n -l "checkpoint[- ]resume\|Checkpoint[- ]resume\|worktree[- ]resume preflight" .agents/skills/run-item .agents/skills/run-item-work .agents/skills/run-epic .codex/skills/workflow-item-orchestrator .claude/agents/item-orchestrator.md .cursor/agents/item-orchestrator.md .claude/commands/run-item.md .claude/commands/run-item-work.md .claude/commands/run-epic.md .cursor/commands/run-item.md .cursor/commands/run-item-work.md .cursor/commands/run-epic.md` | Sixteen item/epic skill, agent, command, and metadata files expose or inherit the current resume contract |
| Bounded-batch mirrors | `for f in .agents/skills/run-items/SKILL.md .agents/skills/run-items/agents/openai.yaml .codex/skills/workflow-orchestrator/SKILL.md .codex/skills/workflow-orchestrator/agents/openai.yaml .claude/commands/run-items.md .cursor/commands/run-items.md; do test -f "$f" && printf '%s\n' "$f"; done` | Six bounded-batch surfaces dispatch or supervise worktree-isolated item runners |
| Design assets | `find docs/specs/developments/20260723110117_1285-checkpoint-resume-worktree-isolation -maxdepth 2 -type f` plus issue-body inspection | Only the approved spec exists; the issue has no `## Design assets` section or UI scope, so no fidelity step applies |

---

## Layer-by-Layer Changes

### Checkpoint Resume Gate

- [ ] Add `scripts/development-workflow/checkpoint-resume-gate.sh` as the
      executable entry gate used by every actual checkpoint-resume handoff.
      Require explicit `--item`, `--expected-worktree`, `--expected-branch`,
      `--main-repo-root`, and
      `--checkpoint-state <pending|satisfied|waived>` values; do not infer
      missing isolation context.
- [ ] Keep isolation verification and checkpoint lifecycle separate inside the
      gate. Invoke the read-only worktree preflight first, record
      `ISOLATION_RESULT`, then evaluate the supplied checkpoint state without
      modifying, satisfying, or waiving it.
- [ ] Emit a stable decision record with
      `RESULT=<continue|checkpoint_pending|stop>`,
      `ISOLATION_RESULT=<pass|stop>`, `CHECKPOINT_STATE`,
      `STOP_CONDITION`, item, expected and observed worktree/branch context,
      reason, and human recovery action. Use
      `STOP_CONDITION=checkpoint_pending` for valid isolation with a pending
      decision and `STOP_CONDITION=unclear_requirements` for incomplete or
      contradictory isolation context. Permit `RESULT=continue` only when
      isolation passes and checkpoint state is `satisfied` or `waived`.
- [ ] Reject every repeated required option, including repetitions with the
      same value, so contradictory handoff context cannot be silently resolved
      by argument order.
- [ ] Make the gate read-only: it must not edit files, change CWD, switch or
      create branches/worktrees, commit, push, write tracker or PR state,
      change labels/comments/reviews, or merge.

### Worktree Preflight Helper

- [ ] Update
      `scripts/development-workflow/worktree-resume-preflight.sh` so explicit
      expected worktree and main-repository root are required for checkpoint
      resume. Missing metadata must yield a structured fail-closed result
      instead of a default or inferred safe context.
- [ ] Remove the `reenter`/`cd` outcome. A current directory equal to or below
      the main clone, outside the expected worktree, or inside a sibling
      worktree must return `RESULT=stop`,
      `STOP_CONDITION=unclear_requirements`, the failed comparison, and
      fresh-runner recovery guidance.
- [ ] Continue only when the current directory is the expected worktree or a
      descendant, the active branch matches exactly, and
      `git worktree list --porcelain` proves one unique, non-detached,
      path-and-branch-consistent registration.
- [ ] Preserve the helper as a read-only isolation primitive so direct tests
      can distinguish worktree validation from the combined checkpoint gate.

### Regression Tests

- [ ] Extend
      `scripts/development-workflow/tests/test-worktree-resume-preflight.sh`
      for required metadata, fail-closed main-clone behavior, wrong and
      lookalike paths/branches, detached or ambiguous registrations, and
      structured `unclear_requirements` evidence.
- [ ] Add
      `scripts/development-workflow/tests/test-checkpoint-resume-gate.sh`.
      Exercise the exact gate command used by orchestration handoffs with
      temporary repositories and worktrees, rather than testing only the
      isolation helper.
- [ ] In the integration test, snapshot the main clone's branch, `HEAD`,
      status, and file markers before a main-clone resume; invoke the gate;
      prove it returns stop and leaves every snapshot unchanged before any
      simulated mutation callback can run.
- [ ] Add missing-metadata, wrong-branch, unexpected-directory, ambiguous
      registration, pending-checkpoint, satisfied/waived checkpoint, and
      concurrent sibling-worktree scenarios. The concurrent scenario must show
      the stopped resume leaves both the main clone and sibling worktree
      untouched.
- [ ] Add surface-contract assertions showing Protocols 90, 91, and 95 invoke
      the executable gate with all required isolation fields and checkpoint
      state, so a standalone helper test cannot pass while the real resume path
      omits the gate.

### Canonical Workflow Protocols

- [ ] Update
      `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      to run `checkpoint-resume-gate.sh` as the first resumed-session action,
      before stage-agent handoff or any repository, tracker, or PR mutation.
- [ ] Update
      `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`
      so epic child resumes pass the same complete context and checkpoint
      lifecycle state into the same gate.
- [ ] Update
      `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      so bounded-batch redispatch and checkpoint continuation use a fresh,
      fully isolated runner with the approved checkpoint decision front-loaded.
      Do not resume a previously paused runner while a sibling is active.
- [ ] Use one decision matrix and one recovery vocabulary across the three
      protocols. Isolation failures use `unclear_requirements`; a valid
      worktree with a pending checkpoint uses `checkpoint_pending` and remains
      a human-decision stop.
- [ ] Require the parent orchestrator to surface each child gate disposition
      explicitly. A silent child exit must not be treated as successful
      continuation.

### Command, Skill, and Agent Surfaces

- [ ] Mirror the fail-closed item contract in
      `.agents/skills/run-item/SKILL.md`,
      `.agents/skills/run-item/agents/openai.yaml`,
      `.agents/skills/run-item-work/SKILL.md`,
      `.agents/skills/run-item-work/agents/openai.yaml`,
      `.codex/skills/workflow-item-orchestrator/SKILL.md`,
      `.codex/skills/workflow-item-orchestrator/agents/openai.yaml`,
      `.claude/agents/item-orchestrator.md`,
      `.cursor/agents/item-orchestrator.md`,
      `.claude/commands/run-item.md`,
      `.claude/commands/run-item-work.md`,
      `.cursor/commands/run-item.md`, and
      `.cursor/commands/run-item-work.md`.
- [ ] Mirror the same epic-child contract in
      `.agents/skills/run-epic/SKILL.md`,
      `.agents/skills/run-epic/agents/openai.yaml`,
      `.claude/commands/run-epic.md`, and
      `.cursor/commands/run-epic.md`.
- [ ] Mirror fresh-dispatch and full-context requirements for portfolio batches
      in `.agents/skills/run-items/SKILL.md`,
      `.agents/skills/run-items/agents/openai.yaml`,
      `.codex/skills/workflow-orchestrator/SKILL.md`,
      `.codex/skills/workflow-orchestrator/agents/openai.yaml`,
      `.claude/commands/run-items.md`, and
      `.cursor/commands/run-items.md`.
- [ ] Ensure every mirror says that isolation verification neither satisfies
      nor waives checkpoint state and that a main-clone resume stops instead of
      changing directories.

### Documentation and Release Notes

- [ ] Update `docs/workflow/development-workflow/README.md` with operator
      guidance to front-load checkpoint decisions, prefer fresh isolated
      dispatch when context cannot be reconstructed, and avoid resuming a
      paused runner while sibling runners remain active.
- [ ] Update `CHANGELOG.md` under `[Unreleased]` in the implementation PR with:
      `- **Fail closed on checkpoint resume isolation** (#1285): Require complete worktree context and stop resumed isolated runners before mutation when the session starts in the main clone or cannot prove its assignment.`
- [ ] Do not change `REVIEW.md`. Its current plan and code review checklists
      already require guardrail preservation, workflow decision matrices,
      parser edge-case coverage, regression tests, and mirrored-surface
      completeness; this item does not add a new review category.

### Database / Data Layer

- [ ] Not applicable. There is no schema, migration, seed, or persistent data
      change.

### Backend / API

- [ ] Not applicable. There is no network API or service endpoint.

### Frontend / UI

- [ ] Not applicable. There is no UI or design-asset surface.

### Infrastructure / Configuration

- [ ] Not applicable. No deployment, secret, environment, dependency, or CI
      configuration changes are required.

---

## Checkpoint Resume Decision Matrix

This item modifies a complex workflow decision gate, so implementation must
preserve the following canonical inputs and outcomes across Protocols 90, 91,
and 95 and every mirrored command/skill surface.

| Gate inputs | Allowed result | Required next action | Mirror surfaces | Example |
| --- | --- | --- | --- | --- |
| Complete context; CWD, branch, and unique registration match; checkpoint `satisfied` or `waived` | `continue` | Resume from the current worktree without changing CWD | Item, epic child, bounded batch, gate integration tests | Fresh runner starts inside its assigned worktree with approval front-loaded |
| Complete context; isolation matches; checkpoint `pending` | `checkpoint_pending` with `STOP_CONDITION=checkpoint_pending` | Stop for the human decision and preserve isolation state | All checkpoint-bearing resume surfaces | Worktree is valid but product approval is absent |
| CWD is the main clone or a descendant | `stop` with `unclear_requirements` | Start a fresh runner with full context and approved checkpoint decision | Session initialization, item, epic, batch, recovery docs, tests | Continuation session starts at process root |
| Required item, worktree, branch, main root, or checkpoint state is missing | `stop` with `unclear_requirements` | Correct the handoff or start a fresh runner; infer nothing | All dispatch/handoff surfaces and tests | Expected worktree path was lost across the pause |
| CWD is outside the expected worktree | `stop` with `unclear_requirements` | Inspect the observed location and start a safe fresh dispatch | All resume surfaces and tests | Session starts in a sibling worktree |
| Active branch differs from the expected branch | `stop` with `unclear_requirements` | Inspect branch ownership; do not switch automatically | All resume surfaces and tests | Expected path is checked out on another item branch |
| Registration is missing, detached, duplicated, or path/branch inconsistent | `stop` with `unclear_requirements` | Repair state outside the stopped session, then use a fresh runner | Worktree discovery, all resume surfaces, recovery docs, tests | Two registrations appear to claim the item branch |

**Behavioral enforcement**:

- `checkpoint-resume-gate.sh` requires every matrix input and is the only
  documented continuation entry command.
- `worktree-resume-preflight.sh` performs the unique registered-worktree,
  current-directory, and branch comparisons without mutating state.
- The gate invokes the preflight exactly once per resume attempt and derives
  its isolation decision from that single output record; callers must invoke a
  new gate immediately before every later resume attempt instead of caching or
  reusing an earlier pass.
- The gate returns success only for `continue`; callers therefore cannot reach
  their mutation callback for `checkpoint_pending` or `stop`.
- Recovery text never instructs the stopped process to `cd`, switch, recreate,
  reset, restore, stash, clean, or commit.

---

## Parser-Risk Addendum

This plan is parser-risk because the worktree preflight parses structured
`git worktree list --porcelain` records.

### Edge-Case Enumeration

1. **Boundary paths**: exact expected worktree, descendant directory, main
   clone root, main-clone descendant, sibling worktree, and same-prefix sibling
   path.
2. **Negative branch lookalikes**: an issue-number prefix such as `12850`, a
   different branch type, or a branch suffix that only contains the expected
   name must not match.
3. **Multiple records**: two registrations that claim the expected branch or
   path must be ambiguous and stop.
4. **Path and branch disagreement**: the expected path registered on a
   different branch and the expected branch registered at a different path
   must both stop.
5. **Detached or incomplete records**: `detached`, missing `branch`, missing
   `worktree`, and failed `git worktree list` data must stop.
6. **Whitespace and metacharacters**: registered paths with spaces must remain
   intact and be compared canonically without word splitting.
7. **Missing required gate fields**: each required option omitted or empty must
   produce structured `unclear_requirements` evidence.
8. **Checkpoint-state variants**: `pending`, `satisfied`, and `waived` are
   recognized; unknown or empty values stop and never become implicit approval.
9. **Repeated or conflicting options**: every repeated required option is
   rejected, including repetitions with the same value; silent contradictory
   context is forbidden.
10. **Main-clone negative case**: even one valid matching worktree must not
    convert a main-clone CWD into a re-entry/continue result.

### Unit and Integration Test Mapping

| Edge case | Automated coverage |
| --- | --- |
| 1 | `test-worktree-resume-preflight.sh`: exact, descendant, main, main-descendant, sibling, and same-prefix path cases |
| 2 | `test-worktree-resume-preflight.sh`: exact expected branch versus issue and branch-type lookalikes |
| 3 | `test-worktree-resume-preflight.sh`: ambiguous duplicate registration fixture |
| 4 | `test-worktree-resume-preflight.sh`: expected-path/wrong-branch and expected-branch/wrong-path fixtures |
| 5 | `test-worktree-resume-preflight.sh`: detached, incomplete, missing, and list-failure fixtures |
| 6 | `test-worktree-resume-preflight.sh`: worktree path containing spaces |
| 7 | `test-checkpoint-resume-gate.sh`: one case per required handoff field |
| 8 | `test-checkpoint-resume-gate.sh`: pending, satisfied, waived, and invalid state cases |
| 9 | `test-checkpoint-resume-gate.sh`: repeated/conflicting argument behavior selected during implementation |
| 10 | Both test files: main-clone invocation stops and preserves repository snapshots |

### Suppression Semantics

Not applicable. The gate and helper do not define inline suppression
directives.

---

## Testing Strategy

**Test types**: Shell unit, shell integration, protocol-surface regression,
smoke, ShellCheck, workflow-shell guard, and Markdown lint.

**Key scenarios to test**:

1. A fully specified resume from the assigned worktree with a satisfied or
   waived checkpoint returns `continue` (AC1, AC2, AC3, AC7).
2. A valid worktree with a pending checkpoint returns `checkpoint_pending`
   without altering lifecycle state (AC7).
3. A main-clone, main-descendant, sibling-directory, wrong-branch, missing,
   detached, or ambiguous resume returns `unclear_requirements` before a
   simulated mutation callback (AC4, AC5, AC6, AC9, AC10).
4. Item, epic, and bounded-batch entry surfaces pass the same required context,
   invoke the same gate, and expose the same outcomes (AC1, AC2, AC8).
5. Recovery output prefers a fresh, pre-approved runner and never directs the
   stopped process to repair or re-enter worktree state (AC4, AC6, AC11, AC13).
6. A concurrent fixture proves the stopped resume leaves the shared main clone
   and sibling worktree unchanged (AC12, AC13).

**Smoke test runbook**:
`docs/testing/workflow/1285-checkpoint-resume-worktree-isolation.smoke-test.md`

**Regression suite**:

- `scripts/development-workflow/tests/test-worktree-resume-preflight.sh`
- `scripts/development-workflow/tests/test-checkpoint-resume-gate.sh`
- `scripts/development-workflow/tests/test-run-epic-checkpoint-lifecycle.sh`
- `scripts/development-workflow/tests/test-run-bounded-prelude.sh`
- `scripts/development-workflow/tests/test-run-item-scope-resolver.sh`
- `scripts/development-workflow/tests/test-run-epic-scope-resolver.sh`

**Residual verification strategy**: Before implementation readiness, run a
live repository search for the old `RESULT=reenter`, automatic `cd`, and
advisory-only resume wording. The evidence source is the zero-residual search
output plus the surface-contract assertions in
`test-checkpoint-resume-gate.sh`. Any intentional historical occurrence must
be listed with an out-of-scope rationale rather than silently ignored.

---

## Seed Data

No persistent seed data is required. Tests create deterministic temporary git
repositories and registered worktrees.

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Main clone fixture | `develop` checkout with branch, `HEAD`, status, and marker snapshots | `scripts/development-workflow/tests/test-checkpoint-resume-gate.sh` |
| Assigned worktree fixture | Expected issue branch registered at a unique path | Both worktree-resume test files |
| Invalid registration fixtures | Missing, detached, wrong-branch, wrong-path, and ambiguous entries | `scripts/development-workflow/tests/test-worktree-resume-preflight.sh` |
| Concurrent sibling fixture | A second worktree with an unchanged marker and branch while the resumed item stops | `scripts/development-workflow/tests/test-checkpoint-resume-gate.sh` |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/README.md` - document fail-closed
      checkpoint-resume operation and fresh-runner/front-loaded approval
      guidance.
- [ ] Protocols 90, 91, and 95 - update the canonical handoff, decision
      matrix, stop evidence, and recovery behavior described above.
- [ ] Command, agent, skill, and `agents/openai.yaml` surfaces listed under
      **Command, Skill, and Agent Surfaces** - mirror the canonical contract.
- [ ] `CHANGELOG.md` - add the exact `[Unreleased]` entry listed above.
- [ ] `AGENTS.md` does not require an update because it delegates detailed
      orchestration behavior to the canonical workflow protocols and commands.
- [ ] `docs/project/` and `docs/best-practices/` do not require updates because
      this feature changes workflow runtime safety, not project architecture,
      data, testing policy, or general coding conventions.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| A mirrored surface omits a required gate input | Medium | High | Enumerate every live item, epic, and batch surface; add surface-contract tests and a zero-residual search |
| Checkpoint and isolation state become conflated | Medium | High | Keep separate output fields; accept checkpoint state as read-only input; test pending versus satisfied/waived |
| Shell parsing accepts an ambiguous worktree | Low | High | Require exact canonical path plus branch, reject multiple/incomplete records, and cover parser edge cases |
| Main-clone stop still allows a later caller mutation | Low | High | Make the executable gate return non-zero for all non-continue outcomes and test a guarded mutation callback |
| New strict metadata requirements break safe callers silently | Medium | Medium | Update every caller surface in the same implementation, emit explicit failed-field evidence, and run adjacent orchestration regressions |
| Concurrent sibling state changes during the regression | Low | High | Use isolated temporary fixtures and snapshot both main and sibling worktree state before/after the gate |

---

## Implementation Order

1. Harden `worktree-resume-preflight.sh` by requiring explicit isolation
   metadata, removing `reenter`, emitting `unclear_requirements`, and accepting
   only exact current-worktree proof. Extend the existing unit tests for every
   parser-risk edge case. Maps to AC2, AC3, AC4, AC5, AC6, and AC10.
2. Add `checkpoint-resume-gate.sh` with the required context contract,
   separated isolation/checkpoint fields, decision matrix outputs,
   single-preflight invocation rule, repeated-option rejection, and
   success-only-on-continue exit semantics. Add its integration test in the
   same coherent step. Maps to AC1, AC2, AC3, AC4, AC5, AC7, AC9, and AC10.
3. Update Protocol 91 to invoke the executable gate before any resumed-session
   mutation and to use the canonical decision matrix and recovery output. Maps
   to AC1 through AC11.
4. Update Protocol 95 and its item/epic mirrored surfaces so epic child resumes
   pass the same complete context, checkpoint state, outcomes, and evidence.
   Maps to AC1, AC2, AC7, AC8, and AC11.
5. Update Protocol 90 and all bounded-batch surfaces to front-load approvals,
   use fresh fully isolated dispatch after pauses, surface child dispositions,
   and avoid resuming a paused runner while siblings remain active. Add the
   concurrent integration scenario. Maps to AC8, AC11, AC12, and AC13.
6. Update `docs/workflow/development-workflow/README.md` and every remaining
   item/epic command, agent, skill, and metadata mirror. Run the residual search
   and confirm only explicitly justified historical references remain. Maps to
   AC6, AC8, AC11, and AC13.
7. Run the focused shell tests, adjacent checkpoint/bounded-orchestration
   regressions, ShellCheck on changed shell files, and
   `workflow-shell-guard-lint.py --base-ref origin/develop`. Confirm the output
   proves the real gate blocks simulated mutation and preserves main/sibling
   snapshots. Maps to AC2, AC9, AC10, and AC12.
8. Execute the smoke runbook and update its assertions with implementation
   evidence.
9. Update the project documentation listed under **Documentation Updates**.
10. Add under `CHANGELOG.md` `[Unreleased]`:
    `- **Fail closed on checkpoint resume isolation** (#1285): Require complete worktree context and stop resumed isolated runners before mutation when the session starts in the main clone or cannot prove its assignment.`
