# Deprecate Direct Item-Orchestrator Command for Cursor Runs - Implementation Plan

**Spec**: [1_1190-deprecate-direct-item-orchestrator-cursor-runs_specs.md](1_1190-deprecate-direct-item-orchestrator-cursor-runs_specs.md)
**Smoke test runbook**: [1190-deprecate-direct-item-orchestrator-cursor-runs.smoke-test.md](../../../testing/workflow/1190-deprecate-direct-item-orchestrator-cursor-runs.smoke-test.md)

---

## Summary

**Approach**: Update the Cursor-facing command and agent guidance so `/run-item`
is the only normal user-facing entrypoint while `item-orchestrator` remains an
internal subagent/handoff role. Keep mirrored Claude/Codex/shared docs aligned
where they mention the same entrypoint, and add smoke-test coverage that checks
the canonical Cursor path plus model-routing intent.

**Estimated complexity**: M

**Rationale**: The change is mostly documentation and command-wrapper guidance,
but it spans mirrored agent surfaces and workflow docs. The main risk is either
over-removing internal `item-orchestrator` references that are still needed for
subagent dispatch, or under-updating Cursor-facing prose that still tells users
to invoke `/item-orchestrator` directly.

**Dependencies**: Spec PR #1195 is merged to `develop`.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `b460337` |
| Template-fit check | Read `.ai-dev-workflow.yaml` and spec | `template.is_template: true`; spec is generic workflow tooling for this template, not downstream framework-specific behavior |
| Primary run-item surfaces | `rg -l "item-orchestrator\|/item-orchestrator\|/run-item\|run-item" AGENTS.md .cursor/commands .cursor/agents .claude/commands .claude/agents .agents/skills .codex/skills docs/workflow/development-workflow docs/testing/workflow -g '*.md' -g '*.yaml' -g '*.mdc' \| sort` | Live search found the command, agent, skill, workflow-doc, and smoke-test surfaces that need review; implementation should update the targeted subset listed below and leave unrelated historical smoke tests intact unless they describe current guidance |
| Current Cursor user-facing conflict | Read `AGENTS.md` Cursor note and `.cursor/commands/run-item.md` | `AGENTS.md` currently says Cursor users may invoke `/item-orchestrator` directly; `.cursor/commands/run-item.md` does not yet state Cursor internal handoff/model-routing behavior |
| Model-routing source | Read `docs/workflow/development-workflow/agent-model-config.md` and `.cursor/agents/*.md` | Cursor agent model pins already exist; implementation should preserve these assignments and explain that `/run-item` can route through them internally |

---

## Layer-by-Layer Changes

### Documentation / Command Guidance

- [ ] Update `AGENTS.md` Cursor note so users are directed to workflow commands
      first, especially `/run-item <target>` for single-item advancement. Keep
      Cursor subagents documented as configured internal/expert roles, but do
      not present `/item-orchestrator` as the normal user-facing path.
- [ ] Update the **Workflow Commands** row for **Advance One Item** in `AGENTS.md`
      only if needed to clarify that Cursor users invoke `/run-item`, while the
      `item-orchestrator` role is internal/subagent execution support rather
      than an alternate user entrypoint.
- [ ] Update `.cursor/commands/run-item.md` to define the Cursor execution
      contract:
      - `/run-item` runs the bounded prelude first.
      - After confirmation, Cursor should hand off internally to the configured
        `item-orchestrator` and stage subagents when supported.
      - The handoff preserves confirmed scope and selected policy.
      - The receiving internal context must not rerun the bounded prelude or
        re-prompt for the same confirmed policy.
      - If internal handoff is unavailable, the fallback still starts from
        `/run-item` and must preserve Protocol 91 stops.
- [ ] Update `.cursor/agents/item-orchestrator.md` so its description and opening
      guidance identify it as an internal target for `/run-item` handoff and
      legacy compatibility, not the normal command users should invoke.
- [ ] Update `.claude/commands/run-item.md`, `.claude/agents/item-orchestrator.md`,
      `.agents/skills/run-item/SKILL.md`, and
      `.codex/skills/workflow-item-orchestrator/SKILL.md` only where needed to
      preserve mirrored terminology and avoid contradicting the Cursor-specific
      handoff contract. Do not add Cursor-only behavior to non-Cursor surfaces.
- [ ] Review `.cursor/commands/run-item-work.md` and `.claude/commands/run-item-work.md`
      to ensure their deprecation wording still points to `/run-item` and does
      not encourage direct `item-orchestrator` use.
