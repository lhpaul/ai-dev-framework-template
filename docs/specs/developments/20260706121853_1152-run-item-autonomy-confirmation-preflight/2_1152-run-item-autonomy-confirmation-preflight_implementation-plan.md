# Implementation Plan: Run Item Autonomy Confirmation Preflight (#1152)

**Spec**: [1_1152-run-item-autonomy-confirmation-preflight_specs.md](1_1152-run-item-autonomy-confirmation-preflight_specs.md)
**Smoke test runbook**: [run-item-autonomy-confirmation-preflight.smoke-test.md](../../../testing/workflow/run-item-autonomy-confirmation-preflight.smoke-test.md)

---

## Summary

**Approach**: Reuse the existing bounded prelude and run-epic policy helper as
the single autonomy-policy path, then make their run-item output explicit enough
for operators and agent wrappers to present a run-epic-style confirmation
summary. Update Protocol 91 and mirrored `/run-item` surfaces so preflight
confirmation is invocation-scoped authority for the selected item and prevents
redundant prompts for the same backlog-start or stage-handoff authority.

**Estimated complexity**: M

**Rationale**: The change is not algorithmically large, but it spans shared
shell helpers, orchestration protocol text, mirrored agent/command surfaces, and
regression tests. Parser-risk applies because the implementation changes shell
option parsing, JSON shaping, and structured-text output over workflow policy
data.

**Dependencies**: None. Spec PR #1155 is merged and issue #1152 is in
`Spec Ready`.

---

## Template-Fit Check

Passes. The spec improves framework-template workflow tooling and command
surfaces that every downstream project can inherit. It does not reference a
downstream application framework, runtime, database, UI library, or
stack-specific implementation pattern.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `8af50c6` |
| Existing plan artifact | `find docs/specs/developments/20260706121853_1152-run-item-autonomy-confirmation-preflight -maxdepth 1 -type f -print` | Spec only; plan file did not exist before this stage. |
| Run-item and item-orchestrator surfaces | `find .agents/skills/run-item .codex/skills/workflow-item-orchestrator .claude/commands .cursor/commands .claude/agents .cursor/agents -maxdepth 2 -type f \( -name '*.md' -o -name '*.yaml' \) \| sort \| rg 'run-item\|item-orchestrator\|workflow-item-orchestrator'` | 11 files found: `.agents/skills/run-item/SKILL.md`, `.agents/skills/run-item/agents/openai.yaml`, `.claude/agents/item-orchestrator.md`, `.claude/commands/run-item-work.md`, `.claude/commands/run-item.md`, `.claude/commands/run-items.md`, `.codex/skills/workflow-item-orchestrator/SKILL.md`, `.codex/skills/workflow-item-orchestrator/agents/openai.yaml`, `.cursor/agents/item-orchestrator.md`, `.cursor/commands/run-item-work.md`, `.cursor/commands/run-item.md`, `.cursor/commands/run-items.md`. |
| Shared helper tests | `ls scripts/development-workflow/tests \| rg 'bounded\|run-item\|policy\|orchestrat'` | Existing focused tests include `test-run-bounded-prelude.sh` and `test-run-epic-policy-recommender.sh`. |
| Cross-stage agent references | `grep -rl "02-generate-implementation-plan-protocol\|03-implement-development-protocol" .claude/agents/ .cursor/agents/ .codex/skills/ \| sort` | 6 planning/implementation agent skill files found; no new cross-cutting checklist is introduced by this feature. |
| Existing smoke runbook location | `ls docs/testing && find docs/testing/workflow -maxdepth 1 -type f \| sort \| tail -n 20` | Workflow smoke runbooks live under `docs/testing/workflow/`. |

---

## Layer-by-Layer Changes

### Workflow Shell Helpers

- [ ] Update `scripts/development-workflow/run-bounded-prelude.sh` to attach a
      structured `policyRecommendation.confirmationSummary` object to JSON
      output. The object should contain operator-facing lines for scope,
      effective policy, field sources, checkpoints, copy-paste equivalent, and
      read-only guarantee. This satisfies AC1 and AC2 without changing the
      policy model.
