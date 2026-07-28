# Implementation Plan: Epic Continuation Gate

**Spec**: [1_1372-epic-continuation-gate_specs.md](1_1372-epic-continuation-gate_specs.md)
**Smoke test runbook**: [1372-epic-continuation-gate.smoke-test.md](../../../testing/workflow/1372-epic-continuation-gate.smoke-test.md)

---

## Summary

**Approach**: Extend the read-only epic scope resolver with one deterministic `continuation` object derived from its final, enriched items, groups, and saved invocation policy. It will emit `continue`, `complete`, or `needs_resolution`, name the relevant child items, and render the same result in text mode. Protocol 95 and every run-epic command/skill mirror will require a refresh after each child terminal decision and obey that result.

**Estimated complexity**: M — the implementation is contained to workflow shell, tests, and mirrored guidance, but changes a cross-cutting terminal decision.

**Dependencies**: Approved spec PR #1373 (merged). No additional runtime or open-item dependencies.

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repository revision | `git rev-parse origin/develop` | `6c82d4b927a9efc5b832d28b93870a0c5003dacd` |
| Current resolver contract | `sed -n '600,860p' scripts/development-workflow/run-epic-scope-resolver.sh` | Resolver already has enriched groups and a final JSON/text rendering boundary; continuation should be derived there without mutations. |
| Existing regression harness | `rg -n 'MOCK_EPIC_MODE|all.*merged|empty|whitespace' scripts/development-workflow/tests/test-run-epic-scope-resolver.sh` | The shell harness has mock GitHub fixtures and must gain the named continuation cases under Resolver and tests (`continuation_merged_plus_eligible`, `continuation_authorized_backlog`, `continuation_in_review`, `continuation_eligible_plus_blocked`, `continuation_all_merged`, `continuation_empty_scope`, `continuation_unauthorized_backlog`, `continuation_whitespace_items`), plus optional named-stop cases for ambiguous / blocked-only / out-of-scope. |
| Runner mirrors | `rg -l 'run-epic|merge_granted|rediscovery' .agents/skills/run-epic .claude/commands/run-epic.md .cursor/commands/run-epic.md docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` | Protocol 95, the Codex alias and metadata, and Claude/Cursor command mirrors are applicable. |
| Template fit | `sed -n '1,220p' .ai-dev-workflow.yaml` | `template.is_template: true`; this is generic shipped workflow behavior. |

## Layer-by-Layer Changes

### Resolver and tests

- [ ] In `scripts/development-workflow/run-epic-scope-resolver.sh`, add a pure continuation classifier after the final scope groups are known. Its JSON fields must include outcome, terminal flag, next action, remaining items, and named-stop data when resolution is required. It must never mutate tracker, Git, PR, issue, or cleanup state. Maps to AC1-AC6.
- [ ] Define precedence from each enriched item, not groups alone. First, any in-review item, non-Backlog eligible item, or Backlog item with `policy.mayStartBacklog: true` yields `continue`, even when another sibling is blocked or ambiguous; list those actionable children in `remainingItems` and leave `affectedItems` empty. If no child can continue, empty scope; `ambiguous` or `blocked` groups; and an `eligible` item whose status is `Backlog` while `policy.mayStartBacklog` is false yield `needs_resolution`. For those stops: empty and ambiguous leave `affectedItems` empty; blocked puts the blocked child in `affectedItems` and names its dependency in `humanAction`; unauthorized-Backlog puts that Backlog child in `affectedItems`. `out_of_scope` remains a downstream-consumer classification and is not a resolver-produced continuation input. Only a non-empty all-`already_merged` scope yields `complete` with both arrays empty. Maps to AC2-AC6.
- [ ] Map every `needs_resolution` result to a guardrails-enforcement named stop: empty, ambiguous, and unauthorized-Backlog scope use `missing_tracker_context` (with the latter requesting an explicit policy confirmation that grants backlog-start authority); a blocked dependency uses `unclear_requirements` with the dependency named. Preserve any delegated-gate `human_required` result as supporting authority evidence, never as `continuation.stopCondition`. Do not create a second guardrail or policy model. Maps to AC5-AC6 and the named-stop contract.
- [ ] Render stable text keys alongside JSON so manual operators see the outcome and next action. Preserve existing grouping and read-only guarantees. Maps to Operational Visibility and AC8.
- [ ] Extend `scripts/development-workflow/tests/test-run-epic-scope-resolver.sh` with eight named cases (fixture ids below). For each case assert both JSON (`continuation.*` camelCase) and text mode (stable key order; omit null-valued `stop_condition` / `human_action` lines). Assert outcome, `terminal`, `nextAction`, `remainingItems` / `affectedItems` per the Continuation Schema, and named-stop fields. Maps to AC7.
  - `continuation_merged_plus_eligible` — merged + eligible non-Backlog → `continue`
  - `continuation_authorized_backlog` — authorized Backlog sibling → `continue`
  - `continuation_in_review` — in-review sibling → `continue`
  - `continuation_eligible_plus_blocked` — eligible + blocked → `continue` (actionable in `remainingItems`)
  - `continuation_all_merged` — non-empty all-merged → `complete`
  - `continuation_empty_scope` — empty scope → `needs_resolution` / `missing_tracker_context`
  - `continuation_unauthorized_backlog` — unauthorized Backlog → `needs_resolution` / `missing_tracker_context`
  - `continuation_whitespace_items` — whitespace-only `--items` → validation failure (no continuation object)

