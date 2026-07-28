# Implementation Plan: Epic Continuation Gate

**Spec**: [1_1372-epic-continuation-gate_specs.md](1_1372-epic-continuation-gate_specs.md)
**Smoke test runbook**: [1372-epic-continuation-gate.smoke-test.md](../../../testing/workflow/1372-epic-continuation-gate.smoke-test.md)

---

## Summary

**Approach**: Extend the read-only epic scope resolver with one deterministic `continuation` object derived from its final, enriched items, groups, and saved invocation policy. It will emit `continue`, `complete`, or `needs_resolution`, name the relevant child items, and render the same result in text mode. Protocol 95 and every run-epic command/skill mirror will require a refresh after each child terminal decision and obey that result.

**Estimated complexity**: M — the implementation is contained to workflow shell, tests, and mirrored guidance, but changes a cross-cutting terminal decision.

**Dependencies**: None. The merged spec PR #1373 is the approved prerequisite.

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repository revision | `git rev-parse origin/develop` | `6c82d4b927a9efc5b832d28b93870a0c5003dacd` |
| Current resolver contract | `sed -n '600,860p' scripts/development-workflow/run-epic-scope-resolver.sh` | Resolver already has enriched groups and a final JSON/text rendering boundary; continuation should be derived there without mutations. |
| Existing regression harness | `rg -n 'MOCK_EPIC_MODE|all.*merged|empty|whitespace' scripts/development-workflow/tests/test-run-epic-scope-resolver.sh` | The shell harness has mock GitHub fixtures and must gain the four acceptance scenarios. |
| Runner mirrors | `rg -l 'run-epic|merge_granted|rediscovery' .agents/skills/run-epic .claude/commands/run-epic.md .cursor/commands/run-epic.md docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` | Protocol 95, the Codex alias and metadata, and Claude/Cursor command mirrors are applicable. |
| Template fit | `sed -n '1,220p' .ai-dev-workflow.yaml` | `template.is_template: true`; this is generic shipped workflow behavior. |

## Layer-by-Layer Changes

### Resolver and tests

- [ ] In `scripts/development-workflow/run-epic-scope-resolver.sh`, add a pure continuation classifier after the final scope groups are known. Its JSON fields must include outcome, terminal flag, next action, remaining items, and named-stop data when resolution is required. It must never mutate tracker, Git, PR, issue, or cleanup state. Maps to AC1-AC6.
- [ ] Define precedence from each enriched item, not groups alone: empty scope; `ambiguous`, `blocked`, or `out_of_scope` groups; and an `eligible` item whose status is `Backlog` while `policy.mayStartBacklog` is false yield `needs_resolution`. Any in-review item, non-Backlog eligible item, or Backlog item with `policy.mayStartBacklog: true` yields `continue`; only a non-empty all-`already_merged` scope yields `complete`. Include the exact affected item and a concrete human action for resolution. Maps to AC2-AC6.
- [ ] Map every `needs_resolution` result to an existing named stop: empty or ambiguous scope uses `missing_tracker_context`; a blocked dependency uses `unclear_requirements` with the dependency named; an unauthorized Backlog child uses `human_checkpoint_required`; and an out-of-scope item uses `missing_tracker_context` with an instruction to resolve epic membership. Do not create a second guardrail or policy model. Maps to AC5-AC6 and the named-stop contract.
- [ ] Render stable text keys alongside JSON so manual operators see the outcome and next action. Preserve existing grouping and read-only guarantees. Maps to Operational Visibility and AC8.
- [ ] Extend `scripts/development-workflow/tests/test-run-epic-scope-resolver.sh` with merged-plus-eligible, all-merged, empty scope, unauthorized-Backlog, and whitespace-only `--items` cases. Assert the outcome, terminal status, remaining/affected child behavior, policy-sensitive Backlog routing, and rejection of whitespace-only input. Maps to AC7.

### Protocol and command mirrors

