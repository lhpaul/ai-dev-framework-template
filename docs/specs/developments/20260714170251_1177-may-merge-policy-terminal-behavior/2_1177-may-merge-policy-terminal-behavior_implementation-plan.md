# May-Merge Policy Terminal Behavior — Implementation Plan

**Spec**: [1_1177-may-merge-policy-terminal-behavior_specs.md](1_1177-may-merge-policy-terminal-behavior_specs.md)
**Smoke test runbook**: [1177-may-merge-policy-terminal-behavior.smoke-test.md](../../../testing/workflow/1177-may-merge-policy-terminal-behavior.smoke-test.md)

---

## Summary

**Approach**: Make the selected merge authority explicit at the shared guardrails
handoff, then propagate the same granted-versus-denied terminal contract through
the item, batch, and epic protocols plus their supported command, agent, and
skill surfaces. Implementation should reuse the existing run-epic risk,
delegated-gate, audit, batch-merge, cleanup, and tracker helpers; it must not
introduce a second policy engine.

**Estimated complexity**: M

**Rationale**: The behavior is conceptually small, but the contract is
cross-surface workflow behavior. The implementation must update several
canonical and mirrored instruction files and add regression coverage for
terminal-state wording and delegated merge gates.

**Dependencies**: None.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `38829f7` |
| Tracker state | `gh issue view 1177 --json number,title,state,labels,projectItems,url --jq '{number,title,state,url,labels:[.labels[].name], projectItems:[.projectItems[] \| {status:.status.name,title:.title}]}'` | Issue `#1177` is open and on project `AI Development Framework` with status `Writing Plan`. |
| Stage isolation | `pwd -P`; `git rev-parse --abbrev-ref HEAD`; supplied batch metadata | Worktree path is `.codex-worktrees/run-items-20260716/1177-plan`, branch is `implementation-plan/1177-may-merge-policy-terminal-behavior`, approved base is `develop`, isolation is `worktree`, mutation classification is `mutating`. |
| Existing merge-policy surfaces | `rg -l "run-epic-delegated-gate\|may_merge_pr\|--may-merge\|delegated merge\|ready-for-human-review" docs/workflow/development-workflow/protocols/9*.md docs/workflow/development-workflow/guardrails-enforcement.md .claude/commands/run-{item,items,epic}.md .cursor/commands/run-{item,items,epic}.md .agents/skills/run-{item,items,epic}/SKILL.md .codex/skills/workflow-{item-orchestrator,orchestrator}/SKILL.md .claude/agents/{item-orchestrator,orchestrator}.md .cursor/agents/{item-orchestrator,orchestrator}.md scripts/development-workflow/tests/test-run-*.sh scripts/development-workflow/tests/test-batch-merge*.sh \| sort` | Relevant files include Protocols `90`, `91`, `92`, `93`, `94`, `95`, `guardrails-enforcement.md`, `/run-item`, `/run-items`, `/run-epic` command and skill surfaces, item/orchestrator agent guidance, and existing run-epic/batch test files. |
| Cross-cutting stage guidance search | `grep -rl "02-generate-implementation-plan-protocol\|03-implement-development-protocol" .claude/agents/ .cursor/agents/ .codex/skills/ \| sort` | Planning/implementation guidance references are `.claude/agents/developer.md`, `.claude/agents/tech-lead.md`, `.cursor/agents/developer.md`, `.cursor/agents/tech-lead.md`, `.codex/skills/workflow-implementer/SKILL.md`, and `.codex/skills/workflow-plan-writer/SKILL.md`. |
| Test surface inventory | `find scripts/development-workflow/tests -maxdepth 1 -type f -name "*.sh" \| sort` | Existing shell tests are standalone files; there is no single committed `run-all.sh`. New coverage can be added as focused `test-*.sh` scripts and run directly. |

---

## Layer-by-Layer Changes

### Workflow Protocols And Guardrails Documentation

- [ ] Update `docs/workflow/development-workflow/guardrails-enforcement.md` to
      define the merge-authority terminal-state contract in Gate 5 and Gate 6:
      `merge_granted` means readiness is intermediate, `merge_denied` means
      readiness is the human handoff, and all stops must name the blocker and
      required human action. This covers AC1-AC5 and AC10.