- [ ] Review `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      where it mentions Cursor `/item-orchestrator` dispatch. If retained, label
      it as internal dispatch from orchestration, not user-facing invocation.
- [ ] Update `docs/workflow/development-workflow/agent-model-config.md` to
      reinforce the model-routing intent: Cursor pins subagent models so
      `/run-item` internal handoff can use the role-appropriate model instead of
      relying on the parent Composer model.

### Smoke Test Coverage

- [ ] Add `docs/testing/workflow/1190-deprecate-direct-item-orchestrator-cursor-runs.smoke-test.md`
      covering all acceptance criteria from the spec.
- [ ] The smoke test should inspect Cursor and shared guidance surfaces, not run
      an end-to-end live Cursor session. It should verify:
      - Cursor user-facing guidance names `/run-item <target>` as canonical.
      - Cursor docs do not instruct normal direct `/item-orchestrator`
        invocation.
      - Remaining `item-orchestrator` references are internal, compatibility, or
        historical test context.
      - `/run-item` handoff preserves bounded prelude confirmation.
      - Model-routing intent points at configured Cursor subagents.
      - Mirrored run-item surfaces remain consistent.

### Tests / Tooling

- [ ] Run markdown lint on every modified markdown file plus this plan and the
      smoke runbook.
- [ ] Run a targeted `rg` verification after implementation to inspect remaining
      direct `/item-orchestrator` references and classify each as internal,
      compatibility, or historical.

### Changelog

- [ ] Add an `[Unreleased]` entry during implementation:
      `- **Deprecate direct Cursor item-orchestrator path** (#1190): Clarify that Cursor users start single-item work with /run-item while internal handoff preserves configured subagent model routing.`

---

## Testing Strategy

**Test types**: Documentation inspection, smoke checklist, markdown lint.

**Key scenarios to test**:

1. Cursor `/run-item` is the canonical user-facing command for single-item work
   and maps to AC1.
2. Direct `/item-orchestrator` references are no longer presented as the normal
   Cursor path and map to AC2 and AC3.
3. The Cursor `/run-item` handoff contract preserves bounded prelude scope and
   policy without duplicate prompts and maps to AC4 and AC5.
4. Stage-specific model routing through configured Cursor agents is documented
   and maps to AC6 and AC8.
5. Mirrored Cursor, Claude, Codex, and shared workflow surfaces remain aligned
   and map to AC7.

**Smoke test runbook**: `docs/testing/workflow/1190-deprecate-direct-item-orchestrator-cursor-runs.smoke-test.md`

**Regression suite**: No automated application regression suite applies. This is
a repository workflow documentation change; markdown lint and repository
inspection smoke coverage are the appropriate verification layer.

### Parser-risk addendum

Not applicable. The plan does not introduce parser, scanner, lint rule, regex
engine, or structured-text parsing behavior.

### Concurrent-event-source addendum

Not applicable. The plan does not introduce event listeners, callbacks, timers,
async queues, or shared mutable runtime state.

---

## Seed Data

No seed data is required.

| Entity | Values / Scenario | File |
| --- | --- | --- |
| None | Documentation and workflow guidance inspection only | Not applicable |

---

## Documentation Updates

- [ ] `AGENTS.md` - update Cursor user guidance and, if needed, the single-item
      workflow command row.
- [ ] `.cursor/commands/run-item.md` - define Cursor's canonical `/run-item`
      handoff contract.
- [ ] `.cursor/agents/item-orchestrator.md` - clarify internal/compatibility role.
- [ ] `.claude/commands/run-item.md` - keep mirrored canonical entrypoint wording
      consistent without adding Cursor-only behavior.
- [ ] `.claude/agents/item-orchestrator.md` - keep mirrored internal role wording
      consistent where applicable.
- [ ] `.agents/skills/run-item/SKILL.md` - keep Codex command alias wording
      consistent with canonical `/run-item`.
- [ ] `.codex/skills/workflow-item-orchestrator/SKILL.md` - keep legacy Codex
      orchestrator wording from contradicting `/run-item` as canonical.
- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      - clarify Cursor `item-orchestrator` mentions as internal dispatch where
      currently ambiguous.
- [ ] `docs/workflow/development-workflow/agent-model-config.md` - document why
      Cursor `/run-item` internal handoff preserves configured model routing.
- [ ] `docs/testing/workflow/1190-deprecate-direct-item-orchestrator-cursor-runs.smoke-test.md`
      - add smoke coverage for this feature.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Internal dispatch references are removed or over-deprecated | Medium | Medium | Keep `item-orchestrator` as an internal subagent role and only deprecate direct normal user invocation |
| Cursor-specific behavior leaks into Claude or Codex guidance | Medium | Low | Update mirrored surfaces only for canonical terminology; keep Cursor handoff details in Cursor-facing docs |
| A remaining `/item-orchestrator` mention is misclassified | Medium | Medium | Add smoke-test steps requiring every remaining direct mention to be classified as internal, compatibility, or historical |
| Implementation forgets model-routing motivation | Low | Medium | Update `agent-model-config.md` and smoke-test assertions to verify Cursor model-routing intent |

---

## Code Samples

No code samples are included. Implementation should edit markdown guidance and
smoke-test files only.

---

## Implementation Order

1. Update Cursor-facing user guidance in `AGENTS.md` so `/run-item <target>` is
   the normal single-item entrypoint and direct `/item-orchestrator` use is not
   advertised as the normal path.
2. Update `.cursor/commands/run-item.md` with the post-prelude internal handoff
   contract and fallback behavior.
3. Update `.cursor/agents/item-orchestrator.md` so it describes an internal
   `/run-item` handoff role and legacy compatibility rather than a normal direct
   command.
4. Review and minimally update mirrored run-item surfaces:
   `.claude/commands/run-item.md`, `.claude/agents/item-orchestrator.md`,
   `.agents/skills/run-item/SKILL.md`, and
   `.codex/skills/workflow-item-orchestrator/SKILL.md`.
5. Review deprecated alias surfaces `.cursor/commands/run-item-work.md` and
   `.claude/commands/run-item-work.md`; update only if they imply direct
   `item-orchestrator` usage.
6. Update Protocol 90 and `agent-model-config.md` where needed to distinguish
   internal dispatch from user-facing invocation and to capture model-routing
   intent.
7. Add the smoke test runbook for #1190.
8. Add the `[Unreleased]` CHANGELOG entry using the literal from the Changelog
   section above.
9. Run:
   `rg -n "Invoke them directly|/item-orchestrator|Cursor.*item-orchestrator|item-orchestrator.*Cursor" AGENTS.md .cursor .claude .agents .codex docs/workflow/development-workflow docs/testing/workflow`
   and confirm each remaining hit is internal, compatibility, or historical
   smoke-test context.
10. Run markdown lint on all changed markdown files.
11. Commit with a Conventional Commit message and open the implementation PR.