- [ ] Update `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` Step 11 to re-resolve after every child terminal decision, branch on the continuation result, and forbid completion before live verification of a `complete` result. Specify `needs_resolution` as the named-stop contract. Maps to AC1-AC6.
- [ ] Update `.agents/skills/run-epic/SKILL.md` and `.agents/skills/run-epic/agents/openai.yaml` with the same post-child refresh and outcome contract for Codex.
- [ ] Update `.claude/commands/run-epic.md` and `.cursor/commands/run-epic.md` with equivalent continuation outcomes and next actions. Keep them as mirrors of Protocol 95, not independent policy definitions. Maps to AC8.
- [ ] Add one `[Unreleased]` entry to `CHANGELOG.md` only in the implementation PR: `- **Add epic continuation gate** (#1372): require delegated epic runs to re-resolve remaining child work before closeout.` Maps to the issue scope.

### Non-applicable layers

- Database, backend/API, frontend/UI, and infrastructure/configuration changes are not applicable. This feature uses existing shell, GitHub CLI, and project configuration surfaces.

## Decision-Gate Matrix

| Resolver state after refresh | Outcome | Runner action | Evidence |
| --- | --- | --- | --- |
| Eligible non-Backlog, authorized Backlog, or in-review child remains | `continue` | Name and advance the child under the saved invocation policy. | Resolver regression and Protocol 95 wording. |
| Every resolved child is merged and scope is non-empty | `complete` | Verify live child state, then complete epic closeout. | All-merged regression. |
| Empty, ambiguous, blocked, out-of-scope, or unauthorized Backlog child | `needs_resolution` | Stop with the mapped named condition, affected child, and human action. | Empty-scope and authority/resolution assertions. |

## Testing Strategy

- Run `bash scripts/development-workflow/tests/test-run-epic-scope-resolver.sh` for all resolver outcomes and whitespace input validation.
- Run `shellcheck scripts/development-workflow/run-epic-scope-resolver.sh scripts/development-workflow/tests/test-run-epic-scope-resolver.sh` and `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`.
- Run markdown lint and the heuristic lint on the plan/runbook during this stage; during implementation, run the same documentation checks for changed mirrors and the focused shell harness.
- Review the matrix above against Protocol 95, Codex, Claude, and Cursor mirrors before readiness.

## Documentation Updates

- [ ] Protocol 95 and the four run-epic command/skill surfaces listed above.
- [ ] `CHANGELOG.md` only in implementation.
- [ ] No project architecture or best-practice documentation change is required.

## Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| An all-merged-looking group hides unresolved scope | Classify empty and unresolved groups before complete; require live verification in Protocol 95. |
| Mirrors drift from resolver semantics | Keep the three-outcome matrix in the protocol and add focused wording assertions where practical. |
| Whitespace creates an implicit empty item | Retain strict explicit-item parsing and cover whitespace-only input in the harness. |

## Implementation Order

1. Add the resolver continuation classifier and text renderer, then run its focused harness.
2. Add the four regression fixtures/assertions, including named-stop assertions.
3. Update Protocol 95 and all Codex, Claude, and Cursor run-epic mirrors from the matrix.
4. Add the literal CHANGELOG entry above, run ShellCheck, the shell guard, markdown lint, and targeted tests.
5. Open the implementation PR only after the plan PR is merged and the implementation guard approves the `feature/1372-epic-continuation-gate` branch.

## Document Quality Gate

- Spec/brief coverage: Checked - each acceptance criterion maps to a resolver, mirror, or test change.
- Implementation-order consistency: Checked - resolver precedes regressions and mirrors.
- Verification support: Checked - commands and current resolver locations are recorded above.
- Complex workflow decision-gate matrix: Checked - the continuation outcomes, next actions, and mirrors are explicit.
- Parser/API/concurrency checklist: Not applicable - no new parser, API surface, snapshot model, or concurrent event source is introduced.