### Protocol and command mirrors

- [ ] Update `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` Step 11 to re-resolve after every child terminal decision, branch on the continuation result, and forbid completion before live verification of a `complete` result. Specify `needs_resolution` as the named-stop contract. The resolver itself does not emit `out_of_scope` items; when a downstream consumer's bounded-handoff comparison detects one, Protocol 95 must stop before closeout with `missing_tracker_context`, list the affected item, and require a human to correct membership or explicitly re-scope it. Maps to AC1-AC6.
- [ ] Update `.agents/skills/run-epic/SKILL.md` and `.agents/skills/run-epic/agents/openai.yaml` with the same post-child refresh and outcome contract for Codex.
- [ ] Update `.claude/commands/run-epic.md` and `.cursor/commands/run-epic.md` with equivalent continuation outcomes and next actions. Keep them as mirrors of Protocol 95, not independent policy definitions. Maps to AC8.
- [ ] Add one `[Unreleased]` entry to `CHANGELOG.md` only in the implementation PR: `- **Add epic continuation gate** (#1372): require delegated epic runs to re-resolve remaining child work before closeout.` Maps to the issue scope.

### Non-applicable layers

- Database, external HTTP/REST API, frontend/UI, and infrastructure/configuration changes are not applicable. This feature uses existing shell, GitHub CLI, and project configuration surfaces. The resolver's new `continuation` JSON/text result is an internal protocol contract (not an external API); validate its schema, serialization, and mirror compatibility under Document Quality Gate below.

## Decision-Gate Matrix

| Resolver state after refresh | Outcome | Runner action | Evidence |
| --- | --- | --- | --- |
| Eligible non-Backlog, authorized Backlog, or in-review child remains | `continue` | Name and advance the child under the saved invocation policy. | Resolver regression and Protocol 95 wording. |
| Every resolved child is merged and scope is non-empty | `complete` | Verify live child state, then complete epic closeout. | All-merged regression. |
| No actionable child remains and scope is empty, ambiguous, blocked, or has unauthorized Backlog work | `needs_resolution` | Stop with the mapped named condition, affected child, and human action. | Empty-scope and authority/resolution assertions. |
| A downstream bounded-handoff comparison detects an out-of-scope item | `needs_resolution` | Stop before closeout with `missing_tracker_context`; name the item and ask a human to correct membership or explicitly re-scope it. | Protocol 95 and mirror wording assertions. |

## Continuation Schema (authoritative)