- [ ] Update `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      so Work Item Runner Step 8a/8b/8c explicitly branches after readiness:
      if the effective stage policy grants merge authority, continue into the
      delegated merge gate and approved merge path; otherwise report
      `ready_human_merge` and stop without merging. This covers AC1-AC5 and AC10.
- [ ] Update `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      so explicit-list supervision distinguishes `merged`,
      `ready_human_merge`, `merge_blocked`, `policy_inconsistent`, and
      `out_of_scope` per in-scope PR. This covers AC6-AC8 and AC10.
- [ ] Update `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`
      so epic delegated-review and delegated-merge steps use the same terminal
      outcome names and identify any stalled-at-ready in-scope PR during a
      merge-authorized run as `policy_inconsistent` unless a named merge gate
      blocker exists. This covers AC6-AC8 and AC10.
- [ ] Update `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md`
      to clarify that `ready-for-human-review` is an automation-clean readiness
      label, not necessarily the terminal state when merge authority is granted.
      This covers AC1, AC2, and AC5.
- [ ] Update `docs/workflow/development-workflow/guardrails.md` only if the
      current plain-language examples still imply that readiness is always
      terminal. Keep the schema unchanged. This covers AC1, AC2, and AC9.
- [ ] Update `docs/workflow/development-workflow/README.md` only if the command
      summary needs the same granted-versus-denied handoff wording for
      `/run-item`, `/run-items`, or `/run-epic`. This covers AC9.

### Command, Agent, And Skill Surfaces

- [ ] Update the command aliases for `/run-item`, `/run-items`, and `/run-epic`:
      `.claude/commands/run-item.md`, `.claude/commands/run-items.md`,
      `.claude/commands/run-epic.md`, `.cursor/commands/run-item.md`,
      `.cursor/commands/run-items.md`, and `.cursor/commands/run-epic.md`.
      The wording must state both branches of the condition: merge-granted
      runs continue through merge and cleanup; merge-denied runs stop at
      `ready_human_merge` without merge. This covers AC1, AC2, AC6, and AC9.
- [ ] Update repo command-style Codex skills:
      `.agents/skills/run-item/SKILL.md`, `.agents/skills/run-items/SKILL.md`,
      `.agents/skills/run-epic/SKILL.md`, and their
      `agents/openai.yaml` prompts where the current prompt mentions delegated
      merge or terminal behavior. This covers AC1, AC2, AC6, and AC9.
- [ ] Update legacy canonical Codex workflow skills:
      `.codex/skills/workflow-item-orchestrator/SKILL.md`,
      `.codex/skills/workflow-item-orchestrator/agents/openai.yaml`,
      `.codex/skills/workflow-orchestrator/SKILL.md`, and
      `.codex/skills/workflow-orchestrator/agents/openai.yaml`. This covers
      AC1, AC2, AC6, and AC9.
- [ ] Update mirrored agent guidance:
      `.claude/agents/item-orchestrator.md`, `.claude/agents/orchestrator.md`,
      `.cursor/agents/item-orchestrator.md`, and
      `.cursor/agents/orchestrator.md`. Keep mirrors semantically aligned and
      avoid tool-specific policy differences. This covers AC6, AC9, and AC10.
- [ ] Leave tech-lead/developer plan-generation guidance unchanged unless the
      implementation discovers a direct contradiction in the live files from
      the cross-cutting stage guidance search. The planned behavior concerns
      orchestration terminal states, not plan-writing or implementation-stage
      checklists.

### Shell Helpers And Tests

- [ ] Prefer documentation/protocol updates first. Modify shell helpers only if
      the implementation finds an existing helper that emits or validates a
      contradictory terminal outcome. Candidate helpers from the verification
      surface are `run-bounded-prelude.sh`,
      `run-epic-delegated-gate.sh`, `run-epic-audit-trail.sh`,
      `item-completion-self-check.sh`, and `batch-merge.sh`.
- [ ] Add focused regression tests under
      `scripts/development-workflow/tests/`. Either extend existing test files
      where behavior already belongs or add
      `scripts/development-workflow/tests/test-may-merge-terminal-contract.sh`
      for static contract checks across protocols, commands, skills, and agent
      mirrors. This covers AC1, AC2, AC6, AC9, and AC10.