- [ ] Update `scripts/development-workflow/run-bounded-prelude.sh` non-JSON
      output to print the same summary in a run-item-neutral way. Avoid a raw
      JSON-only experience when an operator or wrapper does not request
      `--json`. This satisfies AC1 and AC2.
- [ ] Update `scripts/development-workflow/run-epic-policy-recommender.sh`
      display wording so text output is not branded only as "Run Epic" when the
      original command is `/run-item`. Preserve the existing JSON schema fields
      and add new fields only in a backward-compatible way. This satisfies AC8.
- [ ] Keep all helpers read-only in the prelude path. Do not add tracker,
      branch, PR, label, comment, merge, issue-close, or cleanup mutation to
      either helper. This satisfies AC8 and the read-only guarantee in AC2.

### Orchestration Protocols

- [ ] Update `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      so the bounded prelude section explicitly says the runner must present the
      new confirmation summary before mutation.
- [ ] In Protocol 91, introduce a named invocation-scoped state such as
      `RUN_ITEM_POLICY_CONFIRMED=true`, plus companion binding fields for the
      resolved item identifier and normalized selected policy, after the human
      confirms inferred policy or after all autonomy flags are explicit and no
      unresolved checkpoint or guardrail conflict blocks mutation. Use the full
      binding as the mechanism that prevents redundant prompts only for the same
      selected item and policy. This satisfies AC4 and AC5.
- [ ] Update the Protocol 91 backlog-start gate language so a confirmed bounded
      prelude for the same resolved item satisfies the initial backlog-start
      confirmation. The gate must still stop when no confirmed policy exists, a
      different item is encountered, or the requested action exceeds the
      selected policy. This satisfies AC3, AC5, and AC6.
- [ ] Update checkpoint language in Protocol 91 so pending checkpoints remain
      visible after preflight confirmation and block the protected stage until
      satisfied or waived with rationale. This satisfies AC6 and AC7.
- [ ] Update `docs/workflow/development-workflow/bounded-run-prelude.md` with the
      new summary contract, explicit flag behavior, pending-checkpoint behavior,
      and no-redundant-prompt continuation rule for `/run-item`. This satisfies
      AC1 through AC7.
- [ ] Update `docs/workflow/development-workflow/guardrails-enforcement.md`
      Gate 2 so it recognizes the same Protocol 91 invocation-scoped
      confirmation binding for the resolved item and selected policy. Gate 2
      must not require a second backlog-start confirmation when that binding
      matches, and must still stop when the binding is absent, belongs to a
      different item, or permits less authority than the requested action. Do not
      change guardrails field names or modes. This supports AC3, AC5, AC6, and
      AC8.

### Agent and Command Surfaces

- [ ] Update `.agents/skills/run-item/SKILL.md` to instruct Codex to print
      `policyRecommendation.confirmationSummary` after the prelude and to record
      the invocation-scoped confirmation before entering Protocol 91.
- [ ] Update `.agents/skills/run-item/agents/openai.yaml` so the default prompt
      mentions the preflight confirmation summary and no redundant re-prompting
      for the same selected policy.
- [ ] Update `.codex/skills/workflow-item-orchestrator/SKILL.md` and
      `.codex/skills/workflow-item-orchestrator/agents/openai.yaml` with the
      same summary and invocation-scoped confirmation language.
- [ ] Update `.claude/commands/run-item.md` and `.cursor/commands/run-item.md`
      with the same operator contract.
- [ ] Update `.claude/agents/item-orchestrator.md` and
      `.cursor/agents/item-orchestrator.md` so subagent-style item runners honor
      the same summary and no-redundant-prompt behavior.
- [ ] Review `.claude/commands/run-item-work.md` and
      `.cursor/commands/run-item-work.md`. Because they are deprecated aliases,
      either leave them as pointers to `/run-item` or add one sentence stating
      the alias inherits `/run-item` preflight confirmation behavior.
- [ ] Review `.claude/commands/run-items.md` and `.cursor/commands/run-items.md`
      for accidental contradiction. Do not broaden this feature into
      `/run-items`; update only if a shared prelude sentence would otherwise
      conflict with the run-item contract.

### Documentation

- [ ] Update `docs/workflow/development-workflow/README.md` only if its command
      overview needs to mention the run-item confirmation summary or explicit
      autonomy flags for single-item runs.
- [ ] Update `AGENTS.md` only if the high-level Codex Skills section needs a
      concise note about the `/run-item` confirmation summary.
- [ ] Add a `CHANGELOG.md` entry under `[Unreleased]` in the implementation PR,
      not in this plan PR. Literal entry:

      ```markdown
      - **Clarify run-item autonomy confirmation** (#1152): add a run-epic-style
        confirmation summary for single-item runs, preserve checkpoint and
        guardrail stops, and avoid redundant approval prompts after an
        invocation-scoped confirmation.
      ```

### Smoke Test Runbook

- [ ] Add `docs/testing/workflow/run-item-autonomy-confirmation-preflight.smoke-test.md`
      covering the operator-visible confirmation summary, explicit flag path,
      pending checkpoint path, and post-confirmation continuation behavior.

---

## Testing Strategy

**Test types**: Shell unit tests, static documentation checks, markdown lint,
and workflow smoke review.

**Key scenarios to test**:

1. Inferred `/run-item` policy prints an operator-facing summary with effective
   policy, field sources, checkpoints, copy-paste command, and read-only
   guarantee. Maps to AC1, AC2, and AC3.
2. Explicit `/run-item` policy still prints the summary and is identified as
   explicit confirmation when no unresolved checkpoint or guardrail conflict
   blocks mutation. Maps to AC4.
3. Pending checkpoints remain visible and require satisfaction or waiver with
   rationale before their protected stage proceeds. Maps to AC3, AC6, and AC7.
4. Confirmed preflight state satisfies the backlog-start confirmation for the
   same resolved item and does not cause a second identical prompt. Maps to AC5.
5. New stop conditions still interrupt the run with named reasons. Maps to AC6.
6. Codex, Claude, and Cursor run-item surfaces describe the same behavior. Maps
   to AC10.

**Smoke test runbook**:
`docs/testing/workflow/run-item-autonomy-confirmation-preflight.smoke-test.md`

**Regression suite**:

- `bash scripts/development-workflow/tests/test-run-bounded-prelude.sh`
- `bash scripts/development-workflow/tests/test-run-epic-policy-recommender.sh`
- `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`
- `npx markdownlint-cli2 "docs/specs/developments/20260706121853_1152-run-item-autonomy-confirmation-preflight/2_1152-run-item-autonomy-confirmation-preflight_implementation-plan.md" "docs/testing/workflow/run-item-autonomy-confirmation-preflight.smoke-test.md"`

### Parser-Risk Addendum

**Edge-case enumeration**:

1. `/run-item 1152` with policy values sourced from guardrails: summary reports
   field source `guardrails`, `requiresConfirmation=true`, and does not claim
   the values were explicit.
2. `/run-item 1152 --delegate-review --may-merge --may-start-backlog true
   --max-risk medium --base develop`: summary reports explicit field sources
   for supplied flags and still prints before mutation.
3. `/run-item` with a recommended pending checkpoint: summary lists checkpoint
   stage, domain, satisfaction state, required human action, and
   `--checkpoints-file checkpoint-policy.json`.
4. Checkpoint waiver without `waiver_rationale`: helper exits non-zero and does
   not produce a policy that could silently waive the checkpoint.
5. Ambiguous base or ambiguous item scope: summary names the ambiguity and does
   not present the copy-paste command as authority to mutate.
6. Text output with original command `/run-item`: heading and body are
   run-item-neutral or run-item-specific, not "Run Epic" only.
7. JSON output remains backward-compatible: existing fields stay present and
   `confirmationSummary` is additive.
8. Confirmed preflight plus backlog item: Protocol 91 does not ask for the same
   backlog-start confirmation again for the same resolved item.
9. Confirmed preflight plus new blocker: Protocol 91 still stops on new named
   stop conditions.

**Unit test mapping**:

- `scripts/development-workflow/tests/test-run-bounded-prelude.sh`
  - Add tests for edge cases 1, 2, 3, 5, 6, and 7.
  - Add a fixture assertion that `policyRecommendation.confirmationSummary`
    includes scope, policy, field source, checkpoint, copy-paste, and read-only
    fields.
- `scripts/development-workflow/tests/test-run-epic-policy-recommender.sh`
  - Extend existing explicit-policy and checkpoint tests for edge cases 3 and 4
    if the summary object is created in the recommender instead of only in the
    bounded prelude.
- Static protocol/surface checks
  - Use a simple `rg` verification in the smoke runbook for edge cases 8 and 9:
    confirm Protocol 91 names the invocation-scoped confirmation state and the
    named-stop exceptions.

**Suppression semantics**: Not applicable. This feature does not introduce
inline suppression directives.

### Concurrent-Event-Source Addendum

- **Shared mutable state guards**: Not applicable; no concurrent event sources
  or shared in-memory state are introduced.
- **Re-entrancy / in-flight tracking**: Not applicable; helpers are invoked as
  one-shot shell commands.
- **Event deduplication**: Not applicable; no listener or event stream is added.
- **Listener and resource cleanup**: Not applicable; no listeners, timers, or
  handles are registered.
- **Race conditions at initialization**: Not applicable; no async
  initialization path is introduced.
- **Race conditions at teardown**: Not applicable; no async teardown path is
  introduced.
- **Error propagation across async boundaries**: Not applicable; no async
  callback path is introduced.

---

## Seed Data

No persistent seed data is required.

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Shell fixture scope JSON | Temporary fixtures for run-item policy, explicit policy, ambiguous base, and checkpoints | Created inside `scripts/development-workflow/tests/test-run-bounded-prelude.sh` |
| Checkpoint policy JSON | Temporary valid and invalid checkpoint waiver fixtures | Created inside the shell test temp directory |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      - Define the run-item confirmation summary and invocation-scoped
        confirmation behavior.
- [ ] `docs/workflow/development-workflow/bounded-run-prelude.md` - Document the
      summary object, explicit flag behavior, checkpoint behavior, and
      no-redundant-prompt continuation.
- [ ] `docs/workflow/development-workflow/guardrails-enforcement.md` - Update
      only if the implementation needs a cross-reference to invocation-scoped
      confirmation; otherwise leave unchanged.
- [ ] `docs/workflow/development-workflow/README.md` - Add a concise
      single-item explicit-autonomy example if needed.
- [ ] `AGENTS.md` - Add a short `/run-item` confirmation note if needed for
      command-surface parity.
- [ ] `.agents/skills/run-item/SKILL.md` and
      `.agents/skills/run-item/agents/openai.yaml` - Codex run-item behavior.
- [ ] `.codex/skills/workflow-item-orchestrator/SKILL.md` and
      `.codex/skills/workflow-item-orchestrator/agents/openai.yaml` - Legacy
      Codex orchestrator behavior.
- [ ] `.claude/commands/run-item.md` and `.cursor/commands/run-item.md` -
      command behavior for Claude and Cursor.
- [ ] `.claude/agents/item-orchestrator.md` and
      `.cursor/agents/item-orchestrator.md` - subagent runner behavior.
- [ ] `.claude/commands/run-item-work.md` and
      `.cursor/commands/run-item-work.md` - alias inheritance note if needed.
- [ ] `docs/testing/workflow/run-item-autonomy-confirmation-preflight.smoke-test.md`
      - Human-readable smoke coverage for the implementation.
- [ ] `CHANGELOG.md` - Add the implementation entry shown in the documentation
      layer above during the implementation PR.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| A second policy model is accidentally introduced in command wrappers. | Medium | High | Keep shell helpers as the source of policy truth and make wrappers print `confirmationSummary` rather than re-deriving policy. |
| Confirmation could be treated as a silent checkpoint waiver. | Medium | High | Keep checkpoint satisfaction state explicit and require waiver rationale in helper validation and protocol text. |
| Backlog-start confirmation could be skipped for unrelated items. | Low | High | Require Protocol 91 to store companion binding fields with `RUN_ITEM_POLICY_CONFIRMED`, including the resolved item identifier and normalized selected policy, and ignore the confirmation when either value changes. |
| Summary text could drift across Codex, Claude, and Cursor surfaces. | Medium | Medium | Update mirrored surfaces in the same implementation PR and add smoke/static checks for the common phrases. |
| Shell JSON additions break existing consumers. | Low | Medium | Make `confirmationSummary` additive and keep existing JSON fields unchanged. |

---

## Code Samples

No production code samples are required. Implementation should prefer small
shell/JQ additions in existing helpers and protocol text changes over new
standalone abstractions.

---

## Implementation Order

1. Update `run-epic-policy-recommender.sh` text output labels if needed so the
   helper can describe `/run-item` policy without "Run Epic" wording.
2. Update `run-bounded-prelude.sh` to add
   `policyRecommendation.confirmationSummary` to JSON output and to print the
   same summary in non-JSON mode.
3. Extend `test-run-bounded-prelude.sh` for inferred policy, explicit policy,
   pending checkpoints, ambiguous base, text-output heading, and additive JSON
   summary fields.
4. Extend `test-run-epic-policy-recommender.sh` only for recommender-owned
   summary or checkpoint behavior changed in Step 1.
5. Update Protocol 91 to define the invocation-scoped confirmation state, the
   backlog-start no-redundant-prompt rule, and the named-stop/checkpoint
   exceptions.
6. Update `bounded-run-prelude.md` to document the summary object and
   confirmation contract.
7. Update run-item command and agent surfaces across Codex, Claude, and Cursor:
   `.agents/skills/run-item/SKILL.md`,
   `.agents/skills/run-item/agents/openai.yaml`,
   `.codex/skills/workflow-item-orchestrator/SKILL.md`,
   `.codex/skills/workflow-item-orchestrator/agents/openai.yaml`,
   `.claude/commands/run-item.md`, `.cursor/commands/run-item.md`,
   `.claude/agents/item-orchestrator.md`, and
   `.cursor/agents/item-orchestrator.md`.
8. Review deprecated alias files and run-items files for contradiction; add
   alias inheritance notes only if necessary.
9. Update `docs/workflow/development-workflow/README.md`, `AGENTS.md`, and
   `guardrails-enforcement.md` only where the prior steps introduce a stale or
   incomplete public contract.
10. Add the smoke runbook at
    `docs/testing/workflow/run-item-autonomy-confirmation-preflight.smoke-test.md`.
11. Add the `CHANGELOG.md` entry under `[Unreleased]` using the literal in the
    Documentation Updates section.
12. Run verification:
    - `bash scripts/development-workflow/tests/test-run-bounded-prelude.sh`
    - `bash scripts/development-workflow/tests/test-run-epic-policy-recommender.sh`
    - `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`
    - `npx markdownlint-cli2 "docs/workflow/development-workflow/**/*.md" ".agents/skills/run-item/SKILL.md" ".codex/skills/workflow-item-orchestrator/SKILL.md" ".claude/commands/run-item.md" ".cursor/commands/run-item.md" "docs/testing/workflow/run-item-autonomy-confirmation-preflight.smoke-test.md" "CHANGELOG.md"`
13. Manually run the smoke test runbook and record any deviations in the
    implementation PR body.