This is the single source of truth for the resolver `continuation` object. Protocol 95 and every run-epic command/skill mirror must reference these keys; they must not redefine alternate shapes.

### JSON object (under top-level key `continuation`)

| Key | Type | Required | Omission / null rules |
| --- | --- | --- | --- |
| `outcome` | string enum: `continue` \| `complete` \| `needs_resolution` | always | Never null or omitted. |
| `terminal` | boolean | always | `false` for `continue`; `true` for `complete` and `needs_resolution`. |
| `nextAction` | string | always | Non-empty operator-facing next step. Never null. |
| `remainingItems` | array of positive integers (issue numbers) | always | Empty array `[]` when none; never null or omitted. For `continue`, lists actionable remaining children only (eligible non-Backlog, authorized Backlog, or in-review). Never includes blocked/ambiguous/out-of-scope siblings that did not win precedence. |
| `affectedItems` | array of positive integers | always | Empty array `[]` when none; never null or omitted. For `needs_resolution`: empty when stop is empty or ambiguous scope; blocked child id for `unclear_requirements`; unauthorized Backlog child id for `missing_tracker_context`. Empty for `continue` and `complete`. |
| `stopCondition` | string \| null | always present | Non-null only when `outcome` is `needs_resolution`. Exact values: `missing_tracker_context` (empty, ambiguous, or unauthorized Backlog scope), `unclear_requirements` (blocked dependency). Omit meaning is not allowed — use JSON `null` when N/A. |
| `humanAction` | string \| null | always present | Non-null only when `outcome` is `needs_resolution`; concrete unblock instruction. Use JSON `null` when N/A. |

Representative fixtures:

```json
{"outcome":"continue","terminal":false,"nextAction":"Advance remaining eligible child under the saved invocation policy.","remainingItems":[102],"affectedItems":[],"stopCondition":null,"humanAction":null}
```

```json
{"outcome":"complete","terminal":true,"nextAction":"Verify live child states, then complete epic closeout.","remainingItems":[],"affectedItems":[],"stopCondition":null,"humanAction":null}
```

```json
{"outcome":"needs_resolution","terminal":true,"nextAction":"Stop; resolve named condition before ending the run.","remainingItems":[],"affectedItems":[],"stopCondition":"missing_tracker_context","humanAction":"Resolve epic membership or tracker scope so at least one in-scope child is present."}
```

### Text mode keys (stable order)

Render these keys in this order when not using `--json`:

1. `continuation.outcome`
2. `continuation.terminal`
3. `continuation.next_action`
4. `continuation.remaining_items` (comma-separated, or empty)
5. `continuation.affected_items` (comma-separated, or empty)
6. `continuation.stop_condition` (omit line when null)
7. `continuation.human_action` (omit line when null)

Text snake_case keys map 1:1 to the camelCase JSON fields above (`next_action` ↔ `nextAction`, etc.).

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
2. Add the eight regression fixtures/assertions, including named-stop assertions and the three continue-branch variants.
3. Update Protocol 95 and all Codex, Claude, and Cursor run-epic mirrors from the matrix.
4. Add the literal CHANGELOG entry above, run ShellCheck, the shell guard, markdown lint, and targeted tests.
5. Open the implementation PR only after the plan PR is merged and the implementation guard approves the `feature/1372-epic-continuation-gate` branch.

## Document Quality Gate

- Spec/brief coverage: Checked - each acceptance criterion maps to a resolver, mirror, or test change.
- Implementation-order consistency: Checked - resolver precedes regressions and mirrors.
- Verification support: Checked - commands and current resolver locations are recorded above.
- Complex workflow decision-gate matrix: Checked - the continuation outcomes, next actions, and mirrors are explicit.
- Parser/API/concurrency checklist: Checked for internal contract - the Continuation Schema section above is authoritative for JSON keys, types, null rules, text-key names/order, and `needs_resolution` stop mappings. Protocol 95 and mirrors reference that schema; harness fixtures assert against it. No external HTTP API, snapshot model, or concurrent event source is introduced.