- [ ] Extend `scripts/development-workflow/tests/test-run-epic-delegated-gate.sh`
      only if helper behavior changes are needed for `merge_blocked` or
      missing-authority evidence. This covers AC3-AC5.

### Database / Data Layer

- [ ] Not applicable. No database schema, migration, seed data, or persistent
      product data changes are in scope.

### Frontend / UI

- [ ] Not applicable. This feature changes workflow runner behavior and
      documentation surfaces, not application UI.

### Infrastructure / Configuration

- [ ] No schema or CI configuration change is planned. If a new shell test is
      added, keep it executable with direct `bash` invocation and avoid adding
      new CI requirements unless the repository already routes matching tests.

---

## Testing Strategy

**Test types**: Static contract tests, shell unit tests, markdown/documentation
checks, and workflow smoke-test review.

**Key scenarios to test**:

1. Merge-granted handoff says readiness labels are intermediate and merge,
   cleanup, and tracker verification must follow when gates pass. Maps to AC1
   and AC3.
2. Merge-denied handoff says the runner applies readiness labels when eligible,
   reports `ready_human_merge`, and does not execute a merge. Maps to AC2 and
   AC5.
3. Merge-granted PR that reaches readiness but fails a merge gate reports
   `merge_blocked` with the failed gate and human action. Maps to AC4.
4. Batch and epic summaries use the same terminal outcomes for every in-scope
   PR and mark unexplained stalled-at-ready outcomes as `policy_inconsistent`.
   Maps to AC6, AC7, and AC10.
5. Out-of-scope PRs discovered during a merge-authorized run are reported as
   `out_of_scope` and never sent to the merge path. Maps to AC8.
6. `/run-item`, `/run-items`, and `/run-epic` surfaces use consistent wording
   across Claude, Cursor, Codex skill, and OpenAI prompt mirrors. Maps to AC9.

**Smoke test runbook**:
`docs/testing/workflow/1177-may-merge-policy-terminal-behavior.smoke-test.md`

**Regression suite**:

- Add or update shell tests in `scripts/development-workflow/tests/` and run
  the affected tests directly. At minimum, run:
  - `bash scripts/development-workflow/tests/test-may-merge-terminal-contract.sh`
    if a new static contract test is added.
  - `bash scripts/development-workflow/tests/test-run-epic-delegated-gate.sh`
    if delegated-gate behavior is changed.
  - `bash scripts/development-workflow/tests/test-run-bounded-prelude.sh`
    if prelude policy wording or output fields are changed.

### Parser-risk addendum

Not applicable. The planned implementation does not introduce or materially
change a parser, lint scanner, tokenizer, regex engine, or suppression
semantics.

### Concurrent-event-source addendum

Not applicable. The planned implementation does not add event listeners,
timers, socket callbacks, async queues, or shared mutable state across
concurrent execution contexts.

### Cross-cutting checklist addendum

This work modifies a cross-surface orchestration terminal-state contract, but it
does not introduce or rename a cross-cutting checklist category that every
future feature plan or implementation must satisfy. The file enumeration above
still explicitly covers all affected protocols, command wrappers, agent mirrors,
and Codex skill files discovered by the live searches.

---

## Seed Data

No seed data is required.

| Entity | Values / Scenario | File |
| --- | --- | --- |
| None | Workflow terminal behavior is validated with shell fixtures and static documentation checks. | Not applicable |

---

## Documentation Updates

The implementation PR must update these project documentation files only as
needed by the final wording:

- [ ] `docs/workflow/development-workflow/guardrails-enforcement.md` — define
      merge-granted and merge-denied terminal behavior and outcome names.
- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      — align batch supervision and summary outcomes.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      — align Work Item Runner readiness, merge, cleanup, and tracker
      verification flow.
- [ ] `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` —
      align epic delegated merge and rediscovery outcomes.
- [ ] `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md`
      — clarify readiness labels are not always terminal.
- [ ] `docs/workflow/development-workflow/guardrails.md` — update examples only
      if existing text implies readiness is terminal despite merge authority.
- [ ] `docs/workflow/development-workflow/README.md` — update command summary
      only if needed for user-facing consistency.
- [ ] Command, skill, and agent guidance files listed under
      **Command, Agent, And Skill Surfaces** — align terminal behavior wording.
- [ ] `CHANGELOG.md` — update during implementation, not in this plan PR.
      Use this literal entry under `[Unreleased]`:
      `- **Clarify delegated merge terminal behavior** (#1177): Documented that merge-authorized runs continue from readiness through merge and cleanup while merge-denied runs stop at human handoff.`

`AGENTS.md` does not need an implementation update unless the command table
itself is found to contradict the canonical workflow docs after the protocol
edits.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| One surface still treats `ready-for-human-review` as terminal under merge authority. | Medium | High | Use the live surface search in the Verification Log and add static tests over protocol, command, skill, and agent files. |
| Implementation creates a parallel policy model separate from run-epic helpers. | Low | High | Keep `guardrails-enforcement.md` as the single policy path and reuse `run-epic-risk-classifier.sh`, `run-epic-delegated-gate.sh`, and `run-epic-audit-trail.sh`. |
| Batch or epic wording authorizes out-of-scope merges. | Low | High | Preserve explicit in-scope PR lists and require `out_of_scope` reporting for discovered unrelated PRs. |
| Shell tests become brittle by matching long prose blocks. | Medium | Medium | Test concise required phrases and outcome tokens rather than whole paragraphs. |
| Human handoff wording becomes ambiguous for two-step workflows. | Medium | Medium | Require final summaries to state selected merge authority, expected terminal state, actual terminal state, and next human action. |

---

## Implementation Order

1. Update `guardrails-enforcement.md` with the canonical contract:
   `merge_granted` continues after readiness through Gate 5 and merge cleanup;
   `merge_denied` stops at `ready_human_merge`; `merge_blocked`,
   `policy_inconsistent`, and `out_of_scope` are named outcomes with blocker
   evidence.
2. Update Protocol 91 so the Work Item Runner branches after Step 8c based on
   the effective stage merge authority. Ensure the granted branch cites the
   delegated-gate mechanism and approved merge path, and the denied branch
   forbids merge commands and reports the denying policy value.
3. Update Protocol 90 so explicit-list batch supervision and final summaries
   classify every in-scope PR by expected terminal state and actual terminal
   outcome. Add the `policy_inconsistent` case for merge-granted PRs that stop
   at readiness without a named blocker.
4. Update Protocol 95 so epic delegated review, delegated merge, cleanup, and
   rediscovery use the same outcome vocabulary and policy-consistency checks as
   Protocols 90 and 91.
5. Update Protocol 92, and then `guardrails.md` / workflow README only where
   needed, to clarify that readiness labels are automation-clean evidence but
   not always terminal.
6. Update `/run-item`, `/run-items`, and `/run-epic` command wrappers for
   Claude and Cursor, repo command-style Codex skills in `.agents/skills/`, and
   legacy Codex skills in `.codex/skills/` so every supported surface states the
   same granted-versus-denied condition.
7. Update mirrored `item-orchestrator` and `orchestrator` agent guidance for
   Claude and Cursor. Confirm the wording remains semantically aligned across
   mirrors.
8. Add focused regression coverage. Prefer a new
   `test-may-merge-terminal-contract.sh` for cross-surface static contract
   checks, and extend existing run-epic/bounded-prelude tests only if helper
   behavior changes.
9. Run targeted validation:
   - `bash scripts/development-workflow/tests/test-may-merge-terminal-contract.sh`
     if added.
   - `bash scripts/development-workflow/tests/test-run-epic-delegated-gate.sh`
     if delegated-gate behavior changes.
   - `bash scripts/development-workflow/tests/test-run-bounded-prelude.sh` if
     bounded-prelude wording or output changes.
   - `npx markdownlint-cli2 "docs/workflow/development-workflow/**/*.md" ".agents/skills/**/*.md" ".codex/skills/**/*.md" ".claude/**/*.md" ".cursor/**/*.md"`.
   - `find docs/specs/developments docs/testing/workflow -name "*.md" -print0 | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md`.
10. Update `CHANGELOG.md` under `[Unreleased]` with the literal entry from
    **Documentation Updates**.
11. Before implementation PR readiness, verify residual evidence by rerunning
    the live surface search from the Verification Log and confirming every
    listed affected protocol/command/skill/agent surface either contains the
    terminal-state contract or is intentionally not applicable.
